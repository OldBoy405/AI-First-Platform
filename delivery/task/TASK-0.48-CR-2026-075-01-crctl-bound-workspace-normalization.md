---
spec-id: ai-first-platform
version: "0.48"
id: CR-2026-075-TASK-01
type: TASK
cr-ref: CR-2026-075
plan-ref: "change-requests/CR-2026-075/plan.md"
sdd-ref: "change-requests/CR-2026-075/sdd.md"
target-version: 0.48
title: crctl 绑定归一与失败关闭
slug: crctl-bound-workspace-normalization
status: pending
estimate: 8h
depends-on: []
created: 2026-10-03T00:15:00+08:00
---

## 任务描述

在 `crctl.mjs` 实现绑定归一与失败关闭（FR-03、FR-04；SDD §2.1/§3.2/§4.2）。目标：task 子进程携带完整可信绑定三元组时，非 help 子命令在真遗漏 `--workspace` 的情况下首次即使用 `CRCTL_OPERATIONAL_WORKSPACE` 的真实路径，不再报 `WORKSPACE_REQUIRED`；显式异根、绑定不完整或互相冲突先于 `detectWorkspace` 拒绝；无绑定声明的显式 CLI 模式行为逐字不变。输入是 `process.env` 的三个绑定值与既有 CLI `flags.workspace`，输出是归一后的 `flags.workspace` 或硬失败。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs` — 新增私有 `bindTaskWorkspace(cmd, flags, env)` 并在 `main()` 内接线；不改任何命令处理器、失败面与 `HELP` 文本。
- `skills/shared/crctl/scripts/test/crctl.test.mjs` — A 段 CLI 向量（A1/A2/A5/A6/A8；B1/B3 的 CLI 可观测边界）。

本 TASK 不修改提示词、Pipeline 模板或部署副本（FR-14 收敛见 TASK-08），不修改 `lib/durable-tx.mjs`（TASK-03）。

## 实现要点

- 判据逐字落 SDD §2.1/§4.2（`bindTaskWorkspace` 唯一实现）：
  - `declared(op) = 'CRCTL_OPERATIONAL_WORKSPACE' in env`（含空串/空白），`declared(audit)` 同理；`!declared(op) && !declared(audit)` → 直接返回，不改 `flags`（显式 CLI 模式；`help`、`kb init`、注册 bootstrap、独立 CLI/CI 不受影响）。
  - 任一声明存在即进入绑定声明分支：`taskId`/`op`/`audit` 去空白后全非空、两路径 `realpath` 存在且为目录、`deriveInstallRoot(realpath(op)) === deriveInstallRoot(realpath(audit))`；任一不满足 → `WORKSPACE_CONTEXT_MISMATCH`（非零、零业务写入、先于任何 CR 数据读写）。
  - `flags.workspace === undefined` → `flags.workspace = realpath(op)`（只有真遗漏才归一）。
  - `typeof flags.workspace !== 'string' || flags.workspace.trim() === ''` → 直接返回（不改写），由既有 `requireExplicitWorkspace` 原样报 `WORKSPACE_REQUIRED`；空串/裸旗标不在本地纠正集合。
  - `!sameRealPath(realpathOrSelf(flags.workspace), realpath(op))` → `WORKSPACE_CONTEXT_MISMATCH`（绑定不可被显式异根覆盖）；同一真实目录或合法别名（junction、Windows 大小写、`\\?\` 前缀、尾部分隔符）接受。
- 调用位置 DEC-1：`main()` 内 `parseArgs(rest)` 之后、`requireExplicitWorkspace(cmd, flags)` 之前（`crctl.mjs:3786-3788`）；归一集中一处，不塞进各命令处理器、不新增公开旗标、不在 `detectWorkspace` 内回退 env（CR-2026-072 已删除的行为不得重开）。
- FR-04 边界：本函数不做业务纠正、不自动重试、不切 CLI 版本。允许的一次纠正只有「旧显式入口缺根」与「额外 `validate prd.md`」两类，由调用方 Skill 在节点日志可证明「预检零业务写入」时执行一次；第二次失败或权限/绑定/写入不明走既有停止或事务恢复路径；`BAD_ARGS` 不在纠正集合内。
- AC-A8：Windows 动态路径用例传入 argv 原样，不重拼 shell 字符串；用例必须在 Windows 真机执行（`cmd-01` 在本机 Windows 运行）。
- 工程纪律 #1：新增用例读入文件后先做 `\r\n → \n` 规范化，跨行匹配失败硬失败。

## 验收条件

1. 在 tools CR worktree 根执行证据命令 `cmd-01`（plan §6.2 原样：repo=tools、cwd=`.`、executable=`node`、args=`["--test","skills/shared/crctl/scripts/test/crctl.test.mjs"]`、timeout=900）：全绿。真实运行范围 = 单文件 `crctl.test.mjs`（本轮基线 237 用例 / 172s，同目录、`node --test`）；不声称覆盖 crctl 全部子命令行为。新增/调整用例必须覆盖：
   - AC-A5：同真实目录与合法别名接受；异根 `WORKSPACE_CONTEXT_MISMATCH` 且绑定不被覆盖。
   - AC-A6：无绑定声明时缺根 `WORKSPACE_REQUIRED`；仅 task ID 不误绑定；旧 `CRCTL_WORKSPACE` 不作 fallback；`help` 可用。
   - AC-A8：Windows 空格/中文路径的 argv 完整性。
   - AC-B1：**M2 面**——有效绑定下显式传入不可用 `--workspace`（空串/纯空白/裸旗标）时 `bindTaskWorkspace` **不归一**、`requireExplicitWorkspace` 返回 `WORKSPACE_REQUIRED`；补已确认显式根（与 `CRCTL_OPERATIONAL_WORKSPACE` 同一真实目录或合法别名）后同调用成功（**仅 CLI 侧边界单测**，构成本 TASK 提供给 TASK-08 实际调用方节点回放的输入）。FR-04 的取证面按 plan §4 末「0.12 前提更正与 FR-04 批准验收恢复记录」三段口径：段① `cmd-01`（CLI 机器语义，**有效绑定**场景）/ 段② `cmd-05`（调用方静态合同）/ 段③ 实际受控调用方节点的节点日志/回放（`test-evidence/caller-replay/`），三段载体互不冒充、任一段缺失即 FR-04 不通过。**本 TASK 已 `done`**，其 `cmd-01` 落地用例（`crctl.test.mjs:628-648` 的 `runCrctl(argv)` 无绑定场景；`fixed` 分支只断言错误码不等于 `WORKSPACE_REQUIRED`、无 `status===0`；空串/纯空白/裸旗标三例未传 `bind3`）未含 M2 有效绑定与补已确认同根成功断言，**该补验的唯一 owner 是 CR-2026-075-TASK-08**（plan §4 末第四条第 1 项）；段③的生产与归档 owner 同为 CR-2026-075-TASK-08，本 TASK 不产出回放记录、不另立第二套回放。有效绑定首次归一 A1（M1 真缺参直接归一、全程不出现错误码）的证据为 `cmd-01` 与 `cmd-07`；M3/S2 字面来源向量由本卡 AC-A6 承担。见 plan §5 证据范围、§6.1 FR-04 观测面说明与 SDD §2.1 四模式判定表/§4.2.1。
   - AC-B3：第二次失败不自动重试；`BAD_ARGS`、空串、裸旗标不在本地纠正集合。**调用方侧**的同 run 调用计数与失败路由所属的段③节点日志/回放面（含 B 变体固定取 SDD §2.1 **M4 面**的原始记录断言）由 plan §4 末第三、四条归 CR-2026-075-TASK-08 生产并归档、CR-2026-075-TASK-10 复跑汇总；本 TASK 已 `done` 且不承担段③。AC-B3 的其余子面（第二次仍非零、`BAD_ARGS`、权限或路径拒绝、其它上下文冲突、写入或提交结果不明）按 SDD §5.2 由本卡的 `cmd-01` 入口向量覆盖（段①），其在有效绑定场景的补验 owner 同为 CR-2026-075-TASK-08；本 TASK 只保证 CLI 边界行为。
2. 失败关闭顺序：绑定冲突/不完整/异根向量断言「非零 + 零业务写入」（调用前后 CR 数据文件与 HEAD 逐字相同），并以「不存在的 workspace + 缺 `change-requests/` 的 fixture」组合证明失败先于 `detectWorkspace`/`loadGates`。
3. 文件集检查经受控入口（本运行时禁止原生 Git；argv 固定于本卡）。cwd 与验收条件 1 同为 tools CR worktree 根；占位绑定：`<tools-worktree>` 取 Pipeline `resources[]` 中 repo=`tools` 的 `worktreePath` 原样值，`<operational-workspace>` 取 `crctl workspace inspect CR-2026-075` 的 `operationalWorkspace` 原样值，不拼接、不回退主工作区：

   `node skills/shared/crctl/scripts/crctl.mjs git status --porcelain --cwd <tools-worktree> --workspace <operational-workspace>`

   断言输出仅含本 TASK 声明的两个文件（`skills/shared/crctl/scripts/crctl.mjs`、`skills/shared/crctl/scripts/test/crctl.test.mjs`）。status 仅证明文件集，内容正确性由验收条件 1/2 证明。

## 完成标志

- `cmd-01` 全绿，且 AC-A5/A6/A8、AC-B1/B3 的 CLI 侧断言在用例中逐条可见；本 TASK 为 TASK-08 的实际调用方节点回放提供 CLI 侧固定边界（M2 面：显式不可用 `--workspace` → `WORKSPACE_REQUIRED`，与补已确认显式根后成功），回放记录与调用方断言不在本 TASK 内重复（CLI fixture 仅边界单测）。
- `bindTaskWorkspace` 为 crctl.mjs 私有函数，无新增导出、无新增模块；除 `main()` 调用点与新增测试外与其他命令处理器 diff 为零。
- `WORKSPACE_CONTEXT_MISMATCH` 只在 SDD §4.2 的两处判定点触发；`WORKSPACE_REQUIRED`/`BAD_ARGS` 语义与优先级逐字不变。
- 产物已落盘并提交，commit 自含其新增测试；不夹带 TASK-03/04/06 对同一文件的改动（R9 顺序编辑），不改任何提示/模板文本（FR-14 门槛见 TASK-08）。

## 接口契约

**消费**（逐字对齐 SDD 与目标仓现状）：

- `parseArgs(argv)`、`main()` 既有装配顺序（`crctl.mjs:3786-3792`）：`cmd === 'git'` 走 `parseGitArgs(rest)`；`help`/`--help`/`-h` 提前返回；`kb` 特判分支在本函数之后不受影响。
- `realpathOrSelf(p)`（`crctl.mjs:558`）、`sameRealPath(a, b)`（`crctl.mjs:563`）：Windows 大小写不敏感的真实路径比较语义，不新增第二套比较实现。
- `deriveInstallRoot(opWs)`（`skills/shared/crctl/scripts/lib/workspace-transactions.mjs:47`，已在 `crctl.mjs:29` 导入）：install root 一致性校验的唯一来源。
- `requireExplicitWorkspace(cmd, flags)`（`crctl.mjs:3292`）：显式模式下的唯一根关卡，文本与语义不改。

**产出**：

```text
bindTaskWorkspace(cmd, flags, env)   // 私有；返回 void；只改 flags.workspace 或 fail() 硬失败
env: {
  MULTICA_TASK_ID?: string,
  CRCTL_OPERATIONAL_WORKSPACE?: string,   // declared = 键存在（含空串）；present = 去空白后非空
  CRCTL_TASK_AUDIT_ROOT?: string
}
```

- 新增失败码 `WORKSPACE_CONTEXT_MISMATCH`（stderr 单一 `{error:{code,message}}`、非零退出、零业务写入）。
- 失败优先级与 SDD §3.2 一致：绑定声明分支内的不完整/冲突/异根 → `WORKSPACE_CONTEXT_MISMATCH`；无绑定声明且缺根 → `WORKSPACE_REQUIRED`。
- 下游引用同一份契约：TASK-02 的发布点写出的三元组即本函数的输入（SDD §2.1 定义），TASK-08 的 FR-14 收敛门槛以本 TASK 的 `cmd-01` 结果为前置；两处都不得改写或缩写本契约。

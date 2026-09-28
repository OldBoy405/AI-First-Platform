---
id: CR-2026-072-TASK-02
type: TASK
cr-ref: CR-2026-072
plan-ref: "change-requests/CR-2026-072/plan.md"
sdd-ref: "change-requests/CR-2026-072/sdd.md"
target-version: 0.45
title: crctl CLI 入口失败关闭：强制显式 --workspace
slug: crctl-workspace-required
status: pending
estimate: 8h
depends-on: ["CR-2026-072-TASK-01"]
created: 2026-09-28T23:52:00+08:00
---

## 1. 任务描述

在 `skills/shared/crctl/scripts/crctl.mjs` 统一 CLI 入口实施失败关闭：非 `help` 且需要 CR 数据访问的子命令必须提供非空、有效的 `--workspace`；缺失/空值返回结构化 `WORKSPACE_REQUIRED`，无效路径返回 `WORKSPACE_NOT_FOUND`（或现有更具体的有效性错误），均发生在读取 CR 状态、执行门禁或写文件之前。删除 `CRCTL_WORKSPACE` 环境变量与 cwd 向上探测对 CR 数据命令的隐式根选择。保留现有状态/事务/深原语实现，不为显式路径再造状态副本。`status` 终态分支同样经入口校验，不依赖 `STATUS_DIVERGED` 兜底纠错。本 TASK 依赖 TASK-01 完成（同批交付门，发布顺序前置）。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`
  - `main()`（:3498）：在 `const ws = detectWorkspace(flags.workspace)` 之前插入前置校验分支；`cmd === 'git'` 时 `parseGitArgs` 后同样按命令分类辨明（git 白名单命令、纯静态 `validate` 等非 CR 数据入口逐项辨明，不粗暴拦截 Git 通道；一旦涉及 CR 事实源/审计同样要求显式合法 root）
  - `detectWorkspace(explicit)`（:142）：删除 `process.env.CRCTL_WORKSPACE` 分支与 cwd 向上查找 `change-requests/_backlog.yml` 回退；显式值仅 `path.resolve` + 存在性校验
  - `authorityWorkspace(ws, _cr, override)`（:528）：写路径对 `CRCTL_OPERATIONAL_WORKSPACE` 与当前任务已确认 operational path 比对，不一致于首次读取 CR 数据/写入前失败关闭，不以环境值覆盖显式旗标
  - `cmdStatus`（:901）终态 `resolveTerminalForQuery` 分支：经入口校验后行为不变
- `skills/shared/crctl/scripts/test/crctl.test.mjs`：新增跨项目隔离与旗标校验用例

## 3. 实现要点

- SDD §4.2：`parseArgs`/`parseGitArgs` 得出 flag 后，非 help 且需 CR 数据的子命令先校验 `typeof workspace === 'string' && flags.workspace.trim() !== ''`，否则 `fail('WORKSPACE_REQUIRED', ...)`；合法值仅从该 flag 进入 `detectWorkspace`。
- 错误 JSON 沿用 `{error:{code,message}}` + 非零退出；`--workspace` 的值只是参数，错误信息不泄露其他项目账本内容。
- 旗标解析拒绝无值、全空白、重复不一致值；`help` 保留无旗标。
- 路径校验含 Windows realpath 大小写规范化（SDD §7），防相对路径/symlink 逃逸。

## 4. 验收条件

1. 新增用例（自建临时 workspace）：A、B 两目录各含同名 `CR-2026-001`（A `archived`、B `developing`）；显式 B 路径时 `status`/`next` 仅返回 B 事实，终态查询不产生 `STATUS_DIVERGED` 纠错路径。
2. 新增用例：cwd=B、`CRCTL_WORKSPACE=A` 时，缺 `--workspace` 与空 `--workspace ""` 的 CR 数据读写命令 stderr 输出 `{"error":{"code":"WORKSPACE_REQUIRED",...}}` 且退出非零，A/B 两目录文件哈希前后不变（零读写副作用）。
3. 新增用例：显式 B 路径 + `CRCTL_WORKSPACE=A` 时 `gate`/`advance` 只采信 B；显式无效路径返回 `WORKSPACE_NOT_FOUND` 且不回退 A 或 cwd；`CRCTL_OPERATIONAL_WORKSPACE` 与显式 operational path 不一致时写命令失败关闭。
4. 既有 `node --test test/crctl.test.mjs` 全量通过：现有合法显式路径的读写、门禁、CAS、事务语义不变。

## 5. 完成标志

crctl.test.mjs（含新增隔离/旗标用例）全绿；`WORKSPACE_REQUIRED`/`WORKSPACE_NOT_FOUND` 在 `loadGates` 与任何 CR 数据读取之前生效；env/cwd 回退代码路径从 `detectWorkspace` 移除；全部改动以 `[cr] ` 前缀 commit 提交。

## 6. 接口契约

- **消费**：TASK-01 迁移完成信号（caller-contract 显式旗标断言全绿）作为本 TASK 合入前置。
- **产出**（供 TASK-05 与下游调用方消费的错误契约）：
  - `WORKSPACE_REQUIRED`：非 help 的 CR 数据命令缺/空 `--workspace`，先于 `loadGates`/状态读取/写文件，输出 `{error:{code:"WORKSPACE_REQUIRED",message}}`，退出非零。
  - `WORKSPACE_NOT_FOUND`：显式路径不存在或缺少 `change-requests/`，输出 `{error:{code:"WORKSPACE_NOT_FOUND",message}}`，退出非零，不回退 env/cwd。
  - `authorityWorkspace(ws, _cr, override)` 语义：`override || CRCTL_OPERATIONAL_WORKSPACE` 与任务确认 operational path realpath 不一致时失败关闭；一致时返回 `path.resolve(configured)`。

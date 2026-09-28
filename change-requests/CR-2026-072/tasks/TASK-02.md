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
  - `authorityWorkspace(ws, _cr, override)`（:528）：删除 `override || CRCTL_OPERATIONAL_WORKSPACE` 短路选一，改为**权威恒为显式确认路径 + env 仅作提示校验**——权威 = 显式 `--operational-workspace`（任务已确认 operational path）存在时取该值，否则取 `ws`（入口校验后的显式 `--workspace`）；env `CRCTL_OPERATIONAL_WORKSPACE` 永不作为权威、永不覆盖旗标，存在时（无论旗标是否同时存在）须各自 realpath 规范化后与权威比对，不一致（含两值同时存在冲突、**仅 env 存在且与 `ws` 冲突**）于首次读取 CR 数据/写入前失败关闭（`OPERATIONAL_WORKSPACE_MISMATCH`，非零退出）；一致或仅旗标存在（env 缺失）返回权威；两者皆缺失返回 `ws` 维持现状（SDD §2/§4.4）
  - `cmdStatus`（:901）终态 `resolveTerminalForQuery` 分支：经入口校验后行为不变
- `skills/shared/crctl/scripts/test/crctl.test.mjs`：新增跨项目隔离与旗标校验用例

## 3. 实现要点

- SDD §4.2：`parseArgs`/`parseGitArgs` 得出 flag 后，非 help 且需 CR 数据的子命令先校验 `typeof workspace === 'string' && flags.workspace.trim() !== ''`，否则 `fail('WORKSPACE_REQUIRED', ...)`；合法值仅从该 flag 进入 `detectWorkspace`。
- SDD §4.4/数据模型行：**可信 operational path 唯一来源** = 调用方经 `--operational-workspace` 显式传入的任务已确认路径（Pipeline 预检 / `crctl workspace inspect` 返回的 `operationalWorkspace`，随任务上下文传递）；env `CRCTL_OPERATIONAL_WORKSPACE` 仅是 daemon 注入的预检绑定提示，不是确认源、不得覆盖旗标、**不得单独作权威**。**缺失时行为**：env 缺失非错误（非 Pipeline/无注入场景常态），仅旗标存在直接采信 override；**仅 env 存在（旗标缺失）失败关闭**——权威仍为 `ws`（入口校验后的显式 `--workspace`，即当前任务已确认 B authority），realpath(env) 与 realpath(ws) 不一致时于首次读取 CR 数据/写入前 `OPERATIONAL_WORKSPACE_MISMATCH` 非零退出，env 不得把 `resolveCrState`/`updateCrMdStatus`/事务写入重定向到 A，一致时返回 `ws`；两者皆缺失返回 `ws`，无 operational 比对面。校验落在 `authorityWorkspace` 解析内：`preflightAdvance`/`performAdvance`/`cmdTest` 取得返回值早于任何 CR 数据读取或写入，失败即不产生 A/B 任何副作用。
- 错误 JSON 沿用 `{error:{code,message}}` + 非零退出；`--workspace` 的值只是参数，错误信息不泄露其他项目账本内容。
- 旗标解析拒绝无值、全空白、重复不一致值；`help` 保留无旗标。
- 路径校验含 Windows realpath 大小写规范化（SDD §7），防相对路径/symlink 逃逸。

## 4. 验收条件

1. 新增用例（自建临时 workspace）：A、B 两目录各含同名 `CR-2026-001`（A `archived`、B `developing`）；显式 B 路径时 `status`/`next` 仅返回 B 事实，终态查询不产生 `STATUS_DIVERGED` 纠错路径。
2. 新增用例：cwd=B、`CRCTL_WORKSPACE=A` 时，缺 `--workspace` 与空 `--workspace ""` 的 CR 数据读写命令 stderr 输出 `{"error":{"code":"WORKSPACE_REQUIRED",...}}` 且退出非零，A/B 两目录文件哈希前后不变（零读写副作用）。
3. 新增用例：显式 B 路径 + `CRCTL_WORKSPACE=A` 时 `gate`/`advance` 只采信 B；显式无效路径返回 `WORKSPACE_NOT_FOUND` 且不回退 A 或 cwd；`--operational-workspace` 指向 B 而 `CRCTL_OPERATIONAL_WORKSPACE` 指向 A（**两值同时存在且冲突**）时，写命令在首次 CR 数据读取/写入前返回 `{"error":{"code":"OPERATIONAL_WORKSPACE_MISMATCH",...}}` 非零退出且 A/B 两目录文件哈希前后不变（零副作用）；**仅 env 冲突**：无 `--operational-workspace`、显式 `--workspace=B`、`CRCTL_OPERATIONAL_WORKSPACE=A` 时，`advance` 等写命令同样在首次 CR 数据读取/写入前返回 `OPERATIONAL_WORKSPACE_MISMATCH` 非零退出（env 不得作唯一权威重定向读写），A/B 两目录文件哈希前后不变（零副作用）；两值一致、仅 env 且与 `--workspace` 一致（env=B）、或仅旗标存在（env 缺失）时正常执行。
4. 既有 `node --test test/crctl.test.mjs` 全量通过：现有合法显式路径的读写、门禁、CAS、事务语义不变。

## 5. 完成标志

crctl.test.mjs（含新增隔离/旗标用例）全绿；`WORKSPACE_REQUIRED`/`WORKSPACE_NOT_FOUND` 在 `loadGates` 与任何 CR 数据读取之前生效；env/cwd 回退代码路径从 `detectWorkspace` 移除；全部改动以 `[cr] ` 前缀 commit 提交。

## 6. 接口契约

- **消费**：TASK-01 迁移完成信号（caller-contract 显式旗标断言全绿）作为本 TASK 合入前置。
- **产出**（供 TASK-05 与下游调用方消费的错误契约）：
  - `WORKSPACE_REQUIRED`：非 help 的 CR 数据命令缺/空 `--workspace`，先于 `loadGates`/状态读取/写文件，输出 `{error:{code:"WORKSPACE_REQUIRED",message}}`，退出非零。
  - `WORKSPACE_NOT_FOUND`：显式路径不存在或缺少 `change-requests/`，输出 `{error:{code:"WORKSPACE_NOT_FOUND",message}}`，退出非零，不回退 env/cwd。
  - `authorityWorkspace(ws, _cr, override)` 语义（修订）：删除 `override || env` 短路；**权威恒为显式确认路径**——旗标 `override`（调用方传入的任务已确认 operational path，来源 = Pipeline 预检 / `workspace inspect` 的 `operationalWorkspace`）存在 → 返回 `path.resolve(override)`，否则 → 返回 `ws`（入口校验后的显式 `--workspace`）；env `CRCTL_OPERATIONAL_WORKSPACE` 永不作为权威、永不覆盖旗标，存在时各自 realpath 规范化后与权威比对——不一致（两值同时存在冲突，或**仅 env 存在且与 `ws` 不一致**）→ 首次 CR 数据读取/写入前 `OPERATIONAL_WORKSPACE_MISMATCH` 非零退出；一致或仅旗标存在（env 缺失）→ 返回权威；皆缺失 → 返回 `ws`。

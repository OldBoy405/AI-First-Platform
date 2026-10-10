---
id: CR-2026-076-TASK-03
type: TASK
cr-ref: CR-2026-076
plan-ref: "change-requests/CR-2026-076/plan.md"
sdd-ref: "change-requests/CR-2026-076/sdd.md"
target-version: 0.49
title: "crctl 绑定归一只读诊断与失败关闭口径 + 合同文本同步"
slug: crctl-binding-diagnostics-contract
status: pending
estimate: 12h
depends-on: [CR-2026-076-TASK-01]
created: 2026-10-10T16:30:15+08:00
---

## 任务描述

目标（FR-SUP-07 的诊断口径与写入边界安全校验部分；AC-03 的 crctl 侧出口）：按 SDD §4.1 步骤 4 与 §3.1，把 crctl 侧的绑定归一与「开工检查」固化为可验证的只读诊断面 + 失败关闭，使作者／评审者在业务写入前能区分「绑定正确」与「命令恰好成功」。

背景与输入条件：`dep-1` 结论原文——绑定三元组缺失或不完整、两路径非目录或异安装根、显式 `--workspace` 与绑定异根，均以 `WORKSPACE_CONTEXT_MISMATCH` 失败关闭且零业务写入；`\?\` 命名前缀与尾分隔符按同一真实目录的合法别名处理。`dep-2` 为第二道门：非 help 子命令在无绑定且无显式 `--workspace` 时以 `WORKSPACE_REQUIRED` 失败关闭。`dep-3` 提供 `workspace inspect` 的只读输出面。

依赖性质说明：对 TASK-01 是**语义**依赖（诊断口径以已发布的绑定三元组语义为准），不是文件依赖（plan §2 依赖说明）。

明确不做：不新增／不改名 crctl 子命令（`dep-2`，`case '<cmd>'` 集合不变）；不新增同义错误码（`dep-28` 单出口 `ok()`／`fail()`）；不改 `rules.json` 白名单与 deny 面；`workspace inspect` 的 `freshness` 块属 TASK-10，本 TASK 不实现。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`：`bindTaskWorkspace`（`dep-1`）、`requireExplicitWorkspace`（`dep-2`）、`cmdWorkspace`（`dep-3`，:3731）、`cmdStatus`
- `skills/shared/crctl/scripts/test/crctl.test.mjs`：新增定向用例（当前登记 237 顶层用例，本 TASK 追加后按 cmd-11 登记面据实更新）
- `skills/shared/crctl/SKILL.md`：合同文本同步（声明无新增子命令、绑定归一与失败关闭诊断口径、`warnings[]` 语义引用 TASK-06）

## 实现要点

1. 只读诊断口径（供作者／评审者开工检查）：`workspace inspect`／`status`／`next` 三个入口在业务写入前被消费——不得以「命令成功」或「next 能看到 PRD」单独证明绑定正确；诊断输出的 `operationalWorkspace`／`operationalWorkspaceError`／`resources[].{repo,branch,worktreePath,classification,dirty}` 保持既有字段类型（`dep-3`）。
2. 失败关闭面（断言全部保留，不降级为 warning）：三元组不完整／两路径非目录／异安装根／显式 `--workspace` 与绑定异根 → `WORKSPACE_CONTEXT_MISMATCH`，零业务写入；无绑定且无显式根 → `WORKSPACE_REQUIRED`。绑定不可被显式 `--workspace` 覆盖。
3. 目录别名归一：`\\?\` 前缀与尾分隔符各剥一层后按同一真实目录处理（`realpath` 后仍为目录才通过）。
4. 绑定来源诊断标签（E5）只作只读输出（含 TASK-01 产出的 `BINDING_INHERITED_WARN` 透传），不进入任何账本、不新增字段类型。
5. 合同文本同步：`skills/shared/crctl/SKILL.md` 增补绑定归一与失败关闭说明、`review-loop reset --continue-reason`（TASK-08 实现）、`validate` 只读维度 `owner-source-anomalies`（TASK-15 实现）、`warnings[]` 语义（TASK-06 实现）的引用口径；**只写合同引用，不越权实现他人 TASK 的行为**。
6. 仓库不变量：`crctl.test.mjs` 中「推导 ≡ 登记」断言（状态机 transitions 声明数与 `gate-registry.json#stateMachine` 一致）必须随 TASK-07 的 +1 声明同步为 32 条声明（TASK-07 负责改常量；本 TASK 只保证该断言文件存在且当前通过）。

## 验收条件

1. **cmd-04（绑定归一只读诊断与失败关闭）**：单文件 `skills/shared/crctl/scripts/test/crctl.test.mjs` 定向用例断言 `WORKSPACE_CONTEXT_MISMATCH` 与 `WORKSPACE_REQUIRED` 的全部触发面与零业务写入；覆盖 `\\?\` 前缀／尾分隔符别名归一。运行范围＝该单文件，**不声称**覆盖 crctl 全部子命令行为，也不声称覆盖 `lib/` 模块内部语义。
2. **cmd-09（合同文本一致性）**：tools 仓六文件（`pipeline-structure.test.mjs`、`contract-scan.test.mjs`、`check-skill-matrix.test.mjs`、`check-agents-contract.test.mjs`、`lint-prompts.test.mjs`、`skill-scope.test.mjs`）通过——用于 `skills/shared/crctl/SKILL.md` 合同文本改动后的一致性核对；不声称覆盖业务逻辑行为。
3. **零改动面**：`crctl --help` 的子命令集合与改动前逐字一致（无新增／改名／删除），`rules.json` `git` 白名单与 `protectedPaths` 未改动。
4. 真实执行退出码与输出原样落 `test-evidence/cmd-04.log`、`test-evidence/cmd-09.log`；不得新增 plan 未列命令。

## 完成标志

- 绑定归一只读诊断与两个失败关闭出口有定向用例覆盖，`cmd-04`、`cmd-09` 真实执行退出码 0 并留证；
- `skills/shared/crctl/SKILL.md` 合同文本同步落盘（含「无新增子命令」的显式声明与诊断口径）；
- 本 TASK 在 `tasks/_index.yml` 即时标记 `done`。

## 接口契约

消费（TASK-01 产出的语义，不得缩写）：
- `func (d *Daemon) resolveTaskWorkspaceBinding(ctx context.Context, task *Task, localAssignment *localDirectoryAssignment) (taskWorkspaceBinding, error)`（multica `server/internal/daemon/pipeline_task.go:202`）产出的绑定三元组语义：`CRCTL_OPERATIONAL_WORKSPACE`（操作根 realpath）、`CRCTL_TASK_AUDIT_ROOT`（审计根）、`MULTICA_TASK_ID`；
- `BINDING_INHERITED_WARN`（TASK-01 产出的绑定来源诊断 code，只读透传）。

产出（供 TASK-04／TASK-05／TASK-06／TASK-08／TASK-11／TASK-13／TASK-14／TASK-15 消费同一份口径）：
- `bindTaskWorkspace`：入参为进程环境三元组与显式 `--workspace`，出参为归一后的操作根（realpath）；失败时经 `fail()` 返回 `WORKSPACE_CONTEXT_MISMATCH`（三元组不完整／非目录／异安装根／显式根异根）或 `WORKSPACE_REQUIRED`（无绑定且无显式根），**零业务写入**；
- `cmdWorkspace(ws, positional, flags)`（`crctl.mjs:3731`）：`workspace inspect` 只读输出 `operationalWorkspace`、`operationalWorkspaceError`、`resources[].{repo,branch,worktreePath,classification,dirty,localBranch,remoteBranch}`、`changed`；字段类型与既有实现逐字一致（新增 `freshness` 块由 TASK-10 追加）；
- 合同文本：`skills/shared/crctl/SKILL.md` 的「无新增子命令」声明是 TASK-07／TASK-08／TASK-15 的行为边界依据。

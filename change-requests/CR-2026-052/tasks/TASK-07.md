---
id: CR-2026-052-TASK-07
type: TASK
cr-ref: CR-2026-052
plan-ref: "change-requests/CR-2026-052/plan.md"
sdd-ref: "change-requests/CR-2026-052/sdd.md"
title: "multica CUSTOM.md 台账登记（CR-2026-052 里程碑）"
slug: multica-custom-ledger-register
status: pending
estimate: 2h
depends-on: ["CR-2026-052-TASK-06"]
created: 2026-08-27T10:44:32+08:00
---

# TASK-07：CUSTOM.md 台账登记

## 1. 任务描述

按 multica 仓 `CUSTOM.md` 现状结构登记 CR-2026-052 全部定制（迁移、governance 自研包、router 接线、runner 适配），编号顺延，原因追溯含 CR 编号。对应 AGENTS.md 纪律 10、NFR-7。

## 2. 涉及文件 / 模块

- 修改 `multica/CUSTOM.md`（CR 里程碑总览新增 CR-2026-052 行；代码改动明细追加条目，编号顺延；具体表格划分以登记时 CUSTOM.md 现状为唯一事实源）

## 3. 实现要点（AGENTS.md 纪律 10 / NFR-7）

登记范围（对照 TASK-01~06 实际落代码，以彼时 multica 仓实际结构为准）：
1. **迁移**：469/470/471（server/migrations/，up/down 各一，CONCURRENTLY + 单语句惯例）。
2. **governance 自研包**：
   - `server/pkg/db/queries/approval.sql`（新文件，6 条查询）
   - `server/pkg/db/queries/issue.sql` 追加 `LockIssueInWorkspaceForShare`（FOR SHARE）
   - `server/pkg/db/generated/*.go`（`make sqlc` 生成，注明"生成产物，真源在 .sql"，不单列行号）
   - `server/internal/governance/approval.go`：`GrantAckEvent`/`SetGrantAckHandler` 扩展签名/`SetGrantAckCommittedHandler`/`HandleGrantsAck` 重写/`resolveContinuationTarget`
   - `server/internal/service/task.go`：`EnqueueApprovalContinuation`/`NotifyContinuationTaskEnqueued`/`ApprovalContinuationSpec`/`EnqueueOutcome`
   - `server/internal/governance/runner.go`：`WakeGrant` 签名扩展、`ValidateGrantAck`
   - `server/cmd/server/router.go`：双钩接线点替换
3. **`// AIFIRST:` / `-- AIFIRST:` 挂钩点**：在新增 sql/Go 代码处标注 `-- AIFIRST: CR-2026-052 …` / `// AIFIRST: CR-2026-052 …`（合并后 grep 口径 `303/1070` 基线只升不降）。

字段（编号顺延；以 CUSTOM.md 现状字段为准，本 TASK 不复刻格式）：关联 CR=CR-2026-052、阶段/版本、完成状态、完成日期、涉及行号、延后项（无）、合并注意（含 `make sqlc` 重生成验证）。

## 4. 验收条件

1. `CUSTOM.md` CR 里程碑总览含 CR-2026-052 行；代码改动明细逐条登记，编号连续无跳号。
2. `grep -rnE "AIFIRST|CR-2026-052" server/ --include=*.go --include=*.sql` 命中数较基线（303 文件/1070 处）只升不降。
3. 登记的文件清单与实际落代码（TASK-01~06 git diff）逐条核对无遗漏。

## 5. 完成标志

CUSTOM.md 登记完成 + grep 口径核对通过 + 与实际改动逐条对账无遗漏。

## 6. 接口契约

- **消费**：TASK-01~06 已落地的 multica 代码与迁移（git diff 为对账源）。
- **产出**：无生产接口；台账条目供双周 rebase 前核对（CUSTOM.md 文件头明示用途）。

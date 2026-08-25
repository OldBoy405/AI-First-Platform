---
id: CR-2026-051-TASK-03
type: TASK
cr-ref: CR-2026-051
plan-ref: "change-requests/CR-2026-051/plan.md"
sdd-ref: "change-requests/CR-2026-051/sdd.md"
title: governance 触发条件与误触发隔离真库测试（AC-1 / AC-2）
slug: governance-gate-trigger-isolation-tests
status: pending
estimate: 8h
depends-on: [CR-2026-051-TASK-02]
created: 2026-08-25T23:20:00+08:00
---

## 任务描述

用真库集成测试把发布点的触发面钉死：四个人工审批门禁 × 合法转换各发布**恰好一次**（AC-1），且通用 `cr:updated`、首见分支、乱序/非法（`needs_reconcile`）、自环、checkpoint/review/trace 分支、reconcile/gate_projection 全部**零发布**（AC-2）。同时断言载荷字段与 `event_id` 形状、`shell_issue_id` 的两种取值（有值 / NULL），这是 BL-3「载荷携带但不作查询输入」的生产侧一半（消费侧一半在 TASK-06）。

## 涉及文件 / 模块

仓根取 `execution_context.resources[]` 中 `repo=multica` 的 `worktreePath`；以下为该仓根相对路径：

- `server/internal/governance/crsync_approval_gate_test.go`（新：`package governance`，复用同包既有 `TestMain`/`testPool`/`testWorkspaceID`/`resetCR`/`postEvents`/`ev`/`crRow`）

零改动：`crsync_test.go` 及其 `TestMain`（CUSTOM.md C6 明示不得为跑通而改 skip 逻辑）、其余既有测试文件。

## 实现要点

1. **测试数据约定**：CR-ID 用 `CR-9051-0NN` 形态（同包 `cleanup` 按 `CR-9%` 清理，且满足 `crIDRe` 的 `^CR-\d{4}-\d{3}$`）；每个用例首行 `resetCR(t, crID)`；事件通过 `postEvents(t, svc, testWorkspaceID, []OutboxEvent{ev(...)})` 走完整 `HandleCREvents` 链路（不直接调私有 `applyStatus`），保证测的是真实入口。
2. **收集器**：`bus := events.New()`；`bus.Subscribe(EventCRApprovalGateEntered, handler)` 与 `bus.Subscribe(EventCRUpdated, handler)` 各挂一个带 `sync.Mutex` 的切片收集器（`Publish` 是同步调用，`postEvents` 返回后即可断言，无需 sleep）。
3. **AC-1 四门禁**（每条独立 CR，前置状态用合法链路铺到位后再触发目标转换，断言目标事件恰 1 条）：
   - `drafting → requirement-reviewing`（trigger `review-requirement`）
   - `tech-designing → tech-design-review-pending`（trigger `write-tech-design-complete`）
   - `tech-design-reviewed → task-breakdown`（trigger `write-dev-tasks`）
   - `developing → code-reviewing`（trigger `review-code`）
   - 追加一条**门禁重入**：`task-breakdown → tech-design-review-pending`（trigger `review-dev-plan:upstream-design-blocker`）同样发布 1 条（该转换在 `transitions_gen.go:33` 有声明，属回退到架构审批门禁）。
   - 每条断言：`e.Type == EventCRApprovalGateEntered`、`e.WorkspaceID == testWorkspaceID`、`e.ActorType == "system"`，`e.Payload.(protocol.ApprovalGateEnteredPayload)` **真类型断言成功**（不走 map），且 `CRID`/`Status` 与事件一致、`EventID == crID + ":" + kind + ":" + sha`。
4. **AC-2 零发布矩阵**（每条断言 approval-gate 收集器长度为 0，同时 `cr:updated` 收集器 > 0 以证明链路确实跑了）：
   - 通用状态更新到非门禁状态（如 `requirement-reviewing → requirement-approved`，trigger `approve-requirement`）；
   - **自环**：`task-breakdown → task-breakdown`（trigger `write-dev-tasks`，`transitions_gen.go:30` 合法）与 `requirement-reviewing → requirement-reviewing`（trigger `review-requirement`）；
   - **首见分支**：对全新 CR 直接投 `from=""`→`drafting`（`legalFresh`）以及 `from="tech-designing"`→`tech-design-review-pending`（首见但中途，走 best-effort + `needs_reconcile`）——后者是最容易漏的一条：**目标是门禁状态但仍必须零发布**；
   - **乱序/非法**：`curStatus` 与 `FromStatus` 不匹配时投一条指向门禁的事件（断言 `needs_reconcile = true` 且零发布）；
   - **非 status 事件**：`event_kind` 为 `checkpoint` / `review` / `trace` 的事件零发布（trace 事件按既有 `trace_ingest_test.go` 的最小合法 payload 构造）；
   - **reconcile / gate_projection**：调用既有 reconcile 入口（参照 `reconcile_test.go` 的调用形态）与 `projectGateTransition` 路径后零发布；
   - **订阅面**：断言 `EventCRApprovalGateEntered != EventCRUpdated`，且四门禁转换在 `cr:updated` 收集器里也照常有事件（证明本 CR 没有改既有广播面）。
5. **`shell_issue_id` 两态**（BL-3 生产侧）：一条 CR 先 `UPDATE cr SET shell_issue_id = <本 workspace 内新建 issue 的 id>`，再触发门禁转换，断言 `Payload.ShellIssueID != nil` 且等于该 issue id 字符串；另一条 CR 保持 `shell_issue_id IS NULL`，断言 `Payload.ShellIssueID == nil`（不是空字符串）。issue/project 造数参照 `project_gates_test.go:49-51` 的既有 INSERT 形态。
6. **golden JSON 同源**：对第 5 条的两条载荷各做一次 `json.Marshal`，断言与 TASK-01 定义的 canonical 形状一致（`shell_issue_id` 键恒在、无值为 `null`）——防止生产侧被换成 map 或加了 `omitempty` 而 TASK-01 的单测发现不了。
7. 测试注释英文；不引入 sleep/轮询（`Publish` 同步）；不修改既有断言。

## 验收条件

1. `cd server && go test ./internal/governance/ -run ApprovalGate -v -count=1` 全部 `--- PASS`（真库；出现 `--- SKIP` 视为未测，按 CUSTOM.md C6 修 `DATABASE_URL` 后重跑）。
2. AC-1 五条（四门禁 + 门禁重入）各断言"恰好 1 条"事件，且载荷四字段与 `event_id` 三段形状全部相符。
3. AC-2 矩阵至少覆盖 8 种零发布情形（非门禁目标、两种自环、两种首见分支、乱序/非法、三类非 status 事件、reconcile/gate_projection），每条同时证明 `cr:updated` 链路仍工作。
4. `shell_issue_id` 有值 / NULL 两态断言通过，且 golden JSON 与 TASK-01 一致。
5. `go test ./internal/governance/ -count=1` 整包通过（对照 CUSTOM.md「已知测试失败基线」排除既有失败）；`git diff --name-only` 在本 TASK 范围内只有新增的 `crsync_approval_gate_test.go`。

## 完成标志

上述 5 条全通过并留下 `-v` 的 `--- PASS` 输出（write-test-report 阶段直接引用该证据）；`crctl task done CR-2026-051 --task CR-2026-051-TASK-03 --workspace <kb worktree>` 已登记。M1 里程碑到此闭合：发布侧的触发与隔离已可证。

## 接口契约

- **消费**：TASK-01 的 `protocol.ApprovalGateEnteredPayload{CRID, Status, EventID, ShellIssueID *string}`；TASK-02 的 `governance.EventCRApprovalGateEntered`（导出常量）与包内 `approvalGateStatuses`。既有测试设施（同包，签名原样）：`testPool *pgxpool.Pool`、`testWorkspaceID string`、`resetCR(t *testing.T, crID string)`、`postEvents(t *testing.T, svc *SyncService, workspaceID string, evs []OutboxEvent) crEventsResponse`、`ev(crID, kind, from, to, trigger, sha, file string) OutboxEvent`、`crRow(t *testing.T, crID string) (string, bool, string)`、`NewSyncService(pool *pgxpool.Pool, bus *events.Bus) *SyncService`、`events.New()`、`(*events.Bus).Subscribe(string, func(events.Event))`。
- **产出**：仅测试，不导出任何新符号。下游 TASK-08 汇总时引用本 TASK 的测试名前缀 `ApprovalGate`（`-run ApprovalGate` 必须能选中本 TASK 全部用例）。

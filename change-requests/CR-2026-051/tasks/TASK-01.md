---
id: CR-2026-051-TASK-01
type: TASK
cr-ref: CR-2026-051
plan-ref: "change-requests/CR-2026-051/plan.md"
sdd-ref: "change-requests/CR-2026-051/sdd.md"
title: 共享事件契约与 canonical JSON 形状（pkg/protocol）
slug: shared-approval-gate-event-contract
status: pending
estimate: 3h
depends-on: []
created: 2026-08-25T23:20:00+08:00
---

## 任务描述

在 `pkg/protocol` 声明本 CR 唯一的事件名常量与载荷类型，使生产侧（`internal/governance`）与消费侧（`internal/integrations/lark`）共享一份**编译期**契约，且不互相 import（SDD §3.2.1 / §5 DD-4，BL-4 的合规落点）。该载荷同时是 WS 广播帧的 payload（`cmd/server/listeners.go#SubscribeAll` 会 `json.Marshal` 后广播到 workspace 房间），因此 json tag 是客户端可见契约，本 TASK 用 golden JSON 把形状钉死。

改动面说明：`server/pkg/protocol/events.go` 超出 PRD FR-10 字面清单一处，已由架构审批确认纳入（`approval.yml#tech-design`，plan.md §0），回写期由需求负责人以 revision 修订 FR-10。

## 涉及文件 / 模块

仓根取 `execution_context.resources[]` 中 `repo=multica` 的 `worktreePath`；以下为该仓根相对路径：

- `server/pkg/protocol/events.go`（改：新增 1 个常量 + 1 个结构体，落在既有 `EventCRUpdated`（`:191-196`）同一 AIFIRST 区域）
- `server/pkg/protocol/events_approval_gate_test.go`（新：golden JSON 契约测试，`package protocol`，零 DB 零网络）

## 实现要点

1. 常量：`EventCRApprovalGateEntered = "cr:approval-gate-entered"`，与 `EventCRUpdated` 同构（同一 `const` 块内），带英文 `// AIFIRST: CR-2026-051 FR-1 …` 注释，注明"专用语义事件，刻意不复用 `cr:updated`（后者从 5 处发布、包含投影维护）"、"声明在此而非 `internal/governance`，因为生产者与消费者必须共享编译期契约且不得互相 import"。
2. 载荷结构体（字段顺序即 JSON 键序，不得调整）：

   ```go
   type ApprovalGateEnteredPayload struct {
       CRID         string  `json:"cr_id"`
       Status       string  `json:"status"`
       EventID      string  `json:"event_id"`
       ShellIssueID *string `json:"shell_issue_id"`
   }
   ```

3. **不加 `omitempty`**：canonical 形状要求 `shell_issue_id` 键恒在、无值时为 `null`（SDD §3.2.1 不变量 6 + §7.4 golden 用例）。该口径已经 dev-plan 评审**定案采纳**，SDD §2 术语表原来的 `omitempty` 括注已在上游回修中纠正为「键恒在、无值为 `null`」（sdd.md §2 / §9；plan.md §5.3）——四处现已一致，本 TASK 无需再做取舍判断。
4. 结构体注释（英文）须写明三件事：载荷只带定位标识（证据/标题/收件人由消费侧回读 PG，ARCHITECTURE.md §7 handler 可重放）；本结构同时是 WS 帧形状，**只允许加字段**；`ShellIssueID` 为指针因 `cr.shell_issue_id` 可空（迁移 362），且**仅作相关/诊断，不得作为查询输入**（FR-3）。
5. multica 仓内注释一律英文（其 CLAUDE.md 硬规则）；不新增 import、不引入任何 `internal/` 依赖（`pkg/protocol` 必须保持叶子包）。

## 验收条件

1. `json.Marshal(ApprovalGateEnteredPayload{CRID:"CR-2026-051", Status:"tech-design-review-pending", EventID:"CR-2026-051:status:abc1234", ShellIssueID: <指向 "11111111-1111-4111-8111-111111111111">})` 字节级等于
   `{"cr_id":"CR-2026-051","status":"tech-design-review-pending","event_id":"CR-2026-051:status:abc1234","shell_issue_id":"11111111-1111-4111-8111-111111111111"}`。
2. `ShellIssueID == nil` 时字节级等于 `{"cr_id":"…","status":"…","event_id":"…","shell_issue_id":null}`（键存在、值为 `null`，证明未加 `omitempty`）。
3. `json.Unmarshal` 上述两份 golden 回解后与原值 `reflect.DeepEqual` 相等（往返无损）。
4. 断言 `EventCRApprovalGateEntered == "cr:approval-gate-entered"` 且 `!= protocol.EventCRUpdated`。
5. `cd server && go build ./... && go vet ./pkg/protocol/` 零报告；`grep -c "AIFIRST: CR-2026-051" server/pkg/protocol/events.go` ≥ 2。

## 完成标志

`cd server && go test ./pkg/protocol/ -run ApprovalGate -v -count=1` 输出含 `--- PASS`（不接受 `--- SKIP`）；`go vet ./pkg/protocol/` 零报告；随后在 knowledge-base CR worktree 执行 `node {TOOLS_ROOT}/skills/shared/crctl/scripts/crctl.mjs task done CR-2026-051 --task CR-2026-051-TASK-01 --workspace <kb worktree>` 把任务标记 done（做完即标，不积压到回写期）。

## 接口契约

- **消费**：无上游 TASK（本 CR 首个）。仅依赖既有 `package protocol`（`server/pkg/protocol/events.go`，零 `internal/` 依赖）与标准库 `encoding/json`（仅测试）。
- **产出**（下游只许引用，禁止各自复制字段或字面量）：
  - `protocol.EventCRApprovalGateEntered string = "cr:approval-gate-entered"` — TASK-02 取别名、TASK-05 用于 `Subscribe`；
  - `type protocol.ApprovalGateEnteredPayload struct { CRID string; Status string; EventID string; ShellIssueID *string }`（json tag 见实现要点 2）— TASK-02 构造并发布，TASK-05 `parsePayload` 做真类型断言，TASK-03/TASK-06 断言 golden JSON。

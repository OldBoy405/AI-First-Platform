---
id: CR-2026-051-TASK-08
type: TASK
cr-ref: CR-2026-051
plan-ref: "change-requests/CR-2026-051/plan.md"
sdd-ref: "change-requests/CR-2026-051/sdd.md"
title: 改动面静态核对、全量回归与 CUSTOM.md 台账收尾
slug: change-surface-audit-and-custom-ledger
status: pending
estimate: 6h
depends-on: [CR-2026-051-TASK-03, CR-2026-051-TASK-07]
created: 2026-08-25T23:20:00+08:00
---

## 任务描述

收口三件事：① 按 AC-8 逐条核对改动文件集合与零改动边界；② 跑全量回归证明 AC-6（Web 审批链路行为不变）与 AC-9（覆盖面）成立；③ 按 `CUSTOM.md` **彼时现状**顺延登记本 CR 的一行台账（AGENTS.md 纪律 10：漏记的后果是双周 rebase 时定制无法逐条核对、`// AIFIRST:` 标记可能静默丢失）。同时把 plan.md §0 的两项 PRD 偏离写进回写清单，避免回写期漏改。

## 涉及文件 / 模块

仓根取 `execution_context.resources[]` 中 `repo=multica` 的 `worktreePath`；以下为该仓根相对路径：

- `CUSTOM.md`（改：顺延新增一行；当前最大条目 #52，**落码时以彼时 CUSTOM.md 现状为唯一事实源**，表格划分与字段以其现状为准，不照抄本卡格式）
- 无代码改动。若核对中发现越界文件，在本 TASK 内回退该文件，不新增功能改动。

knowledge-base CR worktree（`repo=ai-first-platform-docs`）侧：`change-requests/CR-2026-051/` 的 `traceability.yml` 由 crctl 写入，**不手改**；回写偏离项记录写在本 TASK 的完成证据与 `write-test-report` 输入里。

## 实现要点

1. **改动面核对（AC-8）**，逐条比对 `git diff --name-only <CR 基线>...HEAD` 与下列合法集合：
   - `server/internal/governance/crsync.go`
   - `server/internal/integrations/lark/approval_reminder.go`（新）、`approval_reminder_card.go`（新）
   - `server/internal/integrations/lark/client.go`（1 行接口方法）、`http_client.go`（helper 提取）
   - `server/cmd/server/router.go`（wiring）
   - `server/pkg/protocol/events.go`（**+1 常量 +1 载荷类型；超 FR-10 字面清单，已由架构审批确认**，approval.yml#tech-design / plan.md §0）
   - 测试文件：`pkg/protocol/events_approval_gate_test.go`、`internal/governance/crsync_approval_gate_test.go`、`internal/integrations/lark/approval_reminder_test.go`、`approval_reminder_card_test.go`、`cmd/server/approval_reminder_wiring_test.go`（5 新）+ 4 个上游替身各 1 行空实现（`outbound_test.go`、`outcome_replier_test.go`、`typing_indicator_test.go`、`inbound_enricher_test.go`）
   - `CUSTOM.md`
   集合外的任何文件即越界，当场回退。
2. **零改动硬断言**：`git diff --name-only` 中 `server/pkg/db/queries/`、`server/pkg/db/generated/`、`server/migrations/`、`packages/`、`apps/` 前缀零命中；`tools` 仓 worktree `git status --porcelain` 为空且 HEAD 未动（本 CR tools 零改动）；`grep -rn "outbox\|retry\|撤回" 本 CR 新增代码` 无对应实现（不新增重试/outbox/撤回，AC-8）。
3. **`// AIFIRST:` 标记核对**：每处上游文件改动都有 `// AIFIRST: CR-2026-051 …` 英文注释（`crsync.go`、`client.go`、`http_client.go`、`router.go`、`pkg/protocol/events.go`、4 个测试替身），`grep -c` 计数与改动点数一致。
4. **全量回归（AC-6 / AC-9）**：
   - `cd server && go build ./... && go vet ./pkg/protocol/ ./internal/governance/ ./internal/integrations/lark/ ./cmd/server/`
   - `go test ./internal/governance/ -count=1`（含既有 `approval_test.go`、`approval_crosscheck_test.go`、`project_gates_test.go` —— AC-6 的直接证据：Web 审批签名/证据/漂移/grant 链路行为不变，且这些测试**一行未改**）
   - `go test ./internal/integrations/lark/ -count=1`、`go test ./cmd/server/ -count=1`、`go test ./pkg/protocol/ -count=1`
   - 逐条对照 `CUSTOM.md#已知测试失败基线` 排除既有失败；**新增失败即回归**，必须在本 TASK 内定位修复或回退相关改动。
5. **AC 覆盖面清点（AC-9）**：按 plan.md §5.2 的归属表逐条确认对应测试存在且 `--- PASS`（不是 `--- SKIP`），形成一张 13 行的 AC → 测试名 → 结果表，作为 `write-test-report` 的输入草稿（本 TASK 不代替测试报告）。
6. **CUSTOM.md 登记**（评审强制项，不得拿 CUSTOM #5 顶替 —— #5 只覆盖 governance 包的 pgx 例外，不覆盖 lark 包），「合并注意」列须含 SDD §7.3 的五项：
   ① `crsync.go` 发布点随上游事件机制改名跟改；
   ② **两条裸 SQL 依赖的列清单**：`cr.shell_issue_id`/`cr.title`、`issue.project_id`、`project.id`、`workspace.slug`、`member.role`、`channel_user_binding.bound_at`/`channel_user_id`/`multica_user_id`/`installation_id`/`channel_type`/`workspace_id`、`channel_installation.id`/`status`/`channel_type`/`workspace_id` —— 并注明 `config` JSONB **不在**裸 SQL 依赖面内（由上游 `installationFromRow` 解码）；
   ③ `APIClient` 接口新方法与 4 个测试替身空实现须整组保留；
   ④ `pkg/protocol/events.go` 的常量与载荷类型（与 #22/#23 同文件，上游新增事件类型时取并集）；
   ⑤ 依赖的上游凭据入口 `InstallationService.GetInWorkspace` / `installationCredentialsFor`，上游改签名则跟改。
   另在"验证"字段写明本 CR 的取证命令（第 4 条的四条 `go test`）。
7. **回写期偏离登记**：把 plan.md §0 两项写成一段明确的回写待办（`writeback-prd-sdd` 期以 revision 修订 PRD **FR-10 改动清单**加入 `server/pkg/protocol/events.go`、修订 **§4.4 可观测性**允许事件级 `failed` 无 recipient 字段，并注明"结论是否受影响：不受影响"），随本 TASK 的提交信息与测试报告输入一并留痕。

## 验收条件

1. 改动面核对输出（`git diff --name-only` 全量清单 + 与合法集合的逐条比对结论）零越界；零改动前缀断言全部为空命中。
2. `// AIFIRST: CR-2026-051` 标记计数与上游改动点数一致（至少 7 处文件命中）。
3. 第 4 条的四条 `go test` 全部通过；新增失败为 0（既有基线失败逐条对照 `CUSTOM.md#已知测试失败基线` 注明）；`git diff` 证明 `approval_test.go`、`approval_crosscheck_test.go`、`project_gates_test.go`、`http_client_test.go` 一行未改。
4. 13 行 AC → 测试名 → 结果表齐全，无 `--- SKIP` 冒充通过。
5. `CUSTOM.md` 新增行落地：编号顺延（不与既有冲突）、五项合并注意齐备、验证命令可复制执行；`git diff CUSTOM.md` 只有新增行（不改动既有行）。
6. 回写待办两项已成文留痕。

## 完成标志

上述 6 条全通过；`crctl task done CR-2026-051 --task CR-2026-051-TASK-08 --workspace <kb worktree>` 已登记（8 个 TASK 全部 done，不留到回写期补标 —— AGENTS.md 纪律 8）。随后 CR 的下一步以 `crctl next CR-2026-051` 为准（预期为 `write-test-report` / `review-code` 方向的开发期节点），本 TASK 不自行推进状态。

## 接口契约

- **消费**：TASK-01~07 的全部产出（不新增调用面）；plan.md §5.1 的 checklist 与 §5.2 的 AC 归属表；`CUSTOM.md` 现状（编号、表格划分、字段定义以彼时文件为唯一事实源）。
- **产出**：
  - `CUSTOM.md` 新增一行台账（双周 rebase 逐条核对的唯一清单）；
  - 13 行 AC → 测试名 → 结果对照表（`write-test-report` 的输入草稿）；
  - 两项回写期 PRD revision 待办（`writeback-prd-sdd` 消费）。

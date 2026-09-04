---
cr: CR-2026-059
pipeline-node: write-dev-plan（dev-plan attempt 1 BLOCK 回修完成，待独立 review-dev-plan 复评 attempt 2/3）
status: task-breakdown
updated: 2026-09-04T17:55:00+08:00
owner-agent: dev-agent
---

# CR-2026-059 工作流导航缓存（_context.md）

> 导航缓存，非 canonical。canonical 事实以 `cr.md` / `review-loop.yml` / `traceability.yml` / `review-annotations/*` 为准。

## 当前状态

- 架构期已闭环：sdd.md cycle 3 复评 PASS（canonical 落盘，attempt 3/3），人工 `approve --stage tech-design` 已于 2026-09-04 批准。
- dev-plan 评审环 attempt 1/3 = **BLOCK（9 条 blocker B-DP-01..09，`review-annotations/dev-plan.yml` 已落盘并随 commit `6067ca8` 提交）**，已按 repair-target 回修完成：commit `88cd3ee`（plan.md + TASK-01..04 + _index.yml + cr.md status 重推 task-breakdown），checkpoint batch `2b831656f9c40467` 三仓 confirmed 并推送。
- 下一步：独立 `quality-reviewer-agent` 执行 `review-dev-plan` 复评（attempt 2/3，逐条闭合 B-DP-01..09）。

## 本轮回修落点（attempt 1 → 2）

- **B-DP-01**：plan §6.1 交付覆盖表全部 canonical TASK id + 双向集合断言段（A=表内 id 集、B=_index.yml id 集，A=B 已实测）。
- **B-DP-02**：TASK-01 `BindDraftAttachmentsToChatMessageParams` 增 `UploaderType string/UploaderID pgtype.UUID`（WHERE 含 uploader 门禁）；TASK-02 消费签名从鉴权身份推导（恒 `"member"`），验收补跨上传者负向向量。
- **B-DP-03**：TASK-01 接口契约逐项锁定 sqlc Params/pgtype/返回/冲突无行语义（含 `SetChatSessionAgentID`、`GetChatMessageInWorkspace` 经 session JOIN、`CreateChatMessage` 作者列扩展、幂等五查询）；TASK-02 `DiscussionSessionDeps` 完整字段（Queries/TxStarter/TaskSvc）+ 事件/队列责任边界声明。
- **B-DP-04**：`buildMergedForwardContentFromMessages(ctx, taskSvc *TaskService, msgs []db.ChatMessage, registerCR bool) string` 签名在 TASK-02 产出与 TASK-03 消费逐字一致（包归属 service、unexported；TASK-03 经扩展后 `IssueService.MergeForwardDiscussion` 消费）；merge-forward message_ids 幂等（reserve/接管/finalize/失败删键 + 崩溃窗口诚实注记）落 TASK-02。
- **B-DP-05**：cmd-04 args 扩展为 `./cmd/server/ ./internal/handler/ ./internal/service/ ./internal/realtime/`（timeout 1800），AC-29/FR-20 联合验收；TASK-03 验收 2 同步同一命令。
- **B-DP-06**：cmd-06 增跑 `projects/components/discussion-pane.test.tsx`；plan §7 AC-6 唯一主责 = TASK-04（cmd-06，关联 TASK-03 cmd-02）、AC-18 = TASK-04（cmd-06）；TASK-04 验收 3 补 pane 行为向量。
- **B-DP-07**：TASK-04 补 merge-forward 前端契约——client `mergeForwardDiscussion(projectId, {commentIds}|{messageIds}, registerCr, idempotencyKey?)`、pane 消息源切换（shared 选 ChatMessage/legacy 选 comment）、message_ids+Idempotency-Key 与 legacy 分支、前端验收。
- **B-DP-08**：CUSTOM.md 登记改为各 TASK 各自登记并纳入完成标志（plan §3/§5 ⑦；TASK-01..04 完成标志各自含登记条目范围），禁止预登记。
- **B-DP-09**：TASK-03 产出 HTTP 契约补全（GET discussion 项目不存在 404；shared 消息列表非成员/错 kind/跨项目 404、归档 200 只读；merge-forward 权限/幂等/legacy），TASK-04 消费同一份完整清单。

## 本轮产物（回修后）

- `plan.md`（updated 2026-09-04T17:45+08:00）：交付覆盖表 26 FR 行（canonical id）+ 双向集合断言；证据命令表 cmd-01..06（cmd-04 四包联合、cmd-06 pane+parity）；AC 矩阵 32 行（AC-6/AC-18 唯一主责 TASK-04/cmd-06，后端关联 TASK-03）。
- `tasks/TASK-01..04.md` + `_index.yml`（`crctl task init --count-hint 4` 刷新，totalEstimateHours=72h）：TASK-04 标题增「merge-forward 适配」。
- commit：`6067ca8`（评审三账本 canonical）+ `88cd3ee`（回修 + status task-breakdown）；checkpoint batch `2b831656f9c40467`（ai-first-platform-docs `88cd3ee` confirmed；multica `be6426a7c`/tools `8b1e352` unchanged confirmed）。

## 评审入口（给 reviewer / 恢复会话）

1. 权威 worktree：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-059`（分支 `requirement/CR-2026-059`，HEAD `571f64b` = checkpoint metadata）。
2. 评审对象：回修后 `plan.md` + `tasks/TASK-01..04.md` + `tasks/_index.yml`，对照已审批 `sdd.md`；evidence 基线 = multica CR worktree HEAD `be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d`。
3. 前置：`multica cr bind-current-task CR-2026-059` → `crctl gate CR-2026-059 --for dev-plan-reviewing`（已预跑 pass）→ `crctl review-record CR-2026-059 --stage dev-plan --bump-attempt`（attempt 2，轮次由 crctl 记账；无论 PASS/BLOCK 都落盘 canonical；**落盘后请随即提交并推送三账本**）。
4. **复评必须逐条闭合**：B-DP-01（plan §6.1 canonical+断言）、B-DP-02（TASK-01/02 uploader 门禁）、B-DP-03（TASK-01/02/03 完整契约与 deps）、B-DP-04（TASK-02/03 带 taskSvc 签名）、B-DP-05（plan cmd-04/TASK-03 验收 2）、B-DP-06（plan §7 + cmd-06 + TASK-04 验收 3）、B-DP-07（TASK-04 merge-forward 前端）、B-DP-08（各 TASK CUSTOM.md 完成标志）、B-DP-09（TASK-03/04 HTTP 契约）。
5. PASS：落盘后回报；人工 `approve --stage dev-start` 由 coordinator 发布。BLOCK：按 repair-target 直连 @ dev-agent 回修。

## 已核实事实基线（沿用 sdd §10）

- 三仓 `workspace inspect` healthy；multica CR worktree HEAD `be6426a7c`（还原提交，树=main e8b25259）；tools `8b1e352`。
- `BindUnboundDraftAttachments` 既有 uploader 参数（attachment.sql.go:74 Params）；`buildMergedForwardContent(ctx, s *TaskService, ...)` 既有 taskSvc 依赖（project_chat.go:492）；`chat_message` 无 workspace_id 列（033）→ `GetChatMessageInWorkspace` 经 session JOIN；`discussion-pane.test.tsx` 已存在（views 测试目录同层）。

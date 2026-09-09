# _context.md — CR-2026-062 工作流导航缓存

> 本文件仅供返工与 `/resume` 导航。canonical 事实以 `cr.md`、`review-loop.yml`、`traceability.yml`、评审记录为准。

## 当前状态

- CR：CR-2026-062（AIFI-18 · 来源文档 CR-D：Team Agent 和 Private Ask 发送框 UI 优化，target-version 0.35）
- status：`task-breakdown`（plan/TASK 二次重建完成；待独立 `review-dev-plan` 合并评审 → PASS 后人工 `approve --stage dev-start`）
- Pipeline：code-implementation 前两个 authoring 节点已完成；下一节点 = `review-dev-plan`（humanApproval=false，由本 run 收尾评论 mention quality-reviewer-agent 发起）
- reviewLoop：`review-tech-design` cycle 1 attempt 1（B-005 复评 PASS 后 canonical 已重置）；`review-dev-plan` attempt 0/3（前两轮均为 UPSTREAM 未 bump，本轮为首次计数）
- 下一步以 `crctl next CR-2026-062` 为准

## 产物

- PRD：`change-requests/CR-2026-062/prd.md`（review-requirement PASS、人工审批通过）
- SDD：`change-requests/CR-2026-062/sdd.md`（**最新批准版**，含 B-005 修订 `fe689a97`：`listTasksByIssue` 按 `Promise<AgentTask[]>` 数组消费、`taskEntry = tasks.find(task => task.id === sentTaskId)` 唯一选取、空列表/未命中回落 items-only、AC-5(i)(j)/§6.9-2(iv)(v)；`review-annotations/sdd.yml` PASS、blockers=[]、subject-sha256 `5259087713930e7eee00bb6074ae0d4a3d78f9df4eb18d1256401e6afb5fdf28`，评审证据 `b2329dd0` + 人工二次审批 `493ede05`）
- PLAN：`change-requests/CR-2026-062/plan.md`（**二次重建版**，提交 `88c49757`：同步 B-005 数组语义 + 闭合 B-006——新增 cmd-09 入库版本化符号级 zero_diff 检查器、cmd-08 收窄为仅文件白名单职责）
- TASK：`change-requests/CR-2026-062/tasks/TASK-01..04.md` + `tasks/_index.yml`（**二次重建版**，待提交；`crctl task init --count-hint 4` → taskCount=4、totalEstimateHours=64 与 plan §5 一致，FR-23 交叉校验无差异）
- 状态提交：advance `tech-design-reviewed → task-breakdown`（trigger `write-dev-tasks`，`--expect tech-design-reviewed` 通过）

## dev-plan 评审 blockers（canonical `review-annotations/dev-plan.yml`，最新评审提交 `246a5109`，route=upstream；新评审落盘后将被覆盖）

- B-001~B-004：已关闭（reviewer 建议列「已解决」）
- **B-005（已闭环）**：SDD 侧已回修（`fe689a97`）→ `review-tech-design` PASS（`b2329dd0`）→ 人工二次审批（`493ede05`）；本轮重建已同步 TASK-02 至数组/唯一选取/未命中回落口径。
- **B-006（本轮重建已闭合，待 review-dev-plan 复核）**：plan §5/§6.1 FR-7/§6.2/§7 AC-8 与 TASK-01/04 已改为——cmd-08 仅文件白名单职责；新增 cmd-09 = `packages/views/chat/components/chat-input-zero-diff.test.ts`（修改 chat-input.tsx 前从基线 `117fc6be` 逐字提取 S1 `ChatInputProps` L58–160 / S2 `ChatInput` L162–790 / S3 `ChatInputDraftAdapter` L810–827 / S4 `ChatInputCoreProps` L829–833 四段快照，运行时 `\r\n→\n` 规范化后 substring 逐字命中 + 五个符号锚点各恰一次，读取/解析失败硬失败）；删除「name-only 清单可证明符号零 diff/符号零出现」的错误完成条件。

## TASK 拆分（4 个，二次重建版）

- TASK-01（16h）：ChatInputCore 两层 DOM + flow 底栏 + ariaLabel/stopAriaLabel + allowSubmitWhileRunning + **零差异检查器（cmd-09，B-006）**；回滚 RU4
- TASK-02（20h）：Team Agent 消息流/队列栏/横幅两层 + ModePane @container + 工具栏 leftAdornment（project-chat-model-row 随行移除）+ 双源停止路径（**B-005 数组口径**：tasks.find by sentTaskId、未命中回落 items-only）；depends TASK-01；回滚 RU3
- TASK-03（12h）：Private Ask 横幅两层 + 工具栏 leftAdornment（private-ask-model-row → private-ask-model-picker）+ 停止路径原样；depends TASK-01、TASK-02；回滚 RU2
- TASK-04（16h）：e2e spec 真跑 + 差异文档 + 全量回归 + 受控 diff 白名单核对（cmd-08 文件级）+ 符号级 zero_diff 复核（cmd-09）；depends TASK-02、TASK-03；回滚 RU1

## 权威工作区与代码基线

- operational_workspace：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-062`
- 代码仓（resources[] 原样）：multica worktree `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-062`（HEAD `117fc6be657f91d43df5892b52782a18329c7aed`，SDD 全部既有实现证据基于此 SHA）
- tools worktree：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-062`（无实施改动；diff 白名单经 tools 仓 crctl 受控执行）

## 评审与回修入口

- 下一节点 `review-dev-plan`（独立 fresh reviewer，由本 run 收尾评论 mention 发起；attempt 1/3）：
  - 评审对象：`change-requests/CR-2026-062/plan.md`（二次重建 `88c49757`）+ `change-requests/CR-2026-062/tasks/`（二次重建 TASK-01..04 + `_index.yml`）；对照已审批 `sdd.md`（`review-annotations/sdd.yml` verdict=pass、subject-sha256 `52590877…`，评审证据 `b2329dd0`、审批 `493ede05`）、`prd.md` 按 SDD 引用抽查、来源文档 §12 CR-D/§13；首轮 blockers 权威清单见 canonical `review-annotations/dev-plan.yml`（提交 `246a5109`）——本轮重建声称 B-005/B-006 已解决，请逐条回修可重验
  - PASS 且 blockers=[] → 保持 `task-breakdown`，停在人工审批节点不执行 approve（「确认进入代码开发」的 `approve --stage dev-start` 指令由 coordinator 发布）；BLOCK → 按 repair-target 双轨：`write-dev-plan`（回修本链）/ `write-tech-design`（上游）
- 后续节点：approve-dev-start（人工）→ implement-code → write-test-report → review-code → approve-code（人工）；发布经 merge/writeback 流程（不进交付 TASK）

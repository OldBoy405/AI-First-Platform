# _context.md — CR-2026-062 工作流导航缓存

> 本文件仅供返工与 `/resume` 导航。canonical 事实以 `cr.md`、`review-loop.yml`、`traceability.yml`、评审记录为准。

## 当前状态

- CR：CR-2026-062（AIFI-18 · 来源文档 CR-D：Team Agent 和 Private Ask 发送框 UI 优化，target-version 0.35）
- status：`tech-design-review-pending`（dev-plan 上游 BLOCK 的 B-005 已在 SDD 回修，提交 `fe689a97`；待独立 `review-tech-design` 复评 → 人工架构审批 → 重建 plan/TASK 关闭 B-006）
- Pipeline：回退到 architecture-design 复审链；下一节点 = `review-tech-design`（humanApproval=false，why=SDD 已修订（subject digest 不一致），重新评审刷新证据）
- reviewLoop：`review-tech-design` cycle 3 attempt 2（本轮复评 bump 后为 attempt **3/3 = 本 cycle 最后一轮**——若仍 BLOCK 按 Skill 停止自动回修，需人工 `review-loop reset`）；`review-dev-plan` attempt 0/3（首轮与本轮均为 UPSTREAM 未 bump）
- 下一步以 `crctl next CR-2026-062` 为准

## 产物

- PRD：`change-requests/CR-2026-062/prd.md`（review-requirement PASS、人工审批通过）
- SDD：`change-requests/CR-2026-062/sdd.md`（**B-005 回修版**，提交 `fe689a97`，+22/−19：§4.3.1 `tasks`/`taskEntry`/`taskActive`/`taskTerminal` 信号表、生命周期闭合表、边界、§4.4、D-7、AC-5(i)(j)、§6.9-2(iv)(v)、§9 scope_in、依赖 #4/#14/#18、SDD-CLOSE-04/05；`listTasksByIssue` 按 `Promise<AgentTask[]>` 数组消费、`taskEntry = tasks.find(task => task.id === sentTaskId)` 唯一选取、空列表/未命中回落 items-only；上一版 cycle 3 attempt 2 PASS 证据（subject-sha256 `7e85f6b2…`）已因修订失效）
- PLAN：`change-requests/CR-2026-062/plan.md`（重建版 `ca562bc8`+`8d7c229a`——**相对 B-005 修订后的 SDD 已过期**，须在本次技术评审 PASS + 人工审批后再次重建，同步 TASK-02 并关闭 B-006）
- TASK：`change-requests/CR-2026-062/tasks/TASK-01..04.md` + `tasks/_index.yml`（重建版 `419d5274`——同上，待重建；`crctl task init --count-hint 4` → taskCount=4、totalEstimateHours=64）
- 状态提交：advance `tech-design-review-pending → tech-designing`（trigger `review-tech-design:block -> write-tech-design`，commit `1b07eff3`）→ advance `tech-designing → tech-design-review-pending`（trigger `write-tech-design-complete`，commit `943bf2c2`）

## dev-plan 评审 blockers（canonical `review-annotations/dev-plan.yml`，最新评审提交 `246a5109`，route=upstream）

- B-001~B-004：上一轮已关闭（reviewer 建议列「已解决」；重建后不属本轮阻塞）
- **B-005（本轮新增，上游设计疑点）**：SDD §4.3.1 把 `listTasksByIssue` 结果当单个 `taskEntry` 读 `taskEntry.status`，但 API 返回 `Promise<AgentTask[]>`。**本轮已回修**（`fe689a97`）：数组消费 + `tasks.find(task => task.id === sentTaskId)` 唯一选取 + 空列表/未命中回落 items-only + AC-5(i)(j)/§6.9-2(iv)(v) 测试行；待重新技术评审/审批后同步 TASK-02。
- **B-006（本轮新增，plan/TASK 侧）**：`cmd-08`（`crctl git diff --name-only`）被用于证明 `chat-input.tsx` 内 `ChatInput` 函数体与 props 签名 zero_diff，TASK-01/04 完成标志要求这些符号"在 diff 清单中零出现"——name-only 不含符号信息且该文件必然出现。**待重建 plan/TASK 时闭合**：增加稳定符号级/patch 级 zero_diff 证据（优先版本化检查器，或明确受控 patch diff 的可审计判定），删除 name-only 可证明符号零 diff 的错误完成条件，`cmd-08` 仅保留文件白名单职责。

## TASK 拆分（4 个，重建版，待下一轮再重建）

- TASK-01（16h）：ChatInputCore 两层 DOM + flow 底栏 + ariaLabel/stopAriaLabel + allowSubmitWhileRunning（multica packages/views/chat）；回滚 RU4
- TASK-02（20h）：Team Agent 消息流/队列栏/横幅两层 + ModePane @container + 工具栏 leftAdornment（project-chat-model-row 随行移除）+ 双源停止路径；depends TASK-01；回滚 RU3
- TASK-03（12h）：Private Ask 横幅两层 + 工具栏 leftAdornment（private-ask-model-row → private-ask-model-picker）+ 停止路径原样；depends TASK-01、TASK-02；回滚 RU2
- TASK-04（16h）：e2e spec 真跑 + 差异文档 + 全量回归 + 受控 diff 白名单核对；depends TASK-02、TASK-03；回滚 RU1

## 权威工作区与代码基线

- operational_workspace：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-062`
- 代码仓（resources[] 原样）：multica worktree `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-062`（HEAD `117fc6be657f91d43df5892b52782a18329c7aed`，SDD 全部既有实现证据基于此 SHA）
- tools worktree：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-062`（无实施改动；diff 白名单经 tools 仓 crctl 受控执行）

## 评审与回修入口

- 下一节点 `review-tech-design`（独立 fresh reviewer，由本 run 收尾评论 mention 发起；cycle 3 attempt 3/3，最后机会，回修必须一次闭合）：
  - 评审对象：`change-requests/CR-2026-062/sdd.md`（本轮修订点：§1.3、§4.3.1 信号表/生命周期闭合表/边界、§4.4、D-7、§6 AC-5、§6.9-2、§9 scope_in、依赖 #4/#14/#18、SDD-CLOSE-04/05）；对照 `prd.md`、来源文档 §12 CR-D/§13、canonical `review-annotations/dev-plan.yml`（提交 `246a5109`，B-005 原文）
  - PASS 且 blockers=[] → 保持 `tech-design-review-pending`，停在人工架构审批节点不执行 approve（审批指令由 coordinator 发布）；BLOCK → `crctl advance --to tech-designing --trigger "review-tech-design:block -> write-tech-design" --expect tech-design-review-pending`，回修由本 dev-agent 承接后再次复评
- 后续链（SDD 复审 PASS + 人工审批后，由 coordinator 委派）：重建 plan.md/tasks/（覆盖 `ca562bc8`/`419d5274`；同步 TASK-02 至 B-005 口径；关闭 B-006——符号级 zero_diff 证据、cmd-08 仅文件白名单）→ mention quality-reviewer-agent 发起新的独立 `review-dev-plan`
- 后续节点：approve-dev-start（人工）→ implement-code → write-test-report → review-code → approve-code（人工）；发布经 merge/writeback 流程（不进交付 TASK）

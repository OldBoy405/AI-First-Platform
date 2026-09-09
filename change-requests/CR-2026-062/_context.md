# _context.md — CR-2026-062 工作流导航缓存

> 本文件仅供返工与 `/resume` 导航。canonical 事实以 `cr.md`、`review-loop.yml`、`traceability.yml`、评审记录为准。

## 当前状态

- CR：CR-2026-062（AIFI-18 · 来源文档 CR-D：Team Agent 和 Private Ask 发送框 UI 优化，target-version 0.35）
- status：`tech-design-review-pending`（review-dev-plan BLOCK route=upstream → 回技术设计修订链；canonical 评审提交 `db136cbe`，状态回退提交 `aeef8813`）
- Pipeline：architecture-design，下一节点 = `review-tech-design`（humanApproval=false，why=存在较新的 dev-plan 上游设计疑点，技术评审证据过时，重新评审）
- reviewLoop：`review-tech-design` cycle 2 / attempt 2（上次 PASS）；**本轮 SDD 已再修订，复评将 bump 至 cycle 2 attempt 3/3（该 cycle 最后一轮，BLOCK 则需人工 review-loop reset）**；`review-dev-plan` attempt 0/3（UPSTREAM 未 bump）
- 下一步以 `crctl next CR-2026-062` 为准

## 产物

- PRD：`change-requests/CR-2026-062/prd.md`（review-requirement PASS、人工审批通过）
- SDD：`change-requests/CR-2026-062/sdd.md`（本轮 B-001 上游回修提交 `13c46469`：§9 testid 保留/替换契约 + `multica/CUSTOM.md` 治理 sidecar 纳入 scope_in + AC-8 受控 `crctl git diff` + §6.9-3 e2e 真跑证据契约；上轮 PASS subject-sha256 `47388739…` 已失效，待重新评审/审批）
- PLAN：`change-requests/CR-2026-062/plan.md`（提交 `40654e0b`，**待 SDD 重新审批后按 B-002/B-003/B-004 重建**）
- TASK：`change-requests/CR-2026-062/tasks/TASK-01..04.md` + `tasks/_index.yml`（提交 `0d3497ac`，同上待重建）
- 状态提交：本轮 advance `tech-design-review-pending → tech-designing`（trigger `review-tech-design:block -> write-tech-design`）与 `tech-designing → tech-design-review-pending`（trigger `write-tech-design-complete`）

## dev-plan 评审 blockers（canonical `review-annotations/dev-plan.yml`，route=upstream）

- B-001（上游，本轮已修 sdd.md）：testid 保留/替换契约 + CUSTOM.md 治理 sidecar 批准范围
- B-002（plan/TASK 重建时修）：真实 e2e 真跑证据、packages/views 全量 vitest、diff 白名单各配稳定 cmd-NN；环境不可建立时技术中止，不得把未执行关键 AC 记为完成
- B-003（plan/TASK 重建时修）：diff 白名单核对改用受控 `crctl git diff --name-only <base> --cwd <resources[].worktreePath>`（原生 git 被 deny）
- B-004（plan/TASK 重建时修）：回滚单元按逆拓扑定义组合回滚（revert TASK-01 连带 02/03/04），同步风险表与覆盖表回滚列

## TASK 拆分现状（4 个，重建前参考，见 plan.md 附录）

- TASK-01（16h）：ChatInputCore 两层 DOM + flow 底栏 + ariaLabel/stopAriaLabel + allowSubmitWhileRunning（multica packages/views/chat）
- TASK-02（20h）：Team Agent 消息流/队列栏/横幅两层 + ModePane @container + 工具栏 leftAdornment + 双源停止路径（multica packages/views/projects）；depends TASK-01
- TASK-03（12h）：Private Ask 横幅两层 + 工具栏 leftAdornment + 停止路径原样；depends TASK-01、TASK-02
- TASK-04（16h）：e2e spec + 差异文档 + 全量回归收尾；depends TASK-02、TASK-03

## 权威工作区与代码基线

- operational_workspace：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-062`
- 代码仓（resources[] 原样）：multica worktree `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-062`（HEAD `117fc6be657f91d43df5892b52782a18329c7aed`，SDD 全部既有实现证据基于此 SHA）
- tools worktree：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-062`（无实施改动）

## 评审与回修入口

- 下一节点 `review-tech-design`（独立 fresh reviewer，由本 run 收尾评论 mention 发起）：
  - 评审对象：`change-requests/CR-2026-062/sdd.md`（本轮修订点：§1.1 表 CUSTOM.md 行、§9 scope_in/zero_diff testid 契约与治理 sidecar、§6 AC-3/AC-7/AC-8、§6.9-3 证据契约）；对照 `prd.md`、来源文档 §12 CR-D/§13
  - 前置：CR status=`tech-design-review-pending`；`workspace inspect` 三仓 healthy；reviewLoop cycle 2 attempt 2 → 本轮 bump 至 3/3
  - PASS 且 blockers=[] → 停在人工架构审批节点（`crctl approve --stage tech-design`，指令由 coordinator 发布，本 Agent 不代签）；审批后由 coordinator 委派重建 plan/TASK（落实 B-002/B-003/B-004）
  - BLOCK → `crctl advance --to tech-designing --trigger "review-tech-design:block -> write-tech-design" --expect tech-design-review-pending`；若 bump 后达到 maxAttempts=3 则停止自动回修，需人工 `review-loop reset`
- 后续节点：approve-tech-design（人工）→ write-dev-plan → write-dev-tasks → review-dev-plan → approve-dev-start（人工）→ implement-code → write-test-report → review-code → approve-code（人工）；发布经 merge/writeback 流程（不进交付 TASK）

# _context.md — CR-2026-062 工作流导航缓存

> 本文件仅供返工与 `/resume` 导航。canonical 事实以 `cr.md`、`review-loop.yml`、`traceability.yml`、评审记录为准。

## 当前状态

- CR：CR-2026-062（AIFI-18 · 来源文档 CR-D：Team Agent 和 Private Ask 发送框 UI 优化，target-version 0.35）
- status：`tech-design-review-pending`（review-tech-design cycle 3 attempt 1 BLOCK：B-001 `project-chat-model-row` 锚点残留 → 本轮定点回修完成，待独立复评）
- Pipeline：architecture-design，下一节点 = `review-tech-design`（humanApproval=false，why=SDD 已修订（subject digest 不一致），重新评审刷新证据）
- reviewLoop：`review-tech-design` **cycle 3 / attempt 1**（本轮 bump 后将至 2/3）；`review-dev-plan` attempt 0/3（UPSTREAM 未 bump）
- 下一步以 `crctl next CR-2026-062` 为准

## 产物

- PRD：`change-requests/CR-2026-062/prd.md`（review-requirement PASS、人工审批通过）
- SDD：`change-requests/CR-2026-062/sdd.md`（本轮 B-001 定点回修提交 `19d98578`：testid 二选一闭合为「删除、不迁移」——§9 scope_in 改显式保留/移除/替换清单（移除 2 项：`private-ask-model-row`（替换为新增 `private-ask-model-picker`）、`project-chat-model-row`（无替换锚点）；新增 1 项；其余保留），§1.1/§3.2/AC-4/§6.9-2/zero_diff/依赖 #4 同步；上轮 PASS subject-sha256 `47388739…` 已失效，待重新评审/审批）
- PLAN：`change-requests/CR-2026-062/plan.md`（提交 `40654e0b`，**待 SDD 重新审批后按 B-002/B-003/B-004 重建**）
- TASK：`change-requests/CR-2026-062/tasks/TASK-01..04.md` + `tasks/_index.yml`（提交 `0d3497ac`，同上待重建）
- 状态提交：本轮 advance `tech-designing → tech-design-review-pending`（trigger `write-tech-design-complete`）；上一轮评审回退 `tech-design-review-pending → tech-designing`（`659133dc`）与评审证据 `93eaeb2f` 由 reviewer 落盘

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
  - 评审对象：`change-requests/CR-2026-062/sdd.md`（本轮修订点：§1.1 两宿主行、§3.2 两 TSX 锚点注释、§6 AC-4/§6.9-2 锚点口径、§9 scope_in 保留/移除/替换清单 + zero_diff、依赖 #4；B-001 闭合为「删除、不迁移」）；对照 `prd.md`、来源文档 §12 CR-D/§13；dev-plan 上游 blockers 见 canonical `review-annotations/dev-plan.yml`（提交 `db136cbe`）
  - 前置：CR status=`tech-design-review-pending`；`workspace inspect` 三仓 healthy；reviewLoop cycle 3 attempt 1 → 本轮 bump 至 2/3（如仍 BLOCK，按 Skill 回退 `tech-designing`，达到 3/3 则需人工 `review-loop reset`）
  - PASS 且 blockers=[] → 停在人工架构审批节点（`crctl approve --stage tech-design`，指令由 coordinator 发布，本 Agent 不代签）；审批后由 coordinator 委派重建 plan/TASK（落实 B-002/B-003/B-004：稳定证据命令、受控 crctl git diff、逆拓扑组合回滚单元）
  - BLOCK → `crctl advance --to tech-designing --trigger "review-tech-design:block -> write-tech-design" --expect tech-design-review-pending`
- 后续节点：approve-tech-design（人工）→ write-dev-plan → write-dev-tasks → review-dev-plan → approve-dev-start（人工）→ implement-code → write-test-report → review-code → approve-code（人工）；发布经 merge/writeback 流程（不进交付 TASK）

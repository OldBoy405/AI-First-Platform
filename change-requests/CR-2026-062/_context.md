# _context.md — CR-2026-062 工作流导航缓存

> 本文件仅供返工与 `/resume` 导航。canonical 事实以 `cr.md`、`review-loop.yml`、`traceability.yml`、评审记录为准。

## 当前状态

- CR：CR-2026-062（AIFI-18 · 来源文档 CR-D：Team Agent 和 Private Ask 发送框 UI 优化，target-version 0.35）
- status：`task-breakdown`（plan/TASK 重建完成，提交 `ca562bc8` plan + `419d5274` TASK + advance 状态提交）
- Pipeline：code-implementation，下一节点 = `review-dev-plan`（humanApproval=false，why=缺少 dev-plan.yml 评审记录）
- reviewLoop：`review-tech-design` cycle 3 attempt 2（PASS 已审批，approval `b7a07b34`）；`review-dev-plan` attempt 0/3（首轮 UPSTREAM 未 bump，重建后按 attempt 1/3 起算）
- 下一步以 `crctl next CR-2026-062` 为准

## 产物

- PRD：`change-requests/CR-2026-062/prd.md`（review-requirement PASS、人工审批通过）
- SDD：`change-requests/CR-2026-062/sdd.md`（cycle 3 attempt 2 PASS：verdict=pass、blockers=[]、subject-sha256 `7e85f6b2…`；评审证据 `f1d0f3fa`、人工二次审批 `b7a07b34`；testid 保留/移除/替换清单、CUSTOM.md 治理 sidecar、AC-8 受控 diff、§6.9-3 证据契约均已入批准范围）
- PLAN：`change-requests/CR-2026-062/plan.md`（**重建版**提交 `ca562bc8`，覆盖首轮 `40654e0b`：B-002 真实 e2e 真跑 cmd-07 / packages/views 全量 vitest cmd-04 / diff 白名单 cmd-08；B-004 §4.0 逆拓扑组合回滚单元 RU1~RU4 并同步风险表与 §6.1 回滚列；两张稳定表 + AC/业务闭环覆盖矩阵）
- TASK：`change-requests/CR-2026-062/tasks/TASK-01..04.md` + `tasks/_index.yml`（**重建版**提交 `419d5274`，覆盖首轮 `0d3497ac`；`crctl task init --count-hint 4` → taskCount=4、totalEstimateHours=64 与 plan §5 一致；TASK-04 完成边界为真跑 e2e 证据，ENVIRONMENT_MISMATCH 技术中止口径；B-003 受控 `crctl git diff --name-only 117fc6be --cwd <resources[].multica.worktreePath>`）
- 状态提交：advance `tech-design-reviewed → task-breakdown`（trigger `write-dev-tasks`，`--expect tech-design-reviewed` 通过）

## dev-plan 评审 blockers（canonical `review-annotations/dev-plan.yml`，提交 `db136cbe`，route=upstream）

- B-001：SDD 上游已修并重新评审/审批闭环（reviewer 复评建议列「已解决」；重建后不属本轮阻塞）
- B-002：重建已闭合——plan §6.2 cmd-04（全量 vitest）/cmd-07（e2e 真跑，无 --list；ENVIRONMENT_MISMATCH 中止）/cmd-08（diff 白名单核对）各为稳定 cmd-NN；TASK-04 完成边界同步
- B-003：重建已闭合——diff 白名单核对只写受控 `crctl git diff --name-only <117fc6be> --cwd <resources[].multica.worktreePath>`（禁止原生 git，路径只取 execution_context.resources），= cmd-08
- B-004：重建已闭合——plan §4.0 回滚单元 RU1~RU4（逆拓扑组合，revert 顺序恒降序），风险表 R2~R6 与 §6.1 回滚列全量同步

## TASK 拆分（4 个，重建版）

- TASK-01（16h）：ChatInputCore 两层 DOM + flow 底栏 + ariaLabel/stopAriaLabel + allowSubmitWhileRunning（multica packages/views/chat）；回滚 RU4
- TASK-02（20h）：Team Agent 消息流/队列栏/横幅两层 + ModePane @container + 工具栏 leftAdornment（project-chat-model-row 随行移除）+ 双源停止路径；depends TASK-01；回滚 RU3
- TASK-03（12h）：Private Ask 横幅两层 + 工具栏 leftAdornment（private-ask-model-row → private-ask-model-picker）+ 停止路径原样；depends TASK-01、TASK-02；回滚 RU2
- TASK-04（16h）：e2e spec 真跑 + 差异文档 + 全量回归 + 受控 diff 白名单核对；depends TASK-02、TASK-03；回滚 RU1

## 权威工作区与代码基线

- operational_workspace：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-062`
- 代码仓（resources[] 原样）：multica worktree `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-062`（HEAD `117fc6be657f91d43df5892b52782a18329c7aed`，SDD 全部既有实现证据基于此 SHA）
- tools worktree：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-062`（无实施改动；cmd-08 经 tools 仓 crctl 受控执行）

## 评审与回修入口

- 下一节点 `review-dev-plan`（独立 fresh reviewer，由本 run 收尾评论 mention 发起，attempt 1/3）：
  - 评审对象：`change-requests/CR-2026-062/plan.md`（重建版）+ `tasks/`（TASK-01..04 + `_index.yml`）；对照已审批 `sdd.md`（review-annotations/sdd.yml verdict=pass、subject-sha256 `7e85f6b2…`）、`prd.md` 按 SDD 引用抽查、来源文档 §12 CR-D/§13；dev-plan 上游 blockers 见 canonical `review-annotations/dev-plan.yml`（提交 `db136cbe`）
  - 执行口径（按 Skill）：前置仅 `crctl workspace inspect CR-2026-062` → 八类维度评审 → 临时 payload `<worktree>/.crctl/tmp/review-dev-plan.yml` → `crctl review-record --stage dev-plan --bump-attempt --from ...` 落盘
  - PASS 且 blockers=[] → 保持 `task-breakdown`，停在人工审批节点不执行 approve（「确认进入代码开发」的 `approve --stage dev-start` 指令由 coordinator 发布）
  - BLOCK → 按 repair-target 双轨：`write-dev-plan`（`advance --to tech-design-reviewed --trigger "review-dev-plan:block -> write-dev-plan" --expect task-breakdown`，回修由本 dev-agent 承接）/ `write-tech-design`（上游，回 `tech-design-review-pending`）
- 后续节点：approve-dev-start（人工）→ implement-code → write-test-report → review-code → approve-code（人工）；发布经 merge/writeback 流程（不进交付 TASK）

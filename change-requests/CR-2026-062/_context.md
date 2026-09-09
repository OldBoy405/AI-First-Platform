# _context.md — CR-2026-062 工作流导航缓存

> 本文件仅供返工与 `/resume` 导航。canonical 事实以 `cr.md`、`review-loop.yml`、`traceability.yml`、评审记录为准。

## 当前状态

- CR：CR-2026-062（AIFI-18 · 来源文档 CR-D：Team Agent 和 Private Ask 发送框 UI 优化，target-version 0.35）
- status：`task-breakdown`（code-implementation 第 1、2 节点 write-dev-plan → write-dev-tasks 已完成）
- Pipeline：code-implementation，下一节点 = `review-dev-plan`（独立 reviewer，humanApproval=false；合并评审 plan + TASK）
- reviewLoop：`review-dev-plan` 尚未有记录（首次评审 attempt 1/3 待 reviewer bump）；`review-tech-design` cycle 2 / attempt 2（PASS，人工审批已通过）
- 下一步以 `crctl next CR-2026-062` 为准

## 产物

- PRD：`change-requests/CR-2026-062/prd.md`（review-requirement PASS、人工审批通过）
- SDD：`change-requests/CR-2026-062/sdd.md`（review-tech-design PASS cycle 2 attempt 2；评审证据 `178bae83`，人工审批 `cf3482d3`）
- PLAN：`change-requests/CR-2026-062/plan.md`（本 run 新增，提交 `40654e0b`；两张稳定表 + AC/业务闭环覆盖矩阵 + 4 任务组映射附录；总工时 64h 账本口径）
- TASK：`change-requests/CR-2026-062/tasks/TASK-01..04.md` + `tasks/_index.yml`（本 run 新增，提交 `0d3497ac`；`crctl task init --count-hint 4` 生成，taskCount=4、totalEstimateHours=64）
- 状态提交：`f5bd8d09`（`tech-design-reviewed → task-breakdown`，trigger `write-dev-tasks`）

## TASK 拆分（4 个，组映射 1:1，见 plan.md 附录）

- TASK-01（16h）：ChatInputCore 两层 DOM + flow 底栏 + ariaLabel/stopAriaLabel + allowSubmitWhileRunning（multica packages/views/chat）
- TASK-02（20h）：Team Agent 消息流/队列栏/横幅两层 + ModePane @container + 工具栏 leftAdornment + 双源停止路径（multica packages/views/projects）；depends TASK-01
- TASK-03（12h）：Private Ask 横幅两层 + 工具栏 leftAdornment + 停止路径原样；depends TASK-01、TASK-02
- TASK-04（16h）：e2e spec + 差异文档 + 全量回归收尾；depends TASK-02、TASK-03
- 证据命令 cmd-01..06 见 plan.md §6.2（cmd-06 = playwright --list 口径；e2e 真跑需 FRONTEND_ORIGIN 环境）

## 权威工作区与代码基线

- operational_workspace：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-062`
- 代码仓（resources[] 原样）：multica worktree `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-062`（HEAD `117fc6be657f91d43df5892b52782a18329c7aed`，SDD 全部既有实现证据基于此 SHA）
- tools worktree：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-062`（无实施改动）

## 评审与回修入口

- 下一节点 `review-dev-plan`（独立 fresh reviewer，由本 run 收尾评论 mention 发起）：
  - 评审对象：`plan.md` + `tasks/`（对照 `sdd.md` 已审批内容、`prd.md` 按 SDD 引用抽查、来源文档 §12 CR-D/§13）
  - 前置：CR status=`task-breakdown`；`workspace inspect` 三仓 healthy；输入文件齐备
  - PASS 且 blockers=[] → 保持 `task-breakdown`，停在人工审批节点（`crctl approve --stage dev-start`，指令由 coordinator 发布，本 Agent 不代签）
  - BLOCK repair-target=`write-dev-plan` → `crctl advance --to tech-design-reviewed --trigger "review-dev-plan:block -> write-dev-plan" --expect task-breakdown`，回修 plan/TASK 后按 write-dev-plan → write-dev-tasks → review-dev-plan 重放
  - BLOCK repair-target=`write-tech-design`（上游设计疑点）→ 回 `tech-design-review-pending`，走技术设计修订链
- 后续节点：approve-dev-start → implement-code（4 个 TASK 串行）→ write-test-report（cmd-01..06）→ review-code → approve-code；发布经 merge/writeback 流程（不进交付 TASK）

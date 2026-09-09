# _context.md — CR-2026-062 工作流导航缓存

> 本文件仅供返工与 `/resume` 导航。canonical 事实以 `cr.md`、`review-loop.yml`、`traceability.yml`、评审记录为准。

## 当前状态

- CR：CR-2026-062（AIFI-18 · 来源文档 CR-D：Team Agent 和 Private Ask 发送框 UI 优化）
- status：`tech-designing`（review-tech-design BLOCK 回退后），回修完成 → 将推进 `tech-design-review-pending`
- Pipeline：architecture-design，节点 2 = `review-tech-design`（独立 reviewer，humanApproval=false）
- reviewLoop：`review-tech-design` current=1/max=3（本轮为第 1 轮 BLOCK 后的回修，attempt 1/3）
- 下一步以 `crctl next CR-2026-062` 为准

## 产物

- PRD：`change-requests/CR-2026-062/prd.md`（review-requirement PASS、人工审批通过）
- SDD：`change-requests/CR-2026-062/sdd.md`（首版 commit `06f0f28`；本轮 B-001/B-002/B-003 回修）
- 评审记录：`change-requests/CR-2026-062/review-annotations/sdd.yml`（verdict=block，评审提交 `f7009b1`）
- 状态提交历史：`3d58dac`（→tech-designing）、`31fffd2`（→tech-design-review-pending）、`2a10fd08`（BLOCK 回退 →tech-designing）

## 权威工作区与代码基线

- operational_workspace：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-062`
- 代码仓（resources[] 原样）：multica worktree `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-062`（HEAD `117fc6be657f91d43df5892b52782a18329c7aed`，SDD 全部既有实现证据基于此 SHA 实读）
- tools worktree：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-062`

## 本轮回修（review-tech-design BLOCK，attempt 1/3，repair-target=write-tech-design）

- B-001 两层 DOM：`TeamAgentStreamView` 根与 `ProjectQueueBar` 均改为外层 `CHAT_GUTTER`>内层 `CHAT_COLUMN` 两个 DOM 层（禁止单元素合并）；composer 横幅区同两层块。SDD §1.2/§4.1 规则 3/5/6、§6 AC-1、依赖 #1/#6。
- B-002 可访问名称：ChatInputCore 补传 `ariaLabel`/`stopAriaLabel`（send_tooltip/stop_tooltip）；两宿主 Model/Thinking 工具栏控件带 sr-only 类别标签（model_label/thinking_label，无新 key）。SDD §3.2/§4.2/§6 FR-6/AC-7/§7、依赖 #3/#10/#11。
- B-003 停止路径：Team Agent composer `isRunning`=最近一次发送 task 仍在活动队列（`sentTaskId`←`ProjectChatSendResult.task_id` + `projectQueueItemsOptions` items 判定），`onStop`=`useCancelProjectQueueTask`（TSUG-007 三支）；传 `allowSubmitWhileRunning=true` 保持运行中可续发（FR-7 不回归）。SDD §4.3.1/D-7、依赖 #4/#8/#11 + 新增 #13~#16。

## 评审与回修入口

- 评审对象：`sdd.md`；关键审查点 = §4.1 两层 DOM、§4.3.1 停止路径、§3.2 aria/sr-only、§9 批准范围、既有实现依赖 16 条（SHA 117fc6be）
- BLOCK → 按 reviewLoop 回 `write-tech-design`（status 回 `tech-designing`，attempt 由 reviewer bump）
- PASS + blockers=[] → 停在人工审批节点（`crctl approve --stage tech-design`），审批指令由 coordinator 发布，本 Agent 不代签
- 工作区保持干净：`_context.md` 必须随 CR 提交（独立 context 提交），否则 review-tech-design 的 workspace inspect 会因 dirty 中止

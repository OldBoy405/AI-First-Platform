# _context.md — CR-2026-062 工作流导航缓存

> 本文件仅供返工与 `/resume` 导航。canonical 事实以 `cr.md`、`review-loop.yml`、`traceability.yml`、评审记录为准。

## 当前状态

- CR：CR-2026-062（AIFI-18 · 来源文档 CR-D：Team Agent 和 Private Ask 发送框 UI 优化）
- status：`tech-design-review-pending`（cycle 2 定点回修完成，已推进待复评）
- Pipeline：architecture-design，节点 2 = `review-tech-design`（独立 reviewer，humanApproval=false）
- reviewLoop：`review-tech-design` cycle=2、current-attempt=0（所有者 review-loop reset 授权开启；下一轮评审为 cycle 2 attempt 1/3）
- 下一步以 `crctl next CR-2026-062` 为准

## 产物

- PRD：`change-requests/CR-2026-062/prd.md`（review-requirement PASS、人工审批通过）
- SDD：`change-requests/CR-2026-062/sdd.md`（首版 `06f0f28`；attempt 1 回修 B-001/B-002/B-003；attempt 2 回修 B-003 v2 双源活动性 `cae70aa`；cycle 2 回修 B-003 硬降级原子清空 `681ac67`）
- 评审记录：`change-requests/CR-2026-062/review-annotations/sdd.yml`（verdict=block；评审提交 `f7009b1`（attempt 1）、`8862ffe`（attempt 2）、`f287ef8`（attempt 3，B-003 硬降级顺序分支残留，maxAttempts 耗尽））
- review-loop：`136cac2`（review-loop reset cycle 2，独立治理提交，crctl 独占）
- 状态提交历史：`3d58dac`（→tech-designing）、`31fffd2`（→tech-design-review-pending）、`2a10fd08`（attempt 1 BLOCK 回退）、`e006c37c`（attempt 2 BLOCK 回退）、cycle 2 本轮 advance 提交（→tech-designing、→tech-design-review-pending）

## 权威工作区与代码基线

- operational_workspace：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-062`
- 代码仓（resources[] 原样）：multica worktree `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-062`（HEAD `117fc6be657f91d43df5892b52782a18329c7aed`，SDD 全部既有实现证据基于此 SHA 实读）
- tools worktree：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-062`

## 历轮回修（review-tech-design BLOCK，repair-target=write-tech-design）

- attempt 1（已关闭）：B-001 两层 DOM（外层 `CHAT_GUTTER`>内层 `CHAT_COLUMN`，禁止单元素合并）；B-002 可访问名称（ChatInputCore 补传 `ariaLabel`/`stopAriaLabel`；Model/Thinking 工具栏控件带 sr-only 类别标签，无新 key）；B-003 初版停止路径（`sentTaskId` + `useCancelProjectQueueTask` + `allowSubmitWhileRunning`）。
- attempt 2（已关闭）：修正「items 含 sentTaskId ⇒ 排队/派发/运行」语义错误——queue items 服务端仅过滤 queued+dispatched（agent.sql `ListProjectPendingTasks` L2947-2961），任务 running 后离开列表。改为**双源活动性判定**：`trackedActive = (taskInItems || taskActive) && !taskTerminal`；`taskEntry` 来自容器 Issue 任务时间线 `issueKeys.tasks(sentIssueId)`（`api.listTasksByIssue`，与 TeamAgentStreamView 同 query key，缓存收敛去重），ACTIVE={queued,dispatched,waiting_local_directory,running}、TERMINAL={completed,failed,cancelled}；`sentIssueId` 取自 `ProjectChatSendResult.issue_id`（不依赖面板 `chat.issue_id` 刷新）。
- cycle 2 定点回修（本轮，唯一残留 B-003 硬降级顺序分支）：发送成功且返回 `task_id`/`issue_id` **任一无效（空）** → **原子清空 `sentTaskId`+`sentIssueId`**（确定性转移，不留旧目标）；发送**失败** → **保留**旧活动目标（可继续取消最近一次有效发送的 task）。补「有效活动 A → 下一次发送成功返回空 ID」**顺序测试**：断言 stop 消失且**不调用 `cancelTaskById(A)`**。同步修订 §4.3.1 硬降级 bullet/sent 状态表/入队窗口/首次容器绑定/续发 bullet、§6 AC-5（f）（g）（h）、§6.9 硬降级矩阵（i）（ii）（iii）。范围未扩面。

## 评审与回修入口

- 评审对象：`sdd.md`；关键审查点 = §4.3.1 双源活动性判定与生命周期闭合表（queued→dispatched→running→terminal）+ **硬降级确定性转移**（成功空 ID → 原子清空；失败 → 保留旧目标）、AC-5（f）/（g）/（h）与 §6.9 硬降级矩阵（含顺序分支断言不调用 `cancelTaskById(A)`）、§9 批准范围、既有实现依赖 21 条（SHA 117fc6be）
- BLOCK → 按 reviewLoop 回 `write-tech-design`（status 回 `tech-designing`，attempt 由 reviewer bump；cycle 2 起 attempt 0→1/3）
- PASS + blockers=[] → 停在人工审批节点（`crctl approve --stage tech-design`），审批指令由 coordinator 发布，本 Agent 不代签
- 工作区保持干净：`_context.md` 必须随 CR 提交（独立 context 提交），否则 review-tech-design 的 workspace inspect 会因 dirty 中止

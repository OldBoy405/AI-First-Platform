# _context.md — CR-2026-062 工作流导航缓存

> 本文件仅供返工与 `/resume` 导航。canonical 事实以 `cr.md`、`review-loop.yml`、`traceability.yml`、评审记录为准。

## 当前状态

- CR：CR-2026-062（AIFI-18 · 来源文档 CR-D：Team Agent 和 Private Ask 发送框 UI 优化）
- status：`tech-design-review-pending`（cycle 2 attempt 2 定点回修完成，已推进待复评）
- Pipeline：architecture-design，节点 2 = `review-tech-design`（独立 reviewer，humanApproval=false）
- reviewLoop：`review-tech-design` cycle=2、current-attempt=1（所有者 review-loop reset 授权开启 cycle 2；下一轮评审为 cycle 2 attempt 2/3）
- 下一步以 `crctl next CR-2026-062` 为准

## 产物

- PRD：`change-requests/CR-2026-062/prd.md`（review-requirement PASS、人工审批通过）
- SDD：`change-requests/CR-2026-062/sdd.md`（首版 `06f0f28`；attempt 1 回修 B-001/B-002/B-003；attempt 2 回修 B-003 v2 双源活动性 `cae70aa`；cycle 2 回修 B-003 硬降级原子清空 `681ac67`；cycle 2 attempt 2 回修 B-003 失败回流可见动作 `9ca36ec`）
- 评审记录：`change-requests/CR-2026-062/review-annotations/sdd.yml`（verdict=block；评审提交 `f7009b1`（attempt 1）、`8862ffe`（attempt 2）、`f287ef8`（attempt 3，B-003 硬降级顺序分支残留，maxAttempts 耗尽）、`5d5a06d`（cycle 2 attempt 1，B-003 失败回流可见动作矛盾））
- review-loop：`136cac2`（review-loop reset cycle 2，独立治理提交，crctl 独占）
- 状态提交历史：`3d58dac`（→tech-designing）、`31fffd2`（→tech-design-review-pending）、`2a10fd08`（attempt 1 BLOCK 回退）、`e006c37c`（attempt 2 BLOCK 回退）、`dcc8ab2`（cycle 2 attempt 1 BLOCK 回退）、cycle 2 attempt 2 本轮 advance 提交（→tech-design-review-pending）

## 权威工作区与代码基线

- operational_workspace：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-062`
- 代码仓（resources[] 原样）：multica worktree `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-062`（HEAD `117fc6be657f91d43df5892b52782a18329c7aed`，SDD 全部既有实现证据基于此 SHA 实读）
- tools worktree：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-062`

## 历轮回修（review-tech-design BLOCK，repair-target=write-tech-design）

- attempt 1（已关闭）：B-001 两层 DOM（外层 `CHAT_GUTTER`>内层 `CHAT_COLUMN`，禁止单元素合并）；B-002 可访问名称（ChatInputCore 补传 `ariaLabel`/`stopAriaLabel`；Model/Thinking 工具栏控件带 sr-only 类别标签，无新 key）；B-003 初版停止路径（`sentTaskId` + `useCancelProjectQueueTask` + `allowSubmitWhileRunning`）。
- attempt 2（已关闭）：修正「items 含 sentTaskId ⇒ 排队/派发/运行」语义错误——queue items 服务端仅过滤 queued+dispatched（agent.sql `ListProjectPendingTasks` L2947-2961），任务 running 后离开列表。改为**双源活动性判定**：`trackedActive = (taskInItems || taskActive) && !taskTerminal`；`taskEntry` 来自容器 Issue 任务时间线 `issueKeys.tasks(sentIssueId)`（`api.listTasksByIssue`，与 TeamAgentStreamView 同 query key，缓存收敛去重），ACTIVE={queued,dispatched,waiting_local_directory,running}、TERMINAL={completed,failed,cancelled}；`sentIssueId` 取自 `ProjectChatSendResult.issue_id`（不依赖面板 `chat.issue_id` 刷新）。
- cycle 2 定点回修（已关闭）：唯一残留 B-003 硬降级顺序分支——发送成功且返回 `task_id`/`issue_id` **任一无效（空）** → **原子清空 `sentTaskId`+`sentIssueId`**（确定性转移，不留旧目标）；发送**失败** → **保留**旧活动目标。补「有效活动 A → 下一次发送成功返回空 ID」顺序测试：断言 stop 消失且不调用 `cancelTaskById(A)`。同步修订 §4.3.1 硬降级/sent 状态表、§6 AC-5（f）（g）（h）、§6.9 矩阵（i）（ii）（iii）。
- cycle 2 attempt 2（本轮，唯一残留 B-003 失败回流可见动作）：复评指出保留旧目标 + 失败保草稿（`isEmpty=false`）+ Team Agent `allowSubmitWhileRunning=true` ⇒ §4.2 `running` 判定式为 false，右下角实际渲染**发送（重试）按钮**而非 AC-5(h)/§6.9(iii) 原断言的 stop。裁定（选项一，保留 queue-send/retry 优先级，与 ChatInput L758-767 权威判定式及 host 代码「on failure the draft is preserved so the user can just hit send again」一致）：**失败后保草稿 + 发送（重试）按钮；清空草稿后（`isEmpty=true`）stop 重新出现并可取消保留的旧目标 A**。同步修订 §4.2（可见动作口径单一事实 + JSX 注释）、§4.3 失败重试行、§4.3.1 sent 状态表/硬降级、§4.4 边界验证、D-7 Consequences、§1.3 一屏流程、AC-5（a）（b）（d）（h）（成功路径 stop 断言补 isEmpty 前置）、§6.9（iii）与双源矩阵 stop 断言前置、SDD-CLOSE-04e/05、依赖 #2/#3（补 ChatInput L758-767 判定式与 handleSend 保草稿行号）。未扩面，零契约变更。

## 评审与回修入口

- 评审对象：`sdd.md`；关键审查点 = §4.3.1 双源活动性判定与生命周期闭合表（queued→dispatched→running→terminal）+ 硬降级确定性转移（成功空 ID → 原子清空；失败 → 保留旧目标）+ **失败回流可见动作**（保草稿 → 发送/重试按钮、清空草稿 → stop 重新出现，与 §4.2 `running` 判定式一致）、AC-5（a）~（h）与 §6.9 矩阵（成功路径 stop 断言带 isEmpty 前置；顺序分支断言不调用 `cancelTaskById(A)`）、§9 批准范围、既有实现依赖 21 条（SHA 117fc6be）
- BLOCK → 按 reviewLoop 回 `write-tech-design`（status 回 `tech-designing`，attempt 由 reviewer bump；当前 cycle 2 attempt 1/3，下次 BLOCK 即 2/3）
- PASS + blockers=[] → 停在人工审批节点（`crctl approve --stage tech-design`），审批指令由 coordinator 发布，本 Agent 不代签
- 工作区保持干净：`_context.md` 必须随 CR 提交（独立 context 提交），否则 review-tech-design 的 workspace inspect 会因 dirty 中止

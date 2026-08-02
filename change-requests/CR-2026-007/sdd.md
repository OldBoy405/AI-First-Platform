---
id: CR-2026-007-sdd
type: SDD
cr-ref: CR-2026-007
title: P2 三模式聊天 CR-B — D3 完整形态 技术设计
target-version: "0.14"
owner: Ray
owner-role: development
status: draft
created: "2026-08-02T11:05:00+08:00"
updated: "2026-08-02T11:05:00+08:00"
revision: "0.1.0"
---

# SDD — CR-2026-007：D3 完整形态（队列条 + 撤回 + 停止 + 过滤开关）

> 输入：PRD rev 0.1.1（FR-1~7 / NFR-1~5 / AC-1~6）+ 需求评审 6 条 SUG（全部在本设计闭合，
> 见各 DD 的 [SUG-xxx] 标注）。全部设计决策基于对 multica main（52b571774，含 CR-A 合并）
> 的实码调查，引用处给出 文件:行 证据。

## 1. 调查结论（设计前提，均已实码核实）

| # | 结论 | 证据 |
|---|---|---|
| I-1 | `CancelTaskByUser`（`POST /api/tasks/{taskId}/cancel`）**没有状态门槛**：权限=originator-or-owner/admin（403 `not_task_originator`），对 queued/dispatched/running 一律走 `CancelTaskWithResult`（软删+WS 广播+agent 对账） | handler/chat.go:1082-1176 |
| I-2 | 不可取消状态（已完成等）由 `CancelTaskWithResult` 返回错误 → handler 回 **400**（非 409） | handler/chat.go:1152-1156 |
| I-3 | 群聊任务的 `trigger_comment_id` 全链路存在：入队落库（service/task.go:750）、响应体回传（AgentTaskResponse）、前端 schema 已解析（core/api/schemas.ts:594） | 三处实码 |
| I-4 | `queue-status` **无轮询**：CR-A 用 WS `task:*` 事件失效重取（D1 触发列表：queued/cancelled/running/completed/failed），组件内注释明确"不做 interval" | project-team-agent-chat.tsx:207,352 |
| I-5 | 前端已有 `api.cancelTaskById(taskId)`（含 zod schema 与 fallback） | core/api/client.ts:1896 |
| I-6 | 消息流结构：comments+tasks 按 created_at 合流，task 渲染为 `TaskExecutionCard`（内含 `TimelineView` 过程条目），cancelled 状态已有 interrupted 徽标分支 | project-team-agent-chat.tsx:112,183,197,262 |
| I-7 | CR-A 输入区**没有**停止按钮；满队锁存/恢复由 queue-status 驱动 | 同上 grep 全文 |

## 2. 设计决策

### DD-1 停止入口不占用发送键 [SUG-001]

**决策**：发送键恒为发送；「停止」按钮放在两处——运行中任务卡（`TaskExecutionCard`）头部
与队列展开列表项。可见性=发起人本人或 workspace owner/admin（客户端镜像判断，服务端
I-1 权限为准）。

**偏离交互稿 §3.4 的论证**（PRD 要求偏离需论证）：「发送变停止」锚点源自 1:1 chat
单会话语义（同一时刻只有一个进行中回复）；共享队列下 PRD AC-1 明确要求自己任务运行中
仍可连发入队，两者互斥。取共享队列语义。字典 `chat.agentGenerating`（「Agent 回复中」）
保留，用作运行中任务卡的状态文案而非输入区替换。

### DD-2 撤回=停止=同一端点，UI 文案按状态区分 [SUG-002]

**决策**：全部走既有 `POST /api/tasks/{taskId}/cancel`，服务端**零改动**（I-1 已覆盖全部
状态与双权限）。dispatched 无操作空洞——它和 queued 一样可被 originator/owner 取消。
UI 区分语义：列表中 queued/dispatched 项按钮文案「清除对话」（撤回），running 项与
运行卡按钮文案「停止」。

**错误口径修正**（已同步 PRD 0.1.1 AC-2）：403=非发起人非 owner；**400**（非 409）=
不可取消状态（竞态：点撤回时任务恰已完成）。前端对两者统一结构化 toast 呈现服务端
message，不静默；列表本身经 WS 已刷新，无需前端回滚逻辑。

### DD-3 队列明细：`?include=items` 参数扩展 queue-status [SUG-005]

**决策**：`GET /api/projects/{id}/queue-status?include=items`。**opt-in**：不带参数时
响应与现状逐字节一致（AC-5 对拍基础）；带参时追加：

```json
{
  "queue_depth": 3, "queue_limit": 50,
  "items": [{
    "task_id": "…", "status": "queued", "priority": 100,
    "created_at": "…",
    "originator": { "id": "…", "name": "…", "avatar_url": "…" },
    "summary": "触发消息前 140 字符"
  }]
}
```

- 新 sqlc 查询 `ListProjectPendingTasks`：`agent_task_queue` JOIN issue（project 过滤）
  JOIN users（originator 显示信息）LEFT JOIN comment（trigger_comment_id → summary，
  服务端截断 140 字符）；`status IN ('queued','dispatched')`（与 D1 深度口径一致）；
  `ORDER BY priority DESC, created_at ASC`（与 claim SQL 同序，owner 插队项天然排前，
  满足 FR-2 顺序要求）。放 `project.sql`（与 CountProjectPendingTasks 同域）。
- 为什么不独立端点：明细与 depth/limit 永远同时消费（队列条一个组件），同一次 fetch
  免两次往返与两 key 一致性问题；I-4 证明无轮询放大风险（事件驱动 refetch，payload
  上限=limit≤50 项×轻字段）。SUG-005 担忧的高频轮询前提不成立，但 opt-in 参数仍保留
  ——右侧 sidebar 指示与 CR-A composer 恢复逻辑继续无参调用，零改动零膨胀。
- 前端：`projectKeys.queueItems(wsId, id)` 新 query key + `projectQueueItemsOptions`；
  WS 失效沿 D1 触发列表（I-4），在既有 task:* invalidation 处并列失效两个 key。
- 权限：与现端点一致（workspace 成员可读，交互稿"全员可见"）。
- sqlc 重生成注意 Windows CRLF 噪音：`git diff --ignore-all-space --numstat` 甄别，
  只保留真变更文件（CR-A 已踩过）。

### DD-4 过滤开关的可测谓词 [SUG-003]

**决策**：「只看 Agent 请求」开启时，渲染规则精确为：
1. comment 气泡（用户请求）**全部保留**；
2. `TaskExecutionCard` 切换为**摘要形态**：只渲染卡头（agent 名 + 状态徽标 + 耗时）
   与完成态的最终结果文本（`AgentTask.result` 非空时截断显示），**不渲染 `TimelineView`**；
3. 系统性条目（如「已撤回」角标）不受影响。

可测断言（AC-4 执行口径）：开启后 DOM 中无 TimelineView 条目节点、无网络请求发出；
关闭后与开启前渲染一致。纯 render 分支，不动缓存不动数据。
"最终结果"的数据判定=task.result 字段（完成任务的结果载体，schemas.ts:586），
不依赖对 transcript text 条目的启发式猜测——这就是可测谓词。

**持久化**：`project-chat-store`（CR-A 建的独立 store）新增
`agentRequestFilter: Record<projectId, boolean>`，走既有 `createWorkspaceAwareStorage`
persist，默认 false。刷新后保留（AC-4）。

### DD-5 「已撤回」标注与请求摘要共用 task↔comment 既有关联 [SUG-004]

**决策**：零新增写路径。I-3 证实关联链完整：
- **「已撤回」角标**（FR-3）：前端渲染 join——stream 中 `status='cancelled'` 的 task，
  其 `trigger_comment_id` 对应的 comment 气泡加角标。数据都在既有缓存里，纯前端。
- **items[].summary**（FR-6）：服务端同一关联 LEFT JOIN comment（DD-3）。
- 边界：非群聊来源任务（Issue 页 @提及）trigger_comment_id 也存在，summary 同样可取；
  quick-create 等无 trigger comment 的任务 summary 为空字符串，前端显示占位文案。

### DD-6 被停者对账：DD-1 消解主风险，剩余链路全既有 [SUG-006]

SUG-006 的核心担忧（被停者输入区卡在"停止"态）被 DD-1 **结构性消解**——输入区没有
停止态，永远可发。剩余对账链路逐环均为既有能力：
`CancelTaskWithResult` → `task:cancelled` WS 广播（D1 既有）→ use-realtime-sync 失效
→ ① 任务缓存刷新 status=cancelled → TaskExecutionCard interrupted 徽标（I-6 既有分支）；
② queue-status/queue-items 双 key refetch → 队列条计数与列表项消失。
AC-3 的"无幽灵状态"在**被停者浏览器**断言以上两点（双浏览器验收，不只对操作者成立）。

## 3. 改动清单

### 后端（multica server，全部读侧）

| 文件 | 改动 |
|---|---|
| `server/pkg/db/queries/project.sql` | 新查询 `ListProjectPendingTasks`（DD-3） |
| `server/internal/handler/project.go` | `GetProjectQueueStatus` 加 `include=items` 分支 + item 响应结构体（originator 显示信息组装） |
| sqlc 重生成 | 只保留真变更（CRLF 甄别） |

无迁移、无新端点、无新 WS 事件、无写路径改动（NFR-1 达成手段）。

### 前端（multica packages）

| 文件 | 改动 |
|---|---|
| `core/api/schemas.ts` / `client.ts` | QueueItems 响应 schema + `getProjectQueueStatus` 可选 include 参数（无参调用零变化） |
| `core/projects/queries.ts` | `projectQueueItemsOptions` + `projectKeys.queueItems` |
| `core/projects/mutations.ts` | `useCancelProjectQueueTask`（调 `api.cancelTaskById`，onSettled invalidate queueStatus/queueItems/timeline keys，onError 结构化 toast） |
| `core/realtime/use-realtime-sync.ts`（或 CR-A 的既有失效处） | task:* 失效清单并列 queueItems key |
| `core/projects/project-chat-store.ts` | `agentRequestFilter` map（DD-4） |
| `views/projects/components/project-queue-bar.tsx`（新） | 常驻条（count=0 收起）+ 展开列表 + 逐项「清除对话/停止」按钮 |
| `views/projects/components/project-team-agent-chat.tsx` | TaskExecutionCard 停止按钮（DD-1）+ 摘要形态分支（DD-4）+「已撤回」角标（DD-5）+ 气泡悬浮「复制」（clipboard，FR-7）+ 挂载 queue-bar 与过滤开关 |
| `views/locales/{en,ja,ko,zh-Hans}` | 队列条/清除对话/停止/已撤回/只看 Agent 请求/复制/占位摘要 等全部新 key ×4 |
| 测试 | views：queue-bar 渲染与 mutation 调用、过滤开关 DOM 断言（无 TimelineView 节点）、已撤回角标、复制；server：include 参数向后兼容对拍 + items 顺序/权限单测 |

## 4. 零回归对拍清单（NFR-1/3 验收手段）

1. `queue-status` 无参调用：改动前后同场景响应逐字节一致（handler 单测固化）。
2. D1 右侧 sidebar `ProjectQueueStatus`、CR-A composer 满队恢复：不改其调用，回归测试全绿。
3. `cancelTaskById` 既有消费方（1:1 chat 停止、任务详情页）：本 CR 只新增调用方，不改实现。
4. `useChatStore` 零触碰；`project-chat-store` 只增字段（persist 版本兼容：新字段缺省 {}）。
5. locale parity 测试全绿（新 key 四语齐上）。

## 5. 风险与对策

| 风险 | 等级 | 对策 |
|---|---|---|
| sqlc 重生成 CRLF 噪音污染 diff | 低 | CR-A 已验证的甄别流程（`--ignore-all-space --numstat`） |
| 撤回/停止竞态（点按钮时状态已变） | 低 | 服务端本就拒绝（I-2），前端 toast 原因 + WS 已刷新列表，无需补偿 |
| items JOIN comment 在长队列下的查询成本 | 低 | LIMIT=queue_limit（≤50 默认），索引走 issue.project_id 既有路径；不做缓存 |
| 过滤开关摘要形态漏渲染 running 态信息 | 低 | 摘要形态保留状态徽标+耗时（DD-4-2），running 用户仍能看到"在跑" |
| presenter（CR-E）后续改入队语义 | 无冲突 | 需求评审已确认：CR-E 只动入队侧，本 CR 的队列读侧 UI 与 cancel 路径不受影响 |

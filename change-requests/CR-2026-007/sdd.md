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
updated: "2026-08-02T12:10:00+08:00"
revision: "0.2.1"
---

# SDD — CR-2026-007：D3 完整形态（队列条 + 撤回 + 停止 + 过滤开关）

> 输入：PRD rev 0.1.3（FR-1~7 / NFR-1~5 / AC-1~6）+ 需求评审 6 条 SUG（DD 标注闭合）。
> rev 0.2.0：技术评审 attempt 0 = block，修复 3 条 blocker（cancel 幂等语义、私有 agent
> cancel 前置门槛、NULL originator 丢项）并吸收 TSUG-001/002/003/005/006（见 §6）。
> 全部设计决策基于对 multica main（52b571774，含 CR-A 合并）的实码调查。

## 1. 调查结论（设计前提；I-2/I-8/I-9 为技术评审修正/新增）

| # | 结论 | 证据 |
|---|---|---|
| I-1 | `CancelTaskByUser`（`POST /api/tasks/{taskId}/cancel`）无状态门槛：非 chat 分支先过 `canAccessPrivateAgent`，再做 originator-or-owner/admin 检查（403 `not_task_originator`），然后对任意状态调 `CancelTaskWithResult` | handler/chat.go:1082-1176 |
| I-2 | **（rev 0.2.0 修正）**不可取消状态是**幂等 200**不是 400：`CancelAgentTask` 的 WHERE 限定 `status IN ('queued','dispatched','running','waiting_local_directory','deferred')`（agent.sql:718），已完成任务命中 ErrNoRows 后回读原任务、err=nil，handler 返回 200 + 原状态任务体；400 仅在任务行不存在时出现 | service/task.go:1250-1257 |
| I-3 | 群聊任务 `trigger_comment_id` 全链路存在：入队落库（task.go:750）、响应体回传、前端 schema 解析（schemas.ts:594）；且 `agent_task_queue.trigger_summary` 列**已在入队时截断落库**（含跨 workspace 防泄漏 MUL-4252）并已回传前端（schemas.ts:600） | task.go:137-153,752 |
| I-4 | `queue-status` 无轮询：WS `task:*` 事件失效重取（use-realtime-sync.ts:541 的 queueStatusAll 前缀失效），组件注释明确"不做 interval" | project-team-agent-chat.tsx:207,352 |
| I-5 | 前端已有 `api.cancelTaskById(taskId)`（含 zod schema 与 fallback） | core/api/client.ts:1896 |
| I-6 | 消息流：comments+tasks 按 created_at 合流，task 渲染 `TaskExecutionCard`（内含 `TimelineView`），cancelled 已有 interrupted 徽标分支 | project-team-agent-chat.tsx:112,183,197,262 |
| I-7 | CR-A 输入区没有停止按钮；满队锁存/恢复由 queue-status 驱动 | 同上 |
| I-8 | **（新增）**`SendProjectChatMessage` 不做 agent 权限检查——成员可对 private/受限 `public_to` 的 Team Agent 成功发消息入队；但 I-1 的 `canAccessPrivateAgent` 前置会挡住同一成员撤回自己的任务（403 "no access to this agent"）——**发得进撤不回**的权限不对称 | project_chat.go:101-171 vs chat.go:1135 |
| I-9 | **（新增）**`originator_user_id` 对 autopilot/agent 来源任务刻意为 NULL（"deliberately unattributed"），这些任务照常占用项目队列（`CountProjectPendingTasks` 只按 issue.project_id + status 过滤，在 **agent.sql:1017-1026**，不排除任何来源）；`AgentTaskResponse` 目前不回传 originator 字段 | task.go:327, agent.sql:1017 |

## 2. 设计决策

### DD-1 停止入口不占用发送键 [SUG-001]

**决策**：发送键恒为发送；「停止」按钮放两处——运行中任务卡（`TaskExecutionCard`）头部
与队列展开列表项。可见性=发起人本人或 workspace owner/admin（客户端镜像，服务端 DD-2 为准）。

**偏离交互稿 §3.4 的论证**：「发送变停止」源自 1:1 chat 单会话语义；共享队列下 PRD AC-1
要求运行中仍可连发入队，两者互斥，取共享队列语义。`chat.agentGenerating` 字典保留用作
运行中任务卡状态文案。

**"是我发起的"前端判定 [TSUG-002]**：`AgentTaskResponse` 现无 originator 字段（I-9），
trigger_comment_id→timeline 作者映射在 coalesce 合并（MUL-4195 re-stamp）下有漂移边界，
不可靠。**决策：`taskToResponse` 增只读附加字段 `originator_user_id`（omitempty）**，
前端 schema 加 optional 字段——判定 = `task.originator_user_id === currentUserId`。
向后兼容（旧客户端忽略新字段），一处组装、两处消费（运行卡停止钮 + items 无需重复回传）。

### DD-2 撤回=停止=同一端点；幂等竞态语义 + 私有 agent 门槛小改 [SUG-002]

**端点**：全部走既有 `POST /api/tasks/{taskId}/cancel`。dispatched 无操作空洞（I-1 无状态
门槛）。UI 文案：queued/dispatched 项「清除对话」，running 项与运行卡「停止」。

**竞态语义（rev 0.2.0 修正，blocker 1）**：服务端对已完成任务是**幂等 200 + 原状态任务体**
（I-2），不拒绝。前端判定三分支 [TSUG-007]：① `status === 'cancelled'` → 成功（含重复
撤回已 cancelled 项的幂等 200——**静默成功不弹错**，双击撤回不误报）；② 其它终态
（completed/failed）→ toast「任务已结束，无法撤回」；③ 403 → toast 服务端 message。
已同步 PRD 0.1.3。无 409/400 竞态分支。mutation 测试覆盖三分支。

**私有 agent 权限不对称（blocker 2，服务端唯一写路径小改）**：I-8 证实"发得进撤不回"。
**决策：`CancelTaskByUser` 非 chat 分支调整检查顺序——`originator == caller` 时直接放行
（发起人对自己发起的任务天然知情，无泄漏面：响应体只含其本人任务），仅对非发起人保留
`canAccessPrivateAgent` + owner/admin 检查**。替代方案（send 路径收紧为禁止对私有 agent
发消息）被否：会让已配置私有 Team Agent 的项目群聊整体不可用，破坏 CR-A 已交付行为。
本改动配 handler 单测：private agent + 成员撤自己 → 200；撤他人 → 403（access gate 仍在）。

### DD-3 队列明细：`?include=items` 参数扩展 queue-status [SUG-005]

`GET /api/projects/{id}/queue-status?include=items`。**opt-in**：不带参响应逐字节不变
（AC-5 对拍）；带参追加 items[]：

```json
{
  "queue_depth": 3, "queue_limit": 50,
  "items": [{
    "task_id": "…", "status": "queued", "priority": 100,
    "created_at": "…",
    "originator": { "id": "…", "name": "…", "avatar_url": "…" },   // 可为 null（I-9）
    "summary": "trigger_summary 列原值"
  }]
}
```

- 新 sqlc 查询 `ListProjectPendingTasks` 放 **agent.sql**（与 CountProjectPendingTasks
  相邻，TSUG-005 修正位置）：`agent_task_queue` JOIN issue（project 过滤）**LEFT JOIN
  users**（blocker 3：INNER JOIN 会丢 I-9 的 NULL originator 任务，items 数与 depth
  不一致）；`status IN ('queued','dispatched')`（与 depth 口径完全一致，同一过滤复制）；
  `ORDER BY priority DESC, created_at ASC`（与 claim SQL 同序）。
- **summary 直接 SELECT 既有 `trigger_summary` 列 [TSUG-001]**——入队时已截断落库且已做
  跨 workspace 防泄漏（I-3），不 JOIN comment、不在 handler 二次截断。无 trigger 的任务
  该列为空 → 前端占位文案；originator 为 null → 前端占位「系统任务」（blocker 3 前端半边）。
- 为什么不独立端点：明细与 depth/limit 同组件同时消费，一次 fetch；I-4 证明无轮询放大
  （事件驱动 refetch，payload ≤ limit×轻字段）。opt-in 保证既有消费方零改动零膨胀。
- 前端 query key **挂在 queue-status 前缀下**：`projectKeys.queueStatus(wsId, id)` 延伸
  `[...queueStatus, "items"]`——白拿 use-realtime-sync.ts:541 的 `queueStatusAll` 前缀
  失效，**失效处零改动** [TSUG-006]。
- 权限：与现端点一致（workspace 成员可读）。
- sqlc 重生成 CRLF 甄别流程沿 CR-A（`git diff --ignore-all-space --numstat`）。

### DD-4 过滤开关的可测谓词 [SUG-003]

「只看 Agent 请求」开启时：
1. comment 气泡全部保留；
2. `TaskExecutionCard` 切摘要形态：卡头（agent 名 + 状态徽标 + 耗时）+ 完成态最终回复
   文本 = **`result.output`**（result 是 `{output, pr_url, tool_calls,…}` 整包 JSON，
   daemon.go:2470-2509；渲染整包会出 JSON 垃圾 [TSUG-003]）；`output` 为空串时占位
   「（无文本回复）」；**不渲染 `TimelineView`**；
3. 「已撤回」角标等系统性条目不受影响。

可测断言（AC-4）：开启后 DOM 无 TimelineView 条目节点、无网络请求；关闭还原。
持久化：`project-chat-store` 增 `agentRequestFilter: Record<projectId, boolean>`，
走既有 `createWorkspaceAwareStorage`，默认 false。

### DD-5 「已撤回」标注与请求摘要共用既有关联 [SUG-004]

零新增写路径（I-3 关联链完整）：
- 「已撤回」角标：前端渲染 join——stream 中 `status='cancelled'` 的 task 之
  `trigger_comment_id` 对应 comment 气泡加角标，数据全在既有缓存。
- items[].summary：`trigger_summary` 列直读（DD-3，TSUG-001 简化后不再 JOIN comment）。
- 边界：Issue 页 @提及任务 trigger 链同样成立；quick-create/autopilot 无 trigger 任务
  summary 空 + originator null，占位显示（blocker 3）。

### DD-6 被停者对账：DD-1 消解主风险，剩余链路全既有 [SUG-006]

输入区没有停止态可卡（DD-1），SUG-006 主风险结构性消解。剩余链路逐环既有：
`CancelTaskWithResult` → `task:cancelled` WS 广播 → use-realtime-sync 失效 →
① 任务缓存 status=cancelled → interrupted 徽标（I-6 既有分支）；② queueStatus 前缀
失效 → 队列条计数与列表项消失（DD-3 的 key 设计使其同前缀自动覆盖）。
AC-3 在**被停者浏览器**断言以上两点。

## 3. 改动清单

### 后端（multica server）

| 文件 | 改动 | 性质 |
|---|---|---|
| `server/pkg/db/queries/agent.sql` | 新查询 `ListProjectPendingTasks`（LEFT JOIN users，含 trigger_summary） | 读 |
| `server/internal/handler/project.go` | `GetProjectQueueStatus` 加 `include=items` 分支 + item 结构体（originator 可空） | 读 |
| `server/internal/handler/agent.go` | `AgentTaskResponse` 增 `originator_user_id`（omitempty）+ `taskToResponse` 组装 | 读（附加字段） |
| `server/internal/handler/chat.go` | `CancelTaskByUser` 非 chat 分支：originator==caller 先行放行，非发起人保留 access gate + owner/admin（DD-2，**唯一写路径改动**） | 权限小改 |
| sqlc 重生成 | CRLF 甄别只保留真变更 | — |

无迁移、无新端点、无新 WS 事件。

### 前端（multica packages）

| 文件 | 改动 |
|---|---|
| `core/api/schemas.ts` / `client.ts` | items 响应 schema、AgentTask 增 optional `originator_user_id`、`getProjectQueueStatus` 可选 include 参数（无参调用零变化） |
| `core/projects/queries.ts` | `projectQueueItemsOptions`，key = `[...queueStatus(wsId,id), "items"]`（DD-3） |
| `core/projects/mutations.ts` | `useCancelProjectQueueTask`：调 `api.cancelTaskById`；成功但 `status!=='cancelled'` → 幂等竞态 toast（DD-2）；403 → toast message；onSettled invalidate queueStatus 前缀 |
| `core/projects/project-chat-store.ts` | `agentRequestFilter` map（DD-4） |
| `views/projects/components/project-queue-bar.tsx`（新） | 常驻条（count=0 收起）+ 展开列表（占位：originator null→「系统任务」，summary 空→占位）+ 逐项「清除对话/停止」 |
| `views/projects/components/project-team-agent-chat.tsx` | 运行卡停止按钮（DD-1 判定用 originator_user_id）+ 摘要形态（DD-4，result.output）+「已撤回」角标（DD-5）+ 气泡悬浮「复制」（FR-7）+ 挂 queue-bar 与过滤开关 |
| `views/locales/{en,ja,ko,zh-Hans}` | 全部新 key ×4（队列条/清除对话/停止/已撤回/只看 Agent 请求/复制/系统任务占位/已结束无法撤回 等） |

### 测试面（TSUG-004 增补两项加粗）

- server：include 参数向后兼容对拍（无参逐字节一致）、items 顺序与口径=depth（**含
  NULL originator 任务计入 items**）、**cancel 已完成任务幂等 200 断言**、private agent
  下 originator 放行/非 originator 403 单测（DD-2）。
- views：queue-bar 渲染与 mutation（幂等竞态分支）、过滤开关 DOM 断言（无 TimelineView
  节点 + result.output 渲染）、已撤回角标、复制、originator null 占位。

## 4. 零回归对拍清单（NFR-1/3 验收手段）

1. `queue-status` 无参调用：改动前后同场景响应逐字节一致（handler 单测固化）。
2. D1 sidebar `ProjectQueueStatus`、CR-A composer 满队恢复：调用不改，回归全绿。
3. `cancelTaskById` 既有消费方（1:1 chat 停止、任务详情页）：DD-2 权限改动只**放宽**
   originator 自撤路径、不收紧任何既有放行路径——既有消费方行为不变（单测覆盖）。
4. `AgentTaskResponse` 新字段 omitempty，旧客户端/既有 schema fallback 不受影响。
5. `useChatStore` 零触碰；`project-chat-store` 只增字段（persist 缺省 {} 兼容）。
6. locale parity 全绿。

## 5. 风险与对策

| 风险 | 等级 | 对策 |
|---|---|---|
| DD-2 cancel 权限调序引入越权 | 低 | 只对 `originator==caller` 放行（该 ID 服务端落库不可伪造）；非发起人路径检查原样；单测双向覆盖 |
| sqlc CRLF 噪音 | 低 | CR-A 验证过的甄别流程 |
| items 口径与 depth 漂移 | 低 | 同一 status 过滤复制 + 单测断言 count==len(items)（含 NULL originator 造数） |
| 过滤摘要形态信息不足 | 低 | 保留状态徽标+耗时；output 空占位 |
| presenter（CR-E）改入队语义 | 无冲突 | 需求评审确认只动入队侧 |

## 6. 技术评审记录（attempt 0 → 修复映射）

| 评审发现 | 处置 |
|---|---|
| blocker 1：I-2 假断言（幂等 200 非 400） | I-2 重写；DD-2 竞态语义改为响应状态判定；PRD 0.1.2 同步 |
| blocker 2：私有 agent 撤回 403 不对称 | I-8 新增；DD-2 服务端小改（originator 先行放行）+ 单测 |
| blocker 3：INNER JOIN 丢 NULL originator | I-9 新增；DD-3 LEFT JOIN + 前端占位 + 口径单测 |
| TSUG-001 trigger_summary 列直读 | DD-3/DD-5 采纳，删 JOIN comment |
| TSUG-002 originator 前端判定缺口 | DD-1 采纳（响应体附加字段方案） |
| TSUG-003 result.output 谓词 | DD-4 采纳 |
| TSUG-004 两个测试面 | §3 测试面加粗两项 |
| TSUG-005 查询坐标 agent.sql | DD-3/§3 修正 |
| TSUG-006 queueStatus 前缀 key | DD-3 采纳，失效处零改动 |
| attempt 1 blocker：PRD 正文三处残留（FR-3 旧竞态口径+漏 dispatched、NFR-1/技术前提"零改动"与 DD-2 冲突） | PRD 0.1.3 三处同步 |
| TSUG-007 重复撤回幂等静默 | DD-2 三分支明确 + mutation 测试 |

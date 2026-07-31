---
id: CR-2026-004-sdd
type: SDD
cr-ref: CR-2026-004
title: P2 三模式聊天 D1 — Team Agent 共享队列容量上限 技术设计
status: draft
created: "2026-08-01T00:30:00+08:00"
updated: "2026-08-01T00:30:00+08:00"
---

# SDD — Team Agent 共享队列容量上限

> 设计原则：机制层（`agent_task_queue` 表 + claim SQL + WS 事件 + CancelTask 服务）全部既有，本 CR 只加业务逻辑层。全部代码事实已对照 multica fork 当前源码核实（文中标注文件路径）。

## 1. 架构概览

三个改动点，全部落在既有模块内，无新模块：

```
┌ 前端 packages/views（web+desktop 共享）─────────────────┐
│ 队列条：满 & 非 owner/admin → 输入区禁用 + 「Agent 忙」  │
│ 依赖既有 WS task:queued / task:cancelled 事件刷新队列数   │
└──────────────────────────────────────────────────────────┘
┌ server/internal/service/task.go（TaskService）───────────┐
│ ① 入队守卫：issue 挂钩的 Enqueue* 入口统一过容量检查      │
│ ② priority 覆盖：caller ∈ {owner,admin} → priority=100    │
│ ③ 撤回权限边界：包装既有 CancelTaskWithResult             │
└──────────────────────────────────────────────────────────┘
┌ 存储 ────────────────────────────────────────────────────┐
│ project.settings JSONB（新迁移，仿 workspace.settings）    │
│ 键 team_agent_queue_limit；agent_task_queue 零改动         │
└──────────────────────────────────────────────────────────┘
```

**入队链路选点**：Team Agent 任务即 issue 挂钩任务（`agent_task_queue.issue_id` → `issue.project_id`，034 迁移已有索引 `idx_issue_project`）。`TaskService` 的 issue 系入队函数（`EnqueueTaskForIssue` / `ForMention` / `ForThreadParent` / `ForSquadLeader*` / `EnqueueQuickCreateTask`，`service/task.go:651-1010`）在 INSERT 前统一调用新守卫 `guardProjectQueueCapacity`。`EnqueueChatTask`（Private Ask 沙箱，chat_session 挂钩）**不过守卫**——个人队列不设共享上限（PRD 范围）。`EnqueueDeferredAssigneeFallback`（系统 deferred 补偿）不过守卫——系统动作非用户入队。

## 2. 数据模型

**零改动**：`agent_task_queue`（`priority INT` 默认 0、`status` 含 `cancelled`、`originator_user_id` 均既有，001/022 等迁移）。

**新迁移 `1XX_project_settings.up.sql`**（编号取当时最新，当前最新 158）：

```sql
ALTER TABLE project ADD COLUMN settings JSONB NOT NULL DEFAULT '{}';
-- down: ALTER TABLE project DROP COLUMN settings;
```

仿 `workspace.settings`（001_init.up.sql:20）既有惯例。键约定：

| 键 | 类型 | 默认 | 语义 |
|---|---|---|---|
| `team_agent_queue_limit` | int | 缺省/非法值回退 50（代码常量 `DefaultTeamAgentQueueLimit`） | 项目共享队列容量上限 |

**新 sqlc 查询**（`server/pkg/db/queries/agent.sql`）：

```sql
-- name: CountProjectPendingTasks :one
-- Queue depth for a project's shared Team Agent queue. Counts queued +
-- dispatched (same "pending" semantics as HasPendingTaskForIssue);
-- running / waiting_local_directory / deferred / terminal states excluded.
SELECT count(*) FROM agent_task_queue atq
JOIN issue i ON i.id = atq.issue_id
WHERE i.project_id = $1 AND atq.status IN ('queued', 'dispatched');
```

**容量口径决策**（需求评审建议 1）：`queued + dispatched` 计入，`running` 排除。依据：既有 `HasPendingTaskForIssue`（agent.sql:736）就是这个"pending"口径；单写者语义下 running 恒 ≤1，排除后上限含义 = 纯排队深度，与设计稿「50 条排队」字面一致。

## 3. 接口契约

### 3.1 入队守卫（FR-1/FR-2，服务层内部函数）

```go
// service/task.go — called by every issue-linked Enqueue* before INSERT.
// callerID: the human user triggering the enqueue (originator); system
// paths (deferred fallback, autopilot) pass zero UUID and skip the guard.
func (s *TaskService) guardProjectQueueCapacity(
    ctx context.Context, issue db.Issue, callerID pgtype.UUID,
) (priorityOverride int32, err error)
```

行为：

1. `issue.ProjectID` 无效（任务不挂项目）→ 直接放行，无覆盖（守卫只治理项目共享队列）。
2. 查 caller 的 workspace `member.role`（001_init `member` 表，`owner/admin/member` 枚举——项目无独立角色表，owner/admin 判定即 workspace 角色，与 P2 设计稿「Owner+Admin 默认」一致）。
3. `role ∈ {owner, admin}` → 返回 `priorityOverride=100`，跳过容量检查（FR-2）。
4. 否则 `CountProjectPendingTasks` ≥ 上限 → 返回 `ErrProjectQueueFull{Depth, Limit}`（FR-1）。

**priority=100 决策**（需求评审建议 2）：既有档位为 0–4（`priorityToInt`：urgent=4/high=3/medium=2/low=1/默认 0，`service/task.go:2634`；chat 固定 2）。100 与既有档位有明确隔离带，claim SQL `ORDER BY priority DESC, created_at ASC`（agent.sql:384）天然实现插队，owner/admin 内部仍 FIFO。常量 `PreemptPriorityOwnerAdmin = 100`，注释标明 0–4 为普通档位、100 为治理插队档。

### 3.2 满队拒绝的 HTTP 契约（FR-1）

既有入队触达点（评论 @提及、issue 指派、快速创建）所在 handler 把 `ErrProjectQueueFull` 映射为：

```
HTTP 429 Too Many Requests
{ "code": "project_queue_full", "queue_depth": 50, "queue_limit": 50 }
```

### 3.3 撤回（FR-4，复用既有 CancelTask）

既有 `TaskService.CancelTaskWithResult`（service/task.go:1223）已实现软删（`status='cancelled'`，行保留，`CancelAgentTask` 查询 agent.sql:715）+ `task:cancelled` WS 广播 + agent 状态对账。**本 CR 只加权限边界**，在 handler 层：

```
DELETE /api/tasks/{id}/queue-entry   （或挂接既有 cancel 端点，实现期按既有路由风格定）
权限：caller == task.originator_user_id 且 task.status == 'queued'
      → 放行（成员撤自己的排队项）
      caller ∈ {owner, admin}
      → 放行（既有停止语义，任意状态，沿用现行为）
      其余 → 403 { "code": "not_task_originator" }
      task.status != 'queued'（成员路径）→ 409 { "code": "task_not_queued" }
```

撤回后 `CountProjectPendingTasks` 自然减一（`cancelled` 不在统计口径内），无需额外释放逻辑。

### 3.4 配置读写（FR-3）

- 读：入队守卫内读 `project.settings->>'team_agent_queue_limit'`，解析失败/缺失/≤0 一律回退 `DefaultTeamAgentQueueLimit=50`，**不阻塞入队链路**（PRD FR-3）。
- 写：既有 project 更新端点（handler/project.go）扩展接受 `settings` 局部合并；仅 workspace owner/admin 可改。

### 3.5 前端（FR-5）

`packages/views` 队列条组件（web + desktop 自动共享，mobile 不在范围）：

- 队列数来源：既有 WS `task:queued` / `task:cancelled` / `task:dispatch` 事件（protocol/events.go:33-41）驱动的 query 失效重取，附带 `queue_depth/queue_limit`。
- 满 & 非 owner/admin：输入区禁用 + 「Agent 忙，请稍后」提示；收到 429 `project_queue_full` 同样进入禁用态；深度降回上限以下自动恢复。

## 4. 关键流程（入队守卫伪代码）

```
Enqueue*(issue, caller):
  prio, err = guardProjectQueueCapacity(issue, caller)
  if err == ErrProjectQueueFull: return 429            # FR-1
  if prio > 0: params.Priority = prio                  # FR-2（覆盖原 priorityToInt 结果）
  INSERT INTO agent_task_queue (...)                   # 既有路径不动
  NotifyTaskEnqueued(...)                              # 既有 WS 广播不动
```

**弱一致界定**（PRD NFR-2）：count 与 INSERT 之间无锁，并发窗口可短暂超限 1~2 项。接受——上限是体验治理阈值非硬资源约束，不为它引入 advisory lock 或串行化。测试断言用 `≥ limit` 判满而非 `== limit`。

## 5. 技术选型与替代方案

| 决策 | 选择 | 放弃项与理由 |
|---|---|---|
| 上限存储（评审建议 3） | `project.settings` JSONB 新列 | 独立配置表：一个 int 不值一张表；workspace.settings：粒度不对（需求是 per-project） |
| 插队实现 | 固定 `priority=100` | 相对提升（max+1）：需先查队列最大值，多一次查询且并发下不稳定；改 claim SQL：违反"机制层不动"原则 |
| 容量统计 | 每次入队实时 count | 缓存计数器：要维护失效一致性，队列深度 ≤ 几十，JOIN count 走 `idx_issue_project` 足够快 |
| 撤回 | 复用 `CancelTaskWithResult` + handler 权限边界 | 新写 withdraw 服务：与既有 cancel 语义重复，且既有实现已处理 WS 广播/agent 对账/chat 清理等边角 |

## 6. FR → 技术实现映射

| FR | 实现 | 触点文件 |
|---|---|---|
| FR-1 容量校验 | `guardProjectQueueCapacity` + `CountProjectPendingTasks` + 429 映射 | service/task.go、queries/agent.sql、相关 handler |
| FR-2 插队豁免 | 守卫返回 `priorityOverride=100`，owner/admin 跳过容量检查 | service/task.go |
| FR-3 上限可配置 | `project.settings` 新列 + 键解析回退 50 + project 更新端点扩展 | 新迁移、handler/project.go |
| FR-4 撤回 | handler 权限边界（originator+queued / owner+admin）→ 既有 `CancelTaskWithResult` | 相关 handler、service/task.go（复用） |
| FR-5 实时可见 | 既有 WS task:* 事件 + 队列条禁用态组件 | packages/views |

## 7. 安全与性能考量

- **权限判定服务端做**：429/403/409 全部由后端裁决，前端禁用态只是体验优化——绕过前端直接调 API 得到相同拒绝（mobile 客户端自动被覆盖）。
- **审计**：撤回行完整保留（谁 `originator_user_id`、何时 `completed_at`、什么任务）；审计/日志不记录消息正文（沿用平台审计口径）。
- **性能**：count 查询走 `idx_issue_project` + `agent_task_queue` 状态过滤，队列深度数量级几十，无需新索引；实现期若 EXPLAIN 显示 atq 侧全表扫，补 `(issue_id, status)` 部分索引，作为实现期观察项而非前置承诺。
- **不影响既有路径**：chat（Private Ask）、autopilot、deferred 补偿均不过守卫，行为零变化；非 embedded 幂等、claim 竞争语义零触碰。
- **诚实边界**：P2 设计稿引用的「P0 §2.2 已加 cr_id+pipeline_node_run_id」尚未落库（158 迁移只建了 cr 投影表）——本 CR 不依赖这两列，容量治理经 `issue.project_id` 关联即可，无阻塞。

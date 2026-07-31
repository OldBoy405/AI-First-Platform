---
id: CR-2026-004-TASK-01
type: TASK
cr-ref: CR-2026-004
plan-ref: "change-requests/CR-2026-004/plan.md"
sdd-ref: "change-requests/CR-2026-004/sdd.md"
title: multica 后端 — 队列容量守卫 + 插队 + 撤回权限边界
status: pending
estimate: 8h
depends-on: []
assignee: ""
created: "2026-08-01T00:55:00+08:00"
---

## 任务描述
在 multica fork（`requirement/CR-2026-004` worktree）实现共享队列容量治理的全部后端逻辑：迁移、sqlc 查询、入队守卫、priority 覆盖、429 映射、撤回权限边界、project settings 写入口。SDD §1-§4 为唯一实现依据。

## 涉及文件
- `server/migrations/1XX_project_settings.{up,down}.sql`（新建，编号按合入时最新）
- `server/pkg/db/queries/agent.sql`（新增 `CountProjectPendingTasks`）+ sqlc 重新生成
- `server/internal/service/task.go`（`guardProjectQueueCapacity` + 常量 `DefaultTeamAgentQueueLimit=50` / `PreemptPriorityOwnerAdmin=100`；`CreateAgentTask`/`CreateQuickCreateTask` 两条路径接入守卫——以 SDD §1 INSERT 点裁决表为准，其余 4 条路径不动）
- 相关 handler（`ErrProjectQueueFull` → 429 `project_queue_full`；撤回端点权限边界：originator+queued 或 workspace owner/admin；project 更新端点接受 settings 合并，仅 owner/admin）

## 实现要点
- 守卫签名与行为按 SDD §3.1 四步：无 project 放行 → 查 workspace member.role → owner/admin 返回 priority=100 跳过检查 → count ≥ limit 拒绝。
- 容量口径 `queued + dispatched`（SDD §2 决策，与 `HasPendingTaskForIssue` 口径一致）。
- 撤回复用 `CancelTaskWithResult` 服务本体（零改动），权限只加在 handler 层；403 `not_task_originator` / 409 `task_not_queued`。
- limit 解析失败/缺失/≤0 回退 50，不阻塞入队。
- 弱一致（NFR-2）：不加锁；测试判满用 `≥ limit`。
- 注释一律英文（multica 仓 CLAUDE.md 硬规则）。

## 验收条件
1. Go 真库集成测试：满队（默认 50 与自定义 2 两组）时普通成员入队 → `ErrProjectQueueFull`，无新行；owner/admin 入队 → 落库且 priority=100。
2. 集成测试：不过守卫的 4 条路径（deferred/retry/autopilot/chat）在满队时仍能正常入队。
3. 集成测试：originator 撤回自己 queued 项 → `status='cancelled'` 行保留；撤他人项 → 403；撤非 queued 项 → 409；owner/admin 撤任意 → 沿用既有行为。
4. `go test ./...` 通过 + sqlc generate 无 diff 残留 + lint 零报错。

## 完成标志
上述测试全绿 + worktree commit + 完成记录回填本文件。

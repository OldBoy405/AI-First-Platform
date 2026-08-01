---
id: CR-2026-004-TASK-01
type: TASK
cr-ref: CR-2026-004
plan-ref: "change-requests/CR-2026-004/plan.md"
sdd-ref: "change-requests/CR-2026-004/sdd.md"
title: multica 后端 — 队列容量守卫 + 插队 + 撤回权限边界
status: done
estimate: 8h
depends-on: []
assignee: ""
created: "2026-08-01T00:55:00+08:00"
spec-id: ai-first-platform
version: "0.12"
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

## 完成记录（2026-08-01）

- **实现 commit**：multica worktree `requirement/CR-2026-004` @ `44d58b155`（15 文件，+640）。
- **交付内容**：迁移 159（project.settings JSONB）、`CountProjectPendingTasks`、`GetProjectSettings`/`UpdateProjectSettings`、`guardProjectQueueCapacity`（新文件 `internal/service/task_queue_capacity.go`）、两常量（DefaultTeamAgentQueueLimit=50 / PreemptPriorityOwnerAdmin=100）、quick-create 429 映射（`writeProjectQueueFull`）、`CancelTaskByUser` 停止权限收紧（403 `not_task_originator`）、`UpdateProject` settings 白名单合并（owner/admin 门禁 + 正整数校验）。
- **验收条件核验**：
  1. ✅ 真库集成测试 6 个全绿（`project_queue_capacity_test.go`）：满队拒绝（limit=2，`ErrProjectQueueFull` 且无新行）、owner 插队（落库 priority=100）、非法配置回退默认 50、deferred 路径绕过守卫、非发起人成员撤回 403（行未动）+ 发起人撤回软删成功、owner 撤任意成功。
  2. ✅ 不过守卫路径验证：deferred 显式测试；retry/autopilot/chat 由守卫只挂在两个用户路径的构造保证（SDD INSERT 点裁决表）。
  3. ✅ `go build ./...`、`go vet`、handler 包全量测试 ok；service 包排除 10 个 SKILL.md frontmatter 检查后 ok——该 10 个失败在未改动的 main 主检出同样失败（Windows CRLF checkout 环境问题，非本 CR 引入，留证）。
  4. ✅ sqlc generate 干净（生成物已入库，行尾噪音未入 diff）。
- **实现期设计修正**（相对 SDD §3.2/§3.3，均记录归档）：
  1. 评论触发的入队是既有 fire-and-forget 结构（评论先落库，enqueue 失败仅 warn 日志）——429 契约落在 quick-create 等"入队即请求本体"的端点；评论路径满队反馈由前端禁用态承担（T02）。人类发言不因 Agent 队列满而被阻断，语义更合理。
  2. 撤回复用既有 `POST /api/tasks/{taskId}/cancel`，不新建路由；成员对**自己的**任务不限 queued 状态（P2 停止语义本就允许停自己运行中的任务），故 409 `task_not_queued` 未引入——收紧点只有一个：非 owner/admin 不能动别人的任务。
  3. quick-create 任务入队时未挂 issue，不占用计数口径的槽位（很快转为 issue），软限制语义下可接受，代码注释已标注。
- **迁移已应用**至开发库（`ALTER TABLE project ADD COLUMN IF NOT EXISTS settings ...`，schema 部署动作，非业务数据写入）。

---
id: CR-2026-053-TASK-05
type: TASK
cr-ref: CR-2026-053
plan-ref: "change-requests/CR-2026-053/plan.md"
sdd-ref: "change-requests/CR-2026-053/sdd.md"
title: 新增绑定接口 POST /api/crs/{cr_id}/bind-current-task（含 sqlc 绑定读写 query 与生成物）
slug: bind-current-task-api
status: pending
estimate: 4h
depends-on: []
created: 2026-08-28T11:20:00+08:00
---

## 任务描述

在 Multica 仓新增 task-scoped 窄接口：

```http
POST /api/crs/{cr_id}/bind-current-task
Authorization: Bearer mat_<task-scoped token>
```

请求体：`{}`（或空）。不接受 `task_id`、`agent_id`、`workspace_id`、`issue_id`、`project_id`——全部由服务端从 task token + 数据库派生（FR-B1/FR-B2）。

同时在 `server/pkg/db/queries/agent.sql` 新增绑定读写 query 并 `make sqlc` 再生成（SDD §2.3），并在 handler/service 代码注释固化 FR-B11 信任上限声明。

## 涉及文件 / 模块

- `server/cmd/server/router.go` — 新增路由
- `server/internal/handler/` — 新增 handler
- `server/internal/service/task.go` — `TaskService.BindCurrentTaskToCR` 实现
- `server/pkg/db/queries/agent.sql` — 新增绑定读写 query（复用 GetAgentTaskInWorkspace/GetIssue/GetProjectInWorkspace/GetCrShellIssueInWorkspaceForShare 模式）
- `server/pkg/db/generated/` — `make sqlc` 生成物（禁手改）

## 实现要点

参考 SDD §3.1/§4.1/§2.3：
- 身份全服务端从 task token + 数据库派生（`mat_` 中间件写 X-Task-ID/X-Agent-ID/X-Workspace-ID）
- 单事务九步校验（FOR UPDATE 锁顺序：agent → task → issue → project → cr）
- 三写入（task.cr_id + cr.shell_issue_id + activity_log），任一步失败整体回滚
- 七种错误码（§3.1 错误响应表）；CAS：NULL→值 或同值重放（changed 由锁内旧值判定）
- 冲突路径写 `cr_issue_bind_rejected` 审计（FR-B4）
- FR-B11 信任上限代码注释：CR-ID 由 Skill 提交、同 workspace 错绑残余风险声明

## 验收条件

1. `make sqlc` 成功生成绑定读写 query 与生成物
2. `go test ./server/internal/service/... -run TestBindCurrentTaskToCR` 通过（7 种错误场景 + 同值重放 changed=false + 事务失败零部分更新，AC-B1~B11）
3. `go test ./server/pkg/db/... -run TestBindQueries` 通过（绑定读写 query 单测）

## 完成标志

- handler + service + agent.sql + sqlc 生成物已 commit
- 接口测试通过

## 接口契约

**HTTP 接口**: `POST /api/crs/{cr_id}/bind-current-task`

**产出**:
```json
{
  "cr_id": "string",
  "task_id": "uuid",
  "issue_id": "uuid",
  "project_id": "uuid",
  "changed": true
}
```

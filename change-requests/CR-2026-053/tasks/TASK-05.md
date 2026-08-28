---
id: CR-2026-053-TASK-05
type: TASK
cr-ref: CR-2026-053
plan-ref: "change-requests/CR-2026-053/plan.md"
sdd-ref: "change-requests/CR-2026-053/sdd.md"
title: 新增绑定接口 POST /api/crs/{cr_id}/bind-current-task
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

请求体：`{}`（或空）。不接受 `task_id`、`agent_id`、`workspace_id`、`issue_id`、`project_id`。

## 涉及文件 / 模块

- `server/cmd/server/router.go` — 新增路由
- `server/internal/handler/` — 新增 handler
- `server/internal/service/task.go` — `TaskService.BindCurrentTaskToCR` 实现

## 实现要点

参考 SDD §3.1 和 §4.1:
- 身份全服务端从 task token + 数据库派生
- 单事务九步校验（task → issue → project → cr 锁顺序）
- 三写入（task.cr_id + cr.shell_issue_id + activity_log）
- 七种错误码（§3.1 错误响应表）
- CAS 语义：NULL→值 或同值重放

## 验收条件

1. 接口路由注册成功
2. 七种错误场景返回正确错误码
3. 同值重放 `changed=false`，无重复审计
4. 事务失败时两字段零部分更新
5. AC-B1~AC-B11 覆盖测试通过

## 完成标志

- handler + service 实现已 commit
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
  "changed": true/false
}
```

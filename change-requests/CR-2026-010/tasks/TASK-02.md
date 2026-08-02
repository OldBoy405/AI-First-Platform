---
id: CR-2026-010-TASK-02
type: TASK
cr-ref: CR-2026-010
plan-ref: "change-requests/CR-2026-010/plan.md"
sdd-ref: "change-requests/CR-2026-010/sdd.md"
title: presenter 服务（grant 状态机 6 转移）+ 7 个 API 路由 + 成员移除联动
slug: presenter-grant-service
status: pending
estimate: 6h
depends-on: [CR-2026-010-TASK-01]
assignee: ""
created: "2026-08-02T13:57:20+08:00"
---

## 任务描述

在 multica 落地 SDD §4.2/§4.4：presenter grant 的六转移状态机（申请/批准/拒绝/转让/撤销/释放）
与对应 API。这是 T03（发送端点接入）、T04（通知）、T05（前端数据层）的共同前置。

## 涉及文件

- 新文件 `server/internal/service/project_presenter.go`：六个转移方法共用模板
  （advisory xact lock `'presenter|'||workspaceID||'|'||projectID` 沿 `project_chat.go:61-64`
  写法 → 读当前状态 → 转移合法性校验 → 写 grant 行 → 返回结果，activity 写入与 publish 归 T04
  但本任务需预留调用点/接口）：
  - `RequestPresenter(ctx, projectID, callerID)`：调用者非 owner/admin（400 `role_cannot_request`）；
    本人无 pending（唯一索引兜底 409 `request_already_pending`）→ INSERT `pending`。
  - `ApprovePresenter(ctx, projectID, approverID, targetUserID)`：approver 需 owner（403）；
    该 pending 存在（404 `no_pending_request`）；无 active（409 `presenter_already_active`）→
    该 pending 行原地翻转为 `active`（`granted_by=approverID`，`created_at` 保留为申请时间）。
  - `RejectPresenter(ctx, projectID, approverID, targetUserID)`：同 approve 权限校验；
    pending→`rejected`。
  - `TransferPresenter(ctx, projectID, callerID, targetUserID)`：caller 需是当前 active 本人
    （403 `not_presenter`）；target 需工作区成员（400 `target_not_member`）→ 事务内旧 active
    行→`transferred` + INSERT 新 active 行（`granted_by=callerID`）。
  - `RevokePresenter(ctx, projectID, approverID)`：approver 需 owner；active 存在（404
    `no_active_presenter`）→ active→`revoked`。
  - `ReleasePresenter(ctx, projectID, callerID)`：caller 需是当前 active 本人（403）→
    active→`released`。
  - `GetPresenterState(ctx, projectID, callerID)`：返回 `{presenter, pending_requests, my_request}`
    三段（TSUG-003 定案——`pending_requests` 仅 owner/admin 可见完整列表，`my_request` 任何角色
    可见本人的 pending 行或 null，避免非 owner 角色因 pending 列表被过滤而拿不到自己"申请中"态
    的数据源）。
- `server/internal/handler/project_presenter.go`（新文件）：7 个 handler，角色校验用
  `h.requireWorkspaceRole`（handler.go:644 族）/ `h.requireWorkspaceMember`；错误结构化 code
  （沿 `writeProjectQueueFull` 先例）。
- `server/cmd/server/router.go`：在 `r.Route("/{id}")`（:1079 一带，`RequireWorkspaceMember`
  组内，与 `queue-status`/`chat` 平级）加 7 条路由：
  ```
  GET  /api/projects/{id}/presenter
  POST /api/projects/{id}/presenter/request
  POST /api/projects/{id}/presenter/approve   {user_id}
  POST /api/projects/{id}/presenter/reject    {user_id}
  POST /api/projects/{id}/presenter/transfer  {user_id}
  POST /api/projects/{id}/presenter/revoke
  POST /api/projects/{id}/presenter/release
  ```
- `server/internal/handler/workspace.go`：成员移除路径（既有"至少一个 owner"校验一带，
  :630-640 附近）追加一次 `revoke-if-active + reject-all-pending`（actor=system 的单
  UPDATE），防止移出成员后 grant 悬挂指向不存在的成员。

## 实现要点

- 六转移严格按 SDD §4.2 的表格执行角色/前置状态校验，非法转移一律 403/404/409 结构化返回，
  不写库、不触发任何副作用（AC-4 服务端权威的直接验证对象）。
- `approve` 语义：不新增第 7 个状态，直接把 pending 行 UPDATE 为 active（`resolved_by`/
  `resolved_at` 留空——该行本身转为当前态；行的完整历史由 `created_at`(申请时间) +
  `status='active'` + `granted_by`(approver) 三字段表达，配合 T04 的 activity_log 记录
  `{from:null/prev_user, to:target}` 补足审计叙事）。
- 成员移除联动：查询该成员在该 workspace 名下所有 project 的 active/pending grant 行，
  批量置 `revoked`/`rejected`（`resolved_by` 记为一个约定的 system 标记，非 UUID 也可用
  NULL + 单独日志，SDD 未强制字段值，实现时任选一种自洽方案）。
- partial unique 索引冲突（并发 approve 撞车）时返回 409，不 panic；service 层捕获
  DB 唯一约束违例转换为业务错误码。

## 验收条件

1. 单测覆盖六转移的合法路径与非法路径矩阵（至少：正常申请→批准、正常申请→拒绝、转让、撤销、
   释放、非 owner 批准 403、非 presenter 转让 403、owner/admin 申请 400、重复申请 409、
   撤销不存在的 presenter 404）。
2. `GetPresenterState` 对三种角色（owner、pending 申请人、无关成员）分别验证响应体的
   `pending_requests`/`my_request` 字段可见性符合 TSUG-003 定案。
3. 成员移除联动单测：某成员持有 active grant 时被移出 workspace → grant 行状态变化可查。

## 完成标志

上述单测全绿；7 个路由 curl 冒烟通过（含错误路径）；`go vet`/`go build` 零报错。

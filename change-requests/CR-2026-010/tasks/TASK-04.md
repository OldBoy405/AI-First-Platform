---
id: CR-2026-010-TASK-04
type: TASK
cr-ref: CR-2026-010
plan-ref: "change-requests/CR-2026-010/plan.md"
sdd-ref: "change-requests/CR-2026-010/sdd.md"
title: 通知双通道（activity_log + notifyDirect + WS 事件）
slug: presenter-notifications
status: pending
estimate: 4h
depends-on: [CR-2026-010-TASK-02]
assignee: ""
created: "2026-08-02T13:57:20+08:00"
---

## 任务描述

在 multica 落地 SDD §4.5/DD-8/DD-9：六转移写 activity_log（消息流卡片可回放）+ 5 种定向 inbox
通知（申请/批准/拒绝/转让/撤销）+ 1 个 WS 事件（`project:presenter_changed`，头部实时更新）。

## 涉及文件

- `server/internal/service/project_presenter.go`（T02 已建）：六转移方法末尾各追加一次
  `queries.CreateActivity(...)`（挂容器 Issue，`server/internal/handler/squad.go:943-974`
  的 `RecordSquadLeaderEvaluation` 写法可直接照抄骨架）：
  action 常量 `presenter_requested`/`presenter_approved`/`presenter_rejected`/
  `presenter_transferred`/`presenter_revoked`/`presenter_released`；
  details 形状沿 `activity_listeners.go:110`（assignee_changed）：
  `{from_user_id?, to_user_id?, by_user_id}`。
- `server/pkg/protocol/events.go`：加 `EventProjectPresenterChanged = "project:presenter_changed"`。
- `server/internal/service/project_presenter.go`：六转移成功后 `h.publish`/`s.Bus.Publish`
  两次——① `EventActivityCreated`（沿 `squad.go:943` 的 handler 内直写+广播先例，供消息流
  实时渲染）；② `EventProjectPresenterChanged`（workspace 广播，payload
  `{project_id, presenter_user_id|null}`，供头部刷新）。
- `server/cmd/server/notification_listeners.go` 或 `project_presenter.go` 内联调用
  `notifyDirect(...)`（:366 既有函数）——**TSUG-002 定案：IssueID 传容器 Issue 会导致前端
  inbox 默认路由深链到被隐藏的 Issue 页，本任务需在 details 里带 `project_id`，前端路由分支
  归 T06**：
  | 转移 | 收件人 | inbox type |
  |---|---|---|
  | request | 全体 owner（遍历 `ListMembers` 过滤 role=owner，循环调用） | `presenter_requested` |
  | approve | 申请人 | `presenter_approved` |
  | reject | 申请人 | `presenter_rejected` |
  | transfer | 受让人 | `presenter_transferred` |
  | revoke | 原 presenter | `presenter_revoked` |
  | release | — 无定向对象，仅 activity 卡，不调 notifyDirect | — |
- `packages/core/types/inbox.ts`：`InboxItemType` 联合加 5 个成员
  （`presenter_requested/approved/rejected/transferred/revoked`）。**不加入**
  `notifTypeToGroup`（`notification_listeners.go:78-94`）——权限类通知不可静音，缺省即强制送达。
- `packages/views/inbox/components/inbox-detail-label.tsx`（及 `inbox-display.ts` 若需要）：
  5 个新 type 的展示文案分支。

## 实现要点

- activity 写入与 inbox 写入是两条独立副作用，任一失败不应回滚已成功的转移状态变更
  （grant 行状态是权威状态，通知是尽力而为——沿 `CreateComment` 现状"通知失败仅 slog.Warn"
  的既有容错哲学，不做强一致事务合并）。
- `EventActivityCreated` 的 payload 形状需与 `use-issue-timeline.ts:196-212` 现有的
  `activity:created` 前端 handler 兼容（直接复用其 `TimelineEntry` 转换逻辑，本任务
  只保证后端 payload 字段命名一致，不改前端——前端消费归 T06）。
- release 无 notifyDirect 是有意为之（无明确"通知对象"，全项目成员从消息流卡片得知即可），
  不要误加。

## 验收条件

1. 单测：六转移各自产生一条 activity_log 行（action/details 断言）；五转移（不含 release）
   各自产生一条 inbox_item 行（recipient/type/details.project_id 断言）；release 不产生
   inbox_item。
2. WS 事件断言：六转移各触发一次 `EventActivityCreated` + 一次 `EventProjectPresenterChanged`
   publish（可用 events.Bus 的测试替身验证调用次数与 payload）。
3. request 通知多 owner 场景：项目有 2 个 owner 时，申请产生 2 条 inbox_item（各自一条）。

## 完成标志

上述单测全绿；`go vet`/`go build` 零报错；locale 侧的 5 个 inbox type 展示文案人工核对
不报错（不要求本任务补四语，四语随 T06 统一提交）。

---
id: CR-2026-056-TASK-09
type: TASK
cr-ref: CR-2026-056
plan-ref: "change-requests/CR-2026-056/plan.md"
sdd-ref: "change-requests/CR-2026-056/sdd.md"
title: M4 附件草稿安全与 1h sweeper
slug: m4-draft-attachment-sweeper
status: pending
estimate: 8h
depends-on: [CR-2026-056-TASK-07]
created: 2026-08-30T20:45:00+08:00
---

## 任务描述

未绑定草稿附件的可见性收紧（上传者门）、上传省略 `issue_id`、发送事务内绑定草稿（替代今日事务外 `linkAttachmentsByIDs`）、1h TTL sweeper（行锁覆盖对象删除 + 条件删行，BLOCK-011）。对应 plan.md M4、SDD §4.9/§4.10。

输入条件：TASK-03 附件三个新查询已生成；TASK-07 发送事务已含 `BindUnboundDraftAttachments` 调用。

## 涉及文件 / 模块

- `server/internal/handler/file.go`（`loadAttachmentForRequest` / `loadAttachmentForDownload` 上传者门；`UploadFile` 容忍缺 `issue_id`；删除/重试绑定同一上传者门）
- `server/internal/service/project_chat.go` / 发送路径（移除事务外 `linkAttachmentsByIDs`，改走发送事务内 `BindUnboundDraftAttachments`）
- sweeper 新 service 函数（测试文件 `chat_draft_attachment_cleanup_test.go`），注入 `storage.Storage`
- `server/cmd/server/runtime_sweeper.go`（独立 1h ticker 挂 `runRuntimeSweeper` 旁路）

## 实现要点

1. **上传者门（§4.9，FR-15）**：五类绑定（`issue_id`/`comment_id`/`chat_session_id`/`chat_message_id`/`task_id`）全空的行，下载/GET/删除仅允许 `uploader_type=member` 且 `uploader_id=caller`，否则 404（不泄露存在性）；项目附件列表因 `issue_id` 为空本就不出现；草稿 id 不进团队 WebSocket。
2. **上传省略 `issue_id`**：`UploadFile` form 的 `issue_id` 可缺省；`TeamAgentComposer` 上传不再传 `issueId`（前端侧行为在 TASK-10，后端本 TASK 保证容忍）。
3. **发送事务内绑定**：发送路径改用事务内 `LockUnboundDraftAttachments` + `BindUnboundDraftAttachments`（TASK-07 已接入调用；本 TASK 移除事务外 `linkAttachmentsByIDs` 的草稿用途，并核对 `LinkAttachmentsToComment` 不误用于未绑定草稿）；0 行 → `409 attachment_already_bound`。
4. **sweeper（§4.10，AC-28）**：新 service 函数注入 `storage.Storage`（`*storage.S3Storage` / `*storage.LocalStorage` 均满足，用 `DeleteObject` 返回 error 以便重试）。独立 1h ticker（挂 `runRuntimeSweeper` 旁路或 `lastDraftSweep` 节流；禁止在 GET/PATCH/发送路径扫表）。流程：无锁选出候选（五类全空且 `created_at < now() - interval '168 hours'`，LIMIT 100）→ 每候选一事务：`SELECT ... FOR UPDATE SKIP LOCKED WHERE id AND workspace AND 五类全空 AND source_context_id IS NULL AND created_at < now()-168h` → miss 即 continue（发送已 Bind 或他人拿走）→ `Storage==nil` 或 url 空则 ROLLBACK 留待下轮 → 持行锁 `Storage.DeleteObject` → 失败 ROLLBACK 留待下轮 → 成功则 `DeleteUnboundDraftAttachment`（WHERE 再次要求五类全空）→ COMMIT。恰好 168h00s 本轮不删。**禁止**使用现有 `DeleteAttachment`（其只排除 `source_context_id`，绑定后仍会删行）。锁序：双方按 `attachment.id` 升序行锁；sweeper 不拿项目 advisory，与发送不成环。

## 验收条件

1. AC-14：无容器时上传（无 `issue_id`）；其他成员 GET/download 该草稿 → 404；项目列表不出现。
2. AC-28 年龄边界：167h59m 保留；168h00s 保留；168h01s 删对象 + 删行（`go test ./server/internal/service/ -count=1 -run ChatDraftAttachment`）。
3. 对象删除失败（fake Storage）：行保留，下一 tick 重试；`Storage=nil` 不删行。
4. 并发夹具：sweeper 选出候选后、删对象前，发送完成 Bind → sweeper 锁内重读 miss 或条件 DELETE 0 行，对象**不得**删除、已绑定行仍在（BLOCK-011）。
5. 代码检索：sweeper 路径无 `DeleteAttachment` 调用。

## 完成标志

`-run ChatDraftAttachment` 全绿 + 上传者门夹具绿并提交。

## 接口契约

- 消费：TASK-03 的 `LockUnboundDraftAttachments` / `BindUnboundDraftAttachments` / `DeleteUnboundDraftAttachment`；TASK-07 发送事务（绑定挂钩点、锁序 §4.14）；基线 `storage.Storage` 接口的 `DeleteObject`（`server/internal/storage/storage.go`）。
- 产出：sweeper service 入口（供 `cmd/server` 1h ticker 调用；注入 `storage.Storage`，nil 安全）与草稿上传/读取的 404 语义——供 TASK-10（前端上传省略 `issue_id`）与 TASK-11（AC-14/15/28 证据）消费。

---
id: CR-2026-056-TASK-06
type: TASK
cr-ref: CR-2026-056
plan-ref: "change-requests/CR-2026-056/plan.md"
sdd-ref: "change-requests/CR-2026-056/sdd.md"
title: M3 会话内核：GET Ensure / PATCH config / Bind
slug: m3-session-ensure-patch-bind
status: pending
estimate: 8h
depends-on: [CR-2026-056-TASK-05]
created: 2026-08-30T20:45:00+08:00
---

## 任务描述

Team Agent 会话内核：GET 只 Ensure session（不建 Issue，含升级收养）、PATCH `/chat/config`（CAS 栅栏 + 三态）、`BindProjectChatContainer`（幂等、接受外层 tx、session 作用域）。对应 plan.md M3 第 1–3 项、SDD §4.1/§4.2/§4.4/§4.7.1。

输入条件：TASK-03 查询与 TASK-05 Resolve/校验已就绪。

## 涉及文件 / 模块

- `server/internal/service/project_chat.go`（GET Ensure 重构、`BindProjectChatContainer` 抽出；`ensureContainerIssue` 的发送路径内部 Commit 移除在 TASK-07 完成）
- `server/internal/handler/project_chat.go`（GET 响应扩展、新增 PATCH config handler）
- `server/cmd/server/router.go`（注册 `PATCH /api/projects/{projectId}/chat/config`）

## 实现要点

1. **GET Ensure（§4.1）**：先拿项目级 advisory `project-chat-session|{workspace_id}|{project_id}`（权威键，§2.1 / BLOCK-016），锁内事务重读 `settings.team_agent_id`（禁止锁前快照）；未配置则不建 session（沿用现有引导语义）；`GetActiveProjectChatSession` miss 则 `InsertProjectChatSession`（`base_*` 写当时 Agent 默认、允许空串、`issue_id=NULL`、`status='active'`）；不调用 `EnsureProjectChatIssue`、不 INSERT 新 issue。响应（§3.1）：`{session_id, issue_id(可空), team_agent_id, model, thinking_level, model_source, thinking_level_source}`；`ResolveChatConfig` 只做展示，不做 §4.3 校验。
2. **升级收养（§2.1，执行点一）**：GET Ensure 插入该项目第一行 session 的同一事务，当 `CountProjectChatSessions==1` 且 `issue_id IS NULL` 且 `GetLegacyUnboundProjectChatIssue` 恰好 0/1 行时，`UPDATE issue SET origin_id=session.id WHERE id=legacy.id AND origin_id IS NULL AND origin_type='project_chat'` + `BindProjectChatSessionIssue` CAS。换绑后 COUNT≥2 禁止收养（AC-18 不回退）。
3. **PATCH `/chat/config`（§3.1/§4.7.1）**：owner/admin 强制（非则 `403 forbidden_chat_config`）；请求体三态用 `json.RawMessage` 按键存在性判定：省略=保持，JSON `null` 或空串=清除（`*_override` 写 SQL NULL），非空=设 override（空串不得存入 override 列）；流程：同项目 advisory → 重读 `team_agent_id` → `LockProjectChatSessionByID FOR UPDATE` → status/agent 不符即 `409 chat_session_closed_or_changed` → `ResolveChatConfig` + §4.3（经 TASK-05 `ChatCatalogPort`/`ValidateResolvedChatConfig`）→ `UPDATE ... WHERE id AND status='active' AND agent_id=$current`，`RowsAffected==0` → 409；响应形状同 GET。
4. **`BindProjectChatContainer`（§4.4）**：接受外层 tx（发送路径复用，TASK-07 消费）；调用方必须已持项目级 advisory；内部 `LockProjectChatSessionByID FOR UPDATE` → assert `status=active` 且 `agent_id==project.team_agent_id`（事务内重读，不符 409）→ `issue_id` 已设则直接返回该 Issue → `GetIssueByOrigin(workspace,'project_chat',session.id)` 命中则 CAS 回读返回 → 收养（执行点二：`COUNT==1` 且 `issue_id` NULL 时认领遗留行，堵 GET 提交后转投插入的分裂）→ 否则 `createContainerInOuterTx`（新容器 `origin_id=session.id`，ON CONFLICT origin 回读）+ `BindProjectChatSessionIssue` CAS。可选 session 键 `project-chat|{ws}|{session.id}` 只串行本 session，不替代项目级锁。
5. Team Agent 路径禁止按 project 调 `GetProjectChatIssue` / `EnsureProjectChatIssue`（§1.6）；timeline 只读当前 `session.issue_id`。

## 验收条件

1. 绿场打开面板：`issue_id=null`，无新 `project_chat` 行（AC-11）；未配置项目保持现有引导语义，配置类操作 `409 team_agent_not_configured`（AC-20）。
2. 升级夹具：`origin_id` NULL 遗留行存在时，第一行 session 的 GET 收养并返回已有 `issue_id`；「升级后未发送即换绑」时第二行 session 不得收养（§2.1 夹具）。
3. PATCH 三态：省略不改；`null`/空串清 override；非空设 override；空串永不落 override 列（AC-17）；无 Issue 亦可 PATCH（FR-9）。
4. 非 owner/admin PATCH → `403 forbidden_chat_config`（AC-6）；closed / agent 漂移 session → `409 chat_session_closed_or_changed`。
5. 并发两个 GET：部分唯一索引 + advisory 下最多一行 active。
6. `go test ./server/internal/handler/ -count=1` 本 TASK 夹具绿。

## 完成标志

上述夹具绿 + `go build` 绿，提交至 multica CR worktree。

## 接口契约

- 消费：TASK-03 的 `GetActiveProjectChatSession` / `LockProjectChatSessionByID` / `InsertProjectChatSession` / `PatchProjectChatSessionConfig` / `BindProjectChatSessionIssue` / `CloseActiveProjectChatSession`（本 TASK 只用前者之外的写路径）/ `GetLegacyUnboundProjectChatIssue` / `CountProjectChatSessions`、`GetIssueByOrigin`；TASK-05 的 `service.ResolveChatConfig`、`service.ValidateResolvedChatConfig(model, thinking, provider string, catalog agent.Catalog) error`、`service.ChatCatalogPort`；基线 `GetProjectChat` handler、advisory 封装。
- 产出：
  - `service.BindProjectChatContainer`（接受外层 tx 的幂等绑定，返回容器 Issue；签名以「调用方已持项目级 advisory + 传入 outerTx」语义为准，Go 形参形状实施期定）
  - GET `/api/projects/{projectId}/chat` 新响应形状（§3.1：可空 `issue_id` + source 字段）与 `PATCH /api/projects/{projectId}/chat/config` handler
  - 项目级 advisory 权威键 `project-chat-session|{workspace_id}|{project_id}` 的使用范式

  供 TASK-07（container/messages/merge-forward/换绑）、TASK-08（lockKeyPrefix 对齐）、TASK-10（前端 API 形状）消费。

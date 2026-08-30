---
id: CR-2026-056-TASK-13
type: TASK
cr-ref: CR-2026-056
plan-ref: "change-requests/CR-2026-056/plan.md"
sdd-ref: "change-requests/CR-2026-056/sdd.md"
title: M3 Private Ask 后端闭环：GET 扩展 / PATCH config / 发送回填+校验+快照
slug: m3-private-ask-backend-closure
status: pending
estimate: 6h
depends-on: [CR-2026-056-TASK-05]
created: 2026-08-30T21:11:00+08:00
---

## 任务描述

Private Ask（`chat_session`）后端闭环（BLOCK-001，attempt 2 追加 BLOCK-004~008）：GET 展示扩展（新建即写快照、响应带 `session_id`）、新 `PATCH /api/chat/sessions/{sessionId}/config`（`FOR UPDATE` 行锁 + 锁内序列）、发送路径回填 `base_*` + §4.3 校验 + `chat_config` 快照（`CreateChatTask` 参数接缝，限 project-bound）。对应 plan.md M3 第 9 项、SDD §2.2/§3.2/§4.6/§4.7.1。不经 `project_chat_session`，不引入新表。

输入条件：TASK-03 的 `PatchChatSessionConfig` / `BackfillChatSessionBaseIfNull` / `LockChatSessionInWorkspace` / 带 `workspace_id` 的 `GetProjectChatSessionForCreator` / 改造后 `CreateChatSession`（`base_*` 参数）/ 改造后 `CreateChatTask`（`context` 参数）已生成；TASK-05 的 `ResolveChatConfig` / `ValidateResolvedChatConfig` / `ChatCatalogPort` 已就绪；TASK-08 的 `context.chat_config` merge 语义/共享 helper 可消费（若 TASK-08 未落盘，merge 语义按其接口契约实现，符号归属不变）。

## 涉及文件 / 模块

- `server/internal/handler/project_chat.go`（`GetProjectPrivateChat`，基线 :156；新建分支基线 :205）
- `server/internal/handler/chat.go`（新 `PatchChatSessionConfig` handler；`SendChatMessage` 基线 :824；`ChatSessionResponse` 基线 :1951 只读参照，不改共享结构）
- `server/internal/service/task.go`（`SendDirectChatMessage` 基线 :2402：分支 + 回填 + `CreateChatTask` 参数快照挂钩点）
- `server/cmd/server/router.go`（注册 `PATCH /api/chat/sessions/{sessionId}/config`）

## 实现要点

1. **GET（§3.2，BLOCK-004 新建快照）**：`GetProjectPrivateChat` 改调 TASK-03 改造后的 `GetProjectChatSessionForCreator`（传入认证上下文 `workspace_id`，Hard Invariant 1）；get-or-create 新建走基线 `CreateChatSession`（project_chat.go:205 调用点），消费其新增 `BaseModel` / `BaseThinkingLevel` 参数，**在 INSERT 同一语句**写入当时 Team Agent 默认（先 `GetAgent` 载入已解析的 `team_agent_id` 行，取 `agent.Model` / `agent.ThinkingLevel`，允许空串）——禁止事后补写（事后 UPDATE 会破坏 INSERT 时快照契约并与并发读竞态）；唯一索引竞态的败者重选路径直接返回胜者行（快照值以胜者 INSERT 为准，基线模式不变）。响应在既有 `ChatSession` 形状上附加 `session_id`（= `session.ID`，同一 UUID）与 `model` / `thinking_level` / `model_source` / `thinking_level_source`（`ResolveChatConfig` 只做展示，不做 §4.3 校验）。历史行 `base_*` NULL 且无 override → `agent_default` 跟随展示、**不写库**（FR-11/AC-19）；GET 除 get-or-create 外不产生任何写。
2. **PATCH `/api/chat/sessions/{sessionId}/config`（§3.2/§4.7.1，BLOCK-008 行锁）**：新 handler，鉴权与加载约束不变（creator-only；`project_id IS NULL` 普通 1:1 `chat_session` 拒绝 `404 chat_session_not_found`；不得触及 `project_chat_session`）。全部写入在**同一 PostgreSQL 事务**内，序列固定为「锁查询 → 回填 → Resolve → Patch」：
   - `qtx.LockChatSessionInWorkspace(id, workspace_id)`（TASK-03 新查询：`WHERE id AND workspace_id FOR UPDATE`，行锁 + workspace 重读一步完成；禁无 workspace 的 `GetChatSession`）→ 0 行 `404 chat_session_not_found`（错误 workspace 同 0 行）；
   - 锁内行上检查：`session.CreatorID != caller` → `403 forbidden_chat_config`（AC-25）；`project_id IS NULL` → `404`；
   - `qtx.BackfillChatSessionBaseIfNull`（首写回填，仅 `base_*` NULL 时写当时 Agent 默认）；
   - `ResolveChatConfig` → §4.3 校验（经 `ChatCatalogPort` / `ValidateResolvedChatConfig`，失败 `400 invalid_model_or_thinking_level`）——在行锁下完成，与 §4.7.1 Team Agent PATCH「advisory → FOR UPDATE → Resolve → 写」同序（Private Ask 无换绑 CAS，行锁即栅栏）；锁内可能经历 cache miss 的 LiveLoad（30s 上限），与 Team Agent PATCH 同一已接受取舍；
   - `qtx.PatchChatSessionConfig` 写三态（`json.RawMessage` 按键存在性：省略=保持、`null`/空串=清除、非空=设 override；空串永不落 override 列）；
   - commit。**任一步失败 → 整体 rollback**：override 与回填均不落库、行锁随事务释放，无补偿写。
   - 响应：`ChatSession` + `session_id`（= `id`）+ 四个附加字段（与 GET 同形状）。
3. **发送（§4.6，BLOCK-005 接缝 + BLOCK-006 范围封闭）**：`SendChatMessage` → `SendDirectChatMessage`：
   - **范围分支（BLOCK-006）**：基线两函数同时服务 project Private Ask 与 `project_id IS NULL` 普通 `chat_session`。本 CR 全部新行为（事务前 Resolve + §4.3 校验、事务内回填、`chat_config` 快照）**仅当 `project_id IS NOT NULL` 时生效**；判定取**事务内锁后重读行** `currentSession.ProjectID.Valid`（权威；覆盖 `ClearChatSessionProjectByProject` 把 `project_id` 置 NULL 的窗口，此时按普通发送走）。普通 `chat_session` 保持字节级零变化：不回填、不校验、`CreateChatTask` 的 `context` 仍传 NULL、不引入任何新错误码。
   - **Private Ask 分支**：事务外先 `ResolveChatConfig`（历史行按 `agent_default` 解析）+ §4.3 校验，失败 `400`：不落消息、不回填、不入队（校验含 catalog I/O，必须在开事务前完成，与基线 `buildRuntimeMCPOverlay` / attribution 同一前置模式）。
   - **快照接缝（BLOCK-005）**：基线 `SendDirectChatMessage` 的 `runInTx` 内经 `qtx.CreateChatTask`（chat.sql:1071）建任务，基线 INSERT 不写 `context`。接缝 = TASK-03 改造的 `CreateChatTask` 新增 jsonb 参数 `sqlc.narg('context')`：Private Ask 分支在 `runInTx` 内的 `qtx.CreateChatTask` 实参传入按 TASK-08 merge 语义/共享 helper 构造的 `{"chat_config":{"model":...,"thinking_level":...}}`——保留既有 JSON 键、禁整对象覆盖；值 = Resolve 输出。实现与测试绑定在该实参点，禁止事务外补一条 UPDATE。普通分支该实参保持 NULL。
   - 同一 `qtx`：`qtx.BackfillChatSessionBaseIfNull`（首次发送回填，先于任务创建，失败不留痕）。
   - 并发事实：基线 `runInTx` 已持 `LockChatSessionForRuntimeBind` FOR UPDATE 行锁；与 PATCH 的 `LockChatSessionInWorkspace` 同行锁，PATCH∥发送天然串行（见验收 7）。
   - 不改变 Private Ask 附件绑定与错误码映射（`409`/`429`/`502` 基线语义保持）。
4. **调用方同步**：`GetProjectChatSessionForCreator` 其余调用方（`autopilot.go` 等）Params 传 `workspace_id` 已在 TASK-03 完成，本 TASK 核对无遗漏（缺参编译不过即为证据）。共享 `ChatSessionResponse` 与 `chatSessionToResponse` **不改**（加 `session_id` 只落在 Private Ask GET/PATCH 的响应组装，不波及全部 chat 列表/单取端点）。

## 验收条件

1. AC-3：两 creator 各有独立 session；A 的 override 不影响 B 的 GET/发送快照（跨 creator 隔离夹具）。
2. AC-19：历史行（`base_*` NULL）GET → `*_source=agent_default` 且不写库；首次 PATCH / 首次发送后 `base_*` 落库为当时 Agent 默认，其后 Agent 默认变更不影响该 session 的有效值。
3. AC-25：非创建者 PATCH → `403 forbidden_chat_config`；`project_id IS NULL` session PATCH → `404`；错误 `workspace_id` → 0 行（`404`）。
4. 三态夹具：省略不改；`null`/空串清 override；非空设 override；空串永不落 override 列（与 Team Agent PATCH 同语义）。
5. **新建快照夹具（BLOCK-004）**：新建 session 首次 GET → `model`/`thinking_level` 精确等于创建时刻 Team Agent 默认、`*_source=session_default`；行与 `base_*` 同 INSERT 落库（断言行创建后无后续 UPDATE，如审计触发器或事务内快照比对）；其后改 Agent 默认，该 session 的 `base_*` 不变。既有 `CreateChatSession` 调用方（`agent_builder.go` / `chat.go` / `mika_agent.go` / channel engine）行为回归：`base_*` 仍 NULL。
6. **发送快照接缝夹具（BLOCK-005）**：Private Ask 发送成功 → 任务行 `context.chat_config` 精确等于 Resolve 输出（override 优先）；校验失败（非法 model / Waitable 无 cache / Blocked）→ `400`、无消息、无回填、无任务行；merge 保留既有键的单测断言（给定含既有键的 context，merge 后原键与 `chat_config` 并存，既有键值不变）。
7. **普通聊天回归夹具（BLOCK-006）**：`project_id IS NULL` session 发送成功、语义与基线一致：`base_*` 仍 NULL、任务 `context` 无 `chat_config`（NULL）、注入 catalog 失败不影响该发送（不经过校验分支）；对该 session 的 PATCH → `404`。
8. **`session_id` 夹具（BLOCK-007）**：GET/PATCH 响应 `session_id` 为合法 UUID 且精确等于 `session.ID`（UUID 逐字符保留，不重写不截断）；响应同时含四附加字段。
9. **并发与回滚夹具（BLOCK-008）**：① PATCH∥发送同打一行历史行（`base_*` NULL）——行锁串行，两者先后提交后 `base_*` 为单一一致值、override 不丢、发送快照与事后 GET/DB 一致；② 并发两 PATCH 各设一字段——锁内重读后两 override 并存（无丢更新）；③ §4.3 校验失败 → `400` 且整体回滚（本次回填也不落库）、随后第二次 PATCH 立即可进（锁已释放）。
10. `cd server && go test ./internal/handler/ ./internal/service/ -count=1` 本 TASK 夹具绿；`cd server && go build ./...` 绿。

## 完成标志

上述夹具绿并提交至 multica CR worktree。

## 接口契约

- 消费：TASK-03 的 `PatchChatSessionConfig` / `BackfillChatSessionBaseIfNull` / `LockChatSessionInWorkspace` / 带 `workspace_id` 的 `GetProjectChatSessionForCreator` / 改造 `CreateChatSession`（`base_*` narg）/ 改造 `CreateChatTask`（`context` narg）；TASK-05 的 `service.ResolveChatConfig` / `service.ValidateResolvedChatConfig` / `service.ChatCatalogPort`；TASK-08 的 `context.chat_config` merge 语义（共享实现）；基线 `SendDirectChatMessage` 的 `runInTx` 事务与 `LockChatSessionForRuntimeBind` 行锁。
- 产出：
  - `PATCH /api/chat/sessions/{sessionId}/config` handler 与响应形状（`ChatSession` + `session_id` + 四附加字段）；
  - GET `/api/projects/{projectId}/private-chat` 新响应形状（同上，§3.2）；
  - 新建即写 `base_*` 的 get-or-create 路径（`CreateChatSession` 参数消费）；
  - `CreateChatTask` 实参点的 `chat_config` 快照接缝（仅 project-bound 分支）与普通聊天零变化回归——供 TASK-10（前端 Private Ask 可写 picker，消费 `session_id`）与 TASK-11（AC-3/19/25 与 BLOCK-004~008 证据）消费。

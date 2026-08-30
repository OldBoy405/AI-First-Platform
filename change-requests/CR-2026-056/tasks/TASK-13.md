---
id: CR-2026-056-TASK-13
type: TASK
cr-ref: CR-2026-056
plan-ref: "change-requests/CR-2026-056/plan.md"
sdd-ref: "change-requests/CR-2026-056/sdd.md"
title: M3 Private Ask 后端闭环：GET 扩展 / PATCH config / 发送回填+校验+快照
slug: m3-private-ask-backend-closure
status: pending
estimate: 4h
depends-on: [CR-2026-056-TASK-05]
created: 2026-08-30T21:11:00+08:00
---

## 任务描述

Private Ask（`chat_session`）后端闭环（BLOCK-001）：GET 展示扩展、新 `PATCH /api/chat/sessions/{sessionId}/config`、发送路径回填 `base_*` + §4.3 校验 + `chat_config` 快照。对应 plan.md M3 第 9 项、SDD §2.2/§3.2/§4.6。不经 `project_chat_session`，不引入新表。

输入条件：TASK-03 的 `PatchChatSessionConfig` / `BackfillChatSessionBaseIfNull` / 带 `workspace_id` 的 `GetProjectChatSessionForCreator` 已生成；TASK-05 的 `ResolveChatConfig` / `ValidateResolvedChatConfig` / `ChatCatalogPort` 已就绪。

## 涉及文件 / 模块

- `server/internal/handler/project_chat.go`（`GetProjectPrivateChat`，基线 :156）
- `server/internal/handler/chat.go`（新 `PatchChatSessionConfig` handler；`SendChatMessage` 基线 :824）
- `server/internal/service/task.go`（`SendDirectChatMessage` 基线 :2402：回填 + 快照挂钩点）
- `server/cmd/server/router.go`（注册 `PATCH /api/chat/sessions/{sessionId}/config`）

## 实现要点

1. **GET（§3.2）**：`GetProjectPrivateChat` 改调 TASK-03 改造后的 `GetProjectChatSessionForCreator`（传入认证上下文 `workspace_id`，Hard Invariant 1）；get-or-create 新建时写 `base_model` / `base_thinking_level`（当时 Agent 默认，允许空串）；响应在既有 `ChatSession` 上附加 `model` / `thinking_level` / `model_source` / `thinking_level_source`（`ResolveChatConfig` 只做展示，不做 §4.3 校验）。历史行 `base_*` NULL 且无 override → `agent_default` 跟随展示、**不写库**（FR-11/AC-19）。
2. **PATCH `/api/chat/sessions/{sessionId}/config`（§3.2，新 handler）**：
   - 鉴权 creator-only：`session.CreatorID != caller` → `403 forbidden_chat_config`（AC-25）。
   - 加载必须 `GetChatSessionInWorkspace`（禁无 workspace 的 `GetChatSession`）；`project_id IS NULL` 的普通 1:1 `chat_session` 拒绝（`404 chat_session_not_found`，本 CR 只对 Private Ask 生效）；不得触及 `project_chat_session`。
   - 请求体三态与 Team Agent PATCH 相同（`json.RawMessage` 按键存在性：省略=保持、`null`/空串=清除、非空=设 override；空串永不落 override 列）。
   - 首次写回填：同事务内 `BackfillChatSessionBaseIfNull`（仅 `base_*` NULL 时写当时 Agent 默认）→ `ResolveChatConfig` → §4.3 校验（经 `ChatCatalogPort` / `ValidateResolvedChatConfig`，失败 `400 invalid_model_or_thinking_level`，不落任何写）→ `PatchChatSessionConfig`。
   - 响应：`ChatSession` + 四个附加字段（同 GET 形状）。
3. **发送（§4.6）**：`SendChatMessage` → `SendDirectChatMessage`：
   - 事务外先 `ResolveChatConfig`（历史行按 `agent_default` 解析）+ §4.3 校验，失败 `400`：不落消息、不回填、不入队（校验含 catalog I/O，必须在开事务前完成，与基线 `buildRuntimeMCPOverlay` / attribution 同一前置模式）。
   - 既有 `runInTx` 事务内：`qtx.BackfillChatSessionBaseIfNull`（首次发送回填，与本次写同事务，失败不留痕）；任务创建处的 `context` JSONB merge `{"chat_config":{"model":...,"thinking_level":...}}`（TASK-08 定义的快照格式与 merge 语义：保留既有键、禁整对象覆盖；值 = Resolve 输出）。
   - 不改变 Private Ask 附件绑定与错误码映射（`409`/`429`/`502` 基线语义保持）。
4. **调用方同步**：`GetProjectChatSessionForCreator` 其余调用方（`autopilot.go` 等）Params 传 `workspace_id` 已在 TASK-03 完成，本 TASK 核对无遗漏（缺参编译不过即为证据）。

## 验收条件

1. AC-3：两 creator 各有独立 session；A 的 override 不影响 B 的 GET/发送快照（跨 creator 隔离夹具）。
2. AC-19：历史行（`base_*` NULL）GET → `*_source=agent_default` 且不写库；首次 PATCH / 首次发送后 `base_*` 落库为当时 Agent 默认，其后 Agent 默认变更不影响该 session 的有效值。
3. AC-25：非创建者 PATCH → `403 forbidden_chat_config`；`project_id IS NULL` session PATCH → `404`；错误 `workspace_id` → 0 行（`404`）。
4. 三态夹具：省略不改；`null`/空串清 override；非空设 override；空串永不落 override 列（与 Team Agent PATCH 同语义）。
5. 发送快照夹具：任务 `context.chat_config` 等于 Resolve 输出（override 优先）；校验失败（非法 model / Waitable 无 cache / Blocked）→ `400`、无消息、无回填、无任务行。
6. `cd server && go test ./internal/handler/ ./internal/service/ -count=1` 本 TASK 夹具绿；`cd server && go build ./...` 绿。

## 完成标志

上述夹具绿并提交至 multica CR worktree。

## 接口契约

- 消费：TASK-03 的 `PatchChatSessionConfig` / `BackfillChatSessionBaseIfNull` / 带 `workspace_id` 的 `GetProjectChatSessionForCreator`；TASK-05 的 `service.ResolveChatConfig` / `service.ValidateResolvedChatConfig` / `service.ChatCatalogPort`；基线 `GetChatSessionInWorkspace`、`SendDirectChatMessage` 的 `runInTx` 事务、TASK-08 定义的 `context.chat_config` 快照格式。
- 产出：
  - `PATCH /api/chat/sessions/{sessionId}/config` handler 与响应形状（`ChatSession` + 四附加字段）；
  - GET `/api/projects/{projectId}/private-chat` 新响应形状（§3.2）；
  - Private Ask 发送的 `chat_config` 快照证据——供 TASK-10（前端 Private Ask 可写 picker）与 TASK-11（AC-3/19/25 证据）消费。

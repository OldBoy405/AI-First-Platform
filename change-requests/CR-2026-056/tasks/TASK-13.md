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

Private Ask（`chat_session`）后端闭环（BLOCK-001，attempt 2 追加 BLOCK-004~008，cycle 2 追加 BLOCK-009/010）：GET 展示扩展（新建即写快照、响应带 `session_id`）、新 `PATCH /api/chat/sessions/{sessionId}/config`（`FOR UPDATE` 行锁 + 锁内序列）、发送路径回填 `base_*` + §4.3 校验 + `chat_config` 快照（`CreateChatTask` 参数接缝，限 project-bound）。对应 plan.md M3 第 9 项、SDD §2.2/§3.2/§4.6/§4.7.1。不经 `project_chat_session`，不引入新表。

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
3. **发送（§4.6，BLOCK-005 接缝 + BLOCK-006 范围封闭 + BLOCK-009 事务边界）**：`SendChatMessage` → `SendDirectChatMessage`：
   - **分支判定与快照绑定同一锁内行（BLOCK-009，权威算法）**：取消事务外 Resolve/校验预检。固定序列 = 基线既有 `runInTx`（task.go:2402 函数内）→ `LockChatSessionForRuntimeBind`（FOR UPDATE，事务首语句，chat.sql:390）→ `GetChatSession` 锁内重读 → **分支判定** → 分支内动作 → `CreateChatTask` → commit。分支判定、Resolve、§4.3 校验、回填与 `chat_config` 快照全部基于**锁后重读行 `currentSession`**（同一行、同一事务、同一份 Resolve 输出），任一步失败整体 rollback。本 TASK 只在该锁后插入分支与动作：不新增锁查询、不改变基线锁序（§4.14 锁序首条仍是该行锁）。
   - **范围分支（BLOCK-006）**：本 CR 全部新行为（回填、Resolve + §4.3 校验、快照）**仅当锁内行 `currentSession.ProjectID.Valid` 为真时生效**（权威判定；覆盖 `ClearChatSessionProjectByProject` 把 `project_id` 置 NULL 的窗口）。普通 `chat_session`（锁内行为 NULL）保持字节级零变化：不回填、不 Resolve、不校验、**完全不触 catalog I/O**、`CreateChatTask` 的 `context` 仍传 NULL、不引入任何新错误码——校验只可能在锁后且分支判定为 Private Ask 时执行，故「普通聊天被新 catalog 提前 400」无发生窗口。
   - **Private Ask 分支（锁内）**：`qtx.BackfillChatSessionBaseIfNull`（首次发送回填，先于任务创建）→ `ResolveChatConfig`（按锁内行 `base_*`/override 解析，历史行按 `agent_default`）→ §4.3 校验（`ValidateResolvedChatConfig`）→ 快照。校验失败 `400`：整体 rollback，不落消息、不回填、不入队。
   - **catalog I/O 与行锁取舍（BLOCK-009，显式声明）**：校验 catalog I/O 移入行锁内。代价与上限：`CacheLoad` 为 24h last-known-good cacheable（命中无网络 I/O）；cache miss 才 `LiveLoad`（30s 上限 = `modelListPendingTimeout`）；Waitable 无 cache fail-fast 不发起 I/O。最坏 = 该 session 行锁持至 30s，阻塞同一 session 的并发 PATCH/发送/rebind；行锁是单 session 行（FOR UPDATE 单行），爆炸半径限一个 session——与 PATCH §4.7.1「行锁内 LiveLoad 30s」同一已接受取舍。**否掉的替代方案（版本检查/重试）**：需要可靠行版本来源（`updated_at` 被 `ClearChatSessionProjectByProject` 有意跳过，不可作版本依据）与重试循环/耗尽错误语义，且事务外 catalog I/O 仍基于可能过期行——多一套机制换不来正确性；锁内 Resolve + 校验是单一权威点、无重试路径。
   - **快照接缝（BLOCK-005）**：基线 `SendDirectChatMessage` 的 `runInTx` 内经 `qtx.CreateChatTask`（chat.sql:1071）建任务，基线 INSERT 不写 `context`。接缝 = TASK-03 改造的 `CreateChatTask` 新增 jsonb 参数 `sqlc.narg('context')`：Private Ask 分支在 `runInTx` 内的 `qtx.CreateChatTask` 实参传入按 TASK-08 merge 语义/共享 helper 构造的 `{"chat_config":{"model":...,"thinking_level":...}}`——保留既有 JSON 键、禁整对象覆盖；值 = 锁内 Resolve 输出（与校验同一份，禁止二次解析）。实现与测试绑定在该实参点，禁止事务外补一条 UPDATE。普通分支该实参保持 NULL。
   - 并发事实：基线 `runInTx` 已持 `LockChatSessionForRuntimeBind` FOR UPDATE 行锁；与 PATCH 的 `LockChatSessionInWorkspace`（同行锁）、项目删除的 `ClearChatSessionProjectByProject`（chat.sql:18 普通 UPDATE，同行走锁）天然串行——PATCH∥发送、project clear∥发送均被同行锁栅栏（见验收 9/10）。
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
10. **事务边界与并发夹具（BLOCK-009/010，分支判定与快照绑定锁内行）**：
    - **project clear ∥ send（BLOCK-010，两顺序各自为可执行夹具，逐项断言，不得仅引用 BLOCK-008 的 PATCH 夹具代替）**：历史 Private Ask session（`base_*` NULL、无 override、`project_id` 非空）上并发项目删除的 `ClearChatSessionProjectByProject`（chat.sql:18，普通 UPDATE）与发送（`LockChatSessionForRuntimeBind` FOR UPDATE）——同行走锁，天然串行；顺序由测试控制（clear 以测试事务执行同款 UPDATE 并控制提交点；catalog 时序以 latch fake `ChatCatalogPort` 控制），每顺序按「成功 / 失败注入」两个子夹具断言：
      - **① clear 先提交（普通路径）**：send 锁后重读 `project_id` 已 NULL → 按普通聊天路径处理。**成功子夹具**：发送成功；事务后 DB 断言 `base_model`/`base_thinking_level` 单一一致值 = 仍 NULL（普通路径不回填）、任务行 `context` 为 NULL（无快照，与锁内普通分支判定一致）、消息行与任务行存在且 `task_id` 关联正确（发送结果与锁内行状态一致）。**失败注入 a（catalog 不应触发）**：强制 `CacheLoad` miss + `LiveLoad` 失败——发送仍成功、无 `invalid_model_or_thinking_level` 400（普通路径完全不触 catalog I/O）。**失败注入 b（任务创建 = 该路径入队点）**：删除 carrier runtime 行使 `CreateChatTask` 的 `lock_task_owner_rows`（migration 284）栅栏谓词为假 → INSERT 0 行 → 事务内错误 → 发送失败；事务后 DB 断言零残留：`base_*` 仍 NULL（无部分回填）、无任务行（无孤儿任务）、无消息行、`updated_at` 未变（`TouchChatSession` 已回滚）；随后重发（恢复 runtime 后）立即可进（行锁随回滚释放）。
      - **② send 先提交（project-bound 路径）**：锁内行 `project_id` 非空 → Private Ask 路径。**成功子夹具**：发送成功；`base_model`/`base_thinking_level` 单一一致值 = 回填恰一次的当时 Agent 默认（两列各一值，无第二处写入）；任务 `context.chat_config` 快照 = 锁内 Resolve 输出（无 override → 等于回填值，与校验共用同一份解析输出、禁止二次解析）；**快照与事后 GET/DB 一致**：事务后断言会话行 `base_*` == 任务快照 == clear 前 Private Ask GET 响应的 `model`/`thinking_level`（`*_source=session_default`）；随后 clear 提交把 `project_id` 置 NULL——再次 DB 断言已落库快照/回填/override 值均不可变。**失败注入 a（catalog，发生于回填之后）**：`CacheLoad` miss + `LiveLoad` 返回错误/超时 → `400 invalid_model_or_thinking_level` → 整体 rollback；事务后 DB 断言零残留：`base_*` 仍 NULL（无部分回填）、无任务行（无孤儿任务）、无消息行。**失败注入 b（任务创建，机制同 ①b）**：整体 rollback；零残留断言同上，且行锁随回滚释放、随后发送立即可进。
    - **PATCH ∥ send**：历史行（`base_*` NULL、无 override）上并发 PATCH（设 override，走 `LockChatSessionInWorkspace` FOR UPDATE）与发送（走 `LockChatSessionForRuntimeBind` FOR UPDATE，同行锁串行）。① PATCH 先提交：send 锁后重读行已含新 override → 快照 = override 优先解析输出——**断言不存在「锁前旧 override/base 解析值混入快照」**（Resolve 在锁内执行，无事务外预解析可陈旧）。② send 先提交：快照 = 当时 `agent_default` 解析值且回填先落库；PATCH 随后写的 override 不被覆盖（无丢更新）。两顺序均断言：`base_*` 单一一致值、override 完整、快照与事后 GET/DB 一致、任一失败整体回滚无残留。
11. `cd server && go test ./internal/handler/ ./internal/service/ -count=1` 本 TASK 夹具绿；`cd server && go build ./...` 绿。

## 完成标志

上述夹具绿并提交至 multica CR worktree。

## 接口契约

- 消费：TASK-03 的 `PatchChatSessionConfig` / `BackfillChatSessionBaseIfNull` / `LockChatSessionInWorkspace` / 带 `workspace_id` 的 `GetProjectChatSessionForCreator` / 改造 `CreateChatSession`（`base_*` narg）/ 改造 `CreateChatTask`（`context` narg）；TASK-05 的 `service.ResolveChatConfig` / `service.ValidateResolvedChatConfig` / `service.ChatCatalogPort`；TASK-08 的 `context.chat_config` merge 语义（共享实现）；基线 `SendDirectChatMessage` 的 `runInTx` 事务与 `LockChatSessionForRuntimeBind` 行锁（锁后重读行 = 分支判定与快照的权威行，发送路径无事务外 Resolve/校验，BLOCK-009）。
- 产出：
  - `PATCH /api/chat/sessions/{sessionId}/config` handler 与响应形状（`ChatSession` + `session_id` + 四附加字段）；
  - GET `/api/projects/{projectId}/private-chat` 新响应形状（同上，§3.2）；
  - 新建即写 `base_*` 的 get-or-create 路径（`CreateChatSession` 参数消费）；
  - `CreateChatTask` 实参点的 `chat_config` 快照接缝（仅 project-bound 分支）与普通聊天零变化回归——供 TASK-10（前端 Private Ask 可写 picker，消费 `session_id`）与 TASK-11（AC-3/19/25 与 BLOCK-004~010 证据）消费。

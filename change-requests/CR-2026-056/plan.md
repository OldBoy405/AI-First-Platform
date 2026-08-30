---
id: CR-2026-056-plan
type: PLAN
cr-ref: CR-2026-056
sdd-ref: "change-requests/CR-2026-056/sdd.md"
target-version: tbd
status: draft
created: 2026-08-30T20:19:35+08:00
updated: 2026-08-30T22:06:00+08:00
---

# 1. 交付里程碑

输入：已审批 PRD（21 FR / 6 US / 28 AC）与已审批 SDD（tech-design attempt 2/3 PASS）。全部实施改动落在 `multica` 仓；`tools` 仓零改动；knowledge-base 只承载本 CR 文档与账本。

| 里程碑 | 交付内容 | 预计工时 | 退出条件 |
|---|---|---:|---|
| M0 基线与实现准备 | 确认两资源 worktree health、multica HEAD = `8746add879cbd1c78e573c2a4a1776e16158c00c`（SDD §9）、最大迁移号 471、测试入口与 `make sqlc` 可用 | 0.5 人天 | 资源均 healthy；基线 SHA 与 SDD §9 一致；验证命令明确（Go 模块在 `server/go.mod`，所有 `go build`/`go test` 一律 `cd server && ...`） |
| M1 数据层 | 迁移 472–480（一文件一句、CONCURRENTLY、无 FK、down 配对）+ sqlc 新查询与改造查询（SDD §2.4 / §2.6；含 `CreateChatSession` / `CreateChatTask` 加参与 `LockChatSessionInWorkspace`，BLOCK-004/005/008） | 1.75 人天 | `make sqlc` 通过；编译绿；新查询与既有符号无命名冲突；改造查询基线调用方零行为回归 |
| M2 领域校验与目录适配 | `pkg/agent` 导出 `ModelIDForCapabilityLookup` / `StaticCatalog` / `ValidateChatConfig`；`chat_config.go`（Resolve + `ChatCatalogPort` + 薄包装）；handler 适配器（`CacheLoad`/`LiveLoad` 30s）与 `cmd/server` 接线 | 1.0 人天 | 四入口唯一校验入口成立；service 不 import handler；`pkg/agent` 单测含空模型哨兵与 codex fail-closed 矩阵 |
| M3 会话/容器/发送内核 | GET Ensure（不建 Issue + 收养）、PATCH config、POST container、messages（Bind-in-tx + `chat_config` merge）、merge-forward、换绑 close、转投兼容钉（`lockKeyPrefix` + `GetProjectChatIssue` ORDER BY）、daemon claim、presenter 活动解析、Private Ask 后端闭环（`GetProjectPrivateChat` 展示扩展 + 新建 INSERT 即写 `base_*` / `PATCH /api/chat/sessions/{sessionId}/config`（`FOR UPDATE` 行锁）/ `SendChatMessage`→`SendDirectChatMessage` 回填+校验+快照（`CreateChatTask` `context` 接缝，仅 project-bound）/ 响应含 `session_id`） | 3.25 人天 | §4.14 锁序全路径一致；AC-7/8/11/12/13/18/20/23 夹具通过；AC-3/19/25（Private Ask）与 BLOCK-004~008 夹具通过；`comment.go` / `RouteDiscussionToTeamAgent` 零 diff |
| M4 附件草稿安全与 sweeper | 上传者门、上传省略 `issue_id`、发送事务内 `BindUnboundDraftAttachments`、1h sweeper（行锁覆盖对象删除 + `DeleteUnboundDraftAttachment`） | 1.0 人天 | AC-14/15/28 夹具通过；`DeleteAttachment` 未被 sweeper 使用；sweeper∥Bind 竞态夹具通过 |
| M5 前端接入 | 独立 zod schema + `UNSAFE_CHAT_CONFIG_FALLBACK`、client 方法、Team Agent `persistModel`→PATCH、Private Ask 可写 picker 与 GET `session_id` 映射断言、四语文案 | 1.75 人天 | `schemas.test.ts`（AC-27，含 Private Ask `session_id` UUID 保留与硬降级）、`parity.test.ts`（AC-26）、组件测（AC-1/2/3/21）通过；无 `updateAgent` 调用 |
| M6 集成验证与证据 | 三组 `go test`、§4.14 夹具 1–3、前端测试全绿、`CUSTOM.md` 登记核对、`write-test-report` | 1.25 人天 | test-report pass；AC-1~AC-28 证据可追溯；KG-1/KG-2 未被当缺陷记录 |
| M7 评审与发布 | 独立 code review、人工 code approval、checkpoint、合并、writeback、archive | 1.0 人天 | code review blocker 清零；`crctl approve --stage code` 后合并归档 |

预计总工时：11.5 人天（13 个任务合计 92h，1 人天=8h）。M1→M2→M3 为主链；M4 依赖 M1（附件查询）与 M3（发送事务挂钩点）；M5 依赖 M3 的响应形状，可与 M4 并行；M6 依赖 M1–M5；M7 依赖 M6。

# 2. 任务依赖图

```text
M0 baseline inspect
  |
  +--> M1 迁移 + sqlc
         |
         +--> M2 pkg/agent + chat_config + catalog 适配
                |
                +--> M3 会话/容器/发送内核 --+--> M6 集成验证与证据 --> M7 评审与发布
                |          |                  |
                |          +--> M4 附件/sweeper ---+
                |                                 |
                +------------> M5 前端接入 ------+
```

实现资源（以 M0 `crctl workspace inspect` 返回为准，不得实施期重拼路径）：

- knowledge-base：`.rayai-worktrees/knowledge-base/requirement/CR-2026-056`，承载 `plan.md`、`tasks/`、测试报告与 CR 账本。
- multica：`.rayai-worktrees/multica/requirement/CR-2026-056`，承载全部代码、测试与 `CUSTOM.md`；基线 HEAD `8746add879cbd1c78e573c2a4a1776e16158c00c`。
- tools：本 CR 无 diff（PRD 范围排除，SDD §1.2）。

Go 验证命令统一约定（BLOCK-002）：multica 仓根目录**没有** `go.mod`，Go 模块在 `server/go.mod`（module `github.com/multica-ai/multica/server`）。所有 `go build` / `go test` 命令一律写为「`cd server && go ...`」，包路径以 `server/` 为根（如 `cd server && go build ./...`、`cd server && go test ./internal/handler/ ./pkg/agent/ ./internal/service/ -count=1`）。基线核验（TASK-01）与证据收集（TASK-11）消费同一组命令；`make sqlc` 在仓根执行。

若 workspace freshness 报告 HEAD 漂移、diverged 或资源异常，先按既有流程暂停并重新确认权威 worktree，不自动合并。

# 3. 任务分组与依赖

## 3.1 M1 数据层

1. 迁移 472–480 按 SDD §2.6 拆九组文件（一文件一句、无 REFERENCES、索引 `CONCURRENTLY`、down 按仓惯例配对）：建表、PK、两个部分唯一索引、历史索引、`chat_session` 四列、`DROP issue_project_chat_unique`、`issue_project_chat_session_origin_uidx`。
2. sqlc 新查询（SDD §2.4 建议名）：`GetActiveProjectChatSession` / `GetProjectChatSessionByID` / `LockProjectChatSessionByID` / `InsertProjectChatSession` / `PatchProjectChatSessionConfig` / `BindProjectChatSessionIssue` / `CloseActiveProjectChatSession` / `GetLegacyUnboundProjectChatIssue` / `CountProjectChatSessions`；Private Ask `PatchChatSessionConfig` / `BackfillChatSessionBaseIfNull` / `LockChatSessionInWorkspace`（`WHERE id AND workspace_id FOR UPDATE`，BLOCK-008）。
3. 改造既有查询：`GetProjectChatSessionForCreator` WHERE 加权威 `workspace_id`（同步改 `autopilot.go` 等调用方 Params，Hard Invariant 1）；`GetProjectChatIssue` 加 `ORDER BY created_at ASC, id ASC LIMIT 1`（BLOCK-017，仅转投继续调用）；附件 `LockUnboundDraftAttachments` / `BindUnboundDraftAttachments` / `DeleteUnboundDraftAttachment`（锁序与既有 `LockAttachmentsForIssueLink` 同为 attachment id 升序）；`CreateChatSession` INSERT 加 `base_model` / `base_thinking_level`（`sqlc.narg`，基线六处调用方零改动传 NULL，仅 Private Ask get-or-create 传当时 Agent 默认——INSERT 时原子快照，BLOCK-004）；`CreateChatTask` INSERT 加 `context` jsonb（`sqlc.narg`，基线调用方传 NULL，Private Ask 发送传合并快照——BLOCK-005 接缝）。
4. `make sqlc` 生成；生成物禁手改。

依赖：1 → 2、3 → 4。命名不得占用 `GetProjectChatSessionForCreator`。

## 3.2 M2 领域校验与目录适配

1. `pkg/agent`：导出 `ModelIDForCapabilityLookup`（未导出符号升格，调用点改调导出符号）、`StaticCatalog`、`ValidateChatConfig`（经 `StaticCatalog` 调 `ValidateThinkingLevelWith`，空 model 哨兵合法、codex 空模型+非空 thinking fail-closed）；`claudeContextWindowTagRe` 只留本包。
2. `service/chat_config.go`：`ResolveChatConfig`（override → base → agent_default → runtime_default，分别解析）+ `ChatCatalogPort` 接口 + `ValidateResolvedChatConfig` 薄包装（只转发 `agent.ValidateChatConfig`，不复制归一化）。
3. handler 侧实现 `ChatCatalogPort`：`CacheLoad`（24h last-known-good cacheable，禁 fallback）、`LiveLoad`（同步一轮、30s 上限、复用 `modelListPendingTimeout` pending-work；HTTP `InitiateListModels` 对 picker 仍异步）；`cmd/server` composition root 注入。
4. 测试：`pkg/agent` 校验矩阵（含 §4.2.1 空模型组合 × provider）与 LiveLoad 错误语义表（超时 / Fail / empty / fallback / Waitable 无 cache）。

依赖：1 → 2 → 3；4 随 1–3 落盘。四入口（PATCH / messages / container / merge-forward）只调 `ValidateResolvedChatConfig`；转投不走（SDD §4.13）。

## 3.3 M3 会话/容器/发送内核

1. GET：advisory `project-chat-session|{ws}|{project}` 内重读 `team_agent_id` → get-or-create session（写 `base_*`）→ `COUNT==1` 且 `issue_id` NULL 时收养遗留 `origin_id IS NULL` 行；禁止 `EnsureProjectChatIssue` / 新建 Issue；响应可空 `issue_id` + source。
2. PATCH `/chat/config`（owner/admin）：advisory → session `FOR UPDATE` → active+agent_id CAS（0 行 → 409 `chat_session_closed_or_changed`）→ Resolve + §4.3 → 只写 override（`json.RawMessage` 三态：省略/清除/设值）。
3. `BindProjectChatContainer`：接受外层 tx；`GetIssueByOrigin` / 已锁 session `issue_id` 解析；收养与新建均 `origin_id=session.id`；可选 session 键 `project-chat|{ws}|{session.id}` 只串行本 session。
4. POST container（presenter 权限，先校验后 Bind，失败不建 Issue）与 messages（必带 `session_id`；同一事务 Bind + comment + enqueue + merge `chat_config` + `BindUnboundDraftAttachments`；成功 201 带回四元组）。
5. merge-forward：Ensure active session → Resolve → §4.3 → 复用发送事务；成功体加 `session_id`/`issue_id`。
6. 换绑：`handler/project.go` 在**同一**项目 advisory 下提交 `team_agent_id` 更新 + `CloseActiveProjectChatSession`，不建新 Issue。
7. 转投兼容钉（唯一允许的转投侧改动）：`EnsureProjectChatIssue` 传入 `lockKeyPrefix` `"project-chat"` → `"project-chat-session"`；`comment.go` / `RouteDiscussionToTeamAgent` 零改动。
8. 任务与执行：`task.go` 入队 merge `context.chat_config`（保留 `head_sha` 等，禁整对象覆盖）；`daemon.go` claim 有快照用快照、缺则回退 agent 列，重试不重读；`project_presenter.go` 改读 active session `issue_id`（未绑定跳过）。
9. Private Ask 后端闭环（BLOCK-001 + BLOCK-004~008，SDD §2.2/§3.2/§4.6/§4.7.1）：`GetProjectPrivateChat` 带 `workspace_id` 查询，get-or-create 新建经改造后 `CreateChatSession` **INSERT 同一语句**写 `base_model`/`base_thinking_level`（当时 Team Agent 默认；禁止事后补写，BLOCK-004）；GET/PATCH 响应 = `ChatSession` + **`session_id`**（= `id`，UUID 逐字符保留）+ `model`/`thinking_level`/`*_source`（只 Resolve 展示，不校验，BLOCK-007）；新 `PATCH /api/chat/sessions/{sessionId}/config` 单事务固定序列「`LockChatSessionInWorkspace`（FOR UPDATE 锁 + 重读）→ 403/404 判定 → `BackfillChatSessionBaseIfNull` → Resolve + §4.3 → `PatchChatSessionConfig`」，失败整体回滚（creator-only、拒 `project_id IS NULL`、三态，BLOCK-008）；`SendChatMessage`→`SendDirectChatMessage` **仅 project-bound 分支**（判定取事务内锁后重读行 `project_id IS NOT NULL`；普通 `chat_session` 零变化回归）：事务前 Resolve + §4.3 校验，既有 `runInTx` 内回填 + 经改造后 `CreateChatTask` 的 `context` 参数实参点写入 `chat_config` 合并快照（TASK-08 共享 merge 语义，保留既有 JSON 键，绑定测试，BLOCK-005/006）。不经 `project_chat_session`。

依赖：1 → 2/3 → 4/5 → 6；7 与 1 共用锁协议；8 依赖 4；9 依赖 M2（Resolve/校验/`ChatCatalogPort`）与 M1 的 Private Ask sqlc 符号，与 1–8 并行，须在 M6 证据前完成。锁序固定为 SDD §4.14 表，禁止颠倒。

## 3.4 M4 附件草稿安全与 sweeper

1. `file.go`：未绑定行（五类全空）下载/GET/删除仅 `uploader_type=member` 且 `uploader_id=caller`，否则 404；草稿 id 不进团队 WS；`TeamAgentComposer` 上传省略 `issue_id`。
2. 发送事务内绑定草稿（替代今日事务外 `linkAttachmentsByIDs`）。
3. sweeper：独立 1h ticker（挂 `runRuntimeSweeper` 旁路，不在请求路径扫表）；注入 `storage.Storage`；`FOR UPDATE SKIP LOCKED` 行锁覆盖 `DeleteObject` + `DeleteUnboundDraftAttachment`；谓词五类全空且 `created_at < now()-168h`（恰好 168h00s 不删）；`Storage=nil` 或删对象失败则 ROLLBACK 留待下轮。
4. 测试：年龄边界（AC-28）、对象失败留行、`Storage=nil` 不删行、sweeper∥Bind 竞态（Bind 抢先则对象与行都不得删）。

依赖：1、2 依赖 M3 发送事务；3 独立文件 `chat_draft_attachment_cleanup_test.go`。禁止 sweeper 使用 `DeleteAttachment`。

## 3.5 M5 前端接入

1. `packages/core`：独立 zod schema（不给 `session_id` 加 `default("")`）+ `UNSAFE_CHAT_CONFIG_FALLBACK` + `parseWithFallback` 硬/软降级；新增 client 方法（GET/PATCH/container/messages 扩展）。
2. `project-team-agent-chat.tsx`：`persistModel` 删除 `api.updateAgent` 改 PATCH session config；接入 `ThinkingPicker`；非 owner/admin 只读；无 `issue_id` 时 composer 可用、上传省略 `issue_id`、timeline 空态；硬降级禁用写操作。
3. `project-private-ask.tsx`：只读徽章改可写 Model/Thinking，走 `PATCH /api/chat/sessions/{id}/config`；不写 Team Agent session；GET 响应经新独立 schema 解析，`session_id`（= `id`）为 PATCH/发送凭据（BLOCK-007 命名映射：UUID 保留断言 + 缺/非法硬降级断言落 `schemas.test.ts`）。
4. 文案四语 + `parity.test.ts`；`schemas.test.ts` 硬/软降级夹具；复用 `ChatInputCore` / draft adapter / `useFileUpload`，不重做视觉。

依赖：1 → 2、3；4 并行。API 形状以 M3 为准；M5 与 M4 可并行。

## 3.6 M6 集成验证与证据

1. `cd server && go test ./internal/handler/ ./pkg/agent/ ./internal/service/ -count=1` 与 `cd server && go test ./internal/service/ -count=1 -run ChatDraftAttachment`；前端 `schemas.test.ts`、locales parity、team-agent / private-ask 组件测。
2. 必过夹具：§4.14 夹具 1–3（GET∥转投、转投后首次 Bind、同 `created_at` 双行 `:one` 固定较小 `id`）、升级收养与「升级后未发送即换绑」、换绑双容器、首次发送失败回滚（五类零残留）、LiveLoad 超时、跨 workspace 0 行、Private Ask 回填/三态/403/发送快照（AC-3/19/25）、Private Ask 新建快照首次 GET（`session_default` 精确值，BLOCK-004）、`CreateChatTask` 接缝快照与键保留单测（BLOCK-005）、普通 `chat_session` 发送零变化回归（BLOCK-006）、`session_id` UUID 保留与硬降级（BLOCK-007）、PATCH `FOR UPDATE` 并发（∥发送 / ∥PATCH）与失败回滚（BLOCK-008）。
3. 按当时实际结构登记 `CUSTOM.md`（编号顺延 #58 之后，`// AIFIRST:` 挂钩点全覆盖）。
4. `write-test-report` 生成证据；失败按 reviewLoop 回 `implement-code` 自修复，不手改测试账本。

依赖：M1–M5 全部完成。KG-1/KG-2 是已知缺口（归 CR-B/CR-C），验收不得当本 CR 缺陷。

# 4. 资源与分工

| 角色 | 工作内容 | 预计工时 |
|---|---|---:|
| CR 协调（cr-coordinator-agent） | M0 基线确认、路径消费、状态推进与门禁 | 0.5 人天 |
| 后端实现（dev-agent / owners.development=Ray） | M1–M4：迁移、sqlc、校验内核、会话/容器/发送、附件与 sweeper、Private Ask 后端闭环（含 BLOCK-004~008 契约） | 7.0 人天 |
| 前端实现（dev-agent） | M5：schema/client/组件/文案（含 Private Ask `session_id` 映射断言） | 1.75 人天 |
| 测试与证据（owners.test=Ray） | M6：全量测试、夹具核对、CUSTOM.md 核对、test-report | 1.25 人天 |
| 独立 reviewer + 人工审批（quality-reviewer-agent / Ray） | M7：code review、`crctl approve --stage code`、合并、writeback、archive | 1.0 人天 |
| 合计 |  | 11.5 人天 |

执行以各资源 worktree owner 与既有 Pipeline 为准；本计划不新增服务账号或基础设施职责。multica 仓代码注释一律英文（其 CLAUDE.md 硬规则）；本仓文档用中文。

# 5. 风险与回滚策略

| 风险 | 预防与检测 | 回滚策略 |
|---|---|---|
| 迁移 479 DROP `issue_project_chat_unique` 后同项目多行 `project_chat` 使旧 `:one` 查询炸 | 480 部分唯一索引先行兜底；`GetProjectChatIssue` 加稳定双键排序（BLOCK-017）+ 夹具 3 | 按 down 文件逆序回滚 479/480；回滚前确认无 `origin_id` 非空新容器依赖 |
| 锁协议变更影响转投 | 唯一内部改动是 `lockKeyPrefix`；GET/Bind/Ensure 共用同一把项目 advisory；§4.14 夹具 1–2 | 恢复 `"project-chat"` 键一行改动；转投行为即回到今日 |
| 发送事务扩大导致锁等待/死锁 | 固定锁序（advisory → session 行 → Issue → 附件 id 升序）；并发夹具 | 回退到今日事务外 `linkAttachmentsByIDs`（单独提交），其余内核保留 |
| Available cache miss 同步 LiveLoad 阻塞最长 30s | 仅 cache miss 才走；Waitable 禁 LiveLoad；30s 上限即 `modelListPendingTimeout` | 无需回滚：超时返回 400 不产生副作用（不写 override、不建 Issue、不入队） |
| 旧桌面客户端把 GET `issue_id` 当必填 | 独立 schema 硬降级只读 + 重试 GET；`schemas.test.ts` | 降级逻辑为只读安全态，无需回滚；必要时回退前端 commit |
| sweeper 误删已绑定草稿或对象泄漏 | 行锁覆盖对象删除 + 条件删行；竞态夹具；禁用 `DeleteAttachment` | 停 1h ticker（单点开关），行数据不受影响 |
| 基线漂移（multica HEAD ≠ `8746add...`） | M0 核对；编码前 `workspace-freshness` gate；diverged 一律人工 | freshness gate 路由（continue / synced-continue / replay / manual），不自动合并 |
| multica 双周 rebase 定制丢失 | `CUSTOM.md` 逐条登记 + `// AIFIRST:` 标记；M6 核对 | 以 CUSTOM.md 清单逐条恢复 |
| KG-1/KG-2 被误判为本 CR 缺陷 | SDD §4.13 已裁定归属 CR-B/CR-C；test-report 明示 | 不适用：评审按既定裁定放行 |
| 某域证据不足 | M6 逐 AC 对照 28 条；code review 缺证据即 block | 保留 CR 在 reviewLoop 回修态，补齐后重评 |

# 6. 验收与发布策略

## 开发完成 checklist

- [ ] M0：两资源 healthy，multica HEAD 与 SDD §9 一致，`make sqlc` 与三组 `go test` 入口可用（均在 `server/` 目录，命令形如 `cd server && go test ./internal/handler/ ./pkg/agent/ ./internal/service/ -count=1`）。
- [ ] 迁移 472–480：一文件一句、`CONCURRENTLY`、无 FK、down 配对；`issue_project_chat_unique` 已 DROP（AC-22）。
- [ ] 校验单一实现：四入口只经 `ValidateResolvedChatConfig` → `agent.ValidateChatConfig`；service 无 handler import、无第二套归一化。
- [ ] GET 不建 Issue（AC-11）；PATCH/container/messages/merge-forward 失败路径均「不写/不建/不入队」（AC-23/24）。
- [ ] Private Ask 后端闭环：新建 INSERT 即写 `base_*`（首次 GET `session_default` 精确值）、GET/PATCH 响应含 `session_id`（= `id`）、PATCH `FOR UPDATE` 行锁序列（锁→回填→Resolve→Patch）+ 并发/回滚夹具、发送回填+校验+`chat_config` 快照（`CreateChatTask` 参数接缝）仅 project-bound 生效且普通聊天零变化回归；历史行 `agent_default` 不落库（AC-3/19/25，FR-11；BLOCK-004~008）。
- [ ] 发送首次绑定与 comment/enqueue/附件绑定同一事务，失败全回滚（AC-15）。
- [ ] 换绑后新 session 新容器、旧 timeline 隔离、收养窗口 COUNT==1 不回退（AC-18）。
- [ ] `comment.go` / `RouteDiscussionToTeamAgent` 零 diff；`GetProjectChatIssue` 同时间戳双行固定较小 `id`。
- [ ] 前端无 `updateAgent` 聊天路径调用；硬降级不伪造 `session_id`（AC-1/2/21/27）；四语文案齐（AC-26）。
- [ ] sweeper 边界与竞态夹具通过（AC-28）；未绑定附件上传者门（AC-14）。
- [ ] `CUSTOM.md` 登记完整；三域测试全绿；`write-test-report` pass。
- [ ] 独立 code review blocker 清零；`crctl approve --stage code` 通过后再合并、writeback、archive。

## 发布策略

本 CR 不引入 feature flag：行为切换随迁移与代码一次性生效；旧客户端兼容由前端独立 schema 硬降级（只读）承担，不保留双写路径。发布顺序即既有流程：各资源 CR worktree 完成实现与测试 → 统一 `crctl checkpoint` → 独立 code review → 人工 code approval → 合并 → writeback → archive。

回滚原则：迁移 down 文件按号逆序执行（480→472），代码按 commit 粒度回退；任何回滚不得保留「半启用」状态（如只回代码不回迁移）。`origin_id=session.id` 新容器行与 `chat_config` 任务快照对旧代码均为兼容只读数据，单独回退代码不产生脏数据。

---
cr: CR-2026-059
pipeline-node: review-tech-design（cycle 1 BLOCK 回修完成，复评待发起）
status: tech-design-review-pending
updated: 2026-09-04T14:35:00+08:00
owner-agent: dev-agent
---

# CR-2026-059 工作流导航缓存（_context.md）

> 导航缓存，非 canonical。canonical 事实以 cr.md / review-loop.yml / traceability.yml / 评审记录为准。

## 当前状态（cycle 1 BLOCK → 回修完成）

- 上一轮独立复评**已 canonical 落盘**（与前两轮不同）：verdict=`block`，评审三账本提交 `179a3a9`，status 由评审方回退至 `tech-designing`，review-loop tech-design cycle 1/3 已开出（`review-annotations/sdd.yml` 为准）。
- 本轮 = `write-tech-design` 回修（reviewLoop fix-mode），逐项闭合 7 个 blocker（B-MIG-1 / B-MIG-2 / B-CONFIG-1 / B-IDEMP-1 / B-REALTIME-1 / B-COORD-1 / B-AUTHOR-1），全部定点修订于 `sdd.md`，PRD 零改动。
- 回修后由本会话 `write-tech-design-complete` 推回 `tech-design-review-pending`；下一步 = 独立 `quality-reviewer-agent` 复评（必须逐条闭合上述 7 项）。

## 回修摘要（逐项 → sdd 落点）

1. **B-MIG-1**（487 内联 PK 隐式唯一索引违反 CONCURRENTLY 硬不变量）→ §2.6 重写：487 建表不内联 PK → 488 `CREATE UNIQUE INDEX CONCURRENTLY chat_idempotency_scope_key_uidx` → 489 单语句 `ADD CONSTRAINT chat_idempotency_pkey PRIMARY KEY USING INDEX` → 490 `CREATE INDEX CONCURRENTLY idx_chat_idempotency_created`；down 逆序；`ON CONFLICT ON CONSTRAINT chat_idempotency_pkey` 为仲裁靶（决策 D-12）。迁移区间 481–490（10 个）。
2. **B-MIG-2**（483 先删后建有无约束窗口）→ §2.3 重写：**先以新名 `chat_session_private_creator_active_unique` CONCURRENTLY 建好收窄索引（483），再 CONCURRENTLY 删旧索引（484）**；全程至少一个唯一约束在位（双强制窗口只过约束不漏放）；改名联动 `chat.sql:16` 注释与 sqlc 生成注释（已核实无 ON CONFLICT 按名引用）；484.down 重建旧宽谓词（数据依赖注记）；决策 D-3 重写。
3. **B-CONFIG-1**（无 Coordinator 时 PATCH 免校验 + 入队校验无确定调用点）→ §4.4 重写为 **provider/catalog authority 阶梯**：L1 = 已配置且 agent 行存在（可路由/归档）→ `LoadChatCatalogForConfig` 逐字；L2 = 未配置/hard-deleted → workspace ready-runtime 并集（`ListAgentRuntimes` created_at ASC + `runtimeVerdict().Ready()` + `ValidateResolvedChatConfig` 逐 runtime，纯 sentinel 恒过，至多 1 次 30s LiveLoad round）；§4.2 `if trigger.needTask` 块标出**入队前校验**（事务内、`CreateChatTask` 之前、400 回滚零写入、Idempotency-Key 可复用）；决策 D-6 重写（推翻「接受并推迟」）。
4. **B-IDEMP-1**（指纹用排序前 attachment_ids）→ §4.6：重复校验后**稳定排序**（UUID 规范串升序）再规范 JSON + sha256；顺序不变性测试向量；§3.4/AC-26 行同步。
5. **B-REALTIME-1**（"既有 relay 广播断连指令"不存在）→ §4.7 重写为完整跨节点断连契约：`Broadcaster.DisconnectWorkspaceUser`（纯新增）+ 保留控制帧 `realtime.control`（绝不投递客户端）+ 载体复用 `user:{userID}` scope 流（持有连接的节点必然消费）+ `deliverEnvelope` 唯一新增分支 + 各模式消费矩阵（Hub/RedisRelay/Sharded/Mirrored/DualWrite）+ 挂接点独立于 `revocationResult.isEmpty()` + 双节点验收向量；§10 新增依赖 41–44（broadcaster/redis_relay/sharded+mirrored/main.go 接线），dep 26 补 user-scope 自动订阅前提；决策 D-11。
6. **B-COORD-1**（触发检测只收可路由 Coordinator，失效 Coordinator mention 退化为普通消息）→ §4.3 重写：输入同时携带 `configured`（settings UUID）与 `routable`；先识别「配置身份 mention」（UUID 归一化比较），再分未配置 → 409 not_configured / 已配置不可路由 → 409 unavailable（均零写入）；其它 Agent mention 保持普通消息；§4.5 归档/hard-delete 行 + AC-31/AC-32 补测试向量。
7. **B-AUTHOR-1**（作者列无端到端消费）→ §2.5 端到端消费契约 + §3.3：服务端 `ChatMessageResponse` 增 `author_type/author_id` 可空字段（`chatMessageToResponse` 直映；`SELECT message.*` 免改查询）；core `ChatMessageSchema`/`ChatMessage` 可空契约（malformed catch 降级）；`DiscussionPane` 作者解析/展示 + NULL/已移出成员回退；三层测试向量；SDD-CLOSE-03 真关闭。

## 本轮附带补强（同源事实，非新方案）

- §4.9 迁移运行器纪律：`concurrentIndexCleanups`/`concurrentDownIndexCleanups` total 不变量 + `TestEveryConcurrentUpBuildHasCleanup`（本 CR 登记清单：up=483/485/488/490，down=484.down）——此前 SDD 未写，缺登记直接挂 CI。
- §10 新增依赖 39–44（runtime.sql ListAgentRuntimes、agent_ready.go runtimeVerdict、realtime 四文件 + main.go 接线），全部绑定 `be6426a7`。
- dep 4/13/26/33/34 结论按 blocker 扩展；§1.2 模块表、§6.1/§6.2/§6.3/§7.2/§9 口径同步（481–490、10 个迁移、指纹稳定排序、并集 authority、断连契约、作者链）。

## 评审入口（给 reviewer / 恢复会话）

1. 权威 worktree：`.rayai-worktrees/knowledge-base/requirement/CR-2026-059`（本目录）。
2. 评审对象：回修后 `change-requests/CR-2026-059/sdd.md`；对照 `prd.md`（选项 A 修订版）。复评必须逐条闭合 B-MIG-1、B-MIG-2、B-CONFIG-1、B-IDEMP-1、B-REALTIME-1、B-COORD-1、B-AUTHOR-1。
3. 证据基线：multica CR worktree HEAD `be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d`（还原提交，树 = main `e8b25259`；§10 依赖 44 项）。
4. 前置：`crctl gate CR-2026-059 --for tech-design-reviewing` → `crctl review-record CR-2026-059 --stage tech-design --bump-attempt`（轮次由 crctl 记账；cycle 1 已落盘，本轮为 attempt 2）。
5. PASS：reviewer 落盘并回报，人工 `crctl approve --stage tech` 由 coordinator 发布。BLOCK：直连回 `write-tech-design`（@ dev-agent）。

## 已核实事实基线（本轮新增核实项）

- `CLAUDE.md`「Database and Migration Rules」：每个新索引（含新表）必须 `CREATE [UNIQUE] INDEX CONCURRENTLY`、独立单语句迁移；运行器事务外执行文件（B-MIG-1 依据）。
- `cmd/migrate` runMigrations：单连接会话级 advisory lock、事务外逐文件；`concurrentIndexCleanups`/`concurrentDownIndexCleanups` total 不变量，`TestEveryConcurrentUpBuildHasCleanup` 守护。
- 旧索引 `chat_session_project_creator_active_unique` 仅被 436 迁移与 `chat.sql:16` 注释/生成注释引用，无 ON CONFLICT 按名引用（改名安全）。
- `ListAgentRuntimes(workspace_id)` ORDER BY created_at ASC；`runtimeVerdict` 为仅依赖 runtime 行的 verdict 原语（L2 并集依据）。
- realtime：`Broadcaster` 仅四广播方法；`deliverEnvelope` 仅客户端 fanout；`Hub.Run` register 自动订阅 workspace+user scope；relay 模式 = hub 单节点/legacy/sharded/dual-mirror + DualWrite 包装（B-REALTIME-1 依据）。
- `ChatMessageResponse`/`chatMessageToResponse`（chat.go L2175/~L2217）；列表查询 `SELECT message.*`（M486 列自动进入）；`ChatMessageSchema` `.loose()` + `quick_actions` 独立降级先例（B-AUTHOR-1 依据）。
- 此前基线（迁移 480 上限、481 FK 前提、436 谓词、三调用点、`writeChatCompletionOutcome` 在 service/task.go:5057 等）仍有效，见 sdd §10。

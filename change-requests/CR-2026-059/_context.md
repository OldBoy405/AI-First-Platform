---
cr: CR-2026-059
pipeline-node: write-tech-design（cycle 2/attempt 2 BLOCK 回修完成，待独立复评发起）
status: tech-design-review-pending
updated: 2026-09-04T14:45:00+08:00
owner-agent: dev-agent
---

# CR-2026-059 工作流导航缓存（_context.md）

> 导航缓存，非 canonical。canonical 事实以 `cr.md` / `review-loop.yml` / `traceability.yml` / `review-annotations/sdd.yml` 为准。

## 当前状态（cycle 2 attempt 2 BLOCK → 回修完成）

- 上一轮独立复评（quality-reviewer，canonical 落盘，attempt 2/3）verdict=`block`，两项 blocker：**B-MIG-3**（482/485/486.down 未定义、§4.9 down 清单不全）与 **B-AUTH-2**（shared 写路径 pre-tx 成员门禁与移出并发存在 TOCTOU）。上一轮七项 blocker（B-MIG-1/2、B-CONFIG-1、B-IDEMP-1、B-REALTIME-1、B-COORD-1、B-AUTHOR-1）已复核为已解决。
- 本轮 = `write-tech-design` 回修，两项 blocker 全部定点闭合于 `sdd.md`；PRD 零改动。
- 评审方 `review-record` 三账本（review-annotations/sdd.yml、review-loop.yml、traceability.yml）本轮落盘后**未提交**（前一轮由评审方自己提交 `179a3a9`）；本会话以单独 `[cr] review tech-design CR-2026-059 attempt 2` 提交清扫（内容零手改，仅提交 canonical 写入）。

## 回修摘要（逐项 → sdd 落点）

1. **B-MIG-3（down 全集缺失）**：
   - §2.2 补 `482.down` = `ALTER TABLE chat_session DROP COLUMN kind;`：普通 ALTER、无钩子；有损回滚数据依赖（仍存 project_shared 行时 kind 区分被抹除、行退回 private 语义；无条件成功，注释写明损失，不静默吞错）。
   - §2.4 补 `485.down` = `DROP INDEX CONCURRENTLY IF EXISTS chat_session_project_shared_active_unique;`：CONCURRENTLY 删除、**不构建 → 无构建钩子**（不登记 `concurrentDownIndexCleanups`）；数据依赖 = 代码未先回滚时并发首开可产生重复 active shared 行。
   - §2.5 补 `486.down` = `ALTER TABLE chat_message DROP COLUMN author_type, DROP COLUMN author_id;`：有损回滚（已写 shared 消息作者归属不可逆丢失，展示退回 NULL 降级）。
   - §2.6 down 给出显式 SQL（490.down 普通 DROP、489.down DROP CONSTRAINT、488.down CONCURRENTLY 删除、487.down DROP TABLE）。
   - §4.9 新增 **down 全集表**（481–490 逆序回滚、类型/钩子登记/数据依赖逐条），明确 `concurrentDownIndexCleanups` 登记 = **仅 484.down**（唯一 down 方向 CONCURRENTLY 构建）；485.down/483.down/488.down 为 CONCURRENTLY 删除不登记；代码先于 485/482.down 回滚的窗口契约。
   - §6.2 AC-19 行同步：down 往返全绿（含 482/485/486.down）、down 侧登记仅 484.down、有损回滚注释、命令 `go test ./server/cmd/migrate/ -count=1`；SDD-CLOSE-08 同步（B-MIG-1/2/3 回修）。
2. **B-AUTH-2（成员资格 pre-tx TOCTOU）**：
   - §4.2 发送事务：`LockSubscriberWrites(ws, caller)` 为**第一把锁**（与 `revokeAndRemoveMember` 同一把 (workspace,user) advisory [D-27]，双方首锁一致 → 与移出串行、无死锁）→ 事务内 `GetMemberByUserAndWorkspace` 复核（在幂等插入等任何写入之前）→ 之后才 project-discussion advisory → 会话行锁。新增锁序/竞态段：锁序固定禁止重排；竞态二择一（移出先提交 → 404 回滚零写入、Idempotency-Key 可复用；发送先锁 → 消息落库后断连生效）；失败事务零残留（幂等/消息/task/附件）。
   - §3.2 shared PATCH 同款事务内复核（advisory 先于会话行锁；复核成员行 + role ∈ {owner,admin}）；§3.4 补双保险注记。
   - §3.5 merge-forward：派发前即时成员复核 + presenter 守卫第二层 + 内核零 diff 残留窗口诚实注记（与 legacy comment_ids 同语义）。
   - §4.8 读路径说明（无写入无需串行）；§7.1 安全节增「写路径移出竞态关闭」条；AC-28/AC-29 行补竞态测试向量（pre-tx 通过后移出先提交 → 404 零写入；移出与发送并发二择一）。
   - §10 依赖 27 扩展：workspace_revoke.go + subscriber.go + autopilot.go + member.sql + subscriber.sql（LockSubscriberWrites 锁序、GetMemberByUserAndWorkspace、DeleteMember），并修正正文 `revokeAndRemoveMember` 引用号为 [D-27]（原 [D-31] 为 §10 编号漂移）；FR-18 行 `writeErrorCode`/`writeProjectChatSendError` 引用修正为 [D-24]/[D-18]。

## 评审入口（给 reviewer / 恢复会话）

1. 权威 worktree：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-059`（分支 `requirement/CR-2026-059`）。
2. 评审对象：回修后 `change-requests/CR-2026-059/sdd.md`；对照 `prd.md`。复评必须逐条闭合 B-MIG-3、B-AUTH-2（落点：§2.2/§2.4/§2.5/§2.6/§3.2/§3.4/§3.5/§4.2/§4.8/§4.9/§6.2 AC-19/AC-28/AC-29/§7.1/§10 dep 27）。
3. 证据基线：multica CR worktree HEAD `be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d`（§10 共 44 项，其中 dep 27 已扩展）。本轮新增核实事实：`revokeAndRemoveMember` 以 `LockSubscriberWrites`（subscriber.sql L27 `pg_advisory_xact_lock(hashtext(ws), hashtext(user))`）为第一把锁后删 member 行；delegated auto-subscribe 路径 subscriber.go:239 / handler/autopilot.go:841 同一把锁；`GetMemberByUserAndWorkspace`（member.sql L10）为无锁 SELECT、`DeleteMember`（L24）按 member 行 id 删除；`sendProjectChatCore` 内核事务自开、presenter 守卫为 pre-tx 层。
4. 前置：`crctl gate CR-2026-059 --for tech-design-reviewing` → `crctl review-record CR-2026-059 --stage tech-design --bump-attempt`（attempt 3，轮次由 crctl 记账；无论 PASS/BLOCK 都落盘 canonical，并**提交三账本**——本轮教训：review-record 只写文件不提交，必须由评审会话随即将三账本提交推送，否则 worktree 脏、checkpoint 会把 canonical 评审记录裹进 wip 提交）。
5. PASS：落盘后回报，人工 `crctl approve --stage tech` 由 coordinator 发布。BLOCK：直连回 `write-tech-design` @ dev-agent。

## 已核实事实基线（本轮新增/沿用）

- `LockSubscriberWrites` = `SELECT pg_advisory_xact_lock(hashtext(ws::uuid::text), hashtext(user::uuid::text))`（subscriber.sql L27），事务级、(workspace,user) 键；`revokeAndRemoveMember` 锁序注释明写「Taken FIRST… First also means every holder acquires it in the same order, so these paths cannot deadlock against each other（MUL-5483 review round 7）」。
- `GetMemberByUserAndWorkspace`（member.sql L10）：`SELECT * FROM member WHERE user_id=$1 AND workspace_id=$2`，无锁；`DeleteMember`（L24）：`DELETE FROM member WHERE id=$1`。
- `sendProjectChatCore`（service/project_chat.go L213）：pre-tx presenter/capacity guard → 自开事务（L276）project-chat-session advisory → 会话行 FOR UPDATE → 绑定容器 → comment/task/附件；锁序固定 §4.14 不得重排（zero_diff 依据）。
- 迁移运行器：`cmd/migrate` runMigrations 单连接会话级 advisory、**事务外逐文件**（支持 CONCURRENTLY）；`concurrentIndexCleanups`/`concurrentDownIndexCleanups` 为 total 不变量（`TestEveryConcurrentUpBuildHasCleanup` / `TestConcurrentIndexCleanupsMatchTheirMigrations` 守护）；down 文件命名 `<version>_<name>.down.sql` 与 up 同目录（479/480/475 先例：CONCURRENTLY 删除 `DROP INDEX CONCURRENTLY IF EXISTS`、重建 `CREATE UNIQUE INDEX CONCURRENTLY`，`-- AIFIRST:` 头注释）。
- 此前基线（迁移 480 上限、481 FK 前提、436 谓词、旧索引名零按名引用、`ListAgentRuntimes` ASC、`runtimeVerdict`、`Broadcaster` 四方法、`ChatMessageResponse`、`ParseMentions` 等）仍有效，见 sdd §10 全文。

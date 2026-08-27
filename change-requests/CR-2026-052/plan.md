---
id: CR-2026-052-plan
type: PLAN
cr-ref: CR-2026-052
sdd-ref: "change-requests/CR-2026-052/sdd.md"
target-version: tbd
status: draft
created: 2026-08-27T10:44:32+08:00
updated: 2026-08-27T10:44:32+08:00
---

# 开发计划：Multica 审批后自动续跑 + audit-drift 去重修复

> 权威输入：`change-requests/CR-2026-052/sdd.md` v0.5（cycle 2 attempt 1 回修，已人工 `approve-tech-design`）。
> 本计划覆盖 SDD v0.5 全部修复（TD-BL-10/11/12 闭环）与 PRD AC-1~AC-12 验收面，逐 TASK 可回指 SDD 章节。

## 1. 交付里程碑

两仓改动互不依赖（SDD §1.1，NFR-9）：multica（Go 服务端，FR-1~FR-11）与 tools（crctl.mjs，FR-12）可独立上线。计划按 5 个里程碑排期，总估算约 **45 人时**（≈ 6 人天）。

| 里程碑 | 内容 | TASK | 估算 | 依赖 |
|---|---|---|---|---|
| M1 数据层与去重修复 | multica 三条迁移 + tools comparable 修复（可并行） | TASK-01, TASK-02, TASK-08 | 12h | M1 内 TASK-02 依赖 TASK-01；TASK-08 独立 |
| M2 核心服务实现 | TaskService 续跑入队 + HandleGrantsAck 事务核心 | TASK-03, TASK-04 | 13h | 依赖 M1（TASK-02） |
| M3 接线与适配 | Runner 双钩适配 + router 接线 | TASK-05 | 4h | 依赖 M2（TASK-04） |
| M4 测试与验证 | multica 集成测试 + tools drift 测试（可并行） | TASK-06, TASK-09 | 14h | 依赖 M3（TASK-05）/M1（TASK-08） |
| M5 台账与发布 | multica CUSTOM.md 台账登记 | TASK-07 | 2h | 依赖 M4（TASK-06） |

阶段划分对照 SDD §1.3 组件树与 §7.4 测试设计；里程碑边界即代码可编译/可测试边界。

## 2. 任务依赖图

```text
  multica 仓                                          tools 仓
  ─────────                                           ───────
  TASK-01 migrations ──► TASK-02 sqlc queries          TASK-08 comparable fix ──► TASK-09 drift tests
                              │
                              ▼
                       TASK-03 TaskService.Enqueue
                              │
                              ▼
                       TASK-04 HandleGrantsAck + 双钩
                              │
                              ▼
                       TASK-05 Runner + router wiring
                              │
                              ▼
                       TASK-06 multica 集成测试
                              │
                              ▼
                       TASK-07 CUSTOM.md 台账
```

依赖拓扑（`depends-on`）：
- TASK-01 → []（无前置）
- TASK-02 → [TASK-01]（queries 引用 470 新列与 469/471 索引）
- TASK-03 → [TASK-02]（依赖 sqlc 生成的查询函数签名）
- TASK-04 → [TASK-02, TASK-03]（事务编排消费 TaskService 入队方法）
- TASK-05 → [TASK-04]（Runner/router 接线消费 GrantAckEvent 与双钩）
- TASK-06 → [TASK-05]（测试覆盖全链，经 TASK-05 传递依赖 TASK-03/04）
- TASK-07 → [TASK-06]（台账登记需待 multica 改动落地与测试通过）
- TASK-08 → []（tools 仓独立，无前置）
- TASK-09 → [TASK-08]（测试覆盖 comparable 修复）

无环、无悬空引用。multica 串行链 01→02→03→04→05→06→07；tools 链 08→09 与 multica 链全程可并行。

## 3. 资源与分工

| 仓 | 角色 | 负责人 | 工时 |
|---|---|---|---|
| multica | 开发 | Ray（cr.md owners.development.id） | ~39h（TASK-01~07） |
| multica | 测试 | Ray（cr.md owners.test.id） | 含于 TASK-06 |
| tools | 开发+测试 | Ray | ~6h（TASK-08~09） |

跨仓无共享代码面：multica 改 `server/`，tools 改 `skills/shared/crctl/scripts/crctl.mjs`，两者无编译/接口耦合（NFR-9）。tools 侧修复可先行独立上线，不阻塞 multica 链。

## 4. 风险与回滚策略

| 风险 | 等级 | 回滚/缓解 |
|---|---|---|
| 迁移 469/470/471 在生产并发写期间锁表 | 中 | 全部用 `CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS` + 单语句（SDD §2.2/2.3，NFR-7）；470 是 `ALTER TABLE ADD COLUMN`（nullable，无表锁重写）；down 迁移幂等（DROP … IF EXISTS）。回滚 = 顺序执行 down 迁移。 |
| 权威锁链 FOR SHARE 阻塞 crsync 投影写 / issue 重指派 | 低 | SDD §7.2/DD-10：ACK 低频人工路径，短事务内持有，等待毫秒级；FOR SHARE 与既有 FOR KEY SHARE 持有方兼容，不新增冲突面；残余死锁由 Postgres 检测中止 → 5xx → daemon 诚实重试（无部分效果）。 |
| 双钩语义被未来误用（canonical handler 写副作用） | 中 | TD-BL-12 闭合：`onGrantAck`/`SetGrantAckHandler` 契约零外部副作用、error→回滚/5xx；`onGrantAckCommitted` 才承载真实 wake、error→日志/2xx。TASK-04 在签名/注释固化契约，TASK-05/06 用 AC-9a~d 锁定。任何未来在 canonical handler 写副作用须先修订 PRD/事务边界。 |
| 阶梯 3 deferred 让位被普通任务长期占槽推迟续跑 | 低 | SDD §7.5/DD-9：`PromoteDueDeferredTasksForRuntime` 槽释放后自动翻 queued，不丢；runtime 离线时 deferred 等待（与任何 deferred 任务一致）；属"不并发唤醒、不注入沙箱"的预期结果，非缺陷。 |
| sqlc 生成物手改 | 中 | ARCHITECTURE §5.5/SDD §1.3：改 `.sql` 后 `make sqlc` 重生成，禁止手改 `pkg/db/generated/*.go`。TASK-02 校验生成物 git diff 只含预期新增。 |
| multica CUSTOM.md 台账漏记导致 rebase 丢定制 | 中 | AGENTS.md 纪律 10：TASK-07 逐条登记新文件/`// AIFIRST:` 挂钩点/迁移/governance 自研包，编号顺延。 |
| tools comparable 修复削弱 dedup 确定性守卫 | 低 | SDD §4.4/DD-6：仅剥离 `detected_at`，摘要字段仍在比较内；同名文件内容真实变化仍冲突报错（AC-12 第三分支）。 |

## 5. 验收与发布策略

### 5.1 验收面（PRD AC-1~AC-12 → TASK/SDD 映射）

| AC | FR | 落点 | 关键断言 |
|---|---|---|---|
| AC-1 | FR-1/FR-4 | TASK-04 + TASK-06 | 同 approval_record 两次 ACK → 恰 1 条续跑任务，第二次幂等返回 |
| AC-2 | FR-2 | TASK-04 + TASK-06 | 四 stage 各 approve/reject → 各 1 条续跑，上下文含 stage/decision；reject 不中断 |
| AC-3 | FR-3 | TASK-04 + TASK-06 | 入队失败 → delivered_at=NULL + HTTP 5xx；修复后下周期重投递成功 |
| AC-4 | FR-5 | TASK-06 | ACK 5xx → grants 保持 pending → 15s 重投递（deliverGrants fake） |
| AC-5 | FR-6 | TASK-03/04 + TASK-06 | 同 CR 再 ACK → 后继 ≤1，运行中任务无注入事件；AC-5g/5i claim-vs-append 时序 |
| AC-6 | FR-7 | TASK-04 + TASK-06 | 无 shell issue/squad/leader → 保持未 ACK + 原因码；AC-6b/6c FOR SHARE race；AC-6d 跨 workspace 同名 CR 隔离 |
| AC-7 | FR-8 | TASK-04 + TASK-06 | 历史 delivered_at 非空行不产生任务，无回填迁移 |
| AC-8 | FR-9 | TASK-04 + TASK-06 | 上下文无"状态→下一步"映射；Runner 关闭时零调用，ACK 仍生效 |
| AC-9 | FR-10 | TASK-04/05 + TASK-06 | 回调收到字段与 approval_record 一致；AC-9a~d 双钩 error→HTTP 语义 |
| AC-10 | FR-11 | TASK-03/04 + TASK-06 | 不新增执行状态列；续跑进度在既有任务/issue 展示面可见 |
| AC-11 | FR-12 | TASK-08 + TASK-09 | 同漂移两次观测 → 文件数 1，第二次无 EMIT_FAILED |
| AC-12 | FR-12 | TASK-08 + TASK-09 | 删除后重观测 → 新文件按窗口计数；不同 CR/摘要不误合并；内容真变化仍冲突 |

### 5.2 SDD v0.5 TD-BL 修复覆盖

| Blocker | 闭合措施 | 落点 |
|---|---|---|
| TD-BL-10 workspace-qualified authority | 迁移 470 `approval_workspace_id` carrier + CHECK；迁移 471 `(workspace,cr)` queued/deferred 唯一索引；所有 fallback/merge/lock 读按 `$ws` 限定；guarded INSERT 全链 workspace join 复核；AC-6d 同名 CR 跨 workspace 隔离 | TASK-01(470/471) + TASK-02(ws-scoped queries) + TASK-04(resolveContinuationTarget) + TASK-06(AC-6d) |
| TD-BL-11 仅合并 queued/deferred | 阶梯 2 仅 `GetMergeableApprovalContinuationTaskByWorkspaceAndCrForUpdate`（状态 queued/deferred，FOR UPDATE）锁行合并；dispatched/waiting_local_directory/running 一律阶梯 3 补插独立后继；AC-5g/5i 真实 claim-response 快照时序 | TASK-03(阶梯逻辑) + TASK-04 + TASK-06(AC-5g/5i) |
| TD-BL-12 双钩回调语义 | 保留 `onGrantAck`/`SetGrantAckHandler` 为预提交 error→5xx canonical callback（零副作用）；新增 `SetGrantAckCommittedHandler`/`onGrantAckCommitted` 提交后真实 wake（error→日志/2xx）；Runner `ValidateGrantAck`→pre-flight、`WakeGrant`→committed；AC-9a~d 锁定 error→HTTP 语义 | TASK-04(GrantAckEvent+双钩) + TASK-05(ValidateGrantAck/WakeGrant+router) + TASK-06(AC-9a~d) |

### 5.3 发布策略

- **验证顺序**（SDD §7.4）：multica 根 `make sqlc` → `cd server && go test ./internal/governance/... ./internal/daemon/...`；tools worktree `node --test skills/shared/crctl/scripts/test/crctl.test.mjs`。仓库根无 `go.work`、Go module 在 `server/go.mod`，禁止写不可执行的 `go test ./server/internal/...`（TD-SUG-5）。
- **两仓独立上线**：tools 侧 FR-12 不要求 daemon/服务端配合（NFR-9），可先发；multica 侧上线后即对四类审批生效。无 feature-flag 需求（ACK 鉴权与端点不变，NFR-12）。
- **不回填历史**（FR-8/AC-7）：上线后只处理新 ACK，旧 `delivered_at` 非空行天然不进 UPDATE 结果集。
- **CUSTOM.md 台账**：TASK-07 登记迁移 469/470/471、governance 自研包（approval.sql、GrantAckEvent/双钩、resolveContinuationTarget、TaskService 续跑方法）、router 接线点与 runner 适配，编号顺延。
- **回滚**：任一迁移 down 幂等；代码回滚 = revert 对应 commit（迁移与代码同提交或紧邻提交，便于整段回退）。tools 侧回滚 = revert comparable 一行修复。

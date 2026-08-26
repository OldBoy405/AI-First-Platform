---
id: CR-2026-051-plan
type: PLAN
cr-ref: CR-2026-051
sdd-ref: "change-requests/CR-2026-051/sdd.md"
target-version: tbd
status: draft
created: 2026-08-25T23:20:00+08:00
updated: 2026-08-26T11:40:00+08:00
---

# 0. 输入与前置事实（落笔前当场核实）

| 项 | 值 |
|---|---|
| PRD | `change-requests/CR-2026-051/prd.md`，sha256 `b64a92cfe182…`，33911 B（LF 口径，磁盘即 LF；本 CR 全程未改） |
| SDD | `change-requests/CR-2026-051/sdd.md`，sha256 `39999101f3f3…`，93545 B（LF 口径，磁盘即 LF）—— **上游回修后版本**，非 cycle 1 的 `7bbcf822c9d5…`/81407 B |
| 架构评审 | `review-annotations/sdd.yml`：verdict `pass`、blocker 0、subject-sha256 `39999101…`（= 上表 SDD）；`review-loop.yml#review-tech-design` = **cycle 2 / attempt 1**（cycle 1 的两次 attempt 针对旧 SDD，`detectNewTechDesignCycle` 已开新周期） |
| 架构审批 | `approval.yml#tech-design`：approver `OldBoy405`、`2026-08-26T10:35:47+08:00`、`via: crctl-approve`、evidence-digest `9cfdd8e4…`、target-status `tech-design-reviewed`。cycle 1 的旧审批（`Ray`/`2026-08-25T23:05:49`/`a44a0416…`）已因新评审证据触发 `EVIDENCE_DRIFT` 失效，由本次人工重签取代 |
| CR 状态 | 进入本 Skill 前 `crctl status` = `tech-design-reviewed`（由 `task-breakdown` 经 `review-dev-plan:block -> write-dev-plan` 回退）、`crctl next` = `write-dev-plan`；`gateBlockers` 仅预期的 `developing: dev-start` |
| 开发计划评审 | `review-annotations/dev-plan.yml`：verdict `block`、`repair-target=write-dev-plan`、blocker 2、subject-sha256 `6efbaaa9…`（= 上一版 plan.md + TASK-01~08 的复合 digest）；`review-loop.yml#review-dev-plan` = cycle 1 / attempt **1/3**。**本轮 = 该 block 的定点回修**，逐条处置见 §5.6 |
| operational workspace | `…\.rayai-worktrees\knowledge-base\requirement\CR-2026-051`（`crctl workspace inspect` 原样值，三仓 resources 全 `healthy`、`dirty=false`） |
| 落码仓 | `multica` → `…\.rayai-worktrees\multica\requirement\CR-2026-051`（HEAD `93aa7c5bd`）。`tools` 仓本 CR 零改动、只读 |
| 计划内引用的代码事实 | 全部在上述 multica worktree（分支 `requirement/CR-2026-051`）当场核实，不照抄 SDD 措辞（清单见 §5.3） |

**审批期三项确认（delivery-agent 转达，两次审批均无异议，按 SDD 主题采纳）**：

1. **FR-10 改动面 +1 文件**：`server/pkg/protocol/events.go`（+1 常量 +1 载荷类型）纳入合法改动集（SDD §5 DD-4 主方案生效，备选 1 map/JSON envelope 作废）。
2. **事件级 `failed` 日志无 recipient 字段**：SDD §4.6 第 5 条的可观测性加法细化采纳。
3. **AC-4 情形① 的场景级口径**（cycle 2 重签时新增确认，对应 `sdd.yml#suggestions[0]`）：无 owner/admin 的事件记**事件级** `no-approver`；混合 workspace 中普通 `member` 以「不进入收件人集合」证明零发送，**不产生逐 member 的收件人级 skip 日志**（SDD §4.6 第 7 条）。**这一条不是 PRD 偏离**——`no-approver` 本就在 PRD FR-8.2 的 9 值枚举内，且本就归 PRD §4.4 的事件级 partition，因此**不进**下面的回写期 revision 清单，只作为实施期口径固化（落点：TASK-06 验收 4 情形① 的两条互补断言，含「不得描述成收件人级 reason」的反向断言）。

**第 1、2 项**是对**已审批 PRD 字面**的加法（FR-10 改动清单 / §4.4 可观测性表），因此列为回写期偏离项：`writeback-prd-sdd` 时须以 revision 修订 PRD FR-10 与 §4.4，并注明"结论是否受影响"（先例：CR-2026-050 TASK-02 的 AC-05 改判口径）。本计划把该登记动作固化为 TASK-08 完成标志的一条，不留在人的记忆里。

# 1. 交付里程碑

按 SDD 的依赖方向切三段：**契约与发布侧 → 传输与提醒器 → 装配与收口**。每段都能独立取得可执行证据（真库 `--- PASS`），不存在"要等全链打通才知道对不对"的阶段。

| 里程碑 | 内容 | TASK | 估算 |
|---|---|---|---|
| M1 契约与发布侧 | 共享事件契约（`pkg/protocol`）+ governance 发布点 + 触发/隔离真库测试（AC-1、AC-2） | TASK-01 ~ TASK-03 | 16h |
| M2 传输与提醒器 | `APIClient` 新方法与 `sendCardToOpenID` 提取 + 审批卡模板 + 提醒器同步回调 + 异步读链与投递（AC-3~AC-5、AC-7、AC-10~AC-13 主体） | TASK-04 ~ TASK-06 | 28h |
| M3 装配与收口 | `router.go` 无条件订阅 wiring（AC-12 形态）+ 改动面静态核对 + 全量回归 + CUSTOM.md 台账（AC-6、AC-8、AC-9） | TASK-07 ~ TASK-08 | 11h |

估算总工时：**55h（约 7 人天，单开发）**。

本 CR **无阶段 gate 强制 checkpoint**（PRD 未要求，AC 里也没有对应项）：M1/M2 各自的完成证据就是该里程碑最后一个 TASK 的完成标志。远端推送按 `push-progress` 常规节奏走，不额外造 gate。

# 2. 任务依赖图

```text
TASK-01 (pkg/protocol 共享事件契约 + golden JSON)
   │
   ├──▶ TASK-02 (governance 发布点 + shell_issue_id 扩列)
   │        │
   │        └──▶ TASK-03 (governance 真库：四门禁触发 + 误触发隔离) ──┐
   │                                                                  │
   └──▶ TASK-05 (提醒器骨架：构造/注册/零 I/O 回调/日志四入口)        │
            ▲            │                                            │
            │            └──▶ TASK-06 (异步读链 + 分类 + 凭据水化 + 投递) │
            │                          │                              │
TASK-04 (APIClient 新方法 + sendCardToOpenID 提取 + 卡片 + 4 替身)     │
                                       │                              │
                                       └──▶ TASK-07 (router wiring)  ─┤
                                                                      │
                                                     TASK-08 (改动面核对 + 全量回归 + CUSTOM.md)
```

- **声明依赖**：TASK-02 ← 01；TASK-03 ← 02；TASK-05 ← 01, 04；TASK-06 ← 05；TASK-07 ← 06；TASK-08 ← 03, 07。TASK-01 与 TASK-04 无依赖，可并行；**单开发者按编号顺序串行执行**，避免 TASK-05/06 同时编辑 `approval_reminder.go`。
- **多仓路径纪律**：仓根只允许以 `execution_context.resources[].repo` 匹配 repo-id 后取对应 `worktreePath`。本 CR 全部代码路径为 `repo=multica` 仓根相对路径；禁止从 knowledge-base worktree 拼接 `multica/` 或 `server/`。`repo=tools` 仅只读参考，零改动（AC-8 断言项）。
- **同文件顺序约束**：`approval_reminder.go` 由 TASK-05 建立骨架（构造/注册/`handleEvent`/日志入口），TASK-06 只在其后追加 `deliver` 与读链，不回改 TASK-05 已固定的构造契约；`http_client.go` 只在 TASK-04 动一次（helper 提取），后续 TASK 不得再改其正文。

# 3. 资源与分工

| 角色 | 人员 | 范围 |
|---|---|---|
| 开发 | Ray（`cr.md owners.development.id`） | TASK-01 ~ TASK-08 全部 |
| 测试 | Ray（`cr.md owners.test.id`） | 各 TASK 内测试的真库取证（C6 口径）；`write-test-report` 阶段按 AC-1~AC-13 汇总 |
| 需求 | Ray（`cr.md owners.requirement.id`） | 回写期两项 PRD revision（§0 的 FR-10 改动面 +1 文件、§4.4 事件级 `failed` 无 recipient） |

工时分布：M1 16h / M2 28h / M3 11h。M2 占比最高（51%），因为提醒器是本 CR 唯一的新增执行体，且 AC-3/AC-4/AC-10 的真库四态断言集中在 TASK-06。

# 4. 风险与回滚策略

| 风险 | 缓解与回滚 |
|---|---|
| **私有 helper 提取改动上游函数正文**（`SendBindingPromptCard`，SDD §4.5 唯一一处） | 回归锁是既有断言**原样不改即通过**：`http_client_test.go:1077`（happy path）、`:1270`、`:1276`（错误路径）。任一处需要改测试才能过 ⇒ 判定行为不等价，**回滚 helper 提取**，退化为在 `approval_reminder_card.go` 内自持传输段（代价：~30 行重复 + 两处 token 失效处理会漂移，须在 CUSTOM.md 记明） |
| **真库测试假绿**（CUSTOM.md C6；`lark` 包 DB helper 走 `t.Skipf`、`governance` 包 `TestMain` 在 DB 不可达时整包 skip，`go test` 仍 exit 0） | 每条 DB 测试必须 `-v` 看到 `--- PASS`；出现 `--- SKIP` 一律视为**未测**，不得据此标记 TASK done。`DATABASE_URL` 按 C6 取真密码 + 5433 转发。**禁止为跑通而改 `TestMain` 或 skip 逻辑** |
| **裸 SQL 列名只在运行时暴露**（DD-2 的既定代价） | 两条裸 SQL 全部被 TASK-06 的真库测试覆盖；TASK-08 在 CUSTOM.md「合并注意」列登记列清单（含"`config` JSONB 不在裸 SQL 依赖面"）。上游改列名时该行是唯一核对清单 |
| **typed-nil 接口 panic**（`h.LarkInstallations` 为 nil 指针时赋给接口字段） | 防护在 TASK-07 wiring 显式判空（`if h.LarkInstallations != nil` 才赋值）；**验证也只能在 TASK-07**：提醒器内不反射、`r.credentials == nil` 对 typed-nil 为假（SDD §3.2.3），所以 TASK-05 不再承担该断言（原计划的“双保险”是错的，dev-plan 评审 BL-3 已纠）。TASK-07 验收 3 把「无条件赋值 → `iface == nil` 为假」升为**执行断言**，以防日后重构把判空当冗余删掉。已核实的不对称：`h.LarkAPIClient` 本身是接口类型，其判空对 typed-nil 不承重（仅形态统一） |
| **事件误触发**（发布点放错分支，把 reconcile/重放/自环也当审批入口） | TASK-03 的隔离矩阵逐分支断言零发布（首见分支、`else` needs_reconcile、checkpoint/review/trace、`reconcile.go`、`gate_projection.go`、自环）。发布点是 append-only 挂钩，回滚 = revert `crsync.go` 单文件改动，既有投影语义不受影响 |
| **`APIClient` 接口新方法漏补测试替身** → `lark` 包整包 build 失败（连带上游既有测试全红） | TASK-04 一次补齐 4 个替身（`outbound_test.go`、`outcome_replier_test.go`、`typing_indicator_test.go`、`inbound_enricher_test.go`），`go build ./... && go vet ./internal/integrations/lark/` 是其完成标志的硬条件 |
| **WS 扇出成为客户端可见契约**（`listeners.go#SubscribeAll` 会广播本事件） | 载荷只有四个标识、无标题/证据/收件人；本 CR 不改 `listeners.go`、不改 `packages/`（前端对未知 type 为 no-op，SDD §1.3 已核）。今后只允许**加字段**，改/删键名视为破坏性变更 |
| **改动面越界**（AC-8 逐条核对） | TASK-08 用 `git diff --name-only` 与 FR-10 声明集合 + §0 审批确认的 `pkg/protocol/events.go` 逐条比对；越界文件当场回退。硬断言：零迁移、`pkg/db/queries/**`、`pkg/db/generated/**`、`tools/**`、`packages/**` 零改动 |
| **回写期漏登记两项 PRD 偏离** | 已固化为 TASK-08 完成标志的一条（写入 `traceability.yml`/回写清单），不依赖会话记忆 |

**整体回滚粒度**：本 CR 无 DDL、无数据迁移、无 outbox/队列表，全部改动 = 2 个新文件 + 6 处最小挂钩 + 测试。回滚 = revert 对应 commit（发布侧与消费侧可分别独立回滚：只 revert `crsync.go` 挂钩 ⇒ 提醒器订阅在但永不触发；只 revert wiring ⇒ 事件发布但无订阅者）。

# 5. 验收与发布策略

## 5.1 发布前 checklist（= TASK-08 完成标志）

在 multica worktree（`repo=multica` 的 `worktreePath`）执行：

1. **编译与静态检查**：`cd server && go build ./...`；`go vet ./pkg/protocol/ ./internal/governance/ ./internal/integrations/lark/ ./cmd/server/`；
2. **本 CR 专项真库测试**（C6 口径，须见 `--- PASS`，`--- SKIP` 视为未测）：
   - `go test ./pkg/protocol/ -run ApprovalGate -v -count=1`
   - `go test ./internal/governance/ -run 'ApprovalGate' -v -count=1`
   - `go test ./internal/integrations/lark/ -run 'ApprovalReminder' -v -count=1`
3. **回归**：`go test ./internal/governance/ -count=1`、`go test ./internal/integrations/lark/ -count=1`、`go test ./cmd/server/ -count=1`；对照 CUSTOM.md「已知测试失败基线」排除既有失败，**新增失败即回归**；`http_client_test.go` 三处 `SendBindingPromptCard` 断言未被修改（`git diff` 核）；
4. **改动面核对（AC-8）**：`git diff --name-only <CR 基线>...HEAD` 与 FR-10 集合 + `pkg/protocol/events.go` 逐条比对；零迁移、`pkg/db/queries`/`generated`/`tools`/`packages` 零改动；
5. **台账**：`CUSTOM.md` 顺延新增一行（当前最大条目 #52，落码时以彼时 CUSTOM.md 现状为唯一事实源），"合并注意"列含 SDD §7.3 列出的五项；
6. **回写期偏离登记**：§0 两项 PRD 偏离写入回写清单（`writeback-prd-sdd` 期以 revision 修订 PRD FR-10 与 §4.4）。

## 5.2 AC 覆盖归属（13 项，出自 SDD §7.4）

| AC | 主责 TASK |
|---|---|
| AC-1 触发条件（四门禁 × 合法转换各一次） | TASK-03 |
| AC-2 误触发隔离 | TASK-03 |
| AC-3 有效绑定收件人各一张卡 + 双层去重 | TASK-06 |
| AC-4 四类不发送各留可区分原因 | TASK-06 |
| AC-5 卡片最小内容 + CTA + 基地址缺失零发送 | TASK-04（模板/CTA 断言）、TASK-06（`app-url-missing`） |
| AC-6 Web 审批链路行为不变 | TASK-08（既有 `approval*_test.go`/`project_gates_test.go` 原样通过） |
| AC-7 三类日志字段 + 失败/跳过下无回滚 | TASK-05（字段口径）、TASK-06（`failed`/`skipped` 落点） |
| AC-8 改动面与零改动边界 | TASK-08 |
| AC-9 测试覆盖面 | TASK-03 + TASK-06 + TASK-08（汇总核对） |
| AC-10 跨 workspace 负向 + 载荷伪造负向 | TASK-06 |
| AC-11 非阻塞（回调零 I/O + 阻塞替身下响应不延迟） | TASK-05（回调零调用）、TASK-07（端到端阻塞替身） |
| AC-12 飞书未启用形态 | TASK-05（`feishu-disabled` 判定）、TASK-07（wiring 形态） |
| AC-13 panic 自恢复 + `overloaded` 丢弃 | TASK-05 |

本计划**不代替测试报告**：AC 的最终取证归 `write-test-report`，此表只定"哪个 TASK 必须把该 AC 的测试写出来"。

## 5.3 计划期已核实的代码事实（供评审复核，均在 multica worktree 当场执行）

| 事实 | 位置 |
|---|---|
| `APIClient` 接口 + `stubAPIClient` 全套 stub 方法（新方法须两侧都补） | `internal/integrations/lark/client.go:20`、`:362-414` |
| `SendBindingPromptCard` 传输段（helper 提取的原文，含 `receive_id_type=open_id`、`isTokenError`→`invalidateToken`） | `internal/integrations/lark/http_client.go:467-504` |
| helper 依赖的既有私有方法 | `http_client.go`：`tenantAccessToken:189`、`resolveBaseURL:248`、`invalidateToken:258`、`doJSON:1116`、`isTokenError:1155`、`bindingPromptTemplate:1225` |
| `InstallationService.GetInWorkspace` + `DecryptAppSecret` + `ErrInstallationNotFound` | `internal/integrations/lark/installation.go:110`、`:96`、`:131` |
| `installationCredentialsFor(inst, resolver)` / `CredentialsResolver` | `feishu_channel.go:104` / `outbound.go:159` |
| `Installation` 字段（`WorkspaceID`/`Status`/`AppID`/`TenantKey`/`Region` 均在结构体上，`config` 已由上游解码） | `store.go:42-59` |
| `applyStatus` 既有 `SELECT status …`（扩列点）与唯一可信分支 | `internal/governance/crsync.go:396-408`、`:435` |
| `OutboxEvent` 字段（`CRID`/`EventKind`/`CommitSHA`/`FromStatus`/`ToStatus`） | `crsync.go:86-99` |
| `EventCRUpdated` 共享常量先例（本 CR 常量的同构落点） | `pkg/protocol/events.go:191-196`；别名 `governance/crsync.go:48` |
| `events.Event` 字段与 `Bus.Subscribe/Publish/SubscribeAll` | `internal/events/bus.go:9-22`、`:52`、`:60`、`:70` |
| `NewRouterWithOptions(pool, hub, bus, …)` — wiring 处 `pool`/`bus` 均在作用域；lark 条件块 `if larkKey…:468` / `else:639` | `cmd/server/router.go:317`、`:468`、`:502`、`:639` |
| `cr.shell_issue_id` 为可空 `UUID REFERENCES issue(id) ON DELETE SET NULL` | `migrations/362_aifirst_cr_projection.up.sql:23` |
| pgx v5.9.2 `pointerPointerScanPlan`（`*string` 目标可承接 NULL → nil，扩列无需新 import） | `go.mod:18` + `pgx@v5.9.2/pgtype/pgtype.go:491-515` |
| `util.UUIDToString` / `util.ParseUUID`（lark 包已 import `internal/util`） | `internal/util/pgx.go:41`、`:19`；`lark/ids.go` |
| lark 包 DB 测试 helper 走 `t.Skipf`（假绿风险来源） | `internal/integrations/lark/channel_store_scope_test.go:21-31` |
| `pgxpool.New` **不预建连接**（`defaultMinConns` / `defaultMinIdleConns` 均为 0，idle 资源创建在后台 goroutine）⇒ 「非 nil 但连不通的真池」可确定性构造，构造期零连接尝试、零 error | `pgx@v5.9.2/pgxpool/pool.go:19-21`、`:212`、`:335-338` |
| `Pool.Close()` 之后取连接返回 `puddle.ErrClosedPool`（`"closed pool"`）—— 查询**报错而非 panic**，可用于确定性强制 DB 失败分支 | `pgx@v5.9.2/pgxpool/pool.go:599`（`p.p.Acquire` 直传 err）、`puddle/v2@v2.2.2/pool.go:23`、`:371` |
| `(*pgxpool.Pool).Stat().AcquireCount()` 存在（有真库时的「零查询」可执行证据） | `pgx@v5.9.2/pgxpool/stat.go:18` |
| lark 包中**触库的四个测试文件 `t.Parallel()` 计数均为 0**（`binding_token_test.go`、`channel_cleanup_test.go`、`channel_store_rebind_test.go`、`channel_store_scope_test.go`）；包内 117 处 `t.Parallel()` 全在不触库的用例里 ⇒ 触库用例**包内**串行。**但这不足以做“测试内改 `public` schema”的安全前提**（下一行给出反例；dev-plan 评审 attempt 1 BL-2，见 §5.6） | `grep -c 't.Parallel()' internal/integrations/lark/*_test.go` |
| `scripts/test-go.sh` 把**全部 regular packages 交给同一次 `go test`**（`go list ./...` 除 `pkg/agent`）且**不传 `-p`/`-parallel`** ⇒ 包级并行度 = 默认 GOMAXPROCS、所有包共享同一个 `DATABASE_URL` ⇒ 任何测试内对 `public` schema 的改动（如 `ALTER TABLE … RENAME`）都有**跳包并发**风险，且进程被强杀时 `t.Cleanup` 无法恢复 | `scripts/test-go.sh:28-38`（`-p 2 -parallel 2` 仅附在 `./pkg/agent/...` 那一行） |
| `pgconn.Config.RuntimeParams` 可以**会话默认值**下发 `search_path`（字段注释直接以 `search_path` 为例）；`pgxpool.ParseConfig` → `cfg.ConnConfig.RuntimeParams["search_path"] = …` → `pgxpool.NewWithConfig` 可得一个**只影响自己连接**的专用池（`pgx.ConnConfig` 嵌入 `pgconn.Config`；DSN 中非连接参数的键也一律进 RuntimeParams） ⇒ TASK-06 验收 7② 的隔离失败注入可实现 | `pgx@v5.9.2/pgconn/config.go:51`、`:340-377`；`pgx/v5/conn.go:22-23`；`pgxpool/pool.go:122-123`、`:361` |
| **仓内已有的私有 schema 命名先例（= TASK-06 本轮直接复用的形态）**：`suffix := fmt.Sprintf("%d_%d", time.Now().UnixNano(), rand.Uint32())`（`math/rand/v2`）+ **固定前缀**→ `pgx.Identifier{schema}.Sanitize()` → `CREATE SCHEMA <ident>` 与 `t.Cleanup` 里 `DROP SCHEMA IF EXISTS <ident> CASCADE`（失败只 `t.Logf`）。**名称里没有 `t.Name()`、没有任何变长输入** ⇒ 长度按构造有界（固定前缀 + ≤ 19 B unixnano + `_` + ≤ 10 B uint32），截断与重跑冲突两类问题同时消失 | `cmd/migrate/migrate_invalid_index_test.go:20-30`（锚点）；**全仓共 10 处 / 6 个测试文件**（`grep -rn 'fmt.Sprintf("%d_%d", time.Now().UnixNano(), rand.Uint32())' --include=*_test.go server/` → 10 行）：`migrate_concurrent_test.go:121`、`migrate_drift_finding_test.go:49`、`migrate_invalid_index_test.go:20`/`:135`/`:252`/`:380`/`:545`、`migrate_mul5999_index_retry_test.go:170`、`migrate_redundant_indexes_test.go:22`、`migrate_workspace_seam_test.go:32` |
| 仓内已有 `*pgconn.PgError` 的 `errors.As` 用法先例（TASK-06 的 `42703` 自检与 `42501` 退化同形）；仓内尚无 `42501`/`insufficient_privilege` 引用（本 CR 首次引入，取 PostgreSQL 标准错误码） | `internal/governance/gate_projection.go:160`、`internal/handler/agent.go:1295`、`:1910`；`grep -rn '42501\|insufficient_privilege' server/` 零命中 |

**一处 SDD 内部不一致，已由 dev-plan 评审定案（采纳本计划口径）**：SDD §2 术语表曾把载荷字段写作“`shell_issue_id *string`（JSON `omitempty`）”，与 §3.2.1 结构体、§3.2.1 不变量 6 的 canonical 形状、§7.4 golden JSON 用例三处一致要求的「键恒在、可为 `null`」相矛。评审结论：**采纳不加 `omitempty`**（canonical JSON 同时是 WS 帧契约，键恒在才对客户端稳定），§2 那句括注按笔误处理——上游回修已将 SDD §2 同步纠正（见 sdd.md §9 上游设计回修行）。TASK-01 / TASK-03 的 golden 断言不需变动（本就按三处一致写的）。

同时采纳的口径②：`lark` 包内 `approvalGateStageLabels + stageLabel()` 收敛（过滤与展示语义等价，未命中仍回退 status），已写进 SDD §4.3 并同步 §4.1 伪代码与 §7.1；**边界**：只在 lark 包内，`governance` 侧的 `approvalGateStatuses` 保持独立声明。

## 5.4 发布形态

无 feature flag、无新环境变量、无新配置项（FR-11）：启用条件全部由既有事实判定（`MULTICA_LARK_SECRET_KEY` / owner-admin 角色 / 有效飞书绑定 / 项目链 workspace 一致 / `appURL`）。发布 = multica 单仓 merge；`tools` 与 knowledge-base 侧只有 CR 产物与台账，无运行时改动。

## 5.5 架构评审（cycle 2）三条非阻塞建议的处置

`review-annotations/sdd.yml#suggestions` 三条建议不构成 blocker，但均落在**计划层（TASK 验收条件）**，本轮一并消化，逐条给落点；**三条均未改 sdd.md**（已审批且 digest 绑定，改动会再次触发新审查周期）。

| # | 建议 | 处置 | 落点 |
|---|---|---|---|
| 1 | 人工审批时显式确认 AC-4 场景级口径；实施测试不得把混合 workspace 的零发送描述成收件人级 reason | 已在 cycle 2 重签时确认（§0 第 3 项，非 PRD 偏离）；TASK-06 已有反向断言禁止收件级 `no-approver` | plan §0；TASK-06 验收 4 情形①(a)(b) + 反向断言 |
| 2 | 零 DB 断言面对具体类型 `*pgxpool.Pool` 时**不得声称存在接口替身**；可用 nil 前置分支或 `Stat().AcquireCount()` 前后不变 | 删除全部「pool 替身零调用」措辞，改为三种**可执行**取证：① `Pool: nil`（结构上不可能发生查询）；② 非 nil 但连不通的真池 + 断言「日志中不存在任何 `result=failed` 行」（若真尝试过查询，连接失败必留下一条 `failed`，因此“无 failed”是零 DB 的**正向**证据）；③ 有真库时附加 `pool.Stat().AcquireCount()` 前后不变。强制 DB 报错分两种：事件级（项目链）用已 `Close()` 的**独立**真池（`ErrClosedPool` 是报错而非 panic）；收件人级（绑定候选查询）用**私有 schema 遮蔽 + 专用池 `search_path`**（原 RENAME 方案已废，见 §5.6 BL-2） | TASK-05 验收 1/2/5/8、TASK-06 验收 7、TASK-07 验收 2/3③ |
| 3 | `approvalGateStageLabels` 若实现为包级 map，应不导出且运行期零写入；若要严格兑现“无包级可变全局状态”可改单个 switch helper | **保留 SDD §4.3 已定的 map + `stageLabel()` 形态**（不改已审批 SDD，也不制造计划层对 SDD 的新偏离），取建议的**前半句**：把 TASK-05 的“不新增包级可变全局状态”精确化为“不导出 + 初始化后只读、运行期零写入”，并加一条**静态断言**守住 | TASK-05 要点 10/11、验收 8 |

建议 2 涉及的三条 pgx 事实（不预连、`ErrClosedPool` 报错、`Stat().AcquireCount()`）已当场核实并进 §5.3 表。“触库用例集体不 `t.Parallel()`”也已核实，**但已不再充当安全前提**——dev-plan 评审 attempt 1 指出包内串行推不出跳包串行，TASK-06 验收 7② 已改为不改 `public` schema 的私有 schema 遮蔽方案（见 §5.6 BL-2）。

## 5.6 开发计划评审（cycle 1 / attempt 1 = BLOCK）两条 blocker 的定点回修

`review-annotations/dev-plan.yml`：verdict `block`、`repair-target=write-dev-plan`、subject `6efbaaa9…`。两条均落在**验收取证形态**：**sdd.md / prd.md 零改动**，实现面与依赖方向不变。

### BL-1 — TASK-05 验收自相矛盾（不可满足）

- **根因**：要点 2 规定“`Pool`/`Client`/`Credentials` 任一为 nil 时构造期必记一条 Error”，验收 1(d) 又把“无 Error 日志”当作零查询证据——两条 `Error` 级日志（构造期 dependency-missing / 异步体 panic 兜底）**无可区分字段**，只能粗粒度写“有/无 Error”，于是两条要求直接冲突。
- **回修**：给这两条日志加一个**诊断字段 `phase`**——`phase=construct`（附 `missing`）与 `phase=panic-recovered`，均**不带 `result` 字段**；验收 1 改为“**允许并正向断言**构造期 Error（`missing` 恰等于该子用例置 nil 的那一项，(c) 子用例为 0 条），**只禁** `result=failed` 与 `phase=panic-recovered`”。
- **不越红线**：`phase` 是诊断字段而非结果分类——**不进** PRD FR-8.2 的 9 项 `reason` 闭集、不新增第 10 个 reason、不改 SDD §4.6 的四类结果口径。
- **落点**：TASK-05 要点 2 / 5 / 9（末段新增两条非 result 类 Error 的口径）、验收 1 / 4；同家族**预防性**修正 TASK-07 验收 2（原“无 Error 级 recover 日志”同样模糊，且那里三依赖均为 nil、构造期 Error 必现）。

### BL-2 — TASK-06 验收 7② 改 `public` 表名造错不安全

- **根因**：原安全前提（lark 包内触库用例均不 `t.Parallel()`）只覆盖**包内**并行；`scripts/test-go.sh` 把全部 regular packages 交给同一次 `go test`、默认包级并行且共享同一个 `DATABASE_URL`（§5.3 新增行），重命名窗口内其它包可访问 `channel_user_binding`；且测试进程被强杀/崩溃时 `t.Cleanup` 无法恢复表名。
- **回修**：废弃 `ALTER TABLE … RENAME`，改为**私有 schema 遮蔽 + 专用池 `search_path`**：唯一命名的私有 schema 内只建一个**列不兼容的同名遮蔽表**，提醒器拿一个 `RuntimeParams["search_path"] = "<shadow>, public"` 的**专用池**——`cr`/`issue`/`project`/`workspace`/`member`/`channel_installation` 仍解析到 `public`（前两跳确定成功），只有第三跳命中遮蔽表并在**语句准备期**报 `42703`。
- **为何更安全**：① `public` 零改动，其它包的会话看不见该 schema；② 失败与表中有无数据无关，确定性可重复；③ **正确性与隔离性不依赖 `t.Cleanup` 被执行**——强杀后的遗留物只是一个惰性的私有 schema（对照被重命名的 `public` 表：遗留即全局破坏）。
- **落点**：TASK-06 验收 7②（四步取证 + 断言 + 取证前提自检）、“零改动”段新增“禁改 `public` schema 任何对象”硬约束；§5.3 新增两条事实并修正 `t.Parallel()` 那行的结论。

**评审认可、本轮未动的部分**：pgx 三条事实（不预连 / `ErrClosedPool` / `Stat().AcquireCount()`）、依赖拓扑无悬空无环、8 TASK / 55h / 3 里程碑、接口契约与 AC 覆盖。**估算 delta = 0**：BL-1 多两个结构化日志字段，BL-2 把一条 DDL 换成两条 DDL + 一个专用池（均在 TASK-06 已预算的真库造数面内）。

## 5.7 开发计划评审（cycle 1 / attempt 2 = BLOCK）两条新 blocker 的定点回修

`review-annotations/dev-plan.yml`：verdict `block`、`repair-target=write-dev-plan`、subject `6ae1fffb…`、attempt **2/3**。评审已**认可 §5.6 两条的核心修法**（`phase` 区分与私有 schema 遮蔽）；本轮两条均是那两个修法**自身的细节缺口**。**sdd.md / prd.md 零改动**，实现面与依赖方向不变。

### BL-1 — TASK-05 的 `Error` 契约仍自相矛盾

- **根因**：要点 3（`Register(bus == nil)` 记 Error）与要点 9 末段（`construct` / `panic-recovered` 两条是“本 TASK 唯一的 `Error` 级输出”）两条无法同时成立。§5.6 BL-1 只把两条 result-less Error 做了区分，**漏数了 `Register(nil)` 这第三条**。
- **回修**：不新开体系，把它**并入已有的 `phase` 诊断字段体系**——新增第三个互斥值 `phase=register`（附 `missing=bus`，不带 `result`）；要点 9 末段改为一张**三行闭集表**（`construct` / `register` / `panic-recovered`），“唯一”的准确说法变为“这张表就是闭集”。
- **计数口径（评审点名要求核对的邨作）**：明写所有“恰一条”均为**按 `phase` 值分别计数**（非 Error 总行数），因此 attempt 1 定下的 `construct` / `panic-recovered` 断言数值**不受本次扩集影响**；并在验收 1 反向断言里补上“(a)~(d) 均传真 bus ⇒ `phase=register` 行数恒为 0”。
- **新增一条可执行验收**：验收 1 子用例 **(e)**——三依赖健康 + `Register(nil)` ⇒ 恰一条 `phase=register` 且 `missing == "bus"`、`phase=construct` 为 0；再向**另建的真 bus** 发一条真事件，断言**零 `result=*` 行**（直接兑现“不订阅”，而非“订阅了一半”）。原本要点 3 的行为无任何验收看着，这是顺手堵住的覆盖缺口。
- **不越红线**：`phase` 仍是诊断字段而非结果分类——**不进** PRD FR-8.2 的 9 项 `reason` 闭集、不新增第 10 个 reason、不改 SDD §4.6（SDD §4.6 本就只定义四类结果日志，全文无 `phase`）。
- **落点**：TASK-05 要点 3 / 要点 9 末段（三行闭集表 + 计数口径）/ 验收 1（计数口径 + 反向 + 新子用例 (e)）/ 验收 4；同家族同步 TASK-07 验收 2（三值闭集 + `phase=register` 恒 0 + 计数口径）。

### BL-2 — TASK-06 私有 schema 名不保证唯一（63 字节上限）

- **根因**：§5.6 BL-2 定的名字 `ac7_<sanitize(t.Name())>_<pid>_<unixnano>` 把 **变长的 `t.Name()`** 放在中间，PostgreSQL 标识符 63 字节上限会静默截断**尾部**——而尾部正是唯一性的全部来源。一旦截断，强杀遗留同名 schema 后重跑会 `CREATE SCHEMA` 冲突，**恰好推翻§5.6 自己的结论**（“正确性与隔离性不依赖清理被执行”以名称真唯一为前提）。
- **回修（不自创算法，直接复用仓内先例）**：改成 `"ac7_binding_shadow_" + fmt.Sprintf("%d_%d", time.Now().UnixNano(), rand.Uint32())` + `pgx.Identifier{schema}.Sanitize()`（`cmd/migrate` 下 **10 处 / 6 个测试文件**同型先例，已核实并进 §5.3）。**`t.Name()` 彻底退出名称**：名字里再没有任何变长输入，长度按构造有界（前缀 19 B + ≤ 19 B + 1 + ≤ 10 B = **最长 49 B**，恒 ≤ 63），“截断”这一类问题不是被断言盯住而是**被消除**。名称只计算一次，CREATE / `search_path` / DROP 三处强制复用同一个变量（DDL 用 `schemaIdent`，`search_path` 用裸 `schema`）。
- **断言（评审点名）**：静态 `len(schema) <= 63`（Go `len(string)` 即 UTF-8 字节长度；字母表 `[a-z0-9_]` 均单字节）+ `^[a-z][a-z0-9_]*$`；**另加一条比长度算术更直接的直证**——CREATE 后回读 `SELECT count(*) FROM pg_namespace WHERE nspname = $1`（参数为 `schema` 原值）= 1，让用例当场证伪，而不是把“63 字节”当作记忆断言写进计划（工程纪律 4：事实断言先核实，无法当场核实的就下沉成用例内断言）。
- **同时落入评审的非阻塞建议**：`CREATE SCHEMA` 报 `42501`（`insufficient_privilege`）时 `t.Skipf`，其余 err 一律 `t.Fatalf`（不静默降级）；**硬门禁原样保留**——`--- SKIP` 只表示未测，不得据此标 TASK done。
- **落点**：TASK-06 验收 7② 步骤 1（命名算法 + 四条子约束 + 42501 退化）/ 步骤 2（`search_path` 复用 `schema` 变量）/ 步骤 4（`DROP SCHEMA IF EXISTS <schemaIdent> CASCADE`）/ 取证前提自检（拆成四条，新增后两条）；§5.3 新增 2 行已核实事实。

### 本轮自查（评审剩下 1 次回修额度，主动排同类隐患）

| 自查面 | 方法 | 结果 |
|---|---|---|
| 其它以 `t.Name()` 派生的 DB 标识符 | `grep -rn 't\.Name()' plan.md tasks/` | 修前全仓只有 TASK-06:87 一处把 `t.Name()` 当**标识符构成成分**（已修），无漏网。**修后同一条 grep 仍会命中 7 处，但全为叙述性引用**（§5.3 先例行、§5.7 BL-2 根因/回修、本自查行、变更记录、TASK-06:87 废弃形态引用 + :88 “不再进入名称”声明），无任何一处仍将它用作名称成分——复审时请按此口径对账 |
| 其它变长拼名（pid / unixnano / rand / sanitize） | `grep -rn 'sanitize\|unixnano\|Getpid\|rand\.' plan.md tasks/` | `pid`/`Getpid` 已从方案中**彻底移除**（仅存于§5.7 根因与 TASK-06:87 的废弃形态引用）；`UnixNano`/`rand.Uint32()` 仍在用，但两者均是**定长上界**的十进制数字（≤ 19 B / ≤ 10 B）而非变长输入，不引入 63 B 风险；`sanitize` 仅剩废弃形态引用（新方案用的是 pgx 自带的 `pgx.Identifier{}.Sanitize()`，不手写 sanitize） |
| 其它受 63 字节约束的对象名 | 通读 TASK-06 验收全文 | 遮蔽表名是**固定**字面 `channel_user_binding`（必须同名才能遮蔽，不得动）；其余造数只写**数据列**（`workspace.slug` 等）而非标识符，不受 63 B 约束 |
| `phase` 口径引用点是否全部同步三值闭集 | `grep -rn 'phase' tasks/`（修后 13 行 / **7 个引用点**） | TASK-05 要点 2（:41）、要点 3（:42，本轮新增）、要点 5（:44）、要点 9 末段（:55-62 的三行闭集表 + 计数口径）、验收 1（:70-76）、验收 4（:81）；TASK-07 验收 2（:61）——已逐点核对并同步（TASK-07 那处本轮新增三值声明与 `phase=register` 恒 0） |
| “唯一 / 恰一条”这类计数断言是否仍有口径歧义 | 通读 TASK-05/07 全部日志断言 | 已在 TASK-05 要点 9 末段与验收 1 首行、TASK-07 验收 2 尾句三处明写“按 `phase` 值分别计数” |
| `Error` 闭集与 SDD 是否冲突 | `grep -n 'phase' sdd.md` | 零命中——SDD §4.6 只定义四类**结果**日志，`phase` 纯属计划层诊断字段，三值扩集不触发 SDD 偏离 |

**估算 delta = 0（55h / 8 TASK / 3 里程碑均不变）**：BL-1 是一个已有诊断字段多一个枚举值 + 一条三行级的子用例（在 TASK-05 已预算的日志断言 harness 内）；BL-2 是把一行字符串拼接换成仓内先例的同长写法 + 两条断言（均在 TASK-06 已预算的真库造数面内）。无新增文件、无新增实现面、无依赖方向变更，`tasks/_index.yml` 无需重生。

# 6. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-25 | v0.1.0 | Ray | 初始计划：M1 契约与发布侧 / M2 传输与提醒器 / M3 装配与收口，8 TASK，55h；固化审批期两项确认与回写期 PRD revision 登记；记录一处 SDD 内部不一致的处置口径（`shell_issue_id` 无 `omitempty`） |
| 2026-08-26 | v0.1.1 | Ray | 随 **上游设计回修**（dev-plan 评审 verdict=block、route=upstream、repair-target=`write-tech-design`）同步：① 风险表 typed-nil 行改正——原“双保险（TASK-05 + TASK-07）”不成立，验证点唯一归 TASK-07 wiring 层（并记录已核实的不对称：`LarkInstallations` 是具体指针、`LarkAPIClient` 是接口）；② §5.3 那处“请证审确认”改为已定案（两项口径均采纳，`omitempty` 括注已在 SDD §2 纠正；阶段名映射收敛已写进 SDD §4.3 并附边界）；③ TASK-03 AC-2 零发布矩阵改为**按路径选 liveness probe**（`trace` 走 `ingestTrace`、不进 `publish`，不得断言 `cr:updated > 0`）；④ TASK-05 依赖缺失用例改为**逐依赖隔离四子例**、删除 typed-nil 断言；⑤ TASK-06 AC-4 情形①改为**事件级 `no-approver` + 混合 workspace 零发送**两条互补断言（不改 PRD、不加第 10 个 reason）；⑥ TASK-07 验收 3 升为执行断言。**估算 delta = 0（55h 不变）**：均为验收条件与取证形态改写，无新增文件、无新增实现面；TASK-06 新增的两个 workspace 造数场景复用同一 fixture helper（该 TASK 已为 AC-4 其余三情形预算真库造数），故 `tasks/_index.yml` 与 `totalEstimateHours: 55` 未动 |
| 2026-08-26 | v0.1.2 | Ray | **本轮（cycle 2 审批后重跑 `write-dev-plan` / `write-dev-tasks`）**：① §0 前置事实刷新——SDD 换为上游回修后的 `39999101…`/93545 B，新增「架构评审」行（sdd.yml pass / cycle 2 attempt 1），审批行换为重签后的 `OldBoy405`/`10:35:47`/`9cfdd8e4…`（并记旧审批因 `EVIDENCE_DRIFT` 失效）；② 审批期确认由两项扩为三项（新增 AC-4 场景级口径，**不计入回写期 PRD revision 清单**，因 `no-approver` 本在 FR-8.2 枚举与 §4.4 事件级 partition 内）；③ 新增 §5.5：架构评审 cycle 2 三条非阻塞建议的逐条处置与落点（建议 2 删除 TASK-05/06/07 中全部“pool 替身零调用”措辞——`*pgxpool.Pool` 是具体类型、无接口替身可言；建议 3 把包级 map 的“不导出 + 运行期零写入”写成静态断言）；④ §5.3 新增 4 条当场核实的代码事实（`pgxpool.New` 不预连、`ErrClosedPool` 为报错非 panic、`Stat().AcquireCount()` 存在、触库用例集体不 `t.Parallel()`）。**估算 delta = 0（55h、8 TASK、3 里程碑均不变）**：本轮全部改动为取证形态与前置事实刷新，无新增文件、无新增实现面、无依赖方向变更，`tasks/_index.yml` 无需重生 |
| 2026-08-26 | v0.1.3 | Ray | **开发计划评审 cycle 1 / attempt 1 = BLOCK（repair-target=`write-dev-plan`）的两处定点回修**，新增 §5.6 逐条记根因/回修/落点：① **BL-1**（TASK-05 验收 1(d) 与要点 2 自相矛盾、不可满足）——为构造期 dependency-missing Error 与 panic 兜底 Error 加可区分诊断字段 `phase=construct`（+`missing`）/ `phase=panic-recovered`，验收 1 改为“允许并正向断言构造期 Error、只禁 `result=failed` 与 `phase=panic-recovered`”，验收 4 同步精确化（`phase` 不进 FR-8.2 的 9 项 reason 闭集、不改 SDD §4.6）；预防性修正 TASK-07 验收 2 的同型模糊措词；② **BL-2**（TASK-06 改 `public` 表名不安全）——废弃 `ALTER TABLE … RENAME` + `t.Cleanup`，改为**私有 schema 遮蔽 + 专用池 `search_path`** 的确定性失败注入（`public` 零改动、失败在语句准备期与数据无关、正确性不依赖清理执行），并在“零改动”段硬写禁改 `public`；③ §5.3 新增 2 条当场核实的事实（`scripts/test-go.sh` 包级并行与共享 `DATABASE_URL`、`pgconn.Config.RuntimeParams` 支持 `search_path`）并修正 `t.Parallel()` 那行的结论（不再充当安全前提）。**估算 delta = 0（55h、8 TASK、3 里程碑均不变）**：两处均为验收取证形态改写，无新增文件、无新增实现面、无依赖方向变更，sdd.md / prd.md 零改动，`tasks/_index.yml` 无需重生 |
| 2026-08-26 | v0.1.4 | Ray | **开发计划评审 cycle 1 / attempt 2 = BLOCK（repair-target=`write-dev-plan`，subject `6ae1fffb…`）的两处定点回修**，新增 §5.7 逐条记根因/回修/落点 + 本轮自查表：① **BL-1**（TASK-05 要点 3 的 `Register(bus=nil)` Error 与要点 9 末段“两条是唯一 Error 级输出”互斥）——把 `Register(nil)` **并入已有 `phase` 诊断字段体系**，新增第三个互斥值 `phase=register`（附 `missing=bus`、不带 `result`），要点 9 末段改为三行**闭集表**（`construct`/`register`/`panic-recovered`），并明写所有“恰一条”均为**按 `phase` 值分别计数**（故 attempt 1 定下的数值不受扩集影响）；顺手补上原本无人看守的覆盖缺口：验收 1 新增子用例 **(e)**（`Register(nil)` → 恰一条 `phase=register` + 另建真 bus 发事件后**零 `result=*` 行**，直接证明“不订阅”）；验收 4 与 TASK-07 验收 2 同步三值闭集与计数口径。**不越红线**：`phase` 仍是诊断字段，不进 FR-8.2 的 9 项 `reason`、不新增第 10 个、不改 SDD §4.6（已核实 sdd.md 全文无 `phase`）；② **BL-2**（TASK-06 私有 schema 名 `ac7_<sanitize(t.Name())>_<pid>_<unixnano>` 未守 PostgreSQL 标识符 63 字节上限、长测试名会静默截断尾部唯一后缀）——**`t.Name()` 与 `pid` 一并退出名称**，直接复用仓内已有先例 `"ac7_binding_shadow_" + fmt.Sprintf("%d_%d", time.Now().UnixNano(), rand.Uint32())` + `pgx.Identifier{}.Sanitize()`（`cmd/migrate` 下 **10 处 / 6 个测试文件**同型，已核实并进 §5.3），名称里再无变长输入 ⇒ 长度按构造有界（**最长 49 B**），截断这一类问题被**消除**而非仅被断言盯住；名称只算一次、CREATE/`search_path`/DROP 强制复用同一变量；断言补 `len(schema) <= 63` + `^[a-z][a-z0-9_]*$`，并加一条**比长度算术更直接的直证**——CREATE 后 `pg_namespace` 回读该名恰 1 行（当场证伪服务端截断，不把“63 字节”写成记忆断言）；评审的非阻塞建议一并落地：`CREATE SCHEMA` 报 `42501` 时 `t.Skipf`、其余 err `t.Fatalf`，**硬门禁不变**（`--- SKIP` 视为未测、不得据此标 TASK done）。③ §5.3 新增 2 条当场核实的事实（`cmd/migrate` 私有 schema 命名先例 7 处；`*pgconn.PgError` 的 `errors.As` 仓内先例 + `42501` 仓内零引用故取 PostgreSQL 标准码）。**估算 delta = 0（55h、8 TASK、3 里程碑均不变）**：两处均为验收取证形态与日志字段口径改写，无新增文件、无新增实现面、无依赖方向变更，sdd.md / prd.md 零改动，`tasks/_index.yml` 无需重生 |

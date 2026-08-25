---
id: CR-2026-051-plan
type: PLAN
cr-ref: CR-2026-051
sdd-ref: "change-requests/CR-2026-051/sdd.md"
target-version: tbd
status: draft
created: 2026-08-25T23:20:00+08:00
updated: 2026-08-26T00:30:00+08:00
---

# 0. 输入与前置事实（落笔前当场核实）

| 项 | 值 |
|---|---|
| PRD | `change-requests/CR-2026-051/prd.md`，sha256 `b64a92cfe182…`，33911 B（LF 口径，磁盘即 LF） |
| SDD | `change-requests/CR-2026-051/sdd.md`，sha256 `7bbcf822c9d5…`，81407 B（LF 口径，磁盘即 LF） |
| 架构审批 | `approval.yml#tech-design`：approver `Ray`、`2026-08-25T23:05:49+08:00`、`via: crctl-approve`、evidence-digest `a44a0416…`、target-status `tech-design-reviewed`；`traceability.yml#reviews.tech-design` verdict `pass`、attempt 2、blocker 0 |
| CR 状态 | 进入本 Skill 前 `crctl status` = `tech-design-reviewed`，`crctl next` = `write-dev-plan` |
| operational workspace | `…\.rayai-worktrees\knowledge-base\requirement\CR-2026-051`（`crctl workspace inspect` 原样值，三仓 resources 全 `healthy`、`dirty=false`） |
| 落码仓 | `multica` → `…\.rayai-worktrees\multica\requirement\CR-2026-051`（HEAD `93aa7c5bd`）。`tools` 仓本 CR 零改动、只读 |
| 计划内引用的代码事实 | 全部在上述 multica worktree（分支 `requirement/CR-2026-051`）当场核实，不照抄 SDD 措辞（清单见 §5.3） |

**审批期两项确认（delivery-agent 转达，审批时无异议，按 SDD 主题采纳）**：

1. **FR-10 改动面 +1 文件**：`server/pkg/protocol/events.go`（+1 常量 +1 载荷类型）纳入合法改动集（SDD §5 DD-4 主方案生效，备选 1 map/JSON envelope 作废）。
2. **事件级 `failed` 日志无 recipient 字段**：SDD §4.6 第 5 条的可观测性加法细化采纳。

两项都是对**已审批 PRD 字面**的加法（FR-10 改动清单 / §4.4 可观测性表），因此列为回写期偏离项：`writeback-prd-sdd` 时须以 revision 修订 PRD FR-10 与 §4.4，并注明"结论是否受影响"（先例：CR-2026-050 TASK-02 的 AC-05 改判口径）。本计划把该登记动作固化为 TASK-08 完成标志的一条，不留在人的记忆里。

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

**一处 SDD 内部不一致，已由 dev-plan 评审定案（采纳本计划口径）**：SDD §2 术语表曾把载荷字段写作“`shell_issue_id *string`（JSON `omitempty`）”，与 §3.2.1 结构体、§3.2.1 不变量 6 的 canonical 形状、§7.4 golden JSON 用例三处一致要求的「键恒在、可为 `null`」相矛。评审结论：**采纳不加 `omitempty`**（canonical JSON 同时是 WS 帧契约，键恒在才对客户端稳定），§2 那句括注按笔误处理——上游回修已将 SDD §2 同步纠正（见 sdd.md §9 上游设计回修行）。TASK-01 / TASK-03 的 golden 断言不需变动（本就按三处一致写的）。

同时采纳的口径②：`lark` 包内 `approvalGateStageLabels + stageLabel()` 收敛（过滤与展示语义等价，未命中仍回退 status），已写进 SDD §4.3 并同步 §4.1 伪代码与 §7.1；**边界**：只在 lark 包内，`governance` 侧的 `approvalGateStatuses` 保持独立声明。

## 5.4 发布形态

无 feature flag、无新环境变量、无新配置项（FR-11）：启用条件全部由既有事实判定（`MULTICA_LARK_SECRET_KEY` / owner-admin 角色 / 有效飞书绑定 / 项目链 workspace 一致 / `appURL`）。发布 = multica 单仓 merge；`tools` 与 knowledge-base 侧只有 CR 产物与台账，无运行时改动。

# 6. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-25 | v0.1.0 | Ray | 初始计划：M1 契约与发布侧 / M2 传输与提醒器 / M3 装配与收口，8 TASK，55h；固化审批期两项确认与回写期 PRD revision 登记；记录一处 SDD 内部不一致的处置口径（`shell_issue_id` 无 `omitempty`） |
| 2026-08-26 | v0.1.1 | Ray | 随 **上游设计回修**（dev-plan 评审 verdict=block、route=upstream、repair-target=`write-tech-design`）同步：① 风险表 typed-nil 行改正——原“双保险（TASK-05 + TASK-07）”不成立，验证点唯一归 TASK-07 wiring 层（并记录已核实的不对称：`LarkInstallations` 是具体指针、`LarkAPIClient` 是接口）；② §5.3 那处“请证审确认”改为已定案（两项口径均采纳，`omitempty` 括注已在 SDD §2 纠正；阶段名映射收敛已写进 SDD §4.3 并附边界）；③ TASK-03 AC-2 零发布矩阵改为**按路径选 liveness probe**（`trace` 走 `ingestTrace`、不进 `publish`，不得断言 `cr:updated > 0`）；④ TASK-05 依赖缺失用例改为**逐依赖隔离四子例**、删除 typed-nil 断言；⑤ TASK-06 AC-4 情形①改为**事件级 `no-approver` + 混合 workspace 零发送**两条互补断言（不改 PRD、不加第 10 个 reason）；⑥ TASK-07 验收 3 升为执行断言。**估算 delta = 0（55h 不变）**：均为验收条件与取证形态改写，无新增文件、无新增实现面；TASK-06 新增的两个 workspace 造数场景复用同一 fixture helper（该 TASK 已为 AC-4 其余三情形预算真库造数），故 `tasks/_index.yml` 与 `totalEstimateHours: 55` 未动 |

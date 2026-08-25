---
id: CR-2026-051-sdd
type: SDD
cr-ref: CR-2026-051
title: IM 渠道审批接入 — 飞书审批提醒卡片（通知型 MVP） 技术设计
status: draft
created: 2026-08-25T20:34:02+08:00
updated: 2026-08-25T21:33:00+08:00
---

# 0. 输入与前置事实

| 项 | 值 |
|---|---|
| PRD | `change-requests/CR-2026-051/prd.md`，sha256 `b64a92cfe182…`（33911 B，已核） |
| CR 状态 | 进入本 Skill 前 `requirement-approved` → 已 `crctl advance --to tech-designing --trigger write-tech-design` |
| operational workspace | `…\.rayai-worktrees\knowledge-base\requirement\CR-2026-051`（`crctl workspace inspect` 原样值） |
| 目标代码仓 | `multica` → `…\.rayai-worktrees\multica\requirement\CR-2026-051`（`resources[].worktreePath`），三仓 resources 全 `healthy`、`dirty=false` |
| 架构基线 | 上述 multica worktree 根 `ARCHITECTURE.md`（**已存在，直接引用，未改**）。`tools` 仓本 CR 零改动，其 `ARCHITECTURE.md` 与本设计无关、未参考 |
| 本文引用的 multica 代码事实 | 均在上述 multica worktree（分支 `requirement/CR-2026-051`）内当场核实，非照抄 PRD 措辞 |
| 评审回修输入 | `change-requests/CR-2026-051/review-annotations/sdd.yml`：`verdict: block`，BL-1～BL-4 全 P1，`review-loop.review-tech-design.current-attempt: 1`，`subject-sha256 f56d38e9…`（= 本次修订前的 sdd.md，已当场核对一致，LF 口径） |
| 本次修订模式 | reviewLoop 回修（Skill Step 1/Step 2 自修复分支，允许 status = `tech-designing`）：按 BL-1～BL-4 逐条定点修复 + 三项评审定案落地 + 三条非阻塞建议处理；整体方案骨架不重写 |

本 SDD 只做技术方案，不改 PRD 的 FR/AC 与范围红线（设计稿 §2.2 排除项）。**一处需要审批确认的边界**：BL-4 要求事件契约必须在跨包可编译位置，落点为 `server/pkg/protocol/events.go`（+1 常量 +1 载荷类型），这比 PRD FR-10 的字面改动清单多一个文件。本 SDD **不自行改 PRD 字面**，而是把该 delta 显式列出（§5 DD-4、§6 FR-10 行、§8），供 `approve-tech-design` 确认或驳回（驳回则退化为 DD-4 备选 1）。

---

# 1. 架构概览

## 1.1 模块边界

新增**两个自研文件**（全部在 multica 仓），加**五处最小挂钩**（其中 `pkg/protocol/events.go` 为 BL-4 修复新增，见 §5 DD-4）：

```text
server/pkg/protocol/events.go                            [改：挂钩点，~2 行 —— BL-4]
  ├─ EventCRApprovalGateEntered      事件名唯一声明（governance 与 lark 共同引用）
  └─ ApprovalGateEnteredPayload      载荷类型唯一声明（canonical JSON 形状）
        ▲ 被 import（governance / lark 均已 import pkg/protocol，无新依赖方向）
server/internal/governance/crsync.go                    [改：挂钩点，~18 行]
  └─ applyStatus() 可信转换分支 → publishApprovalGateEntered()
        │ events.Bus.Publish（同步、进程内）
        ▼
server/internal/integrations/lark/approval_reminder.go   [新：自研，提醒器]
  ├─ Register(bus)                     订阅 cr:approval-gate-entered（无条件注册）
  ├─ handleEvent(e)                    ★ bus 回调：仅解析 + 信号量 TryAcquire + go
  └─ deliver(ctx, ev)                  异步：读链 → 收件人 → 逐个单次发送 → 日志
        │
        ├──► reminderReader（同文件内私有）  workspace-closed 只读链（pgx，分类用）
        ├──► installationCredentialSource   InstallationService.GetInWorkspace（凭据水化，
        │                                   workspace+channel_type 由上游查询闭合）→ DecryptAppSecret
        └──► approvalCardSender             APIClient.SendApprovalReminderCard

server/internal/integrations/lark/approval_reminder_card.go [新：自研，卡片与传输]
  ├─ ApprovalReminderParams            最小参数类型
  ├─ approvalReminderTemplate()        卡片 JSON 模板
  ├─ (*httpAPIClient) SendApprovalReminderCard()   真实传输（open_id 私聊）
  └─ (*stubAPIClient) SendApprovalReminderCard()   stub：Warn + ErrAPIClientNotConfigured

server/internal/integrations/lark/client.go              [改：挂钩点，1 行接口方法]
server/internal/integrations/lark/http_client.go         [改：挂钩点，传输段提取为私有 helper]
server/cmd/server/router.go                              [改：挂钩点，~12 行 wiring]
```

依赖方向（不新增反向依赖）：

```text
cmd/server/router.go            composition root：构造 + 订阅（在飞书密钥条件块之外）
  → integrations/lark（提醒器 + 卡片 + 传输）
  → internal/events.Bus（只订阅，不改）
  → pgxpool（只读）、InstallationService（workspace-scoped 安装读取 + 解密凭据）
governance/crsync.go            只发布事件，不认识 lark 包（单向）
  ↘
   pkg/protocol（叶子包，零 internal 依赖）← lark 也 import 同一个包
```

`governance` 不 import `lark`，`lark` 不 import `governance`：两侧的编译期共同点只有叶子包 `pkg/protocol`（事件名 + 载荷类型），运行期只通过 `events.Bus` 传递。这是 `ARCHITECTURE.md` §4「fork governance may consume existing services and events, but must not duplicate task execution / Git transactions / CR state machines」的合规形态，也是 BL-4 要求的「可编译跨包契约」——**不再依赖字符串字面量与 `any` 断言的隐式约定**（原设计把常量与载荷类型放在 `governance/crsync.go`，lark 侧无从类型断言，正是 BL-4 指出的缺陷）。

## 1.2 关键流程

```text
daemon POST /api/daemon/cr-events
  → HandleCREvents（workspaceID 来自 DaemonAuth，唯一可信锚点）
  → ingest（cr_sync_event 幂等入账 ON CONFLICT DO NOTHING）
  → applyStatus
       ├─ curStatus == ev.FromStatus && KnownStatuses[ev.ToStatus] && IsLegalTransition(...)   ← 唯一可信分支
       │    ├─ UPDATE cr SET status = ev.ToStatus
       │    ├─ projectGateTransition(...)
       │    └─ publishApprovalGateEntered(ws, ev)     ← ★ 本 CR 唯一新增发布点
       │         └─ 仅当 ev.FromStatus != ev.ToStatus 且 ev.ToStatus ∈ 四门禁
       └─ else → needs_reconcile = TRUE（不发布）
  → publish（既有 cr:updated，未改）
  → HTTP 200 返回（r.Context() 随响应写出被取消）

  ┌─ 同步（bus 回调，零 I/O，微秒级）────────────────────────┐
  │ handleEvent(e): 解析 payload → 校验字段 → sem TryAcquire  │
  │   acquire 失败 → 记 reason=overloaded 事件级日志 → return  │
  │   acquire 成功 → go deliver(...) → 立即 return             │
  └────────────────────────────────────────────────────────────┘

  ┌─ 异步（独立 goroutine，context.Background() 派生）────────┐
  │ defer recover()（自持）；defer sem 释放                    │
  │ ctx, cancel = WithTimeout(Background(), 60s)               │
  │ 1. 飞书可用性判定（零 DB）    不可用 → feishu-disabled     │
  │ 2. appURL 判定（零 DB）       空串 → app-url-missing       │
  │ 3. 读链（每跳带 workspace_id = 锚点，fail-closed）         │
  │      cr → issue → project → workspace.slug                 │
  │      → member(role ∈ owner/admin) → binding ⋈ installation │
  │      DB 报错（非零行）→ 事件级 result=failed（不是 skip）  │
  │ 4. 逐收件人：分类 → 登记 attemptedOpenIDs（发送前！）      │
  │      → GetInWorkspace 水化凭据 + 状态/租户复核             │
  │      → WithTimeout(ctx, 10s) → SendApprovalReminderCard    │
  │ 5. 三类结果日志 sent/failed/skipped（§4.6 字段口径）       │
  └────────────────────────────────────────────────────────────┘
```

`HandleCREvents` 的响应时延只增加"bus 回调内的解析 + 一次非阻塞 channel send"，不含任何 I/O 等待——这是 AC-11 可断言的边界。

## 1.3 已核实的既有事实（本设计的地基）

| 事实 | 核实位置 |
|---|---|
| `events.Bus.Publish` 逐个**同步**调用订阅者；recover 只包住同步 handler，**不覆盖派生 goroutine** | `server/internal/events/bus.go`（`for _, h := range handlers { func(){ defer recover(); h(e) }() }`） |
| 状态消费走请求 ctx | `crsync.go#HandleCREvents` 传 `r.Context()` 进 `ingest` |
| 唯一可信转换分支持有 `FromStatus`/`ToStatus` | `crsync.go#applyStatus` 第 435 行的 `if curStatus == ev.FromStatus && KnownStatuses[...] && IsLegalTransition(...)` |
| 事件幂等键 | 迁移 391 `cr_sync_event_workspace_dedup_idx UNIQUE (workspace_id, cr_id, commit_sha, event_kind)` |
| `--embedded` 占位 sha 形状 | `crsync.go` 常量 `pendingShaPrefix = "pending:"`，crctl 侧 `pending:{ms}:{pid}:{seq}` |
| `channel_installation.status` CHECK | 迁移 124 `CHECK (status IN ('active','revoked'))`；撤销保留行（`handler/lark.go#RevokeLarkInstallation`） |
| channel_* 无外键、无 cascade，完整性归应用层 | 迁移 124 文件头两条硬规则 |
| 按 open_id 私聊发卡已有先例 | `http_client.go#SendBindingPromptCard`（`receive_id_type=open_id`）；`SendInteractiveCard` 走 `outboundMessageRequest` 固定 `receive_id_type=chat_id`，**不能**用于 open_id 私聊 |
| 有界超时同口径先例 | `outbound.go#Patcher.handleEvent`：`context.WithTimeout(context.Background(), 10*time.Second)`，注释明写"bus 同步投递，卡住的 Lark HTTP 会 wedge 整个 publish 调用点" |
| 飞书为条件装配；stub 零 HTTP | `router.go` 第 468 行 `if larkKey, err := secretbox.LoadKey("MULTICA_LARK_SECRET_KEY"); err == nil`，else 第 639 行 `lark integration disabled`；`client.go#stubAPIClient` 所有方法 Warn + `ErrAPIClientNotConfigured`；`ChannelRouter` 为无条件构建先例 |
| appURL 解析 | `router.go#appURLFromEnv()`：`MULTICA_APP_URL` → `FRONTEND_ORIGIN` → `""`，均 `TrimRight(…, "/")` |
| 现有查询确有"仅按外键"路径 | `governance/project_gates.go` 的 `cr JOIN issue ON issue.id = cr.shell_issue_id` 未比对 `cr.workspace_id = issue.workspace_id` |
| 可复用的绑定查询与其缺口 | `queries/channel.sql#FindChannelBindingForMember`（workspace + user + channel_type + `ci.status='active'` + `ORDER BY b.bound_at DESC LIMIT 1`）——**缺** `ci.workspace_id`/`ci.channel_type` 闭合，且"无行"无法区分 missing/revoked/orphan（详见 §5 DD-2） |
| 凭据水化路径（BL-1 的答案） | `InstallationService.GetInWorkspace(ctx, id, workspaceID)`（`installation.go:110`）→ `ChannelStore.GetLarkInstallationInWorkspace`（`channel_store.go:89`）→ sqlc `GetChannelInstallationInWorkspace`（`queries/channel.sql:82`，**WHERE id + workspace_id + channel_type 三条均带**）→ `installationFromRow`（`store.go:144`）把 JSONB `config` 解成 `AppID`/`AppSecretEncrypted`/`TenantKey`/`BotOpenID`/`Region`；无行返回 `ErrInstallationNotFound`。**已有上游查询，本 CR 不新增 sqlc** |
| 凭据组装现成 helper | `installationCredentialsFor(inst, resolver)`（`feishu_channel.go:104`，包内私有，**零改动直接复用**）：resolver 为 nil 报错、`DecryptAppSecret(inst)` 解密、把 `AppID`/`TenantKey`/`RegionOrDefault(Region)` 装成 `InstallationCredentials`（`client.go:341`） |
| 安装凭据存在 JSONB `config` 里，裸 SQL 取不到平展字段 | `store.go` 文件头 + `feishuInstallConfig`（`store.go:127`）：`app_id`/`app_secret_encrypted`（base64）/`tenant_key`/`bot_open_id`/`region` 全在 `config` JSONB；`decodeSecret` 还需容忍迁移回填的 MIME 折行 base64。这正是 BL-1 指出的缺口：分类用的裸 SQL **不应**自己解 config，而应走上游已有解码入口 |
| 事件契约共享的既有先例（BL-4 的答案） | `pkg/protocol/events.go:191-196` 已有 fork 新增的 `// AIFIRST:` 常量 `EventCRUpdated = "cr:updated"`，注释明写「governance.EventCRUpdated references this constant rather than duplicating the string literal」；`governance/crsync.go:48` 就是 `const EventCRUpdated = protocol.EventCRUpdated`。CUSTOM.md #22/#23（CR-2026-010 / CR-2026-011 TASK-05）已登记对 `pkg/protocol/events.go` 的同类改动 |
| 两侧均已 import `pkg/protocol` | `governance/crsync.go`（同上）；lark 包在 `outbound.go` / `registration_service.go` 已 import。`pkg/protocol` 自身零 `internal/` 依赖（叶子包）——把契约放进去**不新增任何依赖方向、无环风险** |
| 总线事件会被 WS 广播（决定载荷形状） | `cmd/server/listeners.go:207` 的 `bus.SubscribeAll` 把**每个**非 personal / 非 chat-scoped 事件经 `projectOutbound` + `json.Marshal` 广播到 workspace 房间；`projectOutbound`（`listeners.go:51`）对未登记 `internalOnlyPayloadKeys` 的类型原样返回，所以结体载荷按 json tag 序列化——载荷的 JSON 形状本身就是一份对外契约（§3.2.1 固定之） |
| 前端对未知事件类型免疫 | `packages/core/api/ws-client.ts:102-141`：无 string `type` 的帧丢弃，否则 `handlers.get(msg.type)` 为空即不处理；`use-realtime-sync.ts:960` 的 `onAny` 按前缀查 `refreshMap`，而 `refreshMap` **无 `cr` 键**（仅 inbox/agent/member/…/task）。新事件对前端是 **no-op**，本 CR 前端零 diff（与 CUSTOM #23 需成对贴回 `core/types/events.ts` 的情形不同） |
| `applyStatus` 手上的 cr 字段（BL-3 的可行性） | `crsync.go:399-401` 的 `SELECT status FROM cr WHERE workspace_id = $1 AND cr_id = $2`——现只取 status；带上 `shell_issue_id` 只需把该既有查询扩为两列（同文件内，零新增往返） |
| 字符串 → `pgtype.UUID` | `internal/util.ParseUUID`（`util/pgx.go:19`）；lark 包已 import `internal/util` |
| 飞书未启用时 `h.LarkAPIClient` 是 **nil 而非 stub**（修正初稿的措辞） | `router.go:502` 是全文唯一赋值点且在 `MULTICA_LARK_SECRET_KEY` 成功分支内，`handler.New` 不给默认 stub；`h.LarkInstallations` 同理保持 nil。故 `feishu-disabled` 判定必须先接 nil，且要防 typed-nil 接口陷阱（§3.2.3）；stub 仅作测试替身（AC-12） |

---

# 2. 术语硬化（Step 2.5 前置，首次状态推进前完成）

只处理进入数据模型 / 状态机 / 接口契约、且存在歧义或别名的术语。`CONTEXT.md` 与 PRD §1.3 术语表只读沿用。

| PRD canonical term | 代码别名 / 取值 | 边界场景（已验证） | 硬化结论 |
|---|---|---|---|
| 飞书渠道 | Go 包名 `lark`；DB 判别值 `channel_type = 'feishu'`；`Installation.Region` 区分 Feishu 大陆 / Lark 国际 | 迁移 124 把既有行 backfill 成 `channel_type='feishu'`；`'lark'` **不是**合法判别值 | 一切 DB 谓词写 `'feishu'`；包名/类型名沿用 `lark` 前缀（传输族），二者不互推 |
| **stage（审批阶段）** | ① `approval_record.stage` = `gates.json#approvalStages` 四键（`requirement`/`tech-design`/`dev-start`/`code`）；② PRD §4.4 的日志 `stage` = **事件的新状态**（`requirement-reviewing` 等） | 两者一一对应但**字面不同**，混用会让日志检索与审批账本对不上 | 日志字段 `stage` **一律取 CR status 字面值**（`requirement-reviewing`/`tech-design-review-pending`/`task-breakdown`/`code-reviewing`）；卡片上的中文阶段名是**展示层映射**（§4.3 表），不落日志、不与 `approval_record.stage` 混用；本 CR 不读写 `approval_record` |
| 有效（飞书）绑定 | 代码无此概念；最近似的 `FindChannelBindingForMember` 只校验 `b.workspace_id` + `b.channel_type` + `ci.status='active'` | 安装被撤销后绑定行保留（`status='revoked'`）；`installation_id` 可悬空（无外键）；`ci.workspace_id` 未被校验 | SDD 定义 `effectiveFeishuBinding` = PRD FR-5 三条件，**不**把 `FindChannelBindingForMember` 当唯一判据（§5 DD-2） |
| event_id | `events.Event` 无此字段；`cr_sync_event` 有 PK `id BIGSERIAL` 与幂等键 `(workspace_id, cr_id, commit_sha, event_kind)` | `--embedded` 模式 `commit_sha` 为 `pending:{ms}:{pid}:{seq}` 占位符——仍逐事件唯一，幂等键不退化；不同 workspace 可存在同名 CR（`cr` 的唯一键是 `(workspace_id, cr_id)`），故三段投影**全局不唯一** | `event_id = "{cr_id}:{event_kind}:{commit_sha}"`；**检索与对账的完整相关键是二元组 `(workspace_id, event_id)`**（`workspace_id` 既在事件 envelope 也是必填日志字段）——日志检索/文档/测试一律写二元组口径，不得单拿 `event_id` 当全局唯一键（§5 DD-1） |
| shell_issue_id（新增，BL-3） | `cr.shell_issue_id`（迁移 362，可 NULL）；载荷字段 `shell_issue_id *string`（JSON `omitempty`） | 历史 CR 为 NULL；跨 workspace 异常关联时该 issue 可能不属于锚点 workspace（PRD 澄清 4） | 载荷携带它以满足 FR-1 的「CR/issue 关联标识」，但它**只作相关/诊断字段，不得作为查询输入**；目标项目仍按 FR-3 从 PG 事实（`cr` 行）重新解析（ARCHITECTURE §7：bus 是通知不是持久权威，handler 必须可重放） |
| recipient | Multica `user.id`（权威）vs 飞书 `open_id`（= `channel_user_binding.channel_user_id`） | PRD §4.4 已定口径 | 日志 `recipient_user_id` 必填、`recipient_open_id` 仅发送成功/失败时出现；去重第一键是 user id |
| workspace 锚点 | `HandleCREvents` 中 `resolveDaemonWorkspace(r, s.pool)` 的返回值 | 请求体 `workspace_root_hash` 仅日志用，不可作信任输入（既有 SDD-SUG-002） | 锚点只能来自 DaemonAuth；`events.Event.WorkspaceID` 承载它，消费侧不得用读到的任何 `workspace_id` 覆盖锚点 |

**无语义冲突需要需求负责人裁决**，故未中断流程。

**HTTP/REST 契约：不触发。** 本 CR 不新增或修改任何 HTTP API（无新路由、无新请求/响应体、无鉴权面变化）；`router.go` 的改动只是进程内 wiring 与事件订阅。故本 SDD 不含接口契约中的 HTTP 章节，§3 只写进程内接口。

---

# 3. 数据模型与接口契约

## 3.1 数据模型：零 DDL

**不新增表、不新增列、不新增索引、不新增 migration。** 全部为只读消费既有表：

| 表 | 读取列 | 用途 | 读取方式 | 归属 |
|---|---|---|---|---|
| `cr` | `status`、`shell_issue_id`（发布侧）；`cr_id`、`workspace_id`、`title`、`shell_issue_id`（提醒器侧） | 载荷 issue 关联 + 事件锚定 + 卡片标题 | 发布侧：`applyStatus` 既有 SELECT 扩为两列；提醒器侧：§4.4 第一条 SQL | fork（迁移 362） |
| `issue` | `id`、`workspace_id`、`project_id` | 项目解析 | §4.4 第一条 SQL | 上游 |
| `project` | `id`、`workspace_id` | 项目存在性 + CTA projectID | §4.4 第一条 SQL | 上游 |
| `workspace` | `id`、`slug` | CTA workspaceSlug | §4.4 第一条 SQL | 上游 |
| `member` | `workspace_id`、`user_id`、`role` | owner/admin 收件人集合 | 成员查询（§4.2 步骤 3） | 上游（`role CHECK IN ('owner','admin','member')`） |
| `channel_user_binding` | `id`、`workspace_id`、`multica_user_id`、`installation_id`、`channel_type`、`channel_user_id`、`bound_at` | 绑定与 open_id | §4.4 第二条 SQL | 上游（迁移 124） |
| `channel_installation` | 分类：`id`、`workspace_id`、`channel_type`、`status`（均为平展列）；凭据：整行含 `config` JSONB | 有效性分类 + 发送凭据 | 分类走 §4.4 第二条裸 SQL；**凭据走既有 sqlc `GetChannelInstallationInWorkspace`**（`GetInWorkspace`），`config` 由 `installationFromRow` 解码，不在裸 SQL 里解 | 上游（迁移 124） |

索引覆盖核实：`cr` 有 `UNIQUE (workspace_id, cr_id)`；`issue`/`project`/`member` 主键与 workspace 列既有索引足够（单次门禁收件人规模为个位数，读放大可忽略）；`channel_user_binding` 有 `UNIQUE (installation_id, channel_user_id)`。**无需新索引**。

## 3.2 进程内接口契约

### 3.2.1 事件契约（governance → bus → lark）

```go
// server/pkg/protocol/events.go  —— BL-4：事件名与载荷类型的唯一声明处
// （先例：同文件 191-196 行的 AIFIRST 常量 EventCRUpdated，governance 侧取别名）

// AIFIRST: CR-2026-051 FR-1 — dedicated approval-gate semantic event.
// Deliberately NOT EventCRUpdated: that one is published from 5 sites
// (3x crsync, gate_projection, reconcile) and would fire on projection
// maintenance, not on a fresh approval request. Declared here (not in
// internal/governance) because BOTH the producer (internal/governance)
// and the consumer (internal/integrations/lark) must share one
// compile-time contract without importing each other.
EventCRApprovalGateEntered = "cr:approval-gate-entered"

// ApprovalGateEnteredPayload carries only location identifiers. Approval
// evidence, titles, project ids and recipients are deliberately absent —
// the consumer re-reads them from PostgreSQL so handlers stay replayable
// (ARCHITECTURE.md §7: the bus is notification, not durable authority).
//
// This struct is ALSO the outbound WS frame shape: listeners.go
// SubscribeAll marshals every bus payload to the workspace room, so the
// json tags below are a client-visible contract — additive changes only.
// ShellIssueID is a pointer because cr.shell_issue_id is nullable
// (migration 362); it is a correlation field only and MUST NOT be used
// as a query input (FR-3 resolves the project chain from PostgreSQL).
type ApprovalGateEnteredPayload struct {
    CRID         string  `json:"cr_id"`
    Status       string  `json:"status"`         // ev.ToStatus, one of the four gates
    EventID      string  `json:"event_id"`       // "{cr_id}:{event_kind}:{commit_sha}"
    ShellIssueID *string `json:"shell_issue_id"` // nullable; correlation only
}
```

`governance` 侧只保留别名与四门禁集合（与既有 `EventCRUpdated` 完全同构）：

```go
// server/internal/governance/crsync.go

// AIFIRST: CR-2026-051 FR-1 — alias of the shared protocol constant,
// same shape as EventCRUpdated above (line 48): the string literal is
// declared once, in pkg/protocol.
const EventCRApprovalGateEntered = protocol.EventCRApprovalGateEntered

// approvalGateStatuses are the four human-approval gates (PRD FR-1 cond. 4),
// verified against ../tools/dir-graph.yaml#change-request-track.state_machine.
var approvalGateStatuses = map[string]bool{
    "requirement-reviewing":      true, // 需求审批
    "tech-design-review-pending": true, // 架构审批
    "task-breakdown":             true, // 开发启动审批
    "code-reviewing":             true, // 代码审批
}
```

消费侧（lark）的解析因此是**真正的类型断言**，而不是 map 取键：

```go
// server/internal/integrations/lark/approval_reminder.go
func parsePayload(v any) (protocol.ApprovalGateEnteredPayload, bool) {
    p, ok := v.(protocol.ApprovalGateEnteredPayload)   // compile-time contract
    if !ok || p.CRID == "" || p.Status == "" || p.EventID == "" {
        return protocol.ApprovalGateEnteredPayload{}, false
    }
    return p, true
}
```

上游若改字段名/类型，两侧同时 build 失败（而不是运行时静默停摆）——这是 BL-4 要求的可编译契约。**不支持** map 形态回退解析（不写 `map[string]any` 分支）：多一条宽容路径就多一个无人覆盖的静默降级面。

发布点（`applyStatus` 可信分支内，`projectGateTransition` 之后）：

```go
// AIFIRST: CR-2026-051 FR-1/FR-2 — publish only from the trusted branch,
// only on a real status change, only for the four approval gates.
// shellIssueID comes from the same SELECT that already read curStatus
// (one query, two columns) — no extra round trip, no signature change
// on ingest/apply.
func (s *SyncService) publishApprovalGateEntered(workspaceID string, ev OutboxEvent, shellIssueID *string) {
    if s.bus == nil || ev.FromStatus == ev.ToStatus || !approvalGateStatuses[ev.ToStatus] {
        return
    }
    s.bus.Publish(events.Event{
        Type:        EventCRApprovalGateEntered,
        WorkspaceID: workspaceID,
        ActorType:   "system",
        Payload: protocol.ApprovalGateEnteredPayload{
            CRID:         ev.CRID,
            Status:       ev.ToStatus,
            EventID:      ev.CRID + ":" + ev.EventKind + ":" + ev.CommitSHA,
            ShellIssueID: shellIssueID,
        },
    })
}
```

`shellIssueID` 的取值方式（BL-3 的最小改法）：把 `applyStatus` 开头那条既有查询从 `SELECT status` 扩为 `SELECT status, shell_issue_id`（`crsync.go:399`，同一 workspace 谓词不变），扫进 `*string`。`found == false` 分支不用该值（也不发布）。**不**在发布点另开一次查询：那样会多一次往返，也会引入一个与本次转换不同时点的读取。

契约不变量（供 AC-1/AC-2 断言）：

1. 只在 `applyStatus` 的可信分支调用——`found == false` 的首次见闻分支**不**调用（`legalFresh` 为真也不调用：注册转移的目标状态不可能是四门禁之一，且首次见闻本身可能缺历史）；
2. `else` 分支（乱序 / 非法，只置 `needs_reconcile`）不调用；
3. `apply` 的 `checkpoint` / `review` / `trace` / default 分支不调用；
4. `reconcile.go`、`gate_projection.go` 不调用；
5. 自环（`from == to`）被条件 1 过滤；
6. **canonical JSON 形状**：`{"cr_id":"…","status":"…","event_id":"…","shell_issue_id":"…"|null}`——由 `pkg/protocol` 的 json tag 唯一定义，同时是 WS 广播帧的 payload（§1.3 已核：`listeners.go` 的 `SubscribeAll` 会把它广播到 workspace 房间）；只允许加字段，不得改/删现有键名（ARCHITECTURE §5 不变量 8：客户端容忍加法漂移）；
7. 载荷只做定位与相关：`shell_issue_id` **不进任何 SQL 参数**，消费侧仍按 FR-3 从 `cr` 行重新解析（AC-10 的跨 workspace 负向断言因此对载荷伪造也成立）。

### 3.2.2 传输契约（lark 包内）

```go
// server/internal/integrations/lark/approval_reminder_card.go

// ApprovalReminderParams is the minimal input for the approval reminder
// card. Mirrors BindingPromptParams: credentials + open_id + one CTA URL,
// plus the three display fields FR-6 allows. No approval evidence, no diff.
type ApprovalReminderParams struct {
    InstallationID InstallationCredentials
    OpenID         OpenID
    CRID           string // "CR-2026-051"
    CRTitle        string // cr.title; empty renders CRID only
    StageLabel     string // display-only Chinese label (§4.3 map)
    ApproveURL     string // {appURL}/{slug}/projects/{projectID}?tab=chat
}
```

`client.go` 的 `APIClient` 接口新增一行（唯一的接口面改动，带 `// AIFIRST:` 标记）：

```go
// AIFIRST: CR-2026-051 FR-9 — dedicated approval reminder outbound.
// Separate from SendInteractiveCard because that one hard-codes
// receive_id_type=chat_id (outboundMessageRequest) and cannot address an
// open_id p2p chat; separate from SendBindingPromptCard because the card
// body and CTA differ. Implementations live in approval_reminder_card.go.
SendApprovalReminderCard(ctx context.Context, p ApprovalReminderParams) error
```

实现均落在自研文件 `approval_reminder_card.go`（Go 允许同包跨文件定义方法，故 `client.go` / `http_client.go` 正文零改动）：

- `func (c *httpAPIClient) SendApprovalReminderCard(...) error` — 复用私有 helper `sendCardToOpenID(ctx, creds, openID, cardJSON)`（由 `SendBindingPromptCard` 的既有逻辑提取，见 §4.5）；
- `func (s *stubAPIClient) SendApprovalReminderCard(...) error` — `Warn` + `ErrAPIClientNotConfigured`，零 HTTP。

### 3.2.3 提醒器构造契约

```go
// server/internal/integrations/lark/approval_reminder.go

// installationCredentialSource is the narrow seam the reminder needs from
// InstallationService: the workspace-scoped installation read (which also
// fences channel_type) plus app_secret decryption. *InstallationService
// satisfies it as-is; no upstream signature changes (BL-1).
type installationCredentialSource interface {
    CredentialsResolver // DecryptAppSecret(inst Installation) (string, error)
    GetInWorkspace(ctx context.Context, id, workspaceID pgtype.UUID) (Installation, error)
}

type ApprovalReminderConfig struct {
    Pool        *pgxpool.Pool                 // read-only; nil ⇒ reminder degrades to no-op
    Client      APIClient                     // nil or !IsConfigured() ⇒ feishu-disabled
    Credentials installationCredentialSource  // nil ⇒ feishu-disabled
    AppURL      string                        // appURLFromEnv(); "" ⇒ app-url-missing
    Logger      *slog.Logger
    // MaxInFlight bounds concurrent deliveries (FR-8.1). 0 ⇒ default 8.
    MaxInFlight int
    // EventTimeout / RecipientTimeout default to 60s / 10s (FR-8.1).
    EventTimeout     time.Duration
    RecipientTimeout time.Duration
}

// NewApprovalReminder never returns nil: Register/handleEvent must be safe
// to call on any construction outcome (a nil return would panic at the
// unconditional Register call site required by FR-8.3).
func NewApprovalReminder(cfg ApprovalReminderConfig) *ApprovalReminder
func (r *ApprovalReminder) Register(bus *events.Bus)  // Subscribe(EventCRApprovalGateEntered, r.handleEvent)
```

**API 参数不得静默忽略（CONTRIBUTING.AIFIRST 规则六）**：`MaxInFlight` / `EventTimeout` / `RecipientTimeout` 只有“0 值走文档化默认”这一种退化，非零值一律生效。

**依赖缺失的处理（评审非阻塞建议②：不得 panic）**：

- `Pool == nil` / `Credentials == nil` / `Client == nil`：构造函数记一条 `Error` 并返回一个 **标记为 unusable 的真实对象**（不返回 nil）；`Register` 照常订阅（FR-8.3 要求无条件注册），`deliver` 在步骤 1 即以事件级 `feishu-disabled` 返回（处于任何 DB 查询之前）。**不新增第 10 个跳过原因**：FR-8.2 的 9 项枚举是已审批口径，而“依赖未装配”语义与 `feishu-disabled`（飞书 integration 不可用）一致。
- **typed-nil 接口陷阱（必须在 wiring 层防）**：`h.LarkInstallations` 是 `*lark.InstallationService`，飞书未启用时为 nil 指针。直接赋给接口字段会得到一个 `!= nil` 但调用即 panic 的接口值，所以 `router.go` 必须显式判空后才赋值（下方 wiring 片段），提醒器内部不依赖反射。

`Register` 的调用点在 `router.go` 中**飞书密钥条件块之外**（FR-8.3）：

```go
// AIFIRST: CR-2026-051 FR-8.3 — registered unconditionally, OUTSIDE the
// MULTICA_LARK_SECRET_KEY block, so a disabled Lark integration still
// consumes the event and logs a feishu-disabled skip instead of the
// subscription being absent. h.LarkAPIClient / h.LarkInstallations are
// nil in that case: assign them only when non-nil, otherwise the config
// would hold a typed-nil interface that panics on first use.
reminderCfg := lark.ApprovalReminderConfig{
    Pool: pool, AppURL: appURLFromEnv(), Logger: slog.Default(),
}
if h.LarkAPIClient != nil {
    reminderCfg.Client = h.LarkAPIClient
}
if h.LarkInstallations != nil {
    reminderCfg.Credentials = h.LarkInstallations
}
lark.NewApprovalReminder(reminderCfg).Register(bus)
```

飞书未启用时两个依赖均为 nil（§1.3 已核：`router.go:502` 是 `h.LarkAPIClient` 唯一赋值点，**默认不是 stub 而是 nil**）：提醒器在**任何 DB 查询之前**判定不可用（§4.2 步骤 1），故两种形态都收敛到 `feishu-disabled`；测试里可换成 `lark.NewStubAPIClient`（`IsConfigured() == false`）断言零真实请求（AC-12）。

---

# 4. 关键算法与流程

## 4.1 同步侧（bus 回调）：零 I/O + 非阻塞

```text
handleEvent(e events.Event):
    # 只做解析与校验，禁止 DB / HTTP —— AC-11 用零调用替身断言
    p, ok := parsePayload(e.Payload)            # protocol.ApprovalGateEnteredPayload 类型断言 + 字段非空
    if !ok:            log(warn, "malformed payload"); return
    if !approvalGateStatuses[p.Status]:         return       # 防御性二次过滤
    if e.WorkspaceID == "":                     log(warn); return

    select:
      case r.sem <- struct{}{}:                 # 非阻塞获取
          go r.deliver(p, e.WorkspaceID)        # 立即返回，不等待
      default:
          logSkip(event, reason="overloaded", p, e.WorkspaceID)   # 丢弃，不排队
    return
```

`sem` 是 `chan struct{}`（容量 `MaxInFlight`，默认 8）。非阻塞 `select` + `default` 是"有上限、过载丢弃、不排队"的最小实现——**不新增队列表、不新增任务框架、不重试**（PRD §7 范围排除）。回调总耗时 = 一次类型断言 + 一次 map 查 + 一次 channel send，无 I/O，故 `HandleCREvents` 时延与"无提醒器"基线同量级。

## 4.2 异步侧（deliver）：fail-closed 读链 + 单次投递

```text
deliver(p, anchorWorkspaceID):
    defer func(){ if v := recover(); v != nil { log(error, "panic recovered", v) } }()   # 自持，bus 的 recover 覆盖不到
    defer func(){ <-r.sem }()                                                            # 释放并发额度
    ctx, cancel := context.WithTimeout(context.Background(), r.eventTimeout)              # 脱离请求 ctx；60s
    defer cancel()

    # ── 1. 飞书可用性（零 DB，最先判）───────────────────────────
    if r.pool == nil || r.client == nil || !r.client.IsConfigured() || r.credentials == nil:
        logSkip(event, "feishu-disabled"); return            # AC-12：零真实请求、零收件人查询；也覆盖依赖未装配（§3.2.3）

    # ── 2. CTA 基地址（零 DB）──────────────────────────────────
    if r.appURL == "":
        logSkip(event, "app-url-missing"); return            # 不发无效链接；不新增 URL 合法性校验器

    # ── 3. workspace-closed 读链（每跳带 workspace_id = 锚点）──
    ctx1 := 单条 SQL（§4.4）：cr ⋈ issue ⋈ project ⋈ workspace，三处 workspace_id = $1
    switch:
      db 报错（非 ErrNoRows）→ logFailEvent(step="project-chain", errClass(err)); return   # 不当 skip
      no rows          → logSkip(event, "project-unresolved" | "workspace-mismatch"); return
      slug == ""       → logSkip(event, "workspace-mismatch"); return

    approvers, err := SELECT user_id FROM member WHERE workspace_id = $1 AND role IN ('owner','admin')
    if err != nil:
        logFailEvent(step="approver-query", errClass(err)); return                         # 不当 skip
    if len(approvers) == 0:
        logSkip(event, "no-approver"); return

    approveURL := r.appURL + "/" + slug + "/projects/" + projectID + "?tab=chat"

    # ── 4. 逐收件人：分类 → 发送前登记 → 水化凭据 → 单次发送 ──
    attemptedOpenIDs := {}                        # BL-2：语义是"已尝试"，不是"已成功"
    for userID in approvers:                      # 个位数规模，顺序执行
        rows, err := 有效绑定候选（§4.4 第二条 SQL，LEFT JOIN installation）
        if err != nil:
            logFail(userID, "", step="binding-query", errClass(err)); continue              # 不当 skip
        if len(rows) == 0:
            logSkip(recipient, userID, "binding-missing"); continue
        pick, reason := chooseEffective(rows)     # §4.3
        if pick == nil:
            logSkip(recipient, userID, reason); continue      # installation-revoked / -missing / workspace-mismatch

        # ★ BL-2：登记必须早于任何可失败动作（水化 / 解密 / 发送）
        if pick.OpenID in attemptedOpenIDs:
            continue                              # 同一 open_id 单次事件只尝试一次（FR-5/AC-3、FR-8.2）
        attemptedOpenIDs.add(pick.OpenID)

        # ★ BL-1：workspace-scoped 完整安装读取（config JSONB 由上游解码）
        inst, err := r.credentials.GetInWorkspace(ctx, pick.InstallationID, anchorWorkspaceUUID)
        switch:
          errors.Is(err, ErrInstallationNotFound) → logSkip(recipient, userID, "installation-missing"); continue
          err != nil                              → logFail(userID, pick.OpenID, step="credential-hydrate", errClass(err)); continue
        # 租户 / 状态复核（水化后再校一次，封住"分类 → 发送"之间的 TOCTOU 窗）
        if UUIDToString(inst.WorkspaceID) != anchorWorkspaceID:
            logSkip(recipient, userID, "workspace-mismatch"); continue
        if inst.Status != "active":
            logSkip(recipient, userID, "installation-revoked"); continue

        creds, err := installationCredentialsFor(inst, r.credentials)   # 既有 helper：解密 + AppID/TenantKey/Region
        if err != nil:
            logFail(userID, pick.OpenID, step="credential-decrypt", errClass(err)); continue

        rctx, rcancel := context.WithTimeout(ctx, r.recipientTimeout)   # 10s
        err = r.client.SendApprovalReminderCard(rctx, ApprovalReminderParams{...})
        rcancel()
        if err != nil: logFail(userID, pick.OpenID, step="send", errClass(err))   # 单收件人失败不影响同批其他人
        else:          logSent(userID, pick.OpenID)
```

**关键约束的落点**：

- 异步开始时**不重新读 CR 状态**（FR-8.4）——语义是"曾实际进入该门禁"；不做消息撤回、不做补偿；
- `ctx` 由 `context.Background()` 派生，与 `r.Context()` 的生命周期完全解耦；
- 进程退出时在飞 goroutine 允许丢失，**不做 drain/join**（FR-8.4，与既有 crash window 口径一致）；
- 全链只读，无事务、无写入；
- **失败与跳过不同类（评审非阻塞建议③）**：DB 报错、凭据水化/解密报错、发送报错一律记 `result=failed`（带 `error_class` + `step`），**不**占用 FR-8.2 的 9 项 `reason` 枚举；`reason` 只给“按设计不发”的确定态（零行 / 角色不符 / 安装失效 / 未启用 / 过载）。字段口径见 §4.6；
- **尝试登记早于任何可失败动作**（BL-2）：同一 `open_id` 在单次事件内无论首次结果如何，都不会被后续用户再次尝试（卸掉了旧设计“失败就不登记 → 重复发”的退回行为）。

## 4.3 有效绑定选择与去重（`chooseEffective`）

输入是同一 `(workspace 锚点, userID, channel_type='feishu')` 下的全部绑定候选（每行带 LEFT JOIN 到的**安装标识与校验列**：`ci.id`/`ci.workspace_id`/`ci.channel_type`/`ci.status`，可为 NULL）。本函数**只做分类**，不取凭据；凭据由 §4.2 的 `GetInWorkspace` 水化（BL-1）。

```text
chooseEffective(rows):                 # rows 已按 bound_at DESC, id ASC 排序（确定性）
    seenRevoked, seenMissing, seenMismatch := false, false, false
    for row in rows:
        if row.InstallationID is NULL or row.Inst is NULL:  seenMissing  = true; continue
        if row.Inst.WorkspaceID != anchor or row.Inst.ChannelType != 'feishu':
                                                            seenMismatch = true; continue
        if row.Inst.Status != 'active':                      seenRevoked  = true; continue
        return row, ""                 # 第一条命中即 bound_at 最新的有效绑定 → 每用户一张卡
    # 无有效绑定：按"最具体优先"给出唯一可区分原因
    if seenMismatch: return nil, "workspace-mismatch"
    if seenRevoked:  return nil, "installation-revoked"
    if seenMissing:  return nil, "installation-missing"
    return nil, "binding-missing"      # 理论不可达（rows 非空必落入上面某一支），兜底
```

排序键 `bound_at DESC, id ASC` 是 PRD FR-5 的确定性口径，与既有 `FindChannelBindingForMember` / `FindReusableChannelUserBinding` 的 `bound_at DESC` tiebreak 一致（后者无二级键，本设计补上 `id ASC` 消除并列不确定性）。

**分类结果不是最终授权（BL-1 的双层闭合）**：`chooseEffective` 选中的只是一个 `installation_id`；真正取凭据时再走一次 `GetInWorkspace(id, 锚点)`——该上游查询自带 `workspace_id` 与 `channel_type` 谓词（§1.3 已核），因此租户闭合在“分类”与“取凭据”两道各自成立；水化后再对 `inst.WorkspaceID` / `inst.Status` 做一次显式复核，封住两次读取之间的撤销窗。分类与水化不一致时（例：分类时 active、水化时 revoked）**以水化结果为准**并记对应 reason。

**卡片阶段名映射（展示层，不落日志）**：

| CR status（日志 `stage` 取值） | 卡片展示 |
|---|---|
| `requirement-reviewing` | 需求审批 |
| `tech-design-review-pending` | 架构审批 |
| `task-breakdown` | 开发启动审批 |
| `code-reviewing` | 代码审批 |

映射是**封闭 switch + default 回退到 status 原文**：新增门禁状态时不会渲染空白（enum switch 必须有 default，`ARCHITECTURE.md` §5 不变量 8 的同款纪律）。

## 4.4 SQL：workspace 闭合的两条只读查询

第一条（CR → issue → project → workspace.slug，一次往返，三处 workspace 谓词）：

```sql
-- AIFIRST: CR-2026-051 FR-3 — every hop carries workspace_id = $1 (the
-- DaemonAuth anchor). Deliberately NOT the project_gates.go join shape:
-- that one joins issue by primary key only, which cannot detect a
-- cross-workspace shell_issue_id. No fallback re-query on miss.
SELECT p.id::text, w.slug, c.title
  FROM cr c
  JOIN issue   i ON i.id = c.shell_issue_id AND i.workspace_id = $1
  JOIN project p ON p.id = i.project_id     AND p.workspace_id = $1
  JOIN workspace w ON w.id = $1
 WHERE c.workspace_id = $1 AND c.cr_id = $2;
```

`INNER JOIN` + 全跳 workspace 谓词即 fail-closed：`shell_issue_id IS NULL`、issue/project 跨 workspace、或任一行缺失都返回零行，一律跳过。**零行时的原因判定**：再查一次 `SELECT shell_issue_id IS NULL FROM cr WHERE workspace_id=$1 AND cr_id=$2`——为真或无行 ⇒ `project-unresolved`；否则 ⇒ `workspace-mismatch`。这**不是**"放宽条件重查"（FR-3 禁止项）：该查询仍带 `workspace_id = $1`，且只用于选日志原因，不产生任何收件人或发送。

第二条（每收件人一次，候选 + 安装联查）：

```sql
-- AIFIRST: CR-2026-051 FR-5 — effective-binding candidates for one member.
-- LEFT JOIN (not INNER) so a dangling installation_id (channel_* has NO
-- foreign keys, migration 124) is observable as installation-missing
-- instead of silently collapsing into binding-missing.
SELECT b.id, b.channel_user_id, b.installation_id,
       ci.id, ci.workspace_id, ci.channel_type, ci.status
  FROM channel_user_binding b
  LEFT JOIN channel_installation ci ON ci.id = b.installation_id
 WHERE b.workspace_id = $1 AND b.multica_user_id = $2 AND b.channel_type = 'feishu'
 ORDER BY b.bound_at DESC, b.id ASC;
```

注意 `ci.workspace_id` / `ci.channel_type` / `ci.status` 只**取回**不在 SQL 里过滤——过滤放在 `chooseEffective` 里，正是为了产出可区分的跳过原因（若写进 WHERE，三种失效原因会全部退化成“零行”，AC-4 无法验收）。

**两条 SQL 均不取凭据（BL-1 的修正点）**：发送所需的 `app_id` / `app_secret_encrypted` / `tenant_key` / `region` 全在 `channel_installation.config` 这个 JSONB 里，且密文是可能 MIME 折行的 base64（`store.go` 文件头）——拿裸 SQL 自己 `->>` + 手写 base64 宽容解码等于在 fork 侧重实现一份 `installationFromRow`。**正确做法**：拿到 `installation_id` 后调既有的 `InstallationService.GetInWorkspace(ctx, id, workspaceUUID)`（内部就是 sqlc `GetChannelInstallationInWorkspace`，WHERE 带 id + workspace_id + channel_type，返回的 `Installation` 已由 `installationFromRow` 解好 config），再给既有 `installationCredentialsFor(inst, resolver)` 组装成 `InstallationCredentials`。所以：**裸 pgx 只用于“可区分分类”，凭据路径完全走上游已有、已带租户谓词的查询**，既满足 AC-4，也不重实现解码/解密。

**DB 错误不得当零行**：两条查询与成员查询的 `err != nil`（非 `ErrNoRows`）一律进 `result=failed`（带 `step`），不复用任何 `reason`——否则“库挂了”会伪装成“用户未绑定”（§4.6）。

## 4.5 私有 helper 提取（行为等价）

`SendBindingPromptCard` 与 `SendApprovalReminderCard` 的传输部分完全同构（`receive_id_type=open_id` + `msg_type=interactive` + tenant token + 错误码 / token 失效处理）。提取为 `http_client.go` 内私有 helper：

```go
func (c *httpAPIClient) sendCardToOpenID(ctx context.Context, creds InstallationCredentials, openID OpenID, cardJSON, op string) error
```

`SendBindingPromptCard` 改为调用它（**唯一一处对上游函数正文的改动，带 `// AIFIRST:` 标记**）。行为等价由既有测试锁定：`http_client_test.go#TestHTTPClient_SendBindingPromptCard_HappyPath` 及第 1270/1276 行的错误路径断言必须**原样通过、不修改**（§4.3 兼容性要求"现有绑定提示卡片行为不得因私有 helper 提取而改变"）。

> **评审已定案（sdd.yml suggestions 第 2 条）**：采纳 `sendCardToOpenID` 提取；退化方案（在自研文件重写 ~30 行传输逻辑）作废。评审同时要求：既有绑定提示测试保持不变之外，必须为**审批卡路径**补下列五类测试（“证明复用正确”而不是“推定复用正确”），均写在自研测试文件内：
>
> | # | 测试 | 断言要点 |
> |---|---|---|
> | 1 | 参数校验 | `OpenID == ""` / `ApproveURL == ""` 各返回错误且**零 HTTP**（与 `SendBindingPromptCard` 前两条同口径） |
> | 2 | 成功路径 | 打到 `/open-apis/im/v1/messages`、`receive_id_type=open_id`、`receive_id == open_id`、`msg_type=interactive`、body.content 为审批卡模板 |
> | 3 | token 失效 | 响应 `code` 为 token 类错误时触发 `invalidateToken(creds.AppID)`，下一次调用重新换 token（复用 helper 内的 `isTokenError` 分支） |
> | 4 | JSON 转义 | CR 标题包含 `"` / `\` / 换行 / emoji 时，卡片 JSON 仍可被 `json.Unmarshal` 回解且文本不损（模板不拼字符串，走 `json.Marshal`） |
> | 5 | stub 形态 | `stubAPIClient.SendApprovalReminderCard` 返回 `ErrAPIClientNotConfigured`、零 HTTP（与 AC-12 共用断言） |
>
> 其中第 3 条是“提取后两处 token 失效处理不会漂移”的真正回归锁。

## 4.6 结果日志口径（sent / failed / skipped）

PRD §4.4 已定义必需字段枚举；本节只把它落成三个单一入口，并补齐评审要求的“**DB 读取错误也要有结构化 `failed`**”（非阻塞建议③）。

| 入口 | 使用时机 | 字段 |
|---|---|---|
| `logSent(userID, openID)` | 卡片发送成功 | `cr_id`、`stage`、`workspace_id`、`event_id`、`recipient_user_id`、`recipient_open_id`、`result=sent` |
| `logFail(userID, openID, step, errClass)` | 收件人级失败：绑定查询报错 / 凭据水化报错 / 解密报错 / 发送报错或超时 | 同上 + `result=failed` + `error_class` + `step`（`openID` 尚未取到时缺省） |
| `logFailEvent(step, errClass)` | **事件级**失败：项目链查询 / 成员查询报错（尚无收件人） | `cr_id`、`stage`、`workspace_id`、`event_id`、`result=failed`、`error_class`、`step`；**无** recipient 字段 |
| `logSkip(scope, [userID], reason)` | 按设计不发 | 事件级：四个必填 + `result=skipped` + `reason`；收件人级额外带 `recipient_user_id` |

口径固定点：

1. `stage` = CR status 字面值（§2 术语硬化），**不**取卡片上的中文阶段名、不取 `approval_record.stage`；
2. `reason` 取值严格限于 FR-8.2 的 9 项枚举（集中声明为常量，不散拼字符串），**不新增第 10 项**；
3. `error_class` 取值为 PRD §4.4 括号内的四类：`timeout` / `rate-limited` / `not-configured` / `other`（DB 与解密错误归 `other`）；
4. `step` 是本 SDD 新增的**可选定位字段**（`project-chain` / `approver-query` / `binding-query` / `credential-hydrate` / `credential-decrypt` / `send`），取值是闭集常量、不含任何响应体或凭据文本——目的是让“库挂了”与“飞书报错”在日志里可区分；
5. **事件级 `failed` 无 recipient 字段**：与 PRD §4.4 “事件级跳过无 `recipient_open_id`” 同一条例外模式（字段按作用域条件出现）；这是对 PRD 可观测表的**加法细化**，不删不改已有必需字段，已列入 §8 供审批可见；
6. 日志里永不出现审批证据、签名材料、token、diff、飞书响应体原文（PRD §4.2/§4.4）。

---

# 5. 技术选型与决策记录

只记录同时满足「难以逆转 + 无上下文会疑惑 + 有真实权衡替代」的四条。事件类型隔离（专用事件 vs `cr:updated`）已由 PRD FR-1/FR-2 拍板，不在此复述。

## DD-1 `event_id` 绑定到账本幂等键的字符串投影

- **Decision**：`event_id = "{cr_id}:{event_kind}:{commit_sha}"`，在 `publishApprovalGateEntered` 内由手上的 `OutboxEvent` 直接拼出，贯穿事件级与收件人级全部日志。
- **Context**：quality-reviewer 需求评审 attempt 2 的实现期建议①要求 `event_id` 绑定**稳定的来源事件标识**并贯穿日志。`events.Event` 无此字段；来源侧唯一稳定标识是 `cr_sync_event` 的幂等键 `(workspace_id, cr_id, commit_sha, event_kind)`（迁移 391 唯一索引）。`workspace_id` 已是独立日志字段，故投影为三段字符串即可唯一定位一次来源事件。`--embedded` 模式的 `commit_sha` 是 `pending:{ms}:{pid}:{seq}` 占位符——**仍逐事件唯一**（CR-2026-003 修的正是占位符互撞问题），幂等键不退化。
- **Alternatives**：
  1. `cr_sync_event.id`（BIGSERIAL）——更短，但 `ingest` 的 INSERT 是 `ON CONFLICT DO NOTHING` 无 `RETURNING`，要把 id 从 `ingest` 一路传到 `applyStatus` 再传进发布点，属为一个日志字段改动治理核心的调用签名；
  2. 每次发布新生成 UUID——能串起一次投递的多条日志，但**不指向来源事件**，重放或双通道上报时无法与账本对账，达不到建议①的要求。
- **Consequences**：日志可直接与 `cr_sync_event` 三列对账，零 schema 改动、零额外查询；代价是 `event_id` 较长且含冒号分隔（检索需整串匹配，不做子串解析）。
- **相关键口径（评审非阻塞建议①）**：三段投影**不是全局唯一的**——`cr` 的唯一键是 `(workspace_id, cr_id)`，两个 workspace 完全可以各有一个 `CR-2026-051`，幂等键本身也是四列含 workspace。本设计**不**把 `workspace_id` 拼进 `event_id` 字符串（会与已有的独立日志字段重复、且把一个可对账投影变成四段不可读串），而是**显式声明检索与对账键为二元组 `(workspace_id, event_id)`**：`workspace_id` 在事件 envelope（`events.Event.WorkspaceID`）与三类日志里均为必填字段（PRD §4.4），所以二元组在日志侧是现成可用的。文档/断言/运维检索一律写二元组口径，禁止把 `event_id` 当全局主键用。

## DD-2 提醒器自带只读 pgx seam，不新增 sqlc 查询（评审已采纳）

- **Status**：`review-annotations/sdd.yml` suggestions 第 1 条明确「accept the raw pgx seam rather than expanding FR-10 into channel.sql/sqlc」，同时附三条强制条件：① 补全安装凭据读取；② 补租户闭合检查；③ 把 lark 裸 SQL 的列依赖登记进 `CUSTOM.md`（CUSTOM #5 只覆盖 governance 包，不能代替本 CR）。三条已分别落到 §4.2/§4.4（凭据路径）、§4.3+§4.4（双层租户闭合）、§7.3（CUSTOM.md 新增条目）。

- **Decision**：提醒器的读链（§4.4 两条 SQL）用 `*pgxpool.Pool` 直接执行，写在自研文件内；**不**往 `server/pkg/db/queries/channel.sql` 加查询、不重跑 `make sqlc`。
- **Context**：需要一条现有 sqlc 查询集里没有的读——"某 workspace 某成员的全部 feishu 绑定候选 + LEFT JOIN 安装"。最近似的 `FindChannelBindingForMember` 有两处不够：它不闭合 `ci.workspace_id` / `ci.channel_type`（PRD 澄清 4 指出的正是这类漏洞），且 `LIMIT 1` + `INNER JOIN ci … status='active'` 把 missing / revoked / orphan 三种失效**全部压成"零行"**，AC-4 要求的可区分跳过原因无法实现。加 sqlc 查询要改上游 `channel.sql` 并重生成 `pkg/db/generated/*.go`——CUSTOM.md 明列这两类文件是 fork 最大的合并冲突面，且**超出 PRD FR-10 声明的改动文件集合**（AC-8 逐条核对改动面）。
- **Alternatives**：
  1. `channel.sql` 加 `-- AIFIRST:` 查询 + `make sqlc`——编译期列名安全（上游改列名会 build 失败），先例充分（CUSTOM #17 起、#48）；但突破 FR-10 改动面，需求侧要重新确认，且吃进生成物冲突面；
  2. 只用现有 `FindChannelBindingForMember` + `GetChannelInstallationInWorkspace` 两步——零新查询，但如上所述放弃 AC-4 的可区分原因，等于降级已审批的验收标准。
- **Consequences**：改动面严格落在 FR-10 内，`governance` 包既有"fork 代码直接用 pgx 以避开上游 query 文件"的同款先例（CUSTOM.md #5）。**代价与缓解**：裸 SQL 失去 sqlc 的编译期列名校验，上游若重命名 `member.role` / `channel_user_binding.bound_at` 这类列会在**运行时**才暴露——缓解手段是 §7 的真库测试全部覆盖这两条 SQL（`ARCHITECTURE.md` §7 已要求 DB 测试真跑 PostgreSQL 而非 skip 假绿），并在 CUSTOM.md 登记行的"合并注意"里写明这两条 SQL 依赖的列清单。
- **范围收紧（本次回修）**：裸 pgx 的职责从“读链 + 凭据”收窄为仅“**可区分分类**”——凭据一步改走既有上游 `GetInWorkspace`（sqlc）。这同时解了 BL-1 与“裸 SQL 列依赖面”两个问题：安装侧只剩 `ci.id`/`ci.workspace_id`/`ci.channel_type`/`ci.status` 四个**平展列**被裸 SQL 引用，`config` JSONB 的内部形状（`app_id`/`app_secret_encrypted`/`tenant_key`/`region` + base64 宽容解码）完全不进 fork 代码，上游改 config 形状时本 CR 零改动。

## DD-3 `SendApprovalReminderCard` 进 `APIClient` 接口

- **Decision**：在 `client.go` 的 `APIClient` 接口加一行方法声明（唯一接口面改动，带 `// AIFIRST:`），实现与参数类型全部落在自研文件 `approval_reminder_card.go`（含 `*httpAPIClient` 与 `*stubAPIClient` 两个方法，Go 同包跨文件定义方法，故 `http_client.go` 正文只动 §4.5 的 helper 提取）。
- **Context**：`SendInteractiveCard` 走 `outboundMessageRequest`，`receive_id_type` 固定 `chat_id`，无法寻址 open_id 私聊；`SendBindingPromptCard` 的卡片体与 CTA 不同。所以必须有新方法。放接口上会连带要求 4 个上游测试替身（`outbound_test.go#fakeAPIClient`、`outcome_replier_test.go#stubAPIClientWithRecorder`、`typing_indicator_test.go#fakeTypingAPIClient`、`inbound_enricher_test.go#enricherFakeClient`）各补一个空实现。
- **Alternatives**：不进接口——`NewHTTPAPIClient` 返回的是 `APIClient` 接口值，提醒器只能对自研窄接口做**运行时类型断言**取能力。零上游文件改动，但断言失败是静默的：上游哪天给 `APIClient` 套一层装饰器，提醒功能会无声停摆而不是编译报错。对一个审批感知链路，"静默停摆"比"多改 4 个测试替身"贵得多。
- **Consequences**：编译期保证 wiring 正确；代价是 5 个上游文件（`client.go` + 4 个测试文件）各有一处最小改动，全部 `// AIFIRST:` 标记并登记 CUSTOM.md，双周 rebase 时逐条核对。

## DD-4 事件名与载荷类型放在共享 `pkg/protocol`（BL-4）

- **Decision**：`EventCRApprovalGateEntered` 与 `ApprovalGateEnteredPayload` 声明在 `server/pkg/protocol/events.go`；`governance` 侧取常量别名（`const EventCRApprovalGateEntered = protocol.EventCRApprovalGateEntered`）并发布该结体，lark 侧直接 `v.(protocol.ApprovalGateEnteredPayload)` 类型断言。
- **Context**：初稿把常量与载荷类型放在 `governance/crsync.go`，同时又要求 lark 不依赖 governance——这两条同时成立时，`events.Event.Payload` 是 `any`，lark **既无法断言该类型，也没有稳定的事件名来源**（BL-4 原文）。fork 自己已有现成口径：`protocol/events.go:191-196` 的 `EventCRUpdated` 就是为此而存，注释明写「governance.EventCRUpdated references this constant rather than duplicating the string literal」。另一个硬事实：总线事件会经 `listeners.go` 的 `SubscribeAll` 广播到 workspace 房间，所以载荷**本身就是一份 WS 帧契约**——`pkg/protocol` 正是全仓存放 WS 契约类型的包（`messages.go` 里已有 20+ 个 `*Payload` 结体）。
- **Alternatives**：
  1. **map/JSON envelope 契约**（BL-4 允许的第二选项）：发布 `map[string]any`，两侧各自维护键名常量 + 回归测试锁形状。FR-10 文件集不动，但键名契约仍靠两处字面量对齐，上游/本侧任一侧改键名不会 build 失败——只会在运行时静默不发卡。**若审批驳回 DD-4，退化到本选项**，并须补两侧契约测试（生产侧断言 map 键集与值类型、消费侧断言缺键/错类型时走 malformed 分支）；
  2. lark 直接 import governance：也能得到编译期契约且不动 FR-10 文件集（已核当前无循环：governance 只依赖 events/middleware/scheduler/service，且这些包不依赖 lark），但把主体为上游的 `integrations/lark` 变成依赖 fork 专有包的 sibling——与 `ARCHITECTURE.md` §4 的分层方向相背，且一旦 governance 的依赖闭包将来碰到 lark 就是循环；
  3. 结构式接口断言（lark 本地宣告一个带 getter 的接口，governance 载荷实现它）：无需共享包，但方法名漂移时仍是运行时静默失败，与 DD-3 已否决的"运行时断言"同一类风险。
- **Consequences**：两侧获得真正的编译期契约（字段/类型/事件名任一处漂移 → build 失败），且不引入新依赖方向（两侧均已 import `pkg/protocol`，它自身零 `internal/` 依赖）。**代价与边界**：① 改动文件集多一个 `server/pkg/protocol/events.go`，超出 FR-10 字面清单，已在 §0/§6/§8 显式标出供 `approve-tech-design` 确认（本 SDD 不自行改 PRD）；② CUSTOM.md 需新增一行登记该常量与载荷类型（先例 #22/#23 同文件）；③ 载荷 json tag 成为客户端可见契约，今后只允许加字段（§3.2.1 不变量 6）。

---

# 6. FR 到技术实现映射

| FR | 技术实现 | 落点 |
|---|---|---|
| FR-1 门禁进入语义事件 | `protocol.EventCRApprovalGateEntered` + `protocol.ApprovalGateEnteredPayload`（共享包声明）+ governance 侧常量别名 + `approvalGateStatuses` + `publishApprovalGateEntered`，仅在 `applyStatus` 可信分支、`from != to`、目标 ∈ 四门禁时发布；载荷四字段含可空 `shell_issue_id`（= FR-1 的「CR/issue 关联标识」） | §3.2.1 / `pkg/protocol/events.go` + `governance/crsync.go` |
| FR-2 触发面隔离 | 不订阅 `EventCRUpdated`；不在 `found==false` 首见分支、`else`（needs_reconcile）分支、`checkpoint`/`review`/`trace`/default 分支、`reconcile.go`、`gate_projection.go` 发布；自环由 `from != to` 过滤 | §3.2.1 五条契约不变量 |
| FR-3 项目/workspace 解析 + 跨 workspace fail-closed | 单条 INNER JOIN SQL，`cr`/`issue`/`project`/`workspace` 四跳全带 `workspace_id = $1`；零行→跳过；原因判定的第二次查询仍带 workspace 谓词，且不产出收件人 | §4.4 第一条 SQL / §4.2 步骤 3 |
| FR-4 收件人角色筛选 | `SELECT user_id FROM member WHERE workspace_id = $1 AND role IN ('owner','admin')`，与 Web 侧 `roleAllowed(role,"owner","admin")` 同口径；空集 → `no-approver` | §4.2 步骤 3 |
| FR-5 有效绑定、去重、可区分跳过 | LEFT JOIN 候选查询 + `chooseEffective`（三条件判定，产出 4 种原因）+ 水化后租户/状态复核；`bound_at DESC, id ASC` 取最新 ⇒ 每用户一张卡；**`attemptedOpenIDs` 在发送前登记**做 open_id 级二次去重（BL-2） | §4.2 / §4.3 / §4.4 第二条 SQL |
| FR-6 卡片最小内容 | `approvalReminderTemplate`：header `待人工审批` + CR ID/标题 + 阶段名 + 固定说明 + 单一 button `前往审批`；模板内无 approve/reject action、无正文/证据/diff | §3.2.2 / `approval_reminder_card.go` |
| FR-7 CTA 与基地址 | `appURL + "/" + slug + "/projects/" + projectID + "?tab=chat"`；`appURL == ""` → `app-url-missing` 且零发送；**不新增** URL 合法性校验器 | §4.2 步骤 2/3 |
| FR-8.1 非阻塞边界 | 回调零 I/O；`chan struct{}` 非阻塞信号量（默认 8，过载 `overloaded` 丢弃不排队）；`context.Background()` 派生；60s/10s 有界超时；goroutine 自持 `recover` | §4.1 / §4.2 |
| FR-8.2 结构化可观测 | `logSent` / `logFail` / `logFailEvent` / `logSkip` 四入口，字段按 PRD §4.4 表（落地口径见 §4.6）；`reason` 受限于 9 项枚举常量；DB / 凭据 / 发送错误一律进 `failed` + `error_class` + `step`，不占用 `reason` | §4.2 / §4.6 / §7.3 |
| FR-8.3 未启用仍消费 | `Register` 调用点在 `MULTICA_LARK_SECRET_KEY` 条件块**之外**；步骤 1 在任何 DB 查询前判 `client==nil / !IsConfigured() / credentials==nil` → `feishu-disabled` 返回；stub 方法零 HTTP | §3.2.3 / §4.2 步骤 1 |
| FR-8.4 失败隔离与 crash window | 全链只读、无事务、发布点之后；发送失败/超时只记日志；不做异步前状态二次校验、不做撤回、不做 drain/join、不引入 outbox/幂等键 | §4.2 关键约束 |
| FR-9 发送能力复用边界 | 单一用途 `ApprovalReminder`（只做解析/收件人/发送/记账）+ `SendApprovalReminderCard` + `ApprovalReminderParams`；模板封装在 client 侧；`sendCardToOpenID` 私有 helper 与绑定提示共用；**不**公开卡片 JSON 接口、**不**抽象跨渠道 notifier | §3.2.2 / §4.5 |
| FR-10 零改动边界 | 改动面：`governance/crsync.go`、`lark/approval_reminder.go`（新）、`lark/approval_reminder_card.go`（新）、`lark/client.go`（1 行接口）、`lark/http_client.go`（helper 提取）、`cmd/server/router.go`（wiring）、**`pkg/protocol/events.go`（+1 常量 +1 载荷类型，BL-4 回修新增，超 FR-10 字面清单一处——待审批确认）**、6 个测试文件（4 个替身补空实现 + 2 个新测试文件）、`CUSTOM.md` 登记。零改动：`tools/` 全部、schema/migration、CR 账本、`governance/approval.go`、Web 审批页与 API、grant daemon、`pkg/db/queries/*`、`pkg/db/generated/*`、`packages/`（前端对未知事件类型 no-op，§1.3 已核） | §5 DD-2/DD-3/DD-4 |
| FR-11 启用条件不新增配置 | 无新环境变量、无 feature flag、无用户通知偏好；启用条件全部由既有事实（密钥/角色/绑定/项目链/基地址）判定，不满足即按枚举原因跳过 | §4.2 |

**FR-1 载荷字面：初稿的“有意收窄”已被评审驳回，本次改回携带（BL-3）**。初稿的 `Payload` 只带 `cr_id`/`status`/`event_id`，并自行裁定不带 issue 标识“符合最小标识”。评审结论（sdd.yml BL-3）：**SDD 不得自行把已审批的 FR 改成“有意收窄”**。现采纳评审给出的第一选项：载荷增加可空 `shell_issue_id *string`，取值来自 `applyStatus` 开头那条既有 `SELECT`（扩为两列，零额外往返，§3.2.1）。

两个必须同时成立的约束（否则违反 FR-3 与 ARCHITECTURE §7）：

1. 该字段**只作相关/诊断**，永不作为查询输入；目标项目仍由 §4.4 第一条 SQL 从 `cr` 行重新解析（bus 不是持久权威，handler 必须可重放）；
2. 它可为 `null`（历史 CR 的 `shell_issue_id IS NULL`），消费侧不得把 `null` 当错误——仍走 `project-unresolved` 跳过口径。

回归锁：AC-10 的跨 workspace 负向测试新增一项“**载荷的 `shell_issue_id` 被伪造成另一个 workspace 的 issue 时仍零发送**”（证明它真的没进查询路径，§7.4）。

---

# 7. 安全与性能考量

## 7.1 安全控制点

| 风险 | 控制 |
|---|---|
| CR 标题跨 workspace 外泄 | 唯一锚点来自 DaemonAuth（`resolveDaemonWorkspace`）；读链四跳 + 成员 + 绑定 + 安装**每跳**带 `workspace_id = 锚点`；任一跳不符即整体跳过、不放宽重查、不跨 workspace 兜底。审计口径：提醒器的全部 DB 访问面 = §4.4 两条裸 SQL + 成员查询 + `GetInWorkspace`（后者自带 id+workspace_id+channel_type 三谓词），**不存在**仅按主键/仅按外键的查询路径，可静态核对 |
| 凭据读取的租户闭合（BL-1） | 凭据不由裸 SQL 组装，而走 `InstallationService.GetInWorkspace(id, 锚点)`；水化后额外复核 `inst.WorkspaceID == 锚点` 与 `inst.Status == 'active'`。即“分类”与“取凭据”两次都带租户谓词，任一跳失效即零发送 |
| 新事件经 WS 扇出到 workspace 房间 | 已核实：`listeners.go` 的 `SubscribeAll` 会把本事件广播给该 workspace 的客户端（不跨 workspace）。载荷只有 `cr_id`/`status`/`event_id`/`shell_issue_id`——**无标题、无评审证据、无收件人、无凭据**，而同房间既有 `cr:updated` 已广播 CR 状态，故**未新增外泄面**；Web 审批页本身就向 workspace 成员展示这些标识。不为此改 `listeners.go` 的 `personalEvents`/`internalOnlyPayloadKeys`（那才是真正超 FR-10 改动面） |
| 越权收到提醒 | 收件人只取 `role IN ('owner','admin')`；`member` 角色与未绑定用户零发送 |
| 卡片成为绕过签名审批的入口 | 卡片只有一个 `url` 类型 button，无 action/callback、无 token；审批权威仍在 Web 签名链路与 `crctl` 门禁，点 CTA 后由既有链路重新校验（`governance/approval.go` 零改动） |
| 凭据泄漏 | `InstallationCredentials.AppSecret` 只在单次调用在飞期间存在，不落日志、不落库；日志只出 `recipient_open_id`，不出凭据、token、签名材料、diff、飞书响应体原文（`error_class` 只记类别） |
| 撤销安装后仍可发送 | 有效绑定强制 `installation.status = 'active'` + 同 workspace + `channel_type='feishu'`；revoked / orphan / mismatch 三类各自跳过并留可区分原因 |
| 恶意/异常 payload | `handleEvent` 只做类型断言与非空校验，字段异常直接丢弃记 warn；防御性二次过滤 `approvalGateStatuses` |

## 7.2 性能目标与边界

| 指标 | 目标 | 保障手段 |
|---|---|---|
| `HandleCREvents` 时延增量 | 与"无提醒器"基线同量级（仅解析开销） | 回调零 I/O + 非阻塞信号量；AC-11 用阻塞替身 + 零调用断言 |
| 单收件人发送 | ≤ 10s | `WithTimeout(ctx, 10s)`，与 `Patcher.handleEvent` 同口径 |
| 单事件整体 | ≤ 60s | `WithTimeout(Background(), 60s)`；超时按失败记日志，不重试 |
| 在飞提醒并发 | ≤ `MaxInFlight`（默认 8） | 容量固定的 `chan struct{}` + 非阻塞 acquire；过载丢弃记 `overloaded` |
| 单事件 DB 往返 | 2 + 2N 次（链路 1 + 成员 1 + 每收件人：候选查询 1 + `GetInWorkspace` 1；链路零行时 +1 次原因判定） | N = owner/admin 数，正常个位数；凭据水化只对**选中**的安装做一次（BL-1 引入的额外往返上限） |
| 进程崩溃/退出 | 允许在飞提醒丢失 | 不引入 outbox / 持久化 / drain / 补偿 |

## 7.3 工程纪律落点（CONTRIBUTING.AIFIRST）

- **规则一/二**：自研逻辑集中在两个新文件；上游文件只留最小挂钩（`client.go` 1 行、`http_client.go` helper 提取、`router.go` wiring、4 个测试替身），每处 `// AIFIRST: CR-2026-051 …` 标记；
- **规则五**：两个新文件预算内（预估各 < 400 行），远低于 800 行提醒线；不新增包级可变全局状态（`MaxInFlight` / 超时 / 依赖全走构造注入）；
- **规则六**：9 个跳过原因 + 4 类 `error_class` + 6 个 `step` 均集中声明为常量（不散拼字符串）；构造参数不静默忽略、依赖缺失不返回 nil（§3.2.3）；卡片模板、`chooseEffective`、`parsePayload` 均为独立可单测的小单元；
- **CLAUDE.md**：multica 仓内新增/改动的代码注释一律英文（本 SDD 中文，代码英文）；
- **CUSTOM.md（评审强制项，不得拿 CUSTOM #5 顶替）**：本 CR 落码后按彼时 CUSTOM.md 现状顺延登记**一行新条目**（#5 只覆盖 governance 包的 pgx 例外，不覆盖 lark 包），"合并注意"列写明：① `crsync.go` 发布点需随上游事件机制改名跟改；② **§4.4 两条裸 SQL 依赖的列清单**（`cr.shell_issue_id`/`cr.title`、`issue.project_id`、`project.id`、`workspace.slug`、`member.role`、`channel_user_binding.bound_at`/`channel_user_id`/`multica_user_id`/`installation_id`/`channel_type`/`workspace_id`、`channel_installation.id`/`status`/`channel_type`/`workspace_id`——注明 `config` JSONB **不**在裸 SQL 依赖面内，由 `installationFromRow` 解码）；③ `APIClient` 接口新方法与 4 个测试替身空实现须整组保留；④ `pkg/protocol/events.go` 的常量与载荷类型（与 #22/#23 同文件，上游新增事件类型时取并集）；⑤ 依赖的上游凭据入口（`InstallationService.GetInWorkspace` / `installationCredentialsFor`）——上游改签名则跟改。

## 7.4 测试设计（对齐 AC-1～AC-13）

| 测试 | 覆盖 AC | 要点 |
|---|---|---|
| `governance`：四门禁 × 合法转换各发布一次 | AC-1 | 真库；断言事件类型、`workspace_id`、payload 三字段与 `event_id` 形状 |
| `governance`：误触发隔离 | AC-2 | 通用 `cr:updated` 不触发；重放（`curStatus != FromStatus`）、自环（`from == to`）、checkpoint/review/trace、首见分支、reconcile/gate_projection 均零发布；断言订阅集合不含 `EventCRUpdated` |
| `lark`：happy path 多收件人 | AC-3 | 每个有效绑定 owner/admin 一张卡；同用户多绑定只发一张（取 `bound_at` 最新）；同 open_id 只发一次 |
| `lark`：**首个尝试失败 + 重复 open_id**（BL-2 回归） | AC-3、FR-8.2 | 两个不同 user 指向同一 `open_id`，第一个发送返错：断言客户端**只被调用一次**、第二个用户无发送且无日志重复尝试；同型用例覆盖“首次凭据解密失败”与“首次超时” |
| `lark`：**凭据水化四态**（BL-1 回归） | AC-3、AC-4、AC-10 | ① happy：`GetInWorkspace` 返回完整安装 → 发送时 `InstallationCredentials` 的 `AppID`/`AppSecret`/`TenantKey`/`Region` 均与库里一致（真库 + 真 secretbox）；② `ErrInstallationNotFound` → `installation-missing` 跳过；③ 水化后 `status='revoked'` → `installation-revoked`（分类后被撤销的 TOCTOU 窗）；④ 水化后 `workspace_id` 不符 → `workspace-mismatch`。另断言安装属另一 workspace 时 `GetInWorkspace` 本身就查不到 |
| `governance`+`lark`：**共享契约**（BL-4 回归） | AC-1、AC-9 | 生产侧发布的 `Payload` 可被消费侧 `v.(protocol.ApprovalGateEnteredPayload)` 直接断言成功（同一包类型）；golden JSON：`json.Marshal(payload)` 等于 `{"cr_id":…,"status":…,"event_id":…,"shell_issue_id":…}`（`null` 形态单独一例）；递交 `map[string]any` 或异类型时 `parsePayload` 返回 false 且零 DB/HTTP |
| `lark`：**载荷 shell_issue_id 不参与解析**（BL-3 回归） | AC-10 | 载荷带上另一 workspace 的 issue id（伪造）时，仍以 `cr` 行为准解析；当 CR 本身的 `shell_issue_id IS NULL` 时 → 零发送 + `project-unresolved`（证明载荷未进查询路径） |
| `lark`：**事件级/收件人级 failed 日志** | AC-7、FR-8.2 | 注入 pool 报错替身：链路查询失败 → 一条 `result=failed`、`step=project-chain`、无 recipient 字段、**不出现任何 `reason`**；绑定查询失败 → 收件人级 `failed`（`step=binding-query`）而非 `binding-missing` |
| `lark`：**依赖缺失不 panic** | AC-12、AC-13 | `NewApprovalReminder` 在 `Pool`/`Client`/`Credentials` 任一为 nil 时返回非 nil 对象；`Register(bus)` + 发布一条真事件后进程存活、一条 `feishu-disabled`、零 DB；另一例把 typed-nil `*InstallationService` 给进去也不 panic |
| `lark`：四类不发送 | AC-4 | `member` 角色 / `binding-missing` / `installation-revoked` / `installation-missing` 各留可区分 reason |
| `lark`：卡片与 CTA | AC-5 | 模板断言五项最小内容 + 无 approve/reject action；CTA 等于 `{appURL}/{slug}/projects/{projectID}?tab=chat`；`appURL==""` 零发送 |
| `governance`：Web 审批链路回归 | AC-6 | 既有 `approval*_test.go` / `project_gates_test.go` 原样通过，不修改 |
| `lark`：三类日志字段 + 无回滚 | AC-7 | 断言 §4.4 必需字段齐全、`reason` 落在 9 项枚举内；失败/跳过下投影仍成功 |
| 静态改动面核对 | AC-8 | `git diff --name-only` 与 FR-10 声明集合逐条比对；断言无新 migration、`pkg/db/queries`/`generated` 零改动、`tools/` 零改动 |
| `lark`：跨 workspace 负向 | AC-10 | issue/project/绑定/安装任一层 workspace 不符 → 零发送 + `workspace-mismatch`；静态核对提醒器内无"仅按主键/仅按外键"查询 |
| `lark`+`governance`：阻塞替身 | AC-11 | 客户端替身阻塞至超时：`HandleCREvents` 时延与无提醒器基线同量级、投影不变、无回滚；bus 回调内 DB/HTTP 替身零调用 |
| `lark`：stub 形态 | AC-12 | 未设 `MULTICA_LARK_SECRET_KEY`：事件被消费、一条 `feishu-disabled` 事件级跳过、`NewStubAPIClient` 零真实请求、读链零查询（pool 替身零调用） |
| `lark`：panic 与过载 | AC-13 | goroutine 内注入 panic → 被自持 recover 记日志、进程存活；`MaxInFlight=1` 占满后新事件记 `overloaded`、不排队、不重试 |
| `lark`：绑定提示行为等价 + 审批卡五类 | §4.3 兼容性、FR-9 | `http_client_test.go` 三处既有 `SendBindingPromptCard` 断言**不修改**即通过（helper 提取的回归锁）；另补审批卡的参数校验 / 成功 / token 失效 / JSON 转义 / stub 五类（§4.5 表） |

DB 相关测试须在可用 PostgreSQL 环境取到无 skip 的 `=== RUN` / `--- PASS` 证据（CUSTOM.md C6：包级 `TestMain` 在 DB 不可达时整包 skip，会产生 exit 0 假绿；**不得为此改 TestMain**）。

---

# 8. 残余风险与未决项

| 项 | 说明 | 处置 |
|---|---|---|
| **FR-10 改动面 +1 文件（需审批确认）** | BL-4 的修复把事件名与载荷类型放进 `server/pkg/protocol/events.go`（+1 常量 +1 结构），而 FR-10 字面清单未列该文件（AC-8 逐条核改动面） | 本 SDD **不自行改 PRD**。请 `approve-tech-design` 二选一：① 确认该 delta（AC-8 核对时计入合法改动集）；② 驳回 → 退化到 DD-4 备选 1（map/JSON envelope + 两侧契约测试），改动面回到 FR-10 字面内，代价是失去编译期契约 |
| 事件级 `failed` 日志无 recipient 字段 | PRD §4.4 把 `recipient_*` 挂在“成功/失败”上，而链路/成员查询报错发生在收件人集合存在之前 | 沿用 PRD 自己的条件字段模式（事件级跳过已无 `recipient_open_id`），属**加法细化**、不删不改已有必需字段（§4.6 第 5 条）；审批可见，若不接受则改为输出空值 recipient 字段 |
| 新事件会进 WS workspace 扇出 | `listeners.go` 的 `SubscribeAll` 对所有事件生效，本事件因此成为一份客户端可见的加法契约（前端当前 no-op） | 载荷无标题/证据/收件人，与同房间已有 `cr:updated` 同级别（§7.1）；本 CR 不改 `listeners.go`、不改前端；今后只允许加字段 |
| DD-2 的运行时列名风险 | 裸 SQL 无编译期列名校验（本次已把 `config` JSONB 形状排出裸 SQL 依赖面，风险面缩到四个平展列） | 真库测试覆盖两条 SQL + CUSTOM.md 登记列清单（§7.3）；评审已采纳该 seam（DD-2 Status） |
| `MaxInFlight` 默认 8 | 无生产数据支撑的经验值 | 收件人规模个位数、单事件 ≤60s，8 足以覆盖正常并发；构造参数可调，不新增环境变量（FR-11） |
| `cr.title` 可能为空 | 迁移 362 默认 `''`，由 reconcile 回填 | 卡片模板空标题时只渲染 CR ID，不渲染空行 |
| 凭据水化多一次往返 | 每个有效收件人 +1 次 `GetInWorkspace`（§7.2） | 收件人个位数、均为主键+租户索引命中；**不**做安装级缓存（缓存会把刚被撤销的安装变成可用凭据） |

**上一轮的三项未决点已关闭**（attempt 1 评审已给结论，不再作风险留存）：DD-2 裸 pgx seam = 采纳（附三条强制条件，已落地）；§4.5 helper 提取 = 采纳（附五类测试，已落地）；载荷收窄 = 驳回（已改回携带可空 `shell_issue_id`）。

**§8「Prompt 采纳影响」不触发**：本 CR 不改 `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支，也不改 `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny`（`tools/` 整包零改动），crctl 命令面与 guard deny 面均无新增或变更，故条件性小节按 Skill 规则省略。

---

# 9. 修订记录

| 版本 | 时间 | 变更 |
|---|---|---|
| 初稿 | 2026-08-25T20:34:02+08:00 | 首版。基于 PRD `b64a92cf…`（11 FR / 5 US / 13 AC）与 multica worktree 实地核实的 15 条既有事实；含 6 项术语硬化、3 条决策记录（DD-1 event_id / DD-2 pgx 读 seam / DD-3 接口方法）、FR-1～FR-11 全映射、13 项 AC 测试设计。已收 quality-reviewer 两条实现期建议：① `event_id` 绑定账本幂等键投影并贯穿三类日志（DD-1、§4.4 字段）；② CTA 按锚定 `workspace_id` 读 `workspace.slug`（§4.4 第一条 SQL 的 `JOIN workspace w ON w.id = $1`）并补跨 workspace slug 回归断言（AC-10 测试项）。 |
| 技术评审 attempt 1 回修 | 2026-08-25T21:33:00+08:00 | 按 `review-annotations/sdd.yml`（verdict `block`，BL-1～BL-4 均 P1）定点修复，方案骨架（专用事件 → 非阻塞回调 → 异步 fail-closed 读链 → 单次投递）未变。<br>① **BL-1 凭据路径**：裸 SQL 职责收窄为“可区分分类”，凭据改走既有 `InstallationService.GetInWorkspace`（id+workspace_id+channel_type 三谓词，`installationFromRow` 解 `config` JSONB）+ `installationCredentialsFor`；新增窄接口 `installationCredentialSource`、水化后租户/状态复核、查询与解密失败的结构化 `failed` 日志（§1.1、§1.3、§3.2.3、§4.2、§4.3、§4.4、§4.6）。<br>② **BL-2 去重语义**：`sentOpenIDs` → `attemptedOpenIDs`，登记提到任何可失败动作之前；补“首个尝试失败 + 重复 open_id”回归（§4.2、§6 FR-5 行、§7.4）。<br>③ **BL-3 载荷**：撤销初稿的“有意收窄”，载荷新增可空 `shell_issue_id`（取自 `applyStatus` 既有 SELECT 扩为两列，零额外往返），并硬约束“只作相关、不作查询输入” + 伪造载荷的负向断言（§2、§3.2.1、§6、§7.4）。<br>④ **BL-4 跨包契约**：事件名与载荷类型上提到共享叶子包 `pkg/protocol`（先例：同文件的 `EventCRUpdated`、CUSTOM #22/#23），两侧真类型断言 + canonical JSON 契约 + 两侧契约测试（新增 DD-4）；同时把“FR-10 改动面 +1 文件”显式列入 §0/§6/§8 供审批裁定，**未自行改 PRD 字面**。<br>三项评审定案已内化：DD-2 采纳（附凭据读取、租户闭合、CUSTOM.md 新增条目三条强制条件）、§4.5 提取采纳（附参数校验/成功/token 失效/JSON 转义/stub 五类测试）、§8 Prompt 跳过确认成立。<br>三条非阻塞建议已处理：相关键口径 `(workspace_id, event_id)`（DD-1）、依赖缺失不返 nil + typed-nil 接口防护（§3.2.3）、DB 读错统一进结构化 `failed`（§4.6）。<br>另修正/新增两条核实事实：飞书未启用时 `h.LarkAPIClient` 是 **nil 而非 stub**（初稿措辞错）；本事件会经 `listeners.go#SubscribeAll` 进 WS workspace 扇出（已评估：无新增外泄面、前端 no-op、前端零 diff）。 |

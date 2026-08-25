---
id: CR-2026-051-sdd
type: SDD
cr-ref: CR-2026-051
title: IM 渠道审批接入 — 飞书审批提醒卡片（通知型 MVP） 技术设计
status: draft
created: 2026-08-25T20:34:02+08:00
updated: 2026-08-25T20:34:02+08:00
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

本 SDD 只做技术方案，不改 PRD 的 FR/AC 与范围红线（设计稿 §2.2 排除项）。

---

# 1. 架构概览

## 1.1 模块边界

新增三个**自研文件**（全部在 multica 仓），加两处最小挂钩：

```text
server/internal/governance/crsync.go                    [改：挂钩点，~15 行]
  └─ applyStatus() 可信转换分支 → publishApprovalGateEntered()
        │ events.Bus.Publish（同步、进程内）
        ▼
server/internal/integrations/lark/approval_reminder.go   [新：自研，提醒器]
  ├─ Register(bus)                     订阅 cr:approval-gate-entered（无条件注册）
  ├─ handleEvent(e)                    ★ bus 回调：仅解析 + 信号量 TryAcquire + go
  └─ deliver(ctx, ev)                  异步：读链 → 收件人 → 逐个单次发送 → 日志
        │
        ├──► reminderReader（同文件内私有）  workspace-closed 只读链（pgx）
        └──► approvalCardSender             APIClient.SendApprovalReminderCard

server/internal/integrations/lark/approval_reminder_card.go [新：自研，卡片与传输]
  ├─ ApprovalReminderParams            最小参数类型
  ├─ approvalReminderTemplate()        卡片 JSON 模板
  ├─ (*httpAPIClient) SendApprovalReminderCard()   真实传输（open_id 私聊）
  └─ (*stubAPIClient) SendApprovalReminderCard()   stub：Warn + ErrAPIClientNotConfigured

server/internal/integrations/lark/client.go              [改：挂钩点，1 行接口方法]
server/cmd/server/router.go                              [改：挂钩点，~10 行 wiring]
```

依赖方向（不新增反向依赖）：

```text
cmd/server/router.go            composition root：构造 + 订阅（在飞书密钥条件块之外）
  → integrations/lark（提醒器 + 卡片 + 传输）
  → internal/events.Bus（只订阅，不改）
  → pgxpool（只读）、InstallationService（只解密凭据）
governance/crsync.go            只发布事件，不认识 lark 包（单向）
```

`governance` 不 import `lark`，`lark` 不 import `governance`：两侧只通过 `events.Bus` 的事件类型字符串耦合。这是 `ARCHITECTURE.md` §4「fork governance may consume existing services and events, but must not duplicate task execution / Git transactions / CR state machines」的合规形态。

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
  │ 4. 逐个收件人：WithTimeout(ctx, 10s) → SendApprovalReminder│
  │ 5. 三类结构化日志（§4.4 字段口径）                         │
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
| 凭据来源 | `InstallationService.DecryptAppSecret(inst)`（`CredentialsResolver` 接口，定义于 `outbound.go:159`）；`Installation` 结构见 `store.go:42`（`AppID`/`AppSecretEncrypted`/`TenantKey`/`Region`/`Status`/`WorkspaceID`） |

---

# 2. 术语硬化（Step 2.5 前置，首次状态推进前完成）

只处理进入数据模型 / 状态机 / 接口契约、且存在歧义或别名的术语。`CONTEXT.md` 与 PRD §1.3 术语表只读沿用。

| PRD canonical term | 代码别名 / 取值 | 边界场景（已验证） | 硬化结论 |
|---|---|---|---|
| 飞书渠道 | Go 包名 `lark`；DB 判别值 `channel_type = 'feishu'`；`Installation.Region` 区分 Feishu 大陆 / Lark 国际 | 迁移 124 把既有行 backfill 成 `channel_type='feishu'`；`'lark'` **不是**合法判别值 | 一切 DB 谓词写 `'feishu'`；包名/类型名沿用 `lark` 前缀（传输族），二者不互推 |
| **stage（审批阶段）** | ① `approval_record.stage` = `gates.json#approvalStages` 四键（`requirement`/`tech-design`/`dev-start`/`code`）；② PRD §4.4 的日志 `stage` = **事件的新状态**（`requirement-reviewing` 等） | 两者一一对应但**字面不同**，混用会让日志检索与审批账本对不上 | 日志字段 `stage` **一律取 CR status 字面值**（`requirement-reviewing`/`tech-design-review-pending`/`task-breakdown`/`code-reviewing`）；卡片上的中文阶段名是**展示层映射**（§4.3 表），不落日志、不与 `approval_record.stage` 混用；本 CR 不读写 `approval_record` |
| 有效（飞书）绑定 | 代码无此概念；最近似的 `FindChannelBindingForMember` 只校验 `b.workspace_id` + `b.channel_type` + `ci.status='active'` | 安装被撤销后绑定行保留（`status='revoked'`）；`installation_id` 可悬空（无外键）；`ci.workspace_id` 未被校验 | SDD 定义 `effectiveFeishuBinding` = PRD FR-5 三条件，**不**把 `FindChannelBindingForMember` 当唯一判据（§5 DD-2） |
| event_id | `events.Event` 无此字段；`cr_sync_event` 有 PK `id BIGSERIAL` 与幂等键 `(workspace_id, cr_id, commit_sha, event_kind)` | `--embedded` 模式 `commit_sha` 为 `pending:{ms}:{pid}:{seq}` 占位符——仍逐事件唯一，幂等键不退化 | `event_id = "{cr_id}:{event_kind}:{commit_sha}"`（§5 DD-1） |
| recipient | Multica `user.id`（权威）vs 飞书 `open_id`（= `channel_user_binding.channel_user_id`） | PRD §4.4 已定口径 | 日志 `recipient_user_id` 必填、`recipient_open_id` 仅发送成功/失败时出现；去重第一键是 user id |
| workspace 锚点 | `HandleCREvents` 中 `resolveDaemonWorkspace(r, s.pool)` 的返回值 | 请求体 `workspace_root_hash` 仅日志用，不可作信任输入（既有 SDD-SUG-002） | 锚点只能来自 DaemonAuth；`events.Event.WorkspaceID` 承载它，消费侧不得用读到的任何 `workspace_id` 覆盖锚点 |

**无语义冲突需要需求负责人裁决**，故未中断流程。

**HTTP/REST 契约：不触发。** 本 CR 不新增或修改任何 HTTP API（无新路由、无新请求/响应体、无鉴权面变化）；`router.go` 的改动只是进程内 wiring 与事件订阅。故本 SDD 不含接口契约中的 HTTP 章节，§3 只写进程内接口。

---

# 3. 数据模型与接口契约

## 3.1 数据模型：零 DDL

**不新增表、不新增列、不新增索引、不新增 migration。** 全部为只读消费既有表：

| 表 | 读取列 | 用途 | 归属 |
|---|---|---|---|
| `cr` | `cr_id`、`workspace_id`、`title`、`shell_issue_id` | 事件锚定 + 卡片标题 + issue 关联 | fork（迁移 362） |
| `issue` | `id`、`workspace_id`、`project_id` | 项目解析 | 上游 |
| `project` | `id`、`workspace_id` | 项目存在性 + CTA projectID | 上游 |
| `workspace` | `id`、`slug` | CTA workspaceSlug | 上游 |
| `member` | `workspace_id`、`user_id`、`role` | owner/admin 收件人集合 | 上游（`role CHECK IN ('owner','admin','member')`） |
| `channel_user_binding` | `id`、`workspace_id`、`multica_user_id`、`installation_id`、`channel_type`、`channel_user_id`、`bound_at` | 绑定与 open_id | 上游（迁移 124） |
| `channel_installation` | `id`、`workspace_id`、`channel_type`、`status`、`config` | 有效性 + 发送凭据 | 上游（迁移 124） |

索引覆盖核实：`cr` 有 `UNIQUE (workspace_id, cr_id)`；`issue`/`project`/`member` 主键与 workspace 列既有索引足够（单次门禁收件人规模为个位数，读放大可忽略）；`channel_user_binding` 有 `UNIQUE (installation_id, channel_user_id)`。**无需新索引**。

## 3.2 进程内接口契约

### 3.2.1 事件契约（governance → bus → lark）

```go
// server/internal/governance/crsync.go

// AIFIRST: CR-2026-051 FR-1 — dedicated approval-gate semantic event.
// Deliberately NOT EventCRUpdated: that one is published from 5 sites
// (3x crsync, gate_projection, reconcile) and would fire on projection
// maintenance, not on a fresh approval request.
const EventCRApprovalGateEntered = "cr:approval-gate-entered"

// approvalGateStatuses are the four human-approval gates (PRD FR-1 cond. 4),
// verified against ../tools/dir-graph.yaml#change-request-track.state_machine.
var approvalGateStatuses = map[string]bool{
    "requirement-reviewing":      true, // 需求审批
    "tech-design-review-pending": true, // 架构审批
    "task-breakdown":             true, // 开发启动审批
    "code-reviewing":             true, // 代码审批
}

// ApprovalGateEnteredPayload carries only location identifiers. Approval
// evidence, titles, project ids and recipients are deliberately absent —
// the consumer re-reads them from PostgreSQL so handlers stay replayable
// (ARCHITECTURE.md §7: the bus is notification, not durable authority).
type ApprovalGateEnteredPayload struct {
    CRID    string `json:"cr_id"`
    Status  string `json:"status"`   // ev.ToStatus, one of the four gates
    EventID string `json:"event_id"` // "{cr_id}:{event_kind}:{commit_sha}"
}
```

发布点（`applyStatus` 可信分支内，`projectGateTransition` 之后）：

```go
// AIFIRST: CR-2026-051 FR-1/FR-2 — publish only from the trusted branch,
// only on a real status change, only for the four approval gates.
func (s *SyncService) publishApprovalGateEntered(workspaceID string, ev OutboxEvent) {
    if s.bus == nil || ev.FromStatus == ev.ToStatus || !approvalGateStatuses[ev.ToStatus] {
        return
    }
    s.bus.Publish(events.Event{
        Type:        EventCRApprovalGateEntered,
        WorkspaceID: workspaceID,
        ActorType:   "system",
        Payload: ApprovalGateEnteredPayload{
            CRID:    ev.CRID,
            Status:  ev.ToStatus,
            EventID: ev.CRID + ":" + ev.EventKind + ":" + ev.CommitSHA,
        },
    })
}
```

契约不变量（供 AC-1/AC-2 断言）：

1. 只在 `applyStatus` 的可信分支调用——`found == false` 的首次见闻分支**不**调用（`legalFresh` 为真也不调用：注册转移的目标状态不可能是四门禁之一，且首次见闻本身可能缺历史）；
2. `else` 分支（乱序 / 非法，只置 `needs_reconcile`）不调用；
3. `apply` 的 `checkpoint` / `review` / `trace` / default 分支不调用；
4. `reconcile.go`、`gate_projection.go` 不调用；
5. 自环（`from == to`）被条件 1 过滤。

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

type ApprovalReminderConfig struct {
    Pool        *pgxpool.Pool       // read-only; nil ⇒ reminder cannot run
    Client      APIClient           // nil or !IsConfigured() ⇒ feishu-disabled
    Credentials CredentialsResolver // InstallationService
    AppURL      string              // appURLFromEnv(); "" ⇒ app-url-missing
    Logger      *slog.Logger
    // MaxInFlight bounds concurrent deliveries (FR-8.1). 0 ⇒ default 8.
    MaxInFlight int
    // EventTimeout / RecipientTimeout default to 60s / 10s (FR-8.1).
    EventTimeout     time.Duration
    RecipientTimeout time.Duration
}

func NewApprovalReminder(cfg ApprovalReminderConfig) *ApprovalReminder
func (r *ApprovalReminder) Register(bus *events.Bus)  // Subscribe(EventCRApprovalGateEntered, r.handleEvent)
```

**API 参数不得静默忽略（CONTRIBUTING.AIFIRST 规则六）**：`MaxInFlight` / `EventTimeout` / `RecipientTimeout` 只有"0 值走文档化默认"这一种退化，非零值一律生效；`Pool == nil` 时构造函数直接返回 nil 并记 Error（不静默构造一个永不工作的提醒器）。

`Register` 的调用点在 `router.go` 中**飞书密钥条件块之外**（FR-8.3）：

```go
// AIFIRST: CR-2026-051 FR-8.3 — registered unconditionally, OUTSIDE the
// MULTICA_LARK_SECRET_KEY block. h.LarkAPIClient is the stub when Lark is
// disabled, so the reminder still consumes the event and logs a
// feishu-disabled skip instead of the subscription being absent.
lark.NewApprovalReminder(lark.ApprovalReminderConfig{
    Pool: pool, Client: h.LarkAPIClient, Credentials: h.LarkInstallations,
    AppURL: appURLFromEnv(), Logger: slog.Default(),
}).Register(bus)
```

`h.LarkAPIClient` 在密钥缺失时为 stub / nil、`h.LarkInstallations` 为 nil：提醒器在**任何 DB 查询之前**判定不可用（§4.2 步骤 1），故这两种形态都收敛到 `feishu-disabled`。

---

# 4. 关键算法与流程

## 4.1 同步侧（bus 回调）：零 I/O + 非阻塞

```text
handleEvent(e events.Event):
    # 只做解析与校验，禁止 DB / HTTP —— AC-11 用零调用替身断言
    p, ok := parsePayload(e.Payload)            # 类型断言 + 字段非空
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
    if r.client == nil || !r.client.IsConfigured() || r.credentials == nil:
        logSkip(event, "feishu-disabled"); return            # AC-12：零真实请求、零收件人查询

    # ── 2. CTA 基地址（零 DB）──────────────────────────────────
    if r.appURL == "":
        logSkip(event, "app-url-missing"); return            # 不发无效链接；不新增 URL 合法性校验器

    # ── 3. workspace-closed 读链（每跳带 workspace_id = 锚点）──
    ctx1 := 单条 SQL（§4.4）：cr ⋈ issue ⋈ project ⋈ workspace，三处 workspace_id = $1
    switch:
      no rows          → logSkip(event, "project-unresolved" | "workspace-mismatch"); return
      slug == ""       → logSkip(event, "workspace-mismatch"); return

    approvers := SELECT user_id FROM member WHERE workspace_id = $1 AND role IN ('owner','admin')
    if len(approvers) == 0:
        logSkip(event, "no-approver"); return

    approveURL := r.appURL + "/" + slug + "/projects/" + projectID + "?tab=chat"

    # ── 4. 逐收件人：判定有效绑定 → 单次发送 ──────────────────
    sentOpenIDs := {}
    for userID in approvers:                      # 个位数规模，顺序执行
        rows := 有效绑定候选（§4.4 第二条 SQL，LEFT JOIN installation）
        if len(rows) == 0:
            logSkip(recipient, userID, "binding-missing"); continue
        pick, reason := chooseEffective(rows)     # §4.3
        if pick == nil:
            logSkip(recipient, userID, reason); continue      # installation-revoked / -missing / workspace-mismatch
        if pick.OpenID in sentOpenIDs:
            continue                              # 第二道去重：同 open_id 单次事件只发一次
        creds, err := credentialsFor(pick.Installation)       # DecryptAppSecret
        if err != nil:
            logFail(userID, pick.OpenID, errClass(err)); continue
        rctx, rcancel := context.WithTimeout(ctx, r.recipientTimeout)   # 10s
        err = r.client.SendApprovalReminderCard(rctx, ApprovalReminderParams{...})
        rcancel()
        if err != nil: logFail(userID, pick.OpenID, errClass(err))      # 单收件人失败不影响同批其他人
        else:          sentOpenIDs.add(pick.OpenID); logSent(userID, pick.OpenID)
```

**关键约束的落点**：

- 异步开始时**不重新读 CR 状态**（FR-8.4）——语义是"曾实际进入该门禁"；不做消息撤回、不做补偿；
- `ctx` 由 `context.Background()` 派生，与 `r.Context()` 的生命周期完全解耦；
- 进程退出时在飞 goroutine 允许丢失，**不做 drain/join**（FR-8.4，与既有 crash window 口径一致）；
- 全链只读，无事务、无写入。

## 4.3 有效绑定选择与去重（`chooseEffective`）

输入是同一 `(workspace 锚点, userID, channel_type='feishu')` 下的全部绑定候选（每行带 LEFT JOIN 到的安装字段，可为 NULL）。

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

注意 `ci.workspace_id` / `ci.channel_type` / `ci.status` 只**取回**不在 SQL 里过滤——过滤放在 `chooseEffective` 里，正是为了产出可区分的跳过原因（若写进 WHERE，三种失效原因会全部退化成"零行"，AC-4 无法验收）。

凭据从选中安装行经 `InstallationService.DecryptAppSecret` 解出（`AppID` / `TenantKey` / `Region` 走 `Installation` 结构），与 Patcher / TypingIndicator 同口径。

## 4.5 私有 helper 提取（行为等价）

`SendBindingPromptCard` 与 `SendApprovalReminderCard` 的传输部分完全同构（`receive_id_type=open_id` + `msg_type=interactive` + tenant token + 错误码 / token 失效处理）。提取为 `http_client.go` 内私有 helper：

```go
func (c *httpAPIClient) sendCardToOpenID(ctx context.Context, creds InstallationCredentials, openID OpenID, cardJSON, op string) error
```

`SendBindingPromptCard` 改为调用它（**唯一一处对上游函数正文的改动，带 `// AIFIRST:` 标记**）。行为等价由既有测试锁定：`http_client_test.go#TestHTTPClient_SendBindingPromptCard_HappyPath` 及第 1270/1276 行的错误路径断言必须**原样通过、不修改**（§4.3 兼容性要求"现有绑定提示卡片行为不得因私有 helper 提取而改变"）。

> 若评审认为动上游函数正文的风险不可接受，退化方案是不提取、在自研文件内重写这段 ~30 行传输逻辑（代价：重复代码 + 两处 token 失效处理可能漂移）。本设计选择提取，因为既有测试对旧行为有充分锁定。

---

# 5. 技术选型与决策记录

只记录同时满足「难以逆转 + 无上下文会疑惑 + 有真实权衡替代」的三条。事件类型隔离（专用事件 vs `cr:updated`）已由 PRD FR-1/FR-2 拍板，不在此复述。

## DD-1 `event_id` 绑定到账本幂等键的字符串投影

- **Decision**：`event_id = "{cr_id}:{event_kind}:{commit_sha}"`，在 `publishApprovalGateEntered` 内由手上的 `OutboxEvent` 直接拼出，贯穿事件级与收件人级全部日志。
- **Context**：quality-reviewer 需求评审 attempt 2 的实现期建议①要求 `event_id` 绑定**稳定的来源事件标识**并贯穿日志。`events.Event` 无此字段；来源侧唯一稳定标识是 `cr_sync_event` 的幂等键 `(workspace_id, cr_id, commit_sha, event_kind)`（迁移 391 唯一索引）。`workspace_id` 已是独立日志字段，故投影为三段字符串即可唯一定位一次来源事件。`--embedded` 模式的 `commit_sha` 是 `pending:{ms}:{pid}:{seq}` 占位符——**仍逐事件唯一**（CR-2026-003 修的正是占位符互撞问题），幂等键不退化。
- **Alternatives**：
  1. `cr_sync_event.id`（BIGSERIAL）——更短，但 `ingest` 的 INSERT 是 `ON CONFLICT DO NOTHING` 无 `RETURNING`，要把 id 从 `ingest` 一路传到 `applyStatus` 再传进发布点，属为一个日志字段改动治理核心的调用签名；
  2. 每次发布新生成 UUID——能串起一次投递的多条日志，但**不指向来源事件**，重放或双通道上报时无法与账本对账，达不到建议①的要求。
- **Consequences**：日志可直接与 `cr_sync_event` 三列对账，零 schema 改动、零额外查询；代价是 `event_id` 较长且含冒号分隔（检索需整串匹配，不做子串解析）。

## DD-2 提醒器自带只读 pgx seam，不新增 sqlc 查询

- **Decision**：提醒器的读链（§4.4 两条 SQL）用 `*pgxpool.Pool` 直接执行，写在自研文件内；**不**往 `server/pkg/db/queries/channel.sql` 加查询、不重跑 `make sqlc`。
- **Context**：需要一条现有 sqlc 查询集里没有的读——"某 workspace 某成员的全部 feishu 绑定候选 + LEFT JOIN 安装"。最近似的 `FindChannelBindingForMember` 有两处不够：它不闭合 `ci.workspace_id` / `ci.channel_type`（PRD 澄清 4 指出的正是这类漏洞），且 `LIMIT 1` + `INNER JOIN ci … status='active'` 把 missing / revoked / orphan 三种失效**全部压成"零行"**，AC-4 要求的可区分跳过原因无法实现。加 sqlc 查询要改上游 `channel.sql` 并重生成 `pkg/db/generated/*.go`——CUSTOM.md 明列这两类文件是 fork 最大的合并冲突面，且**超出 PRD FR-10 声明的改动文件集合**（AC-8 逐条核对改动面）。
- **Alternatives**：
  1. `channel.sql` 加 `-- AIFIRST:` 查询 + `make sqlc`——编译期列名安全（上游改列名会 build 失败），先例充分（CUSTOM #17 起、#48）；但突破 FR-10 改动面，需求侧要重新确认，且吃进生成物冲突面；
  2. 只用现有 `FindChannelBindingForMember` + `GetChannelInstallationInWorkspace` 两步——零新查询，但如上所述放弃 AC-4 的可区分原因，等于降级已审批的验收标准。
- **Consequences**：改动面严格落在 FR-10 内，`governance` 包既有"fork 代码直接用 pgx 以避开上游 query 文件"的同款先例（CUSTOM.md #5）。**代价与缓解**：裸 SQL 失去 sqlc 的编译期列名校验，上游若重命名 `member.role` / `channel_user_binding.bound_at` 这类列会在**运行时**才暴露——缓解手段是 §7 的真库测试全部覆盖这两条 SQL（`ARCHITECTURE.md` §7 已要求 DB 测试真跑 PostgreSQL 而非 skip 假绿），并在 CUSTOM.md 登记行的"合并注意"里写明这两条 SQL 依赖的列清单。

## DD-3 `SendApprovalReminderCard` 进 `APIClient` 接口

- **Decision**：在 `client.go` 的 `APIClient` 接口加一行方法声明（唯一接口面改动，带 `// AIFIRST:`），实现与参数类型全部落在自研文件 `approval_reminder_card.go`（含 `*httpAPIClient` 与 `*stubAPIClient` 两个方法，Go 同包跨文件定义方法，故 `http_client.go` 正文只动 §4.5 的 helper 提取）。
- **Context**：`SendInteractiveCard` 走 `outboundMessageRequest`，`receive_id_type` 固定 `chat_id`，无法寻址 open_id 私聊；`SendBindingPromptCard` 的卡片体与 CTA 不同。所以必须有新方法。放接口上会连带要求 4 个上游测试替身（`outbound_test.go#fakeAPIClient`、`outcome_replier_test.go#stubAPIClientWithRecorder`、`typing_indicator_test.go#fakeTypingAPIClient`、`inbound_enricher_test.go#enricherFakeClient`）各补一个空实现。
- **Alternatives**：不进接口——`NewHTTPAPIClient` 返回的是 `APIClient` 接口值，提醒器只能对自研窄接口做**运行时类型断言**取能力。零上游文件改动，但断言失败是静默的：上游哪天给 `APIClient` 套一层装饰器，提醒功能会无声停摆而不是编译报错。对一个审批感知链路，"静默停摆"比"多改 4 个测试替身"贵得多。
- **Consequences**：编译期保证 wiring 正确；代价是 5 个上游文件（`client.go` + 4 个测试文件）各有一处最小改动，全部 `// AIFIRST:` 标记并登记 CUSTOM.md，双周 rebase 时逐条核对。

---

# 6. FR 到技术实现映射

| FR | 技术实现 | 落点 |
|---|---|---|
| FR-1 门禁进入语义事件 | `EventCRApprovalGateEntered` + `approvalGateStatuses` + `ApprovalGateEnteredPayload` + `publishApprovalGateEntered`，仅在 `applyStatus` 可信分支、`from != to`、目标 ∈ 四门禁时发布 | §3.2.1 / `governance/crsync.go` |
| FR-2 触发面隔离 | 不订阅 `EventCRUpdated`；不在 `found==false` 首见分支、`else`（needs_reconcile）分支、`checkpoint`/`review`/`trace`/default 分支、`reconcile.go`、`gate_projection.go` 发布；自环由 `from != to` 过滤 | §3.2.1 五条契约不变量 |
| FR-3 项目/workspace 解析 + 跨 workspace fail-closed | 单条 INNER JOIN SQL，`cr`/`issue`/`project`/`workspace` 四跳全带 `workspace_id = $1`；零行→跳过；原因判定的第二次查询仍带 workspace 谓词，且不产出收件人 | §4.4 第一条 SQL / §4.2 步骤 3 |
| FR-4 收件人角色筛选 | `SELECT user_id FROM member WHERE workspace_id = $1 AND role IN ('owner','admin')`，与 Web 侧 `roleAllowed(role,"owner","admin")` 同口径；空集 → `no-approver` | §4.2 步骤 3 |
| FR-5 有效绑定、去重、可区分跳过 | LEFT JOIN 候选查询 + `chooseEffective`（三条件判定，产出 4 种原因）；`bound_at DESC, id ASC` 取最新 ⇒ 每用户一张卡；`sentOpenIDs` 集合做 open_id 级二次去重 | §4.3 / §4.4 第二条 SQL |
| FR-6 卡片最小内容 | `approvalReminderTemplate`：header `待人工审批` + CR ID/标题 + 阶段名 + 固定说明 + 单一 button `前往审批`；模板内无 approve/reject action、无正文/证据/diff | §3.2.2 / `approval_reminder_card.go` |
| FR-7 CTA 与基地址 | `appURL + "/" + slug + "/projects/" + projectID + "?tab=chat"`；`appURL == ""` → `app-url-missing` 且零发送；**不新增** URL 合法性校验器 | §4.2 步骤 2/3 |
| FR-8.1 非阻塞边界 | 回调零 I/O；`chan struct{}` 非阻塞信号量（默认 8，过载 `overloaded` 丢弃不排队）；`context.Background()` 派生；60s/10s 有界超时；goroutine 自持 `recover` | §4.1 / §4.2 |
| FR-8.2 结构化可观测 | `logSent` / `logFail` / `logSkip` 三入口，字段按 §4.4 PRD 表；`reason` 取值受限于 9 项枚举常量（集中声明，不散拼字符串——CONTRIBUTING.AIFIRST 规则六） | §4.2 / §7.3 |
| FR-8.3 未启用仍消费 | `Register` 调用点在 `MULTICA_LARK_SECRET_KEY` 条件块**之外**；步骤 1 在任何 DB 查询前判 `client==nil / !IsConfigured() / credentials==nil` → `feishu-disabled` 返回；stub 方法零 HTTP | §3.2.3 / §4.2 步骤 1 |
| FR-8.4 失败隔离与 crash window | 全链只读、无事务、发布点之后；发送失败/超时只记日志；不做异步前状态二次校验、不做撤回、不做 drain/join、不引入 outbox/幂等键 | §4.2 关键约束 |
| FR-9 发送能力复用边界 | 单一用途 `ApprovalReminder`（只做解析/收件人/发送/记账）+ `SendApprovalReminderCard` + `ApprovalReminderParams`；模板封装在 client 侧；`sendCardToOpenID` 私有 helper 与绑定提示共用；**不**公开卡片 JSON 接口、**不**抽象跨渠道 notifier | §3.2.2 / §4.5 |
| FR-10 零改动边界 | 改动面：`governance/crsync.go`、`lark/approval_reminder.go`（新）、`lark/approval_reminder_card.go`（新）、`lark/client.go`（1 行接口）、`lark/http_client.go`（helper 提取）、`cmd/server/router.go`（wiring）、6 个测试文件（4 个替身补空实现 + 2 个新测试文件）、`CUSTOM.md` 登记。零改动：`tools/` 全部、schema/migration、CR 账本、`governance/approval.go`、Web 审批页与 API、grant daemon、`pkg/db/queries/*`、`pkg/db/generated/*` | §5 DD-2/DD-3 |
| FR-11 启用条件不新增配置 | 无新环境变量、无 feature flag、无用户通知偏好；启用条件全部由既有事实（密钥/角色/绑定/项目链/基地址）判定，不满足即按枚举原因跳过 | §4.2 |

**一处对 PRD 字面的收窄，请评审确认**：FR-1 把事件载荷描述为「CR 标识、workspace 标识、CR/issue 关联标识、新状态、事件标识」。本设计的 `Payload` 只带 `cr_id` / `status` / `event_id`（workspace 标识由 `events.Event.WorkspaceID` 承载），**不**带 issue id——因为 FR-3 明确要求订阅方按 `cr.shell_issue_id → issue.project_id → project.workspace_id` 自行解析，且 `ARCHITECTURE.md` §7 规定"bus 是通知不是持久权威，handler 必须能从 PostgreSQL/Git 事实重放"。若在事件里塞 issue id，`applyStatus` 需额外查一次 `cr`，且与 FR-3 的解析契约重复。判断：符合 FR-1"只携带定位所需最小标识"的约束，属**有意收窄而非漏项**。

---

# 7. 安全与性能考量

## 7.1 安全控制点

| 风险 | 控制 |
|---|---|
| CR 标题跨 workspace 外泄 | 唯一锚点来自 DaemonAuth（`resolveDaemonWorkspace`）；读链四跳 + 成员 + 绑定 + 安装**每跳**带 `workspace_id = 锚点`；任一跳不符即整体跳过、不放宽重查、不跨 workspace 兜底。审计口径：提醒器内**不存在**任何仅按主键/仅按外键的查询路径（§4.4 两条 SQL 是全部 DB 访问面，可静态核对） |
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
| 单事件 DB 往返 | 3 + N 次（链路 1 + 成员 1 + 每收件人 1；零行时 +1 次原因判定） | N = owner/admin 数，正常个位数 |
| 进程崩溃/退出 | 允许在飞提醒丢失 | 不引入 outbox / 持久化 / drain / 补偿 |

## 7.3 工程纪律落点（CONTRIBUTING.AIFIRST）

- **规则一/二**：自研逻辑集中在两个新文件；上游文件只留最小挂钩（`client.go` 1 行、`http_client.go` helper 提取、`router.go` wiring、4 个测试替身），每处 `// AIFIRST: CR-2026-051 …` 标记；
- **规则五**：两个新文件预算内（预估各 < 400 行），远低于 800 行提醒线；不新增包级可变全局状态（`MaxInFlight` / 超时 / 依赖全走构造注入）；
- **规则六**：9 个跳过原因 + 错误类别集中声明为常量（不散拼字符串）；构造参数不静默忽略（§3.2.3）；卡片模板与 `chooseEffective` 是独立可单测的小单元；
- **CLAUDE.md**：multica 仓内新增/改动的代码注释一律英文（本 SDD 中文，代码英文）；
- **CUSTOM.md**：本 CR 落码后按彼时 CUSTOM.md 现状顺延登记一行，"合并注意"列写明 ① `crsync.go` 发布点须随上游事件机制改名跟改；② §4.4 两条裸 SQL 依赖的列清单（`cr.shell_issue_id`/`cr.title`、`issue.project_id`、`project.id`、`workspace.slug`、`member.role`、`channel_user_binding.bound_at`/`channel_user_id`/`multica_user_id`、`channel_installation.status`/`channel_type`/`workspace_id`）；③ `APIClient` 接口新方法与 4 个测试替身空实现须整组保留。

## 7.4 测试设计（对齐 AC-1～AC-13）

| 测试 | 覆盖 AC | 要点 |
|---|---|---|
| `governance`：四门禁 × 合法转换各发布一次 | AC-1 | 真库；断言事件类型、`workspace_id`、payload 三字段与 `event_id` 形状 |
| `governance`：误触发隔离 | AC-2 | 通用 `cr:updated` 不触发；重放（`curStatus != FromStatus`）、自环（`from == to`）、checkpoint/review/trace、首见分支、reconcile/gate_projection 均零发布；断言订阅集合不含 `EventCRUpdated` |
| `lark`：happy path 多收件人 | AC-3 | 每个有效绑定 owner/admin 一张卡；同用户多绑定只发一张（取 `bound_at` 最新）；同 open_id 只发一次 |
| `lark`：四类不发送 | AC-4 | `member` 角色 / `binding-missing` / `installation-revoked` / `installation-missing` 各留可区分 reason |
| `lark`：卡片与 CTA | AC-5 | 模板断言五项最小内容 + 无 approve/reject action；CTA 等于 `{appURL}/{slug}/projects/{projectID}?tab=chat`；`appURL==""` 零发送 |
| `governance`：Web 审批链路回归 | AC-6 | 既有 `approval*_test.go` / `project_gates_test.go` 原样通过，不修改 |
| `lark`：三类日志字段 + 无回滚 | AC-7 | 断言 §4.4 必需字段齐全、`reason` 落在 9 项枚举内；失败/跳过下投影仍成功 |
| 静态改动面核对 | AC-8 | `git diff --name-only` 与 FR-10 声明集合逐条比对；断言无新 migration、`pkg/db/queries`/`generated` 零改动、`tools/` 零改动 |
| `lark`：跨 workspace 负向 | AC-10 | issue/project/绑定/安装任一层 workspace 不符 → 零发送 + `workspace-mismatch`；静态核对提醒器内无"仅按主键/仅按外键"查询 |
| `lark`+`governance`：阻塞替身 | AC-11 | 客户端替身阻塞至超时：`HandleCREvents` 时延与无提醒器基线同量级、投影不变、无回滚；bus 回调内 DB/HTTP 替身零调用 |
| `lark`：stub 形态 | AC-12 | 未设 `MULTICA_LARK_SECRET_KEY`：事件被消费、一条 `feishu-disabled` 事件级跳过、`NewStubAPIClient` 零真实请求、读链零查询（pool 替身零调用） |
| `lark`：panic 与过载 | AC-13 | goroutine 内注入 panic → 被自持 recover 记日志、进程存活；`MaxInFlight=1` 占满后新事件记 `overloaded`、不排队、不重试 |
| `lark`：绑定提示行为等价 | §4.3 兼容性 | `http_client_test.go` 三处既有 `SendBindingPromptCard` 断言**不修改**即通过（helper 提取的回归锁） |

DB 相关测试须在可用 PostgreSQL 环境取到无 skip 的 `=== RUN` / `--- PASS` 证据（CUSTOM.md C6：包级 `TestMain` 在 DB 不可达时整包 skip，会产生 exit 0 假绿；**不得为此改 TestMain**）。

---

# 8. 残余风险与未决项

| 项 | 说明 | 处置 |
|---|---|---|
| DD-2 的运行时列名风险 | 裸 SQL 无编译期列名校验，上游重命名相关列会在运行时才暴露 | 真库测试覆盖两条 SQL + CUSTOM.md 登记列清单；评审若判定不可接受，切 DD-2 备选 1（`channel.sql` + `make sqlc`），但需先由需求负责人扩 FR-10 改动面 |
| §4.5 动上游函数正文 | `SendBindingPromptCard` 改调私有 helper | 既有三处测试断言不改即为回归锁；评审否决则改为自研文件内重写传输逻辑（代价见 §4.5 注） |
| §6 事件载荷收窄 | Payload 不带 issue id | 已给出理由与 FR-3/ARCHITECTURE 依据，请评审明确采纳或驳回 |
| `MaxInFlight` 默认 8 | 无生产数据支撑的经验值 | 收件人规模个位数、单事件 ≤60s，8 足以覆盖正常并发；构造参数可调，不新增环境变量（FR-11） |
| `cr.title` 可能为空 | 迁移 362 默认 `''`，由 reconcile 回填 | 卡片模板空标题时只渲染 CR ID，不渲染空行 |

**§8「Prompt 采纳影响」不触发**：本 CR 不改 `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支，也不改 `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny`（`tools/` 整包零改动），crctl 命令面与 guard deny 面均无新增或变更，故条件性小节按 Skill 规则省略。

---

# 9. 修订记录

| 版本 | 时间 | 变更 |
|---|---|---|
| 初稿 | 2026-08-25T20:34:02+08:00 | 首版。基于 PRD `b64a92cf…`（11 FR / 5 US / 13 AC）与 multica worktree 实地核实的 15 条既有事实；含 6 项术语硬化、3 条决策记录（DD-1 event_id / DD-2 pgx 读 seam / DD-3 接口方法）、FR-1～FR-11 全映射、13 项 AC 测试设计。已收 quality-reviewer 两条实现期建议：① `event_id` 绑定账本幂等键投影并贯穿三类日志（DD-1、§4.4 字段）；② CTA 按锚定 `workspace_id` 读 `workspace.slug`（§4.4 第一条 SQL 的 `JOIN workspace w ON w.id = $1`）并补跨 workspace slug 回归断言（AC-10 测试项）。 |

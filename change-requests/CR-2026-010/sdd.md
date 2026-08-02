---
id: CR-2026-010-sdd
type: SDD
cr-ref: CR-2026-010
title: P2 三模式聊天 CR-E — 技术设计（presenter 控制权 + claim 串行化键改造）
target-version: "0.17"
owner: Ray
owner-role: development
status: draft
created: "2026-08-02T11:46:28+08:00"
updated: "2026-08-02T11:46:28+08:00"
revision: "0.1.0"
prd-ref: "change-requests/CR-2026-010/prd.md"
---

# SDD — P2 三模式聊天 CR-E

> 本 SDD 基于对 multica main（含 CR-2026-006 合并）的实地代码调查编写，文件路径/行号均已核实，
> 路径相对 multica 仓根。需求评审 3 条建议（SUG-001/002/003）的落地见 §6。
> **调查修正一处 PRD 前提**：现有 claim 串行化键不是 `agent_id` 单键，而是
> `(agent_id, issue_id)` / `(agent_id, chat_session_id)` / `(agent_id, 全NULL)` 三分支
> （`server/pkg/db/queries/agent.sql:350-388`）——改造实质是把 issue 分支从"同 issue"放宽为
> "同 project"，chat_session 分支原样保留，PRD 的"Private Ask 并行不受影响"由此天然成立。

## 1. 设计总览

presenter 是全仓绿地（grep 零命中）。设计分四块，复用密度延续 CR-A：

```
后端  M1-3 迁移：agent_task_queue 加冗余 project_id 列（入队 stamp + 回填 + 部分索引）
              + project_presenter_grant 单表（状态即审计，partial unique 保单主持人）
      claim SQL：issue 分支换 project 键（跨 agent）+ 提交前 advisory lock 复核防竞态
      发送端点：SendProjectChatMessage 前加控制权守卫（403 presenter_required）
      6 转移 API：/api/projects/{id}/presenter/* 七个路由（1 GET + 6 POST）
      通知双通道：activity_log(挂容器 Issue)→消息流卡片可回放；notifyDirect→定向 inbox
前端  头部：三模式 TabsList 右侧空位挂「当前主持人」chip + 面板入口
      面板：chat 面板内自建 Sheet（成员列表 + 按角色的操作按钮）
      通知卡：TeamAgentStreamView 合并循环加第三类条目（放宽 activity filter）
      WS：零新增前端 handler（project: 前缀自动失效 + activity:created 既有直写）
```

## 2. 关键设计决策

| # | 决策 | 依据 |
|---|---|---|
| DD-1 | **presenter 状态用单表 `project_presenter_grant`，状态行即审计**：`status ∈ pending/active/rejected/released/revoked/transferred`，行不删除只改状态；`(project_id) WHERE status='active'` 部分唯一索引在 DB 层保证单主持人（NFR-5 的兜底） | 不选 `project.settings` 键：settings 分支硬编码 owner/admin 门禁（project.go:505），且申请列表本就需要表；不选"状态表+申请表"两张：一张表状态机覆盖两者，还免费获得完整历史（SUG-001）。partial unique 先例：160_issue_origin_project_chat.up.sql:18 |
| DD-2 | **claim 串行化改造 = issue 分支换 project 键且跨 agent**：`atq.project_id` 非空时与全项目 active 任务互斥（不再限定同 agent）；project_id 为空的 issue 任务/chat 任务/quick-create 形状三分支**原样保留** | 交互设计 §3.1 的口径是"NOT EXISTS(active task on same project)"——项目内所有 issue 任务共享同一 worktree，跨 agent 并发写才是单写者要防的场景；chat_session 分支不动 = PRD FR-3 的 Private Ask 并行约束 |
| DD-3 | **`agent_task_queue` 加冗余 `project_id` 列**（入队时从 issue stamp），不在 claim SQL 里双侧 JOIN issue | claim 是热路径，现有支撑索引全是 (agent/runtime, priority, created_at) 族，双侧 JOIN 无覆盖路径；冗余列 + `(project_id) WHERE status IN (active集)` 部分索引让 NOT EXISTS 探测只扫极小索引 |
| DD-4 | **claim 竞态防护 = 提交前 advisory xact lock + 复核，冲突方 requeue**：ClaimAgentTask 返回行带非空 project_id 时，取 `pg_advisory_xact_lock('claim-project|{project_id}')` 再复核无其他 active；违例走既有 `RequeueAgentTaskAfterClaimFailure` 回队 | 既有 per-agent 锁 `GetAgentForClaimUpdate`（FOR UPDATE）只串行化同 agent 的 claim，跨 agent 同项目并发 claim 在 READ COMMITTED 下 NOT EXISTS 互不可见。锁在 UPDATE 后取无死锁环（等待只发生在 advisory 锁上）；advisory lock 先例 project_chat.go:61-64，requeue CAS 先例 agent.sql:415-431 |
| DD-5 | **控制权守卫只落薄发送端点，不动 Issue 页评论 @提及路径**：普通成员非 presenter 发群聊 → 同步 403 `presenter_required`；Issue 页 mention 入队行为不变，执行层由 DD-2 的项目串行化兜住 | PRD FR-2 界定的守卫点就是薄发送端点；CR-A NFR-3"Issue 页评论路径不动"延续。Issue 页任务照常入队但必须等项目槽 = "不被执行（排队）"语义 |
| DD-6 | **presenter 非空时 owner/admin 的插队优先级抑制**：容量豁免保留，priority 100 覆盖改为 0（普通序） | 切分文档 §0.1"管理员可直接对话但 Agent 忙时需等待"：不抢占 presenter 的排队消息；presenter 空时 D1 语义原样 |
| DD-7 | **撤销/转让不打断运行中任务**：转移只改 grant 行，运行中任务自然完成；新 presenter 的消息按 DD-2 排队等槽 | 停止能力归 CR-B（发送者/Owner 停止按钮）与 D1 cancel 端点，紧急打断走那条路；claim 层打断需动 daemon 协议，超出本 CR（SUG-002 定案） |
| DD-8 | **通知双通道**：6 转移全部写 activity_log（挂容器 Issue，action=`presenter_*`）→ 消息流卡片 + 刷新可回放；申请/批准/拒绝/撤销/转让 5 种另发 `notifyDirect` 定向 inbox（release 无定向对象，仅流内卡片） | activity 路线让通知卡免费获得持久化 + `activity:created` WS 直写（use-issue-timeline.ts:196 现成模板）；notifyDirect（notification_listeners.go:366）是"申请→Owner 收件箱"的既有定向通道，quick_create_failed 先例证明 issue_id 可空 |
| DD-9 | **WS 零新增前端 handler**：新事件 `project:presenter_changed`（服务端常量 + publish），前端靠既有 `project` 前缀兜底失效 `projectKeys.all`；流内卡片靠既有 `activity:created` 直写 | slack_installation 先例证明前缀路径可不扩 WSEventType 联合（use-realtime-sync.ts:519）；presenter 变更低频，projectKeys.all 失效成本可接受 |

## 3. 数据模型与迁移（3 个 migration，161–163）

**M161 `agent_task_queue` 加列 + 回填**：
```sql
ALTER TABLE agent_task_queue
  ADD COLUMN project_id UUID REFERENCES project(id) ON DELETE SET NULL;
UPDATE agent_task_queue atq SET project_id = i.project_id
  FROM issue i WHERE atq.issue_id = i.id AND i.project_id IS NOT NULL;
```
回填覆盖全部历史行（含 active），使新 claim SQL 上线即对在途任务生效（SUG-003）。

**M162 部分索引（单语句 + CONCURRENTLY，沿 080 约定）**：
```sql
CREATE INDEX CONCURRENTLY idx_atq_project_active
  ON agent_task_queue(project_id)
  WHERE status IN ('dispatched','running','waiting_local_directory') AND project_id IS NOT NULL;
```

**M163 presenter 状态表**：
```sql
CREATE TABLE project_presenter_grant (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    project_id   UUID NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    user_id      UUID NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
    status TEXT NOT NULL CHECK (status IN
        ('pending','active','rejected','released','revoked','transferred')),
    granted_by  UUID,            -- approver (approve) / previous presenter (transfer)
    resolved_by UUID,            -- who closed this row (reject/revoke/release/transfer)
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX ppg_active_uniq  ON project_presenter_grant(project_id) WHERE status='active';
CREATE UNIQUE INDEX ppg_pending_uniq ON project_presenter_grant(project_id, user_id) WHERE status='pending';
CREATE INDEX ppg_project_idx ON project_presenter_grant(project_id, created_at DESC);
```
状态语义：`pending`=待审申请；`active`=现任主持人（每项目至多一行，DB 保证）；其余四值为闭结状态。
转让 = 事务内旧 active 行 → `transferred` + 插入新 active 行。

## 4. 后端设计

### 4.1 claim SQL 改造（agent.sql `ClaimAgentTask`）

NOT EXISTS 重写（原外提的 `active.agent_id = atq.agent_id` 下沉到各保留分支）：
```sql
AND NOT EXISTS (
    SELECT 1 FROM agent_task_queue active
    WHERE active.status IN ('dispatched','running','waiting_local_directory')
      AND (
        -- CR-2026-010: project-scoped single writer, cross-agent.
        (atq.project_id IS NOT NULL AND active.project_id = atq.project_id)
        -- Issues outside any project keep per-(agent, issue) serialization.
        OR (atq.project_id IS NULL AND atq.issue_id IS NOT NULL
            AND active.agent_id = atq.agent_id AND active.issue_id = atq.issue_id)
        -- 1:1 / Private Ask chat: unchanged, parallel to project tasks.
        OR (atq.chat_session_id IS NOT NULL
            AND active.agent_id = atq.agent_id AND active.chat_session_id = atq.chat_session_id)
        -- Quick-create shape: unchanged.
        OR (atq.issue_id IS NULL AND atq.chat_session_id IS NULL AND atq.autopilot_run_id IS NULL
            AND active.agent_id = atq.agent_id AND active.issue_id IS NULL
            AND active.chat_session_id IS NULL AND active.autopilot_run_id IS NULL)
      )
)
```
`ORDER BY priority DESC, created_at ASC` 与 `FOR UPDATE SKIP LOCKED` 不动。`make sqlc` 再生成。

**入队 stamp**：`CreateAgentTask` 加 `project_id` 参数；三个 issue 系入队点
（assignee task.go:738 族 / mention task.go:823 族 / 群聊 project_chat.go:160→mention）
从 `issue.ProjectID` 传入；chat（task.go:1103 `CreateChatTask`）与 quick-create 保持 NULL。

**竞态复核（DD-4）**：`ClaimTask`（task.go:1336 runInTx 内）在 `ClaimAgentTask` 返回行
`project_id` 非空时追加两步：
```
SELECT pg_advisory_xact_lock(hashtextextended('claim-project|' || project_id, 0));
SELECT count(*) FROM agent_task_queue
 WHERE project_id=$1 AND status IN ('dispatched','running','waiting_local_directory') AND id != $2;
-- count > 0 → RequeueAgentTaskAfterClaimFailure（既有 CAS 回队）→ 本轮返回无任务
```

### 4.2 presenter 服务与转移状态机

新文件 `server/internal/service/project_presenter.go`。所有写转移共用模板：
**advisory xact lock `presenter|{workspaceID}|{projectID}`（沿 project_chat.go:61 写法）→
读当前状态 → 转移合法性校验 → 写 grant 行 → 写 activity_log → publish**。
partial unique 索引兜底并发（锁失效时插入冲突而非双 active）。

| 转移 | 调用者角色校验 | 前置状态 | 动作 |
|---|---|---|---|
| request | 任意成员（owner/admin 拒绝：无需申请，400） | 无本人 pending（唯一索引兜底）| INSERT pending |
| approve | owner | 该 pending 存在；**无 active**（有则 409 `presenter_already_active`）| pending→（保留）+ INSERT active（granted_by=owner）；同项目其他 pending 不动 |
| reject | owner | 该 pending 存在 | pending→rejected |
| transfer | 现任 presenter 本人 | active 存在且属本人；目标为工作区成员 | active→transferred + INSERT 新 active（granted_by=原 presenter）|
| revoke | owner | active 存在 | active→revoked |
| release | 现任 presenter 本人 | active 存在且属本人 | active→released |

approve 语义澄清：批准即把该 pending 行"消费"为一条新 active 行（pending 行置 approved？——
不引入第 7 个状态：pending 行改 `resolved_by/resolved_at` 并置 `rejected` 以外的闭结即用
**转移到 active 行的 `granted_by` + activity 记录**表达；实现上直接 UPDATE 该 pending 行为
active（同一行翻转，保留 created_at 为申请时间），审计链条最短。

成员移除联动：`workspace.go` 移除成员路径追加一次 `revoke-if-active + reject-all-pending`
（单 UPDATE，actor=system），防悬挂 presenter。

**读接口**：`GetProjectPresenterState(projectID)` → `{active_grant | null, pending[]}`，
pending 列表仅 owner/admin 可见（服务端过滤，对齐前端红线 use-realtime-sync.ts:106 的
"跨用户数据走服务端权限过滤"）。

### 4.3 发送端点接入（project_chat.go `SendProjectChatMessage`）

容量守卫**之前**插入控制权守卫（PRD FR-2 顺序）：
```
role   = GetMemberByUserAndWorkspace(caller)
active = 查 active grant
allowed = active!=nil ? (caller==active.user_id || role∈{owner,admin})
                      : (role∈{owner,admin})
!allowed → 403 presenter_required { presenter_user_id?: string }   // 消息不落库不入队
```
（普通成员在 presenter==null 时同样被拒——设计稿 §2"其余申请 presenter"的默认态语义。）
守卫通过后沿既有链路：容量守卫 → 落 comment → 入队；**DD-6** 在此处生效——
`active!=nil && caller!=active.user_id`（即 owner/admin 等待场景）时把 guard 返回的
priority 100 覆盖压回 0，容量豁免保留。

### 4.4 API 契约（router.go `r.Route("/{id}")` 组内，RequireWorkspaceMember 之下）

```
GET  /api/projects/{id}/presenter          → 200 { presenter: {user_id, granted_at, granted_by} | null,
                                                   pending_requests: [{id,user_id,created_at}] }  // pending 按角色过滤
POST /api/projects/{id}/presenter/request  → 201 | 400 role_cannot_request | 409 request_already_pending
POST /api/projects/{id}/presenter/approve  {user_id} → 200 | 403 | 404 no_pending_request | 409 presenter_already_active
POST /api/projects/{id}/presenter/reject   {user_id} → 200 | 403 | 404
POST /api/projects/{id}/presenter/transfer {user_id} → 200 | 403 not_presenter | 400 target_not_member
POST /api/projects/{id}/presenter/revoke   → 200 | 403 | 404 no_active_presenter
POST /api/projects/{id}/presenter/release  → 200 | 403 not_presenter
```
role 校验用 `h.requireWorkspaceRole`（handler.go:644）族；错误一律结构化 code（沿
`writeProjectQueueFull` 的 code 化先例）。各 POST 需要容器 Issue 时（写 activity）调
`EnsureProjectChatIssue`（幂等，advisory lock 已有）。

### 4.5 通知与事件（DD-8/DD-9）

**activity_log**（6 转移各一条，挂容器 Issue）：action 常量
`presenter_requested / presenter_approved / presenter_rejected / presenter_transferred /
presenter_revoked / presenter_released`；details 形状沿 assignee_changed 先例
（activity_listeners.go:110）：`{from_user_id?, to_user_id?, by_user_id}`。
写入后 publish `EventActivityCreated`（squad.go:943 的 handler 内直写 + 广播先例）。

**定向 inbox**（notifyDirect，IssueID 传容器 Issue、details 带 project_id）：

| 转移 | 收件人 | inbox type |
|---|---|---|
| request | 全体 owner（循环 notifyDirect） | `presenter_requested` |
| approve | 申请人 | `presenter_approved` |
| reject | 申请人 | `presenter_rejected` |
| transfer | 受让人 | `presenter_transferred` |
| revoke | 原 presenter | `presenter_revoked` |
| release | —（无定向对象，仅活动卡） | — |

5 个 type 加入前端 `packages/core/types/inbox.ts` 联合 + `inbox-detail-label.tsx` 分支；
**不加**入 `notifTypeToGroup`（权限通知不可静音，map 缺省即强制送达）。无 DB 迁移。

**WS**：`protocol/events.go` 加 `EventProjectPresenterChanged = "project:presenter_changed"`，
6 转移成功后 publish（workspace 广播，payload `{project_id, presenter_user_id|null}`）；
前端零代码（`project` 前缀兜底失效）。

## 5. 前端设计

### 5.1 数据层（packages/core）

- `api/schemas.ts`：`ProjectPresenterState` schema（`.loose()`）+ EMPTY 兜底；
  `api/client.ts`：`getProjectPresenter` + 6 个 POST（`parseWithFallback` 模式）。
- `projects/queries.ts`：`projectPresenterOptions(wsId, projectId)`，key 挂
  `projectKeys` 树下（`project:` 前缀失效自动覆盖）。
- `projects/mutations.ts`：6 个 mutation 照 `useSendProjectChatMessage` 形状；
  成功 onSettled invalidate presenter + chat 两个 key；**非乐观**（跨用户权限数据，红线）。

### 5.2 头部「当前主持人」（FR-6）

`project-chat-panel.tsx:74` 的 `<TabsList variant="line">` 行右侧空位（TabsTrigger 均
flex-none）挂 `PresenterHeader`：ActorAvatar(sm) + 名字（`useActorName`）+
「当前主持人」label；无 presenter 时显示空态口径（`chat.presenter.default`=Owner/Admin）；
右侧 icon 按钮开控制面板。数据 `projectPresenterOptions`，WS 失效驱动实时。

### 5.3 chatControlPanel 权限面板（FR-5）

聊天面板内自建受控 `<Sheet side="right">`（照抄 project-detail.tsx:597-603 的 mobile 写法，
无既有成员抽屉可复用——已核实）。内容：
- 成员列表 = workspace 成员（`memberListOptions`，无项目级成员概念——已核实），行结构照抄
  settings `MemberRow`（members-tab.tsx:74-182：ActorAvatar + 名字 + 角色 Badge
  {owner:Crown, admin:Shield}）；现任 presenter 行加高亮徽标。
- 按角色渲染操作：普通成员见「请求 Agent 访问权限」（有 pending 时显示"申请中"禁用态）；
  owner 对 pending 行见 批准/拒绝、对 active 行见 撤销；presenter 本人见 转让（选人弹层照抄
  CR-A `TeamAgentSetupPicker` 的 PropertyPicker 骨架，project-chat-panel.tsx:272-283）与 释放。
- 面板开关状态不持久化（会话内 useState 即可，YAGNI）。

### 5.4 消息流通知卡（FR-4）

- 放宽 `project-team-agent-chat.tsx:66-69` 的 filter：保留 member comment 之外，追加
  `type==="activity" && action.startsWith("presenter_")` 的条目。
- `TeamAgentStreamView`（:99-118）合并循环加第三个 for：push
  `{key: "p:"+id, at, node: <PresenterNoticeCard/>}`，排序逻辑不动。
- `PresenterNoticeCard`：内联系统状态条样式（居中窄条：icon + 文案 + 时间——即 PRD 提到的
  CodeBanana 系统状态卡形态，比 ActivityBlock 骨架更贴聊天语境）；文案从
  `chat.notices[action]` 同构字典取（与 `chat.tabs[mode]` 动态索引同型），插值
  from/to 用户名（`useActorName`）。
- 实时：既有 `activity:created` 直写缓存（use-issue-timeline.ts:196-212）零改动；
  回放：activity 在 timeline 里持久化，天然满足。
- `issue-detail.tsx:984` 的 `NEVER_COALESCE_ACTIONS` 加入 6 个 presenter action
  （审计事件不可合并——Issue 详情页同样会展示容器外项目 Issue 的 presenter 活动？容器 Issue
  被隐藏，不会进 issue-detail；此处加集合是防御性一致）。

### 5.5 发送被拒呈现（FR-8）

`handleSend` 的 code 分支链（project-team-agent-chat.tsx:390-405）加 `presenter_required`：
复用 429 黄条的位置与样式（:424-439）渲染「当前主持人为 {name}，需请求 Agent 访问权限」+
「请求权限」按钮（直接调 request mutation）；`locked` 计算并入该状态；与 429 禁用态并存
（两条件 or）。恢复：presenter 变更 WS 失效 presenter query 后自动解锁。

### 5.6 locale

`projects.json` 的 `chat` 子树下新增（en/ja/ko/zh-Hans 四语，parity 测试强制）：
`chat.presenter.{label,default,request_cta,requested,locked_title}`、
`chat.control.{title,approve,reject,revoke,transfer,release,pending_badge,presenter_badge}`、
`chat.notices.{presenter_requested,...6 键同构字典}`；inbox 侧 5 个 type 的 label 进
`inbox.json`。

## 6. 需求评审建议落地

### 6.1 SUG-001 存储模型（定案）
单表 `project_presenter_grant`，状态行即审计（行不删只闭结），partial unique 双索引
分别保证"单 active"与"单人单 pending"；转移历史 = 表本身 + activity_log 双记录
（后者供消息流回放）。待审申请唯一性：`(project_id, user_id) WHERE pending`；
过期策略不做（YAGNI，owner 收件箱可见即可）；成员移除时 system 角色闭结其 active/pending
（§4.2 联动）。

### 6.2 SUG-002 撤销/转让撞运行中任务（定案 = DD-7）
不打断：grant 转移即时生效于**入队守卫**（新消息立即按新 presenter 判定），运行中任务
自然完成；紧急打断走 D1 cancel / CR-B 停止按钮。补充回归用例：presenter A 任务运行中
revoke A → 任务完成不中断；期间 A 再发消息 → 403（守卫即时生效）。

### 6.3 SUG-003 上线兼容（定案）
M161 回填覆盖在途行 → 新 claim SQL 上线即对存量 active 任务生效；部署窗口内旧二进制
入队的新行 project_id=NULL → 走保留的 per-issue 分支（旧语义），随任务终结自然收敛；
单机部署窗口极短，无需双写开关。回归清单（AC-3 映射）：
① CR-2026-004：满队 429 / owner-admin 豁免与插队 / 撤回 / queue-status（既有测试直接跑）；
② CR-2026-006：群聊守卫→落库→入队→claim→执行→回放链路（既有测试 + presenter=null 场景）；
③ 新增并发测试：同项目两 agent 各一 queued 任务并发 claim → 恰一个成功（DD-4 复核路径）；
④ chat_session 任务与项目任务并行 claim 互不阻塞（既有 1:1 chat 测试 + 新断言）。

## 7. FR → 设计映射

| FR | 落点 |
|---|---|
| FR-1 状态模型与六转移 | §3 M163 + §4.2（转移表 + advisory lock 模板 + 403 结构化） |
| FR-2 入队守卫 | §4.3（守卫前置于容量守卫，403 presenter_required） |
| FR-3 claim 串行化改造 | §3 M161/M162 + §4.1 + DD-2/3/4 |
| FR-4 通知卡片 | §4.5 activity 通道 + §5.4（流内卡 + 回放） |
| FR-5 chatControlPanel | §5.3 |
| FR-6 chatHeader 主持人 | §5.2 |
| FR-7 WS 事件 | §4.5（project:presenter_changed + activity:created）+ DD-9 |
| FR-8 拒绝呈现 | §5.5 |

## 8. 安全与性能考量 / 风险与回归面

- **服务端权威（NFR-1）**：六转移角色校验全在 handler/service；pending 列表服务端按角色
  过滤；前端 mutation 非乐观。绕前端直调 API 的 403 路径为 AC-4 验证对象。
- **单写者的三层保证**：入队守卫（挡普通成员）→ claim SQL project 分支（挡并发执行）→
  advisory lock 复核（挡跨 agent 竞态窗口）；DB 层 partial unique 兜 presenter 状态并发。
- **性能**：claim 新增探测走 idx_atq_project_active（active 任务数极小的部分索引）；
  advisory lock 仅 project_id 非空的成功 claim 路径多一次锁 + 一次 count，锁粒度 per-project；
  发送端点多两次点查（member + active grant），均为 PK/索引命中。
- **风险表**：

| 风险 | 缓解 |
|---|---|
| claim SQL 改写破坏既有三分支语义（本 CR 首要风险） | 分支保留策略（§4.1 只动 project 分支）+ §6.3 四组回归；sqlc 再生成后 diff 审查限定 agent.sql.go |
| 跨 agent 项目串行化降低多 agent 项目吞吐 | 设计即如此（共享 worktree 单写者）；ponytail: per-project 串行是天花板，多 worktree 并行另立 CR |
| 部署窗口 NULL project_id 行走旧语义 | §6.3：自然收敛，窗口极短，接受并记录 |
| 容器 Issue 的 activity 从其他入口泄漏 | 容器 Issue 已被 CR-A 全入口隐藏（§6.1 清单）；activity 只随 timeline 出（按 issue 查询） |
| 申请人是 pending 状态时被移出工作区 | §4.2 成员移除联动闭结；测试覆盖 |
| owner/admin 消息与 presenter 消息在容器 Issue 上合并为同一 pending 任务（既有 idx_one_pending_task_per_issue_agent + MergeCommentIntoPendingTask） | 语义上两者都已过守卫、合并执行可接受；activity 与 comment 归属清晰；记录为已知行为，AC-1 验证时以"是否被执行"为准而非任务行数 |

## 9. AC → 验证方式

| AC | 方式 |
|---|---|
| AC-1 单一写者 | 真机三角色矩阵：presenter 置位后成员 403+提示条+SELECT 证不落库；admin 发送入队、presenter 任务运行期不执行（SQL 断言 active 唯一）、空闲后执行；presenter 正常执行；agent 空闲时 admin 直发即执行 |
| AC-2 状态机全覆盖 | 五条路径真机走通：申请→批准 / 申请→拒绝 / 转让 / 撤销 / 释放；每步核对 流内卡片 + 定向 inbox + 头部实时（第二浏览器会话无刷新更新）+ grant 行状态 |
| AC-3 回归 | §6.3 四组：①②既有测试全绿 ③新并发 claim 测试（两 agent 同项目恰一成功）④chat 并行断言；`go vet/build` + `make sqlc` diff 审查 |
| AC-4 服务端权威 | curl 直调六端点 × 非法角色矩阵（非 owner 批准/撤销、非 presenter 转让/释放、owner/admin 申请、非成员）全部 403/400 结构化；直调发送端点验 403 presenter_required |
| AC-5 四语/双端 | locale parity 测试全绿；web + desktop（共享 views 包）目视回归 |

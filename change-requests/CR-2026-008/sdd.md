---
id: CR-2026-008-sdd
type: SDD
cr-ref: CR-2026-008
title: P2 三模式聊天 CR-C — 技术设计（D5 Private Ask + B2 chat_session 项目维度）
target-version: "0.15"
owner: Ray
owner-role: development
status: draft
created: "2026-08-02T10:48:45+08:00"
updated: "2026-08-02T10:48:45+08:00"
revision: "0.1.0"
prd-ref: "change-requests/CR-2026-008/prd.md"
---

# SDD — P2 三模式聊天 CR-C：D5 Private Ask（含 B2 迁移）

> 本 SDD 基于 multica main（`52b5717`，已含 CR-2026-006/CR-A 合并）的实地代码调查编写，
> 文件路径/行号均已核实，路径相对 multica 仓根。需求评审 3 条建议（SUG-1/2/3）落地见 §6。
> **§6.2 的核实结论改变了本 CR 的后端主工作量**：隐私收敛不是"可能要做"，是必做且是最大单项。

## 1. 设计总览

Private Ask 面 = **既有 1:1 chat 的全部基础设施 + 一个项目维度**。前端零新消息组件
（`ChatMessageList`/`ChatInput`/`TaskStatusPill` 全部纯 props 直接组合，已核实签名）；
后端新增面积：1 个 migration（1 列 + 2 索引）、既有 chat 列表查询加排除谓词、1 个
get-or-create 端点、以及**隐私收敛**——把 ChatSessionID 事件从 workspace 广播改为
per-user 定向推送（§6.2 核实：当前 main 上聊天内容仍在全工作区 fanout，这是 PRD FR-6
预留条件分支的"条件成立"路径）。

```
前端 project-chat-panel（CR-A 已建）
        └─ Private Ask 面（本 CR，替换空态占位）
             ├─ GET /api/projects/{id}/private-chat   （get-or-create 会话，sessionId 面板自管）
             ├─ ChatMessageList(messages, pendingTask, availability)   ← chatKeys.messages/pendingTask 既有 query
             ├─ ChatInput(纯 props) → 既有 POST /api/chat/sessions/{id}/messages
             └─ TaskStatusPill（生成中/停止，仅本人）
后端 B2: chat_session + project_id（nullable）
     隐私: listeners.go SubscribeAll — ChatSessionID 事件改 SendToUser(creator)，fail-closed
```

## 2. 关键设计决策

| # | 决策 | 依据 |
|---|---|---|
| DD-1 | **隐私收敛走 per-user 定向推送（SendToUser），不启用 MUL-1138 scope 订阅路由** | 核实（§6.2）：`listeners.go` SubscribeAll 把含 ChatSessionID 的事件全量 `BroadcastToWorkspace`（cmd/server/listeners.go:187），注释明说 Phase 1 scope 路由因客户端未发 subscribe 帧而故意未启用，贸然启用=静默丢消息。chat 会话是 creator 私有契约（HTTP 层与 scope_authorizer.go:74-92 双重确认 creator-only），per-user 推送=语义精确等价，且**前端零改动**（SendToUser 覆盖同用户全部连接/多设备，hub.go:560-562）。启用 scope 订阅需改 WSClient 订阅协议 + 断线重放，超出本 CR 量级，留待 MUL-1138 客户端 PR |
| DD-2 | **事件携带收件人**：`events.Event` 加 `ChatRecipientID` 字段，发布点填 session creator；桥接层 fail-closed | listeners.go 无 DB 访问（registerListeners(bus, b) 只拿 bus+broadcaster）；发布点（§4.3 清单）都持有或可一次取到 session。**fail-closed 是红线的技术表达**：ChatSessionID 非空而收件人为空 → 丢弃 + ERROR 日志，永不回落 workspace 广播 |
| DD-3 | **get-or-create 端点挂项目路由** `GET /api/projects/{id}/private-chat`，语义=取 `(project_id, creator_id)` 最新 active 会话、无则建 | 对照 CR-A 的 `GET /api/projects/{id}/chat`（router.go:1080，项目成员鉴权先例）；单活跃会话语义=CUSTOM.md DEC-1，SUG-1 落地见 §6.1 |
| DD-4 | **并发防重用部分唯一索引**，不用应用层锁 | `CREATE UNIQUE INDEX ... ON chat_session(project_id, creator_id) WHERE project_id IS NOT NULL AND status='active'`，冲突方重查——照抄 CR-A M1 容器 Issue 的防并发模式（160_issue_origin_project_chat.up.sql） |
| DD-5 | **既有全局 chat 面加排除谓词 `project_id IS NULL`**，Private Ask 会话不进浮窗/全页 chat 列表与 pending 聚合 | `ListChatSessionsByCreator`/`ListAllChatSessionsByCreator`（queries/chat.sql）按 (workspace, creator) 全量列会话，不加谓词则 Private Ask 会话会串进全局 chat 列表（NFR-2 回归红线）；pending 聚合（/api/chat/pending-tasks，router.go:1299-1300）同理——否则全局 FAB 徽标会指向列表里不存在的会话 |
| DD-6 | **Private Ask 会话不暴露 work_dir**，创建时 work_dir=NULL，面板不提供本地目录设定 | chat task 的 execenv 默认在 scratch 目录运行（execenv.go:227-236），仅当用户给 session 设了 work_dir 才重定向到本地目录（execenv.go:59-66 LocalWorkDir）；不暴露该入口 + chat 任务本就不做项目 worktree checkout = Ask-only「无法写 worktree」的机制保证，AC-3 真机验证 |
| DD-7 | **个人队列零开发**：chat 任务走既有 `EnqueueChatTask`（priority=2，task.go:1104-1121），不触碰 `guardProjectQueueCapacity` | 已核实 EnqueueChatTask 全路径无项目队列守卫调用；chat 任务无 issue/project 维度，不计入 D1 项目队列深度——FR-4「不受项目满队影响」天然成立，验收即证 |

## 3. 数据模型与迁移（1 个 migration）

**M1 `161_chat_session_project.up.sql`**：

```sql
ALTER TABLE chat_session ADD COLUMN project_id UUID REFERENCES project(id) ON DELETE CASCADE;
CREATE INDEX idx_chat_session_project ON chat_session(project_id, creator_id) WHERE project_id IS NOT NULL;
CREATE UNIQUE INDEX chat_session_project_creator_active_unique
  ON chat_session(project_id, creator_id) WHERE project_id IS NOT NULL AND status = 'active';
```

- nullable 列 + 部分索引：存量行零改写，迁移在含存量数据的库上 O(1) 执行（AC-5 无损要求）。
- down 迁移：DROP 两索引 + DROP COLUMN。
- `ON DELETE CASCADE`：项目删除时私聊会话随删（与 chat_message 级联一致，033_chat.up.sql:23）。

`chat_message` 不动；provider 会话恢复（`chat_session.session_id`）沿用，多轮上下文零开发。

## 4. 后端设计

### 4.1 sqlc 查询（queries/chat.sql）

新增：
- `GetProjectChatSessionForCreator`：`SELECT * FROM chat_session WHERE project_id=$1 AND creator_id=$2 AND status='active' ORDER BY created_at DESC LIMIT 1`（DEC-1 取法：最新 active）。
- `CreateChatSession` 扩 `project_id` 参数（nullable，既有调用方传 NULL，向后兼容）。

加排除谓词 `AND cs.project_id IS NULL`（DD-5）：
- `ListChatSessionsByCreator` / `ListAllChatSessionsByCreator`（全局 chat 会话列表两条）。
- pending 聚合查询（`ListPendingChatTasks`/`HasPendingChatTasks` 背后的 SQL，实施时按
  chat_pending_tasks 测试文件定位具体 query 名）。
- **不加**谓词的：`GetChatSession`/`GetChatSessionInWorkspace`（按 id 取，两面共用）、
  消息读写、GC 检查（`GetChatSessionGCCheck`，router.go:770——项目会话沿用同一 GC 生命周期）。

`make sqlc` 后 diff 审查限定 chat 相关 .sql.go。

### 4.2 `GET /api/projects/{id}/private-chat`（get-or-create）

`handler/project_chat.go` 内新增（与 CR-A 的 GetProjectChat 同文件同模式）：

1. 项目成员鉴权（沿 GetProjectChat 先例）。
2. `GetProjectChatSessionForCreator` 命中 → 返回 `{ session }`。
3. 未命中 → `CreateChatSession`（project_id=项目、agent_id=`settings.team_agent_id`、
   creator=caller、work_dir 不设、title 固定 `Private Ask`）；唯一索引冲突（并发双开）→ 重查返回。
   Team Agent 未配置 → `409 team_agent_not_configured`（复用 CR-A 错误码，前端引导态现成）。
4. 响应含 `agent_availability` 所需的 agent/runtime 信息（对齐既有会话接口形状，前端
   availability 判定复用）。

会话建立后，发消息/停止/已读全部走既有 `/api/chat/sessions/{id}/*` 端点（router.go:1283），
creator-only 鉴权既有，零新增。

### 4.3 隐私收敛（DD-1/DD-2，FR-6 主体）

**发布侧**——`events.Event`（internal/events/bus.go:21 已有 ChatSessionID 字段）加
`ChatRecipientID string`，填值点全量清单（grep ChatSessionID 发布点核实）：

| 发布点 | 事件 | 收件人来源 |
|---|---|---|
| handler/chat.go:303/350/399/489/680/880 `publishChat` | chat:message、chat:session_updated/deleted/read | caller userID（HTTP 层已强制 caller==creator） |
| handler/chat_title.go:104 | chat:session_updated（自动改题） | 同上/会话 creator |
| service/task.go:2819 | chat:done | `GetChatSession(task.ChatSessionID).CreatorID`（:579 已有同款取法） |
| handler/daemon.go:3192 `publishTask` | task:message（**chat 任务流式内容**） | task.ChatSessionID.Valid 时取 session creator；同函数内一次取值，随批次复用 |
| task 状态类事件（claim/完成/失败）中 ChatSessionID.Valid 的 | task:* | 同上；实施时以 `grep publishTask` 全量过一遍，凡 task.ChatSessionID.Valid 一律补 hint+收件人 |

`publishChat` 签名加 recipient 参数（调用点同步改）；chat 任务的 `publishTask` 路径新增
`publishChatTask` 变体或在 Event 上直接补两字段。

**桥接侧**——`cmd/server/listeners.go` SubscribeAll 在 workspace fanout 之前加一个分支：

```go
if e.ChatSessionID != "" {
    if e.ChatRecipientID != "" {
        b.SendToUser(e.ChatRecipientID, data)   // 多设备天然覆盖（hub.go:560）
    } else {
        slog.Error("chat event without recipient dropped", "type", e.Type, "chat_session_id", e.ChatSessionID)
        // fail-closed：宁可丢事件（前端靠既有 invalidate/refetch 自愈），绝不回落 workspace 广播
    }
    return
}
```

**前端零改动的依据**：`use-realtime-sync.ts` 的 chat handler 全部按 payload 内
chat_session_id 失效/直写本人缓存（:128/:939-990），非 creator 的客户端本就没有对应 query
缓存，收不到事件后行为不变；pending 聚合本就是"收事件→invalidate→服务端权限过滤重取"
（:106-121 的 PR#5018 安全注释），改为定向推送后该链路对 creator 完全保留。

### 4.4 既有 1:1 chat 的隐私顺带修复（明确入范围）

§6.2 核实说明当前**全局 1:1 chat 的消息内容同样在全工作区 fanout**（靠前端"没有缓存可写"
不渲染，抓包可见明文）。DD-1 的收敛按 `ChatSessionID != ""` 判别，天然把既有全局 chat 一并
收进 per-user 推送——这不是范围蔓延，而是同一条红线的同一处修复点（改的就是同一个 if 分支），
且是 NFR-2「浮窗/全页 chat 回归」必须覆盖的路径。回归面见 §8。

## 5. 前端设计

### 5.1 新组件 `packages/views/projects/components/project-private-ask.tsx`

替换 project-chat-panel 中 Private Ask 空态占位（CR-A 留的挂点），**不引入
use-chat-controller.ts / useChatStore**（该 controller 耦合全局单例 activeSessionId，
CR-A SDD 已论证）：

- 进入面时 `GET /api/projects/{id}/private-chat` 拿 sessionId（组件内 state/query 自管）。
- 消息流：`chatKeys.messages(sessionId)` + `chatKeys.pendingTask(sessionId)` 既有 query
  （store 无关，已核实）喂给 `ChatMessageList`（纯 props：messages/pendingTask/availability/
  分页三件套，chat-message-list.tsx:42-56）；WS 直写/失效由 use-realtime-sync 既有 handler
  按 sessionId 命中，零新增事件处理。
- 输入区：`ChatInput`（纯 props，附件/@提及/草稿现成）→ 既有会话消息发送端点；草稿走 CR-A 的
  project-chat-store `{projectId}:private-ask` 命名空间（store 已建，键已预留模式）。
- 生成状态与停止：`TaskStatusPill`（纯 props）+ 既有停止端点（仅本人会话，权限天然成立）。
- 模型选择器：沿 CR-A DD-4 模式绑定 agent 配置展示；Private Ask 面**只读徽标**（改模型走
  Team Agent 面/agent 配置，避免个人面改共享 agent 配置的越权歧义）。ponytail: 只读徽标是
  最短正确路径，个人级模型覆盖需 daemon 协议支持，已被 CR-A §6.3 排除。
- `409 team_agent_not_configured` → 复用 CR-A 引导态组件。
- **无 Ask/Coding 切换控件、无 work_dir 设定入口**（DD-6）。

### 5.2 locale

新增文案（Private Ask 面副标题/只读模式徽标/停止确认等）四语（en/ja/ko/zh-Hans），
过 locales parity 测试。空态问候语 `heyPrivateAsk` CR-A 已四语落库，直接沿用。

## 6. 需求评审建议落地

### 6.1 SUG-1 get-or-create 取法（定案，承 CUSTOM.md DEC-1）

`(project_id, creator_id, status='active')` 按 `created_at DESC LIMIT 1` 取最新，无则创建；
并发双开由部分唯一索引兜底（DD-4），冲突方重查。archived 会话不复活——归档后下次进入
新建会话（与全局 chat 归档语义一致）。会话列表/切换明确不做（PRD §7）。

### 6.2 SUG-2 WS 推送核实结论（定案，事实改变设计权重）

按工程纪律 4 落笔前核实，结论：

1. **服务端 scope 基建已存在但未启用**：Hub 订阅协议（hub.go:914-960）、ScopeChat 授权器
   （scope_authorizer.go:74-92，creator-only）、Redis relay 均已落地（MUL-1138 Phase 1）。
2. **当前生效路径是全 workspace fanout**：listeners.go SubscribeAll（:150-196）对含
   ChatSessionID 的事件仍 `BroadcastToWorkspace`，注释明说客户端未发 subscribe 帧、
   启用 scope 路由会静默丢消息。
3. **前端自己的安全注释佐证**（use-realtime-sync.ts:106-121，PR#5018）："Chat task:* events
   are a workspace fanout delivered to every member"——切分文档 §B 的担忧在代码里有署名实锤。

→ PRD 概述预留的条件分支**成立**：per-user 收敛是本 CR 必做后端项，方案取 DD-1/DD-2，
AC-1 的抓包验证是其验收。设计稿 §9.3 "WS chat:{sessionId} 房间（SendToUser）"的表述在
per-user 收敛后成立（以 SendToUser 实现，非房间订阅）。

### 6.3 SUG-3 TaskStatusPill 显式检查项（转测试设计）

写入测试报告模板检查单（对应 AC-6）：① 发送后 pill 出现且状态流转（排队→运行→完成）；
② 运行中「发送」变「停止」，点击后任务中断、已生成内容保留、pill 消失；③ 停止仅对本人
会话可用（他人无入口——Private Ask 面本身仅本人可达，属结构性保证，测试确认无越权端点即可）；
④ agent 无可用 Runtime 时 pill/availability 呈现「请先启动本地 Agent」引导（复用既有
availability 机制）。

## 7. FR → 设计映射

| FR | 落点 |
|---|---|
| FR-1 B2 迁移 | §3 M1（列 + 2 索引，存量零改写） |
| FR-2 会话获取 | §4.2 get-or-create + §6.1 取法（DD-3/DD-4） |
| FR-3 Private Ask 面 | §5.1（纯 props 组合，不触 controller/store 单例） |
| FR-4 个人独立队列 | DD-7（EnqueueChatTask 既有路径，零开发，验收证明） |
| FR-5 Ask-only 只读 | DD-6（work_dir 不暴露 + scratch execenv + 无切换控件） |
| FR-6 隐私推送 | §4.3 + §4.4（DD-1/DD-2，fail-closed） |
| FR-7 与 Team Agent 并行 | 结构性成立：两面异队列异任务类型（DD-7），AC-2 验证 |
| FR-8 输入区能力 | §5.1（ChatInput 纯 props 现成 + 模型只读徽标 + 无斜杠命令） |
| FR-9 停止 | §5.1 TaskStatusPill + 既有停止端点（creator-only 天然） |

## 8. 风险与回归面

| 风险 | 缓解 |
|---|---|
| **隐私收敛波及既有 chat 实时体验**（本 CR 最大风险面） | 收敛前后对 creator 的投递语义等价（SendToUser 覆盖全部连接）；回归清单：浮窗 FloatingChat 收发/未读徽标、全页 /chat 流式、pending FAB、多设备同账号、chat:done 缓存直写。Lark 集成走 bus 订阅（outbound.go:262）不经 WS 桥，不受影响（已核实其订阅点在 bus 层） |
| 漏掉某个 chat 任务的 task:* 发布点 → 该事件仍进 workspace 广播 | 实施时 `grep -rn "publishTask\|Bus.Publish"` 全量清单核对 ChatSessionID.Valid 分支；AC-1 抓包用「Team Agent 跑任务 + Private Ask 并行」双流场景，正是最容易漏的 task:message 路径 |
| fail-closed 丢事件导致 creator 端 UI 卡顿 | 丢弃分支只在"发布点忘填收件人"的实现 bug 下触发，ERROR 日志暴露；前端 invalidate/refetch 模式对丢失事件自愈（PR#5018 已建立该模式） |
| 全局 chat 列表排除谓词遗漏入口 | §4.1 清单 + 实施时 grep chat_session 全部 SELECT；AC-4 三处会话互不串的验收覆盖 |
| 唯一索引与存量脏数据冲突 | 索引条件 `project_id IS NOT NULL`，存量行全部 NULL，不可能冲突 |
| mobile（独立 RN 组件集）消费同批 chat 端点 | 服务端排除谓词与 per-user 推送对 mobile 同样生效（服务端过滤）；mobile UI 不在 P2 范围，抽查列表接口一处即可 |

## 9. AC → 验证方式

| AC | 方式 |
|---|---|
| AC-1 隐私（首要） | 双浏览器 A/B 同项目：A 在 Private Ask 发问至 Agent 回复全程，B 端 devtools WS 帧逐条核对——无 chat:message/chat:done/task:message 及任何含 A 会话 id 的帧；同时 A 的第二设备（另开浏览器同账号）正常收到（SendToUser 多连接验证）。加测：Team Agent 任务并行运行时重复抓包（task:* 路径） |
| AC-2 并行 | Team Agent 跑长任务中，同成员 Private Ask 发问得到回复；构造 D1 项目满队（limit 压 1），Private Ask 发送不受 429/禁用影响；两面 pill/队列状态互不串扰 |
| AC-3 Ask-only | 真机：Private Ask 让 Agent 改项目文件 → 无 worktree 写入、`git status` 干净；UI 无 Ask/Coding 切换、无 work_dir 入口 |
| AC-4 会话隔离 | 同用户项目 X / 项目 Y / 全局 /chat 三处各发消息：`SELECT project_id FROM chat_session` 核对归属；三处列表互不出现对方会话；刷新后各自恢复且多轮上下文延续（provider session 复用） |
| AC-5 迁移回归 | 含存量 chat_session 数据库上跑 M1（up/down 各一遍）；浮窗/全页 chat 全量回归（含 §8 隐私收敛回归清单）；Team Agent 面收发与执行卡回归 |
| AC-6 输入区/状态/双端/四语 | §6.3 检查单 ①–④ + 附件/@成员提及真机过一遍；web 与 desktop 双端；locales parity 测试全绿 |

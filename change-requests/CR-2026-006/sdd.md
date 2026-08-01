---
id: CR-2026-006-sdd
type: SDD
cr-ref: CR-2026-006
title: P2 三模式聊天 CR-A — 技术设计（三 tab 窗口骨架 + Team Agent 消息流核心）
target-version: "0.13"
owner: Ray
owner-role: development
status: draft
created: "2026-08-02T00:30:00+08:00"
updated: "2026-08-02T00:30:00+08:00"
revision: "0.1.0"
prd-ref: "change-requests/CR-2026-006/prd.md"
---

# SDD — P2 三模式聊天 CR-A

> 本 SDD 基于 multica worktree（`requirement/CR-2026-006`，派生自含 CR-2026-004 合并的 main）的
> 实地代码调查编写，所有文件路径/行号均已核实。需求评审 3 条建议（SUG-001/002/003）的落地见 §6。
> 路径相对 multica 仓根。

## 1. 设计总览

复用密度是本设计的核心：**不新建消息表、不新建 WS 连接、不新建消息渲染组件**。
Team Agent 群聊 = 一个 `origin_type='project_chat'` 的隐藏容器 Issue，
消息 = 该 Issue 的 comment 流（既有 timeline / WS / 通知基础设施全部直用），
Agent 执行卡 = 既有 task-runs + `task:message` 流（issue-detail 已有同款组合渲染），
新增的后端面积只有：1 个 migration、5 处查询排除谓词、1 个 service 方法、2 个 handler 路由、
1 个 project.settings 白名单键。

```
前端 project-detail (Tabs: Issues | Chat)
        └─ project-chat-panel（新）
             ├─ 三模式 tab 条（ui/tabs line variant）
             ├─ Team Agent 面：useIssueTimeline(容器issue) + listTasksByIssue + TimelineView(导出)
             │    输入区：ChatInput(复用) → POST /api/projects/{id}/chat/messages
             ├─ Private Ask 面：空态占位（CR-C）
             └─ Discussion 面：空态占位（CR-D）
后端 GET  /api/projects/{id}/chat            （容器 Issue lazy 创建 + 返回 issue_id/team_agent_id）
     POST /api/projects/{id}/chat/messages   （守卫 → 落 comment → 入队，满队同步 429）
```

## 2. 关键设计决策

| # | 决策 | 依据 |
|---|---|---|
| DD-1 | 容器 Issue 标记用 **`origin_type='project_chat'`**（扩 CHECK 约束），不用 metadata JSONB | origin_type 扩值有 4 次 migration 先例（060/111/131/149，DROP+ADD CONSTRAINT）；metadata GIN 索引只支持包含过滤、无排除过滤，排除谓词得全表扫 JSONB |
| DD-2 | 项目↔Team Agent 绑定用 **`project.settings.team_agent_id`**（JSONB 白名单键） | `project` 表无 agent 字段（已核实 migrations/queries 无先例）；CR-2026-004 已建立 settings 白名单键 + owner/admin 校验的完整先例（`team_agent_queue_limit`） |
| DD-3 | 薄发送端点**守卫前置**：guard → 落 comment → 入队；残余入队失败走**物理删除补偿** | 现状 `CreateComment`（handler/comment.go:1158-1334）是"落库→201→fire-and-forget 入队，失败仅 slog.Warn"；guard 前置消除占绝对多数的容量类失败；comment 无软删除（`DeleteComment` 是物理 DELETE，comment.sql:423-425），补偿即物理删 |
| DD-4 | 模型选择器 = **绑定 Team Agent 的模型配置编辑**（复用 `model-picker` + agent 更新端点），不做按消息覆盖 | 已核实 daemon 不消费任务 context 的模型覆盖（claim 响应固定取 `agent.Model`，daemon.go:1486；context JSONB 无模型消费点）——按消息覆盖需要动 daemon 协议，超出本 CR；改 Agent 配置模型是真实生效的最短链路 |
| DD-5 | 历史回放用 **timeline 全量返回**（硬帽 2000），不做真分页 | `GET /api/issues/{id}/timeline` 无分页（activity.go:43 全量 cap 2000），前端 Virtuoso 虚拟列表渲染无压力；PRD AC-3 的意图"可达最早消息"全量天然满足。ponytail: 消息量逼近 2000 时另立分页优化，容器 Issue 创建初期远未及 |
| DD-6 | 实时链路**零新增 WS 事件** | `comment:created` 已被 `use-issue-timeline.ts:93` 直写缓存；`task:message` 已被 `use-realtime-sync.ts:889` 直写；`task:*` 前缀失效已含 queue-status（:541，CR-2026-004） |

## 3. 数据模型与迁移（1 个 migration）

**M1 `1xx_issue_origin_project_chat.up.sql`**：
1. `issue.origin_type` CHECK 约束扩值 `'project_chat'`（照抄 149 的 DROP+ADD 模式）。
2. 部分唯一索引 `CREATE UNIQUE INDEX issue_project_chat_unique ON issue(project_id) WHERE origin_type='project_chat'`
   ——并发 lazy 创建下保证每项目至多一个容器 Issue（冲突方 `ON CONFLICT DO NOTHING` 后重查）。

不加新表、不加新列。`project.settings.team_agent_id` 是 JSONB 键，无 schema 变更。

## 4. 后端设计

### 4.1 查询排除谓词（SUG-001 落地，见 §6.1 全量清单）

排除谓词统一为 `i.origin_type IS DISTINCT FROM 'project_chat'`，落在 5 个查询点 + 2 个统计点：
handler 手写 SQL 的 `ListIssues`（issue.go:938 where 初始化处，list+count 共用）、
`ListGroupedIssues`（issue.go:1270）、`buildSearchQuery`（issue.go:465-468，注意该查询含
comment 内容子查询命中，必须排除否则聊天内容会从全局搜索泄漏进 Issue 结果）；
sqlc 的 `ListIssues`/`CountIssues`/`ListOpenIssues`（queries/issue.sql）+ `make sqlc`；
统计 `GetProjectIssueStats`/`CountIssuesByProject`（queries/project.sql:41-51，容器不计入项目 Issue 数）。
前端零改动（看板/泳道/甘特/my-issues 全走 `GET /api/issues`，已核实）。

### 4.2 `GET /api/projects/{id}/chat`

项目成员鉴权 → 查/建容器 Issue（`origin_type='project_chat'`，title 固定 `Team Agent Chat`，
依赖 M1 唯一索引防并发重复）→ 返回 `{ issue_id, team_agent_id | null }`。
`team_agent_id` 读 `project.settings`；未配置时前端渲染配置引导态（见 §5.3）。

### 4.3 `POST /api/projects/{id}/chat/messages`（薄发送端点）

`TaskService.SendProjectChatMessage(ctx, projectID, callerID, content, attachmentIDs)`，顺序：

1. 项目成员鉴权；解析 `settings.team_agent_id`，未配置 → `409 team_agent_not_configured`。
2. **容量守卫**：调 `guardProjectQueueCapacity`（task_queue_capacity.go:59，同包私有可直调；
   新 service 方法与它同在 `internal/service`）。满队 → `429 project_queue_full`（含 depth/limit，
   复用 `writeProjectQueueFull` 的映射写法，issue.go:2010-2017）。**评论未落库，无孤儿。**
   owner/admin 沿 D1 语义豁免并携带插队优先级。
3. `Queries.CreateComment` 落 comment（author=caller，挂容器 Issue）。
4. 入队：复用 `EnqueueTaskForMention` 路径把任务派给 team agent（绕过 mention 解析，直接指定
   agent；priority 沿现状默认，owner/admin 由 guard 返回的覆盖优先级生效——D1 既有机制）。
5. **补偿（SUG-002 落地，见 §6.2）**：步骤 4 失败 → 物理 `DeleteComment` + 返回
   `502 enqueue_failed`（结构化错误，语义="消息未发出，可重试"）。补偿删除本身失败（双重故障）→
   ERROR 日志（含 comment_id/task 意图，**不含消息正文**，沿审计脱敏约束）+ 仍返回 502。
6. 成功后 `publish(comment:created)` + 201 `{ comment, task_id }`。WS 发布放在入队成功之后——
   失败的发送不会先广播再消失（补偿窗口内其他客户端全量刷 timeline 的竞态窗口极小，接受并记录）。

对照现状：既有 Issue 页评论 @提及路径（CreateComment handler）完全不动，fire-and-forget 语义保留。

### 4.4 `UpdateProject` 白名单扩键

`settings.team_agent_id`：owner/admin 可写（沿 CR-2026-004 的 `team_agent_queue_limit` 校验模式），
校验 agent 存在且对项目所在 workspace 可见。

## 5. 前端设计

### 5.1 入口（project-detail.tsx）

`ResizablePanel id="content"` 内（:470 flex 列），`BreadcrumbHeader` 之后用 `ui/tabs.tsx`（line
variant）包住既有 `IssueSurface`（Issues tab）与新 `ProjectChatPanel`（Chat tab）；`?tab=` 参数
沿 apps/web 既有 searchParams 用法，缺省 issues。右侧 sidebar（含 ProjectQueueStatus）不动。
不采用"chat 作为 IssueSurface 第 5 个 mode"——modes 语义是同一数据的渲染模式，聊天不是。

### 5.2 新组件 `packages/views/projects/components/project-chat-panel.tsx`

- **三模式 tab 条**：Team Agent / Private Ask / Discussion（tooltip + 空态问候语三条 + 首次教程
  气泡，气泡已读态入 project-chat store）。Private Ask / Discussion 面 = 纯空态（问候语 + "由后续
  版本提供"副文案），不发任何请求。
- **Team Agent 消息流**：`GET /api/projects/{id}/chat` 拿容器 issue_id 后，组合既有
  `useIssueTimeline(issueId)`（comment 流，WS 直写缓存已有）+ `api.listTasksByIssue`（执行卡）+
  `buildTimeline`/`TimelineView` 渲染工具执行卡（**需从 chat-message-list.tsx 导出 TimelineView**，
  这是既有内部组件的导出化，无逻辑改动）；按时间交错呈现用户消息气泡 / Agent 回复 / 执行卡，
  组合方式对照 issue-detail.tsx:251-254 的 coalesce 先例。顶部"暂无更早消息"即全量列表顶（DD-5）。
- **输入区**：复用 `chat-input.tsx`（纯 props：附件/@提及/草稿），`onSend` 接薄发送端点。
  429 → 输入区禁用 + 「Agent 忙，请稍后」+ depth/limit 展示（分支写法对照 quick-create 的
  `project_queue_full` 处理），恢复由 `projectQueueStatusOptions`（D1）失效驱动；owner/admin
  不进禁用态。`502 enqueue_failed` → toast「发送失败，请重试」（草稿保留）。
  `409 team_agent_not_configured` → 引导态。
- **模型选择器（DD-4）**：输入区右侧放 `model-picker`（复用
  `packages/views/agents/components/inspector/model-picker.tsx` 模式，数据源
  `runtimeModelsOptions`，models.ts:40-52），绑定 team agent 的模型配置；有 agent 编辑权限者可改
  （走既有 agent 更新端点），无权限者只读徽标展示当前模型。无可用 Runtime →「请先在设置中启动
  本地 Agent」+ 发送禁用（复用既有 chat availability 机制与 `agent_unavailable` 结构化错误先例）。
- **Team Agent 未配置引导态**：owner/admin 见内联 agent 选择器（选定即写
  `settings.team_agent_id`），成员见「请联系项目 Owner 配置 Team Agent」。

### 5.3 状态与草稿

新建 `project-chat-store`（zustand，persist 按 workspace slug 命名空间——照抄 useChatStore 的
持久化写法但**独立 store**，不触碰其全局单例 `activeSessionId`）：
`drafts: Record<"{projectId}:{mode}", string>`、`activeMode: Record<projectId, mode>`、
教程气泡已读标记。三面独立 query key 天然成立（timeline/task-runs 按 issueId，未来 CR-C/D 各有
自己的 key 根）。

### 5.4 locale

新增文案（三条问候语、教程气泡、满队/未配置/无 Runtime 提示、tab 名等）全部四语
（en/ja/ko/zh-Hans），过 `packages/views/locales/` parity 测试。

## 6. 需求评审建议落地

### 6.1 SUG-001 容器 Issue 隐藏影响面（全量清单，逐一核实过）

| 入口 | 结论 | 动作 |
|---|---|---|
| Issue 列表/看板/泳道/甘特/my-issues | 全走 `GET /api/issues`（handler 手写 SQL） | issue.go:938 加谓词（覆盖 list+count） |
| open_only 分支 | sqlc `ListOpenIssues` | issue.sql 加谓词 + make sqlc |
| sqlc `ListIssues`/`CountIssues` | handler 已不用，但保留调用方 | 同上加谓词（防御性一致） |
| 分组看板 | `ListGroupedIssues` 手写 SQL | issue.go:1270 加谓词 |
| 全局搜索 | `buildSearchQuery` 含 **comment 内容子查询**——不排除会把聊天内容泄进搜索结果 | issue.go:465-468 加谓词 |
| 项目统计 | `GetProjectIssueStats`/`CountIssuesByProject` 会把容器计入 | project.sql:41-51 加谓词 |
| inbox/通知 | comment 落库不直接发通知；订阅仅来自显式订阅/autopilot/quick-create 三处 `AddIssueSubscriber`——容器 Issue **天生无订阅者**，无需改 | 无动作（验收时验证） |
| @提及通知 | `notifyMentionedMembers` 无视订阅直接发 inbox——群聊 @人 自然触达 | 保留（正是设计想要的行为，PRD US-1 语境） |
| mobile | 按 parity 规则复用同批端点（服务端过滤即覆盖）；mobile 本就不在 P2 范围 | 验收抽查一处即可 |

### 6.2 SUG-002 部分失败补偿语义（定案）

- 容量类失败（绝对多数）：**守卫前置**根除——429 时评论未落库，无任何残留。
- 残余入队失败（DB 异常等低概率）：**物理删除补偿** + `502 enqueue_failed`，用户侧语义
  ="未发出，可重试"（草稿保留）。不采用事务合并方案：`EnqueueTaskForMention` 内含守卫、插入、
  广播多步副作用，拆开接 WithTx 侵入面大于收益（ponytail: 补偿删除是 3 行代码）。
- 双重故障（补偿删除也失败）：ERROR 日志（脱敏：只记 id 不记正文）+ 502；孤儿评论表现为
  "可见但 Agent 无响应"，概率=两个独立 DB 故障相乘，接受并在 plan 风险表登记。
- WS 广播后置到入队成功之后，失败的发送不产生他人可见的幽灵消息。

### 6.3 SUG-003 模型选择器核实结论（定案）

已核实：既有 chat 输入区**无**模型选择器（chat-input.tsx 442 行零命中；sendChatMessage body 仅
content+attachment_ids）；daemon 不消费任务级模型覆盖（claim 固定 `agent.Model`）。
→ 落地为 DD-4：复用 `model-picker` + `runtimeModelsOptions` + agent 更新端点，绑定 Team Agent
配置模型（真实生效的最短链路）；按消息模型覆盖需动 daemon 协议，**明确排除**，与 Ask/Coding
切换同批留后续 CR。工作量按"复用组件 + 新挂点"估，不含新链路。

## 7. FR → 设计映射

| FR | 落点 |
|---|---|
| FR-1 入口骨架 | §5.1（project-detail Tabs + ?tab=） |
| FR-2 三模式 tab | §5.2（tab 条 + 空态 + 教程气泡；PA/Disc 占位） |
| FR-3 草稿持久化 | §5.3（project-chat-store） |
| FR-4 容器 Issue | §3 M1 + §4.1/§4.2 + §6.1 |
| FR-5 薄发送端点 | §4.3 + §6.2 |
| FR-6 消息流 | §5.2（timeline+task-runs+TimelineView 组合，DD-5/DD-6） |
| FR-7 满队反馈 | §5.2 输入区（429/502/409 三分支 + queue-status 恢复） |
| FR-8 模型选择器 | DD-4 + §5.2 + §6.3 |

## 8. 风险与回归面

| 风险 | 缓解 |
|---|---|
| 排除谓词遗漏某个 Issue 查询入口 | §6.1 清单来自全量 grep 调查；验收 AC-5 逐入口过 + 全局搜索单测聊天内容不泄漏 |
| sqlc 重新生成波及无关 generated 文件 | 只改 3 条 SQL，`make sqlc` 后 diff 审查限定 issue/project 两个 .sql.go |
| timeline 2000 硬帽（DD-5 的 ceiling） | ponytail 标注：消息量预警留给 CR-B 队列条常驻数据（同一 queue-status 轮询顺带），逼近时另立分页 CR |
| TimelineView 导出化影响既有 chat | 纯导出无逻辑改动；chat 页与浮窗回归（AC-6） |
| project-detail 主区重构引入布局回归 | Tabs 只包裹不改 IssueSurface props；四 modes 回归截图对比 |
| 补偿窗口竞态（他端全量刷 timeline 撞见待删评论） | 窗口毫秒级，撞见后下次失效即消失；不加锁（记录已知边界） |

## 9. AC → 验证方式

| AC | 方式 |
|---|---|
| AC-1 骨架 | 真机：Chat tab 进入/切换（devtools 网络面板证零请求）/?tab= 深链/草稿刷新保留/web+desktop 双端 |
| AC-2 闭环 | 真机 E2E：发消息→守卫→comment 落库（SELECT 只读核对）→入队→claim→执行卡流式→完成回复 |
| AC-3 回放 | 刷新后 timeline 全量回放（含执行卡）；顶部"暂无更早消息" |
| AC-4 满队 | settings.team_agent_queue_limit 压到 1（D1 配置端点）构造满队：成员 429+禁用+不落库（SELECT 核对），owner 正常入队；释放后恢复 |
| AC-5 容器隔离 | 逐入口核对：列表/看板/泳道/甘特/my-issues/全局搜索（含 comment 内容搜索）/项目统计数；通知侧证无订阅推送 |
| AC-6 回归 | locale parity 测试 + 浮窗/全页 chat/Issue 页评论 @提及回归 + IssueSurface 四 modes 目视回归 |
| AC-7 模型选择器 | 有 Runtime：下拉与 runtimes 页一致、owner 改模型后 agent 配置生效（SELECT 核对）；无 Runtime：引导文案 + 发送禁用 |

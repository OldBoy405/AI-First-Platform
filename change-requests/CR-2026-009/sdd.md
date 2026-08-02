---
id: CR-2026-009-sdd
type: SDD
cr-ref: CR-2026-009
title: P2 三模式聊天 CR-D — 技术设计（D6 Discussion：discussion 容器 Issue + 纯人类多人聊天）
target-version: "0.16"
owner: Ray
owner-role: development
status: draft
created: "2026-08-02T11:20:00+08:00"
updated: "2026-08-02T11:20:00+08:00"
revision: "0.1.0"
prd-ref: "change-requests/CR-2026-009/prd.md"
---

# SDD — P2 三模式聊天 CR-D

> 本 SDD 基于 multica main（52b5717，含 CR-2026-006/CR-A 合并）的实地代码调查编写，
> 所有文件路径/行号均已核实。需求评审 3 条建议（SUG-001/002/003）的落地见 §6。
> 路径相对 multica 仓根。

## 1. 设计总览

Discussion = **第二个隐藏容器 Issue + 纯 comment 流**，是 CR-A 模式的直接复刻减法版：
没有 agent、没有队列、没有薄发送端点——发送就是既有 `POST /api/issues/{id}/comments`，
实时就是既有 `comment:created`（`use-issue-timeline` 已直写缓存），通知就是既有
`notifyMentionedMembers`。新增面积：1 个 migration、1 个 ensure 服务函数 + 1 个 GET 端点、
8 处排除谓词扩值、**1 处触发豁免短路（本 CR 唯一动既有行为的点）**、1 个前端 DiscussionPane。

```
前端 project-chat-panel（CR-A 已有，Discussion 占位 → 实面）
        └─ DiscussionPane（新）
             ├─ GET /api/projects/{id}/discussion → { issue_id }（lazy 创建容器）
             ├─ useIssueTimeline(issueId) → CommentCard 列表（WS 直写缓存，零新增事件）
             └─ ReplyInput（复用，draftKey 原生草稿持久化）→ POST /api/issues/{id}/comments
后端 计算评论触发的唯一汇聚点 computeCommentAgentTriggers 按容器类型短路（红线豁免）
```

## 2. 关键设计决策

| # | 决策 | 依据 |
|---|---|---|
| DD-1 | 容器标记 **`origin_type='project_discussion'`**，migration 照抄 160 的 DROP+ADD CHECK + 部分唯一索引模式 | 与 CR-A 的 `project_chat` 完全同构；`origin_type` 列可空（042_autopilot.up.sql:75 无 NOT NULL），谓词必须 NULL 安全 |
| DD-2 | 红线豁免落在 **`computeCommentAgentTriggers` 函数顶部短路**（comment.go:1579）：`issue.OriginType=='project_discussion'` → 返回 nil | 该函数是全部 agent 触发的唯一汇聚点——@agent/@squad 提及、父评论续聊路由、assigned-squad-leader fallback 全在其内；3 个调用点（comment.go:1150/1358/2282）共用，一处短路全路径豁免，API 直建 comment 的边缘入口也被覆盖（SUG-001 的"写窄漏边缘入口"由此排除）。成员提及通知走 `notifyMentionedMembers`（notification_listeners.go:427），与触发链完全独立，不受影响 |
| DD-3 | **发送不建新端点**：Discussion 发消息 = 既有 `POST /api/issues/{id}/comments` | 无队列无守卫无入队，薄发送端点的三段式（guard→comment→enqueue）在 Discussion 无一适用；既有评论端点鉴权（workspace 成员）、附件、@提及、WS 广播全部现成 |
| DD-4 | 排除谓词从单值改为 **NULL 安全的容器类型清单**：`(i.origin_type IS NULL OR i.origin_type NOT IN ('project_chat','project_discussion'))`，8 处同步替换 | 保持一份可 grep 的容器清单，后续再加容器类型只改清单；不用 `NOT LIKE 'project_%'` 之类前缀魔法（未来非容器的 project_* 起源值会被误伤） |
| DD-5 | 入口端点独立：**`GET /api/projects/{id}/discussion`** → `{ issue_id }`，不并入 `GET /api/projects/{id}/chat` | PRD FR-1 要求"首次打开 Discussion 面时"才创建；并入 chat 端点会导致打开 Team Agent 面就预创建 discussion 容器（永不用 Discussion 的项目白背一个容器）。与 GetProjectChat（project_chat.go:28）同构，代码量相同 |
| DD-6 | 草稿用 ReplyInput **原生 `draftKey`**（reply-input.tsx:24-38 → useCommentDraftStore），不再走 project-chat-store | PRD FR-3 的意图是"独立持久化、互不串扰"；draftKey 以 discussion 容器 issueId 为键天然与其他两面隔离，复用现成机制优于在 project-chat-store 重复实现一份草稿逻辑 |
| DD-7 | 提及选择器**不做前端目标过滤**（@列表仍含 agent） | 红线由 DD-2 服务端豁免保证（@agent 不入队、无通知、无响应）；编辑器提及目标过滤需给 ContentEditor 加插件参数并层层透传，收益仅是选择器少几项。ponytail: 若用户实际频繁误 @agent，升级路径是 ContentEditor 增加 mention 目标过滤 prop |
| DD-8 | **inbox 提及通知落点补强**：容器起源 Issue 的 inbox 预览顶部加「前往项目聊天」跳转条，`project_chat` 与 `project_discussion` 共用 | 现状 inbox 按 issue_id 选中并预览 Issue 详情（inbox-page.tsx:76/149）——被提及者点开看到的是隐藏容器 Issue 的裸详情。PRD AC-2 要求"跳转到该讨论"；跳转条 → 项目页 `?tab=chat&mode=discussion`（CR-A 的 `?tab=` 已有，`?mode=` 本 CR 顺带补，panel 读参一次性设 activeMode）。CR-A 的 team-agent 提及通知同样受益 |

## 3. 数据模型与迁移（1 个 migration）

**M1 `161_issue_origin_project_discussion.up.sql`**（照抄 160 模式）：
1. `issue_origin_type_check` DROP+ADD，允许值追加 `'project_discussion'`
   （160.up.sql:15 现值：autopilot / quick_create / lark_chat / slack_chat / agent_create / project_chat）。
2. `CREATE UNIQUE INDEX issue_project_discussion_unique ON issue(project_id) WHERE origin_type='project_discussion'`
   ——并发 lazy 创建下每项目至多一个（FR-1 幂等），冲突方重查取胜者。

down 对称回收（照抄 160.down 的"先删容器数据再收约束"顺序）。不加新表、不加新列。

## 4. 后端设计

### 4.1 排除谓词扩值（8 处，DD-4 形态）

| 位置 | 查询 |
|---|---|
| handler/issue.go:474 | `buildSearchQuery`（含 comment 内容子查询——聊天内容不泄入全局搜索） |
| handler/issue.go:945 | `ListIssues` 手写 SQL（list+count 共用，覆盖看板/泳道/甘特/my-issues） |
| handler/issue.go:1279 | `ListGroupedIssues` |
| queries/issue.sql:15 / 176 / 224 | sqlc `ListIssues` / `CountIssues` / `ListOpenIssues` + `make sqlc` |
| queries/project.sql:45 / 54 | `GetProjectIssueStats` / `CountIssuesByProject`（容器不计入项目 Issue 数） |

### 4.2 `GET /api/projects/{id}/discussion`（DD-5）

router.go:1080 旁新增路由。handler 与 `GetProjectChat` 同构：项目存在性校验
（`GetProjectInWorkspace`）→ `EnsureProjectDiscussionIssue` → `{ issue_id }`。
service 侧把 `EnsureProjectChatIssue`（project_chat.go:37）的容器创建主体抽为私有
`ensureContainerIssue(originType, title)`，两个公开函数各传参调用（title 固定
`Discussion`）；sqlc 增 `GetProjectDiscussionIssue`（照抄 issue.sql:358-360 改类型值）。

### 4.3 触发豁免（DD-2，本 CR 唯一动既有行为的点）

`computeCommentAgentTriggers`（comment.go:1579）顶部：

```go
// project_discussion containers are the human-only Discussion surface:
// no comment on them may ever enqueue an agent run (CR-2026-009 red line).
if issue.OriginType.Valid && issue.OriginType.String == "project_discussion" {
    return nil
}
```

豁免面自证：该函数覆盖 @agent/@squad 提及触发、`hasMemberMention` 分支、agent 作者的
squad-leader fallback、父评论续聊路由全部四类；`SendProjectChatMessage`
（project_chat.go:139）直调 `EnqueueTaskForMention` 但硬绑 team-agent 容器 Issue，
不经过 discussion 容器，无豁免外溢（SUG-001 的"写宽误伤 team-agent-chat"由此排除）。

### 4.4 通知链（零改动）

`notifyMentionedMembers`（notification_listeners.go:427，三个调用点 :577/:742/:805）
基于 comment 事件独立运行，@成员直发 inbox，与触发链无耦合——FR-4 白拿。

## 5. 前端设计

### 5.1 `DiscussionPane`（project-chat-panel.tsx 的 discussion 占位 → 实面）

- 进入 Discussion tab 首次挂载时 `GET /api/projects/{id}/discussion`（react-query，
  staleTime Infinity）拿 issueId。
- 消息流：`useIssueTimeline(issueId)` → 只渲染 comment 条目（容器 Issue 无 task/activity
  噪音，防御性过滤一行）→ `CommentCard` 列表（ActorAvatar + ReadonlyContent + ReactionBar +
  附件全在卡内现成）。`comment:created` WS 直写缓存（use-issue-timeline.ts:93）→ AC-1 实时性
  零新增事件。空态复用 CR-A 已落的 `heyDiscussion` 问候语（去掉"由后续版本提供"副文案）。
- 输入区：`ReplyInput`（issueId=容器、parentId=root、draftKey=容器 issueId 命名空间）→
  onSubmit 调既有 createComment API。ReplyInput 本身只有附件 + @提及——PRD FR-3 的
  "无模式/模型/技能下拉、无停止"由组件选择天然满足，无需裁剪代码。
- `?mode=` 深链（DD-8 顺带）：panel 挂载时读一次 searchParam 设 activeMode。

### 5.2 inbox 跳转条（DD-8）

inbox 预览侧：所选 item 的 issue 为容器起源（`origin_type ∈ {project_chat, project_discussion}`）
时，预览顶部渲染「此消息来自项目聊天 → 前往查看」，链接 `项目页?tab=chat&mode={team_agent|discussion}`。
issue 详情数据 inbox 预览已在取（含 origin_type/project_id），纯渲染分支。

### 5.3 locale

新增文案（跳转条、Discussion 空态副文案调整等）四语（en/ja/ko/zh-Hans），过 parity 测试。

## 6. 需求评审建议落地

### 6.1 SUG-001 豁免机制定案

按容器类型在 `computeCommentAgentTriggers` 单点短路（§4.3），不在提及解析层做——
提及解析（util.ParseMentions）被通知链共用，动它会伤 FR-4。既有 Issue 页评论回归验证：
非容器 Issue 的 OriginType 为 NULL 或其他值，短路不命中，triggers 行为逐字节不变；
`filterSuppressedCommentAgentTriggers` / suppressAgentIds 链路不动。

### 6.2 SUG-002 隐藏影响面复核（基于 CR-A SDD §6.1 清单逐点核对 discussion 值）

| 入口 | 结论 |
|---|---|
| 列表/看板/泳道/甘特/my-issues/open_only/分组/全局搜索/项目统计 | §4.1 的 8 处谓词扩值全覆盖（与 CR-A 完全同批位置，无新增入口——已 grep 复核 main 无 CR-A 之后新增的 Issue 列表查询） |
| inbox/通知 | 容器天生无订阅者（订阅仅显式/autopilot/quick-create 三处），@提及通知是设计要的行为（FR-4）；落点体验缺口由 DD-8 跳转条补强 |
| mobile | 服务端过滤即覆盖；mobile 不在 P2 范围 |

### 6.3 SUG-003 FR-6 行内系统条核实结论（定案：裁剪）

已核实：multica **无 project_member 表**（成员唯一模型是 workspace 级 `member`，
001_init.up.sql:26；项目无独立成员集）；成员变更仅有 `member:added` 瞬时 WS 广播
（invitation.go:456），**不落任何持久化消息流**。把 workspace 级成员变更持久化进每个
项目的 Discussion 流属于错误作用域（一次入职会刷屏所有项目讨论）。
→ **FR-6 本 CR 裁剪不实现**，走 PRD AC-7 预留的裁剪口径（本节即留痕）。
升级路径：若未来引入项目级成员模型，以系统身份 comment 落容器 Issue 即可获得
持久化系统条，渲染侧 CommentCard 按 author_type 分支。

## 7. FR → 设计映射

| FR | 落点 |
|---|---|
| FR-1 discussion 容器 Issue | §3 M1 + §4.2（ensure + 唯一索引幂等）+ §4.1（隐藏） |
| FR-2 消息流 | §5.1（useIssueTimeline + CommentCard，DD-3/零新增 WS 事件） |
| FR-3 输入区纯人类形态 | §5.1（ReplyInput 天然无 agent 控件，DD-6 草稿/DD-7 提及） |
| FR-4 @提及通知 | §4.4（零改动）+ §5.2（AC-2 落点跳转条） |
| FR-5 零 Agent 触发红线 | §4.3 单点短路 + §6.1 豁免面自证 |
| FR-6 行内系统条 | §6.3 裁剪定案（AC-7 裁剪口径生效） |

## 8. 风险与回归面

| 风险 | 缓解 |
|---|---|
| 谓词替换（单值→清单）改动 8 处，漏改某处导致 discussion 容器泄漏 | 位置清单来自 grep `project_chat` 全量命中；实现后以 `grep -rn "project_chat'" server` 断言零残留单值谓词；AC-4 逐入口验收 |
| 触发短路误伤非容器 Issue | 短路条件是等值判断且带 Valid 检查；既有 comment 触发单测全量回归 + 新增 discussion 容器负向单测（@agent 评论 → triggers 为空） |
| `make sqlc` 再生成波及面 | 只改 issue/project 两个 .sql，diff 审查限定对应 .sql.go |
| inbox 跳转条对既有通知流回归 | 纯渲染分支，非容器 item 零路径变化；CR-A 的 team-agent 通知顺带获得跳转（行为增强，验收记录即可） |
| ReplyInput 提及选择器含 agent 的 UX 误导（DD-7 的 ceiling） | 服务端红线兜底；观察实际误用率，升级路径已注明 |

## 9. AC → 验证方式

| AC | 方式 |
|---|---|
| AC-1 多人实时 | 双浏览器双成员真机：A 发 B 实时上屏（comment:created 直写缓存）；刷新全量回放（timeline 全量返回，容器初期远低于 2000 硬帽，沿 CR-A DD-5 口径） |
| AC-2 提及通知 | @成员 → inbox 出现 item → 点击 → 预览含跳转条 → 落 Discussion tab 对应讨论 |
| AC-3 红线 | 发多条消息（含正文 @Agent 的一条）→ `SELECT count(*) FROM agent_task_queue` 前后零增量（DB 级）；同会话在普通 Issue 页 @agent 评论 → 正常入队（豁免不外溢反向验证） |
| AC-4 容器隔离 | 逐入口核对（列表/看板/泳道/甘特/my-issues/全局搜索含 comment 子查询/项目统计数）；与 team-agent-chat 容器并存互不干扰；重复进入 Discussion tab 后 `SELECT count(*)` 容器唯一 |
| AC-5 输入区形态 | 目视核对无模式/模型/技能/停止控件，仅附件+@；草稿：Discussion 输入后切 tab/刷新回来仍在，且 Team Agent 面草稿互不串扰 |
| AC-6 回归 | locale parity；Team Agent 面收发、Issue 页评论 @提及入队、浮窗/全页 chat 回归；comment 触发链单测全绿 |
| AC-7 系统条（裁剪） | §6.3 裁剪结论 + 评审记录留痕，按裁剪后范围验收（无实现项） |

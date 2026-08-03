---
id: CR-2026-012-sdd
type: SDD
cr-ref: CR-2026-012
title: P2 三模式聊天 CR-G — 技术设计（D8 DC 协调者 + 讨论转执行 + ChatInput 解耦）
target-version: "0.19"
owner: Ray
owner-role: development
status: draft
created: "2026-08-03T18:21:13+08:00"
updated: "2026-08-03T18:38:00+08:00"
revision: "0.1.1"
prd-ref: "change-requests/CR-2026-012/prd.md"
---

# SDD — P2 三模式聊天 CR-G

> 本 SDD 基于 multica `requirement/CR-2026-012` worktree（44769bbb8，含 CR-2026-009/010/011 全部合并）
> 的实地代码调查编写，所有文件路径/行号均已核实。需求评审 4 条建议（REQ-SUG-001..004）的落地见 §6。
> 路径相对 multica 仓根。
>
> **调查纠正 PRD 两处引用假设**（工程纪律留痕）：① PRD 引用的 `shadowchat.mergedForwardMessage`
> 等字典锚点是 CodeBanana 参考文档的锚点，multica 无 `shadowchat` 命名空间——新增文案按仓内惯例
> 落 `projects.json` 嵌套对象、snake_case、四语同 commit（DD-12）。② PRD FR-6 假设的
> "P0 Issue→CR 升级链路"在服务端不存在（router 全集核实：CR 相关只有 crctl 事件投影摄入 +
> 三个只读/审批端点，无任何 create/promote 路径；158 迁移注释明示权威在 git）——升级为 CR
> 由执行 Agent 按 requirement-register Skill 完成，服务端零 CR 写路径（DD-8）。

## 1. 架构概览

三块工作互相独立、可并行实施，汇合在 Discussion 面与 Team Agent 面：

```
① DC 协调者（后端为主）
   Discussion comment → computeCommentAgentTriggers（comment.go:1579 短路点改造：全拒 → 仅放行 DC）
        └─ @DC 触发 → EnqueueTaskForMention（既有，容量守卫适用）→ DC 任务（挂 discussion 容器）
             ├─ claim：AskOnly=true（新规则：discussion 容器任务一律只读沙箱，复用 CR-C 整链）
             ├─ 完成：CompleteTask → createAgentComment（既有不变量）→ 协调输出=可见 comment
             └─ DC 输出含 @{Team Agent} → enqueue 层 re-target（DD-5）→ 任务落 team-agent-chat 容器
② 合并转发（前后端）
   DiscussionPane 多选态（新，本地 Set state）→ 合并预览 Dialog →
   POST /api/projects/{id}/chat/merge-forward（新端点）
        └─ 校验选中 comment ∈ 本项目 discussion 容器 → 组装合并结构 markdown
           → 复用 SendProjectChatMessage 服务内核（presenter/容量守卫 + comment + enqueue + 补偿删除）
③ ChatInput 解耦（纯前端）
   ChatInput 拆为 ChatInputCore（只认 adapter）+ 默认包装（useChatStore adapter）
        └─ Team Agent 面 / Private Ask 面以 project-chat-store adapter 接入（附件槽扩展 DD-10）
```

## 2. 关键设计决策

| # | 决策 | 依据与替代方案权衡 |
|---|---|---|
| DD-1 | **DC = agent 模板 + project setting**：新增 agenttmpl 模板 `discussion-coordinator`（agenttmpl/templates/*.json，25 个模板同款），项目绑定走 `project.settings` 新 key `discussion_coordinator_agent_id`（镜像 `team_agent_id`，task_queue_capacity.go:35 先例）；创建时 `permission_mode=public_to`+workspace target（全员可 @）。**不引入 DB 级内置 Agent**（全仓无 is_system 先例，agenttmpl 包注释明示模板故意 repo-only） | 替代：agent 表加 is_system 列——为一个角色建新机制，且违背模板先例；弃 |
| DD-2 | **激活口子 = 短路点改造**：`computeCommentAgentTriggers`（comment.go:1579-1590）的 `project_discussion → return nil` 改为：读项目 settings 的 DC id，未配置 → 照旧 return nil；已配置 → 正常计算后**过滤只保留 `agentID == DC`** 的触发。@提及经既有 `canInvokeAgent`（comment.go:1696）鉴权。**v1 仅 @提及激活**：Discussion 是刻意的扁平流（discussion-pane.tsx:25-36 设计注释，无 reply 线程），"回复 DC 激活"裁剪（§6.1）；未来若 reply-to 落地，父评论路由触发天然被同一过滤覆盖，零额外改动 | 单一 choke point 是 CR-D 验证过的豁免面（4 调用点共用），在同点收窄保证"红线单开口"（NFR-2）可测试自证 |
| DD-3 | **DC 只读 = claim 层规则**：issue 任务 claim 响应中，任务所挂 issue 为 `project_discussion` 容器 → `AskOnly=true`（agent.go:329 wire 字段已有，CR-C 整链复用：brief 无 Repositories 段 runtime_config_sections.go:558、checkout 拒绝 daemon.go:2888 activeTaskAuth、health_test.go:437 有测试形态可抄）。DC 模板技能集只配 `mentioning`（builtin） | "forbidden 全部写 Skill"：技能本是白名单制（LoadAgentSkillBundles，daemon.go:2250 不在 allowed 即 404），模板不配写类技能 + AskOnly 沙箱双重达成；不需要新的黑名单机制 |
| DD-4 | **DC 可见输出 = 零新增**：DC 任务是 discussion 容器上的 issue 任务，完成不变量（task.go:1920-1958 CompleteTask→createAgentComment）自动落 agent comment → `comment:created` workspace 广播（listeners.go:209）全员实时可见、刷新回放。失败且不重试 → 既有 `type="system"` comment（task.go:2113）。**trivial 抑制豁免**（评审 TSUG-002）：`isTrivialDoneOutput` 抑制（task.go:1951）对 discussion 容器任务豁免（一行容器判定），保证"激活必有可见输出"（AC-2）是机制保证而非 prompt 约定；DC 模板 instructions 同时要求实质性总结输出，测试补 trivial 输出边界用例 | REQ-SUG-003 所担心的"新增后端接缝"经核实不存在——这正是选择"DC 任务挂 discussion 容器"而非独立会话模型的决定性理由 |
| DD-5 | **DC 路由 = enqueue 层 re-target**：`enqueueSingleCommentTrigger`（comment.go:1540）处新增：触发 comment 所在 issue 为 discussion 容器、作者为 DC、目标为项目 `team_agent_id` 时，改为 `EnsureProjectChatIssue` + 以 DC 身份（authorType=agent）落一条路由 comment 于 chat 容器 + `enqueueMentionTaskWithCommentPlan` 挂 chat 容器——任务与路由说明出现在 **Team Agent 面**（AC-3）；DC 在 Discussion 的完成输出即协调说明。originator 经 trigger comment 链解析为激活 DC 的人类（resolveOriginatorForIssueTask，task.go:863），容量守卫按人类 originator 正常适用 | 替代：放行 DC 的 @团队Agent 就地入队（挂 discussion 容器）——任务/输出全落 Discussion，Team Agent 面不可见，违背 AC-3 与"讨论归讨论、执行归执行"的容器语义；弃 |
| DD-6 | **满队可审计反馈**：discussion 容器上的触发 enqueue 撞 `ErrProjectQueueFull` → 以 system comment 落容器（结构化文案：队列 N/M），不静默（既有普通 Issue 评论触发失败仅日志，本 CR 不改那边）；合并转发端点同步返回 429 `project_queue_full`（复用 writeProjectQueueFull，issue.go:2033），前端保留多选态与预览 | REQ-SUG-004；DC 激活是 fire-and-forget comment 路径，429 无处返回，system comment 是"过程即记录"下唯一诚实呈现 |
| DD-7 | **合并转发 = 新端点复用 Send 内核**：`POST /api/projects/{id}/chat/merge-forward`；服务端取选中 comments（校验全部属于本项目 discussion 容器）按 created_at 排序，组装合并结构 markdown（§4.3），走 `SendProjectChatMessage` 同款服务序（presenter 守卫 → 容量守卫 → CreateComment on chat 容器 → enqueue → 失败补偿删除 → 成功才广播，project_chat.go:191-259 逐步复用）。**不用 `coalesced_comment_ids`**——该机制假设同 issue 的 comment 交付计划，跨容器语义不符 | presenter 守卫在既有路径内自然生效（CR-E 已交付），无需本 CR 关心；上限 `comment_ids ≤ 50` 防 prompt 爆量（ponytail: 超长讨论合并的摘要压缩是升级路径） |
| DD-8 | **升级 CR = prompt 指令，服务端零 CR 写路径**：请求带 `register_cr: true` → 组装内容追加 requirement-register 指令块（要求 Team Agent 按该 Skill 建 CR 并回报 CR-ID）。判定语义（REQ-SUG-002 定案）：**不做服务端强制**——预览内「升级为 CR」复选框由用户决定，默认勾选态 = 前端读 projectGates（project-team-agent-chat.tsx:107 已消费的 `projectGatesOptions`）无在途 gate 时默认勾选，有则默认不勾；cr_id 归因走既有 `AttributeTaskToCR`（daemon.go:2412 StartTask CRID 回传），注册成功后的后续 pipeline 节点任务自然归因，本 CR 不加列不加端点 | CR 权威在 git（158 迁移注释），任何服务端"建 CR"端点都违背权威铁律；指令块随 comment 可见，升级动作本身留在讨论记录里 |
| DD-9 | **ChatInput 拆分而非条件分支**：抽 `ChatInputCore`（props 收 `draftAdapter: ChatInputDraftAdapter`，内部零 useChatStore）+ 既名导出 `ChatInput`（薄包装：内部 hook 构造默认 adapter——读 activeSessionId/selectedAgentId 派生 draftKey/editorKey + 四写方法，语义与今日逐字节一致）。传入自定义 adapter 的消费方直接用 `ChatInputCore` | rules-of-hooks 下"传 adapter 就不订阅 store"无法在单组件内做条件 hook；拆分让"自定义 adapter 时不触碰 useChatStore"成为**结构性事实**，单测静态断言可锁（§5.4）。`/chat` 页与浮窗 import 与 props 零改动 |
| DD-10 | **project-chat-store 扩附件槽**：`draftAttachments: Record<key, Attachment[]>` + `setDraftAttachments/addDraftAttachment`（key 沿 `projectChatDraftKey`），`setDraft("")` 时联动清附件；沿既有 zustand persist（`multica_project_chat`）与 workspace rehydration | 全局 store 有附件持久化先例（store.ts:81-113）；不持久化则切 tab 丢附件，与文本草稿语义不对称 |
| DD-11 | **@提及仅成员 = 编辑器类型过滤**：`MentionSuggestionOptions` 加 `itemTypes?: MentionItem["type"][]`（buildSyncItems 结果按 type 过滤，含 server-search 分支），`ContentEditor` 透传新 prop `mentionItemTypes`；两个回填面传 `["member"]`。Discussion 面维持 CR-D DD-7 现状（不过滤，服务端红线兜底）不动 | 通用 editor 小改（一处过滤点），比在消费方包装 contextItems 干净；CR-D 当时评估的"层层透传"成本因本 CR 本来就动 ContentEditor props 而摊薄 |
| DD-12 | **字典键落位**：`projects.json` 新增嵌套对象 `chat.merged_forward.*`（trigger_message / chat_history / messages_in_conversation / preview_title / confirm / cancel / register_cr_label 等）与 `chat.dc.*`（queue_full_notice 等），snake_case、四语同 commit（CR-D 惯例：git 3bce9ade0，8 文件一次补齐，parity.test.ts 强制） | PRD 引用的 shadowchat.* 是 CodeBanana 锚点非仓内键（§0 纠正①） |

## 3. 数据模型与迁移

**零 migration**。全部落在既有结构：

| 变更 | 载体 |
|---|---|
| DC 绑定 | `project.settings` JSONB 新 key `discussion_coordinator_agent_id`（读法照抄 task_queue_capacity.go:100-114 的 settings 读取，非法值视为未配置） |
| DC Agent 本体 | 普通 agent 行（模板物化，agenttmpl 机制） |
| DC/合并转发任务 | `agent_task_queue` 既有列（trigger_comment_id / project_id / originator_user_id 等，B4 两列不动） |
| 合并转发消息 | chat 容器上的普通 comment（合并结构在 content markdown 内） |
| 回填面附件草稿 | 前端 project-chat-store persist（非 DB） |

## 4. 后端设计

### 4.1 触发过滤改造（DD-2，本 CR 唯一动既有行为的点之一）

`computeCommentAgentTriggers`（comment.go:1579）：

```go
if issue.OriginType.Valid && issue.OriginType.String == "project_discussion" {
    dcAgentID := h.projectDiscussionCoordinatorID(ctx, issue.ProjectID) // settings 读取，未配置 → 零值
    if !dcAgentID.Valid {
        return nil // CR-2026-009 红线原样
    }
    triggers = computeAsUsual(...)
    // 放行两类并集（SDD-BLOCK-001 修正）：
    //  ① 目标为 DC 的触发（激活：@DC；未来 reply-to 落地则父评论作者=DC 亦命中）
    //  ② 作者为 DC 且目标为项目 team_agent_id 的显式提及触发（路由，交 §4.2 re-target 消费）
    // 其余（成员提及、@第三方 agent、squad、续聊路由）照旧丢弃；DC @DC 自触发按作者=目标排除
    return filterDiscussionTriggers(triggers, dcAgentID, teamAgentID, commentAuthor)
}
```

- 4 个调用点（comment.go:1150/1358/2294、daemon.go:2730）自动继承收窄语义；DC 完成输出中的
  @{team agent} 提及经 daemon.go:2730（completion reconcile）与 comment.go:1358 两路都会命中
  第 ② 类，均汇入 §4.2 的 re-target。
- `discussion_trigger_exemption_test.go` 全量保留（未配置 DC 场景）+ 新增已配置 DC 的分支：
  @DC 放行（①）、成员 @其他 agent 仍拒、正文含 DC 名字无 mention 链接不触发（mention 是
  `[@Label](mention://…)` 结构化链接，纯文本天然不命中）、**DC 作者 @团队Agent 放行（②）、
  DC 作者 @第三方 agent 拒、DC @DC 自触发拒**。

### 4.2 DC 路由 re-target（DD-5）

`enqueueSingleCommentTrigger`（comment.go:1540）`case commentTriggerSourceMentionAgent` 内：

```go
if isDiscussionContainer(issue) && commentAuthorIsDC && trigger.AgentID == projectTeamAgentID {
    chatIssue := EnsureProjectChatIssue(...)
    routeComment := CreateComment(chatIssue, AuthorType: "agent", AuthorID: dc, content: 原 DC comment 摘录 + 路由标注)
    task := enqueueMentionTaskWithCommentPlan(chatIssue, teamAgentID, routeComment.ID, ...)
    // 满队 → DD-6 system comment 落 discussion 容器；成功 → EventCommentCreated 广播 chat 容器侧
}
```

- 进入本分支的正是 §4.1 第 ② 类触发（DC 作者 × team_agent 目标）；第 ① 类（激活）走普通
  就地入队。DC @成员 / @第三方 agent / DC @DC 均已在 §4.1 过滤，不进本分支。
- **originator 定案**（评审 TSUG-001）：DC 完成 comment 的 `parent_id` = 激活它的人类 @DC
  comment（task.go:1958 createAgentComment 以 TriggerCommentID 为 parent），re-target 分支
  由此链显式解析激活人类并作为路由任务的 originator 传入——容量守卫按人类 originator 生效；
  若链上解析不到人类（异常态），沿 task_queue_capacity.go:49-57 的既有 a2a 直通语义放行并
  记日志，AC-3 验收以显式解析路径为准。任务期核实 `resolveOriginatorForIssueTask` 是否已
  具备穿透能力，不足则在 re-target 处显式计算后透传（enqueue 变体参数或入队后 set，取小者）。

### 4.3 合并转发端点（DD-7/DD-8）

```
POST /api/projects/{id}/chat/merge-forward        （router.go:1081 旁，user session 鉴权）
req : { comment_ids: string[] (1..50), register_cr?: boolean }
resp: 201 { comment_id, task_id }                  （同 SendProjectChatMessageResponse）
err : 400 invalid_comment_selection（空/超限/含非本项目 discussion 容器的 comment）
      403 presenter_required ｜ 409 team_agent_not_configured ｜ 429 project_queue_full
      502 enqueue_failed（补偿删除后）
```

组装的 comment content（markdown，全员可读即"合并预览"的持久形态）：

```
## {chat.merged_forward.trigger_message}
> {最早一条选中消息全文（作者/时间标注）}

## {chat.merged_forward.chat_history}（{count} 条）
- [{作者} {时间}] {消息内容}
- …（按 created_at 升序）

[register_cr=true 时追加]
## 升级为 CR
请按 requirement-register Skill 将上述讨论注册为 CR（目标 workspace 的 knowledge-base 仓），
完成后在本会话回报 CR-ID。
```

服务函数 `MergeForwardDiscussion`：校验（comments 全属 `GetProjectDiscussionIssue` 的容器）→
复用 `SendProjectChatMessage` 的守卫与补偿序（project_chat.go:191-259 抽公共内核或平行实现，
以抽内核为先）。`trigger_summary` 由既有 `buildCommentTriggerSummary` 自然生成。

### 4.4 AskOnly claim 规则（DD-3）

issue 任务 claim 组装处（agent.go:312-329 响应体 / daemon.go 对应 handler）：任务 issue 的
`origin_type == 'project_discussion'` → `resp.AskOnly = true`。规则按容器而非按 agent——
**discussion 容器上的任何任务都只读**（当前只有 DC 任务能挂上来，规则面向未来收敛）。
chat session 路径的既有 AskOnly 判定（daemon.go:1846）不动。

### 4.5 DC settings 读取与配置

- `projectDiscussionCoordinatorID`：settings JSONB 读 key，UUID 解析失败视为未配置（fail-safe 回到红线全拒）。
- 配置入口沿 `team_agent_id` 的既有 project settings 更新端点/UI 面（CR-A 已有），新 key 零后端改动
  （settings 是自由 JSONB）；前端设置面加一个 agent 选择器项。

## 5. 前端设计

### 5.1 DiscussionPane 多选态 + 合并预览（无先例，自研交互）

- **多选态**：`DiscussionPane` 本地 `useState<Set<string>>`（消息量级小，无需 zustand；
  issue selection-store 是跨组件场景，此处单组件内够用）。入口：消息 hover 操作或工具条
  「选择」按钮进入选择模式 → `DiscussionMessage` 左侧渲染 Checkbox（`@multica/ui`）。
- **底部批量条**：选中 N>0 时浮出（batch-action-toolbar.tsx 视觉惯例）：「已选 {count} 条」+
  「合并转发」+「取消」。
- **合并预览 Dialog**：trigger_message = 最早一条选中消息；chat_history 列表（作者/时间/内容，
  升序）；`messages_in_conversation` 计数文案；「升级为 CR」Checkbox（默认态按 DD-8 读
  projectGates；**gates 端点缺失/报错时回落默认不勾选**——端点受 approvalSvc 特性开关保护，
  签名密钥未配置的环境整组路由不存在，router.go:720-727，评审 TSUG-003）；确认 → POST
  merge-forward → 成功 toast + 退出多选态；429/403 → 结构化错误提示，**保留多选态与预览**（DD-6）。
- DC 绑定后 Discussion 空态/教程文案不动；DC 的 agent comment 用既有 `DiscussionMessage`
  渲染（ActorAvatar 已按 author_type 分支），零新组件。

### 5.2 ChatInputCore 拆分（DD-9）

`packages/views/chat/components/chat-input.tsx` 内：

```ts
export interface ChatInputDraftAdapter {
  draftKey: string; editorKey: string;
  draft: string; attachments: Attachment[];
  setDraft(draft: string): void;
  setAttachments(attachments: Attachment[]): void;
  addAttachment(attachment: Attachment): void;
  clearDraft(): void;
}
function ChatInputCore(props: ChatInputProps & { draftAdapter: ChatInputDraftAdapter }) { …今日全部实现，store 触点逐一改读 adapter… }
export function ChatInput(props: ChatInputProps) { const adapter = useGlobalChatDraftAdapter(); return <ChatInputCore {...props} draftAdapter={adapter} />; }
```

五处触点全部改经 adapter（技术债文档 §4.1 四处 + 探查补充的 `onUpdate` :387-398 写点）：
读订阅（:112-150）、restore effect（:186-220，`restoreDraftRequest.sessionId !== adapter.draftKey`
判定不变）、`handleUpload`（:231）、`handleSend/commitInput`（:284 keyAtSend 捕获改捕获
adapter 引用 + :309-312 清理，`extraDraftKeys` 语义仅默认 adapter 使用方需要，Core 里保留
回调形态）、`onUpdate`（:389/:395）。JSX（:354-441）与既有 `ChatInputProps` 不变；
`/chat` 页（chat-page.tsx:194）与浮窗（chat-window.tsx:867）零改动。

### 5.3 两面回填（DD-10/DD-11）

- **project-chat-store 扩展**：`draftAttachments` + 两写法 + `setDraft("")` 联动清理（§2 DD-10）。
- **adapter 构造**（每面约 15 行 hook）：`draftKey = projectChatDraftKey(projectId, mode)`、
  `editorKey = mode`（恒定，项目面无"切 agent 重挂载"语义，技术债文档 §4.3 定案照抄）。
- **Team Agent 面**：`TeamAgentComposer` 的 textarea（project-team-agent-chat.tsx:845-859）
  换 `ChatInputCore`；`onSend` 接既有 `useSendProjectChatMessage` 流（pending bubble/错误分支
  :708-765 不动）；**薄发送端点扩 `attachment_ids?: string[]`**（SendProjectChatMessageRequest
  project_chat.go:214 加可选字段，comment 绑定沿 `POST /api/issues/{id}/comments` 的既有
  attachment 绑定逻辑抽用）；`onUploadFile` 用 `useFileUpload(api).uploadWithToast(file, { issueId: chat容器 })`；
  `mentionItemTypes=["member"]` + `contextItems`（use-chat-context-items 既有）。
- **Private Ask 面**：`PrivateAskComposer` 同款替换；`onSend` 接 `api.sendChatMessage`（附件
  参数沿全局 chat 的既有签名）；`onUploadFile` 绑定已有 session；`mentionItemTypes=["member"]`。
  停止按钮/模型只读徽标等结构不动（只换输入组件）。
- Discussion 面**不接** ChatInput（CR-D DD-6 的 useCommentDraftStore 草稿语义保留）。

### 5.4 单测锁定（PRD FR-7）

`chat-input.test.tsx` 新增：
- **静态断言**：mock `@multica/core` 的 `useChatStore`，渲染 `ChatInputCore` + 自定义 adapter，
  断言 mock 零调用（拆分后为结构性成立，测试防未来回归）。
- **行为断言**：输入/上传/发送/restore 各动作后断言 adapter 方法按预期调用、全局 store state
  快照不变。
- 既有用例全量跑在 `ChatInput` 默认包装上，证明默认路径零回归。

### 5.5 locale（DD-12）

`projects.json`：`chat.merged_forward.*`（约 10 键）、`chat.dc.*`（约 3 键）、settings 面
DC 选择器文案；四语同 commit，parity 全绿。

## 6. 需求评审建议落地

### 6.1 REQ-SUG-001（回复激活）——定案：v1 裁剪为仅 @提及激活

Discussion 是刻意的扁平 comment 流（CR-D 设计注释 discussion-pane.tsx:25-36，reply 线程被
切分文档 §0.4 写死排除）；为 DC 单独引入 reply-to UI 违背该定案且服务端父评论路由需要
parentId 才能命中。**AC-2 按 @提及单一激活方式验收**，本节即裁剪留痕。升级路径：未来 reply-to
落地时，DD-2 的过滤对"父评论作者为 DC"的触发天然放行，零额外后端改动。

### 6.2 REQ-SUG-002（升级 CR 判定 + 归因）——定案见 DD-8

判定不做服务端强制（用户勾选，前端 projectGates 提供默认态建议）；cr_id 归因依赖既有
StartTask CRID 回传链，注册产生的后续节点任务自然归因；合并转发任务本身注册前无 CR-ID
可归因，属 CR-H（Runner）范围外的已知留白，不在本 CR 造临时机制。

### 6.3 REQ-SUG-003（DC 输出机制）——定案见 DD-4，接缝不存在

DC 任务挂 discussion 容器 → 完成不变量自动落 agent comment → workspace 广播。零新增通道、
零新增身份机制（author_type=agent 渲染现成）。失败呈现沿 type="system" comment 既有语义。

### 6.4 REQ-SUG-004（满队反馈）——定案见 DD-6

合并转发：同步 429 + 前端保留选择态。DC 激活：system comment 落容器（唯一可审计的
异步反馈位）。测试计划补两用例（§9 风险表关联）。

## 7. FR → 技术实现映射

| FR | 落点 |
|---|---|
| FR-1 DC 角色 | DD-1（模板+setting）+ §4.5；权限 DD-3（AskOnly claim 规则 + 白名单技能集） |
| FR-2 静默/激活边界 | §4.1 过滤改造（未配置=全拒不变；@提及经 canInvokeAgent；纯文本名字不命中） |
| FR-3 可见输出+路由 | DD-4（完成不变量落 comment）+ §4.2 re-target（路由现身 Team Agent 面） |
| FR-4 多选态+合并预览 | §5.1（本地 Set + 批量条 + 预览 Dialog，自研交互定案） |
| FR-5 合并生成单任务 | §4.3 端点 + 组装结构（一次确认 = 1 comment + 1 task） |
| FR-6 升级 CR | DD-8（register_cr 指令块，服务端零 CR 写路径，判定=用户勾选+gates 默认态） |
| FR-7 draftAdapter 解耦 | DD-9 + §5.2（拆分结构性达成"不触碰"）+ §5.4 双重锁定 |
| FR-8 两面回填 | §5.3（adapter + 端点扩 attachment_ids + mentionItemTypes 过滤） |

## 8. 安全与性能考量

- **红线单开口自证**（NFR-2）：收窄仍在唯一 choke point（4 调用点共用）；未配置 DC 的项目
  行为与 CR-D 交付态逐字节一致；exemption 测试保留 + 扩展。
- **DC 权限硬约束**（NFR-1）：AskOnly 在 claim 响应置位、daemon activeTaskAuth 执行期强制、
  brief 无 Repositories 段——三层同 CR-C 交付链，非 prompt 约束；技能白名单制天然禁写类 Skill。
- **越权面**：merge-forward 校验 comment 归属（跨项目/跨容器 id 混入 → 400）；DC 触发过 canInvokeAgent；
  升级 CR 指令块只是 comment 文本，执行强度由 Team Agent 的既有 execenv/controlled-shell/crctl
  验签链承担，本 CR 不新增执行通路（NFR-3）。
- **性能**：合并转发 ≤50 条上限；组装为一次批量查 comments + 一次 comment 写入；DC 触发过滤
  多一次 settings 读取（GetProject 单行，可与既有 projectTeamAgentID 读取合并）。
- **redaction**：DC/团队 agent 输出沿 redact.Text 既有路径（task.go:1950/2113），无新泄露面。

## 9. 风险与回归面

| 风险 | 缓解 |
|---|---|
| 触发过滤改造误伤普通 Issue 评论触发 | 改动仅在 `project_discussion` 分支内；既有 exemption 测试 + comment 触发全量单测回归 |
| re-target 分支的补偿语义（路由 comment 落了、enqueue 失败） | 沿 SendProjectChatMessage 的补偿删除模式（project_chat.go:236）；失败落 DD-6 system comment |
| ChatInput 拆分回归 /chat 页与浮窗 | 默认包装保持既名导出与 props；既有 chat-input.test.tsx 全量 + 浮窗/全页手测；draftKey/editorKey 派生逻辑原样搬入默认 adapter（含 :114-140 注释语义） |
| project-chat-store 扩附件后 persist 兼容 | 新字段可缺省（旧持久化数据无 draftAttachments → 空 map），rehydration 测试补分支 |
| mentionItemTypes 过滤漏 server-search 分支 | buildSyncItems 与 MentionList 异步搜索两处都过滤；单测断言 agent/squad/issue 不出现 |
| 合并转发长内容 prompt 爆量 | ≤50 条硬上限 + trigger_summary 截断既有机制；`ponytail:` 注释标注摘要压缩为升级路径 |
| parity 漏键 | 四语同 commit（CR-D 惯例），parity.test.ts 门禁 |

## 10. AC → 验证方式

| AC | 方式 |
|---|---|
| AC-1 静默边界 | 未配置 DC 项目 + 已配置 DC 项目各发普通消息/纯文本含 DC 名字消息 → `agent_task_queue` 零增量（DB 级，沿 CR-2026-009 AC-3 口径复验） |
| AC-2 激活与可见输出 | @DC → 任务入队（AskOnly=true 断言）→ 完成 → discussion 容器出现 agent comment，双浏览器实时可见；含 trivial 输出边界用例（DD-4 豁免生效仍落 comment）；审计：任务 work_dir 无写入、checkout 被拒（health_test 形态） |
| AC-3 路由 | DC 输出 @团队Agent → chat 容器出现路由 comment + 任务，Team Agent 面可见并执行；满队场景 → discussion 容器出现 system comment（DD-6） |
| AC-4 合并转发 | 多选 N 条 → 预览含三段结构 → 确认 → chat 容器 1 comment + 1 task，claim 到的 TriggerCommentContent 含完整合并结构；取消退出多选零副作用；429 → 预览保留 |
| AC-5 升级 CR | register_cr=true → comment 含指令块 → Team Agent 执行 requirement-register → knowledge-base 仓出现合规 CR 壳（cr.md + _backlog 条目）、回报 CR-ID；register_cr=false / 已有在途 gate 默认不勾 → 无指令块 |
| AC-6 解耦锁定 | §5.4 静态+行为双断言；既有 chat-input 测试全绿 |
| AC-7 回填 | 两面附件上传/渲染、@列表仅成员、富文本；跨项目跨模式草稿/附件隔离（project-chat-store key 断言 + 真机） |
| AC-8 回归 | parity 全绿；CR-D Discussion / CR-A Team Agent / CR-C Private Ask / 浮窗全页 chat 回归；presenter 与容量守卫回归（merge-forward 走同链路） |

---
id: CR-2026-012-prd
type: PRD
cr-ref: CR-2026-012
title: P2 三模式聊天 CR-G — D8 DC 协调者 + 讨论转执行（合并转发）+ ChatInput 解耦
target-version: "0.19"
owner: Ray
owner-role: requirement
status: draft
created: "2026-08-03T17:23:41+08:00"
updated: "2026-08-03T17:23:41+08:00"
revision: "0.1.0"
---

# PRD — P2 三模式聊天 CR-G：D8 DC 协调者 + 讨论转执行 + ChatInput 解耦

> 依据：`docs/product/P2-三模式聊天窗口主体-交付切分.md` v2（d7e4ece）的 CR-G 节（D8），
> 交互契约与字典锚点以《P2-三模式聊天交互设计》§5.1/§5.2 为准（`shadowchat.discussion`、
> `assignAgentTooltip`、`mergedForwardMessage.triggerMessage/chatHistory/messagesInConversation`）。
> **本 CR 是自研设计定位**——切分文档 §0.3 识别的两处偏差（DC 输出可见性、合并转发交互）
> 无 CodeBanana 实物可抄，本 PRD §1 定案。ChatInput 解耦技术债按
> `docs/product/P2-ChatInput组件与全局store解耦-技术债务.md` §4.1 方案 A 随本 CR 一并偿还
> （该文档 §6 约定的触发时机——CR-G 开始设计阶段——即现在）。
> 前置：CR-2026-009（CR-D）已交付 discussion 容器 Issue 与纯人类消息流；
> CR-2026-006（CR-A）已交付 Team Agent 消息流与入队路径（转发目的地）。

## 1. 概述

**背景**：CR-D 交付后，Discussion 是纯人类聊天面，与执行完全隔离（零 Agent 触发红线）；
CR-A 交付的 Team Agent 面是执行现场。两者尚无接合：讨论沉淀了但不能转化为执行——达成共识后
仍要有人手动去 Team Agent 面复述上下文；讨论本身也无人协调（总结、追踪、路由）。本 CR 交付
D8 的两个接合件：DC（Discussion Coordinator）协调者与合并转发（讨论转执行），落地 CodeBanana
核心理念「沟通发生在执行发生的地方」。同时，CR-A/CR-C 两次因 `ChatInput` 全局 store 耦合
而手写降级 composer（纯文本、无附件、无 @提及），技术债文档约定 CR-G 开工即第三次撞坑收敛点——
本 CR 一并偿还并回填两面。

**本 CR 交付**：
1. **DC 特殊 Agent**：默认静默，@提及 DC 或回复 DC 消息激活；只协调不执行——execenv 只读 +
   forbidden 全部写 Skill（服务端强制）；可 `EnqueueTaskForMention`（经 A2A）把任务路由到
   Team Agent；协调输出作为 Discussion 消息**全员可见**。
2. **合并转发（讨论转执行）**：多选 Discussion 消息 → 合并预览 → 生成一个带
   `triggerMessage` + `chatHistory` 汇总结构的 Team Agent 任务；项目尚无关联 CR 时，
   可触发 `requirement-register` 走 P0 的 Issue→CR 升级链路把讨论升级为 CR。
3. **ChatInput 解耦（方案 A，纯前端）**：`ChatInput` 新增可选 prop
   `draftAdapter?: ChatInputDraftAdapter`；未传时落回默认实现（`/chat` 页与浮窗零改动），
   传入时完全按 adapter 渲染/回写、不触碰 `useChatStore`；回填 Team Agent 面与 Private Ask 面
   （附件 + @提及仅成员 + 富文本），接 `project-chat-store` 的 `{projectId}:{mode}` 命名空间；
   新增单测锁定"自定义 adapter 时不触碰 `useChatStore`"。

**两处偏差的定案**（切分文档 D8 节要求 PRD 阶段先定）：
1. **DC 输出可见性 → 定案：可见协调输出**。CodeBanana 的 DC 是静默协调器（消息不出现在聊天中），
   本平台按"过程即记录"审计要求反其道：DC 的总结/追踪/路由动作全部以 Discussion 消息呈现，
   全员可见、可回放。静默协调不可取，此为产品决策，SDD 不得回退。
2. **合并转发交互 → 自研设计**。CodeBanana 实物只有多选逐条转发；"多条合并为一个带上下文任务"
   是本平台增量（字典 `mergedForwardMessage` 存在但无页面实物）。本 PRD 给交互轮廓
   （FR-4：多选态 + 合并预览 + 确认发送），视觉与细节 SDD 自定，无原产品可抄。

**技术前提**（SDD 阶段细化，偏离需论证）：
1. **红线豁免的唯一开口**：CR-2026-009 的零 Agent 触发红线原文即预留"除非 CR-G 的 DC 被显式
   激活"。本 CR 打开且仅打开这一个口子：@提及 DC / 回复 DC 才入队，其余 Discussion 消息
   （含正文出现 DC 名字但未 @ 的）行为与 CR-D 交付态完全一致。
2. **DC 权限是服务端硬约束**：execenv 只读 + forbidden 全部写 Skill 由任务执行环境强制，
   不是 prompt 层的君子约定；DC 的"执行"能力仅剩把任务路由给 Team Agent。
3. **不新增执行通路**：DC 路由与合并转发的目的地都是 CR-A 既有 Team Agent 入队路径
   （`EnqueueTaskForMention`），受 D1 容量守卫与既有 claim 串行化约束，队列语义零改动。
4. **"回复 DC 激活"的落地形态待 SDD 定案**：切分文档 §0.4 写死排除了消息回复（reply）线程，
   而 DC 的第二种激活方式是"回复 DC 的 Discussion 消息"。SDD 需定案最小实现（如仅针对 DC
   消息的轻量 reply-to 引用，不做通用线程），若论证成本过高可降级为仅 @提及激活，留痕即可。
5. ChatInput 改造范围按技术债文档 §4.1 逐行核实结论：`chat-input.tsx` 单文件四处改动点
   （读订阅、restoreDraft effect、handleUpload、handleSend/commitInput），约 230 行机械替换，
   渲染 JSX 与既有 props 接口不变。

## 2. 用户故事

- **US-1** 作为**项目成员**，我希望讨论跑偏或过长时 @DC 得到一份可见的总结/追踪/路由建议，
  而且这份协调记录留在讨论流里全员可查，以便协调过程本身也是可审计的项目记录。
- **US-2** 作为**项目成员**，我希望把达成共识的若干条讨论消息一次多选、合并转发成一个
  Team Agent 任务，而不是自己去 Team Agent 面复述上下文，以便"讨论的地方就是发起执行的地方"。
- **US-3** 作为**项目成员**，我希望一段有价值的讨论在尚无 CR 时能直接升级为合规的 CR，
  以便需求从口头共识进入治理轨道不需要换场景重新录入。
- **US-4** 作为**项目成员**，我希望在 Team Agent 面与 Private Ask 面获得与浮窗同级的输入体验
  （附件、@提及成员、富文本），而不是纯文本框，以便项目内沟通不再是降级体验。
- **US-5** 作为**平台维护者**，我希望 DC 在环境层面就无法写任何文件、`ChatInput` 新消费方
  在组件层面就无法误触全局单例，以便这两条红线靠机制而非靠 code review 记忆维持。

## 3. 功能需求

| ID | 需求 | 优先级 |
|---|---|---|
| FR-1 | **DC 特殊 Agent 角色**：平台内置 DC（Discussion Coordinator）特殊 Agent——execenv 权限只读 + forbidden 全部写 Skill（服务端强制，非 prompt 约束）；具备 `EnqueueTaskForMention`（经 A2A）路由能力；在 Discussion 面可被 @提及（字典 `shadowchat.discussion`/`assignAgentTooltip`） | P0 |
| FR-2 | **静默/激活边界**：DC 默认静默——普通 Discussion 消息（含正文提及 DC 名字但未 @ 的）不触发 DC、不产生 `agent_task_queue` 行（CR-D 红线不变）；@提及 DC 或回复 DC 消息（形态按技术前提 4 SDD 定案）时激活，激活即走既有入队路径（受 D1 容量守卫，满队结构化反馈） | P0 |
| FR-3 | **可见协调输出**：DC 激活后产生的协调输出（总结/追踪/路由说明）作为 Discussion 消息进入消息流，全员实时可见、刷新可回放；DC 路由任务时在 Discussion 内留下可见的路由说明，同时 Team Agent 面出现对应任务；DC 任务全程零文件写入 | P0 |
| FR-4 | **合并转发多选态 + 合并预览**：Discussion 消息流支持进入多选模式勾选若干消息；发起合并转发前展示合并预览——触发消息（`triggerMessage`）+ 聊天记录汇总（`chatHistory`）+ 「对话中的 {count} 条消息」（`messagesInConversation`），确认后发送，可取消退出多选态 | P0 |
| FR-5 | **合并转发生成任务**：确认后生成**一个** Team Agent 任务，prompt 上下文含 `triggerMessage` + `chatHistory` 汇总结构（多选 N 条 → 一个任务，非逐条 N 个）；走 CR-A 既有入队路径，受容量守卫，任务在 Team Agent 面正常呈现与执行 | P0 |
| FR-6 | **讨论升级 CR**：合并转发时项目尚无关联 CR 的场景下，可触发 `requirement-register` 把该段讨论升级为 CR——走 P0 的 Issue→CR 升级链路，产生合规 CR 壳（含讨论上下文）；已有 CR 时不重复创建 | P0 |
| FR-7 | **ChatInput draftAdapter 解耦（方案 A）**：`ChatInput` 新增可选 prop `draftAdapter?: ChatInputDraftAdapter`（`draftKey`/`editorKey`/`draft`/`attachments` + `setDraft`/`setAttachments`/`addAttachment`/`clearDraft`）；未传时落回默认实现（读 `useChatStore` 派生 `draftKey`，`/chat` 页与浮窗零改动）；传入时组件全部草稿/附件读写走 adapter，不触碰 `useChatStore`；新增单测双重锁定（静态断言 + 行为断言）"自定义 adapter 时不触碰 `useChatStore`" | P0 |
| FR-8 | **回填 Team Agent 面与 Private Ask 面**：两面以 `draftAdapter` 接入 `ChatInput`（adapter 落 `project-chat-store` 的 `{projectId}:{mode}` 命名空间，`editorKey` 恒定为 mode），替换手写 composer，补齐附件（文件/图片）、@提及仅成员、富文本；停止/取消、模型只读徽标等既有能力语义不变 | P0 |

## 4. 非功能需求

- **NFR-1 DC 权限硬约束**：只读 execenv 与写 Skill 禁用由服务端任务执行环境强制；DC 任务
  执行后审计验证零文件写入；DC 无审批、无 CR 状态操作能力（权威铁律不因新角色出现豁口）。
- **NFR-2 红线单开口**：Discussion 零 Agent 触发红线仅"DC 显式激活"一处豁免；CR-2026-009 的
  AC-3（普通消息 DB 级零队列行）在本 CR 交付后复验仍成立。
- **NFR-3 队列语义零改动**：DC 路由与合并转发均复用既有入队路径；容量守卫、claim 串行化、
  撤回/停止语义不变；不新增执行通路。
- **NFR-4 既有消费方零回归**：`/chat` 页与浮窗走默认 adapter 路径，行为与既有测试零变化；
  `chat-input.test.tsx` 既有用例全绿。
- **NFR-5 双端一致**：web 与 desktop（Electron 共享 `packages/views`）行为一致；mobile 不在 P2 范围。
- **NFR-6 四语文案**：DC 消息、多选态、合并预览、升级 CR 等全部新增 UI 文案提供
  en/ja/ko/zh-Hans，locale parity 测试全绿（`mergedForwardMessage` 族字典键已存在，沿用）。

## 5. 验收标准

- **AC-1**（FR-2，静默边界）Discussion 内发送多条普通消息，含一条正文出现 DC 名字但未 @ 的：
  DC 零响应，`agent_task_queue` 无新增行（DB 级验证，即 CR-2026-009 AC-3 复验）。
- **AC-2**（FR-2/3，激活与可见输出）@提及 DC → DC 激活，协调输出以 Discussion 消息出现在
  消息流，另一浏览器会话的成员实时可见，刷新后可回放；审计验证该任务全程无任何文件写入。
- **AC-3**（FR-1/3，路由）DC 按协调判断路由任务 → Team Agent 面出现对应任务且正常执行，
  Discussion 内留有可见路由说明；共享队列满时激活 DC 得到结构化满队反馈，不静默失败。
- **AC-4**（FR-4/5，合并转发）多选 N 条 Discussion 消息 → 合并预览呈现 triggerMessage +
  chatHistory + 「对话中的 N 条消息」→ 确认后 Team Agent 面出现**一个**任务，其 prompt 上下文
  含 `triggerMessage` + `chatHistory` 汇总结构；中途取消退出多选态无副作用。
- **AC-5**（FR-6，升级 CR）项目无关联 CR 时合并转发触发 `requirement-register` → 走 P0
  Issue→CR 升级链路产生合规 CR 壳，讨论上下文随升级带入；已有 CR 场景不重复创建。
- **AC-6**（FR-7，解耦锁定）`/chat` 页与浮窗既有测试全绿零回归；新增单测证明传入自定义
  adapter 时 `ChatInput` 不读不写 `useChatStore`（静态 + 行为双重断言）。
- **AC-7**（FR-8，回填）Team Agent 面与 Private Ask 面可上传附件、@提及仅成员（Agent/文件树
  不出现在 Private Ask 建议列表）、富文本输入；跨项目、跨模式真机验证不串草稿、不串附件
  （`{projectId}:{mode}` 隔离语义不变）。
- **AC-8**（NFR-5/6，回归）web 与 desktop 行为一致；locale parity 测试全绿；CR-D Discussion
  面、CR-A Team Agent 面既有回归通过。

## 6. 成功指标

- 讨论转执行闭环打通：从"多选讨论 → 一键生成带上下文的 Team Agent 任务（或升级 CR）"全程
  不离开 Discussion 面，「沟通发生在执行发生的地方」从理念变为可演示路径。
- 协调过程可审计：DC 的每次总结/路由都是消息流里的持久记录，"过程即记录"覆盖到人类讨论层。
- 三次踩坑的耦合债一次性偿清：Team Agent 面与 Private Ask 面输入体验与浮窗对齐（技能选择器
  除外），且单测机制性防止第四次踩坑；后续新聊天面接入成本降为"写一个薄 adapter"。

## 7. 范围排除

- **技能选择器**——独立平台缺口（前后端都缺、语义未定案），按技术债文档 §7 另议，
  不随解耦回填；两面输入区本 CR 交付后仍无技能选择器。
- **ChatInput 方案 B**（完全受控组件）——不做；方案 A 已满足新消费方隔离需求。
- **DC 高级协调能力**（周期性自动总结、无 @ 主动介入、跨项目协调）——本 CR 仅 @提及/回复
  激活的被动协调。
- **通用消息回复（reply）线程与逐条转发**——切分文档 §0.4 写死排除（合并转发除外）；
  技术前提 4 的 DC reply-to 若做也仅限 DC 消息，不外溢为通用能力。
- **presenter 控制权**——CR-E（CR-2026-010，并行 CR），本 CR 不依赖不实现；合并转发入队
  沿当下队列权限语义。
- 切分文档 §0.4 其余写死排除项继续有效（双入口、work-viewer、上下文用量、语音、斜杠命令、
  导出 Skill 草稿、恢复检查点、点踩反馈、mobile）。

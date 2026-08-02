# P2 ChatInput 组件与全局 store 解耦 — 技术债务

> 来源：CR-2026-008（P2 三模式聊天 CR-C：D5 Private Ask）实施 TASK-04 时的核实发现。
> SDD §5.1 原计划"直接组合纯 props 的 `ChatMessageList` + `ChatInput` + `TaskStatusPill`"，
> 实测 `ChatMessageList`/`TaskStatusPill` 属实，但 `ChatInput`（`packages/views/chat/components/chat-input.tsx`）
> 内部读写全局单例 `useChatStore`，并非纯 props——这是 SDD 断言的一处证伪（工程纪律 4）。
> 本文把根因、当前受影响范围、解耦方案与后续计划记录下来，防止"临时绕过"变成"没人再提"。
> 日期：2026-08-02。

---

## 0. 一句话结论

`ChatInput` 不是"聊天输入框组件"，是"**全局 1:1 chat 的输入框**"——它的草稿/附件状态硬编码存在
`useChatStore`（浮窗与 `/chat` 页共享的全局单例）里，键由组件内部读该单例的 `activeSessionId`/
`selectedAgentId` 派生。任何新的聊天面（项目内 Private Ask、未来的 Discussion、DC）只要渲染
`<ChatInput>`，无论传不传 props，都会隐式接入这个全局单例，与 CR-2026-006/CR-2026-008 反复强调的
"不得触碰 `useChatStore`"红线冲突。CR-2026-008 的对策是绕开它、手写一个精简 composer，代价是
Private Ask 面本期没有富文本编辑、附件上传、@提及。

---

## 1. 耦合点（逐行核实，`chat-input.tsx`）

| 行 | 代码 | 问题 |
|---|---|---|
| 112–113 | `const activeSessionId = useChatStore((s) => s.activeSessionId); const selectedAgentId = useChatStore((s) => s.selectedAgentId);` | 组件内部直接订阅全局单例，无对应 props 入口 |
| 141 | `const draftKey = activeSessionId ?? newSessionDraftKey(selectedAgentId);` | 草稿存储键完全由上面两个全局字段派生，调用方无法覆盖 |
| 143–150 | `inputDraft`/`draftAttachments` 的读与 `setInputDraft`/`setInputDraftAttachments`/`addInputDraftAttachment`/`clearInputDraft` 四个写操作 | 全部落在 `useChatStore`，按 `draftKey` 存取；没有"传入自定义 store"的接缝 |
| 154 | `const editorKey = selectedAgentId ?? "no-agent";` | 编辑器 React key 也依赖全局 `selectedAgentId`，用于"切换 agent 时强制重挂载编辑器" |
| 197 | `restoreDraftRequest.sessionId !== draftKey` | 取消任务后的"草稿恢复"逻辑同样按 `draftKey` 判定落点 |

`useChatStore` 侧对应定义（`packages/core/chat/store.ts:139–158`）：`activeSessionId`/
`selectedAgentId`/`inputDrafts`/`inputDraftAttachments` 四个字段 + 上述四个写方法，是该 store
的核心职责之一，不是可以轻易抽走的边角状态。

## 2. 现有合法消费方 vs 新增消费方的错配

`grep <ChatInput` 命中且仅命中两处（今天）：

- `packages/views/chat/chat-page.tsx`（`/chat` 全页）
- `packages/views/chat/components/chat-window.tsx`（浮窗）

这两者**本来就应该共享同一个 `activeSessionId`**——浮窗和全页是同一个全局会话的两个视图，
耦合在这里是设计意图，不是缺陷。

问题出现在第三类消费方：CR-2026-006 的 Team Agent 面、CR-2026-008 的 Private Ask 面，
以及未来 CR-D 的 Discussion 面、CR-G 的 DC 面——它们各自有自己的会话概念（按项目、按讨论容器），
根本不该有"全局唯一活跃会话"这回事。`ChatInput` 的内部实现假设"永远只有一个全局会话"，
这个假设对消费方 1/2 成立、对 3/4/5/6 不成立，但组件本身无法区分。

**CR-2026-006 已经踩过一次**：`project-team-agent-chat.tsx` 的 `TeamAgentComposer` 同样没有用
`<ChatInput>`，而是手写了一个 textarea + 发送按钮（见其源码，附件/@提及/富文本一律没有）。
当时的 SDD 没有把这个决策的理由写清楚——本文算是把 CR-A 和 CR-C 两次独立踩坑的根因合并记录。

## 3. 因此被降级/绕过的功能（按面清点）

### 3.1 CR-2026-008 Private Ask 面（`project-private-ask.tsx`）实际交付 vs PRD FR-8 承诺

| PRD FR-8 承诺 | 实际交付 | 降级原因 |
|---|---|---|
| 附件（文件/图片） | ❌ 未交付 | `ChatAddMenu` 的上传结果写入 `useChatStore.inputDraftAttachments[draftKey]`，绕不开耦合 |
| @提及仅成员 | ❌ 未交付 | @提及建议列表本身可以走 props（`contextItems`），但**选中后的内容落地**是 `ContentEditor` 写回 `setInputDraft`，同样落在全局 store |
| 技能选择器 | ❌ 未交付 | **与本次耦合无关**——`ChatAddMenu` 源码注释明写"leaving room for future add-actions (agents, skills, tools)"，即技能选择器在全平台任何聊天面（含 CR-A 的 Team Agent 面）都还没实现，是独立的平台缺口，不是本次降级；详见 §7 |
| 模型选择器 | ✅ 交付（只读徽标） | 与耦合无关，是 SDD-SUG-003 的独立范围决策（个人面不应有权改共享 Agent 配置） |
| 发送/停止（仅停自己） | ✅ 交付 | 手写 composer + 既有 `cancelTaskById` 端点，不依赖 `ChatInput` |
| 富文本（markdown/列表等） | ❌ 未交付（纯 textarea） | `ContentEditor`（Tiptap）本身不耦合 store，但 `ChatInput` 把它与 store 焊在一起使用；单独抽 `ContentEditor` 出来是可行的（见 §5），本次未做 |

### 3.2 CR-2026-006 Team Agent 面（`project-team-agent-chat.tsx`，已交付版本）同样缺失

- 附件、@提及、富文本——与 Private Ask 面缺失原因相同（`TeamAgentComposer` 同样绕开了 `ChatInput`）。
- 这部分未在 CR-A 的 PRD/SDD 里被记录为"因耦合降级"，本文补记，避免后续误判为"CR-A 就是故意
  只做纯文本"。

### 3.3 未受影响的能力

- 消息渲染（`ChatMessageList`）、工具执行卡（`TimelineView`）、生成状态（`TaskStatusPill`）——
  三者均已核实为纯 props，Private Ask 与 Team Agent 两面均正常复用，不在本文债务范围内。
- 停止/取消（`cancelTaskById`）——服务端 creator-only 端点，前端调用不经过 `useChatStore`。

---

## 4. 解耦方案（技术方案，供后续 CR 参考）

目标：`ChatInput` 的草稿/附件状态来源可替换，缺省行为对现有两个消费方（`/chat` 页、浮窗）
零改变，新消费方（项目内各聊天面）可以传入自己的存储实现。

### 4.1 方案 A（推荐）：抽出一个 draft-store adapter 接口，注入替代默认实现

```ts
// 新增，packages/views/chat/components/chat-input.tsx
interface ChatInputDraftAdapter {
  draftKey: string;                                   // 调用方决定这个键怎么算
  editorKey: string;                                   // 同上，替代 selectedAgentId 派生
  draft: string;
  attachments: Attachment[];
  setDraft: (draft: string) => void;
  setAttachments: (attachments: Attachment[]) => void;
  addAttachment: (attachment: Attachment) => void;
  clearDraft: () => void;
}
```

- `ChatInput` 新增可选 prop `draftAdapter?: ChatInputDraftAdapter`。
- 未传时，组件内部落回今天的实现（读 `useChatStore` 的 `activeSessionId`/`selectedAgentId` 派生
  `draftKey`）——`/chat` 页与浮窗零改动。
- 传入时，组件完全按 adapter 提供的值渲染/回写，不再触碰 `useChatStore`。
- 项目内各聊天面各自写一个薄 adapter，接到 `project-chat-store`（CR-A 已建，Private Ask 面
  已在用它存纯文本草稿）的 `{projectId}:{mode}` 命名空间上，草稿隔离语义不变。

**代价**：`ChatInput` 内部的 `useEffect`（`restoreDraftRequest` 处理、focus 管理）需要跟着从
"直接读 store" 改成"读 adapter 提供的字段"，改动集中在 40 行区间（111–220），不动渲染 JSX。

### 4.2 方案 B（更彻底，量级更大）：`ChatInput` 变成完全受控组件

`content`/`attachments` 全部由父组件通过 props 传入 + `onChange` 回调，`ChatInput` 自身不持有
任何草稿状态。`/chat` 页与浮窗需要各自包一层适配去读写 `useChatStore`（工作量从"组件内部改"
转移到"两个消费方各包一层"）。更符合"纯 props"的原始设计意图，但改动面更大（两个既有消费方
都要动），风险高于方案 A。

### 4.3 建议

方案 A：改动集中在 `ChatInput` 一个文件，两个既有消费方零风险，新消费方按需接入。
`editorKey` 的"切 agent 强制重挂载编辑器"语义在 adapter 模式下由调用方自己决定（项目内聊天面
没有"切换 agent"这个操作，`editorKey` 可以恒定为 `mode`）。

---

## 5. 影响面与工作量估算

- **`chat-input.tsx` 本体改造**：抽 adapter 接口 + 落回默认实现，约 0.5–1 人日（含既有单测
  `chat-input.test.tsx` 回归 + 新增 adapter 分支单测）。
- **`/chat` 页、浮窗**：零改动（默认行为路径）。
- **回填 Private Ask 面**：接 adapter 后补附件/@提及，约 0.5 人日（`ChatMessageList`/composer
  结构已就位，只是换输入组件）。
- **回填 Team Agent 面**（CR-A 的技术债，随本次一起偿还性价比最高）：同上，约 0.5 人日。
- **技能选择器**：不在本次范围——它是独立平台缺口（§3.1），需要先有一个技能选择 UI 组件本身
  （目前不存在于任何聊天面），解耦完成后才谈得上"复用到哪些面"。

合计约 1.5–2 人日，纯前端，不涉及后端/数据库改动。

---

## 6. 后续计划

- 本文先作为记录留档，不单独立项。**触发立项的时机**：CR-D（Discussion）或 CR-G（DC）任一个
  开始设计阶段——两者同样需要项目/讨论范围的独立会话，会第三次撞上同样的耦合，那时候"三次不同
  CR 独立绕过同一个坑"应该收敛为一次性解决。
- 立项时的验收标准建议：
  1. `/chat` 页、浮窗行为零回归（既有测试全绿，不加新失败）。
  2. Private Ask 面、Team Agent 面补齐附件 + @提及仅成员，真机验证不串草稿、不串附件。
  3. 新增 `chat-input.test.tsx` 覆盖"传入自定义 adapter 时不触碰 `useChatStore`"（静态断言 +
     行为断言双重锁定，防止未来重新引入耦合）。
- 在此之前，Team Agent 面与 Private Ask 面维持现状（纯文本 + 手写 composer），不建议在解耦
  完成前给单个面"打补丁式"接入 `ChatAddMenu`——那样会在 `ChatInput` 之外再长出第二套耦合。

---

## 7. 技能选择器 — 独立缺失项（与本文主题无关，一并记录待补齐）

> 本节是 §3.1 表格"技能选择器"行的展开。与 `ChatInput`/`useChatStore` 耦合**无关**——这是
> 输入区一个从未被任何聊天面实现过的能力，借本文机会一并记录，避免散落在多个 CR 里各提一次。

### 7.1 现状核实结论

- 全平台**任何**聊天面（浮窗、`/chat` 页、CR-A 的 Team Agent 面、本次的 Private Ask 面）
  均无技能选择器；`ChatAddMenu`（输入区左下角"+"菜单，`chat-add-menu.tsx`）目前只有文件上传
  一项，组件注释原文"leaving room for future add-actions (**agents, skills, tools**)"——
  预留了挂点，但从未实现。
- 后端同样没有"本条消息narrow到指定技能子集"的机制：`execenv.TaskContextForEnv.AgentSkills`
  是 Agent 的**全部已配置技能**，无条件物化进每个任务的 brief（`context.go:167/671/695/734`），
  不存在按消息选择技能子集的输入通路。这是前后端都缺、不是纯前端活。

### 7.2 设计依据薄弱，语义未定案

《P2 三模式聊天交互设计》§6 输入区能力表仅一行："技能选择器 | Team Agent ✓ | Private Ask ✓ |
Discussion ✗ | 字典锚点 `chatHeader.tooltipSkills`"，没有交互细节。且字典锚点命名本身有歧义：
`chatHeader` 是窗口头部的"[技能]"按钮（§1 窗口骨架，打开右侧抽屉），与本表所在的"输入区"是
两个不同位置——这是从 CodeBanana 字典借用锚点时产生的命名巧合还是本就该是同一入口，交互设计
文档没有说清楚。**动工前需要产品先定一件事**：技能选择器选的是什么、选完发生什么？至少两种
候选语义，二选一或都不选：

1. **窄化本条消息的技能上下文**（推荐，最小可用）：从该消息发起的这一个任务，只把选中的技能
   物化进 brief，而不是 Agent 全部已配置技能——用于"这条消息我要你严格按 X 技能的做法回复"。
2. **技能作为消息附件**（类似 Command 的"高频入口"，参考 §6.1 斜杠命令的路由模式）：选中技能
   即触发该技能定义的固定流程，消息内容作为该流程的输入参数——语义更接近"调用"而非"提示"，
   与 Command 资源类型重叠，需要先厘清 Skill vs Command 的边界（§6.1 已有"Skill=稳定做法、
   Command=高频入口"的四分类框架，可直接套用来判断技能选择器该落在哪一类）。

窗口头部"[技能]"抽屉入口本身也还是占位（CR-2026-006 PRD §7："chatHeader 右侧抽屉本 CR 只留
入口占位……其余不实现"），是另一个待补齐点，但那是"查看/管理项目技能库"的入口，语义上更接近
既有的 Agent 详情页技能配置（见 §7.3），与输入区内联选择器是两回事，产品阶段应一并定义两者
关系（是否为同一份 UI 在两处复用）。

### 7.3 可复用的既有构件

- **`SkillPickerList`**（`packages/views/agents/components/skill-picker-list.tsx`）+
  **`skillListOptions`**（`packages/core/workspace/queries.ts`）：Agent 详情页"配置这个 Agent
  长期具备哪些技能"用的搜索+列表 UI，已有查询与渲染，适合直接复用为选择器的列表部分（语义
  不同——那是"永久配置"，这里是"本次覆盖/追加"，但 UI 层可共享）。
- **`ChatAddMenu`**：现成的"+"菜单挂点，加一个 `DropdownMenuItem`（同文件已有文件上传项的写法）
  即可挂上入口，不需要新建菜单组件。
- **builtin skill 的 4 个资产元数据字段**（P3 §3 已定义：用途/输入/输出/前置要求）：技能选择器
  的列表项摘要文案可直接读这些字段，不需要为选择器另造一套描述格式。

### 7.4 建议补齐范围（按语义分档，产品定案后择一）

**P0 最小档（若选 7.2 方案 1：窄化技能上下文）**：
- 前端：`ChatAddMenu` 加"技能"入口 → 复用 `SkillPickerList` 弹出多选 → 选中项作为本条消息的
  临时状态（不落全局 store，落在调用方自己的 draft/state，与 §4 的 adapter 方案天然兼容）。
- 后端：薄发送端点（Team Agent 的 `POST /api/projects/{id}/chat/messages`、Private Ask 的
  既有 `POST /api/chat/sessions/{id}/messages`）新增可选 `skill_ids` 参数，入队时覆盖
  `TaskContextForEnv.AgentSkills`（而非并入 Agent 全部技能——"窄化"是本档的核心语义）。
- 量级粗估：前端 1 人日（含 adapter 兼容）+ 后端 1 人日（两端点各一处参数改动 + execenv 覆盖
  逻辑），共约 2 人日。

**P1 完整档（若选 7.2 方案 2：技能即调用）**：涉及 Skill vs Command 边界厘清、可能新增执行
通路——量级需重新评估，不在本文预估范围内，产品定案后另立 SDD。

### 7.5 明确排除

- Discussion 面不做（交互设计表已写 ✗，无 Agent 驱动语境下选技能无意义）。
- 窗口头部"[技能]"抽屉入口的完整实现（技能库浏览/项目级技能管理）不随本项一起做，沿
  CR-2026-006 PRD §7 的占位现状，另有归宿（P3 Skill Market 前端落地时顺带）。

### 7.6 归宿建议

不单独立项。触发时机：CR-D（Discussion，虽然本身不做技能选择器，但会重新审视输入区能力矩阵）
或 P3 Skill Market 前端开工时——两者任一开始设计阶段，都应该把 7.2 的语义问题带去一并定案，
避免第三次"表格里写着但从没人问过到底是什么意思"。

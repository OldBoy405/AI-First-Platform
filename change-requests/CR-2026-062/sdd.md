---
id: CR-2026-062-sdd
type: SDD
cr-ref: CR-2026-062
title: Team Agent 和 Private Ask 发送框 UI 优化 技术设计
target-version: 0.35
status: draft
created: 2026-09-09T16:41:00+08:00
updated: 2026-09-09T16:41:00+08:00
---

# 1. 架构概览

## 1.1 目标与边界

将 Team Agent（`project-team-agent-chat.tsx`）与 Private Ask（`project-private-ask.tsx`）项目聊天发送框的布局与视觉语言对齐普通非项目聊天（`chat-input.tsx` 的 `ChatInput`/`ChatInputCore` + `chat-column.ts`），不改任何业务语义。

**改动面**（代码实施全部落在 multica 仓 `packages/views/`；本 CR 不新增/不修改 server、API、迁移、数据模型、store）：

| 文件 | 改动性质 | 内容 |
|---|---|---|
| `packages/views/chat/components/chat-input.tsx` | 修改（`ChatInputCore` 仅） | wrapper 采用 `CHAT_GUTTER`；surface 采用 `CHAT_COLUMN` + 与 `ChatInput` 一致的 chrome；底部工具栏由 absolute 改为 flow 布局（见 §4） |
| `packages/views/chat/components/chat-column.ts` | 只读复用 | 不修改，复用 `CHAT_GUTTER`/`CHAT_COLUMN` |
| `packages/views/projects/components/project-team-agent-chat.tsx` | 修改 | composer wrapper 对齐；横幅区（pending-message/presenter/queue-full）迁入 gutter 对齐块；`*-model-row` 独立行移除，Model/Thinking 控件经 `leftAdornment` 进底部工具栏；消息流 `TeamAgentStreamView` 根容器改用 `CHAT_GUTTER`+`CHAT_COLUMN` |
| `packages/views/projects/components/project-private-ask.tsx` | 修改 | composer wrapper 对齐；`private-ask-model-row` 移除，控件经 `leftAdornment` 进底部工具栏 |
| `packages/views/projects/components/project-chat-panel.tsx` | 修改（一行类名） | `ModePane` 根加 `@container`（容器感知 gutter 的前提，见 §4.1） |
| `packages/views/projects/components/project-queue-bar.tsx` | 修改（最小） | `px-4` → `CHAT_GUTTER`，内部内容包 `CHAT_COLUMN`，与消息列/发送框边缘对齐 |
| `packages/views/projects/components/project-chat-composer-layout-diff.md` | 新增 | 差异说明文档（完成标志交付物，见 §5.6/SDD-CLOSE-04） |
| 组件测试与 e2e | 修改/新增 | 见 §6.9 与 AC 映射 |

**不动**：`ChatInput`（全局 composer）渲染结构与 props 签名、`SubmitButton`、`ChatAddMenu`、`ModelPicker`/`ThinkingPicker` 组件本体、draft adapter 接口、`useProjectChatStore`、`PATCH /chat/config` 端点、server 全部代码。

## 1.2 依赖图

```text
project-chat-panel.tsx (ModePane, 加 @container)
  ├─ project-team-agent-chat.tsx  TeamAgentStreamView  ──┐
  │   消息流根容器: CHAT_GUTTER + CHAT_COLUMN（原 max-w-3xl/px-4）│
  ├─ project-queue-bar.tsx  CHAT_GUTTER 对齐              │
  ├─ project-team-agent-chat.tsx  TeamAgentComposer ──────┤
  │   ChatInputCore(leftAdornment=Model/Thinking 工具栏)  │
  └─ project-private-ask.tsx  PrivateAskComposer ─────────┤
      ChatInputCore(leftAdornment=Model/Thinking 工具栏)  │
                                                          ▼
chat-input.tsx ChatInputCore ── 复用 ──> chat-column.ts (CHAT_GUTTER / CHAT_COLUMN)
     │ 底层复用（不改）
     ├─ packages/ui submit-button / chat-add-menu
     ├─ packages/views/agents/.../model-picker / thinking-picker（chip variant）
     └─ packages/views/editor（ContentEditor：附件预览/上传态/内部滚动）
```

依赖方向保持 `views -> core + ui` 不变（multica ARCHITECTURE.md §4）；`chat-column.ts` 常量是唯一对齐事实源，本 CR 不复制第二份常量（PRD FR-1）。

## 1.3 关键流程（一屏）

```text
渲染：ModePane(@container) → 消息流/队列栏/composer 各行以 CHAT_GUTTER→CHAT_COLUMN 嵌套
     → 发送框 surface 边缘与消息列边缘对齐
配置：ModelPicker/ThinkingPicker(chip) → 与现状完全相同的 persistModel/persistThinking
     → PATCH /api/projects/:id/chat/config（Team Agent）或
       PATCH /api/chat/sessions/:id/config（Private Ask）→ 不改 Agent 配置
发送：ContentEditor → handleSend（draftAdapter/附件引用/pendingUploads 门禁原样）
     → 宿主 onSend → pending-message 渲染（原样）
```

## 1.4 与 crctl/guard 命令面关系

本 CR 不触及 `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支，也不触及 `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny`，故 Skill 第 8 节「Prompt 采纳影响」按规则省略（不适用）。

# 2. 数据模型

**N/A（本 CR 无数据模型变更）**。理由与边界：

- 不新增/修改 API、数据库字段、任务快照或数据模型（PRD FR-7，来源 FR-33）。
- 会话配置（model/thinking_level）继续存于既有 `project_chat_session`/`chat_session`（CR-2026-056 交付），本 CR 只改渲染层。
- 草稿/附件/项目隔离继续走 `useProjectChatStore`（Zustand，`drafts`/`draftAttachments`），`ChatInputCore` 只认 `ChatInputDraftAdapter` 接口，不接触 `useChatStore`——该结构事实被 `chat-input.test.tsx` 钉住，本 CR 保持。
- 不回滚项、无迁移、无 DDL：Skill「数据/schema 变更与写路径鉴权完整性」条件不触发，故本节无回滚/约束窗口条目。

# 3. 接口契约

**本 CR 不新增、不修改任何 HTTP API / IPC / 事件契约**（PRD 已声明契约确定性四查 N/A）。本节只固化两类既有契约的消费方式，供评审与测试核对。

## 3.1 既有服务端契约（只消费，不改）

| 契约 | 消费点 | 本 CR 行为 |
|---|---|---|
| `PATCH /api/projects/:id/chat/config`（body `{session_id, model?, thinking_level?}`，三态语义；owner/admin 服务端 403 `forbidden_chat_config`） | `packages/core/api/client.ts` `patchProjectChatConfig`（L3722） | Team Agent 工具栏 Model/Thinking 控件继续调用，路径/参数不变 |
| `PATCH /api/chat/sessions/:id/config`（creator-only 服务端 403） | `packages/core/api/client.ts` `patchChatSessionConfig`（L3783） | Private Ask 工具栏控件继续调用，路径/参数不变 |

## 3.2 组件级契约（ChatInputCore）

`ChatInputCoreProps extends ChatInputProps` 的 props 签名**全部保持不变**（含 `leftAdornment?: ReactNode`）。本 CR 只改内部渲染结构与类名。宿主传给 `leftAdornment` 的内容约定如下（TypeScript 片段，落在两个项目组件内）：

```tsx
// TeamAgentComposer（project-team-agent-chat.tsx）——三态分支与既有 testid 全部保留：
const toolbar = agent ? (
  <>
    {!canConfigure ? (
      <span data-testid="project-chat-model-readonly">
        <ModelPicker runtimeId={agent.runtime_id} runtimeOnline={!!runtimeOnline}
          value={chatModel} canEdit={false} onChange={() => {}} />
      </span>
    ) : runtimeReady ? (
      <span data-testid="project-chat-model-picker">
        <ModelPicker runtimeId={agent.runtime_id} runtimeOnline={!!runtimeOnline}
          value={chatModel} canEdit onChange={persistModel} />
      </span>
    ) : (
      <span data-testid="project-chat-model-runtime-guide">
        {t(($) => $.chat.stream.runtime_guide)}
      </span>
    )}
    {thinkingLevels.length > 0 && (
      <span data-testid="project-chat-thinking-picker" className="flex items-center gap-1">
        <ThinkingPicker value={chatThinking} levels={thinkingLevels}
          canEdit={canConfigure} onChange={persistThinking} />
      </span>
    )}
  </>
) : undefined;

// PrivateAskComposer（project-private-ask.tsx）——creator-only 可编辑，testid 保留：
const toolbar = (
  <>
    {agent ? (
      <ModelPicker runtimeId={agent.runtime_id} runtimeOnline={!!runtimeOnline}
        value={model} canEdit onChange={persistModel} />
    ) : null}
    {thinkingLevels.length > 0 && (
      <span data-testid="private-ask-thinking-picker" className="flex items-center gap-1">
        <ThinkingPicker value={thinkingLevel} levels={thinkingLevels} canEdit onChange={persistThinking} />
      </span>
    )}
  </>
);
```

控件使用 `ModelPicker`/`ThinkingPicker` 现有 `chip` variant（默认值），自带 `aria-label`/tooltip（`pickers.model_tooltip`/`pickers.thinking_tooltip`）与 `min-w-0 truncate` 截断；不在工具栏中新增文案 key（NFR-3：继续用既有 `chat.stream.model_label`/`thinking_label`/`runtime_guide` 之外不新增 key；工具栏内不渲染文字 label，语义由 chip 文本 + tooltip 承载——差异文档记录）。

# 4. 关键算法与流程

## 4.1 对齐几何（gutter → column 嵌套，复用唯一常量）

采用 `chat-column.ts` 的嵌套顺序语义（gutter 在 cap 外、按**容器**而非 viewport 缩放）：

```text
CHAT_GUTTER = "px-5 @2xl:px-8 @4xl:px-12"   // 容器感知，@ 变体需 @container 祖先
CHAT_COLUMN = "mx-auto w-full max-w-4xl"     // 居中、封顶、封顶下满宽
```

落地规则：

1. `ChatInputCore` wrapper：`"px-5 pb-3 pt-0"` → `cn(CHAT_GUTTER, "pb-3 pt-0", noAgent && "cursor-not-allowed")`。
2. `ChatInputCore` surface：`"relative mx-auto flex min-h-16 max-h-40 w-full max-w-4xl flex-col rounded-lg bg-card pb-9 border-1 border-border transition-colors focus-within:border-brand"` → `cn(CHAT_COLUMN, "relative flex min-h-16 max-h-40 flex-col rounded-lg border border-surface-border bg-surface transition-[border-color,box-shadow] focus-within:border-brand focus-within:ring-2 focus-within:ring-ring/20", noAgent && "pointer-events-none opacity-60")`，并补 `data-slot="chat-input-surface"`（与 `ChatInput` L651 对齐，供截图/测试共用选择器；`ChatInput` 与其测试均不受影响——两组件从不同时挂载）。
3. Team Agent 消息流根容器：`"mx-auto flex w-full max-w-3xl flex-col gap-4 px-4 py-3"` → `cn(CHAT_GUTTER, CHAT_COLUMN, "flex flex-col gap-4 py-3")`（消息列与发送框边缘对齐，FR-1/AC-1 的几何前提）。
4. `ModePane` 根（project-chat-panel.tsx L199）：`"flex h-full flex-col p-4"` → 加 `@container`。项目面板宽窄由 ResizablePanel 决定，`@container` 使 `@2xl`/`@4xl` 按面板宽度生效（窄面板恒基态 px-5，不依赖 viewport——FR-1/AC-3）。
5. `ProjectQueueBar` 根：`"shrink-0 border-t px-4 py-2"` → 根保持 `shrink-0 border-t`，内部内容包一层 `cn(CHAT_GUTTER, CHAT_COLUMN, "py-2")`（队列栏与消息列/发送框边缘一致；内容与交互零改动）。

## 4.2 底部工具栏（flow 布局，窄屏整体换行）

`ChatInputCore` 底栏由两处 absolute 行（现 L1128/L1137）改为 surface 内的普通流布局行，成为「输入区 → 底栏」两层结构：

```tsx
{/* 编辑器区：在普通聊天 flex-1 min-h-0 overflow-y-auto 基础上，以显式 min-h-8 作为
    底栏换行时的输入区地板（overflow-y-auto 已使 flex 自动最小尺寸为 0，无需同时声明
    min-h-0——两者同为 min-height 工具类，并写会产生样式层叠歧义） */}
<div className="flex-1 min-h-8 overflow-y-auto px-3 py-2">…ContentEditor…</div>
{/* 底栏：左组可换行，右组固定 */}
<div className="flex items-center justify-between gap-2 px-1.5 pb-1.5">
  {(uploadEnabled || leftAdornment) && (
    <div className="flex min-w-0 flex-1 flex-wrap items-center gap-1">
      {uploadEnabled && <ChatAddMenu onSelectFile={(f) => editorRef.current?.uploadFile(f)} />}
      {leftAdornment}
    </div>
  )}
  <div className="flex shrink-0 items-center gap-1">
    <SubmitButton …props 不变… />
  </div>
</div>
```

要点：

- surface 由 `pb-9`（为 absolute 行预留）改为 `pb-0`，底栏自身 `px-1.5 pb-1.5` 提供与普通聊天 absolute 行（`bottom-1.5 left-1.5` = 6px）同等的贴边距离；`max-h-40` 保留（差异文档条目 D-4）。
- 左组 `flex-wrap`：窄屏（360px 浮窗/窄项目面板）时 Model chip、Thinking chip、添加菜单**在底栏内整体换行**，不与输入区重叠、不把发送/停止按钮顶出面板；右组 `shrink-0` 始终在右下角。
- 编辑器 `flex-1 min-h-8 overflow-y-auto` 保证长文本内部滚动（FR-2）；`min-h-8` 地板保证底栏换行最多占满时输入区仍可操作（FR-4「不挤压输入区」的落点解释，见 §4.4 术语硬化）。
- `leftAdornment` 为空且无上传时不渲染左组（现状条件 `uploadEnabled || leftAdornment` 不变）；仅右组时布局与普通聊天一致。
- 换行算法 = CSS flex-wrap 自身，无 JS 测量、无 ResizeObserver、无状态机。

## 4.3 视觉状态映射（不回归，AC-5）

| 状态 | 承载 | 本 CR |
|---|---|---|
| 附件预览/上传中 | `ContentEditor` attachments + `pendingUploads`（chat-input.tsx L870） | 不变 |
| 上传中禁发 | `SubmitButton disabled` 含 `pendingUploads > 0`（L1140）+ `handleSend` 内 `hasActiveUploads()` 门禁 | 不变 |
| 发送中 | `isSubmitting` → `SubmitButton loading` | 不变 |
| 运行中停止 | `isRunning` → `SubmitButton running/onStop`（Team Agent 无 onStop，沿用队列栏取消路径；Private Ask onStop 原样） | 不变 |
| 失败重试 | 宿主 `onSend` 返回 false 保草稿 + toast（原样） | 不变 |
| 空态 | placeholder（原样） | 不变 |

## 4.4 术语硬化（Step 2.5）

| PRD 术语 | 代码别名/落点 | 边界验证 |
|---|---|---|
| 「底部工具栏控件 / leftAdornment 或等价底部工具栏 slot」 | 选定现有 `ChatInputCore.leftAdornment` slot（**不**新建等价 slot/组件）；代码别名 `leftAdornment` | 360px 浮窗 + 长模型 ID：chip `min-w-0 truncate` 截断 + 左组 wrap，验证不横向溢出 |
| 「窄屏换行（不挤压输入区）」 | 解释 = 底栏整体在自身行带内换行、输入区永不与控件重叠；编辑区 `flex-1 min-h-8 overflow-y-auto` 地板 | 底栏两行场景：编辑器仍可聚焦、可滚动、发送按钮不被顶出 |
| 「单一输入 surface」 | = `ChatInputCore` surface 采用与 `ChatInput` 相同的 border/bg/focus/圆角/内部滚动类名集合 | 焦点态：`focus-within:ring-2 ring-ring/20` 与普通聊天一致（组件测试断言） |

无语义冲突需需求负责人澄清，全部在 PRD 授权范围内裁定。

# 5. 技术选型与替代方案

## D-1 复用 chat-column.ts 常量（而非复制/新造常量）

- **Decision**：`ChatInputCore`、Team Agent 消息流、队列栏、两 composer wrapper 全部引用 `CHAT_GUTTER`/`CHAT_COLUMN` 单一事实源。
- **Context**：PRD FR-1 明令「不复制第二份常量」；`chat-column.ts` 文件头注释已说明嵌套顺序语义与容器感知原因。
- **Alternatives**：a) 复制常量到项目组件——PRD 明令禁止且埋下漂移风险；b) 保持 `mx-auto max-w-3xl px-4` 消息列不动、只改 composer——消息列与发送框边缘仍不对齐，AC-1 不过。
- **Consequences**：项目消息列宽度由 max-w-3xl 变 max-w-4xl（对齐普通聊天），属预期视觉变化，记录入差异文档。

## D-2 底栏 flow 布局（而非 absolute + wrap）

- **Decision**：`ChatInputCore` 底栏改为普通流布局（编辑区上方、底栏行下方）。
- **Context**：现有 absolute 行（L1128/L1137）在 360px 面板接入 Model/Thinking chip 后必然与编辑区/右组按钮重叠；FR-3/FR-4 要求「换行不挤压输入区、互不遮挡」。
- **Alternatives**：a) 保持 absolute，左组 `max-w-[calc(100%-3rem)] flex-wrap`——换行后向上长入编辑区（重叠，违反 FR-4）；b) 给 surface 加动态 padding（JS 测量底栏高度）——引入 ResizeObserver 与状态，违反「不引入新状态管理」精神。
- **Consequences**：一行态下与普通聊天视觉等价；`ChatInput`（全局）不动，普通聊天基线零变化（NFR-5）。

## D-3 控件用现有 chip variant 移入 leftAdornment（而非新工具栏组件）

- **Decision**：直接复用 `ModelPicker`/`ThinkingPicker` 默认 `chip` variant，宿主以 `leftAdornment` 传入。
- **Context**：chip variant 自带截断、tooltip、可访问名称、`canEdit=false` 只读形态，正是工具栏所需；PRD NFR-4 不引入新组件。
- **Alternatives**：a) 新建 `ProjectChatConfigToolbar` 组件——两份状态/样式逻辑，负抽象价值（两宿主差异仅在 canEdit 与 testid）；b) 保留 `*-model-row` 独立行——正是本 CR 要消除的第二套视觉体系。
- **Consequences**：Model/Thinking 文字 label（`model_label`/`thinking_label`）不再常驻显示，语义由 chip 文本 + tooltip 承载；写入差异文档。

## D-4 surface 高度封顶保留 max-h-40（不照搬普通聊天 max-h-96）

- **Decision**：`ChatInputCore` surface `max-h-40` 保留，不改为 `max-h-96`/`max-h-[50%]` 体系。
- **Context**：项目面板是短视口（消息流 + 队列栏 + 发送框共处），10rem 封顶是既有可用行为；AC-2 只要求「长文本内部滚动、发送按钮不被顶出」，max-h-40 + `overflow-y-auto` 已满足。
- **Alternatives**：照搬 `max-h-96`——项目面板内发送框可占满大半面板，挤压消息流，体验回退。
- **Consequences**：与普通聊天存在封顶值差异 → 必要差异，记入差异文档。

## D-5 @container 加在 ModePane 根

- **Decision**：`project-chat-panel.tsx` 的 `ModePane` 根 div 加 `@container`。
- **Context**：`@2xl:`/`@4xl:` 变体需要 `@container` 祖先；项目面板宽度由 ResizablePanel（可拖拽、含窄场景）决定。
- **Alternatives**：a) 加在 composer wrapper——只有发送框吃容器变体，消息列/队列栏吃不到，边缘再次错位；b) 不加——@ 变体永不生效，退回恒定 px-5（功能上不坏但丢失容器感知语义，与「复用 chat-column 语义」不符）。
- **Consequences**：Discussion 面板同用 ModePane，无 @ 变体使用方，零影响。

## D-6 差异说明文档落点

- **Decision**：新增 `packages/views/projects/components/project-chat-composer-layout-diff.md`（英文，随 multica 仓提交）。
- **Context**：来源文档把「与普通非项目聊天布局的差异说明，仅记录必要差异」列为主要交付物；就近放代码旁最易在 rebase/评审时被发现。
- **Alternatives**：a) 放 `apps/docs`——面向用户的产品文档站，不适合内部实现注记；b) 放 openwiki——生成物，禁手编。
- **Consequences**：实施期若差异变化，同 PR 内更新该文件。

# 6. FR 到技术实现映射

| FR | 技术实现落点 | 验收入口 |
|---|---|---|
| FR-1 布局对齐 | `chat-input.tsx` ChatInputCore wrapper/surface 改用 `CHAT_GUTTER`/`CHAT_COLUMN`；`project-team-agent-chat.tsx` 消息流根容器与 composer wrapper 对齐；`project-chat-panel.tsx` 加 `@container`；`project-queue-bar.tsx` 对齐 | AC-1 |
| FR-2 单一输入 surface | ChatInputCore surface 类名集合 = ChatInput surface（border-surface-border/bg-surface/rounded-lg/focus-within ring/内部滚动）；分层结构 §4.2 | AC-2 |
| FR-3 控件入底部工具栏 | 两宿主构造 `leftAdornment`（§3.2），`persistModel`/`persistThinking` 原样；Team Agent 三态（可编辑/只读徽标/runtime guide）原样；Private Ask creator-only 原样 | AC-4 |
| FR-4 窄屏不溢出不遮挡 | §4.2 flow 布局 + wrap + `min-h-8` 地板；e2e 360px 回归 | AC-3 |
| FR-5 视觉状态一致 | §4.3 状态映射表逐项不变；`SubmitButton` 复用 | AC-5 |
| FR-6 可访问性保持 | chip variant 自带 aria-label/tooltip；SubmitButton aria 不变；键盘发送 Mod+Enter 由 ContentEditor `onSubmit` 原样承载 | AC-7 |
| FR-7 不新增数据与业务语义 | 改动清单仅渲染层（§1.1）；`zero_diff` 清单（§9） | AC-6/AC-8 |
| FR-8 共享组件适配与测试 | Web/Desktop 共享 `packages/views`；组件测试 + Playwright（§6.9）；差异文档（§5.6） | AC-7/AC-8 |

## AC 逐项设计与验收映射（Step 2.6）

- **AC-1** 设计落点：ChatInputCore wrapper/surface + Team Agent 消息流根 + 队列栏 + ModePane `@container`。可观测结果：组件测试断言两 composer surface 的 class 集合与 `ChatInput` surface 一致且 wrapper 含 `CHAT_GUTTER`、消息流根含 `CHAT_GUTTER`+`CHAT_COLUMN`；Playwright 宽面板截图发送框边缘与消息列边缘对齐。可达性：所有路径均为无状态静态类名，无查询/权限前置，挂载即成立。
- **AC-2** 设计落点：ChatInputCore surface 类名集合（§4.1-2）。可观测结果：组件测试对 surface 断言 `border-surface-border bg-surface rounded-lg focus-within:ring-2` 等 token；长文本注入后编辑器区 `overflow-y-auto` 生效、发送按钮仍在视口内。可达性：与 draft 内容长度解耦，测试直接驱动。
- **AC-3** 设计落点：§4.2 底栏 flow 布局 + `ModePane @container`。可观测结果：Playwright 在 360px 视口打开项目聊天面板，断言无横向溢出（`scrollWidth <= clientWidth`）且输入区/附件预览/配置控件/发送停止按钮无重叠（boundingBox 检查 + 截图基线）。可达性：面板宽度由 e2e 固定 viewport 决定，不依赖数据。
- **AC-4** 设计落点：两宿主 `leftAdornment` 内容（§3.2），`persistModel`/`persistThinking` 与 `patchProjectChatConfig`/`patchChatSessionConfig` 调用路径不变。可观测结果：组件测试沿用既有 `project-chat-model-picker`/`project-chat-model-readonly`/`project-chat-model-runtime-guide`/`project-chat-thinking-picker`/`private-ask-thinking-picker` testid 断言三态与渲染；mock api 断言 PATCH URL/body 与现状一致且无 `updateAgent` 调用。可达性：三态由 `canConfigure`/`runtimeReady` 分支决定，既有测试已覆盖全部三态路径。
- **AC-5** 设计落点：§4.3 映射表（`pendingUploads`/`isSubmitting`/`isRunning` 门禁原样）。可观测结果：既有 chat-input/项目聊天测试全绿；新增 ChatInputCore 底栏布局下 send/stop/upload 状态断言。可达性：状态由既有的 hooks/state 驱动，布局改动不参与状态机。
- **AC-6** 设计落点：`ChatInputCore` 仍只依赖 `draftAdapter`（接口不变）；两宿主 `useTeamAgentDraftAdapter`/`usePrivateAskDraftAdapter` 不变；pending-message 渲染迁入 gutter 对齐块但 testid/渲染条件不变。可观测结果：`chat-input.test.tsx` adapter isolation 套件全绿（`useChatStore` 零订阅）；项目组件测试断言 `project-chat-pending-message`/`private-ask-pending-message` 仍按原条件渲染。可达性：结构性事实，无前置过滤。
- **AC-7** 设计落点：chip variant（aria-label/tooltip 内建）+ SubmitButton aria 不变 + Mod+Enter 不变。可观测结果：组件测试/可访问性断言（role/name/tooltip）；Playwright 键盘发送 + 运行中停止。可达性：不依赖平台（Web/Desktop 共享同一组件）。
- **AC-8** 设计落点：§1.1 改动清单闭合性。可观测结果：实施 diff 范围审查（`git diff --name-only` 白名单核对，无 `server/`、无 `server/migrations/`）；普通聊天截图基线对比（`ChatInput` 路径零 diff）；差异文档存在且每条有理由。可达性：范围由提交内容静态可查。

## 组件测试与 Playwright 计划（FR-8 细化）

1. `packages/views/chat/components/chat-input.test.tsx`：ChatInputCore 套件新增——wrapper/surface 类名断言（CHAT_GUTTER/CHAT_COLUMN/surface token）、底栏流布局结构、`leftAdornment` 渲染于左组、`data-slot="chat-input-surface"`。
2. `packages/views/projects/components/project-team-agent-chat.test.tsx` / `project-private-ask.test.tsx`：断言模型/思考控件 testid 现在位于 composer 区域内（`project-chat-composer`/`private-ask-composer` 子树）；既有三态与 PATCH 断言保持。
3. e2e 新增 `e2e/project-chat-composer.spec.ts`（或并入既有 spec）：宽面板截图（发送框 vs 消息列边缘对齐、与普通聊天 surface 视觉一致）；窄面板 360px 回归（AC-3）。
4. 差异文档：`packages/views/projects/components/project-chat-composer-layout-diff.md`。

# 7. 安全与性能考量

- **权限**：Model/Thinking 控件的可编辑性完全沿用现状分支（Team Agent `canConfigure` owner/admin；Private Ask creator-only），服务端 403 强制（CR-2026-056）不变；只读徽标/runtime guide 形态保留。布局改动不新增任何可写路径。
- **数据**：不新增请求——控件数据源沿用 `runtimeModelsOptions`、`projectChatOptions`、`projectPrivateChatOptions` 等既有 query；底栏换行纯 CSS，无测量/无新 state。
- **可访问性**：chip 控件自带 aria-label 与 tooltip；`SubmitButton` 的 `aria-label`/`stopAriaLabel` 不变；`aria-disabled`（noAgent）不变；焦点可见性（focus-within ring）与普通聊天一致（增强）。
- **边界**：窄面板 360px、长模型 ID（truncate）、thinkingLevels 为空（不渲染 thinking 控件）、agent 为 null（不渲染工具栏）、noAgent 置灰——逐一在 §4 设计中覆盖。
- **失败模式**：CSS 类名改动最坏结果为视觉回退，无数据/事务风险；无需回滚方案（无迁移）。

# 9. 批准范围（契约）

- **scope_in**（本 CR 必须交付）：
  - FR-1~FR-8 全部实现条目（§6 映射表），验收 AC-1~AC-8。
  - 改动文件白名单：§1.1 表列文件 + 上表测试文件 + `e2e/project-chat-composer.spec.ts` + `packages/views/projects/components/project-chat-composer-layout-diff.md`。
- **scope_out**（明确排除）：server 任何代码；任何 API 变更；`server/migrations/`；任务快照逻辑；数据模型；`ChatInput`（全局）视觉基线与业务语义；`useProjectChatStore` 结构；Discussion UI；mobile；新 UI 组件库/新状态管理；`ModelPicker`/`ThinkingPicker`/`SubmitButton`/`ChatAddMenu` 组件本体；draft adapter 接口。
- **zero_diff**（不得改动）：`chat-input.tsx` 中 `ChatInput`（全局）函数体与 `ChatInputProps` 签名；`ChatInputCore` props 签名；`ChatInputDraftAdapter` 接口；`packages/core/api/client.ts` 全部；`useProjectChatStore` 与其 adapter hook 的读写语义；`ContentEditor` 及 editor 包；`PATCH` 端点与三态 body 语义；`project-team-agent-chat.tsx` 中 `handleSend`/`handleComposerUpload`/`persistModel`/`persistThinking` 函数体与既有 testid（`project-chat-*`/`private-ask-*` 系列）；locale 文件（无新 key）。
- **follow_up**（留给后续 CR）：Discussion 面板视觉对齐（CR 顺序边界明令不混入）；mobile 端；`ChatInputCore` 与 `ChatInput` 两套 composer 实现的结构性合并去重（本 CR 只做视觉对齐，不做大重构）。

# 既有实现依赖与事实

基线：multica worktree `117fc6be657f91d43df5892b52782a18329c7aed`（requirement/CR-2026-062 分支，已含 CR-A/CR-B/CR-C 合入产物）。以下全部在该 SHA 实读核实：

1. repo: multica
   relative path: packages/views/chat/components/chat-column.ts
   stable symbol/对象: `CHAT_GUTTER`（L27）、`CHAT_COLUMN`（L30）及文件头「gutter scales with the CONTAINER, never the viewport」语义注释
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: 本 CR 对齐的唯一几何事实源；@ 变体需要宿主标记 `@container`。

2. repo: multica
   relative path: packages/views/chat/components/chat-input.tsx
   stable symbol/对象: `ChatInput`（全局）wrapper `cn(..., CHAT_GUTTER, ...)`（L638）、surface `data-slot="chat-input-surface"`（L651）+ `CHAT_COLUMN` + `border-surface-border bg-surface ... focus-within:ring-2`（L659-660）、底栏 absolute 行（L738/L753）
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: 视觉对齐基准；本 CR 不修改此函数。

3. repo: multica
   relative path: packages/views/chat/components/chat-input.tsx
   stable symbol/对象: `ChatInputCore` wrapper `"px-5 pb-3 pt-0"`（L1066）、surface `"relative mx-auto flex min-h-16 max-h-40 ... bg-card pb-9 border-1 border-border ..."`（L1077）、编辑器 `flex-1 min-h-0 overflow-y-auto px-3 py-2`（L1088）、底栏 absolute 行（L1128/L1137）、`leftAdornment?: ReactNode`（ChatInputProps L123）、`pendingUploads`（L870）、`SubmitButton disabled` 含 `pendingUploads > 0`（L1140）、「never touches useChatStore」注释（L856）
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: 本 CR 改造对象；props 签名与 draft 隔离事实保持。

4. repo: multica
   relative path: packages/views/projects/components/project-team-agent-chat.tsx
   stable symbol/对象: `TeamAgentStreamView` 根 `"mx-auto flex w-full max-w-3xl flex-col gap-4 px-4 py-3"`（L313）；`TeamAgentComposer` wrapper `"shrink-0 border-t px-4 py-3"`（L864）、`data-testid="project-chat-model-row"` 独立行（L916，含 `project-chat-model-readonly` L925 / `project-chat-model-picker` L935 / `project-chat-model-runtime-guide` L945 / `project-chat-thinking-picker` L951）、`ChatInputCore` 使用点（L968）；`persistModel`（L733）/`persistThinking`（L746）调用 `patchProjectChatConfig`；L686-692 注释「api.updateAgent 不得从聊天路径调用」
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: Team Agent 侧改造对象；三态分支、testid、PATCH 路径全部保留。

5. repo: multica
   relative path: packages/views/projects/components/project-private-ask.tsx
   stable symbol/对象: `PrivateAskComposer` wrapper `"shrink-0 border-t px-4 py-3"`（L392）、`data-testid="private-ask-model-row"`（L405）与 `private-ask-thinking-picker`（L420）、`ChatInputCore` 使用点（L436，disabled=running/isRunning/onStop）；`persistModel`（L327）/`persistThinking`（L340）调用 `patchChatSessionConfig`
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: Private Ask 侧改造对象；creator-only 语义不变。

6. repo: multica
   relative path: packages/views/chat/components/chat-message-list.tsx
   stable symbol/对象: 已使用 `CHAT_GUTTER`（L319）/`CHAT_COLUMN`（L325、L373、L406）的既有消息列表
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: Private Ask 消息列已对齐（证明 chat-column 常量可安全用于项目面板）；Team Agent 自绘流容器需对齐。

7. repo: multica
   relative path: packages/views/projects/components/project-chat-panel.tsx
   stable symbol/对象: `ModePane` 根 `"flex h-full flex-col p-4"`（L199），承载 Team Agent/Private Ask/Discussion 三面板
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: `@container` 的放置点；对 Discussion 零影响。

8. repo: multica
   relative path: packages/views/projects/components/project-queue-bar.tsx
   stable symbol/对象: 根 `"shrink-0 border-t px-4 py-2"`（L61），位于消息流与 composer 之间
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: 队列栏边缘参与「消息列↔发送框对齐」链，需最小对齐。

9. repo: multica
   relative path: packages/core/api/client.ts
   stable symbol/对象: `patchProjectChatConfig`（L3722，`PATCH /api/projects/:id/chat/config`，session_id 必填、三态 body、owner/admin 403）、`patchChatSessionConfig`（L3783，`PATCH /api/chat/sessions/:id/config`，creator-only 403）
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: 工具栏控件的唯一写路径（本 CR 不改）。

10. repo: multica
    relative path: packages/views/agents/components/inspector/model-picker.tsx / thinking-picker.tsx / chip.ts
    stable symbol/对象: `ModelPicker`/`ThinkingPicker` `variant="chip"`（默认）+ `CHIP_CLASS`（`group flex min-w-0 ... px-1.5 py-0.5 text-caption hover:bg-accent`）；chip 触发按钮自带 `aria-label={triggerTitle}` 与 tooltip；`canEdit=false` 只读 span 形态
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: 工具栏控件复用对象（不新建组件）；可访问名称/tooltip 由组件内建承载。

11. repo: multica
    relative path: packages/ui/components/common/submit-button.tsx
    stable symbol/对象: `SubmitButton` props（loading/busy/running/onStop/tooltip/ariaLabel/stopTooltip/stopAriaLabel）与 send/stop/loading 渲染
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: 右下角发送/停止按钮复用对象（不修改）。

12. repo: multica
    relative path: packages/views/locales/en/projects.json
    stable symbol/对象: `chat.stream.model_label`="Model"、`chat.stream.thinking_label`="Thinking"、`chat.stream.runtime_guide`（en/ja/ko/zh-Hans 四语目录均存在，parity.test.ts 覆盖）
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: 无新增文案 key（NFR-3）；runtime guide 文本继续复用。

# SDD-CLOSE 关闭记录

- **SDD-CLOSE-01** PRD §1.2 规则 3「输入区、附件预览、底部工具栏分层」→ 关闭：§4.2 flow 两层结构 + 编辑器 `overflow-y-auto`；附件预览仍由 ContentEditor 在编辑器区内承载（与普通聊天同构）。判定覆盖数据生产/消费与兼容降级：本项纯渲染分层，无数据生产/存储/传输/schema/降级层，无遗漏层。
- **SDD-CLOSE-02** PRD §1.2 规则 4「leftAdornment 或等价底部工具栏 slot」的机制选定 → 关闭：选定现有 `leftAdornment`（D-3），§3.2 给出两宿主构造契约。
- **SDD-CLOSE-03** PRD §1.2 规则 2/FR-1「复用单一输入 surface、对齐」的落地类名集合 → 关闭：§4.1-2 逐类名给出（border-surface-border/bg-surface/rounded-lg/focus-within ring）。
- **SDD-CLOSE-04** 来源完成标志「差异说明文档」的落点与内容 → 关闭：`packages/views/projects/components/project-chat-composer-layout-diff.md`（D-6）；最小内容大纲：a) 消息列/队列栏/发送框共用 CHAT_GUTTER+CHAT_COLUMN 的说明；b) 底栏 flow 布局与普通聊天 absolute 行的等价性；c) surface `max-h-40`（vs 普通聊天 `max-h-96`）保留理由；d) Model/Thinking 文字 label 不再常驻、chip+tooltip 承载的说明。每项均须给出「是否必要差异 + 理由」。

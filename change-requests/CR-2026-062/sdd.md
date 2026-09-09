---
id: CR-2026-062-sdd
type: SDD
cr-ref: CR-2026-062
title: Team Agent 和 Private Ask 发送框 UI 优化 技术设计
target-version: 0.35
status: draft
created: 2026-09-09T16:41:00+08:00
updated: 2026-09-09T21:59:09+08:00
---

# 1. 架构概览

## 1.1 目标与边界

将 Team Agent（`project-team-agent-chat.tsx`）与 Private Ask（`project-private-ask.tsx`）项目聊天发送框的布局与视觉语言对齐普通非项目聊天（`chat-input.tsx` 的 `ChatInput`/`ChatInputCore` + `chat-column.ts`），不改任何业务语义。

**改动面**（代码实施全部落在 multica 仓 `packages/views/`；治理台账 `multica/CUSTOM.md` 为仓库纪律 #10 强制 sidecar（见表格末行与 §9），不承载产品代码语义；本 CR 不新增/不修改 server、API、迁移、数据模型、store）：

| 文件 | 改动性质 | 内容 |
|---|---|---|
| `packages/views/chat/components/chat-input.tsx` | 修改（`ChatInputCore` 仅） | wrapper（外层）采用 `CHAT_GUTTER`；surface（内层）采用 `CHAT_COLUMN` + 与 `ChatInput` 一致的 chrome；底部工具栏由 absolute 改为 flow 布局（见 §4）；`SubmitButton` 调用补传 `ariaLabel`/`stopAriaLabel`；采纳 `ChatInputProps` 既有 `allowSubmitWhileRunning` 字段（签名不变，见 §3.2/§4.2） |
| `packages/views/chat/components/chat-column.ts` | 只读复用 | 不修改，复用 `CHAT_GUTTER`/`CHAT_COLUMN` |
| `packages/views/projects/components/project-team-agent-chat.tsx` | 修改 | composer wrapper 对齐（横幅区迁入「外层 `CHAT_GUTTER`>内层 `CHAT_COLUMN`」两层块）；`project-chat-model-row` 独立行及其 testid 锚点**一并移除**（§9 移除清单第 2 项，无替换锚点——断言改用内部四个 testid 位于 `project-chat-composer` 子树；内部 testid 随 `leftAdornment` 原样保留，见 §9 testid 保留/移除/替换清单），Model/Thinking 控件经 `leftAdornment` 进底部工具栏（只读值带 sr-only 类别标签）；`TeamAgentStreamView` 根容器改为「外层 `CHAT_GUTTER`>内层 `CHAT_COLUMN`」两层 DOM；新增运行中停止路径（§4.3.1/D-7：`sentTaskId`/`sentIssueId` + 任务时间线（task-runs）与 queue items 双源活动性，覆盖 running） |
| `packages/views/projects/components/project-private-ask.tsx` | 修改 | composer wrapper 对齐（pending-message 迁入「外层 `CHAT_GUTTER`>内层 `CHAT_COLUMN`」两层块）；`private-ask-model-row` 独立行及其 testid 锚点一并移除（§9 移除清单第 1 项，替换锚点为新 `private-ask-model-picker`），控件经 `leftAdornment` 进底部工具栏（带 sr-only 类别标签）；停止路径（`pendingTaskId → api.cancelTaskById`）原样不动 |
| `packages/views/projects/components/project-chat-panel.tsx` | 修改（一行类名） | `ModePane` 根加 `@container`（容器感知 gutter 的前提，见 §4.1） |
| `packages/views/projects/components/project-queue-bar.tsx` | 修改（最小） | 根 `px-4` 移除，内部内容改为「外层 `CHAT_GUTTER`>内层 `CHAT_COLUMN`」两层 DOM，与消息列/发送框边缘对齐（禁止单元素合并，见 §4.1 规则 5） |
| `packages/views/projects/components/project-chat-composer-layout-diff.md` | 新增 | 差异说明文档（完成标志交付物，见 §5.6/SDD-CLOSE-04） |
| `CUSTOM.md`（multica 仓根） | 修改（治理台账） | 按仓库纪律 #10 登记本 CR 新增/修改文件台账（编号顺延、原因含 CR 编号与 TASK）；无产品代码语义（governance sidecar，§9 scope_in 受控条目） |
| 组件测试与 e2e | 修改/新增 | 见 §6.9 与 AC 映射 |

**不动**：`ChatInput`（全局 composer）渲染结构与 props 签名、`ChatInputCore` props 签名、`SubmitButton`、`ChatAddMenu`、`ModelPicker`/`ThinkingPicker` 组件本体、draft adapter 接口、`useProjectChatStore`、`PATCH /chat/config` 端点、server 全部代码。

## 1.2 依赖图

```text
project-chat-panel.tsx (ModePane, 加 @container)
  ├─ project-team-agent-chat.tsx  TeamAgentStreamView ──────────┐
  │   外层 CHAT_GUTTER > 内层 CHAT_COLUMN 两层 DOM（原单元素 max-w-3xl/px-4）│
  ├─ project-queue-bar.tsx  根 border-t > 外层 CHAT_GUTTER > 内层 CHAT_COLUMN │
  ├─ project-team-agent-chat.tsx  TeamAgentComposer ────────────┤
  │   横幅区: 外层 CHAT_GUTTER > 内层 CHAT_COLUMN；                │
  │   ChatInputCore(leftAdornment=Model/Thinking 工具栏,         │
  │                 allowSubmitWhileRunning + onStop 停止路径 §4.3.1,│
  │                 运行态=task-runs 时间线 + queue items 双源)    │
  └─ project-private-ask.tsx  PrivateAskComposer ───────────────┤
      横幅区: 外层 CHAT_GUTTER > 内层 CHAT_COLUMN；                │
      ChatInputCore(leftAdornment=Model/Thinking 工具栏)         │
                                                                 ▼
chat-input.tsx ChatInputCore ── 复用 ──> chat-column.ts (CHAT_GUTTER / CHAT_COLUMN)
     │ 底层复用（不改）
     ├─ packages/ui submit-button / chat-add-menu
     ├─ packages/views/agents/.../model-picker / thinking-picker（chip variant）
     └─ packages/views/editor（ContentEditor：附件预览/上传态/内部滚动）
```

依赖方向保持 `views -> core + ui` 不变（multica ARCHITECTURE.md §4）；`chat-column.ts` 常量是唯一对齐事实源，本 CR 不复制第二份常量（PRD FR-1）。

**嵌套不变量（回修 B-001）**：所有对齐块都必须以**两个 DOM 层**嵌套——外层 `CHAT_GUTTER`、内层 `CHAT_COLUMN`。单元素同时携带两者会把 gutter padding 计入 `max-w-4xl` 封顶计算，重演 `chat-column.ts` 文件头点名的历史错位形态（内容边缘比 composer surface 内缩一个 gutter），故 §4.1 全部落地规则均按两层 DOM 给出。

## 1.3 关键流程（一屏）

```text
渲染：ModePane(@container) → 消息流/队列栏/横幅区/发送框各处均以「外层 CHAT_GUTTER > 内层 CHAT_COLUMN」两层 DOM 嵌套
     → 发送框 surface 边缘与消息列边缘对齐（B-001）
配置：ModelPicker/ThinkingPicker(chip) → 与现状完全相同的 persistModel/persistThinking
     → PATCH /api/projects/:id/chat/config（Team Agent）或
       PATCH /api/chat/sessions/:id/config（Private Ask）→ 不改 Agent 配置
发送：ContentEditor → handleSend（draftAdapter/附件引用/pendingUploads 门禁原样）
     → 宿主 onSend → pending-message 渲染（原样）
停止：Team Agent 运行中（task-runs 时间线含 sentTaskId 且 status∈active，或仍在 queue items
     ——§4.3.1 双源）→ 草稿空/上传中时 SubmitButton 渲染 stop → onStop 取消该 task
     （useCancelProjectQueueTask，TSUG-007 三支语义）；草稿非空时按钮为发送（queue send，
     失败保草稿后即重试按钮，§4.2）；Private Ask → onStop 原样
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
// TeamAgentComposer（project-team-agent-chat.tsx）——三态分支与四个内部 testid 全部保留；
// 锚点口径（B-001 定点回修）：Fragment 根**不**携带 data-testid="project-chat-model-row"——
// 该锚点随独立行一并移除（§9 移除清单第 2 项，无替换锚点），断言以四个内部 testid 位于
// project-chat-composer 子树为准；可见文字 label 不再渲染，类别语义以 sr-only 保留（B-002）：
const toolbar = agent ? (
  <>
    {!canConfigure ? (
      <span data-testid="project-chat-model-readonly">
        <span className="sr-only">{t(($) => $.chat.stream.model_label)}</span>
        <ModelPicker runtimeId={agent.runtime_id} runtimeOnline={!!runtimeOnline}
          value={chatModel} canEdit={false} onChange={() => {}} />
      </span>
    ) : runtimeReady ? (
      <span data-testid="project-chat-model-picker">
        <span className="sr-only">{t(($) => $.chat.stream.model_label)}</span>
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
        <span className="sr-only">{t(($) => $.chat.stream.thinking_label)}</span>
        <ThinkingPicker value={chatThinking} levels={thinkingLevels}
          canEdit={canConfigure} onChange={persistThinking} />
      </span>
    )}
  </>
) : undefined;

// PrivateAskComposer（project-private-ask.tsx）——creator-only 可编辑；
// testid 口径（B-001 定点回修）：private-ask-model-row 已移除，模型控件用新锚点
// private-ask-model-picker（§9 移除清单第 1 项/新增清单）；private-ask-thinking-picker 保留；
// 类别语义同样以 sr-only 保留（B-002）：
const toolbar = (
  <>
    {agent ? (
      <span data-testid="private-ask-model-picker">
        <span className="sr-only">{t(($) => $.chat.stream.model_label)}</span>
        <ModelPicker runtimeId={agent.runtime_id} runtimeOnline={!!runtimeOnline}
          value={model} canEdit onChange={persistModel} />
      </span>
    ) : null}
    {thinkingLevels.length > 0 && (
      <span data-testid="private-ask-thinking-picker" className="flex items-center gap-1">
        <span className="sr-only">{t(($) => $.chat.stream.thinking_label)}</span>
        <ThinkingPicker value={thinkingLevel} levels={thinkingLevels} canEdit onChange={persistThinking} />
      </span>
    )}
  </>
);
```

控件使用 `ModelPicker`/`ThinkingPicker` 现有 `chip` variant（默认值）：可编辑 chip 的触发按钮自带 `aria-label={triggerTitle}`（`pickers.model_tooltip`/`pickers.thinking_tooltip` 文案）与 tooltip；`canEdit=false` 只读 chip 是纯 `<span>`（值文本 + `title`），**没有类别可访问名称**——因此宿主工具栏分支（Team Agent 三态 + Private Ask）全部以 `sr-only` 类别标签（既有 `chat.stream.model_label`/`thinking_label` 文案）包裹，辅助技术读作「模型 <值>」「思考级别 <值>」（B-002 回修）。不在工具栏中新增文案 key（NFR-3）；工具栏内不再常驻渲染可见文字 label（差异文档记录）。

**ChatInputCore 侧两处最小改动（props 签名不变）**（B-002 回修）：

1. `SubmitButton` 调用补传 `ariaLabel={t(($) => $.input.send_tooltip)}`、`stopAriaLabel={t(($) => $.input.stop_tooltip)}`——与 `ChatInput`（全局，L778/L782）完全同 key 同语义，无新文案 key。`submit-button.tsx` 的 ArrowUp/Square 均 `aria-hidden`，不传则图标按钮无可访问名称，AC-7 的 role/name 断言无落点。
2. 采纳 `ChatInputProps` 中既有 `allowSubmitWhileRunning?: boolean` 字段（L102，`ChatInputCore` 此前未解构使用，签名零变化）：发送门禁与按钮 `running` 判定按 `ChatInput` 同款语义（§4.2/§4.3.1）；Team Agent 传 `true`（队列天然支持续发），Private Ask 不传（行为与现状逐位一致）。

# 4. 关键算法与流程

## 4.1 对齐几何（gutter → column 嵌套，复用唯一常量）

采用 `chat-column.ts` 的嵌套顺序语义（gutter 在 cap 外、按**容器**而非 viewport 缩放）：

```text
CHAT_GUTTER = "px-5 @2xl:px-8 @4xl:px-12"   // 容器感知，@ 变体需 @container 祖先
CHAT_COLUMN = "mx-auto w-full max-w-4xl"     // 居中、封顶、封顶下满宽
```

落地规则：

1. `ChatInputCore` wrapper（外层 gutter）：`"px-5 pb-3 pt-0"` → `cn(CHAT_GUTTER, "pb-3 pt-0", noAgent && "cursor-not-allowed")`。
2. `ChatInputCore` surface（内层 column，独立 DOM 节点）：`"relative mx-auto flex min-h-16 max-h-40 w-full max-w-4xl flex-col rounded-lg bg-card pb-9 border-1 border-border transition-colors focus-within:border-brand"` → `cn(CHAT_COLUMN, "relative flex min-h-16 max-h-40 flex-col rounded-lg border border-surface-border bg-surface transition-[border-color,box-shadow] focus-within:border-brand focus-within:ring-2 focus-within:ring-ring/20", noAgent && "pointer-events-none opacity-60")`，并补 `data-slot="chat-input-surface"`（与 `ChatInput` L651 对齐，供截图/测试共用选择器；`ChatInput` 与其测试均不受影响——两组件从不同时挂载）。wrapper 与 surface 本来就是两个 DOM 层，保持分层（B-001）。
3. Team Agent 消息流根容器：`"mx-auto flex w-full max-w-3xl flex-col gap-4 px-4 py-3"` 拆为**两个 DOM 层**（B-001 回修）：

   ```tsx
   <div className={cn(CHAT_GUTTER)}>                               {/* 外层：gutter 在 cap 之外 */}
     <div className={cn(CHAT_COLUMN, "flex flex-col gap-4 py-3")}> {/* 内层：阅读列 */}
       …no-earlier 分隔 + items…
     </div>
   </div>
   ```

   **禁止** `cn(CHAT_GUTTER, CHAT_COLUMN, …)` 单元素合并：gutter padding 会并入 `max-w-4xl` 封顶计算，使内容边缘比 composer surface 内缩一个 gutter（`chat-column.ts` 文件头点名的历史错误形态）；消息列与发送框边缘对齐（FR-1/AC-1）必须靠两层嵌套成立。
4. `ModePane` 根（project-chat-panel.tsx L199）：`"flex h-full flex-col p-4"` → 加 `@container`。项目面板宽窄由 ResizablePanel 决定，`@container` 使 `@2xl`/`@4xl` 按面板宽度生效（窄面板恒基态 px-5，不依赖 viewport——FR-1/AC-3）。
5. `ProjectQueueBar` 根：`"shrink-0 border-t px-4 py-2"` → 根保持 `shrink-0 border-t`，内部改为**两个 DOM 层**（B-001 回修）：

   ```tsx
   <div className="shrink-0 border-t" data-testid="project-queue-bar">
     <div className={cn(CHAT_GUTTER)}>            {/* 外层：gutter */}
       <div className={cn(CHAT_COLUMN, "py-2")}>  {/* 内层：阅读列 */}
         …toggle + expanded list（内容与交互零改动）…
       </div>
     </div>
   </div>
   ```

6. 两 composer 外层（project-team-agent-chat.tsx L864 / project-private-ask.tsx L392）：`"shrink-0 border-t px-4 py-3"` → `"shrink-0 border-t"`；横幅区（pending-message / presenter-required / queue-full / private-ask-pending-message）迁入**两个 DOM 层**块：外层 `cn(CHAT_GUTTER, "pt-3")`、内层 `cn(CHAT_COLUMN)`（无横幅时该块仍渲染，保留 pt-3 顶部间距）；`ChatInputCore` 的 wrapper（gutter + `pb-3`）继续提供底部间距与对齐。横幅右缘与 surface 右缘一致（pending-message `justify-end` 贴 column 右缘）。

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
    <SubmitButton
      onClick={handleSend}
      disabled={isEmpty || isSubmitting || !!disabled || !!noAgent || pendingUploads > 0}
      loading={isSubmitting}
      // 与 ChatInput 同款队列语义（B-003 回修）：allowSubmitWhileRunning 时运行中
      // 仍可发送（Queue Send），仅空输入/上传中回落为 Stop；未传时运行中只显示 Stop。
      // 推论（失败回流可见动作，§4.3.1/AC-5(h)）：发送失败保草稿（isEmpty=false）
      // ⇒ running=false，渲染发送/重试按钮；清空草稿后 stop 重新出现并可取消旧目标。
      running={!!isRunning && (!allowSubmitWhileRunning || isEmpty || pendingUploads > 0)}
      onStop={onStop}
      tooltip={sendShortcut
        ? `${t(($) => $.input.send_tooltip)} · ${formatShortcut(sendShortcut)}`
        : t(($) => $.input.send_tooltip)}
      ariaLabel={t(($) => $.input.send_tooltip)}       {/* B-002：发送可访问名称 */}
      stopTooltip={t(($) => $.input.stop_tooltip)}
      stopAriaLabel={t(($) => $.input.stop_tooltip)}   {/* B-002：停止可访问名称 */}
    />
  </div>
</div>
```

要点：

- surface 由 `pb-9`（为 absolute 行预留）改为 `pb-0`，底栏自身 `px-1.5 pb-1.5` 提供与普通聊天 absolute 行（`bottom-1.5 left-1.5` = 6px）同等的贴边距离；`max-h-40` 保留（差异文档条目 D-4）。
- 发送门禁与按钮状态同步采纳 `allowSubmitWhileRunning`（ChatInputProps 既有字段，`ChatInputCore` 此前未解构使用，本次补上，签名不变）：`handleSend` 门禁的 `isRunning` 项改为 `isRunning && !allowSubmitWhileRunning`；SubmitButton `running` 判定如上片段。Private Ask 不传该字段 → 行为与现状逐位一致；Team Agent 传 `true`（队列天然支持续发，见 D-7）。**可见动作口径（单一事实，§4.3.1/AC-5 以此为准）**：`trackedActive=true` 时，草稿非空且无上传中 → `running=false` → 渲染**发送（queue send；发送失败保草稿后即重试）按钮**；草稿为空或上传中 → `running=true` → 渲染 **stop**。因此失败回流后的可见动作是「保草稿 + 发送（重试）按钮」，**不是 stop**；保留的旧目标在清空草稿后由重新出现的 stop 取消（§4.3.1）。
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
| 运行中停止 | Team Agent：`isRunning`=最近一次发送 task 处于活动生命周期（queued/dispatched 由 queue items、running/waiting_local_directory 由任务时间线判定，§4.3.1 双源）；`onStop`=受权取消该 task（§4.3.1）；Private Ask：`running/pendingTaskId → onStop=api.cancelTaskById` 原样 | §4.3.1 |
| 失败重试 | 宿主 `onSend` 返回 false 保草稿 + toast（原样） | 不变；失败回流后草稿非空且 Team Agent `allowSubmitWhileRunning=true` ⇒ `running=false`，右下角为**发送（重试）按钮**；旧活动目标保留在 sent 状态，**清空草稿后 stop 重新出现**可取消（§4.3.1） |
| 空态 | placeholder（原样） | 不变 |

### 4.3.1 Team Agent composer 运行中停止路径（B-003 回修 v2）

事实（multica@117fc6be）：`TeamAgentComposer` 当前 `isRunning={isPending}`（`useSendProjectChatMessage` 的本地入队窗口）且不传 `onStop`；`SubmitButton` 在 `running=true` 时把右下角按钮 `onClick` 直接绑定 `onStop`——当前渲染的是一个**无处理器的停止按钮**，且入队窗口结束后任务真正运行期间反而没有任何运行态。`ProjectQueueBar` 展开后的取消是另一入口，不能替代 composer 右下角动作。PRD FR-5/AC-5、来源 AC-33 与规则 5「右下角复用普通聊天的发送/停止按钮和 loading、上传中、运行中状态」要求该动作可用；同时规则 8 要求保留运行中停止。因此裁定：**接入可执行停止路径，而不是渲染不可用按钮或以队列栏替代**（「不渲染 stop」无需求授权）。

**B-003 v2 修正（上一轮语义错误）**：`projectQueueItemsOptions` 的 items 由服务端查询 `ListProjectPendingTasks`（server/pkg/db/queries/agent.sql L2947-2961）过滤为**仅 queued + dispatched**——任务进入 `running` 后离开该列表，因此 items 不能单独作为 `running` 的事实源。本设计改用**双源活动性判定**：queue items 覆盖 queued/dispatched 窗口，**容器 Issue 任务时间线**（Team Agent 消息流已读取的 task-runs 列表，`AgentTask.status` 含 `running`/`waiting_local_directory`）覆盖 running 及其后生命周期，两者取并、终态覆盖，闭合 queued→dispatched→running→terminal 全生命周期。零新增 API、零服务端契约变更（zero_diff）。

状态与动作（全部复用既有受权能力，零新增 API/状态管理；两个事实源复用既有 query 缓存，无新增请求）：

| 信号 | 来源 | 语义 |
|---|---|---|
| `sentTaskId` / `sentIssueId` | `useSendProjectChatMessage(...).mutateAsync()` 成功返回值 `ProjectChatSendResult.task_id` / `issue_id`（schemas.ts L1524-1529；组件内单条语句 `useState` 保存）。**确定性转移（cycle 2 回修）**：发送成功且返回 `task_id`/`issue_id` **任一无效（空）** → **原子清空两个 ID**（不留旧目标）；发送**失败**（mutation reject，`handleSend` catch 分支返回 false，setState 未执行）→ **保留**旧值。**失败回流的可见动作（cycle 2 attempt 2 回修）**：保留旧值 ≠ 立即渲染 stop——失败保草稿令 `isEmpty=false`，且 Team Agent 传 `allowSubmitWhileRunning=true`，§4.2 判定式得 `running=false`，右下角渲染**发送（重试）按钮**；用户**清空草稿**后 `isEmpty=true` → `running=true` → stop 重新出现，点击取消该保留的 task（草稿清空前也可经 ProjectQueueBar 既有入口取消） | 本 composer 最近一次成功入队的 task 与其容器 Issue |
| `taskInItems` | `useQuery(projectQueueItemsOptions(wsId, projectId)).data.items` 中是否存在 `task_id === sentTaskId`（items 服务端过滤 queued/dispatched，见依赖 #21；与 ProjectQueueBar 共用同一 query key 缓存，react-query 去重） | queued/dispatched 取消窗口 |
| `taskEntry` | `useQuery({ queryKey: issueKeys.tasks(sentIssueId), queryFn: () => api.listTasksByIssue(sentIssueId), staleTime: 30_000, enabled: !!sentIssueId })`——与 `ProjectTeamAgentChat` 消息流已读取的 task-runs 列表（本文件 L98-102）同一 query key（`["issues","tasks",issueId]`，issues/queries.ts L179）；两者同时启用时收敛为同一缓存，**不产生重复请求** | 该 task 的权威状态（含 running/waiting_local_directory 与终态） |
| `taskActive` | `taskEntry != null && ACTIVE.has(taskEntry.status)`，`ACTIVE = { queued, dispatched, waiting_local_directory, running }`（与 agent.ts L286-298 状态联合及「active vs done」分桶注释一致） | 任务时间线判定的活动态（含真正的 running） |
| `taskTerminal` | `taskEntry != null && TERMINAL.has(taskEntry.status)`，`TERMINAL = { completed, failed, cancelled }` | 任务时间线判定的终态 |
| `trackedActive` | `(taskInItems || taskActive) && !taskTerminal` | 运行态判定：任一源说活动即活动；任务时间线说终态即覆盖陈旧 items 残留 |
| `isRunning`（传 ChatInputCore） | `trackedActive` | 运行态：终态落地后自动回落 false，按钮回发送态 |
| `onStop` | `handleStop`：`cancelTask.mutateAsync(sentTaskId)`（`useCancelProjectQueueTask`，本文件 TaskExecutionCard 已使用） | 取消最近一次发送的 task |
| `allowSubmitWhileRunning`（传 ChatInputCore） | `true` | 运行中仍可续发（队列语义），与现状「入队完成后即可再发」一致（FR-7 不回归） |

生命周期闭合表（B-003 验收口径，测试计划 §6.9 逐行覆盖）：

| 阶段 | queue items（服务端过滤 queued+dispatched） | 任务时间线（`GET /api/issues/:id/task-runs`） | `trackedActive` |
|---|---|---|---|
| queued | ✓ 含 sentTaskId | ✓ status=queued | true（两源均真） |
| dispatched | ✓ 含 sentTaskId | ✓ status=dispatched | true |
| running | ✗（离开 items） | ✓ status=running | true（任务时间线单独支撑） |
| waiting_local_directory | ✗ | ✓ status=waiting_local_directory（active 分桶） | true |
| completed / failed / cancelled | ✗ | ✓ status=terminal | false（`!taskTerminal` 覆盖陈旧 items 残留，不渲染死按钮） |

两个事实源的实时性由既有 WS 失效保障：`task:*` 前缀事件失效 `["issues","tasks"]`（use-realtime-sync.ts L926）与 `projectKeys.queueStatusAll(wsId)`（L902，items 键挂在同一前缀下）——composer 与消息流卡片、队列栏同一次刷新，无需新增订阅或轮询。

竞态与错误语义（沿用 TSUG-007 三支，与 TaskExecutionCard/ProjectQueueBar 完全一致）：

1. `res.status === "cancelled"` → 静默成功（含重复取消的幂等 200）；
2. 其他终态 → `toast.error(chat.stream.cancel_already_finished)`；
3. 抛 `ApiError`（403 等）→ `toast.error(e.message)`。

边界：

- **入队窗口**（mutation in-flight）：`isRunning=false`，ChatInputCore 内部 `isSubmitting` 显示 loading（不再显示无目标的 stop）；响应落地后 `sentTaskId`/`sentIssueId` 按确定性转移更新（有效则写入、任一空则原子清空，见「硬降级」）、任务时间线与 items 经 WS `task:*` 前缀失效刷新，短暂窗口内 `trackedActive` 可能滞后翻 true，可接受（与消息流/队列栏同一实时缓存口径）。
- **首次发送的容器绑定**：面板持有的 `chat.issue_id`（`projectChatOptions` 缓存，全局 staleTime=Infinity 且 send 成功路径不失效，见依赖 #15）可能在首次发送后短暂停留在旧值；composer **不依赖面板 props**，以发送响应自带的 `issue_id`（`ProjectChatSendResultSchema` L1531-1537 为 UUID 必填）键定任务时间线查询——首条消息的 running 覆盖不依赖面板刷新。面板缓存随后收敛为同一 issueId 时，两边 query key 相同、缓存自动去重。无容器（`sentIssueId` 为空：未发送/硬降级已清空）时查询 disabled，活动性回落 items-only（恒 false，因两个 sent ID 均已原子清空）。
- **续发**：`allowSubmitWhileRunning=true` 时，运行中 + 有内容 → 按钮为发送（queue send），空输入/上传中 → stop；再次发送成功后（返回 ID 有效）`sentTaskId`/`sentIssueId` 指向最新 task——**stop 只作用于最近一次**，其余任务仍由队列栏逐条取消；若该次返回空 ID，则按「硬降级」原子清空（无运行态），其余任务仍由队列栏逐条取消（差异文档记录）。
- **硬降级**：send 成功但 `parseWithFallback` 使返回的 `task_id=""` 或 `issue_id=""`（任一无效；成功 body 缺 `session_id`/`issue_id` 会把**整个结果**降级为空 fallback、`task_id` 缺失 default 为空串，schemas.ts L1519-1523/L1531-1537）→ **原子清空 `sentTaskId` 与 `sentIssueId`**（确定性转移：不留上一次的有效目标——否则 stop 会错误取消旧 task）；send **失败**（mutation reject → `handleSend` catch 返回 false 保草稿，成功行 setState 未执行）→ **保留**旧活动目标。**保留 ≠ 渲染 stop**：失败保草稿（`isEmpty=false`）+ `allowSubmitWhileRunning=true` ⇒ §4.2 判定式 `running=false`，右下角为**发送（重试）按钮**；**清空草稿后 stop 重新出现**并可取消该旧目标（AC-5(h)/§6.9(iii) 落点）。清空后 `trackedActive` 恒 false，composer 无运行态（不渲染死按钮）。
- **取消成功回流**：`useCancelProjectQueueTask.onSettled` 失效 `projectKeys.queueStatus` 前缀（含 items）+ WS `task:*` 事件失效任务时间线，`trackedActive` 翻 false、按钮回发送态。
- **权限**：取消权限由服务端 403 强制（originator 或 owner/admin）；本路径只取消本 composer 最近发送的 task（originator 恒为当前用户），不扩大权限面、不新增可写路径。

## 4.4 术语硬化（Step 2.5）

| PRD 术语 | 代码别名/落点 | 边界验证 |
|---|---|---|
| 「底部工具栏控件 / leftAdornment 或等价底部工具栏 slot」 | 选定现有 `ChatInputCore.leftAdornment` slot（**不**新建等价 slot/组件）；代码别名 `leftAdornment` | 360px 浮窗 + 长模型 ID：chip `min-w-0 truncate` 截断 + 左组 wrap，验证不横向溢出 |
| 「窄屏换行（不挤压输入区）」 | 解释 = 底栏整体在自身行带内换行、输入区永不与控件重叠；编辑区 `flex-1 min-h-8 overflow-y-auto` 地板 | 底栏两行场景：编辑器仍可聚焦、可滚动、发送按钮不被顶出 |
| 「运行中停止（Team Agent）」 | 解释 = composer 右下角 stop 作用于最近一次发送且处于活动生命周期的 task（queued/dispatched 由 queue items、running/waiting_local_directory 由任务时间线判定）；代码别名 `sentTaskId`/`sentIssueId`/`taskInItems`/`taskEntry`/`trackedActive`；可见动作（stop vs 发送/重试）由 §4.2 `running` 判定式唯一决定 | 边界验证：task 在任务时间线为终态（completed/failed/cancelled）→ stop 不渲染、按钮回发送态（终态覆盖陈旧 items）；running 且离开 items → 运行态仍真，草稿空/上传中渲染 stop、草稿非空渲染发送（queue send）；发送失败保草稿 → 发送（重试）、清空草稿后 stop 重新出现；重复点击 → 幂等静默（TSUG-007 分支 1） |
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

## D-7 Team Agent 运行中停止路径（B-003 回修 v2）

- **Decision**：`isRunning` 采用**双源活动性判定**——queue items（服务端过滤 queued+dispatched，覆盖排队/派发窗口）∪ 容器 Issue 任务时间线（`issueKeys.tasks(sentIssueId)`，`AgentTask.status` 覆盖 running/waiting_local_directory 与终态），并集后以任务时间线终态覆盖；`onStop` 复用 `useCancelProjectQueueTask` 取消 `sentTaskId`，并传 `allowSubmitWhileRunning=true` 保持运行中可续发；不渲染无处理器的 stop。
- **Context**：上一轮「items 含 sentTaskId ⇒ 排队/派发/运行」不成立——items 只含 queued/dispatched，任务 running 后离开列表、按钮会错误回发送态（B-003 复评指出）。任务时间线是 Team Agent 消息流已读取的既有事实源（同一 query key，缓存收敛去重），且 WS `task:*` 事件同时失效两个源（use-realtime-sync.ts L926/L902），生命周期闭合无需新契约。PRD FR-5/AC-5 与来源 AC-33 要求运行中停止可用；FR-7 要求 send/stop 业务行为不回归（取消端点、权限、TSUG-007 语义均复用现状）。
- **Alternatives**：a) 不渲染 stop、只留队列栏——违反来源规则 5「右下角复用发送/停止按钮和运行中状态」，无需求授权；b) `isRunning` 常 true 并锁发送直到 task 终态——改变现状「入队完成后即可再发」的发送行为，违反 FR-7；c) 给 ChatInputCore 新增独立 stop 槽位解耦——扩大共享组件契约面，超出「最小调整」；d) 修改 queue-items 服务端过滤或新增 API 返回 running——违反本 CR zero_diff（不新增/修改 API、服务端零改动）。
- **Consequences**：stop 只作用于最近一次 task（其余由队列栏逐条管理）；入队窗口短暂无运行态（loading）；running 期间（含离开 items 后）可见动作由 §4.2 判定式决定——草稿空/上传中 → stop，草稿非空 → 发送（queue send）；终态落地后回发送态。发送失败保草稿 → 发送（重试）按钮，清空草稿后 stop 重新出现并可取消保留的旧目标（可见动作与状态保留一致，无第二动作入口）。该语义与生命周期闭合表（§4.3.1）记入差异文档。

# 6. FR 到技术实现映射

| FR | 技术实现落点 | 验收入口 |
|---|---|---|
| FR-1 布局对齐 | `chat-input.tsx` ChatInputCore wrapper（外层 `CHAT_GUTTER`）/surface（内层 `CHAT_COLUMN`）；`project-team-agent-chat.tsx` 消息流根与横幅区、`project-queue-bar.tsx` 均为两层 DOM；`project-chat-panel.tsx` 加 `@container` | AC-1 |
| FR-2 单一输入 surface | ChatInputCore surface 类名集合 = ChatInput surface（border-surface-border/bg-surface/rounded-lg/focus-within ring/内部滚动）；分层结构 §4.2 | AC-2 |
| FR-3 控件入底部工具栏 | 两宿主构造 `leftAdornment`（§3.2），`persistModel`/`persistThinking` 原样；Team Agent 三态（可编辑/只读徽标/runtime guide）原样；Private Ask creator-only 原样 | AC-4 |
| FR-4 窄屏不溢出不遮挡 | §4.2 flow 布局 + wrap + `min-h-8` 地板；e2e 360px 回归 | AC-3 |
| FR-5 视觉状态一致 | §4.3 状态映射表逐项不变；`SubmitButton` 复用；Team Agent 运行中停止路径 §4.3.1（可执行，非死按钮；双源覆盖 queued→dispatched→running 全生命周期） | AC-5 |
| FR-6 可访问性保持 | ChatInputCore 传 `ariaLabel`/`stopAriaLabel`（B-002）；只读/可编辑配置控件带 sr-only 类别标签；chip variant 自带 aria-label/tooltip；键盘发送 Mod+Enter 由 ContentEditor `onSubmit` 原样承载 | AC-7 |
| FR-7 不新增数据与业务语义 | 改动清单仅渲染层（§1.1）；`zero_diff` 清单（§9） | AC-6/AC-8 |
| FR-8 共享组件适配与测试 | Web/Desktop 共享 `packages/views`；组件测试 + Playwright（§6.9）；差异文档（§5.6） | AC-7/AC-8 |

## AC 逐项设计与验收映射（Step 2.6）

- **AC-1** 设计落点：ChatInputCore wrapper/surface 两层 + Team Agent 消息流根两层 + 队列栏两层 + ModePane `@container`。可观测结果：组件测试断言两 composer wrapper（外层）含 `CHAT_GUTTER`、surface（内层）含 `CHAT_COLUMN` 且二者为**不同 DOM 节点**；消息流根为「外层 `CHAT_GUTTER`>内层 `CHAT_COLUMN`」两层；队列栏同两层（§4.1 规则 3/5/6）。Playwright 宽面板截图发送框边缘与消息列边缘对齐（差 < 1px 容差）。可达性：所有路径均为无状态静态类名，无查询/权限前置，挂载即成立。
- **AC-2** 设计落点：ChatInputCore surface 类名集合（§4.1-2）。可观测结果：组件测试对 surface 断言 `border-surface-border bg-surface rounded-lg focus-within:ring-2` 等 token；长文本注入后编辑器区 `overflow-y-auto` 生效、发送按钮仍在视口内。可达性：与 draft 内容长度解耦，测试直接驱动。
- **AC-3** 设计落点：§4.2 底栏 flow 布局 + `ModePane @container`。可观测结果：Playwright **真跑**（非 `--list`，见 §6.9-3 证据契约）在 360px 视口打开项目聊天面板，断言无横向溢出（`scrollWidth <= clientWidth`）且输入区/附件预览/配置控件/发送停止按钮无重叠（boundingBox 检查 + 截图基线）。可达性：面板宽度由 e2e 固定 viewport 决定，不依赖数据。
- **AC-4** 设计落点：两宿主 `leftAdornment` 内容（§3.2），`persistModel`/`persistThinking` 与 `patchProjectChatConfig`/`patchChatSessionConfig` 调用路径不变。可观测结果：组件测试沿用既有 `project-chat-model-picker`/`project-chat-model-readonly`/`project-chat-model-runtime-guide`/`project-chat-thinking-picker`/`private-ask-thinking-picker` testid 断言三态与渲染，并断言 Team Agent 四个控件 testid 位于 `project-chat-composer` 子树（**不再以 `project-chat-model-row` 为定位锚点**——该 testid 随独立行移除，§9 移除清单第 2 项）；Private Ask 模型控件以新 `private-ask-model-picker` testid 定位（`private-ask-model-row` 随行移除，§9 移除清单第 1 项）；mock api 断言 PATCH URL/body 与现状一致且无 `updateAgent` 调用。可达性：三态由 `canConfigure`/`runtimeReady` 分支决定，既有测试已覆盖全部三态路径。
- **AC-5** 设计落点：§4.3 映射表（`pendingUploads`/`isSubmitting`/运行态门禁）+ §4.3.1 Team Agent 停止路径（`sentTaskId`/`sentIssueId`/`taskInItems`/`taskEntry`/`trackedActive`/`handleStop`，双源）。可观测结果：既有 chat-input/项目聊天测试全绿；新增——（a）queued/dispatched 窗口：mock 发送返回 `task_id` 且 mock queue items 含该 task → stop 渲染（发送成功后 `commitInput` 已清空草稿、`isEmpty=true` ⇒ §4.2 判定式 `running=true`）、点击后 `cancelTaskById(task_id)` 被调用；（b）**running**：mock 发送返回 `task_id`+`issue_id`，mock `listTasksByIssue(issue_id)`（task-runs）含该 task 且 `status="running"`、mock items **不含**该 task → stop 仍渲染（发送成功后草稿已清空 ⇒ 满足 §4.2 判定式；证明运行中停止可达，不依赖 items）；（c）终态回流：task-runs 该 task `status="completed"`（items 即使陈旧仍含该 task）→ 按钮回发送态（终态覆盖）；（d）`waiting_local_directory`（同上，草稿已清空）→ stop 渲染；（e）取消返回非 cancelled 终态 → `cancel_already_finished` toast；（f）硬降级：首次发送即返回空 `task_id`/`issue_id`（任一无效）→ 两个 sent ID 原子清空、不渲染死按钮；（g）**顺序分支**：先发送成功返回有效 `task_id`+`issue_id`（活动 A，stop 渲染）→ 下一次发送**成功但返回空 `task_id`** → 断言 stop 消失、按钮回发送态且**不调用 `cancelTaskById(A)`**（空 ID 分支不得取消旧 task）；（h）发送失败（mutation reject）→ 草稿保留、旧活动目标保留（sent 状态不变）；**可见动作与 §4.2 判定式一致**：草稿非空 + `allowSubmitWhileRunning=true` ⇒ `running=false`，右下角渲染**发送（重试）按钮**（非 stop）；随后清空草稿（`isEmpty=true`）→ stop 重新渲染、点击仍调用 `cancelTaskById(A)`；重试成功且返回有效 ID → `sentTaskId` 更新为新 task（stop 只作用于最近一次）。可达性：状态由既有 hooks/query（queue items 缓存与 task-runs 缓存，WS `task:*` 失效）驱动，布局改动不参与状态机；task-runs 查询以发送响应自带的 `issue_id` 键定，不依赖面板 `chat.issue_id` 刷新（§4.3.1 边界）。
- **AC-6** 设计落点：`ChatInputCore` 仍只依赖 `draftAdapter`（接口不变）；两宿主 `useTeamAgentDraftAdapter`/`usePrivateAskDraftAdapter` 不变；pending-message 渲染迁入 gutter 对齐块但 testid/渲染条件不变。可观测结果：`chat-input.test.tsx` adapter isolation 套件全绿（`useChatStore` 零订阅）；项目组件测试断言 `project-chat-pending-message`/`private-ask-pending-message` 仍按原条件渲染。可达性：结构性事实，无前置过滤。
- **AC-7** 设计落点：ChatInputCore 传 `ariaLabel`/`stopAriaLabel`（send_tooltip/stop_tooltip 既有 key）+ 配置控件 sr-only 类别标签（model_label/thinking_label）+ chip 内建 aria-label/tooltip + Mod+Enter 原样。可观测结果：role/name 断言——发送按钮 accessible name=send_tooltip 文案、运行态停止按钮=stop_tooltip 文案、Team Agent 只读 model/thinking 值各有「模型/思考级别」类别 sr-only 标签；Playwright **真跑**（非 `--list`，见 §6.9-3 证据契约）键盘发送 + 运行中停止（§4.3.1）。可达性：不依赖平台（Web/Desktop 共享同一组件）。
- **AC-8** 设计落点：§1.1 改动清单闭合性。可观测结果：实施 diff 范围审查——受控 `crctl git diff --name-only <基线 SHA> --cwd <resources[].multica.worktreePath>`（原生 `git` 在 controlled-shell 下被 deny，白名单核对一律经 crctl git 受控执行，路径只取 `execution_context.resources`；基线为 `117fc6be`），核对改动文件 ∈ 白名单（§1.1 表 + 测试文件 + `e2e/project-chat-composer.spec.ts` + 差异文档 + 治理 sidecar `multica/CUSTOM.md` 受控例外），无 `server/`、无 `server/migrations/`、无 API 路由/数据模型变更；普通聊天截图基线对比（`ChatInput` 路径零 diff）；差异文档存在且每条有理由。可达性：范围由提交内容静态可查（命令口径为 plan 证据命令表一条稳定 cmd-NN）。

## 组件测试与 Playwright 计划（FR-8 细化）

1. `packages/views/chat/components/chat-input.test.tsx`：ChatInputCore 套件新增——wrapper（外层 GUTTER）/surface（内层 COLUMN）两层类名断言 + surface token、底栏流布局结构、`leftAdornment` 渲染于左组、`data-slot="chat-input-surface"`；a11y——发送按钮 accessible name=send_tooltip 文案、`running+onStop` 时停止按钮 accessible name=stop_tooltip 文案；`allowSubmitWhileRunning=true` 时运行中+有内容 → 发送可用且 handleSend 放行、空输入 → 停止；未传该字段 → 运行中发送被拦（现状行为，Private Ask 依赖）。
2. `packages/views/projects/components/project-team-agent-chat.test.tsx` / `project-private-ask.test.tsx`：断言模型/思考控件 testid 现在位于 composer 区域内（`project-chat-composer`/`private-ask-composer` 子树；**不再以 `project-chat-model-row`/`private-ask-model-row` 为定位锚点**——两锚点随独立行移除，§9 移除清单）；既有三态与 PATCH 断言保持；新增——sr-only 类别标签存在（model_label/thinking_label 文案）、Team Agent 消息流根/队列栏两层 DOM 结构（外层 GUTTER 节点与内层 COLUMN 节点分离）、Team Agent 停止路径双源矩阵（§4.3.1 生命周期闭合表逐行）：mock `listTasksByIssue` 返回含 `sentTaskId` 的 task-runs（queued / dispatched / **running** / waiting_local_directory / completed / failed / cancelled 七态各一例），mock queue items 按服务端过滤口径只放 queued/dispatched——断言 queued/dispatched 时 stop 出现（items 含；发送成功后草稿已清空、`isEmpty=true`）、**running 且 items 不含该 task 时 stop 仍出现**（任务时间线支撑，草稿已清空）、终态时按钮回发送态（终态覆盖陈旧 items 残留）、点击 stop 调用 `cancelTaskById(task_id)`、非 cancelled 终态 → `cancel_already_finished` toast；硬降级矩阵（cycle 2 回修）：（i）首次发送即返回空 `task_id`/`issue_id` → 不渲染死按钮；（ii）**顺序分支**：活动 A（有效 sent ID、stop 渲染）→ 下一次发送成功返回空 `task_id` → 断言 stop 消失、发送态恢复且**不调用 `cancelTaskById(A)`**（两个 sent ID 已原子清空）；（iii）发送失败（mutateAsync reject）→ 旧活动目标保留（sent 状态不变）、草稿保留；断言右下角渲染**发送（重试）按钮**（无 stop Square、无 stop_tooltip 名称——草稿非空 + allowSubmitWhileRunning=true ⇒ running=false，与 §4.2 判定式一致）；随后清空草稿 → stop 重新渲染、点击仍调用 `cancelTaskById(A)`。
3. e2e 新增 `e2e/project-chat-composer.spec.ts`（或并入既有 spec）：宽面板截图（发送框 vs 消息列边缘对齐、与普通聊天 surface 视觉一致）；窄面板 360px 回归（AC-3）；运行中停止交互（AC-5/§4.3.1）与键盘发送（AC-7）。**证据契约（B-002 上游回修）**：spec 必须**真跑**作为 AC-1/AC-3/AC-5/AC-7 的浏览器行为证据——实施期在 `FRONTEND_ORIGIN` 指向运行中的前端+服务端时真跑四组用例；环境无法建立时按 ENVIRONMENT_MISMATCH 技术中止（AC-3/AC-5/AC-7 的浏览器行为面不得记为完成，test-report 记录未执行原因）；`--list` 仅证明 spec 可解析/可发现，不得冒充浏览器行为证据；packages/views 全量 `vitest run` 与交付 diff 白名单核对（经受控 `crctl git diff`，见 AC-8）各登记为稳定证据命令（plan §6.2 cmd-NN）。
4. 差异文档：`packages/views/projects/components/project-chat-composer-layout-diff.md`。

# 7. 安全与性能考量

- **权限**：Model/Thinking 控件的可编辑性完全沿用现状分支（Team Agent `canConfigure` owner/admin；Private Ask creator-only），服务端 403 强制（CR-2026-056）不变；只读徽标/runtime guide 形态保留。布局改动不新增任何可写路径。
- **数据**：不新增请求——控件数据源沿用 `runtimeModelsOptions`、`projectChatOptions`、`projectPrivateChatOptions` 等既有 query；停止路径双源复用既有缓存：queue items 与 ProjectQueueBar 同 key、task-runs 与 TeamAgentStreamView 同 key（`issueKeys.tasks`），react-query 收敛去重；底栏换行纯 CSS，无测量/无新 state。
- **可访问性**：ChatInputCore 补传 `ariaLabel`/`stopAriaLabel`（send_tooltip/stop_tooltip，与 `ChatInput` 同 key，B-002）；只读 Model/Thinking 值带 sr-only 类别标签（model_label/thinking_label）；chip 控件自带 aria-label 与 tooltip；`aria-disabled`（noAgent）不变；焦点可见性（focus-within ring）与普通聊天一致（增强）。
- **边界**：窄面板 360px、长模型 ID（truncate）、thinkingLevels 为空（不渲染 thinking 控件）、agent 为 null（不渲染工具栏）、noAgent 置灰——逐一在 §4 设计中覆盖。
- **失败模式**：CSS 类名改动最坏结果为视觉回退，无数据/事务风险；无需回滚方案（无迁移）。停止路径失败按 TSUG-007 三支降级为 toast，无状态写入。

# 9. 批准范围（契约）

- **scope_in**（本 CR 必须交付）：
  - FR-1~FR-8 全部实现条目（§6 映射表），验收 AC-1~AC-8。
  - 改动文件白名单：§1.1 表列文件（含治理 sidecar `multica/CUSTOM.md`，见下）+ 上表测试文件 + `e2e/project-chat-composer.spec.ts` + `packages/views/projects/components/project-chat-composer-layout-diff.md`。
  - **testid 保留/移除/替换清单（唯一事实，B-001 定点回修，二选一闭合为「删除、不迁移」）**：被移除的独立行锚点一律随行删除、不迁移到新容器，不存在「保留并迁到 toolbar 容器」的并存读法；清单如下：
    - **移除（共 2 项，均随独立行删除）**：① `private-ask-model-row`（Private Ask 独立模型行，§1.1/§3.2/AC-4）→ 替换锚点为新增 `private-ask-model-picker`；② `project-chat-model-row`（Team Agent 独立模型行外层容器锚点）→ **无替换锚点**：断言改用其内部四个 testid 位于 `project-chat-composer` 子树（§6.9-2）；代码事实：multica `117fc6be` 中该 testid 仅 `project-team-agent-chat.tsx` L916 一处声明点，全仓无测试/e2e 引用（本轮实读核实）。
    - **新增（共 1 项）**：`private-ask-model-picker`（Private Ask 模型控件，随 `leftAdornment` 进底部工具栏）。
    - **保留（值不变，其余全部）**：Team Agent 内部四个 testid `project-chat-model-readonly`/`project-chat-model-picker`/`project-chat-model-runtime-guide`/`project-chat-thinking-picker` 随 `leftAdornment` 原样保留；其余 `project-chat-*`/`private-ask-*` 系列（含 `private-ask-thinking-picker`、`project-chat-pending-message`、`private-ask-pending-message`、`project-queue-bar`、`project-chat-composer`/`private-ask-composer`）逐一保留且值不变。
    - 测试/e2e 断言仅随上述两个移除锚点更新（`private-ask-model-row`→`private-ask-model-picker`；`project-chat-model-row`→内部四个 testid 的 composer 子树断言）。
  - **治理 sidecar（仓库纪律 #10 强制，B-001 上游回修）**：`multica/CUSTOM.md` 纳入批准范围——实施时按该文件当时实际结构登记本 CR 新增/修改文件台账（编号顺延、原因含 CR 编号与 TASK）；该文件为 governance 台账、不承载产品代码语义，AC-8 交付 diff 白名单核对将其列为唯一受控例外出口（不因此放宽 server/API/迁移/数据模型等其余白名单项）。
  - Team Agent composer 运行中停止路径（§4.3.1/D-7，双源：queue items + 容器 Issue 任务时间线（`issueKeys.tasks`/`api.listTasksByIssue` 只读复用），`onStop` 复用 `useCancelProjectQueueTask`，不新增 API）；ChatInputCore 的 `ariaLabel`/`stopAriaLabel` 补传与 `allowSubmitWhileRunning` 采纳（§3.2）。
- **scope_out**（明确排除）：server 任何代码；任何 API 变更；`server/migrations/`；任务快照逻辑；数据模型；`ChatInput`（全局）视觉基线与业务语义；`useProjectChatStore` 结构；Discussion UI；mobile；新 UI 组件库/新状态管理；`ModelPicker`/`ThinkingPicker`/`SubmitButton`/`ChatAddMenu` 组件本体；draft adapter 接口。
- **zero_diff**（不得改动）：`chat-input.tsx` 中 `ChatInput`（全局）函数体与 `ChatInputProps` 签名；`ChatInputCore` props 签名；`ChatInputDraftAdapter` 接口；`packages/core/api/client.ts` 全部（含 `listTasksByIssue`/`getProjectQueueItems`/`cancelTaskById`，只读消费）；`packages/core/issues/queries.ts`、`packages/core/chat/queries.ts`、`packages/core/projects/queries.ts`/`mutations.ts`、`packages/core/realtime/use-realtime-sync.ts` 全部（`issueKeys.tasks` 与失效路径只读复用）；`useProjectChatStore` 与其 adapter hook 的读写语义；`ContentEditor` 及 editor 包；`PATCH` 端点与三态 body 语义；server 任何代码（含 queue-items 过滤口径与 `/api/issues/:id/task-runs`）；`project-team-agent-chat.tsx` 中 `handleComposerUpload`/`persistModel`/`persistThinking` 函数体、`handleSend` 的业务语义（唯一新增一条语句：成功后记录 `sentTaskId`/`sentIssueId`，§4.3.1）；testid 保留/移除/替换清单按 scope_in 唯一执行（B-001 定点回修）——移除锚点 2 项（`private-ask-model-row`、`project-chat-model-row`）随独立行删除、不迁移；替换/新增仅 `private-ask-model-row`→`private-ask-model-picker` 一项；`project-chat-model-row` 无替换锚点；其余 `project-chat-*`/`private-ask-*` testid（含 Team Agent 内部四个 testid）一律不变；locale 文件（无新 key）；`ChatInputCore` props 签名与 `SubmitButton`/`ModelPicker`/`ThinkingPicker` 组件本体。
- **follow_up**（留给后续 CR）：Discussion 面板视觉对齐（CR 顺序边界明令不混入）；mobile 端；`ChatInputCore` 与 `ChatInput` 两套 composer 实现的结构性合并去重（本 CR 只做视觉对齐，不做大重构）。

# 既有实现依赖与事实

基线：multica worktree `117fc6be657f91d43df5892b52782a18329c7aed`（requirement/CR-2026-062 分支，已含 CR-A/CR-B/CR-C 合入产物）。以下全部在该 SHA 实读核实：

1. repo: multica
   relative path: packages/views/chat/components/chat-column.ts
   stable symbol/对象: `CHAT_GUTTER`（L27）、`CHAT_COLUMN`（L30）及文件头「gutter scales with the CONTAINER, never the viewport」语义注释
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: 本 CR 对齐的唯一几何事实源；@ 变体需要宿主标记 `@container`。文件头明确 gutter 必须在 cap 之外、按**两层 DOM**（外层 GUTTER > 内层 COLUMN）嵌套；单元素合并会把 gutter 计入 `max-w-4xl` 封顶（历史错位形态）——B-001 回修依据。

2. repo: multica
   relative path: packages/views/chat/components/chat-input.tsx
   stable symbol/对象: `ChatInput`（全局）wrapper `cn(..., CHAT_GUTTER, ...)`（L638）、surface `data-slot="chat-input-surface"`（L651）+ `CHAT_COLUMN` + `border-surface-border bg-surface ... focus-within:ring-2`（L659-660）、底栏 absolute 行（L738/L753）、SubmitButton `running` 判定式（L758-767：`!!isRunning && (!allowSubmitWhileRunning || hasNothingToSend || gate.uploading)`，注释「an empty composer offers Stop, while live content swaps it to Queue Send」）
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: 视觉对齐基准；本 CR 不修改此函数。§4.2 可见动作口径的权威模板——Team Agent 传 `allowSubmitWhileRunning=true` 时与其同语义（草稿非空→发送/重试、草稿空/上传中→stop）。

3. repo: multica
   relative path: packages/views/chat/components/chat-input.tsx
   stable symbol/对象: `ChatInputCore` wrapper `"px-5 pb-3 pt-0"`（L1066）、surface `"relative mx-auto flex min-h-16 max-h-40 ... bg-card pb-9 border-1 border-border ..."`（L1077）、编辑器 `flex-1 min-h-0 overflow-y-auto px-3 py-2`（L1088）、底栏 absolute 行（L1128/L1137）、`leftAdornment?: ReactNode`（ChatInputProps L123）、`pendingUploads`（L870）、`SubmitButton disabled` 含 `pendingUploads > 0`（L1140）、`SubmitButton` 调用只传 `tooltip`/`stopTooltip` 未传 `ariaLabel`/`stopAriaLabel`（L1144-1147）、`running={isRunning}`（L1142）、`handleSend` 门禁含 `isRunning`（L958）、`handleSend` 失败不 commitInput 保草稿（catch L1039-1042 / `accepted === false` L1044-1046 均直接 return）、成功 `commitInput()` 清空编辑器并 `setIsEmpty(true)`（L1014）、未解构 `allowSubmitWhileRunning`（ChatInputProps L102 已有该字段）、「never touches useChatStore」注释（L856）
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: 本 CR 改造对象；props 签名与 draft 隔离事实保持；B-002/B-003 改动点（ariaLabel/stopAriaLabel 补传、allowSubmitWhileRunning 采纳）全部发生在 `ChatInputCore` 内部。失败保草稿（`isEmpty=false`）+ `allowSubmitWhileRunning=true` ⇒ `running=false` 是 AC-5(h) 可见动作（失败回流渲染发送/重试而非 stop）的代码事实基础。

4. repo: multica
   relative path: packages/views/projects/components/project-team-agent-chat.tsx
   stable symbol/对象: `TeamAgentStreamView` 根 `"mx-auto flex w-full max-w-3xl flex-col gap-4 px-4 py-3"`（L313）；`TeamAgentComposer` wrapper `"shrink-0 border-t px-4 py-3"`（L864）、`data-testid="project-chat-model-row"` 独立行（L916，含 `project-chat-model-readonly` L925 / `project-chat-model-picker` L935 / `project-chat-model-runtime-guide` L945 / `project-chat-thinking-picker` L951）、`ChatInputCore` 使用点（L968-973，只传 `isRunning={isPending}` 不传 `onStop`——B-003 事实）、`useSendProjectChatMessage` 解构 `{mutateAsync, isPending}`（L675）、`useCancelProjectQueueTask` 已在本文件 TaskExecutionCard 使用（L499，TSUG-007 三支 L514-520）；`persistModel`（L733）/`persistThinking`（L746）调用 `patchProjectChatConfig`；L686-692 注释「api.updateAgent 不得从聊天路径调用」；**任务时间线已读取**——`ProjectTeamAgentChat` 容器 `useQuery({ queryKey: issueKeys.tasks(issueId), queryFn: () => api.listTasksByIssue(issueId), staleTime: 30_000, enabled: hasContainer })`（L98-102，L8 已 import `issueKeys`）；`taskStatusKind`（L445-457，queued/dispatched/waiting_local_directory/running → "running" kind）；`TaskExecutionCard.canStop = task.status === "running" && (isOriginator || canConfigure)`（L510，取消动作经同一 mutation L514）
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: Team Agent 侧改造对象；三态分支、四个内部 testid、PATCH 路径全部保留（`project-chat-model-row` 锚点随独立行移除、无替换锚点，§9 移除清单第 2 项——全仓引用核实：该 testid 仅此处 L916 声明点，无测试/e2e 引用）；B-001（两层 DOM）、B-002（sr-only）改动点所在；B-003 v2 的任务时间线事实源（`issueKeys.tasks`）已由消息流读取，composer 以发送响应 `issue_id` 自键定同 key 复用，不产生重复请求。

5. repo: multica
   relative path: packages/views/projects/components/project-private-ask.tsx
   stable symbol/对象: `PrivateAskComposer` wrapper `"shrink-0 border-t px-4 py-3"`（L392）、`data-testid="private-ask-model-row"`（L405）与 `private-ask-thinking-picker`（L420）、`ChatInputCore` 使用点（L436，disabled=running/isRunning/onStop）；`persistModel`（L327）/`persistThinking`（L340）调用 `patchChatSessionConfig`
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: Private Ask 侧改造对象；creator-only 语义不变。

6. repo: multica
   relative path: packages/views/chat/components/chat-message-list.tsx
   stable symbol/对象: 既有消息列表的权威两层嵌套——外层容器 `cn("flex-1 overflow-y-auto", CHAT_GUTTER)`（L319）、内层 `cn(CHAT_COLUMN, ...)`（L325/L373/L406）
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: 两层 DOM 嵌套的权威基线（B-001 回修依据）；Private Ask 消息列已对齐（证明 chat-column 常量可安全用于项目面板）；Team Agent 自绘流容器需按同一形态对齐。

7. repo: multica
   relative path: packages/views/projects/components/project-chat-panel.tsx
   stable symbol/对象: `ModePane` 根 `"flex h-full flex-col p-4"`（L199），承载 Team Agent/Private Ask/Discussion 三面板
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: `@container` 的放置点；对 Discussion 零影响。

8. repo: multica
   relative path: packages/views/projects/components/project-queue-bar.tsx
   stable symbol/对象: 根 `"shrink-0 border-t px-4 py-2"`（L61），位于消息流与 composer 之间；展开列表取消经 `useCancelProjectQueueTask`（L33，TSUG-007 三支 L39-50）；items 来自 `projectQueueItemsOptions`（服务端过滤 queued/dispatched，见 #21）
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: 队列栏边缘参与「消息列↔发送框对齐」链，需两层 DOM 最小对齐（B-001）；其取消语义与停止路径复用同一 mutation；其 items 查询缓存与 composer 双源之一共用同一 query key（react-query 去重）。

9. repo: multica
   relative path: packages/core/api/client.ts
   stable symbol/对象: `patchProjectChatConfig`（L3722，`PATCH /api/projects/:id/chat/config`，session_id 必填、三态 body、owner/admin 403）、`patchChatSessionConfig`（L3783，`PATCH /api/chat/sessions/:id/config`，creator-only 403）
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: 工具栏控件的唯一写路径（本 CR 不改）。

10. repo: multica
    relative path: packages/views/agents/components/inspector/model-picker.tsx / thinking-picker.tsx / chip.ts
    stable symbol/对象: `ModelPicker`/`ThinkingPicker` `variant="chip"`（默认）+ `CHIP_CLASS`（`group flex min-w-0 ... px-1.5 py-0.5 text-caption hover:bg-accent`）；可编辑 chip 触发按钮自带 `aria-label={triggerTitle}` 与 tooltip；`canEdit=false` 只读 chip 为纯 `<span>`（值文本 + `title`，无类别可访问名称）
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: 工具栏控件复用对象（不新建组件）；可编辑 chip 的可访问名称/tooltip 由组件内建承载；只读 chip 的类别语义必须由宿主 sr-only 标签补齐（B-002）。

11. repo: multica
    relative path: packages/ui/components/common/submit-button.tsx
    stable symbol/对象: `SubmitButton` props（loading/busy/running/onStop/tooltip/ariaLabel/stopTooltip/stopAriaLabel）；`running=true` 分支 `onClick={onStop}`、ArrowUp/Square 均 `aria-hidden`（无 ariaLabel/stopAriaLabel 时图标按钮无可访问名称）
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: 右下角发送/停止按钮复用对象（不修改）；B-002 要求调用方必须传 ariaLabel/stopAriaLabel、B-003 要求调用方必须传可执行 onStop。

12. repo: multica
    relative path: packages/views/locales/en/projects.json
    stable symbol/对象: `chat.stream.model_label`="Model"、`chat.stream.thinking_label`="Thinking"、`chat.stream.runtime_guide`（en/ja/ko/zh-Hans 四语目录均存在，parity.test.ts 覆盖）
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: 无新增文案 key（NFR-3）；runtime guide 文本继续复用。

13. repo: multica
    relative path: packages/core/api/schemas.ts
    stable symbol/对象: `ProjectChatSendResult`（L1524-1529，含 `task_id` 与 `issue_id`；`ProjectChatSendResultSchema` L1531-1537 二者为 UUID 必填，fallback 时整体降级为空串）；`QueueItem`（L1736，`task_id`/`status`/`originator`；items 由服务端过滤为 queued/dispatched）；`AgentTaskSchema.status: z.string().default("cancelled")`（L2261）
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: B-003 双源数据事实源——停止目标（send 返回的 task_id）+ 容器 Issue id（send 返回的 issue_id）+ 两个活动性事实源（items 与 task-runs）的 schema 边界。

14. repo: multica
    relative path: packages/core/api/client.ts
    stable symbol/对象: `sendProjectChatMessage`（L3756，POST /api/projects/:id/chat/messages，返回 `ProjectChatSendResult`）；`cancelTaskById`（L3569，POST /api/tasks/:id/cancel，终态任务返回幂等 200 携带真实状态）；`listTasksByIssue`（L2478，GET /api/issues/:id/task-runs，`AgentTaskListSchema` fallback `[]`）
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: B-003 发送返回（task_id/issue_id）、取消端点与任务时间线端点的既有契约（本 CR 不改，只消费）。

15. repo: multica
    relative path: packages/core/projects/mutations.ts
    stable symbol/对象: `useSendProjectChatMessage`（L63-77，返回 `{mutateAsync, isPending}`，isPending=本地入队窗口；onError 仅 409 失效 `projectKeys.chat`——成功路径不失效）；`useCancelProjectQueueTask`（L93-106，`mutateAsync(taskId)`、onSettled 失效 `projectKeys.queueStatus` 前缀含 items；TSUG-007 三支语义）
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: B-003 复用对象——停止路径与 TaskExecutionCard/ProjectQueueBar 同一 mutation、同一竞态/错误语义；无新增请求；`projectKeys.chat` 成功路径不失效（全局 staleTime=Infinity，query-client.ts）是 composer 用发送响应 `issue_id` 自键定任务时间线的依据（§4.3.1 边界）。

16. repo: multica
    relative path: packages/core/projects/queries.ts
    stable symbol/对象: `projectQueueItemsOptions`（L59，queryKey=`projectKeys.queueItems(wsId, id)`=queueStatus 前缀 + `"items"`，WS `task:*` 前缀失效；服务端过滤 queued/dispatched，见 #21）
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: composer 双源之一（queued/dispatched 窗口）与 ProjectQueueBar 共用同一 query 缓存（react-query 去重），NFR-4「不新增重复请求」成立；items 不含 running 是 B-003 v2 引入任务时间线源的原因。

17. repo: multica
    relative path: packages/core/issues/queries.ts
    stable symbol/对象: `issueKeys.tasks(issueId)`=`["issues","tasks",issueId]`（L179）；`issueKeys.tasksAll()`（L177）注释「any task lifecycle event refreshes every per-issue list, regardless of which issue is currently mounted」
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: B-003 任务时间线事实源的 query key——composer 以发送响应的 `issue_id` 键定（`issueKeys.tasks(sentIssueId)`），与 TeamAgentStreamView 同 key 时收敛为同一缓存，不产生重复请求。

18. repo: multica
    relative path: packages/core/types/agent.ts
    stable symbol/对象: `AgentTask.status` 联合：`"queued" | "dispatched" | "waiting_local_directory" | "running" | "completed" | "failed" | "cancelled"`（L291-298）；`waiting_local_directory` 注释「Treated as an active (non-terminal) state alongside queued/dispatched/running by every consumer that buckets tasks into "active vs done"」（L286-290）
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: B-003 的 ACTIVE/TERMINAL 集合定义事实源——ACTIVE={queued,dispatched,waiting_local_directory,running}、TERMINAL={completed,failed,cancelled}，与既有 active-vs-done 分桶口径一致。

19. repo: multica
    relative path: packages/core/realtime/use-realtime-sync.ts
    stable symbol/对象: `task:` 前缀失效：`qc.invalidateQueries({ queryKey: ["issues","tasks"] })`（L926）与 `projectKeys.queueStatusAll(wsId)`（L902）；WS 断线重连时 `issueKeys.tasksAll()`（L683）
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: 双源的实时性保障——任一 task 生命周期事件（含 task:running/task:completed）同时刷新任务时间线与 queue items，composer 无需新增订阅/轮询；B-003 v2 生命周期闭合的时效前提。

20. repo: multica
    relative path: server/internal/service/project_chat.go
    stable symbol/对象: `sendProjectChatCore` 经 `CreateAgentTask`（task.go L1655-1660）以 `IssueID: issue.ID`（容器 Issue）创建 Team Agent 任务；send 成功后广播 `EventCommentCreated`/`EventTaskQueued`（L557/L578）
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: Team Agent 任务**必然出现在容器 Issue 的 task-runs 列表**（`/api/issues/:id/task-runs`），且 task-runs 生命周期覆盖 queued→dispatched→running→terminal——B-003 v2 用任务时间线覆盖 running 的成立前提（服务端事实，本 CR 不改）。

21. repo: multica
    relative path: server/pkg/db/queries/agent.sql
    stable symbol/对象: `ListProjectPendingTasks`（L2947-2961）注释「identical pending reading (queued + dispatched on the project's issues)」，WHERE `i.project_id = $1`
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: queue items 服务端过滤口径的权威事实——items 只含 queued+dispatched，任务 running 后离开列表；这是 B-003 v2 必须引入任务时间线作为 running 事实源的原因（服务端契约保持，zero_diff）。

# SDD-CLOSE 关闭记录

- **SDD-CLOSE-01** PRD §1.2 规则 3「输入区、附件预览、底部工具栏分层」→ 关闭：§4.2 flow 两层结构 + 编辑器 `overflow-y-auto`；附件预览仍由 ContentEditor 在编辑器区内承载（与普通聊天同构）。判定覆盖数据生产/消费与兼容降级：本项纯渲染分层，无数据生产/存储/传输/schema/降级层，无遗漏层。
- **SDD-CLOSE-02** PRD §1.2 规则 4「leftAdornment 或等价底部工具栏 slot」的机制选定 → 关闭：选定现有 `leftAdornment`（D-3），§3.2 给出两宿主构造契约。
- **SDD-CLOSE-03** PRD §1.2 规则 2/FR-1「复用单一输入 surface、对齐」的落地类名集合 → 关闭：§4.1-2 逐类名给出（border-surface-border/bg-surface/rounded-lg/focus-within ring），且全部对齐块均为外层 `CHAT_GUTTER` > 内层 `CHAT_COLUMN` 两层 DOM（B-001 回修）。
- **SDD-CLOSE-04** 来源完成标志「差异说明文档」的落点与内容 → 关闭：`packages/views/projects/components/project-chat-composer-layout-diff.md`（D-6）；最小内容大纲：a) 消息列/队列栏/发送框共用 CHAT_GUTTER+CHAT_COLUMN 两层嵌套的说明；b) 底栏 flow 布局与普通聊天 absolute 行的等价性；c) surface `max-h-40`（vs 普通聊天 `max-h-96`）保留理由；d) Model/Thinking 可见文字 label 不再常驻、chip+tooltip 承载，类别语义由 sr-only 标签保留；e) Team Agent composer 停止作用于最近一次发送 task 的语义（其余任务仍由队列栏逐条取消），含双源生命周期闭合表（queued/dispatched 由 queue items、running/waiting_local_directory 由任务时间线，终态覆盖）与失败回流可见动作口径（保草稿 → 发送/重试按钮，清空草稿 → stop 重新出现，§4.2 判定式）。每项均须给出「是否必要差异 + 理由」。

- **SDD-CLOSE-05** PRD FR-5/规则 5「右下角复用发送/停止按钮和 loading、上传中、运行中状态」在 Team Agent 侧的运行态来源与停止语义（PRD 未给落点）→ 关闭：§4.3.1/D-7（`sentTaskId`/`sentIssueId` + 双源活动性——queue items 覆盖 queued/dispatched、容器 Issue 任务时间线覆盖 running/waiting_local_directory/终态，终态覆盖闭合 queued→dispatched→running 全生命周期 + `useCancelProjectQueueTask`；send/stop/retry 业务行为与权限不变，零新增 API；失败保草稿 → 发送（重试）按钮、清空草稿 → stop 重新出现，可见动作与 §4.2 `running` 判定式唯一一致（AC-5(h) 落点））。

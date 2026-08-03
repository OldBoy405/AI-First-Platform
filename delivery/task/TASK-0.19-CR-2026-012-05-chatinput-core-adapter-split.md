---
id: CR-2026-012-TASK-05
type: TASK
cr-ref: CR-2026-012
plan-ref: "change-requests/CR-2026-012/plan.md"
sdd-ref: "change-requests/CR-2026-012/sdd.md"
title: ChatInputCore 拆分 + 默认包装 + 双重锁定单测
slug: chatinput-core-adapter-split
status: done
estimate: 6h
depends-on: []
assignee: ""
created: "2026-08-03T18:45:31+08:00"
spec-id: ai-first-platform
version: "0.19"
---

## 任务描述
落地 SDD DD-9 + §5.2/§5.4：`ChatInput` 等价重构为 `ChatInputCore`（只认
`ChatInputDraftAdapter`，零 useChatStore）+ 既名默认包装（内部 hook 构造全局 store
adapter），"自定义 adapter 不触碰 useChatStore"成为结构性事实。

## 涉及文件
- `packages/views/chat/components/chat-input.tsx`：
  ① 导出 `interface ChatInputDraftAdapter`（draftKey/editorKey/draft/attachments +
  setDraft/setAttachments/addAttachment/clearDraft，SDD §5.2 定义）；
  ② `ChatInputCore`：今日全部实现，五处 store 触点改经 adapter——读订阅（:112-150）、
  restore effect（:186-220，`restoreDraftRequest.sessionId !== adapter.draftKey` 判定
  不变）、`handleUpload`（:231）、`handleSend/commitInput`（:284 keyAtSend 改捕获
  adapter 引用；:309-312 清理走 adapter.clearDraft，extraDraftKeys 保留回调形态）、
  `onUpdate`（:389/:395）；JSX（:354-441）与 `ChatInputProps` 不变；
  ③ `ChatInput`（既名导出）：`useGlobalChatDraftAdapter()` 构造默认 adapter——
  activeSessionId/selectedAgentId 订阅、draftKey 派生（:141 语义 + :114-140 注释原样
  搬入）、editorKey（:154）、四写方法映射
- `packages/views/chat/components/chat-input.test.tsx`：新增双重锁定——
  静态断言（mock useChatStore，渲染 ChatInputCore + 自定义 adapter，断言 mock 零调用）+
  行为断言（输入/上传/发送/restore 后 adapter 方法按预期调用、全局 store state 快照不变）

## 实现要点
- `/chat` 页（chat-page.tsx:194）与浮窗（chat-window.tsx:867）**零改动**（import 与
  props 均不变），既有测试全量跑在默认包装上证明等价。
- 拆分是纯等价重构 + 新接口，单 commit 完成便于 revert。

## 验收条件
1. 既有 chat-input.test.tsx 全量用例在默认包装上全绿（零回归）。
2. 新增静态断言：自定义 adapter 下 useChatStore mock 零调用。
3. 新增行为断言：各动作后 adapter 调用序正确、全局 store 快照不变。

## 完成标志
测试全绿 + lint/类型检查零报错 + `/chat` 页与浮窗手测（输入/附件/发送/切 agent 草稿恢复）无差异。

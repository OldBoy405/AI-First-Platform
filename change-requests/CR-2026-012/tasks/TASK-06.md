---
id: CR-2026-012-TASK-06
type: TASK
cr-ref: CR-2026-012
plan-ref: "change-requests/CR-2026-012/plan.md"
sdd-ref: "change-requests/CR-2026-012/sdd.md"
title: project-chat-store 附件槽 + mentionItemTypes 过滤 + 两面回填
slug: backfill-team-agent-private-ask
status: pending
estimate: 8h
depends-on: [CR-2026-012-TASK-04, CR-2026-012-TASK-05]
assignee: ""
created: "2026-08-03T18:45:31+08:00"
---

## 任务描述
落地 SDD §5.3 + DD-10/DD-11：Team Agent 面与 Private Ask 面的手写 textarea composer 换
`ChatInputCore`，补齐附件 + @提及仅成员 + 富文本；草稿/附件落 project-chat-store
`{projectId}:{mode}` 命名空间。

## 涉及文件
- `packages/core/projects/project-chat-store.ts`：扩 `draftAttachments:
  Record<key, Attachment[]>` + `setDraftAttachments/addDraftAttachment`；
  `setDraft("")` 联动清附件；persist 兼容（旧数据无该字段 → 空 map）+
  rehydration 分支测试（project-chat-store.test.ts）
- `packages/views/editor/extensions/mention-suggestion.tsx`：`MentionSuggestionOptions`
  加 `itemTypes?: MentionItem["type"][]`——`buildSyncItems`（:538-609）与 MentionList
  异步搜索（:187-218）两处过滤
- `packages/views/editor/content-editor.tsx`：透传新 prop `mentionItemTypes`
- `packages/views/projects/components/project-team-agent-chat.tsx`：`TeamAgentComposer`
  的 textarea（:845-859）→ `ChatInputCore` + 面内 adapter hook（draftKey =
  projectChatDraftKey(projectId,"team_agent")，editorKey="team_agent" 恒定）；onSend 接
  既有 `useSendProjectChatMessage` 流（pending bubble/错误分支 :708-765 不动），传
  attachment_ids（T04 端点）；onUploadFile = `useFileUpload(api).uploadWithToast(file,
  { issueId: chat 容器 })`；`mentionItemTypes=["member"]` + contextItems
- `packages/views/projects/components/project-private-ask.tsx`：`PrivateAskComposer`
  同款替换；onSend 接 `api.sendChatMessage`（附件参数沿全局 chat 既有签名）；
  onUploadFile 绑既有 session；`mentionItemTypes=["member"]`；停止按钮/模型只读徽标不动

## 实现要点
- Discussion 面**不动**（CR-D 的 useCommentDraftStore 草稿语义保留，SDD §5.3 末条）。
- adapter hook 每面约 15 行，不抽公共包装（两面 mode 常量不同而已，抽象收益为负）。

## 验收条件
1. 两面可上传附件（渲染/删除/发送后清空）、@列表仅成员（agent/squad/issue 不出现，
   含搜索分支断言）、富文本（markdown 列表/加粗）可用。
2. 跨项目、跨模式草稿与附件隔离：store key 级单测 + 真机切换验证不串。
3. 回归：两面发送/停止/错误分支（429/403/409）行为不变；Discussion 面零变化。

## 完成标志
单测全绿 + lint/类型零报错 + 双面真机走查记录（附件/提及/富文本/隔离）。

---
id: CR-2026-012-TASK-07
type: TASK
cr-ref: CR-2026-012
plan-ref: "change-requests/CR-2026-012/plan.md"
sdd-ref: "change-requests/CR-2026-012/sdd.md"
title: DiscussionPane 多选态 + 合并预览 Dialog + DC 设置项 + 四语文案
slug: discussion-multiselect-preview
status: done
estimate: 6h
depends-on: [CR-2026-012-TASK-04]
assignee: ""
created: "2026-08-03T18:45:31+08:00"
spec-id: ai-first-platform
version: "0.19"
---

## 任务描述
落地 SDD §5.1/§5.5 + DD-12：合并转发的全部前端交互（自研设计，无 CodeBanana 实物可抄）+
DC 绑定设置项 + 本 CR 全部新增文案四语落位。

## 涉及文件
- `packages/views/projects/components/discussion-pane.tsx`：
  ① 多选态——本地 `useState<Set<string>>`，工具条「选择」入口，`DiscussionMessage` 左侧
  Checkbox（@multica/ui）；② 底部批量条（batch-action-toolbar.tsx 视觉惯例）：
  「已选 {count} 条」+「合并转发」+「取消」；③ 合并预览 Dialog：trigger_message =
  最早一条选中消息、chat_history 升序列表（作者/时间/内容）、messages_in_conversation
  计数、「升级为 CR」Checkbox（默认态读 projectGatesOptions，**端点缺失/报错 → 默认
  不勾**，TSUG-003）；确认 → POST merge-forward → 成功 toast + 退出多选态；
  429/403 → 结构化提示且**保留多选态与预览**（DD-6）
- `packages/core/api/client.ts`：`mergeForwardDiscussion(projectId, commentIds,
  registerCr)` client 方法 + 类型
- 项目设置面（team_agent_id 既有配置位同面）：DC agent 选择器项（读写
  `discussion_coordinator_agent_id` settings key）
- `packages/views/locales/{en,ja,ko,zh-Hans}/projects.json`：`chat.merged_forward.*`
  （trigger_message/chat_history/messages_in_conversation/preview_title/confirm/cancel/
  register_cr_label/select_entry/selected_count 约 10 键）+ `chat.dc.*`
  （queue_full_notice 等约 3 键）+ 设置项文案；四语同 commit（CR-D 惯例 3bce9ade0）

## 实现要点
- DC 的 agent comment 用既有 `DiscussionMessage` 渲染（ActorAvatar 按 author_type 分支），
  零新组件。
- 多选态为单组件内状态，不进 zustand（SDD §5.1 定案）。

## 验收条件
1. 多选 → 预览三段结构与计数正确 → 确认 → Team Agent 面出现任务；取消/半途退出多选
   零副作用。
2. 429 场景：错误提示 + 多选与预览保留；approvalSvc 未配置环境：升级 CR 默认不勾、
   预览不报错。
3. parity.test.ts 全绿（四语无缺键）。

## 完成标志
单测 + parity 全绿 + lint/类型零报错 + 多选/预览/错误分支真机走查记录。

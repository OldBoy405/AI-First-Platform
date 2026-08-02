---
id: CR-2026-006-TASK-03
type: TASK
cr-ref: CR-2026-006
plan-ref: "change-requests/CR-2026-006/plan.md"
sdd-ref: "change-requests/CR-2026-006/sdd.md"
title: 入口 Tabs + 三模式 tab 骨架 + project-chat-store + 四语文案
slug: chat-window-shell
status: done
estimate: 4h
depends-on: [CR-2026-006-TASK-01]
assignee: ""
created: "2026-08-02T01:15:00+08:00"
spec-id: ai-first-platform
version: "0.13"
---

## 任务描述
落地 SDD §5.1/§5.3/§5.4：project-detail 入口改造 + 窗口骨架 + 独立状态层。本任务只交付骨架与
Private Ask/Discussion 空态占位，Team Agent 消息流内容归 T04。

## 涉及文件
- `packages/views/projects/components/project-detail.tsx`：`ResizablePanel id="content"` 内
  （:470 flex 列），`BreadcrumbHeader` 之后用 `packages/ui/components/ui/tabs.tsx`（line variant）
  包住既有 `IssueSurface`（Issues tab）与新 `ProjectChatPanel`（Chat tab）；`?tab=` 参数缺省 issues；
  右侧 sidebar 不动
- 新建 `packages/views/projects/components/project-chat-panel.tsx`：三模式 tab 条骨架
  （Team Agent / Private Ask / Discussion，tooltip + 空态问候语 + 首次教程气泡），先接
  `GET /api/projects/{id}/chat`（T01 交付）拿容器 issue_id；Private Ask/Discussion 面本任务只做
  纯空态（问候语 + "由后续版本提供"占位文案）
- 新建 `packages/views/projects/store/project-chat-store.ts`（zustand，persist 按 workspace slug
  命名空间）：`drafts: Record<"{projectId}:{mode}", string>`、`activeMode`、教程气泡已读标记——
  **独立 store，不复用 `useChatStore`**（其 `activeSessionId` 是浮窗与 /chat 页共享的全局单例，
  挂第三个消费者会互抢会话）
- `packages/views/locales/{en,ja,ko,zh-Hans}/*.json`：新增全部文案（三条空态问候语、教程气泡、
  tab 名、未配置引导态提示等），过 parity 测试

## 实现要点
- 切 tab 纯前端不重拉数据：三面各自独立 query key（Team Agent 面的 key 见 T04；PA/Disc 本任务
  为空态不发请求）。
- Team Agent 未配置态（`team_agent_id` 为 null）：owner/admin 见内联 agent 选择器 CTA（写
  `settings.team_agent_id`，T01 交付的端点），普通成员见「请联系项目 Owner 配置 Team Agent」。
- 单测覆盖：Tabs 切换不触发网络请求（mock 断言）；`?tab=` 深链解析；草稿按
  `{projectId}:{mode}` 隔离持久化；未配置态两种角色分支渲染正确。

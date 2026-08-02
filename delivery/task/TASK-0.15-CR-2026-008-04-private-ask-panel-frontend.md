---
id: CR-2026-008-TASK-04
type: TASK
cr-ref: CR-2026-008
plan-ref: "change-requests/CR-2026-008/plan.md"
sdd-ref: "change-requests/CR-2026-008/sdd.md"
title: 前端 Private Ask 面（纯 props 组合 + 只读模型徽标 + 四语）
slug: private-ask-panel-frontend
status: done
estimate: 5h
depends-on: ["CR-2026-008-TASK-01"]
assignee: ""
created: "2026-08-02T11:25:00+08:00"
spec-id: ai-first-platform
version: "0.15"
---

# TASK-04 — 前端 Private Ask 面

## 任务描述

把 project-chat-panel 的 Private Ask 空态占位替换为完整聊天面（SDD §5.1），**不引入
use-chat-controller.ts / useChatStore 单例**。

## 涉及文件 / 模块（multica 仓 packages/）

- `packages/views/projects/components/project-private-ask.tsx`（新建）
- `packages/views/projects/components/project-chat-panel.tsx`（挂入新面，替换占位）
- project-chat-store（CR-A 已建）：草稿键 `{projectId}:private-ask`
- `packages/views/locales/`（四语新增文案）

## 实现要点

- 进入面时 `GET /api/projects/{id}/private-chat` 拿 sessionId（组件内自管，query 缓存）。
- 消息流：`chatKeys.messages(sessionId)` + `chatKeys.pendingTask(sessionId)` 既有 query 喂
  `ChatMessageList`（纯 props：messages/pendingTask/availability/分页三件套）；WS 直写由
  use-realtime-sync 既有 handler 按 sessionId 命中，零新增事件处理。
- 输入区：`ChatInput`（纯 props）→ 既有 `/api/chat/sessions/{id}/messages`；生成中
  `TaskStatusPill` + 既有停止端点。
- 模型选择器：**只读徽标**展示 team agent 当前模型，tooltip 文案「模型随 Team Agent 配置」
  （SDD-SUG-003 落地），文案计入四语。
- `409 team_agent_not_configured` → 复用 CR-A 引导态组件。
- 无 Ask/Coding 切换控件、无 work_dir 入口、无斜杠命令（PRD FR-8/§7）。

## 验收条件

1. 组件测试：面内不 import use-chat-controller/useChatStore（静态断言或 lint 规则）；
   发送/流式/停止/附件/@成员提及在 mock 层验证。
2. 草稿：`{projectId}:private-ask` 与 team-agent 草稿互独立，刷新保留。
3. 只读徽标 + tooltip 呈现正确；无编辑入口。
4. locales parity 测试全绿（en/ja/ko/zh-Hans）。

## 完成标志

组件测试通过 + parity 全绿 + web/desktop 双端目视一致 + lint 零报错。

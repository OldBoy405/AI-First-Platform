---
id: CR-2026-056-TASK-10
type: TASK
cr-ref: CR-2026-056
plan-ref: "change-requests/CR-2026-056/plan.md"
sdd-ref: "change-requests/CR-2026-056/sdd.md"
title: M5 前端接入：schema / client / 两面板 / 文案
slug: m5-frontend-session-config
status: pending
estimate: 12h
depends-on: [CR-2026-056-TASK-07, CR-2026-056-TASK-13]
created: 2026-08-30T20:45:00+08:00
---

## 任务描述

前端接入会话级配置：独立 zod schema + 硬/软降级、client 方法、Team Agent 面板改 PATCH、Private Ask 可写 picker、四语文案。对应 plan.md M5、SDD §3.4/§4.11。

输入条件：TASK-06/07/13 的后端 API 形状已定稿（GET / PATCH / container / messages / merge-forward 响应，SDD §3.1/§3.2；Private Ask `PATCH /api/chat/sessions/{sessionId}/config` 见 TASK-13）。

## 涉及文件 / 模块

- `packages/core/api/schemas.ts`（新独立 schema + `UNSAFE_CHAT_CONFIG_FALLBACK`；不改 `ChatSessionSchema` 塞默认值）
- `packages/core/api/` client（新增 GET/PATCH session config、POST container、messages 扩展参数）
- `packages/core/api/schemas.test.ts`（硬/软降级夹具，AC-27）
- `packages/views/projects/components/project-team-agent-chat.tsx`（`persistModel` 改造、ThinkingPicker、无 Issue 态）
- `packages/views/projects/components/project-private-ask.tsx`（只读徽章改可写）
- `packages/views/locales/`（四语文案）与 `packages/views/locales/parity.test.ts`（AC-26）

## 实现要点

1. **独立 schema + 降级（§3.4，NFR-8）**：新独立 zod schema（不给 `session_id` 加 `z.string().default("")`，不把字段塞进 `ChatSessionSchema`）；`UNSAFE_CHAT_CONFIG_FALLBACK = { session_id: "", issue_id: null, model: "", thinking_level: "", model_source: "runtime_default", thinking_level_source: "runtime_default" }`。经 `parseWithFallback`：**硬降级**——缺/空/非 UUID 的 `session_id`（或 messages 成功体缺 `session_id`/`issue_id`）→ 整体 fallback，UI 只读、禁用 picker/PATCH/发送、重试 GET；**软默认**——合法 UUID 但缺 model/source/`issue_id` → 字段级默认（`model=""`、`thinking_level=""`、`*_source="session_default"`、`issue_id=null`），控件可写。禁止用空 `session_id` 发 PATCH/发送。
2. **client 方法**：`GET /api/projects/{projectId}/chat`（响应解析用新 schema）、`PATCH /api/projects/{projectId}/chat/config`、`POST /api/projects/{projectId}/chat/container`、`POST /api/projects/{projectId}/chat/messages`（body 必带 `session_id`）、Private Ask `PATCH /api/chat/sessions/{sessionId}/config`。
3. **Team Agent 面板（§4.11，FR-1/FR-18）**：`persistModel` **删除** `api.updateAgent`，改 PATCH session config；Thinking 同样（接入 `ThinkingPicker`，空串哨兵与 Agent 页一致）；非 owner/admin 控件只读（后端 403 仍为准，AC-6）；无 `issue_id` 时 composer 可用、上传省略 `issueId`、timeline 空态；硬降级时禁用写操作并提示；复用 `ChatInputCore` / draft adapter（`useTeamAgentDraftAdapter`）/ `useFileUpload` / 停止/重试，不重做视觉。
4. **Private Ask 面板（FR-3/FR-12）**：去掉只读模型徽章，改可写 Model/Thinking，走 `PATCH /api/chat/sessions/{id}/config`（creator-only）；不写 Team Agent session；历史缺 `base_*` 的 `agent_default` 展示照常（后端语义）。
5. **文案**：新增文案四语齐（`parity.test.ts` 绿，AC-26）。

## 验收条件

1. `packages/core/api/schemas.test.ts`：硬降级 → 全量 fallback 且只读；软默认 → `*_source="session_default"` 且可写；无伪造 `session_id`（AC-27）。
2. `packages/views/locales/parity.test.ts` 绿（AC-26）。
3. 组件测：`persistModel`/Thinking 持久化后 `api.updateAgent` 无调用（spy 断言，AC-1/AC-2）；两成员 Private Ask 互不影响（AC-3）；picker 可写且 draft/附件/发送/停止/重试不回归（AC-21）；非 owner/admin 控件只读态渲染。
4. 全局检索：聊天路径无 `updateAgent` 调用（AC-1）。
5. 类型检查与上述测试在 multica CR worktree 前端工作流下全绿。

## 完成标志

前端测试（schemas / parity / 组件测）全绿并提交。

## 接口契约

- 消费：TASK-06 GET/PATCH 响应形状（§3.1：`session_id`、可空 `issue_id`、`team_agent_id`、`model`、`thinking_level`、`model_source`、`thinking_level_source`；PATCH 三态请求体）；TASK-07 messages 请求体（必带 `session_id`）与成功体 `{session_id, issue_id, comment_id, task_id}`、container 200 体、merge-forward 附加字段；TASK-09 上传省略 `issue_id` 的后端容忍；基线 `parseWithFallback`（`packages/core/api/schema.ts`）、`ModelPicker` / `ThinkingPicker`。
- 产出：前端测试证据与「无 `updateAgent`」基线——供 TASK-11 汇总（AC-1/2/3/21/26/27）。

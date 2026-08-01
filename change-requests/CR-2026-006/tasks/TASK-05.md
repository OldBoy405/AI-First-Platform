---
id: CR-2026-006-TASK-05
type: TASK
cr-ref: CR-2026-006
plan-ref: "change-requests/CR-2026-006/plan.md"
sdd-ref: "change-requests/CR-2026-006/sdd.md"
title: 模型选择器（绑定 Team Agent 配置）+ 权限态/Runtime 态文案区分
slug: model-picker
status: pending
estimate: 3h
depends-on: [CR-2026-006-TASK-01, CR-2026-006-TASK-03]
assignee: ""
created: "2026-08-02T01:15:00+08:00"
---

## 任务描述
落地 SDD DD-4/§5.2 与 PRD FR-8：输入区模型选择器，绑定的是 Team Agent 的模型配置（不是按消息
覆盖——已核实 daemon 不消费任务级模型覆盖）。本任务是技术评审 **TSUG-003** 的落地点。

## 涉及文件
- `packages/views/projects/components/project-chat-panel.tsx`：Team Agent 面输入区右侧接入模型
  选择器，复用 `packages/views/agents/components/inspector/model-picker.tsx` 的模式，数据源
  `runtimeModelsOptions`（`packages/core/runtimes/models.ts:40-52`）
- Agent 模型配置的既有更新端点（沿用，无需新增后端）

## 实现要点
- **TSUG-003 两种禁用态必须区分文案**，不能合并成一种"不可用"提示：
  1. **无编辑权限**（当前用户对该 Team Agent 无编辑权——项目 owner/admin 身份与 agent 编辑权限
     可能错位，例如 agent 由他人创建）→ 只读徽标展示当前模型，**无 CTA、无错误语气文案**。
  2. **无可用 Runtime**（daemon 未上报任何可用模型）→ 引导文案「请先在设置中启动本地 Agent」+
     发送禁用（复用既有 chat availability 机制与 `agent_unavailable` 结构化错误先例）。
  - 两者判定顺序：先查编辑权限决定是否可交互，再查 Runtime 可用性决定选择器内容/发送可用性——
    避免把"我没权限改"误判成"环境没配好"，反之亦然。
- 有编辑权限且有可用 Runtime：正常下拉选择，选中后调 agent 更新端点持久化。
- 单测覆盖：四种组合（有权限×有Runtime / 有权限×无Runtime / 无权限×有Runtime / 无权限×无Runtime）
  分别渲染正确的选择器状态与文案。

---
id: CR-2026-011-TASK-06
type: TASK
cr-ref: CR-2026-011
plan-ref: "change-requests/CR-2026-011/plan.md"
sdd-ref: "change-requests/CR-2026-011/sdd.md"
title: CrGateCard 三变体 + 消息流插入 + 执行卡迷你条 + 批准/驳回交互
slug: gate-card-interactions
status: done
estimate: 6h
depends-on: [CR-2026-011-TASK-04, CR-2026-011-TASK-05]
assignee: ""
created: "2026-08-02T12:40:00+08:00"
spec-id: ai-first-platform
version: "0.18"
---

## 任务描述
落地 SDD §5.2：门禁项作为第三类时间线元素进入 Team Agent 消息流；审批卡/blocked 卡/历史条
三变体；批准/驳回全交互（含 409/403 结构化呈现与 pending_advance 跨端一致态）。

## 涉及文件
- `packages/views/projects/components/`（新 `cr-gate-card.tsx`）：三变体——
  ① **审批卡**（pending 段）：CR-ID + 段名 + 证据清单（文件 + sha256 前 12 位）+ digest 指纹 +
  needs_reconcile 警示条；`can_approve` → 批准/驳回按钮（驳回展开必填 reason textarea），
  否则只读"等待 {角色} 审批"；`pending_advance=true` → 「已批准，等待推进」态（TSUG-001，
  服务端派生，刷新/他端一致）；
  ② **blocked 卡**：blocker 列表（id/location/issue/suggestion 直渲 detail JSONB）+
  「reviewLoop attempt N/3」进度点；
  ③ **历史条**：passed/failed 单行折叠，可展开看当时证据指纹
- `packages/views/projects/components/project-team-agent-chat.tsx`（:99-118）：合并循环增
  第三数据源（gates 响应的 node_run / 事件时间排序键），与 comment/task 双源交错
- 同文件 `TaskExecutionCard`：`task.cr_id` 非空且该 CR 有活跃门禁 → 卡头迷你门禁条
  （点击滚动定位到对应 CrGateCard）
- mutation：`approveCr` 提交带 `evidence_digest`（取自 gates 响应）——
  409 EVIDENCE_DRIFT → 呈现 expected/current 指纹 + 「证据已变更，请刷新后重审」；
  403 → FORBIDDEN_APPROVER / human-actor 原因文案；成功 → invalidate projectGates

## 实现要点
- 排序键沿既有合并循环的 `at → key` 约定，门禁项取 node_run started_at（无 node_run 时取
  cr 投影 updated_at）。
- 驳回 reason 必填校验在前端 + 服务端双侧（reject_reason 注入 review_feedback 是治理语义，
  空 reason 无意义）。
- 文案入 T05 建立的 `projects.json#governance` 袋，四语齐。
- 单测/Storybook：三变体渲染；can_approve=false 无按钮；409/403 分支；pending_advance 态；
  迷你条定位滚动。

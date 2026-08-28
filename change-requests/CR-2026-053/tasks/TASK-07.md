---
id: CR-2026-053-TASK-07
type: TASK
cr-ref: CR-2026-053
plan-ref: "change-requests/CR-2026-053/plan.md"
sdd-ref: "change-requests/CR-2026-053/sdd.md"
title: 前端审批卡可见性修复
slug: approval-card-visibility-fix
status: pending
estimate: 3h
depends-on: [CR-2026-053-TASK-05]
created: 2026-08-28T11:20:00+08:00
---

## 任务描述

修复前端审批卡可见性：
1. 从 `CrGateCard` 提取 `ApprovalCard` 为独立组件
2. 修改 `project-team-agent-chat.tsx` 渲染规则：
   - `cr.pending_stage` 非空时直接渲染唯一 `ApprovalCard`
   - 保留历史节点渲染

## 涉及文件 / 模块

- `packages/views/projects/components/cr-gate-card.tsx`
- `packages/views/projects/components/project-team-agent-chat.tsx`

## 实现要点

参考 SDD §4.3 (FR-B6):
- `pending_stage` 非空即渲染 ApprovalCard（当前卡）
- `gate_nodes` 循环中跳过当前 `human_approval/running` 节点
- 保留历史 blocked card 与历史节点
- gates API schema 不变

## 验收条件

1. `pnpm test packages/views/projects/components/` 覆盖 AC-C1~C6 且通过
2. `pending_stage` 非空时审批卡可见，为空时不渲染当前审批卡
3. 历史节点仍正常显示

## 完成标志

- 前端组件修改已 commit
- E2E 测试通过

## 接口契约

**消费**:
- `/api/projects/{id}/gates` 响应（不变）

**产出**:
- `ApprovalCard` 组件渲染当前审批信息

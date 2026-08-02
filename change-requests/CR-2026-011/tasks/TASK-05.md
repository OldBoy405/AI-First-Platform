---
id: CR-2026-011-TASK-05
type: TASK
cr-ref: CR-2026-011
plan-ref: "change-requests/CR-2026-011/plan.md"
sdd-ref: "change-requests/CR-2026-011/sdd.md"
title: 前端 client 层 + cr:updated 接线 + CrStatusBadge + 四语文案
slug: client-layer-badge
status: pending
estimate: 4h
depends-on: [CR-2026-011-TASK-01]
assignee: ""
created: "2026-08-02T12:40:00+08:00"
---

## 任务描述
落地 SDD §5.1/§5.3/§5.4 + DD-6/DD-7/DD-8：审批/门禁的前端 client 层（全新——审批 API 至今
零前端调用方）、`cr:updated` 前端半边补齐、chatHeader 位置的 16 态徽标、四语文案。

## 涉及文件
- `packages/core`：api `getProjectGates(projectId)` / `approveCr(wid, crId, body)`；
  query key 根 `projectGates(projectId)`
- `packages/core/types/events.ts`：`WSEventType` union 增 `cr:updated` +
  `WSEventPayloadMap` 增 `{cr_id, status, needs_reconcile}`（:11-79 / :393+）
- `packages/core/realtime/use-realtime-sync.ts`：增 `cr:updated` handler → invalidate
  `projectGates` 根（handled 列表 :600-616 + handler 区）
- `packages/views/projects/components/`（新 `cr-status-badge.tsx`）：模式 TabsList 右侧
  （project-chat-panel.tsx:74-93）；16 态文本 + P0 §4.1 七桶配色；多 CR popover
  （DD-7：显示 `updated_at` 最新的非终态 CR，popover 全列）；只读无操作
- `packages/views/locales/{en,ja,ko,zh-Hans}/projects.json`：新 `governance` 子袋
  （16 态名 ×4 语、徽标/popover/后续 T06 卡片文案统一入此袋）

## 实现要点
- **DD-8 降级**：gates 请求 404（APPROVAL_SIGNING_KEY 未配置，路由整组未挂载）→ query 标记
  disabled，徽标与门禁 UI 整体不渲染、不重试、不报错；单测覆盖该分支。
- 失效策略：workspace 级广播 + 按 projectGates 根失效即可（事件频度极低，不做 payload 细分）。
- parity 测试全绿（新 key 四语齐；勿留空对象——空对象在 parity 中零 key 会挂）。
- 单测：badge 16 态渲染快照；多 CR 取值规则（updated_at 排序）；404 降级分支。

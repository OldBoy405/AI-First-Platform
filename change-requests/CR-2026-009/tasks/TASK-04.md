---
id: CR-2026-009-TASK-04
type: TASK
cr-ref: CR-2026-009
plan-ref: "change-requests/CR-2026-009/plan.md"
sdd-ref: "change-requests/CR-2026-009/sdd.md"
title: inbox 容器起源跳转条（project_chat / project_discussion 共用）
slug: inbox-container-jump-banner
status: pending
estimate: 2h
depends-on: [CR-2026-009-TASK-01]
assignee: ""
created: "2026-08-02T11:55:00+08:00"
---

## 任务描述
落地 SDD §5.2 / DD-8：@提及通知的 inbox 落点现状是隐藏容器 Issue 的裸预览；加「前往项目聊天」
跳转条满足 PRD AC-2（"可点击跳转到该讨论"），CR-A 的 team-agent 提及通知顺带受益。

## 涉及文件
- `packages/views/inbox/components/`（预览侧组件）：所选 item 的 issue
  `origin_type ∈ {project_chat, project_discussion}` 时，预览顶部渲染跳转条，链接
  项目页 `?tab=chat&mode={team_agent|discussion}`（mode 按 origin_type 映射）
- `packages/views/locales/`：跳转条文案四语

## 实现要点
- issue 详情数据 inbox 预览已在取（含 origin_type/project_id），纯渲染分支，非容器 item 零路径变化。
- `?mode=` 深链的接收端由 T03 落地，本任务只负责链接生成。

## 验收条件
1. 组件测试：container-origin item 渲染跳转条且 href 正确（两种 origin 各一例）；普通 item 不渲染。
2. 真机：Discussion 中 @成员 → inbox item → 点击跳转条落 Discussion tab（可并入 T05 AC-2 场景）。

## 完成标志
组件测试 + parity + lint 全绿。

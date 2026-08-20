---
spec-id: ai-first-platform
version: "0.21"
id: CR-2026-047-TASK-09
type: TASK
cr-ref: CR-2026-047
plan-ref: "change-requests/CR-2026-047/plan.md"
sdd-ref: "change-requests/CR-2026-047/sdd.md"
title: 前端看板（三件式复用、观察期无雷达、定义页、Web/Desktop 接线）
slug: dashboard-maturity-views
status: pending
estimate: 20h
depends-on: ["CR-2026-047-TASK-08", "CR-2026-047-TASK-10"]
created: 2026-08-20T01:30:00+08:00
---

# TASK-09 前端看板

## 任务描述

按 SDD §1.1/§3.5/§6（FR-9/10/13/16/18/22/23）实现 E2 看板页面：趋势/排名/治理三板块 + “AI 原生组织建议”最新/历史/追问区。观察期只渲染三件式、无雷达图；数量指标与质量护栏同屏；定义页公开 v1 口径与可刷性；页脚反 Goodhart 声明。复用既有 sibling 组件和 Team Agent 对话路由，不新建独立通路。

## 涉及文件 / 模块

- `packages/views/dashboard/maturity/`（新建目录：主页面、板块组件、建议最新/历史面板、定义页、测试）
- `packages/views` 共享 route 注册 + Web/Desktop 平台接线（沿既有 dashboard 接线模式，无 iframe/新域名）
- 复用（不复制）：`packages/views/dashboard/components/{dim-segmented,usage-trend-card,leaderboard}` 三件式

## 实现要点

- 数据：全部走 TASK-08 client 方法；TanStack Query，query key 必含 `workspaceId`。
- 头部：范围/Owner mode/“每日 00:30 更新前一日”/成员数/Token 总量/成本（`cost_status` 四态渲染：authoritative/mixed/estimated/unavailable，unknown 显示“估算不可用”而非 0）。
- 排名：仅 `scope=project`；metric 选择器含 8 raw + total；观察期默认 raw；`total` 且 scores 空显示 unavailable 空态；无任何 user 入口（route、DOM、组件均不得出现）。
- 治理板块：恒渲染 5 卡 6 字段（P50/P90 合一卡），`unavailable` 显示“未测量/数据通道待 CR-C”，不得显示 0，不得影响总分展示。
- 观察期（`observation.active`）：无雷达图，仅三件式；`calibration_status` 与 config_rev 断点（跨 `config_rev` 的趋势图断点标记）。
- 定义页：8 项口径（v1 member 定义、Token 四列口径、EPC/Team Agent/流程完整率定义）与已知可刷性说明；页脚“Token 为行为数据非绩效”。
- 建议区消费 `getMaturitySuggestions()` 与 `getMaturitySuggestionHistory()`：最新报告渲染 markdown；历史按 ISO week 降序、cursor 加载更多；无报告 200 empty；重复 report_key 只展示 API 去重后的最新版。若 Org Admin 未初始化，Owner/Admin 可选本 workspace runtime 并调用 TASK-10 `ensureOrgAdminWorkspace(workspaceId,runtimeId)`；普通成员只看 unavailable。每条报告的“追问”按钮调用 `useWorkspacePaths().chat()` 并导航到 `${wsPaths.chat()}?session=${report.chat_session_id}`（既有 `packages/views/chat/chat-page.tsx` URL→store 深链合同），不复制 chat UI/上下文。
- loading/empty/error/unavailable 四态组件测试。

## 验收条件

1. component 测试：loading/empty/error/unavailable 全渲染；observing fixture 断言无雷达图组件；cost_status 四态文案正确。
2. 排名 fixture：项目排名无个人入口；`metric=total` 空 scores 显示 unavailable。
3. route/DOM 断言：页面与组件树无 user ranking 相关 id/文案/开关；Web 与 Desktop route smoke test 通过（复用 views，无 iframe）。
4. 跨 config_rev 趋势图出现断点标记。
5. suggestions/history fixture：最新与历史按 ISO week 排序、同 report_key 只一项、empty/error 可见；点击“追问”跳转携带原 `chat_session_id`，连续两轮消息仍命中同一 session（AC-20/AC-21）。
6. Org Admin 未初始化 fixture：Owner/Admin 看 runtime 选择+初始化动作并调用 TASK-10 client；普通成员不见按钮；成功后刷新 suggestions query。

## 完成标志

views 测试全绿 + route smoke test 通过；`packages/core` schema/client 消费无告警。

## 接口契约

- 消费（TASK-08）：`packages/core/api/client.ts` 六个 maturity GET 方法，尤其 `getMaturitySuggestions(workspaceId)`、`getMaturitySuggestionHistory(workspaceId,{limit,cursor})`；zod 类型 `SuggestionResponse/SuggestionHistoryResponse/MaturityReport`。消费（TASK-10）：`ensureOrgAdminWorkspace(workspaceId:string,runtimeId:string): Promise<OrgAdminResponse>`。
- 产出：`packages/views/dashboard/maturity/` 主页面、`MaturitySuggestionsPanel`、`MaturitySuggestionHistory` 与共享 route（供 TASK-11 UI 矩阵验证）；追问路径合同=`${useWorkspacePaths().chat()}?session=${report.chat_session_id}`，无新 chat 接口。

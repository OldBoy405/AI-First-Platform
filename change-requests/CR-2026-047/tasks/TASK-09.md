---
id: CR-2026-047-TASK-09
type: TASK
cr-ref: CR-2026-047
plan-ref: "change-requests/CR-2026-047/plan.md"
sdd-ref: "change-requests/CR-2026-047/sdd.md"
title: 前端看板（三件式复用、观察期无雷达、定义页、Web/Desktop 接线）
slug: dashboard-maturity-views
status: pending
estimate: 20h
depends-on: ["CR-2026-047-TASK-08"]
created: 2026-08-20T01:30:00+08:00
---

# TASK-09 前端看板

## 任务描述

按 SDD §1.1/§6（FR-9/10/13/16/18）实现 E2 看板页面：趋势/排名/治理三板块，观察期只渲染三件式、无雷达图；数量指标与质量护栏同屏；定义页公开 v1 口径与可刷性；页脚反 Goodhart 声明。复用既有 sibling 组件，不新建独立通路。

## 涉及文件 / 模块

- `packages/views/dashboard/maturity/`（新建目录：主页面、板块组件、定义页、测试）
- `packages/views` 共享 route 注册 + Web/Desktop 平台接线（沿既有 dashboard 接线模式，无 iframe/新域名）
- 复用（不复制）：`packages/views/dashboard/components/{dim-segmented,usage-trend-card,leaderboard}` 三件式

## 实现要点

- 数据：全部走 TASK-08 client 方法；TanStack Query，query key 必含 `workspaceId`。
- 头部：范围/Owner mode/“每日 00:30 更新前一日”/成员数/Token 总量/成本（`cost_status` 四态渲染：authoritative/mixed/estimated/unavailable，unknown 显示“估算不可用”而非 0）。
- 排名：仅 `scope=project`；metric 选择器含 8 raw + total；观察期默认 raw；`total` 且 scores 空显示 unavailable 空态；无任何 user 入口（route、DOM、组件均不得出现）。
- 治理板块：恒渲染 5 卡 6 字段（P50/P90 合一卡），`unavailable` 显示“未测量/数据通道待 CR-C”，不得显示 0，不得影响总分展示。
- 观察期（`observation.active`）：无雷达图，仅三件式；`calibration_status` 与 config_rev 断点（跨 `config_rev` 的趋势图断点标记）。
- 定义页：8 项口径（v1 member 定义、Token 四列口径、EPC/Team Agent/流程完整率定义）与已知可刷性说明；页脚“Token 为行为数据非绩效”。
- loading/empty/error/unavailable 四态组件测试。

## 验收条件

1. component 测试：loading/empty/error/unavailable 全渲染；observing fixture 断言无雷达图组件；cost_status 四态文案正确。
2. 排名 fixture：项目排名无个人入口；`metric=total` 空 scores 显示 unavailable。
3. route/DOM 断言：页面与组件树无 user ranking 相关 id/文案/开关；Web 与 Desktop route smoke test 通过（复用 views，无 iframe）。
4. 跨 config_rev 趋势图出现断点标记。

## 完成标志

views 测试全绿 + route smoke test 通过；`packages/core` schema/client 消费无告警。

## 接口契约

- 消费（TASK-08）：`packages/core` 6 个 client 方法与 zod schema（`MaturityOverallResponse` 等）。
- 产出：`packages/views/dashboard/maturity/` 组件与 route（供 TASK-11 UI 矩阵验证）；无下游代码消费方。

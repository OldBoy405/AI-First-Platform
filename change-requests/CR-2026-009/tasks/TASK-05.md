---
id: CR-2026-009-TASK-05
type: TASK
cr-ref: CR-2026-009
plan-ref: "change-requests/CR-2026-009/plan.md"
sdd-ref: "change-requests/CR-2026-009/sdd.md"
title: 端到端验收（AC-1~7）+ 回归
slug: e2e-acceptance
status: pending
estimate: 4h
depends-on: [CR-2026-009-TASK-02, CR-2026-009-TASK-03, CR-2026-009-TASK-04]
assignee: ""
created: "2026-08-02T11:55:00+08:00"
---

## 任务描述
按 SDD §9 的验证方式逐条走 PRD AC-1~7，结果写入 test-report.md。

## 验收条件（即 PRD AC，验证方式见 SDD §9）
1. **AC-1** 双浏览器双成员：A 发 B 实时上屏；刷新全量回放。
2. **AC-2** @成员 → inbox item → 跳转条 → 落 Discussion tab 对应讨论。
3. **AC-3（红线）** 发多条消息（含 @Agent 正文）→ `agent_task_queue` 零增量（SELECT 前后核对）；普通 Issue 页 @agent 正常入队（豁免不外溢）。
4. **AC-4（红线）** 逐入口核对容器隐藏（列表/看板/泳道/甘特/my-issues/全局搜索含 comment 子查询/项目统计数）；与 team-agent-chat 容器并存；重复进入不重复创建（SELECT 容器唯一）。
5. **AC-5** 输入区形态目视核对；草稿切 tab/刷新保留且与 Team Agent 面互不串扰。
6. **AC-6** locale parity；Team Agent 面收发、Issue 页评论 @提及入队、浮窗/全页 chat 回归。
7. **AC-7** FR-6 裁剪留痕核对（SDD §6.3 + 评审记录），无实现项。

## 完成标志
test-report.md 覆盖 AC-1~7 全部结论（含红线两条的 DB 级证据）+ 回归项全绿。

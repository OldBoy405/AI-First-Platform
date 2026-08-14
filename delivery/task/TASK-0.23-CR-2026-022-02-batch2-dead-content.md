---
spec-id: ai-first-platform
version: "0.23"
id: CR-2026-022-TASK-02
type: TASK
cr-ref: CR-2026-022
plan-ref: "change-requests/CR-2026-022/plan.md"
sdd-ref: "change-requests/CR-2026-022/sdd.md"
title: 批 2 — 死内容清理（cr-status-set 下线 + validate-doc/focus-briefing/record-adr 等）（FR-4~8）
slug: batch2-dead-content
status: pending
estimate: 6h
depends-on: [CR-2026-022-TASK-01]
assignee: ""
created: "2026-08-06T08:30:00+08:00"
---

## 任务描述

批 2 死内容清理：删除/订正无消费者的废弃产物与失实声明。删除前必须先核实无外部读者（纪律：删前引用计数）。

## 涉及文件 / 模块

- FR-4：删 `skills/cr/cr-status-set/SKILL.md` 整文件 + `skills/_index.yml` 对应条目；`skills/_index.yml` cr-review-record brief 改「经 crctl advance 推进」（先 grep 全仓 `cr-status-set` 引用，除 lint R3 黑名单定义外清零后才删）
- FR-5：`skills/shared/validate-doc/SKILL.md` 删维度 2「gate 合规性」（无排期背书不留）；删 writeback-* 写入后「自动调用本 Skill」声明
- FR-6：`skills/planning/focus-briefing/SKILL.md` 竞品过滤改为 write-competitive-report 写索引补 `status: new`、消费后翻 `seen`（**不要直接去掉过滤**）；pipeline 注册表数据源向运行时确认真实路径，确认不了整体删该数据源
- FR-7：`skills/competitive/report-to-planning-suggestion/SKILL.md` 补「目标运行时未提供 brainstorming 时直接委托 planning-draft」降级路径（**不移除 external delegate**）；`agents/_index.yml` 5 处 `pending` 清空为 `[]`（保留键）
- FR-8：`skills/planning/record-adr/SKILL.md` + `constraints/adrs.yml` 删前核实全仓零读者（grep 引用计数 + 前端/agent 读取面），核实记录入任务证据后删除

## 实现要点

1. 每项删除先 grep 坐实引用面，把 grep 结果写进 commit message 或任务注释
2. focus-briefing 的 status 翻转：write-competitive-report 写 `status: new` 是生产者侧改动（与 FR-17 同文件，注意顺序，先看该文件现状）
3. agents/_index.yml 只清 `pending:` 值，不动 capabilities/consumers

## 验收条件

1. `grep -r "cr-status-set"` 全仓仅剩 lint R3 黑名单定义与历史设计文档（docs/漂移治理.md、漂移治理_v2.md、二开修改报告_v2.html——记录 crctl 取代前的设计史，不修改）；skills/matrix/agents/指南文档零引用
2. validate-doc 无「gate 合规性」维度、无 writeback 自动调用声明
3. focus-briefing 保留 `status=new` 过滤且 write-competitive-report 会写该字段；消费翻转 seen 已落地
4. record-adr/adrs.yml 删除有"无读者"核实证据（constraints/adrs.yml 全仓 grep 仅自身写入清单提及）
5. `agents/_index.yml` 所有 `pending:` 为 `[]` 且键存在

## 完成标志

验收 1~5 通过 + `check-skill-matrix.mjs` 不报缺引用 + lint 复扫零违例。

---
id: CR-2026-002-TASK-11
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: 端到端验收串联（AC-1..7 冒烟 + 证据记录）
status: pending
estimate: 8h
depends-on: [CR-2026-002-TASK-05, CR-2026-002-TASK-06, CR-2026-002-TASK-07, CR-2026-002-TASK-08, CR-2026-002-TASK-09, CR-2026-002-TASK-10]
assignee: ""
created: "2026-07-31T09:30:00+08:00"
---

## 任务描述
全链路验收：用一个真实测试 CR（或本 CR 自身）在本机全栈（Docker 三容器 + daemon + crctl）串联跑通 AC-1..7 的端到端半边，逐条记录证据（命令、输出摘要、时间戳），为 write-test-report 提供输入。

## 涉及文件
- 无新代码（验收动作）；证据记录到本文件完成记录 + 后续 test-report.md
- 发现缺陷 → 回对应 TASK 修复后复跑

## 实现要点
- 串联剧本：断网 advance（AC-1）→ 联网补传+投影+WS（AC-2）→ 手工篡改投影自愈（AC-3）→ 无 TTY grant 审批全链（AC-4①）→ Agent 任务内越权三连（AC-5①②③）→ activity_log 两类行（AC-6/AC-7③）→ TTY 篡改检出（AC-7）。
- 与 M0 冒烟同一套结果标记约定（Issue 或命令输出留痕均可）。

## 验收条件
1. AC-1..7 每条至少一次端到端通过记录（单测覆盖的子项引用对应 TASK 测试结果）。
2. 全程无绕过 crctl 手改权威文件（审计可查）。

## 完成标志
七条 AC 证据链完整 + 完成记录回填 → 进入 write-test-report。

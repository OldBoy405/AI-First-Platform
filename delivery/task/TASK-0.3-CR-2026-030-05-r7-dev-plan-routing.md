---
spec-id: ai-first-platform
version: "0.3"
id: CR-2026-030-TASK-05
type: TASK
cr-ref: CR-2026-030
plan-ref: "change-requests/CR-2026-030/plan.md"
sdd-ref: "change-requests/CR-2026-030/sdd.md"
title: 实现 R7 权威字面量校验与开发计划三路契约
slug: r7-dev-plan-routing
status: pending
estimate: 8h
depends-on: [CR-2026-030-TASK-04]
created: "2026-08-11T02:34:00+08:00"
---

# TASK-05 实现 R7 权威字面量校验与开发计划三路契约

## 1. 任务描述

落实 SDD §3.8～§3.9、§4.11～§4.12：R7 直接严格解析 `dir-graph.yaml#change-request-track.state_machine.transitions` 并校验静态 `(to, trigger)` pair；`review-dev-plan` 持有 NORMAL/UPSTREAM 两条精确 advance，Pipeline 仅保留 PASS/NORMAL/UPSTREAM 路由和 replay。

## 2. 涉及文件 / 模块

- tools：`skills/shared/crctl/scripts/lint-prompts.mjs`
- tools：`skills/shared/crctl/scripts/test/lint-prompts.test.mjs`
- tools：`skills/shared/crctl/scripts/test/crctl.test.mjs`
- tools：`skills/develop/review-dev-plan/SKILL.md`
- tools：`pipeline-templates/code-implementation.pipeline.json`

## 3. 实现要点

- strict loader 规范化 CRLF，逐条解析全部声明；缺失、空、截断或任一畸形均 `STATE_MACHINE_PARSE_FAILED`。
- 静态 pair 必须同时匹配 `to` 与完整 trigger；仅当 to/trigger 含模板变量时跳过字面量检查。
- NORMAL 固定 `review-dev-plan:block -> write-dev-plan`；UPSTREAM 固定 `review-dev-plan:upstream-design-blocker`。
- Skill 是两条 advance 的唯一 Prompt 所有者；Pipeline 不复制具体命令，只定义 route/replay/abort，节点数不变。
- PASS 保持 `task-breakdown`；NORMAL attempt 递增并重放三节点；UPSTREAM 不增加 NORMAL attempt 且停止自动重放。

## 4. 验收条件

1. 完整 authority pair 通过，短 trigger 与 to/trigger 错配均命中 R7 `CONTRADICTS`。
2. LF/CRLF 结果一致；缺失、空、截断、畸形 transitions 均 hard fail。
3. PASS/NORMAL/UPSTREAM 黑盒结果、状态和 attempt 记账符合 SDD AC-23～AC-26。
4. `review-dev-plan/SKILL.md` 恰含两条具体 advance；code pipeline 不含这两条命令且节点数保持。

## 5. 完成标志

R7 与 dev-plan 路由定向测试全部通过，短 trigger 同时被 lint/runtime 拒绝，`tasks/_index.yml` 中 TASK-05 标记 `done`。

## 6. 接口契约

- **消费**：`dir-graph.yaml#change-request-track.state_machine.transitions` 的 `{from,to,trigger}` 声明。
- **产出**：strict transition loader 返回非空 authority pair 集；错误 `STATE_MACHINE_PARSE_FAILED`/R7 `CONTRADICTS`；review 结果 `{verdict, route, repairTarget, currentAttempt}`。

---
spec-id: ai-first-platform
version: "0.20.6"
id: CR-2026-045-TASK-11
type: TASK
cr-ref: CR-2026-045
plan-ref: "change-requests/CR-2026-045/plan.md"
sdd-ref: "change-requests/CR-2026-045/sdd.md"
title: 五节点 E2E 纵切、手动回归与 CUSTOM 台账
slug: e2e-slice-manual-regression-custom-ledger
status: pending
estimate: 8h
depends-on:
  - CR-2026-045-TASK-02
  - CR-2026-045-TASK-03
  - CR-2026-045-TASK-04
  - CR-2026-045-TASK-05
  - CR-2026-045-TASK-06
  - CR-2026-045-TASK-07
  - CR-2026-045-TASK-08
  - CR-2026-045-TASK-09
  - CR-2026-045-TASK-10
created: 2026-08-17T20:39:31+08:00
---

# TASK-11 五节点 E2E 纵切、手动回归与 CUSTOM 台账

## 1. 任务描述

端到端验证固定 `architecture-design` 五节点纵切：write → review(block→repair→pass) → human_approval → approve → push-progress，覆盖 AC-04~AC-10 完整链；同时验证 Runner feature off 时手动路线回归（AC-15）、模块职责边界静态检查（AC-16）与零新增框架（AC-17），并按 Multica 纪律登记 CUSTOM.md 台账。

## 2. 涉及文件 / 模块

- `server/internal/governance/runner_e2e_test.go`（新增，真实 PostgreSQL + 真实 crctl 深原语 fixture）
- tools 侧手动 architecture Pipeline 回归证据（Runner 未启动时行为不变）
- `CUSTOM.md`（Multica 仓库根目录；对照实际结构做本 CR 最终对账，编号顺延，原因含 CR-2026-045 与 TASK）

## 3. 实现要点

- E2E fixture 复用既有 crosscheck 模式：真实 crctl review/approve/checkpoint 深原语 + 签名 grant（需 `APPROVAL_SIGNING_KEY` + 真实 `CRCTL_PATH`），验证 Runner 只调度、不签名不写受控文件。
- 覆盖 block→repair→pass 全链、reject 回退、checkpoint `phase=complete` 后 run completed、checkpoint 故障重跑不重执行设计/review/审批。
- 手动回归：Runner feature off 时，现有 write→review→人工审批→approve→push-progress 手动路线逐节点通过。
- 静态检查：Agent/Pipeline/Skill/crctl/脚本/README 遵守 PRD §2.2 职责边界（AC-16）；生产依赖/运行表/模板表/消息总线/通用 DSL/事务框架新增数量 0（AC-17）。
- CUSTOM.md：对照 Multica 实际结构逐条登记新增文件、迁移、生成物与 AIFIRST 挂钩点，标注上游改动时的贴回/核对策略。

## 4. 验收条件

1. E2E 五节点全链在真实 PostgreSQL 下 `=== RUN`/`--- PASS`，无 TestMain skip 假绿；block/repair/pass、reject、checkpoint 均覆盖。
2. 手动路线回归通过（AC-15）；模块职责边界与零新增框架静态检查通过（AC-16/AC-17）。
3. Multica 各代码 TASK 已在完成时登记根目录 `CUSTOM.md`，本 TASK 对所有条目做最终对账（新文件、迁移撞号、生成物、上游核对策略），且 `CUSTOM.md` 现状为唯一事实源。

## 5. 完成标志

E2E 纵切 + 手动回归 + 职责边界检查 + CUSTOM 台账全部通过。

## 6. 接口契约

- 消费：TASK-02~TASK-10 全部产出（registry、索引、runner、carrier、唤醒、parity、outbox）。
- 产出：`runner_e2e_test.go` 全链证据、手动路线回归证据、CUSTOM.md 台账条目；本 CR 代码评审（review-code）据此取证。

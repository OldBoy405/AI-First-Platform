---
id: CR-2026-049-TASK-13
type: TASK
cr-ref: CR-2026-049
plan-ref: "change-requests/CR-2026-049/plan.md"
sdd-ref: "change-requests/CR-2026-049/sdd.md"
title: CUSTOM.md 台账与 AC 集成收尾
slug: custom-md-ledger-ac-integration
status: pending
estimate: 8h
depends-on: [CR-2026-049-TASK-03, CR-2026-049-TASK-12]
created: 2026-08-20T20:59:46+08:00
---

# TASK-13 — CUSTOM.md 台账与 AC 集成收尾

## 1. 任务描述

按 multica 现状结构登记 `CUSTOM.md` 台账（编号顺延、原因含 `CR-2026-049` 与 TASK 号）；补齐 AC-1~AC-15 收尾测试（跨语言 golden、静态 contract、迁移 registry、E2E 冒烟）；执行 plan §5 发布 checklist 并记录结果。

## 2. 涉及文件 / 模块

- `CUSTOM.md`（multica，对照当时实际结构登记）
- 跨语言 golden：Go `yaml.v3` 解析同一 traceability 与 Node 事件 payload 深比较
- 静态 contract 测试（grep）：`cr_sync_event` join/conflict 必带 workspace；无 `spec_trace` 表；无 select-before-insert
- E2E 冒烟：三仓真实 baseline、健康态、trace 端到端

## 3. 实现要点

- CUSTOM.md：覆盖本 CR 新增迁移 385–397、governance trace 分支、commitprefix/drift/scheduler 新包、前端 schemas/views；`// AIFIRST:` 注释点齐全。
- 冒烟走 `crctl workspace inspect` 权威 worktree；E2E 只读不伪造审批。
- 发布 checklist 输出到本 CR 目录 `test-report` 素材（不进受控账本）。

## 4. 验收条件

1. CUSTOM.md 台账行与 git diff 一一对应（文件清单脚本比对零遗漏）。
2. `go test ./...`（受影响包）+ tools `node --test` + frontend `vitest/eslint` 全绿。
3. 冒烟：真实三仓 baseline 成功、治理板块健康态正确、trace 事件端到端仅一行且 processed。

## 5. 完成标志

全量测试绿；发布 checklist 六项全部满足并留证。

## 6. 接口契约

- 消费：TASK-03 的 `ARCHIVE_TRACE_PENDING` 语义、TASK-12 的 views 路由、其余全部 TASK 的产物。
- 产出：`CUSTOM.md` 台账行；AC 收尾测试与冒烟记录（供 code 评审与 write-test-report 消费）。

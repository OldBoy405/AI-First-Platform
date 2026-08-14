---
id: CR-2026-027-TASK-10
type: TASK
cr-ref: CR-2026-027
plan-ref: "change-requests/CR-2026-027/plan.md"
sdd-ref: "change-requests/CR-2026-027/sdd.md"
title: 五项最小验证全绿 + AC 全量核对（含 bootstrap-base-sha 断言）
slug: final-five-minimal-checks
status: pending
estimate: 4h
depends-on:
  - "CR-2026-027-TASK-02"
  - "CR-2026-027-TASK-03"
  - "CR-2026-027-TASK-04"
  - "CR-2026-027-TASK-05"
  - "CR-2026-027-TASK-06"
  - "CR-2026-027-TASK-07"
  - "CR-2026-027-TASK-08"
  - "CR-2026-027-TASK-09"
created: "2026-08-09T23:35:00+08:00"
---

# TASK-10 — 五项最小验证与 AC 全量核对（FR-14）

## 任务描述

按 v2 方案 §6.6 的五项最小验证清单收尾，逐条核对 PRD AC-1~AC-23 的可执行项（含 bootstrap-base-sha 断言），确认无回归、无旁路、无新依赖。

## 涉及文件 / 模块

- 无新代码改动（验证与核对产出：验证结果记录 + 必要时修订性提交）

## 实现要点（SDD §7.2）

1. `git diff --check`：workspace 与 tools worktree 的待合入变更零空白/行尾告警
2. `JSON.parse(pipeline-templates/feature-writeback.pipeline.json)` 通过（未被本 CR 触及但按清单校验）
3. `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全绿（含 TASK-03~08 新增向量）
4. `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` 零发现（TASK-08/09 改过 prompt）
5. 两项 grep 清零（按 AC-1 判定方式）：
   - tools 隐藏特例：`merge-feature-branch` 无 tools 硬编码分支
   - 25/47「现状」表述：workspace 根 + tools 包无违规命中（历史注脚除外）

## 验收条件（对应 AC 全量核对）

1. AC-1/AC-2/AC-3/AC-6/AC-7：Phase 0 文档项（TASK-01/02 产出复核）
2. AC-8~AC-10：approve 原子化（TASK-03 产出复核）
3. AC-11~AC-13：TASK 门禁（TASK-04 产出复核）
4. AC-14：`migrate-backlog` 幽灵清理（TASK-05 产出复核；主工作区已清理）
5. AC-15/AC-16：archive 原子化 + inbox-emit（TASK-06/07 产出复核）
6. AC-17：终态查询（TASK-07 产出复核）
7. AC-18：review-record 输出（TASK-08 产出复核）
8. AC-19：五项最小验证全部通过（本 TASK）
9. AC-20：无新增第三方依赖/公共 Runner 库/新子命令（import 语句只含 `node:*`；crctl.mjs 仍单文件）
10. AC-21：历史 CR 查询/归档行为兼容（026 归档实景回放或等价用例）
11. AC-22：tools worktree 存在；`bootstrap-base-sha` = 记录值；custom/main 无本 CR 直接提交；tools merge-commits 与 docs/multica 同批（merge 阶段复核）
12. AC-23：复核 TASK-07/08 的 task-breakdown normal/upstream/exhausted、tech-design freshness 与 post-PASS cycle=2/attempt=1，旧 attempts 保留

## 完成标志

五项验证全绿；AC-1~AC-23 核对表完成并随本 TASK 记录；无遗留 blocker。

## 接口契约

- 消费：TASK-01~09 全部产出（tools worktree、crctl.mjs、测试、SKILL.md、ARCHITECTURE.md、bootstrap-base-sha）
- 产出：验证结果记录（TASK 完成标志），供 code review 与测试报告引用

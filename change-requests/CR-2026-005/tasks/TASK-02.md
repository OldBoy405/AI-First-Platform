---
id: CR-2026-005-TASK-02
type: TASK
cr-ref: CR-2026-005
plan-ref: "change-requests/CR-2026-005/plan.md"
sdd-ref: "change-requests/CR-2026-005/sdd.md"
title: 端到端验收（AC-1~5）
status: done
estimate: 3h
depends-on: [CR-2026-005-TASK-01]
assignee: ""
created: "2026-08-01T15:25:00+08:00"
---

## 任务描述
在 TASK-01 实现基础上，完整跑 PRD 五条 AC，证据记录到本文件完成记录 + test-report.md。

## 涉及文件
- 无新代码（验收动作）

## 实现要点
- AC-2 是本 CR 的核心场景（复现原故障），需要构造一个"tasks/_index.yml 有 done 任务但全局索引缺对应行"的临时 fixture（可在临时目录或用一次性 CR-ID 造数，验收后清理，不污染真实 change-requests/ 与 delivery/task/）。
- AC-1 用真实的 CR-2026-001~004 只读复算，不修改任何真实文件。

## 验收条件
1. AC-1（正向）：CR-2026-001~004 重放 `deliveryIndexComplete` 均 `ok:true`，不误报。
2. AC-2（负向，复现故障）：fixture 场景下门禁 `ok:false`，错误详情列出缺失任务 id。
3. AC-3（skill 正向）：对 fixture 调用 `writeback-tasks` 后文件+索引齐备，随后门禁转 `ok:true`（自证闭环）。
4. AC-4（幂等）：重复调用 `writeback-tasks` 不产生重复索引行/文件覆盖异常。
5. AC-5（边界）：无 done 任务的 CR 与 `delivery/task/_index.yaml` 不存在两种场景分别验证不误报。

## 完成标志
五条 AC 证据记录 + 完成记录回填 → write-test-report。

## 完成记录（2026-08-01）

详见 `change-requests/CR-2026-005/test-report.md`。五条 AC 全绿，AC-1 真实数据重放过程中发现并修复一处 schema 假设错误（delivery/task/_index.yaml 顶层 `tasks:` 包裹键）。

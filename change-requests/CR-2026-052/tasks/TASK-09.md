---
id: CR-2026-052-TASK-09
type: TASK
cr-ref: CR-2026-052
plan-ref: "change-requests/CR-2026-052/plan.md"
sdd-ref: "change-requests/CR-2026-052/sdd.md"
title: "tools crctl.test.mjs：AC-11/AC-12 drift 去重测试"
slug: tools-drift-dedup-tests
status: pending
estimate: 4h
depends-on: ["CR-2026-052-TASK-08"]
created: 2026-08-27T10:44:32+08:00
---

# TASK-09：tools drift 去重测试

## 1. 任务描述

扩展 `skills/shared/crctl/scripts/test/crctl.test.mjs` 既有 drift 用例（:776），覆盖 PRD AC-11/AC-12。对应 SDD §7.4 tools 侧。

## 2. 涉及文件 / 模块

- 修改 `skills/shared/crctl/scripts/test/crctl.test.mjs`

## 3. 实现要点（SDD §7.4 / PRD AC-11/AC-12）

### AC-11（同漂移二次观测 → 文件恰 1、无 EMIT_FAILED）
- 构造同一漂移（同 cr、stage、expected/actual 摘要），连续两次观测（`detected_at` 不同）。
- 断言：outbox 中该 `dedup_name` 文件数 == 1；第二次返回幂等结果（无新写入、无异常抛出）；audit.log 无 `EMIT_FAILED`（event_kind=audit、trigger=evidence-drift）行。

### AC-12（删除后重观测 → 新文件按窗口计数；不误合并；内容真变化仍冲突）
- 漂移被采集删除后再观测 → 产生新文件，审计记录按观测窗口计数（保留既有语义）。
- 不同 CR 或不同摘要的漂移不因修复被误合并（`dedup_name` 生成与比较键确定性回归）。
- 同名文件内容真实变化（摘要 8 位截断碰撞等极端情形）仍冲突报错——确定性守卫不削弱（第三分支）。

用例须与 TASK-08 的 `comparable()` 修复一致：`detected_at` 不参与比较，摘要字段仍参与。

## 4. 验收条件

1. `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全 PASS（不含 pre-existing 无关失败：CR-2026-037 pipeline 采纳、archive-tx RED-7，与本改动无关，注明）。
2. AC-11/AC-12 三分支均有对应断言且方向正确。
3. 用例不依赖被采集端行为变化（纯 outbox 侧）。

## 5. 完成标志

测试落盘 + `node --test` 通过 + AC-11/12 可逐条回指（plan §5.1）。

## 6. 接口契约

- **消费**：TASK-08 的 `comparable()` 修复行为（剥离 `detected_at`）。
- **产出**：无生产接口。

---
id: CR-2026-058-TASK-06
type: TASK
cr-ref: CR-2026-058
plan-ref: "change-requests/CR-2026-058/plan.md"
sdd-ref: "change-requests/CR-2026-058/sdd.md"
target-version: 0.30
title: README 行 22/行 76 改写与静态文案断言（FR-5，AC-5）
slug: readme-guard-wording
status: pending
estimate: 3h
depends-on: [CR-2026-058-TASK-05]
created: 2026-09-01T16:50:00+08:00
---

## 1. 任务描述

目标：按 FR-5/AC-5 改写 tools 仓人读入口的 writeback 版本守卫表述：README 行 22/行 76 两处（SDD §4.7 已重核实际行文），并在 `crctl.test.mjs` 增加静态文案断言（README 禁止串零命中 + 「唯一更正入口」writeback 事务限定 + UNASSIGNED 文案区分）。

背景：README 现行表述「`--target-version` 与 `cr.md` 规范化全等才放行」与 FR-1 新判定表不符；「把 `unassigned` 更正为真实版本的唯一入口是 `crctl version-set`」需限定为 writeback 事务之外（回灌只发生在 writeback 事务内、只碰两账本）。README **不存在**「两侧须为真实版本且全等才放行」字面串（SDD §6.3 证据 7），改写对象是行 22/行 76 实际行文。

输入条件：TASK-01 已改写 `guardWritebackVersion` 的 `WRITEBACK_VERSION_UNASSIGNED` 文案（SDD §4.7 第三处）；TASK-05 已在 crctl.test.mjs 落静态断言框架。

## 2. 涉及文件 / 模块

- `README.md`（tools 仓根；行 22、行 76 两处）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`（新增 README 静态文案断言）

## 3. 实现要点

1. **README 行 22**：现行「`crctl writeback-apply` 在入口做版本守卫：`--target-version` 与 `cr.md` 规范化全等才放行，版本错误零 candidate/journal 痕迹」改为 FR-1 判定表语义：**「`crctl writeback-apply` 入口版本守卫：cr.md=`unassigned` 且输入为真实版本时放行并在 writeback 事务内原子回灌 authority 的 cr.md/_backlog 该条目的 target-version（冻结的 prd/sdd/plan/tasks 不动）；其余版本错误（两侧/输入侧 unassigned、两侧真实但不一致、任一侧规范化失败）零 candidate/journal 痕迹」**；同行「把 `unassigned` 更正为真实版本的唯一入口是 `crctl version-set`」加限定：**「writeback 事务之外」**——`version-set` 仍是唯一的非 writeback 更正入口（仍禁止 merging/writing-back、仍同步六类产物）；writeback 回灌只发生在 writeback 事务内、只碰两账本。
2. **README 行 76**：现行「`crctl writeback-apply` 的版本守卫保证版本错误在 candidate/journal 之前短路」保留，补一句回灌分支说明（与行 22 一致）；同行「唯一更正入口」同样加 writeback 事务限定。
3. **crctl.test.mjs 静态文案断言**（TASK-05 框架内追加）：
   - README 中禁止串零命中：`规范化全等才放行` / `两侧须为真实版本` 等旧表述（`git grep` 语义，读文件断言）零命中（测试夹具字符串除外）；
   - 行 22/行 76 新行文包含「writeback 事务」限定词与「回灌」语义；
   - `guardWritebackVersion` 的 UNASSIGNED 文案能区分两侧/输入侧 unassigned 与已放行回灌分支（TASK-01 已改，此处静态断言复核）。

## 4. 验收条件

1. `node --test --test-reporter=dot --test-skip-pattern "CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引" skills/shared/crctl/scripts/test/crctl.test.mjs` 通过（exit 0）：新增 README 静态断言全绿。
2. 静态核对：`grep -n "规范化全等才放行" README.md` 零命中（AC-5）；行 22/行 76 均含「writeback 事务」限定。
3. `git diff --name-only` 仅含 `README.md` 与 `crctl.test.mjs` 两个文件（本 TASK 边界）；writeback Skill 调用形态零改动（仍只传 `--target-version`，PRD FR-5）。

## 5. 完成标志

README 两处改写完成且静态断言全绿；`git grep` 在 tools 仓人读入口不再把「任一侧 unassigned 一律拒绝」写成现行规则；`_index.yml` 本 TASK 标 done。

## 6. 接口契约

- 消费：TASK-01 已改的 UNASSIGNED 文案（静态断言复核对象）；SDD §4.7 三处改写清单。
- 产出（供 TASK-07 消费）：README 新行文（AC-5 静态证据面）；crctl.test.mjs README 静态断言（cmd-01 证据面扩展）。

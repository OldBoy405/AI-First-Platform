---
spec-id: ai-first-platform
version: "0.26"
id: CR-2026-025-TASK-07
type: TASK
cr-ref: CR-2026-025
plan-ref: "change-requests/CR-2026-025/plan.md"
sdd-ref: "change-requests/CR-2026-025/sdd.md"
title: 全量验证关卡 + ARCHITECTURE.md 登记 + 溯源提交
slug: verify-register-ship
status: pending
estimate: 2h
depends-on: [CR-2026-025-TASK-06]
created: "2026-08-09T02:30:00+08:00"
---

## 1. 任务描述

执行 FR-22 验证关卡（三件套 + 三测试文件），AC-1~AC-23 逐条对照执行证据，按 FR-24 登记 `ARCHITECTURE.md`，按 FR-23 完成溯源提交（PRD 收尾节）。

## 2. 涉及文件

- 修改：`tools/ARCHITECTURE.md`（§8 已登记列表补本 CR 一条；§3 crctl 段若需补测试文件则同步）
- 只读验证：全部 TASK-01~06 产出文件

## 3. 实现要点

- FR-22 三件套：`check-skill-matrix.mjs` + `check-agents-contract.mjs` + `lint-prompts.mjs --mode enforce` 全绿；`node --test` 跑通 `crctl.test.mjs`、`lint-prompts.test.mjs`、`check-skill-matrix.test.mjs` 全部用例（AC-16）。
- AC-1~AC-23 逐条核对：AC-5/AC-18 以"024 批次一已合入（`18358df`）"为前提执行并在证据中注明。
- FR-24：`ARCHITECTURE.md` §8 补登记一条（crctl 命令面语义扩展：task done 守卫 / review-record 三账本 / next drafting 路由；check-skill-matrix 检查 4 + 新测试文件；合既有不变量不触 §5 判据）；`dir-graph.yaml` 无脚本级清单面（SDD §1.1 已实测），不改动。
- FR-23：提交只 add 本 CR 文件清单（NFR-9，禁 `git add -A`）；message 注明来源为方案 v2.6 §7（D-2/D-5）、CR-2026-024 SDD 评审实测与本 CR 需求/技术评审发现，含 CR-2026-025 编号；`grep -r "C:\\Users"` 在本 CR 改动中零命中（AC-17）。

## 4. 验收条件

1. AC-16：三件套全绿 + 三测试文件全部用例通过（命令输出留存为证据）。
2. AC-17：commit message 溯源齐全、本机绝对路径零命中、`ARCHITECTURE.md` §8 已登记。
3. AC-1~AC-15、AC-18~AC-23 逐条有对应 TASK 的测试/实跑证据引用，无遗漏条目。

## 5. 完成标志

验证关卡全绿 + AC 清单核对完毕 + 溯源提交落盘 + `_index.yml` 登记 done。

## 6. 接口契约

- 消费：TASK-01~06 全部产出（代码、测试、声明面、提示词终态）。
- 产出：本 CR 在 tools 仓的最终提交与验证证据集，供 write-test-report / review-code 引用。

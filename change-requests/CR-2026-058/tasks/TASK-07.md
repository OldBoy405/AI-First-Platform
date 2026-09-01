---
id: CR-2026-058-TASK-07
type: TASK
cr-ref: CR-2026-058
plan-ref: "change-requests/CR-2026-058/plan.md"
sdd-ref: "change-requests/CR-2026-058/sdd.md"
target-version: 0.30
title: 全量回归与测试报告（cmd-01～cmd-03）
slug: full-regression-test-report
status: pending
estimate: 5h
depends-on: [CR-2026-058-TASK-01, CR-2026-058-TASK-02, CR-2026-058-TASK-03, CR-2026-058-TASK-04, CR-2026-058-TASK-05, CR-2026-058-TASK-06]
created: 2026-09-01T16:50:00+08:00
---

## 1. 任务描述

目标：实施收敛点——按 plan.md §5.1 固定命令集运行 cmd-01～cmd-03（经 `crctl test` 机器区，`shell:false`），核对机器区 status=pass 与 skipped=false、覆盖矩阵 cmd-NN 与机器区 `commands` 下标全等，产出 `write-test-report`（`test-report.md`）落盘，并更新 `_context.md`。

背景：FR-16 要求 cmd-NN 稳定关联（机器区 commands 列表 1-based 下标 = `test-evidence/cmd-NN.log` 文件名）；基线红 BR-1/BR-2 按 plan.md §5.3 例外表逐条登记与 skip-pattern 排除；测试证据是本 CR AC-1～AC-6 的唯一/主要证据面。

输入条件：TASK-01～TASK-06 全部完成且各自验收通过；tools worktree 干净；覆盖矩阵（plan.md §6.1）已定稿。

## 2. 涉及文件 / 模块

- `change-requests/CR-2026-058/test-report.md`（knowledge-base CR worktree，write-test-report 落盘）
- `change-requests/CR-2026-058/_context.md`（run 收尾覆写，独立提交 `[cr] update context`）
- 证据目录：tools worktree `test-evidence/cmd-NN.log`（crctl test 机器区生成）

## 3. 实现要点

1. **命令集（plan.md §5.1 固定顺序，NN 与矩阵全等）**：
   - cmd-01：`node --test --test-reporter=dot --test-skip-pattern "CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引" skills/shared/crctl/scripts/test/crctl.test.mjs`
   - cmd-02：`node --test --test-reporter=dot skills/shared/crctl/scripts/test/writeback-tx.test.mjs`
   - cmd-03：`node --test --test-reporter=dot --test-skip-pattern "(CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引|TASK-01 RED-7：预存确定性 dedup 文件)" skills/shared/crctl/scripts/test/crctl.test.mjs skills/shared/crctl/scripts/test/writeback-tx.test.mjs skills/shared/crctl/scripts/test/archive-tx.test.mjs skills/shared/crctl/scripts/test/register-tx.test.mjs skills/shared/crctl/scripts/test/version-set.test.mjs skills/shared/crctl/scripts/test/test-cr.test.mjs`
   - cwd = tools CR worktree；skip-pattern 字面量必须包含用例全名；JSON 侧为独立 args 元素。
2. **机器区核对**：`crctl test` 输出机器区 `commands` 列表下标与 plan.md §6.1 矩阵 cmd-NN 全等；三命令 exit 0 且 `skipped=false`（dot reporter 下 FR-16 冻结模式表零命中，plan.md §5.3 判定规则 ①）。
3. **红计数核对**：BR-1/BR-2 之外无任何失败；例外表与 skip-pattern 字面量逐条全等（§5.3 判定规则 ②③）。
4. **test-report.md 落盘**：按 `write-test-report` Skill 结构——逐 AC（AC-1～AC-6）证据映射（cmd-NN + 断言要点）、NFR-1 回归结论、错误码清单核对（仅两个新码）、zero_diff 面核对结论、基线红例外表、失败项为空。
5. **`_context.md` 更新**：run 收尾整体覆写四块（状态 / 产物地图 / 规则指针 / 待办），独立提交 `[cr] update context`，≤100 行。
6. **接口签名汇总核对**（write-dev-tasks Skill）：TASK-01～TASK-06 声明的接口签名（`resolveWritebackAuthorityPath` / `guardWritebackVersion` 返回值 / `planVersionRefill` 产物 / `RefillEntry` / payload `versionRefill`）消费-产出一致性核对，差异输出 WARN 不静默覆盖。

## 4. 验收条件

1. 三命令 exit 0：cmd-01（crctl.test.mjs 向量 + 静态断言）、cmd-02（writeback-tx 全夹具）、cmd-03（六文件全量回归）全部通过；BR-1/BR-2 被 skip-pattern 排除（非失败）。
2. 机器区 status=pass：`crctl test` 输出 `commands` 列表 1-based 下标与 plan.md §6.1 cmd-NN 全等；`skipped=false` 逐条断言（FR-16 关键测试 cmd-02 唯一证据不被 skip）。
3. `test-report.md` 存在且逐 AC 证据映射完整（AC-1～AC-6 每行有 cmd-NN + 断言要点）；错误码清单与 §5.2 第 3 条一致。
4. 红计数不增加：除 BR-1/BR-2 外无新增失败用例。
5. `_context.md` 已覆写（四块齐全、≤100 行）并独立提交。

## 5. 完成标志

机器区 status=pass（三命令 exit 0 且 skipped=false）；`test-report.md` 落盘且证据映射完整；接口签名核对无差异（或差异已登记 WARN）；`_context.md` 已提交；`_index.yml` 本 TASK 标 done——以上全部为 developing 内可被 `crctl task done` 登记的事件（FR-10：本 TASK 完成边界不含 merge/writeback/archive）。

## 6. 接口契约

- 消费：TASK-01～TASK-06 全部产出（函数签名、payload 形状、CLI 信封、测试向量、README 行文）；`crctl test` 机器区。
- 产出（供 write-test-report / review-code 消费）：`test-report.md`（逐 AC 证据）；机器区 commands 列表（cmd-NN 权威下标）；`test-evidence/cmd-NN.log` 证据文件。

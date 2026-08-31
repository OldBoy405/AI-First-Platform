---
id: CR-2026-057-TASK-11
type: TASK
cr-ref: CR-2026-057
plan-ref: "change-requests/CR-2026-057/plan.md"
sdd-ref: "change-requests/CR-2026-057/sdd.md"
target-version: unassigned
title: 全量回归、契约扫描与测试报告（AC-18/AC-4/AC-17）
slug: full-regression-and-test-report
status: pending
estimate: 9h
depends-on: [CR-2026-057-TASK-02, CR-2026-057-TASK-03, CR-2026-057-TASK-04, CR-2026-057-TASK-05, CR-2026-057-TASK-06, CR-2026-057-TASK-07, CR-2026-057-TASK-08, CR-2026-057-TASK-09, CR-2026-057-TASK-10]
created: 2026-08-31T22:00:00+08:00
---

## 任务描述

收敛点（test owner）：运行 plan §5.1 六条命令（cmd-01～cmd-06），产出 `test-report.md` 与 `test-evidence/cmd-NN.log`（经 `crctl test`），并完成四项静态核对（AC-4 contract-scan 零命中、AC-17 diff 审阅、AC-11 gates 零改动、AC-13 frontmatter 全等）。完成边界 = test-report.md 落盘 + 全部命令绿（developing 内可登记事件，非 merge/writeback/archive 前置）。

输入条件：TASK-02～TASK-10 全部 done；tools CR worktree 干净。

## 涉及文件 / 模块

- `change-requests/CR-2026-057/test-report.md`（crctl test 机器区生成，knowledge-base worktree）
- `change-requests/CR-2026-057/test-evidence/cmd-01.log` ～ `cmd-06.log`
- 只读核对：`skills/shared/crctl/gates.json`、`pipeline-templates/`、本 CR 过程文档 frontmatter

## 实现要点

1. 测试计划（cr-test-plan/v1，shell:false，cwd = tools CR worktree）命令顺序**严格等于** plan §5.1 六条；`crctl test CR-2026-057 --plan <temp-json>` 原子发布机器证据。
2. 核对机器区 `commands` 1-based 下标与覆盖矩阵 cmd-NN 全等（FR-16 稳定关联）；关键测试 = cmd-02～cmd-06，全部须 `exit-code: 0` 且 `skipped: false`。
3. 基线红核对（plan §5.3 / R7）：cmd-01 与 cmd-06 中的「CR-2026-037 Prompt 采纳」与 archive-tx「RED-7」两条既有失败——确认仍为同一根因、非本 CR 引入；在 test-report.md 记录根因与 follow_up 建议；**红计数不因本 CR 增加**（新红必须 triage：若由本 CR 引入则修到绿，不得带入评审）。
4. AC-4：`node --test skills/shared/crctl/scripts/test/contract-scan.test.mjs` 对 3 Pipeline + 11 SKILL 零命中复核。
5. AC-17：diff 审阅——本 CR diff 不包含 P1-3 举例中除 FR-12/14/15/16 以外的检查实现；`FAULT_POINTS` 无新增（version-set 测试复用既有注入点）。
6. AC-11：`gates.json` 零 diff；`deliveryIndexComplete` 行为不变。
7. AC-13 静态侧：cr.md / PRD / SDD / plan / 全部 TASK frontmatter `target-version` 全等 `unassigned`。
8. 接口签名汇总核对：TASK-01 产出签名与 TASK-02/03/04 消费一致；TASK-05 产出字段与 TASK-07 消费口径一致；TASK-04 错误码族与 SDD §3.3 一致。不一致时输出 WARN 并列出差异（不静默覆盖）。
9. FR-23 交叉校验：`crctl task init` 返回 `totalEstimateHours` 与 plan §5.4（84h）一致；不一致 WARN 并说明。
10. 完成后即时在 `tasks/_index.yml` 将 TASK-01～TASK-11 逐条标 done（`crctl task done`，developing 态）；不得把 merge/writeback/archive 相关动作写入本 TASK 完成标志（FR-10）。

## 验收条件

1. cmd-01～cmd-06 全部运行；cmd-02～cmd-06 exit 0 且 `skipped: false`；cmd-01/cmd-06 除两条基线红外全绿。
2. test-report.md 机器区 commands 下标与矩阵 cmd-NN 全等；test-evidence/ 六文件齐。
3. contract-scan 零命中；gates.json / pipeline-templates 零 diff；frontmatter 全等 unassigned；`totalEstimateHours` = 84h。
4. 基线红两条在报告中登记根因与 follow_up，且红计数不增加。

## 完成标志

test-report.md 落盘（机器区 status=pass 或按 FR-16 语义标注基线红）+ 六命令证据齐 + 四项静态核对通过 + TASK 全部 done 登记；提交 `[cr] implement CR-2026-057 TASK-11`。

## 接口契约

- 消费：TASK-01 产出（`normalizeTargetVersion` / `readCrMdTargetVersion` 签名）、TASK-02/03/04 错误码契约、TASK-05 机器区 `skipped` 字段、plan §5.1 命令集、plan §6 覆盖矩阵。
- 产出：`test-report.md` + `test-evidence/cmd-NN.log`（机器证据）；`tasks/_index.yml` done 状态（经 crctl task done）。
- 不产出代码；不改任何受控账本（除 crctl 通道）。

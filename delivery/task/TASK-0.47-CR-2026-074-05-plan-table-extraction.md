---
spec-id: ai-first-platform
version: "0.47"
id: CR-2026-074-TASK-05
type: TASK
cr-ref: CR-2026-074
plan-ref: "change-requests/CR-2026-074/plan.md"
sdd-ref: "change-requests/CR-2026-074/sdd.md"
target-version: 0.47
title: 两规范表提取
slug: plan-table-extraction
status: pending
estimate: 2h
depends-on: [CR-2026-074-TASK-04]
created: 2026-10-01T00:55:00+08:00
---

## 任务描述

在 traceability 脚本内实现 PLAN 两张规范表的定位与提取（SDD §4.4；FR-6；AC-06/AC-07），替代 dep-11 现状的整篇扫描。

## 涉及文件 / 模块

- `skills/writeback/scripts/writeback-traceability.mjs` — 私有取表函数（不新增导出/模块；dep-11 现状整篇扫描 FR/cmd 行且 `cells.filter(Boolean)` 丢空位）。
- `skills/writeback/scripts/test/writeback.test.mjs` — 两规范表正负场景、空位/管道/诱饵用例（与 TASK-04 同测试文件，顺序编辑）。

## 实现要点

- 先 LF 归一，`split(/\r?\n/)`；表头去两端管道、各格 trim 但不丢空格，数组必须逐字等于：
  - `['FR/关键AC','SDD交付项','主责/关联TASK','验收证据','回滚']`
  - `['证据ID','repo','cwd','executable','args','timeout']`
- 匹配表头紧接一行 Markdown 分隔行；分隔格按 `^:?-{3,}:?$` 验证且与表头列数一致。每类恰一张，否则 STRUCTURE_MISMATCH。
- 只读分隔行后连续的管道数据行，到首个非表行停止，不全篇筛 FR/cmd。章节号、其他表及表外诱饵不参加集合。
- 覆盖数据行：去外侧管道后 split，保留中间空格，恰 5 格且首格匹配 `^FR-\d+`；不丢空单元格以凑列。按 FR 数字顺序构造链，列 1/2/3/4/5 依次对应 FR标题/SDD/TASK/evidence/rollback，rollback 不进入链。
- 命令数据行：只取首个单元格检查 `^cmd-\d{2}$`；不检查数据行列数，不解析 args 内的 `|` 为命令列错误。
- 空数据集合仍不能构成可解析链/证据表 → STRUCTURE_MISMATCH。失败在 `writeCandidate` 前发生，不触 authority/本阶段 journal。
- 取表结果传入 dep-11 下游交叉校验：TASK 账本、test-report 命令 ID、merge facts 和最终 validator 的检查不删。不新增重复 FR/cmd 限制，不改已批准 PLAN 的写法来适配 parser。
- 历史 PLAN 样本（CR-2026-061 的 args 管道、CR-2026-066 的表外 FR 诱饵）从 knowledge-base `change-requests/<CR>/plan.md` 裁剪，实施时记录原文 SHA（规范行尾）与来源 commit，再纳入 tools 测试 fixture，不修改签字源。

## 验收条件

1. 在 tools CR worktree 执行 `node --test skills/writeback/scripts/test/writeback.test.mjs`（证据 cmd-03）全绿，且 AC-06 断言覆盖：061/066 历史规范片段与合成诱饵 fixture 下，新链/命令 ID 与规范片段期望一致、表外无误收、空位不移列、args 含管道仅验首格。
2. AC-07 断言覆盖：结构错 STRUCTURE_MISMATCH 且 authority/本阶段 journal 不变；集合/错误在 LF 与 CRLF 两行尾下相同。负测在合法 writing-back/其他证据齐全时变动目标表，让负测触达 parser 而非状态/缺证据先失败。
3. 先建立旧解析仅针对规范片段的基准结果，再比较新解析集合（不把旧全篇误收冻结为期望）；历史样本行尾规范后存来源摘要，测试执行不读取其他 KB trunk。

## 完成标志

- cmd-03 全绿含 AC-06/AC-07 断言；取表函数为脚本私有、无新增导出/模块。
- 历史 061/066 PLAN 原文 SHA（规范行尾）与来源 commit 已记录于测试 fixture 注释。
- diff 限 `writeback-traceability.mjs` 与 `writeback.test.mjs`。

## 接口契约

**消费**：dep-11 `buildNewMilestone`/`trunkOf`（交叉校验下游不删；`trunkOf` 由 TASK-06 改造）；PLAN 规范表判据（本契约表头数组、分隔行 `^:?-{3,}:?$`、FR 首格 `^FR-\d+`、命令首格 `^cmd-\d{2}$`，逐字）。

**产出**：私有取表函数结果——`fr-chain`（FR/SDD/TASK/evidence 四元组按 FR 数字顺序，rollback 不入链）与命令 ID 集合；STRUCTURE_MISMATCH 前置于 writeCandidate。下游消费方 TASK-06（同文件 trunk 改造基线）、TASK-08（集成变体）与既有 validator 引用同一集合语义，不得缩写。

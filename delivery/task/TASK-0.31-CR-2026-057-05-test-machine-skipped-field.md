---
spec-id: ai-first-platform
version: "0.31"
id: CR-2026-057-TASK-05
type: TASK
cr-ref: CR-2026-057
plan-ref: "change-requests/CR-2026-057/plan.md"
sdd-ref: "change-requests/CR-2026-057/sdd.md"
target-version: unassigned
title: crctl test 机器区 skipped 字段（FR-16）
slug: test-machine-skipped-field
status: pending
estimate: 8h
depends-on: [CR-2026-057-TASK-01]
created: 2026-08-31T22:00:00+08:00
---

## 任务描述

`crctl test` 机器区每条 command 增加布尔字段 `skipped`（additive，不删既有字段），计算规则冻结（SDD §2.4/§4.5）：`skipped = (exit-code == 0) && (stdout/stderr 两段匹配域内命中冻结模式表任一模式（大小写不敏感））`。skip 的唯一证据来源 = 本机器区字段；review-code 只读该字段，不自行解析框架输出（评审侧规则在 TASK-07）。

输入条件：TASK-01 完成；tools CR worktree。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（`FROZEN_SKIP_PATTERNS`、新 `extractStdioSections`、`runTestPlan`、`renderTestMachineReport`）
- `skills/shared/crctl/scripts/test/test-cr.test.mjs`（fixture 适配 + skipped 向量，cmd-05）

## 实现要点

1. `FROZEN_SKIP_PATTERNS` 模块级常量：5 条字面量 RegExp（均带 `i`）：`(^|\n)# skip\b`、`(^|\n)ok \d+ # skip\b`、`\bskipped:\s*[1-9]\d*`、`\bSKIPPED\b`、`\bno tests to run\b`。**冻结，实施期不得增删**（FR-16）。
2. `extractStdioSections(normText)` 纯函数（§2.4 提取规则，先 `\r\n→\n`、`split(/\r?\n/)`）：定位 `--- stdout ---` 与 `--- stderr ---` 标记行各恰好 1 次；缺失/重复 → 硬失败 `TEST_LOG_MARKER_INVALID`（NFR-3，禁止静默降级）；返回 `{ stdout, stderr }`。
3. `runTestPlan` 每条 command 生成 logContent 后：`norm = logContent.replaceAll('\r\n','\n')` → `secs = extractStdioSections(norm)` → `skipped = (r.status === 0) && FROZEN_SKIP_PATTERNS.some(re => re.test(secs.stdout + '\n' + secs.stderr))` → `results.push({ ...既有字段, skipped })`。匹配域仅两段：`$ <command> <args>` 行与 `(exit=0)` 元数据行不参与（B-SDD-004）。
4. `renderTestMachineReport` 每 command 块末追加 `    skipped: {c.skipped}`；既有字段与顺序不动。
5. non-zero / timeout 一律 `skipped: false`（那是失败不是 skip）。
6. 测试：fixture cr.md 补 `target-version`（SDD §6.1 item 4）；夹具组——5 种模式各一 + CRLF 变体 → `skipped:true`；无模式 exit 0 → false；non-zero → false；模式文本仅出现在 `$ <cmd> <args>` 行或 `(exit=0)` 行 → false；标记缺失/重复 → `TEST_LOG_MARKER_INVALID` 硬失败。

## 验收条件

1. 命中模式表夹具全部 `skipped:true`；无模式 exit 0 与 non-zero 均为 false。
2. 两域外模式文本不命中（false skipped 防护）；标记缺失/重复硬失败（不静默）。
3. 机器区既有无 skipped 字段的命令块原样保留（additive 断言）。
4. cmd-05 绿（AC-16 自动化侧全项）；test-cr 既有用例不新增失败。

## 完成标志

cmd-05 全绿；AC-16 自动化侧逐项核对通过；提交 `[cr] implement CR-2026-057 TASK-05`。

## 接口契约

- 消费：无新 lib 依赖（`FROZEN_SKIP_PATTERNS` 本 TASK 内定义）；既有 `runTestPlan` 的 `cmd-NN` 命名与 log 分段格式（SDD §10 #7）不改。
- 产出：
  - `extractStdioSections(normalizedLogText) → { stdout: string, stderr: string }`（标记缺失/重复抛 `TEST_LOG_MARKER_INVALID`，不返回部分结果）。
  - `runTestPlan` results 每条 command 增 `skipped: boolean`；`renderTestMachineReport` 每 command 块追加 `skipped:` 行。
- 评审侧消费（TASK-07）：review-code 只读机器区 `skipped`/`exit-code`/`timed-out` 与覆盖矩阵 `cmd-NN`；本 TASK 不产出评审规则。

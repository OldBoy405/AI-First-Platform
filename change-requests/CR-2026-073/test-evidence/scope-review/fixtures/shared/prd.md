---
id: __CR__-prd
type: PRD
cr-ref: __CR__
target-version: 0.46
status: approved
created: "__AT__"
---

# __CR__ 需求（fixture 快照）

## 1. 用途与非目标

同一份 SDD/AC 的三个证据范围快照之一，用于 CR-2026-073 TASK-04 / plan §5 的 `review-dev-plan` 定向证据口径取证（U 误设全仓 / S 子集冒充全量 / P 定向一致）。本快照不实现任何能力、不进入业务分支、不产生业务交付。

## 2. 功能需求

| FR | 描述 | AC |
|---|---|---|
| FR-1 | `tools/scripts/duration.mjs` 新增纯函数 `parseDuration(text)`：`"1h30m"` → `5400000`；非法输入 → `null` | AC-1 |
| FR-2 | 同模块新增纯函数 `formatDuration(ms)`：`5400000` → `"1h30m"`；负数 → `""` | AC-2 |

## 3. 验收标准

| AC | 可观测判据 |
|---|---|
| AC-1 | 定向用例 `duration parse targeted case` 通过：`parseDuration` 的合法输入与非法输入两类断言 |
| AC-2 | 定向用例 `duration format targeted case` 通过：`formatDuration` 的正常值与非负校验两类断言 |

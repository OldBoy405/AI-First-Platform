---
id: CR-2026-041-TASK-01
type: TASK
cr-ref: CR-2026-041
plan-ref: "change-requests/CR-2026-041/plan.md"
sdd-ref: "change-requests/CR-2026-041/sdd.md"
title: generator 注入 evidence 块并删 status
slug: generator-inject-evidence-block
status: pending
estimate: 6h
depends-on: []
created: 2026-08-15T22:05:40+08:00
---

# TASK-01 generator 注入 evidence 块并删 status

## 1. 任务描述

在 `writeback-traceability.mjs` 中新增 `readEvidenceInputs(crDir)`，读取 7 份 canonical 证据文件并生成 evidence 对象（含 LF digest）；改造 `buildSegment()` 在 `frs` 之后追加 `evidence:` 块，且不再输出 `status` 行。对应 FR-01（最小证据摘要）与 FR-05（新 milestone 无 status）。

## 2. 涉及文件 / 模块

- `skills/writeback/scripts/writeback-traceability.mjs`（唯一改动文件）

## 3. 实现要点

- 按 SDD §2.2 固定 path map 读取（路径相对 CR 目录）：
  - `test` → `test-report.md`（frontmatter `status`）
  - `reviews.{requirement,tech-design,dev-plan,code}` → `review-annotations/{requirement,sdd,dev-plan,code}.yml`（`verdict`）
  - `approval` → `approval.yml`
  - `merge` → `merge-commits.yml`
- `readEvidenceInputs(crDir)` 返回 `{ test, reviews, approval, merge }`；每项含 `status`/`verdict` 派生值、`path`（workspace 相对 POSIX 路径 `change-requests/{cr}/...`）、`sha256(normalize(readFile(p)))`。
- 任一输入缺失 / 状态不通过 / 结构非法 → `fail('EVIDENCE_INVALID', ...)`，零 candidate 输出（对齐 SDD §3.1）。
- `buildSegment()` 在 `frs` 段后追加 `evidence:` 块，格式对齐 SDD §2.1；删除 `if (ms.status) lines.push(...)` 的 `status` 行（FR-05）。
- digest 用 LF 归一内容哈希，与 CAS 锚点 `readHashRaw` 区分（SDD §2.2）；复用 `lib.mjs` 的 `sha256`/`normalize`/`readFile`/`readFrontmatter`/`parseYaml`。
- SELF_CHECK 增加断言：candidate 内 `evidence:` 块恰好出现一次、`test/reviews(4)/approval/merge` 七项齐全、path map 精确、无 `\r`、既有段字节不变（保留既有断言）。

## 4. 验收条件

1. 证据七项齐全时，candidate 的 `traceability.yml` 当前 milestone 段含 `evidence:` 块，七项 path 与 §2.2 map 精确相等，且不含 `status:` 行。
2. 任一证据文件缺失或 `status`/`verdict` 非 `pass` 时，脚本以 `EVIDENCE_INVALID` 退出，candidate 目录不产生 manifest。

## 5. 完成标志

`node writeback.test.mjs`（生成侧用例）通过，且 SELF_CHECK 断言覆盖 evidence 块与 status 删除。

## 6. 接口契约

- **消费**：`lib.mjs` 的 `readFile`、`normalize`、`sha256`、`readFrontmatter`、`parseYaml`、`writeCandidate`。
- **产出**：
  - `readEvidenceInputs(crDir) -> { test, reviews, approval, merge }`
  - `buildSegment()` 输出含 `evidence:` 块、无 `status` 行的 milestone 段（供 TASK-02 的 `validateMilestoneEvidence` 消费）。

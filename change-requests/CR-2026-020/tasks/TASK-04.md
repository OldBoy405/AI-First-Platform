---
id: CR-2026-020-TASK-04
type: TASK
cr-ref: CR-2026-020
plan-ref: "change-requests/CR-2026-020/plan.md"
sdd-ref: "change-requests/CR-2026-020/sdd.md"
title: writeback-traceability.mjs 入库脚本
slug: writeback-traceability-script
status: pending
estimate: 6h
depends-on: [CR-2026-020-TASK-01]
assignee: ""
created: "2026-08-04T22:21:12+08:00"
---

## 任务描述

实现 traceability 回写脚本。**不是全量重建**（PRD 原表述已在 SDD §8 D3 修正）：头部结构化字段更新 + 本 CR milestone 段末尾追加，保留既有累积历史与手工注释逐字节不变（SDD §4.3、FR-3/FR-7）。

## 涉及文件 / 模块

- 新建 `tools/skills/writeback/scripts/writeback-traceability.mjs`
- 依赖 TASK-01 的 `lib.mjs`
- 读写对象：`specs/{spec}/traceability.yml`（写，头部更新 + 追加）；`change-requests/_backlog.yml` 的 `merge-commits[]`（只读，账本文件，禁止写）；`--milestone-file`（Agent 起草的本 CR milestone YAML 段，只读输入）

## 实现要点（引用 SDD §4.3、§2.2、§8 D3）

1. CLI 契约：`--workspace --cr --spec --version --milestone-file <path> [--dry-run]`。
2. 定向提取 `_backlog.yml` 中 `{cr}` 条目的 `merge-commits[]`（六字段：repo/trunk/sha/branch/source-sha/merged-at），字段不齐全 → `fail('MERGE_COMMITS_MISSING', ...)`，不猜测、不取 trunk 最新提交。
3. 读 `--milestone-file`：结构校验（`cr`/`milestone`/`target-version`/`fr-chain[].fr` 必填）；若文件内已含 `merge-commits`，与脚本提取结果做一致性校验（不一致则硬失败，避免人工誊抄与账本口径分叉）。
4. 幂等判据：`specs/{spec}/traceability.yml` 中已存在 `- cr: {cr}` 段 → noop。
5. 头部字段更新：行级锚定更新 `cr-ref`/`target-version`/`generated-at`；`cr-history[]` 追加去重；**头部手工注释与既有 milestones 段落逐字节保留**，不重排、不重新序列化整份文件。
6. 本 CR milestone 段追加到文件末尾（`milestones:` 列表下追加一个新条目，格式对齐现有段落）。
7. 自检：回读断言 `- cr: {cr}` 段恰 1 处、`merge-commits` 数与提取结果一致、既有历史段字节级不变（可用长度/哈希对比未受影响区间）。

## 验收条件

1. 对已归档 CR 的 `_backlog.yml` 历史条目（如 CR-2026-019）做只读提取测试：验证 `merge-commits[]` 六字段提取正确（对照 §0 事实基线核实的真实结构）。
2. 用 `specs/ai-first-platform/traceability.yml` 的只读副本（复制到临时目录，**不改真实文件**）做追加测试：追加新 milestone 段后，前 989 行内容（含头部手工注释）逐字节不变，仅文件末尾新增一段。
3. `--milestone-file` 缺少 `fr-chain[].fr` 时硬失败，不落盘。
4. merge-commits 缺失或某仓字段不全时 `fail('MERGE_COMMITS_MISSING', ...)`，非零退出。
5. 同一 CR 重复执行：noop。

## 完成标志

脚本落盘，上述 5 条验收手工跑通（临时目录测试，不改真实 `specs/ai-first-platform/traceability.yml`），commit 到 tools 仓。

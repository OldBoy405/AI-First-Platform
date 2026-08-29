---
spec-id: ai-first-platform
version: "0.5"
id: CR-2026-054-TASK-02
type: TASK
cr-ref: CR-2026-054
plan-ref: "change-requests/CR-2026-054/plan.md"
sdd-ref: "change-requests/CR-2026-054/sdd.md"
title: "接入 archive 候选校验"
slug: archive-candidate-validation
status: pending
estimate: 10h
depends-on: [CR-2026-054-TASK-01]
created: 2026-08-29T18:15:00+08:00
---

# 1. 任务描述

在 `workspace-transactions.mjs` 的共用 `buildEntries()` 中接入文件私有 `validateArchiveCandidates`，对四份即将写入的候选内容执行严格解析、根形状检查和 archive 后置不变量校验，并确保所有失败发生在 write-set hash、stage、commit 和 push 之前。

# 2. 涉及文件 / 模块

- `tools` worktree 的 `skills/shared/crctl/scripts/workspace-transactions.mjs`
- 现有 archive transaction 测试辅助代码（仅在需要补充输入时修改）

# 3. 实现要点

- 实现精确输入：`validateArchiveCandidates({ cr, finalStatus, candidates: { backlog, history, index, crMd } })`。
- 四候选根形状分别为 backlog 的 `change-requests`、history 的 `history`、index 的 `change-requests`、cr.md frontmatter 对象。
- 校验目标 CR 在 backlog 为 0 次、history 为 1 次、index 为 1 次且 status 等于 finalStatus、cr.md status 等于 finalStatus；history ID 全局唯一且 final-status 属于 archived/rejected/withdrawn。
- 将 strict parser 错误和形状/不变量错误统一包装为现有 `TxError('ARCHIVE_YAML_INVALID', ...)`，详情包含 file、category、line、cr 和适用 key；缺失不变量使用 `line: null`。
- 保留 archiveLedgerEdits 的既有 ENTRY_NOT_IN_BACKLOG、ENTRY_ALREADY_IN_HISTORY、INDEX_ENTRY_NOT_FOUND 错误，不扩大校验到常规 crctl 路径。

# 4. 验收条件

对应 PRD 验收标准：AC-2。

1. 首次 archive 和远端 trunk 变化后的 rebuild 均经由同一 `buildEntries()` 校验，任何候选错误都发生在 write-set 计算及 Git 写入之前。
2. 正常 archived/rejected/withdrawn 候选通过；根形状、目标 CR 计数、history 唯一性或非法终态失败时返回稳定 `ARCHIVE_YAML_INVALID` 详情。
3. 既有 archive 生成错误码仍按原路径返回，未被统一包装吞没。

# 5. 完成标志

私有校验接入共用构建点，相关 archive 测试通过，代码没有新增 CLI、状态、账本或通用 schema 服务。

# 6. 接口契约

- 消费：TASK-01 提供的 `parseYaml(text, { strict: true })`；既有 `archiveLedgerEdits`、`crMdStatusText` 和 `buildEntries()`。
- 产出：文件私有 `validateArchiveCandidates({ cr, finalStatus, candidates })`，供 TASK-03 的行为测试通过 archive 公共入口验证；不导出测试接口。

---
id: CR-2026-039-TASK-03
type: TASK
cr-ref: CR-2026-039
plan-ref: "change-requests/CR-2026-039/plan.md"
sdd-ref: "change-requests/CR-2026-039/sdd.md"
title: cr.md 时间字段统一为 updated（三个 writer 收敛）
slug: cr-md-updated-unification
status: pending
estimate: 3h
depends-on: [CR-2026-039-TASK-02]
created: 2026-08-15T01:31:31+08:00
---

# 任务描述

`cr.md` frontmatter 时间字段收敛为单一 `updated`（最近一次受控修改时间）。受控 writer 共三处：register 渲染（现状已写 `updated`，不改）、状态推进（advance/approve/reject 与 merge finalize 共用的 `crMdStatusText`）、Owner 正式移交（`editCrOwnerProjection`）。reader 兼容规则固定为 `updated ?? updated-at`（写入代码注释，当前无消费点，不新增无调用方 helper）。

# 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（`crMdStatusText` 修订 + 新增导出纯函数）
- `skills/shared/crctl/scripts/crctl.mjs`（`editCrOwnerProjection` 接入）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`（新增用例）

# 实现要点（SDD §4.4）

- 提取共享纯函数到 workspace-transactions.mjs 并导出，两处调用同一实现，禁止复刻：
  ```
  refreshCrMdUpdated(fm: string, at?: string) -> string
  ```
  语义：先删既有 `updated-at:` 行（若存在），再对 `updated:` 行原位刷新（不存在则追加）；任何情况下不得双字段共存；替换产生的空行需清理。
- `crMdStatusText` 在 status 替换后调用 `refreshCrMdUpdated`；`editCrOwnerProjection` 生成新 cr.md 文本后同样调用。
- 行尾纪律：两函数入参均为已 LF 规范化的 frontmatter body；CRLF 输入经既有调用链规范化后结果一致。

# 验收条件

1. `crMdStatusText` 纯函数单测：含 `updated-at:` 的旧 frontmatter → 输出仅单一 `updated`（值刷新、无残留空行）；含 `updated:` → 原位刷新；两者皆无 → 追加；CRLF 来源文本规范化后结果一致。
2. `crctl owner-set` 后 cr.md `updated` 刷新为本次移交时间戳（复用 handoverAt 或 nowIso，与移交时间一致）。
3. register / advance / approve 产物 frontmatter 均不含双字段（遍历现存 fixture 断言）。
4. 既有依赖 cr.md frontmatter 的用例（CAS、状态读取、merge finalize）不回归。

# 完成标志

新增用例全部通过 + 既有全量测试不回归；提交为一个可回滚 commit。

# 接口契约

- 消费：无上游 TASK 产出；使用 workspace-transactions.mjs 既有 `matchFrontmatter` 语义（签名不变）。
- 产出（workspace-transactions.mjs 导出，供 crctl.mjs 导入）：
  ```
  refreshCrMdUpdated(fm: string, at?: string) -> string
  ```
  入参为 LF 规范化的 frontmatter body（不含 `---` 围栏）；`at` 缺省 `nowIso()`；返回新 body。

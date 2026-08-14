---
id: CR-2026-018-TASK-02
type: TASK
cr-ref: CR-2026-018
plan-ref: "change-requests/CR-2026-018/plan.md"
sdd-ref: "change-requests/CR-2026-018/sdd.md"
title: advance 改为只写 cr.md，删除 updateBacklogStatus 调用（FR-1）
slug: advance-single-write
status: pending
estimate: 10h
depends-on: ["CR-2026-018-TASK-01"]
assignee: ""
created: "2026-08-04T16:35:00+08:00"
---

## 1. 任务描述

实现 SDD §4.2：`cmdAdvance` 删除对 `updateBacklogStatus(:674)` 的调用（:814），只保留 `updateCrMdStatus`；将 `updateCrMdStatus` 内部所有 `{updated: false, why}` 分支升级为硬失败（`fail('CR_MD_WRITE_FAILED', why)`），因为 cr.md 已升级为权威写入目标，不能再"尽力写、失败静默"。顺带把 standalone commit 模式的 `git add change-requests`（:820）收窄为精确路径 `change-requests/{cr}/cr.md`。

依赖 TASK-01：advance 的前置读（`cmdAdvance:800` 取 current status）已在 TASK-01 中改调 `resolveCrState`，本任务只需处理写路径。

## 2. 涉及文件 / 模块

- `tools/skills/shared/crctl/scripts/crctl.mjs`：`cmdAdvance`（:796-816 段）、`updateCrMdStatus`（:708 起，硬失败化）
- `tools/skills/shared/crctl/scripts/test/crctl.test.mjs`：新增用例

## 3. 实现要点

- `updateBacklogStatus` 函数本身（:674-:705）本任务暂不删除函数体——保留供 TASK-04（migrate-backlog）复用其条目定位算法，只删除 `cmdAdvance` 对它的**调用**。函数体清理留到 TASK-03/04 完成后统一处理，避免死代码残留跨任务反复横跳。
- `updateCrMdStatus` 硬失败改造需覆盖：cr.md 不存在、无 frontmatter、CAS 冲突三种既有分支。
- `result.files` 从 `[backlogPath(ws), crmd.path]` 改为 `[crmd.path]`。

## 4. 验收条件

- AC-1（对应 PRD/SDD）：测试 workspace 执行一次合法 advance，`git diff` 只显示 `cr.md` 变更，`_backlog.yml` 无 diff。
- 新增单元测试：cr.md 不存在时 advance 报 `CR_MD_WRITE_FAILED` 且不写任何文件（含 `_backlog.yml` 不应被写，因为调用已删除）。
- 现有 21 个用例全绿。

## 5. 完成标志

`cmdAdvance` 单写 cr.md 落地；`updateCrMdStatus` 硬失败化；git add 范围收窄；AC-1 对应测试通过；lint 零报错。

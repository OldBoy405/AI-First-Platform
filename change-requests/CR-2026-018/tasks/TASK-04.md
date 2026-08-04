---
id: CR-2026-018-TASK-04
type: TASK
cr-ref: CR-2026-018
plan-ref: "change-requests/CR-2026-018/plan.md"
sdd-ref: "change-requests/CR-2026-018/sdd.md"
title: 新增 crctl migrate-backlog 子命令（FR-5）
slug: migrate-backlog-command
status: pending
estimate: 10h
depends-on: ["CR-2026-018-TASK-03"]
assignee: ""
created: "2026-08-04T16:45:00+08:00"
---

## 1. 任务描述

实现 SDD §4.3：新增 `crctl migrate-backlog` 子命令，对存量 v1 workspace 执行一次性迁移——逐条目核对 `_backlog.yml` status 与 `cr.md` status 一致性，不一致则 `MIGRATE_STATUS_MISMATCH` 硬失败并列出差异（禁止静默取一侧，纪律 #1）；一致则复用 `updateBacklogStatus` 的条目定位算法（:678-690）行级删除 `status:`/`updated-at:` 行，顶层 `schema` 升 `cr-backlog/v2`，CAS 写回，生成迁移报告（gitignored，SDD §2.3 决策），standalone commit `[cr] migrate backlog to v2: {N} entries, status->cr.md`。幂等：已是 v2 时输出 already-migrated，退出码 0。

## 2. 涉及文件 / 模块

- `tools/skills/shared/crctl/scripts/crctl.mjs`：新增 `cmdMigrateBacklog`；CLI 帮助文本（:1235 段）新增子命令说明
- `tools/skills/shared/crctl/scripts/test/crctl.test.mjs`：新增用例

## 3. 实现要点

- 迁移报告路径：`.crctl/migrate-backlog-report.yml`（已在 `.gitignore` 覆盖范围内，复用现有 `.crctl/` 约定）。
- 此时可以清理 TASK-02 中保留的 `updateBacklogStatus` 死代码路径——若其条目定位算法被本任务复用为独立辅助函数，建议提取为 `locateBacklogEntryLines()` 共享，避免重复实现两套定位逻辑。
- commit message 携带条目数与 schema 版本摘要（SDD §2.3 决策，替代报告文件入库）。

## 4. 验收条件

- AC-5：对含 ≥2 条目的存量 `_backlog.yml` 执行迁移：一致时产出无 status 的 v2 索引 + 迁移报告，commit message 含条目数摘要；人为制造一处不一致时命令非零退出且不写任何文件。
- 幂等测试：对已是 v2 的 workspace 重复执行，输出 already-migrated，退出码 0，无文件变更。
- 现有 21 个用例全绿。

## 5. 完成标志

`migrate-backlog` 子命令落地；AC-5 三种场景（成功/失败/幂等）测试通过；CLI 帮助文本更新；lint 零报错。

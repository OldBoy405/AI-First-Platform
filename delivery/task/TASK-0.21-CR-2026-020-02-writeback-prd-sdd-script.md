---
spec-id: ai-first-platform
version: "0.21"
id: CR-2026-020-TASK-02
type: TASK
cr-ref: CR-2026-020
plan-ref: "change-requests/CR-2026-020/plan.md"
sdd-ref: "change-requests/CR-2026-020/sdd.md"
title: writeback-prd-sdd.mjs 入库脚本
slug: writeback-prd-sdd-script
status: pending
estimate: 6h
depends-on: [CR-2026-020-TASK-01]
assignee: ""
created: "2026-08-04T22:21:12+08:00"
---

## 任务描述

实现 PRD/SDD 回写脚本：首次回写整份落地、增量回写按里程碑分节追加，并对 `specs/_index.yml` 做结构化字段更新（SDD §4.1、FR-1）。

## 涉及文件 / 模块

- 新建 `tools/skills/writeback/scripts/writeback-prd-sdd.mjs`
- 依赖 TASK-01 的 `lib.mjs`
- 读写对象：`specs/{spec}/PRD.md`、`SDD.md`、`specs/_index.yml`（写）；`change-requests/{cr}/prd.md`、`sdd.md`（只读）

## 实现要点（引用 SDD §4.1、§2.2、§3）

1. CLI 契约：`--workspace --cr --spec --version [--brief] [--dry-run]`（SDD §3）。
2. 首次回写：`specs/{spec}/PRD.md` 不存在 → 整份拷贝 CR `prd.md` + 补齐 frontmatter（`spec_id`/`version`/`status`/`cr_ref`）；SDD.md 同理。
3. 增量回写：幂等判据 = 里程碑标题行 `## {标题}（v{version} · CR-{id}）` 已存在则 noop；否则将 CR 文档正文（去 frontmatter）整体 H 级 +1 后追加到文件末尾。
4. `specs/_index.yml` 更新：用 `lib.mjs` 的 `extractBlock` 定位 `- id: {spec}` 块，更新 `current`/`cr-ref`/`updated` 三个行级字段，`cr-history[]` 按 id 追加去重；`brief` 仅当 `--brief` 传入时整行替换，未传入不动。
5. dry-run 模式：打印 PRD.md/SDD.md/_index.yml 三个目标文件将产生的 diff，不落盘。
6. 自检（实跑末尾）：回读断言里程碑标题行恰 1 次、`_index.yml` 对应条目字段齐全、全文件无 `\r`。

## 验收条件

1. 对一个不存在 `specs/{spec}/` 的假 spec_id 首次回写：`specs/{spec}/PRD.md`、`SDD.md` 落地且 frontmatter 补全；`specs/_index.yml` 新增对应 `features[]` 条目。
2. 对已有基线（可用 `specs/ai-first-platform/` 只读复制到临时目录测试，不得直接改动真实 specs）做增量回写：新里程碑节追加、既有内容逐字节不变（`diff` 校验旧内容前缀不变）、H 级正确 +1。
3. 同一 CR 重复执行：第二次输出 `"noop": true`，文件无变化（`git diff` 或内容哈希对比为空）。
4. `--dry-run` 模式下文件系统无任何变化（mtime 不变），stdout 含预期 diff。

## 完成标志

脚本落盘，上述 4 条验收手工跑通（临时目录测试，不碰真实 `specs/`），commit 到 tools 仓。

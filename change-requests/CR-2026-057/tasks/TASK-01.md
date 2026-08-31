---
id: CR-2026-057-TASK-01
type: TASK
cr-ref: CR-2026-057
plan-ref: "change-requests/CR-2026-057/plan.md"
sdd-ref: "change-requests/CR-2026-057/sdd.md"
target-version: unassigned
title: 版本规范化纯函数与守卫读取基元
slug: normalize-version-and-cr-md-reader
status: pending
estimate: 6h
depends-on: []
created: 2026-08-31T22:00:00+08:00
---

## 任务描述

在 tools CR worktree 的 `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` 落地两个纯函数/只读基元：`normalizeTargetVersion`（FR-12/FR-14/FR-15 共用的版本值域与规范化，SDD §2.1/§4.1）与 lib 内 `readCrMdTargetVersion`（writeback 守卫读取 cr.md 版本事实的行级读取器，SDD §2.2/§1.4）。本 TASK 不接任何 CLI 调用方（TASK-02/03/04 消费）。

输入条件：CR status=task-breakdown 之后、developing 内；tools CR worktree HEAD=8c0a6db（SDD §10 依赖符号行号以实际文件核对）。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（新增导出与 lib 内函数）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`（新增单测组，cmd-01 覆盖）

## 实现要点

1. `normalizeTargetVersion(raw, { allowUnassigned = true } = {})`：按 SDD §2.1 七步顺序短路；纯 string→result，**禁止抛异常**。禁止同义值集合冻结 11 项：`tbd`、`n/a`、`na`、`n.a.`、`pending`、`none`、`unknown`、`todo`、`wip`、`null`、`undefined`。真实版本正则 `^(0|[1-9]\d*)\.(0|[1-9]\d*)(\.(0|[1-9]\d*))?$`；`v`/`V` 前缀在大小写折叠**前**对 trim 串剥离恰好一个（`vv0.30` → malformed）。
2. `readCrMdTargetVersion(workspacePath, crId)`：路径 `${workspacePath}/change-requests/${crId}/cr.md`；读入后先 `\r\n→\n` 规范化（NFR-3），`split(/\r?\n/)` 行级匹配 `^target-version:` 行；文件不可读 / 无 frontmatter / 缺字段 → `{ ok: false, reason: 'missing' }`。
3. 不加 IO 以外的任何副作用；不新增依赖；不动 `durable-tx.mjs`、`yaml-subset.mjs`（zero_diff 5）。

## 验收条件

1. 值域表单测全绿（cmd-01）：合法 `unassigned` / `0.30` / `v0.30`→`0.30` / `V0.30`→`0.30` / `0.1.0`；非法：缺省、空、`tbd`、`TBD`、`n/a`、`pending`、`0.29-rc`、`1`、`0.30.0.1`、`latest`、内嵌空白、非 string。
2. `allowUnassigned=false` 下 `unassigned` → `{ ok:false, reason:'unassigned-not-allowed' }`。
3. `readCrMdTargetVersion` 对 CRLF cr.md / 缺字段 / 文件缺失三类夹具返回符合契约；对 LF 文件返回 raw 串。
4. 既有 crctl.test.mjs 用例除基线红（plan §5.3 两条）外不新增失败。

## 完成标志

cmd-01 中新增单测组全绿；`workspace-transactions.mjs` 新增导出无 IO；提交 `[cr] implement CR-2026-057 TASK-01`。

## 接口契约

- 消费：无（本 CR 首个基元）。
- 产出（供 TASK-02/03/04 与测试消费，签名冻结）：
  - `normalizeTargetVersion(raw, { allowUnassigned = true } = {}) → { ok: true, value: string } | { ok: false, reason: 'missing'|'empty'|'forbidden'|'unassigned-not-allowed'|'malformed' }`
  - `readCrMdTargetVersion(workspacePath, crId) → { ok: true, raw: string } | { ok: false, reason: 'missing' }`
- 错误码映射由调用方完成：register → `REGISTER_VERSION_INVALID`；writeback-apply → `WRITEBACK_VERSION_INVALID`；version-set `--to` → `VERSION_SET_INVALID`。本 TASK 不抛业务错误码。

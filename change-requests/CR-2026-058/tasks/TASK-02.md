---
id: CR-2026-058-TASK-02
type: TASK
cr-ref: CR-2026-058
plan-ref: "change-requests/CR-2026-058/plan.md"
sdd-ref: "change-requests/CR-2026-058/sdd.md"
target-version: 0.30
title: planVersionRefill 与行级编辑纯函数（FR-2.1 backlog 预检 + cr.md 语义复核）
slug: plan-version-refill
status: pending
estimate: 12h
depends-on: [CR-2026-058-TASK-01]
created: 2026-09-01T16:50:00+08:00
---

## 1. 任务描述

目标：实现 SDD §4.3 `planVersionRefill`（模块私有）——回灌分支的唯一计划器：同源绑定（⓪）+ backlog 预检四错误码（①）+ cr.md 同源重读语义复核（③）+ 两个行级编辑纯函数。产物为 journal payload 持久化的 `versionRefill` 计划（`inputVersion` / `crMd` 条目 / `backlog` 条目 / `crMdBase`），**纯读 + 纯文本变换，无任何文件写入、无 journal/lock/candidate 副作用**。

背景：FR-2.1 要求回灌前对同一 authority 的 `_backlog.yml` 预检（条目唯一性 + 前置值），禁止静默覆盖另一真实版本、禁止缺失时插入；B-SDD-02 要求 guard 采样与 plan 二次读取同源绑定、值级语义复核。

输入条件：TASK-01 产出的 `guardWritebackVersion` authority 快照语义；`yaml-subset.mjs#matchEntryBlock(text, id)` 返回 `{start, end, text, indent}`（SDD §6.3 证据 3）；`normalizeTargetVersion` 支持 `allowUnassigned=true`。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（新增模块私有 `planVersionRefill` / `applyTargetVersionToCrMd` / `editBacklogEntryTargetVersion`）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`（新增 plan 向量）

## 3. 实现要点

1. `planVersionRefill({ txws, authority, cr, stage, version })`（SDD §4.3）：
   - ⓪ 同源绑定（防御性重申）：`authority.source !== 'transaction-workspace' || authority.path !== txws` → throw `WRITEBACK_STATE_MISMATCH`（**复用既有码**，message 载 authority-mismatch 与两侧路径；不新增公开错误码——B-SDD-04）。
   - ① backlog 预检（先于任何副作用）：读 `txws/change-requests/_backlog.yml`（不可读 → `ENTRY_NOT_IN_BACKLOG` `{cr}`）；`\r\n→\n` 后行级切分（既有 `backlogLines`，`\r?\n` 口径）；命中计数用行级正则 `/^([ \t]*)- id:\s*["']?([^\s"']+)["']?\s*$/` 与 CR-ID 比对（SDD §2.3，与 merge 侧 `locateBacklogEntry` 同口径）：0 命中 → `ENTRY_NOT_IN_BACKLOG`；>1 → `WRITEBACK_BACKLOG_ENTRY_DUPLICATE` `{cr, count}`；恰好 1 → `matchEntryBlock` 定位（null → 防御性 `ENTRY_NOT_IN_BACKLOG`），读条目内 `^[ \t]*target-version:` 行（缺行 → `WRITEBACK_VERSION_INVALID` `{cr, backlogReason:'missing'}`），`normalizeTargetVersion(allowUnassigned=true)`（失败 → `WRITEBACK_VERSION_INVALID` `{cr, backlogReason: reason}`）。
     - backlog 规范化值分支：`unassigned` → `editBacklogEntryTargetVersion` 生成 after，`backlogEntry={path:'change-requests/_backlog.yml', beforeSha256, afterSha256, afterText}`；与输入全等 → `backlogEntry=null`（幂等）；另一真实版本 → `WRITEBACK_BACKLOG_VERSION_MISMATCH` `{cr, crMd:'unassigned', backlog:bv.value, input:version}`。
   - ③ cr.md 同源重读 + 语义复核：读 `txws/change-requests/{cr}/cr.md`（null → `WRITEBACK_VERSION_INVALID` `{crMdReason:'missing'}`）；`\r\n→\n` 后行级提取 target-version 规范化（失败 → INVALID `{crMdReason}`）；分支：已=输入 → `stage!=='baseline' ? crMdEntry=null : crMdBase={text, sha256}`（幂等）；另一真实版本 → `WRITEBACK_VERSION_MISMATCH` `{cr, crMd:rv.value, input:version}`（两次采样间漂移，拒绝零写入）；仍 unassigned → baseline：`crMdBase={text, sha256}`、`crMdEntry=null`（并入 statusTransition）；非 baseline：`applyTargetVersionToCrMd` 生成 `crMdEntry={path, beforeSha256, afterSha256, afterText}`。
   - 返回 `{ inputVersion: version, crMd: crMdEntry|null, backlog: backlogEntry|null, crMdBase: {text, sha256}|null }`。
2. `applyTargetVersionToCrMd(text, version)`（行级编辑硬失败纪律，NFR-3/纪律 #1）：
   - 先 `\r\n→\n`；`matchFrontmatter` 失败 → `WRITEBACK_VERSION_INVALID` `{crMdReason:'missing'}`；frontmatter 内无 `^target-version:` 行 → 同码硬失败；命中行 `replace(/^(target-version:).*$/, '$1 ' + version)` 后重建 frontmatter；**必须校验替换结果**：替换后文本不同 → 正常返回；相同（已等于目标版本）→ 幂等放行返回原文；禁止「匹配不到仍静默返回原文」的降级路径。
3. `editBacklogEntryTargetVersion(text, cr, version)`（B-CODE-001 口径，SDD §4.3 ②）：
   - `span = norm.slice(blk.start, blk.end)` 单行定点替换 `^([ \t]*)target-version:.*$` → `${ind}target-version: ${version}`；`replaced === spanText` → 硬失败（`WRITEBACK_VERSION_INVALID`）；返回 `norm.slice(0, blk.start) + replaced + norm.slice(blk.end)`——**禁止**用 `block.text` split/join 重建（块尾换行不在 `block.text` 内）。
4. crctl.test.mjs 新增 plan 向量（临时目录直接构造 cr.md/_backlog 内容，不依赖完整夹具，SDD §6.2 AC-4 可达性）：
   - 语义复核四分支：仍 unassigned → 放行生成条目；已=输入 → 幂等 null（baseline 给 crMdBase）；已=另一真实 → MISMATCH；非法 → INVALID；
   - backlog 预检五向量：unassigned → 回灌条目；等值 → null；另一真实 → `WRITEBACK_BACKLOG_VERSION_MISMATCH`；缺失 → `ENTRY_NOT_IN_BACKLOG`；重复 → `WRITEBACK_BACKLOG_ENTRY_DUPLICATE`；缺行/非法 → INVALID（含 `backlogReason`）；
   - 同源断言：`authority.path !== txws` → `WRITEBACK_STATE_MISMATCH`（复用既有码、extra 保持既有 `{cr, phase}` 形状、证据进 message）；
   - 行级编辑硬失败：frontmatter 缺 `target-version` 行 → INVALID；backlog 替换未命中 → INVALID；CRLF 输入与 LF 输出等价断言。

## 4. 验收条件

1. `node --test --test-reporter=dot --test-skip-pattern "CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引" skills/shared/crctl/scripts/test/crctl.test.mjs` 通过（exit 0）：新增 plan 向量全绿。
2. 静态核对：`WRITEBACK_AUTHORITY_DRIFT` 零残留（grep workspace-transactions.mjs）；同源硬失败仅用 `WRITEBACK_STATE_MISMATCH`；新增公开错误码仅 `WRITEBACK_BACKLOG_VERSION_MISMATCH` / `WRITEBACK_BACKLOG_ENTRY_DUPLICATE` 两个。
3. `planVersionRefill` 无文件写入副作用（代码审阅：只读文件 + 纯函数变换；失败路径零写入）。
4. 行级编辑硬失败纪律：替换未命中一律 throw，无静默返回原文路径（代码审阅 + 向量覆盖）。

## 5. 完成标志

crctl.test.mjs plan 向量全部通过（exit 0）；错误码清单符合 B-SDD-04 收敛口径；代码 review 自检通过；`_index.yml` 本 TASK 标 done。

## 6. 接口契约

- 消费：TASK-01 产出 `guardWritebackVersion` 的 authority 快照语义；`matchEntryBlock(text, id)` → `{start, end, text, indent}`；`normalizeTargetVersion(raw, {allowUnassigned})`；`backlogLines(text)`；`matchFrontmatter(text)`。
- 产出（供 TASK-03 消费）：
  - `planVersionRefill({txws, authority, cr, stage, version})` → `{inputVersion: string, crMd: RefillEntry|null, backlog: RefillEntry|null, crMdBase: {text: string, sha256: string}|null}`；`RefillEntry = {path: string, beforeSha256: string, afterSha256: string, afterText: string}`；
  - 模块私有 `applyTargetVersionToCrMd(text, version)` → string；`editBacklogEntryTargetVersion(text, cr, version)` → string；
  - throw 码：`WRITEBACK_STATE_MISMATCH`（复用）、`ENTRY_NOT_IN_BACKLOG`、`WRITEBACK_BACKLOG_ENTRY_DUPLICATE`、`WRITEBACK_BACKLOG_VERSION_MISMATCH`、`WRITEBACK_VERSION_INVALID`（extra 见 SDD §3.2）。

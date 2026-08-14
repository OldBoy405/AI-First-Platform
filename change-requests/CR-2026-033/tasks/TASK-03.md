---
id: CR-2026-033-TASK-03
type: TASK
cr-ref: CR-2026-033
plan-ref: "change-requests/CR-2026-033/plan.md"
sdd-ref: "change-requests/CR-2026-033/sdd.md"
title: latest-checkpoint 编辑器与三个纯函数（T03b）
slug: checkpoint-editor-pure-functions
status: pending
estimate: 12h
depends-on:
  - CR-2026-033-TASK-02
created: 2026-08-13T19:06:07+08:00
---

## 任务描述

实现 latest-checkpoint 账本编辑器与 batch-id/remote 分类三个无 I/O 纯函数，全部直接单测。此任务只落纯函数，不接 Git。

## 涉及文件 / 模块

- 修改 `tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（新增三个导出纯函数）
- 新增 `tools/skills/shared/crctl/scripts/test/checkpoint-pure.test.mjs`

## 实现要点（引用 SDD §2.1/§2.2/§3.2/§3.3）

1. `editLatestCheckpoint(backlogText, cr, snapshot)`：用 TASK-02 的 locator 取得当前 CR block，再由 editor 校验目标 CR/owned key（`latest-checkpoint`、旧 `checkpoints[]`/`remote-ref`/`last-push-*`）重复或结构畸形时硬失败；整块替换 `latest-checkpoint` 并删除旧字段；不改 `cr.md`、其他 CR、未知字段或注释；CRLF→LF 后处理。
2. `checkpointBatchId({ cr, graphDigest, repositories })`：canonical JSON（键序固定、repositories 按 repo id 排序、无空白）后 `sha256(...).slice(0, 16)`；不含 message/actor/时间/路径/txId。
3. `classifyCheckpointRemote({ remoteSha, sourceSha, remoteIsSourceAncestor, sourceIsRemoteAncestor, journalSaysPublished })`：返回 `confirmed|pushable|create|advanced|diverged|history-rewritten` 分类；不改共享 `classifyRemoteCommit()`。

## 验收条件

1. 纯函数单测：同 facts 同 batch-id；任一 source/remote-ref/graphDigest 变化则 batch-id 变化；message/actor 不影响。
2. editor 单测：CRLF 输入、EOF 条目、旧字段一次删除、其他 CR 条目与注释原样保留；当前 CR/owned key 重复或畸形由 editor 硬失败，不要求 locator 改变既有行为。
3. classifier 六分类覆盖（含 journalSaysPublished + remote 不含 source → history-rewritten）。

## 完成标志

三纯函数 + 单测全绿；commit 到 tools 仓 `requirement/CR-2026-033`。

## 接口契约

- 消费：TASK-02 的 `matchEntryBlock(text, id) -> {start,end,text,indent}|null`。
- 产出：
  - `editLatestCheckpoint(text, cr, snapshot) -> string`（after image）
  - `checkpointBatchId({cr, graphDigest, repositories}) -> string`（16-hex）
  - `classifyCheckpointRemote({remoteSha, sourceSha, remoteIsSourceAncestor, sourceIsRemoteAncestor, journalSaysPublished}) -> string`
  - 均为纯函数，TASK-04 消费。

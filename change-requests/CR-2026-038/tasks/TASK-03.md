---
id: CR-2026-038-TASK-03
type: TASK
cr-ref: CR-2026-038
plan-ref: CR-2026-038-plan
sdd-ref: CR-2026-038-sdd
title: 实现 backlog 条目语义 merge tree
slug: semantic-backlog-merge
authority: tools
status: pending
estimate: 10h
depends-on: [CR-2026-038-TASK-02]
owner: Ray
created: "2026-08-14T21:22:00+08:00"
updated: "2026-08-14T21:22:00+08:00"
---

# TASK-03：实现 backlog 条目语义 merge tree

## 1. 任务描述

在 knowledge-base repo 的 merge prepare 中，以最新 trunk `_backlog.yml` 原文为基底，只替换原 CR source 中目标 CR 的唯一完整条目；用原生 Git 临时 index 构造 synthetic tree，同时保持最终 merge commit parents 为最新 trunk 与原 source。

输入为 SDD §2.6、§4.6～§4.7 和 TASK-02 后稳定的 transaction module。输出为 initial prepare 与 remote rebuild 共用的 semantic merge helper。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
- 必要时仅将 locator 最小下沉至现有 `skills/shared/crctl/scripts/lib/yaml-subset.mjs`
- `skills/shared/crctl/scripts/test/merge-tx.test.mjs`

## 3. 实现要点

1. 提炼 `replaceBacklogEntry(trunkText, sourceText, crId)` 纯函数；LF 解析视图定位唯一块，用原始 offset 切片，非目标 prefix/suffix 字节不变。
2. 完整采用 source 目标块，包括 owners、latest-checkpoint 和未知 v2 字段；不得读取、推导或生成 backlog status。
3. trunk/source 目标缺失、重复或边界非法分别硬失败；禁止整文件 ours/theirs、行号拼接或模糊回退。
4. 增加 `gitReadBlobRaw(repo, treeish, path)` 固定 `git cat-file blob` argv，返回未 trim 的 Buffer/UTF-8；不复用会裁剪 stdout 的 helper。
5. `prepareMergeTree()` 对 knowledge-base 使用 `hash-object`、临时 `GIT_INDEX_FILE`、`read-tree source`、`update-index --cacheinfo`、`write-tree`、`commit-tree -p source`、`merge-tree --write-tree`；finally 删除临时 index。
6. 最终 merge commit 显式 `-p baseSha -p sourceSha`；synthetic commit 不成为 parent/ref。
7. initial prepare 与 origin stale rebuild 必须调用同一个 helper；其他 repo 保持普通 `merge-tree --write-tree`。

## 4. 验收条件

- [ ] 参数测试覆盖目标首/中/末、trunk 前/后/两侧新增 CR、注释/空行/未知字段、LF/CRLF，非目标 prefix/suffix 字节等于 trunk。
- [ ] source 目标的 owners/latest-checkpoint/未知字段完整保留，helper 静态/行为测试证明不读写 backlog status。
- [ ] trunk/source 缺失、重复或结构非法返回约定错误码，所有 repo remote refs 零前进。
- [ ] merge 集成最终 tree 保留 trunk 新 CR 并采用 source 目标条目；真实其他文件冲突仍 `MERGE_PREPARE_CONFLICT`。
- [ ] 最终 merge commit parents 精确为 latest base + original source，synthetic commit 不在 parent/ref。
- [ ] initial prepare 与 remote stale rebuild 语义一致，tools/multica repo merge 行为零回归。
- [ ] `node --test skills/shared/crctl/scripts/test/merge-tx.test.mjs` 全绿。

## 5. 完成标志

backlog pure-function 与三仓 merge fixture 全绿；任何不可唯一解析场景均在 publish 前硬失败，final ancestry 契约保持。

## 6. 接口契约

**消费 TASK-02**：现有 `mergeCr()`/Git adapter 与稳定 `workspace-transactions.mjs` 文件所有权；不调用 writeback callback。

**产出给现有 merge flow**：

```text
replaceBacklogEntry(trunkText:string, sourceText:string, crId:string) -> string
gitReadBlobRaw(repo:string, treeish:string, path:string) -> Buffer
prepareMergeTree({repoId,repoPath,baseSha,sourceSha,crId,tmpRoot}) -> {
  treeSha:string, baseSha:string, sourceSha:string
}
```

`prepareMergeTree` 的 initial/rebuild 调用签名必须一致；最终 commit 始终使用返回的 base/source 原始 SHA 作为 parents。

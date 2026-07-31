---
id: CR-2026-003-TASK-01
type: TASK
cr-ref: CR-2026-003
plan-ref: "change-requests/CR-2026-003/plan.md"
sdd-ref: "change-requests/CR-2026-003/sdd.md"
title: crctl embedded 事件 commit_sha 占位符（pendingCommitSha）
status: done
estimate: 3h
depends-on: []
assignee: ""
created: "2026-07-31T21:00:00+08:00"
---

## 任务描述
修缺陷 A 的 crctl 半边：embedded 模式的 status 事件不再用恒定空串作 `commit_sha`，改为进程内唯一占位符，消除 `cr_sync_event` 幂等键 `(cr_id, commit_sha, event_kind)` 上的碰撞。仓库：tools。

## 涉及文件
- `skills/shared/crctl/scripts/crctl.mjs`：新增 `pendingCommitSha()`（`pending:{ms}:{pid}:{seq}`，进程内单调 seq）；`cmdAdvance` 的 `commit_sha: committed ? gitHeadSha(ws) : ''` 改为 `: pendingCommitSha()`
- `skills/shared/crctl/scripts/test/crctl.test.mjs`：新增用例

## 实现要点
- SDD §4.1。占位符仅两行改动；不碰非 embedded 路径（committed 分支仍用真实 HEAD sha）。
- `pending:` 前缀是与 multica 服务端（T02）的跨语言契约，测试断言必须引用该字面量。

## 验收条件
1. JS 测试：同一进程连续两次 embedded advance（可用两个不同 CR 或同 CR 两连推），产出的 outbox 事件 `commit_sha` 均以 `pending:` 开头且互不相同。
2. JS 测试：非 embedded advance 的事件 `commit_sha` 仍为真实 git HEAD sha（不受影响）。
3. 既有 crctl 测试套件全绿（回归）。

## 完成标志
node --test 全绿 + 完成记录回填。

## 完成记录（2026-07-31）

- **提交**：tools@0c8e306。
- **实现**：`pendingCommitSha()`（`pending:{ms}:{pid}:{seq}`，进程内单调 seq）+ `cmdAdvance` 接入（committed 分支不变仍用真实 HEAD sha）。
- **实现期新发现（SDD 未预见）**：outbox 文件名嵌入 `commit_sha.slice(0,8)`，占位符切出 `pending:` 含冒号——**Windows 文件名非法**，事件文件会写失败即事件丢失。补文件名片段消毒（`replace(/[^A-Za-z0-9]/g,'')`，仅影响文件名，事件 JSON 内容与契约前缀不动）。
- **测试**：新用例（双 embedded 占位符互异 + 非 embedded 真实 sha 不受影响 + 文件名无冒号断言）+ 旧 `--no-commit` 契约测试更新到新口径（空串 → pending: 前缀）。crctl 套件 21/21 全绿。

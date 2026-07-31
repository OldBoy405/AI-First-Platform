---
id: CR-2026-003-TASK-01
type: TASK
cr-ref: CR-2026-003
plan-ref: "change-requests/CR-2026-003/plan.md"
sdd-ref: "change-requests/CR-2026-003/sdd.md"
title: crctl embedded 事件 commit_sha 占位符（pendingCommitSha）
status: pending
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

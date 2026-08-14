---
spec-id: ai-first-platform
version: "0.3"
id: CR-2026-030-TASK-03
type: TASK
cr-ref: CR-2026-030
plan-ref: "change-requests/CR-2026-030/plan.md"
sdd-ref: "change-requests/CR-2026-030/sdd.md"
title: 实现 Owner 正式移交原语
slug: owner-formal-handover
status: pending
estimate: 12h
depends-on: [CR-2026-030-TASK-02]
created: "2026-08-11T02:34:00+08:00"
---

# TASK-03 实现 Owner 正式移交原语

## 1. 任务描述

落实 SDD §2.2～§2.5、§3.5～§3.6、§4.4～§4.7，将 `owner-set` 收敛为双投影、历史、通知、隔离 Git commit 和失败回滚一致的正式移交原语。`handover-cr` 后续只需消费该结构化结果并发布；`resume-from-remote` 不再承担 Owner 写入。

## 2. 涉及文件 / 模块

- tools：`skills/shared/crctl/scripts/crctl.mjs`
- tools：`skills/shared/crctl/scripts/test/crctl.test.mjs`

## 3. 实现要点

- 新增内部 `OwnerChangeFact`/`OwnerHistoryEntry` 语义：`note` 只进入 owner-history 与 inbox，不进入 owners outbox、成功 audit 或当前投影。
- clean precheck 通过 `controlledGit(..., {audit:false})` 获取 tracked staged/unstaged；untracked-only 不阻塞。
- 双投影一致性先校验，真实变化仅生成一个 `handoverAt`；requirement 角色同步兼容 owner。
- 两账本候选经一次 `casWriteMulti()`，随后只 add 两路径并复核 staged set，正式 commit 后读真实 SHA。
- add/commit/隔离校验失败按开始快照 CAS 恢复、撤销本次暂存并复核 clean；外部变化不得 reset/checkout。
- commit 成功后尝试 owners 与 inbox 两事件，共用 SHA；outbox 失败非阻断。

## 4. 验收条件

1. 双投影漂移、staged-only、unstaged-only、mixed tracked fixture 均返回零副作用结构化错误；untracked-only 允许继续。
2. 三角色真实 handover 各只追加一条 owner-history，不追加 handover-history；唯一时间戳贯穿两投影、history、notify、audit 与 payload。
3. 成功 commit 只含 `cr.md` 与 `_backlog.yml`；owners/inbox 共用真实 SHA，owners/audit 显式无 `note`。
4. add/commit/isolation 失败恢复 clean baseline；CAS/unstage/clean 恢复失败返回 `OWNER_COMMIT_ROLLBACK_FAILED` 并保留外部变化。
5. clean 同值重放 `changed=false` 且 audit、commit、outbox、时间和历史不变。

## 5. 完成标志

TASK-01 中 AC-7～AC-16 对应测试转绿，owner-set 成功与所有注入失败路径均有可执行证据，`tasks/_index.yml` 中 TASK-03 标记 `done`。

## 6. 接口契约

- **消费**：`casWriteMulti(writes)`；`controlledGit(ws, sub, args, cwd, caller, options?: {audit?: boolean})`。
- **产出**：`owner-set <cr> --role <requirement|development|test> --owner <id> [--note <text>]` 返回 `{changed, role, from, to, handover_at?, commit_sha?, warnings?}`；错误码 `OWNER_PROJECTION_DRIFT`、`OWNER_WORKTREE_DIRTY`、`OWNER_COMMIT_FAILED`、`OWNER_COMMIT_ROLLBACK_FAILED`。

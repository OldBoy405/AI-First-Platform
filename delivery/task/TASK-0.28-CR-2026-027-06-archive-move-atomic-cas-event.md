---
spec-id: ai-first-platform
version: "0.28"
id: CR-2026-027-TASK-06
type: TASK
cr-ref: CR-2026-027
plan-ref: "change-requests/CR-2026-027/plan.md"
sdd-ref: "change-requests/CR-2026-027/sdd.md"
title: archive-move 三账本 CAS 原子化 + archive event + 收件人
slug: archive-move-atomic-cas-event
status: pending
estimate: 10h
depends-on: ["CR-2026-027-TASK-01"]
created: "2026-08-09T23:35:00+08:00"
---

# TASK-06 — archive-move 三账本 CAS 原子化（FR-11）

## 任务描述

将归档事件与账本移动收进同一原子写入：archive-move 在内存构造 archive event，与 backlog→history 移动 + `_index.yml` 终态更新经同一 `casWriteMulti` 三文件写入，CAS 成功后发 archive outbox；事件与三账本要么同生要么同灭。

## 涉及文件 / 模块

- tools `skills/shared/crctl/scripts/crctl.mjs`（`cmdArchiveMove`、`editArchiveMove`、`editInboxEmit` 行生成逻辑提取）
- tools `skills/shared/crctl/scripts/test/crctl.test.mjs`

## 实现要点（SDD §2.2/§3.2）

1. 前置态放宽：`resolveCrState` 当前 status ∈ {archived, rejected, withdrawn}；`--final-status` 必须与当前 status 完全一致，否则 `FINAL_STATUS_MISMATCH` 硬失败（D-8）
2. 三文本读取：`_backlog.yml` + `_history.yml` + `_index.yml` → 内存生成三份新文本（backlog 移除条目、history 追加终态条目 + notify-log 事件、index 更新 status/archived-at/可选 writeback-spec-id 三字段）→ 同一 `casWriteMulti`
3. archive event：复用 `editInboxEmit` 的日志行格式（提取共享行生成函数），事件条目写入 **history 条目**的 notify-log；payload 富化 `final-status`/`archive-reason`（中文原文不经 Shell 转义）/`writeback-spec-id`/`archived-at`
4. 收件人（D-10）：`to = unique(owners.requirement.id, owners.development.id, owners.test.id)`；缺 owners 回退顶层 `owner`；最终为空 → CAS 前 `ARCHIVE_RECIPIENTS_MISSING`
5. 重复调用（TD-BL-3 拍板）：CR 已移出 backlog 时走受控 history 检测——final-status 一致 → `{ result: 'already-archived', finalStatus }` 零写入不发 outbox；不一致 → `FINAL_STATUS_MISMATCH`；history 无 → `CR_STATUS_NOT_FOUND`
6. CAS 成功后 `emitOutboxEvent(archive)`；任一 event/文件结构错误或 CAS 冲突时事件与三份账本均不写
7. 普通 `inbox-emit` 空 `--to` 校验在 TASK-07 落地

## 验收条件

1. 三种终态（archived/rejected/withdrawn）归档均三账本同批写入；`_index.yml` 终态三字段正确（AC-4/AC-15）
2. 中文 archive reason 完整保留（不经 Shell 转义）
3. 三角色收件人去重、legacy 顶层 owner 回退、空收件人 `ARCHIVE_RECIPIENTS_MISSING`、可选 spec-id 均按契约
4. 重复调用 → `already-archived`（含 finalStatus）零写入；final-status 不一致 → `FINAL_STATUS_MISMATCH`；history 无 → `CR_STATUS_NOT_FOUND`
5. CAS 冲突或事件结构错误 → 事件与三账本均不写；CAS 成功后 outbox 事件存在
6. `--final-status` 与 cr.md 当前 status 不一致 → 硬失败（AC-13）

## 完成标志

crctl.test.mjs 归档用例全绿（三终态/收件人矩阵/重复调用/outbox 时序/CRLF）；既有 inbox-emit 通知路径不回归。

## 接口契约

- 消费：TASK-01 产出的 tools worktree；TASK-04 的 archived 门禁（前置态 reachability）
- 产出：`cmdArchiveMove` 三账本 CAS（`already-archived`/`FINAL_STATUS_MISMATCH`/`ARCHIVE_RECIPIENTS_MISSING`）；TASK-07 的 inbox-emit 校验、TASK-09 的 cr-archive 契约同步、TASK-10 的 AC-15/AC-16 验收基于本产出

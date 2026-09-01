---
id: CR-2026-057-TASK-02
type: TASK
cr-ref: CR-2026-057
plan-ref: "change-requests/CR-2026-057/plan.md"
sdd-ref: "change-requests/CR-2026-057/sdd.md"
target-version: unassigned
title: register 硬校验 --target-version（FR-12）
slug: register-target-version-guard
status: pending
estimate: 8h
depends-on: [CR-2026-057-TASK-01]
created: 2026-08-31T22:00:00+08:00
---

## 任务描述

`crctl register` 的 `--target-version` 由可选改必填并硬校验（FR-12/AC-12）：删除 `targetVersion = input.targetVersion ?? 'tbd'` 缺省值（workspace-transactions.mjs 第 589 行，SDD §10 #1），校验位于 `registerCr` 顶部、锁/journal/fetch/账本写之前——失败零写入。同步 `cmdRegister` 参数面与 HELP 文本。

输入条件：TASK-01 完成（消费 `normalizeTargetVersion`）；tools CR worktree。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（`registerCr` 顶部校验、inputDigest、`buildRegistrationTexts`、返回对象）
- `skills/shared/crctl/scripts/crctl.mjs`（`cmdRegister`、HELP 行）
- `skills/shared/crctl/scripts/test/register-tx.test.mjs`（夹具适配 + 负向用例组，cmd-02）

## 实现要点

1. §4.2 时序：`registerCr` 第 1 步既有 owners/origin/year/summary 校验不动 → 第 2 步 NEW `tv = normalizeTargetVersion(input.targetVersion)`，`!tv.ok` → `throw TxError('REGISTER_VERSION_INVALID', ...)`（此时无任何持久化痕迹）。
2. `--target-version` **不**进入 `cmdRegister` 必填 BAD_ARGS 循环：缺省走规范化层返回 `REGISTER_VERSION_INVALID`（SDD §3.1 契约）。
3. `inputDigest` 与 `buildRegistrationTexts` 使用规范化值 `tv.value`（幂等判定与 cr.md/backlog 文本均落规范串）；`registerCr` 返回对象补 `targetVersion: tv.value`。
4. 幂等：同 `--registration-key` 且规范化后同值 → 既有续跑；规范化后不同值 → 既有 `REGISTRATION_INPUT_MISMATCH`（不另造错误码）。
5. `register-tx.test.mjs`：`regArgs` 补 `--target-version unassigned`；新增负向组（缺 flag / 空串 / `tbd` / `TBD` / `n/a` / `pending` / `0.29-rc`）断言 `REGISTER_VERSION_INVALID` + 零写入（无 cr.md、无 backlog 新条目、无 worktree、无 journal）；正向 `unassigned` / `0.30` / `v0.30`→写入 `0.30`，断言 cr.md 与成功 JSON `targetVersion` 为规范化值；幂等续跑断言。

## 验收条件

1. 负向 7 类输入（缺 flag、空、`tbd`、`TBD`、`n/a`、`pending`、`0.29-rc`）→ 非零退出、`REGISTER_VERSION_INVALID`、零写入。
2. 正向 `unassigned` / `0.30` / `v0.30` → 成功，cr.md `target-version` 与 JSON `targetVersion` 为规范化值（`v0.30` → `0.30`）。
3. 同 key 重跑：同值续跑同 CR；异值 `REGISTRATION_INPUT_MISMATCH`。
4. cmd-02 绿（AC-12 全项）；既有 register-tx 用例不新增失败。

## 完成标志

cmd-02 全绿；AC-12 逐项核对通过；提交 `[cr] implement CR-2026-057 TASK-02`。

## 接口契约

- 消费：`normalizeTargetVersion(raw, { allowUnassigned: true })`（TASK-01，签名见其卡）；既有 `loadOrCreateJournal` / `buildRegistrationTexts` 骨架不改语义。
- 产出（供下游测试与 cr.md 消费）：成功 stdout JSON 增字段 `targetVersion: string`（规范化值）；失败 stderr `{error:{code:'REGISTER_VERSION_INVALID',message}}`；cr.md/backlog 条目 `target-version` 恒为规范化值。
- 不产出新模块导出；错误码族不新增（幂等冲突复用 `REGISTRATION_INPUT_MISMATCH`）。

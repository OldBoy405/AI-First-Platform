---
spec-id: ai-first-platform
version: "0.33"
id: CR-2026-060-TASK-01
type: TASK
cr-ref: CR-2026-060
plan-ref: "change-requests/CR-2026-060/plan.md"
sdd-ref: "change-requests/CR-2026-060/sdd.md"
target-version: "0.33"
title: G1 注册与 authority（flag、mode 裁决、pre-review、advance guard）
slug: register-authority-mode-guards
status: pending
estimate: 16h
depends-on: []
created: 2026-09-03T00:35:00+08:00
---

## 任务描述

在 tools CR worktree 落地 G1：`crctl register` 新必填 `--target-spec-id`、统一结果 builder（含 `registrationAt` 持久化）、双账本字段、`resolveTargetSpecMode` / `resolveWritebackAuthorityStrict`、pre-review gate、advance 层零写入 guard，以及 `requirement-register` Skill 与 `requirement-authoring.pipeline.json` 的 register 输入合同。本 TASK 不实现 writeback/archive 命令分支（TASK-04 消费本 TASK 产出的解析器）。

输入条件：CR status=`developing`；tools CR worktree 实施基线 HEAD=`860288ce96d568ed31a86a8c478d1cfa7f1087e9`（SDD §10；符号行号以工作区实际文件核对）。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`：`cmdRegister`（:3080，删除 :3098 早退与 :3103 第二个 `nowIso()`）、`cmdGate`（:956，新增 `--mode pre-review` 分支）、`preflightAdvance`（:963，挂 `assertRequirementReviewAdvanceGuard`）、新增 `resolveTargetSpecMode` / `resolveWritebackAuthorityStrict` / `runPreReviewGateChecks` / `assertRequirementReviewAdvanceGuard` / `buildRegisterResult`
- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`：`registerCr`（:654；`inputDigest` :679 纳入 `targetSpecId`；`recoverCommand` :684 含 `--target-spec-id`）、`buildRegistrationTexts`（:347，新增 `target-spec-id` 行且全部时间字段消费单一 `registrationAt`）
- `skills/requirement/requirement-register/SKILL.md`：参数表 +`target_spec_id`；命令模板 +`--target-spec-id`；消费 snake_case 成功 JSON
- `pipeline-templates/requirement-authoring.pipeline.json`：inputs 增加 required `registration_key`/`target_spec_id`/`target_version`（若尚未必填）；register 节点只透传 `cr_id + operational_workspace`
- `skills/shared/crctl/scripts/test/register-tx.test.mjs`（cmd-02）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`（cmd-03：gate/advance 向量）

禁止改动：`cmdVersionSet` / `normalizeTargetVersion` / `performAdvance` 的 commit/outbox/audit 内核 / `durable-tx.mjs` / `gates.json` / `rules.json` / `multica` 仓。

## 实现要点

1. `cmdRegister` 在既有必填 flag 循环**之前**校验 `--target-spec-id`：缺失/空 → `REGISTER_TARGET_SPEC_ID_REQUIRED`（优先且唯一，不落 `BAD_ARGS`）；不匹配 `^[a-z0-9][a-z0-9._-]*$` 或含 `/` `\` CR LF → `REGISTER_TARGET_SPEC_ID_INVALID`。`registerCr` 内防御性复查（同码，先于锁/journal）。
2. `payload.registrationAt = payload.registrationAt || nowIso()` 随 `save('allocated')` 冻结；`buildRegistrationTexts({..., now: registrationAt})`；owners outbox 的 `assigned-at`/`changes[].at` 原样 = `result.registrationAt`。
3. 新增 `buildRegisterResult`：成功/幂等/恢复共用；删除 `:3098` `if (!result.changed) return ok(...)` 早退。`changed=false` 同构输出 snake_case 全键，`outbox=null`、`warnings=[]`。
4. `resolveTargetSpecMode(ctx, cr, { authority })` 纯读取、自身不解析路径；两处均缺 → `legacy`；单侧/非法/不一致 → 抛 `TARGET_SPEC_AUTHORITY_DRIFT`（`extra.kind ∈ {missing|invalid|mismatch}`）。读入 `\r\n→\n`；跨行匹配失败硬失败。
5. `resolveWritebackAuthorityStrict(ctx, cr)` 只读、永不回退；txws 缺失/不自洽 → `WRITEBACK_SPEC_REQUIRED`；非 post-finalize → 既有 `WRITEBACK_STATE_MISMATCH`。**禁止** new-mode 消费 `resolveWritebackAuthorityPath` 的 cr-worktree 回退（该函数保持永不抛，仅 legacy 版本守卫使用）。
6. `runPreReviewGateChecks`：authority=CR worktree；kind→check code 映射 missing→`TARGET_SPEC_AUTHORITY_MISSING`、invalid→`_INVALID`、mismatch→`_DRIFT`；new mode `unassigned` → `TARGET_VERSION_UNASSIGNED`；fail 时外层 `GATE_BLOCKED`、exit 1、零写入。`--mode pre-review` 配其他 `--for` → `BAD_ARGS`。
7. `assertRequirementReviewAdvanceGuard` 挂 `preflightAdvance`、`runGateChecks` 之前、仅 `flags.to==='requirement-reviewing'`；new+unassigned → `GATE_BLOCKED`/`TARGET_VERSION_UNASSIGNED`；`preflightAdvance` 自身无写入。legacy 零改动。

## 验收条件

1. 缺/空 `--target-spec-id` → `REGISTER_TARGET_SPEC_ID_REQUIRED` 且零写入（cmd-02）。
2. 非法 spec id → `REGISTER_TARGET_SPEC_ID_INVALID` 且零写入（cmd-02）。
3. 成功注册：`cr.md` 与 `_backlog.yml` 的 `target-spec-id` 全等；JSON 含 `cr_id/target_spec_id/operational_workspace/tx_id/target_version/side_effects/recover_command/outbox/warnings`（cmd-02）。
4. 同 key 同输入重跑 `changed=false`、无新 commit/outbox/worktree，JSON 仍同构（`outbox=null`）；同 key 换 spec → `REGISTRATION_INPUT_MISMATCH` 零写入（cmd-02）。
5. ledger `owners.*.assigned-at` === outbox payload `owners.*.assigned-at` === `result.registrationAt`（精确字符串相等）；同 key 重试两次 `registrationAt` 相等；`recover_command` 含 `--target-spec-id` 且可过新必填校验（cmd-02）。
6. 单侧缺失/非法/不一致 → 顶层 `TARGET_SPEC_AUTHORITY_DRIFT`（kind 进 extra）零写入；两处均缺 → `legacy`（cmd-02）。
7. new mode `unassigned`：`crctl gate --for requirement-reviewing --mode pre-review` 与公开 `crctl advance --to requirement-reviewing --trigger review-requirement` 均 `GATE_BLOCKED`/`TARGET_VERSION_UNASSIGNED`、exit 1，且 cr.md/annotation/review-loop/trace/outbox/journal/commit/attempt 全部不变（cmd-03）。
8. 既有 register-tx / crctl.test.mjs 用例除 §5.3 BR-1 外不新增失败。

## 完成标志

cmd-02 新增向量全绿；cmd-03 中 gate/advance 直连拒绝向量全绿；`crctl.mjs` 导出本 TASK 接口契约所列函数；提交 `[cr] implement CR-2026-060 TASK-01`；`crctl task done CR-2026-060 --task CR-2026-060-TASK-01`。

## 接口契约

- 消费：无（本 CR 首个基元 TASK）。既有 `normalizeTargetVersion` / `readCrMdTargetVersion` / `readBacklogTargetVersionField` / `resolveOperationalWorkspace` / `registerCr` 事务内核只扩展、不改签名语义。
- 产出（供 TASK-02/TASK-04 与测试消费，签名冻结）：
  - `resolveTargetSpecMode(ctx, cr, { authority: { path: string, source: string } }) → { mode: 'new', targetSpecId: string } | { mode: 'legacy' }`；失败抛 `TxError('TARGET_SPEC_AUTHORITY_DRIFT', message, { kind: 'missing'|'invalid'|'mismatch' })`
  - `resolveWritebackAuthorityStrict(ctx, cr) → { path: string, source: 'transaction-workspace' }`；失败抛 `TxError('WRITEBACK_SPEC_REQUIRED' | 'WRITEBACK_STATE_MISMATCH', ...)`
  - `buildRegisterResult(ctx, { cr, journal, payload, changed }) → { cr, txId, phase, changed, targetVersion, targetSpecId, registrationAt, sideEffects, recoverCommand, operationalWorkspace }`
  - `runPreReviewGateChecks(ws, cr) → { cr, for: 'requirement-reviewing', mode: 'pre-review', pass: boolean, checks: Array<{ type, code, ok, why }> }`
  - `assertRequirementReviewAdvanceGuard(ws, cr, ctx) → void`（失败走 `fail('GATE_BLOCKED', ...)`）
  - `cmdRegister` JSON：`ok({ op:'register', cr_id, target_spec_id, operational_workspace, tx_id, phase, changed, target_version, side_effects, recover_command, outbox, warnings })`
- CLI：`crctl gate <cr> --for requirement-reviewing --mode pre-review`；`crctl register ... --target-spec-id <id>`。

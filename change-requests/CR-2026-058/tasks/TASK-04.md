---
id: CR-2026-058-TASK-04
type: TASK
cr-ref: CR-2026-058
plan-ref: "change-requests/CR-2026-058/plan.md"
sdd-ref: "change-requests/CR-2026-058/sdd.md"
target-version: 0.30
title: merge-fixture 参数化与 writeback-tx 集成测试改写（FR-4 集成层，AC-1/AC-2/AC-3/AC-6）
slug: writeback-tx-refill-fixtures
status: pending
estimate: 14h
depends-on: [CR-2026-058-TASK-03]
created: 2026-09-01T16:50:00+08:00
---

## 1. 任务描述

目标：按 FR-4/AC-4 改写 CR-2026-057 已合入的 `writeback-tx.test.mjs` 契约（删除/改写「cr.md=unassigned + 输入真实版本 → `WRITEBACK_VERSION_UNASSIGNED`」断言），并新增回灌正向/冲突/故障点/FR-3 分叉/CLI 信封夹具（AC-1/AC-2/AC-3/AC-6 唯一证据）。`merge-fixture.mjs` 增加 `targetVersion` 参数化（SDD §6.3 证据 6）。

背景：旧断言把「unassigned + 真实输入」当拒绝绿灯契约，本 CR 语义改为放行并回灌（PRD FR-4）。direct tasks/traceability 回灌夹具必须用 `status=writing-back` + 两账本 `unassigned`（merged 夹具 `status=merging` 不满足 tasks/traceability 生成器前置，不可作 direct 夹具——SDD §6.2 AC-2.3 可达性）。

输入条件：TASK-03 完整接线（payload 冻结 + entries 合成 + 恢复协议 + §4.5 baseline 合成）。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/test/merge-fixture.mjs`（`makeCodeApprovedFixture({ targetVersion = '0.2' })` 参数化：cr.md 与 `_backlog.yml` 条目补 `target-version: <v>` 行；默认 0.2 保持既有行为；`makeMergedFixture` 同步透传）
- `skills/shared/crctl/scripts/test/writeback-tx.test.mjs`（改写 + 新增夹具）

## 3. 实现要点

1. **保留既有断言**（不改）：两侧真实但不一致 → `WRITEBACK_VERSION_MISMATCH` + 六项零观察点；输入 `n/a` → `WRITEBACK_VERSION_INVALID`；输入 `unassigned`（含两侧 unassigned）→ `WRITEBACK_VERSION_UNASSIGNED`；同参重试同码。
2. **删除**「cr.md=unassigned + 输入真实版本 → UNASSIGNED」正向拒绝断言——该 (fixture, 输入) 组合的新语义是放行回灌（AC-1.1）。**UNASSIGNED 期望收敛（B-DP-03）**：改写后 `writeback-tx.test.mjs` 中 `WRITEBACK_VERSION_UNASSIGNED` 期望只允许出现在两个冻结负向向量内——`AC-1.2`（cr.md 真实 + 输入 unassigned）与 `AC-1.3`（两侧 unassigned）；原 CR-2026-057 AC-14 的 unassigned 向量并入 AC-1.2（保留六项零观察点与同参重试同码断言）。正反语义向量证明的完整规则见 §3.3 冻结向量标识与 §4 验收 2。
3. **AC-1 判定表六行 + 冻结向量标识**（merged 夹具，authority=txws；B-DP-03 正反语义向量证明的载体）：`makeMergedFixture({ targetVersion: 'unassigned' })` 参数化夹具 + 默认 `0.2` 夹具：
   - **AC-1.1（放行向量，冻结名）**：cr.md=unassigned + `0.30`（及 `v0.30` 规范化等价）→ 非版本错误（放行并回灌或既有后续错误，**不得为 `WRITEBACK_VERSION_UNASSIGNED`**）；测试名必须含冻结标识 `AC-1.1`；
   - **AC-1.2（输入侧 unassigned 负向，冻结名）**：cr.md=`0.2`（真实）+ 输入 `unassigned` → UNASSIGNED + 六项零观察点 + 同参重试同码（承接原 CR-2026-057 AC-14 的 unassigned 向量）；测试名必须含冻结标识 `AC-1.2`；
   - **AC-1.3（两侧 unassigned 负向，冻结名）**：cr.md=unassigned + 输入 `unassigned` → UNASSIGNED + 六项零观察点；测试名必须含冻结标识 `AC-1.3`；
   - 4) `0.2`+`0.9` → MISMATCH；5) `n/a` → INVALID；6) `0.2`+`0.2` → 放行不改版本字段（MISMATCH/INVALID/全等行沿用既有断言，无冻结名要求）。
4. **AC-2.1 成功回灌**（baseline 必须走 2.1）：两账本均 `unassigned` + `--target-version 0.30` → 两账本 target-version=规范化 `0.30`；`prd.md`/`sdd.md`/`plan.md`/`TASK-*.md` 哈希与调用前全等（NFR-6）；baseline status 变迁与版本回灌同一次 commit（`git show` 该 commit 同时含 cr.md status=writing-back+版本行、_backlog 版本行、specs 三文件）；tasks/traceability 各跑一次只断言版本行无新 diff（`git log --follow` 两账本路径仅首 commit 含版本行变更）。
5. **AC-2.2 backlog 冲突五向量**（txws authority 上直接构造）：1) 条目已是另一真实版本 `0.29` → exit 1、`WRITEBACK_BACKLOG_VERSION_MISMATCH`、`error.backlog=0.29`、`error.input=0.30`；2) 删除条目 → `ENTRY_NOT_IN_BACKLOG`；3) 复制条目命中>1 → `WRITEBACK_BACKLOG_ENTRY_DUPLICATE` 且 `error.count>=2`；4) 条目 target-version 非法（`n/a`）→ `WRITEBACK_VERSION_INVALID`（含 `backlogReason`）；5) 条目已=输入 `0.30`、cr.md 仍 unassigned → 放行只回灌 cr.md、backlog 版本行无 diff。全部拒绝路径：specs/candidate/journal/lock/cr.md(status+target-version)/_backlog 字节级零变化、零 commit（既有 `snapshotSixPoints` 扩展 _backlog 哈希）。
6. **AC-2.3 三故障点 + 1b 部分 apply 冻结回归**（`CRCTL_FAULT_POINT` 既有注入点，禁止发明新注入点）：
   - 1) `writeback-after-apply`：首次 exit≠0、`error.code=FAULT_INJECTED`、HEAD 无 writeback commit；同参重试 exit 0、`phase=complete`、origin 恰好一个 `writeback baseline` commit 且同时含两账本 0.30 与 baseline 业务文件；
   - direct tasks/traceability 回灌夹具（txws 直接构造 status=`writing-back` + 两账本 `unassigned`，不经 baseline）：`writeback-after-apply` 后同参重试，guard 读 cr.md 已真实版本（refill=false），cr.md 条目仅由 `payload.versionRefill.crMd` 重建，重试 commit 含 cr.md 版本行 + _backlog 版本行 + 本 stage 业务文件，stdout `files` 含两账本路径（B-SDD-01 回归）；
   - 1b：direct 夹具 + `CRCTL_FAULT_POINT=tx-apply-between-rename` → 首次 exit≠0、manifest state=`prepared`；随后夹具把 txws `_backlog.yml` 置为 `payload.versionRefill.backlog.afterText`（构造「backlog 已 after、cr.md 仍 unassigned」rename 间现场）；同参重试（不设 env）：`payload.versionRefill` 保持首次落盘值（不重算、backlog 条目不降为 null），`recoverWriteSet` 按 manifest 补齐 cr.md，commit 同时含两账本 0.30 与业务文件，stdout `files` 含两账本路径；
   - 2) `writeback-after-commit`：同参重试不新增 commit（`git log` 中 `writeback baseline` 恰好 1 条）、`phase=complete`、两账本版本行在该唯一 commit 内；
   - 3) `writeback-after-push`：同参重试 exit 0、`phase=complete`、`commit` 等于中断前 journal 已记录 sha、origin 不新增 commit、两账本保持该 commit 映像（`changed` 沿用既有 `did && !wasComplete`）。
7. **AC-3 FR-3 分叉夹具**：merged 夹具 merge 后手改 requirement worktree 副本 cr.md 的 `target-version`（不影响 txws）→ 守卫以 txws 值为准：txws=unassigned+输入真实 → 放行且只回灌 txws、worktree 文件内容不变；`code-approved` 夹具上 MISMATCH 仍优先于 `WRITEBACK_STATE_MISMATCH`；窄解析器回退（source=cr-worktree）时 refill=false → `WRITEBACK_STATE_MISMATCH` 零写入（authority 快照绑定 throw 位，message 含 guardPath/opPath）。
8. **AC-6 CLI 信封**（`runCrctl` spawn，公共 CLI 断言非库函数返回值）：1) AC-2.1 首次成功：exit 0、stdout JSON `op=writeback-apply`、`phase` 严格 `"complete"`、`changed=true`、`status=writing-back`（baseline）、`commit` 匹配 `^[0-9a-f]{40}$`、`files` 同时含 `change-requests/{CR}/cr.md` 与 `change-requests/_backlog.yml`、`recoverCommand` 含规范化 `--target-version`、stderr 不可解析为 `{error:{code}}` 成功冲突信封；2) 同参第二次：exit 0、`phase=complete`、`changed=false`、`commit`/`files` 与首次相同（仍含两账本路径）；3) AC-2.2.1 失败：exit 1、stdout 无 `phase=complete` 成功对象、stderr `error.code=WRITEBACK_BACKLOG_VERSION_MISMATCH` 且 `error.backlog`/`error.input` 扁平并入 error（不要求 `error.details`）。

## 4. 验收条件

1. `node --test --test-reporter=dot skills/shared/crctl/scripts/test/writeback-tx.test.mjs` 通过（exit 0）：全部既有保留断言 + 新增夹具全绿（AC-1/AC-2/AC-3/AC-6）。
2. **正反语义向量证明（B-DP-03，AC-4 静态核对）**：
   - 正向：`writeback-tx.test.mjs` 必须包含冻结标识 `AC-1.1`/`AC-1.2`/`AC-1.3` 各 ≥1 处（放行向量与两条合法负向向量存在且命名可核对）；
   - 反向：逐 `test(...)` 块结构化核对——任何包含 `WRITEBACK_VERSION_UNASSIGNED` 期望的测试块，其测试名必须含 `AC-1.2` 或 `AC-1.3`；旧「cr.md=unassigned + 真实输入 → UNASSIGNED」正向拒绝断言与该规则不相容（其 (fixture,输入) 组合已被 AC-1.1 放行语义覆盖）→ 零残留可判定；禁止标识 `AC-1.1-OLD` 零出现（防命名混淆）；
   - 执行层：AC-1.1 放行向量与旧正向拒绝断言同 (fixture,输入) 组合、期望互斥，cmd-02 执行绿即证明旧断言未被执行生效；
   - CR-2026-057 既有 AC-14 其它零观察点（candidate/journal 零痕迹）在拒绝路径上保持（unassigned 向量并入 AC-1.2）。
3. `merge-fixture.mjs` 默认行为不变：`makeCodeApprovedFixture()` 无参数时仍为 `target-version: 0.2`（既有断言零影响）；`_backlog.yml` 条目补行对既有断言无破坏（cmd-02 全绿即证）。
4. 零新增 fault-point：`FAULT_POINTS` 登记表 `git diff` 零改动（grep 核对仅用既有 `writeback-after-apply`/`writeback-after-commit`/`writeback-after-push`/`tx-apply-between-rename`）。
5. `git diff --name-only` 仅含 `merge-fixture.mjs` 与 `writeback-tx.test.mjs` 两个文件（本 TASK 边界）。

## 5. 完成标志

writeback-tx.test.mjs 全绿（exit 0）；AC-1/AC-2/AC-3/AC-6 夹具全部落盘；旧 unassigned 拒绝断言改写完成；`_index.yml` 本 TASK 标 done。

## 6. 接口契约

- 消费：TASK-03 产出的 journal payload `versionRefill` 形状、CLI 成功/失败信封（FR-6）；既有 `makeFixture` / `makeCodeApprovedFixture` / `makeMergedFixture` / `snapshotSixPoints` / `runCrctl`。
- 产出（供 TASK-07 消费）：参数化夹具 `makeCodeApprovedFixture({ targetVersion = '0.2' })` 与 `makeMergedFixture({ targetVersion = '0.2' })`（cr.md 与 `_backlog.yml` 条目均写 `target-version: <v>` 行；默认 0.2 保持既有行为）；writeback-tx.test.mjs 全量夹具即 cmd-02 唯一证据面。

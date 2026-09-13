---
id: CR-2026-065-TASK-02
type: TASK
cr-ref: CR-2026-065
plan-ref: "change-requests/CR-2026-065/plan.md"
sdd-ref: "change-requests/CR-2026-065/sdd.md"
target-version: 0.38
title: 去重契约提级：lib/outbox-contract.mjs 单一事实源 + emitOutboxEvent 最小改点 + BR-5 构造改对与同名不同内容用例
slug: outbox-dedup-contract-and-br5
status: pending
estimate: 16h
depends-on: []
created: 2026-09-13T05:05:00+08:00
---

# CR-2026-065-TASK-02 去重契约提级与 BR-5 修正（G2，FR-8…FR-10）

## 1. 任务描述

**目标**：把 `crctl.mjs#emitOutboxEvent` 里「哪些字段参与去重比较」从注释里的口头约定提为**可机器检查的单一事实源**（`lib/outbox-contract.mjs`），把冻结红向量 BR-5（`archive-tx.test.mjs:373` `TASK-01 RED-7`）按 owner 裁定的「**构造改对**」修正（不改产品语义、不整条作废），并新增「同名但内容不同」的显式用例。

**背景**：BR-5 当前是红的（`archive-tx.test.mjs:373`，实现按内容相等去重 → `EMIT_FAILED`）：`:386` 预写了**同名但内容不同**的占位文件，却断言 `warnings: []` —— 构造失真，非产品缺陷。产品现状语义（`crctl.mjs:293` `emitOutboxEvent`，内联比较块 `:320-346`；archive/status/audit/trace 共用）＝「**内容相等才算已发送**」：文件名存在且比较面逐字段相等 → 返回文件名、不覆盖、不新增；不等 → `OUTBOX_DEDUP_CONFLICT` → 调用方 `EMIT_FAILED`。**本卡不改产品语义、不整条作废**；CR-2026-052 TASK-08 的 drift-audit「排除 `detected_at`」语义不动。

**零语义变化口径**：与产品现状 `crctl.mjs:336`（`delete p.detected_at`）**同读法**；`payload.detected_at` 是 payload 根下的**相对键**。

**范围边界（`zero_diff`）**：`crctl.mjs` 顶层 dispatch 与所有既有子命令的**签名、参数、错误码零 diff**（只允许 `emitOutboxEvent` 内部实现改点，且返回语义不变）；`lib/yaml-subset.mjs` / `lib/durable-tx.mjs` / `lib/workspace-transactions.mjs` / `rules.json` / `dir-graph.yaml` / `pipeline-templates/*` / 所有 `SKILL.md` 零 diff。

## 2. 涉及文件 / 模块

| 文件（相对 `tools` 仓根） | 动作 | 说明 |
|---|---|---|
| `skills/shared/crctl/scripts/lib/outbox-contract.mjs` | **新增** | 产品面（最小）：字段分类 + 投影函数；产品与测试共同 import |
| `skills/shared/crctl/scripts/crctl.mjs` | 改 `emitOutboxEvent` | 内联比较块（`:320-346`）→ 调用契约模块；注释收敛为指向本模块的指针 |
| `skills/shared/crctl/scripts/test/archive-tx.test.mjs` | 改 RED-7 构造（`:373`）+ 新增用例 | 构造 A（真实崩溃窗口）+ 构造 B（同名不同内容）；沿用文件内局部 helper |
| `skills/shared/crctl/scripts/test/trace-outbox.test.mjs` | 新增契约断言 | §3.1 六条不变性（含 `payload.observed_at` 反例与投影闭合边界） |

## 3. 实现要点

### 3.1 `lib/outbox-contract.mjs`（逐字对齐 SDD §3.1）

```js
export const OUTBOX_COMPARED_FIELDS = Object.freeze([...]);   // 参与比较（SDD §2.2 上半表）
export const OUTBOX_EXCLUDED_FIELDS = Object.freeze(['occurred_at']);        // 顶层不参与
export const OUTBOX_VOLATILE_PAYLOAD_KEYS = Object.freeze(['detected_at']);  // payload 根下键名（相对键）
export function buildOutboxEvent(input, nowIsoString) { /* 规范化事件对象 */ }
export function buildOutboxComparable(event) { /* 由上面三个声明驱动的投影 */ }
```

- `OUTBOX_COMPARED_FIELDS` = `v` / `event_kind` / `cr_id` / `from_status` / `to_status` / `trigger` / `commit_sha` / `actor` / `evidence` / `payload`（即现有事件对象除 `occurred_at` 外的全部字段）。
- `buildOutboxEvent(input, nowIsoString)`：返回 `{ v: 1, event_kind, cr_id, from_status: '', to_status: '', trigger: '', commit_sha: '', actor: '', evidence: {}, payload: {}, occurred_at: nowIsoString }`（缺省值口径与现状 `crctl.mjs:302-315` 逐字一致，顺序固定）。
- `buildOutboxComparable(event)`：`out = {}`；`for (f of OUTBOX_COMPARED_FIELDS) out[f] = event[f]`；`payload = { ...event.payload }`；`for (k of OUTBOX_VOLATILE_PAYLOAD_KEYS) delete payload[k]`；`out.payload = payload`；`return out`。**只读**：不得就地 `delete` 原事件字段。
- 六条不变性（plan §6.1 FR-10 口径；SDD §3.1 逐条，测试断言）：
  1. **单一事实源**：`crctl.mjs#emitOutboxEvent` 改用 `buildOutboxEvent` + `buildOutboxComparable`；`crctl.mjs` 中**不得**再出现字段枚举或 `detected_at` 的语义副本（只允许指向本模块的指针注释）；
  2. **字段分类集合相等**：`Object.keys(buildOutboxEvent(sample, now)) ≡ OUTBOX_COMPARED_FIELDS ∪ OUTBOX_EXCLUDED_FIELDS`——新增字段未登记进两类之一即红；
  3. **枚举排除非自动**：`OUTBOX_VOLATILE_PAYLOAD_KEYS` 只做枚举排除，不得实现为「按名字/类型自动排除所有时间类字段」；反例：`payload.observed_at`（未登记）**仍参与比较**；
  4. **投影闭合**：`Object.keys(buildOutboxComparable(ev).payload) ∩ OUTBOX_VOLATILE_PAYLOAD_KEYS = ∅`；键缺失 / `payload` 为空 / 嵌套对象三类边界同样成立（常量与投影必须同一键空间，否则本条红）；
  5. **投影只读**：不改入参；
  6. **行为等价**：同比较面重放仍视为已发送（返回文件名）；比较面不等仍抛 `OUTBOX_DEDUP_CONFLICT`（FR-8 语义零变化）。
- 用例命名：`trace-outbox.test.mjs` 与 `archive-tx.test.mjs` 新增用例的 `test(...)` 名**必须以 `CR-2026-065` 起始**（`cmd-03` 的 `--test-name-pattern CR-2026-065` 以此命中）。

### 3.2 `crctl.mjs#emitOutboxEvent` 最小改点

- 事件对象构造改用 `buildOutboxEvent(ev, nowIso())`；比较改用 `buildOutboxComparable`；
- `crctl.mjs` 中**不得**再出现字段枚举或 `detected_at` 的语义副本（只允许指针注释，例如「契约见 `./lib/outbox-contract.mjs`」）；
- **判重不变**：`exists(target) && comparable(existing) === comparable(event) → 命中`（返回文件名，不覆盖）；不等 → `throw OUTBOX_DEDUP_CONFLICT` → 既有 catch 走 `auditLog(result:'EMIT_FAILED')` + 返回 `null`（调用方 warning 语义不变）；
- 文件名生成、原子 rename、`CRCTL_OUTBOX_FAIL` 测试钩子、`dedup_name` 分支等其余行为**一字不改**。

### 3.3 BR-5 构造 A（替换 RED-7 r2，SDD §4.5）

1. 正常跑一次 archive（r1）：归档 commit + archive 事件真实写入（内容 = 该 commit 的真实事件）；
2. 定位 journal：`<kb>/.crctl/transactions/archive/<cr>/<txId>/journal.json`，把 `payload.outboxEmitted` 置回 `false`（模拟「文件已写、journal 未标记」的崩溃窗口）；确认 archive 事件文件仍在、内容未变；
3. 重放 archive（r2，同一 spec-id）断言：`warnings = []`、`outbox = `archive-<cr>-<commit>.json``、事件文件数量仍为 1、文件字节内容与 r1 完全一致（不覆盖）、origin master commit 数不变、r3 重放不再生成事件。

### 3.4 BR-5 构造 B（新增用例，SDD §4.5）

1. r1 正常归档 → 事件文件 `E` 存在；
2. 将 `E` 内容替换为不同内容（例如 `{"placeholder":true}`），并把 journal 的 `outboxEmitted` 置回 `false`；
3. 重放 archive 断言：`warnings` 含 `EMIT_FAILED`（`event_kind=archive`）；`.crctl/audit.log` 出现 `OUTBOX_DEDUP_CONFLICT`（可见信号至少其一，二者此处同时具备）；`E` 内容仍是步骤 2 写入的内容（未覆盖）；journal 的 `payload.outboxEmitted !== true`（保持 pending）；
4. 删除冲突文件 → 再重放：outbox 返回 `archive-<cr>-<commit>.json`、`warnings = []`、origin master commit 数不变（零新 commit）、`E` 内容为真实 archive 事件、`outboxEmitted === true`（补发成功）。

### 3.5 回归保护与纪律

- CR-2026-052 TASK-08 的 `detected_at` drift-audit 用例（`crctl.test.mjs:798`「同一漂移二次观测 → 文件 1、无 EMIT_FAILED」）**必须保持绿**（FR-8.3）；
- 沿用 `archive-tx.test.mjs` 文件内局部 helper（`makeWritebackFixture:14` / `archiveOutboxFiles:231`），**不上提**共享 fixture；不新增 fixture 框架；`*.test.mjs` 集合保持 21（不新增测试文件）；
- 所有读文本/写断言先做行尾规范化（`\r\n → \n`），解析失败硬失败；
- 断言只读受治理账本：不写 `_index.yml` / `_backlog.yml` / `cr.md` / `approval.yml`。

## 4. 验收条件（可执行）

1. `cmd-03`（§6.2 证据命令表，tools cwd `.`）：`node --test --test-reporter=dot --test-name-pattern "TASK-01 RED-7" --test-name-pattern "CR-2026-065" skills/shared/crctl/scripts/test/archive-tx.test.mjs skills/shared/crctl/scripts/test/trace-outbox.test.mjs` → **exit 0**（基线现状 exit 1 / 22.6 s，失败断言 `actual: [{code:'EMIT_FAILED',event_kind:'archive'}]` vs `expected: []`；`--test-name-pattern CR-2026-065` 同时命中本卡新增的契约用例与 BR-5 新用例）。
2. 回归保护：`node --test --test-reporter=dot --test-name-pattern "同一漂移二次观测" skills/shared/crctl/scripts/test/crctl.test.mjs` → **exit 0**（CR-2026-052 TASK-08 `detected_at` 语义不回归）。
3. 契约面自检：`node -e "import('./skills/shared/crctl/scripts/lib/outbox-contract.mjs').then(m => { /* 打印五导出与不变性 1/3 的即时结果 */ })"` 形态的即时校验 → 五导出齐备、集合相等与投影闭合均成立（正式断言面在 `cmd-03`）。
4. diff 面自检：`crctl git diff --name-only dddd0ad63fb79bd7608314b4553f30e8ce7b7289` → 仅 `skills/shared/crctl/scripts/lib/outbox-contract.mjs`、`skills/shared/crctl/scripts/crctl.mjs`、`skills/shared/crctl/scripts/test/archive-tx.test.mjs`、`skills/shared/crctl/scripts/test/trace-outbox.test.mjs`（+ 同 CR 其他 TASK 的允许面）；`skills/shared/controlled-shell/rules.json` 与所有 `SKILL.md` 零 diff。

## 5. 完成标志

- `cmd-03` exit 0；回归保护命令 exit 0；新增用例名以 `CR-2026-065` 起始；
- `lib/outbox-contract.mjs` 五导出齐备，`crctl.mjs` 内不再有字段枚举/`detected_at` 语义副本，dispatch 与既有子命令签名/参数/错误码零 diff；
- 构造 A/B 按 §4.5 逐条落地，注入/构造物**不在**交付 diff；
- 任务账本登记：`crctl task done CR-2026-065 --task CR-2026-065-TASK-02`。

## 6. 接口契约

**消费（上游/既有，逐字；只读）**

- `crctl.mjs#emitOutboxEvent(ws, ev)`（`:293` 起；本卡改其内部实现，**签名与返回语义不变**：成功返回文件名 `string`，失败 `null`）；
- `lib/workspace-transactions.mjs`：`archiveCr`（`:3449`）/ `emitArchiveIfNeeded`（`:3510` 附近，`payload.outboxEmitted` 语义）/ archive 事件发送点（`:3520`）/ cleanup-pending（`:3683`、`:3705`）；
- `test/merge-fixture.mjs` 六个导出：`sha256(:11)` / `git(:14)` / `runCrctl(:20)` / `makeFixture(:27)` / `makeCodeApprovedFixture(:95)` / `originMasterCount(:197)`；
- `test/archive-tx.test.mjs` 文件内局部 helper：`makeWritebackFixture(:14)` / `archiveOutboxFiles(:231)`（沿用、不上提）。

**产出（`lib/outbox-contract.mjs`，逐字对齐 SDD §3.1；下游 TASK-03 的 `contract-scan.test.mjs` 静态断言「产品面无第二份字段枚举」消费本模块）**

- `OUTBOX_COMPARED_FIELDS: readonly string[]`（`Object.freeze`）、`OUTBOX_EXCLUDED_FIELDS: readonly string[]`（`['occurred_at']`）、`OUTBOX_VOLATILE_PAYLOAD_KEYS: readonly string[]`（`['detected_at']`，payload 根下相对键）；
- `buildOutboxEvent(input, nowIsoString) -> object`；
- `buildOutboxComparable(event) -> object`。

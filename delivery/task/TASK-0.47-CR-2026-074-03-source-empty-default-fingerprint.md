---
spec-id: ai-first-platform
version: "0.47"
id: CR-2026-074-TASK-03
type: TASK
cr-ref: CR-2026-074
plan-ref: "change-requests/CR-2026-074/plan.md"
sdd-ref: "change-requests/CR-2026-074/sdd.md"
target-version: 0.47
title: source 空缺省 + 历史指纹矩阵
slug: source-empty-default-fingerprint
status: pending
estimate: 1h
depends-on: [CR-2026-074-TASK-02]
created: 2026-10-01T00:55:00+08:00
---

## 任务描述

将 `registerCr` 的 source 缺省值由 `manual` 改为空串，并以测试冻结 SDD §2.3 的历史指纹矩阵（FR-10；AC-11）。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` — `registerCr` 内 `const source = input.source ?? 'manual';` 改为 `const source = input.source ?? '';`（dep-6：source 缺省为 manual 且参与 inputDigest，同 key 不同指纹 → REGISTRATION_INPUT_MISMATCH，指纹校验早于注册账本副作用）。
- `skills/shared/crctl/scripts/test/register-tx.test.mjs` — 空 source 与历史指纹矩阵用例（与 TASK-02 同测试文件，顺序编辑）。

## 实现要点

- 唯一代码变更（SDD §2.3）：`input.source ?? ''`。新省略与显式空串进入同一空 source 指纹及持久化值；显式路径值不归一成 manual/空串；owner/version/spec/CR 分配/锁/journal/指纹算法/显式 source 均不改。
- 历史指纹矩阵（SDD §2.3 表，四行逐行建测）：
  | 事务已存 source | 本次输入 | 预期 |
  | --- | --- | --- |
  | manual，旧省略注册 | 仍省略 source | 新计算为空，REGISTRATION_INPUT_MISMATCH；零账本重写/零新增 CR，保留原 journal 指纹 |
  | manual | 显式 source=manual，其他指纹字段一致 | 原指纹匹配，按注册深原语续跑/noop，保留 manual，不重新分配 CR-ID |
  | 显式路径 | 同一路径与相同字段 | 原指纹匹配，原续跑/noop |
  | 空串 | 省略或显式空串，其他字段相同 | 指纹匹配，原续跑/noop |
- 历史 fixture 用变更前 manual 注册指纹/现场构造，不由新代码重新造"旧默认"；不修改旧 recovery argv/journal，不为旧默认值引入兼容重归一化。
- writer 路径规则（dep-14）不改：空串不进入 `write-requirement-prd` 的非空 source 存在性条件；测试以真实 register 产物空值 + 不变合同断言为证据，不声称 CLI 自动执行了 writer。

## 验收条件

1. 在 tools CR worktree 执行 `node --test skills/shared/crctl/scripts/test/register-tx.test.mjs`（证据 cmd-02）全绿，且矩阵四行逐行断言（AC-11）通过。
2. 新注册产物断言：省略 `--source` 与显式 `--source ''` 两种调用产出的 cr.md/backlog source 值均为空串，且 inputDigest 指纹一致（同 key 重放互为 noop）。
3. 非空 source 合同断言：存在/不存在/越界的非空输入对照 dep-14 合同逐项覆盖（register CLI 侧不新增校验，产物值原样持久化）。

## 完成标志

- cmd-02 全绿含矩阵断言；`registerCr` 除该一行缺省值外零 diff（指纹算法与注册行为 zero_diff）。
- 历史 manual 事实不迁移：既有 `CR-2026-074` 的 manual 注册现场不变（测试外的真实账本零接触）。

## 接口契约

**消费**：dep-6 `registerCr` 的 source/inputDigest/loadOrCreateJournal 路径（现值 `input.source ?? 'manual'` 改为 `input.source ?? ''`，行内其余逐字不变）；TASK-02 编辑后的同文件状态。

**产出**：缺省 source 语义——省略/显式空串 → 空串指纹与空串持久化值；显式 manual/路径 → 原值指纹。无签名变化（内部缺省值变更）。下游消费方 TASK-09（requirement-register/SKILL.md 的 source 默认空串说明与历史指纹冲突边界）引用同一语义，不得另造口径。

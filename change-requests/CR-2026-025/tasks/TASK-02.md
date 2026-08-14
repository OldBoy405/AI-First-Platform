---
id: CR-2026-025-TASK-02
type: TASK
cr-ref: CR-2026-025
plan-ref: "change-requests/CR-2026-025/plan.md"
sdd-ref: "change-requests/CR-2026-025/sdd.md"
title: 项③ isEmpty 失败回显收敛
slug: blockers-brief-echo
status: pending
estimate: 2h
depends-on: []
created: "2026-08-09T02:30:00+08:00"
---

## 1. 任务描述

收敛 `evaluatePassCondition` 的 `isEmpty` 失败分支回显：数组型 `actual` 逐项截断、`why` 只给条数与证据文件指针，消除同一 blockers 长文本在 detail 中重复全量落地（PRD 项③，SDD §4.3）。

## 2. 涉及文件

- 修改：`tools/skills/shared/crctl/scripts/crctl.mjs`（`evaluatePassCondition`）
- 修改：`tools/skills/shared/crctl/scripts/test/crctl.test.mjs`（追加向量）

## 3. 实现要点

- 在 `evaluatePassCondition` 作用域内引入常量 `ITEM_MAX = 120`（D-7：常量不做配置）与纯函数 `briefArray(v)`：字符串项超长按 `x.slice(0, ITEM_MAX) + '…(+N字)'` 截断，非字符串项原样保留，返回数组类型不变（FR-13）。
- 仅改 `isEmpty === true` 且 `!okv` 分支：`actual = Array.isArray(val) ? briefArray(val) : (val ?? null)`；数组型 `why = 期望 ${fieldPath} 为空，实际 ${val.length} 条（详见 ${doc.path}）`，不得包含任一完整原文（FR-12）。
- **不改**：`equals` 分支、标量 `isEmpty` 路径、`runGateChecks` 顶层 check、`cmdAdvance`、`fail()`（D-9）。
- 改动处注释写明（FR-14）：只封单条长度、不封条数；全量原文唯一来源是 `file` 字段指向的 `review-annotations/{stage}.yml`。

## 4. 验收条件

1. FR-15 五类向量全过：构造含超长 blockers（7 条各约 500 字）的证据后跑 `gate --for <评审通过态>` 与失败的 `advance`，断言退出非 0、`checks[].detail[].actual` 仍为数组且每项长度 ≤ `ITEM_MAX + 后缀长度`、`why` 含条数与 `详见` 指针且不含完整原文、`GATE_BLOCKED` message 维持现状不含原文、标量 `equals` 失败输出与改动前一致（AC-12/AC-13）。
2. 改动处注释含"只封单条长度、不封条数"与全量原文来源说明（AC-14）。
3. `node --test crctl.test.mjs` 全绿。

## 5. 完成标志

FR-15 向量全绿 + 既有用例零回归 + `_index.yml` 登记 done。

## 6. 接口契约

- 消费：既有 `evaluatePassCondition` 内部结构（`cond`/`doc`/`fieldPath`），无外部签名变化。
- 产出：`briefArray(v: unknown[]): unknown[]`（模块内纯函数，TASK-03 不消费）；gate/advance JSON 输出字段名与层级不变（NFR-3，消费方 `.length`/索引取值安全）。

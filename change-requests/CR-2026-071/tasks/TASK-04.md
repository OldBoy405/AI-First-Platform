---
id: CR-2026-071-TASK-04
type: TASK
cr-ref: CR-2026-071
plan-ref: "change-requests/CR-2026-071/plan.md"
sdd-ref: "change-requests/CR-2026-071/sdd.md"
target-version: 0.44
title: bak 副本审计与四个线上 Agent 指令同源同步
slug: bak-audit-and-agent-sync
status: pending
estimate: 2h
depends-on: [CR-2026-071-TASK-03]
created: 2026-09-27T16:45:00+08:00
---

# CR-2026-071-TASK-04 — bak 副本审计与四个线上 Agent 指令同源同步

## 1. 任务描述

- 目标：审计 `bak/` 目录用途并修正仍可部署副本的同类漂移（或留排除理由），以合同源全文为唯一输入同步四个线上 Agent instructions 并逐个 `agent get` 核验（FR-2，AC-3）。
- 背景：dep-4 确认 `bak/cr-coordinator-agent.md:45` 与 `bak/quality-reviewer-agent.md:67` 含同类漂移、其余 bak 文件无委派子句；线上 dev-agent 与 cr-coordinator-agent 已取证含 `enqueued` 语义。
- 输入条件：TASK-01 四份提示词成品、TASK-03 合同源全文与回归绿灯；`sdd.md` §4.1 bak 段落与 §4.2、`plan.md` §1/M3；multica CR worktree 可读写；执行线上同步的身份具备 `multica agent update/get` 权限（owner Ray）。

## 2. 涉及文件 / 模块

- multica CR worktree 内修改/留痕：`cr-prompts-revised/bak/` 下全部文件——仍可作为部署来源的副本按 SDD §4.1 全文同等修正；确认不再部署的副本在该目录留一行排除理由（不删文件保历史可追溯）。
- 线上（只读核验 + 定向更新，不更换 ID/绑定）：`requirement-writer`（`6317495b…`）、`dev-agent`（`ff6fcbb6…`）、`quality-reviewer-agent`（`2ed1a9de…`）、`cr-coordinator-agent`（`87ca2271…`）四个 Agent 的 instructions，仅替换委派判定段落。
- 只读取证：AIFI-35 评审结果与账本（zero_diff 兜底，不触发其 reviewer）。

## 3. 实现要点

- 参考 SDD §4.2：以合同源全文为唯一输入，经 `multica agent update <id>` 更新四个线上 Agent instructions，仅替换委派判定段落，其余职责、绑定、skill 列表原样保留，不更换 ID。
- 逐个 `multica agent get <id> --output json` 核验成品含规范三元组且无 `enqueued` 成功语义、无 `target_unavailable` status 语义；任一不符即失败，不得以"文件已改"代替线上交付。
- bak 审计结论落盘（保留/排除理由）；更新范围限定判定段落原文替换。

## 4. 验收条件

1. "需维护" bak 集合中每个文件均通过 TASK-03 回归的无漂移断言（含规范三元组与豁免子句、无 `enqueued` 成功语义）；排除副本各有留痕的一行排除理由。
2. 四个线上 Agent 的 `agent get` 成品原文均与合同源逐字一致（`enqueued` 成功语义与 `target_unavailable` status 语义双清零），四份原文留存交付记录备查。
3. AIFI-35 无新 reviewer run、其 CR 状态/账本零 diff（`git`/远端只读核验，不触发委派）。

## 5. 完成标志

- bak 修正/排除理由已落盘，四份线上指令已同步且四份 `agent get` 核验通过，验收条件 1～3 全部通过；线上核验原文已留存交付记录；本 TASK 实际产生的文件修改与线上同步记录已由本 TASK 落实登记，不预登记 TASK-05 的全量验证记录。

## 6. 接口契约

- 消费：上游 TASK-01 的四份提示词判定段落原文、上游 TASK-03 的合同源全文（线上同步唯一输入）与回归绿灯结论。消费形态为 Markdown 文本，不涉及函数签名（SDD §3：线上同步经既有 `multica agent update/get` 通道，无新接口）。
- 产出：下游 TASK-05 消费本 TASK 的四份 `agent get` 成品原文（AC-3 证据）与 bak 审计结论；产出形态为线上指令文本 + 交付记录，不暴露函数签名。
- 共享契约锁定：线上四份判定段落、源四份提示词、合同源三方必须逐字一致；任一字差异即为交付失败，不得以"文件已改"代替。

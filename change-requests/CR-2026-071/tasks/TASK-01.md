---
id: CR-2026-071-TASK-01
type: TASK
cr-ref: CR-2026-071
plan-ref: "change-requests/CR-2026-071/plan.md"
sdd-ref: "change-requests/CR-2026-071/sdd.md"
target-version: 0.44
title: multica 四份提示词委派判定子句全文替换
slug: multica-prompts-delegation-clauses
status: pending
estimate: 4h
depends-on: []
created: 2026-09-27T16:45:00+08:00
---

# CR-2026-071-TASK-01 — multica 四份提示词委派判定子句全文替换

## 1. 任务描述

- 目标：按 SDD §4.1 合同正文，替换 multica 仓四份提示词中的委派成功/失败判定子句，消除 `enqueued` 成功语义与 `target_unavailable` status 语义（FR-1）。
- 背景：dep-3 确认四份文件现状与平台枚举（dep-1/dep-2）冲突；本 TASK 只改判定段落，不改职责、绑定与 skill 列表。
- 输入条件：`plan.md` §1/M1 与交付覆盖表 FR-1 行、`sdd.md` §4.1、`cr.md` target-version 0.44 已就绪；multica CR worktree 已存在且可读。

## 2. 涉及文件 / 模块

multica CR worktree（`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-071`）内：

- 修改：`cr-prompts-revised/requirement-writer.md`（靶点约 `:43`）
- 修改：`cr-prompts-revised/dev-agent.md`（靶点约 `:39`）
- 修改：`cr-prompts-revised/quality-reviewer-agent.md`（靶点约 `:93`，PASS/BLOCK 委派段约 `:69` 按需对齐措辞、不改路由语义）
- 修改：`cr-prompts-revised/cr-coordinator-agent.md`（靶点约 `:50`）
- 只读取证：`server/internal/handler/admission.go`（dep-1 L32-41、dep-2 L50-64/L118，不修改，zero_diff）

以上行号以 dep-3 取证 commit `a0d0d369` 为基线，实施期以 worktree 实际行文核对。

## 3. 实现要点

- 参考 SDD §4.1：将四处现状逐字替换为 §4.1 合同正文全文（成功集合 `queued|coalesced|deferred`；失败为 `blocked` 记 reason_code 或被 mention 的 agent/squad 目标缺失 outcome；`target_unavailable` 归入 reason_code；未知 status 不判成功；human-only 豁免；发布失败与投递失败二分；多目标互不掩盖；不因误判重复 mention）。
- `cr-coordinator-agent.md` 核心修正：`target_unavailable` 从 status 列移除；"无触发结果"收窄为"被 mention 的 agent/squad 目标缺失 outcome"。
- `quality-reviewer-agent.md` "其余"必须按全文展开为 blocked/缺失 outcome/未知 status，且保留 human-only 豁免。
- multica 仓代码注释一律英文（新注释如有，必须英文）；提示词与合同正文本身中文不变。

## 4. 验收条件

1. 四份文件均含 SDD §4.1 合同正文全部子句（成功三元组、按目标求值、缺失 outcome 失败、human-only 豁免、未知 status 不成功、发布失败二分、不掩盖不重复），且全文逐字一致，可用 `grep` 逐文件核验。
2. 四份文件均不再含 `enqueued` 成功语义，且均不再把 `target_unavailable` 列为 status（允许作为 reason_code 记录出现），可用 `grep -n "enqueued\|target_unavailable"` 核验上下文。
3. `git diff --stat` 仅触碰上述四份提示词文件，未触碰 `admission.go`、AIFI-35 路径与线上指令（线上同步属 TASK-04）。

## 5. 完成标志

- 上述四份提示词文件已落盘修改，验收条件 1～3 全部通过；本 TASK 实际产生的文件修改已由本 TASK 落实登记，不预登记 TASK-03/04 的产物。

## 6. 接口契约

- 消费：无上游 TASK 产出。本 TASK 直接消费 SDD §4.1 合同正文（自然语言规则文本，非代码函数签名；SDD §3 明确本 CR 无新增/修改 HTTP/IPC/事件接口）。
- 产出：下游 TASK-03 消费本 TASK 落盘的四份提示词判定段落原文（文件路径 + 判定段落全文），TASK-04 消费同一原文做线上同步；产出形态为 Markdown 文件文本，不暴露函数签名，故无参数/返回类型。
- 共享契约锁定：四份文件内联的合同全文必须与 TASK-03 新建的 `delegation-contract.md` 正文逐字一致；任一字差异即为漂移，由回归测试（TASK-03）捕获。

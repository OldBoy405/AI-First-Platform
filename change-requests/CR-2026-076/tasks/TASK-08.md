---
id: CR-2026-076-TASK-08
type: TASK
cr-ref: CR-2026-076
plan-ref: "change-requests/CR-2026-076/plan.md"
sdd-ref: "change-requests/CR-2026-076/sdd.md"
target-version: 0.49
title: "认证人类「继续」一次一 cycle：review-loop reset 判定与幂等"
slug: review-loop-continue-once
status: pending
estimate: 12h
depends-on: [CR-2026-076-TASK-04]
created: 2026-10-10T16:30:15+08:00
---

## 任务描述

目标（FR-07；AC-15／AC-16；SDD §4.7 + D-03）：让「认证人类的继续」在非 TTY 下也能合法表达且**一次指令只开一个 cycle**，并保证失败可恢复同一操作、成功重投不再增 cycle。

背景与输入条件：`dep-20` 结论原文——审批入口已分本地与 server-approve 两路，本地路径无签名事实可作区分依据；§3.1 要求 `review-loop reset` 新增**可选** `--continue-reason`，保留既有 `--loop`／`--reason`，TTY 模式保持。授权事实写入既有审计 `.crctl/audit.log` 与既有恢复依据。

明确不做：不新增票据服务、权限数据库或常驻调度器；不改 `review-loop.yml` 字段类型（E3：字段沿用，只新增审计记录）；不把旧评论重解释为无限授权。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`：`async function cmdReviewLoopReset(ws, cr, gates, flags)`（:1971）、审计写入路径 `.crctl/audit.log`
- `skills/shared/crctl/scripts/test/crctl.test.mjs`：定向用例
- 合同文本：`skills/sync/handover-cr/SKILL.md`（与继续/交接相关的契约说明）

## 实现要点

1. 判定顺序严格按 SDD §4.7，顺序不可交换：
   ```text
   ① 认证来源与权限（平台已认证人类触发事实 + 既有角色权限，不认 Agent 自报人类、不认仅 --confirm）
   ② 当前 CR/loop/耗尽事实（LOOP_EXHAUSTED；未耗尽 → LOOP_NOT_EXHAUSTED）
   ③ 目标唯一性（唯一 → 普通"继续"即可表达；不唯一 → 明确询问，不固定措辞）
   ④ 原指令的重放/恢复事实（同一来源指令在同一明确目标操作范围只授权一次）
   ⑤ 明确 cycle 转换（current-cycle+1，attempt 归零，历史 attempts 保留）
   ```
2. 新参数 `--continue-reason`（可选）：提供**认证来源事实**，不是授权本身；`--loop`／`--reason` 既有参数语义不变；TTY 直连模式保留，两条路径汇合到同一写入缝。
3. 幂等与恢复：失败可恢复同一操作；成功重投**不得**再增 cycle；下一次耗尽必须有新的人类指令。
4. 边界：新 cycle 不清真实 blockers、不代表业务批准。
5. 审计：授权事实写入既有 `.crctl/audit.log`（不新增字段类型、不新增账本）。

## 验收条件

1. **AC-15（cmd-04）**：认证人类「继续」只开一个下一 cycle；目标不唯一时要求明确询问（非零或明确询问出口），不固定措辞；Agent 自报人类或仅 `--confirm` 不构成授权。
2. **AC-16（cmd-04）**：重复继续指令不增 cycle（重投幂等断言）；失败只恢复原操作；真实 blockers 不被清除；未耗尽时返回 `LOOP_NOT_EXHAUSTED` 且不写 cycle。
3. **TTY 与认证来源两条路径**：断言两条路径汇合到同一写入缝（同一 cycle 转换结果），且审计记录在两条路径下均落盘。
4. 运行范围＝`crctl.test.mjs` 单文件，**不声称**覆盖 crctl 全部子命令行为；真实执行输出落 `test-evidence/cmd-04.log`，不新增 plan 未列命令。

## 完成标志

- 五步判定、幂等重投、未耗尽分支与审计落盘均有用例覆盖，`cmd-04` 真实执行退出码 0 并留证；
- `skills/sync/handover-cr/SKILL.md` 相关契约说明落盘（不新增权限模型）；
- 本 TASK 在 `tasks/_index.yml` 即时标记 `done`。

## 接口契约

消费（TASK-04 产出，不得缩写）：
- `async function cmdReviewRecord(ws, cr, gates, flags)`（:2200）落盘的 `review-loop.yml` 事实（`current-cycle`／`current-attempt`／`attempts[]`），以及 `LOOP_EXHAUSTED` 判定所依赖的 attempt 事实；
- `warnings[]` 与 `next` 的 `humanApproval=true` 语义（TASK-05／TASK-06 产出）：`humanApproval=true` 表示等待合法人类继续，本 TASK 提供该等待的合法解除入口。

产出（供 TASK-10／TASK-17 与后续 CR 消费，消费方不得缩写）：
- `async function cmdReviewLoopReset(ws, cr, gates, flags)`（:1971）参数面：新增**可选** `--continue-reason <text>`；保留 `--loop`／`--reason`（§3.1）；
- 语义结果：`current-cycle = current-cycle + 1`、`current-attempt = 0`、`attempts[]` 历史保留（E3 字段集不变）；
- 审计契约：`.crctl/audit.log` 新增一条含认证来源与目标操作范围的记录（既有审计格式，不新增字段类型）；
- 既有错误码不变（§3.2）：未耗尽 → `LOOP_NOT_EXHAUSTED`；输入冲突 → 既有码，不新增同义错误码；
- 幂等键：同一来源指令 + 同一目标操作范围只授权一次，**不新增票据账本**。

---
id: CR-2026-071-TASK-05
type: TASK
cr-ref: CR-2026-071
plan-ref: "change-requests/CR-2026-071/plan.md"
sdd-ref: "change-requests/CR-2026-071/sdd.md"
target-version: 0.44
title: 全量验证与交付记录（含 AIFI-35 零改动核验与发布）
slug: full-verification-and-delivery
status: pending
estimate: 2h
depends-on: [CR-2026-071-TASK-02, CR-2026-071-TASK-03, CR-2026-071-TASK-04]
created: 2026-09-27T16:45:00+08:00
---

# CR-2026-071-TASK-05 — 全量验证与交付记录（含 AIFI-35 零改动核验与发布）

## 1. 任务描述

- 目标：跑通 plan §6 证据命令表 cmd-01～cmd-03，完成 plan §5 checklist（四份 `agent get` 成品一致、AIFI-35 零触发零账本改动、`crctl checkpoint` 发布），形成交付记录说明 P0/P1 实现、所跑测试、线上核验及未覆盖边界（AC-6）。
- 背景：本 TASK 无新增代码，是 M4 会合验证点；跨仓依赖仅在此会合（multica 与 tools 无共享代码依赖，SDD §1）。
- 输入条件：TASK-02（tools 三文件）、TASK-03（合同 + 回归）、TASK-04（bak + 线上同步）全部完成；`plan.md` §5/§6、`sdd.md` §6 AC 映射与 §9 批准范围。

## 2. 涉及文件 / 模块

- 只读执行（不修改被测文件）：multica CR worktree 根执行 cmd-01；tools CR worktree 根执行 cmd-02、cmd-03。
- 只读核验：四个线上 Agent 的 `agent get` 成品（复用 TASK-04 留存原文，不重复更新线上指令）。
- 只读核验：AIFI-35 线程（无新 reviewer run）与其 CR 状态/账本零 diff；本 CR 的 `approval.yml`、`merge-commits.yml`（如有）、checkpoint 元数据（审计事实来源，不进 TASK ledger）。
- 本 TASK 落盘物：仅交付记录文本（实现/测试/核验/边界说明），不新建提示词、合同、Pipeline 节点文件。

## 3. 实现要点

- 按 plan §6 证据命令表逐条执行：cmd-01 `node --test cr-prompts-revised/test/delegation-contract.test.mjs`（multica worktree 根，timeout 120）；cmd-02 `node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`（tools worktree 根，timeout 120）；cmd-03 `node -e "JSON.parse(...requirement-authoring.pipeline.json...)"`（tools worktree 根，timeout 60）。`cwd` 为各 worktree 根，executable 直接 spawn，无 shell 内建/管道/重定向。
- 交付记录列 P0/P1 实现、所跑测试、线上核验原文索引、未覆盖边界（含 SDD §9 follow_up：reviewer 提交禁令二选一、平台未来新增 status 跟进 CR、bak 排除副本重启用须补回归）。
- 发布：`crctl checkpoint`（`push-progress` 深原语）`phase=complete` 三仓 confirmed；feature-flag 不适用（plan §5）。

## 4. 验收条件

1. cmd-01、cmd-02、cmd-03 在各自 worktree 根全部绿灯（全绿输出留存，任一红灯即失败，不静默覆盖）。
2. plan §5 checklist 全闭：cmd 全绿、四份 `agent get` 成品与合同逐字一致（原文留存）、AIFI-35 无新 reviewer run 且其 CR 状态/账本零 diff、`crctl checkpoint` phase=complete 三仓 confirmed。
3. 交付记录已形成，含 P0/P1 实现、所跑测试、线上核验、未覆盖边界四节；`git diff --stat` 证明本 TASK 未修改提示词/合同/Pipeline/测试正文（仅交付记录文本）。

## 5. 完成标志

- 三条证据命令全绿输出已留存，checklist 全闭，交付记录已落盘；验收条件 1～3 全部通过。本 TASK 的完成边界是 `developing` 内可被 `crctl task done` 登记的事件（验证落盘 + 记录形成），不含 merge/审批/checkpoint 的流程控制语义（审计事实以 approval.yml 与 checkpoint 元数据为准）。

## 6. 接口契约

- 消费：上游 TASK-02 的 Pipeline 节点序列与结构测试绿灯、TASK-03 的 cmd-01 绿灯与合同文本、TASK-04 的四份 `agent get` 成品原文与 bak 审计结论。消费形态为文件文本与命令绿灯结论，无函数签名（SDD §3：判定逻辑是自然语言规则 + 离线回归脚本）。
- 产出：交付记录文本（P0/P1/测试/核验/边界）；无下游 TASK，无新暴露签名。
- 共享契约锁定：本 TASK 不引入新契约；仅复述上游三方的既有契约结论，不转述、不缩略；任一上游结论为红，本 TASK 即失败，不掩盖。

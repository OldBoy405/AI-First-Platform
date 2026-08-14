---
id: CR-2026-022-TASK-05
type: TASK
cr-ref: CR-2026-022
plan-ref: "change-requests/CR-2026-022/plan.md"
sdd-ref: "change-requests/CR-2026-022/sdd.md"
title: 批 2.5 — checkpoint-add LEGAL 白名单派生 + push-progress Step 3 重写 + 节点 12 补齐（FR-11）
slug: checkpoint-add-legal
status: pending
estimate: 6h
depends-on: []
assignee: ""
created: "2026-08-06T08:30:00+08:00"
---

## 任务描述

FR-11（2.1-G，最高杠杆：一处改动惠及 3 条流水线）：checkpoint-add 的 LEGAL 白名单从硬编码窄列表改为从状态机派生全非终态；push-progress 重写为逐仓显式调用 checkpoint-add；节点 12 补齐描述；onFail 告警方案（SDD D-4：工具层告警）。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`：`cmdCheckpointAdd`（约 :1575-1585）LEGAL 判断
- `skills/sync/push-progress/SKILL.md`：Step 2-3 重写
- `pipeline-templates/code-implementation.pipeline.json`：节点 12 prompt 补齐 checkpoint-add 描述
- 三条流水线（requirement-authoring/architecture-design/code-implementation）push-progress 节点 prompt：与 push-progress 新 Step 3 对齐（TASK-17 再抽样板，本任务只改语义）

## 实现要点（SDD §4.2/§3.3/D-4）

1. `cmdCheckpointAdd` 的 LEGAL 改为派生：`const { sm } = loadStateMachine(ws); const LEGAL = (sm.states||[]).filter(s => !(sm.terminal||[]).includes(s))`——与 cmdOwnerSet 同源；loadStateMachine 失败维持硬失败
2. push-progress Step 3 重写为：对每个 active repo ① `git rev-parse HEAD` ② `crctl checkpoint-add --repo <r> --sha <sha>` ③ 禁止手工编辑 _backlog.yml；错误处理路径：checkpoint-add 失败即非零退出，摘要中强制输出 `CHECKPOINT_ALERT` 段（工具层告警，不依赖 pipeline onFail）
3. code-implementation 节点 12 prompt 补「经 crctl checkpoint-add 更新 _backlog」与节点 3/8 一致
4. 三处 push-progress 节点 onFail 维持 `skip` 不变（SDD D-4 决策），但节点 prompt 语义与新 Step 3 对齐

## 验收条件

1. `drafting`/`requirement-reviewing`/`task-breakdown` 等非终态调用 `checkpoint-add` 成功落账；`archived`/`rejected`/`withdrawn` 终态拒绝
2. push-progress 按新 Step 3 执行后 `_backlog` checkpoints 与远端 SHA 一致
3. 节点 12 prompt 含 checkpoint-add
4. 模拟 checkpoint-add 失败：命令非零退出且摘要含 CHECKPOINT_ALERT

## 完成标志

验收 1~4 通过 + crctl.test.mjs 新增 12 非终态参数化用例全绿 + 灰度演练（NFR-5）中 drafting 态 checkpoint-add 真落账。

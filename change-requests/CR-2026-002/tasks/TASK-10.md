---
id: CR-2026-002-TASK-10
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: AI 行为审计 + EVIDENCE_DRIFT 留证（activity_log 双 action）
status: pending
estimate: 8h
depends-on: [CR-2026-002-TASK-09, CR-2026-002-TASK-03]
assignee: ""
created: "2026-07-31T09:30:00+08:00"
---

## 任务描述
FR-6/D6 + FR-7 留证半边（D7）：gitguard 拒绝事件与 crctl 漂移检出经 daemon 任务回调上报，落 `activity_log`；工具调用摘要随任务完成回调持久化。仓库：multica。

## 涉及文件
- gitguard 拒绝路径：记录 `{caller, sub, at}`（**不含参数正文**）→ 随既有任务回调族上报
- crctl gate/validate 检出 EVIDENCE_DRIFT 时输出结构化行 → daemon 捕获 `{cr_id, stage, expected_digest, actual_digest, detected_at}`（**不含证据内容**）→ 上报
- 服务端：activity_log 写入两个新 action（T04 已备常量）
- 任务完成回调：工具调用摘要序列（工具名/目标路径/结果码，不含输入输出正文）与 `skills_used[]` 同层持久化

## 实现要点
- 零新增探针原则：全部复用既有回调通道，不加独立上报进程（源方案 §C.5）。
- 摘要来源：pkg/agent 六类 Message 流的 tool-use/tool-result 已流经服务端，只需在完成回调聚合。

## 验收条件
1. 端到端：任务内触发一次 FORBIDDEN_* → activity_log 出现对应行且无参数正文（AC-6①）。
2. 端到端：批后篡改证据 → validate 检出 → activity_log 出现 evidence_drift 行（AC-7③ 留证半边）。
3. 任务详情可查工具调用摘要序列；与 skills_used[] 同回调到达（AC-6②③）。

## 完成标志
端到端三项实测记录 + go test 绿 + 完成记录回填。

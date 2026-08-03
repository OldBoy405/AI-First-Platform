---
id: CR-2026-011-TASK-02
type: TASK
cr-ref: CR-2026-011
plan-ref: "change-requests/CR-2026-011/plan.md"
sdd-ref: "change-requests/CR-2026-011/sdd.md"
title: 门禁节点投影器（状态映射表 + node_id 决议单点 + cr:updated 发布）
slug: gate-node-projector
status: done
estimate: 6h
depends-on: [CR-2026-011-TASK-01]
assignee: ""
created: "2026-08-02T12:40:00+08:00"
---

## 任务描述
落地 SDD §4.1 + DD-1/DD-6：crsync worker 增门禁节点投影器，从 crctl 事件流按静态映射表
推导 `pipeline_run` / `pipeline_node_run` 行；投影变更后 publish 既有 `cr:updated`。

## 涉及文件
- `server/internal/governance/crsync.go`：`applyStatus` 成功路径挂投影调用；新增映射表常量
  （SDD §4.1 表：16 态 → pipeline_run lazy upsert + human_approval 节点 running/passed；
  rejected/withdrawn → run cancelled + running 节点 failed；approve 事件按 (cr_id,stage)
  最新 approval_record 回填 node_run.approval_id）
- 同包新文件（如 `pipeline_projection.go`）：投影 upsert 逻辑（raw pgxpool，沿"fork 不碰
  sqlc"约定）+ **`ResolveNodeID(pipelineID, nodeRef)` 公共函数**
- `server/pkg/protocol/events.go`：增 `cr:updated` 常量，governance 局部常量（crsync.go:35）改引它

## 实现要点
- **TSUG-002 落地**：`ResolveNodeID` 是 node_id 唯一决议点——先核实 tools
  `pipeline-templates/*.pipeline.json` 有无稳定节点 UUID：有则直取，无则
  UUIDv5(固定 ns, `{pipeline_id}|{node_ref}`)；结论写函数注释；配测试向量文件
  （输入→期望 UUID hex），CR-H Runner 复用同函数同向量。
- run 状态派生：存在 running human_approval 节点 → `waiting_approval`，否则 `running`；
  archived → completed。
- upsert 幂等：UNIQUE(run_id,node_id,attempt) ON CONFLICT 更新 status/时间戳；事件重放安全
  （crsync 既有 at-least-once + per-CR 串行前提下）。
- attempt 权威在 git，投影只读展示，**不做 PG→git 回写**。
- 单测：映射表全 16 态逐态断言（进入态→期望 run/node 状态）；同事件重放幂等；
  rejected 中断路径；approval_id 回填。

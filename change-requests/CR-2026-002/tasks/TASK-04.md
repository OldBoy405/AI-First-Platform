---
id: CR-2026-002-TASK-04
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: migrations（cr / cr_sync_event / approval_record）+ transitions_gen.go 入库
status: pending
estimate: 8h
depends-on: []
assignee: ""
created: "2026-07-31T09:30:00+08:00"
---

## 任务描述
FR-2 数据前置：三张新表迁移（DDL 见 SDD §2.1，注意 approval_record 用部分唯一索引 `WHERE decision='approve'`）+ activity_log 两个 action 枚举常量 + 状态机 23 条转移表生成入库。仓库：multica。

## 涉及文件
- 新增 `server/migrations/{next}_aifirst_cr_projection.sql`（三表 + 索引）
- 新增 `server/internal/governance/transitions_gen.go`（生成产物，头注释记 tools commit SHA）+ 生成脚本 `server/internal/governance/gen/`（读 tools dir-graph.yaml）
- 新增 CI 步骤：重新生成 == 已入库（漂移即红，SDD-SUG-003）
- activity_log action 常量：`aifirst.gitguard_denied`、`aifirst.evidence_drift`（放 governance 包，不动上游枚举定义处）

## 实现要点
- 迁移风格对齐 multica 既有 396 个迁移的命名与工具链。
- transitions_gen.go 含 `IsLegalTransition(from, to, trigger) bool`；数据来源 tools dir-graph.yaml 的 16 态/23 条转移。
- CUSTOM.md 记账：新迁移文件属自研，rebase 时保序。

## 验收条件
1. `make selfhost-build COMPOSE=docker-compose.exe` 起栈后三表存在、索引正确（\d 检查部分唯一索引）。
2. 同 (cr_id,stage,digest) 先 reject 再 approve 两次插入均成功；approve 重复插入被幂等拒绝。
3. transitions 单测：23 条合法转移全 true、抽样非法转移 false。
4. CI 一致性校验步骤红绿验证（手改 gen 文件 → 红）。

## 完成标志
构建通过 + 迁移可重放（down/up 或重建卷）+ 单测绿 + 完成记录回填。

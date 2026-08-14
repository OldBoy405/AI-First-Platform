---
spec-id: ai-first-platform
version: "tbd"
id: CR-2026-032-TASK-04
type: TASK
cr-ref: CR-2026-032
plan-ref: "change-requests/CR-2026-032/plan.md"
sdd-ref: "change-requests/CR-2026-032/sdd.md"
title: 验证 Multica Archive 投影并执行跨仓验收
slug: multica-archive-contract
status: pending
estimate: 6h
depends-on: [CR-2026-032-TASK-03]
created: "2026-08-13T09:52:00+08:00"
---

# TASK-04 验证 Multica Archive 投影并执行跨仓验收

## 1. 任务描述

使用 TASK-02 的真实 outbox 契约验证 Multica 现有消费者，无生产协议改动。输入是 schema v1 `archive` 事件和 TASK-01～03 的完整 tools 产物；输出为一个既有 governance 测试文件中的契约向量、`CUSTOM.md` 追溯登记，以及可供 `write-test-report` 消费的跨仓验证证据。

## 2. 涉及文件 / 模块

- Multica：`server/internal/governance/crsync_test.go`（优先；若实现期事实核实显示同职责测试已迁移，只允许改一个既有 governance `*_test.go`）
- Multica：`CUSTOM.md`
- tools：TASK-01～03 产物（只读验证）
- knowledge-base：`change-requests/CR-2026-032/test-report.md`（由后续 `write-test-report` Skill 生成，本 TASK 不直接写）

## 3. 实现要点

- 遵守 Multica `CLAUDE.md`：新增 Go 注释和错误文本使用英文，测试沿用现有 DB fixture，不新建测试框架。
- seed CR 投影状态 `writing-back`，并 seed `pipeline_id=feature-writeback` 的活动 `pipeline_run`。
- 构造与 TASK-02 精确一致的 `OutboxEvent`：`V=1`、`EventKind=archive`、`FromStatus=writing-back`、`ToStatus=archived`、`Trigger=cr-archive`、固定真实形态 commit SHA、actor/occurred_at。
- 首次 ingest 断言：事件被 known kind 接收；合法转换通过；`cr.status=archived`；`projected_commit` 等于事件 SHA；feature-writeback run 结束；`cr_sync_event` 该幂等键数量为 1。
- 重放同一 `(cr_id,commit_sha,event_kind)`，断言事件行仍为 1、CR/run 投影不重复变化。
- 不为测试增加 production archive 分支、兼容层、迁移、query、generated 文件或 daemon schema 修改。
- 按 `CUSTOM.md` 当前“代码改动”表编号顺延，登记测试文件、CR-2026-032/TASK-04、test-only/production-zero-diff 边界与定向验证命令。
- 执行 tools archive/crctl/Prompt 静态检查与 Multica 定向测试；Go 测试必须 `-count=1 -v`，确认目标 test 输出 `=== RUN` 和 `--- PASS`，数据库不可达整包 skip 记未验证并阻断 pass。
- 审计三仓 changed-files：tools 落 SDD §1.2 白名单；Multica 仅一个测试文件+CUSTOM；knowledge-base 仅 CR 过程产物/账本。

## 4. 验收条件

1. Multica 目标契约测试实际 RUN/PASS，证明 archive 事件投影 archived、更新 projected commit、结束 feature-writeback run并保持幂等。
2. Multica production Go、migration、query/generated、daemon collector 和数据库 schema diff 全为空；`CUSTOM.md` 有精确 CR/TASK 追溯。
3. tools archive 定向测试、crctl 回归、Prompt lint、Skill/Agent contract、Pipeline parse 全部通过；不得靠删除/放宽旧断言获得绿灯。
4. 既有 traceability fixture 仍可归档；`gates.json`、`dir-graph.yaml`、writeback traceability generator 无变化，ARC-02 未提前启用。
5. 所有 PRD AC-01～AC-11 均映射到实际测试名、命令或 changed-files 守卫；任何失败或 skip 都阻止后续 test-report 标 pass。

## 5. 完成标志

跨仓验证证据完整、目标 Go 测试无 skip、diff 白名单无越界，结果可由后续 `write-test-report` 汇总；`tasks/_index.yml` 中 TASK-04 经 `crctl task done` 标记 done。

## 6. 接口契约

- **消费**：TASK-02 的 schema v1 archive 事件与固定 `ArchiveResult`；TASK-03 的 Skill/README 文档契约；Multica 现有 `SyncService.ingest(ctx,workspaceID,OutboxEvent) error`、`applyStatus()`、`completeRun()`。
- **产出**：Multica test-only 契约与 CUSTOM 台账记录；跨仓验证命令/结果，供 `write-test-report` 消费；不产出 production 接口。

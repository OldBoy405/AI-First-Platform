---
id: CR-2026-002-TASK-07
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: reconcile 对账（server/daemon 双模式）
status: pending
estimate: 8h
depends-on: [CR-2026-002-TASK-05]
assignee: ""
created: "2026-07-31T09:30:00+08:00"
---

## 任务描述
FR-3/D3：定时对账非终态 CR 的 `projected_commit` vs knowledge-base origin HEAD，差异则重放修复；`REMOTE_RECONCILE_MODE=server|daemon` 双模式。仓库：multica。

**开工条件（AC-3 环境前置）**：GitHub fine-grained PAT——仅 AI-First-Platform 单仓、仅 Contents: Read-only。server 模式实测前必须就位；PAT 未就位时先交付 daemon 模式。

## 涉及文件
- 新增 `server/internal/governance/reconcile.go`（+ 测试）
- 配置项 `REMOTE_RECONCILE_MODE` + `KNOWLEDGE_BASE_REMOTE_URL` + 凭据 env
- daemon 模式：daemon 侧定时 `crctl status --json` 全量快照上报（复用 cr-events 端点，event_kind=snapshot 或独立轻端点，实现时定并回写本文件）

## 实现要点
- 调度复用 `sys_cron_executions` DB 调度器（multica 现成）。
- server 模式：`git ls-remote` 或 GitHub API 取 origin HEAD + 读 `_backlog.yml`（raw content API）比对状态。
- 修复动作 = 标记 needs_reconcile 的 CR 按权威侧重放（拉最新 backlog 状态覆写投影行），**不反向写 git**。
- 对账周期默认 5min，可配。

## 验收条件
1. 测试/实测：手工 `UPDATE cr SET status='x'` → 下个周期自愈为权威状态（AC-3①）。
2. 两模式各实测一次生效（server 模式对 GitHub origin，AC-3②）。
3. needs_reconcile=true 的 CR 对账后恢复 false。

## 完成标志
go test 绿 + 双模式实测记录 + 完成记录回填。

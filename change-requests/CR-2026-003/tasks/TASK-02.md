---
id: CR-2026-003-TASK-02
type: TASK
cr-ref: CR-2026-003
plan-ref: "change-requests/CR-2026-003/plan.md"
sdd-ref: "change-requests/CR-2026-003/sdd.md"
title: multica 服务端 pending 防护 + reconcile 历史快照扩展
status: pending
estimate: 4h
depends-on: []
assignee: ""
created: "2026-07-31T21:00:00+08:00"
---

## 任务描述
修缺陷 A 的服务端半边（占位符不得进投影指针）+ 修缺陷 C（reconcile 快照覆盖 `_history.yml`）。仓库：multica（fork 自研目录，规则一）。

## 涉及文件
- `server/internal/governance/crsync.go`：`pendingShaPrefix` 常量 + `projectableSha()`；`applyStatus()` INSERT 与 UPDATE CASE 两处写入点接入
- `server/internal/governance/reconcile.go`：`ParseHistory()`（EOL 规范化 + 解析失败硬失败）、`mergeAuthority()`（backlog 覆盖 history）；`snapshotPayload` 增 `History` 字段；`ingestSnapshot` 合并
- `server/internal/governance/reconcile_github.go`：`FetchGitHubSnapshot` 同一 HEAD sha 追加拉取 `_backlog.yml` 之外的 `_history.yml` 并合并
- `server/internal/daemon/crevents.go`：`buildSnapshotEvent` 本地读 `_history.yml`（缺失视为空，不报错）
- 对应测试文件（crsync_test / reconcile_test / crevents_test）

## 实现要点
- SDD §4.1 服务端半边 + §4.2。`ApplySnapshot` 本体零改动。
- 幂等键继续用完整占位符；仅投影指针语义排除 `pending:` 前缀。
- 跨语言契约：测试中 `"pending:"` 字面量与 tools 侧（T01）一致。
- 向后兼容：`History` 字段缺失按空处理（旧 daemon 可继续上报）。

## 验收条件
1. AC-1 集成测试（真库）：同 CR 注入两条 `pending:` 占位符 status 事件 → `cr_sync_event` 两行均落库处理，投影状态两次都正确推进，且 `cr.projected_commit` 全程不含 `pending:` 前缀。
2. AC-2 集成测试（真库）：`_history.yml` 含 `final-status: archived` 的 CR + 投影行状态不一致 → `ApplySnapshot`（合并快照）后收敛为 `archived`、`needs_reconcile=false`。
3. `ParseHistory` 单测：LF/CRLF/空文件/坏 YAML 硬失败四态。
4. 既有 governance + daemon 测试全绿（回归，重点 NFR-1：真实 sha 事件的去重行为不变）。

## 完成标志
go test 真库全绿（-v 确认 --- PASS，防静默跳过）+ fmt/vet 干净 + 完成记录回填。

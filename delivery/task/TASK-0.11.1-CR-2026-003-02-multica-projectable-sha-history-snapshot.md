---
id: CR-2026-003-TASK-02
type: TASK
cr-ref: CR-2026-003
plan-ref: "change-requests/CR-2026-003/plan.md"
sdd-ref: "change-requests/CR-2026-003/sdd.md"
title: multica 服务端 pending 防护 + reconcile 历史快照扩展
status: done
estimate: 4h
depends-on: []
assignee: ""
created: "2026-07-31T21:00:00+08:00"
spec-id: ai-first-platform
version: "0.11.1"
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

## 完成记录（2026-07-31）

- **提交**：multica worktree 6bad142ec，合并入 fork main @ 28e562c21。
- **pending 防护（FR-1 服务端半边）**：`pendingShaPrefix` 常量 + `projectableSha()`，接入 `applyStatus()` INSERT 与 UPDATE CASE 两处——占位符只进幂等键，投影指针按空串语义（保留现值，等 checkpoint 真实 sha 追上）。
- **历史快照（FR-2）**：`ParseHistory`（EOL 规范化、坏 YAML 硬失败、空文件合法）+ `mergeAuthority`（backlog 防御性优先）；`snapshotPayload.History` 可选字段（旧 daemon 不发=旧行为，向后兼容）；server 模式同一 pinned sha 追加拉取 `_history.yml`（404=从未归档，合法）；daemon 模式本地读文件缺失降级为空。`ApplySnapshot` 本体零改动（SDD 预期兑现）。
- **测试**：governance 全包 33 项 PASS（真库 -v 口径，新增 4：占位符不漏投影指针+真实 sha 去重不变(NFR-1)、ParseHistory 四态、mergeAuthority 覆盖序、AC-2 卡死形态自愈——用 CR-2026-001/002 的真实卡死形态 writing-back/needs_reconcile=true 造数据，历史快照治愈为 archived）+ daemon 快照带 history 1 项。vet/build 干净。
- **行尾说明**：本 worktree 为 autocrlf 全量检出，gofmt -l 报全目录假差异（CUSTOM.md 基线既有记录）；diff 核实仅 4 文件 +90/-5 真实改动，提交经 autocrlf 归一化回 LF。
- **代码评审**：verdict pass，0 blocker；2 项非阻塞建议（checkpoint 分支 + ApplySnapshot 的 HeadSHA 写入点也包 projectableSha 做纵深防御；同毫秒双 embedded 文件名理论碰撞），均记录不阻塞、留后续。

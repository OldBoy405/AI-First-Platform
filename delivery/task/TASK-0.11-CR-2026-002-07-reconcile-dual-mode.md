---
id: CR-2026-002-TASK-07
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: reconcile 对账（server/daemon 双模式）
status: done
estimate: 8h
depends-on: [CR-2026-002-TASK-05]
assignee: ""
created: "2026-07-31T09:30:00+08:00"
spec-id: ai-first-platform
version: "0.11"
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

## 完成记录（2026-07-31）

- **提交**：multica worktree e98086a7c。
- **daemon 模式实现决策（回写任务卡"实现时定"项）**：不走 `crctl status --json`（避免 daemon 对 node 运行时的新依赖），daemon 每 5min 直接读 `{root}/change-requests/_backlog.yml` 原文 + `git rev-parse HEAD`（过 gitguard），打包成 `event_kind=snapshot` 复用 cr-events 通道；**解析留在服务端**（`governance.ParseBacklog` 单实现，EOL 规范化 + 解析失败硬失败），两模式共用一个解析器。snapshot 与 audit 同为"无账本"类事件：绕过 cr_sync_event（无 commit sha 幂等键），直接进 `ApplySnapshot`（本身幂等，重放无害）。
- **自愈语义（单实现 ApplySnapshot）**：状态漂移覆写、needs_reconcile 清除、投影缺行补插、快照外的行不动（backlog 只含未归档 CR，缺席≠漂移）、状态机枚举外的值永不投影。只读 git 权威，不反向写。
- **server 模式**：sys_cron 调度器（复用 `sys_cron_executions`，任务名 `aifirst_cr_reconcile`，默认 5min 可配 `RECONCILE_INTERVAL`）；GitHub API 三连（repo 元数据取默认分支 → HEAD sha → 按该 sha 取 raw `_backlog.yml`，无撕裂读）。`REMOTE_RECONCILE_MODE=server` 且配置坏 = 拒绝启动；PAT 仅内存驻留、永不入日志（错误只报状态码）。
- **AC-3①② server 模式实测（对真 GitHub origin）**：手工把 CR-2026-002 投影行篡改为 `drafting`+needs_reconcile → 直接驱动真实 job handler → 从 `github.com/OldBoy405/AI-First-Platform` 拉到 HEAD f044711f5d2b + backlog（1 CR）→ 自愈为 `developing`、needs_reconcile=false、projected_commit=真实 HEAD。留有可重跑的 gated 测试 `TestReconcileLiveGitHub`（env 缺失自动跳过，CI 无感）。
- **AC-3 daemon 模式**：服务端边界全链路测试（snapshot 事件经 POST /cr-events 治愈篡改行 + 坏 payload 整体拒绝不半应用）+ daemon 侧 3 项（首拍即发/节流/上报失败不推进节流窗）。真机 daemon 进程闭环并入 T11 环境刷新。
- **PAT 范围核验（如实记录）**：Contents:Read-only 生效路径已实测；"仅单仓"无法从 API 侧证实——两个仓都是 public，任何 token 均可读，探测不具区分度。对 public 仓该 token 的增量风险为零；若仓库未来转 private，需重新核验单仓范围。
- **顺手修的既有边角**：采集器对没有 `.crctl/` 目录的 root 写 `.scan-cursor` 会永久失败导致全量重扫——补 MkdirAll（测试暴露）。
- **验证口径修正（诚实记录，涉及 T10）**：本任务期发现本机 postgres 密码是 `.env` 随机 48 位串（非 multica/multica 默认值），且宿主 5432 被 WSL relay 干扰——此前 T10 部分 DB 集成测试（audit 5 项、handler 端点 1 项）实际被 TestMain **静默跳过**而 `go test` 仍打 `ok`。已建 5433 专用转发 + 显式取真密码，**全部真库复跑通过**（governance 全包 24 项 + handler 聚合 1 项），T10 结论不变但验证时点以本记录为准。踩坑口径已记 CUSTOM.md C6。

---
id: CR-2026-002-TASK-06
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: daemon CR 事件收集器（crevents.go：outbox 扫描 + commit 兜底 + 上报）
status: pending
estimate: 12h
depends-on: [CR-2026-002-TASK-02, CR-2026-002-TASK-05]
assignee: ""
created: "2026-07-31T09:30:00+08:00"
---

## 任务描述
FR-2 daemon 半边：与 heartbeat 同周期扫描 outbox 与 commit log，合并去重后批量上报，accepted 才删文件。仓库：multica。

## 涉及文件
- 新增 `server/internal/daemon/crevents.go`（+ 测试）
- 修改 daemon 主循环：挂一个收集器调用（单处，AIFIRST 标记）

## 实现要点
- 扫描范围：daemon 已管理的 `.rayai-worktrees/` 各 worktree + 主 workspace 的 `.crctl/outbox/*.json`，按文件名字典序。
- commit 兜底：knowledge-base worktree 维护 `.crctl/.scan-cursor`，`git log {cursor}..HEAD --format=%H%x00%s` 增量；四类正则见 SDD §4.3（稳定契约，勿改格式）。
- 去重键 `(cr_id, commit_sha, event_kind)`——双通道同事件是常态非错误。
- 上报失败整批保留 + 指数退避；rejected 计数 ≥3 → 移 `.crctl/outbox/dead/`。
- git 调用走 T09 的 gitguard.Run（若 T09 未完成，临时直调 exec.Command 并留 TODO 标记，T09 收编）。

## 验收条件
1. 测试：outbox 3 文件 + commit 扫描同事件 → 上报 payload 去重后无重复。
2. 测试：server 返回 accepted 部分成功 → 仅 accepted 文件被删。
3. 端到端：断网跑 crctl advance（outbox 积压）→ 起 server 后 1 个周期内补传、文件清空（AC-1 后半）。
4. 测试：坏 JSON 事件三次 rejected → 进 dead/ 目录且告警日志一条。

## 完成标志
go test 绿 + 端到端补传实测通过 + 完成记录回填。

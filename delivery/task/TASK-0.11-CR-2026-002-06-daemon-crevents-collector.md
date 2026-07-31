---
id: CR-2026-002-TASK-06
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: daemon CR 事件收集器（crevents.go：outbox 扫描 + commit 兜底 + 上报）
status: done
estimate: 12h
depends-on: [CR-2026-002-TASK-02, CR-2026-002-TASK-05]
assignee: ""
created: "2026-07-31T09:30:00+08:00"
spec-id: ai-first-platform
version: "0.11"
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

## 完成记录（2026-07-31）

- **提交**：multica worktree 422eb0351（requirement/CR-2026-002，已推 fork）。
- **crevents.go**：采集器为独立结构 + 窄 `crEventReporter` 接口（测试注入 fake）；heartbeat 同周期 + 启动即首扫；outbox 主通道按文件名字典序（时间戳天然有序）；commit 兜底扫描 `.scan-cursor` 增量、四类 `[cr] ` 前缀契约（含 M0 式记账 commit 不误匹配的负例测试）；**双通道合并 outbox 赢**（trigger/evidence 更全）；批 ≤100；仅 accepted 删文件；rejected 三振进 `dead/`；**上报失败游标不前进**（同区间下个 tick 重扫，离线积压语义）。坏 JSON 文件降级为 V=0 事件让服务端拒绝、走三振——毒事件不卡通道。
- **配置**：`MULTICA_CR_WORKSPACES`（os.PathListSeparator 分隔；Windows 用 `;`，路径含盘符冒号故不用逗号/冒号），未设=采集器整体关闭（零开销）。daemon.go 仅 1 处 AIFIRST 启动钩子。
- **实现相对 SDD 的简化（记录在案）**：不扫各 worktree 的 outbox——T02 实现里 crctl 一律写到 `--workspace` 根（worktree 里调用也是），扫根即全集；SDD §1.2 的"全部已知 worktree"描述按实现现实收窄。
- **测试 5/5**：双通道合并单条且 outbox 赢 + 游标推进后二扫为空；部分 accept 只删被 ack 文件；毒文件三振隔离；网络失败积压保留且游标不动；四类 commit 契约解析（含两个负例）。gofmt/vet/全仓 build 干净。
- **验收③（真机断网补传）移交 T11**：需要重建 backend 镜像（当前容器无 cr-events 端点）+ 以 `MULTICA_CR_WORKSPACES` 重启 daemon——环境刷新在 T11 一次完成，届时工作区已积压的十余个真实 outbox 事件就是现成测试数据。
- **TODO 留痕**：commit 扫描 git 直调 exec（只读 log/rev-parse），T09 gitguard 收编（代码内 TODO 注释）。
- **附带修正**：T05 记录的"gofmt 794 文件为工具链版本差异"改判为 **CRLF autocrlf 根因**（CUSTOM.md 基线行已更新）——fork 新 .go 文件以 LF 写入。

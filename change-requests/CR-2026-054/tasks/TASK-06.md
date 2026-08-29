---
id: CR-2026-054-TASK-06
type: TASK
cr-ref: CR-2026-054
plan-ref: "change-requests/CR-2026-054/plan.md"
sdd-ref: "change-requests/CR-2026-054/sdd.md"
title: "接入 daemon 终态出口和重放 worker"
slug: daemon-terminal-replay
status: pending
estimate: 6h
depends-on: [CR-2026-054-TASK-05]
created: 2026-08-29T18:15:00+08:00
---

# 1. 任务描述

将终态补投核心接入 daemon 的唯一 `reportTerminalTask` 出口，抽出只发送的 helper，并实现 30 秒单 worker 的 snapshot 重放和 root context 关闭行为。

# 2. 涉及文件 / 模块

- `multica` worktree 的 `server/internal/daemon/terminal_report_retry.go`
- `multica` worktree 的 `server/internal/daemon/daemon.go`

# 3. 实现要点

- 实现精确 helper：`deliverTerminalTaskReport(ctx context.Context, report terminalTaskReport) error`，按 report.kind 调既有 CompleteTask/FailTask，复用有限重试。
- `reportTerminalTask` 只在最终瞬时错误时入队；complete 瞬时错误不 fallback，complete 永久错误才构造 fail report。
- 首次入队使用 `sync.Once` 绑定 daemon root context 启动单一 goroutine；重放只调用 deliver helper，不能递归调用 reportTerminalTask。
- 每 30 秒读取快照：成功删除，永久失败删除，瞬时失败保留并结束当前轮；删除前比较当前值与快照值；root context 取消时停止且不 drain。
- `daemon.go` 只保留 SDD 要求的零值字段和统一出口两个小型挂钩。

# 4. 验收条件

对应 PRD 验收标准：AC-5、AC-6。

1. complete 瞬时耗尽只入队 complete report 且不调用 FailTask；complete 永久失败才按既有顺序 fallback 到 FailTask，服务端 payload 保持完整。
2. 重放 worker 单实例、固定 30 秒、网络调用在锁外；首个瞬时错误结束本轮，下一轮仍可重试。
3. daemon root context 取消后 worker 停止，不执行额外 drain；`daemon.go` 不出现逐个 caller 改造或 logger 修改。

# 5. 完成标志

multica 编译通过，daemon 入口接入完成，代码 diff 符合 FR-18 的最小文件范围。

# 6. 接口契约

- 消费：TASK-05 产出的 `terminalReportRetry`、`terminalReportFailure` 及入队/snapshot/delete 能力；现有 daemon root context 和终态 client。
- 产出：`deliverTerminalTaskReport(ctx, report) error`、接入后的 `reportTerminalTask` 和单 worker 重放行为，供 TASK-07 测试；不改变服务端 API。

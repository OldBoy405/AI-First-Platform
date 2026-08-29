---
id: CR-2026-054-TASK-05
type: TASK
cr-ref: CR-2026-054
plan-ref: "change-requests/CR-2026-054/plan.md"
sdd-ref: "change-requests/CR-2026-054/sdd.md"
title: "实现 daemon 终态补投核心"
slug: terminal-report-retry-core
status: pending
estimate: 10h
depends-on: []
created: 2026-08-29T18:15:00+08:00
---

# 1. 任务描述

在 multica daemon 包内实现进程内终态补投集合、不可变报告保存、稳定错误分类和安全日志值，为统一终态出口和重放 worker 提供最小核心能力。

# 2. 涉及文件 / 模块

- `multica` worktree 的 `server/internal/daemon/terminal_report_retry.go`
- 需要时复用同包现有 `terminalTaskReport`、`isTransientError` 和 client 契约

# 3. 实现要点

- 定义零值可用私有 `terminalReportRetry`：`mu sync.Mutex`、`pending map[string]terminalTaskReport`、`once sync.Once`。
- 入队函数按 task ID first-wins，重复相同值不改变集合，冲突值保留首个并输出安全冲突字段。
- 报告按值复制；当前字段无引用类型，未来增加引用字段时在入队和 snapshot 边界深复制。
- 定义 `terminalReportFailure`，实现 `Error() string`、`Unwrap() error` 和 `LogValue() slog.Value`；LogValue 只输出 task_id、terminal_kind、error_class。
- 保留原始 cause 供 `errors.As`/`isTransientError` 和 complete 永久 fallback 使用，但不让 logger 展开原始 cause。

# 4. 验收条件

对应 PRD 验收标准：AC-5、AC-6。

1. 同一 task ID 的相同报告去重，冲突报告 first-wins；比较覆盖当前 report 全部值字段。
2. `terminalReportFailure.LogValue()` 的字段集合严格为 `task_id`、`terminal_kind`、`error_class`，不含原始 cause、errorMessage、output、session、workdir 或完整 report。
3. `Unwrap()` 保持原始瞬时/永久错误分类，`Error()` 仍可供既有 complete 永久 fallback 构造服务端 errorMessage。

# 5. 完成标志

核心文件可由 daemon 零值实例使用，Go 编译通过，单元测试证明值复制、first-wins 和日志脱敏。

# 6. 接口契约

- 消费：同包现有 `terminalTaskReport`、`terminalTaskReportKind`、错误分类函数和 client 错误契约；这些结构必须复用。
- 产出：私有 `terminalReportRetry`、`terminalReportFailure`、入队/snapshot/delete 比较能力，供 TASK-06 和 TASK-07 调用；不导出 daemon 包外 API。

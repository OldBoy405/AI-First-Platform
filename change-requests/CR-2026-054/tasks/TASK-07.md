---
id: CR-2026-054-TASK-07
type: TASK
cr-ref: CR-2026-054
plan-ref: "change-requests/CR-2026-054/plan.md"
sdd-ref: "change-requests/CR-2026-054/sdd.md"
title: "完成终态补投测试和定制登记"
slug: terminal-replay-tests
status: pending
estimate: 6h
depends-on: [CR-2026-054-TASK-06]
created: 2026-08-29T18:15:00+08:00
---

# 1. 任务描述

为 daemon 补投实现建立同包可重复测试，覆盖交付顺序、重放边界、payload 保真和日志脱敏，并按 multica 当时实际结构登记所有定制项。

# 2. 涉及文件 / 模块

- `multica` worktree 的 `server/internal/daemon/terminal_report_retry_test.go`
- `multica` worktree 的 `CUSTOM.md`
- 必要时只修改与测试 fixture 直接相关的 daemon 测试文件

# 3. 实现要点

- 使用 httptest client 或同包 fixture 驱动单轮 helper，不等待真实 ticker。
- 覆盖 complete/fail 瞬时耗尽、永久错误、complete→fail fallback、成功删除、瞬时保留、永久删除、重复/冲突 first-wins、关闭取消和报告值复制。
- 使用捕获 `slog.Handler` 验证新增错误值只包含三个稳定字段，不含原始 cause、errorMessage、output、session、workdir 或完整 report；实际成功任务 caller 的 error 属性必须通过 `terminalReportFailure` 或等价安全值记录。
- 断言 `errors.Unwrap`/`isTransientError` 和实际成功任务 caller 的 fallback 语义未变。
- 按 CUSTOM.md 当前表格结构登记新文件、AIFIRST 挂钩、CR/TASK 来源和验证命令；Go 注释使用英文。

# 4. 验收条件

对应 PRD 验收标准：AC-5、AC-6。

1. `go test` 覆盖所有 SDD §7.3 multica 场景并通过，包含 complete 瞬时不 fallback 和永久才 fallback 的明确请求断言。
2. 日志捕获测试验证每个新增终态错误值字段严格受限，原始 cause 和终态敏感字段不会被格式化或展开。
3. `CUSTOM.md` 登记与实际 diff 文件、挂钩和验证命令逐项一致，没有遗漏或虚构条目。

# 5. 完成标志

daemon 相关 Go 测试通过，`CUSTOM.md` 完成台账核对，multica diff 可供 code review 直接审查。

# 6. 接口契约

- 消费：TASK-06 产出的 `deliverTerminalTaskReport(ctx, report) error`、重放 worker 和已接入 `reportTerminalTask`；TASK-05 的安全错误值。
- 产出：Go 测试证据、日志脱敏证据和 CUSTOM.md 定制登记，供 M4 集成验证及 `write-test-report` 消费。

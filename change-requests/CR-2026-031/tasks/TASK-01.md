---
id: CR-2026-031-TASK-01
type: TASK
cr-ref: CR-2026-031
plan-ref: "change-requests/CR-2026-031/plan.md"
sdd-ref: "change-requests/CR-2026-031/sdd.md"
title: 建立事务故障注入与红测基线
slug: transaction-fault-harness
status: pending
estimate: 8h
depends-on: []
created: 2026-08-11T17:36:00+08:00
---

# 1. 任务描述

建立仅测试启用的确定性 fault harness，并先用红测覆盖 write-set、register、merge、writeback、archive 的关键中断点。输入为 SDD §9 fault points；输出为可复用测试 helper 和失败基线，不实现事务修复本身。

# 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/test/crctl.test.mjs`
- `skills/shared/crctl/scripts/test/` 下既有或新增测试 helper（仅在确有复用时）
- `skills/writeback/scripts/test/writeback.test.mjs`

# 3. 实现要点

- 使用 Node test、临时目录和真实 Git bare remote；不引入依赖。
- `CRCTL_FAULT_POINT` 未设置时必须零行为；设置未知 point 硬失败。
- 红测覆盖 rename 前后、push 成功响应丢失、finalize/cleanup 中断。
- 测试读取文本时先 CRLF 规范化。

# 4. 验收条件

1. 运行 crctl 测试时，新 fault vectors 在旧实现上能稳定暴露至少一个半写或不可续跑失败。
2. 同一 fault point 在 Windows/Ubuntu 命名和触发语义一致，未知 point 测试返回结构化错误。
3. 未设置环境变量时现有测试结果不变。

# 5. 完成标志

fault harness 可由后续 TASK 复用，红测证据记录清楚，lint 与未受影响既有测试通过，任务状态登记 done。

# 6. 接口契约

消费：无。

产出：测试侧 `runCrctl(args: string[], options?: { cwd?: string, env?: Record<string,string>, expectExit?: number }): Promise<{ code:number, stdout:string, stderr:string }>`；生产侧约定环境变量 `CRCTL_FAULT_POINT: string`，由 TASK-04 提供 `fault(point: string, context?: object): void` 实现。

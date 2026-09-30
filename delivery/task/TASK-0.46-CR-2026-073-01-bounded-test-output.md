---
spec-id: ai-first-platform
version: "0.46"
id: CR-2026-073-TASK-01
type: TASK
cr-ref: CR-2026-073
plan-ref: "change-requests/CR-2026-073/plan.md"
sdd-ref: "change-requests/CR-2026-073/sdd.md"
target-version: 0.46
title: 有界测试输出及 ENOBUFS 技术分类
slug: bounded-test-output
status: pending
estimate: 8h
depends-on: []
created: 2026-09-30T13:05:00+08:00
---

## 任务描述

G1 / FR-1～FR-3 / AC-1～AC-3。以批准 SDD §2、§3.1 为输入，在现有同步 `runTestPlan` 增加固定 10 MiB buffer，溢出硬失败且不发布不完整证据；不改测试计划字段和调用签名。

## 涉及文件 / 模块

`tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs` 的 `runTestPlan`；`tools/skills/shared/crctl/scripts/test/test-cr.test.mjs` 的定向黑盒夹具。

## 实现要点

`spawnSync` 保持 `shell:false` / `encoding:'utf8'`，增加 `maxBuffer: 10 * 1024 * 1024`；在临时日志、skip、SHA 和 canonical 构造前区分 `r.error?.code === 'ENOBUFS'`，抛 `TxError('TEST_OUTPUT_EXCEEDED', ...)`，额外字段含 `errCode:'ENOBUFS'`、`maxBufferBytes:10485760`、`exitCode:null`；截断片段仅标诊断，不作断言。其它 error、ETIMEDOUT、真实非零仍按原分支处理。测试用单段 >1 MiB <10 MiB 与单段 >10 MiB，禁止把大输出直接回显终端。

## 验收条件

1. `cmd-01`（plan §6）：只执行 `CR073 long output complete` 案例，验证 stdout/stderr 分区、真实 exit/signal/skip/timeout 与 SHA，不声称全仓通过。
2. `cmd-02`（plan §6）：只执行 `CR073 true failure and legacy classification` 案例，真实非零仍 block，timeout 和启动失败沿用旧类。
3. `cmd-03`（plan §6）：只执行 `CR073 overflow preserves canonical` 案例，ENOBUFS/10485760/null exit 明示，四类 canonical 文件逐字节不变、无完整证据发布。

## 完成标志

TASK-01 变更和上述三个实际运行的定向案例落盘；保留命令真实结果及范围；开发期由 `crctl task done CR-2026-073 --task CR-2026-073-TASK-01 --workspace <KB CR worktree>` 即时登记，不等待回写。无后续 TASK 产物前置。

## 接口契约

- 消费：既有 `plan.commands[]` 中 `executable`、`args`、`absoluteCwd`、`timeoutSeconds`，以及 SDD §3.1 的 `runTestPlan(plan, ctx, cr)` 入参；不改变外部调用。
- 产出：`runTestPlan(plan, ctx, cr)` 仍返回 `{ results, resultFacts, tempLogs, overall }`；`testCr(ctx, { cr, workspace, planPath })` 仍消费该结果；溢出在返回前抛 `TxError('TEST_OUTPUT_EXCEEDED', ...)`，不创建 canonical 机器报告或完整 `cmd-NN.log`。不改变对外签名或字段。与其它 TASK 无消费关系。

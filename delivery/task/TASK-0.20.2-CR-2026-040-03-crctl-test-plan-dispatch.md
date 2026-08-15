---
spec-id: ai-first-platform
version: "0.20.2"
id: CR-2026-040-TASK-03
type: TASK
cr-ref: CR-2026-040
plan-ref: "change-requests/CR-2026-040/plan.md"
sdd-ref: "change-requests/CR-2026-040/sdd.md"
title: crctl.mjs test 子命令迁移到 --plan
slug: crctl-test-plan-dispatch
status: pending
estimate: 4h
depends-on:
  - CR-2026-040-TASK-02
created: 2026-08-15T12:00:00+08:00
---

## 任务描述

将 `skills/shared/crctl/scripts/crctl.mjs` 的 `test` 子命令从 `--cmd` shell 字符串执行改为 `--plan <temp-json>`，删除 `cmdTest` 内 `spawnSync(..., {shell:true})`、逐条 `auditLog` 和直接覆盖报告的逻辑，改为解析参数后调用 `workspace-transactions.testCr` 并输出结构化结果。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`

## 实现要点

- argv 解析：`test` 分支只接受 `--plan` 与 `--workspace`；拒绝并 `BAD_ARGS` 掉 `--cmd`/`--cwd`/`--timeout`。
- `cmdTest(ws, cr, gates, flags)` 改为薄接线：`resolveRepositories`、`testCr`、`ok(response)`；不自行执行命令或写报告。
- 业务 `status: block` 仍走 `ok(...)` 且 exit 0；技术错误沿用 `fail(code, message, extra)` 非零退出。
- 同步 `HELP` 中的 `crctl test` 一行说明；删除 `--cmd` 相关帮助与解析残留。

## 验收条件

- `crctl test CR-2026-040 --plan <合法plan>` 黑盒返回 `op/status/commandDigest/attempt/commands/report/traceability/reviewLoop`；业务 block 仍 exit 0。
- `crctl test CR-2026-040 --cmd "echo hi"` 返回 `BAD_ARGS`，不执行命令、不产生报告/审计。

## 完成标志

- `cmdTest` 不再出现 `shell:true`、`flags.cmdList`、逐条 test audit 或 `fs.writeFileSync(reportPath, ...)`；`git diff` 仅命中 `crctl.mjs`。

## 接口契约

- 消费：`workspace-transactions.mjs` 的 `testCr(ctx, {cr, workspace, planPath})`、`resolveRepositories`、`resolveOperationalWorkspace`；`crctl.mjs` 既有 `ok`/`fail`/`requireCr`。
- 产出：`crctl test <CR-ID> --plan <path> --workspace <ws>` 的 stdout JSON `TestResponse`，供 TASK-04/05/06 与 `write-test-report` 消费。

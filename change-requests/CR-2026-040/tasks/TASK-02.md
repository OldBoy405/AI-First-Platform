---
id: CR-2026-040-TASK-02
type: TASK
cr-ref: CR-2026-040
plan-ref: "change-requests/CR-2026-040/plan.md"
sdd-ref: "change-requests/CR-2026-040/sdd.md"
title: workspace-transactions 新增 testCr 深接口
slug: workspace-transactions-test-cr
status: pending
estimate: 8h
depends-on:
  - CR-2026-040-TASK-01
created: 2026-08-15T12:00:00+08:00
---

## 任务描述

在 `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` 新增结构化测试业务处理器 `testCr` 及其纯函数，承担 plan 校验、`shell:false` 执行、原始日志暂存、marker 分区、机器报告/`traceability.yml#tests`/`review-loop.yml` 的原子写集编排。只依赖既有 repository resolver、`readCrMdStatus`、hash 和 durable-tx 原语。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`

## 实现要点

- 纯函数（不新增公共命令）：
  - `parseTestPlan(raw, ctx, cr)`：CRLF→LF 后 JSON.parse，校验 `schema: cr-test-plan/v1`、非空 commands、字段类型与白名单、repo 解析、cwd realpath containment、worktree 与 `requirement/{CR-ID}` 分支。
  - `canonicalCommandSubject(plan)`：固定键序 JSON，`sha256(JSON.stringify(subject))`。
  - `runTestPlan(plan, ctx, cr)`：`spawnSync(executable, args, {shell:false, cwd, timeout})`；已启动 non-zero/timeout 记业务 block 并继续，启动失败/参数错误中止；日志写 `.crctl/tmp/test/{cr}/{token}/cmd-NN.log`。
  - `parseAnalysisMarker(existingReport)`：唯一 literal `<!-- crctl:analysis-below -->`，缺失/重复硬失败。
  - `renderTestMachineReport(input)`、`renderTestsTraceability(existing, input)`。
- `export async function testCr(ctx, {cr, workspace, planPath})`：
  1. state=`developing`、`owners.test.id`/`assigned-at` 存在、attempt 未达上限；
  2. loadAndValidatePlan；
  3. 运行阶段不建 journal、不持锁；
  4. 读取现有 report/traceability/review-loop 并构造四处 after 文本；
  5. `loadOrCreateJournal({op:"test", cr, graphDigest, inputDigest})` + `applyWriteSet` 一次发布；
  6. 复用既有 review-loop 渲染，输出结构化结果。
- 审计只记一条 `{kind:"test", cr, status, attempt, digest}`，不逐命令审计；stdout/stderr 不进 audit/traceability。

## 验收条件

- 合法 plan 全绿时报告机器区含 `status: pass`、规范化 commands、`command-digest`、日志路径；`traceability.yml#tests` 与 `review-loop.yml` 同批更新。
- 首命令 non-zero 或 timeout 时剩余命令仍执行，最终 `status: block` 且完整证据已发布。
- `tx-apply-between-rename` 注入时恢复后无半状态；已完成事务重放 `changed=false` 且不重复 attempt。

## 完成标志

- `testCr` 及其纯函数可被 `crctl.mjs` 黑盒调用，且不直接写 `_backlog.yml`/`cr.md`；`git diff` 仅命中 `workspace-transactions.mjs`。

## 接口契约

- 消费：`durable-tx.mjs` 的 `acquireLock`、`loadOrCreateJournal`、`saveJournal`、`applyWriteSet`、`recoverWriteSet`、`faultPoint`、`nowIso`；`resolveRepositories`、`getRepository`、`readCrMdStatus`（同模块内）。
- 产出：
  - `export function parseTestPlan(raw, ctx, cr) -> NormalizedPlan`
  - `export function canonicalCommandSubject(plan) -> { subject: object, digest: string }`
  - `export function runTestPlan(plan, ctx, cr) -> { results: CrTestResult[], tempLogs: string }`
  - `export function parseAnalysisMarker(existingReport: string|null) -> { machinePrefix: string, analysisSuffix: string }`
  - `export function renderTestMachineReport(input) -> string`
  - `export function renderTestsTraceability(existing: string|null, input) -> string`
  - `export async function testCr(ctx, { cr, workspace, planPath }) -> TestResponse`

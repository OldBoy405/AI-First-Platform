---
spec-id: ai-first-platform
version: "0.33"
id: CR-2026-060-TASK-04
type: TASK
cr-ref: CR-2026-060
plan-ref: "change-requests/CR-2026-060/plan.md"
sdd-ref: "change-requests/CR-2026-060/sdd.md"
target-version: "0.33"
title: G4 writeback/archive 双路径、new traceability 与 Pipeline 收敛
slug: writeback-archive-trace-pipeline
status: pending
estimate: 18h
depends-on: ["CR-2026-060-TASK-01", "CR-2026-060-TASK-03"]
created: 2026-09-03T00:35:00+08:00
---

## 任务描述

落地 G4：`writeback-apply`/`archive` 的 new/legacy 双路径（消费 TASK-01 的 `resolveTargetSpecMode` 与 `resolveWritebackAuthorityStrict`）、stage=tasks 的 pending preflight、`writeback-traceability.mjs` 的 `--mode new` 分支（legacy 逐字节保留）、archive journal payload 扩展与清理后重放、三个 writeback Skill + `cr-archive`、`review-alignment` 只读化、8 条 Pipeline JSON 的 prompt 收敛（`requirement-authoring` 的 inputs 必填已由 TASK-01 落盘，本 TASK 负责其余 7 条 + 该条的 prompt 五类信息收敛）、规划/竞品/resume 消费 Skill 输入对齐。

完成边界是 developing 内可登记事件：实现与测试已落盘、cmd-04/cmd-05 新增向量绿。**不是**「本 CR 已 merge/writeback/archive」。

输入条件：TASK-01 与 TASK-03 均已 `crctl task done`；tools HEAD 含二者 commit。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`：`cmdWritebackApply`（:3401）mode 分支；`cmdArchive`（:3368）new 可省 spec-id + journal 重放映射
- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`：`applyWritebackAtomic` 入口 `preflightTasksAllDone`（candidate/journal 之前）；`prepareWritebackCandidate`（:2371 附近）mode=new 时跳过 `milestoneFile` 必填并 spawn `--mode new`；`archiveCr`（:3307）payload 增加 `mode`/`specId`/`targetSpecId`
- `skills/writeback/scripts/writeback-traceability.mjs`：新增 `--mode new` 分支（§4.8）；legacy 分支（:60-120 milestone 校验与 fr-chain 构造）逐字节保留
- `skills/writeback/{writeback-prd-sdd,writeback-tasks,writeback-traceability}/SKILL.md`、`skills/cr/cr-archive/SKILL.md`
- `skills/review/review-alignment/SKILL.md`：任意状态只读；输出 `{skill,cr_id,spec_id,current-status,result,drifts,summary}`；不落盘、不写 traceability、不读 mtime/backlog merge-commit/fingerprint；不调用任何 crctl 写命令
- `pipeline-templates/{architecture-design,code-implementation,feature-writeback,product-planning,market-to-plan,competitive-radar,resume-cr}.pipeline.json` 及 `requirement-authoring.pipeline.json` 的 prompt 收敛（§4.9）
- `skills/planning/**/SKILL.md`、`skills/competitive/**/SKILL.md`、`skills/cr/cr-show/SKILL.md`（PRD §3.3.1 必填输入）
- `skills/shared/crctl/scripts/test/writeback-tx.test.mjs`（cmd-04）
- `skills/shared/crctl/scripts/test/archive-tx.test.mjs`（cmd-05）
- `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`（cmd-01，节点数/reviewLoop/passCondition 不漂移）

禁止改动：`writeback-prd-sdd.mjs` / `writeback-tasks.mjs` 两个 generator（完全冻结）；`applyWritebackAtomic` 的 candidate/manifest/journal/commit/push 内核；`durable-tx.mjs`；`gates.json`；Pipeline 的节点数量、`reviewLoop.maxAttempts`/`replayNodes`/`passCondition`、checkpoint 顺序。

## 实现要点

1. `cmdWritebackApply` 顺序严格按 SDD §4.4：参数形态 → `resolveWritebackAuthorityStrict` → `resolveTargetSpecMode({authority: strictAuth})` → new 的 milestone 拒绝（`BAD_ARGS`）与 spec/version 省略补全/显式相等校验（`WRITEBACK_SPEC_MISMATCH` / 既有 `WRITEBACK_VERSION_*`）→ stage=tasks 时 `preflightTasksAllDone` → 既有 version guard / opWs / 第 5.5 步同源绑定 / candidate/journal。legacy 现行路径逐字节保留。
2. `preflightTasksAllDone(txws, cr)`：索引缺失/空 → `WRITEBACK_TASKS_PENDING` `reason=index-missing`；畸形 YAML/重复 id/未知 status → `reason=index-invalid`（硬失败禁止静默降级）；任一非 done → `reason=pending`（`extra.pending` 列 id）。位于 `prepareWritebackCandidate` 之前，零 candidate/journal。
3. traceability new 分支：输入 = 冻结 PLAN 两张表 + TASK 账本/卡 + test-report + merge-commits.yml；映射 `FR→SDD→TASK→repo@mergeSHA→cmd`；plan 表不可解析或 TASK/证据交叉失败 → `STRUCTURE_MISMATCH`；`--milestone-file` 不传入。legacy 夹具逐字节回归。
4. archive：writing-back 首跑 new 可省 `--spec-id`，strict 失败映射为既有 `ARCHIVE_SPEC_REQUIRED`，解析值在 candidate/cleanup 前写入 payload。清理后重放只读 journal payload；payload 缺 specId 且无 flag → `ARCHIVE_SPEC_REQUIRED`。不重放 generator、不重选 spec/version。
5. Pipeline prompt：每条 `kind=skill` 节点只保留五类信息；删改后机械断言不出现账本手写步骤、不出现 crctl 算法副本、不出现 status→节点映射表；`node.ref` 全部为 active Skill；节点数量与 `_index.yml` 一致。
6. review-alignment 不进入 `feature-writeback` Pipeline。

## 验收条件

1. new mode 省略 spec/version 时从 strict txws 读取；显式不一致 → `WRITEBACK_SPEC_MISMATCH`/`WRITEBACK_VERSION_MISMATCH` 且 candidate/journal 前零写入（cmd-04 / AC-11）。
2. txws 缺失/不自洽 → `WRITEBACK_SPEC_REQUIRED`，不消费 cr-worktree 回退（cmd-04 / AC-02/AC-11）。
3. new 传 milestone → `BAD_ARGS`（cmd-04 / AC-11）。
4. stage=tasks 索引缺失/非法/pending → `WRITEBACK_TASKS_PENDING`（三类 `reason`）零写入零发布（cmd-04 / AC-12）。
5. new traceability 由冻结 PLAN/TASK/test-report/merge facts 生成 `FR→SDD→TASK→repo@mergeSHA→cmd`；同输入重复生成 noop；legacy 夹具逐字节不变（cmd-04 / AC-12）。
6. archive new 省略 spec-id 的首跑从 strict authority 解析并持久化 payload；清理后重放只读 payload；payload 缺 spec-id → `ARCHIVE_SPEC_REQUIRED`（cmd-05 / AC-13）。
7. legacy writeback/archive 缺参行为与基线一致（cmd-04/cmd-05 既有向量 / AC-11）。
8. 8 条 Pipeline JSON 可解析、节点数与 `_index.yml` 一致、全部 `node.ref` 为 active Skill；requirement/architecture/coding/writeback 的顺序、reviewLoop、replayNodes、passCondition、checkpoint 前置与基线一致（cmd-01 / AC-15）。
9. review-alignment SKILL 声明任意状态只读、不调用 crctl 写命令、不写 traceability/status/annotation/review-loop/Git（cmd-01 / AC-13/AC-18）。
10. 既有 writeback-tx / archive-tx 用例除 §5.3 BR-2 外不新增失败；cmd-06 既有 version-set/test-cr 不新增失败（AC-16）。

## 完成标志

上述代码与 SKILL/Pipeline 已落盘；cmd-04 与 cmd-05 新增向量全绿；cmd-01 Pipeline 机器事实不漂移；提交 `[cr] implement CR-2026-060 TASK-04`；`crctl task done CR-2026-060 --task CR-2026-060-TASK-04`。本 TASK 不执行、不等待本 CR 的 merge/writeback/archive 流程节点。

## 接口契约

- 消费（来自 TASK-01，签名必须全等）：
  - `resolveTargetSpecMode(ctx, cr, { authority: { path: string, source: string } }) → { mode: 'new', targetSpecId: string } | { mode: 'legacy' }`；`TxError('TARGET_SPEC_AUTHORITY_DRIFT', ..., { kind })`
  - `resolveWritebackAuthorityStrict(ctx, cr) → { path: string, source: 'transaction-workspace' }`；`TxError('WRITEBACK_SPEC_REQUIRED' | 'WRITEBACK_STATE_MISMATCH')`
- 消费（来自 TASK-03，文件序依赖）：`crctl.mjs` 已含 `cmdTaskInit --count-hint` 写入前校验；本 TASK 不得改回该分支。
- 产出：
  - `preflightTasksAllDone(txws, cr) → void`；失败抛 `TxError('WRITEBACK_TASKS_PENDING', ..., { reason: 'index-missing'|'index-invalid'|'pending', pending?: string[] })`
  - `writeback-traceability.mjs` CLI：legacy 保持 `--workspace --cr --spec --version --milestone-file --candidate-out`；new 为 `--mode new --workspace --cr --spec --version --candidate-out`（无 `--milestone-file`）；`--validate-evidence` 模式零改动
  - `archiveCr` journal payload 增补字段：`mode: 'new'|'legacy'`、`specId: string`、`targetSpecId: string | undefined`（新建冻结，重试只读）
  - `cmdWritebackApply` / `cmdArchive` 对外 JSON 既有键保持；new 分支 `recover_command` 含解析后的 spec/version，new traceability 不再含 `--milestone-file`

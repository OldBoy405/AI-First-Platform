---
id: CR-2026-075-TASK-10
type: TASK
cr-ref: CR-2026-075
plan-ref: "change-requests/CR-2026-075/plan.md"
sdd-ref: "change-requests/CR-2026-075/sdd.md"
target-version: 0.48
title: 全量证据回归与未覆盖风险清单
slug: full-evidence-regression-and-residual-risk
status: pending
estimate: 4h
depends-on: [CR-2026-075-TASK-01, CR-2026-075-TASK-02, CR-2026-075-TASK-03, CR-2026-075-TASK-04, CR-2026-075-TASK-05, CR-2026-075-TASK-06, CR-2026-075-TASK-07, CR-2026-075-TASK-08, CR-2026-075-TASK-09]
created: 2026-10-03T00:15:00+08:00
---

## 任务描述

在全部前置 TASK 完成后，按 plan §6.2 证据命令表原样复跑 `cmd-01`～`cmd-10`，把真实运行结果（命令、cwd、退出码、关键输出、真实运行范围）归档到 `change-requests/CR-2026-075/test-evidence/`，并汇总未覆盖风险与 `pending-deploy` 清单（FR-16；SDD §5.2/§5.3）。本 TASK 只做回归与证据归档，**不含任何实现动作**，也不包含 merge / 审批 / 回写等 Pipeline 控制步骤。

## 涉及文件 / 模块

- `change-requests/CR-2026-075/test-evidence/`（KB 仓）— 证据归档：
  - `cmd-01`～`cmd-10` 各自的原始输出与命令记录（含 cwd、退出码、用例计数 / `--- PASS` 行摘要）；
  - `uncovered-risks.md` — 未覆盖风险清单（R10、R11 的复跑结论与 §5.2 中未由 `cmd-*` 覆盖的向量）；
  - `pending-deploy.md` — FR-15 第③④步平台侧未闭合项（消费 TASK-09 台账，复用同一 `pending-deploy` 口径）。
- 不修改实现仓代码、不改 `rules.json`、不改受控账本（`_index.yml` 仅由 `crctl task done` 更新）。

## 实现要点

- 逐条按 plan §6.2 的行原样执行（executable / args / cwd / timeout 不改写、不合并、不替换）：
  - `cmd-01`（tools，`.`，`node --test skills/shared/crctl/scripts/test/crctl.test.mjs`）→ A 段 CLI 归一/失败关闭 + validate 维度层 + 业务入口域用例。
  - `cmd-02`/`cmd-03`（tools，`.`，新增单文件 `planning-entry.test.mjs`/`competitive-report.test.mjs`）→ 两个业务入口与 B15-a/B15-b/B15-c/B18-a。
  - `cmd-04`（tools，`.`，`durable-tx.test.mjs`）→ 原语 `expect` 锁内比对与 `sampleCommitState` 锁内取样（B17-a/B17-b、B18-b/B18-c/B18-d）。
  - `cmd-05`/`cmd-06`（tools，`.`，调用方合同 + 四个合同扫描单文件）→ 提示/登记一致性。
  - `cmd-07`（tools，`skills/shared/engineering-docs/scripts`，`node node_modules/vitest/vitest.mjs run`）→ 工程文档侧北京时间。
  - `cmd-08`（multica，`server`，`go test ./internal/daemon/ -count=1 -v -run "…"`）→ daemon 绑定解析与发布。
  - `cmd-09`（multica，`.`，`delegation-contract.test.mjs`）→ 合同与维护副本一致性。
  - `cmd-10`（multica，`.`，内联只读脚本）→ 部署副本收敛、imported Skills 取用路径、线上 Agent instructions `sha256` 基线。
- 记录口径（CR-2026-073 FR-6/FR-8）：每个 `cmd-NN` 写明真实运行范围（单文件 / 单包定向名集 / 单目录）；范围小于全仓的命令**不得**在任何产物中表述为「全量通过」；不使用 `go test ./...`、`make test` 等全仓命令，不新增 plan 未列的命令行。
- 文档面：`test-report` 由 `owners.test` 责任执行（`write-test-report` Skill），其输入是本 TASK 归档的真实运行结果；本 TASK 不代替 test-report、不写 pass/fail 结论，只提供原样结果与范围说明。
- 未覆盖风险至少逐条记录：R10（multica `./internal/daemon/` 包内 `TestRegisterTaskReposAllowsProjectOnlyURL` 在本机 Windows 因临时仓路径超 MAX_PATH 失败，与本 CR 无关，`cmd-08` 使用定向 `-run` 名集故声明面不覆盖该用例）、R11 的复跑结论（`cmd-09` 收敛后应转绿；若仍红，逐字记录失败项）、§5.2 中由节点日志/回放验收而非 `cmd-*` 覆盖的向量（B1/B3 调用方一次本地纠正、B4 保留项人工检查边界）、FR-15 第③④步平台侧部署未执行项（`pending-deploy`）。

## 验收条件

1. 在 tools CR worktree 根按顺序执行 `cmd-01`～`cmd-07`，在 multica CR worktree 根（`cmd-08` 的 cwd 为 `server`）执行 `cmd-08`～`cmd-10`；十条命令的 executable / args / cwd / timeout 与 plan §6.2 表逐字一致，全部返回可判定结果（全绿为预期；任一红则如实记录原始输出与失败项，不在本 TASK 内修实现）。
2. `test-evidence/` 归档完整：十条命令各有一份原始输出与命令记录；每份记录含 cwd、退出码、真实运行范围说明；`cmd-08` 附 `-v` 的 `--- PASS` 行摘要与九个名集分支命中情况；`cmd-10` 附 imported Skills 取用路径列表与四份线上 Agent instructions `sha256`。
3. `uncovered-risks.md` 覆盖 R10、R11、§5.2 的非 `cmd-*` 向量，并逐条写明「观测面 < 声称面」的边界；不把定向运行表述为全量。
4. `pending-deploy.md` 与 TASK-09 台账口径一致：FR-15 第③④步未闭合项全部标 `pending-deploy`，不表述为已生效。
5. 文件集检查经受控入口（argv 固定）：KB worktree 根执行 `node <tools-worktree>/skills/shared/crctl/scripts/crctl.mjs git status --porcelain --cwd <knowledge-base-worktree> --workspace <knowledge-base-worktree>`，断言新增文件仅在 `change-requests/CR-2026-075/test-evidence/` 下（外加 `tasks/_index.yml` 的 `crctl task done` 受控更新）；实现仓（tools、multica）worktree 的 `git status --porcelain` 为空（本 TASK 零实现改动）。

## 完成标志

- `cmd-01`～`cmd-10` 全部按原样执行且有原始输出归档；任何红项如实记录、不隐藏、不以范围缩小冒充绿。
- `uncovered-risks.md`、`pending-deploy.md` 落盘；`test-evidence/` 可供 `write-test-report` 直接消费。
- 实现仓零改动（tools/multica worktree clean）；KB 侧仅新增 `test-evidence/` 文件与本 TASK 的 `tasks/_index.yml` done 登记。
- 产物已落盘并提交；不做 merge / 审批 / 回写动作（Pipeline 控制步骤不在 TASK 内）。

## 接口契约

**消费**（逐字对齐 SDD 与目标仓现状）：

- plan §6.2 证据命令表：`cmd-01`～`cmd-10` 的 `repo`/`cwd`/`executable`/`args`/`timeout` 五列是唯一事实源，本 TASK 不另写第二套命令形态。
- 各前置 TASK 的产物：TASK-01 的 A 段 CLI 用例与 `cmd-01`；TASK-02 的 daemon 用例与 `cmd-08`；TASK-03 的原语向量与 `cmd-04`；TASK-04/05 的业务入口用例与 `cmd-02`/`cmd-03`；TASK-06 的 validate 向量；TASK-07 的 vitest 向量与 `cmd-07`；TASK-08 的 `cmd-05`/`cmd-06`；TASK-09 的 `cmd-09`/`cmd-10` 与生效版本台账。
- `multica` CLI 只读查询（`skill list`/`agent list`）与三仓 CR worktree（Pipeline `resources[].worktreePath`、`classification=healthy`、`dirty=false`）。

**产出**：

- `test-evidence/` 证据集（十条命令的原始输出 + 命令记录 + `uncovered-risks.md` + `pending-deploy.md`）。
- 供下游消费的稳定引用：`write-test-report` 的机器区与 traceability 引用同一份 `test-evidence/`（不复制、不改写结果）；`review-code` 的证据核对引用同一份归档；FR-15 的平台侧部署后复跑比对以同一 `cmd-10` 为基线，未闭合前差异恒为 `pending-deploy`。

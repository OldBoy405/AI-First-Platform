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

在全部前置 TASK 完成后，按 plan §6.2 证据命令表原样复跑 `cmd-01`～`cmd-12`，把真实运行结果（命令、cwd、退出码、关键输出、真实运行范围）归档到 `change-requests/CR-2026-075/test-evidence/`，并汇总未覆盖风险与生效版本比对的复跑结论（FR-16；SDD §5.2/§5.3）。本 TASK 只做回归与证据归档，**不含任何实现动作**，也不包含 merge / 审批 / 回写等 Pipeline 控制步骤。

## 涉及文件 / 模块

- `change-requests/CR-2026-075/test-evidence/`（KB 仓）— 证据归档：
  - `cmd-01`～`cmd-12` 各自的原始输出与命令记录（含 cwd、退出码、用例计数 / `--- PASS` 行摘要）；
  - `uncovered-risks.md` — 未覆盖风险清单（R10、R11、R12 的复跑结论与 §5.2 中未由 `cmd-*` 覆盖的向量）；
  - `effective-version-rerun.md` — FR-15/AC-B14 的复跑结论：`cmd-09`/`cmd-10`/`cmd-11` 的比对结果与 TASK-09 台账一致时记「实际生效版本一致（覆盖规划/竞品调用方）」；仍不一致则逐条记录目标与两侧 sha256 并报缺失前置（不标 `pending-deploy` 充作通过）。
- 不修改实现仓代码、不改 `rules.json`、不改受控账本（`_index.yml` 仅由 `crctl task done` 更新）。

## 实现要点

- 逐条按 plan §6.2 的行原样执行（executable / args / cwd / timeout 不改写、不合并、不替换）：
  - `cmd-01`（tools，`.`，`node --test skills/shared/crctl/scripts/test/crctl.test.mjs`）→ A 段 CLI 归一/失败关闭 + validate 维度层 + 业务入口域用例。
  - `cmd-02`/`cmd-03`（tools，`.`，新增单文件 `planning-entry.test.mjs`/`competitive-report.test.mjs`）→ 两个业务入口与 B15-a/B15-b/B15-c/B18-a。
  - `cmd-04`（tools，`.`，`durable-tx.test.mjs`）→ 原语 `expect` 锁内比对与 `sampleCommitState` 锁内取样（B17-a/B17-b、B18-b/B18-c/B18-d）。
  - `cmd-05`（ai-first-platform-docs，`.`，内联只读脚本）→ 实际受控调用方节点回放（`test-evidence/caller-replay/{A,B}.node-record.json` 原始记录 + 索引 `records.json`，TASK-08 产出）的逐字段归因与断言：归因字段/`execution_context`/绑定环境三值与短提示原文（`input.shortPrompt` 逐字投影五项保留片段）/受控调用身份（`crctl status CR-2026-075`，入口/子命令/目标无其它参数，且逐次调用的 `entryResolved` 必须归一到 `execution_context.resources` 登记 `tools` worktree 内的 `skills/shared/crctl/scripts/crctl.mjs`，同名异源即红）/首调缺根/恰一处 `--workspace` 补参差异/同 run 调用计数 = 2、纠正 = 1、无第三次调用、停止结果非空、第二次失败落回原异常路径。
  - `cmd-06`（tools，`.`，`caller-contract.test.mjs` + `contract-scan.test.mjs` + `check-skill-matrix.test.mjs` + `check-agents-contract.test.mjs` + `lint-prompts.test.mjs` + `pipeline-structure.test.mjs` 六文件合并运行）→ 调用方合同/登记一致性与 Pipeline 模板结构。
  - `cmd-07`（tools，cwd=`skills/shared/engineering-docs/scripts`，plan §6.2 原样：executable=`node`、args=`["node_modules/vitest/vitest.mjs","run","src/__tests__/generators.test.ts","src/__tests__/validators.test.ts"]`、timeout=600）→ 工程文档侧北京时间。真实运行范围 = 本 CR 声明改动的两个测试文件（plan 0.7 起 `cmd-07` 观测面由该包 vitest 全量收窄为该定向文件集，R12 记录被排除的 `chain.test.ts` 2 例 trunk 自带失败），**不声称该 TS 包全量绿，更不声称 tools 仓全量**。
  - `cmd-08`（multica，`server`，`go test ./internal/daemon/ -count=1 -v -run "…"`）→ daemon 绑定解析与发布。
  - `cmd-09`（multica，`.`，`delegation-contract.test.mjs`）→ 合同与维护副本一致性。
  - `cmd-10`（multica，`.`，内联只读脚本）→ 部署副本收敛、imported Skills 取用路径、四份 CR Agent 线上 instructions 与部署副本逐字比对。
  - `cmd-11`（tools，`.`，内联只读脚本）→ 以本 CR 声明发布文件集为期望（30 项：crctl 12、engineering-docs 6、其余 12 个各 SKILL.md），先逐个断言线上存在再逐文件 LF 全等比对（含新增两个 `lib/`、新增两个 crctl 测试、engineering-docs 的两个 in-scope TS 测试与 `gate-registry.json`），缺文件即红；仅本 CR 未声明改动的既有漂移单列（R8）；并比对规划/竞品两个业务调用方 Agent 线上 instructions 与仓库目标。
  - `cmd-12`（tools，`.`，`node skills/shared/crctl/scripts/test/suite-gate.mjs --run`）→ SDD §5.2/SDD-CLOSE-09 批准的聚合门禁：逐文件加载、磁盘集合 ≡ manifest 文件集、每文件用例数 ≥ 基线。
- 记录口径（CR-2026-073 FR-6/FR-8）：每个 `cmd-NN` 写明真实运行范围（单文件 / 单包定向名集 / 单包定向文件集 / 单目录）；范围小于全仓的命令**不得**在任何产物中表述为「全量通过」；不使用 `go test ./...`、`make test` 等全仓命令，不新增 plan 未列的命令行。
- 文档面：`test-report` 由 `owners.test` 责任执行（`write-test-report` Skill），其输入是本 TASK 归档的真实运行结果；本 TASK 不代替 test-report、不写 pass/fail 结论，只提供原样结果与范围说明。
- 未覆盖风险至少逐条记录：R10（multica `./internal/daemon/` 包内 `TestRegisterTaskReposAllowsProjectOnlyURL` 在本机 Windows 因临时仓路径超 MAX_PATH 失败，与本 CR 无关，`cmd-08` 使用定向 `-run` 名集故声明面不覆盖该用例）、R11 的复跑结论（`cmd-09` 收敛后应转绿；若仍红，逐字记录失败项）、R12 的复跑结论（`cmd-07` 已按 plan §6.2 收窄为本 CR 声明改动的两个测试文件；被排除的 `chain.test.ts` 2 例在 `061a12f` 基线上同样红，逐字记录其原文与本 CR 零改动判据，`chainCheck` 缺陷本体另开独立 CR 跟踪，**不在本 CR 任何产物中表述为已处理**）、§5.2 中不属本 CR `cmd-*` 机器断言的边界（B4 保留项人工检查边界；B1/B3 的调用方一次本地纠正已由 `cmd-05` 消费的**实际调用方节点原始记录**覆盖，不再列为未覆盖）、FR-15/AC-B14 平台侧同步前置的复跑结论（见 `effective-version-rerun.md`；未完成时报告缺失前置，不标 `pending-deploy` 充作通过）。

## 验收条件

1. 在 tools CR worktree 根按顺序执行 `cmd-01`～`cmd-04`、`cmd-06`～`cmd-07` 与 `cmd-11`/`cmd-12`，在 knowledge-base CR worktree 根执行 `cmd-05`（cwd=`.`），在 multica CR worktree 根（`cmd-08` 的 cwd 为 `server`）执行 `cmd-08`～`cmd-10`；十二条命令的 executable / args / cwd / timeout 与 plan §6.2 表逐字一致，全部返回可判定结果（全绿为预期；任一红则如实记录原始输出与失败项，不在本 TASK 内修实现）。
2. `test-evidence/` 归档完整：十二条命令各有一份原始输出与命令记录；每份记录含 cwd、退出码、真实运行范围说明；`cmd-05` 附实际调用方节点原始记录（`caller-replay/{A,B}.node-record.json`）与索引 `records.json` 的归因字段、`input.*`（含 `execution_context.resources` 的登记工具根、短提示原文 `input.shortPrompt` 与五项保留项逐字片段）/`invocations`（含逐次调用的 `entryResolved`）/`routing` 与原始记录逐字段一致性核对结果、受控调用身份（按实际解析来源归一到声明工具入口）与补参差异、断言结果汇总；`cmd-08` 附 `-v` 的 `--- PASS` 行摘要与九个名集分支命中情况；`cmd-10` 附 imported Skills 取用路径列表与四份 CR Agent 的 in-sync/不一致比对结果及两侧 `sha256`；`cmd-11` 附本 CR 声明发布集（30 项）的逐个存在性 + LF 比对结果与 `sha256`（含 crctl 侧新增两个 `lib/` 与两个测试、engineering-docs 侧两个 in-scope TS 测试、`gate-registry.json`）、`out-of-scope-drift` 单列清单、以及规划/竞品两个业务调用方 Agent 的比对结果；`cmd-12` 附逐文件顶层用例数与 `gate-registry.json#manifest` 核对结论。
3. `uncovered-risks.md` 覆盖 R10、R11、R12 与 §5.2 中非 `cmd-*` 的边界，并逐条写明「观测面 < 声称面」的边界；B1/B3 已由 `cmd-05` 消费的实际调用方节点原始记录（`{A,B}.node-record.json`）覆盖（不列为未覆盖）；`cmd-12` 的范围只写 tools `skills/shared/crctl/scripts/test/` 测试文件集合，不把定向运行或该集合表述为多仓全量。
4. `effective-version-rerun.md` 与 TASK-09 台账口径一致：`cmd-09`/`cmd-10`/`cmd-11` 全绿时记「实际生效版本一致（覆盖规划/竞品调用方）」；任一红时逐条记录目标与两侧 sha256 并报告缺失前置，不标 `pending-deploy` 充作通过、不表述为已生效。
5. 文件集检查经受控入口（argv 固定）：KB worktree 根执行 `node <tools-worktree>/skills/shared/crctl/scripts/crctl.mjs git status --porcelain --cwd <knowledge-base-worktree> --workspace <knowledge-base-worktree>`，断言新增文件仅在 `change-requests/CR-2026-075/test-evidence/` 下（外加 `tasks/_index.yml` 的 `crctl task done` 受控更新）；实现仓（tools、multica）worktree 的 `git status --porcelain` 为空（本 TASK 零实现改动）。

## 完成标志

- `cmd-01`～`cmd-12` 全部按原样执行且有原始输出归档；任何红项如实记录、不隐藏、不以范围缩小冒充绿。
- `uncovered-risks.md`、`effective-version-rerun.md` 落盘；`test-evidence/` 可供 `write-test-report` 直接消费。
- 实现仓零改动（tools/multica worktree clean）；KB 侧仅新增 `test-evidence/` 文件与本 TASK 的 `tasks/_index.yml` done 登记。
- 产物已落盘并提交；不做 merge / 审批 / 回写动作（Pipeline 控制步骤不在 TASK 内）。

## 接口契约

**消费**（逐字对齐 SDD 与目标仓现状）：

- plan §6.2 证据命令表：`cmd-01`～`cmd-12` 的 `repo`/`cwd`/`executable`/`args`/`timeout` 五列是唯一事实源，本 TASK 不另写第二套命令形态。
- 各前置 TASK 的产物：TASK-01 的 A 段 CLI 用例与 `cmd-01`；TASK-02 的 daemon 用例与 `cmd-08`；TASK-03 的原语向量与 `cmd-04`；TASK-04/05 的业务入口用例与 `cmd-02`/`cmd-03`、`gate-registry.json` 登记与 `cmd-12`（含跨消费者联合向量 B18-a 的复跑核对）；TASK-06 的 validate 向量；TASK-07 的 vitest 向量与 `cmd-07`；TASK-08 的 `cmd-05`（实际调用方节点原始记录 `{A,B}.node-record.json` + 索引 `records.json`）/`cmd-06`（六文件扫描）；TASK-09 的 `cmd-09`/`cmd-10`/`cmd-11` 与生效版本台账。
- `multica` CLI 只读查询（`skill list`/`agent list`）与三仓 CR worktree（Pipeline `resources[].worktreePath`、`classification=healthy`、`dirty=false`）。

**产出**：

- `test-evidence/` 证据集（十二条命令的原始输出 + 命令记录 + `uncovered-risks.md` + `effective-version-rerun.md`）。
- 供下游消费的稳定引用：`write-test-report` 的机器区与 traceability 引用同一份 `test-evidence/`（不复制、不改写结果）；`review-code` 的证据核对引用同一份归档；FR-15/AC-B14 的复跑以同一 `cmd-10`/`cmd-11` 为判据，不一致时报告缺失前置而非「已生效」。

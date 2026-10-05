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

在全部前置 TASK 完成后，按 plan §6.2 证据命令表原样复跑 `cmd-01`～`cmd-11`，把真实运行结果（命令、cwd、退出码、关键输出、真实运行范围）归档到 `change-requests/CR-2026-075/test-evidence/`，并汇总未覆盖风险与生效版本比对的复跑结论（FR-16；SDD §5.2/§5.3）。本 TASK 只做回归与证据归档，**不含任何实现动作**，也不包含 merge / 审批 / 回写等 Pipeline 控制步骤。

## 涉及文件 / 模块

- `change-requests/CR-2026-075/test-evidence/`（KB 仓）— 证据归档：
  - `cmd-01`～`cmd-11` 各自的原始输出与命令记录（含 cwd、退出码、用例计数 / `--- PASS` 行摘要）；
  - `uncovered-risks.md` — 未覆盖风险清单（R10、R11、R12、R13、**plan FU-1** 与 §5.2 中未由 `cmd-*` 覆盖的向量）；
  - `effective-version-rerun.md` — FR-15/AC-B14 的复跑结论：`cmd-08`/`cmd-09`/`cmd-10` 的比对结果与 TASK-09 台账一致时记「实际生效版本一致（覆盖规划/竞品调用方）」；仍不一致则逐条记录目标与两侧 sha256 并报缺失前置（不标 `pending-deploy` 充作通过）。
- 不修改实现仓代码、不改 `rules.json`、不改受控账本（`_index.yml` 仅由 `crctl task done` 更新）。

## 实现要点

- 逐条按 plan §6.2 的行原样执行（executable / args / cwd / timeout 不改写、不合并、不替换）：
  - `cmd-01`（tools，`.`，`node --test skills/shared/crctl/scripts/test/crctl.test.mjs`）→ A 段 CLI 归一/失败关闭 + validate 维度层 + 业务入口域用例；并承载 FR-04 的 CLI 侧边界向量（M1 真缺参归一成功、M2 显式传入不可用 `--workspace` 不归一并报 `WORKSPACE_REQUIRED`、M3 无绑定声明缺根同码、M4 显式异根 `WORKSPACE_CONTEXT_MISMATCH` 且绑定不可被覆盖、`BAD_ARGS` 与空串/裸旗标不进本地纠正集合、第二次失败不自动重试）。
  - `cmd-02`/`cmd-03`（tools，`.`，新增单文件 `planning-entry.test.mjs`/`competitive-report.test.mjs`）→ 两个业务入口与 B15-a/B15-b/B15-c/B18-a。
  - `cmd-04`（tools，`.`，`durable-tx.test.mjs`）→ 原语 `expect` 锁内比对与 `sampleCommitState` 锁内取样（B17-a/B17-b、B18-b/B18-c/B18-d）。
  - `cmd-05`（tools，`.`，`caller-contract.test.mjs` + `contract-scan.test.mjs` + `check-skill-matrix.test.mjs` + `check-agents-contract.test.mjs` + `lint-prompts.test.mjs` + `pipeline-structure.test.mjs` 六文件合并运行）→ 调用方合同与命令示例、FR-04 调用方纠正约定与六条「不构成授权来源」负面清单的文本断言、合同/矩阵/Agent 登记一致性与 Pipeline 模板受控节点结构。
  - `cmd-06`（tools，cwd=`skills/shared/engineering-docs/scripts`，plan §6.2 原样：executable=`node`、args=`["node_modules/vitest/vitest.mjs","run","src/__tests__/generators.test.ts","src/__tests__/validators.test.ts"]`、timeout=600）→ 工程文档侧北京时间。真实运行范围 = 本 CR 声明改动的两个测试文件（plan 0.7 起该证据 ID 的观测面由该包 vitest 全量收窄为该定向文件集，R12 记录被排除的 `chain.test.ts` 2 例 trunk 自带失败），**不声称该 TS 包全量绿，更不声称 tools 仓全量**。
  - `cmd-07`（multica，`server`，`go test ./internal/daemon/ -count=1 -v -run "…"`）→ daemon 绑定解析与发布。
  - `cmd-08`（multica，`.`，`delegation-contract.test.mjs`）→ 合同与维护副本一致性。
  - `cmd-09`（multica，`.`，内联只读脚本）→ 部署副本收敛、imported Skills 取用路径、四份 CR Agent 线上 instructions 与部署副本逐字比对。
  - `cmd-10`（tools，`.`，内联只读脚本）→ 以本 CR 声明发布文件集为期望（30 项：crctl 12、engineering-docs 6、其余 12 个各 SKILL.md），先逐个断言线上存在再逐文件 LF 全等比对（含新增两个 `lib/`、新增两个 crctl 测试、engineering-docs 的两个 in-scope TS 测试与 `gate-registry.json`），缺文件即红；仅本 CR 未声明改动的既有漂移单列（R8）；并比对规划/竞品两个业务调用方 Agent 线上 instructions 与仓库目标。
  - `cmd-11`（tools，`.`，`node skills/shared/crctl/scripts/test/suite-gate.mjs --run`）→ SDD §5.2/SDD-CLOSE-09 批准的聚合门禁：逐文件加载、磁盘集合 ≡ manifest 文件集、每文件用例数 ≥ 基线。
- 记录口径（CR-2026-073 FR-6/FR-8）：每个 `cmd-NN` 写明真实运行范围（单文件 / 单包定向名集 / 单包定向文件集 / 单目录）；范围小于全仓的命令**不得**在任何产物中表述为「全量通过」；不使用 `go test ./...`、`make test` 等全仓命令，不新增 plan 未列的命令行。
- 文档面：`test-report` 由 `owners.test` 责任执行（`write-test-report` Skill），其输入是本 TASK 归档的真实运行结果；本 TASK 不代替 test-report、不写 pass/fail 结论，只提供原样结果与范围说明。
- 未覆盖风险至少逐条记录：R10（multica `./internal/daemon/` 包内 `TestRegisterTaskReposAllowsProjectOnlyURL` 在本机 Windows 因临时仓路径超 MAX_PATH 失败，与本 CR 无关，`cmd-07` 使用定向 `-run` 名集故声明面不覆盖该用例）、R11 的复跑结论（`cmd-08` 收敛后应转绿；若仍红，逐字记录失败项）、R12 的复跑结论（`cmd-06` 已按 plan §6.2 收窄为本 CR 声明改动的两个测试文件；被排除的 `chain.test.ts` 2 例在 `061a12f` 基线上同样红，逐字记录其原文与本 CR 零改动判据，`chainCheck` 缺陷本体另开独立 CR 跟踪，**不在本 CR 任何产物中表述为已处理**）、R13 的复跑结论（FR-04 的机器语义由 `bindTaskWorkspace`「显式不可用不归一」既有分支产生，`cmd-01` 的 M2 入口边界用例钉住其机器语义；FR-04 机器面零改动、`scope_in` 未授权修改该分支——若复跑发现该分支漂移（空串/纯空白也被归一，则 M2 消失、有效绑定下 `WORKSPACE_REQUIRED` 不可达），逐字记录漂移事实并回到 SDD 正式修订，**不得**在本 CR 内顺手改该分支）、**plan FU-1（FR-04 的节点回放消费面：实际受控调用方节点的 A/B 两变体平台原始记录与索引）已整体移出本 CR 验收**——本 CR 内 FR-04 的观测面只有 `cmd-01` 的 CLI 侧边界向量与 `cmd-05` 的调用方静态合同面两段，**观测面 < 声称面**，须在 `uncovered-risks.md` 单列 FU-1 并写明其依赖（完整 Pipeline Runner / CR-H）与不可达性依据（plan §4 末），并逐字声明本 CR 未生成 `test-evidence/caller-replay/`、未以手工 CLI 调用 / 平台 run 导出面 / 旧环境快照 / `replay.mode` 标签 / 逐次 `env` 日志冒充回放证据、**未表述为「节点回放已通过」**；R14 的防误读边界同此）、以及 §5.2 中不属本 CR `cmd-*` 机器断言的边界（B4 保留项人工检查边界；S2/M3 无绑定声明在本 CR 节点内不产生，只作字面来源登记，其机器行为由 A6 向量 `cmd-01` 覆盖）、FR-15/AC-B14 平台侧同步前置的复跑结论（见 `effective-version-rerun.md`；未完成时报告缺失前置，不标 `pending-deploy` 充作通过）。

## 验收条件

1. 在 tools CR worktree 根按顺序执行 `cmd-01`～`cmd-06`、`cmd-10`、`cmd-11`，在 multica CR worktree 根（`cmd-07` 的 cwd 为 `server`）执行 `cmd-07`～`cmd-09`；十一条命令的 executable / args / cwd / timeout 与 plan §6.2 表逐字一致，全部返回可判定结果（全绿为预期；任一红则如实记录原始输出与失败项，不在本 TASK 内修实现）。
2. `test-evidence/` 归档完整：十一条命令各有一份原始输出与命令记录；每份记录含 cwd、退出码、真实运行范围说明；`cmd-07` 附 `-v` 的 `--- PASS` 行摘要与九个名集分支命中情况；`cmd-09` 附 imported Skills 取用路径列表与四份 CR Agent 的 in-sync/不一致比对结果及两侧 `sha256`；`cmd-10` 附本 CR 声明发布集（30 项）的逐个存在性 + LF 比对结果与 `sha256`（含 crctl 侧新增两个 `lib/` 与两个测试、engineering-docs 侧两个 in-scope TS 测试、`gate-registry.json`）、`out-of-scope-drift` 单列清单、以及规划/竞品两个业务调用方 Agent 的比对结果；`cmd-11` 附逐文件顶层用例数与 `gate-registry.json#manifest` 核对结论。`test-evidence/caller-replay/` **不存在**（本 CR 不生成任何节点回放记录，见 plan FU-1）。
3. `uncovered-risks.md` 覆盖 R10、R11、R12、R13、**plan FU-1** 与 §5.2 中非 `cmd-*` 的边界，并逐条写明「观测面 < 声称面」的边界；FU-1 行必须写明：FR-04 本 CR 观测面 = `cmd-01` 的 CLI 侧边界向量 + `cmd-05` 的调用方静态合同面，节点回放消费面未取证、**不得被读作「已验证」**，其恢复依赖完整 Pipeline Runner（CR-H）；S2/M3 只作字面来源登记并单列其覆盖来源为 A6 向量（`cmd-01`），不得表述为本 CR 节点内已回放；`cmd-11` 的范围只写 tools `skills/shared/crctl/scripts/test/` 测试文件集合，不把定向运行或该集合表述为多仓全量。
4. `effective-version-rerun.md` 与 TASK-09 台账口径一致：`cmd-08`/`cmd-09`/`cmd-10` 全绿时记「实际生效版本一致（覆盖规划/竞品调用方）」；任一红时逐条记录目标与两侧 sha256 并报告缺失前置，不标 `pending-deploy` 充作通过、不表述为已生效。
5. 文件集检查经受控入口（argv 固定）：KB worktree 根执行 `node <tools-worktree>/skills/shared/crctl/scripts/crctl.mjs git status --porcelain --cwd <knowledge-base-worktree> --workspace <knowledge-base-worktree>`，断言新增文件仅在 `change-requests/CR-2026-075/test-evidence/` 下（外加 `tasks/_index.yml` 的 `crctl task done` 受控更新）；实现仓（tools、multica）worktree 的 `git status --porcelain` 为空（本 TASK 零实现改动）。

## 完成标志

- `cmd-01`～`cmd-11` 全部按原样执行且有原始输出归档；任何红项如实记录、不隐藏、不以范围缩小冒充绿。
- `uncovered-risks.md` 已把 plan FU-1 单列为已知未覆盖项（观测面 < 声称面），本 CR 未生成 `test-evidence/caller-replay/`、未以任何替代物冒充节点回放；`effective-version-rerun.md` 落盘；`test-evidence/` 可供 `write-test-report` 直接消费。
- 实现仓零改动（tools/multica worktree clean）；KB 侧仅新增 `test-evidence/` 文件与本 TASK 的 `tasks/_index.yml` done 登记。
- 产物已落盘并提交；不做 merge / 审批 / 回写动作（Pipeline 控制步骤不在 TASK 内）。

## 接口契约

**消费**（逐字对齐 SDD 与目标仓现状）：

- plan §6.2 证据命令表：`cmd-01`～`cmd-11` 的 `repo`/`cwd`/`executable`/`args`/`timeout` 五列是唯一事实源，本 TASK 不另写第二套命令形态。
- 各前置 TASK 的产物：TASK-01 的 A 段 CLI 用例与 `cmd-01`；TASK-02 的 daemon 用例与 `cmd-07`；TASK-03 的原语向量与 `cmd-04`；TASK-04/05 的业务入口用例与 `cmd-02`/`cmd-03`、`gate-registry.json` 登记与 `cmd-11`（含跨消费者联合向量 B18-a 的复跑核对）；TASK-06 的 validate 向量；TASK-07 的 vitest 向量与 `cmd-06`；TASK-08 的 `cmd-05`（六文件扫描，含 FR-04 调用方纠正约定与六条「不构成授权来源」负面清单的文本断言）；TASK-09 的 `cmd-08`/`cmd-09`/`cmd-10` 与生效版本台账。
- plan §4 末 follow_up FU-1 登记（本 TASK 的未覆盖风险输入，**非本 CR 证据**）：FR-04 节点回放消费面的范围、依赖与不可达性依据。
- `multica` CLI 只读查询（`skill list`/`agent list`）与三仓 CR worktree（Pipeline `resources[].worktreePath`、`classification=healthy`、`dirty=false`）。

**产出**：

- `test-evidence/` 证据集（十一条命令的原始输出 + 命令记录 + `uncovered-risks.md` + `effective-version-rerun.md`）。
- 供下游消费的稳定引用：`write-test-report` 的机器区与 traceability 引用同一份 `test-evidence/`（不复制、不改写结果）；`review-code` 的证据核对引用同一份归档；FR-15/AC-B14 的复跑以同一 `cmd-09`/`cmd-10` 为判据，不一致时报告缺失前置而非「已生效」；FU-1 的未覆盖事实在本 CR 产物中一律表述为「未取证」，不得被下游读作「已验证」。

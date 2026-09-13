---
id: CR-2026-065-TASK-04
type: TASK
cr-ref: CR-2026-065
plan-ref: "change-requests/CR-2026-065/plan.md"
sdd-ref: "change-requests/CR-2026-065/sdd.md"
target-version: 0.38
title: 收敛决定与漂移负控：--test-concurrency 有界实测定常量 + 三类注入证据 + manifest.cases 终值刷新 + 范围收口
slug: concurrency-decision-drift-negative-controls
status: pending
estimate: 16h
depends-on: [CR-2026-065-TASK-01, CR-2026-065-TASK-02, CR-2026-065-TASK-03]
created: 2026-09-13T05:05:00+08:00
---

# CR-2026-065-TASK-04 收敛决定、漂移负控与范围收口（G4，FR-12、FR-13、FR-15、FR-16）

## 0. 阻断关闭声明（本条 run replay；2026-09-13）

**本卡不再被阻断。** 上一版 §0 登记的传递性阻断（`plan.md` §0.0 的 SDD §3.4/§4.2 per-file 归属前提在目标运行时不存在 ⇒ TASK-03 的 per-file 核对面不可判、`cmd-01` 永红）已由 **B-4 修订**（`fd48041c`）关闭：归属改由**逐文件 spawn** 给出、文件集合改对**磁盘目录**核对、每文件用例数由报告新增的 `files[]` 逐项可核，并经独立技术评审（`review-annotations/sdd.yml`：pass / `blockers=[]` / `subject-sha256 = ecc1f902…`）与人工审批（`approval.yml#tech-design`，`2026-09-13T13:55:02+08:00`）双重绑定（沿革见 `plan.md` §0.0）。

- **因此本卡 §3.1 / §3.3 / §3.4 的验收面（`cmd-01` exit 0、`cmd-04`、`cmd-05`）现全部可达，按原门槛执行**（不降级、不豁免：三类注入、`exceptions=[]` 交付态与 `manifest.cases` 终值刷新一律照原要求完成）。
- **依赖链不变**：本卡依赖 TASK-03 补齐逐文件 spawn / 单文件解析 / `files[]` / `observer` / `--report <ndjson>`（`plan.md` §9.1「待补齐」）。
- **范围外（不改）**：`sdd.md`（一个字节都不改）、三类注入产物不得留在交付分支、CR-2026-064 与包 B。

## 1. 任务描述

**目标**：把「门禁绿」做成**有约束力且可复现**的：① 用有界实测协议定掉 `--test-concurrency`（TDEC-4）；② 对三类断言面各做一次**真实漂移注入** → 全量命令变红 → 还原 → 复绿，并把证据落盘（FR-13/AC-11）；③ 在全部新用例落地后刷新 `manifest.cases` 终值；④ 用 diff 白名单收口范围（FR-15/AC-13）。

**背景**：现状唯一有「不收敛」观测的配置是 `--test-concurrency=2`（本机 30+ min、父进程空闲子进程停滞），而既有全量实测 894.8 s 未标注并发口径——**禁止**把「已知不收敛观测」的配置不经实测就写进门禁常量（R-03）。

**输入条件**：TASK-01/02/03 全部完成（`depends-on` 强约束）——三条断言面 + 门禁包装器都已落地，注入才能在本 CR 内看到「当场红」。

**范围边界（`zero_diff`）**：`dir-graph.yaml` / `pipeline-templates/*` / 所有 `SKILL.md` / `lib/yaml-subset.mjs` / `lib/durable-tx.mjs` / `lib/workspace-transactions.mjs` / `rules.json` / `crctl.mjs` dispatch 与既有子命令签名零 diff。三类注入是**临时真实漂移**，**注入物不得留在交付分支**。本卡不改任何产品语义、不改 SDD、不触碰 CR-2026-064 与包 B。

## 2. 涉及文件 / 模块

| 文件 | 动作 | 说明 |
|---|---|---|
| `tools`：`skills/shared/crctl/scripts/test/gate-registry.json` | 改 | `manifest.cases` 终值刷新（受控写入 = 人工提交；差异在 diff 中留痕） |
| `tools`：`skills/shared/crctl/scripts/test/suite-gate.mjs` | 改（如需） | 并发常量（`CONCURRENCY`）终值 = 实测选中者；未选中者观测保留在汇总中 |
| KB：`change-requests/CR-2026-065/test-evidence/concurrency/default-run1.json`、`default-run2.json`、`conc2-run1.json`、`conc2-run2.json`、`conc1-run1.json`、`conc1-run2.json` | 新增 | **三候选**（默认 / 2 / 1，TDEC-4）各 ≥2 次**连续**整跑记录（6 份） |
| KB：`change-requests/CR-2026-065/test-evidence/drift/NC-1-inject.json`、`NC-1-restore.json`、`NC-2-inject.json`、`NC-2-restore.json`、`NC-3-inject.json`、`NC-3-restore.json` | 新增 | 三类注入的「注入红 / 还原绿」各 1 份 |
| KB：`change-requests/CR-2026-065/test-evidence/NC-summary.md` | 新增 | 三类注入的「命令 / 耗时 / 是否停滞 / 结论」表 + 逐条还原结论 |

## 3. 实现要点

### 3.1 收敛协议（FR-12 / TDEC-4）

- 候选 = **3 个**：① `runner` 默认并发的等价物 = `max(1, availableParallelism() - 1)`；② `2`；③ `1`；各 ≥2 次**连续**整跑；记录 `command`（含实际池值与展开规模）/ `duration_ms` / `converged` / `failures`；
- 选中者写入 `suite-gate.mjs` 的**唯一常量**（命令单一来源，FR-12.3）；未选中的观测保留在汇总中（**证据可复现，不只写结论**）；
- 硬约束：选中配置必须满足「整跑 ≤ 1200 s」（`cmd-01` 的 `--max-runtime-ms`）；不满足则按 R-01/R-02 处理（调常量，**不得**删命令或放宽 AC）；
- 若候选在 1200 s 内不收敛，不判绿：`converged=false` + `SUITE_NONCONVERGENCE` 即落证据，并据以改选另一候选；
- 证据文件名固定：`concurrency/{default-run1,default-run2,conc2-run1,conc2-run2,conc1-run1,conc1-run2}.json`（`cmd-05` 按此清单核对）。

### 3.2 三类注入（FR-13 / §4.6，逐类「注入 → 全量 `suite-gate --run` → 还原 → 全量 `--run`」）

| # | 注入动作（真实漂移） | 预期红点 | 还原 |
|---|---|---|---|
| N-1 | 向 `tools/dir-graph.yaml#state_machine.transitions` 增加一条真实转换（如 `from: developing, to: developing, trigger: "crctl-test-injection"`） | `crctl.test.mjs` 的 `TASK-06 ⑤` 用例（集合/计数不等） | 删除该行；`crctl git status --short` 确认该文件干净 |
| N-2 | 向 `skills/requirement/write-requirement-prd/SKILL.md` 注入一个禁用词（如 `validate-doc`）或删除「七个章节」要素 | `crctl.test.mjs` 的 `CR-2026-042 静态合同：已知 Skill 越界文本零命中` 用例 | `crctl git checkout -- <path>` 还原并核验干净 |
| N-3 | 在 `lib/outbox-contract.mjs#buildOutboxEvent` 增加一个未登记字段（如 `observed_at`），或向 `OUTBOX_VOLATILE_PAYLOAD_KEYS` 增加未登记键 | `trace-outbox.test.mjs` 的 `CR-2026-065` 契约用例（字段分类 / 投影闭合不变性） | 同 N-2 |

- 每轮注入/还原各跑一次**全量命令**（`suite-gate --run`，与 `cmd-01` 同命令、同 `--max-runtime-ms`）；共 6 次整跑（3 注入 + 3 还原），**不削减任何一次**；
- 证据 JSON 固定字段（S-2 口径；**上一版缺 `verdict`，与 `cmd-05` 读取面不一致，已补齐**）：`command` / `duration_ms` / `converged` / `exit_code` / `failures[]` / **`verdict`（`"pass"` | `"block"`）** / `injection`（diff 摘要）/ `restore`（还原后结论）；
- 证据 JSON 直接落 `--run` 的 stdout 报告（15 字段），**不得手写**；缺字段即 `cmd-05` 红；
- 每轮还原后以 `crctl git status --short` 留痕；注入物**不得**留在交付分支（由 `cmd-04` 的 diff 白名单二次兜底）。

### 3.3 `manifest.cases` 终值刷新（逐文件）

- 在 TASK-01/02 的全部新用例落地后，用一次全量 `--run` 的报告取**每文件实际顶层用例数**（`files[].cases`，**逐文件、不聚合**），刷新 `gate-registry.json#manifest.cases` 终值（受控写入 = 人工提交；与 TASK-01 初值的差异在 diff 中留痕）；
- 终值必须 ≥ 各自初值（只升不降即与 `SUITE_MANIFEST_CASE_DROP` 语义一致）；
- **不得**用全局总计数或「多文件合并报告」充当 per-file 基线（修订版 SDD §2.3：计数单位 = 该文件**独立子进程** TAP 的顶层结果数）。

### 3.4 范围收口（FR-15 / AC-13、FR-16 / AC-14）

- `cmd-04` 的 diff 白名单为机器判据：只允许 `skills/shared/crctl/scripts/test/**`、`skills/shared/crctl/scripts/lib/outbox-contract.mjs`、`skills/shared/crctl/scripts/crctl.mjs`、`.github/workflows/crctl-ci.yml`，其余越界即红；
- `cmd-01` 复核 FR-16：21 文件全绿、`skipped_file_level=0`、`failures=[]`，并给出与 894.8 s 同口径的耗时对比。

### 3.5 纪律

- 所有读文本/解析先 `\r\n → \n`，解析失败硬失败；证据文件写 KB 仓（与 `test-evidence/cmd-NN.log` 同址），随 CR 提交；
- 不新增账本写路径，不写 `_backlog.yml` / `cr.md` / `approval.yml` / `tasks/_index.yml`（`task done` 除外）。

## 4. 验收条件（可执行）

1. `cmd-05`（§6.2，证据形态核对）→ **exit 0**：6 个 `drift/NC-{1,2,3}-{inject,restore}.json` 齐备且 `verdict` / `converged` / `failures[]` 形态正确（注入 `verdict=block` 且失败集合非空；还原 `verdict=pass` 且失败集合为空；两者 `converged=true`）+ **6 个** `concurrency/{default-run1,default-run2,conc2-run1,conc2-run2,conc1-run1,conc1-run2}.json` 齐备 + `NC-summary.md` 在册（基线现状 exit 1 / 44 ms、17 项缺失，见 `plan.md` §6.3）。
2. `cmd-01`（§6.2，最终池值）：`node skills/shared/crctl/scripts/test/suite-gate.mjs --run --max-runtime-ms 1200000` → **exit 0**、其 stdout JSON 内 `failures=[]`、`files_executed=21`、`files[]` 恰 21 条且全为 `state=ok`、`cases_executed>0`、`skipped_file_level=0`、`converged=true`、`observer` 非空，且 `command` 字段与 `suite-gate.mjs` 常量一致。
3. `cmd-04`（§6.2）→ **exit 0**：`manifest.cases` 终值为正整数且 ≥ 初值；diff 路径全部落在白名单内（**注入物不在交付 diff**）。
4. 还原留痕：三次注入后 `crctl git status --short` 均为空（tools worktree clean），且 `crctl git diff --name-only dddd0ad63fb79bd7608314b4553f30e8ce7b7289` 不含 `dir-graph.yaml` 与 `SKILL.md`。

## 5. 完成标志

- **前置（已解除）**：B-4 修订版 SDD 已落地且经评审批审双重绑定（见 §0）；TASK-03 补齐逐文件 spawn / 单文件解析 / `files[]` / `observer` / `--report <ndjson>` 后，本卡按原门槛执行。
- 收敛决定完成：**3 候选各 ≥2 次连续**整跑证据齐备（6 份），选中者写入唯一常量，`cmd-01` 在该常量下 exit 0 且 `converged=true`；
- 三类注入「注入红 / 还原绿」证据齐备，注入物不在交付分支，`NC-summary.md` 完整；
- `manifest.cases` 终值刷新并随 CR 提交；`cmd-01` / `cmd-04` / `cmd-05` 三条命令全绿；
- 任务账本登记：`crctl task done CR-2026-065 --task CR-2026-065-TASK-04`（1-3 号任务同样已 `done`，不积压到回写期）。

## 6. 接口契约

**消费（上游 TASK 产出，逐字）**

- TASK-03：`skills/shared/crctl/scripts/test/suite-gate.mjs` CLI（修订版）—— `--run [--report-out <ndjson>] [--json-out <json>] [--max-runtime-ms <n>] [--cwd <tools-root>]` 与 `--report <ndjson> [--json-out <json>]`；报告模型 `crctl-suite-gate-report/v1` **15 字段**（`schema` / `command` / `observer` / `duration_ms` / `converged` / `exit_code` / `files_executed` / `cases_executed` / `skipped_file_level` / `files[]` / `failures[]` / `checks[]` / `registry` / `platform` / `verdict`）；`files[]` 项 = `{ file, state, exit_code, cases, failures[], skipped, todo, duration_ms }`；并发常量 `CONCURRENCY`；
- TASK-01：`test/gate-registry.json#manifest.cases`（初值）与 `#stateMachine.*`（登记口径不因本卡变化）、`test/assertion-sources.mjs#deriveStateMachine(toolsRoot)`；
- TASK-02：`lib/outbox-contract.mjs` 五导出（N-3 的注入面）。

**产出（`write-test-report` 节点与 `review-code` 消费）**

- `gate-registry.json#manifest.cases` 终值（受控写入；**逐文件**口径）；
- `suite-gate.mjs` 的并发常量终值（若实测选中 `=1` 或 `=2`）；
- KB 证据面：`change-requests/CR-2026-065/test-evidence/concurrency/{default-run1,default-run2,conc2-run1,conc2-run2,conc1-run1,conc1-run2}.json`、`test-evidence/drift/NC-{1,2,3}-{inject,restore}.json`、`test-evidence/NC-summary.md`；字段口径与 §3.2 固定字段一致（含 `verdict`），供 `cmd-05` 形态核对与 `write-test-report` 的同口径耗时对比。

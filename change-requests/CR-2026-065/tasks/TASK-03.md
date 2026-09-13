---
id: CR-2026-065-TASK-03
type: TASK
cr-ref: CR-2026-065
plan-ref: "change-requests/CR-2026-065/plan.md"
sdd-ref: "change-requests/CR-2026-065/sdd.md"
target-version: 0.38
title: CI 真门禁：suite-gate 包装器（TAP 解析 / 清单核对 / 例外面四查 / 退出码）+ contract-scan 静态断言与解析自测 + crctl-ci.yml 步骤改造
slug: ci-suite-gate-and-exception-governance
status: pending
estimate: 20h
depends-on: [CR-2026-065-TASK-01, CR-2026-065-TASK-02]
created: 2026-09-13T05:05:00+08:00
---

# CR-2026-065-TASK-03 CI 真门禁与例外治理（G3，FR-11、FR-14、FR-17）

## 0. 阻断声明（本轮 `write-dev-tasks` replay，2026-09-13）

**本卡在已批准 SDD（`review-annotations/sdd.yml#subject-sha256 = 1e6af84f…`）下不可完成 —— 设计前提为假。** 本声明不修 SDD、不降级任何验收门槛，只登记事实与出口（完整证据见 `plan.md` §0.0）。

**事实（第一手）**：SDD §3.4 / §4.2 要求解析器以「文件名块（`# Subtest: <file>.test.mjs`）+ file 级 plan `1..N`」取得**每文件归属**。真实 21 文件全量 TAP 实测：`# Subtest:` 568 行**全部是用例名**、`# Subtest: *.test.mjs` = **0**、全文唯一 plan = 全局 `1..568`；Node 24.15.0 / 20.20.2 / 18.20.8 三版本一致；`--test-isolation=process|none`、`--test-concurrency=1`、显式文件 vs 目录发现均不产生文件名块。⇒ `files_executed` / `manifest.files` / `manifest.cases` 三项核对面**不可判** ⇒ `cmd-01` 永红 ⇒ AC-01 / AC-12 / AC-15 不可达。

**已完成且可复用的部分**（`implement-code` 已落地，留在 tools worktree 提交 `2c84241`）：`test/suite-gate.mjs` 的两形态 CLI、唯一命令来源（显式 `--test-reporter=tap` + `CONCURRENCY` 常量）、13 个 check code 与退出码规则、例外面四查、非收敛分支与 E-2 收口、13 字段报告模型、`--run` 全字段 JSON 到 stdout。**缺的只有被 §3.4 依赖的 per-file 归属面**；`crctl-ci.yml:109-111` **一字未改**（不把不可用的门禁接进 CI）。

**出口（不属于本卡）**：归属机制是 SDD §3.4 的设计选择，与 §4.2 命令形态、TDEC-1 口径、`manifest.cases` 的 per-file 语义相互绑定 ⇒ `repair-target=write-tech-design` → upstream 链（`plan.md` §9.1）。**不得**在本卡内实现未批准的替代机制（追加第二 reporter 目的地 / 逐文件 spawn / 全局口径），也不得放宽 §3.4 的硬失败语义。

**本卡 §1…§6 保持原样**：它们是 SDD 修订后 replay 本计划的输入契约，届时按修订版 SDD 重述 §3.4 与相关判据面。

## 1. 任务描述

**目标**：让 `.github/workflows/crctl-ci.yml:109-111` 的全量测试步骤成为**真门禁**——由 `test/suite-gate.mjs` 包装 `node --test`、解析 TAP、核对受控清单与例外登记面、按固定 check code 与退出码规则判定；并在 `contract-scan.test.mjs` 增补「登记面不得自证绿」的静态断言与 TAP 解析自测。

**背景**：现状 CI 步骤是裸 `node --test --test-concurrency=2 skills/shared/crctl/scripts/test/*.test.mjs`（无例外、无 skip 白名单），既看不到「哪些文件真的跑了」，也没有「失败集合 / 例外 / 到期」的判定面。**AC-01 的「exit 0 / 失败集合为空」是交付目标**：本卡交付的包装器必须有约束力——事实源漂移时给出非零退出，登记面不得成为自证绿通道。

**输入条件**：TASK-01 的 `gate-registry.json` 与 `assertion-sources.mjs`、TASK-02 的 `lib/outbox-contract.mjs` 均已落地（`depends-on` 强约束）。

**范围边界（`zero_diff`）**：`dir-graph.yaml` / `pipeline-templates/*` / 所有 `SKILL.md` / `lib/yaml-subset.mjs` / `lib/durable-tx.mjs` / `lib/workspace-transactions.mjs` / `rules.json` 零 diff；不新增 crctl 子命令或 flag（FR-17）；不新增测试文件（`*.test.mjs` 集合保持 21）、不新增第三方依赖。

## 2. 涉及文件 / 模块

| 文件（相对 `tools` 仓根） | 动作 | 说明 |
|---|---|---|
| `skills/shared/crctl/scripts/test/suite-gate.mjs` | **新增** | 全量套件门禁包装器；不匹配 `*.test.mjs`，不被 runner 采集 |
| `skills/shared/crctl/scripts/test/contract-scan.test.mjs` | 追加断言 | 受控清单 / 例外登记面 / 写入口静态断言 + `--report/--rc` 解析自测（内联 TAP 片段） |
| `.github/workflows/crctl-ci.yml` | 改 `:109-111` | 步骤 `crctl full test suite` 改为调用 `suite-gate.mjs --run` |

## 3. 实现要点

### 3.1 `suite-gate.mjs` 调用形态（逐字对齐 SDD §3.2）

```text
node skills/shared/crctl/scripts/test/suite-gate.mjs --run [--report-out <tap>] [--json-out <json>]
                                                           [--max-runtime-ms <n>] [--cwd <tools-root>]
node skills/shared/crctl/scripts/test/suite-gate.mjs --report <tap> --rc <exit-code> [--json-out <json>]
```

- `--run`：包装器**自己** spawn 全量套件（CI 与本地证据的唯一形态）；
- `--report/--rc`：只做判定、不跑套件（负控与解析自测用）；两种模式的判定必须**同源同一函数**。

### 3.2 唯一命令来源与执行

- 命令 = `node` + `--test` + **显式 `--test-reporter=tap`**（不把门禁结论交给未登记的 reporter 默认值）+ `[--test-concurrency=<常量>]`（`CONCURRENCY` 为包装器内**唯一常量**；TDEC-4 设计默认＝**去参**，终值由 TASK-04 实测决定）+ 21 个测试文件**绝对路径**（glob 由包装器自己展开，展开后必须非空，否则硬失败）；
- `spawn(cmd, { cwd: toolsRoot, shell: false })`；stdout 落 `--report-out` 指定的 TAP 文件；
- 计时：超过 `--max-runtime-ms` → 终止**本包装器自己 spawn 的 PID 树**（POSIX：`detached:true` + `process.kill(-pid,'SIGKILL')`；Windows：`taskkill /PID <child.pid> /T /F`），`converged = false`、`exit_code = null`；**不按进程名终止任何进程**。

### 3.3 报告模型（字段名固定，SDD §2.4，不得改名）

```text
schema        "crctl-suite-gate-report/v1"
command       实际执行的完整命令（含并发参数，字符串）
duration_ms   全量命令耗时（整数）
converged     进程是否自行结束（false = 触发 --max-runtime-ms 被终止，即停滞）
exit_code     被测命令退出码（被终止时为 null）
files_executed / cases_executed / skipped_file_level
failures[]    失败用例名
checks[]      [{ code, ok, detail, suppressed_by?, not_evaluated? }]
registry      { sha256, exceptions_count }
platform      { platform, node }
verdict       "pass" | "block"
```

### 3.4 TAP 解析（硬失败，禁止降级）

> **本轮阻断点（见 §0）**：本节的「文件名块 + file 级 plan」在目标运行时**不存在** —— 按字面实现，`files_executed` 恒为 ∅。本小节在修订版 SDD 定稿前**不得**以任何替代机制落地，也不得降级为全局口径。

- 以缩进栈识别 `# Subtest: <name>` 块；文件名块（`<name>` 以 `.test.mjs` 结尾）必须有 file 级 plan `1..N`，`N` = 该文件**实际执行的用例数**；块内 `not ok` 行 = 失败用例名（`# SKIP` / `# TODO` 后缀分别计入 skip / todo）；
- 无 file 级 plan、块不成对、plan 与实际行数矛盾 → 抛错（`SUITE_REPORT_UNPARSEABLE`）；**任何解析异常都不得返回「零失败」结果**（工程纪律 #1）；
- 非收敛分支：`converged=false` 时不做清单核对与失败集合核对（`files_executed=null` / `cases_executed=null` / 相关 `checks[].not_evaluated=true`），只判 `SUITE_NONCONVERGENCE` 与登记面自身错误（`EXCEPTION_*`）；`SUITE_REPORT_UNPARSEABLE` 只在「进程已自行结束（`converged=true`）而 TAP 结构仍不完整」时触发（两者不混算）；
- **E-2 收口**：非收敛分支中，**已匹配的 `kind: suite-nonconvergence` 例外视为已观测**，禁用空观测集合判 `EXCEPTION_NOT_OBSERVED`。

### 3.5 check code 与退出码（逐字取自 SDD §3.2 表，不得增删改名）

| check code | 触发条件 | 可否被例外容忍 |
|---|---|---|
| `SUITE_REGISTRY_MISSING` / `SUITE_REGISTRY_SCHEMA_INVALID` | 登记文件缺失 / schema 不符（含字段缺失、类型错误、`expires` 无时区偏移） | 否 |
| `SUITE_REPORT_UNPARSEABLE` | TAP 解析失败或结构不完整（硬失败） | 否 |
| `SUITE_FILE_LOAD_FAILURE` | 某文件整体加载/执行失败（文件级 `not ok`，无 file 级 plan） | 否 |
| `SUITE_MANIFEST_FILE_DRIFT` | 实际执行文件集合 ≠ `manifest.files` | 否 |
| `SUITE_MANIFEST_CASE_DROP` | 某文件实际用例数 < `manifest.cases` 基线 | 否 |
| `EXCEPTION_FIELD_MISSING` / `EXCEPTION_SCHEMA_INVALID` / `EXCEPTION_DUPLICATE` | 例外条目缺 id/kind/reason/owner/expires、kind 非枚举、重复 id | 否 |
| `EXCEPTION_EXPIRED` | `now >= expires`（比较基准 = 门禁运行时 UTC 瞬时） | 否 |
| `EXCEPTION_NOT_OBSERVED` | 登记的例外在本次运行中**未出现**（陈旧登记） | 否 |
| `SUITE_FAILURES_UNREGISTERED` | 观测失败集合中存在未被未到期例外覆盖的失败 | 否（容忍在**触发条件内**：未到期例外覆盖的失败不计入本项；本项一旦触发即不可抑制） |
| `SUITE_NONCONVERGENCE` | `--run` 超过 `--max-runtime-ms` 仍未结束（被终止） | **可抑制（可绿）**：仅当存在未到期、`kind: suite-nonconvergence` 且稳定标识与本项匹配的登记例外；报告仍记 `converged:false` 与 `checks[SUITE_NONCONVERGENCE]`（事实永不隐藏） |

- **退出码：0 当且仅当无任何未抑制触发**；其余 check code 一律不可容忍；
- **交付态特例**：`exceptions = []` ⇒ 退出码 0 **当且仅当**失败集合为空（逐字对齐 AC-01）；
- **stdout 禁词（J-8）**：人类摘要与 JSON 不得出现独立单词 `skipped`（含大小写）/ `# skip` / `no tests to run`（依据 `lib/workspace-transactions.mjs:3992-3998` 冻结模式表），固定字段名用 `skipped_file_level`；
- 四查（SDD §3.2）：幂等（`EXCEPTION_DUPLICATE`）/ 权限与写入边界（唯一写入口 = 人工编辑 + git commit，门禁只读、零写路径）/ 错误闭包（固定 check code + 非零退出 + 零写入）/ 副作用（登记只影响判定、不改变执行；`failures[]` 始终上报）。

### 3.6 `contract-scan.test.mjs` 追加断言

- **静态断言**：仓库内不存在对 `gate-registry.json` 的写入调用（`writeFileSync` / `appendFileSync` / `rmSync` / `renameSync` / `truncate`）；`suite-gate.mjs` 自身无写路径（不写登记面、不写 `.crctl/` 受治理账本、不写被测仓）；
- **解析自测（内联 TAP 片段，关闭 S-3）**：以 `--report/--rc` 形态跑通过：合法片段判绿；三类畸形片段（无 file 级 plan、块不成对、plan 与实际行数矛盾）各自落 `SUITE_REPORT_UNPARSEABLE` 且退出非零；
- **不新增测试文件、不新增 fixture 目录**：`*.test.mjs` 集合仍为 21，自测片段**内联**在测试代码里。

### 3.7 CI 步骤改造（唯一 diff 面）

```yaml
      - name: crctl full test suite
        shell: bash
        run: node skills/shared/crctl/scripts/test/suite-gate.mjs --run
```

（`run` 内不再出现 `--test-concurrency`：命令与并发参数的唯一来源 = 包装器内常量，满足 FR-12.3「同一口径」。）

## 4. 验收条件（可执行）

1. 解析自测（`contract-scan`，窄跑）：`node --test --test-reporter=dot --test-name-pattern "CR-2026-065" skills/shared/crctl/scripts/test/contract-scan.test.mjs` → **exit 0**（合法片段判绿 + 三个畸形片段各自 `SUITE_REPORT_UNPARSEABLE` + 静态断言通过）。
2. `cmd-01`（§6.2，tools cwd `.`）：`node skills/shared/crctl/scripts/test/suite-gate.mjs --run --max-runtime-ms 1200000` → 报告（`--json-out`）字段齐备（§3.3 全部字段），且**判定与失败集合自洽**：`failures=[]` ⇒ exit 0 / `verdict=pass`；否则非零退出。**TASK-01/02 完成后**该次 `--run` 应达成 exit 0、`failures=[]`、`files_executed=21`、`skipped_file_level=0`、`converged=true`（首次干跑单位，plan §6.3）；若默认并发在 1200 s 内不收敛，则按非收敛口径落 `converged=false` 证据、退出码红，并把常量终值决策交给 TASK-04（R-02/R-03）——**不得**把红记成绿。
3. `cmd-04`（§6.2，登记面 schema + `zero_diff` 边界 + diff 白名单）→ **exit 0**（本卡新增路径均在 `skills/shared/crctl/scripts/test/**` 与 `.github/workflows/crctl-ci.yml` 白名单内）。
4. 步骤改造自检：`crctl git diff -- .github/workflows/crctl-ci.yml` 仅 `:109-111` 三行变化；`crctl git diff --name-only dddd0ad63fb79bd7608314b4553f30e8ce7b7289 -- skills/shared/controlled-shell/rules.json dir-graph.yaml pipeline-templates` 为空。

## 5. 完成标志

- **前置（阻断解除）**：修订版 SDD（`write-tech-design` → 重新评审 → 重新人工审批）落地后 replay 本卡；在此之前本卡不得标 `done`，也不得修改 `crctl-ci.yml:109-111`。
- `suite-gate.mjs` 落地：§3.1 CLI、§3.2 唯一命令来源（显式 `--test-reporter=tap`）、§3.3 报告字段、§3.4 TAP 硬失败与非收敛口径、§3.5 check code 与退出码、J-8 禁词；
- `contract-scan.test.mjs` 静态断言 + 三类畸形 TAP 自测绿；CI 步骤改为调用包装器；
- `cmd-01` 首次 `--run` 落盘报告（字段齐备、判定与失败集合自洽；绿或按非收敛口径落红证据）；`cmd-04` exit 0；
- 峰值口径记录：`*.test.mjs` 仍 21 个、无新增依赖、无新增 crctl 子命令/flag；
- 任务账本登记：`crctl task done CR-2026-065 --task CR-2026-065-TASK-03`。

## 6. 接口契约

**消费（上游 TASK 产出，逐字；不得缩略）**

- TASK-01：`test/assertion-sources.mjs` 的 `readTextNormalized(absPath) -> string` / `deriveStateMachine(toolsRoot) -> { namedStates: string[], wildcards: Record<string, string[]>, transitions: { from: string, to: string, trigger: string }[], identifiers: string[], expandedCount: number, declaredCount: number }` / `readTestFileSet(toolsRoot) -> string[]`；`test/gate-registry.json`（`schema` / `manifest.files` / `manifest.cases` / `stateMachine.namedStates` / `stateMachine.wildcards` / `stateMachine.transitions` / `exceptions`）；
- TASK-02：`lib/outbox-contract.mjs` 的五导出（`OUTBOX_COMPARED_FIELDS` / `OUTBOX_EXCLUDED_FIELDS` / `OUTBOX_VOLATILE_PAYLOAD_KEYS` / `buildOutboxEvent(input, nowIsoString)` / `buildOutboxComparable(event)`）——`contract-scan` 静态断言「产品面无第二份字段枚举」的消费面；
- 既有只读：`lib/workspace-transactions.mjs:3992-3998`（冻结 skip 模式表）、`pipeline-templates/_index.yml#code-implementation-v1.nodes`。

**产出（下游 TASK-04 与 `write-test-report` 消费）**

- `test/suite-gate.mjs` CLI：`--run [--report-out <tap>] [--json-out <json>] [--max-runtime-ms <n>] [--cwd <tools-root>]` 与 `--report <tap> --rc <exit-code> [--json-out <json>]`；
- 报告模型 `crctl-suite-gate-report/v1`（字段逐字见 §3.3；`test-evidence/cmd-NN.log` 直接落该 JSON）；
- 并发常量（`CONCURRENCY`）与 `--max-runtime-ms` 默认值（30 min）——TASK-04 的实验协议按同一 CLI 与同一常量口径执行；
- `.github/workflows/crctl-ci.yml:109-111` 的新步骤文本（单一命令来源）。

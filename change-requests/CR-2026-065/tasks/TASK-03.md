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

## 0. 阻断关闭声明（本条 run replay；2026-09-13）

**本卡不再被阻断。** 上一版 §0 登记的阻断（SDD §3.4/§4.2 的 TAP「文件名块 + file 级 plan」per-file 归属前提在目标运行时不存在）已在 `write-tech-design` 节点由 **B-4 修订**（`fd48041c`）关闭，并已通过独立技术评审（`review-annotations/sdd.yml`：`verdict=pass`、`blockers=[]`、`subject-sha256 = ecc1f902…` = 当前 `sdd.md`）与**人工审批**（`approval.yml#tech-design`，`2026-09-13T13:55:02+08:00`，`target-status: tech-design-reviewed`）。CR 现为 `tech-design-reviewed`，`crctl gate --for tech-design-reviewed` = `pass: true`。沿革与关闭证据见 `plan.md` §0.0。

**当前机制（本卡的实现基线，逐字对齐修订版 SDD）**：

- 归属 = **逐文件 spawn**（每文件一个 `node --test --test-reporter=tap <abs file>` 子进程，池大小 = 包装器常量 `CONCURRENCY`），归属在 spawn 时由包装器持有，**不读任何报告**（I1）；
- 文件集合事实源 = **磁盘目录** `readTestFileSet(toolsRoot)` ↔ `manifest.files`（I1）；
- 每文件用例数 = 该文件**自己** TAP 的**顶层 plan ≡ 顶层结果行数**，与 `manifest.cases` 逐项比较（`<` 即红，I2），并写入报告 `files[]`；
- 任何使 I1/I2 不可判的输入 ⇒ **硬失败红**（I3）；唯一允许的替代 = 把每文件观察通道换成结构化事件流（须双运行时实跑探针 + `observer` 登记 + `review-code` 覆盖），任一条不满足即保持红。

**已完成且可复用的部分（`implement-code` 已落地，留在 tools worktree 提交 `2c84241`；本卡**不重写**它）**：`test/suite-gate.mjs` 的两形态框架、13 个 check code 与退出码规则、例外面四查、非收敛分支与 E-2 收口、`--report` 解析自测框架、J-8 禁词约束；`test/gate-registry.json` / `test/assertion-sources.mjs` / `lib/outbox-contract.mjs`（TASK-01/02 交付物）。`crctl-ci.yml:109-111` **一字未改**（阻断期不把不可用的门禁接进 CI）—— 接线属本卡。

**本卡真正待补齐的范围（= `plan.md` §9.1「待补齐」）**：逐文件 spawn（池 = `CONCURRENCY`）、单文件 TAP 解析、报告新增 `files[]` / `observer`（13 → **15** 字段）、`--report <ndjson>` 形态（**`--rc` 取消**）、`crctl-ci.yml:109-111` 接线。

## 1. 任务描述

**目标**：让 `.github/workflows/crctl-ci.yml:109-111` 的全量测试步骤成为**真门禁**——由 `test/suite-gate.mjs` 按 `manifest.files` **逐文件 spawn** 并解析**单文件 TAP**、核对受控清单与例外登记面、按固定 check code 与退出码规则判定；并在 `contract-scan.test.mjs` 增补「登记面不得自证绿」的静态断言、单文件片段解析自测与归属自测。

**背景**：现状 CI 步骤是裸 `node --test --test-concurrency=2 skills/shared/crctl/scripts/test/*.test.mjs`（无例外、无 skip 白名单），既看不到「哪些文件真的跑了」，也没有「失败集合 / 例外 / 到期」的判定面。**AC-01 的「exit 0 / 失败集合为空」是交付目标**：本卡交付的包装器必须有约束力——事实源漂移时给出非零退出，登记面不得成为自证绿通道。

**输入条件**：TASK-01 的 `gate-registry.json` 与 `assertion-sources.mjs`、TASK-02 的 `lib/outbox-contract.mjs` 均已落地（`depends-on` 强约束）。

**范围边界（`zero_diff`）**：`dir-graph.yaml` / `pipeline-templates/*` / 所有 `SKILL.md` / `lib/yaml-subset.mjs` / `lib/durable-tx.mjs` / `lib/workspace-transactions.mjs` / `rules.json` 零 diff；不新增 crctl 子命令或 flag（FR-17）；不新增测试文件（`*.test.mjs` 集合保持 21）、不新增第三方依赖。

## 2. 涉及文件 / 模块

| 文件（相对 `tools` 仓根） | 动作 | 说明 |
|---|---|---|
| `skills/shared/crctl/scripts/test/suite-gate.mjs` | **新增** | 全量套件门禁包装器；不匹配 `*.test.mjs`，不被 runner 采集 |
| `skills/shared/crctl/scripts/test/contract-scan.test.mjs` | 追加断言 | 受控清单 / 例外登记面 / 写入口静态断言 + `--report <ndjson>` 解析自测（内联**单文件** TAP 片段）+ 归属自测（新增用例名以 `CR-2026-065` 起始） |
| `.github/workflows/crctl-ci.yml` | 改 `:109-111` | 步骤 `crctl full test suite` 改为调用 `suite-gate.mjs --run` |

## 3. 实现要点

### 3.1 `suite-gate.mjs` 调用形态（逐字对齐 SDD §3.2，修订版）

```text
node skills/shared/crctl/scripts/test/suite-gate.mjs --run [--report-out <ndjson>] [--json-out <json>]
                                                           [--max-runtime-ms <n>] [--cwd <tools-root>]
node skills/shared/crctl/scripts/test/suite-gate.mjs --report <ndjson> [--json-out <json>]
```

- `--run`：包装器**自己**按 `manifest.files` 清单**逐文件** spawn（CI 与本地证据的唯一形态）；
- `--report <ndjson>`：只做判定、不跑套件（负控、解析自测与回归自测用）；输入与 `--run --report-out` **同一形状**（每行 `{ file, exit_code, converged, tap }`）⇒ 判定函数只有一份；
- **`--rc` 取消**（修订版）：每文件退出码在记录的 `exit_code` 字段，全量结论由 check code 推出，不再由调用方传入。

### 3.2 唯一命令来源与执行（逐文件 spawn）

- 每文件命令 = `node` + `--test` + **显式 `--test-reporter=tap`** + `<该文件绝对路径>`（**每文件一个子进程**；glob 与目录发现**不用** —— SDD §7.4 P5/P6 实测跳版本不一致）；
- 池并发 = 包装器内**唯一常量** `CONCURRENCY`（与 Node `--test-concurrency=N` 同语义，TDEC-4）；设计默认 = `max(1, availableParallelism() - 1)`，候选 {默认、2、1} 的终值由 TASK-04 有界实测定值（**本卡不写死终值**）；
- `spawn(['node','--test','--test-reporter=tap',abs(file)], { cwd: toolsRoot, shell: false })`；**每文件的原始 TAP 与其退出码逐一落 `--report-out` NDJSON**（`{ file, exit_code, converged, tap }`），不与他人混流；
- 池整体计时：超过 `--max-runtime-ms` → 终止**本包装器自己 spawn 的 PID 树**（POSIX：`detached:true` + `process.kill(-pid,'SIGKILL')`；Windows：`taskkill /PID <child.pid> /T /F`），`converged = false`、`exit_code = null`、未结束文件的 `files[].state = unfinished`；**不按进程名终止任何进程**。

### 3.3 报告模型（字段名固定，SDD §2.4，**15 字段**，不得改名）

```text
schema        "crctl-suite-gate-report/v1"
command       实际执行的命令模板与展开规模（含池大小常量，字符串）
observer      本轮实际使用的每文件观察通道（"tap-per-file" = 本设计默认）
duration_ms   全量门禁耗时（整数；池式执行的整体墙钟）
converged     全部子进程是否已自行结束（false = 触发 --max-runtime-ms 被终止，即停滞）
exit_code     全量结论退出码（全绿 0；被终止时为 null；逐文件退出码在 files[]）
files_executed / cases_executed / skipped_file_level
files[]       每文件观察记录 [{ file, state, exit_code, cases, failures[], skipped, todo, duration_ms }]；state ∈ ok|failed|file-load-failure|unfinished
failures[]    失败用例名（全部文件的并集，去重）
checks[]      [{ code, ok, detail, suppressed_by?, not_evaluated? }]
registry      { sha256, exceptions_count }
platform      { platform, node }
verdict       "pass" | "block"
```

- 与上一版的差异：**新增 `observer` 与 `files[]`**（其余字段名不变）；`files[]` 使 I2（每文件用例数 ≥ 基线）在证据面上逐项可核（`files[].cases` ↔ `manifest.cases`），不再需要二次解析报告。
- `--json-out` 可选；**`--run` 不带 `--json-out` 时把上述 15 字段以 JSON 打到 stdout**（J-8 禁词约束不变）—— `test-evidence/cmd-01.log` 逐字落该 JSON（`cmd-01` 的 args 不带 `--json-out`，见 `plan.md` §6.2 表注⑤）。

### 3.4 单文件 TAP 解析（硬失败，禁止降级；B-4 修订）

> 归属**不**由解析给出（spawn 构造持有，I1）；解析器只看**一个进程的一份 TAP**，只取该文件的用例数与失败名。旧版「以缩进栈识别文件名块 + file 级 plan」整段已废止（该形态在目标运行时不存在）。

- 该文件 TAP 必须**同时**满足：① 恰有一条**顶层** plan `1..N`；② 顶层结果行（缩进 0 的 `ok` / `not ok`）数 ≡ N；③ 缩进栈自洽（子块闭合、无孤立 `...`）；`# SKIP` / `# TODO` 后缀分别计入 `skipped` / `todo`；
- 任一不满足 → 抛 `SUITE_REPORT_UNPARSEABLE`（硬失败）；**任何解析异常都不得返回「零失败」结果**（工程纪律 #1）；
- **文件级 vs 用例级失败粒度**：文件级（整文件加载/执行失败）判 `SUITE_FILE_LOAD_FAILURE`，其名字形态（裸文件名 / 绝对路径）只作**辅助判据**（该形态跳版本，SDD §7.4 P2），**不作归属来源**；`failures[]` 只收**用例级**失败名；
- **非收敛分支**：`converged=false` 时不做清单用例数核对与失败集合核对（报告记 `cases_executed = null` / `failures = []`、相关 `checks[].not_evaluated = true`），只判 `SUITE_NONCONVERGENCE` 与登记面自身错误（`EXCEPTION_*`）；但 `files[]` **必须原样保留每个文件的状态**（`ok|failed|file-load-failure|unfinished`）；`SUITE_REPORT_UNPARSEABLE` 只在「子进程已自行结束（`converged=true`）而 TAP 结构仍不完整」时触发（两者不混算）；
- **E-2 收口**：非收敛分支中，**已匹配的 `kind: suite-nonconvergence` 例外视为已观测**，禁用空观测集合判 `EXCEPTION_NOT_OBSERVED`。

### 3.5 check code 与退出码（逐字取自 SDD §3.2 表，不得增删改名）

| check code | 触发条件 | 可否被例外容忍 |
|---|---|---|
| `SUITE_REGISTRY_MISSING` / `SUITE_REGISTRY_SCHEMA_INVALID` | 登记文件缺失 / schema 不符（含字段缺失、类型错误、`expires` 无时区偏移） | 否 |
| `SUITE_REPORT_UNPARSEABLE` | 某文件的 TAP 结构不符（无顶层 plan、plan 与顶层结果行数矛盾、缩进栈不成对）或未产出任何可判结论（硬失败，禁止降级为空结果） | 否 |
| `SUITE_FILE_LOAD_FAILURE` | 某文件整体加载/执行失败：该文件子进程非 0 退出，且（a）其 TAP 中只有一条顶层 `not ok`、其名字为该文件绝对路径或以该文件名结尾；或（b）非 0 退出且顶层结果数为 0 | 否 |
| `SUITE_MANIFEST_FILE_DRIFT` | 磁盘 `test/*.test.mjs` 实际集合 ≠ `manifest.files`；或登记集合中存在未被真实 spawn 的文件 | 否 |
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
- **解析自测（内联**单文件** TAP 片段，修订版）**：以 `--report <ndjson>` 形态跑通：合法单文件片段判绿；三类畸形片段（**无顶层 plan** / plan 与顶层结果行数矛盾 / 缩进栈不成对）各自落 `SUITE_REPORT_UNPARSEABLE` 且退出非零；
- **归属自测**：两条记录（**同一用例名**、不同 `file`）必须分别归属到各自文件（证明归属不来自用例名或报告文本——I1 的机械证据）；
- **测试命名约束（防「窄跑空跑即绿」）**：本卡新增的全部 `test(...)` 用例名**必须以 `CR-2026-065` 起始**；§4.1 的窄跑验收须附**被命中用例名清单**（Node 的 `--test-name-pattern` 无命中时不报错、退出码为 0，仅凭 exit 0 不能证明用例真的跑了）；
- **不新增测试文件、不新增 fixture 目录**：`*.test.mjs` 集合仍为 21，自测片段**内联**在测试代码里。

### 3.7 CI 步骤改造（唯一 diff 面）

```yaml
      - name: crctl full test suite
        shell: bash
        run: node skills/shared/crctl/scripts/test/suite-gate.mjs --run
```

（`run` 内不再出现 `--test-concurrency`：命令与并发参数的唯一来源 = 包装器内常量，满足 FR-12.3「同一口径」。）

## 4. 验收条件（可执行）

1. 解析自测与归属自测（`contract-scan`，窄跑）：`node --test --test-reporter=dot --test-name-pattern "CR-2026-065" skills/shared/crctl/scripts/test/contract-scan.test.mjs` → **exit 0 且附被命中用例名清单**（合法片段判绿 + 三个畸形片段各自 `SUITE_REPORT_UNPARSEABLE` + 归属自测 + 静态断言通过）；清单须至少含 **4 条**本卡新增用例名（合法片段 / 无顶层 plan / plan 与结果行数矛盾 / 缩进栈不成对；归属自测可合并计数），否则本项不算通过（**防空跑即绿**：无命中时 Node 退出码也为 0）。
2. `cmd-01`（§6.2，tools cwd `.`）：`node skills/shared/crctl/scripts/test/suite-gate.mjs --run --max-runtime-ms 1200000` → **exit 0**，且其 **stdout JSON**（= `test-evidence/cmd-01.log`，15 字段；**cmd-01 的 args 不带 `--json-out`**）内 `failures=[]`、`files_executed=21`、`files[]` 恰 21 条且全为 `state=ok`、`skipped_file_level=0`、`cases_executed>0`、`converged=true`、`observer` 非空。**TASK-01/02 完成后**该次 `--run` 应达成此结果（首次干跑单位，`plan.md` §6.3）；若池默认值在 1200 s 内不收敛，则按非收敛口径落 `converged=false` 证据、退出码红，并把常量终值决策交给 TASK-04（R-02/R-03）——**不得**把红记成绿。
3. `cmd-04`（§6.2，登记面 schema + `zero_diff` 边界 + diff 白名单）→ **exit 0**（本卡新增路径均在 `skills/shared/crctl/scripts/test/**` 与 `.github/workflows/crctl-ci.yml` 白名单内）。
4. 步骤改造自检：`crctl git diff -- .github/workflows/crctl-ci.yml` 仅 `:109-111` 三行变化；`crctl git diff --name-only dddd0ad63fb79bd7608314b4553f30e8ce7b7289 -- skills/shared/controlled-shell/rules.json dir-graph.yaml pipeline-templates` 为空。
5. **不改 `sdd.md` 一个字节**（`sha256(LF)` 仍为 `ecc1f902…`）：本卡只按修订版重述实现，不改设计。

## 5. 完成标志

- **前置（已解除）**：修订版 SDD（`write-tech-design` → 重新评审 → 重新人工审批）**已落地**（`fd48041c`；`review-annotations/sdd.yml` pass + `approval.yml#tech-design` 在册）；本卡按修订版机制实现，**不再有阻断前置**。
- `suite-gate.mjs` 落地：§3.1 两形态 CLI（`--report <ndjson>`、`--rc` 取消）、§3.2 逐文件 spawn（池 = `CONCURRENCY`）、§3.3 报告 **15 字段**、§3.4 **单文件** TAP 硬失败与非收敛口径、§3.5 check code 与退出码、J-8 禁词；
- `contract-scan.test.mjs` 静态断言 + 单文件片段解析自测 + 归属自测绿（新增用例名以 `CR-2026-065` 起始）；CI 步骤改为调用包装器；
- `cmd-01` 首次 `--run` 落盘 stdout 报告（15 字段齐备、判定与失败集合自洽；绿或按非收敛口径落红证据）；`cmd-04` exit 0；
- 峰值口径记录：`*.test.mjs` 仍 21 个、无新增依赖、无新增 crctl 子命令/flag；
- 任务账本登记：`crctl task done CR-2026-065 --task CR-2026-065-TASK-03`。

## 6. 接口契约

**消费（上游 TASK 产出，逐字；不得缩略）**

- TASK-01：`test/assertion-sources.mjs` 的 `readTextNormalized(absPath) -> string` / `deriveStateMachine(toolsRoot) -> { namedStates: string[], wildcards: Record<string, string[]>, transitions: { from: string, to: string, trigger: string }[], identifiers: string[], expandedCount: number, declaredCount: number }` / `readTestFileSet(toolsRoot) -> string[]`；`test/gate-registry.json`（`schema` / `manifest.files` / `manifest.cases` / `stateMachine.namedStates` / `stateMachine.wildcards` / `stateMachine.transitions` / `exceptions`）；
- TASK-02：`lib/outbox-contract.mjs` 的五导出（`OUTBOX_COMPARED_FIELDS` / `OUTBOX_EXCLUDED_FIELDS` / `OUTBOX_VOLATILE_PAYLOAD_KEYS` / `buildOutboxEvent(input, nowIsoString)` / `buildOutboxComparable(event)`）——`contract-scan` 静态断言「产品面无第二份字段枚举」的消费面；
- 既有只读：`lib/workspace-transactions.mjs:3992-3998`（冻结 skip 模式表）、`pipeline-templates/_index.yml#code-implementation-v1.nodes`。

**产出（下游 TASK-04 与 `write-test-report` 消费）**

- `test/suite-gate.mjs` CLI（修订版）：`--run [--report-out <ndjson>] [--json-out <json>] [--max-runtime-ms <n>] [--cwd <tools-root>]` 与 `--report <ndjson> [--json-out <json>]`；
- 报告模型 `crctl-suite-gate-report/v1`（**15 字段**，逐字见 §3.3；不带 `--json-out` 时整份 JSON 打到 stdout，`test-evidence/cmd-01.log` 直接落该 JSON）；
- 并发常量（`CONCURRENCY`；默认 `max(1, availableParallelism() - 1)`，终值由 TASK-04 有界实测选定）与 `--max-runtime-ms` 默认值（30 min）——TASK-04 的实验协议按同一 CLI 与同一常量口径执行；
- `.github/workflows/crctl-ci.yml:109-111` 的新步骤文本（单一命令来源）。

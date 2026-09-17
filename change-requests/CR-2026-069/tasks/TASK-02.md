---
id: CR-2026-069-TASK-02
type: TASK
cr-ref: CR-2026-069
plan-ref: "change-requests/CR-2026-069/plan.md"
sdd-ref: "change-requests/CR-2026-069/sdd.md"
target-version: 0.42
title: "OutputGuard Core 纯函数 + policy/capabilities/conformance 三份唯一事实源 + check-install + README + core/conformance/adapters-contract 三个测试 + CI 触发面与步骤"
slug: output-guard-core-contracts
status: pending
estimate: 22h
depends-on: [CR-2026-069-TASK-01]
created: 2026-09-17T17:22:00+08:00
---

# CR-2026-069-TASK-02 OutputGuard Core 与三份契约 JSON（G2，FR-1 第 1~10 项）

## 1. 任务描述

**目标**：在 `../tools` 仓新增 OutputGuard 的**纯函数 Core** 与**三份唯一事实源 JSON**（`policy.json` / `capabilities.json` / `conformance.json`）、只读启动检查 `scripts/check-install.mjs`、模块总览 `README.md`，以及 `test/{core.test.mjs,conformance.test.mjs,adapters-contract.test.mjs}` 三个回归面；并把 `.github/workflows/crctl-ci.yml` 的触发面与步骤补齐（`output-guard/**` + `skills/shared/metrics/**` 两条 path + 两条 step）。

**背景**：FR-1 的全部判定算法（A1~A5）都住在 Core；Adapter（TASK-03~07）只做 Provider hook 的输入输出映射，不复制 policy、不做业务判断（SDD I2 / §3.2 / §3.3）。`thresholds` 的五个数值由 TASK-01 的基线产出，本 TASK 只负责**写进 `policy.json`**，代码内零阈值常量。

**输入条件**：TASK-01 已完成并给出 `thresholds` 五值与最小命令集合；CR status `developing`；`sdd.md` 已审批不得改写。

**范围边界（零越界）**：只新增/改 `output-guard/**`（本 TASK 的 9 个文件）与 `.github/workflows/crctl-ci.yml`。**不改** `skills/shared/crctl/**`（TASK-08）、`skills/shared/metrics/**`（TASK-01）、`../multica`（TASK-09）、`pipeline-templates/**` 的结构、`skills/_index.yml`、`agent-skill-matrix.yml`、`dir-graph.yaml`、`ARCHITECTURE.md` / `README.md`（TASK-08 承担导航落点）；`output-guard/` **不得**被注册为 skill（`dep-9`）。

## 2. 涉及文件 / 模块

| 文件 | 动作 | SDD 落点 |
|---|---|---|
| `output-guard/core.mjs` | 新增（ESM 纯函数，零第三方依赖） | §3.2 |
| `output-guard/policy.json` | 新增（阈值/命令族/裁剪/提示唯一源；`thresholds` 写 TASK-01 产出值） | §2.2.1 |
| `output-guard/capabilities.json` | 新增（Runtime 能力唯一声明源；五 Runtime + `enableOrder`） | §2.2.2 |
| `output-guard/conformance.json` | 新增（跨 Adapter 共享向量 + `declaredVectorCount`） | §2.2.3 |
| `output-guard/README.md` | 新增（总览 + 三个权威入口链接，**不复刻** policy / 能力矩阵） | §3.5 |
| `output-guard/scripts/check-install.mjs` | 新增（只读启动检查：逐 Runtime 一行 `output-guard runtime=… coverage=… policy=v1`） | §1.4.2、AC-19③ |
| `output-guard/test/core.test.mjs` | 新增（A1~A5 纯函数面） | §6.4 |
| `output-guard/test/conformance.test.mjs` | 新增（向量驱动 + `declaredVectorCount` 自棘轮） | §2.2.3 |
| `output-guard/test/adapters-contract.test.mjs` | 新增（按目录发现五个 Adapter，逐 Runtime 执行同一向量；Adapter 缺失记 `ADAPTER_MISSING` 而非假绿） | §3.3、§6.4 |
| `.github/workflows/crctl-ci.yml` | 改（`paths` 增 `output-guard/**`、`skills/shared/metrics/**`；`steps` 增两条测试步骤） | §6.4、`dep-19` |

## 3. 实现要点

1. **Core 接口逐字实现**（§3.2）：`parsePolicy(text)` / `normalizeText(s)` / `parseCall(input, policy)` / `classifyFamily(cmdline, policy)` / `parseEscapeHatch(firstLine, policy)` / `evaluateResult(input, policy)` / `fingerprint(input)` / `renderTrailer(decision)`。三条实现约束（AC-3 机械判据）：① `core.mjs` 内**零阈值字面量**（数值只从入参 `policy` 取）；② 同一 `(policyVersion, ruleId, runtime, toolName, normalizedInput, normalizedBody)` 必产生逐字相同的 `body` 与 `trailer`；③ Core 不读文件、不读环境变量、不调用子进程（policy 读取是 Adapter 的职责）。
2. **A1~A5 算法**（§4.1~§4.5）：A1 逃生阀只解析 shell 命令族首行，不合法标记 → `absent`（不拒绝调用、不新增 action 取值）；A2 五步固定顺序、命中即终态，终态闭包 `{block,rewrite,truncate,passthrough,unavailable}`；`action=unavailable` 有两个合法来源（降级面 / 字段或结构不可保持面），二者不合并、不新增取值；A3 三类确定性裁剪（搜索=唯一文件列表+命中数+缩小写法；列举=去重稳定排序路径+总条目数+缩小写法；读取=**连续行窗口+原始行号**+下一次 `offset/limit` 具体值；普通 shell=头 N 行+尾 M 行+省略量），文本处理前一律 `normalizeText`，切断回退到整行边界；A4 `fingerprint` 的规范化拼接与幂等证明；A5 四场景 fail-open + `reason` **四值闭包**（`ADAPTER_MISSING` / `DISABLED` / `BUNDLE_INVALID` / `POLICY_INVALID`）。
3. **可保持性检查是裁剪的前置门**（§4.2，AC-15 唯一判据）：`toolName` / `toolCallId` / `isError` 必须存在且可原样回填；`exitCode` 按 `capabilities[runtime].preserve.exitCode` 判定（`present` 必保留；`absent-by-runtime` 不作要求，**不因此降级该路径**）；结果结构键集不变。不通过 ⇒ `action=unavailable`（结果逐字不改 + 一行 trailer + `pathCoverage=unavailable`）。
4. **`policy.json`**：`policyVersion:"v1"`；`families` 三族五命令（`grep`|`rg` / `find`|`Get-ChildItem` / `cat`|`Get-Content`）；`thresholds` 五键为 TASK-01 产出的正整数；`hints` 三条文案模板（唯一事实源）；`escapeHatch.marker` 含 `output-guard: full`、`singleLine:true`、`reasonMaxLength` 正整数。
5. **`capabilities.json`**：`enableOrder = ["pi","claude","codebuddy","qoder","codex"]`；五 Runtime 各自 `level`（取值闭包 `full`/`partial`/`unavailable`）、`preserve` 四字段（取值闭包 `present`/`absent-by-runtime`，**落笔前按 `V-1`/`V-3` 核实**）、`paths[]`；`codex.level="partial"` 且必须有 `uncovered:true` 的路径（含 hosted `WebSearch`）；`qoder.startRecord="none"`（无 SessionStart）。**任一 Runtime 由 `full` 降级即 AC-4 未达成**，按 §2.4 走 scope amendment，不得静默吸收。
6. **`conformance.json`**：四类 `kind` 齐备（`escape-hatch` / `decision` / `degradation` / `idempotence`）；`declaredVectorCount` 必须等于实际 `vectors.length`，`conformance.test.mjs` 断言该等式（本 CR 内唯一新增的计数棘轮，不写 `gate-registry.json` 以外的登记面）。
7. **`check-install.mjs`（只读，AC-19③）**：CLI 固定 `node output-guard/scripts/check-install.mjs --tools-root <path>`；对 `enableOrder` 每个 Runtime **恰输出一行** `output-guard runtime=<rt> coverage=<full|partial|unavailable> policy=v1`；只报告缺失/损坏与修复命令，**不**自动安装、不写文件、不改写用户配置（零 `writeFileSync`/`mkdirSync`/`rmSync`/`renameSync`/`copyFileSync`/`chmodSync`/`createWriteStream`）；文件缺失/损坏时打一行 `OUTPUT_GUARD_UNAVAILABLE runtime=<r> reason=<枚举>`。
8. **Adapter 契约驱动**：`adapters-contract.test.mjs` 按 `output-guard/adapters/<rt>/` 目录发现 Adapter（**禁止**目录 glob 依赖 shell），对存在的 Adapter 逐条执行同一组 `conformance` 向量；不存在的 Adapter 记 `ADAPTER_MISSING` 并**非零退出**（只有全部五个 Adapter 落地后本文件才全绿；实施期分 TASK 落地时以 `capabilities.level` 的声明进度为判据，不伪造通过）。
9. **CI 面**：`paths` 增 `output-guard/**` 与 `skills/shared/metrics/**`；`steps` 增两条（`node --test output-guard/test/*.test.mjs` 与 `node --test skills/shared/metrics/test/*.test.mjs` 的等价形态）。`gate-registry.json` 由 TASK-08 同步（本 TASK 不动）。
10. **零依赖**：只用 `node:*` 内建；`output-guard/**` 下不得出现 `package.json`；Adapter 与 Core 之间只用**相对说明符**（`../..` 系列）引用同一 Release 的模块与 policy。

## 4. 验收条件

1. `node --test --test-reporter=dot output-guard/test/core.test.mjs output-guard/test/conformance.test.mjs output-guard/test/adapters-contract.test.mjs` exit 0（TASK-03~07 未落地前，本条的判据是「已落地 Adapter 的向量全绿 + 未落地记 ADAPTER_MISSING 且非零退出」，实施期不得用跳过代替）。
2. `node output-guard/scripts/check-install.mjs --tools-root .` exit 0，stdout 中 `enableOrder` 五个 Runtime 各恰一行稳定形态；运行前后 `crctl git status --porcelain` 逐字相同（只读负向）。
3. `policy.json` 五键全为正整数且与 TASK-01 申报值逐字相等；全仓（除 `output-guard/policy.json`）无阈值键名紧跟数字字面量的第二副本。
4. `capabilities.json` 的 `enableOrder` / `runtimes` 键集 / `preserve` 取值闭包 / `codex.level="partial"` / `qoder.startRecord="none"` / codex `uncovered`（含 `WebSearch`）逐条成立；`conformance.json` 的 `declaredVectorCount === vectors.length`。
5. `output-guard/README.md` 只含总览与三个权威入口名（`policy.json` / `capabilities.json` / `conformance.json`），不含任何阈值数值或完整能力矩阵。
6. `.github/workflows/crctl-ci.yml` 的两条 `paths` 与两条 `steps` 就位；YAML 可解析。

## 5. 完成标志

- 9 个 `output-guard/**` 文件 + CI 两处改动落盘并提交；验收条件 1~6 逐条实测通过。
- 明确记录「Adapter 侧待 TASK-03~07 补齐」的进度事实（`adapters-contract.test.mjs` 的当前判定与 `check-install` 读数），不把未落地 Runtime 记为通过。
- `tasks/_index.yml` 本 TASK 标 `done`。
- **不**包含：任何 Adapter 实现（TASK-03~07）、`crctl.mjs` 改动（TASK-08）、multica 挂载（TASK-09）。

## 6. 接口契约

**产出（供 TASK-03~07 / TASK-09 / TASK-10 消费，逐字对齐 SDD §3.2）**

```ts
// output-guard/core.mjs（ESM，零第三方依赖，无 fs / 无时钟 / 无随机 / 无环境读取）
export function parsePolicy(text: string): Policy            // 失败抛 PolicyParseError → 调用方转 POLICY_INVALID
export function normalizeText(s: string): string             // \r\n → \n（唯一规范化入口，I9）
export function parseCall(input: CallInput, policy: Policy): CallDecision
export function classifyFamily(cmdline: string, policy: Policy): FamilyDecision   // { family, determinate, limits }
export function parseEscapeHatch(firstLine: string, policy: Policy): EscapeDecision  // {state:'valid',reason} | {state:'absent'}
export function evaluateResult(input: ResultInput, policy: Policy): ResultDecision
export function fingerprint(input: FingerprintInput): string
export function renderTrailer(decision: ResultDecision): string
// CallInput   = { runtime, toolName, toolInput }
// ResultInput = { runtime, toolName, toolCallId, isError, exitCode?, body, structure: 'text' | 'content-parts' }
```

```text
// check-install.mjs CLI（逐字）
node output-guard/scripts/check-install.mjs --tools-root <path>
stdout（enableOrder 每 Runtime 恰一行）: output-guard runtime=<rt> coverage=<full|partial|unavailable> policy=v1
stdout（缺失/损坏时）              : OUTPUT_GUARD_UNAVAILABLE runtime=<rt> reason=<ADAPTER_MISSING|DISABLED|BUNDLE_INVALID|POLICY_INVALID>
exit: 0 = 检查完成（缺失按行报告，不算技术失败）；非零仅供不可判的读失败使用
```

**消费（本 TASK 依赖的上游）**

- TASK-01 产出的 `thresholds` 五值（正整数）与最小命令集合（后者本 TASK 不使用，由 TASK-08 消费）。
- `dep-4` / `dep-15` 的 daemon 事实（TASK-09 消费）：daemon 侧 Runtime hooks 写点**只有 claude**；本 TASK 的 `capabilities` 与 `README` 只声明能力，不涉及挂载。

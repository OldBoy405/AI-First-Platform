---
id: CR-2026-069-TASK-01
type: TASK
cr-ref: CR-2026-069
plan-ref: "change-requests/CR-2026-069/plan.md"
sdd-ref: "change-requests/CR-2026-069/sdd.md"
target-version: 0.42
title: "FR-8 离线度量脚本 cr-cost.mjs 四子命令 + lib 四件 + 回归面，并产出 policy.json thresholds 数值与 FR-2 summary 命令集合"
slug: metrics-cr-cost-baseline
status: pending
estimate: 20h
depends-on: []
created: 2026-09-17T17:20:00+08:00
---

# CR-2026-069-TASK-01 FR-8 度量脚本与基线（G1，FR-8 全量）

## 1. 任务描述

**目标**：在 `../tools` 仓新增 `skills/shared/metrics/` 只读度量面——`scripts/cr-cost.mjs` 的四个子命令（`baseline` / `after` / `replay` / `verify-selection`）＋ `scripts/lib/{sessions,aggregate,select,render}.mjs` 纯函数分层 ＋ `test/cr-cost.test.mjs` 回归面；并用基线执行产出两件下游输入：① `policy.json#thresholds` 的五个正整数（交 TASK-02 写入）；② AC-10 的最小命令集合（交 TASK-08 落进 `SUMMARY_PROJECTORS`）。

**背景**：FR-8 是「先计量、后扩项」的判据面（SDD §1.4.4 / §4.7 / §3.6）。它不推进 CR、不参与门禁、不写状态与账本；机器结果只有一份 JSON，人读摘要由同一对象渲染。

**输入条件**：CR status `developing`；`sdd.md` 已审批（sha256(LF) `912627cb…`，**不得改一字**）；`prd.md` 冻结（sha256(LF) `4747bd52…`）；tools worktree HEAD（本节开工时）`82e43dc5…`；KB worktree 可写 `change-requests/CR-2026-069/evidence/`。

**范围边界（零越界）**：只新增 `skills/shared/metrics/**` 6 文件与 KB `evidence/fr8-baseline.json`、`evidence/ac9-sampling.md`。**不改** `skills/shared/crctl/**`（TASK-08）、`output-guard/**`（TASK-02）、`.github/workflows/crctl-ci.yml`（TASK-02）、`dir-graph.yaml`、`lib/durable-tx.mjs` 等 SDD §9 `zero_diff` 面；不新增账本、数据库、仪表盘、sidecar 日志、定时任务、Pipeline 节点或 Skill 步骤。

## 2. 涉及文件 / 模块

| 文件 | 动作 | SDD 落点 |
|---|---|---|
| `skills/shared/metrics/scripts/cr-cost.mjs` | 新增 | §3.6 CLI 契约、§4.7 A7、§4.8 A8 |
| `skills/shared/metrics/scripts/lib/sessions.mjs` | 新增（只读遍历 + EOL 归一 + 硬失败计数） | §4.7 样本筛选、§7.1 第 2 条 |
| `skills/shared/metrics/scripts/lib/aggregate.mjs` | 新增（每会话聚合 + 派生指标 + 护栏 + `k`） | §4.7 |
| `skills/shared/metrics/scripts/lib/select.mjs` | 新增（A8 贪心最小集合算法，**唯一事实源**） | §4.8 |
| `skills/shared/metrics/scripts/lib/render.mjs` | 新增（同一对象渲染人读摘要，不写第二份产物） | §3.6 输出纪律① |
| `skills/shared/metrics/test/cr-cost.test.mjs` | 新增（`node --test`，单文件自足） | §6.4 改动清单 |
| `change-requests/CR-2026-069/evidence/fr8-baseline.json` | 新增（KB，TASK-01 机器 JSON 副本） | §6.5 SDD-CLOSE-07 |
| `change-requests/CR-2026-069/evidence/ac9-sampling.md` | 新增（KB，抽检清单与判定，AC-9） | §6.2 AC-9 可达性 |
| `change-requests/CR-2026-069/evidence/ac10-selection.json` | 新增（KB，`verify-selection` 输出副本，AC-10） | §3.6 `verify-selection` |

零改动核对：`git diff --name-only` 对 `skills/shared/crctl/**`、`output-guard/**`、`pipeline-templates/**`、`agents/**`、`AGENT*.md`、`README.md`、`ARCHITECTURE.md`、`dir-graph.yaml` 保持为空。

## 3. 实现要点

1. **四子命令形态**（§3.6，逐字实现）：`baseline --out <path> [--sessions-root <dir>]... [--window <from>..<to>]`、`after --out <path> --window 14d`、`replay --policy <path>`、`verify-selection --baseline <path>`。`verify-selection` 从 baseline 的 `crctlCommands[]` 重算最小集合，与 `skills/shared/crctl/scripts/lib/summary-projectors.mjs` 的 `SUMMARY_PROJECTORS` 键集逐项比对，**不一致即非零退出**（该模块由 TASK-08 产出；本 TASK 只按接口消费，缺失时按 `verify-selection` 的失败语义非零退出，不静默通过）。
2. **输出纪律**（§3.6，AC-17 / AC-18）：① 机器结果只有一份 JSON，字段集固定为 `window` / `sampleCRs` / `coverage` / `providerUsage{input,cachedInput,cacheWrite,output}` / `toolResultTokens` / `k` / `metrics{tokensPerCR,sessionsPerCR,searchTokenRatio,fullReadRatio,bootstrapTokensPerSession}` / `guardrails{firstPassGateRate,reviewLoopsPerCR,reviewDefectsPerCR}` **＋** `crctlCommands[]` / `tokenEstimator` / `costSource` / `observedAt` / `rule`；② 每个计数字段必须携带 `observedAt` 与 `rule`；③ 代码与门禁中**零硬编码样本常量**（不得出现 `672` / `585` 等观测值）；④ `costSource` 取值闭包 `pi-session-usage` / `external-invoice` / `unavailable`，`costSource=unavailable` ⇒ `k=null` 且输出不出现任何金额宣称；首期只对 Pi 出成本结论，其它 Runtime 只报覆盖度与裁剪量（不外推）。
3. **样本筛选与回放**（§4.7）：只读遍历既有 session（`*.jsonl`，`type`/`role` 形状按 `V-2` 实读，键名差异只改 `sessions.mjs` 的读取口径、不改输出字段集）；离线回放为纯函数重算（不执行任何命令、不依赖网络）；`cachedInput` 映射既有 `cacheRead` 并保留原始键名；`after` 只统计 `coverage=full` 且带 CR-ID 的完整 Pi CR，样本不足输出 `insufficient-sample` **终态**（不产出成本结论）。
4. **A8 选择算法**（§4.8，唯一实现落在 `lib/select.mjs`）：按 `tokens` 降序、tokens 相等按 `command` 字典序 tie-break；贪心取前缀直到累计份额 ≥ 80%；输出即「达到阈值的最小基数集合」。该命令集合与算法**不写入** PRD / Prompt / Skill / 门禁；只在 `select.mjs`、`cr-cost.mjs` 与 baseline evidence 内存在。
5. **thresholds 数值产出**（§2.2.1 + `dep-1` FR-1 第 3 项）：由 baseline 的实测分布得出 `resultTokensCap` / `lineWindow` / `maxHits` / `headLines` / `tailLines` 五个**正整数**，写进 TASK 完成记录（交 TASK-02 落 `policy.json`）。本 TASK **不得**把数值写进任何代码或文档（`core.mjs` 内零阈值是 AC-3 的机械判据）。
6. **行尾与硬失败纪律**（§7.1 / NFR-8）：所有读入先 `\r\n → \n`；JSONL 逐行 `JSON.parse` 失败计入 `malformedLines` 且可见，文件级读失败计入 `unreadableFiles`，**不得整体静默跳过**；解析失败硬失败报错（禁止「匹配不到 → 空集 → 静默通过」）。
7. **零依赖**：只用 `node:*` 内建模块；`skills/shared/metrics/**` 下**不得**出现 `package.json` 或非相对非内建的 `import`/`require` 说明符。
8. **回放抽检（AC-9）**：`replay --policy <path>` 对历史 session 离线回放后，对合法调用做抽检（清单 + 逐条判定 + 零误伤结论）写入 `evidence/ac9-sampling.md`；不得用"未观测到误伤"代替抽检记录。

## 4. 验收条件

1. `node --test --test-reporter=dot skills/shared/metrics/test/cr-cost.test.mjs` exit 0，且覆盖：`insufficient-sample` 分支、14 天窗口判定、`≥20% ∧ 三护栏不恶化` 判定、`costSource=unavailable ⇒ k=null`、A8 贪心集合（正例/反例）、`verify-selection` 注册表相等/不等两向。
2. `node skills/shared/metrics/scripts/cr-cost.mjs baseline --out <tmp>/fr8-baseline.json` 执行成功，产物 JSON 含 §3.2 全部字段，且每个计数字段带 `observedAt` + `rule`。
3. **可执行形态**（cwd = tools worktree；KB 路径不拼接，先由 `crctl workspace inspect CR-2026-069` 的 `resources[].worktreePath` 解析出 `ai-first-platform-docs` worktree，记为 `<KB>`）：
   ```text
   node skills/shared/metrics/scripts/cr-cost.mjs verify-selection --baseline <KB>/change-requests/CR-2026-069/evidence/fr8-baseline.json
   ```
   与 `SUMMARY_PROJECTORS` 键集全等；不等时必须非零退出（负例已由测试 1 覆盖）。该核对在 `cmd-05` 内另有**活体副本**（`cmd-05` 自行 `require` 工具仓的 `summary-projectors.mjs` 并与同一份 `ac10-selection.json#minimalSet` 双向全等，不可判即硬失败），两处不得只做其一。
4. `evidence/fr8-baseline.json` 与 `evidence/ac9-sampling.md` 落 KB 且随 CR 提交；`evidence/ac10-selection.json` 由 `verify-selection` 产出（含 `baselineSha256` / `registryKeys` / `minimalSet` / `verdict` / `observedAt` / `rule`）。
5. `cmd-04` 的「样本常量零硬编码」与「零依赖」两条判据为 0 失败。

## 5. 完成标志

- 6 个新增文件落盘并提交（tools）；三份 KB evidence 落盘并提交。
- 验收条件 1~5 逐条实测通过，原始命令与结果记入 TASK 完成记录。
- `tasks/_index.yml` 中本 TASK 已由 `crctl task done` 标 `done`（工程纪律 #8，不积压到回写期）。
- 明确登记两个下游输入：`thresholds` 五值与最小命令集合（供 TASK-02 / TASK-08 消费）。
- **不**包含：部署后 14 天窗口的真实 `after` 执行（见 TASK-10 与 plan §2.1）、任何门禁/状态推进、任何账本编辑。

## 6. 接口契约

**产出（供 TASK-02 / TASK-08 / TASK-10 消费）**

```ts
// skills/shared/metrics/scripts/lib/select.mjs
export function selectMinimalCommandSet(crctlCommands: { command: string, tokens: number, calls: number }[], threshold: number): string[]
// threshold 固定 0.8；排序 = tokens 降序、tie-break = command 字典序；返回累计份额首次 >= threshold 的前缀命令集合

// skills/shared/metrics/scripts/cr-cost.mjs（CLI 面，逐字）
//   baseline --out <path> [--sessions-root <dir>]... [--window <from>..<to>]
//   after    --out <path> --window 14d
//   replay   --policy <path>
//   verify-selection --baseline <path>
//   exit 0 = 成功；非零 = 失败（含 verify-selection 不一致、政策不可读、baseline 不可解析）
```

**消费（本 TASK 依赖的上游）**

- `skills/shared/crctl/scripts/lib/summary-projectors.mjs` 的 `SUMMARY_PROJECTORS`（TASK-08 产出；`verify-selection` 的比对对象）。
- SDD §3.6 的字段集与 §4.8 的算法（本 TASK 实现，签名逐字对齐 `selectMinimalCommandSet` 语义）。
- `V-2` 的 session JSONL 形状（`type` / `message.role` / `usage.{input,output,cacheRead,cacheWrite}` / `toolResult.{toolCallId,toolName,content,isError}`）：键名与实读不符时只改 `sessions.mjs` 读取口径，输出字段集不变。

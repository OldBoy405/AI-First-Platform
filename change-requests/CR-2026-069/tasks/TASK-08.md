---
id: CR-2026-069-TASK-08
type: TASK
cr-ref: CR-2026-069
plan-ref: "change-requests/CR-2026-069/plan.md"
sdd-ref: "change-requests/CR-2026-069/sdd.md"
target-version: 0.42
title: "FR-2 投影层：summary-projectors + crctl.mjs 三处落点 + golden 金样本 + 两张合同测试 + 棘轮登记 + Prompt 采纳面 + 导航"
slug: crctl-summary-detail
status: pending
estimate: 20h
depends-on: [CR-2026-069-TASK-01]
created: 2026-09-17T17:30:00+08:00
---

# CR-2026-069-TASK-08 FR-2 投影层与调用方同步（G8，FR-2 全量 + AC-21）

## 1. 任务描述

**目标**：为 TASK-01 基线选出的**最小命令集合**（覆盖 ≥80% crctl 输出 token）新增独立 summary projector，把 `crctl.mjs` 的**唯一改造点**收敛到三处（`ok()` 投影入口 / `parseArgs` 的 `--detail` 布尔分支 / HELP 一行），补齐 golden 金样本与两个合同测试，按 `dep-13` 同步 `gate-registry.json`，并按 A10 扫描表把 Prompt 采纳面（Skill / pipeline prompt / agents）在同一 CR 内更新。

**背景**：FR-2 的杠杆是**字段投影**而非空白压缩（D-2）；`--detail` 是纯呈现层布尔开关，不参与状态判定、门禁、审批与 CAS（§3.1）；未投影命令收到 `--detail` 等价于现状（§1.4.6，同时关闭需求评审 S-1）。`dep-20` 的 `lint-prompts` 抓不到"新增能力未被采纳"这一类漂移，只能靠 §8 清单 + `caller-contract.test.mjs` 兜住（§8 触发判定段）。

**输入条件**：TASK-01 已产出 baseline JSON 与最小命令集合（`verify-selection` 的比对基准）；CR status `developing`。

**范围边界（零越界）**：改动面 = `skills/shared/crctl/scripts/crctl.mjs`（**仅三处落点 + 一行 import**）、`skills/shared/crctl/scripts/lib/summary-projectors.mjs`（新增）、`skills/shared/crctl/scripts/test/{crctl-summary.test.mjs,caller-contract.test.mjs,golden/crctl-detail/*.json}`（新增）、`skills/shared/crctl/scripts/test/gate-registry.json`（仅 `manifest.files` / `manifest.cases` 增项）、`skills/shared/crctl/SKILL.md`、四个 review Skill、四个 approve Skill、`skills/sync/**` 命中项、`pipeline-templates/*.pipeline.json` 的 **prompt 文本**、`agents/*.md` 命中项、`README.md`、`ARCHITECTURE.md`。**逐条不触碰**：`crctl.mjs` 的 247 个 `fail()` 出口与全部状态/门禁/审批/CAS/事务/Git 分支、`lib/{durable-tx,workspace-transactions,outbox-contract,yaml-subset}.mjs`、`gates.json`、`dir-graph.yaml`、`agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md`、`controlled-shell/rules.json`、`pipeline-templates/**` 的结构（节点数 8 模板全表不变，含 5/4/12；`reviewLoop`/`replayNodes`/`maxAttempts`）、`pipeline-templates/_index.yml`、`skills/_index.yml`、`skills/shared/crctl/adapters/**`、`output-guard/**`（TASK-02）、`skills/shared/metrics/**`（TASK-01）。

## 2. 涉及文件 / 模块

| 文件 | 动作 | SDD 落点 |
|---|---|---|
| `skills/shared/crctl/scripts/test/golden/crctl-detail/*.json` | 新增（**实现投影前**用未改造 CLI 采集；含 `fieldPaths` + `stable`/`volatile` 标记） | §4.6 金样本 |
| `skills/shared/crctl/scripts/lib/summary-projectors.mjs` | 新增（每命令一个纯函数 + `SUMMARY_PROJECTORS` 注册表，键集 = TASK-01 最小集合） | §4.6、§4.8 |
| `skills/shared/crctl/scripts/crctl.mjs` | 改 3 处落点 + 1 行 import | §1.4.3、§4.6、§9 `scope_in` 第 3 项 |
| `skills/shared/crctl/scripts/test/crctl-summary.test.mjs` | 新增（summary/detail 合同 + 三层等价 + 未注册命令逐字不变） | §4.6、SDD-CLOSE-02 |
| `skills/shared/crctl/scripts/test/caller-contract.test.mjs` | 新增（A10 显式表 + 扫描面逐条判定） | §4.10、§8 |
| `skills/shared/crctl/scripts/test/gate-registry.json` | 改（`manifest.files` 21 → 23、`manifest.cases` 同步；`exceptions` 保持 `[]`） | §6.4、SDD-CLOSE-03 |
| `skills/shared/crctl/SKILL.md` | 改（默认 compact summary + `--detail` + 未投影命令等价现状；只指向 `summary-projectors.mjs`，不复刻字段清单） | §8 第 1 行 |
| `skills/develop/review-tech-design/SKILL.md`、`skills/develop/review-code/SKILL.md`、`skills/develop/review-dev-plan/SKILL.md`、`skills/requirement/review-requirement/SKILL.md` | 改（按 A10 表补 `--detail`；新增 `complete=false` 不得作最终判断的规则条款） | §8、AC-16 |
| `skills/requirement/approve-requirement/SKILL.md`、`skills/develop/approve-tech-design/SKILL.md`、`skills/develop/approve-dev-start/SKILL.md`、`skills/develop/approve-code/SKILL.md` | 改（按 A10 表定点补 `--detail`） | §8、§9 `scope_in` 第 4 项 |
| `skills/sync/**`（A10 命中项）、`pipeline-templates/*.pipeline.json`（prompt 文本）、`agents/*.md`（命中项） | 改（同上，只补 `--detail`） | §8、AC-21① |
| `README.md`、`ARCHITECTURE.md` | 改（README 增权威入口链接一行；ARCHITECTURE §1 鸟瞰增一条组成面 + §3 代码地图增 `output-guard/` 与 `skills/shared/metrics/` 两条；§4/§5/§6 不改） | §9 `scope_in` 第 5 项、AC-13 |

## 3. 实现要点

1. **先采金样本，后动投影**（§4.6）：`crctl.mjs` 未改造时用 `--detail`（改造前即默认输出）在既有 fixture 工作区采集 `golden/crctl-detail/*.json`，标注每条字段路径的 `stable` / `volatile`；采集脚本与 fixture **复用既有测试夹具构造方式**（`dep-14`，消费式引用，不另造并行夹具）。
2. **三处落点（唯一改造点，逐字）**：
   - `main()` 内 `ACTIVE_PROJECTION ← resolveProjection(cmd, flags)`——`flags.detail === true` ⇒ `null`；`cmd` 不在 `SUMMARY_PROJECTORS` ⇒ `null`；否则该命令的纯投影函数；
   - `ok(obj)` 内：`const out = ACTIVE_PROJECTION ? ACTIVE_PROJECTION(obj) : obj;` 后仍 `JSON.stringify(out, null, 2) + '\n'`（**不在全局 `ok()` 删字段**，未注册命令逐字走原路径）；
   - `parseArgs` 的 `--detail` **布尔专用分支**（出现即为真、且**不消费后随 token**，避免 `crctl status --detail CR-2026-069` 被解析成 `flags.detail='CR-2026-069'` 并吃掉位置参数）；
   - HELP 增一行说明 `--detail`。
   合计 ±10 行以内（SDD §1.2 的上界是"≤6 行不含新增导入"）；`ok(` 计数保持 45、`fail(` 计数保持 247 是机械判据。
3. **投影函数是每命令独立的纯函数**：输入成功出口对象、输出 compact summary 对象；**不读全局状态、不访问文件系统**；summary 必须按"调用方充分性"设计——先在 A10 表里枚举每个被投影命令的既有消费字段，再据此定义 summary 必须保留的字段（`--detail` 是显式例外，不是大面积补丁）。
4. **三层等价性合同**（§4.6）：① `fieldPaths(--detail 输出)` ≡ 金样本 `fieldPaths`；② 金样本标 `stable` 的字段路径值逐字相等；③ 标 `volatile` 的字段路径值类型与形态匹配（ISO 8601 / 40 hex / 绝对路径）。**禁止字节比对**。另加一条负向断言：未注册命令 + 未传 `--detail` 时输出与改造前逐字相同（D-9 的代价项）。
5. **A10 扫描表与调用方同步**（§4.10）：扫描面 = `skills/**/SKILL.md`、`pipeline-templates/*.pipeline.json`、`agents/*.md`、`skills/**/*.mjs`、`README.md`；提取 `crctl <子命令> [args]` 与 `node …/crctl.mjs …` 形态；逐条判定 a（子命令不在投影集合 ⇒ 无需动作）/ b（消费字段 ⊆ summary 字段集 ⇒ 无需动作）/ c（需要 summary 之外的字段 ⇒ **必须显式补 `--detail`**）。扫描面之外的**真实调用方**（如 KB 仓 `.github/workflows/cr-guard.yml` 这类仓外 CI）不因"在扫描面外"豁免——逐条做同一字段消费检查并把结论登记进同一张表（按仓标注）；只消费退出码的记"无需动作"。该显式表落成 `caller-contract.test.mjs` 的数据段（人工审过的白名单 + 机械断言）。
6. **棘轮登记同步（同批，硬约束）**：新增 `*.test.mjs` 落在 `readTestFileSet` 的扫描目录内 ⇒ 不同步即 `SUITE_MANIFEST_FILE_DRIFT`；`manifest.files` 21 → **23**、`manifest.cases` 增两条实际顶层用例数，`exceptions` **保持 `[]`**（不签新例外）。
7. **Prompt 采纳面（§8 三件事）**：① 把 `--detail` 写进权威 Skill 文档（`crctl/SKILL.md`）；② 对"需要 summary 之外字段"的真实调用点显式补 `--detail`（A10 表驱动）；③ 四个 reviewer Skill 采纳 `complete=false` 的取证完整性规则（AC-16：`complete=false` 不得作为充分门禁证据，作最终判断前必须继续按 `offset/limit` 切片取证或走逃生阀）。`pipeline-templates/*.pipeline.json` 只改 **prompt 文本**，零节点/零结构变化。
8. **导航面**：README 只增权威入口链接（不复刻 policy / 能力矩阵）；ARCHITECTURE 按 §8 维护规则增 §1 一条组成面 + §3 两条代码地图，**§4/§5/§6 不改**。
9. **不新增平行开关**：不新增 `--output json` / `--verbose` / `--pretty`；不优化 crctl 运行时小文件读取；不建字段/错误码事实页（FR-9 候选，`scope_out`）。

## 4. 验收条件

1. `node --test --test-reporter=dot skills/shared/crctl/scripts/test/crctl-summary.test.mjs skills/shared/crctl/scripts/test/caller-contract.test.mjs` exit 0。
2. `node skills/shared/crctl/scripts/test/suite-gate.mjs --run` exit 0 且 `files_executed=23` / `failures=0` / `exceptions_count=0`（棘轮同步前后均绿由 `crctl test` 的 `cmd-01` 覆盖）。
3. 逐命令比对：被投影命令默认输出 = compact summary；加 `--detail` 与金样本三层等价；退出码不变；错误码与错误体不变（`fail()` 出口零语义变更）。
4. `crctl git diff --name-only <tools base> -- skills/shared/crctl/scripts/crctl.mjs` 的改动行数 ≤ 10 且被删行不含 `fail(` / `passCondition` / `reviewLoop` / `stateMachine` / `approvalStages` / `protectedPaths`。
5. A10 表：扫描面内每一处 (b) 类调用与显式表一致、(c) 类调用都带 `--detail`；`git diff` 中命中的 `agents/*.md` 与 `pipeline-templates/*.pipeline.json` 落点与表一致（未命中则相应文件零 diff）。
6. `node -e "..."` 的 `SUMMARY_PROJECTORS` 键集与 `evidence/ac10-selection.json.minimalSet` 全等（由 TASK-01 的 `verify-selection` 机械核对）。

## 5. 完成标志

- 上述文件全部落盘并提交；验收条件 1~6 的实测命令与结果记入 TASK 完成记录（含金样本采集的**时间点早于**投影实现的事实）。
- 明确登记 A10 表的最终结论（哪些文件命中、哪些记"无需动作"、哪些需 `--detail`），并说明扫描面外真实调用方的逐条判定。
- `tasks/_index.yml` 本 TASK 标 `done`。
- **不**包含：`output-guard/**`、`skills/shared/metrics/**`、`../multica`、任何 `pipeline-templates/**` 的结构变化、任何新增 flag 或错误码。

## 6. 接口契约

**产出（供 TASK-02 CI 面 / 评审与后续调用方消费）**

```ts
// skills/shared/crctl/scripts/lib/summary-projectors.mjs
export const SUMMARY_PROJECTORS: Record<string, (obj: unknown) => unknown>;
// 键集合 = TASK-01 baseline 的 A8 最小命令集合（verify-selection 逐项比对，不一致即非零退出）
// 每个值：纯函数，输入成功出口对象、输出 compact summary 对象；不读全局状态、不访问文件系统
```

```text
skills/shared/crctl/scripts/crctl.mjs（仅三处落点 + 一行 import）
  main():            ACTIVE_PROJECTION ← resolveProjection(cmd, flags)   // detail=true → null；未注册 → null
  ok(obj):           const out = ACTIVE_PROJECTION ? ACTIVE_PROJECTION(obj) : obj;
                     process.stdout.write(JSON.stringify(out, null, 2) + '\n')
  parseArgs(argv):   if (a === '--detail') { flags.detail = true; continue; }   // 布尔专用分支，不消费后随 token
  HELP:              一行说明 --detail
  CLI 契约：crctl <命令> [--detail]；未投影命令 + --detail ≡ 现状；退出码与错误面零变化
```

**消费（本 TASK 依赖的上游）**

- TASK-01：`evidence/fr8-baseline.json#crctlCommands[]` 与 `evidence/ac10-selection.json#minimalSet`（投影键集的唯一来源；基线之前不得预设集合）。
- `dep-6`：`ok(obj)` 单一成功漏斗（45 调用点）、247 个 `fail()` 出口、`parseArgs` 的通用取值行为（本 TASK 的改动面依据）。
- `dep-13`：`readTestFileSet` 只收 `skills/shared/crctl/scripts/test/*.test.mjs`，磁盘集合 ≡ `manifest.files`（棘轮同步义务）。
- `dep-14`：既有事务夹具与断言工具（金样本采集的复用对象）。
- `dep-20`：`lint-prompts` 的 R7~R13 规则集（**不含**未知 flag 校验 ⇒ 新 `--detail` 不触发漂移，但"未被采纳"只能由本 TASK 的表兜住）。
- `dep-21`：四个 reviewer Skill 的现有 crctl 调用面与字段消费（A10 表的主体）。

---
id: CR-2026-075-TASK-05
type: TASK
cr-ref: CR-2026-075
plan-ref: "change-requests/CR-2026-075/plan.md"
sdd-ref: "change-requests/CR-2026-075/sdd.md"
target-version: 0.48
title: 竞品业务入口与确定性转换
slug: competitive-report-command-and-transform
status: pending
estimate: 8h
depends-on: [CR-2026-075-TASK-03, CR-2026-075-TASK-04]
created: 2026-10-03T00:15:00+08:00
---

## 任务描述

实现竞品专用受控写入入口 `crctl competitive-report` 与版本化确定性转换模块 `lib/competitive-report.mjs`（FR-09、FR-11、FR-08 的竞品同构面；SDD §2.3/§2.4/§3.1/§4.3/§4.4/§4.5）。目标：Skill 已确认的竞品 payload 经单一命令落盘为报告 + 竞品主文件 `updates[]` + reports 索引三项一致产物；覆盖策略显式、重放幂等、冲突不静默覆盖。本 TASK 与 TASK-04 共享 `crctl.mjs` 的 `cmdBusinessEntry` 骨架、`recoverBusinessLedgerCommand` 与分派面：**实现产出依赖 TASK-04 在前**（唯一骨架与业务恢复 helper 由 TASK-04 落地，本 TASK 只追加 `kind='competitive'` 分支，禁止复制），两任务顺序编辑同一文件；两条业务意图互不依赖。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/competitive-report.mjs`（新增）— 纯函数转换模块，零第三方依赖，复用 `yaml-subset.mjs`。
- `skills/shared/crctl/scripts/crctl.mjs` — `main()` 的 `competitive-report` 特判派发与 `cmdBusinessEntry` 的 `kind='competitive'` 分支（复用 TASK-04 落地的骨架与错误优先级，不复制骨架）。
- `skills/shared/crctl/scripts/test/competitive-report.test.mjs`（新增）。
- `skills/shared/crctl/scripts/test/crctl.test.mjs` — 业务入口域内竞品用例（B9～B13、B16 落点之一）。
- `skills/shared/crctl/scripts/test/gate-registry.json` — `manifest.files` 登记 `competitive-report.test.mjs` 与 `manifest.cases` 基线（`dep-26`）。

## 实现要点

- 命令面（SDD §3.1）：`crctl competitive-report --from <confirmed-payload.json> [--workspace <project-root>]`；不接 `cr_id` 位置参数；`--workspace` 在绑定环境下可省略（TASK-01 归一），无绑定时缺省 `WORKSPACE_REQUIRED`；未登记旗标 → `BAD_ARGS`。派发位置与 TASK-04 相同（`requireExplicitWorkspace`/`bindTaskWorkspace` 之后、`detectWorkspace`/`loadGates` 之前），不注册 summary 投影（`PROJECTED` 不含新命令）。
- payload 校验（SDD §2.3 竞品表逐字）：`schema = ai-first.competitive-report/v1`；`confirmed` 必须 `true`（否则 `BUSINESS_CONFIRMATION_REQUIRED` 零写入）；`competitor_id` 必须已在竞品索引中登记（`dep-18` 错误处理口径）；`report_date` 匹配 `^\d{4}-\d{2}-\d{2}$` 且是确认时确定的身份日期、**不**与本次执行时钟比对；`title`/`sources[]`/`body`；`updates[]` 每条 `{date,title,source,summary}`，`(date,title)` 为去重键；`conflict_strategy ∈ {overwrite, new-date}`，报告文件已存在时必须显式给出，缺失 → `BUSINESS_CONFIRMATION_REQUIRED`；`path` 必填（POSIX，必须等于 §2.4 推导路径，否则 `BUSINESS_WRITE_SCOPE_DENIED`）；可选 `index_path` 与推导路径不一致 → `BUSINESS_WRITE_SCOPE_DENIED`（不参与 `intentDigest`）。类型/枚举/日期/形态不符 → `BUSINESS_INPUT_INVALID`。
- 路径权威（SDD §2.4）：`compRoot` = `dir-graph.yaml#knowledge-docs.subdirs.competitive.path`（存在时）→ 否则合同默认 `docs/competitive`；报告 `<compRoot>/reports/{competitor-id}-{YYYY-MM-DD}.md`、竞品主文件 `<compRoot>/{competitor-id}.md`、索引 `<compRoot>/reports/_index.yml`；真实路径包含检查；同目录 `_index.yml` 与 `_index.yaml` 并存 → `BUSINESS_WRITE_SCOPE_DENIED`；索引不存在时由本次写入创建。
- 转换（SDD §4.4，纯函数）：`buildCompetitiveReport(input, current) -> { reportText, mainText, indexText, identity, artifacts } | TxError`。报告 frontmatter 含 `addedAt = beijingIso(now)`，`reportDate` 取已确认 `report_date`（不重算）；竞品主文件只重写 `updates[]` 条目集合、正文逐字保留；`(date,title)` 已存在则跳过（既不重复写、也不因 source/summary 变化替换）；reports 索引按 `reportDate` 倒序重排并置 `status: new`；报告/主文件/索引已存在时 `addedAt`/`updated` 等自动审计时间从既有文件逐字继承（§4.5.3），仅目标不存在时用执行时钟。YAML 读写经 `yaml-subset.mjs`，块定位失败/字段缺失/跨行正则不匹配一律硬失败（工程纪律 #1）。
- 幂等与判定顺序（SDD §4.5，骨架复用 TASK-04）：`intentDigest` 键集 = `{v:1, kind:"competitive", competitorId, reportDate, reportPath, mainPath, indexPath, title, sources[], body, updates[]（payload 顺序）, conflictStrategy}` → canonical JSON → `sha256`；`businessTxKey('competitive', 项目根, 身份串 = competitorId + '/' + reportDate)`；journal 落 `{deriveInstallRoot(项目根)}/.crctl/transactions/ledger/{key}`。第 2～4 步不得调换：锁内同意图恢复（TASK-03 的原语 `expect` + `sampleCommitState`，经 TASK-04 落地的唯一 `recoverBusinessLedgerCommand` 承载，不复制比对实现）→ 现场分类（`firstWrite` = 该 `report_date` 报告不存在且 reports 索引无该日期条目；`presentSame`/`presentDifferent`；`inconsistent` = 报告与 reports 索引不一致 → `TX_RECOVERY_CONFLICT`）→ 完成提交定位与 `C..HEAD` 校验 → 第 4 步：`presentDifferent` + `conflict_strategy=overwrite` + `confirmed=true` → 合法覆盖（以当前报告文件为 before，`changed=true` 新提交）；`presentDifferent` + `new-date` 且该日期报告已存在 → `BUSINESS_INTENT_CONFLICT`；其余差异 → 原冲突码失败，返回不成功。
- 提交与回执（SDD §2.3/§4.3 第 7 步）：`beginLedgerTransaction`（`writes` 含报告、竞品主文件、索引三路径）→ `controlledGit add`（仅推导路径）→ staged 集合恒等 → commit（`[cr] competitive-report {身份}` + `AI-First-Tx: <txId>` + `AI-First-Intent: <intentDigest>`）→ 提交后复核（恰一条命中且等于 HEAD）→ `finishLedgerTransaction` → `auditLog` → `ok(回执)`。成功回执前置 = 该 key 无残留 journal（同 TASK-04 的两出口约束）。CAS 语义（`tracked-clean` + 调用前 SHA）逐字沿用 `dep-10`。
- 边界：不推进 CR 状态、不写审批、不读 `specs/`；不因 `source`/`summary` 变化替换既有 `updates[]` 条目；不新增 `rules.json` 提交形态（DEC-5）。

## 验收条件

1. 在 tools CR worktree 根执行证据命令 `cmd-03`（plan §6.2 原样：repo=tools、cwd=`.`、executable=`node`、args=`["--test","skills/shared/crctl/scripts/test/competitive-report.test.mjs"]`、timeout=600）：全绿。真实运行范围 = 新增单文件（同目录、`node --test`）；观测竞品入口的命令面、范围拒绝、确认与冲突、首次写入出口、重放与第三值、CAS 与中断恢复。新增覆盖：
   - B15-b（B-02 合法覆盖）：报告已存在 + 新正文 + `conflict_strategy=overwrite` + `confirmed=true` → exit=0、`changed=true`、新提交；同 payload 再调 → `changed=false`、同一提交；缺 `conflict_strategy` → `BUSINESS_CONFIRMATION_REQUIRED` 零写入；`new-date` 指向已存在日期 → `BUSINESS_INTENT_CONFLICT` 零写入。
   - B15-c（B-06 首次写入出口）：`new-date` 指向尚不存在日期 → exit=0、`changed=true`、`identity`/`artifacts` 取已确认身份与推导路径（`artifacts` 恰三项）、`commit` = 本次提交；首写不要求 `conflict_strategy`。
   - 业务域 B9/B10/B15/B16 的竞品侧：已确认落盘（报告 + `updates[]` 按 `(date,title)` 去重 + reports 索引倒序 `status: new`）、未确认零写入、越界与任意文件清单在业务写入前拒绝、索引唯一。
2. 在 tools CR worktree 根执行证据命令 `cmd-01`（plan §6.2 原样：`node --test skills/shared/crctl/scripts/test/crctl.test.mjs`、timeout=900）全绿，其中业务入口域用例覆盖竞品命令面/旗标袋/投影面（新命令不在 `PROJECTED`）与 `(competitor-id, report-date)` 幂等作用域。**不声称覆盖 crctl 全部子命令行为。**
3. `gate-registry.json`：`manifest.files` 含 `competitive-report.test.mjs`（与磁盘集合逐一一致），`manifest.cases` 给正整数基线（`dep-26`）；登记后执行证据命令 `cmd-11`（plan §6.2 原样：repo=tools、cwd=`.`、executable=`node`、args=`["skills/shared/crctl/scripts/test/suite-gate.mjs","--run"]`、timeout=3600）全绿：逐文件加载成功、磁盘集合 ≡ manifest 文件集、每文件顶层用例数 ≥ 基线（SDD §5.2/SDD-CLOSE-09 的聚合门禁口径）。真实运行范围 = tools `skills/shared/crctl/scripts/test/` 测试文件集合，不扩展为多仓全量。
4. 文件集检查经受控入口（argv 固定），cwd = tools CR worktree 根；`<operational-workspace>` 取 `crctl workspace inspect CR-2026-075` 的 `operationalWorkspace` 原样值：

   `node skills/shared/crctl/scripts/crctl.mjs git status --porcelain --cwd <tools-worktree> --workspace <operational-workspace>`

   断言输出仅含本 TASK 声明的五个文件。status 仅证明文件集。

## 完成标志

- `cmd-03`（含 B15-b/B15-c）与 `cmd-01` 全绿；`gate-registry.json` 清单一致且 `cmd-11` 转绿。
- 完成登记只受既有 DAG 直接前置（TASK-03、TASK-04）约束，不加其他条件：本 TASK 自身验收达成时用 `crctl task done --task CR-2026-075-TASK-05` 登记；生产者 TASK-03 按自身验收即时登记（不等待消费者），跨消费者联合向量由 TASK-04 的 B18-a 用例与本 TASK 竞品侧用例共同验证、并由 TASK-10 复跑 `cmd-02`/`cmd-03` 核对。
- `lib/competitive-report.mjs` 为纯函数模块、零第三方依赖、不反向依赖 CLI；`cmdBusinessEntry` 骨架未被复制成第二份实现（`kind` 分支共用）。
- 覆盖与重放分支互不代替：合法覆盖返回 `changed=true` 与新提交，已完成同意图重放返回 `changed=false` 与原提交。
- 产物已落盘并提交，commit 自含其新增测试与 manifest 登记；`crctl.mjs` 分派面对 TASK-04 改动保持兼容（顺序编辑，R9）。

## 接口契约

**消费**（逐字对齐 SDD 与目标仓现状）：

- TASK-03 产出的 `recoverLedgerTransaction({ root, key, currentHead, headMessage, expect, sampleCommitState })` 与取样器形态（见 TASK-03「接口契约」产出节）：本 TASK 经 TASK-04 的唯一 `recoverBusinessLedgerCommand` 同传 `expect = { inputDigest, txId }` 与 `sampleCommitState`，不另写取样或比对实现。
- TASK-04 产出的 `cmdBusinessEntry(wsRoot, flags, kind)` 骨架、`recoverBusinessLedgerCommand`、错误优先级与 `intentDigest`/`businessTxKey` 计算约定：**本 TASK 依赖 TASK-04 先落地这些唯一产出**（依赖不变量同时反映在 `depends-on` 与 `_index.yml`），本 TASK 只追加 `kind='competitive'` 分支，不改骨架与优先级顺序，不复制第二份实现。
- `beginLedgerTransaction`、`finishLedgerTransaction`、`abortLedgerTransaction`、`loadExistingJournal`、`hasLedgerTransaction`（`lib/durable-tx.mjs:486/522/517/212/458`）；`controlledGit(ws, sub, args, cwd, caller, options)`（`crctl.mjs:399`）、`gitHeadSha(ws, cwd)`（`crctl.mjs:366`）；`deriveInstallRoot`（`lib/workspace-transactions.mjs:47`）、`parseYaml`/`matchEntryBlock`（`lib/yaml-subset.mjs:284/263`）。
- 竞品落盘合同（`dep-18`）：报告 frontmatter 字段集、`updates[]` 去重、`reports/_index.yml` 倒序与 `status: new`、竞品主文件正文不变、`confirmed=true` 前零写入。

**产出**：

```text
crctl competitive-report --from <confirmed-payload.json> [--workspace <project-root>]

buildCompetitiveReport(input, current)
  → { reportText: string, mainText: string, indexText: string,
      identity: { kind: 'competitive', competitorId: string, reportDate: string, path: string },
      artifacts: [string, string, string] }   // [报告, 竞品主文件, reports/_index.yml]，POSIX 相对路径
```

- 成功回执（stdout 单一 JSON，SDD §2.3 竞品同构于规划回执）：`op = "competitive-report"`、`phase = "complete"`、`changed`、`identity`（含 `kind`/`competitorId`/`reportDate`/`path`）、`artifacts`（恰三项）、`commit`；已完成同意图重放与第 2 步 `committed` 收敛时 `commit` 为**该意图先前那次**提交（可为非 HEAD）。
- 失败错误与优先级（`SDD-CLOSE-05`）：`BAD_ARGS` → `WORKSPACE_REQUIRED`/`WORKSPACE_CONTEXT_MISMATCH` → `BUSINESS_INPUT_INVALID` → `BUSINESS_WRITE_SCOPE_DENIED` → `BUSINESS_CONFIRMATION_REQUIRED` → `TX_INPUT_CONFLICT` → `TX_LEDGER_RECOVERY_REQUIRED` → `BUSINESS_INTENT_CONFLICT` → `TX_RECOVERY_CONFLICT` → `TX_LOCK_HELD`/`CAS_CONFLICT` → `TX_GIT_FAILED`。全部非零、零业务写入或按既有结构化恢复收敛；stdout 不出现成功回执。
- 下游引用同一份完整契约：TASK-07 的调用方 SKILL 文本基线（`write-competitive-report` 调用面）与本 TASK 回执逐字一致，TASK-08 的调用登记与矩阵登记引用同一条命令面，均不得缩写。

---
id: CR-2026-075-TASK-04
type: TASK
cr-ref: CR-2026-075
plan-ref: "change-requests/CR-2026-075/plan.md"
sdd-ref: "change-requests/CR-2026-075/sdd.md"
target-version: 0.48
title: 规划业务入口与确定性转换
slug: planning-entry-command-and-transform
status: pending
estimate: 12h
depends-on: [CR-2026-075-TASK-03]
created: 2026-10-03T00:15:00+08:00
---

## 任务描述

实现规划专用受控写入入口 `crctl planning-entry` 与版本化确定性转换模块 `lib/planning-entry.mjs`（FR-08、FR-09、FR-10；SDD §2.3/§2.4/§3.1/§4.3/§4.4/§4.5）。目标：Skill 已确认的规划 payload 经单一命令落盘为正式规划文档 + 规划索引，多文件一致性与幂等/重放/冲突全部由既有 ledger 事务 envelope 承载；业务确认、路径范围与身份日期不由执行时钟重算。本 TASK 不接 CR-ID、不加载状态机/gates。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/planning-entry.mjs`（新增）— 纯函数转换模块，零第三方依赖，复用 `yaml-subset.mjs`。
- `skills/shared/crctl/scripts/crctl.mjs` — `main()` 中按 `kb` 特判先例派发 `planning-entry`；`cmdBusinessEntry(wsRoot, flags, kind)` 骨架与提交定型（本 TASK 落地 `kind='planning'` 分支；TASK-05 顺序追加 `kind='competitive'`，同一份骨架不复制）；新增业务恢复 helper `recoverBusinessLedgerCommand(wsRoot, key, { inputDigest, txId })`（唯一承载业务 `expect` 锁内比对与取样器传参，TASK-05 复用、不复制；既有 `recoverLedgerCommand(ws, key)` 保持两参无 `expect` 不动）。
- `skills/shared/crctl/scripts/test/planning-entry.test.mjs`（新增）。
- `skills/shared/crctl/scripts/test/crctl.test.mjs` — 业务入口域内用例（B9～B13、B16 落点之一）。
- `skills/shared/crctl/scripts/test/gate-registry.json` — `manifest.files` 登记 `planning-entry.test.mjs` 与 `manifest.cases` 逐文件基线（`dep-26`）。

## 实现要点

- 命令面（SDD §3.1）：`crctl planning-entry --from <confirmed-payload.json> [--workspace <project-root>]`；不接 `cr_id` 位置参数；`--workspace` 在绑定环境下可省略（TASK-01 归一），无绑定时缺省 `WORKSPACE_REQUIRED`；只接受 `--from`/`--workspace`，任何未登记旗标 → `BAD_ARGS`（旗标袋语义沿用 `dep-4`）。派发位置：`requireExplicitWorkspace`（及 `bindTaskWorkspace`）之后、`detectWorkspace`/`loadGates` 之前，因此不要求项目根存在 `change-requests/`、不加载状态机与 gates；不注册 summary 投影（`PROJECTED` 不含新命令，默认即完整字段）。
- payload 校验（SDD §2.3 规划表逐字）：`schema = ai-first.planning-entry/v1`；`confirmed` 必须 `true`（否则 `BUSINESS_CONFIRMATION_REQUIRED` 零写入）；`id = {YYYY-MM-DD}-{slug}` 必填且其 `{slug}` 段必须等于 `slug`（`^[a-z0-9][a-z0-9-]*$`，`dep-14`）；`title` 非空；`target_version` 为 `MAJOR.MINOR[.PATCH]` 或 `unassigned`，经 `normalizeTargetVersion` 规范化后持久化（输入可带 v/V）；`owner` 非空、缺省 `product-owner`；`body` 读入后先做 `\r\n → \n` 规范化；`path` 必填（POSIX 分隔符，必须等于 §2.4 推导路径，否则 `BUSINESS_WRITE_SCOPE_DENIED`）；可选 `index_path` 只用于一致性核对、不参与 `intentDigest`。字段类型/枚举/日期/版本/形态不符 → `BUSINESS_INPUT_INVALID`。
- 路径权威（SDD §2.4，单一解析顺序）：`docsRoot` = `dir-graph.yaml#knowledge-docs.subdirs.product-planning.path`（存在时）→ 否则合同默认 `docs/product-planning`；目标文档 `<docsRoot>/{YYYY-MM-DD}-{slug}.md`、索引 `<docsRoot>/_index.yml`。相对路径必须落在项目根内（真实路径包含检查，不用字符串前缀）；同目录同时存在 `_index.yml` 与 `_index.yaml` → `BUSINESS_WRITE_SCOPE_DENIED`（不双写、不改名）；索引不存在时由本次写入创建。payload 的 `path`/`index_path` 只用于比对，不参与摘要。
- 转换（SDD §4.4，纯函数）：`buildPlanningEntry(input, current) -> { docText, indexText, identity, artifacts } | TxError`。`id` 取 `input.id`（已确认身份，不由执行时钟重算）；`docPath = join(docsRoot, id + '.md')`；frontmatter = DESIGN-DOC 字段集（`dep-16`）+ `created`/`updated` = `beijingDate(now)`；`body` 原文（不重排、不补写）；`indexText` 在现有 index 实体块中按 id 追加/更新条目（`created-at = beijingIso(now)`）；`created`/`updated`/`created-at` 属自动审计时间——目标文档/索引已存在时从既有文件逐字继承（§4.5.3），仅目标不存在时用执行时钟；同 id 不同已确认内容（slug 冲突）不覆盖，由 Skill 按原 slug 冲突规则追加短 hash 形成新身份后重新确认（§4.5 第 4.a 步）。YAML 读写经 `yaml-subset.mjs`：块定位失败、字段缺失、跨行正则不匹配一律硬失败（工程纪律 #1）。
- 骨架（SDD §4.3 七步，`cmdBusinessEntry`）：1 语法解析（`--from` 必填且可读）→ 2 可信项目根（`realpath(--workspace 或绑定归一值)`，项目根内解析 `dir-graph`）→ 3 业务字段 → 4 范围校验（推导路径 + 真实路径包含）→ 5 确认与冲突策略（`confirmed===true`）→ 6 意图摘要与幂等/恢复（`intentDigest` + `businessTxKey`；在途事务经本 TASK 新增的 `recoverBusinessLedgerCommand` 在锁内比对期望摘要与 txId、并以锁内现场取样判定 Git 完成事实后收敛（既有 `recoverLedgerCommand(ws,key)` 保持两参无 `expect` 不动））→ 7 事务与提交。首失败即唯一结果；第 1～5 步与第 6 步锁内期望比对零业务写入。
- 幂等与判定顺序（SDD §4.5）：`intentDigest` 按 §4.5.1 的固定键集 `{v:1, kind:"planning", id, docPath, indexPath, title, source, targetVersion, owner, body}` 做 canonical JSON（键字典序、数组保序、UTF-8）后取 `sha256` 64 位十六进制；不含执行时钟时间字段与事务 id。`businessTxKey('planning', 项目根, 身份串=id) = 'biz-planning-' + sha256('v1|' + realpath(项目根) + '|' + 身份串).slice(0,32)`，journal 落在 `{deriveInstallRoot(项目根)}/.crctl/transactions/ledger/{key}`。第 2～4 步按 §4.5.4 不得调换：锁内同意图恢复（`expect={inputDigest, txId: pre?.journal.txId ?? null}` + 锁内取样，统一走 TASK-03 的原语）→ 现场分类 `firstWrite`/`presentSame`/`presentDifferent`/`inconsistent`（`inconsistent` → `TX_RECOVERY_CONFLICT` 零写入）→ 完成提交定位（`git log --oneline --fixed-strings --grep='AI-First-Intent: <intentDigest>' -- <relPaths…>`，0 条 → C=null，>1 条 → `TX_RECOVERY_CONFLICT`；唯一命中经 `git rev-parse --verify` 规范化为 40 位）→ `C..HEAD` 对关联路径为空校验（非空 → `TX_RECOVERY_CONFLICT`）→ 已完成重放返回 `changed=false` + 原提交 C；`presentDifferent` → `BUSINESS_INTENT_CONFLICT`（同身份不同已确认内容、无覆盖策略）；`firstWrite` → 第 5 步。
- 提交与回执（SDD §2.3/§4.3 第 7 步）：`beginLedgerTransaction({ root: installRoot, targetRoot: 项目根, key, inputDigest: intentDigest, writes, headBefore: gitHeadSha(项目根), commitRequired: true })` → `controlledGit add`（仅推导路径）→ staged 集合恒等 → commit（消息三行：`[cr] planning-entry {身份}` + `AI-First-Tx: <txId>` + `AI-First-Intent: <intentDigest>`）→ 提交后复核（重跑完成提交定位，恰好一条命中且其 40 位等于 `git rev-parse HEAD`，否则 `TX_RECOVERY_CONFLICT`）→ `finishLedgerTransaction` → `auditLog` → `ok(回执)`。成功回执前置 = 该 key 无残留 journal：`committed` 分支与第 5 步两个出口都要求 `hasLedgerTransaction(root, key) === false`；收敛后仍残留 → `TX_RECOVERY_CONFLICT`（不返回成功）。`tracked-clean` 前置与 `expectedHash` 取调用前 SHA 的 CAS 语义逐字沿用 `dep-10`。
- 边界：不推进 CR 状态、不写审批、不读 `specs/`、不读 cwd、不读历史评论、不用 `input.now` 推身份；回执只含业务身份、路径、提交 SHA，不输出环境变量或 token。

## 验收条件

1. 在 tools CR worktree 根执行证据命令 `cmd-02`（plan §6.2 原样：repo=tools、cwd=`.`、executable=`node`、args=`["--test","skills/shared/crctl/scripts/test/planning-entry.test.mjs"]`、timeout=600）：全绿。真实运行范围 = 新增单文件（同目录、`node --test`）；观测规划入口的命令面、范围拒绝、确认与冲突、首次写入出口、重放与第三值、CAS 与中断恢复。新增覆盖：
   - B15-a（B-01 跨日身份）：注入固定执行时钟，同一 payload 在 D/D+1/D+2 三个日历日各跑一次 → 三次 `identity.id`/`docPath`/`artifacts` 与 `intentDigest` 逐字相同；D+1 首次落盘后 D+2 重放 `changed=false` 且 `commit` 等于 D+1 的提交。
   - B15-c（B-06 首次写入出口）：无目标文档、无 journal、无完成提交 → exit=0、`changed=true`、`identity`/`artifacts` 取已确认身份与推导路径、`commit` = 本次提交；断言不出现 `BUSINESS_INTENT_CONFLICT`/`TX_RECOVERY_CONFLICT`，且首写不要求 `conflict_strategy`。
   - B18-a（B-04 完成提交定位与第三值）：规划 A 完成 → 规划 B 完成并更新共享 `_index.yml` → 重放 A 不得返回 B 的提交，按 §4.5 第 3.c/3.d 步归入 `TX_RECOVERY_CONFLICT`；A 的完成提交仍由 `AI-First-Intent` 唯一命中；另测「A 提交后另有提交时恢复」返回 `committed` 而非回滚。
   - 业务域 B9/B10/B15/B16 的规划侧：已确认落盘字段/章节/索引唯一、无合同不创建索引、未确认零写入、越界与任意文件清单在业务写入前拒绝。
2. 在 tools CR worktree 根执行证据命令 `cmd-01`（plan §6.2 原样：`node --test skills/shared/crctl/scripts/test/crctl.test.mjs`、timeout=900）全绿，其中业务入口域用例覆盖命令面/旗标袋/投影面（新命令不在 `PROJECTED`）与 `intentDigest` 的跨日不变性。**不声称覆盖 crctl 全部子命令行为。**
3. `gate-registry.json`：`manifest.files` 含 `planning-entry.test.mjs`（与磁盘集合逐一一致），`manifest.cases` 给该文件正整数基线（`dep-26`）；登记后执行证据命令 `cmd-12`（plan §6.2 原样：repo=tools、cwd=`.`、executable=`node`、args=`["skills/shared/crctl/scripts/test/suite-gate.mjs","--run"]`、timeout=3600）全绿：逐文件加载成功、磁盘集合 ≡ manifest 文件集、每文件顶层用例数 ≥ 基线（SDD §5.2/SDD-CLOSE-09 的聚合门禁口径）。真实运行范围 = tools `skills/shared/crctl/scripts/test/` 测试文件集合，不扩展为多仓全量。
4. 文件集检查经受控入口（argv 固定），cwd = tools CR worktree 根；`<operational-workspace>` 取 `crctl workspace inspect CR-2026-075` 的 `operationalWorkspace` 原样值：

   `node skills/shared/crctl/scripts/crctl.mjs git status --porcelain --cwd <tools-worktree> --workspace <operational-workspace>`

   断言输出仅含本 TASK 声明的五个文件。status 仅证明文件集。

## 完成标志

- `cmd-02`（含 B15-a/B15-c/B18-a）与 `cmd-01` 全绿；`gate-registry.json` 清单一致且 `cmd-12` 转绿。
- `lib/planning-entry.mjs` 为纯函数模块、零第三方依赖、不反向依赖 CLI（`dep-24` §3）；`crctl.mjs` 只承担参数/范围校验、事务与回执。
- 提交形态未新增：只用既有 `[cr] ` 前缀与 `AI-First-Tx`/`AI-First-Intent` trailer；`rules.json#protectedPaths`/commit 白名单零改动。
- 产物已落盘并提交，commit 自含其新增测试与 manifest 登记；不夹带 TASK-05 的竞品分支（`crctl.mjs` 分派面顺序编辑，R9）。

## 接口契约

**消费**（逐字对齐 SDD 与目标仓现状）：

- TASK-03 产出的 `recoverLedgerTransaction({ root, key, currentHead, headMessage, expect, sampleCommitState })` 与取样器形态（见 TASK-03「接口契约」产出节）：本 TASK 新增私有 `recoverBusinessLedgerCommand`，由它同传 `expect = { inputDigest, txId }` 与 `sampleCommitState`（不得另写第二套取样或比对实现）；既有 `recoverLedgerCommand(ws, key)` 保持两参无 `expect` 不动，本 TASK 不修改其签名与五位既有调用者。
- `beginLedgerTransaction({ root, targetRoot, key, inputDigest, writes, headBefore, commitRequired })`、`finishLedgerTransaction(tx)`、`abortLedgerTransaction(tx)`、`loadExistingJournal({ root, op, cr, key, inputDigest })`、`hasLedgerTransaction({ root, key })`（`lib/durable-tx.mjs:486/522/517/212/458`）。
- `controlledGit(ws, sub, args, cwd, caller, options)`（`crctl.mjs:399`）与 `gitHeadSha(ws, cwd)`（`crctl.mjs:366`）；Git 形态限 `rules.json` 既有白名单（`add`/`commit`/`log`/`rev-parse` 的已声明 shape），不新增形态。
- `deriveInstallRoot(opWs)`（`lib/workspace-transactions.mjs:47`）、`normalizeTargetVersion(raw, { allowUnassigned })`（同文件 `:179`）、`parseYaml`/`matchEntryBlock`（`lib/yaml-subset.mjs:284/263`）。
- `parseArgs(argv)` 与 `main()` 装配顺序（`crctl.mjs:3786-3792`）：新命令按 `kb` 特判先例派发。

**产出**：

```text
crctl planning-entry --from <confirmed-payload.json> [--workspace <project-root>]

buildPlanningEntry(input, current)
  → { docText: string, indexText: string,
      identity: { kind: 'planning', id: string, path: string },
      artifacts: [string, string] }   // [规划文档, docsRoot/_index.yml]，POSIX 相对路径
```

- 新增私有 helper（业务恢复唯一比对点）：`recoverBusinessLedgerCommand(wsRoot, key, { inputDigest, txId })`，内部对 `recoverLedgerTransaction` 同传 `expect` 与 `sampleCommitState`；不被既有子命令调用（SDD §9 `zero_diff` 第②类）。

- 成功回执（stdout 单一 JSON，逐字满足 SDD §2.3）：

```json
{
  "op": "planning-entry",
  "phase": "complete",
  "changed": true,
  "identity": { "kind": "planning", "id": "2026-10-02-x", "path": "docs/product-planning/2026-10-02-x.md" },
  "artifacts": ["docs/product-planning/2026-10-02-x.md", "docs/product-planning/_index.yml"],
  "commit": "<40-hex>"
}
```

- 失败错误与优先级（`SDD-CLOSE-05` 逐字）：`BAD_ARGS` → `WORKSPACE_REQUIRED`/`WORKSPACE_CONTEXT_MISMATCH` → `BUSINESS_INPUT_INVALID` → `BUSINESS_WRITE_SCOPE_DENIED` → `BUSINESS_CONFIRMATION_REQUIRED` → `TX_INPUT_CONFLICT` → `TX_LEDGER_RECOVERY_REQUIRED` → `BUSINESS_INTENT_CONFLICT` → `TX_RECOVERY_CONFLICT` → `TX_LOCK_HELD`/`CAS_CONFLICT` → `TX_GIT_FAILED`。全部非零、零业务写入或按既有结构化恢复收敛；stdout 不出现成功回执。
- 下游引用同一份完整契约：TASK-05 的 `cmdBusinessEntry(kind='competitive')` 复用骨架与错误优先级，TASK-07 的 SKILL 文本基线（`write-planning-entry` 调用面）与本 TASK 回执逐字一致，TASK-08 的调用登记引用同一条命令面，均不得缩写。

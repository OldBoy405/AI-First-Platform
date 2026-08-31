---
id: CR-2026-057-sdd
type: SDD
cr-ref: CR-2026-057
title: CR 全生命周期最小改造 — 评审闭合、范围冻结、覆盖矩阵与版本事实统一 技术设计
target-version: unassigned
status: draft
created: 2026-08-31T18:30:00+08:00
updated: 2026-08-31T18:30:00+08:00
---

# 1. 架构概览

## 1.1 目标仓与改动面

目标仓：sibling `../tools/`（Skill、模板、`crctl`、README、回归测试）。knowledge-base 只承载本 CR 过程文档（PRD 已落、本 SDD）；`../multica/` 无实施改动（PRD §7 范围排除）。

实施改动收敛为四个面，全部在既有文件内做增量（不新增 Agent、Pipeline、状态、review ledger、事务框架）：

| 面 | 文件 | 性质 |
|---|---|---|
| A. crctl 执行器 | `skills/shared/crctl/scripts/crctl.mjs`、`skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | 版本规范化纯函数、`register` 硬校验、`writeback-apply` 版本守卫、新子命令 `version-set`、`crctl test` 机器区 `skipped` 字段 |
| B. Skill 提示词合约 | 4 个 `review-*` SKILL.md、`write-tech-design`、`write-dev-plan`、`write-dev-tasks`、`write-requirement-prd`、`requirement-register`、`write-test-report`、`implement-code`（一句） | P0-1 评审闭合、FR-3 前缀、批准范围核对、覆盖矩阵、流程控制 TASK 禁止、版本继承、skip 语义 |
| C. 文档模板与人读文档 | `skills/shared/engineering-docs/templates/SDD-template.md`、`README.md`、`ARCHITECTURE.md`（一句增量） | 批准范围章节、版本规则人读同步、crctl 新写入子命令登记 |
| D. 回归测试 | `skills/shared/crctl/scripts/test/`（crctl.test.mjs 增用例；register-tx/writeback-tx/merge-fixture/test-cr 夹具适配） | FR-12/14/15/16 正负向量，既有用例不失败 |

## 1.2 依赖方向（不变）

```
使用方仓库 → Pipeline → Skill → crctl（状态与账本唯一写入执行器）
```

本设计新增的全部执行逻辑位于 crctl 层（`crctl.mjs` 与 `workspace-transactions.mjs`）；Skill 只改"读什么、写什么、调用哪个 crctl 子命令、前后置条件"，不获得任何新的账本写入口。lib 不反向依赖 CLI，纯函数 `normalizeTargetVersion` 落 lib 层供 `crctl.mjs` 与测试单测共用，不形成第二命令入口。

## 1.3 关键流程与状态机口径

CR 生命周期流程（注册 → 需求 → 设计 → 计划/任务 → 编码/测试 → 代码评审 → merge → writeback → archive）不变。本设计不触碰 `dir-graph.yaml#change-request-track.state_machine` 与 `skills/shared/crctl/gates.json`——状态机口径保持既有 **15 个具名状态 + 注册前 `(new)`、28 条声明转移 / wildcard 展开 50 条**，本 CR 不新增状态、不新增转换（PRD B-001 结论）。

版本事实链（P1-1）为三条既有命令 + 一条新命令：

```text
register --target-version <v>（必填，规范化落 cr.md/backlog）
  → PRD/SDD/PLAN/TASK 各产物继承 cr.md 值（Skill 契约）
  → version-set --to <real-version>（唯一更正入口：unassigned → 真实版本，原子同步全链）
  → writeback-apply --target-version <v>（入口版本守卫：与 cr.md 规范化全等才放行）
```

评审闭合链（P0-1）：四个 `review-*` Skill 首轮完成全部适用维度（review-dev-plan/review-code 先核对 SDD 批准范围），FR-3 固定前缀使每轮旧 blocker 状态、新 blocker、范围外发现可机械区分；回修逐条可重验（FR-4）。

## 1.4 模块边界

- `workspace-transactions.mjs`：新增导出 `normalizeTargetVersion`（纯函数）；`registerCr` 顶部校验；`applyWritebackAtomic` 顶部版本守卫；`runTestPlan`/`renderTestMachineReport` 计算并渲染 `skipped`。复用既有 `resolveOperationalWorkspace`（只读）、`canonicalWritebackBusinessInput`、`loadOrCreateJournal`、`prepareWritebackCandidate`。
- `crctl.mjs`：dispatch 新增 `case 'version-set'`；`cmdRegister` 参数面调整；HELP 文本补行。`version-set` 复用 `cmdOwnerSet` 的 durable ledger 事务骨架（`recoverLedgerCommand`/`beginLedgerCommand`/tracked-clean 前置/受控 git add-commit/回滚）。
- Skill 文档层：只改业务判断与输出约束（FR-1：不改状态机、不改 `review-record` schema 必填字段集、不改 attempt 账本）。

---

# 2. 数据模型

## 2.1 版本值域与规范化（FR-12/FR-14/FR-15 共用）

`normalizeTargetVersion(raw, { allowUnassigned = true } = {})` — 纯函数，落 `workspace-transactions.mjs`：

```text
输入: raw 字符串
1. 缺省或非 string → { ok: false, reason: 'missing' }
2. Unicode trim（与 JS String.prototype.trim 相同）后为空 → { ok: false, reason: 'empty' }
3. trim 后对 ASCII 字母 toLowerCase → token
4. token ∈ 禁止同义值集合 → { ok: false, reason: 'forbidden' }
   集合冻结为 11 项：tbd、n/a、na、n.a.、pending、none、unknown、todo、wip、null、undefined
5. token === 'unassigned'：
   allowUnassigned=true → { ok: true, value: 'unassigned' }
   allowUnassigned=false → { ok: false, reason: 'unassigned-not-allowed' }
6. 真实版本候选：trim 后（大小写折叠前）以单个 v/V 开头则剥掉恰好一个前缀；
   剩余必须整串匹配 ^(0|[1-9]\d*)\.(0|[1-9]\d*)(\.(0|[1-9]\d*))?$
   通过 → { ok: true, value: 剥前缀后的规范串 }（v0.30→0.30，0.1.0→0.1.0）
7. 其它一律 { ok: false, reason: 'malformed' }（含 0.29-rc、latest、1、0.30.0.1、内嵌空白）
```

存储与全等比较一律用规范化值。三个调用方把 `reason` 映射为各自错误码：`register` → `REGISTER_VERSION_INVALID`；`writeback-apply` → `WRITEBACK_VERSION_INVALID`；`version-set --to` → `VERSION_SET_INVALID`。该函数是纯 string→result，无 IO，测试直接 import 单测。

## 2.2 writeback 版本守卫状态模型（FR-14）

```text
guardWritebackVersion(crMdTargetRaw, inputTargetRaw):
  a = normalizeTargetVersion(crMdTargetRaw)
  b = normalizeTargetVersion(inputTargetRaw)
  a/b 任一 !ok            → WRITEBACK_VERSION_INVALID
  a/b 任一 === 'unassigned' → WRITEBACK_VERSION_UNASSIGNED
  a !== b（均为真实版本）    → WRITEBACK_VERSION_MISMATCH
  否则                     → { ok: true, value: a }（放行，进入既有 writeback 逻辑）
```

错误优先级：版本错误 > `WRITEBACK_STATE_MISMATCH`（authority 非 Transaction Workspace）> 其它后续错误（AC-14.6 以 `status=drafting` 夹具证明）。守卫通过后，`applyWritebackAtomic` 的既有 `resolveOperationalWorkspace` → source 断言 → candidate/journal 事务原样执行；`canonicalWritebackBusinessInput` 的 `v` 前缀剥离保留（对已规范化输入无副作用，防御性兼容）。

## 2.3 version-set 事务数据（FR-15）

新账本写入子命令，op 标识 `version-set`，ledger tx key = `ledgerTxKey('version', cr)`（复用既有 durable ledger transaction，journal envelope 与 recoverable write-set 不变）。

| 项 | 值 |
|---|---|
| 输入 | `--to` 必填；`normalizeTargetVersion(raw, { allowUnassigned: false })`，结果必须是真实版本 |
| 允许状态 | `drafting`、`requirement-reviewing`、`requirement-approved`、`tech-designing`、`tech-design-review-pending`、`tech-design-reviewed`、`task-breakdown`、`developing`、`code-reviewing`、`code-approved` |
| 禁止状态 | `merging`、`writing-back`、终态 `archived`/`rejected`/`withdrawn` |
| 原子写入集 | 文件存在才纳入（不存在跳过，不算漂移）：`change-requests/{CR}/cr.md` 的 `target-version`；`_backlog.yml` 该条目 `target-version`；`prd.md`、`sdd.md`、`plan.md`、全部 `TASK-*.md` 的 frontmatter `target-version` |
| 输出 | `{ op: "version-set", cr, from, to, changed, files: [<workspace-relative paths>] }`；幂等短路 `changed=false` 零新 commit |
| 状态副作用 | 不改变 CR status（不 advance、不发 status 事件） |
| 业务错误码 | `VERSION_SET_INVALID` / `VERSION_SET_NOT_UNASSIGNED` / `VERSION_SET_STATE_INVALID` / `VERSION_SET_DERIVED_DRIFT`（PRD FR-15 已闭合，SDD 不发明） |

前置/基础设施失败复用 owner-set 同款机制与同前缀错误码族（`VERSION_SET_WORKTREE_DIRTY`、`VERSION_SET_COMMIT_FAILED`、`VERSION_SET_COMMIT_ROLLBACK_FAILED`，镜像 `OWNER_*`；不属于四条业务码，AC-15 负向向量不涉及）。

## 2.4 test-report.md 机器区 additive 字段（FR-16）

`crctl test` 机器区每条 command 增加布尔字段 `skipped`（additive，不删现有字段 `repo/cwd/executable/args/timeout-seconds/exit-code/signal/timed-out/started/log`）：

```text
skipped = (exit-code == 0) && (对应 cmd-NN.log 在 --- stdout --- 与 --- stderr --- 两段、先 \r\n→\n 规范化后，
          命中冻结模式表任一模式（大小写不敏感）)
模式表（冻结，实施期不得增删）：
  1. (^|\n)# skip\b
  2. (^|\n)ok \d+ # skip\b
  3. \bskipped:\s*[1-9]\d*
  4. \bSKIPPED\b
  5. \bno tests to run\b
```

non-zero / timeout 一律 `skipped: false`（那是失败，不是 skip）。模式是字面量正则（无用户输入），匹配即命中、不匹配即 false，不存在"解析失败需静默降级"的分支——符合 NFR-3 硬失败纪律的适用面（该纪律约束新增哈希/跨行解析代码；此处无解析失败态）。`cmd-NN` 定义不变：NN = 两位十进制，等于机器区 `commands` 列表 1-based 下标，与 `test-evidence/cmd-NN.log` 文件名全等。

## 2.5 SDD「批准范围」四字段（FR-5）

`SDD-template.md` 新增固定章节，承载且仅承载（纯文档字段，不进 crctl schema、不新增 ledger 文件、不新增状态）：

```text
scope_in:  当前 CR 必须交付的 FR/AC
scope_out: 明确排除的路径和能力
zero_diff: 明确不得改动的调用点/签名
follow_up: 发现但留给后续 CR 的缺口
```

空字段显式写 `无` 或 `N/A` 加理由，不得省略章节。

## 2.6 review 报告前缀（FR-3，Skill 文本契约，非 canonical schema 字段）

| 前缀 | 含义 | 写入位置 |
|---|---|---|
| `已解决：` | 上一轮某条 blocker 本轮已关闭 | `suggestions` |
| `部分解决：` | 上一轮某条 blocker 仍有残留 | `blockers` |
| `未解决：` | 上一轮某条 blocker 本轮仍在 | `blockers` |
| `本轮新增：` | 本轮新发现的 blocker | `blockers` |
| `范围外：` | 不在本 CR 范围，留给后续 CR | `suggestions` |

机械核对规则与对照键按 PRD FR-3 原文。承载方式复用现有临时 payload + `crctl review-record`（`verdict`/`blockers`/`dimensions`/`suggestions`），`review-record` schema 必填字段集不变。前缀强制在 Skill 文本层（决策 D-4），不在 crctl 加内容校验（FR-17：静态检查仅重复失败且规则确定时下沉）。

---

# 3. 接口契约

本 CR 无 HTTP API（PRD/SDD 不新增 HTTP 接口）→ 不编写 REST 契约。契约面为三条 CLI + 机器区字段 + 两处文档模板。

## 3.1 `crctl register`（FR-12）

| 项 | 契约 |
|---|---|
| 命令 | `crctl register ... --target-version <v>`（flag 由可选改必填；`--target-version` **不**进入 cmdRegister 必填 BAD_ARGS 循环，缺省走规范化层的 `REGISTER_VERSION_INVALID`，满足错误码契约） |
| 输入 | 必填；共用规范化（§2.1） |
| 合法 | 规范化后为 `unassigned` 或真实版本 |
| 错误码 | `REGISTER_VERSION_INVALID`（缺省、空、禁止同义值、畸形真实版本），非零退出 |
| 零写入 | 无 cr.md、无 `_backlog.yml` 新条目、无 worktree、无 register journal（校验位于 `registerCr` 顶部、`loadOrCreateJournal` 与 fetch 之前） |
| 状态副作用 | 成功则 CR `drafting`（现有）；失败不创建 CR |
| 幂等 | 同 `--registration-key` 且**规范化后**版本相同 → 现有续跑（inputDigest 改用规范化值）；版本不同 → 现有输入漂移硬阻断 `REGISTRATION_INPUT_MISMATCH`，不另造错误码 |
| JSON/stdout | 成功对象必须含 `targetVersion` 等于规范化值（`registerCr` 返回对象补该字段）；失败走现有 stderr `{error:{code,message}}` |
| 删除 | `workspace-transactions.mjs` 第 589 行 `targetVersion = input.targetVersion ?? 'tbd'` 缺省值 |

## 3.2 `crctl writeback-apply`（FR-14）

命令与既有成功路径不变（`--stage baseline|tasks|traceability --spec-id --target-version`，traceability 另需 `--milestone-file`；调用者与现有相同，非 TTY 限制）。只约束版本失败路径：

| 条件 | 错误码 | 退出 |
|---|---|---|
| 任一侧规范化失败（含空、禁止同义值、畸形、cr.md 侧缺字段/不可读） | `WRITEBACK_VERSION_INVALID` | 非零 |
| 规范化后任一侧为 `unassigned` | `WRITEBACK_VERSION_UNASSIGNED` | 非零 |
| 两侧均为真实版本但字符串不全等 | `WRITEBACK_VERSION_MISMATCH` | 非零 |
| 一致且为真实版本 | 进入现有 writeback 逻辑 | 现有 |

失败观察点（三 stage 相同，AC-14 断言）：允许 = stderr 结构化 JSON 上表之一 + 非零退出。禁止（与调用前字节级比较）＝目标 specs/delivery/traceability 文件内容变化；`.crctl/candidates/{CR-ID}/{stage}/` 被创建/删除/改写；writeback journal 被创建或改写（含 phase/inputDigest/businessInputDigest）；transaction lock 残留；operational workspace/authority 变化（source、path、cr.md status 与调用前相同）；git commit / origin push。同参重试错误码相同且无增量痕迹。

## 3.3 `crctl version-set`（FR-15，新子命令）

```text
crctl version-set <cr_id> --to <real-version>
```

| 项 | 契约 |
|---|---|
| flag | `--to` 必填（缺 flag → `BAD_ARGS`，与既有命令口径一致）；按共用规范化且结果必须是真实版本（`allowUnassigned=false`） |
| 正向 | 当前 `cr.md` 规范化值为 `unassigned` → 写入 `--to` 的规范真实版本 |
| 幂等 | `cr.md` 与全部已存在派生产物（prd/sdd/plan/TASK-*）及 backlog 条目已经等于 `--to` → `changed=false`，exit 0，零新 commit |
| 非法 `--to` | `VERSION_SET_INVALID`（畸形、禁止同义值、`unassigned`） |
| 当前不是 `unassigned` 且不等于 `--to` | `VERSION_SET_NOT_UNASSIGNED` |
| 状态不在允许集 | `VERSION_SET_STATE_INVALID` |
| 派生产物存在但其 `target-version` ≠ 当前 `cr.md` 值，或缺该字段；backlog 条目缺字段或与 cr.md 不一致 | `VERSION_SET_DERIVED_DRIFT` |
| 调用者 | 与 `owner-set` 相同，非 TTY 限制；identity 由 crctl 生成 |
| 状态副作用 | 不改变 CR status |
| JSON/stdout 成功 | `{ op: "version-set", cr, from, to, changed, files: [...] }` |
| 失败 | stderr `{error:{code,message}}`，零写入（cr.md/backlog/派生产物/git 均不变） |
| 重试 | 失败后重跑同一命令；无半成品（durable ledger transaction 保证） |

真实版本→真实版本、真实版本→`unassigned` 均不允许（前者 `VERSION_SET_NOT_UNASSIGNED`，后者 `VERSION_SET_INVALID`）。

## 3.4 `crctl test` 机器区（FR-16）

每 command 追加一行 `skipped: true|false`（§2.4 计算规则）。`review-code` 只读机器区 `skipped`/`exit-code`/`timed-out` 与覆盖矩阵 `cmd-NN`，不得自行解析各测试框架输出。

## 3.5 review payload 输出约束（FR-3）

四个 review Skill 的 `blockers[]`/`suggestions[]` 每条文本必须使用 §2.6 固定前缀之一（ASCII 全角冒号 `：`）；机械核对规则按 PRD FR-3。`review-record` schema（verdict 枚举/blockers 列表/dimensions 齐全）不变。

## 3.6 文档模板（FR-5 / FR-8）

- `SDD-template.md`：新增「批准范围」固定章节（§2.5 四字段）。
- `write-dev-plan` 的 `plan.md`：新增「AC/业务闭环覆盖矩阵」节，表头 `| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |`；关键 AC 的验收证据列必须写稳定标识 `cmd-NN`。

---

# 4. 关键算法与流程

## 4.1 normalizeTargetVersion（§2.1 实现要点）

纯函数实现，无 IO；7 步按序短路。第 6 步正则 `^(0|[1-9]\d*)\.(0|[1-9]\d*)(\.(0|[1-9]\d*))?$` 为字面量；`v` 前缀剥离在大小写折叠前对原始 trim 串执行（`v0.30`/`V0.30` 均合法，`vv0.30` 剥一个后剩 `v0.30` 不匹配 → 畸形）。返回结构 `{ ok, value? , reason? }`，禁止抛异常（调用方映射错误码）。

## 4.2 register 校验时序（FR-12）

```text
cmdRegister(ws, flags)
  → registerCr(ctx, input)                 # workspace-transactions.mjs
      1. owners/origin/year/summary 既有校验（不动）
      2. NEW: tv = normalizeTargetVersion(input.targetVersion)
         !tv.ok → throw TxError('REGISTER_VERSION_INVALID', ..., 零写入)
      3. keyHash / inputDigest = sha256({...targetVersion: tv.value...})   # 规范化值入摘要
      4. loadOrCreateJournal ...（既有事务流程原样，含 recoverCommand 用 tv.value）
      5. buildRegistrationTexts({ targetVersion: tv.value, ... })
      6. 返回对象补 targetVersion: tv.value
```

校验点（第 2 步）位于锁获取、journal、fetch、账本写之前——失败时无任何持久化痕迹，满足零写入清单。

## 4.3 writeback-apply 版本守卫时序（FR-14）

```text
applyWritebackAtomic(ctx, input)
  1. NEW: guard = guardWritebackVersion(ctx, cr, input)
       内部顺序：
       a. b = normalizeTargetVersion(input.targetVersion)
       b. opWs = resolveOperationalWorkspace(ctx, cr)      # 只读解析（无副作用）
       c. a = normalizeTargetVersion(readCrMdTargetVersion(opWs.path, cr))  # cr.md frontmatter target-version
       d. 按 §2.2 状态模型映射 WRITEBACK_VERSION_INVALID / _UNASSIGNED / _MISMATCH
     guard 失败 → throw TxError（此时 traceability replay 分支、source 断言、prepare、journal 均未执行）
  2. 既有 traceability complete-replay 分支（phase=complete && traceOutbox.state=pending 补发）——版本守卫失败不会到达
  3. 既有 resolveOperationalWorkspace → source !== 'transaction-workspace' → WRITEBACK_STATE_MISMATCH
  4. 既有 candidate/journal 事务原样（canonicalWritebackBusinessInput → loadExistingJournal → prepareWritebackCandidate）
```

守卫位于第 1 步（代码顺序先于步骤 3 的 `resolveOperationalWorkspace` 主流程调用，也先于 `prepareWritebackCandidate` 与 `loadOrCreateJournal`），因此版本错误优先于 `WRITEBACK_STATE_MISMATCH`（AC-14.6：`status=drafting` 夹具下错误码是 `WRITEBACK_VERSION_*`）；candidate 目录的 `rmSync`/`mkdir` 只在守卫通过后才可能执行（AC-14.4 观察点 2）。`resolveOperationalWorkspace` 本身只读（读 cr.md status、分类返回），在守卫内部调用不产生任何观察点 1–6 的痕迹。

cr.md 侧读取缺失/无 frontmatter/缺 `target-version` 字段 → 归一化为规范化失败（`WRITEBACK_VERSION_INVALID`），符合 PRD FR-14「任一侧规范化失败」口径。

## 4.4 version-set 事务流程（FR-15，同构 owner-set）

```text
cmdVersionSet(ws, cr, gates, flags)
  1. 缺 --to → BAD_ARGS
  2. to = normalizeTargetVersion(flags.to, { allowUnassigned: false })
     !to.ok → VERSION_SET_INVALID（零写入）
  3. await recoverLedgerCommand(ws, ledgerTxKey('version', cr))     # 断点恢复
  4. resolveCrState(ws, cr)：status 不在允许集 → VERSION_SET_STATE_INVALID
  5. tracked clean 前置（queryTrackedChanges）→ VERSION_SET_WORKTREE_DIRTY
  6. 双投影 + 派生产物漂移检查：
     - crMd.value = normalizeTargetVersion(cr.md target-version)（必须 ok）
     - backlog 条目 target-version 缺失或规范化后 ≠ crMd.value → VERSION_SET_DERIVED_DRIFT
     - 每个已存在的 prd/sdd/plan/TASK-*：frontmatter 缺 target-version 或规范化后 ≠ crMd.value → VERSION_SET_DERIVED_DRIFT
     - crMd.value ≠ 'unassigned' 且 ≠ to.value → VERSION_SET_NOT_UNASSIGNED
     - crMd.value === to.value 且全部已存在产物 === to.value → 幂等短路 ok({changed:false})（零 commit）
  7. 行级编辑纯函数 editTargetVersionLine(text, to.value)：
     - cr.md / prd / sdd / plan / TASK-*：frontmatter 内 ^target-version: 行替换（cr.md 先 \r\n→\n 规范化）
     - _backlog.yml：matchEntryBlock 条目块内 target-version 行替换（同 editBacklogSet 的行级模式）
     - 匹配不到 → fail('LEDGER_PARSE_FAILED', ...) 硬失败（纪律 #1，禁止静默返回原文）
  8. beginLedgerCommand(ws, ledgerTxKey('version', cr), writes, true)   # 写入集 = 步骤 7 的全部候选（expectedHash 取调用前 SHA）
  9. controlledGit add（仅受控路径）→ staged 复核 → commit "[cr] version-set {cr} {from} -> {to}" + AI-First-Tx trailer
     → finishLedgerTransaction → auditLog(kind:'ledger', op:'version-set', ...)
  10. 失败回滚：abortLedgerTransaction + unstage + clean 复核（owner-set 同款，错误码 VERSION_SET_COMMIT_*）
  11. ok({ op:'version-set', cr, from, to, changed:true, files:[<相对路径>] })
```

不调 `updateCrMdStatus`（status 不变）、不发 status outbox 事件、不写 approval.yml。`owner-history`/`handover-history` 不动。

## 4.5 skipped 计算（FR-16）

```text
runTestPlan 每条 command 生成 logContent 后：
  norm = logContent.replaceAll('\r\n', '\n')            # NFR-3：先规范化
  skipped = (r.status === 0) && FROZEN_SKIP_PATTERNS.some((re) => re.test(norm))   # 均带 'i'
  results.push({ ...既有字段, skipped })
renderTestMachineReport：每 command 块末追加 "    skipped: {c.skipped}"
```

模式表见 §2.4。`FROZEN_SKIP_PATTERNS` 为模块级常量数组（字面量 RegExp + `i` flag），实施期不得增删。

## 4.6 四个 review Skill 的流程修订（P0-1 / FR-1～FR-4 / FR-7 / FR-9 / FR-11 / FR-16）

- **首轮完整契约域（FR-1）**：verdict 前完成全部适用维度；同一契约域的独立缺口同轮列出（`本轮新增：`）。PRD/SDD 定义可调用契约时按契约域闭合清单（HTTP API 八项 / crctl·CLI 八项 / Skill 契约五项）一次检查，缺适用项显式写 N/A 及原因。
- **评审顺序**：`review-dev-plan` 与 `review-code` 先核对 SDD「批准范围」（FR-7 路由表），再执行其余维度；`review-tech-design` 先核对批准范围（AC-5：缺章节即 blocker），再查真实 symbol、调用者闭包、依赖方向、事务与锁序（保留既有 Step 2.2 首轮全量规则）。
- **分级（FR-2）**：影响当前实现唯一性或当前验收可达性 → blocker；只影响表达/未来优化/后续 CR → suggestion。
- **前缀（FR-3）**：payload 文本按 §2.6；首轮 blocker 全部 `本轮新增：`；旧 blocker 逐条复核（FR-4），禁止只写「已修复」。
- **review-dev-plan 新增**：覆盖矩阵缺失/关键 AC 无唯一 TASK owner/证据列非 `cmd-NN` → blocker（FR-8/FR-9）；流程控制 TASK 核验（FR-10/FR-11）。
- **review-code 新增**：FR-16 skip 语义（§3.4）与批准范围 code 行路由（FR-7：diff 触碰 scope_out/zero_diff 或把 follow_up 做成当前交付 → blocker，`repair-target=implement-code`，禁止写 `write-tech-design`/`write-dev-plan`）；`implement-code` 补一句「撤回越界 diff」。

---

# 5. 技术选型与替代方案

| 决策 | 选择 | 替代与否决理由 | 是否 ADR |
|---|---|---|---|
| D-1 版本规范化纯函数落点 | `workspace-transactions.mjs` 新导出，三命令共用 | ① crctl.mjs 内联：三处复制、测试需经 CLI 间接覆盖；② 独立新文件：无必要的新模块边界。lib 已是被 crctl.mjs 与测试共同 import 的既有落点 | 否（易逆转、上下文自明、有真实替代但权衡清楚） |
| D-2 version-set 同构 owner-set | 复用 `recoverLedgerCommand`/`beginLedgerCommand`/tracked-clean/受控 git/回滚骨架 | ① 新事务框架：违反 NFR-2 与 ARCHITECTURE.md §6 否决记录；② 独立账本文件：违反「账本唯一写入通道」不变量；③ `backlog-set` 白名单扩展：backlog-set 只覆盖单账本标量，做不到 cr.md+backlog+派生六文件原子 | 否 |
| D-3 skipped 在 `runTestPlan` 计算 | `crctl test` 机器区单一计算点 | ① review-code 自行解析框架输出：FR-16 明令禁止（框架输出多样，reviewer 裁量差异正是 AIFI-14 教训）；② 新 coverage ledger：PRD 排除 | 否 |
| D-4 前缀强制在 Skill 文本层 | 四个 review SKILL.md 契约 + FR-3 机械核对规则 | crctl `review-record` 加内容校验：违反 FR-1「不改 review-record schema」与 FR-17「静态检查仅重复失败且规则确定时下沉」——前缀规则是本 CR 首建，尚无"重复失败"事实 | 否 |
| D-5 批准范围承载 | SDD 文档固定章节（模板 + write-tech-design 契约） | ① 新 ledger 文件：FR-5 明令禁止；② crctl schema 字段：会把纯文档事实引入受控账本，扩大 CR-2026-039 收紧的 schema 面 | 否 |
| D-6 守卫读取 cr.md 的路径解析 | 复用只读 `resolveOperationalWorkspace` | 复制一套 authority 解析：会制造第二个 authority 判据源，漂移风险高于复用；该函数只读无副作用，不违反观察点 1–6 | 否 |

三判据（难以逆转 + 无上下文会疑惑 + 有真实权衡替代）无一同时满足 → 不新增 ADR 文件、不新增审批节点。决策记录落本表。

---

# 6. FR 到技术实现映射

| FR | 技术实现条目 | 落点文件 |
|---|---|---|
| FR-1 首轮完整契约域 | 四 review SKILL 各加「首轮完整契约域」规则与适用维度；review-requirement 补契约域闭合清单（HTTP/CLI/Skill 三行）；review-tech-design 补真实 symbol/调用者闭包/依赖方向/事务锁序核对；review-dev-plan 补覆盖链先查规则；review-code 补 diff/调用者/关键失败路径与测试三态区分 | `skills/requirement/review-requirement/SKILL.md`、`skills/develop/review-tech-design/SKILL.md`、`skills/develop/review-dev-plan/SKILL.md`、`skills/develop/review-code/SKILL.md` |
| FR-2 blocker/suggestion 分级 | 同上四文件加分级判据（当前实现唯一性/当前验收可达性 → blocker） | 同上 |
| FR-3 每轮评审报告结构 | 四文件加 §2.6 前缀表 + 机械核对规则 + 首轮全部 `本轮新增：` 规则 | 同上 |
| FR-4 回修可重验、禁恢复已删字段 | 四文件加「逐条复核旧 blocker 状态，禁止只写已修复」；新增文本不得包含 contract-scan 四个禁止串（保持 AC-4 零命中） | 同上 |
| FR-5 SDD「批准范围」固定章节 | `SDD-template.md` 新增章节（§2.5 四字段 + 空字段规则） | `skills/shared/engineering-docs/templates/SDD-template.md` |
| FR-6 写入与冻结时机 | `write-tech-design` SKILL 加契约必填规则与审批后只读说明（含 PLAN/TASK/code 冲突路由表述） | `skills/develop/write-tech-design/SKILL.md` |
| FR-7 下游评审先核对批准范围 | `review-dev-plan`/`review-code` 各加前置核对与路由表（双轨 repair-target 枚举不变；code 固定 `implement-code`）；`implement-code` 补撤回越界 diff 一句 | `skills/develop/review-dev-plan/SKILL.md`、`skills/develop/review-code/SKILL.md`、`skills/develop/implement-code/SKILL.md` |
| FR-8 plan.md 覆盖矩阵必填 | `write-dev-plan` SKILL 加矩阵节契约（四列表头；关键 AC 证据列 `cmd-NN`） | `skills/develop/write-dev-plan/SKILL.md` |
| FR-9 无唯一 TASK owner 不得进入开发启动 | `review-dev-plan` 加 blocker 规则；不新增 crctl/gates 静态检查 | `skills/develop/review-dev-plan/SKILL.md` |
| FR-10 禁止流程控制交付 TASK | `write-dev-tasks` SKILL 加禁止条款（merge/writeback/archive/完成于 merge 的发布准备；完成边界收敛于 developing 内可登记事件） | `skills/develop/write-dev-tasks/SKILL.md` |
| FR-11 评审核验与归档门禁不变 | `review-dev-plan` 加核验 FR-10 规则；`gates.json`/`deliveryIndexComplete`/`task done` 合法状态零改动（AC-10/AC-11 回归断言） | `skills/develop/review-dev-plan/SKILL.md`（gates 不动） |
| FR-12 register 硬校验 | §4.2：`normalizeTargetVersion` 落 lib；`registerCr` 顶部校验 + inputDigest/文本/返回用规范化值；`cmdRegister` 参数面调整；`crctl.mjs` HELP 行更新 | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`、`skills/shared/crctl/scripts/crctl.mjs` |
| FR-13 后续产物继承同一版本 | 五个 SKILL 修订：`requirement-register`（target_version 必填 + 值域 + unassigned 确认先例 + version-set 入口）、`write-requirement-prd`（补禁止 tbd/禁止改写措辞）、`write-tech-design`/`write-dev-plan`/`write-dev-tasks`（frontmatter 增加/改为 `target-version: {cr.md 值}`，删除 `或 tbd`） | 五个对应 SKILL.md |
| FR-14 writeback-apply 一致性守卫 | §4.3：`guardWritebackVersion` + `applyWritebackAtomic` 顶部插入；错误码三枚；零观察点由测试断言 | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` |
| FR-15 version-set 唯一入口 | §4.4：dispatch 新 case + `cmdVersionSet` + `editTargetVersionLine` 行级编辑纯函数；`ARCHITECTURE.md` §3 一句增量（维护规则触发：crctl 新增写入子命令） | `skills/shared/crctl/scripts/crctl.mjs`、`skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（如需复用 matchEntryBlock 则在 crctl.mjs 内实现，不跨层）、`ARCHITECTURE.md` |
| FR-16 关键测试 SKIP ≠ 完整通过 | §4.5：`runTestPlan`/`renderTestMachineReport` 增 `skipped`；`review-code` SKILL 加只读机器区规则与 blocker/中止语义（关键 AC 唯一证据 skipped:true → blocker `repair-target=implement-code`、摘要含「未执行」；`ENVIRONMENT_MISMATCH` 技术中止保持现有约定）；`write-test-report` SKILL 补机器区 `skipped` 字段与 `cmd-NN` 绑定说明（S-001 落点） | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`、`skills/develop/review-code/SKILL.md`、`skills/develop/write-test-report/SKILL.md` |
| FR-17 下沉触发规则 | 本 CR 只落 FR-12/14/15/16 确定性检查；不落 P1-3 举例其余项（AC-17 由 diff 审阅验证） | —（无新增代码） |
| NFR-1 回归 | `crctl.test.mjs`（或按主题新测试文件，入口仍 `node --test`）补 FR-12/14/15/16 用例；既有夹具适配（见 §6.2） | `skills/shared/crctl/scripts/test/` |
| NFR-2 兼容边界 | 无新 Agent/Pipeline/状态/转换/ledger/事务框架；`dir-graph.yaml`、`gates.json`、`pipeline-templates/` 三文件零改动 | —（不改即证明） |
| NFR-3 行尾纪律 | 新增文本编辑/模式匹配先 `\r\n→\n`；`editTargetVersionLine` 匹配不到硬失败 | 见各落点 |
| NFR-4 性能 | 守卫为常数时间字段比较；无网络调用 | 见各落点 |
| NFR-5 安全 | 审批 TTY/`--grant` 约束不动；version-set 经 durable ledger transaction + 受控 git，无旁路写路径 | 见各落点 |
| NFR-6 文档同步 | `requirement-register` SKILL、`README.md`（注册阶段确定版本 + version-set 唯一更正 + writeback 守卫的人读小节）、`ARCHITECTURE.md` 一句；不在 knowledge-base `dir-graph.yaml` 复刻状态机 | `README.md`、对应 SKILL、`ARCHITECTURE.md` |

## 6.1 既有测试夹具适配清单（实施期必须同步，否则 AC-18 红）

1. `test/merge-fixture.mjs` `makeCodeApprovedFixture`：cr.md 模板补 `target-version: 0.2`（现无该字段，writeback 守卫会将其判为 `WRITEBACK_VERSION_INVALID`）。
2. `test/writeback-tx.test.mjs`：第 103 行附近「`targetVersion:'0.3'` 重试 → `TX_INPUT_CONFLICT`」断言改为 `WRITEBACK_VERSION_MISMATCH`（新守卫先行命中）；其余用例的 `0.2`/`v0.2` 与夹具 cr.md `0.2` 一致，守卫放行。
3. `test/register-tx.test.mjs`：`regArgs` 补 `--target-version unassigned`（FR-12 后必填）；新增负向用例组。
4. `test/test-cr.test.mjs`：fixture cr.md 补 `target-version`（其自身不调 writeback 则仅一致性要求）。
5. `test/crctl.test.mjs`：「task done 非 developing → ILLEGAL_LEDGER_STATE」既有用例保留不放宽（AC-10 回归）。

## 6.2 测试设计（AC-12～AC-16 自动化向量）

- `normalizeTargetVersion` 单测：全值域表（合法：`unassigned`/`0.30`/`v0.30`→`0.30`/`V0.30`/`0.1.0`；非法：缺省/空/`tbd`/`TBD`/`n/a`/`pending`/`0.29-rc`/`1`/`0.30.0.1`/`latest`/内嵌空白/非 string）。
- register 负向：`REGISTER_VERSION_INVALID` × 6 类输入，断言 cr.md/backlog 新条目/journal 均不存在（零写入）；正向：`unassigned`/`0.30`/`v0.30` 成功且 cr.md 与 JSON `targetVersion` 为规范化值；幂等：同 key `v0.30`→`0.30` 续跑同 CR。
- writeback 守卫：三 stage × {MISMATCH、UNASSIGNED、INVALID}，每次调用后断言 §3.2 六项禁止观察点；同参重试同码无增量；`status=drafting` 夹具证明版本错误优先于 `WRITEBACK_STATE_MISMATCH`（AC-14.6）。
- version-set：正向 unassigned→`0.30` 全链同步（files 六类全列）；幂等 changed=false 零 commit；`--to unassigned`/畸形 → INVALID；`merging` → STATE_INVALID；cr.md 手改真实版本而 PRD 仍 unassigned → DRIFT；允许状态抽样 + 终态拒绝；重试无半成品。
- skipped：命中模式表夹具（`# skip`、`ok 3 # skip`、`skipped: 2`、`SKIPPED`、`no tests to run`、CRLF 变体）→ `skipped:true`；无模式 exit 0 → false；non-zero → false（非 skip）。
- AC-1～AC-4（评审行为夹具）不自动化：评审判断是模型行为，证据载体是 `review-annotations/*.yml` 内容，由评审执行时按 AC-1～AC-4 夹具验证；AC-4 由既有 `contract-scan.test.mjs` 零命中断言。
- AC-17：diff 审阅（不引入未再次失败的新 validator）；AC-18：`node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 及既有 writeback/archive/register/test-cr 全绿。

## 6.3 AC 逐项设计与验收映射

| AC | 设计落点 | 可观测结果 | 可达性说明 |
|---|---|---|---|
| AC-1 四节点首轮同轮双缺口 | FR-1 Skill 规则（四文件） | 对应 `review-annotations/{requirement\|sdd\|dev-plan\|code}.yml` 本轮 blockers 同时含两条独立根因、均带 `本轮新增：` | 夹具 PRD/SDD/diff 各自预置两个独立缺口；首轮全量规则保证 verdict 前两者均已发现 |
| AC-2 分级 | FR-2 规则 | 措辞问题入 suggestions、验收不可达入 blockers | 夹具两类问题同轮出现；分级判据是文本规则 |
| AC-3 回修机械核对 | FR-3/FR-4 规则 | 本轮 suggestions 恰 1 条 `已解决：`、blockers 恰 1 条 `未解决：`/`部分解决：`、suggestions 1 条 `范围外：`；payload 与 SKILL 正文无禁止字段名 | 上一轮 2 条 blocker 修 1 留 1 的夹具；前缀规则使状态可机械区分 |
| AC-4 禁止字段零命中 | 不改 contract-scan；新文本不含禁止串 | `contract-scan.test.mjs` 对 3 Pipeline + 11 SKILL 零命中 | 新文本措辞避开四个串（实施时逐文件核对） |
| AC-5 批准范围章节 | FR-5 模板 + FR-6 write-tech-design 契约 | 新起草 SDD 含四字段；缺章节 → review-tech-design blocker | 模板是唯一 SDD 起草入口（skill 引用模板）；缺章节夹具直接触发规则 |
| AC-6 follow_up 做成 TASK → blocker | FR-7 路由表（review-dev-plan 行） | verdict=block 且 `repair-target ∈ {write-dev-plan, write-tech-design}` | 双轨枚举既有（crctl.mjs `REVIEW_REPAIR_TARGETS`/dev-plan 枚举校验），不发明第三值 |
| AC-7 先核对批准范围 + zero_diff | FR-7（review-dev-plan/review-code 前置）+ 既有 `REVIEW_REPAIR_TARGETS.code=implement-code` | code blocker 的 `repair-target=implement-code`；`crctl next` 指向 `implement-code` | 评审顺序是文本规则；code repair-target 由既有 crctl 常量固定，无上游轨 |
| AC-8 覆盖矩阵 | FR-8 write-dev-plan | plan.md 含矩阵节，关键 AC 有 owner + `cmd-NN` | 矩阵是 plan.md 契约必填节 |
| AC-9 删 owner → block | FR-9 review-dev-plan | verdict=block；`crctl next` 不指向 `approve-dev-start` | `approve-dev-start` 消费既有 passCondition（verdict=pass 且 blockers 空）——block 后天然不可达 |
| AC-10 流程控制 TASK | FR-10/FR-11 | review-dev-plan blocker；交付 ledger 无完成边界超出 developing 的条目；`crctl task done` 非 developing 仍 `ILLEGAL_LEDGER_STATE` | `write-dev-tasks` 契约禁止 + 评审核验双层；`task done` 合法状态集零改动 |
| AC-11 deliveryIndexComplete 不变 | gates.json 零改动 | 交付 TASK 未 done 时 archive 仍阻断；无新增豁免 flag | 不动即满足 |
| AC-12 register 正负向量 | FR-12 | 六类负向 `REGISTER_VERSION_INVALID` 零写入；`unassigned`/`0.30`/`v0.30` 成功且 `targetVersion` 规范化值；本 CR `cr.md` 已为 `unassigned` 为正向例 | 校验点位于 registerCr 顶部（任何副作用之前） |
| AC-13 继承侧 | FR-13 | 本 CR PRD/SDD `target-version: unassigned` 与 cr.md 全等；夹具 `version-set` 后已存在产物 frontmatter 与 cr.md 全等 | 产物 frontmatter 由 Skill 契约写入；version-set 原子写集覆盖六类文件 |
| AC-14 writeback 守卫观察点 | FR-14 | 三 stage × 三错误码；每次失败后六项禁止观察点；同参重试同码；drafting 夹具版本错误优先 | 守卫时序 §4.3 保证先于 candidate/journal/authority 断言 |
| AC-15 version-set 正负向量 | FR-15 | 正向全链同步 + JSON from/to/files；INVALID/STATE_INVALID/DERIVED_DRIFT 零写；手改 cr.md 不被官方入口支持（既有保护不变） | 允许状态集与漂移检查在写入前；durable ledger transaction 保证零半成品 |
| AC-16 skip 语义 | FR-16 | 关键 AC 唯一证据 `cmd-NN` 且 `skipped:true` → review-code blocker（`implement-code`）+ 摘要含「未执行」；log 夹具断言 `crctl test` 写 `skipped:true/false` | `skipped` 由 `crctl test` 唯一计算；review-code 只读机器区 |
| AC-17 无未触发新 validator | FR-17 | diff 不含 P1-3 举例其余检查实现 | 范围冻结 + diff 审阅 |
| AC-18 回归全绿 | NFR-1 + §6.1 | `node --test` 全部通过，既有用例不失败 | 夹具适配清单 §6.1 先行 |

---

# 7. 安全与性能考量

- **零写入失败面（FR-12/14/15）**：三个版本入口的失败路径全部发生在任何持久化副作用之前（register 顶部校验、writeback 守卫先于 candidate/journal、version-set 校验先于 beginLedgerCommand）。version-set 的写入经 durable ledger transaction（before snapshots + recoverable write-set），commit 前中断整组回滚，无半成品。
- **并发与 CAS**：register 复用既有 lock + journal envelope + inputDigest（含规范化 targetVersion）；version-set 复用 ledger tx key + expectedHash CAS + tracked-clean 前置；writeback 守卫纯读不取锁。同参重试语义（幂等或同错误码）由 §3 契约覆盖。
- **行尾与硬失败（NFR-3）**：新增 `editTargetVersionLine`、skipped 模式匹配均先 `\r\n→\n`；`LEDGER_PARSE_FAILED` 硬失败不静默。
- **性能（NFR-4）**：三个守卫均为常数时间字符串比较/正则，无网络调用、无目录扫描。`skipped` 只对已生成的 log 文本做 5 个正则测试，每个命令一次。
- **安全（NFR-5）**：不改变 `approve` 的 TTY/`--grant` 约束；version-set 调用者约束与 `owner-set` 相同（非 TTY 限制，identity 由 crctl 生成）；不新增绕过 crctl 的账本写路径；审计日志（`.crctl/audit.log`）覆盖 version-set 与 register 校验失败路径按既有 `fail` 语义输出 stderr JSON。
- **边界条件**：`v` 前缀剥离仅恰好一个（`vv0.30` → 畸形）；版本号禁止前导零（`0` 本身除外）；`0.1.0` 合法（MAJOR.MINOR.PATCH）；backlog 条目缺 `target-version` 视为漂移拒绝（不静默补写）；TASK-* 缺 frontmatter 字段同上。

---

# 8. Prompt 采纳影响

> 触发判定：本 CR 的 diff **触及** `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支（新增 `version-set` case、`register` 参数面变化、`writeback-apply` 版本守卫、`crctl test` 机器区新字段）→ 本节必填。不触及 `skills/shared/controlled-shell/rules.json#protectedPaths.deny`（本 CR 不新增/变更 deny 面——所有新写入均经 crctl 子命令，Agent 仍无直接写账本路径）。

应改为调用新增/扩展子命令（或同步新契约）的 Skill 清单：

| Skill 路径 | 现状 | 应改为 |
|---|---|---|
| `skills/requirement/requirement-register/SKILL.md` | `--target-version` 标记可选；未提值域与更正入口 | 参数表 `target_version` 改必填；补值域（真实版本 `MAJOR.MINOR[.PATCH]` 或 `unassigned`）、禁止 tbd 及同义值、未排期先向用户确认再 `unassigned`（沿用 `origin` 确认先例）、`version-set` 唯一更正入口；Step 2 命令示例含 `--target-version`；Step 3 结果分类表补 `REGISTER_VERSION_INVALID` 行 |
| `skills/requirement/write-requirement-prd/SKILL.md` | 已从 cr.md 读 target-version，但无禁止 tbd/禁止改写措辞 | 补「继承 cr.md，禁止写 tbd、禁止自行改写」措辞 |
| `skills/develop/write-tech-design/SKILL.md` | frontmatter 模板无 `target-version` 字段；无批准范围节 | frontmatter 增 `target-version: {cr.md 值}`；补 FR-6 批准范围节契约必填规则与审批后只读语义 |
| `skills/develop/write-dev-plan/SKILL.md` | `target-version: {target_version 或 tbd}`；无覆盖矩阵节 | frontmatter 改为 `target-version: {cr.md 值}`（删除 `或 tbd`）；参数说明改为从 cr.md 读取；新增「AC/业务闭环覆盖矩阵」必填节 |
| `skills/develop/write-dev-tasks/SKILL.md` | TASK frontmatter 无 `target-version`；无流程控制 TASK 禁止条款 | frontmatter 增 `target-version: {cr.md 值}`；补 FR-10 禁止条款（merge/writeback/archive/完成于 merge 的发布准备不得建交付 TASK） |
| `skills/develop/review-code/SKILL.md` | 以 `test-report.status=pass` 为进入审批前提；不读 `skipped` | 补 FR-16：只读机器区 `skipped`/`exit-code`/`timed-out` 与覆盖矩阵 `cmd-NN`；关键 AC 唯一证据 `skipped:true` → blocker（`repair-target=implement-code`）+ 摘要「未执行」；环境不满足是风险记录不是验收完成；补 FR-7 批准范围前置核对 |
| `skills/develop/review-dev-plan/SKILL.md` | 八类维度无批准范围前置、无覆盖矩阵/关键 AC owner/流程控制 TASK 检查 | 补 FR-7 前置核对与双轨表、FR-8/FR-9 矩阵与 owner 规则、FR-10/FR-11 核验 |
| `skills/develop/review-requirement/SKILL.md`、`skills/develop/review-tech-design/SKILL.md` | 无契约域闭合清单（requirement）/无前缀表 | 补 FR-1～FR-4（闭合清单、分级、前缀表、逐条复核） |
| `skills/develop/write-test-report/SKILL.md` | 机器区字段说明未含 `skipped` | 补机器区 `skipped` 字段（additive）与 `cmd-NN` 稳定关联说明 |
| `skills/develop/implement-code/SKILL.md` | 无越界 diff 撤回语义 | 补一句：code 评审 blocker 若涉范围越界，implementer 必须撤回越界 diff |

供 `review-tech-design` 与人工审批逐条核对。`lint-prompts`（R1–R13）仅能机械抓"crctl 已接管/已禁止的事"，抓不到"新增能力未被采纳"——本清单即兜底。

---

# 9. 批准范围

- **scope_in**：PRD FR-1～FR-17、NFR-1～NFR-6、AC-1～AC-18 的实施方案（本 SDD §2–§7）；对应 PRD §7 范围与附件 §7 P0-1～P1-3。
- **scope_out**：不新增 Agent、Pipeline、状态机状态/转换、review ledger、事务框架、通用 Runner、coverage 系统；不含 AIFI-14 历史产物回写修复；不修改 `../multica/`；不把 `docs/product/`、`docs/analysis/` 既有文档搬进 `specs/`；不提高 `reviewLoop.maxAttempts`；不新增 archive 豁免；不扩展 `crctl task done` 合法状态；不一次性实现 P1-3 举例中除 FR-12/14/15/16 以外的检查项。
- **zero_diff**（明确不得改动，改动即违反本 CR 自身规则）：
  1. `dir-graph.yaml#change-request-track.state_machine`（tools 与 knowledge-base 均不改；状态机口径保持 15 具名状态 + `(new)`、28 声明/50 展开）
  2. `skills/shared/crctl/gates.json`（含 `deliveryIndexComplete`，FR-9/FR-11 明确不加检查）
  3. `crctl task done` 合法状态集（仍仅 `developing`，`ILLEGAL_LEDGER_STATE` 行为不变）
  4. `REVIEW_REPAIR_TARGETS` 常量（`code → implement-code` 不变）与 `review-record` schema 必填字段集、attempt 账本
  5. `skills/shared/crctl/scripts/lib/durable-tx.mjs`、`lib/yaml-subset.mjs`（复用不改）
  6. `pipeline-templates/` 三条 CR Pipeline 的 reviewLoop 结构（contract-scan AC-2 断言）
  7. `skills/shared/controlled-shell/rules.json` `protectedPaths.deny`（不新增 deny 面）
  8. `contract-scan.test.mjs` 的 FORBIDDEN 清单（不增删扫描项）
- **follow_up**：P1-3 候选清单其余项（PLAN symbol 存在性、TASK cwd/package path、reviewLoop repair 节点、writeback 前 pending 交付 TASK 门禁等）留给后续 CR，仅在同类问题重复失败且规则确定时下沉；附件 §7 之外的建议（审批卡直通、取消 agent 委派等）不属于本 CR。

---

# 10. 既有实现依赖与事实

按正文首次出现顺序。repo 均为 `tools`；commit SHA 为 tools 仓本 CR worktree HEAD `7ddeeb7ae57ed097518e2fe176f2e6b31e084ac2`（`crctl git rev-parse HEAD` 核实）。

1. repo: tools
   relative path: `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
   stable symbol/对象: `registerCr`（第 589 行 `const targetVersion = input.targetVersion ?? 'tbd'`）
   commit SHA: 7ddeeb7ae57ed097518e2fe176f2e6b31e084ac2
   依赖结论: FR-12 删除该缺省值并加顶部硬校验；现状默认 `tbd` 是 P1-1 必须消除的版本事实分叉根因。
2. repo: tools
   relative path: `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
   stable symbol/对象: `buildRegistrationTexts`（第 265 行起，cr.md/backlog 条目模板含 `target-version:` 行）；`registerCr` 返回对象（第 718 行 `{ cr, txId, phase, changed, sideEffects, recoverCommand }`）
   commit SHA: 7ddeeb7ae57ed097518e2fe176f2e6b31e084ac2
   依赖结论: FR-12 写入规范化值并让成功对象含 `targetVersion` 字段，依赖这两个模板/返回形态。
3. repo: tools
   relative path: `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
   stable symbol/对象: `canonicalWritebackBusinessInput`（第 2072 行，`startsWith('v')` 剥离）；`prepareWritebackCandidate`（第 2281 行，第 2301-2302 行 `rmSync`+`mkdir` candidate 目录；第 2287 行仅空值 `WRITEBACK_VERSION_INVALID`）
   commit SHA: 7ddeeb7ae57ed097518e2fe176f2e6b31e084ac2
   依赖结论: FR-14 守卫必须在 `prepareWritebackCandidate` 之前拦截，保证版本失败零 candidate 痕迹；`v` 剥离与 FR-12 规范化对齐。
4. repo: tools
   relative path: `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
   stable symbol/对象: `applyWritebackAtomic`（第 2386 行；traceability replay 分支在最前，第 2425 行 `resolveOperationalWorkspace`，第 2426-2428 行 `WRITEBACK_STATE_MISMATCH` 断言，第 2453 行 `prepareWritebackCandidate`，第 2470 行起 `loadOrCreateJournal`）
   commit SHA: 7ddeeb7ae57ed097518e2fe176f2e6b31e084ac2
   依赖结论: FR-14 守卫插入点（顶部、replay 分支之前）与该既有顺序相关；`WRITEBACK_STATE_MISMATCH` 优先级必须让位于版本错误（AC-14.6）。
5. repo: tools
   relative path: `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
   stable symbol/对象: `resolveOperationalWorkspace`（第 160 行，只读 authority 解析，返回 `{phase, path, source}`）
   commit SHA: 7ddeeb7ae57ed097518e2fe176f2e6b31e084ac2
   依赖结论: 守卫读取 cr.md `target-version` 的路径解析复用它，不复制 authority 判据（决策 D-6）。
6. repo: tools
   relative path: `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
   stable symbol/对象: `runTestPlan`（第 3521 行；第 3541-3542 行 `cmd-${String(i+1).padStart(2,'0')}.log`；log 含 `--- stdout ---`/`--- stderr ---` 两段）；`renderTestMachineReport`（第 3592 行，机器区 commands 字段表）
   commit SHA: 7ddeeb7ae57ed097518e2fe176f2e6b31e084ac2
   依赖结论: FR-16 `skipped` 在 `runTestPlan` 计算、`renderTestMachineReport` 追加行——依赖既有 `cmd-NN` 命名与 log 分段格式。
7. repo: tools
   relative path: `skills/shared/crctl/scripts/crctl.mjs`
   stable symbol/对象: `cmdOwnerSet`（第 2461 行起）及其骨架：`ledgerTxKey`（第 676 行）、`recoverLedgerCommand`（第 689 行）、`beginLedgerCommand`（第 703 行）、`queryTrackedChanges` tracked-clean 前置、`rollbackOwnerWrite`（第 2455 行附近）
   commit SHA: 7ddeeb7ae57ed097518e2fe176f2e6b31e084ac2
   依赖结论: `version-set` 同构复用该事务骨架（决策 D-2）；错误码族镜像 `OWNER_*`。
8. repo: tools
   relative path: `skills/shared/crctl/scripts/crctl.mjs`
   stable symbol/对象: `editCrOwnerProjection`（第 2400 行）/`editBacklogOwnerProjection`（第 2418 行）/`editBacklogSet`（BACKLOG_SET_FIELDS，第 2449 行起）的行级正则改写模式与 `matchEntryBlock`/`findBlockEnd`；`readOwnerState`（第 2325 行）双投影一致性思路
   commit SHA: 7ddeeb7ae57ed097518e2fe176f2e6b31e084ac2
   依赖结论: `editTargetVersionLine` 沿用该模式（frontmatter 行替换 + backlog 条目块行替换；匹配不到硬失败）。
9. repo: tools
   relative path: `skills/shared/crctl/scripts/crctl.mjs`
   stable symbol/对象: dispatch `switch (cmd)`（第 3110 行起）；`cmdRegister`（第 2888 行，必填循环不含 `target-version`）；`REVIEW_REPAIR_TARGETS`（第 1841 行，`code: 'implement-code'`）；dev-plan `repair-target` 枚举校验（第 1992 行 `['write-dev-plan', 'write-tech-design']`）；`cmdTest`（第 2719 行）；`task done` 合法状态（第 1761 行 `ILLEGAL_LEDGER_STATE`，仅 `developing`）
   commit SHA: 7ddeeb7ae57ed097518e2fe176f2e6b31e084ac2
   依赖结论: 新 `case 'version-set'` 接入该 switch；FR-7 路由复用既有 repair-target 机制不新增枚举；FR-16/AC-10 依赖 `task done` 行为不放宽。
10. repo: tools
    relative path: `skills/shared/engineering-docs/templates/SDD-template.md`
    stable symbol/对象: 既有 9 节结构（无「批准范围」）
    commit SHA: 7ddeeb7ae57ed097518e2fe176f2e6b31e084ac2
    依赖结论: FR-5 在其上新增固定章节，其余节不动。
11. repo: tools
    relative path: `skills/develop/write-dev-plan/SKILL.md`
    stable symbol/对象: Step 2 frontmatter `target-version: {target_version 或 tbd}`；无覆盖矩阵节
    commit SHA: 7ddeeb7ae57ed097518e2fe176f2e6b31e084ac2
    依赖结论: FR-13 删除 `或 tbd` 改为继承 cr.md；FR-8 新增矩阵节。
12. repo: tools
    relative path: `skills/develop/write-dev-tasks/SKILL.md`（TASK frontmatter 无 `target-version`、无流程控制 TASK 禁止条款）；`skills/requirement/requirement-register/SKILL.md`（`target_version` 可选）；`skills/requirement/review-requirement/SKILL.md`（Step 2 五维度、无首轮闭包/前缀规则）；`skills/develop/review-tech-design/SKILL.md`（Step 2.2 已有首轮全量，可推广）；`skills/develop/review-dev-plan/SKILL.md`（八类维度、双轨已有）；`skills/develop/review-code/SKILL.md`（Step 1/5 以 `test-report.status=pass` 为前提）；`skills/develop/write-test-report/SKILL.md`（机器区字段说明未含 `skipped`）；`skills/develop/implement-code/SKILL.md`
    commit SHA: 7ddeeb7ae57ed097518e2fe176f2e6b31e084ac2
    依赖结论: 全部修订均是对这些既有文本的定点增改（§6 映射表），不重写结构。
13. repo: tools
    relative path: `skills/shared/crctl/scripts/test/contract-scan.test.mjs`
    stable symbol/对象: `FORBIDDEN = ['repair-instructions', 'fixed-blockers', 'suggestion_policy', 'suggestion-policy']`（第 21 行）；PIPELINES 3 条 + SKILLS 11 个（第 23-40 行）
    commit SHA: 7ddeeb7ae57ed097518e2fe176f2e6b31e084ac2
    依赖结论: FR-4/AC-4——新修订文本不得包含这四个串；本 CR 不修改该扫描器。
14. repo: tools
    relative path: `skills/shared/crctl/scripts/test/merge-fixture.mjs`（`makeCodeApprovedFixture` 第 100-101 行 cr.md 模板无 `target-version`）；`test/writeback-tx.test.mjs`（第 103 行附近 `TX_INPUT_CONFLICT` 断言）；`test/register-tx.test.mjs`（`regArgs` 第 87 行无 `--target-version`）；`test/test-cr.test.mjs`（fixture cr.md 第 152 行无 `target-version`）
    commit SHA: 7ddeeb7ae57ed097518e2fe176f2e6b31e084ac2
    依赖结论: §6.1 夹具适配清单的全部依据；不先行适配则 AC-18 必红。
15. repo: tools
    relative path: `skills/shared/crctl/gates.json`（第 102 行 `{ "type": "deliveryIndexComplete" }`）
    stable symbol/对象: `deliveryIndexComplete` 归档门禁
    commit SHA: 7ddeeb7ae57ed097518e2fe176f2e6b31e084ac2
    依赖结论: FR-11/AC-11——本 CR 零改动，行为保持一致。
16. repo: tools
    relative path: `ARCHITECTURE.md`（§3 代码地图 crctl 段；§8 维护规则「crctl 新增写入子命令」触发修订）
    stable symbol/对象: 维护规则触发条件清单
    commit SHA: 7ddeeb7ae57ed097518e2fe176f2e6b31e084ac2
    依赖结论: version-set 属新增写入子命令 → 实施期做一句增量（登记子命令与同构 owner-set 性质），不抄写状态机条款。
17. repo: tools
    relative path: `README.md`（§4 流程总览、§5 自动评审与人工审批、§7 恢复与 status/next）
    stable symbol/对象: 人读流程章节结构
    commit SHA: 7ddeeb7ae57ed097518e2fe176f2e6b31e084ac2
    依赖结论: NFR-6 版本规则人读同步的插入位置。
18. repo: tools
    relative path: `pipeline-templates/requirement-authoring.pipeline.json`（inputs 已含必填 `target_version`）；`architecture-design.pipeline.json`、`code-implementation.pipeline.json`（reviewLoop 结构）
    stable symbol/对象: 三条 CR Pipeline 编排
    commit SHA: 7ddeeb7ae57ed097518e2fe176f2e6b31e084ac2
    依赖结论: NFR-2/zero_diff——本 CR 零改动；requirement-authoring 已标必填是 FR-13 的既有对齐事实（PRD 已核实）。

无其它既有实现依赖；待核实依赖：无。

---
id: CR-2026-038-sdd
type: SDD
cr-ref: CR-2026-038
title: tools CR 生命周期最小优化 1/5 — Writeback 原子化技术设计
status: draft
created: 2026-08-14T20:54:20+08:00
updated: 2026-08-14T20:54:20+08:00
---

# 1. 架构概览

## 1.1 设计目标

本设计落实 PRD FR-01～FR-04，在现有 `crctl writeback-apply` 和 `crctl merge` 内闭合两个边界：

1. baseline 文件、`merging -> writing-back` 状态、commit、lease push、status outbox 和 advance audit 成为一个可恢复发布单元；
2. `_backlog.yml` 合并只采用 CR source 中目标 CR 的完整条目，其他内容以最新 trunk 为准并逐字保留。

本 CR 不重建 durable transaction、状态机、YAML parser、generator 平台或 Git adapter。实现优先级固定为：复用现有能力 > Node 标准库 > 原生 Git/文件 API > 已有依赖 > 一行代码 > 最小新增代码。当前 tools worktree 已核实存在以下可复用能力：

- `workspace-transactions.mjs#applyWriteback()`：manifest 校验、recoverable write-set、精确 stage、commit、lease push 和远端事实分类；
- `crctl.mjs#performAdvance()` / `runGateChecks()`：状态机转换与目标态门禁；
- `durable-tx.mjs`：lock、journal、write-set、fault point；
- `workspace-transactions.mjs#matchEntryBlockTx()` 与 `crctl.mjs#matchEntryBlock()` 同类条目块定位逻辑；
- `skills/writeback/scripts/`：三个 candidate-only 确定性 generator；
- `mergeCr()`：`merge-tree --write-tree`、`commit-tree`、lease publish 和 rebuild；
- archive 的 origin-confirmed 后 outbox、journal marker 和 warning 恢复模式。

## 1.2 逻辑分层与职责边界

```text
Agent
  路由、职责判断、选择 feature-writeback Pipeline / writeback Skill
  不保存状态机，不执行 Git 算法，不写受控文件
    ↓
feature-writeback Pipeline
  节点顺序、业务输入传递、失败中止
  不展开 generator、candidate、manifest、advance、journal、commit/push 算法
    ↓
writeback-* Skill
  前置业务判断、一次 writeback-apply 调用、结果分类、失败语义
  不手写 candidate 路径、账本、状态或 Git
    ↓
crctl.mjs
  CLI 业务参数、状态/门禁适配、outbox/audit adapter、结构化结果
    ↓
workspace-transactions.mjs
  固定 generator 调用、manifest preflight、merge/writeback Git 事务与恢复
    ├─ durable-tx.mjs：lock / journal / recoverable write-set
    ├─ skills/writeback/scripts/：PRD/SDD/TASK/traceability 确定性转换
    └─ Node 标准库 + 原生 Git
```

各层严格遵循以下边界：

| 模块 | 应拥有 | 本 CR 明确不放入 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | Skill 完整算法、账本拼接、candidate/manifest 路径 |
| Skill | 业务判断、步骤编排、输入输出、失败语义 | 原子账本逻辑、重复实现 crctl、手写 commit/push |
| `crctl` | 状态、门禁、CAS、受控账本、审计、原子提交和恢复 | PRD/SDD 内容判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 确定性转换 | 状态推进、人工审批、Git 发布 |
| README | 人读流程总览和权威入口 | 可执行算法、状态机或错误矩阵副本 |

`workspace-transactions.mjs` 继续不反向依赖 `crctl.mjs`。状态门禁、outbox 和 audit 通过与 archive 相同的窄 callback 注入；不为此新增 service/interface/factory。

## 1.3 核心不变量

1. `writeback-apply --stage baseline` 是 `merging -> writing-back` 的唯一生产组合入口；调用方不能传任意 `to` 或 `trigger`。
2. 新事务的完整 generator/manifest/before/snapshot/gate preflight 必须发生在 writeback lock 和 journal 创建之前。
3. 只有 manifest 完整验证后的精确目标路径可作为 `fileExists` 的 planned-existing；其他 gate 类型只读当前 authority。
4. baseline manifest 文件与 `cr.md` 状态候选进入同一 `applyWriteSet()`、同一 staged set、同一 commit 和同一次 lease push。
5. status outbox 与 `kind: advance` success audit 只能在 origin 已确认包含 writeback commit 后发送，并携带该真实 SHA。
6. candidate 是 `.crctl/` 下可丢弃派生物，不是 authority、恢复账本或公共接口。
7. `_backlog.yml` 合并以最新 trunk 完整文本为基底，只替换目标 CR 的唯一完整条目；不读取或生成 backlog status。
8. merge 最终 commit 的两个 parent 仍是最新 trunk 和原始 CR source；内部 synthetic commit 只用于计算 tree，不成为发布 parent 或 ref。
9. 所有文本解析先按 `CRLF -> LF` 建立解析视图；结构未唯一命中必须硬失败，禁止返回空结果或整文件回退。
10. 不增加 npm 依赖、后台清理器、candidate manager、generator registry、通用 YAML patch 或第二事务框架。

## 1.4 Authority 与副作用边界

| 阶段 | Authority | 允许副作用 |
|---|---|---|
| 新事务 preflight | txws 当前 HEAD、origin refs、CR canonical 文件 | fetch；`.crctl/candidates/` 可丢弃输出；无 lock/journal/target write/audit/outbox |
| journal created | 预检通过的 manifest digest + 固定业务输入 | writeback journal 与 lock |
| write-set applied | txws 工作树/index | recoverable baseline + status after image |
| committed | txws commit | 本地 commit；尚未发送 success 投影 |
| origin confirmed | origin trunk 包含 commit | Git 权威事实成立 |
| projections emitted | origin-confirmed commit + journal marker | status outbox、advance audit；失败只 warning |
| complete replay | origin + journal | 只补缺失投影，零新 commit/push |

已存在 journal 的调用属于恢复，不是新事务：先只读识别既有事务，再在原 lock 下恢复持久化 write-set 和 phase；不得清理固定 candidate 后生成不同输入。该分支不违反“非法新输入零 journal”，因为它不创建新 journal，也不把调用方输入写入既有事务。

## 1.5 文件改动边界

### 生产代码与契约

| 文件 | 设计变更 |
|---|---|
| `skills/shared/crctl/scripts/crctl.mjs` | 收缩 `writeback-apply` 公共参数；提炼无写入的 advance preflight；`runGateChecks` 增加仅供 `fileExists` 使用的 planned-existing；注入 status outbox / advance audit adapter；更新 help |
| `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | 固定 generator map/candidate path、完整 preflight、baseline 复合 write-set、projection marker；增加 backlog 条目替换纯函数和 semantic merge tree 构造；初次与 rebuild 共用同一 prepare helper |
| `skills/shared/crctl/scripts/lib/durable-tx.mjs` | 仅登记 writeback projection 故障点；不改事务模型 |
| `skills/writeback/writeback-prd-sdd/SKILL.md` | 收缩为业务输入 + 一次 `writeback-apply` + 结果分类；删除 generator、candidate 和独立 advance |
| `skills/writeback/writeback-tasks/SKILL.md` | 删除 generator/candidate 路径；一次深原语调用 |
| `skills/writeback/writeback-traceability/SKILL.md` | 保留 milestone 业务草稿；删除 generator/candidate 路径；一次深原语调用 |
| `pipeline-templates/feature-writeback.pipeline.json` | 三个 writeback 节点只传业务输入并调用 Skill；baseline 节点删除独立 advance |
| `skills/shared/crctl/SKILL.md`、`skills/_index.yml` | 同步既有命令接口与深原语职责，不增加新 Skill |

### 测试

- `skills/shared/crctl/scripts/test/writeback-tx.test.mjs`
- `skills/shared/crctl/scripts/test/merge-tx.test.mjs`
- `skills/shared/crctl/scripts/test/archive-tx.test.mjs`
- `skills/shared/crctl/scripts/test/crctl.test.mjs`
- `skills/writeback/scripts/test/writeback.test.mjs`（generator 内部 ABI 保持时只补固定路径/调用边界断言，不重写算法测试）

本 CR 不修改 Agent、README、状态机、`gates.json`、`rules.json`、三个 generator 的内容转换算法、Multica 代码或 knowledge-base baseline 文档。

# 2. 数据模型

## 2.1 公共业务输入

`writeback-apply` 仅接受业务输入：

```text
cr_id
target stage: baseline | tasks | traceability
spec_id
target_version
baseline optional: milestone_name, brief
traceability required: milestone_file
workspace
```

删除公共生产参数：

```text
--candidate
--candidate-out
--generator
--manifest
```

stage 到 generator 的映射是 `workspace-transactions.mjs` 内固定常量，不做可注册配置：

```js
const WRITEBACK_GENERATORS = {
  baseline: "writeback-prd-sdd.mjs",
  tasks: "writeback-tasks.mjs",
  traceability: "writeback-traceability.mjs"
};
```

三个版本化脚本保留内部进程 ABI `--candidate-out`，但只有 `crctl` 可以构造和调用；它不是 Agent/Pipeline/Skill/公共 CLI 接口。

## 2.2 Candidate 路径

固定路径：

```text
{operational_workspace}/.crctl/candidates/{CR-ID}/{stage}/
  manifest.json
  blobs/{sha256}
  specs/... 或 delivery/...
```

约束：

- 根由 `resolveOperationalWorkspace()` 返回的 txws 派生，不接受调用方路径；
- `realpath(txws)` 与 candidate 已存在父链逐段检查，任何 symlink/junction 越界返回 `WRITEBACK_CANDIDATE_OUTSIDE_TX` 或 `WRITEBACK_SYMLINK_PARENT`；
- 调用 generator 前确保 txws 的 `.crctl/.gitignore` 使用既有 `*` 规则，`git check-ignore` 必须确认 candidate 被忽略；
- 新事务可清空本 stage 目录后重建；既有 journal 恢复必须复用原固定 candidate，不得重生成不同 manifest；
- archive/workspace 现有 txws 清理会连同 `.crctl/candidates` 删除，不新增清理状态或后台任务。

## 2.3 Manifest 内存快照

preflight 只读一次 `manifest.json`：

```js
{
  textLf,          // 原文 CRLF -> LF，一次读入
  digest,          // sha256(textLf)
  parsed,          // manifest v1
  files: [
    {
      path,
      beforeSha256,
      afterSha256,
      blobText      // 校验 blob hash 时一次读入，apply 阶段复用
    }
  ],
  plannedExisting  // Set<POSIX workspace-relative path>
}
```

`plannedExisting` 只能由 `parsed.files[].path` 生成，且生成前必须已完成 schema、stage、CR、spec-id、path safety、containment、symlink parent、allowlist、before/after hash、blob hash、generator hash、input digest 和 stage 目标矩阵校验。

manifest 文本、blob 文本和 digest 在事务期不二次读取。candidate 后续被修改不影响已通过 preflight 的内存快照；txws 目标仍由 before hash 和 recoverable write-set CAS 保护。

## 2.4 Baseline 状态候选

advance preflight 返回无副作用候选描述：

```js
{
  from: "merging",
  to: "writing-back",
  trigger: "writeback-prd-sdd",
  path: "change-requests/{CR-ID}/cr.md",
  beforeSha256: "<64-hex>",
  beforeText: "<canonical current text>"
}
```

目标文本使用共享的 `crMdStatusText()` 状态 writer 生成；本事务把首次生成的完整 after image/after hash 持久化并在恢复时复用，避免重跑时间变化产生第三值。受控时间字段的名称、兼容读取和渐进迁移继续由同一共享 writer 决定：本 CR 不复制 `updated`/`updated-at` 分支，也不抢占 CR-2026-039 的时间字段统一范围；若该切片先合入，本设计自动消费其统一后的 writer。`performAdvance()` 与 baseline writeback 共用同一无写入 advance preflight；前者随后走现有 CAS/commit，后者把候选转成 write-set entry。不得复制状态转换表或在 `applyWriteback()` 内硬编码门禁。

baseline staged set 固定为：

```text
manifest.files[].path
+ change-requests/{CR-ID}/cr.md
```

staged set 必须精确相等，多一项或少一项均 `WRITEBACK_STAGED_MISMATCH`。

## 2.5 Writeback journal 增量

沿用现有 writeback payload，只增加 baseline 投影和状态事实：

```json
{
  "cr": "CR-2026-038",
  "stage": "baseline",
  "phase": "start|committed|pushed|complete",
  "specId": "tools-cr-lifecycle",
  "committed": false,
  "commit": null,
  "baseSha": null,
  "pushed": false,
  "files": null,
  "statusTransition": {
    "from": "merging",
    "to": "writing-back",
    "trigger": "writeback-prd-sdd",
    "path": "change-requests/CR-2026-038/cr.md",
    "beforeSha256": "<64-hex>",
    "afterSha256": "<64-hex>"
  },
  "outboxEmitted": false,
  "auditEmitted": false
}
```

- tasks/traceability 的 `statusTransition` 为 null，不发送 status outbox 或 advance audit；
- 旧 journal 缺新布尔字段按 false 读取；
- `outboxEmitted` 和 `auditEmitted` 只在 adapter 成功后 durable save；
- outbox 文件名与 audit dedup key 均由 `{cr, from, to, commit}` 确定，关闭“发送成功、marker 保存前崩溃”的重复窗口；
- journal 不保存第二份状态机、gate 或 candidate registry。

## 2.6 Backlog 条目块

纯函数接口：

```js
replaceBacklogEntry(trunkText, sourceText, crId) -> mergedText
```

契约：

1. 对 trunk/source 建立 LF 解析视图，但使用原始行偏移切片，保证 trunk 非目标前缀/后缀字节不变；
2. 目标条目由同缩进 `- id: {CR-ID}` 起始，结束于下一个同级条目、同级注释边界或 EOF；边界外空行/注释属于 trunk，不被替换；
3. trunk 和 source 各自必须且只能命中一次目标 ID；0 次/多次均硬失败；
4. replacement 使用 source 目标条目的全部字段和嵌套块，包括 `owners`、`latest-checkpoint` 和未知字段；
5. 函数不 parse、不读取、不生成 `status`，也不修改其他条目；
6. 输出相同则允许 merge 继续，不制造额外提交层。

错误码固定为：

- `MERGE_BACKLOG_ENTRY_MISSING`：trunk 或 source 缺目标条目；
- `MERGE_BACKLOG_ENTRY_DUPLICATE`：trunk 或 source 目标条目重复；
- `MERGE_BACKLOG_STRUCTURE_INVALID`：缩进/边界无法唯一确定。

# 3. 接口契约

## 3.1 公共 CLI

```text
crctl writeback-apply <cr_id>
  --stage <baseline|tasks|traceability>
  --spec-id <id>
  --target-version <version>
  [--milestone-name <name>]
  [--brief <text>]
  [--milestone-file <workspace-relative-path>]
  --workspace <installation-workspace>
```

规则：

- baseline 接受可选 `milestone-name` / `brief`；
- tasks 不接受 milestone 参数；
- traceability 必须提供 `milestone-file`，其真实路径必须位于 operational workspace 内且父链无 symlink；
- 不接受任意状态、trigger、generator、candidate、manifest 或 output path；
- `--target-version` 缺失在入口 `BAD_ARGS` fail-fast；不从 README、文件名或 branch 猜测；
- `--candidate` / `--candidate-out` 作为未知或明确废弃参数返回 `BAD_ARGS`，不保留双入口。

成功输出保持既有主字段并增加状态/投影可观测字段：

```json
{
  "op": "writeback-apply",
  "cr": "CR-2026-038",
  "stage": "baseline",
  "txId": "<32-hex>",
  "phase": "complete",
  "changed": true,
  "commit": "<origin-confirmed-40-hex>",
  "status": "writing-back",
  "files": ["specs/...", "change-requests/CR-2026-038/cr.md"],
  "warnings": [],
  "recoverCommand": "crctl writeback-apply CR-2026-038 --stage baseline --spec-id ... --target-version ... --workspace ..."
}
```

幂等完成重放返回同一 commit、`changed=false`；可补发 warning 对应的投影，但不得新增 commit/push。

## 3.2 内部 `applyWriteback` 接口

```js
applyWriteback(ctx, {
  cr,
  stage,
  specId,
  targetVersion,
  milestoneName,
  brief,
  milestoneFile,
  workspace,
  validateBaselineAdvance,
  emitStatusEvent,
  emitAdvanceAudit
})
```

三个 callback 只由 `cmdWritebackApply()` 注入：

- `validateBaselineAdvance({ workspace: txws, plannedExisting })`：复用状态机与 gate，返回 §2.4 候选；
- `emitStatusEvent({ cr, from, to, trigger, commit, dedupName }) -> string|null`；
- `emitAdvanceAudit({ cr, from, to, trigger, commit, dedupKey }) -> boolean`。

非 baseline 不调用三个 callback。callback 缺失在任何 transaction/Git 副作用前 fail-fast，避免“生产调用者忘记注入却静默成功”。

## 3.3 `runGateChecks` planned-existing

```js
runGateChecks(ws, cr, targetStatus, gates, {
  specId,
  plannedExisting: Set<string>
})
```

仅 `check.type === "fileExists"` 分支执行：

```text
ok = fs.existsSync(path) || plannedExisting.has(normalizedRelativePath)
```

以下分支禁止读取 planned-existing：`globNonEmpty`、`passCondition`、`approval`、`deliveryIndexComplete`、`attemptsWithinLimit` 以及未知 gate。`plannedExisting` 非 `Set`、含 absolute/`..`/反斜杠或未落在当前 workspace 时直接 `GATE_PLANNED_PATH_INVALID`，不做字符串宽松匹配。

## 3.4 版本化 generator 内部调用

`runFixedGenerator()` 使用 `process.execPath` + `spawnSync(..., {shell:false})`，固定脚本路径由当前 Tools Root 派生。argv 只由 stage 配置和已校验业务输入组成：

| stage | 固定脚本 | 业务 argv |
|---|---|---|
| baseline | `writeback-prd-sdd.mjs` | workspace/cr/spec/version，可选 milestone-name/brief，内部 candidate-out |
| tasks | `writeback-tasks.mjs` | workspace/cr/spec/version，内部 candidate-out |
| traceability | `writeback-traceability.mjs` | workspace/cr/spec/version/milestone-file，内部 candidate-out |

不通过 shell 字符串、不读取脚本 stdout 返回的 manifest 路径作为信任输入；成功后只读取固定 `{candidateDir}/manifest.json`。generator 非零退出原样映射其结构化 error code；stdout 非法不影响固定路径判定。

## 3.5 Projection adapter

status outbox 固定：

```json
{
  "event_kind": "status",
  "cr_id": "CR-2026-038",
  "from_status": "merging",
  "to_status": "writing-back",
  "trigger": "writeback-prd-sdd",
  "commit_sha": "<origin-confirmed-sha>"
}
```

- `commit_sha` 禁止 `pending:`、空值或 txws 本地未确认 SHA；
- `dedup_name = status-{cr}-{commit}.json`；
- outbox 失败返回 `EMIT_FAILED` warning，不反转 Git 成功。

advance audit 固定记录 `kind=advance`、from/to/trigger/by/commit/result=success 和 `dedup_key=advance:{cr}:{commit}`。`auditLogOnce()` 在 append 前按 dedup key 检查现有 JSONL；命中即视为成功并补记 journal marker。audit 文件不可读/不可追加返回 warning，不抛出导致 Git 成功被报告为失败。

## 3.6 错误与恢复

| code/结果 | 触发 | 副作用与恢复 |
|---|---|---|
| `BAD_ARGS` | 缺业务参数、传废弃 candidate/generator 参数 | 零 candidate/journal/authority 写入 |
| generator 结构化错误 | 源文档/业务输入不合法 | 可有可丢弃 candidate；零 lock/journal/authority |
| `WRITEBACK_MANIFEST_*` | JSON/schema/stage/CR/spec/path/hash/digest/矩阵失败 | 零 lock/journal/authority；修正源后同命令重跑 |
| `WRITEBACK_GENERATOR_MISMATCH` | manifest 脚本 hash 与固定脚本不符 | 同上 |
| `GATE_BLOCKED` | baseline advance gate 未通过 | 同上；planned-existing 不扩展其他 gate |
| `WRITEBACK_REMOTE_STALE` | preflight 后或 commit 前 origin 前进 | 未发布 txws 回到新 origin；删除未发布 journal；同业务命令重生成 candidate |
| `WRITEBACK_REMOTE_HISTORY_REWRITTEN` | 已发布 commit 从 origin 历史消失 | 硬阻断，禁止 force/rebuild |
| `FAULT_INJECTED` | write-set/commit/push/projection 测试点 | 同命令按 journal 续跑 |
| `EMIT_FAILED` warning | origin confirmed 后 outbox/audit 失败 | exit 0；重放只补缺失投影 |
| baseline no-op + status=`merging` + 无匹配 journal | 检测到旧协议或不完整外部写入，无法证明同批发布 | `WRITEBACK_ATOMIC_FACT_MISSING` 硬失败；不制造状态单独提交 |
| complete replay | journal + origin 证明已完成 | exit 0、changed=false、零新 commit/push，仅补投影 |

# 4. 关键算法与流程

## 4.1 新 Writeback 事务 preflight

```text
resolve repositories + operational workspace
validate business args and current stage
read-only detect existing writeback journal
  existing -> enter §4.5 recovery branch
  none     -> continue new transaction

candidateDir = txws/.crctl/candidates/{cr}/{stage}
assert containment + no symlink parent + Git ignored
clear only this stage candidate directory
spawn fixed generator with shell=false
if generator noop:
  validate legal no-op state and return changed=false
read manifest exactly once, normalize CRLF -> LF, JSON.parse
validate manifest schema/stage/cr/spec-id/generator id/hash
validate candidate containment/path safety/allowlist/sorted/unique
read each blob once, validate ref/hash, retain blobText
validate inputDigest
validate every target beforeSha256 against txws disk
verify release-subjects snapshot
fetch origin and compare txws HEAD
  stale -> reset detached txws to new origin, return WRITEBACK_REMOTE_STALE
if baseline:
  plannedExisting = exact validated manifest paths
  validate fixed merging -> writing-back transition
  run writing-back gate with plannedExisting

only now acquire writeback lock and create journal
```

候选目录、fetch 和 stale reset 不是 authority 发布；非法 manifest 不创建 journal、lock 残留、target file、commit、push、outbox 或 success audit。

## 4.2 Baseline 复合 write-set

journal 创建后，使用共享状态 writer 生成一次 `cr.md` after image并随事务持久化；恢复只复用该 after image，不重新生成时间字段：

```text
entries = manifest files with cached blobText
entries += cr.md {beforeSha256, afterSha256, content=status writing-back}
applyWriteSet(txws, txRoot, txId, entries)
fault: writeback-after-apply

git add -- <exact entries paths>
assert staged names == exact entries paths
git commit with existing writeback trailers
persist commit/base/files/statusTransition
fault: writeback-after-commit
```

commit message 继续使用：

```text
writeback baseline {CR-ID}

AI-First-Op: writeback
AI-First-Tx: {txId}
AI-First-CR: {CR-ID}
AI-First-Writeback-Stage: baseline
```

不增加状态专用第二 commit，不调用 `performAdvance()` 的写入/commit/outbox 分支。

## 4.3 Lease push 与 origin-confirmed

沿用既有三分类：

- `confirmed`：remote 包含 journal commit；
- `pushable`：remote 仍为 expected base，执行精确 lease push；
- `rebuild`：未发布且 origin 前进，txws reset 后返回 `WRITEBACK_REMOTE_STALE`；
- `history-rewritten`：journal 认为已发布但 commit 不在 remote 历史，硬阻断。

每次 push 后 fetch 并确认 origin 包含 commit，确认前不得设置 `outboxEmitted`/`auditEmitted`，也不得调用 projection callback。

## 4.4 Origin-confirmed 后投影

```text
if stage == baseline and origin confirmed:
  if !outboxEmitted:
    emit deterministic status outbox(real commit)
    success -> save outboxEmitted=true
    failure -> warnings += EMIT_FAILED
  fault: writeback-after-status-outbox

  if !auditEmitted:
    auditLogOnce(dedup_key=advance:{cr}:{commit})
    success -> save auditEmitted=true
    failure -> warnings += EMIT_FAILED
  fault: writeback-after-advance-audit

save phase=complete
return success + warnings
```

两项投影彼此独立：outbox 失败不阻止 audit 尝试，audit 失败也不删除 outbox。重放按各自 marker 补缺项。确定性 outbox 名和 audit dedup key 处理 callback 成功后、journal marker 保存前崩溃窗口。

## 4.5 恢复与幂等

1. 命令先只读固定 key 的现有 journal；存在时不清空 candidate、不运行 generator。
2. 获取同一 writeback lock，`recoverWriteSet({txId})` 只恢复该事务。
3. `committed=false`：使用原固定 candidate 和 journal digest重新验证；write-set 已部分应用时由 before/after 三值恢复，不生成新时间戳。
4. `committed=true,pushed=false`：不重新应用/commit，按 journal commit 续推。
5. `pushed=true/phase=complete`：fetch 确认 commit 仍在 origin；不重新生成 candidate，不新增 commit/push。
6. baseline 依次补 `outboxEmitted` / `auditEmitted`；全部完成返回 `changed=false`。
7. candidate 在需要恢复 apply 且固定目录缺失时返回 `WRITEBACK_CANDIDATE_RECOVERY_MISSING`，禁止从已部分写入的 txws 反向猜 manifest；正常 archive 清理只发生事务完成后，不触发此路径。

## 4.6 `_backlog.yml` 语义合并纯函数

伪代码：

```text
replaceBacklogEntry(trunkRaw, sourceRaw, cr):
  trunkView = locateUniqueEntry(trunkRaw.replace(CRLF, LF), cr)
  sourceView = locateUniqueEntry(sourceRaw.replace(CRLF, LF), cr)
  assert each count == 1 and boundaries valid

  trunkOriginalRange = map normalized line range -> trunkRaw byte offsets
  sourceBlock = source normalized target block
  targetEol = detect EOL at trunk target range
  replacement = sourceBlock joined with targetEol

  return trunkRaw.prefix + replacement + trunkRaw.suffix
```

断言：

```text
result prefix before target === trunk prefix
result suffix after target === trunk suffix
extract(result, cr) === source target entry (EOL-normalized)
all non-target entry IDs/order === trunk
```

函数位于现有 `workspace-transactions.mjs`，直接提炼并复用当前 `matchEntryBlockTx()` 的条目定位语义；若需跨 `crctl.mjs` 共用，只把 locator 最小下沉到既有 `yaml-subset.mjs`，不再写第三份正则，也不新建 YAML patch 模块。现有 archive 条目读取继续复用同一 locator，但本 CR 不借机重写无关 archive editor。

## 4.7 Knowledge-base semantic merge tree

普通 repo 继续直接执行：

```text
git merge-tree --write-tree <baseSha> <sourceSha>
```

knowledge-base repo 在 initial prepare 和 remote rebuild 都调用同一个 `prepareMergeTree()`：

```text
trunkBacklog  = gitReadBlobRaw(<baseSha>, "change-requests/_backlog.yml")
sourceBacklog = gitReadBlobRaw(<sourceSha>, "change-requests/_backlog.yml")
mergedBacklog = replaceBacklogEntry(trunkBacklog, sourceBacklog, cr)

blobSha = git hash-object -w --stdin <<< mergedBacklog
create temporary GIT_INDEX_FILE under installation .crctl/tmp
GIT_INDEX_FILE=... git read-tree <sourceSha>
GIT_INDEX_FILE=... git update-index --cacheinfo <source-mode>,<blobSha>,change-requests/_backlog.yml
syntheticTree = GIT_INDEX_FILE=... git write-tree
syntheticCommit = git commit-tree <syntheticTree> -p <sourceSha>
mergeTree = git merge-tree --write-tree <baseSha> <syntheticCommit>
finalMergeCommit = git commit-tree <mergeTree> -p <baseSha> -p <sourceSha>
remove temporary index in finally
```

`gitRun/gitMust` 仅增加内部 `opts.env` 透传以设置固定 `GIT_INDEX_FILE`；不开放给 CLI/Skill。backlog 内容不得通过现有会对 stdout 执行 `trim()` 的 `gitMust()` 读取；增加一个仅封装固定 `git cat-file blob` argv 的 `gitReadBlobRaw()`，保留首尾空行、CRLF 与末尾换行，并以 Buffer/未裁剪 UTF-8 stdout 返回。source 文件 mode 由 `git ls-tree` 读取并要求为普通 blob，`update-index --cacheinfo` 沿用该 mode。临时 index 位于 `.crctl/tmp`，不入 Git。`hash-object`、synthetic `commit-tree` 只产生不可达对象，不移动 ref、不 checkout、不发布；最终 merge commit 的第二 parent 仍是原始 source SHA，release-subjects 和 ancestry 契约不变。

source backlog path 缺失、不是普通 blob、目标条目缺失/重复或 `merge-tree` 仍冲突时，在任何 repo publish 前硬失败。不得回退到整份 trunk、整份 source、行号拼接或 `-X ours/theirs`。

## 4.8 Caller 收缩

### Pipeline baseline 节点

```text
输入: cr_id, spec_id, target_version, optional milestone_name/brief
调用: writeback-prd-sdd Skill
成功: phase=complete，向 tasks 节点传递结构化结果
失败: abort；WRITEBACK_REMOTE_STALE 可重跑同一节点
```

删除 generator 命令、candidate_dir、manifestPath、独立 `advance --embedded` 和内部校验列表。

### 三个 Skill

每个 Skill 只保留：

1. 业务前置和必填参数；
2. 一次 `crctl writeback-apply` 调用；
3. `complete/noop/stale/history-rewritten/业务源错误` 分类；
4. “下一步以 `crctl next {cr_id}` 为准”。

traceability Skill 仍负责 milestone 业务内容草稿，因为这是业务判断；但不选择 generator 或 candidate 路径。

# 5. 技术选型与替代方案

| 决策 | 采用 | 否决及原因 |
|---|---|---|
| 原子边界 | 深化现有 `applyWriteback()` | baseline 后再 advance：远端可见事实分裂 |
| 状态校验复用 | 提炼 `performAdvance` 的无写入 preflight + callback | 在 transaction lib 复制状态机/gates：第二事实源；lib 反向 import CLI：循环依赖 |
| planned-existing | `Set<validated manifest path>`，只给 fileExists | 虚拟文件系统/候选内容 override：扩大 gate 信任面 |
| generator 选择 | 固定三项对象常量 | plugin/registry/factory：只有三个固定实现且无扩展需求 |
| candidate 生命周期 | txws `.crctl/candidates/{cr}/{stage}` + txws 现有清理 | manager/数据库/后台 GC/公共 query：重复 authority |
| 投影幂等 | journal marker + 确定性 outbox 名/audit key | exactly-once 协议或新 ledger：现有 at-least-once 投影已足够 |
| backlog 编辑 | 条目块纯函数，trunk 原文切片 | YAML serializer/第三方 parser：重排注释字段并增加依赖；模糊字符串：无法硬失败 |
| merge tree | 原生 Git 临时 index + hash-object/read-tree/update-index/write-tree/commit-tree | checkout/rebase/cherry-pick：增加工作树副作用；`-X ours/theirs`：丢目标或其他 CR 数据 |
| synthetic commit | 仅作 merge-tree 输入，最终 parent 仍原 source | 发布 synthetic parent：改变 release-subject ancestry 与审计语义 |
| stale 恢复 | reset detached txws 后同业务命令重生成 | rebase/cherry-pick candidate：candidate 不是 authority |
| no-op legacy | 无原子事实则硬失败 | 单独补状态 commit：继续制造本 CR 要消除的分裂事实 |

# 6. FR 到技术实现映射

| FR | 技术方案 | 主要验收 |
|---|---|---|
| FR-01 | §2.4 baseline 状态候选、§2.5 journal marker、§4.2 同一 write-set/commit、§4.3 origin confirmed、§4.4 投影补发 | AC-01～AC-04 |
| FR-02 | §2.3 manifest 一次读入、§3.4 固定 generator、§4.1 lock/journal 前完整 preflight、§4.5 recovery | AC-05～AC-07 |
| FR-03 | §2.6 条目模型、§4.6 纯函数、§4.7 原生 Git semantic tree、initial/rebuild 共用 helper | AC-08～AC-10 |
| FR-04 | §2.1 公共输入收缩、§2.2 固定 candidate、§3.1 无路径 CLI、§4.8 Caller 收缩 | AC-07、AC-11 |

覆盖率：4/4 FR；12/12 AC 均有设计落点。

## 6.1 AC 验收追溯

| AC | 设计锚点 | 自动验证 |
|---|---|---|
| AC-01 | §4.2 baseline 复合 write-set、§4.3 origin-confirmed | origin 同一 commit 的 tree 同时含 specs 目标与 `cr.md status=writing-back`；随后 tasks 不回退状态 |
| AC-02 | §2.3 `plannedExisting`、§3.3 gate 限权 | 精确 manifest 路径仅放行 `fileExists`；额外路径和其他 gate 类型拒绝且零写入 |
| AC-03 | §2.5 marker、§4.4 projection、§4.5 recovery | apply/commit/push/outbox/audit fault matrix，最终一 commit/一 status event/一 advance audit |
| AC-04 | §4.8 Caller 收缩、§8 Prompt 采纳 | Pipeline/Skill/生产测试零独立 writing-back advance；公共接口无任意状态参数 |
| AC-05 | §4.1 完整 preflight、§9.1 失败矩阵 | 每种 manifest/gate 错误断言零 journal/lock/target/commit/push/outbox/audit |
| AC-06 | §4.1 新事务与 §4.5 recovery 分流 | 非法输入失败后修正源并同命令成功，不出现前次输入导致的 `TX_INPUT_CONFLICT` |
| AC-07 | §2.1、§3.1、§3.4、§4.8 | active 公共 CLI/Skill/Pipeline 静态扫描无 candidate/manifest/generator 路径 |
| AC-08 | §2.6 纯函数、§9.3 参数矩阵 | 首/中/末条和 trunk 前后新增 CR；非目标字节、顺序、注释、空行不变 |
| AC-09 | §2.6 错误码、§4.7 publish 前 prepare | trunk/source 目标缺失/重复硬失败，所有 repo remote refs 不前进 |
| AC-10 | §2.6 source 完整块替换 | owners/latest-checkpoint/未知 v2 字段保留；helper 不读写 backlog status |
| AC-11 | §2.2 candidate 约定、§9.2 ignore/cleanup | 三 stage 只在固定目录生成、`git check-ignore` 通过、commit tree 无 candidate、txws 清理无残留 |
| AC-12 | §9.5 全量回归 | crctl/writeback 全套在 Ubuntu、Windows 全绿，旧 gate/assertion 不放宽 |

# 7. 安全、性能与兼容性

## 7.1 安全

- 所有 repo/trunk/txws/Tools Root 继续来自 workspace `dir-graph.yaml` resolver；
- public CLI 不接受 generator、candidate、manifest、任意 ref/status/trigger；
- generator 使用 argv + `shell:false`，不执行 shell 拼接；
- candidate、milestone-file、manifest target 都做 containment 和 symlink parent 校验；
- manifest allowlist、blob hash、before hash、input digest 和真实 generator hash全部保留；
- planned-existing 不提供内容，只提供已验证精确路径，且不影响非 `fileExists` gate；
- semantic merge 对缺失/重复/边界异常硬失败；不解析或传播 backlog status；
- push 继续使用精确 `--force-with-lease`，禁止 force push/自动 revert。

## 7.2 性能

- preflight 对 manifest 和每个 blob各读取一次，复杂度 O(candidate 总字节数)；
- backlog 替换对 trunk/source 各线性扫描一次，复杂度 O(backlog 字节数)；
- knowledge-base prepare 比现有流程增加固定数量本地 Git plumbing 命令，不增加网络往返；
- repo publish 保持串行，避免并发 lease 和恢复状态膨胀；
- 不增加 cache、worker pool、数据库或长期索引。

## 7.3 Windows / CRLF

- JSON/YAML/Markdown 解析前统一 `replaceAll('\r\n','\n')`；逐行解析使用 `split(/\r?\n/)`；
- manifest digest 使用一次规范化后的文本，blob/before hash继续锚定 generator 与磁盘约定的真实 UTF-8 内容；
- backlog matcher 使用 LF 解析视图和原始偏移，非目标 trunk 字节不因 CRLF 解析被重写；
- `spawnSync` 使用 `shell:false`、`process.execPath` 和 argv，路径含空格时无需 shell quote；
- 临时 index 路径由 `path.join()` 构造，通过 `env.GIT_INDEX_FILE` 传给 Git。

## 7.4 兼容与迁移

- `writeback-apply` 命令名和三 stage 不变，调用方一次性切换参数，不保留生产双入口；
- generator 的 deterministic transformation 和内部 `--candidate-out` ABI 不变，现有 generator 单测可继续直接调用；
- 旧 writeback journal 缺 projection marker 按 false；只有能证明既有 commit 和固定 candidate 的事务才恢复；
- 不迁移历史 baseline、旧 candidate 或旧分裂 commit；baseline noop 但仍在 merging 且无 journal 时硬失败并报告原子事实缺失；
- tasks/traceability 的状态和 commit 语义不变，仅由 crctl 内部代调 generator；
- 状态机、gates、archive、checkpoint 和 traceability schema 均不变。

## 7.5 可观测性

成功输出公开 stage、txId、phase、commit、status、files、warnings 和 recoverCommand，不公开 candidate 路径、generator 路径、journal 路径或本机临时 index。错误保留 code、phase、已确认 side effects 和 recovery command。status outbox 与 `kind: advance` success audit 都绑定 origin-confirmed commit；既有 `kind: writeback` 诊断审计也必须记录返回的 commit，但不替代前述状态审计。candidate 失败不产生 success audit。

# 8. Prompt 采纳影响

本 CR 不新增/删除 `crctl.mjs` dispatch `writeback-apply` 分支，也不修改 `controlled-shell/rules.json#protectedPaths.deny`；但会修改既有命令面参数和职责，因此按强约束主动列出所有直接生产调用方，评审时逐项核对：

| 调用方 | 现状 | 应改为 |
|---|---|---|
| `skills/writeback/writeback-prd-sdd/SKILL.md` | Skill 调 generator、选择 candidate_dir、传 manifestPath，再独立 advance | 一次 `crctl writeback-apply {cr} --stage baseline --spec-id {id} --target-version {ver} ...`；消费 phase/commit/status/warnings |
| `skills/writeback/writeback-tasks/SKILL.md` | Skill 调 tasks generator并传 candidate | 一次 `writeback-apply --stage tasks`，只传业务输入 |
| `skills/writeback/writeback-traceability/SKILL.md` | Skill 调 trace generator并传 candidate | Skill 只起草 milestone_file，然后一次 `writeback-apply --stage traceability` |
| `pipeline-templates/feature-writeback.pipeline.json` baseline 节点 | 复制 generator/apply/advance 三段算法 | 只传业务输入、调用 Skill、按结构化结果中止或进入下一节点 |
| 同 Pipeline tasks/traceability 节点 | 复制 generator/candidate/apply 算法 | 各调用一次对应 Skill，不消费内部路径 |
| `skills/shared/crctl/SKILL.md` | help 契约仍公开 `--candidate` | 更新为业务参数和原子 baseline 语义 |
| `skills/_index.yml` crctl/writeback brief | 描述 candidate manifest 由调用方提供 | 描述 crctl 内部固定 generator 与复合 writeback |
| `skills/shared/crctl/scripts/test/archive-tx.test.mjs` | baseline 后测试独立 `advance --embedded` | 直接断言 baseline 返回 writing-back 且同一 commit，无第二 advance |
| `skills/shared/crctl/scripts/test/writeback-tx.test.mjs` | 测试从外部构造 candidate 并传路径 | 黑盒生产测试只传业务输入；恶意 manifest 通过测试 seam/内部 validator 单测覆盖，不恢复公共 candidate 参数 |

README 和 Agent 的全面职责文本收敛属于 CR-2026-042，本 CR 不借机改写；但本 CR 修改的 Skill/Pipeline 不得继续保留与新命令冲突的算法副本。

# 9. 测试与故障注入

## 9.1 Writeback preflight 零副作用矩阵

逐项制造：非法 JSON、manifest v、stage、CR、spec-id、absolute/`..`/反斜杠/重复路径、symlink parent、allowlist、排序、重复路径、before/after hash、blob ref/missing/hash、generator id/hash、input digest、目标矩阵和 baseline gate 失败。

每例断言：

```text
writeback journal count unchanged
writeback lock 不存在
txws target files/hash/index unchanged
txws staged set empty
origin commit count unchanged
status outbox count unchanged
advance success audit count unchanged
```

随后修正同一业务源并重跑，必须成功且不得出现由失败输入产生的 `TX_INPUT_CONFLICT`。

## 9.2 Baseline 原子与恢复矩阵

1. happy path：origin 单个 commit 同时含 specs 三目标和 `cr.md status=writing-back`；
2. planned-existing：两个 specs 路径通过 `fileExists`，额外/未验证路径拒绝；非 fileExists gate 不受 Set 影响；
3. `writeback-after-apply`、`writeback-after-commit`、`writeback-after-push` 各中断一次后重跑；
4. origin confirmed 后 outbox 写失败、audit 写失败，命令 exit 0 + warning；修复后重放只补缺项；
5. `writeback-after-status-outbox` / `writeback-after-advance-audit` 崩溃窗重放，确定性去重；
6. complete replay：changed=false，commit/status/event/audit 各自唯一；
7. baseline 后立即执行 tasks，状态保持 writing-back，不 reset 到 merging；
8. origin preflight 前进、commit 后前进、push response lost、history rewrite；
9. candidate 目录 `git check-ignore` 为真，commit tree 不含 `.crctl/candidates`；
10. archive/workspace 清理后 txws candidate 随资源删除，无独立 cleanup 任务。

## 9.3 Backlog 纯函数参数化矩阵

- 目标 CR 位于首条、中间、末条；
- trunk 在目标前、后、前后同时新增 CR；
- trunk 其他条目含注释、空行、未知字段、嵌套列表；
- source 目标含三 owners、latest-checkpoint、未知 v2 字段；
- LF、CRLF 和含空格/引号标量；
- trunk/source 目标缺失和重复；
- 结果逐字比较：prefix/suffix、非目标条目、顺序、注释、空行完全等于 trunk；目标块等于 source 的 LF 语义；
- 静态断言 semantic merge helper 不访问 `.status`、`status:` 或 parseYaml 后的条目字段。

## 9.4 Merge 集成矩阵

1. 三 bare remote，knowledge-base backlog 冲突但目标条目可唯一替换，merge 成功；
2. 最终 tree 保留 trunk 新 CR，并采用 source 目标条目；
3. 最终 merge commit parents 精确为最新 base + 原 source，synthetic commit 不在 parent/ref；
4. initial prepare 和 remote stale rebuild 产生相同语义；
5. trunk/source 目标缺失/重复时 `MERGE_BACKLOG_ENTRY_*`，所有 repo remote ref 均不前进；
6. 其他文件真实冲突仍 `MERGE_PREPARE_CONFLICT`，不被 semantic backlog 逻辑吞掉；
7. multica/tools repo 继续使用普通 merge-tree，无 backlog 特例。

## 9.5 静态契约与全量回归

- active Agent/Pipeline/Skill/crctl help 不出现公共 `--candidate`、`--candidate-out`、manifestPath、generator path；
- feature-writeback baseline 后不存在 `advance --to writing-back`；
- Pipeline 节点不含 journal/CAS/merge/stage/commit/push 算法；
- generator unit tests仍覆盖确定性转换和 manifest canonical 公式；
- `node --test skills/shared/crctl/scripts/test/*.test.mjs`；
- `node --test skills/writeback/scripts/test/*.test.mjs`；
- `node skills/shared/crctl/scripts/check-skill-matrix.mjs`；
- `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce`；
- 所有 Pipeline JSON `JSON.parse`；
- Ubuntu 与 Windows CI 全绿，不删除测试、不放宽 gate/assertion。

# 10. 实施顺序与回滚

## 10.1 最小提交顺序

1. **T01 红测**：冻结新 CLI、preflight 零 journal、planned-existing、同 commit 状态、backlog 纯函数与 merge 集成失败用例。
2. **T02 纯函数**：advance 无写入 preflight、`fileExists` planned-existing、backlog locator/replacer、固定 generator map/candidate resolver。
3. **T03 Writeback 深化**：内部 generator/preflight、baseline write-set、projection callback/marker/fault points、恢复测试。
4. **T04 Merge 接入**：临时 index semantic tree，initial/rebuild 共用 helper，缺失/重复硬失败集成测试。
5. **T05 调用方切换**：同一提交修改三个 Skill、feature-writeback Pipeline、crctl Skill/help/index 和旧测试调用；删除独立 advance 与公共 candidate 参数。

T02～T04 期间新路径尚无生产调用方，便于独立验证；T05 必须同提交切换接口，不留双入口。

## 10.2 回滚

- T02/T03/T04 在 T05 前可独立 revert，旧调用方仍使用旧接口；
- T05 必须整体 revert，不能只恢复 Skill 或只恢复 CLI；
- 已由新 baseline 事务发布的 commit 包含状态和 specs，代码回滚不拆分该事实，也不生成补偿 revert；
- in-flight journal 按其记录的代码版本完成或人工阻断，禁止删除 journal/手改账本；
- semantic merge 已发布的 commit 是普通双亲 merge commit，可由 Git 历史审计；不回写旧全文件冲突模型。

# 11. 风险、残余与不做事项

| 风险 | 控制 |
|---|---|
| preflight 与 lock 间 txws/origin 变化 | before hash、HEAD/base 复核、lease push；第三值 stale/recovery，不接受旧 candidate |
| candidate 同 stage 并发生成 | manifest/blob 一次读入与 hash 校验；authority lock在 apply 前串行化；竞争最多导致 preflight hard fail |
| callback 成功、marker 保存前崩溃 | outbox deterministic name + audit dedup key + journal marker |
| synthetic tree 改变 ancestry | 最终 commit parents 显式使用 base 和原 source；测试锁 parent |
| matcher 把条目间注释算入目标 | 同级注释/空行边界规则 + prefix/suffix 字节测试 |
| Windows autocrlf 造成误报 | Git blob读取用于 merge、LF 解析视图、原始偏移替换、双平台测试 |
| 旧协议已回写 baseline 但未推进状态 | 不伪造原子事实；`WRITEBACK_ATOMIC_FACT_MISSING` 硬失败，作为显式迁移事件另行处理 |
| public 参数收缩遗漏调用方 | 全仓静态扫描 + T05 同提交切换；历史文档不作为 active 契约 |

明确不做：

- 不实施来源规格 FR-04～FR-09、FR-11～FR-16 或 Phase E；
- 不新增任意复合状态 API、generator/candidate manager、plugin/schema/error registry、YAML patch 框架或 workflow engine；
- 不修改状态机、gates、人工审批、测试执行、review canonical、CR 时间字段、traceability evidence 或 archive 严格门；
- 不修改 Agent/README/CI 全面职责文本；这些属于 CR-2026-042；
- 不增加后台清理、数据库、消息队列、分布式锁、2PC、npm 依赖；
- 不允许 force push、force rollback、自动补偿 revert、rebase/cherry-pick candidate、手工编辑 `_backlog.yml`/`cr.md`/journal；
- 不批量迁移历史 baseline、candidate、journal 或旧分裂 commit。

# 12. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-14 | v0.1.0 | Ray | 初始设计：固定 generator/candidate 内部化、lock/journal 前完整 preflight、baseline 状态同 write-set/commit/push、origin-confirmed status outbox与 advance audit、目标 CR backlog 条目语义合并及 Git synthetic tree；FR 覆盖 4/4，AC 覆盖 12/12 |

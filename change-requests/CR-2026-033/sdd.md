---
id: CR-2026-033-sdd
type: SDD
cr-ref: CR-2026-033
title: tools Checkpoint 收敛：单一深原语 + latest-checkpoint + 多仓恢复（TCA-011）技术设计
status: draft
created: 2026-08-13T09:58:32+08:00
updated: 2026-08-13T18:51:56+08:00
---

# 1. 架构概览

## 1.1 设计目标

本设计落实 PRD FR-01～FR-09，将 checkpoint 从 `push-progress` Skill 和 Pipeline prompt 中的逐仓 Git 算法收敛为一个可重入的 `crctl checkpoint` 深原语。目标不是伪造多仓 ACID，而是以 **逐仓 lease publish + exact-head freshness + 持久化 journal + knowledge-base metadata commit** 建立唯一完整批次可见点。

核心不变量：

1. 一次 checkpoint 覆盖 `dir-graph.yaml#repositories` 中全部 active repo；repo、branch、worktree、remote 与 knowledge-base 身份全部由既有 resolver 派生。
2. 所有本地 tracked/untracked 未忽略变化均进入对应 source commit；clean repo 不造空 commit，但仍进入当前批次。
3. 只有 knowledge-base metadata commit 被 origin 精确确认后，`latest-checkpoint` 才成为完整 checkpoint authority。
4. `latest-checkpoint` 只有一个当前快照；Git log 保留历史，journal 只保留未完成事务恢复状态。
5. Skill/Pipeline 只调用一次 `crctl checkpoint`，不拥有 Git、账本编辑或恢复分类。

## 1.2 分层与依赖

```text
Pipeline（是否调用、message、失败中止）
  ↓
push-progress Skill（一次 crctl checkpoint 调用 + 结果解释）
  ↓
crctl.mjs
  ├─ 非终态守卫、CLI 参数、固定 JSON 输出、audit、checkpoint outbox
  └─ checkpointCr(ctx, input)
       ├─ repository/worktree resolver + Git/source commit/publish
       ├─ latest-checkpoint 账本候选与 metadata commit
       ├─ checkpoint-specific exact-head 分类
       └─ durable-tx.mjs
            lock / journal / fault points / durable write
  ↓
Node 标准库 + Git + origin requirement/{CR-ID}
```

依赖保持单向：`workspace-transactions.mjs` 不反向依赖 `crctl.mjs`，也不直接发 outbox；它返回 metadata commit 与结构化结果，由 CLI 层沿用现有 `emitOutboxEvent()` 和 `auditLog()`。

## 1.3 Authority 与完整批次可见点

| 阶段 | Authority | 说明 |
|---|---|---|
| preflight/no-op | 当前 worktree、origin refs、现有 `latest-checkpoint` | 只读/fetch；未创建 journal |
| source committed/published | 各 repo local commit + remote ref | 是可恢复资源，不是完整 checkpoint |
| metadata committed | KB local metadata commit | 尚未被 origin 确认，不供 reader 消费 |
| metadata confirmed | KB remote HEAD = metadata commit | 完整 checkpoint 唯一可见点 |
| complete | metadata-confirmed Git 事实 + audit/outbox 投影 | journal 可清理；outbox 失败不反转 Git authority |

非 KB repo 的完整条件是 remote HEAD 精确等于 source SHA。KB 的完整条件是 remote HEAD 精确等于 metadata commit，且 metadata commit 的直接父提交等于 `latest-checkpoint.repositories` 中 KB 的 source SHA。

## 1.4 模块边界与文件落点

### 既有模块修改

| 文件 | 变更 |
|---|---|
| `skills/shared/crctl/scripts/lib/durable-tx.mjs` | 增加 `checkpoint` op/payload 与 checkpoint fault points；复用现有锁、journal 与 durable write |
| `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | 增加 `checkpointCr()`、batch/editor/classifier 纯函数和敏感文件预检；不新增第二模块 |
| `skills/shared/crctl/scripts/lib/yaml-subset.mjs` | 将 `matchEntryBlock()` 从 crctl 私有作用域最小下沉并导出，供旧账本命令与 checkpoint editor 共享 |
| `skills/shared/crctl/scripts/crctl.mjs` | 增加 `cmdCheckpoint`、help/dispatch/import/audit/outbox；删除 `checkpoint-add` 及旧 editor/help/dispatch/tests |
| `skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs` | 新增三 bare remote、多仓恢复与 exact-head 集成测试 |
| `skills/shared/crctl/scripts/test/durable-tx.test.mjs` | checkpoint envelope/fault point 单元测试 |
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | CLI 输出/状态守卫/outbox 测试；删除旧 checkpoint-add 契约测试 |

### T05 caller/reader 迁移

- `skills/sync/push-progress/SKILL.md`
- `skills/sync/list-remote-checkpoints/SKILL.md`
- `skills/sync/resume-from-remote/SKILL.md`
- `skills/sync/pull-progress/SKILL.md`（只移除已删除 `last-push-*` 的摘要依赖，ff-only 算法不变）
- `pipeline-templates/requirement-authoring.pipeline.json`
- `pipeline-templates/architecture-design.pipeline.json`
- `pipeline-templates/code-implementation.pipeline.json`
- `pipeline-templates/resume-cr.pipeline.json`
- `README.md`、`skills/_index.yml`、`ARCHITECTURE.md`

`ARCHITECTURE.md` 在 SDD 撰写期只读；实现期 T05 随新增 crctl 写命令同步更新其入口点/代码地图/运行事实，不另开审批节点。

# 2. 数据模型

## 2.1 `_backlog.yml#latest-checkpoint`

每个 CR 的 `_backlog.yml` 条目只保留一个当前快照：

```yaml
latest-checkpoint:
  batch-id: 0123456789abcdef
  repositories:
    - repo: ai-first-platform-docs
      source-sha: <40-hex>
      remote-ref: refs/heads/requirement/CR-2026-033
    - repo: multica
      source-sha: <40-hex>
      remote-ref: refs/heads/requirement/CR-2026-033
    - repo: tools
      source-sha: <40-hex>
      remote-ref: refs/heads/requirement/CR-2026-033
```

约束：

- `repositories` 按 repo id 字典序稳定排序，数量与事务启动时 active repository graph 完全一致；
- `repo` 唯一，`source-sha` 必须为 40 位小写 hex，`remote-ref` 固定为 `refs/heads/requirement/{cr}`；
- 不持久化 message、actor、时间、本地路径、txId、pushed-at/by/summary；
- editor 每次整块替换 `latest-checkpoint`，同一 metadata commit 删除 `_backlog.yml` 当前 CR 条目中的旧 `checkpoints[]`、`remote-ref`、`last-push-at`、`last-push-by`；
- editor 不修改 `cr.md`，也不改 `_backlog.yml` 其他 CR、未知字段或注释；输入先 CRLF→LF，目标条目/owned key 重复或结构异常时硬失败。

## 2.2 batch-id canonical encoding

为避免字符串拼接歧义，PRD 公式在实现中固定为无空白 canonical JSON：

```js
const input = {
  cr: "CR-2026-033",
  graphDigest: "<64-hex>",
  repositories: [
    { repo: "<id>", sourceSha: "<40-hex>", remoteRef: "refs/heads/requirement/CR-2026-033" }
  ]
};
const batchId = sha256(JSON.stringify(input)).slice(0, 16);
```

对象键顺序按上例固定，repositories 先按 repo id 排序。message、actor、时间、本地路径、txId 不进入 input。同 graph/source facts 重放得到同 id；任一 source SHA、remote-ref 或 graphDigest 变化得到新 id。

## 2.3 checkpoint journal payload

`durable-tx.mjs` 的 `OPS`/`PAYLOAD_KEYS` 增加 `checkpoint`，envelope 增加 `checkpoint: null`。不修改现有 register/merge/writeback/archive/ledger payload。

```json
{
  "v": 1,
  "txId": "<32-hex>",
  "op": "checkpoint",
  "cr": "CR-2026-033",
  "phase": "prepared|sources-committed|repos-confirmed|metadata-committed|metadata-pushed|complete",
  "graphDigest": "<64-hex>",
  "inputDigest": "sha256(JSON.stringify({cr,graphDigest}))",
  "sideEffects": [],
  "lastError": null,
  "checkpoint": {
    "repositories": [
      {
        "repo": "tools",
        "remoteRef": "refs/heads/requirement/CR-2026-033",
        "baseSha": "<40-hex>",
        "sourceSha": "<40-hex-or-null>",
        "remoteBefore": "<40-hex-or-null>",
        "phase": "prepared|committed-local|pushed|confirmed"
      }
    ],
    "batchId": null,
    "kbSourceSha": null,
    "metadataCommit": null
  }
}
```

journal 可记录本机恢复细节，但这些字段不进入 batch-id 或公开 snapshot。`inputDigest` 只绑定 CR 与 repository graph，source facts 由 journal 内各 repo 字段绑定，并允许在 metadata commit 前因恢复重扫而前进。graph 在首个 source commit/push 后变化返回 `GRAPH_CHANGED_DURING_TRANSACTION`。metadata commit 是 source 集合冻结点；其后出现的本地变化属于下一批，不改写已生成的 metadata commit。metadata confirmed 后把 phase 写为 complete；确认 authority 后可删除该 completed checkpoint tx 目录。若进程死在 complete 后、删除前，下一次非 no-op 调用先验证该 batch 仍为 authority，再清理旧 complete journal 并创建新事务。

## 2.4 fault points

一次登记以下固定 point；未知 point 继续 `UNKNOWN_FAULT_POINT`：

- `checkpoint-after-source-commit`
- `checkpoint-after-push`
- `checkpoint-after-confirm`
- `checkpoint-after-metadata-commit`
- `checkpoint-after-metadata-push`

point 只用于确定性测试，不成为公共恢复 API。

# 3. 接口契约

## 3.1 公共 CLI

```text
crctl checkpoint <cr_id> [--message <text>] --workspace <installation-workspace>
```

输入只接受 CR-ID 与可选 message。repo、branch、worktree、trunk、remote、batch-id、actor、时间均内部派生；不接受 files/glob/staged-only/ignore/allow-sensitive/status 等参数。

成功固定输出：

```json
{
  "op": "checkpoint",
  "cr": "CR-2026-033",
  "txId": "<32-hex>",
  "batchId": "0123456789abcdef",
  "phase": "complete",
  "repositories": [
    {
      "repo": "tools",
      "sourceSha": "<40-hex>",
      "remoteRef": "refs/heads/requirement/CR-2026-033",
      "confirmed": true
    }
  ],
  "metadataCommit": "<40-hex>",
  "changed": true,
  "recoverCommand": "crctl checkpoint CR-2026-033 --workspace <workspace>"
}
```

no-op 返回当前 batch、`txId=null`、`changed=false`；`txId` 字段仍存在，但 null 明确表示 journal 前快速路径，不伪造可恢复事务身份。no-op 不建 journal、不更新时间、不 push。失败在 journal 创建后返回非空 `txId/phase/sideEffects/recoverCommand`；零副作用 preflight 错误可省 sideEffects。所有事务错误经既有 `TxError → runTxAsync() → fail()` 转换。

不新增 `checkpoint status`。只读远端查询继续由 `list-remote-checkpoints` Skill 提供。

## 3.2 内部函数

`workspace-transactions.mjs` 新增：

```js
checkpointCr(ctx, { cr, message, workspace })
editLatestCheckpoint(backlogText, cr, snapshot)
checkpointBatchId({ cr, graphDigest, repositories })
classifyCheckpointRemote({ remoteSha, sourceSha, remoteIsSourceAncestor, sourceIsRemoteAncestor, journalSaysPublished })
```

后三个为无 I/O 纯函数并直接单测。`checkpointCr` 是唯一 Git/账本事务处理器；不建 interface/class/factory/registry。

`yaml-subset.mjs` 新增导出：

```js
matchEntryBlock(text, id)
```

`crctl.mjs` 现有 task/owner/backlog/inbox editor 改为 import 该函数，避免复制跨行条目定位器。

## 3.3 exact-head 分类

| Git 事实 | 分类/动作 |
|---|---|
| remote == source | `confirmed` |
| remote 不存在 | 以“ref 必须仍不存在”的 lease 创建，随后精确确认 |
| remote 是 source 祖先 | `pushable`，以当前 remote SHA 做 lease fast-forward，随后精确确认 |
| source 是 remote 祖先且不等 | `CHECKPOINT_REMOTE_ADVANCED`；不写 metadata，提示先同步后重做 |
| 双方分叉 | `CHECKPOINT_REMOTE_DIVERGED`；不 merge、不 push |
| journal 标记已发布，但 remote 不再包含 source | `CHECKPOINT_REMOTE_HISTORY_REWRITTEN` |

该分类独立于既有 `classifyRemoteCommit()`，不得修改 register/merge/writeback/archive 的“commit 是 remote 祖先即可 confirmed”语义。

## 3.4 checkpoint outbox

现有 Multica `server/internal/governance/crsync.go` 消费 `event_kind=checkpoint` 以补全 embedded status 的 `projected_commit`，因此该事件不能随 `cmdGit` 迁移而丢失。

新契约：

- 仅在完整批次 metadata confirmed 后，由 `cmdCheckpoint` 发一次 checkpoint 事件；
- `commit_sha` 固定为 KB metadata commit；payload 可带 `batch_id` 和已确认 repo 摘要；
- `dedup_name` 固定为 `checkpoint-{cr}-{metadataCommit}.json`，复用现有 emitter 的原子写入与同名去重；恢复可重复调用 emitter，但同一 metadata 只留一份待采集事件；
- no-op 不创建新事件；事务中间逐仓 push 不发事件，避免 projected_commit 指向半批次；
- outbox 失败只写 audit，不回滚 Git authority，也不改变公共成功字段。

Multica 不改代码；现有 `TestCheckpointFillsProjectedCommitForEmbedded` 保持通过，tools 侧增加“完整批次确定性去重/no-op 不新增事件”契约测试。

## 3.5 错误码与恢复契约

| code | 触发条件 | 副作用与恢复 |
|---|---|---|
| `CHECKPOINT_WORKTREE_MISSING` | active repo 的 `{repo.worktreePath}/{cr}` 不存在 | 初始 preflight 零副作用；恢复期保留既有 `sideEffects` 并返回同一 `recoverCommand` |
| `CHECKPOINT_WORKTREE_UNREGISTERED` | 路径存在但不在该 repo `git worktree list` | 同上；不自动 adopt/remove |
| `CHECKPOINT_BRANCH_MISMATCH` | worktree 当前分支不是 `requirement/{cr}` | 同上；不自动 checkout |
| `CHECKPOINT_SNAPSHOT_INVALID` | `latest-checkpoint` 缺字段、重复 repo、SHA/ref/graph 集合非法 | journal 前零副作用；不静默降级为“无 snapshot” |
| `CHECKPOINT_SENSITIVE_PATH` | 固定敏感路径或私钥头命中 | 全仓零 add/commit/push，返回命中 repo/path，不输出文件内容 |
| `CHECKPOINT_WORKTREE_CHANGED_DURING_TRANSACTION` | source commit/hook/push 后 worktree 或 index 又变化，metadata 前最终检查不静稳 | 不生成 metadata；保留已有 local commit/push 于 `sideEffects`，返回同一 `recoverCommand`，重跑重做受影响 source |
| `CHECKPOINT_REMOTE_ADVANCED` | source 是 remote 祖先且不等 | 不写 metadata；保留先前 repo 副作用，提示先同步后重做 |
| `CHECKPOINT_REMOTE_DIVERGED` | source 与 remote 分叉 | 不 merge/push/metadata；保留先前副作用并返回恢复命令 |
| `CHECKPOINT_REMOTE_HISTORY_REWRITTEN` | journal 已发布的 source 不再被 remote 包含 | 不继续 publish/metadata；人工确认 remote 历史后重跑 |
| `GRAPH_CHANGED_DURING_TRANSACTION` | 首个 source 副作用后 repository graph digest 变化 | 保留 sideEffects，禁止用新 graph 完成旧 journal |
| `TX_LOCK_HELD` | 同 CR checkpoint 锁已被持有 | 本调用零新副作用；稍后原命令重试 |
| `TX_INPUT_CONFLICT` / `TX_RECOVERY_CONFLICT` / `TX_WRITESET_INVALID` / `TX_BLOB_MISMATCH` | 既有 journal/write-set 与当前事实不一致 | 透传既有 durable-tx 语义，不覆盖第三值；返回 txId、phase、sideEffects、recoverCommand |
| `TX_GIT_FAILED` | 固定 argv 的 Git 操作失败 | journal 前为零副作用；journal 后返回已记录副作用与恢复命令 |
| `UNKNOWN_FAULT_POINT` / `FAULT_INJECTED` | 测试故障点未登记 / 已命中 | 前者零写入；后者保留命中前 journal 与 sideEffects，仅测试使用 |

所有 journal 后错误固定返回 `txId`、`phase`、`sideEffects`、`recoverCommand`；journal 前错误返回 `txId=null` 且不伪造恢复状态。错误表不新增通用错误框架，只冻结 checkpoint 对现有 `TxError`/`runTxAsync()` 的使用。

# 4. 关键算法与流程

## 4.1 全仓 preflight 与敏感文件检查

在任何 `git add/commit/push` 和新 journal 创建之前：

1. 以公共参数 `--workspace=<installation-workspace>` 调用 `resolveRepositories(workspace)`，只用它派生 Installation Root、active repo graph 与 worktree roots；不要求 `ctx.cr` 非空或 operation workspace 自身位于 CR worktree；
2. 以显式 `cr` 对每仓定位 `{repo.worktreePath}/{cr}`，验证真实路径受 containment、路径存在且已登记在该 repo `git worktree list`、当前分支恰为 `requirement/{cr}`；
3. 从 knowledge-base 的 `{kb.worktreePath}/{cr}/change-requests/{cr}/cr.md` 读取 status；`cmdCheckpoint` 复用状态机事实源，只允许非终态；
4. fetch 每仓 `origin requirement/{cr}` 并记录精确 remote HEAD（允许首次不存在）；
5. 以 `git diff --name-only -z --diff-filter=ACMR HEAD --` 收集 tracked 新增/修改/rename 目标，以 `git ls-files --others --exclude-standard -z` 收集未忽略 untracked；对 NUL path 去重，不自行解析 porcelain rename 双路径；
6. 先对全部候选 Git POSIX path 执行固定路径规则，再只读取其中当前存在的普通文件检查 `-----BEGIN ... PRIVATE KEY-----` 头；
7. 任一仓失败则全仓零 add/commit/push，敏感命中统一 `CHECKPOINT_SENSITIVE_PATH`。

固定路径规则与 PRD FR-02 完全一致。路径比较大小写精确；symlink/目录/已删除文件不做内容读取，仍由 Git path 与 repo containment 约束。恢复调用在任何新 add/commit/push 前执行同一全仓敏感预检。扫描复杂度为本轮变化普通文件总字节数，不引入 scanner 依赖、porcelain parser 或例外配置。

## 4.2 journal 前 no-op

仅当以下条件全部成立才返回 no-op：

- 现有 `latest-checkpoint` schema 合法；以当前 graphDigest 与 snapshot repositories 重算 batch-id，结果等于存量 batch-id（由此证明 graph/source facts 一致）；
- 所有 worktree 无未忽略变化；
- 每个非 KB repo：本地 HEAD、remote HEAD、snapshot source SHA 三者精确相等；
- KB：本地/remote HEAD 均为当前 metadata commit，metadata commit 的直接父提交等于 snapshot KB source SHA，remote commit 内的 `_backlog.yml` 包含同一 snapshot；
- repositories 集合、顺序和 remote-ref 完全一致。

满足时返回当前 batch、metadataCommit=KB remote HEAD、`changed=false`；不调用 `loadOrCreateJournal()`，不更新时间、不写 audit/outbox、不 push。message 变化不影响判定。

## 4.3 source commit

no-op 不成立后创建 checkpoint journal，并按 repo id 稳定顺序处理：

```text
git add -A
git diff --cached --quiet
  exit 0 -> sourceSha = HEAD
  exit 1 -> git commit --no-gpg-sign --file=-，sourceSha = new HEAD
  其他   -> TX_GIT_FAILED
durable save sourceSha + local-commit sideEffect（若有）
复核 worktree/index clean；dirty -> CHECKPOINT_WORKTREE_CHANGED_DURING_TRANSACTION
journal repo.phase = committed-local
```

commit message 保持 `wip: {cr} {repo} checkpoint{messageSuffix}`。journal 在每个本地 commit 后 durable 保存；崩溃重跑时若 `HEAD == sourceSha` 且 worktree/index clean 则不重复 commit。若 hook 或外部写入使其再次 dirty，本次不得沿用旧 sourceSha 进入 metadata，按 §4.6 在恢复调用中重新 capture；不在单次命令内无限循环等候外部写入停止。

## 4.4 非 KB publish

对非 KB repo 按 id 排序：

1. fetch 并重读 remote HEAD；
2. 用 checkpoint-specific classifier 判定；
3. `pushable` 时只在 ancestry 已证明 fast-forward 后执行带精确 expected SHA 的 lease push；首次创建要求 ref 仍不存在；
4. push 后再次 fetch/ls-remote，只有 remote HEAD == sourceSha 才记 `confirmed`；
5. push 响应丢失时，重跑通过 remote == source 判 confirmed，不重复 push；
6. 任一 advanced/diverged/history-rewritten 立即中止，不生成 metadata。

已发布 repo 是可恢复副作用，失败 JSON 必须列在 sideEffects 中。

## 4.5 KB metadata commit

所有非 KB repo confirmed 后：

1. 重新检查全部 active repo：`HEAD == journal.sourceSha` 且 worktree/index clean；任一 repo 不满足则抛 `CHECKPOINT_WORKTREE_CHANGED_DURING_TRANSACTION`，不生成 metadata，交由下一次同命令按 §4.6 重新 capture/publish；
2. 将当前 KB HEAD 固定为 `kbSourceSha`；确认 KB remote 等于它或是它的祖先，其他关系按 exact-head 错误阻断；
3. 以所有 repo source facts 生成 batch-id 与完整 snapshot；从此 source 集合冻结，metadata commit 后的新变化属于下一批；
4. `editLatestCheckpoint()` 生成 `_backlog.yml` after image，并用既有 one-entry `applyWriteSet()` 绑定 before/after hash durable 应用；
5. 只 stage `change-requests/_backlog.yml`，复核 staged set 恰为该文件；
6. commit message：`[cr] checkpoint {cr} batch {batchId}`，并带 `AI-First-Op: checkpoint` / `AI-First-Tx` / `AI-First-CR` trailer；
7. 复核 `metadataCommit^ == kbSourceSha`；
8. 以 KB remoteBefore 做 lease push；push 后精确确认 remote HEAD == metadataCommit，且直接父提交 == kbSourceSha；
9. journal phase=complete，返回完整结果；随后 best-effort 清理 completed journal。

只有其他 repo 变化时，KB 不造空 source commit；`kbSourceSha` 可以是上一轮 metadata HEAD，新 metadata commit 直接接在其上，不形成无业务变化的 M1→M2→M3 自循环。

## 4.6 中断恢复

同一 `crctl checkpoint` 入口恢复时，先完成 §4.1 的全仓只读/敏感预检，再按 journal phase 处理：

- metadata 尚未 commit：重扫每个 repo；若 dirty，则执行一次 `git add -A`/source commit，把 `sourceSha` 更新为新 HEAD、`phase` 置回 `committed-local`，即使该 repo 旧 source 曾 confirmed 也必须按 exact-head 再次 publish；若 clean 但 `HEAD != journal.sourceSha`，视为第三值并报 `TX_RECOVERY_CONFLICT`；
- `prepared`：补 source commit；
- `committed-local`：按 remote facts push/confirm；
- `pushed`：先观察 remote，响应丢失时转 confirmed；
- `confirmed`：仅在 `HEAD == sourceSha` 且 clean 时跳过；否则走上述重新 capture；
- 全 repo confirmed 后执行 §4.5 第 1 步最终静稳检查；失败返回 `CHECKPOINT_WORKTREE_CHANGED_DURING_TRANSACTION`，不创建 metadata；下一次原命令会重扫并推进受影响 repo，不要求 stash/reset；
- `metadata-committed`：source 集合已经冻结，只验证 commit、直接父与 snapshot，不重复/改写 commit；此后出现的本地变化留给下一批；
- `metadata-pushed`：确认 remote authority；
- `complete`：返回同一 batch；若另有本地变化，清理已确认的 complete journal 后由下一次 checkpoint 创建新事务。

恢复不 reset/checkout/rebase/cherry-pick/force，不补偿 revert。journal 中任一记录与 Git 第三值冲突即硬失败。该规则只增加 resume 重扫与 phase 回退，不引入后台 watcher、编辑器锁或通用 phase engine。

## 4.7 reader 迁移

`list-remote-checkpoints` 以 KB remote requirement branch 为入口：

1. status 只从该 branch 的 `change-requests/{cr}/cr.md` 读取，不回退 backlog status；
2. 从同一 KB remote branch 的 `_backlog.yml` 读取单个 `latest-checkpoint`；
3. KB remote HEAD 必须是 metadata commit且直接父为 snapshot KB source SHA；非 KB remote HEAD 必须精确等于各自 source SHA；
4. 任一缺仓、超前、分叉、结构错误均标 drift/unknown，不把祖先关系当 synced；
5. “最后推送时间/人”从 KB metadata commit 的 Git author/committer 事实派生，不读取已删除字段。

`resume-from-remote` 在 list 验证完整批次后调用既有 `workspace ensure --mode resume`；`pull-progress` 保留全仓 clean + ff-only 行为，仅调整摘要字段。

# 5. 技术选型与替代方案

| 决策 | 采用 | 否决及原因 |
|---|---|---|
| 多仓一致性 | 可恢复 saga + KB metadata 可见点 | 2PC/数据库/消息队列：不存在共同事务资源，成本与需求不匹配 |
| 当前快照 | 单个 `latest-checkpoint` | `checkpoint-batches[] + latest pointer`：与 Git history/journal 重复事实源 |
| 事务实现 | 扩展既有 durable-tx + 一个 `checkpointCr()` | 新 saga engine/provider/class：只有一个新处理器，无抽象收益 |
| 账本编辑 | 行级定向 editor + 共享 `matchEntryBlock` | 通用 YAML serializer/patch CLI：会重排注释字段且引入第二写入口 |
| freshness | checkpoint-specific exact-head classifier | 修改共享 `classifyRemoteCommit()`：会回归 archive/writeback 的发布证明语义 |
| 敏感检测 | 固定路径 + 私钥头 | gitleaks/熵扫描/例外系统：新增依赖与配置面，超出当前边界 |
| outbox | metadata confirmed 后一次 batch 事件 | 沿用每仓 `cmdGit push` 事件：会把 projected_commit 指向半批次 |
| 查询 | 既有 list Skill | 新 `checkpoint status`：重复公共查询模型并暴露 journal 内部细节 |

# 6. FR 到技术实现映射

| FR | 技术方案 | 主要验证 |
|---|---|---|
| FR-01 | `cmdCheckpoint` + `checkpointCr`；从 Installation Workspace + cr 派生全仓 worktree；状态守卫；固定输出 | 安装根 CLI 黑盒、worktree missing/unregistered/branch mismatch、tracked/untracked/ignored fixture |
| FR-02 | preflight 固定路径与私钥头扫描 | 敏感路径零 index/commit/push；放行 example/sample/template 与普通 pem/key |
| FR-03 | `editLatestCheckpoint` + canonical batch-id | editor LF/CRLF、旧字段一次删除、同 facts 同 id/变化 facts 新 id |
| FR-04 | journal 前 no-op + KB parent/metadata 算法 | 零 journal/no push；KB direct-parent；仅非 KB 变化 |
| FR-05 | checkpoint journal + resume 重扫/re-source + exact-head classifier + lease publish | kill/restart、source/部分 push 后新增变化、response lost、advanced/diverged/history rewrite |
| FR-06 | 4 个 Pipeline 文件共 6 个 checkpoint/remote-compare 节点收缩 | prompt 静态 contract：无 Git/账本算法 |
| FR-07 | push/list/resume/pull Skill 迁移 | remote branch reader、drift、ff-only 恢复摘要 |
| FR-08 | T05 同提交删除 checkpoint-add 与旧 reader/caller | dispatch/help/tests/docs 全仓零残留（历史文档/CUSTOM 除外） |
| FR-09 | T01 红测→T03 pure/editor→T04 transaction→T05 migration | 253 crctl + 10 writeback 基线保持；Ubuntu/Windows CI |

# 7. 安全、性能与可观测性

## 7.1 安全

- 所有 repo/worktree/ref 来自 resolver 与固定 `requirement/{cr}`，不接受任意路径/refspec；
- 敏感扫描在全仓任何 add/commit/push 前完成；命中不提供绕过；
- push 只在 ancestry 证明 fast-forward 后使用精确 lease，不使用无条件 force；
- metadata stage 精确复核 staged set，防止把 source commit 后新出现的文件混入账本 commit；
- 行尾规范化、重复 key、跨行条目定位失败均硬失败，不静默生成空 snapshot。

## 7.2 性能

- no-op 快速路径仍需 fetch 与 remote exact-head 核对，这是正确性成本；但不创建 journal/commit/push；
- repo 数量按当前 active graph 线性处理；不并行 push，避免并发错误与恢复顺序复杂化；
- 敏感内容扫描为 O(本轮变化普通文件总字节数)，使用 Node 标准库，不维护缓存；
- 不为当前三仓规模增加 worker pool、锁分片或增量索引。

## 7.3 审计与观测

- `cmdCheckpoint` 成功/失败沿用 `.crctl/audit.log`，记录 cr/txId/batchId/phase/changed/repo 摘要，不写文件内容或 secret；
- 完整批次成功后一次 checkpoint outbox；失败只审计、不回滚；
- 错误 JSON 公开 phase/sideEffects/recoverCommand，journal 路径和本地绝对路径不进入 `latest-checkpoint`。

# 8. Prompt 采纳影响

本 CR 新增 `crctl.mjs` dispatch `checkpoint`，因此本节必填。T05 必须逐项迁移：

| 调用方 | 现状 | 改为 |
|---|---|---|
| `skills/sync/push-progress/SKILL.md` | Skill 手写 inspect/add/commit/push/rev-parse，并逐仓 checkpoint-add | 一次 `crctl checkpoint {cr_id} [--message ...] --workspace <ws>`，只解释 phase/batch/repos/errors |
| `skills/sync/list-remote-checkpoints/SKILL.md` | 读 `checkpoints[]`、last-push、status fallback | 读 remote KB `latest-checkpoint` + cr.md status，exact-head 判 synced/drift |
| `skills/sync/resume-from-remote/SKILL.md` | 依赖 list 验证但未声明 metadata-confirmed snapshot | 明确只恢复 list 已确认的完整 batch；workspace ensure 算法不变 |
| `skills/sync/pull-progress/SKILL.md` | 摘要读取 `last-push-at/by` | 从 KB metadata commit 派生时间/人；ff-only Git 流程不变 |
| `requirement-authoring.pipeline.json` checkpoint 节点 | 复制全仓 push 与 checkpoint-add 字段 | 只传 cr_id/message，消费 batchId/repositories/phase |
| `architecture-design.pipeline.json` checkpoint 节点 | 复制 git add/commit/push/checkpoint-add | 同上 |
| `code-implementation.pipeline.json` 任务/代码/审批 3 节点 | 三次复制逐仓 Git 与旧账本字段 | 三节点各只调用 push-progress 并消费结构化输出 |
| `resume-cr.pipeline.json` 远端比对节点 | 复制旧字段比较算法 | 只调用 list-remote-checkpoints 并消费 synced/drift/unknown |
| `README.md` | 多处承诺 `checkpoints[]`、last-push 字段 | 只保留完整 checkpoint 定义、阶段用途与失败语义 |
| `skills/_index.yml` | crctl/push-progress brief 仍列 checkpoint-add | 更新为单一 checkpoint 深原语 |
| `ARCHITECTURE.md` | 未列 checkpoint 写事务 | 增加 checkpoint 到 crctl/durable transaction 运行事实与测试入口 |

不修改 `controlled-shell/rules.json#protectedPaths.deny`。新 Git 副作用位于既有 workspace transaction 内部，走固定 argv 的 `gitMust()`，不扩大 Skill 可执行白名单。

# 9. 测试与故障注入

## 9.1 基线

SDD 撰写时已在 tools CR worktree 实跑：

- `node --test skills/shared/crctl/scripts/test/*.test.mjs`：253/253 pass；
- `node --test skills/writeback/scripts/test/*.test.mjs`：10/10 pass。

实施不得放宽旧断言。T01 先提交在旧实现下预期失败的 checkpoint 契约测试，再实施 T03/T04/T05。

## 9.2 三 bare remote 最小矩阵

1. 从 Installation Workspace 根调用成功；worktree missing/unregistered/branch mismatch 使用冻结错误码且全仓零 add/commit/push；
2. 敏感路径/私钥头：index 原样、全仓零 commit/push；例外文件不误拦；含空格与 rename 目标 path 不漏扫；
3. tracked + untracked + ignored：source commit 完整包含前两类、排除 ignored；
4. 三仓有变化与单仓 clean；
5. existing snapshot 完全未变：journal 目录数、commit 数、remote refs、outbox 均不变；
6. source commit/hook 后新增变化：本轮不生成 metadata，重跑更新 sourceSha 后完成；
7. 第二仓 push 后进程退出并新增变化：重跑不重复未变化 repo，受影响 repo 重新 source/publish，metadata 只引用新 SHA；
8. push 响应丢失，重跑观察 remote 收敛；
9. remote ancestor source：lease fast-forward 后精确相等；
10. remote advanced/diverged/history-rewritten：冻结错误码、对应 sideEffects 且零 metadata；
11. metadata commit/push 前后故障与响应丢失：单 metadata commit，direct-parent 正确；
12. 只有非 KB repo 变化：KB source 为上一 HEAD，不造空 source commit；
13. malformed snapshot、CRLF backlog、Windows path、未知 fault point 使用冻结错误码硬失败；
14. 完整批次按 `checkpoint-{cr}-{metadataCommit}.json` 去重，no-op 不新增事件；
15. T05 静态扫描证明 active Skill/Pipeline/README/help 无旧 checkpoint-add 算法/字段。

# 10. 实施顺序、回滚与风险

## 10.1 提交顺序

1. **T01**：冻结 schema/错误码/fault points，新增旧实现下失败的测试；保留 253+10 绿基线。
2. **T03**：durable checkpoint payload、共享 `matchEntryBlock`、latest editor、batch/classifier 纯函数及单测。
3. **T04**：`checkpointCr`、CLI dispatch/help/audit/outbox、多仓 publish/recover 集成测试。旧 push-progress/readers 仍使用旧入口。
4. **T05**：同一可回滚提交迁移 4 个 Skill、4 个 Pipeline 文件（6 节点）、README/index/ARCHITECTURE，并删除 checkpoint-add/旧 tests/旧文案。T05 完成即切换，不双读。

## 10.2 回滚

- T03/T04 尚未迁移 caller，可独立 revert，新命令无人消费；
- T05 必须整提交 revert，不能只恢复 reader 或只恢复 writer；
- metadata-confirmed 的新 snapshot 不回迁旧 `checkpoints[]`。若代码回滚到旧协议，必须先停止新调用并按 Git 历史人工选择协议版本，不生成伪 legacy 数据；
- 事务失败不自动 revert 远端 source commit，恢复方向只有继续完成或在 remote drift 时硬阻断。

## 10.3 风险

| 风险 | 控制 |
|---|---|
| remote 在 preflight 与 push 间前进 | 精确 lease + push 后再次 fetch 确认 |
| metadata commit 自引用或空转 | snapshot KB source 固定为 metadata 直接父，batch 排除 metadata SHA |
| 旧 complete journal 阻塞下一批 | authority 确认后清理；残留时下次先验证再清理 |
| 迁移时 writer/reader 协议错位 | T05 同一提交切换 caller/reader并删除旧入口 |
| checkpoint outbox 丢失/重复 | CLI 层在 metadata-confirmed 后按 cr+metadataCommit 确定性去重；Multica 现有消费者契约测试保持 |
| `pull-progress` 读取已删除字段 | T05 仅改摘要为 metadata Git 事实，不改 ff-only 行为 |
| ARCHITECTURE 与新写命令漂移 | T05 同步更新；本轮 SDD 不借道提前改 living baseline |

# 11. 不做事项

- 不新增数据库、消息队列、分布式锁、2PC、第三方 secret scanner 或 npm 依赖；
- 不新增通用 saga/phase runner、repository interface、provider、registry、plugin、第二事务模块；
- 不新增 checkpoint history 数组、status API、文件选择参数或敏感绕过配置；
- 不自动 merge/rebase/force/reset/补偿 revert；
- 不永久双读旧 `checkpoints[]`，不伪造 legacy batch；
- 不修改 Multica 代码或 `CUSTOM.md`；本 CR 只保持其既有 checkpoint outbox 消费契约；
- 不实施 Test/Traceability/feedback/静态治理后续分组 T06～T16。

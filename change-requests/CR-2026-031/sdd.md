---
id: CR-2026-031-sdd
type: SDD
cr-ref: CR-2026-031
title: crctl 执行层职责边界与 merge/workspace/writeback/archive 事务化技术设计
status: draft
created: 2026-08-11T17:32:01+08:00
updated: 2026-08-11T17:32:01+08:00
---

# 1. 架构概览

## 1.1 设计目标

本设计落实 PRD FR-01～FR-10，并以 `docs/analysis/tools-tca-005-009-015-016-merge-workspace-optimization-plan.md` 为详细设计输入。核心目标不是让多个 Git remote 具备不存在的原子性，而是把现有文本拼接流程收敛为：**单仓 ref CAS + 持久化本地 journal + 远端事实 reconcile + 幂等 roll-forward**。

职责和依赖保持单向：

```text
Agent
  └─ 识别意图、选择 Pipeline
      ↓
Pipeline
  └─ 节点顺序、输入传递、reviewLoop、失败中止
      ↓
Skill
  └─ 业务前置、一次深原语调用、结构化结果解释
      ↓
crctl.mjs
  ├─ dispatch、状态/gate、账本、审批、审计
  └─ 调用两个内部模块
      ├─ lib/durable-tx.mjs
      │   lock / journal / recoverable write-set / fsync / fault / blob cleanup
      └─ lib/workspace-transactions.mjs
          repository resolver + 五个具体业务处理器
          registerCr / ensureWorkspace / mergeCr / applyWriteback / archiveCr
              ↓
          Node 标准库 + Git/文件系统原生能力 + remote refs
```

只新增以上两个内部模块。禁止新增 Transaction class、通用 phase engine、handler registry、adapter/plugin、第三方依赖或第三个事务模块。

## 1.2 现有架构基线的显式修订

`tools/ARCHITECTURE.md` 当前仍声明 crctl 刻意单文件且不引入 WAL。本 CR 是经需求审批的架构级变更，实施时必须在最终协议切换提交中同步修订：

1. `crctl.mjs` 仍是唯一公开 CLI 和状态/账本执行入口，但允许把持久化原语与 Git/workspace 事务实现拆入两个内部模块；
2. 将“多文件 WAL 永不需要”改为“只为已观察到的崩溃恢复需求提供最小 recoverable write-set”；
3. 保留零第三方依赖、状态/账本单一写者、CRLF 规范化、硬失败和人工审批无旁路；
4. 不将两个内部模块暴露为第二 CLI 或第二账本写入通道。

该修订与代码、测试、Skill/Pipeline 契约在同一 CR 完成，不提前改变当前 trunk 运行事实。

## 1.3 Authority

| 阶段 | 写 authority | 说明 |
|---|---|---|
| register～code-approved | CR requirement worktree | 现有开发/评审产物 authority |
| merge prepare/publish | crctl journal + remote refs | journal 是恢复指针，remote ref 是发布事实 |
| merge finalize 后 | detached knowledge-base Transaction Workspace | `operational_workspace` 的唯一来源 |
| archive commit origin confirmed 后 | origin knowledge-base trunk | 业务终态不可回退；cleanup 仅是运维阶段 |

用户主 checkout 从不作为事务 workspace。CR worktree 在 merge finalize 后只读，直到 archive cleanup。

# 2. 模块边界与文件变更

## 2.1 `crctl.mjs`

保留：CLI 参数解析、dispatch、现有状态机/gate/approval/audit、确定性输出和两个内部模块的薄接线。

删除或收敛：

- 死代码 `writeApprovalSection()`；
- 无调用别名 `cr-metrics`；
- `casWriteMulti()` / `tryCasWriteMulti()`，全部迁到同一 recoverable write-set；
- 公开 `cr-init`、`worktree-path`、`merge-metadata`、`archive-move`；
- 无真实调用的 `task allocate`、`scanMaxTaskNumber()`、`appendTaskEntry()`；
- `migrate-backlog`、ghost cleanup、v1 fallback/legacy warning；v1 统一返回 `UNSUPPORTED_BACKLOG_SCHEMA`；
- generic Git 中 register/writeback template 和后置特判；
- 公开 `--caller` 与伪造 caller 授权承诺。

保留历史 `evidenceSha16` 兼容和现有 YAML 子集解析器，不引入通用 YAML 库。

## 2.2 `durable-tx.mjs`

仅导出小型函数集合：

```js
acquireLock({ root, scope, op, cr })
loadOrCreateJournal({ root, op, cr, inputDigest, graphDigest, payload })
saveJournal({ path, journal })
recoverWriteSet({ root })
applyWriteSet({ root, txId, entries })
fault(point, context)
cleanupTxBlobs({ root, txId })
```

该模块只理解 envelope、文件锁、hash 和文件替换，不理解 CR status、Git branch、merge phase 或业务 payload。

## 2.3 `workspace-transactions.mjs`

仅导出五个具体函数和少量真实共享 helper：

```js
registerCr(ctx, input)
ensureWorkspace(ctx, input)
mergeCr(ctx, input)
applyWriteback(ctx, input)
archiveCr(ctx, input)

resolveRepositories(workspace)
classifyRemoteCommit(observation)
```

`classifyRemoteCommit()` 只分类 Git 事实，不接受 callback；各业务处理器自行决定 rebuild/finalize/cleanup。

## 2.4 版本化 writeback 脚本

`writeback-prd-sdd.mjs`、`writeback-tasks.mjs`、`writeback-traceability.mjs` 从“直接写 baseline”收敛为“读取 approved artifacts + baseline，生成 candidate manifest 与 content-addressed blobs”。它们不得推进状态、提交、push、创建 worktree 或修改账本。

# 3. 数据模型

## 3.1 公共 journal envelope

路径：`{Installation Workspace}/.crctl/transactions/{op}/{cr-or-key}/{txId}/journal.json`。路径不进入 Git；业务历史以 origin commit 为准。

```json
{
  "v": 1,
  "txId": "sha256-derived-or-random-id",
  "op": "register|workspace|merge|writeback|archive",
  "cr": "CR-2026-031|null-before-allocation",
  "phase": "op-specific-string",
  "graphDigest": "sha256",
  "inputDigest": "sha256",
  "sideEffects": [],
  "commit": null,
  "lastError": null,
  "createdAt": "ISO-8601",
  "updatedAt": "ISO-8601",
  "register": null,
  "workspace": null,
  "merge": null,
  "writeback": null,
  "archive": null
}
```

不变量：

- `op` 对应的一个 payload 非空，其余必须为 null；
- JSON 写入先写同目录 temp、`fsync(file)`、rename、`fsync(parent)`；
- 读入先规范化 CRLF；schema/JSON/必要字段缺失硬失败；
- `graphDigest` 在零副作用时允许重建；出现任一账本/workspace/remote 副作用后 graph 变化返回 `GRAPH_CHANGED_DURING_TRANSACTION`；
- journal 不是远端账本；丢失时通过 trailer、remote refs、approval snapshot 重建，冲突硬阻断。

## 3.2 Lock record

锁目录由原子 `mkdir` 创建，内部 `owner.json`：

```json
{
  "v": 1,
  "token": "random-128-bit",
  "pid": 1234,
  "hostname": "host-a",
  "startedAt": "ISO-8601",
  "op": "merge",
  "cr": "CR-2026-031"
}
```

释放时 token 必须匹配。无 TTL、无 `force-unlock`。同 hostname 下 `process.kill(pid, 0)`：成功或 EPERM 视为存活，ESRCH 视为不存在；foreign hostname、PID 复用证据不一致或 owner 不完整均保守阻断。

锁粒度：operation lock 覆盖单 CR 单事务；Installation Workspace publish lock 只覆盖短时账本/Git stage/commit/push 临界区。先不实现 per-repo publish lock，只有吞吐实测不足后按 CUSTOM-TODO-007 细分。

## 3.3 Recoverable write-set

manifest：

```json
{
  "v": 1,
  "txId": "...",
  "state": "prepared|applying|complete",
  "entries": [
    {
      "path": "workspace-relative-posix-path",
      "beforeSha256": "hex-or-absent",
      "afterSha256": "hex",
      "blob": "blobs/<afterSha256>"
    }
  ]
}
```

恢复规则逐 entry 执行：

- 当前 hash = after：已完成，跳过；
- 当前 hash = before：从 tx blob redo；
- 其余值：返回 `TX_RECOVERY_CONFLICT`，不得覆盖第三方修改；
- 单文件写也使用 one-entry write-set；
- 全部 entry confirmed 后标记 complete，再清理 temp/blob；清理失败不逆转已完成写入。

## 3.4 Signed release snapshot

`review-annotations/code.yml#release-subjects` 由 crctl 机器注入，模型 payload 不得提供或覆盖：

```yaml
release-subjects:
  version: 1
  repositories:
    - repo: tools
      remote-ref: refs/heads/requirement/CR-2026-031
      reviewed-source-sha: <40-hex>
  artifacts:
    algorithm: sha256
    canonicalization: crlf-to-lf+path-sort
    files:
      - { path: change-requests/CR-2026-031/prd.md, sha256: <64-hex> }
      - { path: change-requests/CR-2026-031/sdd.md, sha256: <64-hex> }
    digest: <64-hex>
```

受控 artifact 集合为 PRD、SDD、dev plan、TASK 文件与 task index；路径排序后读取，内容先 `\r\n → \n`。approve-code 重核 ref/HEAD/artifacts，一致后将该块原样复制到 `approval.yml#code.release-subjects`，并由既有 TTY/Ed25519 approval digest 签入。漂移返回 `RELEASE_SUBJECT_DRIFT` 且零写入。

## 3.5 Writeback candidate manifest v1

```json
{
  "v": 1,
  "stage": "baseline|tasks|traceability",
  "cr": "CR-2026-031",
  "specId": "...",
  "targetVersion": "...",
  "inputDigest": "sha256",
  "generator": { "id": "writeback-prd-sdd", "sha256": "sha256" },
  "files": [
    {
      "path": "specs/<spec-id>/PRD.md",
      "beforeSha256": "hex-or-absent",
      "afterSha256": "hex",
      "blob": "blobs/<afterSha256>"
    }
  ]
}
```

`files` 必须唯一且按 POSIX path 字典序排列。v1 仅允许固定 allowlist 中的 create/replace；禁止 absolute、`..`、反斜杠、重复分隔符、symlink parent、delete、rename、chmod 和 executable bit。blob 只能来自当前 tx 的 content-addressed 目录。

## 3.6 Git commit trailer

所有事务 commit 由 crctl 追加，调用方不可覆盖：

```text
AI-First-Op: register|merge|writeback|archive
AI-First-Tx: <txId>
AI-First-CR: CR-2026-031
```

register 增加 `AI-First-Registration-Key-SHA256`；merge 增加 repo/base/approved-source trailer。固定 trailer 是跨机器 journal 重建锚点，不新增 remote journal branch。

# 4. CLI 接口契约

所有写命令成功返回 JSON；失败统一 `{error:{code,message,...}}` 和非零 exit。结构化输出至少含 `op/txId/phase/changed/sideEffects/recoverCommand`。

## 4.1 Register

```text
crctl register --registration-key <opaque-key>
  --title <text>
  --owner-requirement <id> --owner-development <id> --owner-test <id>
  [--summary <text>] [--source <path>] [--target-version <version>]
  --workspace <Installation Workspace>
```

- key 仅按 SHA-256 写入 trailer/journal，不落明文；
- 同 key + 同 inputDigest 复用 CR-ID/txId并续跑；
- 同 key + 不同输入返回 `REGISTRATION_INPUT_MISMATCH`；
- 原子分配 CR-ID、recoverable 三账本写、registration commit/lease push、active repo workspace ensure；
- 默认 roll-forward，不自动删除已健康 workspace/ref。

## 4.2 Workspace

```text
crctl workspace inspect <CR-ID> --workspace <Installation Workspace>
crctl workspace ensure <CR-ID> --mode resume --workspace <Installation Workspace>
crctl workspace cleanup <CR-ID> --mode partial|archived --workspace <Installation Workspace>
```

resolver 唯一读取 workspace `dir-graph.yaml#repositories`，只接受 active、id/path/trunk/role 完整的仓。bucket 由 repo 声明/role 解析，不写死 repo id。canonical path 必须 realpath-contained 于 `.rayai-worktrees/{bucket}`。

workspace 分类：`missing|healthy|branch-only|remote-only|dirty|wrong-branch|path-unregistered`。ensure 只创建/修复能由 Git 和 graph 证明归属的状态；dirty、wrong-branch、unknown 均硬阻断。cleanup 只删除 journal/archive 事实证明归属且 clean 的资源。

## 4.3 Merge

```text
crctl merge <CR-ID> --workspace <Installation Workspace>
crctl merge status <CR-ID> --workspace <Installation Workspace>
```

单入口自动开始或续跑。prepare 阶段无 ref/worktree/账本副作用；publish 逐仓按 `--force-with-lease=<trunk>:<base>` 等价语义更新 ref；部分发布不推进 CR status。所有仓 confirmed 后才执行 knowledge-base finalize。

主要失败码：`RELEASE_SUBJECT_DRIFT`、`APPROVED_ARTIFACT_DRIFT`、`MERGE_PREPARE_CONFLICT`、`MERGE_REMOTE_STALE`、`MERGE_REMOTE_HISTORY_REWRITTEN`、`GRAPH_CHANGED_DURING_TRANSACTION`。

## 4.4 Writeback apply

```text
crctl writeback-apply <CR-ID> --stage baseline|tasks|traceability
  --candidate <manifest-path> --spec-id <id>
  --workspace <operational_workspace>
```

校验 signed snapshot、stage/spec/version/inputDigest/generator hash、manifest schema、blob/before/after hash、allowlist 和 staged set。脚本退出失败或校验失败时 baseline/staged set 保持不变。未发布 candidate 遇 origin trunk 前进时删除旧 candidate，从新 detached origin 基线重新生成，不 rebase/cherry-pick。

## 4.5 Archive

```text
crctl archive <CR-ID> [--spec-id <id>] --workspace <Installation Workspace>
```

单入口续跑状态、四账本/archive event、archive commit/lease push、workspace/ref cleanup。origin 包含 archive commit 后业务状态固定为 archived；cleanup 失败返回 `CR_ARCHIVE_CLEANUP_PENDING`，journal phase=`cleanup-pending`，重跑只续清理。rejected/withdrawn 未合并 remote refs 始终保留并输出 `preservedRefs`。

## 4.6 Upgrade check（临时）

```text
crctl upgrade-check --workspace <Installation Workspace>
```

fetch 后只读 origin trunk 与 active repo remote refs，输出：

```json
{
  "safe": [],
  "requiresReapproval": [],
  "blocksUpgrade": [],
  "canActivate": true
}
```

有 blocker 或事实不确定 exit 1，全程零写入、不创建 workspace、不合成 snapshot。全部安装完成协议切换且无旧事务后，按 CUSTOM-TODO-009 连同 dispatch/help/tests 整体删除。

# 5. 关键算法与流程

## 5.1 远端事实分类

```js
function classifyRemoteCommit({
  remoteSha,
  expectedBase,
  commitSha,
  commitIsRemoteAncestor,
  journalSaysPublished
}) {
  if (commitIsRemoteAncestor) return 'confirmed'
  if (journalSaysPublished) return 'history-rewritten'
  if (remoteSha === expectedBase) return 'pushable'
  return 'rebuild'
}
```

helper 只分类事实。register finalize/writeback/archive 在 `rebuild` 时从新 origin base 重建各自 commit；merge 依 approved source 和新 base 重做无副作用 prepare。`history-rewritten` 一律硬阻断，不猜测、不自动 force。

## 5.2 Merge saga

1. 获取 operation lock，恢复未完成 write-set/journal；
2. 解析 graph 并计算 graphDigest；
3. 校验 status=`code-approved`、approval/test/review gate；
4. 只从 `approval.yml#code.release-subjects` 读取 per-repo approved source 和 artifact digest；
5. 对 remote requirement ref、worktree HEAD、artifact 重核：
   - code/source/TASK drift 且零 trunk publish：原子标记审批 stale，经新增状态转换 `code-approved -> developing`，trigger=`merge-feature-branch:release-drift -> implement-code`；
   - PRD/SDD drift：`APPROVED_ARTIFACT_DRIFT`；
   - 任一 trunk 已 publish 后 drift：保持 blocked，恢复原 ref 后才能续跑；
6. 每仓 fetch base/source，在临时 index/tree 中验证 merge；冲突时 `MERGE_PREPARE_CONFLICT`，零远端副作用；
7. 用 Git `commit-tree` 生成候选 merge commit，parents 固定 base/source，写固定 trailer，不 checkout、不移动本地 trunk；
8. journal 先记 publish intent，再按 lease 逐仓 push，再记 observation；
9. 重入时调用远端分类，confirmed 跳过，pushable 续推，rebuild 重做该仓 candidate，history-rewritten 硬阻断；
10. 所有仓 confirmed 后，在 detached knowledge-base Transaction Workspace 从最新 origin trunk 生成 finalize commit：同一 commit 内写 `status=merging`、完整 `merge-commits[]`、`merge-verification.md` 和事件；
11. origin confirmed 后返回 `operational_workspace`，不再从 CR worktree 或主 checkout 判断 authority。

## 5.3 Writeback

每 stage：

1. crctl 在 Transaction Workspace 读取 signed snapshot 与当前 artifact；
2. 调固定 generator 只生成 candidate/blobs/manifest；
3. 校验 generator SHA 与 manifest/input/before/after；
4. 用 recoverable write-set 应用 candidate；
5. stage 精确 manifest paths，并断言 staged set 完全相等；
6. 由 crctl 生成 commit + trailer 并 lease push；
7. classify remote：confirmed 进入下一 stage，pushable 推送，rebuild 从新 origin baseline 重生成，history-rewritten 硬阻断；
8. 最后状态推进仍由 crctl gate/CAS 完成。

## 5.4 Archive

1. 校验终态前置、TASK done、writeback/traceability/gate；
2. 在 detached Transaction Workspace 用 recoverable write-set 同批生成四账本与 archive event；
3. 生成 archive commit 并 lease push；
4. origin 未 confirmed 前允许 rebuild/续推，业务状态不提前宣称完成；
5. origin confirmed 后将 journal 置 `cleanup-pending`；
6. 删除仅由 graph+journal+Git ancestry 证明归属且 clean 的 archived worktree/local ref；
7. 未合并 rejected/withdrawn remote ref 放入 `preservedRefs`；
8. cleanup 全成功才 complete；失败仍返回 archived + `CR_ARCHIVE_CLEANUP_PENDING`。

# 6. 技术选型与替代方案

| 决策 | 采用 | 拒绝及原因 |
|---|---|---|
| 持久化 | 本地 JSON journal + Git trailer + remote observation | 数据库/队列/远端 tx branch：没有多主机协调需求，新增运维与第二事实源 |
| 跨仓语义 | 单仓 ref CAS + roll-forward saga | 宣称跨 remote 原子：Git 不支持；默认 revert 会保留历史且扩大副作用 |
| 锁 | 原子目录锁 + PID/hostname/token | TTL/force unlock：可能误删仍存活 owner；分布式锁：本轮无共享 `.crctl` 多主需求 |
| 文件事务 | hash 驱动 recoverable write-set | 连续 rename 无恢复：已有半写风险；通用 WAL 框架：超过真实需求 |
| merge candidate | Git `commit-tree`/临时 index | checkout 本地 trunk：污染主工作区并制造恢复状态 |
| writeback | candidate-only generator + crctl apply | 脚本直接改 baseline/commit：越过 authority、gate 与 staged set 校验 |
| 模块化 | 两个内部模块 | commands/、class/factory/plugin：没有第二变化轴，增加导航成本 |
| schema | backlog v2 最低版本 | 永久 v1 migration/fallback：一次性迁移逻辑成为长期分支 |

# 7. FR 到技术实现映射

| FR | 技术实现 | 主要验证 |
|---|---|---|
| FR-01 | `crctl.mjs` 深原语 dispatch；删除旧公开入口；Skill/Pipeline contract 收敛 | static prompt/dispatch contract |
| FR-02 | `durable-tx.mjs` + `workspace-transactions.mjs`；envelope/lock/write-set/fault | kill/restart 与 schema tests |
| FR-03 | `registerCr()`、registration key digest、resolver/workspace classifier | 分配/commit/push/第 N 仓 fault 重入 |
| FR-04 | `mergeCr()`、commit-tree、lease publish、`classifyRemoteCommit()` | 三 bare remote merge matrix |
| FR-05 | detached Transaction Workspace、单 finalize commit、authority resolver | finalize stale/STATUS_DIVERGED tests |
| FR-06 | code review 机器注入、approve 原样签入、release-drift 转换 | TTY/grant/drift 零写入 tests |
| FR-07 | candidate manifest v1、`applyWriteback()`、精确 staged set | path/blob/hash/trunk drift matrix |
| FR-08 | `archiveCr()`、origin-confirmed terminal、cleanup-pending/preservedRefs | cleanup fault 与重复 archive |
| FR-09 | realpath containment、lock owner 验证、删除 caller/generic destructive Git | traversal/symlink/lock tests |
| FR-10 | 只读 `upgrade-check` 与最终协议切换删除计划 | legacy state/partial publish matrix |

# 8. 安全、性能与兼容性

## 8.1 安全

- 所有 path 先转 POSIX workspace-relative，再拒绝 absolute/`..`/反斜杠/空段；parent realpath 必须在声明 bucket/Transaction Workspace 内；
- destructive cleanup 前同时校验 graph repo、canonical path、registered worktree、branch/ref、clean status 和 journal ownership；
- remote push 只允许声明的 origin/trunk/ref，并按 expected SHA lease；不接受调用方任意 refspec；
- release snapshot 字段由 crctl 注入并由 approval digest 签名；模型只能提交 verdict/blockers；
- 保留人工审批 TTY/Ed25519 无旁路；不使用自报 caller 作为身份；
- 不自动 stash/reset 用户内容，不删除未知目录/ref。

## 8.2 性能

- hash/scan 只覆盖 active repos 和受控 artifact/manifest paths；不遍历整个仓库；
- operation lock 串行化同 CR，publish lock 仅覆盖短临界区；不提前拆 per-repo lock；
- content-addressed blob 去重并在 complete 后清理；
- 外部调用量是观测指标，不能通过删 gate/测试/恢复步骤降低。

## 8.3 兼容性和行尾

- Node 标准库、Git CLI，Windows/Ubuntu 双平台；
- 文件哈希和跨行解析统一 `\r\n → \n`，逐行使用 `split(/\r?\n/)`；解析失败硬失败，不回退为空；
- backlog v1 返回 `UNSUPPORTED_BACKLOG_SCHEMA`；
- 新状态转换使正式口径从当前 27 条声明/49 条展开变为 28/50，具名状态仍为 15；同步 `dir-graph.yaml`、断言和文档，禁止 workspace 复制状态机。

# 9. 测试设计与故障注入

## 9.1 最小 fault points

- write-set：manifest durable 后、每个 rename 前/后、complete 前；
- register：CR-ID 分配后、账本 write-set 后、commit 后、push 后、每个 worktree 前/后；
- merge：每仓 prepare 后、intent 后、push 返回前/后、observation 后、finalize commit/push 前后；
- writeback：candidate 后、apply 每 entry、stage 后、commit/push 前后；
- archive：账本 write-set、archive commit/push、每个 cleanup resource 前后。

通过环境变量仅在 test harness 启用确定性 `CRCTL_FAULT_POINT`；生产未设置时零行为。

## 9.2 测试矩阵

1. 三个 bare remote：prepare conflict、第二仓 push 失败、push 成功响应丢失、remote stale、finalize stale、history rewrite；
2. registration：同 key 在每个 fault point 重跑、输入 mismatch、graph 零副作用变化/有副作用变化；
3. workspace：missing/healthy/branch-only/remote-only/dirty/wrong-branch/path-unregistered、symlink escape；
4. write-set：before/after/third value、真实 kill/restart、single-entry 与 multi-entry；
5. release snapshot：payload 注入覆盖、ref/HEAD/artifact drift、TTY 与 Ed25519 approval；
6. manifest：absolute/`..`/反斜杠/乱序/重复/symlink/tx 外 blob/hash/delete/rename/chmod；
7. authority：CR worktree、主 checkout、Transaction Workspace 冲突；
8. archive：origin confirmed 后 cleanup fault、重复调用、preservedRefs；
9. lock：live PID、EPERM、ESRCH、PID reuse、foreign hostname、token mismatch；
10. upgrade-check：developing、旧 code-approved 零 publish、legacy partial merge、authority unknown，全程零写入。

CI 运行 prompt lint、skill/agent/pipeline contracts、crctl tests、writeback tests、JSON parse，并在 Ubuntu/Windows 运行关键 fault vectors。

# 10. 实施切片与提交顺序

在同一 CR 中拆约 12 个 TASK，每个完成即经版本化账本入口登记 done：

1. fault harness 与红测；
2. 删除死代码、重复算法、无调用命令与 v1 永久兼容；
3. repository resolver、containment 和 authority resolver；
4. `durable-tx.mjs`：lock/journal/write-set/fsync/fault；
5. register + workspace inspect/ensure/cleanup；
6. signed release snapshot、approve 重核与 release-drift 转换；
7. recoverable merge + Git fact classification；
8. Transaction Workspace + candidate-only writeback/apply；
9. archive + cleanup-pending/preservedRefs；
10. Skill/Pipeline/Agent/controlled-shell 收敛；
11. 临时 upgrade-check 与激活 preflight；
12. docs/ARCHITECTURE/README/contracts/双平台 CI 与最终统一协议切换。

中间提交不在 trunk 激活半套协议，不添加 feature flag、wrapper 或双写。本 CR 自身继续由旧 Installation Workspace 流程 merge/writeback/archive；origin 全部确认并通过 upgrade-check 后，下一 CR 起使用新协议。

# 11. Prompt 采纳影响

本 CR 修改 `crctl.mjs` dispatch 和 generic Git/guard 命令面，因此本节必填。以下 active Skill 必须从文本算法改为一次深原语调用：

| Skill | 当前问题 | 新调用 |
|---|---|---|
| `skills/requirement/requirement-register/SKILL.md` | 展开 cr-init、commit/push、逐仓 worktree add | `crctl register --registration-key ...` |
| `skills/sync/resume-from-remote/SKILL.md` | 自行 fetch/分类/worktree add | `crctl workspace ensure <CR> --mode resume` |
| `skills/writeback/merge-feature-branch/SKILL.md` | 持有 prepare/push/revert/metadata/finalize 算法 | `crctl merge <CR>`；只解释结构化结果 |
| `skills/writeback/writeback-prd-sdd/SKILL.md` | generator 直接改 baseline，Skill 拼 commit/advance | generator candidate + `crctl writeback-apply --stage baseline` |
| `skills/writeback/writeback-tasks/SKILL.md` | 同上 | generator candidate + `crctl writeback-apply --stage tasks` |
| `skills/writeback/writeback-traceability/SKILL.md` | 同上 | generator candidate + `crctl writeback-apply --stage traceability` |
| `skills/cr/cr-archive/SKILL.md` | 展开状态/账本/push/Remove-Item/prune/report | `crctl archive <CR>` |
| `skills/develop/review-code/SKILL.md` | 模型 payload 未绑定机器 source/artifact snapshot | 仍调 `review-record --stage code`，明确 release-subjects 由 crctl 注入 |
| `skills/develop/approve-code/SKILL.md` | 未描述 approve 重核 snapshot | 仍调 `crctl approve --stage code`，只解释 drift 结果 |
| `skills/shared/controlled-shell/SKILL.md` | caller 三元放行承诺与实现不符 | 删除授权承诺；说明 caller 仅审计标签也一并取消 |

对应 Pipeline：

- `requirement-authoring.pipeline.json` 删除 repo/Git/worktree 算法，只传 register 输入和 execution context；
- `resume-cr.pipeline.json` 删除重复 preflight/worktree add；
- `feature-writeback.pipeline.json` 删除十步 merge、补偿、metadata 和 writeback 内部算法，只保留节点顺序、`operational_workspace` handoff、passCondition/onFail；
- Agent 仅保留 Pipeline 路由，不新增 writeback agent；`requirement-writer` 删除对 Pipeline 内部步骤的复述。

`lint-prompts`/contract tests 必须检查 active prompt 中不再出现裸 `git worktree/merge/revert/push`、手写账本、`--workspace .` 写回、旧命令名或删除后的 `--caller`。

# 12. 风险与恢复边界

- 多 remote 仍可能部分发布；本设计保证可观察和 roll-forward，不承诺瞬时原子；
- `.crctl` 不支持多主机共享；foreign host 锁保守阻断，由操作者回到 owner host 恢复；
- remote history rewrite、第三值文件冲突、无法证明 authority/ownership 都硬阻断，不提供 force；
- release snapshot 协议前的 partial merge/merging/writing-back 不能自动升级；
- 通用事务框架、per-repo lock 和永久 upgrade-check 均延后，分别受 CUSTOM-TODO-008、007、009 约束；
- `tools/CUSTOM.md` 的 TODO/定制登记必须以实施时 tools worktree 实际结构更新，不能依赖主 checkout 未跟踪文件作为交付事实。

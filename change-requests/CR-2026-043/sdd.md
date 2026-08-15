---
id: CR-2026-043-sdd
type: SDD
cr-ref: CR-2026-043
title: Workspace 基线新鲜度与 CR Worktree 同步治理 技术设计
status: draft
created: 2026-08-16T00:30:49+08:00
updated: 2026-08-16T00:30:49+08:00
---

# 1. 架构概览

## 1.1 目标仓与架构基线

目标代码仓是 Tools（`dir-graph.yaml#repositories.tools`，`trunk: custom/main`）。本 CR 只改方法论包代码（`skills/shared/crctl/scripts/**`、`skills/sync/**`、`pipeline-templates/**` 与索引/README），故 `tools/ARCHITECTURE.md` 是正确的架构基线（已存在，只读引用，不改）。本设计遵守其硬不变量：零第三方依赖（不变量 3）、状态单一写者（不变量 1）、账本单一写入通道（不变量 2）、CRLF→LF 硬失败纪律（不变量 4）、durable-tx 唯一事务框架（§6 刻意不做）。

## 1.2 目标架构

```text
code-implementation.pipeline.json（Pipeline：节点顺序 / 输入传递 / reviewLoop / 失败中止）
  approve-dev-start
    → workspace-freshness(gate=implement-start)          【新增节点 ...016】
    → implement-code → write-test-report → push-progress
    → workspace-freshness(gate=review-start)             【新增节点 ...017】
    → [选择评审 LLM human_approval] → review-code → push-progress → approve-code

workspace-freshness Skill（业务判断：continue / sync / replay / manual）
  → crctl workspace freshness <CR-ID>        【新增窄 CLI，只读业务检查】
  → crctl workspace sync <CR-ID>             【新增窄 CLI，显式 ff-only 同步事务】

crctl.mjs cmdWorkspace（dispatch：inspect|ensure|cleanup|freshness|sync）
  → workspace-transactions.mjs
      classifyWorkspaceFreshness(ctx, cr)    【新增：第二层 freshness 分类，只读】
      syncWorkspaceToTrunk(ctx, { cr })      【新增：lock + journal + 逐仓 ff-only】
        ├─ classifyRepoWorkspace（复用：基础分类事实）
        ├─ gitRun/gitMust（复用：argv、shell:false）
        └─ durable-tx.mjs（复用：acquireLock op=workspace、journal envelope workspace payload、durableWriteFile）
```

## 1.3 模块职责与深模块边界

| 模块 | 职责/接口 | 明确不拥有 |
|---|---|---|
| Agent（dev-agent） | 路由、职责判断、选择 Pipeline/Skill；can-call workspace-freshness | 状态机、Git 算法、受控文件写入 |
| Pipeline（code-implementation） | 两个 gate 节点的位置、输入传递、reviewLoop replayNodes、失败中止 | Skill 完整算法、git 命令、手写账本 |
| `workspace-freshness` Skill | 读 crctl 结构化结果做业务路由；编排 freshness→条件 sync→重核；定义输入输出与失败语义 | ancestry/锁/journal/CAS 算法、重复实现 crctl |
| `crctl.mjs` | `workspace freshness|sync` 参数解析、TxError→fail、audit 登记、HELP 文本 | 业务设计判断、LLM 评审结论、状态推进 |
| `workspace-transactions.mjs` | freshness 分类与同步事务的唯一实现：resolver 复用、preflight、重核、ff-only、journal、恢复 | 状态机、业务账本、远端分支发布 |
| `durable-tx.mjs` | 既有锁/journal/write-set/故障注入登记 | workspace 业务语义 |
| 版本化脚本 | 本 CR 不新增 | — |
| README | 命令入口、结果含义、人工动作索引 | 分类算法或恢复状态机的另一份事实源 |

深模块是 `syncWorkspaceToTrunk`：调用方（CLI/Skill）只掌握 CR-ID 与结构化错误；preflight、锁、逐仓重核、ff-only、journal 与恢复全部隐藏其中。不新增第二事务框架、branch manager 或通用同步接口。

## 1.4 已解决基础设施（只复用，不重做）

| 能力 | 现有实现（已核实） | 本 CR 处理 |
|---|---|---|
| Repository/worktree resolver | `workspace-transactions.mjs#resolveRepositories`：dir-graph 唯一解析、repo id 稳定排序、realpath 身份校验、graphDigest | 全量复用；不新增 repo 配置 |
| Workspace 基础分类 | `classifyRepoWorkspace`：`missing/healthy/branch-only/remote-only/dirty/wrong-branch/path-unregistered`；`WORKSPACE_CLASSIFICATIONS` | freshness 为第二层关系；基础分类与 `ensureRepoWorkspace` 零改动 |
| 受控 Git | `gitRun/gitMust`（`spawnSync('git', args, {shell:false})`），事务处理器独占 Git 副作用 | 复用 fetch、`merge-base --is-ancestor`、`rev-parse`、`merge --ff-only` |
| Durable transaction | `durable-tx.mjs`：`OPS`/`PAYLOAD_KEYS` 已含 `workspace`；`acquireLock({scope,op})`（scope 正则 `[A-Za-z0-9:_-]+`）；journal envelope；`loadOrCreateJournal`（inputDigest 漂移→TX_INPUT_CONFLICT）；`durableWriteFile`；`FAULT_POINTS` 全仓唯一登记表 | 同步事务沿用 op=`workspace`；新增 2 个故障点登记进 FAULT_POINTS |
| Audit 与结构化错误 | `auditLog`（`.crctl/audit.log` JSONL）；`TxError`+`runTxAsync`→`fail(code)` | 复用；新增两个 kind：`workspace-freshness`（仅阻断/失败）、`workspace-sync` |
| Source 发布与重核 | checkpoint、review-record release-subjects、approve-code/merge 重核 | 零改动；sync 不发布远端分支 |
| Pipeline 自修复 | code-implementation reviewLoop（maxAttempts=3、replayNodes、passCondition） | 扩展 review-code 节点 replayNodes 插入 freshness 重放 |
| 契约台账 | `skills/_index.yml`、`agent-skill-matrix.yml`、`pipeline-templates/_index.yml` | 新增 Skill 登记与节点数同步（13→15） |

## 1.5 本次最小改造

| 改造点 | 文件 | 性质 |
|---|---|---|
| `classifyWorkspaceFreshness(ctx, cr)` | `lib/workspace-transactions.mjs` | 新增只读分类函数（复用 classifyRepoWorkspace + ancestry） |
| `syncWorkspaceToTrunk(ctx, { cr })` | `lib/workspace-transactions.mjs` | 新增同步事务（lock + journal + 逐仓 ff-only + 只向前恢复） |
| `workspace freshness|sync` 子命令 | `crctl.mjs`（cmdWorkspace dispatch + HELP） | 窄 CLI 接线，不含算法 |
| 故障点登记 | `lib/durable-tx.mjs#FAULT_POINTS` | 追加 2 条（`ws-sync-after-preflight`、`ws-sync-after-repo`） |
| `workspace-freshness` Skill | `skills/sync/workspace-freshness/SKILL.md` | 新增窄 Skill（业务路由） |
| 两个 gate 节点 + replayNodes | `pipeline-templates/code-implementation.pipeline.json` | 插入 ...016/...017，扩展 ...009 replayNodes |
| 台账同步 | `skills/_index.yml`、`agent-skill-matrix.yml`、`pipeline-templates/_index.yml` | 登记 |
| README 人读段 | `README.md` | 入口与人工动作索引 |
| 测试 | `test/workspace-freshness.test.mjs`（新增）、契约断言并入现有 contract 测试 | 分类/事务/契约/集成 |

`gates.json`、`dir-graph.yaml#change-request-track.state_machine`、`rules.json`（controlled-shell 白名单）均**零改动**：freshness 是 pipeline 节点级门禁而非状态机门禁；`merge --ff-only` 发生在 crctl 深原语内部（gitMust 不经 rules.json 白名单），不扩展 `crctl git` 面。

# 2. 数据模型

## 2.1 每仓 freshness 事实（只读输出）

```typescript
interface RepoFreshnessFact {
  repo: string;                    // repository id
  trunkRef: string;                // 如 "custom/main"
  trunkSha: string | null;         // fetch 后捕获的 refs/remotes/origin/{trunk}
  branch: string;                  // 固定 requirement/{CR-ID}
  headSha: string | null;
  worktreePath: string;
  workspaceClassification: 'missing'|'healthy'|'branch-only'|'remote-only'|'dirty'|'wrong-branch'|'path-unregistered';
  freshness: 'fresh'|'behind-clean'|'diverged'|'unknown';  // 不可比较时 unknown
  dirty: boolean;
  canFastForward: boolean;         // freshness==='behind-clean' 的机械投影
  reason?: string;                 // unknown/blocked 时的结构化原因
}

interface FreshnessResult {
  cr: string;
  repositories: RepoFreshnessFact[];   // 按 repo id 排序
  allFresh: boolean;
  syncable: boolean;                   // 无阻断项且至少一仓 behind-clean（或全 fresh 时 false）
}
```

## 2.2 同步结果与 journal payload

```typescript
interface RepoSyncRecord {
  repo: string;
  beforeSha: string;
  targetTrunkSha: string;
  afterSha: string | null;
  action: 'unchanged'|'fast-forwarded'|'pending'|'blocked';
  reason?: string;
}

interface SyncResult {
  cr: string;
  txId: string | null;      // 全 fresh no-op 时为 null（不创建空 journal）
  phase: 'complete';
  changed: boolean;
  repositories: RepoSyncRecord[];
  recoverCommand: string;
}
```

journal（op=`workspace`，key=`{CR-ID}`）的 `workspace` payload：

```json
{
  "phase": "preflight | syncing | complete",
  "repos": [
    { "repo": "tools", "beforeSha": "...", "targetTrunkSha": "...", "afterSha": "...", "action": "fast-forwarded" }
  ]
}
```

`inputDigest = sha256(JSON.stringify({ op: 'workspace-sync', cr }))`：同一命令重跑 inputDigest 不变可续跑；输入漂移触发既有 `TX_INPUT_CONFLICT`。

## 2.3 audit 记录

| kind | 记录时机 | 字段 |
|---|---|---|
| `workspace-freshness` | 仅阻断或技术失败（成功只读不逐次写） | cr、actor、失败 code、阻断 repo 列表 |
| `workspace-sync` | 每次 sync 调用（含 no-op 与失败） | cr、txId、phase、changed、每仓 action/beforeSha/targetSha/afterSha、actor |

不新建 workspace ledger；成功 fast-forward 的业务提交本身即 Git 权威事实（不变量 6）。

# 3. 接口契约

## 3.1 CLI（crctl.mjs）

```text
crctl workspace freshness <CR-ID> [--workspace <path>]
crctl workspace sync      <CR-ID> [--workspace <path>]
```

- cmdWorkspace dispatch 白名单由 `inspect|ensure|cleanup` 扩展为 `inspect|ensure|cleanup|freshness|sync`；freshness/sync 不接受任何其他 flag（多余 flag → `BAD_ARGS`），CR-ID 复用既有 `/^CR-\d{4}-\d{3,}$/` 校验。
- freshness：`runTxAsync(classifyWorkspaceFreshness(ctx, cr))` → `ok({ op:'workspace-freshness', ...result })`；不写 audit（成功）、不写 journal。
- sync：`runTxAsync(syncWorkspaceToTrunk(ctx, { cr }))` → `auditLog(kind:'workspace-sync')` → `ok({ op:'workspace-sync', ...result })`。
- HELP 文本追加两行用法说明（不写算法细节）。

## 3.2 深模块函数（workspace-transactions.mjs）

```typescript
/** 只读业务检查：零写入（fetch 更新 remote-tracking 元数据除外）。 */
export function classifyWorkspaceFreshness(ctx, cr): FreshnessResult

/** 显式 ff-only 同步事务：lock(op=workspace, scope=workspace-sync-{cr}) + journal + 逐仓重核。 */
export async function syncWorkspaceToTrunk(ctx, { cr }): Promise<SyncResult>
```

错误码（TxError，经 runTxAsync 映射为 fail）：

| code | 语义 |
|---|---|
| `WORKSPACE_FRESHNESS_DIVERGED` | 双方互不为祖先，人工处理 |
| `WORKSPACE_FRESHNESS_CHANGED` | preflight 与写入间 trunk/HEAD/branch/dirty 漂移 |
| `WORKSPACE_TRUNK_UNAVAILABLE` | fetch 或 origin/{trunk} 不可确认 |
| `WORKSPACE_SYNC_BLOCKED` | 基础分类/路径/分支/注册不满足（携带 workspaceClassification） |
| `WORKSPACE_SYNC_CONFLICT` | ff-only 失败或 afterSha≠targetSha |
| 既有复用 | `TX_LOCK_HELD`、`TX_GIT_FAILED`、`REPO_GRAPH_*`、`TX_INPUT_CONFLICT`、`WORKSPACE_CR_INVALID` |

`WORKSPACE_FRESHNESS_STALE` 不是错误码：`behind-clean` 是 freshness 输出中的正常业务事实，由 Skill 决定是否 sync（PRD FR-02：只读检查不得把可同步状态表达为失败）。

## 3.3 Skill 契约（skills/sync/workspace-freshness/SKILL.md）

输入：

| 参数 | 必填 | 说明 |
|---|---|---|
| `cr_id` | ✅ | 目标 CR-ID |
| `gate` | ✅ | `implement-start` \| `review-start` |

输出（供 Pipeline 分流）：`route` ∈ `continue`、`synced-continue`、`replay`、`manual`；`facts`（freshness 结构化结果摘要）；`blockers`（manual 时逐仓原因）。

路由规则：

| gate | freshness 结果 | route |
|---|---|---|
| implement-start | allFresh | `continue` |
| implement-start | syncable | 调 sync → 重跑 freshness → allFresh ? `synced-continue` : `manual` |
| implement-start | 其余 | `manual`（abort，不进入 implement-code） |
| review-start | allFresh | `continue` |
| review-start | syncable | 调 sync → `replay`（review_feedback：基线已前进，需重建实现/测试/checkpoint 证据） |
| review-start | 其余 | `manual`（abort，不盲目消耗 reviewLoop） |

Skill 只调用 `crctl workspace freshness|sync`；不出现 git 命令、锁、journal、CAS、状态推进或账本编辑步骤。

台账登记：`skills/_index.yml` 新增 active 条目；`agent-skill-matrix.yml` 中 `system-orchestrator.owns += workspace-freshness`（唯一 owner）、`dev-agent.can-call += workspace-freshness`。

## 3.4 Pipeline 契约（code-implementation.pipeline.json）

| 新节点 | id | 位置 | ref / 输入 | onFail |
|---|---|---|---|---|
| Workspace freshness（实施前） | `00000000-0000-0000-0015-000000000016` | `approve-dev-start`(...005) 之后、`implement-code`(...006) 之前 | workspace-freshness，`gate=implement-start` | abort |
| Workspace freshness（评审前） | `00000000-0000-0000-0015-000000000017` | 统一 checkpoint `push-progress`(...008) 之后、「选择代码评审 LLM」human_approval(...013) 之前 | workspace-freshness，`gate=review-start` | abort |

`review-code` 节点(...009) 的 `reviewLoop.replayNodes` 由 4 项扩为 5 项：

```text
implement-code(...006) → write-test-report(...007) → push-progress(...008)
  → workspace-freshness(...017, purpose: re-verify-baseline) → review-code(...009)
```

write-test-report 节点(...007) 的测试证据闭环 replayNodes（`implement-code → write-test-report`）不变。`pipeline-templates/_index.yml` 的 code-implementation `nodes: 13 → 15`。

节点 prompt 只描述：读取输入、调用一次 Skill、按 route 分流、失败中止；不复制 Skill 步骤全文，不出现 git/journal 字样。

# 4. 关键算法与流程

## 4.1 classifyWorkspaceFreshness（只读）

```text
for repo of ctx.repositories（已按 id 排序）:
  info = classifyRepoWorkspace(ctx, repo, cr)          # 复用，零改动
  if info.classification != 'healthy':
    emit freshness='unknown', reason=classification     # 不猜测
    continue
  headSha = gitMust(wt, ['rev-parse','HEAD'])
  gitMust(repo.rootPath, ['fetch','origin'])            # 仅更新 remote-tracking 元数据
  trunkSha = gitMust(repo.rootPath, ['rev-parse', `refs/remotes/origin/${repo.trunk}`])
      # 失败 → WORKSPACE_TRUNK_UNAVAILABLE（该仓 unknown，整体不可 fresh）
  if headSha == trunkSha                      → fresh
  elif isAncestor(trunkSha, headSha)          → fresh        # ahead-only 是正常开发态
  elif isAncestor(headSha, trunkSha)          → behind-clean, canFastForward=true
  else                                        → diverged
# isAncestor(a,b) = gitRun(wt, ['merge-base','--is-ancestor', a, b]).status === 0
allFresh = 全部 fresh；syncable = allFresh ? false : 无阻断项 && 存在 behind-clean
```

禁止用时间戳、commit message、`log` 计数等启发式替代 ancestry（PRD FR-01.5）。

## 4.2 syncWorkspaceToTrunk（事务）

```text
lock = acquireLock({ root, scope: `workspace-sync-${cr}`, op: 'workspace' })
journal = loadOrCreateJournal({ op:'workspace', cr, graphDigest, inputDigest })
payload = journal.workspace ?? { phase:'preflight', repos: [] }

# 1) 全仓 preflight（锁内、任何写入前）：classifyWorkspaceFreshness
#    任一仓非 fresh 且非 behind-clean（dirty/diverged/unknown/基础阻断/trunk 不可确认）
#      → 零仓写入，抛对应 TxError；不创建空 journal（全 fresh 直接 changed=false 返回）
#    faultPoint('ws-sync-after-preflight')

# 2) 逐仓（repo id 顺序，跳过 payload 中已 fast-forwarded/confirmed 的仓）：
for repo of behind-clean 仓:
  重核：branch、status --porcelain 为空、HEAD==beforeSha、重新 fetch 并比对 origin/{trunk} SHA
  任一漂移 → WORKSPACE_FRESHNESS_CHANGED（停止后续仓）
  gitMust(wt, ['merge','--ff-only', targetSha])        # 唯一允许的 worktree 写操作
  afterSha = gitMust(wt, ['rev-parse','HEAD'])
  if afterSha != targetSha → WORKSPACE_SYNC_CONFLICT
  payload.repos[i].action='fast-forwarded'; save('syncing')
  faultPoint('ws-sync-after-repo')

# 3) save('complete') → 返回 SyncResult（recoverCommand = 同一 sync 命令）
finally lock.release()
```

恢复语义（重跑同一命令）：journal phase=complete → 幂等成功；phase=syncing → 已 `afterSha==targetSha` 的仓标 `unchanged/confirmed`，仍在 `beforeSha` 的仓继续，其余漂移硬失败；不 reset/revert/删除 journal（PRD FR-04）。多仓只向前，不承诺跨仓 ACID 回滚。

## 4.3 Skill 编排（review-start 同步后重放）

sync 改变了 source HEAD，既有测试/评审/checkpoint 证据全部失效。Skill 返回 `replay` 并附 review_feedback；Pipeline 按 reviewLoop 从 implement-code 顺序重放到 review-code（§3.4）。diverged/manual 场景不进入 replay（避免用自动重试掩盖人工冲突），输出每仓 repo/path/SHA 供人工处理；人工把事实恢复为可比较状态（如提交、pull-progress 或重开 worktree）后重新走 gate。

## 4.4 实施顺序（同一 CR 内，无 feature flag）

1. Phase A：`classifyWorkspaceFreshness` + freshness 子命令 + 分类测试（只读，先落地最安全）。
2. Phase B：`syncWorkspaceToTrunk` + sync 子命令 + 故障注入/恢复测试。
3. Phase C：Skill + Pipeline 两个 gate + replayNodes + 契约测试 + 台账同步。
4. Phase D：README 人读段。

# 5. 技术选型与替代方案

| 被审查方案 | 结论 | 原因 |
|---|---|---|
| 第二套事务框架/WAL/branch manager | 删除 | durable-tx 已有 workspace op、锁、journal、恢复（ARCHITECTURE §6 明确否决） |
| 扩展 `pull-progress` 处理 trunk freshness | 删除 | 其事实源是远端 requirement checkpoint，方向与语义不同，混用会产生两个 trunk 事实源 |
| `ensureRepoWorkspace` 自动同步 | 删除 | 会把注册/resume 的只读补齐扩权成隐式写操作 |
| 自动 merge/rebase/冲突解决 | 删除 | 无法机械判断独有提交的业务取舍；违反零覆盖承诺 |
| 检查远端 requirement 分支一致性 | 删除 | checkpoint/push-progress 既有职责，两个能力不得重复拥有同一远端事实 |
| ahead/behind commit count | 延后 | ancestry 足够 gate 与 sync；count 只增加解析与测试矩阵 |
| 四处 freshness gate | 收敛两处 | implement 前 + review 前覆盖关键边界；测试/checkpoint/审批已有既有重核 |
| 每次成功 freshness 写 audit | 删除 | 审计噪声；只持久化 sync、阻断、竞态与失败 |
| feature flag / 观察期账本 / daemon | 删除 | Phase A→D 的 CR 内顺序已提供安全落地路径 |
| 新增 Agent / npm 依赖 / 版本化脚本 | 删除 | 现有 actor、Node 标准库与 crctl 深原语足够 |

# 6. FR 到技术实现映射

| PRD | 实现落点 |
|---|---|
| FR-01 分层分类 | §4.1 classifyWorkspaceFreshness；freshness 与 WORKSPACE_CLASSIFICATIONS 分层输出 |
| FR-02 只读检查 | §3.1 freshness 子命令；§4.1（fetch 边界、unknown 不降级、成功不写 audit） |
| FR-03 显式同步 | §4.2 syncWorkspaceToTrunk（全仓 preflight、唯一 ff-only、白名单外参数 BAD_ARGS） |
| FR-04 幂等/竞态/恢复 | §4.2（inputDigest、逐仓重核、fault points、只向前恢复、多仓顺序语义） |
| FR-05 生命周期 gate | §3.4 两个节点 + replayNodes 扩展；gate 是 Pipeline 编排而非状态机门禁（gates.json 零改动） |
| FR-06 Skill/Agent/crctl/文档 | §3.3 Skill 契约与台账登记；§1.3 职责表；§8 采纳清单；README 人读段 |

# 7. 安全与性能考量

## 7.1 安全边界

- 唯一 worktree 写操作是 `git merge --ff-only <captured-sha>`；代码中不得出现 reset/clean/stash/rebase/force/普通 merge 的 sync 路径（契约测试扫描）。
- dirty/diverged/unknown/wrong-branch/missing/branch-only/remote-only/path-unregistered 在全仓 preflight 即零写入硬失败。
- ff-only 前逐仓重核四项事实；锁只串行化本地 crctl 事务，不假设锁住远端 trunk——trunk 前进靠重核与既有 release-subjects 重核兜底。
- `crctl git` 白名单（rules.json）不扩展：sync 的 Git 写发生在深原语 gitMust 内部；Skill 侧只读需求由 freshness 子命令满足，无需新增白名单形态。

## 7.2 性能

- 每 gate 每仓成本：1×classify + 1×fetch + ≤2×ancestry；无缓存、无后台扫描、无并发。
- freshness 无锁；sync 独占 `workspace-sync-{cr}` 锁，冲突返回既有 TX_LOCK_HELD。
- 无新增生产依赖（不变量 3）；全部解析先 CRLF→LF、`split(/\r?\n/)`、失败硬失败（不变量 4）。

## 7.3 测试设计

| 层 | 用例 |
|---|---|
| 分类单元 | fresh（HEAD==trunk）、fresh（ahead-only）、behind-clean、diverged、五类基础分类→unknown、trunk 缺失/fetch 失败→WORKSPACE_TRUNK_UNAVAILABLE、多仓稳定排序、Windows 路径身份与 CRLF |
| 事务（`test/workspace-freshness.test.mjs`，复用现有 fixture） | ff-only 成功且 afterSha==target；全 fresh no-op 不建 journal；dirty/diverged/unknown 零写入；preflight 阻断全仓零写入；`ws-sync-after-repo` 故障注入后续跑只向前；trunk 变化→WORKSPACE_FRESHNESS_CHANGED；HEAD/branch/dirty 变化→硬失败；并发锁→TX_LOCK_HELD；重跑幂等不重复提交 |
| 契约 | workspace-freshness active 且 system-orchestrator 唯一 owns、dev-agent can-call；两节点位于 implement-code 前与 review-code 前；replayNodes 含 ...017；`_index.yml nodes=15`；Pipeline prompt 无 git/journal 字样；SKILL.md 无 Git 算法/账本编辑步骤 |
| 集成 | implement gate：behind-clean→sync→继续；diverged→abort；review gate：trunk 前进→拦截→按 replayNodes 重建证据；Windows 与 Ubuntu 各一遍 active repository 矩阵 |

# 8. Prompt 采纳影响

本 CR 触及 `crctl.mjs` 的 dispatch 分支（cmdWorkspace 新增 freshness|sync），本节必填；不触及 `rules.json#protectedPaths.deny`。

| Skill / 文档 | 现状 | 应改为 |
|---|---|---|
| `skills/sync/workspace-freshness/SKILL.md` | 不存在 | 新增：唯一调用方，`crctl workspace freshness` + 条件 `crctl workspace sync`，按 §3.3 路由 |
| `skills/shared/crctl/SKILL.md` | brief 未含 workspace freshness/sync | brief/能力描述补充两个窄子命令（能力面声明，不含算法） |
| `pipeline-templates/code-implementation.pipeline.json` | 无 freshness gate | 按 §3.4 插入两节点并扩展 review-code replayNodes |
| `README.md` | 无 freshness 入口 | 增加命令入口、结果含义与人工处理动作一段，链接 Skill/crctl 权威契约 |

明确不采纳（防止过度扩散）：`implement-code`/`review-code`/`pull-progress`/`push-progress`/`write-test-report` 的 SKILL.md 均不改动——gate 是独立 Pipeline 节点，review-code 的 merge-base diff range、checkpoint 与 pull-progress 的远端 requirement 语义保持原样。

# 9. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-16 | v0.1.0 | Ray | 初始设计：两层分类、显式 ff-only 同步事务、双 gate 与 reviewLoop 重放、职责边界与采纳清单 |

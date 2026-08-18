---
id: CR-2026-046-sdd
type: SDD
cr-ref: CR-2026-046
title: CR 合并与新注册 Worktree 同步治理优化方案 技术设计
status: draft
created: "2026-08-18T20:40:00+08:00"
updated: "2026-08-18T21:02:00+08:00"
---

# SDD — CR 合并与新注册 Worktree 同步治理优化方案

> 目标代码仓：`tools`（本 CR 只改 `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` 与两个测试文件）。
> 架构基线：`tools/ARCHITECTURE.md`（已存在，只读引用；本 CR 不修订它——不新增分组、Pipeline 结构、写入子命令、状态机口径，不构成架构级变更）。

## 1. 架构概览

### 1.1 模块边界与依赖方向

本 CR 严格落在 crctl 执行层，不触及上层：

```text
Skill（write/register/merge 调用点不变，一次深原语）
   ↓ 调用
crctl.mjs（dispatch 分支零改动；merge 输出经 ...result 透传）
   ↓ import
lib/workspace-transactions.mjs   ← 本 CR 唯一实现落点
   ├─ ensureRepoWorkspace（missing 分支修正）
   └─ reconcileLocalTrunks（新增模块内 helper，mergeCr 调用；导出仅供既有测试模式）
   ↓ import（既有）
lib/durable-tx.mjs（TxError/faultPoint/lock——只复用，不改）
```

不新增文件、不新增依赖、不改状态机/gates/Pipeline/README/Skill/Agent。两个测试文件 `test/register-tx.test.mjs`、`test/merge-tx.test.mjs` 追加用例。

### 1.2 两个修改点的位置与关系

| 修改 | 位置（现有代码） | 性质 |
|---|---|---|
| A：注册基点取远端事实 | `ensureRepoWorkspace` 的 `case 'missing'`（现约 L501-524） | 事务内（register journal 恢复语义不变，失败抛 TxError 中断重跑） |
| B：merge 后本地同步 | `mergeCr` 返回前（现约 L1491-1497）新增 helper 调用 | 非事务化（不写 journal/账本，结果只进输出） |

两者共享的既有能力（PRD §1.3）：`classifyRepoWorkspace` 七分类、`gitRun`/`gitMust`、`TxError`、`faultPoint`、register/merge journal envelope 与目录锁。全部直接复用，不改签名。

### 1.3 关键流程

```text
注册（缺口 A）：
  ensureRepoWorkspace 首次 classify = missing
    → git fetch --prune origin（失败 → WORKSPACE_TRUNK_UNAVAILABLE，不创建/修改 CR branch/worktree）
    → classifyRepoWorkspace 重新分类
       → remote-only：git branch --track + worktree 挂接（既有逻辑）
       → branch-only：挂接并发出现的既有本地 CR branch（既有逻辑）
       → missing：解析 refs/remotes/origin/{trunk} 存在后 git branch {cr} <该 ref> + worktree
       → 其他：WORKSPACE_ENSURE_BLOCKED 硬阻断

合并（缺口 B）：
  mergeCr 现有事务（preflight → prepare → lease publish → finalize）不变
    → finalizePushed 确认、journal save('complete')
    → reconcileLocalTrunks(ctx) 逐仓 8 判据（结果只入返回对象）
    → return { ..., localTrunkSync }
```

### 1.4 Prompt 采纳影响判定

本 CR 不触及 `crctl.mjs` 的 dispatch 分支（不新增/重命名子命令，flag 面不变；`localTrunkSync` 经 `ok({ op:'merge', ...result })` 自动透传）与 `skills/shared/controlled-shell/rules.json` 的 deny 面（无新受控路径）。SDD 第 8 节（Prompt 采纳影响）条件不成立，省略。

## 2. 数据模型

### 2.1 无新增持久化结构

- register journal / merge journal：字段不变（PRD FR-6）。
- 无新账本文件、无新 `.crctl` 目录。
- 唯一新增数据形态是 `crctl merge` 成功输出的内存数组 `localTrunkSync`（非持久化、不写 audit、不写 journal）：

```ts
type LocalTrunkSyncRow = {
  repo: string;                       // repositories[].id
  trunk: string;                      // repositories[].trunk
  before: string | null;              // 进入 helper 时可解析的本地 HEAD，否则 null
  remote: string | null;              // fetch 成功后捕获的 origin/{trunk} SHA，否则 null
  after: string | null;               // helper 返回时可解析的本地 HEAD，否则 null
  status: 'synced' | 'unchanged' | 'skipped' | 'failed';
  reason: 'dirty' | 'wrong-branch' | 'diverged' | 'fetch-failed' | 'trunk-unavailable' | 'ff-only-failed' | null;
};
```

### 2.2 字段取值规则（PRD FR-9，实现按此逐字段落值）

| 结果 | status | reason | before | remote | after |
|---|---|---|---|---|---|
| wrong-branch（含 detached/读取失败） | skipped | wrong-branch | 可解析 HEAD 或 null | null | = before |
| dirty | skipped | dirty | HEAD | null | = before |
| fetch 失败 | failed | fetch-failed | HEAD | null | = before |
| trunk 不可解析 | failed | trunk-unavailable | HEAD | null | = before |
| 已一致 | unchanged | null | HEAD | = before | = before |
| 非祖先 | skipped | diverged | HEAD | 已捕获 SHA | = before |
| ff-only 成功 | synced | null | HEAD | 捕获 SHA | 新 HEAD |
| ff-only 失败 | failed | ff-only-failed | HEAD | 捕获 SHA | 失败后实际 HEAD（可解析） |

## 3. 接口契约

### 3.1 `ensureRepoWorkspace(ctx, repo, cr)`（内部函数，行为契约变更）

- 签名不变。`healthy` / `branch-only` / `dirty` / `wrong-branch` / `path-unregistered` 行为不变，且不触发 fetch。
- `missing`：先 `git fetch --prune origin`，清理已从远端删除的 stale tracking refs，再重新分类，按 1.3 流程创建或阻断。
- 新结构化错误 `WORKSPACE_TRUNK_UNAVAILABLE`（TxError），extra 携带 `{ repo, ref?, cause? }`；`ref` 为 trunk 不可解析时的 refs/remotes/origin/{trunk}，`cause` 为 fetch 失败时底层 git 错误摘要。
- 保证：错误路径不创建/修改/删除 `requirement/{CR-ID}` branch 与 worktree；fetch 已更新的 remote-tracking refs 不回滚；不回退本地 trunk；无 reset/stash/rebase。

### 3.2 `reconcileLocalTrunks(ctx)`（新增导出函数，供 mergeCr 与单元测试调用）

- 输入：`ctx`（`resolveRepositories` 产物，含 `repositories[]`：`id/trunk/rootPath`）。
- 输出：`LocalTrunkSyncRow[]`，每仓一行，顺序与 `ctx.repositories` 一致。
- 错误语义：**绝不抛出**。只读判定使用 `gitRun`；有副作用的 `fetch --prune` 与 `merge --ff-only` 均按模块不变量经 `gitMust` 执行，并在局部 try/catch 中转换为 `failed/fetch-failed` 或 `failed/ff-only-failed`（PRD FR-10 的 exit 0 前提）。

### 3.3 `mergeCr(ctx, input)` 返回契约（增量）

- 现有字段全部不变（`cr/txId/phase/changed/sideEffects/recoverCommand/operationalWorkspace/mergedStatus`）。
- 新增 `localTrunkSync: LocalTrunkSyncRow[]`，在 `save('complete')` 之后、return 之前计算。
- helper 只在本次 `mergeCr` 远端 finalize 确认并 `save('complete')` 后执行一次。若进程在 complete 后、helper 前或执行中退出，不提供自动恢复，也不承诺重跑 `crctl merge`（finalize 后 authority/status 门禁会阻止该命令重入）；用户按 PRD FR-10 使用原生 `git pull --ff-only`。
- `crctl merge status` 只读快照、`workspace inspect`、`crctl status` 输出面均不变（PRD NFR-5）。

### 3.4 错误码新增

| code | 触发 | 携带 | 语义 |
|---|---|---|---|
| `WORKSPACE_TRUNK_UNAVAILABLE` | fetch 失败或 origin/{trunk} 不可解析 | repo/ref/cause | 注册事务中断，重跑幂等续跑；不回退本地 trunk |

## 4. 关键算法与流程

### 4.1 ensureRepoWorkspace missing 分支（伪代码）

```text
case 'missing':
  try:
    gitMust(rootPath, ['fetch', '--prune', 'origin'])
  catch e:
    throw TxError('WORKSPACE_TRUNK_UNAVAILABLE', '{repo}: fetch origin 失败（不创建 CR branch/worktree）', { repo, cause: e.message })

  re = classifyRepoWorkspace(ctx, repo, cr)      # 复用既有分类，不新写逻辑

  if re.classification == 'remote-only':
    gitMust(rootPath, ['branch', '--track', branch, 'origin/' + branch])
    return create('from-remote')                 # 既有 create 闭包

  if re.classification == 'branch-only':
    return create('from-local-branch')           # 并发出现本地 CR branch，复用既有恢复

  if re.classification != 'missing':
    throw TxError('WORKSPACE_ENSURE_BLOCKED', 'fetch 后重新分类={cls}，硬阻断', { ...re })

  trunkRef = 'refs/remotes/origin/' + repo.trunk
  trunk = gitRun(rootPath, ['rev-parse', '--verify', '-q', trunkRef])
  if trunk.status != 0 or trunk.stdout == '':
    throw TxError('WORKSPACE_TRUNK_UNAVAILABLE', '{trunkRef} 不可解析，不回退本地 trunk', { repo, ref: trunkRef })

  gitMust(rootPath, ['branch', branch, trunkRef])   # 起点=远端 trunk ref，不再是本地 trunk
  return create('from-remote-trunk')
```

要点：
- `git branch <name> refs/remotes/origin/{trunk}` 是 git 原生起点语义（等价 `git branch <name> <SHA>`，不设置 upstream——CR 分支本就不跟踪 trunk）。
- `classifyRepoWorkspace` 在 worktree 缺失时提前返回，故 fetch 后重新分类只会出现 `branch-only`（并发建分支）、`remote-only`、`missing` 三类；前两者显式复用既有恢复路径，其余（不可达但防御性）硬阻断。
- `--prune` 是满足“远端事实”与 trunk-unavailable 合同的一项原生 Git 参数：远端已删除 trunk/CR 分支时清理 stale `refs/remotes/origin/*`，不新增查询算法或事务。
- 失败发生在 register 事务的 worktree 阶段（账本已提交/push），重跑同命令按 journal `worktrees[]` 续跑，幂等（PRD NFR-2）。

### 4.2 reconcileLocalTrunks（8 判据，PRD FR-8 逐条落位）

```text
for repo in ctx.repositories:
  row = { repo, trunk, before:null, remote:null, after:null, status:null, reason:null }
  before = gitRun(rootPath, ['rev-parse', '-q', 'HEAD'])          # 判据 0（取值）
  row.before = before.status == 0 ? before.stdout : null

  cur = gitRun(rootPath, ['symbolic-ref', '--short', '-q', 'HEAD'])
  if cur.status != 0 or cur.stdout != repo.trunk:                 # 判据 1
    row = { ...row, status:'skipped', reason:'wrong-branch', after: row.before }; continue

  st = gitRun(rootPath, ['status', '--porcelain'])
  if st.status != 0 or st.stdout != '':                           # 判据 2
    row = { ...row, status:'skipped', reason:'dirty', after: row.before }; continue

  try:
    gitMust(rootPath, ['fetch', '--prune', 'origin'])              # 判据 3；副作用只经 gitMust
  catch e:
    row = { ...row, status:'failed', reason:'fetch-failed', after: row.before }; continue

  rr = gitRun(rootPath, ['rev-parse', '--verify', '-q', 'refs/remotes/origin/' + repo.trunk])
  if rr.status != 0 or rr.stdout == '':                           # 判据 4
    row = { ...row, status:'failed', reason:'trunk-unavailable', after: row.before }; continue
  row.remote = rr.stdout                                          # 捕获 SHA，此后不再重新解析

  if row.before == row.remote:                                    # 判据 5
    row = { ...row, status:'unchanged', after: row.before }; continue

  anc = gitRun(rootPath, ['merge-base', '--is-ancestor', row.before, row.remote])
  if anc.status != 0:                                             # 判据 6（before=null 时命令必失败，同归 diverged）
    row = { ...row, status:'skipped', reason:'diverged', after: row.before }; continue

  try:
    faultPoint('local-sync-ff-only-failed', { repo: repo.id })    # 复用既有测试故障注入；仅匹配测试环境变量时抛出
    gitMust(rootPath, ['merge', '--ff-only', row.remote])         # 判据 7：用捕获 SHA，不重解析移动 ref
    h1 = gitRun(rootPath, ['rev-parse', '-q', 'HEAD'])
    row = { ...row, status:'synced', after: h1.status == 0 ? h1.stdout : null }
  catch e:                                                        # 判据 8
    h1 = gitRun(rootPath, ['rev-parse', '-q', 'HEAD'])
    row = { ...row, status:'failed', reason:'ff-only-failed', after: h1.status == 0 ? h1.stdout : null }
```

安全属性：只读判定经 `gitRun`；两条 Git 副作用命令仅为 `git fetch --prune origin`（remote-tracking refs）与 `git merge --ff-only <捕获 SHA>`（本地 trunk），均经 `gitMust` 且局部捕获；无 reset/stash/rebase/普通 merge/checkout；失败即本仓终止，不影响其他仓与远端结果。

### 4.3 调用点（mergeCr）

```text
payload.finalizePushed 确认后（现有代码不变）
  payload.operationalWorkspace = txws
  await save('complete')
  const localTrunkSync = reconcileLocalTrunks(ctx)   ← 新增两行（含 return 里的字段）
  return { ..., localTrunkSync }
```

helper 在 merge 目录锁内执行（return 在 `finally` 释放锁之前）：与既有 merge 事务互斥，无需新锁；不写 journal。进程在 `save('complete')` 后、helper 前或执行中退出时不补偿，且 finalize 后 authority/status 门禁不允许重跑 `crctl merge`；用户按 PRD FR-10 原生执行 `git pull --ff-only`。

## 5. 技术选型与替代方案

| 决策 | 选择 | 替代方案与否决理由 |
|---|---|---|
| 注册基点 | `fetch --prune` + 重新分类 + `git branch <cr> refs/remotes/origin/{trunk}` | register journal 记录 `base-sha/source`（PRD §4.3 否决：本地 ref 已是基点权威事实，journal 复制 Git 事实且跨仓无共享 SHA） |
| 重新分类 | 复用 `classifyRepoWorkspace` 二次调用 | 新写 fetch 后专用分类函数（重复逻辑，违反复用优先） |
| 本地同步 | 非事务化 best-effort ff-only | 本地同步事务/durable journal/intent digest/恢复命令（PRD §6.3 否决：远端事务已完成，本地补偿无同级原子性要求，且再造第二套事务违反 ARCHITECTURE §6） |
| 合并算法 | `git merge --ff-only <捕获 SHA>`（CR-2026-043 workspace sync 已验证模式） | 自写 merge 语义/二次解析移动 ref（捕获 SHA 是 FR-8 明确要求，且已有先例） |
| ff-only-failed 测试 | 复用 `faultPoint('local-sync-ff-only-failed')` 注入 TxError，断言 catch 转换 | 文件系统破坏性构造（index.lock/hook 干扰，脆弱且污染其他判据） |
| 依赖 | Node 标准库（fs/path/crypto/spawnSync）+ 原生 git | 任何新依赖（违反 ARCHITECTURE 不变量 3） |

## 6. FR 到技术实现映射

| FR | 实现位置 | 方式 |
|---|---|---|
| FR-1 | `workspace-transactions.mjs#ensureRepoWorkspace` `case 'missing'` | `fetch --prune` → `classifyRepoWorkspace` 重新分类；首次分类 healthy/branch-only 路径零改动（天然不 fetch） |
| FR-2 | 同上 | 重新分类 `remote-only` 分支复用既有 `--track` + `create('from-remote')` |
| FR-3 | 同上 | `rev-parse --verify -q refs/remotes/origin/{trunk}` 成功后 `git branch <cr> <trunkRef>`；删除原 `git branch <cr> {repo.trunk}` 路径 |
| FR-4 | 同上 | fetch 失败/trunk 不可解析均 `TxError('WORKSPACE_TRUNK_UNAVAILABLE')`；无回退分支 |
| FR-5 | 同上 | 重新分类 branch-only → 复用 `create('from-local-branch')`；dirty/wrong-branch/path-unregistered 等非恢复分类 → `WORKSPACE_ENSURE_BLOCKED` 硬阻断 |
| FR-6 | 无改动 | register journal 结构零变更（`register-tx.test.mjs` 既有 journal 断言回归） |
| FR-7 | `mergeCr` 返回前 + 新 `reconcileLocalTrunks(ctx)` | 逐 `ctx.repositories` 处理 `repo.rootPath`；不遍历 worktree list、不碰 CR worktree |
| FR-8 | `reconcileLocalTrunks` 判据 1-8 | 见 §4.2 伪代码逐条对应 |
| FR-9 | 同上 + `mergeCr` return | `LocalTrunkSyncRow` 字段按 §2.2 表落值 |
| FR-10 | `reconcileLocalTrunks` 不抛 + `mergeCr` 不改 exit 语义 | 任何结果均返回完整数组；`crctl.mjs` 零改动，`ok()` 照常 exit 0 |
| FR-11 | 无改动 | writeback 继续只使用 `operationalWorkspace`（本 CR 不触碰该路径） |

## 7. 安全与性能考量

### 7.1 安全

- **现场零破坏**（PRD NFR-1）：两个修改点合计的写命令仅 `git fetch --prune origin`（更新/清理 remote-tracking refs）、`git branch`（新分支/--track）、`git worktree add`（既有 create 闭包）、`git merge --ff-only <捕获 SHA>`。无 reset/stash/rebase/普通 merge/强制 checkout/本地分支删除；无回滚或补偿事务。
- **不回退本地 trunk**：`WORKSPACE_TRUNK_UNAVAILABLE` 与 `trunk-unavailable` 都是终止/跳过，绝不 fallback 到 `repo.trunk` 本地 ref。
- **并发**：register 修改在 register 事务锁内；helper 在 merge 事务锁内，与其他 merge 互斥。helper 无共享状态。
- **历史重写防护**：注册/merge 事务既有的 `classifyRemoteCommit` 历史重写硬阻断不受影响；helper 只做 ff-only，祖先判定由 git 原生 `merge-base --is-ancestor` 承担，不新增自定义算法。
- **错误输出与观察面**：新增错误码沿既有 `TxError` → `fail` 结构化错误路径返回；本 CR 不新增失败审计能力。`localTrunkSync` 刻意不写 audit/journal（PRD NFR-5 唯一观察面 = merge 输出）。

### 7.2 性能

- 新增 git 调用：注册 missing 仓 +1 fetch、+1 重新分类（4 次只读 git）；merge helper 成功路径每仓最多 8 次 git（before、branch、status、fetch、remote、ancestor、merge、after），各跳过/失败路径提前结束。
- 对照 ARCHITECTURE §7a 外部调用量基线（merge 目标 2-4）：本次每仓 +1 fetch 属必要远端事实刷新，不删除任何 gate/测试/审批。
- 无大文件 IO、无 YAML 解析新增（不触碰行尾纪律敏感面；新增代码不含跨行正则/哈希解析）。

### 7.3 失败模式

| 失败 | 系统行为 |
|---|---|
| 注册 fetch 失败 | `WORKSPACE_TRUNK_UNAVAILABLE`，事务中断，重跑幂等续跑 |
| 注册 trunk 缺失 | 同上，不创建 branch/worktree |
| helper fetch 失败 | 该仓 `failed/fetch-failed`，merge 仍 `phase=complete`、exit 0 |
| helper ff-only 失败 | 该仓 `failed/ff-only-failed`，远端发布不受影响 |
| 进程在 save('complete') 后、helper 前或执行中退出 | 同步不补偿；finalize 后不得重跑 merge，用户原生 `git pull --ff-only` |

## 8. 测试设计（写入两个既有测试文件，不新增文件）

### 8.1 register-tx.test.mjs（单元级：直接 import `ensureRepoWorkspace`/`resolveRepositories`，先例同 `merge-tx` import lib 函数）

1. **stale local trunk**：origin master 推进后本地落后，`ensureRepoWorkspace`（missing）→ 本地 `requirement/{CR}` HEAD == 新 origin master SHA（AC-1）。
2. **远端 CR 分支恢复**：仅远端有 `requirement/{CR}`、本地无任何 ref → 分类 `from-remote`，tracking 正确（AC-2）。
3. **fetch 失败**：`git remote set-url origin <bogus>` → 抛 `WORKSPACE_TRUNK_UNAVAILABLE`，无本地 branch/worktree（AC-3）。
4. **trunk 缺失且本地存在 stale tracking ref**：保留本地 `refs/remotes/origin/master`，仅在 bare origin 执行 `update-ref -d refs/heads/master` → `fetch --prune` 清理 stale ref，随后抛 `WORKSPACE_TRUNK_UNAVAILABLE`（AC-3）。
5. **healthy/branch-only 不 fetch**：bogus url 下 `healthy` 返回 `none`、`branch-only` 返回 `from-local-branch` 不抛错（证明无 fetch，AC-4）。
6. 既有七分类/幂等/fault 测试零回归（AC-4/5）。

### 8.2 merge-tx.test.mjs

1. **happy path 追加断言**：现有三仓 happy path 测试追加 `r.json.localTrunkSync` 断言——三仓 `status=synced`、`before`=fixture 初始 HEAD、`remote`=origin master SHA、`after`=remote；主 checkout `rev-parse master` == origin master（AC-6/7）。
2. **表驱动单元测试**（直接调 `reconcileLocalTrunks`，复用 `merge-fixture.mjs` 已导出的 `makeFixture` bare 三仓）：wrong-branch（checkout 其他分支）、dirty（未提交文件）、diverged（本地前进且 origin 也前进）、fetch-failed（bogus url）、trunk-unavailable（远端删 master、本地保留 stale tracking ref，验证 `--prune` 清理）、unchanged（已同步）→ 断言 status/reason/before/remote/after 按 §2.2 表取值（AC-6）。
3. **ff-only-failed 集成**：helper 的 ff-only try/catch 内调用既有 `faultPoint('local-sync-ff-only-failed')`；以 `CRCTL_FAULT_POINT=local-sync-ff-only-failed` 跑完整 merge → exit 0、`phase=complete`、kb 行 `failed/ff-only-failed`、远端 master 已含 merge commit（AC-6/7）。
4. 既有 journal/lease/finalize/重入测试零回归（AC-8）。

### 8.3 不做的测试

- 不测试"helper 前进程中断"恢复（明确不提供恢复，语义测试覆盖即可）。
- 不引入 mock 框架：全部用真实 git 命令 + 既有 faultPoint 注入。

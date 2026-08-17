---
id: CR-2026-044-sdd
type: SDD
cr-ref: CR-2026-044
prd-ref: CR-2026-044-prd
title: Tools 本地业务门禁、远端发布与人工审批确认技术设计
owner: Ray
owner-role: development
status: draft
created: 2026-08-16T23:45:33+08:00
updated: 2026-08-16T23:49:30+08:00
---

# 1. 背景与约束

本设计承接 `CR-2026-044-prd`。当前 Tools 基线为 `8f530589a0ae395f44760f4965a225ea9ac698d6`，已核实：

- `buildReleaseSubjects` 会 fetch origin，并要求远端 requirement ref 精确等于本地 worktree HEAD。
- `verifyReleaseSubjects` 同时检查本地 source/artifact 与 remote-tracking requirement ref，并可能返回 `remote-ref-drift`。
- `mergeCr` 在逐仓 prepare 循环内才检查远端 source，因此前仓可已生成 candidate、后仓才暴露 publication lag。
- `workspace inspect` 当前只返回 `resources[]`，尚未返回 `resolveOperationalWorkspace` 的 authority path。
- requirement/architecture/code 三条 Pipeline 的审批后 checkpoint 完成合同不一致；architecture 仍有 `auto_push_after_sdd`，code 最终 checkpoint 仍为 `onFail=skip`。
- `cmdApprove` 的共享 TTY 判断当前只接受 `yes`。

## 1.1 不变量

1. 保持 release-subjects v1、approval、review annotation、checkpoint ledger、merge journal 与状态机 schema 不变。
2. 保持当前 15 个具名状态 + `(new)`、28 条声明转移、wildcard 展开 50 条。
3. `crctl` 继续只依赖 Node 标准库，Git 调用继续走 `gitRun/gitMust` 与 `shell:false`。
4. 所有摘要继续先做 CRLF 到 LF；逐行解析继续使用 `split(/\r?\n/)`，解析失败硬失败。
5. checkpoint、freshness/sync、merge、writeback、archive 的 lease、CAS、journal、远端确认与恢复语义不得削弱。
6. 本设计不新增状态、账本、公共 CLI、snapshot schema、事务层、版本化转换脚本或第三方依赖。

# 2. 设计原则与职责边界

## 2.1 Ponytail 选择顺序

实现选择固定为：复用现有能力 > Node 标准库 > 原生 Git/文件 API > 已有依赖 > 一行代码 > 最小新增代码。首个足够方案即停止，不建设 verifier/publication registry、provider、adapter、缓存、daemon 或通用 Pipeline context 框架。

## 2.2 模块职责

| 模块 | 本次职责 | 明确禁止 |
|---|---|---|
| Agent | 选择 architecture/coding/writeback Pipeline，传递 CR-ID | 保存状态机、计算 SHA、写受控文件 |
| Pipeline | 固定节点顺序、传递 `operational_workspace`、声明 checkpoint 完成条件与失败中止 | 复制 Git/ref/journal 算法、手写账本 |
| Skill | 解释 local drift/publication lag、调用现有深原语、输出恢复入口 | 自行 fetch、计算 ancestry、实现事务或直接写账本 |
| `crctl` | 本地证据校验、publication preflight、状态/门禁/CAS/账本/审计/原子提交 | 需求价值判断、LLM 评审结论 |
| 版本化脚本 | 保持现有 PRD/SDD/TASK/traceability 确定性转换 | 状态推进、审批、publication 判定 |
| README | 说明事实边界、节点完成条件与 recoverCommand | 复制 verifier、checkpoint 或 merge 算法 |

# 3. 已有基础设施与最小改造

## 3.1 已有基础设施

| 能力 | 现有入口 | 复用方式 |
|---|---|---|
| Repo/worktree 解析 | `resolveRepositories` | active repo、trunk、KB id 与 worktree 路径唯一来源 |
| 本地 workspace 分类 | `classifyRepoWorkspace(ctx, repo, cr)` | build/verify 每仓先要求 `classification=healthy` |
| Phase authority | `resolveOperationalWorkspace(ctx, cr)` | `workspace inspect` 直接暴露其 `path`，不建新 resolver |
| release snapshot | `buildReleaseSubjects` / `verifyReleaseSubjects` / v1 renderer | 保留签名与 schema，只移除远端依赖 |
| checkpoint | `checkpointCr` | requirement ref 发布与跨环境交接唯一入口 |
| merge saga | `mergeCr` + `prepareMergeTree` + `classifyRemoteCommit` | preflight 后继续原 prepare/publish/rebuild/finalize |
| Durable transaction | `loadOrCreateJournal`、lock、write-set、fault recovery | 不新增 payload 字段或第二事务层 |
| Freshness | `classifyWorkspaceFreshness` / `syncWorkspaceToTrunk` | 保持远端 trunk 预检职责和既有节点位置 |
| 审批 | `cmdApprove` / `approveAndAdvance` | 只改共享 affirmative 判断与 prompt |
| 测试 fixture | `crctl.test.mjs`、`merge-tx.test.mjs`、`checkpoint-tx.test.mjs`、`pipeline-structure.test.mjs` | 扩现有 fixture，不建新框架 |

## 3.2 最小改造

1. 在 `workspace-transactions.mjs` 内收窄 build/verify 的事实来源，并在现有 `mergeCr` 内增加一次全仓 publication preflight。
2. 在 `crctl.mjs#cmdWorkspace` 的 inspect 返回中复用 `resolveOperationalWorkspace` 增加 `operationalWorkspace`；不改变 `ensureWorkspace` 的接口。
3. 在 `crctl.mjs#cmdApprove` 一处把 affirmative 判断改为 `['y', 'yes'].includes(...)`。
4. 调整三条现有 Pipeline 的 workspace 传递与审批后 checkpoint；同步 `_index.yml`。
5. 更新直接消费这些合同的既有 Skill 和人读文档。

# 4. 架构与数据流

## 4.1 本地评审与审批路径

```text
review-record --stage code
  -> resolveRepositories
  -> buildReleaseSubjects
      -> classifyRepoWorkspace(each active repo) == healthy
      -> local worktree HEAD
      -> local controlled artifact digest
      -> release-subjects v1
  -> review-annotations/code.yml

approve --stage code
  -> verifyReleaseSubjects
      -> local classifier + HEAD + artifact only
  -> approval.yml#code.release-subjects
  -> approval + status existing atomic commit
```

该路径不 fetch、不读取 remote-tracking ref，不判断 origin 是否存在。

## 4.2 Checkpoint 与 merge 发布路径

```text
checkpoint
  -> existing source commit / lease publish / KB metadata / remote confirmation

merge
  -> local signed snapshot verification
  -> publication preflight for all active repos
      -> fetch origin
      -> freeze localHead / remoteSourceSha / trunkSha in memory
      -> all remoteSourceSha == localHead
  -> existing prepare / publish / rebuild / finalize saga
```

publication preflight 失败只表示未发布，状态保持 `code-approved`；本地 verifier 失败才按既有 drift kind 回修或阻断。

## 4.3 Pipeline workspace 传递

```text
requirement: register.knowledgeBaseWorktree -> operational_workspace
architecture/code entry:
  crctl workspace inspect CR-ID
    -> resolveOperationalWorkspace.path
    -> operationalWorkspace
subsequent nodes:
  pass same operational_workspace unchanged
```

完整 repo map 仍只由每次 `crctl` 深原语内部的 `resolveRepositories` 解析。

# 5. 数据模型

## 5.1 持久化模型

无新增持久化模型。以下结构保持不变：

- release-subjects v1；
- approval.yml 各 section；
- review annotation；
- latest-checkpoint；
- merge journal `payload.repos[]` 的 `baseSha/sourceSha/mergeSha/pushed/confirmed`；
- 状态机与 gates。

## 5.2 仅内存 publication facts

`mergeCr` 新事务在首次 prepare 前构造局部数组，不写入 journal：

```js
publicationFacts = [{
  repo,             // repo.id
  localHead,        // 当前本地 CR worktree HEAD
  remoteSourceSha,  // fetch 后 origin/requirement/{CR-ID}
  trunkSha,         // fetch 后 origin/{trunk}
}]
```

约束：

1. 按 `ctx.repositories` 稳定顺序收集。
2. 任一事实不可读时立即硬失败。
3. 数组全部验证通过后才进入首次 prepare。
4. 首次 prepare 将 `remoteSourceSha` 复制到既有 `payload.repos[].sourceSha`；之后恢复只使用 journal 已持久化的 `sourceSha`，不新增 publication 字段。

# 6. 接口契约

## 6.1 `buildReleaseSubjects(ctx, cr)`

输入和 v1 输出不变。

逐仓算法：

1. `info = classifyRepoWorkspace(ctx, repo, cr)`。
2. `info.classification !== 'healthy'` 时抛结构化 `RELEASE_WORKSPACE_INVALID`，附 `repo/classification/worktreePath/branch/dirty`；不得降级为空仓或跳过。
3. 从 `info.worktreePath` 执行 `rev-parse HEAD` 得到 `reviewedSourceSha`。
4. `remoteRef` 继续渲染 `refs/heads/requirement/{CR-ID}`。
5. 不执行 remote get-url、fetch 或 remote ref 验证。
6. artifact 收集与 canonical digest 保持现有实现。

## 6.2 `verifyReleaseSubjects(ctx, cr, snapshot)`

返回合同继续为 `{ok:true}` 或 `{ok:false, kind:'code'|'task'|'prd'|'sdd', details}`。

校验顺序（失败 kind 优先级服从 PRD §7：受控 artifact 漂移先给精确 kind，不被 kind=code 覆盖）：

1. snapshot v1 形状与 active repo 集合。
2. 受控 artifact 逐文件哈希、集合与 digest（prd/sdd/task 精确 kind，含未提交篡改；PRD/SDD 漂移无条件硬阻断）。
3. 每仓 `classifyRepoWorkspace(...).classification === 'healthy'`；非 healthy 返回 kind=code（workspace-invalid）。
4. non-KB：当前 HEAD 精确等于 reviewed SHA。
5. KB：reviewed SHA 是当前 HEAD 祖先；区间变更只允许：
   - `change-requests/{CR-ID}/approval.yml`
   - `change-requests/{CR-ID}/cr.md`
   - `change-requests/{CR-ID}/traceability.yml`
   - `change-requests/{CR-ID}/review-loop.yml`
   - `change-requests/_backlog.yml`
   - `change-requests/{CR-ID}/review-annotations/` 前缀
删除 remote get-url、remote ref 读取与 `remote-ref-drift` 返回分支。白名单保留为现有函数内局部 `Set` + prefix，不抽配置或 helper。

## 6.3 `mergeCr(ctx, input)`

公开输入输出不变。

### 所有 merge 调用的共同前置

无论 `payload.repos` 是否为空，每次调用都必须先：

1. 读取 `approval.yml#code.release-subjects` 并执行纯本地 `verifyReleaseSubjects`。
2. PRD/SDD drift 始终返回 `APPROVED_ARTIFACT_DRIFT`。
3. code/TASK drift 且 `payload.repos` 中尚无 pushed 仓时返回既有 `release-drift`；已有任一 pushed 仓时返回 `RELEASE_SUBJECT_DRIFT` 并保持 blocked。
4. 只有本地 verifier 通过后，才进入下述 publication preflight 或 journal 续跑分支。

此共同前置保证已有 prepared/published journal 的续跑同样受本地 signed snapshot 约束；publication preflight 的有无不改变本地证据门禁。

### 新事务 / 零 prepare journal

当 `payload.repos.length === 0` 时才执行 publication preflight。函数内构造两个不同的恢复命令：

```js
const mergeRecoverCommand = `crctl merge ${cr} --workspace ${JSON.stringify(input.workspace || ctx.installRoot)}`;
const checkpointRecoverCommand = `crctl checkpoint ${cr} --workspace ${JSON.stringify(ctx.installRoot)}`;
```

随后：

1. 对全部 active repo fetch origin，读取本地 CR worktree HEAD、remote requirement source 和 trunk SHA。
2. source ref 缺失：抛 `MERGE_SOURCE_MISSING`，payload 附 `repo/ref/recoverCommand: checkpointRecoverCommand`。
3. `remoteSourceSha !== localHead`：抛 `RELEASE_REMOTE_NOT_PUSHED`，payload 附 `repo/head/remote/recoverCommand: checkpointRecoverCommand`。
4. 任一失败时 `payload.repos` 保持空，不调用 `prepareMergeTree` 或 `commit-tree`。
5. 全仓通过后，用同一批 facts 逐仓首次 prepare；`sourceSha=remoteSourceSha`，`baseSha=trunkSha`。

`mergeRecoverCommand` 继续只用于 prepare/publish/finalize、journal 或 lease 等 merge saga 技术失败；publication lag 不得返回它。

### 已有 prepare/publish journal

当 `payload.repos.length > 0` 且共同本地 verifier 已通过时，按既有 journal 恢复合同继续：

- 不清空或重建既有事务事实；
- 已 pushed/confirmed 仓不重做 prepare；
- trunk 前进仍走现有 rebuild；
- rebuild 使用 `rec.sourceSha` 作为冻结 source，不重新采纳移动的 requirement ref；
- journal 声称已发布但远端事实不符仍按既有 history-rewritten 硬阻断；
- 任一 trunk publish 后的本地 signed snapshot drift 保持 blocked。

### 错误到状态的映射

| 结果 | 状态动作 | 恢复 |
|---|---|---|
| local code/TASK drift，零 publish | 既有 `release-drift` 回退 developing | 重建测试/评审/审批 |
| PRD/SDD drift | 保持并硬阻断 | 回上游审批链 |
| remote source missing/stale | 保持 `code-approved` | checkpoint 后重跑 merge |
| remote advanced/diverged/history-rewritten | 保持当前状态 | 由 checkpoint 既有分类给出 pull/manual |
| 任一 publish 后 source drift | 保持 blocked | 恢复原 ref 后续跑原事务；新改动拆新 CR |

## 6.4 `workspace inspect`

`ensureWorkspace(ctx, {mode:'inspect'})` 继续返回 `{resources, changed:false}`，不修改 lib 合同。`cmdWorkspace` 在 `sub==='inspect'` 时额外调用：

```js
const authority = resolveOperationalWorkspace(ctx, cr);
return ok({
  op: 'workspace-inspect',
  cr,
  mode: 'inspect',
  ...result,
  operationalWorkspace: authority.path,
});
```

resolver 抛出的 missing/inconsistent 错误转为 `operationalWorkspace: null` + `operationalWorkspaceError: {code, message}` 结构化字段（inspect 本身保持只读诊断，不命令级失败）；调用方（Pipeline 入口）见 null/非 healthy 必须中止并指向 resume，不 fallback 到 `resources[]`、主 checkout 或目录猜测。

## 6.5 `cmdApprove`

仅修改共享 TTY prompt 和一行判断：

```js
rl.question(`以 approver=${approver} 批准该阶段？只有输入 y 或 yes 才会写入 approval.yml [y/N] `, async (answer) => {
  if (!['y', 'yes'].includes(answer.trim().toLowerCase())) {
    // existing reject rollback
  }
});
```

不新增 helper。TTY 检查、passCondition、evidence digest、reject rollback、grant、resign 和 `approveAndAdvance` 调用位置不变。

# 7. Pipeline 与 Skill 设计

## 7.1 requirement-authoring

- 保留 PRD 草稿 checkpoint 及 `auto_push_after_prd` 可选输入。
- 在 `approve-requirement` 后新增一个强制 `push-progress` 节点，message=`需求审批结果`，`onFail=abort`。
- 节点总数 6 -> 7，并同步 `_index.yml`。
- 阶段终点 checkpoint 失败保持 `requirement-approved`；重跑同一 checkpoint，不重新审批。

## 7.2 architecture-design

- 首节点先调用 `workspace inspect`，要求所有 `resources[].classification=healthy`，再消费 `operationalWorkspace` 并传给后续节点；任一资源非 healthy 时中止并指向 resume，不自动 ensure。
- 删除 `auto_push_after_sdd` 输入和 skip 分支。
- 保留现有审批后 `push-progress` 节点，改为无条件执行且 `onFail=abort`。
- 节点总数仍为 5。

## 7.3 code-implementation

- 首节点先调用 `workspace inspect`，要求所有 `resources[].classification=healthy`，再消费并传递 `operationalWorkspace`；任一资源非 healthy 时中止并指向 resume，后续文档节点不从目录命名猜路径。
- TASK checkpoint 保持可选。
- 代码/测试统一 checkpoint、评审 PASS 后审批前 checkpoint 保持强制。
- 审批后 checkpoint 的 `onFail` 从 `skip` 改为 `abort`。
- freshness 两个节点的位置和算法不变。
- 节点总数维持 trunk 基线 16（CR-2026-042 已删除评审 LLM 选择节点 17→16；本 CR 只改审批后 checkpoint `onFail`，不增删节点）。

## 7.4 Skill 文本

只更新直接消费者：

- `review-code`：snapshot 来自 healthy committed 本地 worktree，不要求远端已同步。
- 四个 `approve-*`：TTY 提示接受 `y|yes`，不自行读 stdin；checkpoint 不进入审批事务。
- `crctl` Skill：同步 local evidence/publication boundary 与 inspect 输出。
- `push-progress`：按 Pipeline 位置区分可选草稿和强制阶段交接。
- `workspace-freshness`：明确只负责 origin trunk 新鲜度，失败零业务状态副作用。
- `merge-feature-branch`：publication lag 保持 `code-approved` 并指向 checkpoint。

# 8. FR 到技术实现映射

| PRD FR | 技术落点 | 验证 |
|---|---|---|
| FR-01 | build/verify 移除 remote；Pipeline 传 operational workspace | 离线与静态调用测试 |
| FR-02 | `buildReleaseSubjects` + classifier | healthy/dirty/missing 测试 |
| FR-03 | `verifyReleaseSubjects` + 精确 KB 白名单 | HEAD/artifact/白名单参数化测试 |
| FR-04 | `approveAndAdvance(code)` 保持接口，消费本地 verifier | remote stale approve 测试 |
| FR-05 | `mergeCr` 零 prepare preflight + 既有 saga | remote missing/stale、checkpoint 后重跑、partial publish 测试 |
| FR-06 | `cmdWorkspace inspect` 暴露 authority path；Pipeline 原样传递 | resolver 与结构测试 |
| FR-07 | 三条 Pipeline 审批后 checkpoint | pipeline structure 测试 |
| FR-08 | freshness 实现不改，只更新职责文本与回归 | freshness 零状态副作用回归 |
| FR-09 | `cmdApprove` 一行判断与 prompt | 四 stage TTY 参数化测试 |
| FR-10 | 既有文件内最小修改；契约 lint | prompt/matrix/pipeline lint |
| FR-11 | `upgrade-check` 只读；在途状态说明与 journal 版本边界 | 兼容矩阵测试/文档断言 |

FR 覆盖率：11/11。

# 9. 安全、性能与一致性

## 9.1 安全

- local verifier 对非 healthy workspace fail closed。
- publication preflight 全仓通过前不产生 candidate。
- remote lag 不写 review/approval/traceability，也不触发业务回退。
- TTY 扩展不改变非 TTY 硬拒、grant 验签与 reject 权威回退。
- 不接受调用方任意 repo、path、ref、SHA 或 refspec。

## 9.2 性能

- status/gate/review/approve 删除 fetch，减少网络调用。
- merge 仍每仓一次必要 fetch；preflight 读取结果直接供首次 prepare 使用，不做第二轮 source fetch。
- 不增加缓存、watcher、后台任务或 commit count 计算。

## 9.3 一致性

- 本地 snapshot 绑定 worktree HEAD 与 artifact digest。
- publication preflight 绑定当前 local HEAD 与 remote source exact equality。
- 首次 prepare 后 source SHA 进入既有 journal，恢复不采纳移动 ref。
- repository graph digest、lease 与 journal 约束保持现有实现。

# 10. 测试设计

只扩现有测试文件。

## 10.1 `crctl.test.mjs`

1. origin 不存在/不可达时，healthy committed worktree 可 build snapshot。
2. dirty/wrong-branch/missing/path-unregistered 零 snapshot 失败。
3. remote requirement stale 但 local 未漂移时 verifier 与 approve-code 通过。
4. non-KB HEAD 漂移失败。
5. KB 白名单六类逐项通过，白名单外路径逐项失败。
6. plan/TASK/_index 集合或 digest 漂移失败；CRLF/LF 等价。
7. `workspace inspect` 返回 resolver 的 `operationalWorkspace`，missing/inconsistent 不猜路径。
8. 四个 stage 参数化验证 `y/Y/yes/YES/YeS` 与空白输入批准。
9. 空输入、no/其他输入继续 reject 回退；非 TTY、grant、resign 回归不变。

## 10.2 `merge-tx.test.mjs`

1. 任一 repo remote source missing：全仓 `payload.repos=[]`、无 candidate、状态 `code-approved`。
2. 任一 repo remote source stale：同上，错误为 `RELEASE_REMOTE_NOT_PUSHED`；两类 publication lag 的 `recoverCommand` 均精确等于 checkpoint 命令，不得等于 merge 命令。
3. checkpoint 后重跑进入 prepare/publish/finalize。
4. 本地 code/TASK drift 零 publish 仍 release-drift；PRD/SDD 漂移硬阻断。
5. 已有 prepared journal 续跑前仍执行本地 verifier；零 publish drift 回退，已有 publish drift 保持 blocked。
6. 已有 prepare/publish journal 按原合同恢复；trunk rebuild 使用冻结 `sourceSha`。
7. merge saga 自身的 prepare/publish/finalize/lease 故障继续返回 merge recoverCommand。

## 10.3 `checkpoint-tx.test.mjs`

保持并重跑 remote advanced/diverged/history-rewritten、lease、metadata commit 与幂等恢复测试；merge 不复制这些分类。

## 10.4 `pipeline-structure.test.mjs`

1. requirement 审批后强制 checkpoint，节点数 7；草稿 checkpoint 仍可选。
2. architecture 无 `auto_push_after_sdd`，审批后 checkpoint `onFail=abort`，节点数 5。
3. code 审批后 checkpoint `onFail=abort`，TASK checkpoint 仍可选，节点数维持 trunk 基线 16（CR-2026-042 已删评审 LLM 选择节点）。
4. architecture/code 首节点要求全部 `resources[].classification=healthy`，取得并后续传递 `operationalWorkspace`；非 healthy 时 abort 并指向 resume。
5. Pipeline 不含 fetch、SHA、Git、CAS、journal 算法文本。

## 10.5 回归命令

```text
node --test skills/shared/crctl/scripts/test/crctl.test.mjs
node --test skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs
node --test skills/shared/crctl/scripts/test/merge-tx.test.mjs
node --test skills/shared/crctl/scripts/test/writeback-tx.test.mjs
node --test skills/shared/crctl/scripts/test/archive-tx.test.mjs
node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
node skills/shared/crctl/scripts/check-agents-contract.mjs
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node skills/shared/crctl/scripts/lint-prompts.mjs
```

# 11. 兼容、启用与回滚

1. release-subjects v1 与账本 schema 不迁移。
2. `developing` 及更早 CR 直接采用新本地 verifier。
3. `code-reviewing` 重跑 review-code 生成当前本地 snapshot。
4. `code-approved` 且 snapshot 与本地一致时，先 checkpoint 再 merge，不重新审批。
5. 已有 candidate 或 trunk publish 的 merge 事务使用启动版本按原 journal 完成；不跨版本切换。
6. 启用前复用现有 `upgrade-check` 只读确认，无新 CLI。
7. TTY 变更可独立回滚；Pipeline/Skill/README 可独立回滚且无数据迁移。
8. local verifier/merge 分类回滚会恢复旧远端依赖，但不会产生 schema 不兼容。

# 12. Prompt 采纳影响

本 CR 不新增 crctl dispatch 分支，也不修改 `rules.json#protectedPaths.deny`，因此不触发强制的“新增命令采纳”场景。但既有命令合同发生收敛，以下 Skill 必须同步：

| Skill | 当前描述 | 应改为 |
|---|---|---|
| `skills/develop/review-code/SKILL.md` | code snapshot 依赖已推送 source | healthy committed 本地 source；发布由 checkpoint/merge 处理 |
| 四个 `approve-*` | TTY 仅 `yes` 或未统一说明 | 共享入口接受 `y|yes`，Skill 不解析 stdin |
| `skills/shared/crctl/SKILL.md` | verifier 混合本地/远端 | 本地证据与 publication 边界分离；inspect 返回 authority path |
| `skills/sync/push-progress/SKILL.md` | checkpoint 普遍可选 | 草稿可选、阶段终点强制，取决于 Pipeline 位置 |
| `skills/sync/workspace-freshness/SKILL.md` | 易被理解为通用 gate | 仅远端 trunk 新鲜度预检，失败零业务证据变化 |
| `skills/writeback/merge-feature-branch/SKILL.md` | remote drift 可进入 release drift | publication lag 保持状态并指向 checkpoint |

# 13. 技术选型与替代方案

| 方案 | 结论 | 原因 |
|---|---|---|
| release-subjects v2 增加 published SHA | 否决 | 本地与发布事实可由现有 snapshot + checkpoint/merge 分层表达，无需迁移 schema |
| 新 publication registry/账本 | 否决 | checkpoint 与 merge journal 已拥有发布事实 |
| approve 内原子 push | 否决 | 把网络事务并入人工审批，扩大失败与恢复边界 |
| merge 自动 checkpoint | 否决 | 隐藏发布动作并复制 checkpoint 分类 |
| 为 affirmative 新建 helper/依赖 | 否决 | 一行数组 includes 足够 |
| 修改 `ensureWorkspace` 返回 authority | 否决 | inspect 命令层复用 resolver 即可，避免污染 workspace 生命周期接口 |

# 14. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-16 | v0.2.0 | Ray | 回修 B-01/B-02：本地 verifier 提升为所有 merge 调用共同前置；区分 checkpoint 与 merge recoverCommand；补充非 healthy workspace 入口阻断 |
| 2026-08-16 | v0.1.0 | Ray | 初始设计：本地 release verifier、merge publication preflight、Operational Workspace 连续性、阶段终点 checkpoint 与共享 TTY `y|yes` |

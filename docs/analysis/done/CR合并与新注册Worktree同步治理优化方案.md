# CR 合并与新注册 Worktree 同步治理优化方案

> 文档性质：平台级流程优化方案与过度设计审查结论。
>
> 适用范围：通过 `crctl` 管理的 knowledge-base、`multica`、`tools` 等参与仓。
>
> 核对基线：当前 Tools Root 的 `crctl`、`dir-graph.yaml#repositories`、相关 Skill/Pipeline，以及 CR-2026-031/043/044 已建立的事务与 workspace 约束。
>
> 目标：在不复制现有事务基础设施的前提下，修复新 CR 初始基点和 merge 后本地主 checkout 不跟随远端两个缺口。

## 1. 决策摘要

保留当前“远端权威、事务 workspace 生成提交、lease push 发布”的合并模型，只做两项最小改造：

1. **新注册 CR 从远端 trunk 创建分支**：`ensureRepoWorkspace` 遇到 `missing` 时先 fetch 并重新分类；远端没有同名 CR 分支时，从 `origin/{trunk}` 创建 `requirement/{CR-ID}`，不再从可能落后的本地 trunk 创建。
2. **merge 完成后 best-effort 快进本地主 checkout**：远端 merge/finalize 已确认后，仅对 `dir-graph.yaml#repositories[].path` 指向的主 checkout 做一次安全检查；当前分支正确、工作区干净且 local HEAD 是 remote HEAD 的祖先时，执行 `git merge --ff-only <remote-sha>`。

目标流程：

```text
注册：missing workspace
  -> fetch origin
  -> 重新分类
  -> 有远端 CR 分支：恢复远端 CR 分支
  -> 无远端 CR 分支：从 origin/{trunk} 创建

合并：现有远端事务模型不变
  -> publication preflight
  -> prepare merge commit
  -> lease publish
  -> remote confirmation
  -> Transaction Workspace finalize
  -> best-effort 同步本地主 checkout
```

本次不增加 Pipeline 节点、Skill Git 算法、register journal 字段、第二套事务框架或历史 CR 迁移流程。

## 2. 现状：已解决的基础设施与剩余缺口

### 2.1 已经解决的基础设施

以下能力已经存在，本次直接复用，不重新设计：

| 已有能力 | 当前权威位置 | 本次处理 |
|---|---|---|
| 参与仓与 trunk 解析 | 工作区 `dir-graph.yaml#repositories` | 直接复用 |
| CR 注册账本 CAS、提交、lease push 与恢复 | `crctl register` + register journal | 保持不变 |
| workspace 七分类与安全补齐 | `classifyRepoWorkspace` / `ensureRepoWorkspace` | 只修正 `missing` 的远端基点选择 |
| 既有 CR 相对远端 trunk 的 freshness 分类与 ff-only 同步 | `crctl workspace freshness/sync` | 继续服务既有 CR，不扩展职责 |
| 跨仓 merge prepare、journal、lease publish、remote confirmation | `crctl merge` | 保持不变 |
| merge 后的唯一业务编辑位置 | detached Transaction Workspace | 保持不变 |
| 状态、门禁、账本、审计与原子提交 | `crctl` | 不新增旁路 |

这些能力已经覆盖跨仓发布一致性、并发推进、部分发布恢复、状态推进和账本原子性。本次没有理由再增加 WAL、补偿事务、持久化 reconciliation intent 或新的状态机。

### 2.2 剩余缺口 A：新 CR 仍可能继承 stale local trunk

当前 `ensureRepoWorkspace` 在 workspace 为 `missing` 且本机未看到远端 CR tracking ref 时，执行等价于：

```text
git branch requirement/{CR-ID} {repo.trunk}
```

这里的 `{repo.trunk}` 是本地 branch。即使远端 trunk 已前进，新 CR 仍可能从落后的本地 `main` / `custom/main` 创建。

此外，首次分类发生在 fetch 之前。本机 remote-tracking ref 过期时，远端实际存在的 `origin/requirement/{CR-ID}` 也可能未被识别。

### 2.3 剩余缺口 B：远端 merge 不移动本地主 checkout

当前 `crctl merge`：

1. 在本机 object database 中生成候选 merge commit；
2. 将候选提交 lease push 到远端 trunk；
3. 确认远端结果；
4. 在 detached Transaction Workspace 中完成 finalize。

它不会 checkout 或移动用户主 checkout 的本地 trunk。这是正确的发布安全边界，但会让 clean 的本地 `main` / `custom/main` 在 merge 后继续落后。

### 2.4 两个缺口不能混成一套新事务

- 缺口 A 是**创建新 CR 时选错基点**，属于 workspace ensure 的 Git 决策。
- 缺口 B 是**远端发布后的本地体验补偿**，不属于业务状态或远端发布事务。

修复 A 不需要修改 merge；修复 B 不应回滚或阻断已经成功的远端 merge。

## 3. 模块职责边界

| 模块 | 应该拥有 | 本次不得增加 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 本地 trunk 同步节点、复制 Skill/crctl 算法、手写账本操作 |
| Skill | 业务前置判断、调用步骤、输入输出、失败语义 | Git 分支算法、原子账本逻辑、重复实现 crctl |
| `crctl` | 状态、门禁、CAS、受控账本写入、审计、Git 深原语、原子提交 | 业务设计判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性内容转换 | 状态推进、人工审批、本地 trunk 治理 |
| README | 面向人的流程总览 | 另一份可执行步骤或状态事实源 |

因此，两项修改都收敛在现有 `crctl` 的 `workspace-transactions.mjs`：

- `ensureRepoWorkspace` 修正新分支基点；
- merge finalize 后调用一个私有、非事务化的本地主 checkout reconciliation helper。

Skill 继续只调用一次深原语，Pipeline 与 README 无需增加可执行细节。

## 4. 最小改造一：新注册从远端 trunk 创建

### 4.1 目标行为

`ensureRepoWorkspace` 首次分类后按以下规则处理：

| 初始分类 | 行为 |
|---|---|
| `healthy` | 直接复用，不 fetch、不移动 |
| `branch-only` | 挂接已有本地 CR 分支，不改基点 |
| `remote-only` | 按现有逻辑从远端 CR 分支创建 tracking branch/worktree |
| `dirty` / `wrong-branch` / `path-unregistered` | 按现有逻辑硬阻断，不 reset、stash 或删除 |
| `missing` | fetch origin，重新分类后再决定创建来源 |

`missing` 的完整流程：

```text
初次 classify = missing
  -> git fetch origin
  -> 再次 classify
     -> remote-only：从 origin/requirement/{CR-ID} 恢复
     -> 仍为 missing：确认 refs/remotes/origin/{trunk} 存在
                       从该远端 trunk ref 创建本地 CR branch
                       创建 worktree
     -> 其他分类：按重新分类后的既有保护规则处理
```

目标 Git 语义：

```text
git branch requirement/{CR-ID} origin/{trunk}
```

不再执行：

```text
git branch requirement/{CR-ID} {local-trunk}
```

### 4.2 失败语义

- fetch 失败或 `origin/{trunk}` 不可解析：返回结构化 `WORKSPACE_TRUNK_UNAVAILABLE`，不创建本地 CR branch/worktree；
- fetch 后发现远端 CR 分支：优先恢复远端 CR 分支，不另建新历史；
- 不允许离线模式或静默回退本地 trunk；
- 已有本地 branch/worktree 不因本次修改被 reset、rebase、stash 或重建。

### 4.3 为什么不扩展 register journal

无需记录每仓 `base-sha`、`source`、`action` 或 `worktree-path`：

1. 现有 register journal 已用 `worktrees[]` 记录逐仓完成进度；
2. 本地 `requirement/{CR-ID}` ref 一旦创建，本身就是基点的 Git 权威事实；
3. 若在 branch 创建后、worktree 创建前中断，重跑会分类为 `branch-only` 并挂接同一分支；
4. 若在 branch 创建前中断，重跑时重新 fetch 最新远端 trunk 是合理行为，不需要冻结旧观察值；
5. 跨仓并不存在必须共享的同一个 SHA，额外 journal 只会复制 Git 已保存的事实。

## 5. 最小改造二：merge 后 best-effort 同步本地主 checkout

### 5.1 边界

本地同步只处理每个参与仓的 `repo.rootPath`，即 `dir-graph.yaml#repositories[].path` 声明的主 checkout。

明确不做：

- 不遍历 `git worktree list` 寻找其他 trunk checkout；
- 不自动 checkout trunk；
- 不 stash、reset、rebase 或普通 merge；
- 不修改 CR worktree；
- 不写业务账本或 CR status；
- 不进入 merge journal，不提供本地同步事务恢复；
- 不因本地同步失败回滚远端发布。

### 5.2 安全判据

远端 merge/finalize 已确认后，每仓依次执行：

```text
1. 读取 repo.rootPath 当前 branch
2. branch != repo.trunk                    -> skipped / wrong-branch
3. git status --porcelain 非空             -> skipped / dirty
4. fetch origin 失败                       -> failed / fetch-failed
5. origin/{trunk} 不可解析                 -> failed / trunk-unavailable
6. local HEAD == remote HEAD               -> unchanged
7. local HEAD 不是 remote HEAD 的祖先      -> skipped / diverged
8. git merge --ff-only <remote SHA> 成功    -> synced
9. ff-only 执行失败                        -> failed / ff-only-failed
```

使用捕获的 remote SHA，而不是在检查后再次解析移动 ref：

```text
git merge --ff-only <captured-origin-trunk-sha>
```

Git 的 ancestry 与 `--ff-only` 是最终安全判据，不新增自定义合并算法。

### 5.3 输出契约

`crctl merge` 保持：

```json
{
  "phase": "complete",
  "changed": true,
  "localTrunkSync": []
}
```

每仓结果采用四态模型：

```json
{
  "repo": "multica",
  "trunk": "main",
  "before": "<local-sha>",
  "remote": "<origin-sha-or-null>",
  "after": "<result-sha>",
  "status": "synced | unchanged | skipped | failed",
  "reason": "dirty | wrong-branch | diverged | fetch-failed | trunk-unavailable | ff-only-failed | null"
}
```

`status` 只表达结果，`reason` 表达原因；不扩展为 `skipped-dirty`、`skipped-diverged`、`skipped-in-use` 等平行状态。

### 5.4 退出与恢复语义

- 远端 merge/finalize 已确认后，本地同步无论 `synced`、`skipped` 或 `failed`，`crctl merge` 都返回 exit 0、`phase=complete`；
- 本地同步结果是运营提示，不改变 `merging`、`writing-back` 或 `archived`；
- 如果进程在远端完成后、本地同步前退出，不为这项体验增强创建 journal；用户可直接使用原生 `git pull --ff-only`；
- 后续 writeback 仍只使用 Transaction Workspace，不依赖本地主 checkout 是否同步。

## 6. 明确删除的过度设计

### 6.1 删除分阶段诊断建设

不保留原 Phase 0/3/4：

- 不先建设一轮只读诊断再改行为；
- 不扩展 `crctl status`、`workspace inspect`、`resume` 或看板；
- 不扫描、批处理或迁移历史 CR；
- 不把 installation trunk 状态混入 CR workspace authority 视图。

两个缺口都有直接、可测试的局部修复，不需要先建立新的治理面。

### 6.2 删除 register workspace intent 账本

不增加每仓 `base-sha/source/action/worktree-path` journal。现有 Git ref 与 register `worktrees[]` 足以恢复。

### 6.3 删除本地同步事务

不为 best-effort ff-only 增加：

- durable journal；
- intent digest；
- recoverCommand；
- 跨仓补偿；
- 状态推进；
- 失败回滚。

远端发布事务已经完成，本地 checkout 同步不具备同等级原子性要求。

### 6.4 删除不必要的状态分类

不单列 `skipped-in-use`、`skipped-missing`、`history-rewritten` 等状态：

- 只处理声明的 `repo.rootPath`，无需搜索“被其他 worktree 占用”的 branch；
- repository root 缺失应由既有 repository resolution 失败处理；
- 对本地同步而言，互不为祖先统一归为 `skipped/diverged` 已足够；
- 具体 Git 技术失败统一使用 `failed + reason`。

## 7. 最小实施面

预计只涉及以下实现与测试位置；不修改 Agent、Pipeline、Skill、README、状态机或 gates：

| 位置 | 最小改动 |
|---|---|
| `../tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | `missing` 时 fetch + 重新分类 + 从 `origin/{trunk}` 建分支；增加私有 local trunk reconciliation helper，并在 merge complete 后调用 |
| `../tools/skills/shared/crctl/scripts/test/register-tx.test.mjs` | 增加远端基点、fetch 后发现远端 CR、远端不可用测试 |
| `../tools/skills/shared/crctl/scripts/test/merge-tx.test.mjs` | 增加 clean fast-forward 与不安全状态跳过测试 |

不新增文件、不新增依赖。继续使用 Node 标准库与原生 Git 命令。

## 8. 测试与验收

### 8.1 注册测试

1. **stale local trunk**：本地 trunk 落后 `origin/{trunk}` 时，新 CR branch HEAD 必须等于 fetch 后的远端 trunk SHA；
2. **远端 CR 分支延迟可见**：本机初始没有 remote-tracking ref，但远端已有 `requirement/{CR-ID}` 时，fetch 后必须恢复该分支；
3. **远端不可确认**：fetch 失败或远端 trunk 缺失时，返回结构化错误，且不创建本地 branch/worktree；
4. 现有 `healthy`、`branch-only`、`dirty`、`wrong-branch`、`path-unregistered` 保护测试继续通过。

### 8.2 merge 后本地同步测试

1. **clean + behind**：远端 merge 成功后，本地主 checkout ff-only 到远端 SHA，结果为 `synced`；
2. **already current**：结果为 `unchanged`，不生成额外提交；
3. **dirty / wrong-branch / diverged**：使用表驱动测试验证结果为 `skipped`、reason 正确、本地现场不变；
4. 所有 skipped 情况下，远端 merge 仍为成功，返回 `phase=complete`；
5. 现有 merge journal、lease publish、finalize、Transaction Workspace 与重入测试继续通过。

### 8.3 验收标准

```text
新 CR 初始基点来自 fetch 后的远端事实
远端已有 CR 分支时优先恢复，不创建平行历史
远端 trunk 不可确认时不回退本地 trunk
远端 merge/finalize 的现有事务语义不变
安全的本地主 checkout 自动 ff-only
不安全或失败的本地同步不破坏现场、不影响远端成功
无新增 Pipeline/Skill/账本/事务框架/依赖
```

## 9. 最终决策

本次治理采用“两处局部修复”，而不是“新建一套同步事务”：

1. `ensureRepoWorkspace` 在真正需要创建资源的 `missing` 状态刷新远端事实，并从远端 CR 分支或 `origin/{trunk}` 创建；
2. `crctl merge` 在远端事务完成后，对声明的本地主 checkout 做一次非事务化、受保护的 ff-only；
3. 现有 register/merge journal、workspace freshness、Transaction Workspace、状态机和账本能力全部复用；
4. 本地同步结果只作为 merge 输出，不扩散到 status、inspect、resume、README 或业务状态；
5. 既有 CR 不迁移，继续按现有 `workspace freshness/sync` 显式处理。

该方案解决两个真实缺口，同时保持模块职责单一、变更面最小，并避免重复建设事务、诊断和状态分类基础设施。

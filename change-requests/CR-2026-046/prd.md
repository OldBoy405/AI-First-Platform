---
id: CR-2026-046-prd
type: PRD
cr-ref: CR-2026-046
title: CR 合并与新注册 Worktree 同步治理优化方案
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: "2026-08-18T20:19:12+08:00"
updated: "2026-08-18T20:28:00+08:00"
---

# PRD — CR 合并与新注册 Worktree 同步治理优化方案

## 1. 概述

### 1.1 问题陈述

在现有 crctl 事务基础设施（远端权威、事务 workspace 生成提交、lease push 发布）上，存在两个独立缺口：

1. **缺口 A（注册基点陈旧）**：`ensureRepoWorkspace` 对 `missing` 分类直接执行 `git branch requirement/{CR-ID} {repo.trunk}`，`{repo.trunk}` 是本地 branch。即使远端 trunk 已前进，新 CR 仍可能从落后的本地 trunk 创建。且首次分类发生在 fetch 之前，本机 remote-tracking ref 过期时，远端已存在的 `origin/requirement/{CR-ID}` 不被识别。
2. **缺口 B（merge 后本地主 checkout 不跟随）**：`crctl merge` 在 detached Transaction Workspace 完成 finalize 后，不移动用户主 checkout（`dir-graph.yaml#repositories[].path`）的本地 trunk。这是正确的发布安全边界，但 clean 的本地 `main` / `custom/main` / `master` 会持续落后。

### 1.2 解决方案摘要

两处局部修复，不新建任何事务框架：

1. `ensureRepoWorkspace` 在 `missing` 分类下先 `git fetch origin` 并重新分类：有远端 CR 分支则恢复；仍 missing 则从 `origin/{trunk}` 创建本地 CR branch。
2. `crctl merge` 在远端事务完成后，对声明的主 checkout 执行一次私有、非事务化的 best-effort ff-only 同步。

实现选择遵循 ponytail 优先级（复用现有能力 > 标准库 > 原生 Git 命令 > 最小新增代码）：
- 复用 `classifyRepoWorkspace` 二次分类，不新写分类逻辑；
- 复用 CR-2026-043 `workspace sync` 已验证的 `git merge --ff-only <preflight 捕获 SHA>` 模式，不新增合并算法；
- 全程使用 Node 标准库与原生 Git 命令，不新增依赖、不新增文件。

### 1.3 已解决基础设施（本次直接复用，不重新设计）

| 已有能力 | 权威位置 | 本次处理 |
|---|---|---|
| 参与仓与 trunk 解析 | 工作区 `dir-graph.yaml#repositories` | 直接复用 |
| CR 注册账本 CAS、提交、lease push 与恢复 | `crctl register` + register journal | 保持不变 |
| workspace 七分类与安全补齐 | `classifyRepoWorkspace` / `ensureRepoWorkspace` | 只修正 `missing` 的基点选择 |
| 既有 CR freshness 分类与 ff-only 同步 | `crctl workspace freshness/sync` | 继续服务既有 CR，不扩展职责 |
| 跨仓 merge prepare、journal、lease publish、remote confirmation | `crctl merge` | 保持不变 |
| merge 后唯一业务编辑位置 | detached Transaction Workspace | 保持不变 |
| 状态、门禁、账本、审计与原子提交 | `crctl` | 不新增旁路 |

### 1.4 模块职责边界

| 模块 | 应该拥有 | 本次不得增加 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 本地 trunk 同步节点、复制 Skill/crctl 算法、手写账本操作 |
| Skill | 业务前置判断、调用步骤、输入输出、失败语义 | Git 分支算法、原子账本逻辑、重复实现 crctl |
| `crctl` | 状态、门禁、CAS、受控账本写入、审计、Git 深原语、原子提交 | 业务设计判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性内容转换 | 状态推进、人工审批、本地 trunk 治理 |
| README | 面向人的流程总览 | 另一份可执行步骤或状态事实源 |

两项修改均收敛在 `../tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs`。Skill 继续只调用一次深原语，Pipeline 与 README 无需增加可执行细节。

## 2. 用户故事

- **US-1**：作为 CR 注册用户，当我注册新 CR 时，即使本地 trunk 落后于远端，我希望新 CR 分支基于远端最新 trunk，以降低后续 merge 冲突面。
- **US-2**：作为续跑用户，当注册进程在分支创建后中断，我重跑注册时希望挂接同一分支，而不是另建一条平行历史。
- **US-3**：作为远端已存在 CR 分支的用户，当本机 remote-tracking ref 过期时，我重跑注册希望恢复远端分支，而不是基于 trunk 新建。
- **US-4**：作为 merge 完成后的开发用户，当我的本地主 checkout 处于 trunk 分支且 clean 时，我希望它自动 ff-only 到远端最新 trunk，无需手动 `git pull`。
- **US-5**：作为本地有未提交变更或分叉的用户，我希望本地同步静默跳过我的现场，绝不 stash/reset/rebase，且不影响已成功的远端 merge。
- **US-6**：作为 crctl 维护者，我希望本次改动不新增 Pipeline 节点、Skill、账本字段、事务框架或依赖，保持模块职责边界不变。

## 3. 功能需求

### 注册路径（缺口 A）

- **FR-1**：`ensureRepoWorkspace` 首次分类为 `missing` 时，必须先执行 `git fetch origin`（失败即终止，见 FR-4），然后调用既有 `classifyRepoWorkspace` 重新分类；`healthy` 与 `branch-only` 分类不得触发 fetch。
- **FR-2**：重新分类为 `remote-only` 时，按现有逻辑从 `origin/requirement/{CR-ID}` 恢复（`git branch --track` + worktree 挂接），不基于 trunk 新建平行历史。
- **FR-3**：重新分类仍为 `missing` 时，必须先解析 `refs/remotes/origin/{trunk}` 存在，然后执行 `git branch requirement/{CR-ID} origin/{trunk}`（即 refs/remotes/origin/{trunk} 指向的 SHA）并创建 worktree；禁止再执行 `git branch requirement/{CR-ID} {local-trunk}`。
- **FR-4**：fetch 失败或 `origin/{trunk}` 不可解析时，返回结构化错误 `WORKSPACE_TRUNK_UNAVAILABLE`；不得创建、修改或删除 `requirement/{CR-ID}` branch/worktree，`git fetch origin` 已产生的 `refs/remotes/origin/*` 更新可以保留；禁止静默回退本地 trunk 或离线模式。
- **FR-5**：重新分类为 `dirty` / `wrong-branch` / `path-unregistered` 时，按既有规则硬阻断，不 reset、stash 或删除任何已有资源。
- **FR-6**：register journal 结构保持不变：不新增 `base-sha`、`source`、`action`、`worktree-path` 字段（本地 `requirement/{CR-ID}` ref 已是基点权威事实；`worktrees[]` 已记录逐仓进度）。

### merge 路径（缺口 B）

- **FR-7**：远端 merge/finalize 确认后，对每个参与仓的 `repo.rootPath`（即 `dir-graph.yaml#repositories[].path` 主 checkout）调用一个私有、非事务化的 local trunk reconciliation helper；不遍历 `git worktree list` 寻找其他 checkout，不处理 CR worktree。
- **FR-8**：helper 每仓按序执行 8 个安全判据，任一不满足即结束该仓，禁止 fallback 到普通 merge/reset/stash：
  1. 读取 `repo.rootPath` 当前 branch；`branch != repo.trunk` → `skipped` / `wrong-branch`；
  2. `git status --porcelain` 非空 → `skipped` / `dirty`；
  3. `git fetch origin` 失败 → `failed` / `fetch-failed`；
  4. `origin/{trunk}` 不可解析 → `failed` / `trunk-unavailable`；
  5. local HEAD == remote HEAD → `unchanged`；
  6. local HEAD 不是 remote HEAD 的祖先 → `skipped` / `diverged`；
  7. `git merge --ff-only <捕获的 remote SHA>` 成功 → `synced`（必须使用步骤 3/4 捕获的 SHA，禁止再次解析移动 ref）；
  8. `git merge --ff-only` 执行失败 → `failed` / `ff-only-failed`。
- **FR-9**：`crctl merge` 成功输出在现有契约上增加 `localTrunkSync: []` 数组；每仓条目四态模型：
  `{ repo, trunk, before, remote, after, status: synced|unchanged|skipped|failed, reason: dirty|wrong-branch|diverged|fetch-failed|trunk-unavailable|ff-only-failed|null }`。
  字段规则固定为：`before` 是进入 helper 时可解析的本地 HEAD，否则为 `null`；`remote` 是 fetch 成功后捕获的 `origin/{trunk}` SHA，否则为 `null`；`after` 是 helper 返回时可解析的本地 HEAD，否则为 `null`。因此 wrong-branch/dirty 在 fetch 前结束时 `remote=null`，fetch-failed 时 `remote=null`，trunk-unavailable 时 `remote=null`，ff-only-failed 时 `remote` 为已捕获 SHA 且 `after` 反映命令失败后的实际 HEAD。
  只表达结果与原因，不扩展为 `skipped-dirty` 等平行状态。
- **FR-10**：远端 merge/finalize 已确认后，无论本地同步结果为 `synced` / `skipped` / `failed`，`crctl merge` 均返回 exit 0、`phase=complete`；本地同步结果不写 merge journal、不写业务账本、不改变 CR status（`merging` / `writing-back` / `archived` 语义不变）、不提供恢复流程（进程中断即不补偿，用户可原生 `git pull --ff-only`）。
- **FR-11**：后续 writeback 仍只使用 detached Transaction Workspace，不依赖本地主 checkout 同步状态。

## 4. 非功能需求

- **NFR-1（安全）**：对已有本地 branch/worktree 与主 checkout 现场零破坏：全程无 `reset`、`stash`、`rebase`、普通 `merge`、强制 checkout 或分支删除。允许的 Git 写入仅包括注册路径中 `fetch` 对 remote-tracking refs 的更新、新建 CR branch/worktree，以及本地同步路径的 `git merge --ff-only <捕获 SHA>`；不得借此引入回滚或补偿事务。
- **NFR-2（幂等）**：branch 创建后、worktree 创建前中断，重跑注册分类为 `branch-only` 并挂接同一分支；branch 创建前中断，重跑重新 fetch 最新远端事实（不冻结旧观察值）。本地同步 helper 重入安全：`unchanged` 分支保证重复执行不产生额外提交。
- **NFR-3（兼容）**：现有 register journal / merge journal / lease publish / finalize / Transaction Workspace / 状态机 / gates 行为不变；`register-tx.test.mjs`、`merge-tx.test.mjs` 既有测试全部继续通过。
- **NFR-4（最小面）**：不新增文件、不新增依赖（仅 Node 标准库 + 原生 Git 命令）、不修改 Agent / Pipeline / Skill / README / 状态机 / gates；实现收敛于 `workspace-transactions.mjs` 与两个测试文件。
- **NFR-5（审计）**：`localTrunkSync` 是本地同步的唯一观察面；不向 `crctl status` / `workspace inspect` / `resume` / 看板扩散新视图。

## 5. 验收标准

- **AC-1（对应 FR-1/3）**：本地 trunk 落后 `origin/{trunk}` 时注册新 CR，CR branch HEAD 等于 fetch 后的远端 trunk SHA。
- **AC-2（对应 FR-2）**：本机初始无 `refs/remotes/origin/requirement/{CR-ID}` 但远端已存在该分支时，fetch 重新分类后恢复远端 CR 分支，不新建历史。
- **AC-3（对应 FR-4）**：fetch 失败或 `origin/{trunk}` 缺失时，返回 `WORKSPACE_TRUNK_UNAVAILABLE`，且不创建、修改或删除 `requirement/{CR-ID}` branch/worktree；测试允许并验证 fetch 已产生的 remote-tracking ref 更新不会被额外回滚，且不得回退到本地 trunk。
- **AC-4（对应 FR-5）**：`healthy`、`branch-only`、`dirty`、`wrong-branch`、`path-unregistered` 现有保护测试继续通过；`healthy`/`branch-only` 不产生 fetch。
- **AC-5（对应 FR-6）**：register journal 结构无新字段，既有 register journal 测试通过。
- **AC-6（对应 FR-8/9）**：表驱动测试覆盖：clean+behind → `synced` 且 HEAD == 捕获 SHA；already current → `unchanged`；dirty / wrong-branch / diverged → `skipped` 且 reason 正确、本地现场字节级不变；fetch-failed / trunk-unavailable / ff-only-failed → `failed` 且 reason 正确。所有结果均断言 `before`、`remote`、`after` 遵循 FR-9 的 SHA/null 规则；failed 场景还必须断言远端 merge 已成功、exit 0、`phase=complete`，且本地主 checkout 现场不被修改。
- **AC-7（对应 FR-10）**：所有 `skipped` / `failed` 场景下，`crctl merge` 返回 exit 0、`phase=complete`，远端 merge 结果不受影响；`localTrunkSync` 输出符合 FR-9 四态契约。
- **AC-8（对应 FR-11/NFR-3）**：现有 merge journal、lease publish、finalize、Transaction Workspace 与重入测试继续通过。

## 6. 成功指标

- 新 CR 初始基点与 fetch 后远端 trunk 不一致的案例数归零（注册路径测试覆盖）。
- merge 完成后 clean 本地主 checkout 落后远端的状态在下次 `crctl merge` 后自动消除（`synced`），不再需要手动干预。
- 既有 CR 注册/merge 测试套件零回归。
- 实现 diff 仅涉及 `workspace-transactions.mjs` 与两个测试文件，无新增文件/依赖。

## 7. 范围排除

1. 不新建第二套事务框架：不增加 WAL、补偿事务、持久化 reconciliation intent、durable journal、intent digest、recoverCommand、跨仓补偿或新的状态机。
2. 不建设分阶段诊断：不扩展 `crctl status`、`workspace inspect`、`resume` 或看板；不扫描、批处理或迁移历史 CR；不把 installation trunk 状态混入 CR workspace authority 视图。
3. 不增加 register journal 字段（`base-sha` / `source` / `action` / `worktree-path`）。
4. 不为本地同步增加事务恢复、失败回滚或状态推进；不因本地同步失败回滚已成功的远端发布。
5. 不单列 `skipped-in-use`、`skipped-missing`、`history-rewritten` 等状态；统一四态 + reason。
6. 不自动 checkout trunk、不遍历其他 worktree、不修改 CR worktree。
7. 不新增 Pipeline 节点、Skill Git 算法、README 可执行细节；既有 CR 不迁移，继续按 `workspace freshness/sync` 显式处理。

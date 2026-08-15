# Workspace 基线新鲜度与 CR Worktree 同步治理

> 文档性质：独立治理 CR 的 PRD/SDD 来源文档，不是 CR-2026-041 或 CR-2026-042 的实施产物。
> 建议归属：后续独立 workspace baseline freshness CR（可作为 CR-2026-043，实际编号以 requirement-register 为准）。
> 分析基线：CR-2026-040 归档后的三仓 trunk：knowledge-base `d81d3df`、tools `077d53a`、multica `0bb8dac`。
> 背景事件：CR-2026-040 在 merge 阶段发现 requirement worktree 基于旧 merge-base，造成 CR-2026-039/040 并发改动冲突和重复评审审批。

## 1. 执行摘要

当前 `ensureRepoWorkspace` 将“worktree 存在、工作区干净、HEAD 位于 `requirement/{CR-ID}` 分支”视为 `healthy`，但不检查该分支是否已经包含仓库 trunk。因此，一个干净但基于旧 trunk 的 worktree 可能被放行，实施代码会从过期基线开始。

本治理 CR 增加独立的 workspace freshness 能力：

1. 对每个 active repository 比较 CR worktree HEAD 与 fetch 后捕获的 `origin/{trunk}` SHA。
2. 复用现有 workspace 分类，再增加独立 freshness 关系：`fresh`、`behind-clean`、`diverged`、`unknown`。
3. `fresh` 包括 HEAD 等于 trunk，以及 CR 分支仅 ahead trunk 的正常开发状态。
4. 只对 `ahead=0 && behind>0` 的 `behind-clean` worktree 允许显式、可审计的 `--ff-only` fast-forward。
5. 对 dirty、diverged、错误分支、路径身份异常和 trunk 事实不确定的 worktree 硬阻断，禁止覆盖。
6. 在 `implement-code` 启动前和 `review-code` 启动前执行 freshness gate；评审 gate 失败时复用既有 reviewLoop 重放实现、测试、checkpoint 和评审。
7. 复用现有 workspace resolver、`durable-tx` 的 `workspace` operation、lock、journal、audit 和原生 Git ancestry/`merge --ff-only`，不新增第二套事务框架。

推荐接口形状：

```text
crctl workspace freshness <CR-ID> --workspace <knowledge-base workspace>
crctl workspace sync <CR-ID> --workspace <knowledge-base workspace>
```

`freshness` 是只读业务检查，但允许 fetch 更新 Git remote-tracking 元数据；`sync` 是显式、只允许 fast-forward 的同步事务。普通 `ensureRepoWorkspace` 不静默同步，也不因本 CR 改变注册和恢复行为。

## 2. 问题与事实

### 2.1 已核实问题

CR-2026-041 和 CR-2026-042 在尚未实施时检查到：

- 三仓 requirement worktree 均无未提交改动。
- 三仓 requirement 分支均无独有提交。
- tools worktree 曾基于 `c790b7e`，落后 CR-2026-040 合入后的 `custom/main`。
- knowledge-base 与 multica 也分别落后各自 trunk。
- `ensureRepoWorkspace` 对这种状态返回 `healthy`，不会提示或同步。

这类状态本身不丢失代码，但会把 trunk 已经合入的 CR 改动留在分支之外，直到最终 merge 才暴露为 `MERGE_PREPARE_CONFLICT` 或 release subject drift。

### 2.2 影响

- 实施阶段使用过期基线，增加跨 CR 文件冲突。
- 已审批的 source SHA 在解决冲突后失效，需要重新测试、评审和审批。
- 评审与审批轮次被无效消耗。
- 仅依赖最终 merge 才发现问题，反馈时间晚，修复成本高。
- 如果不同 CR 修改了治理契约，简单选择 ours/theirs 可能使其中一个 CR 的行为或契约失效。

## 3. 范围

### 3.1 目标

- 在实施前暴露 CR worktree 是否已经包含最新 trunk。
- 对无独有提交的落后分支提供安全 fast-forward。
- 对存在独有提交或本地改动的分支拒绝自动覆盖。
- 在代码评审前重新确认 source freshness。
- 将同步事实、同步阻断和竞态失败写入 canonical audit/journal。
- 使“被评审、被审批、最终合并的 source”保持可验证一致。

### 3.2 不做事项

- 不建设通用分支同步平台、rebase 服务或冲突自动解决器。
- 不自动解决三方代码冲突。
- 不对 dirty worktree 执行 stash、reset、clean 或覆盖。
- 不修改状态机、CR ledger schema 或 release-subjects 的基本事实源。
- 不把 trunk 的提交复制进 CR-specific change-request 文件。
- 不在 041 的 archive 证据治理或 042 的职责文本收敛中隐式夹带本能力。
- 不检查或发布远端 `requirement/{CR-ID}` 分支；该事实继续由 `push-progress`、`pull-progress` 和 checkpoint 事务负责。
- 不修改 `ensureRepoWorkspace` 的注册、resume 或 cleanup 行为。
- 不计算 ahead/behind commit count；第一版只需要 ancestry 关系和 SHA。
- 不增加 feature flag、daemon、观察期账本、branch manager、schema registry、通用同步服务或第二套 transaction abstraction。
- 不承诺 macOS 全量兼容矩阵；第一版覆盖已有 Windows/Linux 运行与测试边界。

### 3.3 逻辑架构职责

| 模块 | 本方案应拥有 | 本方案禁止拥有 |
|---|---|---|
| Agent | 判断当前 CR 应进入 freshness 检查、同步或人工处理；选择 Pipeline/Skill；传递 CR-ID 和 workspace | 状态机、Git ancestry/fast-forward 算法、worktree/ledger 受控写入 |
| Pipeline | `workspace-freshness -> implement-code` 与 `workspace-freshness -> review-code` 的节点顺序；输入传递；失败中止；既有 reviewLoop 重放 | 复制 Skill 步骤全文、执行 Git 命令、手写 journal/audit/ledger |
| Skill | 根据 crctl 结构化结果做业务路由；编排 freshness 与条件 sync；定义输入、输出和失败分类 | 实现 ancestry、dirty、ff-only、锁、恢复、状态或账本算法；重复实现 crctl |
| crctl | repository/worktree 解析、基础 workspace 分类、freshness 事实、锁、受控 Git 操作、CAS/事实重核、journal、audit 和结构化错误 | 判断 CR 是否值得实施、改变业务范围、产生 LLM 评审结论或自行修改 PRD/SDD |
| 版本化脚本 | 本 CR 不新增；若未来需要生成确定性说明或索引，只负责 PRD/SDD/TASK/traceability 类纯转换 | 状态推进、人工审批、Git 分支同步和 runtime freshness 判断 |
| README | 人读流程总览、命令入口和失败后的人工动作；链接到 Skill/crctl 权威契约 | 复制 classification 算法、错误状态机或另一份可执行细节事实源 |

Freshness 使用两层分类，不重定义已有 workspace 事实：

- `workspaceClassification` 复用 `classifyRepoWorkspace` 已有结果，如 `healthy`、`dirty`、`wrong-branch`、`missing`、`remote-only`、`path-unregistered`。
- 只有 workspace 已注册、分支正确、clean 且 HEAD 可读取时，才计算 `freshness`：`fresh`、`behind-clean`、`diverged`、`unknown`。
- `fresh` 表示 fetch 后的 trunk 是 HEAD 的祖先，包括 HEAD 等于 trunk 和 CR 分支仅 ahead trunk 两种情况。
- `behind-clean` 表示 HEAD 是 trunk 的祖先、两者不相等，且不存在 CR 独有提交，允许 fast-forward。
- `diverged` 表示双方互不为祖先，禁止自动同步。
- `unknown` 表示 Git 事实不可确认，必须阻断，不得猜测为 fresh。

### 3.4 已有基础设施与最小改造

#### 已经解决、必须复用

| 能力 | 现有事实源 | 本方案用法 |
|---|---|---|
| repositories、trunk、worktree 解析 | `dir-graph.yaml` + `resolveRepositories`/workspace resolver | 唯一解析 active repos 和目标路径，不新增 repo 配置 |
| worktree 基础分类 | `classifyRepoWorkspace`/`ensureRepoWorkspace` | 复用 dirty、wrong-branch、path-unregistered、missing、remote-only 等事实；不改变 ensure 行为 |
| 受控 Git | `gitRun`/`gitMust` 与 controlled-shell 边界 | 复用 fetch、merge-base ancestry 和固定形态的 `merge --ff-only <captured-sha>` |
| lock/journal/恢复 | `durable-tx.mjs` 的 `workspace` operation | 复用 scope lock、journal envelope 和只向前恢复；不新增事务模型 |
| 审计 | crctl audit | 记录 sync 尝试、before/target/after SHA、竞态和失败原因；成功的重复 freshness 读取不逐次落 audit |
| source 发布与审批绑定 | `checkpoint`、`release-subjects`、approve/merge 重核 | sync 不发布 requirement branch；继续由既有能力发布和签入 source SHA |
| Pipeline/Skill 契约检查 | 现有 Pipeline schema、lint、contract tests | 增加一个窄 Skill 的 active/owner 登记、两个 gate 节点和确定性测试 |

#### 本次最小新增

1. 在现有 workspace 事务模块内增加 freshness 分层分类函数，复用已有基础分类。
2. 增加两个窄 CLI 入口：只读业务检查 `workspace freshness`，以及显式 `workspace sync`。
3. sync 对 `behind-clean` 唯一允许的原生 Git 写操作：`merge --ff-only <captured-trunk-sha>`。
4. 增加 `skills/sync/workspace-freshness/SKILL.md`，由 `system-orchestrator` 主责，供 `dev-agent` 调用；Skill 不承载 Git 算法。
5. 在 `code-implementation` 中增加两个 `workspace-freshness` 节点：implement-code 前和 review-code 前。
6. 覆盖分类、拒绝、幂等、竞态、恢复、多仓部分进度和 Windows/Linux 路径/行尾边界的最小测试集。
7. README 增加一段人读入口和错误处理索引，不复制实现算法。

明确不新增依赖、数据库、daemon、branch manager、自动 rebase、自动冲突解决器、远端 requirement 分支发布器、第二套 transaction abstraction 或新的业务账本文件。

### 3.5 Ponytail 决策

本方案按以下顺序停止在首个足够能力：

1. 复用现有 resolver、基础分类、lock、journal、audit、checkpoint、release-subjects 和既有测试 fixture。
2. 使用 Node 标准库和原生 Git ancestry/`merge --ff-only`。
3. 不增加第三方依赖。
4. 不为单一 sync 场景抽象通用 branch orchestration framework。
5. 不让 ensure 静默扩权；只增加两个窄 CLI 入口、一个窄 Skill 和两个 Pipeline gate。
6. 不计算 commit count；只有在实际人工处理需要时再追加诊断字段。

### 3.6 过度设计审查

| 被审查方案 | 结论 | 原因 |
|---|---|---|
| 新建第二套事务框架、WAL 或 branch manager | 删除 | `durable-tx` 已有 workspace operation、lock、journal 和恢复原语 |
| 扩展 `pull-progress` 同时处理 trunk freshness | 删除 | 它的事实源是远端 requirement checkpoint，方向和语义不同 |
| 修改 `ensureRepoWorkspace` 自动同步 | 删除 | 会扩大注册/resume 权限，并把只读 ensure 变成隐式写操作 |
| 自动 merge/rebase/冲突解决 | 删除 | 无法机械判断 CR 独有提交和 trunk 变更的业务取舍 |
| 检查远端 requirement branch 一致性 | 删除 | 属于 checkpoint/push-progress 既有职责，本 sync 不发布远端分支 |
| ahead/behind count | 延后 | ancestry 关系足以完成 gate 和 sync，避免扩展 Git API 与解析测试 |
| 四处 freshness gate | 收敛为两处 | implement 前和 review 前覆盖关键边界；其他阶段已有测试重跑、checkpoint 和 release-subjects 重核 |
| 每次成功 freshness 查询写 audit | 删除 | 会产生重复审计噪声；只持久化 sync、阻断、竞态和失败事实 |
| feature flag、daemon、观察期账本 | 删除 | 本能力可通过先测试只读分类、再接入 sync/gate 的 CR 内实施顺序完成 |
| 新增 Agent、依赖或版本化转换脚本 | 删除 | 现有 system-orchestrator/dev-agent、Node 标准库和既有确定性脚本已足够 |
| macOS 全量兼容承诺 | 删除 | 当前核心运行与 CI 边界是 Windows/Linux；不为未存在的运行环境扩展验收面 |

## 4. PRD 来源

### 4.1 用户故事

作为 CR 开发负责人，我希望在开始实施和提交代码评审前知道每个参与仓的 requirement worktree 是否已经包含最新 trunk；当分支只是干净地落后 trunk、且没有任何 CR 独有提交时，我希望工具能够明确、可审计地 fast-forward；当分支包含独有提交或本地改动时，我希望工具停止并要求人工处理，而不是静默覆盖我的工作。

### 4.2 功能需求

#### FR-01 分层 freshness 分类

工具必须对每个 active repository 返回结构化结果，至少包括：

- repository id；
- trunk ref 与 fetch 后捕获的 trunk SHA；
- CR branch ref 与 CR HEAD SHA（可读取时）；
- worktree path、branch、dirty 状态；
- `workspaceClassification`；
- `freshness`（可比较时）；
- `canFastForward`；
- 阻断原因或结构化 Git 错误。

freshness 判定必须为：

- trunk 是 HEAD 的祖先，或 HEAD 等于 trunk → `fresh`；
- HEAD 是 trunk 的祖先、两者不等且无 CR 独有提交 → `behind-clean`；
- 双方互不为祖先 → `diverged`；
- Git 事实不完整或基础 workspace 状态不可比较 → `unknown`。

#### FR-02 业务 freshness 检查

`crctl workspace freshness` 必须：

- 读取目标 workspace `dir-graph.yaml` 的 active repositories 和 trunk 声明；
- 对所有 active repositories 按 repository id 稳定排序；
- 在每个仓 fetch `origin`，读取 `refs/remotes/origin/{trunk}` 作为本次 captured target；
- 复用现有 workspace resolver 和基础分类；
- 仅在 workspace healthy、clean、branch 正确且 HEAD 可读取时执行 ancestry 比较；
- 不修改 worktree 文件、local requirement branch、remote requirement branch、CR 状态、approval 或 ledger；
- 允许 fetch 更新 remote-tracking ref/FETCH_HEAD，并明确记录该边界；
- Git 事实缺失、远端不可确认或 repository 声明非法时返回结构化失败，不猜测为 fresh；
- 成功的只读查询不重复写入持久 audit，结构化结果由调用 Skill 消费。

#### FR-03 显式安全同步

`crctl workspace sync` 必须：

- 使用 resolver 解析 active repositories、worktree 和固定 `requirement/{CR-ID}` branch；
- 获取 `workspace-sync-{CR-ID}` scope lock；
- 在任何 Git 写入前重新执行全仓 freshness preflight；
- 只对 `behind-clean` worktree 执行同步；
- 为每个仓捕获 `beforeSha`、`targetTrunkSha` 和 workspace facts；
- 只执行等价于 `git merge --ff-only <captured-trunk-sha>` 的受控操作；
- 不接受调用方任意 branch、refspec、path、reset、force、stash、rebase 或策略参数；
- 按 repository id 稳定顺序处理；
- 每个仓执行前重新确认 HEAD、target trunk SHA、clean 状态和当前分支未变化；
- after SHA 必须等于 captured target SHA；若 HEAD 已等于 target，记录 `unchanged`；
- 不 push requirement branch，不修改 CR 状态、审批或业务账本。

如果任一仓出现 dirty、diverged、wrong-branch、missing、path-unregistered、unknown、trunk 变化或 Git 操作失败，停止后续写入并返回结构化错误。已经完成的仓保留 journal 事实，不执行补偿性 reset、revert 或反向同步。

#### FR-04 保护本地工作

以下情况必须零覆盖、零自动同步：

- worktree dirty；
- CR 分支与 trunk 已分叉；
- worktree 未注册、路径身份不一致或当前分支错误；
- worktree/head/trunk 事实无法确认；
- fetch、lease 或 ancestry 检查失败；
- preflight 与 ff-only 写入前的事实不一致。

远端 requirement branch 的存在与一致性不在本 CR 范围内，由 checkpoint/push-progress 既有能力保护。

#### FR-05 生命周期门禁

freshness gate 接入两个位置：

1. `implement-code` 启动前：`fresh` 继续；`behind-clean` 由该节点显式调用 sync；其他结果阻断实施。
2. `review-code` 启动前：重新 freshness；任何非 fresh 结果阻断评审，并按既有 `reviewLoop.replayNodes` 重放 `implement-code -> write-test-report -> push-progress -> workspace-freshness -> review-code`。

不新增独立的 `write-test-report` freshness 节点或 checkpoint freshness 节点。`review-code` 仍无条件重新执行验证命令；`approve-code` 和 merge 继续由既有 release-subjects 做最终 source SHA 重核。

#### FR-06 审计与证据

sync 动作、阻断和竞态必须记录到现有 crctl audit/transaction journal：

- CR-ID、repository、worktree branch；
- before HEAD、captured trunk SHA、after HEAD；
- workspaceClassification、freshness、操作结果；
- 操作人、时间、transaction id；
- 是否为 fast-forward 或 unchanged；
- 失败原因、actual/expected SHA（若可得）和 recover command。

不新建 workspace ledger，不为每次成功的只读 freshness 查询写重复 audit。review/approve source 的长期证据继续由既有 review annotation、release-subjects、approval digest 和 checkpoint 负责。

#### FR-07 幂等与恢复

相同 CR、相同仓、相同 before/target 输入重复执行必须幂等。中断后重跑同一业务命令：

- 已完成的 fast-forward 不重复产生提交；
- 已经到达 target SHA 的仓标记为 unchanged/confirmed；
- 尚未执行且仍处于 beforeSha 的仓可以继续；
- trunk 已变化、HEAD 被第三方修改、worktree 变 dirty、journal 非法或输入漂移时硬失败；
- 不删除旧 journal，不清理用户文件，不执行反向 reset/revert。

多仓整体语义是稳定顺序、逐仓持久化、失败停止、只向前恢复；单仓 fast-forward 是原生 Git 的原子动作，不承诺跨仓 ACID 回滚。

#### FR-08 跨平台边界

第一版必须保持 Windows 与 Linux 的一致行为：

- 路径身份和 worktree registration 复用现有 canonical/realpath 检查；
- 文本解析遵守 CRLF→LF 规范化纪律；
- Git 输出按 `\r?\n` 解析；
- 不把路径大小写、分隔符或 symlink 差异降级为 fresh；
- macOS 不列为本 CR 的全量验收平台，后续在实际运行环境出现时再补矩阵。

## 4.3 验收标准

- AC-01：已注册、clean、正确分支的 worktree 中，HEAD 等于 trunk 和 HEAD 仅 ahead trunk 都稳定分类为 `fresh`。
- AC-02：HEAD 是 trunk 祖先且无 CR 独有提交时稳定分类为 `behind-clean`，可通过显式 sync fast-forward 到 captured target SHA。
- AC-03：dirty、wrong-branch、missing、path-unregistered 和 remote-only 复用基础 workspace 分类，并返回 `freshness=unknown`，不得猜测为 fresh。
- AC-04：有 CR 独有提交且 trunk 前进的 worktree 分类为 `diverged`，sync 零写入并返回人工处理错误。
- AC-05：trunk 在 preflight 后、ff-only 前发生变化时，事务返回 `WORKSPACE_FRESHNESS_CHANGED`，不使用旧 SHA 继续。
- AC-06：多仓结果按 repository id 稳定排序；同步在任一仓 preflight 阻断时不写入任何仓；已完成仓的中断事实可重跑续接。
- AC-07：implement-code 前无法通过 freshness gate 时不进入代码实施。
- AC-08：实施期间 trunk 前进时，review-code 前 freshness gate 阻止过期 source 进入评审，并按既有 reviewLoop 重放实现、测试、checkpoint 和评审。
- AC-09：同一输入重跑幂等，不重复 fast-forward、不重复生成业务提交、不执行 reset/revert。
- AC-10：sync before/after SHA、transaction id、操作结果和失败原因可在现有 canonical audit/journal 中追溯。
- AC-11：Windows 与 Linux 的 freshness、sync、dirty/diverged/path、CRLF 和 worktree registration 边界测试通过。

## 5. SDD 来源

### 5.1 事实源与权限边界

- repository、trunk、worktree root：由目标 workspace `dir-graph.yaml` resolver 唯一解析。
- CR branch：固定为 `requirement/{CR-ID}`。
- trunk authority：每次 freshness/sync 先 fetch，使用 `refs/remotes/origin/{trunk}` 的 captured SHA。
- source authority：开发期为 CR worktree；merge/回写期继续由现有 operational workspace 规则决定。
- Git 写入：只允许 crctl 深原语通过受控 `gitMust` 执行。
- 状态和账本：继续由 crctl 独占；freshness/sync 不直接修改 `_backlog.yml`、`cr.md` status 或 approval。
- 远端 requirement branch：不由本 CR 检查、发布或修改，继续由 checkpoint/push-progress 负责。
- Skill/Pipeline：只传 CR-ID、workspace 和 `gate` 业务上下文，不手写 Git 算法。

### 5.2 深模块接口

建议在现有 `workspace-transactions.mjs` 内增加窄接口：

```text
classifyWorkspaceFreshness(ctx, cr) -> {
  cr,
  repositories: [{
    repo,
    trunkRef,
    trunkSha,
    branch,
    headSha,
    worktreePath,
    workspaceClassification,
    freshness,
    dirty,
    canFastForward
  }],
  allFresh,
  syncable
}

syncWorkspaceToTrunk(ctx, { cr, workspace }) -> {
  cr,
  txId,
  phase,
  repositories: [{
    repo,
    beforeSha,
    targetTrunkSha,
    afterSha,
    action: 'unchanged' | 'fast-forwarded' | 'blocked',
    workspaceClassification,
    freshness,
    reason
  }],
  changed,
  recoverCommand
}
```

`cmdWorkspace` 只负责参数解析、调用和 JSON 输出。不得在 CLI 层实现 ancestry、dirty、lease、锁或恢复算法。`next` 等业务建议由 `workspace-freshness` Skill 根据结构化结果生成，不由 crctl 推断。

### 5.3 Freshness 算法

对每个 active repository：

1. 通过现有 resolver 解析 repository root、worktree path、trunk ref 和 `requirement/{cr}` branch。
2. 调用既有基础分类；若不是已注册、clean、正确分支且 HEAD 可读取，返回 `freshness=unknown`，不继续猜测。
3. fetch `origin`，读取 `refs/remotes/origin/{trunk}` 的 SHA 作为本次 captured target。
4. 使用 Git ancestry 判断：
   - trunk 是 HEAD 的祖先，或两者相等 → `fresh`；
   - HEAD 是 trunk 的祖先且两者不等 → `behind-clean`；
   - 双方互不为祖先 → `diverged`。
5. `behind-clean` 的可同步条件是 HEAD 是 trunk 的祖先且 worktree clean；不计算 ahead/behind count。
6. 结果按 repository id 排序。crctl 返回事实与机械 `canFastForward`，Skill 再决定当前 gate 是继续、调用 sync 还是阻断。

不通过字符串比较、时间戳或“最近 commit”启发式推断 ancestry。Git 结果非零必须结构化失败。

### 5.4 Sync 事务

`syncWorkspaceToTrunk` 复用现有 durable-tx 的 `workspace` operation：

1. 获取 `workspace-sync-{cr}` scope lock。
2. 在锁内对所有 active repos 执行 freshness preflight，捕获每仓 `workspaceClassification`、`beforeSha` 和 `targetTrunkSha`。
3. 若所有仓都是 fresh，返回 `changed=false`、各仓 `unchanged`，不创建空 journal；若存在任一基础阻断、diverged、unknown 或 trunk 不可确认，零仓写入并返回错误。
4. 按 repository id 稳定顺序处理每个 `behind-clean` 仓。
5. 每仓操作前重新读取 HEAD、target trunk ref、branch 和 dirty 状态；任一事实变化则返回 `WORKSPACE_FRESHNESS_CHANGED`。
6. 使用受控 `git merge --ff-only <targetTrunkSha>`，不使用 `reset --hard`、`clean`、stash、rebase、force push 或普通 merge。
7. 每仓完成后记录 after SHA；after SHA 必须等于 captured target SHA，且动作只能是 `unchanged` 或 `fast-forwarded`。
8. 每个仓完成后持久化 journal/audit；任一仓失败时停止后续仓，保留已完成仓事实，不执行补偿性回滚。
9. sync 完成后 review/checkpoint 仍需按既有流程重核 source SHA；sync 本身不 publish requirement branch。

同步不锁远端 trunk。fetch 后目标 trunk 仍可能变化，因此 ff-only 前必须重新确认 captured SHA；变化即硬失败并要求重新 freshness。

### 5.5 并发与竞态

主要竞态是 fetch 后 trunk 又前进，或者另一个进程修改 worktree。防护要求：

- freshness 只读检查不持有 sync lock；
- sync 在锁内重新执行全仓 preflight；
- ff-only 前重新读取目标 trunk SHA、worktree HEAD、branch 和 dirty 状态；
- 任一事实变化则返回 `WORKSPACE_FRESHNESS_CHANGED`；
- lock 只保护本地 crctl 同步事务，不假设能锁住远端 trunk；
- remote trunk history rewrite 或不可确认直接硬阻断；
- sync 完成后 review/checkpoint 仍需独立重核 source SHA。

### 5.6 Pipeline 接入

新增一个 active Skill：`sync/workspace-freshness`，由 `system-orchestrator` owns，`dev-agent` can-call。该 Skill 输入为：

```text
cr_id
workspace
gate: implement-start | review-start
```

Skill 只调用 `crctl workspace freshness` 和条件性的 `crctl workspace sync`，不接受任意 ref、path、branch、merge strategy 或 force 参数。

`code-implementation` 增加两个节点：

```text
approve-dev-start
→ workspace-freshness(gate=implement-start)
→ implement-code
→ write-test-report
→ push-progress
→ workspace-freshness(gate=review-start)
→ review-code
→ push-progress
→ human_approval
```

implement-start gate：

- `fresh` → 进入 implement-code；
- `behind-clean` → 调用 sync，完成后进入 implement-code；
- 其他结果 → abort，不进入 implement-code。

review-start gate：

- `fresh` → 进入 review-code；
- 其他结果 → abort，并按既有 reviewLoop 的 replayNodes 重放：
  `implement-code -> write-test-report -> push-progress -> workspace-freshness(review-start) -> review-code`。

不新增独立的 write-test-report freshness 节点或 checkpoint freshness 节点。Pipeline 只编排 Skill，Skill 不复制 crctl 算法。修改 Pipeline 后同步 `pipeline-templates/_index.yml` 的实际节点数，并通过现有 pipeline contract tests。

### 5.7 错误语义

固定最小错误类别：

- `WORKSPACE_FRESHNESS_STALE`：worktree 为 `behind-clean`，可由显式 sync 处理；
- `WORKSPACE_FRESHNESS_DIVERGED`：双方互不为祖先，必须人工处理；
- `WORKSPACE_FRESHNESS_CHANGED`：preflight 与写入之间事实变化；
- `WORKSPACE_TRUNK_UNAVAILABLE`：无法确认 captured trunk；
- `WORKSPACE_SYNC_BLOCKED`：基础 workspace 分类、路径、分支或注册状态不满足；
- `WORKSPACE_SYNC_CONFLICT`：ff-only 失败或 history rewrite。

`dirty`、`wrong-branch`、`missing`、`remote-only`、`path-unregistered` 作为每仓 `workspaceClassification` 返回，不为每个状态复制独立错误算法。错误输出必须包含 repository、worktree path、before/actual/expected SHA（若可得）和 recover command，不允许降级为 healthy 或空结果。

## 6. 测试设计

### 6.1 分类单元测试

- fresh：HEAD 等于 trunk；
- fresh：CR HEAD 仅 ahead trunk；
- behind-clean：HEAD 是 trunk 祖先且无独有提交；
- diverged：双方互不为祖先；
- dirty、wrong-branch、missing、remote-only、path-unregistered 复用基础分类并返回 unknown；
- trunk 缺失、fetch 失败、history rewrite；
- 多仓稳定排序；
- Windows path、CRLF 和 worktree registration 边界。

不测试 ahead/behind count，因为第一版不提供该字段。

### 6.2 事务测试

- behind-clean 成功 ff-only，after SHA 等于 captured target；
- 全部 fresh 时 sync no-op，不创建空 journal；
- dirty/diverged/unknown 零写入；
- ff-only 失败不执行 reset/clean/force/revert；
- sync 中断后同命令只向前恢复；
- trunk SHA 在 preflight 后改变时硬失败；
- HEAD、branch 或 dirty 状态在 ff-only 前改变时硬失败；
- 多仓第 N 个仓失败时已完成仓保留，第 N+1 个仓不写入；
- 进程并发锁竞争保守阻断；
- 重跑不重复 fast-forward、不重复业务提交、不删除用户文件；
- audit/journal 记录 before/target/after、txId、失败原因和 recoverCommand。

### 6.3 Pipeline/Skill 契约测试

- `workspace-freshness` 在 `skills/_index.yml` active；
- `system-orchestrator` 是唯一 owns owner，`dev-agent` 具备 can-call；
- 两个 gate 节点位于 implement-code 前和 review-code 前；
- reviewLoop replayNodes 包含第二个 freshness gate；
- Pipeline 不包含 Git 命令、journal 算法或手写账本操作；
- `pipeline-templates/_index.yml` 节点数与 JSON 实际节点数一致。

### 6.4 集成测试

- implement-code 前 stale worktree 被阻止或显式 sync 后继续；
- behind-clean sync 后实现从新 HEAD 开始；
- 实施期间 trunk 前进，review-code 前被拦截；
- review gate 阻断后按既有 replayNodes 重跑实现、测试、checkpoint 和评审；
- release-subjects 与 sync 后 source SHA 继续由既有 approve/merge 重核；
- Windows 与 Ubuntu 至少各跑一遍 active repository matrix。

## 7. 实施与迁移建议

1. 在同一个后续 CR 内先实现只读 freshness 分类和确定性测试。
2. 复用 `durable-tx` 的 workspace operation 增加显式 ff-only sync、journal、锁和恢复测试。
3. 新增并登记 `sync/workspace-freshness` Skill，由 `system-orchestrator` owns。
4. 在 code-implementation Pipeline 中增加 implement-start 和 review-start 两个 gate，并同步 Pipeline index 节点数。
5. 先完成 read-only 分类测试，再启用 sync，再接入两个 Pipeline gate；这是同一 CR 内的实施顺序，不增加 feature flag 或观察期账本。
6. 已有在途 CR 不做批量迁移；它们在下一次经过 implement/review gate 时按新规则检查。
7. `ensureRepoWorkspace`、`pull-progress`、checkpoint、release-subjects、状态机和 baseline 生成脚本保持既有职责。

## 8. 设计决策

### 决策 D-01：不静默 reset

采用 freshness 只读检查 + 显式 sync `--ff-only`。原因：`reset --hard` 会隐藏分支独有提交、误删用户工作，并让同步变成不可审计的破坏性动作。

### 决策 D-02：fresh 包含 ahead-only

采用“trunk 是 CR HEAD 的祖先”作为 fresh 判定，而不是要求 HEAD 与 trunk 完全相等。原因：正常开发分支必然包含 CR 自己的提交；如果 ahead-only 不算 fresh，所有已经开始实现的 CR 都会在测试和评审前被错误阻断。

### 决策 D-03：behind-clean 可同步，diverged 不自动解决

无独有提交的落后分支具备明确 fast-forward 证明；存在独有提交时，工具无法判断应该保留哪一方，必须人工处理并重新评审。

### 决策 D-04：同步不等于发布

sync 只更新本地 requirement worktree 到 captured trunk SHA；checkpoint/push-progress 仍负责将 source 发布到远端。分开两者可以避免同步行为意外改变远端分支事实、release-subjects 或审批证据。

### 决策 D-05：freshness 与基础 workspace 分类分层

复用 `classifyRepoWorkspace` 的 dirty、wrong-branch、missing、remote-only 和 path-unregistered 事实；freshness 只表达 ancestry 关系。原因：不复制既有 workspace resolver 的事实源，也避免把“资源不存在”和“分支落后”混成一个枚举。

### 决策 D-06：只接入两个生命周期 gate

在 implement-code 前做首次 freshness/sync，在 review-code 前做复检。原因：测试报告会在 reviewLoop 中随实现重建，checkpoint 和审批/merge 已有 source 重核；增加更多重复 gate 只增加网络调用和审计噪声。

### 决策 D-07：多仓只向前恢复

单仓 fast-forward 是原生 Git 原子动作，多仓同步采用稳定顺序、逐仓 journal、失败停止和只向前恢复。原因：跨仓补偿性回滚需要 reset/revert，风险高于保留已完成的安全 fast-forward。

### 决策 D-08：不检查远端 requirement branch

freshness/sync 只负责本地 CR worktree 与 trunk 的关系；远端 requirement branch 的 checkpoint、发布和恢复继续由既有 sync/checkpoint 能力负责。原因：避免两个能力重复拥有同一远端事实。

### 决策 D-09：第一版不计算 commit count

第一版只返回 SHA、ancestry 关系和 `canFastForward`。原因：count 不是 gate 或 sync 的必要条件，避免扩展受控 Git API、跨平台解析和测试矩阵；实际需要时再追加诊断字段。

### 决策 D-10：无批量迁移和 feature flag

新 gate 对所有后续进入实施/评审边界的 CR 生效；既有 CR 在下一次 gate 时按同一规则处理。原因：批量扫描、迁移账本和观察期控制面会引入与本能力无关的持久化和运营复杂度。

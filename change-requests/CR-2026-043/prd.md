---
id: CR-2026-043-prd
type: PRD
cr-ref: CR-2026-043
title: Workspace 基线新鲜度与 CR Worktree 同步治理
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-16T00:08:44+08:00
updated: 2026-08-16T00:08:44+08:00
---

# 1. 概述

当前 `crctl workspace inspect/ensure` 能判断 CR worktree 是否存在、已注册、干净且位于正确分支，但不会判断该 worktree 是否已经包含 fetch 后的最新 `origin/{trunk}`。因此，一个分类为 `healthy` 的 worktree 仍可能基于旧 trunk 开始实施，直到代码评审或最终 merge 才暴露冲突，导致测试、评审和审批证据失效并重复执行。

本 CR 增加一项独立的 workspace baseline freshness 能力：

1. 对每个 active repository 比较 CR worktree HEAD 与 fetch 后捕获的 `origin/{trunk}` SHA，返回 `fresh`、`behind-clean`、`diverged` 或 `unknown`。
2. 只对没有 CR 独有提交、没有本地改动的 `behind-clean` worktree 提供显式、可审计的 fast-forward 同步。
3. 在 `implement-code` 前和 `review-code` 前执行 freshness gate；评审前发生安全同步后，复用既有 reviewLoop 重建实现、测试、checkpoint 和评审证据。
4. dirty、diverged、错误分支、路径身份异常或 Git 事实不确定时硬阻断，不覆盖用户工作。

本 CR 不是新事务平台。实现必须复用现有 workspace resolver、基础分类、durable transaction、lock/journal/audit、受控 Git、checkpoint、release-subjects 和 reviewLoop，只做满足上述行为所需的最小改造。

# 2. 目标逻辑架构

## 2.1 Ponytail 优先级

本 CR 的设计和实施必须按以下顺序选择能力，并在首个足够方案处停止：

1. 复用现有能力；
2. Node 标准库；
3. 原生 Git/文件 API；
4. 已有依赖；
5. 一行代码；
6. 最小新增代码。

不得为未来可能出现的同步场景预建通用分支编排、插件、服务或账本。

## 2.2 模块职责边界

| 模块 | 应拥有 | 不应拥有 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 复制 Skill 完整算法、手写账本操作 |
| Skill | 业务判断、编排步骤、输入输出和失败语义 | 手写原子账本逻辑、重复实现 `crctl` |
| `crctl` | 状态、门禁、CAS、受控账本写入、审计、原子提交 | 业务设计判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性转换 | 状态推进、人工审批 |
| README | 人读流程总览 | 另一份可执行细节事实源 |

## 2.3 已经解决的基础设施

以下能力已经存在，本 CR 只复用，不得复制或替换：

| 已有能力 | 当前事实 | 本 CR 的复用方式 |
|---|---|---|
| Repository/worktree resolver | `resolveRepositories` 从 `dir-graph.yaml#repositories` 解析 active repo、trunk、worktree root，并按 repo id 稳定排序 | 作为 repository、trunk 和 worktree 路径的唯一来源 |
| Workspace 基础分类 | `classifyRepoWorkspace` 已返回 `healthy`、`dirty`、`wrong-branch`、`missing`、`branch-only`、`remote-only`、`path-unregistered` | freshness 作为第二层关系，不重定义基础分类；`ensureRepoWorkspace` 行为保持不变 |
| 受控 Git | `gitRun/gitMust` 已使用 argv 与 `shell:false`，事务处理器独占 Git 副作用 | 复用 fetch、ancestry 判断和固定形态的 `merge --ff-only` |
| Durable transaction | durable-tx 已有 `workspace` operation、scope lock、journal envelope、故障恢复和只向前写入基础能力 | 同步沿用现有 operation，不增加 WAL、事务协议或补偿框架 |
| Audit 与结构化错误 | crctl 命令层已有统一 audit 和 `TxError` 输出 | 记录同步、阻断、竞态和恢复事实，不新建 workspace ledger |
| Source 发布与重核 | checkpoint、review annotation、approval release-subjects 和 merge 已绑定/重核 source SHA | freshness/sync 不发布远端 requirement branch，不替代最终 source 重核 |
| Pipeline 自修复 | code-implementation 已有测试与代码评审 reviewLoop、`replayNodes` 和失败中止 | 评审前同步后扩展既有重放链，不创建第二套 loop |

## 2.4 本次应复用的最小改造

| 最小改造 | 归属 | 说明 |
|---|---|---|
| Freshness 第二层分类 | `crctl` 现有 workspace transaction 模块 | 基于基础分类和原生 Git ancestry 返回四类关系及 SHA 事实 |
| 两个窄 CLI 入口 | `crctl workspace` | 增加只读业务检查 `freshness` 与显式 fast-forward `sync` |
| 一个窄 Skill | `skills/sync/workspace-freshness` | 根据 crctl 结构化结果决定继续、条件同步、回修或人工处理；不实现 Git/事务算法 |
| 两个 Pipeline gate | `code-implementation` | 分别位于 `implement-code` 前和 `review-code` 前；评审回修复用既有 reviewLoop |
| 最小契约与行为测试 | 现有测试体系 | 覆盖分类、保护、幂等、竞态、恢复和 Pipeline/Skill 边界 |
| 一段人读说明 | README | 说明入口和失败后的人工动作，链接到 Skill/crctl 权威契约 |

本 CR 不新增依赖、数据库、daemon、branch manager、自动 rebase、冲突解决器、远端 requirement 分支发布器、版本化转换脚本或第二套事务框架。

# 3. 用户故事

- **US-01 开发负责人**：希望在开始实施前确认每个参与仓的 CR worktree 已包含最新 trunk；若只是干净落后，希望通过显式安全同步后继续。
- **US-02 代码评审者**：希望评审开始前重新确认 source 基线新鲜；若同步改变了 source，希望实现、测试和 checkpoint 证据先重建，再进入评审。
- **US-03 CR 协作者**：希望 dirty、diverged、错误分支或身份不明的 worktree 被保守阻断，任何自动动作都不能 reset、stash、rebase、覆盖或删除本地工作。
- **US-04 Tools 维护者**：希望 freshness 复用现有 resolver、workspace transaction、受控 Git 和 reviewLoop，不维护第二套状态、Git 或事务实现。
- **US-05 审计者**：希望同步的 before/target/after SHA、结果和失败原因可在现有 journal/audit 中追溯，并能从中断点安全重试。

# 4. 功能需求

## FR-01 分层 freshness 分类

1. Freshness 必须是独立于 `workspaceClassification` 的第二层关系，不修改现有基础分类语义。
2. 仅当 worktree 已注册、当前分支正确、工作区 clean，且 HEAD 与 fetch 后的 trunk SHA 均可确认时，才执行 ancestry 判断：
   - trunk SHA 等于 HEAD，或 trunk 是 HEAD 的祖先：`fresh`；
   - HEAD 是 trunk 的祖先且两者不等：`behind-clean`；
   - 双方互不为祖先：`diverged`；
   - 基础 workspace 不可比较或 Git 事实不完整：`unknown`。
3. `fresh` 必须包含 CR 分支仅 ahead trunk 的正常开发状态；不得要求 HEAD 与 trunk 完全相等。
4. 每仓结构化结果至少包含 repo id、trunk ref/SHA、CR branch/HEAD、worktree path、基础分类、freshness、dirty、`canFastForward` 和阻断原因。
5. 第一版不计算 ahead/behind commit count，不使用时间戳、commit message 或字符串启发式猜测 ancestry。

## FR-02 只读业务检查

1. `crctl workspace freshness <CR-ID>` 必须从目标 workspace 的 repository resolver 读取全部 active repositories 和各自 trunk，不接受调用方传入任意 repo、branch、ref 或 path。
2. 命令必须对每个 active repository fetch `origin`，以本次捕获的 `refs/remotes/origin/{trunk}` SHA 作为比较目标，并按 repo id 稳定输出结果。
3. freshness 检查不得修改 worktree 文件、local/remote requirement branch、CR 状态、审批或业务账本。fetch 更新 remote-tracking refs/FETCH_HEAD 属于明确允许的 Git 元数据变化。
4. repository 声明、fetch、HEAD、trunk 或 ancestry 事实无法确认时必须结构化失败或返回 `unknown`，不得降级为 `fresh`、`healthy` 或空结果。
5. 成功的重复检查不逐次写持久 audit；阻断和技术失败仍按现有审计规则记录。

## FR-03 显式安全同步

1. `crctl workspace sync <CR-ID>` 必须复用 resolver、workspace 基础分类、durable-tx 的 `workspace` operation、scope lock、journal 和 audit。
2. sync 在任何 Git 写入前必须对全部 active repositories 执行一次完整 preflight。任一仓为 dirty、diverged、unknown、wrong-branch、missing、branch-only、remote-only、path-unregistered 或 trunk 不可确认时，全仓零写入并硬失败。
3. 只有 `behind-clean` 仓允许同步；唯一允许的 worktree 写操作是等价于 `git merge --ff-only <captured-trunk-sha>` 的受控 Git 调用。已经 `fresh` 的仓保持 `unchanged`。
4. 调用方不得传入任意 branch、refspec、path、merge strategy、reset、force、stash、rebase 或 push 参数。
5. 每仓执行前必须重核当前分支、clean 状态、HEAD 和 captured trunk SHA；任一事实变化时停止后续写入并返回 expected/actual 事实。
6. 同步后 `afterSha` 必须等于 captured trunk SHA。sync 不 push requirement branch，不修改 CR 状态、审批、review annotation 或业务账本。

## FR-04 幂等、竞态和只向前恢复

1. 同一 CR、同一 before/target 事实重复执行必须幂等；已到达 target SHA 的仓返回 `unchanged/confirmed`，不得生成额外提交。
2. 全仓 preflight 通过后，按 repo id 稳定顺序逐仓 fast-forward，并在每仓完成后持久化既有 journal/audit 事实。
3. 运行期第 N 个仓失败时，停止第 N+1 个及之后的仓；已完成仓保持 fast-forward 结果，不执行 reset、revert 或反向补偿。
4. 中断后重跑同一命令时，已确认完成的仓不重复写，未执行且事实未漂移的仓可继续。
5. trunk、HEAD、branch、dirty 状态、repository graph 或 journal 发生漂移时硬失败，并返回可执行的恢复提示；不得删除 journal、清理用户文件或猜测继续。
6. 单仓 fast-forward 使用原生 Git 原子语义；多仓只承诺稳定顺序、失败停止、逐仓持久化和只向前恢复，不承诺跨仓 ACID 回滚。

## FR-05 生命周期 gate 与 reviewLoop

1. `code-implementation` 必须增加两个 `workspace-freshness` Skill 节点：一个位于 `implement-code` 前，一个位于 `review-code` 前。
2. implement-start gate 的业务路由：
   - 全仓 `fresh`：继续 `implement-code`；
   - 存在 `behind-clean` 且其余仓可比较：显式调用 sync，重核全仓 `fresh` 后继续；
   - 存在 `diverged`、`unknown` 或基础 workspace 阻断：abort，不进入实施。
3. review-start gate 的业务路由：
   - 全仓 `fresh`：继续 `review-code`；
   - 存在 `behind-clean`：显式调用 sync；同步成功后不得直接评审，必须复用代码评审既有 reviewLoop 重放实现、测试、checkpoint、freshness 和 review-code；
   - 存在不可自动同步的结果：abort 并输出人工处理所需事实，不进行无意义的自动重试。
4. 代码评审 reviewLoop 的重放顺序必须包含：`implement-code -> write-test-report -> push-progress -> workspace-freshness(review-start) -> review-code`。
5. 不增加 `write-test-report`、checkpoint 或审批前的额外 freshness gate。`approve-code` 与 merge 继续使用既有 release-subjects/source SHA 重核。
6. Pipeline 只拥有节点顺序、输入传递、reviewLoop 和失败中止；不得出现 Git 命令、ancestry 算法、journal/audit 写入或 Skill 全文复制。

## FR-06 Skill、Agent、crctl 与文档采用

1. 新增一个 active `workspace-freshness` Skill，由 `system-orchestrator` 唯一 owns，`dev-agent` can-call；不新增 Agent。
2. Skill 输入只包含 `cr_id`、workspace 和 gate 场景；Skill 负责调用 freshness、按结构化结果做业务路由，并在允许时调用 sync。
3. Skill 不接受任意 ref/path/branch/strategy，不实现 Git、锁、journal、CAS、状态推进、账本或审计算法。
4. `crctl` 负责确定性 workspace/Git 事实、受控同步、竞态重核、持久恢复与结构化错误；不得判断需求价值、TASK 是否合理或 LLM 评审是否通过。
5. Agent 只根据职责和 `crctl next` 选择 Pipeline/Skill、传递 CR-ID/workspace 并决定是否需要人工介入；不得保存状态机副本或直接写受控文件。
6. 本 CR 不新增版本化脚本。README 只增加命令入口、结果含义、人工处理动作和权威链接，不复制分类算法、恢复状态机或错误实现细节。
7. 新增 Skill 后必须同步 `skills/_index.yml` 与 `agent-skill-matrix.yml`；Pipeline 节点数变化必须同步 `_index.yml`，并通过现有契约检查。

# 5. 非功能需求

- **安全性**：dirty、diverged、错误分支、路径身份异常和事实不确定场景必须零覆盖；禁止 reset、clean、stash、rebase、force、普通 merge 和自动冲突解决。
- **一致性**：repository、trunk、worktree 只由 `dir-graph.yaml` resolver 解析；freshness 与基础 workspace 分类分层，不创建竞争事实源。
- **可恢复性**：同步复用现有 durable transaction、lock/journal 和只向前恢复；多仓部分进度可重放，不做补偿回滚。
- **可审计性**：sync、阻断和竞态记录 CR-ID、repo、branch、before/target/after SHA、分类、结果、actor、时间和 transaction id；不新建 workspace ledger。
- **跨平台性**：Windows 与 Linux 的路径身份、worktree registration、CRLF/LF 和 Git 输出解析行为一致；所有文本先 CRLF 转 LF，逐行解析使用 `\r?\n`，解析失败硬失败。
- **性能**：每个 gate 对每个 active repository 至多执行必要的 fetch、基础分类和 ancestry 检查；不增加 daemon、缓存、后台扫描或 commit count 计算。
- **兼容性**：`ensureRepoWorkspace`、`pull-progress`、checkpoint、release-subjects、状态机和远端 requirement branch 语义保持不变。
- **依赖约束**：不新增生产依赖；优先使用现有 helper、Node 标准库和原生 Git。

# 6. 验收标准

- **AC-01（FR-01）**：HEAD 等于 trunk、以及 CR HEAD 仅 ahead trunk 时，均稳定分类为 `fresh`。
- **AC-02（FR-01/03）**：HEAD 是 trunk 祖先且两者不等时分类为 `behind-clean`；显式 sync 只通过 ff-only 到达 captured trunk SHA，结果为 `fast-forwarded`。
- **AC-03（FR-01/03）**：dirty、wrong-branch、missing、branch-only、remote-only、path-unregistered 复用现有基础分类，freshness 为 `unknown`，sync 全仓零写入。
- **AC-04（FR-01/03）**：CR 分支与 trunk 双方均有独有提交时分类为 `diverged`；sync 不执行 Git 写入，并返回人工处理所需的 repo、path 与 SHA。
- **AC-05（FR-02）**：freshness 对 active repositories 按 id 稳定输出，使用 fetch 后捕获的 `origin/{trunk}` SHA；除 remote-tracking 元数据外，不修改 worktree、requirement branch、状态、审批或账本。
- **AC-06（FR-03/04）**：任一仓在全仓 preflight 阶段阻断时，没有仓发生 fast-forward；preflight 后 trunk、HEAD、branch 或 dirty 事实变化时，停止后续仓并返回 expected/actual。
- **AC-07（FR-04）**：同一输入重跑幂等，不重复提交；多仓第 N 仓中断后重跑保留已完成仓、继续未完成仓，不执行 reset/revert 或删除用户文件。
- **AC-08（FR-05）**：implement-code 前非 fresh worktree 不会直接进入实施；`behind-clean` 经显式 sync 并重核 fresh 后方可继续。
- **AC-09（FR-05）**：实施期间 trunk 前进时，review-code 前 gate 阻止旧 source 进入评审；behind-clean 同步后按既有 reviewLoop 重放实现、测试、checkpoint、freshness 和评审。
- **AC-10（FR-05/06）**：静态契约检查证明 Pipeline 不含 Git/journal 算法，Skill 不含原子账本/Git 算法，Agent 不含状态机/受控写入，README 不复制可执行细节事实源。
- **AC-11（NFR）**：Windows 与 Linux 的 fresh/behind-clean/diverged/unknown、dirty、路径身份、CRLF 和 worktree registration 测试通过；解析失败不会静默返回空结果或 fresh。
- **AC-12（全范围）**：现有 workspace resolver、register/resume/cleanup、checkpoint、test、reviewLoop、approve 和 merge 回归测试保持通过；无新增生产依赖、状态、业务账本、版本化脚本或事务框架。

# 7. 成功指标

- 进入 `implement-code` 和 `review-code` 的 CR worktree 均有可验证的最新 trunk ancestry 事实。
- 可证明安全的 `behind-clean` 场景能够通过显式 ff-only 同步解决；不可证明安全的场景保持零覆盖并给出结构化阻断。
- 因旧 trunk 直到最终 merge 才发现的冲突和由此触发的重复测试、评审、审批显著减少。
- workspace 同步事实全部落在既有 journal/audit，未出现第二套 transaction、ledger、状态机或远端分支发布路径。
- Agent、Pipeline、Skill、crctl、版本化脚本和 README 的职责边界通过静态契约测试持续成立。

# 8. 依赖与风险

- **依赖**：Tools 当前 repository/worktree resolver、`classifyRepoWorkspace`、`gitRun/gitMust`、durable-tx `workspace` operation、audit、checkpoint、release-subjects、`workspace inspect/ensure/cleanup` 和 code-implementation reviewLoop。
- **风险 R-01：把 ahead-only 错判为 stale**。fresh 必须以“trunk 是 CR HEAD 的祖先”为核心判据，正常 CR 独有提交不得被阻断。
- **风险 R-02：同步覆盖本地工作**。只有基础 workspace healthy、clean 且 HEAD 是 trunk 祖先时允许 ff-only；其他场景全仓 preflight 硬失败。
- **风险 R-03：fetch 后事实变化**。sync 必须在锁内 preflight，并在每仓写入前重核 trunk、HEAD、branch 和 dirty 状态；漂移时停止，不使用旧事实继续。
- **风险 R-04：多仓部分完成被误当作失败回滚**。journal 明确记录每仓进度；恢复只向前，不通过 reset/revert 制造补偿风险。
- **风险 R-05：review gate 同步后证据失效**。同步后不得直接进入 review-code，必须重建实现验证、测试报告和 checkpoint，再重新执行 freshness 与评审。
- **风险 R-06：职责扩散**。契约测试必须约束 Pipeline、Skill、Agent 和 README 不复制 crctl 算法，且 `ensureRepoWorkspace`、`pull-progress` 与 checkpoint 不被扩权。
- **风险 R-07：网络不可用**。无法 fetch 或确认 trunk 时返回 `unknown`/结构化失败并阻断；不使用过期 remote-tracking ref 猜测 fresh。

# 9. 范围排除

- 不建设通用分支同步平台、branch manager、daemon、后台扫描、缓存或数据库。
- 不自动 merge、rebase 或解决冲突；不执行 reset、clean、stash、force push、普通 merge 或补偿性 revert。
- 不修改状态机、CR ledger schema、approval、review annotation、release-subjects 或 merge 的既有事实源。
- 不检查、同步或发布远端 `requirement/{CR-ID}` 分支；该职责继续属于 push-progress、pull-progress 和 checkpoint。
- 不修改 `ensureRepoWorkspace` 的 register、resume、inspect 或 cleanup 行为。
- 不计算 ahead/behind commit count，不增加任意 ref/path/strategy 参数。
- 不新增 Agent、版本化转换脚本、feature flag、观察期账本、错误码 registry、插件系统或第二套事务抽象。
- 不增加 write-test-report、checkpoint 或审批前 freshness gate；本次只接入 implement-code 前和 review-code 前两处。
- 不承诺 macOS 全量验收矩阵；第一版覆盖当前 Windows 与 Linux 运行边界。
- 不修改 `specs/`、`delivery/` 或主工作区同名 CR 目录；本 PRD 只落盘在 CR-2026-043 的 knowledge-base requirement worktree。

# 10. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-16 | v0.1.0 | Ray | 初始草稿：freshness 分层、显式 ff-only 同步、双生命周期 gate、既有 reviewLoop 重放及职责边界 |

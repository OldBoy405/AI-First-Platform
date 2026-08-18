# Tools 本地业务门禁、远端发布与人工审批确认方案

> 文档性质：后续单一治理 CR 的 PRD/SDD 起草依据，不是在途 CR 实施产物，也不是另一份可执行事实源。
> 建议归属：Tools 门禁与审批体验治理 CR；本地/远端事实源分离与 TTY `y|yes` 兼容应在同一 CR 内完成，实际编号以 `requirement-register` 为准。
> 核对基线：`tools@custom/main`，commit `8f530589a0ae395f44760f4965a225ea9ac698d6`。
> 关联依据：`docs/adr/0003-worktree与tools安装基准分离.md`、`docs/adr/0004-执行层职责边界.md`、`docs/analysis/done/tools-cr-lifecycle-minimal-optimization-spec.md`、`docs/analysis/done/workspace-baseline-freshness-governance.md`。

## 1. 最终决策

采用一个边界清晰的模型：

```text
本地 clean committed source 决定业务证据是否有效；
远端 ref 决定 checkpoint、恢复或发布是否完成；
远端未同步不得伪装成本地证据漂移；
只有本地已审批内容真实变化，才允许业务状态回退；
四个人工审批统一由 crctl 接受大小写不敏感的 y 或 yes。
```

对应职责：

```text
业务判定：status / gate / review-record / approve
  -> 只读当前 Operational Workspace 与本地 CR worktree

同步与发布：checkpoint / resume / workspace freshness+sync / merge / writeback / archive
  -> 才读取远端，并继续使用现有 CAS、lease、journal、远端确认和恢复语义
```

本方案不新增状态、账本、snapshot schema、事务框架、公共 CLI、确认模块或第三方依赖。

## 2. 问题与根因

### 2.1 已核实现状

| 位置 | 当前行为 | 边界问题 |
|---|---|---|
| `runGateChecks` | 状态、文件、评审、审批和测试门禁主要读取当前 workspace | 已基本是本地门禁，不应加入远端读取 |
| `buildReleaseSubjects` | 读取本地 HEAD/artifact，同时 fetch 并要求远端 requirement ref 等于 HEAD | 评审 snapshot 依赖网络和 checkpoint 时机 |
| `verifyReleaseSubjects` | 同时检查本地 HEAD/artifact 与远端 requirement ref | 本地证据漂移和发布滞后共享结果通道 |
| `approveAndAdvance(code)` | 审批前调用混合 verifier | 本地证据未变也可能因远端滞后拒绝审批 |
| `mergeCr` | 把 verifier 的 `kind=code/task` 统一视为 release drift | 远端未 checkpoint 可能错误触发 `code-approved -> developing` |
| `mergeCr` per-repo prepare | 已自行 fetch 远端 trunk/requirement ref，并做 prepare、lease 和确认 | merge 已拥有远端发布检查，不需要本地 verifier 重复检查 |
| `checkpointCr` | 已拥有 source commit、requirement ref 发布、KB metadata、远端确认和恢复 | 可直接作为唯一远端 checkpoint 深原语 |
| `workspace freshness/sync` | 读取 origin trunk，做 ancestry 分类与 ff-only 同步 | 属于远端 trunk 新鲜度预检，不是状态或审批门禁 |
| `cmdApprove` | 四个 TTY stage 共用 `answer.trim().toLowerCase() !== 'yes'` | `YES` 可用，常见的 `Y/y` 会进入既有 reject 回退 |

### 2.2 根因

`verifyReleaseSubjects` 同时回答了两个失败语义不同的问题：

1. 当前本地内容是否仍是被评审和审批的内容。
2. 该内容是否已经发布到远端 requirement ref。

本地内容漂移意味着评审/审批证据失效；远端未同步只意味着发布未完成。将两者压成同一个 `kind=code`，使同步问题错误进入业务状态机。

### 2.3 用户可观察症状

- 网络不可用或远端 ref 暂时落后时，已有完整本地证据仍无法 review/approve。
- 本地已经 `code-approved`，审批提交尚未 checkpoint 时，merge 可能把远端滞后当成 code drift 并回退到 `developing`。
- 同一事实有时被描述为状态漂移，有时被描述为 remote ref drift，恢复入口不一致。
- 审批人在 TTY 输入 `Y/y` 时，四个 stage 都会执行现有 reject 权威回退。

## 3. 权威事实与核心不变量

### 3.1 术语

| 术语 | 定义 |
|---|---|
| Operational Workspace | 当前实际读写 CR 阶段产物的 knowledge-base checkout；merge 前通常为 knowledge-base CR worktree |
| CR worktree | `resolveRepositories` 根据 `dir-graph.yaml#repositories` 解析的 active repo `requirement/{CR-ID}` worktree |
| 本地业务事实 | 当前 Operational Workspace 中的 status、review、approval、test evidence、repo HEAD 和受控 artifact |
| 发布事实 | 远端 requirement/trunk ref、checkpoint metadata 与 merge/writeback/archive 的远端确认结果 |
| 本地漂移 | 当前本地 HEAD 或受控 artifact 不再等于 signed snapshot 描述的事实 |
| 发布滞后 | 本地事实有效，但远端 requirement ref 缺失或不等于当前本地 HEAD |
| 交接边界 | Pipeline、runner、Owner 或机器变化，后继执行者不能继续复用同一已验证本地 workspace |

### 3.2 生命周期事实源

| 阶段 | 业务权威 | 远端职责 |
|---|---|---|
| 注册后至 merge 前 | Operational Workspace + `crctl` 内部解析的 CR worktrees | checkpoint、协作和恢复 |
| review/approve | 本地 review evidence、approval、repo HEAD、artifact digest | 保存副本供平台或协作者读取，不决定审批有效性 |
| merge prepare/publish | signed snapshot + 当前本地 worktree 先做业务校验 | requirement source、trunk base、lease publish 和远端确认 |
| merge finalize 后至 archive | Transaction Workspace + journal + origin-confirmed trunk | writeback/archive 发布与恢复 |
| archived | origin-confirmed archive commit 与归档账本 | 团队共享终态 |

### 3.3 核心不变量

1. `crctl gate`、`advance` 目标门禁、`review-record` snapshot 构造和四个 `approve-*` 门禁不得 fetch 或读取 remote-tracking ref。
2. Pipeline 只传 `cr_id + operational_workspace`；完整 repository/worktree map 只由 `resolveRepositories` 解析。
3. release snapshot 必须绑定各 active repo 本地 CR worktree 的 clean committed HEAD 和受控 artifact digest。
4. snapshot 构造和重核都必须复用 `classifyRepoWorkspace`；只有 `classification=healthy` 才允许继续。
5. knowledge-base 的 reviewed SHA 必须是当前 HEAD 祖先，且区间内只能出现既有 metadata 白名单路径；其他 active repo HEAD 必须精确等于 reviewed SHA。
6. 远端 requirement ref 与本地 HEAD 不一致不得直接判定 signed snapshot 失效，也不得触发 `code-approved -> developing`。
7. 只有本地 code/source/TASK 漂移且 merge 尚无 trunk publish 时，才允许复用既有 release-drift 回退。
8. PRD/SDD 本地漂移继续返回 `APPROVED_ARTIFACT_DRIFT`；任一 trunk publish 后的 source 漂移继续硬阻断。
9. checkpoint、merge、writeback、archive 的 CAS、lease、journal、远端确认和恢复语义不得削弱。
10. merge 必须先完成全仓 publication preflight，全部通过后才允许生成任何 prepare candidate。
11. Pipeline 内连续节点原样传递同一个 `operational_workspace`，不得从主 checkout、远端 ref 或目录约定重新猜路径。
12. 阶段终点 checkpoint 是 Pipeline 完成条件，不是业务状态 gate；失败不得回滚已审批状态。
13. 四个 TTY 审批共用 `cmdApprove` 的同一判断：trim 后、大小写不敏感的 `y|yes` 表示批准；其他输入保持现有 reject 语义。

## 4. 逻辑架构与模块职责

| 模块 | 应拥有 | 不应拥有 | 本方案落点 |
|---|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 | 只传 `cr_id + operational_workspace`，不判断 SHA |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 复制 Skill 算法、手写账本操作 | 声明 checkpoint 交接顺序并传递同一 workspace |
| Skill | 业务判断、编排步骤、输入输出、失败语义 | 原子账本逻辑、重复实现 crctl | 解释 local drift/publication lag，不计算 SHA |
| crctl | 状态、门禁、CAS、受控账本写入、审计、原子提交 | 业务设计判断、LLM 评审结论 | 分离本地 evidence 校验和远端发布事务；统一 TTY 判断 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性转换 | 状态推进、人工审批 | 本方案零改动 |
| README | 人读流程总览 | 另一份可执行细节事实源 | 只解释事实源、交接条件和恢复入口 |

不新增公共模块。现有深接口足够：

- `classifyRepoWorkspace`：本地 worktree 健康分类。
- `buildReleaseSubjects`：构造本地 code review snapshot。
- `verifyReleaseSubjects`：重核本地 signed snapshot。
- `checkpointCr`：发布本地 CR workspace 到远端 checkpoint。
- `mergeCr`：执行全仓 publication preflight 与现有 merge saga。

## 5. 已经解决的基础设施

以下能力直接复用，不在本次重建。

| 能力 | 当前实现 | 本次处理 |
|---|---|---|
| Operational/Installation Workspace 分离 | ADR-0003 + workspace resolver | 复用，不增加目录发现规则 |
| repository/worktree map | `dir-graph.yaml#repositories` + `resolveRepositories` | 保持唯一仓库和路径来源 |
| workspace 健康分类 | `classifyRepoWorkspace` | 供 local snapshot 构造和重核复用 |
| 状态机与 gates | Tools `dir-graph.yaml` + `gates.json` + `runGateChecks` | 状态和声明不变，保持本地读取 |
| review-record | annotation + review-loop + traceability 原子落盘 | 仅调整 code snapshot 的事实来源 |
| approve/reject | TTY/Ed25519、evidence digest、approval+status 同提交、审计、恢复 | 全量复用，不把 push 纳入审批事务 |
| release-subjects v1 | repo SHA + PRD/SDD/plan/TASK digest | schema 不变，改为本地 clean worktree 构造和重核 |
| checkpoint | source commit、lease push、KB metadata、latest-checkpoint、恢复 | 远端 requirement 发布和交接唯一入口 |
| workspace freshness/sync | origin trunk fetch、ancestry、ff-only、journal、audit | 保留为远端 trunk 新鲜度预检 |
| merge saga | prepare、commit-tree、逐仓 lease publish、rebuild、finalize、恢复 | 复用，仅修正 publication lag 前置分类 |
| writeback/archive | Transaction Workspace、candidate、manifest、CAS、lease、cleanup | 零协议改造 |
| durable transaction | lock、journal、recoverable write-set、fault recovery | 不新增第二套事务层 |
| 受控 Git | `gitRun`/`gitMust`、`shell:false`、固定 argv | 复用 HEAD、branch、clean、ref 和 ancestry 查询 |
| CRLF 与摘要 | Node 标准库、CRLF -> LF、SHA-256 helper | 算法不变，不引入依赖 |
| 测试 fixture | crctl、checkpoint、merge、freshness 的现有 bare remote fixture | 只扩现有测试 |

## 6. 本次应复用的最小改造

### 6.1 Pipeline 只传业务指针

Pipeline 上下文只保留：

```yaml
execution_context:
  cr_id: CR-YYYY-NNN
  operational_workspace: /absolute/runtime/path/to/kb-cr-worktree
```

- requirement Pipeline 直接复用 `crctl register` 返回的 knowledge-base worktree。
- architecture/code Pipeline 的首个 Skill 调用一次现有 `crctl workspace inspect {cr_id}`，消费其复用既有 `resolveOperationalWorkspace` 返回的单一 `operationalWorkspace` authority path；不从 `resources[]` 猜 knowledge-base repo。
- `workspace inspect` 只增加该结构化结果字段，不新增命令、resolver 或持久化 schema。
- worktree 缺失或 authority 异常时中止并指向既有 `/resume`；业务 Skill 不自动 fetch/ensure。
- 后继节点原样传递 `operational_workspace`。
- 完整 repo map 仍由每个 `crctl` 深原语内部解析；`implement-code` 如需多仓路径，只消费 `crctl workspace inspect/ensure` 的结构化结果，不自行拼路径。

### 6.2 `buildReleaseSubjects` 只构造本地 snapshot

保留接口和 release-subjects v1 schema：

1. 解析 active repositories。
2. 对每仓调用 `classifyRepoWorkspace(ctx, repo, cr)`；非 `healthy` 结构化硬失败。
3. 读取本地 HEAD，写入现有 `reviewed-source-sha`。
4. `remote-ref` 继续写 `refs/heads/requirement/{CR-ID}`，仅表示预期发布分支名，不证明远端存在或已同步。
5. 继续按现有路径排序、CRLF -> LF 和 SHA-256 规则计算受控 artifact digest。
6. 删除 fetch、origin 存在性和 `remote == HEAD` 判定。

不新增 `local-source-sha`、`published-source-sha`、snapshot v2 或 publication 字段。

### 6.3 `verifyReleaseSubjects` 只重核本地漂移

保留 `{ok:true}` / `{ok:false, kind, details}` 合同和 `code|task|prd|sdd` 分类：

- snapshot 形状与 active repo 集合正确；
- 每仓 `classifyRepoWorkspace(...).classification=healthy`；
- non-KB repo 当前 HEAD 精确等于 reviewed SHA；
- KB repo reviewed SHA 是当前 HEAD 祖先；
- KB reviewed SHA 后只允许现有白名单：`approval.yml`、`cr.md`、`traceability.yml`、`review-loop.yml`、`change-requests/_backlog.yml` 和 `review-annotations/`；
- PRD/SDD/plan/TASK/_index 文件集合与 digest 未变；
- 不 fetch，不读取 remote-tracking ref，不返回 `remote-ref-drift`。

白名单保持原位和内容不变，不抽成配置、registry 或新 helper。

### 6.4 `approve-code` 只消费本地证据

`approveAndAdvance(code)` 继续执行现有流程：

1. 从 `review-annotations/code.yml` 读取机器注入 snapshot。
2. 调用纯本地 `verifyReleaseSubjects`。
3. 通过后原样复制 snapshot 到 `approval.yml#code.release-subjects`。
4. 计算 approval evidence digest。
5. 将 `approval.yml + cr.md` 同批提交，进入 `code-approved`。

网络不可用或远端 requirement ref 未更新不影响审批。真实本地漂移仍以 `RELEASE_SUBJECT_DRIFT` 零写入拒绝。

### 6.5 merge 先全仓 publication preflight

`mergeCr` 在既有 merge lock 内按两遍处理。

第一遍只读预检：

1. 读取 `code-approved` 与 signed snapshot，并调用本地 `verifyReleaseSubjects`。
2. 本地 code/TASK 漂移按既有规则回退或阻断；PRD/SDD 漂移继续硬阻断。
3. 对所有 active repo fetch origin，读取当前 local HEAD、remote requirement source 和 remote trunk。
4. 在内存构造 `publicationFacts[] = {repo, localHead, remoteSourceSha, trunkSha}`。
5. 任一 source ref 缺失，返回 `MERGE_SOURCE_MISSING`。
6. 任一 `remoteSourceSha != localHead`，返回 `RELEASE_REMOTE_NOT_PUSHED`，附 `repo/head/remote/recoverCommand=crctl checkpoint ...`。
7. 新事务的 publication preflight 失败时，`payload.repos` 不得出现 prepared candidate，状态保持 `code-approved`。

第二遍复用现有 saga：

- 只有全仓通过后，才使用同一批内存冻结 SHA 进入首次 prepare。
- 首次 prepare 成功后，继续由现有 journal 持久化 `baseSha/sourceSha/mergeSha`；已有 candidate/publish 的 journal 按既有恢复语义续跑，不清空或重建事务事实。
- 预检前进程退出直接重跑，不新增 publication journal 字段。
- prepare/publish/finalize、lease、rebuild、远端确认和 partial publish 恢复算法不变。

merge 不重复实现 remote ahead/diverged/history-rewritten 分类。调用者先按 recoverCommand 执行 checkpoint，再由 checkpoint 的既有 `CHECKPOINT_REMOTE_ADVANCED`、`CHECKPOINT_REMOTE_DIVERGED`、`CHECKPOINT_REMOTE_HISTORY_REWRITTEN` 细分恢复动作。

### 6.6 阶段终点 checkpoint 是完成合同

| Pipeline | 阶段终点顺序 | 失败语义 |
|---|---|---|
| requirement-authoring | `approve-requirement -> push-progress` | `onFail=abort`，保持 `requirement-approved` |
| architecture-design | `approve-tech-design -> push-progress` | `onFail=abort`，保持 `tech-design-reviewed` |
| code-implementation | `approve-code -> push-progress` | `onFail=abort`，保持 `code-approved` |

- requirement 的 PRD 草稿 checkpoint 继续可选。
- architecture 的 `auto_push_after_sdd` 输入删除，终点 checkpoint 不可跳过。
- code 的任务 checkpoint 继续可选；review 前和 PASS 后的既有强制 checkpoint 保留；审批后 checkpoint 从 `skip` 改为 `abort`。
- checkpoint 失败只重跑同一命令，不重新审批，不新增 `checkpoint-pending` 状态。
- 下一 Pipeline 的本地业务节点不重复设置远端 gate。
- 跨 runner/Owner/机器必须由 resume/pull 校验 checkpoint；merge 由 publication preflight 兜底。

该约束是 Pipeline 完成条件和交接合同，不改变状态机。

### 6.7 freshness 只收敛职责和名称

保留实现、节点位置和路由算法，只把语义收敛为“远端 trunk 新鲜度预检”：

- 继续读取 origin trunk 并分类 `fresh/behind-clean/diverged/unknown`。
- 只对 `behind-clean` 执行既有 ff-only sync。
- CR 分支与 trunk 互不为祖先时继续 `diverged -> manual`，不自动 merge/rebase。
- fetch/sync 失败可以中止 Pipeline 节点，但不得修改 status、approval、review verdict 或 reviewLoop attempt。
- `runGateChecks`、`approve-*` 和本地 release verifier 不得调用 freshness。
- 本次不移动 freshness 节点，不新增 local-trunk-only 模式，不修改同步算法。

### 6.8 TTY 确认只改共享入口

四个审批 stage 已汇聚到 `cmdApprove`，生产代码只改一处判断和 prompt：

```js
if (!['y', 'yes'].includes(answer.trim().toLowerCase())) {
```

- `Y/y/yes/YES/YeS` 和带前后空白的等价输入批准。
- 空输入、`N/n/no` 和其他文本继续执行现有 reject 权威回退。
- prompt 改为“输入 y 或 yes 才会写入 approval.yml [y/N]”。
- TTY 检查、evidence、gate、审计、reject 回退、grant 验签、`--resign` 和 approval 原子提交全部不变。
- 不新增 `isAffirmative` helper、配置、输入字典或确认依赖。

## 7. 失败分类与恢复语义

| 类别 | 是否业务证据失效 | 状态动作 | 恢复入口 |
|---|---:|---|---|
| workspace missing/dirty/wrong-branch/path-unregistered | 未形成可信 snapshot | 不推进 | 修复本地 workspace 后重跑当前命令 |
| 本地 non-KB HEAD 或 KB 非白名单路径漂移 | 是 | approve 前零写入；merge 零 publish 时回退 `developing` | 重建测试/review/approval |
| plan/TASK/_index 漂移 | 是 | 同本地 code drift | 重建测试/review/approval |
| PRD/SDD 漂移 | 是，且不能由代码审批覆盖 | 保持并硬阻断 | 回到需求/架构审批链 |
| remote source missing | 否 | 保持 `code-approved` | checkpoint 后重跑 merge |
| remote source 不等于 local HEAD | 否 | 保持 `code-approved` | checkpoint；由其细分 pull/manual |
| remote advanced/diverged/history rewritten | 不自动判断业务证据 | 保持当前状态并阻断 | 复用 checkpoint 的既有分类和恢复动作 |
| trunk advanced before publish | 本地审批不一定失效 | 状态不回退 | 复用 merge rebuild/prepare |
| 任一 trunk publish 后 source drift | 高风险 | 保持 blocked | 恢复原 ref 后续跑原事务；新改动拆新 CR |
| checkpoint 网络/lease/事务失败 | 否 | 保持本地状态 | 重跑同一 recoverCommand |
| freshness fetch/sync 失败 | 否 | 零状态、审批、评审、轮次变化 | 修复远端/本地事实后重跑预检 |
| TTY `y|yes` | 否 | 进入既有批准事务 | `approveAndAdvance` |
| TTY 其他输入 | 属于未批准 | 执行既有 reject 回退 | 按 rerunHint 回修后重新审批 |

## 8. PRD 编写依据

### 8.1 功能需求

- **FR-01 本地业务权威**：merge 前的 status、review、approval、test、release snapshot 和 artifact 门禁只读取当前 Operational Workspace 与本地 CR worktree。Pipeline 只传 `cr_id + operational_workspace`，repo map 由 crctl 解析。
- **FR-02 本地 release snapshot**：`review-record --stage code` 从 `classifyRepoWorkspace=healthy` 的本地 worktree HEAD 构造 release-subjects，继续使用 v1 schema 和现有 artifact digest。origin 缺失、网络不可用或远端 ref 落后不得阻止构造。
- **FR-03 本地审批重核**：`approve-code` 只重核本地 repo HEAD、KB metadata 白名单和受控 artifact。真实本地漂移必须零写入拒绝；publication lag 不得使审批失败。
- **FR-04 发布滞后不回退状态**：merge 在任何 prepare candidate 前完成全仓 publication preflight。远端 requirement ref 缺失或不等于当前 local HEAD 时，返回结构化发布错误并保持 `code-approved`。
- **FR-05 真实漂移继续受控处理**：本地 code/source/TASK 相对 signed snapshot 漂移且 merge 零 trunk publish 时，继续复用 release-drift 回退到 `developing`。PRD/SDD 漂移和 partial publish 后漂移继续硬阻断。
- **FR-06 强制 checkpoint 交接**：三个 Pipeline 在审批后必须完成 checkpoint 才算 Pipeline 完成。checkpoint 失败保持本地审批状态，重跑同一命令恢复，不新增业务状态或审批事务内 push。
- **FR-07 freshness 职责收敛**：`workspace freshness/sync` 继续读取 origin trunk，但只作为远端 trunk 新鲜度预检；不得被状态 gate、approve 或本地 release verifier 调用，不得修改业务证据。
- **FR-08 Pipeline workspace 连续性**：requirement 使用 register 返回路径；architecture/code 入口消费 `workspace inspect` 通过既有 authority resolver 返回的 `operationalWorkspace`；后继节点原样传递。异常时中止并进入既有 resume 流程。
- **FR-09 TTY 人工审批确认**：四个 TTY stage 在共享 `cmdApprove` 接受 trim 后、大小写不敏感的 `y|yes`。其他输入和非 TTY/grant/resign 语义不变。
- **FR-10 最小实现**：复用现有 workspace classifier、release-subjects、checkpoint、merge saga、durable transaction、受控 Git 和测试 fixture；不新增状态、账本、schema、公共命令、事务层或依赖。

### 8.2 非功能需求

- **NFR-01 命令级离线确定性**：已有 clean committed source 时，status/gate/review-record/approve 的本地业务判定不访问网络。包含 checkpoint/freshness 的完整 Pipeline 不承诺端到端离线。
- **NFR-02 Fail closed**：workspace 非 healthy、HEAD/文件不可读或 snapshot 形状非法时硬失败，不得降级为空 snapshot 或 pass。
- **NFR-03 行尾一致性**：artifact digest 继续先执行 CRLF -> LF。
- **NFR-04 零状态机变化**：保持当前 15 个具名状态 + `(new)`、28 条声明转移、wildcard 展开 50 条口径。
- **NFR-05 零 schema 迁移**：release-subjects、approval、review annotation 和 checkpoint ledger schema 不变。
- **NFR-06 跨平台**：Windows/Linux 继续使用 `spawnSync(..., {shell:false})` 与现有路径身份校验。
- **NFR-07 可恢复性**：远端失败只通过现有 checkpoint/merge recoverCommand roll-forward，不手改账本或 force ref。
- **NFR-08 最小实现成本**：不增加缓存、watcher、daemon、数据库、队列、registry、provider 或 adapter。

### 8.3 验收标准

1. origin 不存在或不可用时，所有 local worktree healthy 且 source 已提交，code review snapshot 构造成功。
2. 任一 repo dirty、wrong-branch、missing 或 path-unregistered 时，snapshot 零写入失败。
3. origin requirement ref 落后本地 HEAD 时，本地 snapshot 未漂移则 approve-code 成功。
4. non-KB 本地 HEAD 在 review 后改变，approve-code 返回 local drift，approval/cr.md 零写入。
5. KB reviewed SHA 后只有现有 metadata 白名单提交时重核通过；出现非白名单路径时失败。
6. plan/TASK/_index 增删或 digest 漂移时本地重核失败；LF/CRLF 仍等价。
7. PRD/SDD 漂移继续返回 `APPROVED_ARTIFACT_DRIFT`。
8. 新 merge 事务中任一 repo remote source 缺失或不等于 local HEAD 时，merge 在首次 prepare 前失败，`payload.repos` 无 candidate，status 保持 `code-approved`；已有 journal 仍按既有恢复合同处理。
9. 上一场景执行 checkpoint 后重跑 merge，可以进入既有 prepare/publish/finalize。
10. remote advanced/diverged/history rewritten 由 checkpoint 返回既有分类；merge 不复制 ancestry 算法、不 force。
11. 本地 code/TASK drift 且零 trunk publish 时，仍走唯一 release-drift 回退；已有 publish 时保持 blocked。
12. freshness 失败不改变 status、approval、review evidence 或 reviewLoop attempt。
13. 三个阶段终点 checkpoint 均 `onFail=abort`；失败时已审批状态不回退，重跑 checkpoint 不要求重新审批。
14. architecture 终点不再受 `auto_push_after_sdd` 控制；requirement 草稿和 code task checkpoint 仍可选。
15. architecture/code 入口通过 `workspace inspect` 的 `operationalWorkspace` 字段取得 authority path；该字段复用既有 resolver，异常时不猜路径、不自动 fetch。
16. 四个 TTY stage 对 `Y/y/yes/YES/YeS` 和带空白等价输入进入现有批准事务。
17. 空输入、`N/n/no` 和其他文本继续触发既有 reject 权威回退。
18. 非 TTY 无 grant 仍返回 `APPROVAL_REQUIRES_HUMAN`；grant 和 `--resign` 不受影响。
19. 状态机、gates、release-subjects v1、approval schema 和 durable transaction 无新增类型。
20. 现有 checkpoint、merge、writeback、archive、workspace resolver 和审批回归全绿。

## 9. SDD 编写依据

### 9.1 技术落点

| 文件/模块 | 最小变化 |
|---|---|
| `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | build/verify 复用 `classifyRepoWorkspace` 并移除 remote 判定；merge 增加全仓内存 publication preflight |
| `skills/shared/crctl/scripts/crctl.mjs` | `cmdApprove` 一处接受 `y|yes` 并更新 prompt；workspace inspect 复用既有 resolver 返回 `operationalWorkspace`；approve/merge dispatch 保持既有状态处理 |
| `pipeline-templates/requirement-authoring.pipeline.json` | 审批后新增强制 checkpoint；草稿 checkpoint 仍可选 |
| `pipeline-templates/architecture-design.pipeline.json` | 首节点取得 operational workspace；移除 `auto_push_after_sdd`；审批后 checkpoint 强制 |
| `pipeline-templates/code-implementation.pipeline.json` | 首节点取得 operational workspace；审批后 checkpoint 改为 `onFail=abort`；其余 checkpoint/freshness 位置不变 |
| `pipeline-templates/_index.yml` | 同步实际节点数 |
| `skills/develop/review-code/SKILL.md` | 描述本地 healthy committed source，不复制 snapshot 算法 |
| 四个 `approve-*` Skill | 说明 TTY `y|yes`；不读取 stdin、不复制判断、不调用 push |
| `skills/shared/crctl/SKILL.md` | 更新 TTY 合同与 local/publication 边界 |
| `skills/sync/push-progress/SKILL.md` | 从“可选节点”收敛为按 Pipeline 位置区分可选草稿与强制交接 |
| `skills/sync/workspace-freshness/SKILL.md` | 改称远端 trunk 新鲜度预检，明确零状态语义 |
| `skills/writeback/merge-feature-branch/SKILL.md` | publication lag 保持状态并指向 checkpoint |
| `README.md`、`ARCHITECTURE.md`、ADR-0004 | 只同步人读边界、交接条件和恢复入口 |

### 9.2 接口合同

- **`buildReleaseSubjects(ctx, cr)`**：输入输出与 v1 schema 不变；逐仓要求 `classifyRepoWorkspace(...).classification=healthy`；只读取本地 branch/clean/HEAD 和受控 artifact；不 fetch、不要求 origin 存在、不读取 remote-tracking ref。
- **`verifyReleaseSubjects(ctx, cr, snapshot)`**：输入输出与 drift kind 不变；`ok=false` 只代表本地 workspace、source 或 artifact 失效；不返回 `remote-ref-drift`；KB metadata 白名单不变。
- **`mergeCr(ctx, input)`**：公开接口不变；新事务在本地 verifier 通过后先收集并验证全仓 `publicationFacts`；source missing 返回 `MERGE_SOURCE_MISSING`，source 不精确等于 local HEAD 返回 `RELEASE_REMOTE_NOT_PUSHED`；全仓通过后才进入首次 prepare；已有 journal 按既有恢复合同续跑，不新增 journal 字段。
- **`cmdApprove(ws, cr, gates, flags)`**：CLI 参数和 stage 集合不变；TTY answer 以 `['y', 'yes'].includes(answer.trim().toLowerCase())` 判定批准；false 分支继续复用 audit、`REJECT_ROLLBACK`、`performAdvance` 和 `APPROVAL_DECLINED_ROLLED_BACK`；grant、resign 和非 TTY 分流位置不变。

### 9.3 最小测试矩阵

只扩现有测试文件：

| 测试 | 增量覆盖 |
|---|---|
| `crctl.test.mjs` | local build/verify、workspace 非 healthy、remote stale 不阻断 approve、KB 白名单、TTY `y|yes` 参数化 |
| `merge-tx.test.mjs` | remote missing/stale 全仓零 prepare、checkpoint 后重跑、真实 drift 与 partial publish 回归 |
| `checkpoint-tx.test.mjs` | existing remote advanced/diverged/history rewritten 分类继续成立；Pipeline checkpoint prompt 不复制算法 |
| `pipeline-structure.test.mjs` | 三个阶段终点 checkpoint 顺序与 `onFail=abort`、architecture 输入删除、节点数同步 |

不新增端到端 Pipeline runner、网络模拟框架或新 fixture 层。

### 9.4 兼容、迁移与回滚

- release-subjects v1 与 approval/checkpoint schema 不变，不批量迁移历史 CR。
- `developing` 及更早状态直接采用新本地门禁。
- `code-reviewing` 可重跑 review-code 刷新本地 snapshot。
- `code-approved` 若 snapshot 与本地 worktree 一致，只需 checkpoint 后 merge，不因 remote lag 强制重新审批。
- 已进入 merge 且已有 trunk publish 的 CR 使用激活前 tools 完成，避免跨版本切换事务语义。
- TTY 是向后兼容扩展：既有 `yes/YES` 不变，新增 `y/Y`。
- 实施前只读兼容检查复用现有 `upgrade-check`；默认不扩 CLI。
- Pipeline/Skill/README 文本和 TTY 判断可独立回滚，不需要数据迁移。
- local verifier/merge 分类回滚会恢复旧的远端依赖或误回退风险，但 schema 仍兼容。
- 已启动 merge journal 必须使用启动该事务的 tools 版本完成，不跨版本回滚事务实现。

## 10. 建议实施切分

每项形成可独立评审和回滚的提交，不创建总控框架。

1. **TASK-01：冻结失败向量**：增加 local valid + remote stale 的 approve/merge 红测试，以及 `y/Y` 当前进入 reject 的 TTY 红测试。
2. **TASK-02：TTY affirmative 扩展**：在 `cmdApprove` 一处接受 `y|yes`，更新 prompt，扩现有 TTY fixture。
3. **TASK-03：release-subjects 本地化**：build/verify 复用 `classifyRepoWorkspace`，删除 remote 判定，保持 schema 和 KB 白名单。
4. **TASK-04：merge publication preflight**：在现有 merge lock 内先全仓冻结和校验 publication facts，全部通过后再进入既有 saga。
5. **TASK-05：Pipeline/Skill 采纳**：收敛 operational workspace 传递、三个终点 checkpoint、freshness 名称和 Skill 结果解释；同步索引与结构测试。
6. **TASK-06：架构文档与回归**：修订 ADR-0004、ARCHITECTURE、README，运行现有 crctl/checkpoint/merge/writeback/archive 回归。

## 11. 明确不做

- 不新增 `approval-published`、`checkpoint-pending` 或 remote freshness 状态/账本。
- 不新增 snapshot v2、publication registry、verifier registry 或 mode 参数。
- 不新增 context resolver；Pipeline 复用 `workspace inspect`。
- 不把完整 repo map 固化进 Pipeline 或 Agent。
- 不把 checkpoint 合并进 approve 的原子事务。
- 不新增 local commit CLI，不拆分 checkpoint 的 commit/push 职责。
- 不让 merge 自动 checkpoint，不让 Pipeline/Skill 计算 SHA 或 ancestry。
- 不让下一 Pipeline 通过远端 gate 重新判定本地业务状态。
- 不移动 freshness 节点，不新增自动 merge/rebase 或 local-trunk-only 模式。
- 不把 publication error 写入 review annotation、approval 或 traceability。
- 不因网络失败消耗 reviewLoop attempt。
- 不修改 writeback/archive 发布协议。
- 不批量改写历史 CR。
- 不让四个 approve Skill 各自解析 stdin。
- 不新增确认 helper、prompt 配置、多语言字典或依赖。
- 不借本次改造改变 reject、grant、resign 或非 TTY 安全边界。

## 12. 成功标准

- 因 remote requirement ref 落后但本地内容未变导致的审批失败或状态回退为 0。
- publication lag 的恢复动作 100% 指向 checkpoint/pull/manual，不重新 review/approve。
- 本地 source/artifact 漂移仍 100% 被现有审批/merge 门禁拦截。
- 三个跨 Pipeline 阶段终点均只有 checkpoint complete 才算完成。
- 新增公共 CLI、状态、账本、schema、事务模块和第三方依赖数量均为 0。
- 四个 TTY stage 对 `Y/y/yes/YES` 的接受率为 100%，其他输入的既有回退语义不变。

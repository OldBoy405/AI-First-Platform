---
id: CR-2026-044-prd
type: PRD
cr-ref: CR-2026-044
title: Tools 本地业务门禁、远端发布与人工审批确认方案
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-16T23:35:01+08:00
updated: 2026-08-16T23:42:00+08:00
---

# 1. 概述

当前 Tools 的 release snapshot 校验同时回答两个语义不同的问题：本地内容是否仍是被评审的内容，以及该内容是否已发布到远端 requirement ref。现有 `buildReleaseSubjects` 会 fetch 并要求远端 requirement ref 等于本地 HEAD，`verifyReleaseSubjects` 也会把远端 ref 滞后归入 code drift。这使网络不可用、checkpoint 尚未完成或远端 ref 暂时落后时，本地完整有效的评审和审批证据仍可能被拒绝，甚至在 merge 前错误触发 `code-approved -> developing` 回退。

本 CR 建立清晰边界：

1. status、gate、review-record、approve 的业务证据只由当前 Operational Workspace 与各仓本地 CR worktree 决定。
2. checkpoint、resume、workspace freshness/sync、merge、writeback、archive 才读取远端发布事实。
3. 远端 requirement ref 缺失或滞后只表示发布未完成，不表示本地评审证据失效，也不得触发业务状态回退。
4. 只有本地已审批 source、TASK 或受控 artifact 真实漂移时，才沿用既有回修或硬阻断语义。
5. 四个人工审批阶段在共享 TTY 入口统一接受 trim 后、大小写不敏感的 `y|yes`。

本 CR 只调整既有能力之间的职责边界，不建设新框架。

# 2. 目标逻辑架构

## 2.1 Ponytail 优先级

设计和实施必须按以下顺序选择方案，并在首个足够方案处停止：

1. 复用现有能力；
2. Node 标准库；
3. 原生 Git/文件 API；
4. 已有依赖；
5. 一行代码；
6. 最小新增代码。

不得为未来可能出现的发布、审批或 Pipeline 场景预建通用 verifier registry、publication registry、adapter、provider、缓存、daemon、数据库或第二套事务框架。

## 2.2 模块职责边界

| 模块 | 应该拥有 | 不应该拥有 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 复制 Skill 完整算法、手写账本操作 |
| Skill | 业务判断、编排步骤、输入输出和失败语义 | 手写原子账本逻辑、重复实现 `crctl` |
| `crctl` | 状态、门禁、CAS、受控账本写入、审计、原子提交 | 业务设计判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性转换 | 状态推进、人工审批 |
| README | 人读流程总览 | 另一份可执行细节事实源 |

上述边界必须由现有契约测试或最小增量静态检查持续约束；不得只写在说明文档中。

# 3. 已经解决的基础设施

以下能力已经存在，本 CR 只复用，不复制、不替换：

| 已有能力 | 当前职责 | 本 CR 的复用方式 |
|---|---|---|
| Operational/Installation Workspace 分离 | 解析实际业务工作区与 tools 安装位置 | 继续作为所有 Pipeline 和 Skill 的路径基础 |
| Repository/worktree resolver | 从目标 workspace 的 `dir-graph.yaml#repositories` 解析 active repo、trunk 与 CR worktree | 作为 repo map 和路径的唯一来源 |
| `classifyRepoWorkspace` | 分类 missing、dirty、wrong-branch、path-unregistered、healthy 等本地状态 | release snapshot 构造与重核统一复用；仅 healthy 可继续 |
| 状态机与 gates | `dir-graph.yaml` 和 `gates.json` 声明合法转换与证据门禁 | 状态与转换数量保持不变，不引入 publication 状态 |
| review-record 与 approval | annotation、review-loop、traceability、approval 与 status 的受控写入 | 保留既有证据摘要、原子提交、驳回回退和签名审批 |
| release-subjects v1 | repo reviewed SHA、预期 remote ref 名、受控 artifact digest | schema 不变，只收窄 snapshot 构造和重核的事实来源 |
| checkpoint | source commit、requirement ref 发布、lease、远端确认、metadata 与恢复 | 作为远端 requirement checkpoint 的唯一深原语 |
| workspace freshness/sync | origin trunk 新鲜度分类、ff-only 同步、journal 与 audit | 保留为远端 trunk 预检，不进入本地业务门禁 |
| merge saga | prepare、commit-tree、逐仓 lease publish、rebuild、finalize 与故障恢复 | 只增加首次 prepare 前的全仓 publication preflight |
| writeback/archive | Transaction Workspace、CAS、lease、manifest、远端确认与清理 | 协议和恢复语义保持不变 |
| Durable transaction | lock、journal、recoverable write-set 与只向前恢复 | 不新增 WAL、事务协议或补偿层 |
| 受控 Git 与摘要 | `gitRun/gitMust`、`shell:false`、CRLF 到 LF、SHA-256 | 继续承担 HEAD/ref/ancestry 查询和 artifact 摘要 |
| 现有 bare remote 测试 fixture | 覆盖 crctl、checkpoint、merge、freshness 等行为 | 只扩现有测试文件，不创建新 fixture 框架 |

# 4. 本次应复用的最小改造

| 最小改造 | 归属 | 说明 |
|---|---|---|
| release snapshot 本地化 | 现有 workspace transaction 模块 | `buildReleaseSubjects` 与 `verifyReleaseSubjects` 复用 `classifyRepoWorkspace`，删除 fetch 和远端 ref 相等判定，保持 v1 schema |
| merge publication preflight | 现有 `mergeCr` | 在首次 prepare 前一次性收集所有 active repo 的本地 HEAD、远端 requirement source 与 trunk SHA；全部通过后才进入既有 saga |
| Operational Workspace 连续传递 | 现有 Pipeline 与 `workspace inspect` | Pipeline 只传 `cr_id + operational_workspace`；完整 repo map 仍由 resolver 解析 |
| 阶段终点 checkpoint | 三条现有主 Pipeline | requirement、architecture、code 在审批后 checkpoint 完成才算 Pipeline 完成；失败保持已审批状态并重跑 checkpoint |
| freshness 语义收敛 | 现有 Skill/Pipeline/README | 保持节点位置和同步算法，只明确其是远端 trunk 新鲜度预检，失败不改业务证据 |
| TTY affirmative 扩展 | 共享 `cmdApprove` | 一处判断接受 `y|yes` 并更新 prompt，四个 stage 共用；其他审批语义不变 |
| 最小文档与测试更新 | 现有 Skill、README、ARCHITECTURE、ADR 与测试 | 只同步边界、交接条件、恢复入口和行为回归，不复制实现算法 |

本次新增公共 CLI、状态、账本、snapshot schema、事务模块、版本化转换脚本和第三方依赖的数量必须均为 0。

# 5. 用户故事

- **US-01 需求/开发负责人**：已有 clean committed 本地事实时，希望在网络不可用或远端 requirement ref 滞后时仍能完成 status、gate、review-record 与 approve 的业务判断。
- **US-02 代码评审与审批人**：希望 release snapshot 精确绑定本地被评审 source 和受控 artifact；只有真实本地漂移才使证据失效。
- **US-03 发布执行者**：希望 merge 在生成任何 candidate 前确认所有 active repo 的本地 HEAD 已发布到远端 requirement ref，并在未发布时指向 checkpoint 恢复。
- **US-04 CR 协作者**：希望 Pipeline 连续节点始终使用同一个 Operational Workspace；换 runner、Owner 或机器时通过 checkpoint/resume 显式交接。
- **US-05 人工审批人**：希望四个人工审批在 TTY 中接受常见的 `y/Y/yes/YES`，同时保留非 TTY、grant、resign、驳回回退和证据门禁的安全边界。
- **US-06 Tools 维护者**：希望改造复用既有 resolver、classifier、checkpoint、merge saga、durable transaction 和测试 fixture，不维护第二套发布或事务实现。

# 6. 功能需求

## FR-01 本地业务权威

1. merge 前的 status、gate、review-record、approve 只读取当前 Operational Workspace 与各 active repo 的本地 CR worktree。
2. 上述业务路径不得 fetch、读取 remote-tracking ref 或以 origin 是否存在决定证据有效性。
3. Pipeline 只传递 `cr_id + operational_workspace`；完整 repository/worktree map 由 `resolveRepositories` 在 `crctl` 深原语内部解析。
4. workspace 缺失、路径身份异常或本地事实不可读时 fail closed，不得改从主 checkout、远端 ref 或目录约定猜测。

## FR-02 本地 release snapshot 构造

1. `review-record --stage code` 构造 release-subjects 前，必须对每个 active repo 调用既有 `classifyRepoWorkspace`；只有 `classification=healthy` 才可继续。
2. snapshot 的 `reviewed-source-sha` 来自各仓本地 CR worktree 的 clean committed HEAD。
3. `remote-ref` 字段继续写既有 `refs/heads/requirement/{CR-ID}`，仅表示预期发布分支名，不证明远端存在或已同步。
4. 受控 artifact 继续按路径字典序、CRLF 到 LF 和 SHA-256 规则计算；文件集合与 v1 schema 不变。
5. origin 不存在、网络不可用、远端 requirement ref 缺失或滞后均不得阻止 snapshot 构造。

## FR-03 本地 signed snapshot 重核

1. `verifyReleaseSubjects` 必须校验 snapshot 形状、active repo 集合、本地 workspace healthy、source SHA 与受控 artifact digest。
2. non-KB repo 当前 HEAD 必须精确等于 reviewed SHA。
3. knowledge-base repo 的 reviewed SHA 必须是当前 HEAD 祖先；reviewed SHA 后只允许以下既有 metadata 白名单：`change-requests/{CR-ID}/approval.yml`、`cr.md`、`traceability.yml`、`review-loop.yml`、`change-requests/_backlog.yml` 以及 `change-requests/{CR-ID}/review-annotations/` 前缀。该精确集合保持在现有 verifier 原位，不抽成配置或 registry，不增加新路径。
4. PRD、SDD、plan、TASK 和 `_index.yml` 的集合与 digest 必须保持一致；PRD/SDD 漂移继续使用既有 `APPROVED_ARTIFACT_DRIFT` 分流。
5. verifier 不 fetch、不读取 remote-tracking ref、不返回 `remote-ref-drift`；`ok=false` 只表示本地 workspace、source 或 artifact 失效。

## FR-04 approve-code 只消费本地证据

1. `approveAndAdvance(code)` 继续从 `review-annotations/code.yml` 读取机器注入 snapshot，并调用本地 `verifyReleaseSubjects`。
2. 重核通过后继续把同一 snapshot 写入 `approval.yml#code.release-subjects`，并纳入既有 evidence/approval digest 与原子提交。
3. 真实本地 source、TASK 或 artifact 漂移必须以既有结构化错误零写入拒绝。
4. 网络不可用、origin 缺失或远端 requirement ref 未更新不得阻止代码审批。

## FR-05 merge 全仓 publication preflight

1. 新 merge 事务必须在既有 merge lock 内、首次 prepare 前先完成本地 signed snapshot 重核。
2. 本地 code/TASK 漂移且尚无 trunk publish 时，继续复用唯一的 release-drift 回退；PRD/SDD 漂移继续硬阻断；任一 trunk publish 后的 source 漂移继续 blocked。
3. 本地重核通过后，对全部 active repo fetch origin，在内存中冻结 `{repo, localHead, remoteSourceSha, trunkSha}`。
4. 任一远端 requirement source 缺失时返回 `MERGE_SOURCE_MISSING`；任一 `remoteSourceSha != localHead` 时返回 `RELEASE_REMOTE_NOT_PUSHED`，并提供 repo、head、remote 和 checkpoint recoverCommand。
5. publication lag 失败时 CR 保持 `code-approved`，不得触发 `code-approved -> developing`；`payload.repos` 中不得出现 prepared candidate。
6. 只有全仓 preflight 通过后，才允许使用同一批冻结 SHA 进入现有 prepare/publish/finalize saga。
7. 远端 advanced/diverged/history-rewritten 的细分和恢复继续由 checkpoint 既有算法负责；merge 不复制 ancestry 分类、不自动 checkpoint、不 force。

## FR-06 Operational Workspace 连续性

1. requirement Pipeline 继续使用 register 返回的 knowledge-base worktree 作为 `operational_workspace`。
2. architecture/code Pipeline 入口调用现有 `workspace inspect {cr_id}`，由既有 authority resolver 返回单一 `operationalWorkspace` 字段。
3. 后续连续节点必须原样传递该路径；不得从 `resources[]`、主 checkout、远端 ref 或目录命名重新猜测。
4. `implement-code` 需要多仓路径时，只消费 `workspace inspect/ensure` 的结构化结果，不自行拼接路径。
5. worktree 缺失或 authority 异常时中止，并指向既有 resume 流程；业务 Skill 不自动 fetch/ensure。

## FR-07 阶段终点 checkpoint 合同

1. requirement、architecture、code 三条 Pipeline 均必须在审批后完成 checkpoint，才算该 Pipeline 完成。
2. requirement 的 PRD 草稿 checkpoint 与 code 的 TASK checkpoint继续保持可选；审批后阶段终点 checkpoint 不可跳过。
3. architecture 删除 `auto_push_after_sdd` 输入；code 的审批后 checkpoint 从 `onFail=skip` 改为 `onFail=abort`。
4. checkpoint 失败不得回滚已审批状态，不得要求重新审批；修复远端或 lease 事实后重跑同一 recoverCommand。
5. 跨 runner、Owner 或机器的后继执行必须通过 checkpoint/resume 校验交接；merge publication preflight 作为最终兜底。
6. checkpoint 仍是 Pipeline 完成条件，不进入 approve 原子事务，也不新增 `checkpoint-pending` 状态。

## FR-08 freshness 职责收敛

1. `workspace freshness/sync` 保持现有节点位置、origin trunk fetch、四类结果、ff-only 同步、journal 与 audit 语义。
2. freshness 只作为远端 trunk 新鲜度预检；不得被 status gate、approve 或本地 release verifier 调用。
3. fetch/sync 失败可以中止当前 Pipeline 节点，但不得修改 CR status、approval、review verdict 或 reviewLoop attempt。
4. 本 CR 不移动 freshness 节点，不新增 local-only 模式，不改变同步算法，不自动 merge/rebase。

## FR-09 TTY 人工审批确认

1. 四个审批 stage 共用 `cmdApprove` 的同一判断：`['y', 'yes'].includes(answer.trim().toLowerCase())`。
2. `Y/y/yes/YES/YeS` 及带前后空白的等价输入进入既有批准事务。
3. 空输入、`N/n/no` 和其他文本继续执行既有 reject 权威回退；不得改成无副作用取消。
4. prompt 必须明确“输入 y 或 yes 才会写入 approval.yml [y/N]”。
5. TTY 检查、evidence gate、audit、reject rollback、grant 验签、`--resign` 与 approval/status 原子提交保持不变。
6. 不新增确认 helper、配置、输入字典或依赖。

## FR-10 最小采用与文档边界

1. 只修改实现目标直接涉及的既有 crctl 模块、Pipeline、Skill、测试及人读文档。
2. Skill 只解释 local drift 与 publication lag 的业务分流，不计算 SHA、不复制 Git/事务算法。
3. Pipeline 只声明节点顺序、workspace 传递、checkpoint 完成条件、reviewLoop 与失败中止。
4. README、ARCHITECTURE 和 ADR 只同步事实源边界、交接条件与恢复入口，不复制可执行算法。
5. 不新增 Agent、公共 CLI、状态、账本、snapshot schema、事务层、版本化脚本或第三方依赖。

## FR-11 兼容启用与在途 CR

1. `developing` 及更早状态的 CR 在新版本启用后直接采用新的本地 snapshot 构造与重核规则，不迁移历史账本或 schema。
2. `code-reviewing` 状态的 CR 必须重跑 `review-code`，以当前 healthy committed 本地 source 重新生成 review snapshot 后再审批。
3. `code-approved` 状态的 CR 若既有 signed snapshot 与当前本地 worktree 一致，只需先完成 checkpoint，再进入 merge，不得仅因远端 publication lag 强制重新评审或审批。
4. 已进入 merge 且已有 candidate 或任一 trunk publish 的事务，必须使用启动该事务的 Tools 版本按原 journal 合同完成；不得跨版本重建、清空或改变事务语义。
5. 不批量改写历史 release-subjects v1、approval、review annotation、checkpoint ledger 或 merge journal；启用前只复用现有 `upgrade-check` 做只读兼容检查，不新增 CLI。

# 7. 非功能需求

- **NFR-01 离线确定性**：已有 clean committed source 时，status、gate、review-record 与 approve 的本地业务判定不访问网络。包含 checkpoint/freshness 的完整 Pipeline 不承诺端到端离线。
- **NFR-02 Fail closed**：workspace 非 healthy、HEAD/文件不可读、snapshot 形状非法或仓集合漂移时硬失败，不得降级为空 snapshot、pass 或远端猜测。
- **NFR-03 行尾一致性**：所有 artifact 摘要继续先执行 CRLF 到 LF；逐行解析使用 `split(/\r?\n/)`，跨行解析失败硬失败。
- **NFR-04 状态机稳定**：保持 15 个具名状态 + 注册前 `(new)`、28 条声明转换、wildcard 展开后 50 条的当前口径。
- **NFR-05 Schema 稳定**：release-subjects v1、approval、review annotation、checkpoint ledger 与 durable transaction journal 不迁移。
- **NFR-06 可恢复性**：远端失败只通过既有 checkpoint/merge recoverCommand 向前恢复，不手改账本、不 force ref、不清理 journal。
- **NFR-07 跨平台**：Windows/Linux 继续使用 `spawnSync(..., {shell:false})`、现有路径身份校验和原生 Git argv。
- **NFR-08 最小成本**：不增加缓存、watcher、daemon、数据库、队列、registry、provider、adapter 或生产依赖。

# 8. 验收标准

- **AC-01（FR-01/02）**：origin 不存在或网络不可用时，只要所有本地 CR worktree 为 healthy 且 source 已提交，`review-record --stage code` 能构造 release-subjects v1；调用轨迹中无 fetch 或 remote-tracking ref 读取。
- **AC-02（FR-02）**：任一 active repo 为 dirty、wrong-branch、missing 或 path-unregistered 时，snapshot 零写入失败并返回对应本地 workspace 事实。
- **AC-03（FR-03/04）**：远端 requirement ref 落后本地 HEAD、但本地 snapshot 未漂移时，`approve-code` 能通过本地重核并进入既有批准事务。
- **AC-04（FR-03/04）**：non-KB 本地 HEAD 在 review 后改变时，approve 返回 local source drift，`approval.yml` 与 `cr.md` 零写入。
- **AC-05（FR-03）**：KB reviewed SHA 后，仅修改 `approval.yml`、`cr.md`、`traceability.yml`、`review-loop.yml`、`change-requests/_backlog.yml` 或 `review-annotations/` 前缀时重核通过；逐一增加任一白名单外路径时均返回本地 code drift，且白名单未新增配置或 registry。
- **AC-06（FR-03）**：plan、TASK 或 `_index.yml` 增删/摘要漂移时返回 task drift；LF/CRLF 等价；PRD/SDD 漂移继续返回既有 artifact drift 分类。
- **AC-07（FR-05）**：新 merge 事务中任一 repo 的 remote source 缺失时返回 `MERGE_SOURCE_MISSING`，首次 prepare 前失败，状态保持 `code-approved`，无 candidate。
- **AC-08（FR-05）**：任一 repo 的 remote source 不等于 local HEAD 时返回 `RELEASE_REMOTE_NOT_PUSHED` 和 checkpoint recoverCommand，状态保持 `code-approved`，无 candidate。
- **AC-09（FR-05）**：执行 checkpoint 后重跑 AC-07/08 场景，可以进入既有 prepare/publish/finalize；remote advanced/diverged/history-rewritten 仍由 checkpoint 返回既有分类，merge 不复制 ancestry 算法。
- **AC-10（FR-05）**：本地 code/TASK drift 且零 trunk publish 时仍走唯一 release-drift 回退；PRD/SDD 漂移和已有 trunk publish 后 source drift 保持硬阻断。
- **AC-11（FR-05）**：已有 merge journal 继续按既有 candidate/publish 恢复合同续跑，不清空、不重建已持久化事务事实；新 preflight 不新增 journal 字段。
- **AC-12（FR-06）**：requirement 使用 register 返回的 worktree；architecture/code 从 `workspace inspect.operationalWorkspace` 取得 authority path并在连续节点原样传递，异常时不猜路径、不自动 fetch/ensure。
- **AC-13（FR-07）**：三个 Pipeline 均满足“审批后 checkpoint 且 `onFail=abort`”；失败时已审批状态不回退，重跑 checkpoint 不要求重新审批。
- **AC-14（FR-07）**：architecture 不再声明 `auto_push_after_sdd`；requirement PRD 草稿 checkpoint 和 code TASK checkpoint 仍可选；Pipeline `_index.yml` 节点数同步。
- **AC-15（FR-08）**：freshness fetch/sync 失败不会改变 status、approval、review evidence 或 reviewLoop attempt；现有 fresh/behind-clean/diverged/unknown 与 ff-only 回归保持通过。
- **AC-16（FR-09）**：四个 TTY stage 参数化验证 `Y/y/yes/YES/YeS` 和带空白等价输入进入批准事务。
- **AC-17（FR-09）**：空输入、`N/n/no` 和其他文本继续触发现有 reject 回退；非 TTY 无 grant 仍返回 `APPROVAL_REQUIRES_HUMAN`；grant 与 `--resign` 回归不变。
- **AC-18（FR-10）**：静态契约检查证明 Agent、Pipeline、Skill、crctl、版本化脚本和 README 遵守第 2.2 节职责边界，且 Pipeline/Skill/README 未复制 Git、CAS、journal 或状态机算法。
- **AC-19（FR-10/NFR）**：状态机、gates、release-subjects v1、approval/checkpoint schema、durable transaction 与生产依赖清单无新增类型。
- **AC-20（全范围）**：现有 crctl、checkpoint、merge、writeback、archive、workspace resolver、freshness 与四阶段审批回归全部通过。
- **AC-21（FR-11）**：`developing` 及更早状态无需 schema 迁移即可采用新本地 verifier；`code-reviewing` 必须重跑 code review 生成当前 snapshot。
- **AC-22（FR-11）**：`code-approved` 且本地 snapshot 一致、远端 source 滞后时，checkpoint 后可继续 merge，期间不回退状态、不要求重新 review/approve。
- **AC-23（FR-11）**：已有 candidate 或 trunk publish 的 merge journal 由启动版本按原合同续跑；新版本不重建、清空或迁移该 journal，且启用前 `upgrade-check` 只读。

# 9. 成功指标

- 远端 requirement ref 滞后但本地内容未变导致的 review/approve 失败或状态回退为 0。
- publication lag 的恢复动作 100% 指向 checkpoint/pull/manual，不要求重新 review/approve。
- 本地 source、TASK 和 artifact 漂移仍 100% 被现有审批或 merge 门禁拦截。
- 三个跨 Pipeline 阶段终点均只有 checkpoint complete 才算完成。
- 新增公共 CLI、状态、账本、schema、事务模块、版本化脚本和第三方依赖数量均为 0。
- 四个 TTY stage 对 `Y/y/yes/YES` 的接受率为 100%，其他输入保持既有回退语义。

# 10. 依赖与风险

## 10.1 依赖

- Tools 当前 workspace resolver、`classifyRepoWorkspace`、`buildReleaseSubjects`、`verifyReleaseSubjects`、`checkpointCr`、`mergeCr`、durable transaction、`gitRun/gitMust` 与现有 bare remote fixture。
- 当前 release-subjects v1、approval evidence digest、KB metadata 白名单和 merge journal 恢复合同。
- requirement、architecture、code 三条 Pipeline 以及相关 approve、push-progress、workspace-freshness、merge-feature-branch Skill。

## 10.2 风险

- **R-01 把发布滞后误判为本地漂移**：本地 verifier 不得读取远端；远端精确相等检查只进入 checkpoint/merge 发布边界。
- **R-02 放松本地证据门禁**：snapshot 构造与重核必须先要求 `classifyRepoWorkspace=healthy`，并保留 source/artifact/白名单校验。
- **R-03 merge 产生部分准备事实**：publication preflight 必须覆盖全仓并在首次 prepare 前完成；全部通过后才进入既有 saga。
- **R-04 已启动事务跨版本切换**：已有 candidate/publish 的 merge journal 必须使用启动该事务的 tools 版本按既有合同完成，不在恢复中切换事务语义。
- **R-05 Pipeline workspace 漂移**：同一 Pipeline 连续节点原样传递 authority path；跨 runner/Owner/机器通过 checkpoint/resume 重新建立事实。
- **R-06 文档成为第二事实源**：README/ARCHITECTURE/ADR 只写边界与入口，具体算法和错误分类继续以 crctl、gates、Pipeline JSON 和 Skill 契约为准。
- **R-07 TTY 扩展破坏驳回安全边界**：只修改共享 affirmative 判断与 prompt；false 分支、grant/resign 和非 TTY 路径保持原实现。

# 11. 范围排除

- 不新增 `approval-published`、`checkpoint-pending` 或 remote freshness 状态/账本。
- 不新增 snapshot v2、publication/verifier registry、mode 参数或 context resolver。
- 不把完整 repo map 固化进 Pipeline 或 Agent，不让 Pipeline/Skill 计算 SHA 或 ancestry。
- 不把 checkpoint 合并进 approve 原子事务，不让 merge 自动 checkpoint。
- 不新增 local commit CLI，不拆分 checkpoint 的 commit/push 职责。
- 不移动 freshness 节点，不新增自动 merge/rebase、local-only 模式或新的同步算法。
- 不把 publication error 写入 review annotation、approval 或 traceability，不因网络失败消耗 reviewLoop attempt。
- 不修改 writeback/archive 发布协议，不批量改写历史 CR。
- 不让四个 approve Skill 各自解析 stdin，不新增确认 helper、配置或输入依赖。
- 不借本次改造改变 reject、grant、resign、非 TTY 或 Ed25519 安全边界。
- 不新增 Agent、版本化转换脚本、第三方依赖或第二套事务框架。

# 12. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-16 | v0.2.0 | Ray | 回修 B-01/B-02：冻结 KB metadata 精确白名单；补充 developing/code-reviewing/code-approved/已启动 merge 的兼容启用合同与 AC |
| 2026-08-16 | v0.1.0 | Ray | 初始草稿：本地业务权威、远端 publication preflight、Operational Workspace 连续性、阶段终点 checkpoint 与 TTY `y|yes` |

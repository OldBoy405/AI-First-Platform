# Tools archive、checkpoint、test 与 traceability 治理落地方案

> 分析日期：2026-08-12
> 分析对象：`C:/Users/GOBAO/Downloads/AI/tools`，分支 `custom/main`，基线 `8a2e6a1`
> 需求来源：[`tools-text-contract-audit.md`](./tools-text-contract-audit.md) 中 TCA-010/011/012/013/014/019
> 文档性质：跨 CR 治理落地总路线图，不是单个实施 CR；状态机、门禁、权限矩阵和 Git 白名单仍分别以 tools 仓 `dir-graph.yaml`、`gates.json`、`agent-skill-matrix.yml`、`rules.json` 为准。交付固定拆为 Archive、Checkpoint、Test、Traceability/feedback、静态治理五个顺序 CR，详见 §12。

## 1. 执行摘要

附件审计形成于 CR-2026-031 合入前后交界期，当前仓库已经发生关键变化，不能直接按原问题描述实施：

- **TCA-010（archive 四文件两次写）主体已解决**：当前 `crctl archive` 已通过 recoverable write-set 一次生成四账本、单 commit、lease push，并以 `cleanup-pending` 表达发布后清理未完成。
- **TCA-019（写入后 commit 失败不回滚）已具备可复用基础设施**：`durable-tx.mjs` 已提供 journal、目录锁、before/after hash、redo/rollback、commit trailer 恢复；approve、review-record、owner-set、register、merge、writeback、archive 已部分接入。
- **TCA-011 仍未解决**：checkpoint 仍由 Skill 手写逐仓 Git 算法，并逐仓调用 `checkpoint-add`；远端发布、批次事实与 backlog 投影不是一个可恢复事务。
- **TCA-012 仍未解决**：`crctl test` 只顺序写日志和报告骨架；模型随后另写分析、traceability，再单独 bump attempt，四者可能不一致。
- **TCA-013 仍未解决**：`feedback-writeback` 在终态调用明确禁止终态写入且没有 feedback 消费者的 `inbox-emit`，同时直接修改 baseline traceability，并建议手工创建空文件。
- **TCA-014 仍未解决**：`review-alignment` 声明 `readonly: true` 却要求写 traceability；`change-impact-analysis` 还假设 baseline存在实际并不存在的 `requirements[].reviews.*`/`summary.stale` schema。

| 原 TCA | 当前判定 | 本方案对应项 |
|---|---|---|
| TCA-010 | 主体已修；错误回显、正常归档 outbox 与文档语义可独立加固，严格 traceability gate 必须等待 baseline generator 先补齐证据 | ARC-01/03/04/05、Phase 1；ARC-02、Phase 4 |
| TCA-011 | 未修，且发现 KB checkpoint 元数据晚一轮 | CKP-01~07、Phase 2 |
| TCA-012 | 未修，另有 shell 拼接、受信执行权限暴露与证据覆盖问题 | TST-01~07、Phase 3 |
| TCA-013 | 未修，终态通知入口不可执行且没有合法消费者，baseline 写入也不受控 | TRA-08~10、Phase 4 |
| TCA-014 | 未修，另有 mtime、旧 merge 事实源和 schema 分叉 | TRA-01/02/06/07、Phase 4 |
| TCA-019 | 基础设施已具备，但 scoped 写链并未全部接入 | Phase 1~4 的 durable write/commit/recover |

本次不应再引入数据库、通用事务框架或新的 Pipeline Runner。最小正确路线是：

1. **复用已有 `durable-tx` 与 transaction workspace**，不再造事务层。
2. 新增四个窄接口：
   - `crctl checkpoint <cr>`：独占多仓 checkpoint Git saga，并原子替换单个 `latest-checkpoint` 当前快照；
   - `crctl test run/record <cr>`：真实执行与原子记账分离；
   - `crctl traceability-record <cr>`：接收 alignment机器检查参数或 feedback业务 payload，内部固定选择 generator并完成受控写；
   - 保留并小幅加固现有 `crctl archive <cr>`。
3. 新增/调整三个确定性 generator（test、alignment、feedback各一个）：
   - `build-test-record.mjs`；
   - `traceability-drift.mjs`；
   - `writeback-feedback.mjs`；
   - 同时增强现有 `writeback-traceability.mjs`，让测试和评审证据真正进入 baseline。
4. Skill 只做业务判断和一次深原语调用；Pipeline 只保留输入传递、节点顺序、reviewLoop 与失败路由；Agent 只保留意图路由。alignment Skill只选择 CR/stage并调用机器检查，不生成业务 payload。
5. 将 `test-report.md`、CR traceability 与 baseline traceability 从 guard 的 `ask`/未保护提升为 **crctl 独占写**，模型只能写 `.crctl/tmp/` 中的严格业务 payload；candidate 目录、manifest schema、generator 路径与输出目录均为 crctl 内部细节。

## 2. 当前实现与验证基线

### 2.1 已运行验证

在 tools 仓根目录实际执行：

| 验证 | 当前结果 | 能证明什么 | 不能证明什么 |
|---|---:|---|---|
| `lint-prompts --mode enforce` | 0 findings | R1-R9 当前规则未命中 | 不检查 checkpoint 批次原子性、终态事件、readonly 冲突、Pipeline 算法复制 |
| `check-skill-matrix` | 57 active Skill 通过 | active/owner/文档矩阵基本一致 | 不检查 Skill 是否直接写受控文件、frontmatter readonly 与正文行为 |
| `check-agents-contract` | 9 Agent 通过 | 不变式 1-3 | 脚本明确声明“不绕过 Skill 写受控文件”未静态检查 |
| writeback tests | 10/10 | candidate-only、增量追加、基本幂等 | 不验证测试/评审证据真的进入 baseline，不验证 trunk 缺失硬失败 |
| crctl tests | 253/253 | CR-2026-031 的 register/merge/writeback/archive/durable-tx 主链稳定 | `cmdTest` 没有完整行为回归；checkpoint 仅有单仓单写测试；feedback/drift 无实现测试 |
| Pipeline JSON parse | 8 个通过 | JSON 语法正确 | 不验证职责边界、参数传递、reviewLoop 语义 |

结论：当前绿灯是真实的，但只说明已有测试覆盖的实现自洽，不能作为 TCA-011/012/013/014 已解决的证据。

### 2.2 已解决且必须复用的基础设施

以下能力已经存在，本方案不得以 checkpoint/test/traceability “特殊”为由复制：

| 资产 | 路径 | 本次复用方式 |
|---|---|---|
| durable transaction | `skills/shared/crctl/scripts/lib/durable-tx.mjs` | 复用锁、journal、recoverable write-set、ledger rollback；仅增加 checkpoint/traceability 所需 operation payload 与 fault point |
| workspace/repository resolver | `.../lib/workspace-transactions.mjs` | 复用 repo、trunk、worktree、phase authority、transaction workspace 解析 |
| candidate manifest | `skills/writeback/scripts/lib.mjs` + `applyWriteback()` | 复用 path containment、before/after hash、blob、manifest digest；抽取私有校验函数供 test/traceability 使用，不另造 manifest 协议 |
| YAML 子集解析 | `.../lib/yaml-subset.mjs` | 所有账本与 traceability 解析复用；不得再写跨行正则降级路径 |
| release/fault 测试 fixture | `scripts/test/merge-fixture.mjs` | 扩展为 checkpoint、feedback、traceability baseline 测试夹具 |
| 双平台 CI | `.github/workflows/crctl-ci.yml` | 继续作为唯一完整 CI；补新增测试和 checker |

### 2.3 本次最小改造边界

| 模块 | 已解决基础设施 | 本次唯一最小新增 | 禁止重造 |
|---|---|---|---|
| Archive | `archiveCr()`、durable write-set、commit trailer、lease push、cleanup-pending | 错误回显、既有 archive outbox、待 TRA-03 后加结构 gate | 新 archive 命令、terminal v2、第二套归档事务 |
| Checkpoint | repository/worktree resolver、journal/lock/fault、Git 原生 ancestry/lease | 一个显式 `checkpointCr()` + 单个 `latest-checkpoint` 编辑器 + exact-head freshness | 通用 saga/phase runner、checkpoint 历史账本、status API、文件选择器 |
| Test run | Node `spawn`、resolver、Git diff/ls-files、标准库 SHA-256、现有审计 | argv plan、run manifest、有界流式日志与完整工作现场摘要的最小持久化 | 外部幂等键/exactly-once、shell 沙箱、executable registry、测试框架、日志服务/压缩协议、watcher/snapshot workspace、通用任务执行器 |
| Test record | durable write-set、现有 candidate bundle校验形态、YAML parser | 一个固定 generator + 一个显式 record handler | 外部 candidate API、新 manifest 协议、第二套 CAS/事务层 |
| Traceability | writeback candidate、Transaction Workspace、YAML parser、commit/push恢复、`review-record`机器注入能力、既有 code `release-subjects` | 非 code评审的固定 `input-subjects`、无 payload 的 alignment机器检查、feedback固定 generator + 一个窄 `traceabilityRecord()` handler | impact/stale新模型、通用 subject registry/glob配置、通用 YAML patch、generator registry/plugin、Skill 手写账本 |
| Pipeline/Skill/Agent | 现有 pipeline reviewLoop、Skill matrix与 crctl 状态机 | 删除复制算法并缩窄参数/权限 | 新 Pipeline Runner、Agent 状态映射、README 可执行副本 |

实现判断继续遵循：复用现有实现 > Node 标准库 > Git/文件系统原生能力 > 已安装依赖 > 一行实现 > 最小新增代码。只有至少三个真实处理器出现同一非平凡重复或同一恢复缺陷需三处修复，才允许从调用点向既有 `durable-tx.mjs` 提炼最小公共函数；本方案不预建接口层、provider、registry、plugin 或通用事务引擎。

## 3. 目标职责分配

| 层 | archive | checkpoint | test | traceability |
|---|---|---|---|---|
| Agent | 路由到 writeback/同步/测试/质量 Skill | 识别“保存/换机/移交”意图 | 选择 coding pipeline、测试责任人 | 识别 alignment/feedback意图 |
| Pipeline | 节点顺序、输入传递、失败中止 | 决定 checkpoint 节点是否可跳过 | `implement → test → repair` reviewLoop | writeback 顺序；不复制生成/落盘算法 |
| Skill | 前置业务判断、调用深原语、结果分类 | 提供 message，调用一次 `crctl checkpoint` | 组织命令计划、分析运行结果，以 `run-id + analysis` 调用一次 record | feedback产出业务判断 payload；alignment只选择 stage并调用一次无 payload的机器检查 |
| crctl | archive 状态/gate/账本/Git/恢复 | 全仓 Git、`latest-checkpoint` 当前快照、journal、审计 | 状态守卫、执行证据、固定 generator 选择、内部 candidate 校验、原子受控写 | 固定 generator 选择、scope/status/allowlist/CAS/commit/push/审计/恢复 |
| 版本化脚本 | 无 | 无；checkpoint 是 Git/账本事务 | 将 run manifest + 分析 payload确定性转换为内部 report/trace/review-loop candidate | alignment由 crctl固定机器事实转换为当前 drift 投影；feedback、baseline milestone 由业务 payload确定性转换 |
| README | 阶段说明和失败语义概览 | “一次保存全部 active repo” | 测试闭环概览 | in-flight 与 baseline 的关系 |

删除测试：若删除新增深模块，Git saga、恢复、候选校验和账本原子性会重新散落到多个 Skill/Pipeline，说明这些模块具有足够深度；不需要再加 repository interface、事务 provider 或 plugin 系统。

## 4. 全量问题清单

### 4.1 Archive

#### ARC-01（TCA-010，已基本解决）：四账本归档已收敛为单入口

- **现状证据**：
  - `skills/cr/cr-archive/SKILL.md` 只调用一次 `crctl archive`；
  - `workspace-transactions.mjs#archiveCr()` 对 `cr.md`、`_backlog.yml`、`_history.yml`、`_index.yml` 使用同一 recoverable write-set；
  - `archive-tx.test.mjs` 验证四账本同 commit、lease push、幂等重放和 cleanup-pending。
- **结论**：不新增 `archive-finalize`；当前 `archive` 就是应保留的深接口。附件中的“两次写入”问题已经过时。

#### ARC-02：归档前置只检查 traceability 文件存在，不检查“本 CR 段”与结构

- **位置**：`workspace-transactions.mjs#archiveCr()`。
- **具体行为**：只用 `existsSync(specs/{spec}/traceability.yml)` 判断追溯回写完成。
- **风险**：旧 spec 的 traceability 文件即使没有当前 CR milestone，也会通过 archive 前置；错误 `spec_id` 只要目录内存在文件，也可能误归档。
- **实施依赖**：本项不得先于 TRA-03 单独上线。当前 `writeback-traceability.mjs` 尚未把 tests、四类 reviews、approval 完整注入 baseline；若先收紧 gate，会让正常 CR 因 generator 无法产出所需结构而全部无法归档。
- **调整**：在同一个 traceability CR 中，先完成 TRA-03 并通过 generator 自检，再收紧 archive 前置。baseline不新增顶层或 milestone级 schema-version；archive只精确定位并严格校验当前 CR段，历史 milestones作为 opaque段不参与新结构校验。确定性验证：
  1. `spec-id` 与参数一致；
  2. `cr-history` 含当前 CR；
  3. `milestones` 中当前 CR 恰好一段；
  4. 该段包含当前 `merge-commits.yml` 的全部 repo；
  5. 测试、四类 review 与 approval 摘要存在且来源路径可解析。
- **实现位置**：复用 YAML parser 的纯校验函数；`cmdArchive` 先跑 archived gate，`archiveCr` 在事务内保留关键结构复核，防 TOCTOU。集成测试必须使用增强后的 generator 真实产物通过 gate，不手写一份只为测试通过的理想 traceability fixture。

#### ARC-03：cleanup 失败详情被 journal 保存但未返回调用者

- **位置**：`archiveCr()` 中 `payload.lastCleanupError`；`cr-archive/SKILL.md` 结果分类。
- **具体行为**：catch 会设置 `lastCleanupError`，但 `cleanup-pending` 返回对象不包含该字段；Skill 却声称可依据它处理。
- **风险**：出现非资源型异常时，返回 `phase=cleanup-pending, remaining=[]`，调用者不知道为何无法完成。
- **调整**：所有 complete/cleanup-pending 返回固定包含：`commit`、`lastCleanupError`、`remaining`、`preservedRefs`、`recoverCommand`。cleanup fault 测试断言错误码可见。

#### ARC-04：正常归档 commit 已成为权威，但缺少 Multica 实际消费的 `archive` outbox 投影

- **位置**：`cmdArchive()` 只写本地 audit；history 内有 notify-log，但没有在 origin 确认后产生 `event_kind=archive` 的 outbox。
- **已核实消费者**：Multica daemon 的 `server/internal/daemon/crevents.go` 会在配置 `MULTICA_CR_WORKSPACES` 时扫描 `{workspace}/.crctl/outbox/*.json` 并上报 `/api/daemon/cr-events`；`server/internal/governance/crsync.go` 接受 `archive`，将其按状态事件投影，`gate_projection.go` 在 `archived` 时结束 writeback pipeline run。
- **当前降级路径**：现有 archive commit subject 为 `archive CR-...`，不匹配 Multica commit fallback 的 `[cr] archive CR-...`；即使匹配，fallback 生成的 archive 事件也缺 `from_status/to_status/trigger`，不能直接完成合法状态投影。目前只能等待包含 `_history.yml` 的周期 snapshot reconcile 兜底。
- **调整**：仅对正常归档，在 archive commit 被 origin confirmed 后复用既有 outbox schema 发一次 `event_kind=archive`：`from_status=writing-back`、`to_status=archived`、`trigger=cr-archive`、`commit_sha=<真实 archive commit SHA>`。沿用现有 `(cr_id, commit_sha, event_kind)` 幂等键，不新增 `terminal` 事件类型、topic 或协议版本。outbox 失败只返回 warning，不回滚已发布 authority；canonical 事实仍在同一 archive commit 的 `_history.yml` 中，snapshot reconcile 继续作为兜底。
- **提前终止边界**：`rejected/withdrawn` 在进入终态时已经由 `crctl advance` 发出完整 `status` outbox；后续 archive 只搬移账本，不再发送第二个 archive/status 事件，避免伪造重复状态转换。

#### ARC-05：README 将“归档”和“清理”描述成一个全成全败动作

- **风险**：实际语义是“归档发布成功后，cleanup 可 pending”；错误认知会诱导手工删资源。
- **调整**：README 只写：`archive` 先发布终态事实，再安全清理；`cleanup-pending` 时 status 已终态，只能重跑同命令。不要复制 cleanup 分类算法。

### 4.2 Checkpoint

#### CKP-01（TCA-011）：Skill 拥有完整逐仓 Git 算法

- **位置**：`skills/sync/push-progress/SKILL.md#Step 1~3`。
- **具体实例**：Skill 手写 worktree 遍历、`add -A`、diff、commit、push、rev-parse、逐仓失败处理。
- **违反原则**：Skill 不应拥有 Git 算法；该算法也被四个 Pipeline prompt 重复。
- **调整**：Skill 收缩为一次调用 `crctl checkpoint {cr_id} [--message ...]` 与结果分类。`crctl checkpoint` 保留既有“保存全部未忽略变化”语义：只在 resolver 确认的当前 CR worktree 与 `requirement/{cr_id}` 分支运行；每仓在 commit 前纳入 tracked/untracked 的全部未忽略变化，不提供 `--files`、include/exclude glob、staged-only mode 或 checkpoint ignore 配置。
- **敏感文件边界**：仓库当前没有可复用 secret scanner，本次不新增依赖或内容扫描框架。crctl 在 `add -A` 前从 Git 状态取得本轮新增/修改的普通文件路径，先按 workspace-relative POSIX 路径执行固定规则，再只对这些文件检查私钥头；命中则在尚未修改 index 时返回 `CHECKPOINT_SENSITIVE_PATH`，整个 checkpoint 零 commit/零 push。固定路径规则为：basename `.env`、`.env.*`（明确放行 `.env.example`、`.env.sample`、`.env.template`），basename `id_rsa|id_dsa|id_ecdsa|id_ed25519`，以及任意层级后缀 `.aws/credentials`、`.config/gcloud/application_default_credentials.json`、`.netrc`、`.pypirc`；路径比较按 Git 路径的大小写精确语义，不做平台相关模糊匹配。内容规则仅匹配 `-----BEGIN ... PRIVATE KEY-----`。不拦截所有 `*.pem/*.key`，不识别通用 TOKEN/PASSWORD，不做熵扫描，不引入 gitleaks/trufflehog，不提供 `--allow-sensitive` 或例外配置。`.gitignore` 仍是项目特定临时文件与本地配置的第一道边界。

#### CKP-02（TCA-011）：逐仓 `checkpoint-add` 不是批次原子写

- **位置**：`crctl.mjs#cmdCheckpointAdd()`。
- **具体行为**：每次只 CAS `_backlog.yml` 一次并追加一个 repo；没有 batch-id、manifest、journal 或 commit。
- **风险**：第 N 仓写失败会留下同一轮的部分 repo；resume 无法区分“完整 checkpoint”和“半记录”。
- **调整**：删除公开 `checkpoint-add`，改为 `crctl checkpoint` 在所有 repo remote confirmed 后一次生成完整批次并写入。

#### CKP-03：旧 `checkpoints[]` 无限追加；新模型只需最近一次完整 checkpoint

- **位置**：`push-progress/SKILL.md` 与 `editCheckpointAdd()`。
- **风险**：旧实现无限追加，消费者可能取第一条/最后一条产生不同结论。运行时 reader 实际只需要最近一次完整 checkpoint；历史已存在于 Git，未完成事务恢复已存在于 durable journal，再建 `checkpoint-batches[] + latest 指针 + 兼容投影` 会形成重复事实源。
- **调整**：整个 CR 条目只保留一个可原子替换的当前快照：

```yaml
latest-checkpoint:
  batch-id: <sha256(cr-id + repository-graph-digest + 按 repo id 排序的 repo/source-sha/remote-ref) 前 16 位>
  repositories:
    - repo: <id>
      source-sha: <本轮内容 commit>
      remote-ref: refs/heads/requirement/<cr>
```

`batch-id` 是内容寻址标识，只由 `cr-id`、事务启动时的 repository graph digest，以及按 repo id 排序后的 `repo/source-sha/remote-ref` 组成；明确排除 `message`、actor、时间、本地路径和 journal txId。`latest-checkpoint` 也不持久化 `pushed-at/by/summary`，这些都可从 metadata commit 推导。它只标识当前完整 checkpoint 并支持幂等重放，不表示账本保留历史批次数组。相同 graph 与 source facts 重跑必须 `changed=false`，即使 message 不同也不得产生新 metadata commit；任一 repo source SHA 或参与仓图变化时才形成新 id。`latest-checkpoint` 每次整块替换，不追加；reader 只消费该映射；历史查询走 Git log，事务中间态只读 journal。首次成功执行新命令时，直接从本轮真实 repo source SHA 生成该映射，并删除旧 `checkpoints[]`、顶层 `remote-ref`、`last-push-at`、`last-push-by`，不永久双读、不维护兼容 projection。

#### CKP-04：knowledge-base checkpoint 元数据天然“晚一轮”

- **当前顺序**：先 push knowledge-base 分支，再执行 `checkpoint-add` 改 backlog；本轮元数据没有进入刚推送的 remote HEAD。
- **风险**：换机后恢复到远端分支时，可能只能看到上一轮 checkpoint 记录；下一次 push 才把上一次元数据带上。
- **调整**：深原语采用本轮恢复 HEAD + KB metadata commit：
  1. 创建任何 journal/source/metadata commit 前先执行 no-op 快速确认：读取现有 `latest-checkpoint`，fetch 全部参与仓，核对 graph digest、远端 freshness 与本地未忽略变化；全部未变时直接返回现有 checkpoint，`changed=false`，不创建 journal、不更新时间、不 push；
  2. 有真实变化时，各 repo 先形成并确认本轮恢复 HEAD；有业务变化的仓创建 source commit，clean 仓沿用当前 HEAD；
  3. 非 knowledge-base repo 先发布并精确确认 remote HEAD；
  4. knowledge-base 在自己的本轮恢复 HEAD 之上生成**只含 checkpoint 账本**的 metadata commit；
  5. 发布 knowledge-base metadata commit；
  6. `latest-checkpoint.repositories` 中 KB `source-sha` 固定为 metadata commit 的直接父提交。它表示“本轮 metadata 创建前已确认的 KB 恢复 HEAD”，不要求一定是纯业务内容 commit；只有其他 repo 变化时，该父提交可以是上一轮 metadata HEAD。

这样避免 commit 内容引用自身 SHA，也避免把上一轮 metadata HEAD误当作新业务变化导致 `M1 → M2 → M3` 空转。

#### CKP-05：多仓 push 没有持久化恢复状态，且通用“已发布”分类不足以证明 Checkpoint freshness

- **风险**：进程在第二仓 push 后退出，重跑无法可靠区分 push 成功响应丢失、远端被他人推进和真正未推。现有共享 `classifyRemoteCommit()` 把“candidate 是 remote 祖先”视为 confirmed，这适合证明 archive/writeback commit 已发布，但不足以证明 checkpoint 仍精确描述各仓当前恢复 HEAD。
- **调整**：在现有 durable journal 增加 `op=checkpoint`，逐仓记录 `prepared → committed-local → pushed → confirmed`，最后记录 `metadata-committed → metadata-pushed → complete`。不修改共享 `classifyRemoteCommit()` 对其他事务的既有语义；checkpoint 在生成 metadata 前增加 exact-head freshness 分类：
  - remote == source SHA：confirmed；
  - remote 是 source SHA 的祖先：本地 source 可按当前 remote SHA 做 lease fast-forward publish；push 后必须再确认精确相等；
  - source SHA 是 remote 的祖先且不相等：`CHECKPOINT_REMOTE_ADVANCED`，不写 metadata，提示先走 `pull-progress` 后重新 checkpoint；
  - 双方分叉：`CHECKPOINT_REMOTE_DIVERGED`，不自动 merge、不 force；
  - journal 已记录发布，但 remote 不再包含 source：`CHECKPOINT_REMOTE_HISTORY_REWRITTEN`。

对非 knowledge-base repo，完整 Checkpoint 的最终条件是 remote HEAD 精确等于 source SHA。knowledge-base repo 因其 remote HEAD 还包含随后生成的 metadata commit，最终条件单独定义为：metadata commit 是 remote HEAD，且记录的 KB source SHA 是该 metadata commit 的直接父提交。KB source SHA 表示 metadata 创建前的恢复 HEAD，不要求是纯业务 commit；不得把“任意祖先”解释为当前完整状态。

#### CKP-06：Pipeline 复制 checkpoint 算法

- **位置**：
  - `requirement-authoring.pipeline.json` checkpoint 节点；
  - `architecture-design.pipeline.json` checkpoint 节点；
  - `code-implementation.pipeline.json` 的任务、代码、审批 checkpoint 三个节点；
  - `resume-cr.pipeline.json` 的远端比对节点。
- **调整**：每个节点只保留输入、是否跳过、输出字段与 onFail。例如：

```text
执行 push-progress：cr_id={{inputs.cr_id}}，message=<阶段摘要>。
消费输出 batchId/repositories/phase；非 complete 按 Skill 失败语义中止。
```

具体 Git 命令、账本字段和恢复分类只存在于 crctl/Skill。

#### CKP-07：远端列表仍保留已删除的 status fallback 与旧 checkpoint 口径

- **位置**：`list-remote-checkpoints/SKILL.md`。
- **问题**：声称 cr.md 缺 status 时回退 backlog status，但当前 crctl 已永久删除该兼容；仍按单 repo `checkpoints[]` 与 remote SHA 相等判断。
- **调整**：状态只读 `cr.md`；checkpoint 只读取单个 `latest-checkpoint`。非 knowledge-base repo 要求 remote HEAD 与 source SHA 精确相等；knowledge-base 要求 remote HEAD 等于 metadata commit，且记录的 source SHA 是其直接父提交。任一仓远端超前或分叉均标记 drift，不把“仍是祖先”当作 synced。

### 4.3 Test

#### TST-01（新增，权限高风险）：`crctl test` 把受信代码执行能力伪装成普通账本命令

- **位置**：`crctl.mjs#cmdTest()`。
- **具体行为**：`spawnSync(command, { shell: true })` 执行调用者提供的任意字符串。
- **风险**：当前接口既有 shell 拼接注入风险，又因 dev/quality Agent 都可路由 `write-test-report` 而扩大代码执行能力。测试命令本身可通过 `node -e`、`python -c`、npm/make 脚本或项目测试代码执行任意逻辑；仅禁 shell executable 或做 executable allowlist不能形成安全沙箱。
- **调整**：
  - 改成 `crctl test run <cr> --plan <json>`；plan 中每条命令必须是 `argv: [executable, ...args]`，使用 Node 标准库 `spawn()` + `shell:false`，拒绝空 executable、空 argv 元素和 NUL；
  - cwd 不接受任意路径，由 active repository id 解析到当前 CR worktree并做 realpath containment；timeout 使用代码常量定义默认值与固定上下限，不提供 workspace/config扩展面，具体毫秒值在Phase 0 SDD中冻结并以边界测试锁定；日志记录 argv、cwd、exit code、signal、stdout/stderr；
  - stdout/stderr 由 `spawn()` 以字节流有界写入临时文件，以控制内存和输出上限；它们只是执行过程的临时捕获。首版只固定每 run 日志合计 50 MiB 的代码常量，不提供 plan/workspace 配置；不额外设置 per-stream 上限，避免正常单命令输出被过早截断。record 阶段按 UTF-8 文本读取，沿用现有字符串 candidate 与 durable write-set；非法 UTF-8 使用 Node 默认替换解码并记录 `decode-replacements=true` warning，不为罕见二进制输出扩展 Buffer 事务、Base64 或编码 registry；
  - run 日志合计写入达到 50 MiB 时终止当时正在写入的命令，保留已捕获前缀但明确 `outputLimitExceeded=true`、捕获字节数/hash、日志不完整，并机械形成 `TEST_OUTPUT_LIMIT_EXCEEDED` blocker；随后停止剩余命令并记 `skipped=prior-output-limit`。这是唯一输出上限，不存在 per-stream limit；这是可信记录的业务 block，`test run` exit 0，不宣称代码缺陷；不得把截断日志或未完整执行的命令判为 pass；
  - 临时原始日志的 hash/size 必须与 run manifest 精确一致后才能 record；record 将其解码为有界 UTF-8 人读文本，再由现有字符串 candidate/write-set按最终文本字节写入 canonical evidence；不新增二进制 write-set；
  - 不建 executable allowlist、package-script registry 或测试命令配置系统，也不把 argv/cwd 校验描述成安全沙箱；隔离依赖 runtime/container/OS 身份，不在本轮实现；
  - `test run` 明确定义为开发期受信代码执行能力，只允许 dev-agent 经 `write-test-report` 路由触发；quality-reviewer-agent 删除 `write-test-report` 调用权，只消费已经 canonical record 的测试证据。

#### TST-02（TCA-012）：日志、报告、traceability、轮次由四条路径写

- **位置**：
  - `cmdTest()` 顺序写 `test-evidence/*.log` 与 `test-report.md`；
  - `write-test-report/SKILL.md` 再编辑报告分析；
  - Skill 直接写 `traceability.yml#tests`；
  - `crctl attempt` 单独写 `review-loop.yml`。
- **风险**：任一阶段失败都可能形成“报告 pass、trace 仍 block”或 attempt 已 bump 但报告未完成。
- **调整**：分成两个公开深原语而非一个巨型命令：
  1. `crctl test run` 只在 `.crctl/tmp/test-runs/{run-id}/` 生成真实退出码 manifest 和临时日志，不写 canonical 文件；
  2. Skill 读取结果，形成严格业务分析 payload；
  3. Skill 以 `run-id + analysis` 调用一次 `crctl test record`；
  4. record 内部按固定映射调用 `build-test-record.mjs`，在 crctl 管理的事务临时目录生成文本 candidate，校验 generator SHA/allowlist/before-after hash及临时日志 hash/size后，以一次 durable write-set 写入报告、版本化 evidence 目录、traceability tests、review-loop。

不公开 `--candidate`、generator id/path、candidate 输出目录或 manifest schema；它们是 crctl 与固定版本化脚本之间的内部协议。

#### TST-03：现有 test-report 会覆盖上一轮，且中断运行不能伪装成完整证据

- **风险**：第二轮 `cmd-01.log` 覆盖第一轮，无法审计“第 1 轮失败、第 2 轮通过”；进程死在某条命令期间时，若把已完成命令和重跑结果拼接，会伪造一轮完整测试。
- **调整**：
  - crctl 在启动命令前生成 `run-id` 和 run 目录，流式写临时日志；全部命令结束后一次原子写 `state=complete` manifest。进程中断时 manifest 缺失或非 complete，已经足以禁止 record，不逐命令更新可恢复状态；
  - 进程中断留下的 run 保持 incomplete，禁止 record，也不从下一条自动续跑；调用方重新执行 `test run` 时产生新 run-id并从头运行；
  - 不增加外部 `run-key` 或 exactly-once 协议。Multica 虽有 `pipeline_node_run.id` 投影表，但当前迁移明确尚无 Runner，daemon 也未把该 ID 注入 Skill 环境；为成功响应丢失的罕见窗口新增跨层键传递不成立。重试可能重跑受信测试代码，这是当前最小方案的诚实边界；
  - canonical evidence 每轮使用 `test-evidence/{run-id}/cmd-01.log`；`test-report.md` 只展示 latest，并链接历史 attempts。traceability 与 review-loop 保存每轮 result、subject digest、report/evidence 路径；
  - 一个 `run-id` 只接受一个 analysis digest：同 run-id/同 analysis 幂等返回 `changed=false`；已 record 后换 analysis 返回 `TEST_RECORD_INPUT_MISMATCH`，未完成事务也不得替换 journal 输入；需要修正判断时重新运行，产生新 run-id。

#### TST-04：缺少 status、owner 与完整工作现场 freshness 守卫

- **现状**：`cmdTest()` 未确认 CR 为 `developing`，tester 缺失时回退当前 identity，也不绑定被测内容。
- **风险**：可在错误阶段生成 pass 报告；测试人责任错配；Pipeline 在 checkpoint 前运行测试，代码常有未提交变化，只记录各仓 HEAD 会漏掉 tracked/staged/deleted/renamed 与 untracked 内容漂移。
- **调整**：`test run/record` 都要求 status=`developing`，且 `owners.test.id` 与 assigned-at 完整、禁止 identity fallback。crctl 使用 Git 原生输出与 Node 标准库计算每个 active repo 的工作现场摘要：
  - `sha256(repo-id + HEAD SHA + git diff --binary HEAD + 排序后的未跟踪普通文件路径/内容 SHA-256)`；
  - tracked/staged/deleted/renamed 由 `git diff --binary HEAD` 覆盖；untracked 来自 `git ls-files --others --exclude-standard -z`，按 NUL 分隔路径字节排序；文件内容流式 SHA-256；
  - symlink 只记录 link target、不跟随；submodule 只记录 gitlink SHA、不递归；ignored 文件不进入摘要，与 checkpoint `git add -A` 边界一致；
  - run 前后各计算一次。测试过程改变任一摘要时，complete manifest 标记 `subject-mutated=true` 并机械形成 `status=block`；不 stash、不创建临时 commit或 snapshot workspace；
  - record 再计算摘要，必须与 run 完成后精确相等，否则 `TEST_SUBJECT_DRIFT`、零 canonical 写；
  - approve-code/gate 比对 test subject 与代码评审所消费的被测工作现场/后续 release-subjects，不允许仅凭相同 HEAD 接受旧 pass。

摘要是 crctl 捕获和验证的执行事实；Skill 不计算，generator 不读取 Git，只消费经验证的 manifest字段。

#### TST-05：模型分析段不是受控输入，且可伪造最终测试状态

- **现状**：注释要求模型只在 marker 后补充，但 guard 对 `test-report.md` 只是 `ask`，不是技术禁止；若新 analysis 允许自报 `status`，模型还可能把真实失败升级为 pass。
- **调整**：
  - 模型只写 `.crctl/tmp/test-analysis.yml`；generator 完整生成报告；`test-report.md` 与 `test-evidence/**` 加入 protectedPaths.deny，删除 marker 后直接编辑契约；
  - `test-analysis/v1` 只允许 TASK coverage、blockers、risks及固定 `repair-target=implement-code`，不得提供/覆盖 `status`、command result、subject SHA、tester、时间或日志路径；coverage 只允许 `covered|not-applicable`，缺失 TASK 由 generator 对照 `_index.yml` 机械形成 `TEST_TASK_COVERAGE_MISSING` blocker；
  - generator 机械推导最终状态，不作业务判断：仅当 run complete、全部 command pass、当前 `_index.yml` 每个 TASK 恰有一条 coverage、coverage 全为 `covered` 或带非空 reason 的 `not-applicable`、`blockers=[]` 且无 `disposition=blocker` risk 时为 pass，其余均为 block；
  - `missing` coverage、失败/超时/signal/launch error 自动形成机器 blocker；analysis 可因业务覆盖判断把全绿 run 降为 block，不能把真实失败升为 pass；
  - block 时至少有一条 repair instruction；`not-applicable` 必须有非空原因。Skill 拥有 coverage/blocker/risk 业务判断，版本化脚本只执行上述确定性组合，crctl 只验证 run 事实、schema、不变量并原子落盘。

#### TST-06：test 的 reviewLoop 输出与退出码契约不完整

- **位置**：Pipeline 要求 `blockers`、`repair-target`、`repair-instructions`，当前 `crctl test` 只返回 status/tester/runs，并在任一测试命令非零后 `process.exit(1)`。
- **风险**：Pipeline 的 `onFail=abort` 表示 Skill/基础设施异常，正常测试失败应由 `status=block` 驱动 reviewLoop；若 run/record 因业务 block 非零退出，失败证据会在 analysis/record 前被技术中止。
- **调整**：
  - `test run` 成功执行或有界终止 plan并持久化 complete run manifest后始终 exit 0；子命令非零、超时、signal、executable 不存在、输出超限均作为 command result，未触发 run 总输出上限时继续执行剩余命令并聚合 `status=block`；达到总上限时剩余命令标记 skipped；
  - plan/status/owner/worktree 非法、run 目录或证据无法持久化、进程中断导致 manifest 不完整等契约/基础设施错误才 exit 1；
  - `test record` 成功原子记录后即使 `status=block` 也 exit 0；schema、subject drift、事务恢复失败、`LOOP_EXHAUSTED` 等才 exit 1；
  - blockers/repair target/repair instructions 来自 analysis payload，经 generator 落盘；record 输出固定 `status/blockers/repairTarget/repairInstructions/attempt`，Pipeline 只消费这些字段。

#### TST-07：测试证据没有行为测试

- **现状**：253 个 crctl tests 中没有覆盖完整 `cmdTest` 的状态、覆盖、崩溃和重试矩阵。
- **调整**：新增独立 `test-record.test.mjs`，不要继续把所有案例堆进 `crctl.test.mjs`。

### 4.4 Traceability 与 feedback

#### TRA-01（TCA-014）：readonly 元数据与写入行为矛盾

- **位置**：`review-alignment/SKILL.md` 的 `readonly: true` 与“只读 + 写 traceability.yml”。
- **调整**：改为 `readonly: false`，但明确 Skill 不直接写受控文件；它只选择待检查的 stage并调用一次无 payload的 `traceability-record`。generator、scope、candidate和机器 finding 均不暴露为 Skill 输入。

#### TRA-02（TCA-014）：impact Skill建立在不存在的 baseline schema上

- **位置**：`review-alignment` 拟写当前 `drift[]`；`change-impact-analysis` 却要求写 `requirements[].reviews.*`、`change-log[]`和 `summary.stale`。
- **事实**：真实 baseline是 `milestones[].frs[]`加 milestone级 reviews/tests/approvals；没有顶层 `requirements[]`、per-requirement perspective、stale resolution或消费 gate，且 FR-ID脱离 milestone CR并不唯一。
- **调整**：本次退休 `change-impact-analysis`，从 quality Agent、skill matrix、Agent/Skill索引和 README能力表移除；不实现 impact kind、Git diff捕获、stale传播、change-log或 resolution生命周期。未来若出现真实需求，先以 `milestone CR + FR-ID`定义 requirement identity，并明确谁置 stale、谁重审、谁清除、哪个 gate消费，再单独立 CR。
- `traceability-drift.mjs`只负责 alignment当前投影。`drift[]`不是事件日志，也是 alignment唯一持久化投影：每个 CR/stage使用稳定 key `alignment:<CR-ID>:<stage>`，最多维护一个当前 finding；finding只由 crctl机器事实组成，按 `kind=artifact|repository` 和 `id`排序记录 `state`、changed/missing subjects。不持久化 `needs-review`、`suggested-skill`、`reason`或message；unknown本身已表达需要人工判断，命令响应只根据 `(stage, state)`临时推导建议 Skill和人读说明，模型不得提供或覆盖任何 finding字段。aligned不产生条目，drift产生当前 finding，unknown只产生 `state=unknown`且不得当作 aligned。全 aligned时删除该 CR/stage拥有的旧条目；数组清空时删除整个 `drift`字段，其他所有者条目原样保留。原本无 alignment finding时 `changed=false`、不 commit。counts仅在命令响应中从最终 `drift[]`机械计算，不写 `summary`、counter、`checked-at`或 `last-aligned-at`，也不更新 baseline `generated-at`；finding digest和幂等比较不包含建议 Skill或人读 message。修复时间线由 Git保存，不增加 resolution事件、drift-history、change-log或审计表。

#### TRA-03（新增，高优先级）：baseline generator 没有兑现 README 的 tests/reviews 回写承诺

- **位置**：`writeback-traceability.mjs` 当前只生成 merge-commits 与编辑性 `frs`；README 声称 test-report 与 review annotations 会进入 baseline traceability。
- **风险**：发布态 traceability 丢失测试与评审链，archive 却只因文件存在而放行。
- **调整**：generator 必须从 canonical 源机器注入：
  - `change-requests/{cr}/traceability.yml#tests/#reviews`；
  - `test-report.md`；
  - `review-annotations/{requirement,sdd,dev-plan,code}.yml`；
  - `approval.yml`；
  - `merge-commits.yml`。

milestone-file 只保留 LLM 擅长的 `FR → SDD/TASK/code/evidence` 编辑性映射，不允许誊抄 tests/reviews/merge。

#### TRA-04：generator 对缺失 trunk 静默回退 `master`

- **位置**：`writeback-traceability.mjs` 中 `trunkOf(repo) || 'master'`。
- **风险**：违反 repositories 唯一事实源；非 master 仓会生成伪事实。
- **调整**：repo 不存在、重复或缺 trunk 一律 `REPO_GRAPH_INVALID`；复用 repository resolver 或同一个 YAML parser，不写新的轻量扫描回退。

#### TRA-05：generator 注释仍声称 merge 来源是 backlog

- **位置**：文件头注释与局部变量 `fromBacklog`，实现已改读 `merge-commits.yml`。
- **风险**：维护者会按错误事实源继续修改。
- **调整**：注释、变量、测试名称统一为 merge manifest；README 不列六字段算法。

#### TRA-06：drift 依赖 mtime，现有摘要也未完整绑定跨节点输入

- **位置**：`review-alignment` AL-01~AL-03、AL-06。
- **风险**：checkout、copy、autocrlf 会改变 mtime；不同机器无法稳定复算。现有 requirement annotation只绑定 PRD、tech-design annotation只绑定 SDD、dev-plan没有输入摘要；拿 checkpoint时间或不相关摘要替代，会把无法证明的关系伪装成确定事实。
- **调整**：扩展既有 `crctl review-record`，由 crctl机器注入固定 `input-subjects`：
  - requirement：`prd.md`；
  - tech-design：`prd.md + sdd.md`；
  - dev-plan：`sdd.md + plan.md + tasks/_index.yml + tasks/TASK-\d+.md`固定集合；复用/最小抽取既有 code release snapshot 的受控 artifact收集逻辑，缺必需的 SDD、plan或 index硬失败，不另造 index ID到文件路径的映射规则；
  - code：继续使用既有 `release-subjects`，其已覆盖 PRD/SDD/plan/TASK index/TASK文件和各仓 reviewed source SHA，不重复写 `input-subjects`。
- 每项只含 workspace-relative path与 LF canonical SHA-256，按路径排序；payload提供 `input-subjects`、旧 `subject-file/subject-sha256`或 `release-subjects` 一律以 `REVIEW_SUBJECTS_FORGED` 零写入拒绝。不增加 subject registry、glob配置或 fingerprint命令。
- 新 requirement/tech-design annotation只写 `input-subjects`，不双写旧字段；`cmdNext`和 tech-design cycle检测通过一个窄读取 helper优先消费新结构，仅对历史 annotation兼容读取旧 `subject-file/subject-sha256`。不批量迁移旧证据。
- alignment只按“记录输入摘要 vs 当前同路径摘要”机械得到 `aligned|drift|unknown`：相同为 aligned，不同为 drift，旧证据缺少足够绑定为 unknown（需人工判断）；禁止回退 mtime、reviewed-at顺序、checkpoint时间或任意祖先关系猜测。执行范围按 CR/stage固定；传 `--stage`时只检查并原子替换该 key，未传时按 requirement、tech-design、dev-plan、code固定顺序先计算全部机器结果，再以一个 after image和一次 durable write-set原子更新四个 key。code阶段把 `release-subjects`展开为 artifact/repository两个机器主体集合。
- alignment不拥有 reviewLoop、attempt、maxAttempts或 repair-target。`traceability-record` 成功形成可信当前投影时无论 aligned/drift/unknown均 exit 0；schema、subject读取、generator、CAS或事务失败才 exit 1。Skill只选择 stage，不提供 strict、reason、severity或其他 finding字段；命令结果只按 `(stage, state)`临时推导 `suggested-skill`和 message，不将它们写入 finding，也不接受调用方覆盖。需要阻断时由既有调用节点消费 `state`，不建 alignment专属回修链。

#### TRA-07：alignment 仍读取 backlog merge-commits

- **位置**：`review-alignment` 读取契约与 AL-04。
- **调整**：checkpoint 读 latest batch，merge 读 `change-requests/{cr}/merge-commits.yml`；backlog 不再保存 merge 事实。

#### TRA-08（TCA-013）：终态 feedback 通知入口不可执行且没有消费者

- **位置**：`feedback-writeback/SKILL.md#Step 4` 调 `inbox-emit`；`cmdInboxEmit()` 明确拒绝 archived/rejected/withdrawn。Multica 当前接受的 event kind 中没有 `feedback`，既有 `inbox` 也只记录通知事件，不形成 feedback 投影；终态 Owner 不是可靠的反馈发起人事实。
- **调整**：不放宽 `inbox-emit`，不新增或复用任何 outbox kind，也不猜测收件人。反馈完成事实由新的 `crctl traceability-record --kind feedback --from <payload> [--spec-id <id>]` 内部调用固定 `writeback-feedback.mjs`，并在同一 trunk commit 中：
  1. 在目标 baseline 顶层 `feedback[]` 写唯一 `cr/outcome/deviation/lessons` 记录；
  2. 向 `_history.yml` 当前 CR 条目写入 `feedback-input-sha256`。
- feedback payload 固定要求 `deviation` 与 `lessons` 两个字符串字段，允许空字符串；先规范化 CRLF 为 LF，再对固定字段顺序的 canonical JSON 计算 `feedback-input-sha256`。history 条目已有的 CR id、`writeback-spec-id` 和 `final-status` 共同构成 `(CR-ID, spec-id)` 身份与 outcome，不在 history 重复正文、outcome、时间、summary 或 commit SHA。rejected/withdrawn 首次记录时若 history 缺 `writeback-spec-id`，同一事务写入调用方显式提供的 spec-id；已有不同值返回 `FEEDBACK_SPEC_MISMATCH`。
- lease push 成功后直接返回 `changed/cr/spec-id/outcome/commit-sha`；`commit-sha` 固定表示当前已确认包含该事实的 origin trunk HEAD，首次写入时就是本次事务 commit，同值 no-op 时允许是其后继 commit。不承诺 Multica 实时展示 feedback。平台若未来需要通知，必须另立 CR 定义消费者、收件人、UI 与事件协议。
- 当前 CR 模型只有单个 `writeback-spec-id`，没有 `target.refs` 多 spec 事实。feedback 只接受已存在于 `_history.yml` 且具有唯一 `final-status` 的终态 CR；rejected/withdrawn 若尚未完成现有 archive 账本移动，返回 `FEEDBACK_HISTORY_REQUIRED`，不从 backlog/cr.md 猜 outcome。archived 从 history 机器派生 spec-id，调用方显式值只作 expectation；rejected/withdrawn 要求显式 `--spec-id`。不接受 spec 列表或 `specs-updated[]`，不写 tech-note；deviation/lessons 只进入目标 spec traceability。
- feedback 是 `(CR-ID, spec-id)` 唯一的一次性终态事实。首次记录写 baseline feedback record + history input digest；相同 digest 重放 `changed=false` 且不更新时间、不重复事实，不同 digest 返回 `FEEDBACK_INPUT_MISMATCH`、零覆盖。未完成事务只能按 journal 原 digest 恢复，不接受替换输入；不增加 feedback-id、revision、append/patch/supersedes 或覆盖模式。已发布反馈需修正时另开正式 CR。

这比新增一条无消费者的事件协议更小，也让 baseline 与 history 共享同一发布边界。

#### TRA-09：feedback 直接手写 baseline，并建议人工创建空 traceability

- **风险**：绕过 candidate 校验、CAS、Git commit、恢复；空文件还会掩盖“writeback 未完成”。
- **调整**：`writeback-feedback.mjs` 只作为 `traceability-record` 内部确定性转换，不由 Skill 直接调用。目标 traceability 不存在时：
  - archived/accepted：硬失败，说明发布回写链不完整；
  - rejected/withdrawn：若确实需要为已有 spec 记结论，脚本基于既有 spec schema 创建完整最小结构，不允许手工空文件。

#### TRA-10：feedback outcome 可与终态冲突

- **现状**：调用者可给 archived CR 传 `outcome=rejected`。
- **调整**：outcome 从 `_history.yml#final-status` 唯一派生：archived→accepted，rejected→rejected，withdrawn→withdrawn；公开参数和 payload 均不接受 outcome。

#### TRA-11：baseline milestone 的 `status: writing-back` 会永久留在发布基线

- **位置**：milestone-file 示例允许模型传入 status，generator原样写。
- **调整**：baseline milestone 使用发布语义 `status: released`，由 generator 固定生成；CR 生命周期状态只在 history/CR 中维护，不复制进 baseline。

#### TRA-12：candidate 的 generator 身份是自报字段

- **现状**：manifest 校验 generator id 与 sha256 形状，但没有证明 sha 等于当前 Tools Root 对应脚本。
- **权限风险**：调用者可伪造合法 id/任意 digest 的 candidate，让 crctl 应用非版本化转换结果。
- **调整**：test record和 traceability handler分别以固定 `switch` 将已知 stage/kind映射到 Tools Root脚本路径，运行时计算脚本 SHA并与内部 manifest比对。只覆盖实际存在的 generator，不建 capability registry、plugin或外部 generator选择接口。

### 4.5 Agent、Pipeline、README 与 guard 的范围内越权

#### LAY-01：dev-agent 复制完整执行链并从 backlog 读 status

- **位置**：`agents/dev-agent.md#工作协议` 第 ② 步。
- **调整**：删除 13 步状态链，只保留 `/architecture`、`/coding` 路由与质量责任；状态统一通过 `crctl status/next`。

#### LAY-02：quality-reviewer-agent 暴露写入产物且错误继承测试执行能力

- **调整**：路由表输出改成“alignment机器检查结果 + traceability-record结果”，并删除退休的 impact路由，不让 Agent看见 YAML编辑算法；从 `can-call`删除 `write-test-report`，quality reviewer只读取 canonical test record，不能触发 `test run`。

#### LAY-03：feature-writeback Pipeline 仍复制深原语内部算法

- **位置**：merge、baseline、tasks、traceability、archive 五个 node prompt。
- **调整**：保留 `ref`、inputs、上一节点输出、pass/fail；删除 prepare/lease/write-set/staged set/rebuild 等内部步骤。这些应只出现在 Skill/crctl 文档和测试中。

#### LAY-04：README 存在相互冲突的 Owner/恢复描述

- **位置**：README 前文说 resume 不改 Owner，后文参数表与节点表仍保留 `new_owner/new_owner_role`。
- **与本范围关系**：checkpoint/resume 的权限和事实源会因此混乱。
- **调整**：resume 只恢复；移交只走 handover。删除旧参数与角色移交文案。

#### LAY-05：受控路径保护不完整

- **现状**：
  - `change-requests/{cr}/traceability.yml` 未在 deny；
  - `test-report.md`、baseline traceability 只在 ask；
  - test evidence 未保护。
- **调整后 deny**：
  - `change-requests/*/test-report.md`；
  - `change-requests/*/test-evidence/**`；
  - `change-requests/*/traceability.yml`；
  - `specs/*/traceability.yml`。
- **允许**：模型只写 `.crctl/tmp/**` 中由公开命令定义的 plan/analysis payload；candidate 目录和 manifest 仅由 crctl 内部创建与消费，不能作为 Skill/Pipeline 交接面。

#### LAY-06：caller 维度不是实际权限边界

- **位置**：`rules.json` 明示 callers 仅预留且全为 `*`；crctl 注释仍称“三元白名单”。
- **调整**：本次不做可伪造的 `--caller`。文档改为诚实边界：
  - Agent/Skill matrix 是路由授权；
  - crctl 通过状态、证据、路径 allowlist 和事务守卫防越权写；
  - Git/OS 凭证是本地发布权限边界；
  - 若平台未来要求 Agent 级强认证，复用 signed grant 思路传服务端签名 execution grant，另立 CR。

## 5. 目标深模块接口

### 5.1 `crctl checkpoint`

```text
crctl checkpoint <cr_id> [--message <text>] --workspace <installation-workspace>
```

输入只包含 CR 与人类可读 message；repo、branch、worktree、trunk、remote、batch-id、actor/time 全部内部派生。

成功输出固定字段：

```json
{
  "op": "checkpoint",
  "cr": "CR-...",
  "txId": "...",
  "batchId": "...",
  "phase": "complete",
  "repositories": [{"repo":"...","sourceSha":"...","remoteRef":"...","confirmed":true}],
  "metadataCommit": "...",
  "changed": true,
  "recoverCommand": "crctl checkpoint ..."
}
```

不再公开 `checkpoint-add`，也不新增 `checkpoint status`。正常执行、中断续跑与幂等重放均调用同一个 `crctl checkpoint`；成功结果返回 `phase=complete` 与当前 `latest-checkpoint`，失败结果返回 `txId/phase/sideEffects/recoverCommand`。只读远端查询继续由现有 `list-remote-checkpoints` Skill 承担，durable journal 保持 crctl 内部恢复细节，不成为公共查询模型。

### 5.2 `crctl test run/record`

```text
crctl test run <cr_id> --plan <test-plan.json> --workspace <cr-worktree>
crctl test record <cr_id> --run-id <run-id> --analysis <test-analysis.yml> --workspace <cr-worktree>
```

- `run`：开发期受信代码执行能力；启动前生成 `run-id` 与 run 目录，全部结束后一次原子写 complete manifest，不维护无恢复用途的逐命令事务状态。使用 Node `spawn()` 将 stdout/stderr 有界流式写临时文件并记录 hash/size。命令 fail/timeout/signal/launch error或日志超限聚合为 `status=block`，但只要形成可信 complete manifest，命令 exit 0；日志超限时终止当前命令，截断证据不得判 pass，run 总上限后剩余命令记 skipped。只有无法形成可信 manifest 的契约/基础设施错误才 exit 1。中断 run 禁止 record，重新调用会从头产生新 run-id；不承诺 exactly-once。argv/shell:false、repo-id cwd containment与 timeout只防误用，不构成沙箱；不建外部幂等键、executable allowlist或日志配置面。
- `record`：由 `run-id` 定位 run manifest/log，重算完整工作现场摘要并与 run 完成值精确比较，重核 status/owner，校验 analysis payload不含受信事实或最终 status；内部选择固定 `build-test-record.mjs`，由脚本按 run facts + coverage/blocker/risk 机械推导 status并生成 candidate，crctl 校验后原子写 report + evidence + trace + review-loop。成功记录 `status=block` 仍 exit 0，由 Pipeline 按结构化字段路由；只有契约、freshness、事务或轮次错误非零退出。
- 不公开 `--candidate`、generator 选择或输出目录；Skill 只传业务分析。
- 不再单独调用 `crctl attempt --loop write-test-report`；attempt 是 test record 事务的一部分。

### 5.3 `crctl traceability-record`

```text
crctl traceability-record <cr_id> --kind alignment \
  [--stage <requirement|tech-design|dev-plan|code>] [--spec-id <id>]
crctl traceability-record <cr_id> --kind feedback \
  --from <business-payload.yml> [--spec-id <id>]
```

- `alignment`：不接受 `--from`。传 `--stage`时只检查并原子更新该 `(CR-ID, stage)`；未传时按固定顺序检查四个 stage，全部机器结果生成后以同一 durable write-set原子更新，任一技术失败四阶段零写，drift/unknown作为可信业务结果照常共同提交。无 `--spec-id`时写当前 CR traceability，有 `--spec-id`时写 baseline。stable key固定为 `alignment:<CR-ID>:<stage>`，每个 CR/stage最多一个当前 finding；crctl从 annotation的 `input-subjects`/`release-subjects`与当前事实机械计算 `aligned|drift|unknown`，finding只含机器生成的 `state`、changed/missing artifact/repository subjects；不持久化 `suggested-skill`、`reason`或message，响应只按 `(stage, state)`临时推导建议 Skill和说明，调用方不能提供或覆盖任何 finding字段。
- `feedback`：仅接受已归入 `_history.yml` 的终态 CR，每次单个 spec；仍只在 backlog/cr.md 的 rejected/withdrawn 返回 `FEEDBACK_HISTORY_REQUIRED`。archived 从 `_history.yml#writeback-spec-id` 机器派生，显式 `--spec-id` 只作 expectation；rejected/withdrawn 要求显式 `--spec-id`，首次成功时把它写为 history 的 `writeback-spec-id`。内部调用固定 `writeback-feedback.mjs`，并把 baseline 顶层唯一 feedback record 与 history 的 `feedback-input-sha256` 作为同一事务/commit；payload 严格要求 deviation/lessons 两个字符串，不接受 outcome/spec 列表/tech-note 开关。成功发布返回 `changed/cr/spec-id/outcome/commit-sha`，不发送 outbox。
- scope只由 kind与 `--spec-id`有无决定，不根据 status猜测；Skill只传 alignment的 stage或 feedback的严格业务 payload；不公开 `--scope`、`--candidate`、generator id/path、输出目录或 manifest schema。
- handler内用两项固定 `switch(kind)`，不建 registry/plugin；不提供通用 YAML patch、任意 path或任意 generator参数。

| kind | scope 派生 | 状态 | 可写路径 |
|---|---|---|---|
| alignment | 无 spec-id时当前 CR；有 spec-id时 baseline | 非终态或已发布 spec | 当前 CR或 `specs/{spec}/traceability.yml` |
| feedback | baseline；archived 派生单个 spec，rejected/withdrawn 显式单个 spec | 已存在于 history 的 archived/rejected/withdrawn | 单个 spec traceability、当前 CR history 的 `writeback-spec-id`/`feedback-input-sha256` |

### 5.4 `crctl archive` 保持现接口

只补：严格 gate、结构校验、固定返回字段、正常归档 `archive` outbox；不改名、不新增 `terminal` 事件类型，也不再包一层 `archive-finalize`。

## 6. 事务、原子性与恢复语义

### 6.1 本地多文件写

所有 scoped canonical 多文件写统一使用现有 recoverable write-set：

1. 读取并 LF 规范化用于解析；before hash 仍按磁盘原字节计算；
2. 构造全部 after candidate；
3. 任一 schema/第三值/CAS 冲突时零写；
4. blobs + prepared manifest durable 落盘；
5. rename 间崩溃由同命令下次启动 redo/skip；
6. commitRequired 的命令以 `AI-First-Tx` trailer 判定 commit 是否已成为 authority；
7. 未 commit 则回滚 before image，已 commit 则只清 journal。

### 6.2 多仓 checkpoint

多 Git 仓不存在真正 ACID 原子 push，本次采用可恢复 saga，不伪称分布式事务：

- **完整 checkpoint 的可见性点**：knowledge-base metadata commit 被 origin confirmed；
- 可见前必须满足 exact-head freshness：所有非 KB repo 的 remote HEAD 精确等于 source SHA，KB remote HEAD 精确等于 metadata commit且 source SHA 为其直接父提交；
- 在此之前，其他 repo 即使已有 source commit，也只是“已发布资源”，不是完整批次；
- journal 记录所有副作用，重跑补齐；
- 不做补偿 revert，因为 checkpoint 是进度保存，不是 release；错误恢复应继续完成或标记 remote diverged，而不是改写历史。

### 6.3 Baseline traceability

- baseline 只在 detached transaction workspace 从 origin trunk 生成 commit；
- before hash stale 时重新生成 candidate，不自动套用旧 candidate；
- lease push 遇远端前进：若尚未发布，返回 `TRACEABILITY_REMOTE_STALE`；调用方重跑 generator；
- history rewritten：硬阻断，不 force。

### 6.4 审计与 outbox

- Git commit/账本是 authority；本地 `.crctl/audit.log` 与 outbox 是可重建投影；
- 正常归档只复用既有 `event_kind=archive` schema，携带 `writing-back → archived`、`trigger=cr-archive` 与真实 commit SHA；`rejected/withdrawn` 不在归档阶段重复发事件；
- outbox 失败不得回滚已确认的 Git commit，但返回 `warnings[]`；
- feedback 不发送 outbox；canonical 事实只在同一 Git commit 的 baseline `feedback[]` 记录与 history `feedback-input-sha256` 中，Multica 实时通知/展示不在本次承诺内；
- 所有错误 JSON 包含 `txId`、`phase`、`sideEffects`、`recoverCommand`（零副作用错误可省 sideEffects）。

## 7. 分步实施计划

### Phase 0：冻结契约并先加红测

1. 在 SDD/任务中冻结 `latest-checkpoint`、test run manifest、test analysis payload、review `input-subjects`、alignment 机器 finding、feedback 业务 payload/history digest 和内部 traceability candidate schema，并冻结test timeout默认值/上下限代码常量；公开 Skill/Pipeline 契约不包含 candidate schema，review payload 不得包含机器 subject。
2. 为 ARC-03/04、CKP-02/04/05、TST-01~06、TRA-03/04/08/12 先写旧实现下失败的测试；ARC-02 的严格 gate 红测归入 traceability CR，必须与 TRA-03 的 generator 产物集成测试成对出现，不在 Archive 小修中提前启用。
3. 保存当前 253 + 10 绿基线，新增测试不得靠修改旧断言“适配”错误行为。
4. 定义所有新 fault point 后一次登记到 `FAULT_POINTS`；未知 point 继续硬失败。

**完成门**：新增测试在旧实现下按预期红，现有测试仍绿。

### Phase 1：Archive 独立小修

1. 返回固定字段 `commit/lastCleanupError/remaining/preservedRefs/recoverCommand`。
2. origin confirmed 后，对正常归档复用现有 `event_kind=archive` 发幂等 outbox；字段固定为 `writing-back → archived`、`trigger=cr-archive` 与真实 archive commit SHA，不新增 terminal v2；`rejected/withdrawn` 不重复发。
3. README 澄清 archive authority 已发布与 cleanup-pending 的区别，不复制清理分类算法。
4. 补 cleanup 异常详情、正常归档 outbox warning/幂等测试；Multica 侧增加既有 schema 的契约测试，证明 archive 事件会投影为 `archived` 并结束 writeback pipeline run。

本 Phase 明确不实施 ARC-02，不要求当前 baseline 出现尚未由 generator 生成的 tests/reviews 结构。

**完成门**：cleanup-pending 必有可执行恢复信息；正常归档实时投影到 Multica，outbox 失败不反转 Git authority；现有可归档 CR 不因未升级 traceability schema 被阻断。

### Phase 2：Checkpoint 深原语

1. 在 durable journal 增加 `checkpoint` operation 与 fault points。
2. 在 `workspace-transactions.mjs` 实现 `checkpointCr()`：先做 existing-checkpoint no-op 快速确认（不建 journal）；有真实变化时再执行全 repo/branch/worktree preflight、固定敏感路径与私钥头检查、local commit、remote exact-head classify/push、KB metadata commit、`latest-checkpoint` 整块替换与恢复。checkpoint 始终保存全部未忽略变化，不增加文件选择或敏感规则绕过参数。
3. 增加单一 `cmdCheckpoint` dispatch/help/audit；不新增 status 子命令，写入、续跑与幂等重放共用同一入口，只读查询保留在 `list-remote-checkpoints`。
4. 首次新 checkpoint 不解析或归组旧 `checkpoints[]`：按本轮真实 source SHA 生成新的 `latest-checkpoint`，并在同一 metadata commit 删除旧 `checkpoints[]` 与顶层 `remote-ref/last-push-*`；无 `CHECKPOINT_LEGACY_AMBIGUOUS` 迁移分支。
5. 三 bare remote 测试：
   - CR worktree/branch 不匹配与敏感路径命中均在任何 `add/commit/push` 前零副作用失败；
   - 同一 `latest-checkpoint`、graph/remote/local 全未变的重跑在创建 journal 前 `changed=false`；
   - 全成功，含 clean repo；
   - 第二仓 push 后 kill/restart；
   - push 响应丢失；
   - remote fast-forward（remote 是 source 的祖先）可 lease publish并最终精确相等；
   - remote advanced（source 是 remote 的祖先但不相等）返回 `CHECKPOINT_REMOTE_ADVANCED`，同步后重做；
   - remote diverged；
   - KB metadata commit/push 失败；
   - 同批重放零新 commit；
   - CRLF backlog 与 Windows path。
6. 将 `push-progress` 缩成一次调用；迁移所有 Pipeline。
7. 更新 list/resume reader 后删除 `checkpoint-add` dispatch、help、测试和文案。

**完成门**：任意时刻只有 metadata-confirmed 的单个 `latest-checkpoint` 被 resume 消费；不存在半 repo 投影、“元数据晚一轮”或账本内历史批次数组。

### Phase 3：Test 原子记录

1. 定义 `test-plan/v1`（argv、cwd repo id、timeout、purpose）并实现 `test run`：启动前生成 run-id/run 目录并捕获完整工作现场 subject；subject 复用 Git `diff --binary HEAD`、`ls-files -z`与标准库流式 SHA-256，不创建 snapshot；使用 Node `spawn()` + `shell:false`，repo-id cwd containment、timeout 上下限，捕获 exit/signal/timeout/launch error；stdout/stderr 以字节流分流写临时文件，run 日志合计固定 50 MiB，超限终止并形成机器 blocker、不静默截断为 pass；全部结束后一次原子写 complete manifest，不逐命令维护事务状态；record 只把临时日志按 UTF-8 解码成文本 candidate，非法序列标 warning，不新增 Buffer/binary write-set；完整 manifest 的业务 block exit 0，基础设施/契约失败才 exit 1；中断 run 禁止 record，重试从头生成新 run-id；明确不承诺 exactly-once，也不建外部幂等键、伪沙箱、executable registry或日志配置系统。
2. 定义 `test-analysis/v1`：TASK coverage（`covered|not-applicable`）、blockers、repair instructions、risks；业务判断由 Skill/LLM 填，禁止 `status` 与任何 run 事实字段，`repair-target` 首版固定 `implement-code`。generator 对照当前 `_index.yml` 发现缺失 coverage并形成机器 blocker；冻结“run/全 TASK coverage/blocker risk”机械 status 公式，真实失败只能维持/降级为 block，不能被 analysis 升级。
3. 新增内部 `build-test-record.mjs`，读取由 `run-id` 定位的 run manifest、严格 analysis payload与 canonical CR 文件生成 candidate；脚本路径/id/输出目录不暴露给 Skill。
4. 实现 `test record`：
   - 仅接受 `run-id + analysis`，内部固定 generator 选择与 candidate 生命周期；
   - developing/owner/完整工作现场 subject freshness 守卫；
   - generator SHA 与 path allowlist；
   - report、evidence、trace tests、review-loop 同批；
   - run-id + analysis digest 一对一幂等与 maxAttempts；
   - 成功后清理临时 run/analysis/candidate。
5. 重写 `write-test-report` 为 run → 分析 → 单次 record；不直接写任何 canonical 文件，也不调用 generator 命令。
6. Pipeline 仅保留 reviewLoop 与 passCondition，删除报告 schema/写入算法。
7. 从 quality-reviewer-agent 的 `can-call` 删除 `write-test-report`；quality reviewer 只消费 canonical test record，不获得 run 权限。
8. 删除旧 `cmdTest` 与 test-report marker 编辑契约。

**完成门**：每轮 pass/block、日志、报告、trace 与 attempt 始终同号；任何未忽略的 tracked/staged/deleted/renamed/untracked 内容变化都会使旧 pass 不可用于审批，不能因 HEAD 未变而漏检。

### Phase 4：Traceability 事实链与 feedback

1. 先增强 `writeback-traceability.mjs`（TRA-03）：
   - 使用 resolver/YAML parser，删除 master fallback；
   - 机器注入 tests/reviews/approval/merge；
   - milestone status 固定 released；
   - 不新增顶层或 milestone级 schema-version；既有 milestones逐字节保留并视为 opaque历史段，未知顶层字段与注释也必须保留；
   - generator只严格验证本次新增 milestone，baseline reader不得因旧段缺新字段而拒绝整份文件；
   - 幂等检查覆盖当前 CR完整段而非只看 `- cr`。
2. 在 generator 当前段自检通过后实施 ARC-02：提取 `validateArchiveTraceability()`，让 archive只对当前 CR milestone、repo集合、tests/reviews/approval/merge做结构复核；不遍历或规范化旧 milestones。用真实 generator产物做通过测试，并覆盖“文件存在但缺当前 CR”“错误 spec-id”“当前段证据缺失”的零写入失败。
3. 扩展既有 `review-record`：非 code stage按固定表机器注入排序后的 `input-subjects`，拒绝 payload伪造；dev-plan复用既有受控 artifact collector捕获 SDD/plan/TASK index/`TASK-\d+.md`固定集合，缺必需文件硬失败，不新增 index-to-path映射；code复用现有 `release-subjects`；新记录不双写旧 subject标量，现有读取点仅对历史证据兼容旧字段。
4. 新增内部 `traceability-drift.mjs`，只维护 alignment当前 `drift[]`投影：每个 CR/stage使用 `alignment:<CR-ID>:<stage>`，最多一个 finding；finding只含 `state`、`changed-subjects`、`missing-subjects`，unknown不另存 `needs-review`；全 aligned清除该 CR/stage旧条目，数组清空时删除整个字段，原本无 finding时 no-op；响应 counts从最终数组机械计算，不持久化 summary、时间或历史账本。编辑时只替换该 CR/stage拥有的顶层 finding，既有 milestones、其他顶层字段/注释及其他所有者 finding逐字节保留。
5. 实现 `traceability-record --kind alignment [--stage <stage>] [--spec-id <id>]`：不接收 payload。传 stage时只检查并原子更新一个 key；未传时按固定顺序计算四个 stage的 input/release subjects freshness与 artifact/repository finding，全部生成后以一个 after image和一次 durable write-set更新。成功形成 aligned/drift/unknown均 exit 0；任一 schema、subject读取、generator、CAS或事务失败时四阶段零写并 exit 1，不支持部分提交或补偿。crctl内部选择固定 generator并管理 candidate，Skill只选择 stage，不自报 subject/finding字段、不根据 status猜 scope。
6. 重写 `review-alignment`：只选择 stage并调用无 payload的 alignment命令，消费机器返回的 `aligned|drift|unknown`及 changed/missing subjects；不使用 mtime；不直接写文件。旧示例中的 `detected-at`、`requirement-id`、`reason`、`severity`、`summary`和持久化 `suggested-skill` 全部删除；建议 Skill只由 crctl按 `(stage, state)`在响应中临时推导。不存在 alignment专属 strict/reviewLoop/attempt/repair-target，既有调用节点自行决定是否把 drift/unknown作为业务 block，也不在本次批量插入既有 Pipeline。
7. 退休 `change-impact-analysis`，删除 quality Agent路由和 Agent/Skill索引、matrix、README声明；不保留 pending/hidden impact接口。
8. 新增内部 `writeback-feedback.mjs`，实现 `traceability-record --kind feedback --from <payload> [--spec-id <id>]`：只接受已存在于 history 的唯一终态 CR，仍在 backlog/cr.md 的 rejected/withdrawn 返回 `FEEDBACK_HISTORY_REQUIRED`；archived 从 history 派生单个 spec 且显式值只作 expectation；rejected/withdrawn 要求显式单个 spec，并在首次成功时同事务写入 `writeback-spec-id`；终态派生 outcome，内部生成 candidate，将 baseline 顶层唯一 `cr/outcome/deviation/lessons` 记录与 history `feedback-input-sha256` 同 commit。digest 来自 LF 规范化后、固定字段顺序的 deviation/lessons canonical JSON；相同输入 no-op，不同输入 `FEEDBACK_INPUT_MISMATCH` 零覆盖，journal 只恢复原输入。payload 严格要求两个字符串字段，不支持 target.refs、spec 列表、specs-updated、tech-note 或 revision/patch；baseline编辑只追加当前 CR的顶层 feedback记录，既有 milestones、其他顶层字段/注释和其他 feedback记录逐字节保留；成功发布只返回结构化结果，不发送 outbox。
9. 删除 feedback 的 `inbox-emit`、手工空文件、直接 YAML示例算法。

**完成门**：baseline 每个 CR milestone 可追到测试、四类 review、approval 与 merge；增强 generator 的真实产物可通过 archive 严格 gate，缺当前 CR 或缺证据的旧文件不能误放行；feedback 在终态可执行且一次 commit 完成 trace/history，不产生无消费者的 outbox。

### Phase 5：权限、层级与文档收敛

1. 更新 protectedPaths deny，模型只写公开命令定义的 tmp business payload；candidate 仅由 crctl 内部创建。
2. 在 test/traceability 内部 candidate apply 路径校验固定 Tools Root generator digest；不增加外部 apply API。
3. 精简相关 Pipeline prompt与 dev/quality Agent；修正 Agent索引中四条 Pipeline消费 alignment的虚假声明。本次不批量新增 alignment节点或 reviewLoop，后续真实 gate只在明确节点消费 alignment返回的 `state`，不新增 alignment专属 `strict` 参数。
4. README 只保留阶段总览、完整 checkpoint 定义、test 闭环、archive/cleanup-pending 区别、trace 两层模型。
5. 修 README resume/Owner 冲突和 generator 错误注释。
6. 删除重复 `.github/workflows/check-skill-matrix.yml`，由 `crctl-ci.yml` 作为唯一 CI workflow：保留双平台矩阵，在其 `push/pull_request.paths` 中补入 `AGENT-SKILL-MATRIX.md`，继续运行 matrix与 agent 两个 checker；同步更新仍把 `check-skill-matrix.yml`称为 CI入口的 OpenWiki 文档引用，禁止保留两份命令列表或第二个等价 workflow。

**完成门**：Agent 无状态/Git/账本算法；Pipeline 无完整命令序列；Skill 无原子账本与逐仓 Git；README 无可执行细节副本。

## 8. 测试与故障注入矩阵

### 8.1 Archive

| 场景 | 断言 |
|---|---|
| trace 文件存在但无当前 CR | 零账本写，`ARCHIVE_TRACEABILITY_CR_MISSING` |
| tests/reviews 缺失 | gate block，零写 |
| 四账本 rename 第 N 个崩溃 | 重跑 redo/skip，四 hash 最终同批 |
| commit hook 失败 | before image 恢复，index clean |
| push 响应丢失 | remote classify confirmed，不重复 commit |
| cleanup dirty/fault | status archived；remaining/error/recoverCommand 可见；重跑不新增 commit |

### 8.2 Checkpoint

| 场景 | 断言 |
|---|---|
| CR worktree 或 `requirement/{cr}` 分支不匹配 | 所有 repo 零 add/commit/push，返回结构化 preflight 错误 |
| `.env`/凭证固定路径或私钥头命中 | index 保持调用前状态；所有 repo 零 commit/零 push，`CHECKPOINT_SENSITIVE_PATH`；`.env.example|sample|template` 与普通公开 `*.pem/*.key` 不误拦 |
| tracked + untracked 普通变化 | `add -A` 后进入同一 source commit；恢复后文件齐全 |
| 三仓均有变更 | 每仓 source SHA；KB remote 含完整 `latest-checkpoint` |
| 某仓 clean | 不造空 commit，但仍进入当前 `latest-checkpoint` |
| 第二仓 push 后 kill | journal 保留；重跑不重复第一/第二仓 push |
| KB metadata 前中断 | 远端 repo commit 存在但 `latest-checkpoint` 不更新；重跑完成 |
| 同 graph/同 heads、不同 message 重放 | 命中 no-op 快速确认，`changed=false`；batch-id、时间戳与 metadata commit 不变 |
| KB metadata push 后响应丢失 | remote HEAD/直接父关系确认成功，单 metadata commit，不因重跑再造下一层 metadata |
| remote 落后且是 source 祖先 | 按该 remote SHA lease fast-forward；push 后 remote HEAD 精确等于 source |
| remote 已包含 source 后又前进 | `CHECKPOINT_REMOTE_ADVANCED`；不写 metadata、不把祖先关系当完整 checkpoint，先同步后重做 |
| remote diverged | 不 force、不自动 merge；`CHECKPOINT_REMOTE_DIVERGED` + sideEffects/recoverCommand |
| existing checkpoint + graph/remote/local 全未变 | 创建 journal 前返回 `changed=false`；不更新时间、不 push、不产生新 source/metadata commit |
| 只有非 KB repo 变化 | KB 不造空 source commit；新 metadata commit 的直接父提交为上一 KB HEAD，并记录为本轮 KB source SHA |

### 8.3 Test

| 场景 | 断言 |
|---|---|
| 非 developing | run/record 零 canonical 写 |
| owners.test 缺失 | 硬失败，不回退 identity |
| shell metacharacter/空 argv/NUL/越界 repo cwd | plan 校验拒绝；`shell:false`；不声称 executable 安全 |
| quality reviewer 请求执行测试 | 路由权限拒绝；只允许读取现有 canonical test record |
| timeout缺失、低于下限或高于上限 | 缺失时使用SDD冻结的默认值；低于下限或高于上限时plan schema拒绝；边界值由测试锁定，不读取workspace配置 |
| plan/schema/status/owner/worktree 或证据持久化失败 | run exit 1，不产生 complete manifest，不进入 analysis/record |
| 进程死在某条命令期间 | 原 run 保持 incomplete且禁止 record；重新调用从头生成新 run-id，不拼接半轮证据 |
| 子命令 launch error/timeout/signal | 进程存活时记录完整 command result并继续剩余命令，run `status=block` 且 exit 0 |
| 第二命令失败 | run 仍执行剩余命令并 exit 0、status=block；record 仍 exit 0且日志同 run-id、trace/attempt 同批；Pipeline 按 blockers 回修 |
| run 日志合计达 50 MiB | 终止当前命令，后续命令 `skipped=prior-output-limit`；status=block，不假装完整执行 |
| 临时日志 hash/size 与 manifest 不符 | record 契约失败，零 canonical 写 |
| analysis 自报 status/exit/SHA/tester/log，或 coverage 含非法值 | schema 拒绝，零 canonical 写 |
| 同 run-id/同 analysis 重放 | `changed=false`，不重复 attempt，不覆盖历史日志 |
| 同 run-id/不同 analysis，或原 record 事务输入替换 | `TEST_RECORD_INPUT_MISMATCH`，零覆盖；重新运行产生新 run-id |
| command 全绿但 TASK coverage 缺失、blocker 或 blocker risk | generator 机械推导 `status=block`；record exit 0并进入 reviewLoop |
| command 失败但 analysis 无 blocker或意图 pass | 自动机器 blocker，最终仍为 block；不得升级真实失败 |
| 测试命令修改 tracked 或 untracked 工作树 | run 前后摘要不同，`subject-mutated=true`，status=block；不 stash/回滚测试副作用 |
| run 后任一未忽略内容变化但 HEAD 不变 | record 返回 `TEST_SUBJECT_DRIFT`，零写 |
| symlink/submodule/ignored 文件 | symlink 哈希 link target、submodule 只取 gitlink、ignored 不入摘要且不越界读取 |
| rename 间崩溃 | report/evidence/trace/loop 恢复到整组 before 或 after |
| 旧报告存在且 write-test-report loop存在 | 不造 legacy attempt；首次新 record使用 current-attempt+1，保留旧 attempts，report/evidence/trace/loop同批写入 |
| 旧报告存在但 write-test-report loop不存在 | 不从旧报告猜轮次；首次新 record从 attempt 1开始 |
| 旧 loop已达 maxAttempts | LOOP_EXHAUSTED；协议迁移不重置预算，旧报告/attempts保留 |
| 旧固定 cmd-*.log | 不搬迁、不删除；新 evidence使用 run-id目录且不覆盖旧日志，旧引用继续由原路径/Git历史解释 |

### 8.4 Traceability/feedback

| 场景 | 断言 |
|---|---|
| repo 缺 trunk | REPO_GRAPH_INVALID，绝不写 master |
| baseline milestone 缺 test/review | generator/self-check 失败 |
| review payload自报 `input-subjects`、旧 subject标量或 `release-subjects` | REVIEW_SUBJECTS_FORGED，annotation/trace/loop零写 |
| requirement/tech-design新记录 | 只写固定排序 `input-subjects`，不重复写 `subject-file/subject-sha256` |
| dev-plan必需的 SDD/plan/TASK index缺失 | SUBJECT_NOT_FOUND，零写；TASK文件集合复用既有 `TASK-\d+.md`受控 artifact规则，不新建 index-to-path schema |
| 历史 annotation只有 `subject-file/subject-sha256` | 既有 cmdNext/cycle读取兼容；alignment无法证明的跨节点关系为 unknown，不迁移/不猜测 |
| input/release subject相同/不同/缺失 | alignment分别得到 aligned/drift/unknown；不读 mtime/reviewed-at/checkpoint时间 |
| CRLF/LF 等价 | input subject digest与 alignment结果一致 |
| alignment 同一 CR/stage 重放 | stable-key内容不变，`changed=false`；不更新时间、不重复 drift、不产生 commit |
| alignment 全 aligned且有旧 finding | 只删除该 CR/stage拥有的旧 finding；数组清空时删除 `drift`字段，其他所有者条目原样保留；Git保留修复历史 |
| alignment 全 aligned且原本无 finding | `changed=false`，不写 aligned记录、不 commit |
| alignment 未传 stage | 按固定顺序先计算 requirement、tech-design、dev-plan、code全部机器结果，再以一个 after image和一次 durable write-set原子更新四个 key；响应返回四阶段结果及最终 counts |
| alignment 批量业务 drift/unknown | 与其他 stage结果共同提交并 exit 0，不把业务结果误作事务失败 |
| alignment 批量技术失败 | 任一 schema/subject/generator/CAS/事务失败均四阶段零写，不保留前序 stage结果、不做补偿 |
| alignment finding主体 | 只接受 crctl生成的 `state`、`changed-subjects`/`missing-subjects`；文档是 `kind=artifact`，仓库是 `kind=repository`，按 kind/id排序；不持久化 suggested-skill/reason/message |
| alignment响应建议 | 只根据 `(stage, state)`临时推导 suggested-skill和 message；不进入 canonical YAML、digest或幂等比较 |
| alignment 响应 counts | 从最终 `drift[]`机械计算；不写 summary/counter/checked-at/last-aligned-at，不更新 baseline generated-at |
| alignment unknown | 写当前 CR/stage的 `state=unknown`机器投影，不重复保存 `needs-review`；record exit 0，既有调用节点自行决定业务 block，不得判 aligned |
| alignment drift | 写当前 CR/stage的机器 finding；record exit 0，建议 skill由固定 stage映射返回，调用方不得覆盖 |
| alignment schema/subject/generator/CAS/事务失败 | exit 1，零写或按既有 durable transaction恢复；不伪装业务 unknown |
| alignment不新增 reviewLoop | 只返回当前机器事实；既有 Pipeline是否阻断/回修由原节点契约决定，不新增 alignment attempt或 repair-target |
| alignment 无/有 spec-id | 分别只允许当前 CR/baseline allowlist，scope不从 status猜测 |
| alignment/feedback编辑历史异构 baseline | 只修改各自拥有的顶层 `drift[]` finding或 `feedback[]`记录；既有 milestones、未知顶层字段、注释和其他所有者记录逐字节不变 |
| alignment与 feedback并发修改同一 baseline | CAS conflict或事务重生 candidate，不覆盖对方 |
| 已退休 impact命令/Skill引用 | R22或 matrix/index检查失败；运行时无 `kind=impact`分支 |
| archived feedback不传 spec-id | 从 history.writeback-spec-id 派生单个 spec；baseline feedback record + history digest 同 commit，outcome=accepted |
| archived feedback传相同/不同 spec-id | 相同允许并作为 expectation；不同 FEEDBACK_SPEC_MISMATCH、零写 |
| rejected/withdrawn 尚未归入 history | FEEDBACK_HISTORY_REQUIRED，零写；先完成现有 archive 账本移动，不从 backlog/cr.md 猜 outcome |
| rejected/withdrawn 首次 feedback | 要求显式 spec-id 并同事务写入 history.writeback-spec-id；已有不同值 FEEDBACK_SPEC_MISMATCH、零写 |
| rejected/withdrawn feedback缺 spec-id | BAD_ARGS，零写；不从不存在的 target.refs猜测 |
| feedback payload缺字段、字段非字符串，或含 outcome/spec列表/specs-updated/write-tech-note/feedback-id/revision | schema拒绝，零写；严格只接受 deviation/lessons两个字符串 |
| 首次 feedback | `(CR-ID, spec-id)`唯一 baseline 记录与 history `feedback-input-sha256` 同 commit，不产生 outbox |
| 相同 feedback payload重放 | `changed=false`，不更新时间、不重复记录或产生 outbox；`commit-sha` 是当前已确认包含事实的 origin trunk HEAD |
| 同 CR/spec不同 feedback payload，或恢复期替换输入 | FEEDBACK_INPUT_MISMATCH，零覆盖；已发布修订另开正式 CR |
| 伪造 generator digest | GENERATOR_MISMATCH，零写 |
| baseline origin 前进 | stale，重生成后成功；不套旧 candidate |

## 9. 静态治理与 CI

### 9.1 `lint-prompts` 增量规则

不一次实现附件全部 R10-R21，先落与本范围直接相关的最小规则：

- **R10 command existence**：解析 crctl dispatch/help，校验文档中的顶层/二级命令与必填旗标；
- **R14 Pipeline duplication**：删除基于 crctl/Git 命令数或 prompt 行数的启发式 warning；由 `check-pipeline-contract` 的结构性检查判定 replay/input/passCondition/ref 边界；
- **R17 readonly consistency**：frontmatter/meta readonly 与正文写入/输出冲突；
- **R18 controlled writer**：test-report、CR trace、spec trace 写动词必须邻近合法 generator/crctl command；
- **R22 retired command**：`checkpoint-add`、旧 `crctl test --cmd`、terminal `inbox-emit` 迁移后出现即 block；
- **R23 fact-source fallback**：traceability/checkpoint 文案出现 `fallback master`、backlog status fallback、backlog merge-commits 即 block。

实现必须 LF 规范化、逐行/JSON AST 解析；状态机/JSON/YAML 解析失败硬失败。

### 9.2 Pipeline checker

新增轻量 `check-pipeline-contract.mjs`，只做 Pipeline 独有、lint 不适合做的四项：

1. reviewLoop `replayNodes` 存在、顺序合法；
2. passCondition 路径由对应 Skill 输出契约声明；
3. 必填 input 向 node 传递；
4. `ref` 节点 prompt 不得重新拥有 Git/账本/事务算法。

不实现通用 Pipeline 执行器。

### 9.3 CI

`crctl-ci.yml` 在 Ubuntu/Windows 统一运行：

```text
lint-prompts --mode enforce
check-skill-matrix
check-agents-contract
check-pipeline-contract
node --test skills/shared/crctl/scripts/test/*.test.mjs
node --test skills/writeback/scripts/test/*.test.mjs
node --test skills/develop/scripts/test/*.test.mjs
node --test skills/review/scripts/test/*.test.mjs
Pipeline JSON parse
```

paths 增加 `README.md`、`skills/**`、`agents/**`、`pipeline-templates/**`、`rules.json` 的实际位置和 workflow 自身。Windows job 固定验证 CRLF、long path 与 linked worktree。

## 10. 权限模型说明

### 10.1 本次必须做到

- 模型不能直接写测试/traceability canonical 文件；
- Skill 不能直接执行逐仓 Git 或原子账本编辑；
- crctl 只接受 allowlisted path 与已登记 generator；
- archive/feedback 必须满足状态与证据 gate；
- 所有发布使用普通 push/lease，不允许 force 绕过；
- 人工审批仍只走 TTY 或签名 grant，版本化脚本不得审批/推进状态。

### 10.2 本次不伪造的能力

`identity(ws)` 与 `rules.json callers` 不是强身份认证。不能通过新增 `--caller quality-reviewer-agent` 获得真正授权，因为调用者可以自报。当前本地模式的最终权限是 OS 用户和 Git remote 凭证；crctl 提供的是操作级约束、证据门和审计。

若未来需要“只有指定 Agent 可调用 traceability-record”，应由平台签发短时 execution grant，并由 crctl 验签；这是独立安全需求，不在本次用字符串模拟。

## 11. 数据迁移与兼容策略

1. **checkpoint**：不迁移、不归组旧 `checkpoints[]`。首次成功执行新命令时，以本轮真实 repo source SHA 生成单个 `latest-checkpoint`，并在同一 metadata commit 删除旧 `checkpoints[]` 与顶层 `remote-ref/last-push-*`；reader 随命令切换一次性改读新字段，不永久双读。旧 checkpoint 历史仍可从 Git 查询。
2. **test**：不迁移旧 `test-report.md`、trace tests或固定 `cmd-*.log`，也不创建 `legacy-attempt`、伪 run-id或伪 subject digest。首次新 record正常替换 canonical report并写入 `run-id` evidence目录，旧内容由 Git历史保留；旧固定日志暂不搬迁、不删除。若 `review-loop.yml#loops.write-test-report` 已存在，新 record使用 `current-attempt + 1`并保留旧 attempts；若不存在则从 attempt 1开始，不从旧报告猜测轮次。既有 maxAttempts预算不因协议迁移重置，已耗尽仍返回 `LOOP_EXHAUSTED`。
3. **traceability**：不新增顶层或 milestone级 `schema-version`。既有 milestones作为 opaque历史段逐字节保留，不统一旧 status、`fr-chain/frs`或补旧 tests/reviews/approvals；未知顶层字段和注释保留。新 generator只追加并严格自检当前 CR增强 milestone，archive gate也只验证该段；reader不得因旧段缺新字段而拒绝整份 baseline。历史段迁移必须另开明确 migration CR。
4. **feedback**：不为旧 archived CR 自动补 feedback fact；仅在人工触发反馈时按新格式追加，且不发送 outbox。
5. 兼容代码必须带删除条件和测试，不允许“先留着以后再说”。

## 12. 交付分组与任务拆分

本文是跨 CR 的总治理路线图，不是一个包含全部任务的实施 CR。按共享文件冲突和事实依赖固定顺序交付，不并行推进：

| 交付 CR | 范围 | TASK |
|---|---|---|
| A. Archive 小修 | cleanup 回显、正常归档既有 outbox、README 语义；不提前启用严格 traceability gate | T02 |
| B. Checkpoint 收敛 | 单一深原语、`latest-checkpoint`、多仓恢复与旧入口迁移 | T03~T05 |
| C. Test 原子记录 | 受信 run、固定 generator、record 原子记账与旧入口迁移 | T06~T09 |
| D. Traceability/feedback | baseline 证据、ARC-02、input binding、alignment、impact 退休、feedback、guard 与相关层级文档 | T10~T14（含 T10A） |
| E. 静态治理收尾 | 定向 lint、Pipeline checker、唯一双平台 CI 与 OpenWiki 引用更新 | T15~T16 |

T01 是每个交付 CR 各自执行的 schema/错误码/fault point 红测入口，不是要求先建一个跨五条链的公共实现 CR。A 不依赖 B~D；D 的严格 archive gate 必须在 T10 generator 增强后由 T10A 启用；E 只做防回归收尾，不阻塞前四个运行时交付。各 CR 可以独立验收和回滚，但因共享 `crctl.mjs`、事务模块和文档，按 A→B→C→D→E 顺序实施。

| TASK | 内容 | 主要文件 | 依赖 |
|---|---|---|---|
| T01 | schema/错误码/fault point 测试先行 | 新测试夹具、SDD | 无 |
| T02 | Archive 独立小修：返回值、cleanup 语义、正常归档 `archive` outbox（复用 Multica 既有消费契约）；不含严格 traceability gate；Multica契约测试改动同步登记其 `CUSTOM.md` | workspace-transactions、crctl、archive tests；Multica契约测试/CUSTOM台账 | T01 |
| T03 | checkpoint journal 与 `latest-checkpoint` 整块编辑纯函数 | durable-tx、workspace-transactions | T01 |
| T04 | checkpoint 多仓 publish/recover | crctl、checkpoint tests | T03 |
| T05 | push-progress/Pipeline/list/resume 迁移并删 checkpoint-add | Skill/Pipeline/README | T04 |
| T06 | structured test run、中断 run 完整性 + dev-only 路由权限 | crctl、test-run tests、agent-skill-matrix | T01 |
| T07 | build-test-record generator | develop scripts/tests | T06 |
| T08 | test record 原子 apply 与 loop | crctl、durable tx tests | T07 |
| T09 | write-test-report/Pipeline 迁移，删除旧 cmdTest | Skill/Pipeline | T08 |
| T10 | baseline traceability 注入 tests/reviews/approval + resolver | writeback generator/tests | T01 |
| T10A | ARC-02 严格 archive gate；只消费 T10 的真实 generator 结构，不自造第二份 schema | workspace-transactions、archive/writeback 集成测试 | T10 |
| T11 | review-record `input-subjects` + alignment generator/traceability-record + impact退休 | review scripts/crctl/matrix/index/docs/tests | T10A |
| T12 | feedback generator + baseline/history digest transaction；删除终态通知/outbox 承诺 | cr Skill/scripts/crctl/tests | T11 |
| T13 | protectedPaths 与 generator 真值校验 | rules、crctl、hooks tests | T08/T11/T12 |
| T14 | Agent/Pipeline/README 收敛 | agents/pipelines/docs | T05/T09/T12 |
| T15 | R10/R14/R17/R18/R22/R23 + pipeline checker | checker/tests | T14 |
| T16 | 合并CI：删除重复workflow、扩展唯一双平台 `crctl-ci.yml`及 `AGENT-SKILL-MATRIX.md`触发路径、更新OpenWiki旧入口引用并全量回归 | workflows、OpenWiki引用 | T15 |

建议提交粒度：每个 TASK 一个可回滚提交；先测试、再实现、再删除旧入口，不把 checkpoint、test、traceability 三条大链塞进一个提交。

## 13. 完成标准

### 架构

- Agent 只路由，不读 backlog status、不维护状态链；
- Pipeline 只维护节点、输入、reviewLoop、失败语义；
- Skill 不手写逐仓 Git、YAML 账本或 canonical traceability；
- crctl 独占 scoped 状态/gate/CAS/账本/Git/审计/恢复；
- generator 只做确定性转换，不推进状态、不审批、不 push；
- README 不复制深原语算法。

### 一致性与恢复

- archive 四账本同 commit，cleanup pending 可恢复且错误详情可见；
- checkpoint 的 source commit 包含各 CR worktree 的全部未忽略变化；不因模型漏列文件形成“完整账本、残缺现场”；
- test 每轮 report/evidence/trace/attempt 同批，subject 覆盖 HEAD 与全部未忽略工作树内容，旧轮日志不覆盖；
- baseline 每个新 milestone 含 tests/reviews/approval/merge；旧 milestones保持 opaque且逐字节不变，reader不要求其符合新结构；
- feedback 在终态可执行，baseline 记录与 history digest 同 commit，且不发送 outbox；
- 任一 rename/commit/push fault 后，要么零 authority 写入，要么返回 txId + 可执行 recoverCommand；
- 第三值永不被自动覆盖。

### 权限与唯一事实源

- status 只来自 `cr.md`；
- repo/trunk 只来自 repositories resolver；
- merge 只来自 `merge-commits.yml`；
- checkpoint 只来自 metadata-confirmed 且通过 exact-head freshness 的 `latest-checkpoint`；
- outcome 只来自 history final-status；
- canonical test/trace 文件直接写被 guard deny；
- candidate generator digest 与 Tools Root 当前脚本一致。

### 验证

- Ubuntu/Windows CI 全绿；
- 新增 fault tests 覆盖每条 scoped transaction；
- lint 对旧 checkpoint-add、终态 inbox-emit、readonly 冲突、master fallback、Pipeline 算法复制能稳定报错；
- 当前 253 个 crctl tests 与 10 个 writeback tests 不因放宽断言而“假绿”。

## 14. 不做事项（ponytail 边界）

- 不引入数据库、消息队列、分布式锁或 2PC；
- 不新建通用 YAML patch CLI；
- 不建 generator plugin/capability registry；test与 traceability handler各自用固定 `switch` 选择实际存在的脚本；
- 不让 checkpoint 失败时自动 merge、force push 或补偿 revert；
- 不批量重写全部历史 traceability milestone；
- 不用可伪造 caller 字符串冒充 Agent 强认证；
- 不为只调用一次的纯函数创建 interface/factory/class；
- 不把本次范围扩展成全 crctl 所有单文件命令的事务重构；TCA-019 在本次只关闭 archive/checkpoint/test/traceability相关写链，其他旧命令如 task/backlog/inbox的全局收敛应另行盘点；
- 不给 alignment新增 reviewLoop/attempt/maxAttempts/repair-target，不因 Agent索引的虚假 consumers声明批量改四条 Pipeline；
- 不实现 impact/stale/perspective/change-log/resolution模型；退休 `change-impact-analysis`，真实需求出现后以 milestone CR + FR-ID重新建模；
- feedback不支持多 spec target.refs/spec列表，不创建 docs/tech-notes或独立 lessons文档；先建立正式 CR→spec关系模型后才能扩展多目标；
- feedback不提供 revision/append/patch/supersedes/覆盖模式；每个 CR/spec只有一次终态记录，修正已发布内容另开正式 CR。

最终目标不是增加更多命令，而是让四条链各自只有一个真正负责副作用的深接口：archive 已有，checkpoint/test/traceability 补齐；其余层删除重复算法即可。

## 15. 已冻结决策映射

| 问题 | 最终决定 | 方案落点 |
|---|---|---|
| Q1 | 本文是跨 CR 总路线图，禁止作为单个大 CR 实施 | §12 交付分组 |
| Q2 | Archive 小修独立交付；ARC-02 等 generator 增强后再启用 | §4.1、Phase 1/4、T02/T10A |
| Q3 | 只保留单个 `latest-checkpoint`，历史走 Git | CKP-03、§11.1 |
| Q4 | 不新增 `checkpoint status`；写入、恢复和重放共用一个入口 | §5.1、Phase 2 |
| Q5 | `batch-id` 排除 message/actor/time/path/txId | CKP-03 |
| Q6 | checkpoint 固定 `git add -A` 保存全部未忽略变化 | CKP-01、Phase 2 |
| Q7 | 只做固定敏感路径和私钥头检查，无扫描器/例外系统 | CKP-01、§8.2 |
| Q8 | 完整 checkpoint 要求 exact-head；远端超前先同步再重做 | CKP-05、§6.2 |
| Q9 | 创建 journal 前做真正 no-op；KB source 是 metadata commit 直接父提交 | CKP-04/05、§8.2 |
| Q10 | `test record` 隐藏 candidate/generator/path | TST-02、§5.2 |
| Q11 | `test run` 是受信代码执行，不是沙箱；quality reviewer 无执行权 | TST-01、§10 |
| Q12 | 测试 block 是 exit 0 的可信业务结果；技术/契约失败才 exit 1 | TST-06、§5.2 |
| Q13 | 早期 `run-key`/逐命令状态方案经 ponytail 复核撤回；incomplete run 废弃并用新 run-id 整轮重跑 | TST-03、Phase 3 |
| Q14 | analysis 不自报 status；最终状态机械推导且只能维持/降级 | TST-05、Phase 3 |
| Q15 | subject 绑定 HEAD 与全部未忽略工作树内容；漂移零写 | TST-04、§8.3 |
| Q16 | 仅一个 50 MiB/run 总日志上限；超限形成业务 blocker | TST-01、§8.3 |
| Q17 | 撤回通用 Buffer/binary write-set 扩展；保存有界 UTF-8 人读日志并标替换 warning | TST-01、Phase 3 |
| Q18 | 一个 run-id 绑定唯一 analysis digest；不同输入拒绝覆盖 | TST-03、§8.3 |
| Q19 | `traceability-record` 隐藏 candidate/scope/generator内部协议 | TRA-12、§5.3 |
| Q20 | alignment/feedback scope 固定；早期 impact scope 随 Q27 退休 | §5.3、TRA-02 |
| Q21 | 早期 impact diff 捕获方案随 Q27 撤回，不保留空壳协议 | TRA-02、§14 |
| Q22 | `review-record` 机器注入固定 `input-subjects`，历史不足返回 unknown | TRA-06、§8.4 |
| Q23 | `drift[]` 是当前投影；早期 per-subject key/`needs-review`/change-log 设计由 Q27/Q29~31 收窄 | TRA-02、Phase 4 |
| Q24 | alignment 业务结果 exit 0且无专属 reviewLoop；早期 strict/status启发式由 Q29最终接口删除 | TRA-06、§5.3 |
| Q25 | feedback 每次只写单个 spec，不支持 target.refs/tech-note | TRA-08/09、§5.3 |
| Q26 | `(CR-ID, spec-id)` 一次性事实；同输入幂等，不同输入拒绝 | TRA-08、§8.4 |
| Q27 | 退休 `change-impact-analysis`，不新增 impact/stale模型 | TRA-02、Phase 4 |
| Q28 | alignment 不保存 summary/counts/time；响应临时计算 | TRA-02、§8.4 |
| Q29 | alignment 无 payload，key=`alignment:<CR-ID>:<stage>`，每阶段一个 finding | §5.3、Phase 4 |
| Q30 | finding 不保存 reason/message | TRA-02、§8.4 |
| Q31 | finding 不保存 suggested-skill；响应按 `(stage,state)` 推导 | TRA-02、§8.4 |
| Q32 | 无 `--stage` 时四阶段计算后一次原子更新；技术失败四阶段零写 | §5.3、§8.4 |
| Q33 | 不造 legacy attempt/run-id/subject；沿正式 loop 续号，无 loop 从1开始 | §8.3、§11.2 |
| Q34 | 不加 schema-version；旧 milestone/未知字段/注释原样保留，只严格校验当前段 | Phase 4、§11.3 |
| Q35 | feedback 不发送任何 outbox；baseline 记录与 history digest 同 commit | TRA-08、§6.4 |

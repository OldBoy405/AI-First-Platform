# 可信 T committed verdict channel — multica 技术设计

> 阶段：STDD Phase 2 / Gate 2 草案。**本设计尚未实施，未写业务代码、未跑测试、未建库、未部署。**
> Gate 1 原文「确认这份 Gate 1（multica + tools 两条）」已由原生 CLI 登记（2026-10-27T15:23:55）。
> 设计输入：`projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/trusted-verdict-channel-implementation-plan-20261026.md`
> （v0.6.5，sha256 `55ee0d01…b4d8`）。该文经六轮三路复核（R2/R3 全 PASS），但那是**静态设计复核**，
> 不是实现验证、不是本 change 的批准，也不构成任何测试证据。
> 跨仓配套设计：[tools 设计](../../../tools/changes/2026-10-27-trusted-verdict-channel/design.md)（wire/key-purpose/store/crctl 侧）。
> 本文只做 multica 侧落点，不另造字段、预算或第二套裁决。

## Context

- 前身 AIFI-45（`projects/multica/changes/2026-10-22-aifi-45-authorized-execution`）已交付 643–647 迁移、
  Ed25519 阶段 grant/verifier、daemon 授权安装与 trust root、G1/G3/G5 锁修复；本 change **不重做**这些，
  只把它们当作前置依赖并记录版本锁。
- 已核实（2026-10-27，本仓工作区）：最大迁移为 `647_cr_execution_dispatch_root`；643–647 建表分别为
  `cr_execution_binding_issue`、`cr_execution_consumption`、`cr_execution_activation`、
  `cr_execution_notice`、`cr_execution_dispatch_root`；`server/internal/` 下**不存在**任何
  `execution-control`/`merge-facts`/`merge-effects` 路由；`server/internal/service/` 无 `execution_*` 文件；
  `server/pkg/db/generated/` 有 12 处既有未提交 churn（sqlc 生成物，本 change 不提交）。
- 缺口（来自 M003）：准入正路径需要可信 T 已提交裁决，而 `crctl.mjs` 仍以
  `EXECUTION_CONSUMPTION_REQUIRED` 拒绝准入；agent stdout、磁盘 JSON、平台收据、Git 结果都不是证据。
  merge 侧的「批准后写集」当前取自 agent 可写的 `approval.yml`，且核对区间小于实际发布区间。

## Decisions

### 1. 信任根与不保证项

- 信任根：server/DB、operator trust manifest、受保护 control 服务与 T runtime。
- **不保证**：agent/repo writer 可控制 stdout、workspace、Git、annotations、任务参数；其读取服务私钥、
  修改 worker/store、访问 IPC 或注入服务环境属越界；root/DB-superuser/恶意 operator 不在保证内。
- 首期只支持经实测的 Linux 与 Windows 受限身份（X1 已决：Windows 属 strict 生产平台，P0 两侧都要身份证明）。
  当前环境是否具备该边界为 **UNVERIFIED**，不得在 Gate 2 声称已具备。
- **事实可信 ≠ 执行强制**：`merge-facts` 只保证返回事实可信；持 push 权限者可绕过 CLI 直接推送。
  仓库侧闸门（分支保护要求 M 签发状态检查）不在本 change 范围，交付后不得表述为「merge 已强制」。

### 2. 选择、候选与冷启动

- `contract_selection` 只由 operator-pinned scope policy 与 server-validated scope/source 创建并冻结；
  `Selection = Legacy{…} | Strict{…} | Unknown`，Unknown/缺记录/读失败一律拒绝新增 effect，**不由 nil 推断 legacy**。
- **不可降级**：Strict 持久化后，trigger 的 `context.execution.contract` 或 `cr.md` 合同字段被删/改空/改写，
  只能得 `T_VERDICT_BINDING_MISMATCH`；不得改判 Legacy，也不得经 Unknown 落回 legacy。
  Legacy 只能由可信历史目录（`control_fact(kind=legacy-origin-catalog)`）证明。
- 冷启动：`control_reservation` 是**不可执行**占位（不进 `agent_task_queue`、不可 claim），固定 proposed task UUID；
  T permit 后才允许真实 enqueue。`ResolveCandidateTx` 从 DB scope/source/run/node 与 compiled registry 得到真实映射。
- `ExecutionTarget` 为 exact-key tagged union：`{kind:control,reservation_id,owner_fence}` 或
  `{kind:task,task_id,runtime_id,dispatched_at,daemon_id}`，不允许缺字段或双分支并存。

### 3. 受保护 store 与线性化

- 写路径：`control_command`（`created→issued→result_ready→settled_effect|settled_no_effect`，结果未知进
  `uncertain` 并 freeze lineage）→ `tool_verdict`（append-only，拒绝 UPDATE/DELETE/TRUNCATE）→
  `tool_cursor`（行锁+CAS、持久 `owner_fence`、每 lineage 最多一个 open）→ `control_settlement`
  （`kind=effect|no_effect`，immutable，request unique）。
- **线性化点 = caller Tx commit**：同 Tx 重验 current signed head、selection、cursor/fence、原 candidate、root，
  写 root/task/effect mapping/settlement 并释放 slot。ingest ACK 只确认持久化，**不释放 slot**。
- revoke 走既有 CR 锁路径，**不等待 command slot**：撤销先提交 → 旧 permit 只能 `no_effect`；
  effect 先提交 → 撤销不追溯。stop 按 T sequence 生效，前一 effect settled 后才能发后续 stop。
- 固定锁序：deployment head → policy activation head → CR → referenced head → 业务行 → cursor/command →
  dispatch root/task。Tx 内不调用网络。

### 4. 恢复

- restart：先取 M 新 fence 隔离旧 worker；worker 接受新 fence 后才返回 signed checkpoint。
- `ReconcileOwnerTx` 对齐 cursor/checkpoint/journal/open command：tail 相同→恢复原 request；恰领先一项→
  导入原 verdict bytes 再正常 settlement；M 已 settled→返回原 mapping；journal prepared→新 fence 下重放原
  command；缺失/落后/分叉/多项超前→freeze（不猜「未消费」、不清 slot、不建空 store）。
- 普通 restart 不变 epoch/sequence；key rotation 只影响新 verdict，历史用旧 key 验证。

### 5. 数据模型（单个 proposed 迁移 `648_cr_execution_control`，14 张表）

| 后缀（前缀 `cr_execution_`） | 关键字段 / 约束 |
|---|---|
| `contract_selection` | `id,workspace_id,project_id,cr_id,lineage_id,mode,policy_ref,contract_digests,source_ref,origin_id,fresh_work_ref,created_at`；scope/lineage unique；同 workspace/project/origin 仅一归属；immutable |
| `control_reservation` | `id,selection_id,scope,lineage_id,candidate_bytes,candidate_digest,created_at`；fixed proposed task unique；immutable；无 task/runtime 占位行 |
| `control_command` | `request_id,scope,lineage_id,reservation_id,owner_fence,effective_fence,seq,prev_digest,command_bytes,envelope,state,verdict_id,admission_event_ref,admission_seq,issued_at`；issued 时冻结准入边界，签名字段 immutable，状态受限转换 |
| `tool_verdict` | `id,scope,lineage_id,request_id,store_id,epoch,seq,prev_digest,payload_bytes,envelope,digest,commit_ref,receipt_ref`；request unique、store/epoch/seq unique；拒绝 UPDATE/DELETE/TRUNCATE |
| `tool_cursor` | `scope,lineage_id,store_id,epoch,last_seq,last_digest,owner_fence,owner_id,open_request_id,frozen_reason,reconcile_proof`；行锁+CAS；无预算累计器 |
| `control_settlement` | `request_id,verdict_id,kind,effect_kind,effect_ref,fixed_candidate_digest,head_ref,reason,settled_at`；request unique、immutable；`kind=effect|no_effect` |
| `task_binding` | `reservation_id,command_id,verdict_id,task_id,runtime_id,dispatched_at,daemon_id,binding_digest,launch_id,launch_lease_ref,install_snapshot_ref,launch_permit_bytes`；实际 generation unique、immutable |
| `control_fact` | `id,scope,kind,origin_id,source_authority,source_record_id,registry_revision,actor_assignment_ref,attempt_ref,subject_ref,capture_ref,payload_bytes,digest,created_at`；认证来源+immutable；`kind` 决定 provenance tagged union；origin-registration 对 scope/origin 及 scope/source_authority/source_record_id 分别 partial unique |
| `deployment_head` | `scope,generation,snapshot_digest,state,registry_revision,legacy_catalog_ref,legacy_gate,legacy_work_revision`；scope unique；generation/registry/work revision 单调；`legacy_gate=OPEN|DRAINING|RETIRED`；禁止删行归零 |
| `deployment_snapshot` | `scope,generation,profile_digest,inventory,facts_bytes,evidence_refs,digest`；scope/generation unique、immutable |
| `policy_readiness` | `request_id,scope,target,nonce,generation,expiry,command_bytes,observation_frames,verdict_bytes,digest`；nonce/request unique；每 slot 仅可 CAS 登记一份原观测（同 bytes 幂等、异内容拒）；最终 signed result 原字节不可改 |
| `policy_activation_head` | `scope,target_policy,revision,event_id,last_issued_admission_seq`；scope/target unique；启用与停新共用一个 CAS/锁点 |
| `policy_activation_event` | `id,scope,target_policy,previous_id,mode,generation,verdict_ref,actor,reason,cutoff_admission_seq,committed_at`；append-only；`mode=ACTIVE|STOP_NEW` |
| `code_source_freeze` | `workspace_id,cr_id,repo_id,approved_source_sha,approved_revision,approval_record_id,authorization_head_id,approved_at,superseded_at,revoked_at,digest`；`UNIQUE(workspace_id,cr_id,repo_id,approved_revision)` + 部分唯一 `UNIQUE(workspace_id,cr_id,repo_id) WHERE superseded_at IS NULL`（每仓至多一条当前行）；只由 code 批准事务追加写 |

- 合计 **14 张**（业务通道 8 + D7 5 + merge facts 1），全部在同一 proposed 迁移内；无新 FK/cascade；
  软引用逐次验证。workspace deletion 分类：audit/selection/settlement/binding/fact 保留，command/cursor 禁新建并收敛。
- `ChannelTableNames` 登记**DB 全名**（`cr_execution_*`），本表只列后缀；迁移专例以该清单为唯一来源。

### 6. 接口（5 个 daemon 端点 + Tx/reader 签名）

| 端点 | 语义 |
|---|---|
| `GET /api/daemon/execution-control/commands` | 取当前 open command（按 owner scope） |
| `POST /api/daemon/crs/{crID}/execution-verdicts` | ingest 已签 verdict（ACK ≠ 消费完成） |
| `POST /api/daemon/execution-control/checkpoints` | 上报 signed checkpoint（恢复对齐） |
| `GET /api/daemon/execution-control/merge-facts/{crID}` | 只读 merge 事实（R2；workspace 由认证主体解析，请求只带 crID） |
| `POST /api/daemon/crs/{crID}/merge-effects` | `op=reserve|report` 的撤销线性化写端点（R3） |

- 认证：MDT + enrolled key/owner scope；**拒绝** PAT/JWT/task-token 回退（一律 `403 …_UNTRUSTED`）。
- POST 首次有效入账 201、exact replay 200、冲突 409；invalid 400、untrusted 403、unavailable 503。
- Tx 签名（proposed）：`ResolveCandidateTx`、`AdmitDispatchRootTx`、`EnqueuePipelineTaskTx`、`RegisterFreshWorkTx`、
  `EnsureRequestTx`、`BeginOwnerTx`、`ReconcileOwnerTx`、`IngestTx`、`SettleCandidateTx`、
  `BindDeliveredGenerationTx`、`CommittedTReader.ReadCommitted`、`CheckDeploymentAccessTx`、
  `RecordReadinessTx`、`ActivatePolicyTx`、`StopNewAdmissionsTx`、`BeginLegacyDrainTx`、`FinalizeLegacyRetirementTx`、
  `PrepareLaunch`/`CommitLaunch`。
- 真实 task 启动前按真实 task/runtime/`dispatched_at`/daemon generation 校验 643 binding issue、644 consumption、
  645 activation，并逐字段核 issuance envelope/head/challenge；失败或未完成之前不启动 agent。

### 7. 失败码

- verdict 侧闭集：`T_VERDICT_{UNTRUSTED,INVALID,BINDING_MISMATCH,CONFLICT,SEQUENCE_GAP,STALE,STORE_UNAVAILABLE,FENCED,RECOVERY_REQUIRED,UNAVAILABLE}`；未知 code 拒绝。
- 保留 `WAIT_CONSUMPTION/WAIT_EVIDENCE/DENY_STOPPED/DENY_RESUME/DENY_SPECIAL_AUTHORIZATION`；quota deny 只消费 T 裁决。
- merge-facts：`200 / 400 MERGE_FACTS_INVALID / 403 MERGE_FACTS_UNTRUSTED / 404 MERGE_FACTS_NOT_FOUND / 503 MERGE_FACTS_UNAVAILABLE`。
- merge-effects：`MERGE_EFFECT_{INVALID,NOT_FOUND,UNTRUSTED,REVOKED,HEAD_MOVED,INPUT_MISMATCH,CONFLICT,UNAVAILABLE}`，
  码序 `INVALID>UNTRUSTED>NOT_FOUND>REVOKED>HEAD_MOVED>INPUT_MISMATCH>CONFLICT>UNAVAILABLE`。
- 失败码的 CLI 外层映射与优先级以方案 R2.4 为唯一权威，本仓只实现端点侧判定。

### 8. D7 部署就绪控制面

- **T 决定 ready，M 决定是否原子启用**；M 只做身份、绑定、不可变性、当前 generation/有效期/CAS 的效力检查。
- 对象是 `scope × target_policy × deployment_generation`，不是某 lineage 的预算操作；action 闭集
  `verify-channel|enable-policy|retire-legacy-relay`，profile 为 `channel-component|strict-production`。
- `verify-channel` 只能记 `READY_COMPONENT`，不得调用生产 activation，也不得当作 business permit。
- inventory 必须覆盖**所有仍有资格**的实例与安装目标；离线旧实例须核实或先撤销其接单/写入资格。
- 生产默认**不装配**新 channel/reader/decider；无新增 env 启用开关；测试 composition 显式注入真实组件。

#### 8.1 `channel-component` profile v1（SPEC 冻结）

本 change 自己定义、自己验收的组件 profile；只能产出 `READY_COMPONENT`，不得用于生产 activation。

| 组件 ID | 版本/摘要语义 | 观测来源（受保护） | 恢复能力要求 |
|---|---|---|---|
| `multica-server` | 构建 commit + 648 迁移后 14 表 schema 摘要（`ChannelTableNames` 顺序，SHA256） | supervisor 测量的实际进程与安装根 | 重启后 command/receipt 原字节可恢复 |
| `multica-daemon` | 构建 commit + execution-control client 版本 | 同上，按稳定实例 ID 逐个 | 接受新 fence 后才返回 checkpoint |
| `tools-runtime` | 既有 `toolsRuntimeDigest`（受保护实际 runtime 根，不用 marker digest） | installer 测量的 runtime 根 | 恢复表五类动作 |
| `trust-manifest` | `execution-control-trust-manifest/v1` 原始字节 SHA256 + 绝对路径 pin | operator 受保护路径 | 不适用（静态信任根） |
| `protected-store` | store 根身份 + `store_id`/`epoch` | worker 自行读取固定 facts | 缺失即 freeze，不建空 store |
| `readiness-evaluator` | `component-readiness.mjs` 严格入口版本 | tools-runtime 内 | 不适用 |

- `AdmissionDecider` **不在**本 profile；它是 `strict-production` 的必需项，缺失即 NOT_READY（SC-DR-003）。
- `not-applicable` 只允许表中显式写明的两项；其余缺项、重复、unknown 一律 NOT_READY。
- **UNVERIFIED**：`strict-production` profile 的完整内容、真实实例清单与安装目标需部署授权，不在 Gate 2 冻结；未获授权前 S8 只用隔离夹具验证事务原语，不称生产 READY。

### 9. 迁移策略

- 只新增 `648_cr_execution_control.{up,down}.sql`；647 为当前最大。若实施时 648 已被占用，
  **先更新本规范与全部命令**，再顺延编号，不覆盖既有迁移。
- down 必须撤销全部 14 张表及其触发器/索引；reapply 验证同名对象恢复且无遗留业务行。
- 迁移专例在**本次独占 nonce 库**运行，且先造 643–647 夹具，断言其行/对象不变、无 648 孤儿对象。
- 不修改 DB runner/白名单，不对保留库执行 down/reset。

## 切片与依赖

| 片 | 内容 | 依赖 |
|---|---|---|
| S1 | selection/reservation/root/fresh-work + `task_tx` | 648 迁移 |
| S2 | wire/key-purpose 与跨语言向量（Go 侧） | S1 |
| S3/S4 | store 状态机、owner fence、恢复（Go 侧） | S1、S2 |
| S5 | typed facts、repair/resume、sensitive action 接线 | S3/S4 |
| S6 | ingest/settlement/binding + 迁移专例 | S3/S5 |
| S7 | reader、projection fence、终态 fence | S6 |
| R2 | `merge-facts` 端点 + `code_source_freeze` | S1（selection）、S7（fence） |
| R3 | `merge-effects` reserve/report | R2 |
| S8 | D7 readiness/activation/launch（R0–R4） | S1、S7 |

**P0 门控（Gate 2 前用户采纳）**：P0（隔离证明，SC-VC-037）排第一，但只阻塞依赖「daemon 持 T worker」（方案 C）的片；失败即停止 C 路径，转 B 须另行提审，**禁止运行时 silent fallback**。

| 分组 | 片 | P0 未绿时 |
|---|---|---|
| 两条路径都适用 | M-0 迁移、M-S1 selection/reservation/root、M-R2 merge-facts、M-R3 merge-effects（复用 DB 层状态机，不触 worker） | 可先行 |
| 依赖 C 路径 | M-S2 协议的 daemon trust 部分、M-S3/M-S4 worker 与恢复、M-S6 daemon client/binding、M-S7 composition、M-S8 observer/launch | 阻塞 |

若 Linux 与 Windows 隔离环境授权短期不可得，只推进「两条路径都适用」组；P0 失败转 B 时，该组产物按 B 方案复核后保留，不默认作废也不默认沿用。

## 残余风险与非目标

- 端点只保证事实可信，不保证执行强制；仓库侧闸门不在本 change。
- 不实现完整 `AdmissionDecider`、四阶段/resume 单 effect Runner、RUN-009 修复与 AIFI-45 业务 TC/E2E。
- 不做 legacy 业务迁移（D8=A），不导入旧 workspace ledger，不新增迁移动词。
- 不部署、不启用、不做真实 CR 操作；不引入第三个决策服务或新工作流引擎。
- 通道组件通过不自动回填 AIFI-45 的 41/49，禁止跨 change 双计。

## 修订记录

| 日期 | 修订 | 结论是否受影响 |
|---|---|---|
| 2026-10-27 | 初稿（Gate 2 草案） | — |
| 2026-10-27 | Gate 2 前采纳建议：SPEC 冻结 `validation/channel-test-expectations.json`（41 label / 215 leaf，逐 leaf 标 SC）；补 P0 为 SC-VC-037；新增 §8.1 `channel-component` profile；P0 改为只阻塞 C 路径片；agent spec 命令对齐方案 `rungo` 标签，`TestChannelDeploymentAccess` 归 governance（原误写 daemon），包路径改为 `./internal/...` | 否：范围、表、端点与必达 leaf 下限不变；P0 由遗漏补回为方案已有要求 |

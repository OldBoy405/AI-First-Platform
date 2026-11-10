> 产出方式：STDD `design` 档（`model_tiers.design: strong`）只读作者会话 `01a176ef-402a-77b9-a3c5-0f47830ba4c7`；requested `OpenAIPersonal/gpt-6.1-sol:high`，actual 无后端回执 = unknown。主会话从该会话记录原样提取最终回复落盘，未改写。
> 状态：**历史草案 v0.1，已被独立 strong 审查 BLOCK，不得据此实施**。正文保留作者当时的快照；原始提取摘要前缀 `9d3e8827593773af` 仅指补注前文件，不是当前文件摘要。审查见 `trusted-verdict-channel-review-20261026-strong.md`；修订实施方案另存 `trusted-verdict-channel-implementation-plan-20261026.md`。
> 当前事实：F4 已修并验证；正文“helper 只锁 cr”等引用是修复前状态，定位以路径/符号为准。此文件放在 AIFI-45 `validation/` 仅作依赖设计资料，不表示新 change 已注册。新方案须经人类审阅与正常 Gate；没有 Gate3、commit/push 或部署授权。

# Design：可信 T committed verdict channel
## 1. Change、范围与目标
- **建议 change id**：`2026-10-26-aifi-trusted-tools-verdict-channel`；新 change，不并回 AIFI-45 的 dispatch-admission 实现。
- **涉及仓库**：`multica`、`tools`；平台 change 文档由 host 持久化，本次不写文件。
- 路径别名：`M=C:/Users/GOBAO/Downloads/AI/multica`；`G=M/server/internal/governance`；`D=M/server/internal/daemon`；`T=C:/Users/GOBAO/Downloads/AI/tools/skills/shared/crctl/scripts`。
- `P=C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/dispatch-admission-design-20261026.md`；以下引用均为这些路径下的 `file:line`。
- **目标**：建立 server 发起、隔离 control worker 执行、daemon 证明来源、server 验证入账的通道，将 T **实际提交**的 execution consumption、repair admit/outcome/assessment/stop/resume、exact sensitive-action consumption、evidence-delivery verdict 转换为 `AdmissionDecider` 的可信输入；所有额度、重试、no-progress 规则仍只在 T 求值。对应缺口为 `P:43–45,124–125`。
- **非目标**：不让 agent stdout、workspace JSON、Git commit、ACK 或平台 receipt 获得授权效力；不重写 Go budget 引擎；不把 local ledger 改造成 Git write-set；不保证外部副作用 exactly-once；不自动迁移历史不可信 ledger；不自行批准 Gate3 或启用 production admission。
- **状态约定**：下文所有新增类型、文件、表、协议、测试及部署要求均为 **PROPOSED**。本次只 read/grep，没有修改文件、执行测试、访问 DB 或验证部署隔离。

## 2. 已有机制评估：可复用什么，不能信任什么
### 2.1 crsync 的精确信任模型
- outbox 由 `crctl.emitOutboxEvent` 写入 install-root `.crctl/outbox`，并写 `.gitignore=*`；发射失败只审计、不阻断主操作。因此它不是 Git 内的可靠事务提交证明。`T/crctl.mjs:459–496`。
- daemon 同时扫描本地 outbox 与 Git commit，合并后 POST `/api/daemon/cr-events`；全部批次成功才推进 scan cursor。**不是 server 从 GitHub 拉取 outbox**。`D/crevents.go:657–720`。
- commit fallback 执行 `git log --reverse`，按 subject 解析事件；review 从该 SHA 的 annotation 生成 payload，核 CR/type，但没有验证事件生产者签名。`D/crevents.go:1123–1169,1211–1250,1340–1401`。
- HTTP route 使用 `DaemonAuth`；MDT 路径验证 token 并注入 workspace/daemon；middleware 也兼容 PAT/JWT 等路径。`M/server/cmd/server/router.go:1647–1653`；`M/server/internal/middleware/daemon_auth.go:63–78,116–155,207–285`。
- crsync 的 workspace 来自 auth context；fallback 使用 server-set user identity、`X-Workspace-ID` 与 membership 查询。body 中 root hash 不是身份依据。`G/crsync.go:152–166`；`G/daemon_workspace.go:28–60`。
- `OutboxEvent` 没有签名字段；validation 检查版本、CR、kind、时间及部分 payload 限制；普通入账按 `(workspace,CR,commit_sha,event_kind)` 去重。`G/crsync.go:104–119,196–223,268–289`。
- `apply` 将 review 交给 `applyReview`；后者核 CR、stage、attempt、reserved key 后可写 node `passed/blocked` 与 detail。它是投影，不是独立 reviewer 或 T commit 的认证器。`G/crsync.go:439–446`；`G/gate_projection.go:350–435`。
- **结论：能够让伪造 commit 进入被扫描 ref 的 repo writer，可制造格式正确的合法 status/review 投影**；仍须满足解析、CR/type、transition、attempt 等检查，并非任意 payload 都通过。空 trigger 仅按 from/to 匹配。认证的是 relay 的 workspace 身份，不是 commit 作者或工具执行。`D/crevents.go:1220–1248,1345–1377`；`G/transitions_gen.go:96–105`。
- `postEvents` 测试直接注入 daemon context、发送构造事件，并未建立签名生产者信任。`G/crsync_test.go:123–149,174–188`。
- server reconcile 的 `REMOTE_RECONCILE_MODE=server` 启用 GitHub polling；`KNOWLEDGE_BASE_REMOTE_URL/TOKEN` 指定仓库与读取凭据，unset/daemon 不挂该 job。token 作为 GitHub Bearer 使用，不是 T verdict 签名。`G/reconcile_github.go:37–66,235–244`。
- reconcile 固定 default-branch SHA，非 finalize CR 优先固定 requirement-branch SHA，再读 `cr.md`；当前返回 status snapshot，不返回可信 ledger verdict。repo writer 修改这些被选来源同样可改变投影内容。`G/reconcile_github.go:112–220`。
- reconcile job 当前把一个 knowledge-base snapshot 应用于所有含 CR 的 workspace；多 KB 映射不是现成能力。`G/reconcile_github.go:263–306`。
- **可复用**：envelope、batch/retry、workspace scoping、trace 的 insert-or-load/immutable-payload/processed-after-commit 模式；**不可复用为信任根**：unsigned event、commit SHA、`processed_at` 或 review projection。`G/crsync.go:349–436`。

### 2.2 Signed grants
- server 从 `APPROVAL_SIGNING_KEY/_ID` 加载 Ed25519 key；execution 使用 `{key_id,payload_b64,signature}`，对原始 payload bytes 加 domain 签名；grant digest 为 `SHA256(domain || payload)`。`G/approval.go:183–226`；`G/execution_authorization.go:163–169,374–379,403–427`。
- operator manifest 按绝对路径、固定 SHA256、exact 四字段读入；不能直接往现有 v1 塞 verdict key/tool 配置。`G/execution_contract_manifest.go:42–123`。
- T verifier 严格处理 JSON、canonical base64、Ed25519 与 domain；目前只接受 authorization/binding 两域，授权 payload 只验证 initial/revoke。`T/lib/execution-authorization.mjs:48–80,346–402`。
- human authorize 核 middleware actor、owner/admin、DB scope；初始授权不可变重放，不是新的 current-head 验证。`G/execution_authorization_http.go:44–85,119–180`。
- **可复用**：签名字节与 source freeze 模式；**不能推出**：signed grant 已被 T 消费、signed resume 已存在，或 quota 已提交。

### 2.3 Daemon、平台 ledgers 与 T 持久化
- F1：loopback endpoint 的随机 bearer URL 交给 run；持 URL 者可提交 challenge。它不证明调用进程身份，本 change 不扩展它的权限。`D/execution_binding_endpoint.go:30–32,84–102,141–154`。
- F7：仓库 grep 发现 `relayExecutionBinding` 只有定义与测试调用；私有 pipe 也明确不是 same-UID containment。不得把已有 relay 描述成 production trusted consumption 链。`D/execution_binding_relay.go:17–28,77`；`D/execution_binding_relay_test.go:100,155,183,210`。
- **需纠正文档陈旧注释**：`New()` 实际已经设置 `recordConsumptionAfterDelivery=true`，run 收尾调用 recorder；client 注释仍称 production off。该 receipt 仍只记录 proof delivery，不是 T commit。`D/daemon.go:848–852,8764–8766`；`D/execution_consumption_client.go:10–17,55–71`。
- strict daemon preflight 安装并静态检查 grant 后仍返回 `EXECUTION_CONSUMPTION_REQUIRED`；resolver 目前查工具路径存在和 `node` PATH，不做安装包 pin。`D/execution_verifier.go:54–67,82–111`；`D/pipeline_task.go:863–877`。
- trust store 在 daemon HOME 下、workspace 外，拒绝不同内容覆盖；这不是已验证的 OS 隔离证明。relay 还明确说明 same-UID 风险。`D/execution_trust.go:47–81,87–129`；`D/execution_binding_relay.go:27–28`。
- 643 按 head/challenge 唯一，未含 generation；644/645 按 runtime/task/dispatched_at 唯一，均无新 FK/cascade；645 拒绝 UPDATE/DELETE/TRUNCATE。`M/server/migrations/643_cr_execution_binding_issue.up.sql:1–19`；`644_cr_execution_consumption.up.sql:1–23`；`645_cr_execution_activation.up.sql:1–40`。
- consumption 的 issuance EXISTS 仅比 workspace/CR/head/challenge；activation 查同 generation consumption。新 consumer 必须额外核完整 tuple，不以 EXISTS 或 receipt ID 代替。`G/execution_consumption.go:168–179`；`G/execution_activation.go:166–218`。
- T 的 repair/action ledger 使用 local durable write；repair resume 只核 reviewer/current subject 并写 epoch；evidence evaluator 是 facts-in/findings-out，当前没有提交 delivery verdict。`T/lib/repair-governance.mjs:107–110,412–456`；`T/lib/execution-sensitive-action.mjs:104–122`；`T/lib/evidence-delivery.mjs:15–18,30–112`。
- `durableWriteFile` 是 temp/fsync/rename，部分 fsync 错误被忽略；recoverable write-set 是 prepared/redo 协议，不是多文件同时原子可见。`T/lib/durable-tx.mjs:85–103,361–428`。
- execution Git adapter 只拥有三个 CR 文件，不能直接拿来提交 repairs/actions ledger。`T/lib/execution-transaction.mjs:33–36,153–184`。
- repair CLI 仅 decode grant，reviewer facts 来自 workspace ledger；authorization-bind 仍关闭消费。必须替换 trusted 路径的事实采集，不能直接签现有 CLI 输出。`T/crctl.mjs:1596–1650,1880–1894`。

## 3. Threat model 与最小信任根
| Actor | 本设计按其能够伪造的内容建模 | 不授予的能力 |
|---|---|---|
| Agent process | 自己的 stdout、参数、workspace 文件、可写 Git history、labels/reviewer 自报、泄露的 F1 URL | 不能签 verdict，不能选择 control executable、ledger root、command identity |
| Repo writer | 所有可写 repo 文本、commit author、annotations、伪造 outbox；见 §2.1 | Git 可达性/作者签名不等于 trusted T execution |
| Trusted daemon/control worker | 能执行 T、提交其私有 ledger、生成 verdict；若被攻陷即可伪造自己的 attestations | 不持有 human approval 私钥；不能签其他 workspace/daemon 的结果 |
| Server | 能安排 command、持有 current head/DB、执行 admission；server compromise 可绕过本边界 | 不从 result 中重新计算预算；不代替 T 宣告业务消费 |
| Human authorizer | 能批准 scope、revoke、签发受限 resume；权限取现有 owner/admin 检查 | 普通“继续”、repo 修改或 ACK 不构成 resume |

- **最小信任根**：server/DB 与既有 approval key；operator 固定的 daemon attestation public key、tools/runtime artifact；真正隔离的 control worker、私有 ledger 与私钥。
- **新安全前提，不冒称已存在**：agent 无权读私钥/daemon credential、写控制代码/ledger、注入 worker 环境或访问 control pipe。workspace 外目录和 PID/PPID 不足以证明这些条件。
- 推荐首个支持部署使用独立服务身份与受限 agent 身份；不满足隔离时保持 fail-closed。Windows/Linux 实际隔离能力及部署均 **UNVERIFIED**，必须做真实越权探针。

## 4. Options
表中 `B` 表示完整绑定：workspace/project/CR、lineage、run/pipeline/node/node-run/attempt、generation、subject、head digest/revision、origin/logical-step、exact candidate/action。

| 方案 | Authenticity / B | T commit → M advance | Replay / idempotency | 两个 crash window | 成本 / blast radius |
|---|---|---|---|---|---|
| A：复用 crsync，新增 signed verdict payload | 必须增加受保护 producer key 与 B；unsigned 版本不合格 | Git/outbox 与 local ledger 不同事务，须先 protected commit 再可靠发射 | 不能沿用普通 DO NOTHING；须 immutable payload conflict + sequence | T 已提交/M 未收到靠私有 outbox 重送；M 已提交/响应丢靠 exact replay | 中高；collector、kinds、reconcile、projection 都需隔离新语义 |
| B：server 在可信环境重新执行 T engine，不信任外部 T 输出 | server 固定输入与工具；B 来自 DB 和可信 capture | server-hosted T durable commit 后才允许 DB effect | command ID + protected store + DB mapping | 同样需恢复 T/DB 非分布式事务；丢响应返回原 mapping | 高；引入 server Node/runtime、repo capture 与唯一 ledger owner；不应另写 Go budget |
| **C：daemon-owned 隔离 T control worker + signed committed verdict** | operator-enrolled daemon key；server-signed command；worker 重验事实与 B | **显式 committed frame 后签名、入账后 admission** | request ID、lineage sequence、稳定业务 receipt、effect mapping | T commit 后重发原结果；M commit 后 exact replay 原 effect | **中高，推荐**；集中新 worker/API/store，现有 relay/CLI 仅窄挂点 |

- 选择 C：接近现有 daemon trust/install/Node 调用边界，但不能直接复用 arbitrary `Command` relay 或普通 stdout parser。现有锚点为 `D/execution_verifier.go:82–111`、`D/execution_binding_relay.go:54–77`。
- A 可作为以后 signed verdict 的**非可信运输载体**；本期不让 crsync 成为 admission 入口，避免“投影 accepted=授权 accepted”。
- B 是可行替代：仍复用同一 T 规则函数；若组织不能提供 daemon/agent 隔离，应选 B，而非弱化 C 的根。

## 5. 推荐协议与持久化
### 5.1 Server command、key 与 wire
- 新增独立、operator-pinned `execution-verdict-trust-manifest/v1`：允许的 workspace/daemon/coordinator、attestation key、tools digest、store ID/epoch；复用 existing manifest loader 模式，**不修改旧 manifest 四字段语义**。
- server 用既有 approval Ed25519 key 签 `execution-control-command/v1\0 || payloadBytes`；worker 用 pinned server public key 验证。仅 server 内部 planner 可创建 command，agent payload 只是待核实候选。
- daemon 独立 attestation key 仅签 `execution-verdict/v1`；**不导出 approval 私钥到 daemon、不把 key 放 env/agent workspace、不开放 sign(payload) HTTP 接口**。public key 由 operator 绑定，不接受 request 内自带 key 或自动 enrollment。
- 新 wire 复用 `{key_id,payload_b64,signature}`；签名与 digest 都复用 **Ed25519 + SHA256(domain || 原始 payload bytes)**。扩展固定 domain allowlist，不能把现有 verifier 改成“任意 schema 都验证”。既有格式见 `G/execution_authorization.go:163–169,420–427`、`T/lib/execution-authorization.mjs:374–402`。
```text
execution-control-command/v1:
  schema,key_id,request_id,operation,nonce,expected_seq,previous_verdict_digest,
  workspace_id,project_id,cr_id,lineage_id,coordinator_binding,
  run_id,pipeline_id,node_id,node_run_id,attempt,source_task_id,executor_agent_id,
  generation:{task_id,runtime_id,dispatched_at,daemon_id},
  candidate:{intent,proposed_task_id,logical_step,origin_ref},
  subject:{kind,ref,sha256,repository_revisions},
  head:{record_id,grant_id,digest,authorization_revision},
  policy_digest,template_digest,tools_digest,store_id,store_epoch,
  fact_refs,resume_grant_ref?,action?
execution-verdict/v1:
  schema,key_id,request_id,command_digest,sequence,previous_verdict_digest,
  [完整回显上述 scope/run/generation/candidate/subject/head/deployment/store 绑定],
  operation,commit_ref,receipt_ref,disposition,code,replayed,
  repair?,resume?,action?,evidence?
```
- operation 闭集：`execution-consume|repair-admit|repair-outcome|repair-assess|repair-resume|sensitive-consume|evidence-delivery`；业务 payload 分支 exact-key 校验，不适用字段必须不存在。
- `disposition` 闭集：`permit|continue-exact|deny|stopped|pending`；operation 自身完成不等于 dispatch permit，例如 outcome/resume 成功不能直接授予任意新 root。
- `commit_ref={store_id,store_epoch,sequence,tx_id}`，**不是 Git SHA**；`receipt_ref` 优先复用现有业务 receipt，outcome/assessment/evidence 使用本次 committed event ID。
- `consumed/limit` 仅诊断，M decoder/decider 不暴露用于授权的数字接口；head digest、subject digest、tools digest沿用各自既有定义，不重新序列化 grant 或发明第二套 canonical digest。
- JSON 限制建议沿用 safe integers、UTF8、无重复键、exact keys、固定 nesting/body limits；signed bytes 不做 CRLF normalization。现有规则见 `T/lib/execution-authorization.mjs:45–80`。

### 5.2 可信执行与 T commit
1. server 从 DB/compiled registry/current head 构造 command；在事务中固定 candidate ID、generation 映射、subject refs 与 lineage command slot，再 commit；不在持 DB 锁时等待 worker。
2. daemon 只从 authenticated server command queue 接单；校验 server 签名、owner/store epoch、部署 pin。使用固定 executable、净化环境、私有 control pipe；不继承 F1 URL，不接受 task 提供的 argv/root。
3. worker 重验 grant/source、command、实际安装根和 subject；reviewer/implementer identity 由 server task-attribution refs 与 daemon-owned capture 交叉核验，**不能取 repo `by/reviewer` 自报作为身份**。
4. repo 内容可以作为被审对象/阻断文本，但必须按固定 revision capture、重新计算既有 subject/origin digest；review/test verdict 必须能归属真实已登记 attempt。无法核实则 pending/deny，不签“已验证事实”。
5. 复用 repair/action/evidence 规则函数，改为显式注入 `LedgerStore`；默认 local store 保留旧 CLI 行为，trusted 路径使用 protected store。不得 monkey-patch fs 或复制预算条件。
6. protected store 每 lineage 使用一个原子发布的 **业务 after-image + request-result index + pending verdict outbox** bundle；跨 action/repair 的相关状态同属该事务。journal 恢复到完整状态前不能发 committed frame。
7. 在同一 lineage 锁下先按 request ID 查结果，再求值；这样 outcome retry、assessment 重投、resume 重投也不会重复递增或追加。拒绝可提交审计 verdict，但不消费业务额度。
8. durable commit 成功后 worker 才经私有 pipe 发 `CommittedResult`；daemon 只为自己登记 command 的可信 worker frame 签名。普通 agent stdout、磁盘扫描、文件名或退出码均不能进入 signer。
9. crash 后由同一受保护 worker 恢复原 command，再返回已提交结果；M 不读取本机 JSON。bundle 是 T 的内部持久化，不是可提交到 M 的证据格式。
10. trusted store 使用可检测失败的 fsync/rename 路径；不把现有 best-effort fsync 承诺升级为强耐久性。旧 primitive 的兼容模式保留，新增 strict durability 模式及故障测试。

### 5.3 Ordering、freshness 与 DB
- 每 `(workspace,CR,lineage)` **最多一个未解决 command**；覆盖所有上述 operations，不只是 admit。新 command 不能越过旧 command 的 T-commit/M-settlement 窗口。
- 每结果递增 sequence、链接 previous verdict digest；M 只接受期望下一项，同 request 同 bytes 返回原结果，同 ID 不同 bytes拒绝。乱序/缺项不猜、不按 occurred_at 排序。
- result 入账后 command 保持 `result_ready`；与 admission effect 的 commit 或明确 `no_effect` settlement 同事务才释放 slot。不能先 ACK/release，再让旧 permit 与后来的 stop 竞争。
- 每次新 admission 要求对应当前 command 的结果；旧 receipt 可以定位原任务，但不能短路 current head、stop、subject 或 generation 检查。
- 建议新增迁移，编号实施时分配：`cr_execution_control_command`、`cr_execution_tool_verdict`、`cr_execution_tool_cursor`；新表 **不加 FK/cascade**，软引用由应用验证，沿用 643–645 规则。
- command：固定 command envelope/candidate、唯一 request ID、受限状态与最终 effect mapping；partial unique index 限制每 lineage 一个 open slot。
- verdict：原始 envelope、原始 payload bytes/digest、绑定索引、commit/receipt refs；unique `(workspace,request_id)` 和 `(workspace,CR,lineage,store_epoch,sequence)`；拒绝 UPDATE/DELETE/TRUNCATE。
- cursor：expected sequence/digest、owner/store epoch；row lock + CAS 更新。**M 不保存可用于重新决策的 repair/action 累计器**。
- ACK 丢失不删除 T outbox；M commit/response lost 重试返回原 verdict/effect refs，不再次求值、不创建 task。T committed/M 未提交则重送原结果；M 拒绝 stale head 时保存 audit/no-effect、不退款。
- 新表必须明确 workspace deletion 分类：verdict audit `keep`，command/cursor `settle`；应用禁新命令、收敛 pending，不借 cascade 删除历史。现有 schema-coverage 约束见 `M/server/internal/handler/workspace_delete_manifest_test.go:17–20,166–180`。
- ledger owner 只能是冻结 coordinator/store；迁机、备份回滚、丢失 store、seq 回退一律 freeze，不能创建空 ledger 重开额度。

## 6. M consumer、AdmissionDecider 与 signed resume
- 新增 `GET /api/daemon/execution-control/commands`、`POST /api/daemon/crs/{crID}/execution-verdicts`；仅 MDT auth + operator-enrolled daemon key，拒绝普通 PAT/JWT/task-token fallback。
- POST 严格验 domain/key、完整 B、command digest/nonce、owner/epoch、sequence 与原始 bytes；事务入账后 201，exact replay 200，冲突 409；HTTP accepted **不等于 effect admitted**。
- 新增 `CommittedTReader.ReadCommitted(ctx,tx,key) (TDecision,ResumeProof,Action,error)`；仅查询验证后的 ledger 和 command mapping，不在 decider 内发网络请求、调用 Node 或扫描文件。
- decider 沿用 `P:71–80` 顺序：先 DB binding/current head，再 T committed result，再 root/adoption；未知值/error 永不产生 effect。result-ready 到 root/task/effect mapping/command settlement 使用调用者同一 Tx。
- generation 明确区分 **已存在 source/control generation** 与 **尚未 enqueue 的 target ProposedTaskID**；两者都绑定 command，不把 target 候选冒称 active claim。现有 active claim 只认 queue/task/runtime join，见 `M/server/pkg/db/queries/execution_binding.sql:1–18`。
- 无合法 source/control generation 时返回 `WAIT_CONSUMPTION`；不为取得 proof 偷建 execution task。冷启动 generation 建立方式为 AIFI-45 前置接口决策，见 §8/H3。
- 643/644/645 仍为必要的 generation/platform facts，非 T consumption。新增完整 issuance-envelope/generation/head/challenge 交叉检查，不通过 F1 或“delivery recorder 已写 receipt”放行。
- 为新合同增加 projection fence：unsigned crsync/status/reconcile 只更新可诊断投影，不得修改 strict Runner 的授权性 node/run state，也不能成为 fact identity 来源。legacy 保留原行为；应覆盖 `projectGateTransition` 和 `applyReview` 两条写路。现有写路见 `G/gate_projection.go:62–115,350–435`。
- 新增独立 `execution-repair-resume/v1` 与 record wrapper，仍用现有 server approval key；受相同 human owner/admin 检查，冻结原始来源并绑定 lineage、current head/revision、origin、stop_ref、subject、evidence refs、expected epoch、grant ID。
- resume 不修改 authorization/v1 字段集、不增加额度、不复活 revoke/terminal root。T 验签及绑定后调用唯一 resume 规则；幂等身份改为 `(resume_grant_id,stop_ref,subject,expected_epoch)`，M 只消费 resulting proof。
- trusted evidence path 要提交 `evaluateEvidenceDelivery` 的结果及其固定 fact refs；不得继续使用 CLI “有非空 test-report/有某 grant 文件”的采集结果冒称可信证据。当前较弱采集见 `T/crctl.mjs:1786–1808`。
- **fail-closed codes**：集中注册 `T_VERDICT_{UNTRUSTED,INVALID,BINDING_MISMATCH,CONFLICT,SEQUENCE_GAP,STALE,STORE_UNAVAILABLE}`；分别映射 `DENY_T_VERDICT/DENY_BINDING/DENY_UNAVAILABLE`，effect 均 None。
- 无 committed consumption→`WAIT_CONSUMPTION`；可信 pending→`WAIT_EVIDENCE`；T quota exhausted→`DENY_T_VERDICT`；stop→`DENY_STOPPED`；resume/action 缺专项→`DENY_RESUME/DENY_SPECIAL_AUTHORIZATION`。保留原 T code 作诊断，禁止按 message 或 consumed/limit 放宽。

## 7. Vertical slices、TC 与 RED mutations
所有新测试文件均为 proposed；每片先 RED 再 GREEN，保存 mutation diff/raw logs。下列“解阻”是具备 AIFI-45 seams 后的正向路径依赖，不是当前已通过。

| 顺序 / 文件 | Given / When / Then | 必须失败的 RED mutation | 解阻 |
|---|---|---|---|
| S1：协议/根；新增 `G/execution_tool_verdict{,_test}.go`、`D/execution_control_trust{,_test}.go`、`T/lib/execution-control-protocol.mjs`、`T/test/execution-control-protocol.test.mjs` | Given pinned command/key；When 改 domain、duplicate key、任一 B 字段或注入 agent stdout；Then 无可接受 verdict，合法 Go↔Node 字节向量通过 | 删除 signature verification 或 subject/generation equality | 所有 TC 的认证基础 |
| S2：protected transaction；新增 `T/lib/execution-control-store.mjs`，改 `durable-tx.mjs`、repair/action 的 store seam；新增 fault tests | Given 同一 admit/outcome/assessment request；When 在 rename 前后 kill、并发重投；Then 恢复原结果、一次消费/一次 assessment、未完成事务无 committed frame | 将 committed frame 移到 durable commit 前 | 003、006、010 的 T commit 基础 |
| S3：worker/plumbing；新增 `D/execution_control_worker.go`、client/tests、`T/lib/execution-control-worker.mjs`；窄接 `execution_verifier.go`、`crctl.mjs` | Given daemon 固定工具/私有 root 与 server command；When agent 用 F1 URL、假 argv、替换工具、访问 pipe/root；Then 不触发 verdict signer；合法 worker 可提交 | 允许 task argv 选择 worker，或让 F1 endpoint 调 signer | 002/003 正向链 |
| S4：ingest/order；新增上述 migrations、`G/execution_control_command.go`、`execution_tool_ingest.go` 及 DB/race tests；扩 routes | Given T 已提交；When M rollback/丢响应/重复/乱序、permit 后 stop 排队；Then 重送原结果、exact replay，slot 未 settlement 不越序 | 在 result-ready 时提前释放 lineage slot，或冲突按 DO NOTHING 接受 | 003；006 stop 顺序 |
| S5：repair/resume/evidence；改 `repair-governance.mjs` store/replay seam、`evidence-delivery.mjs` commit wrapper；新增 trusted fact resolver、`G/execution_repair_resume.go`/tests | Given signed grant、真实 reviewer attempt/current subject；When quota exhausted、两次 no-progress、伪 reviewer/旧 subject/unsigned resume；Then T 拒绝；合法 signed resume 仅一次 epoch，旧预算不重置 | quota exhausted 改 permit；resume 跳过 grant signature/stop_ref equality | **006 完整正向** |
| S6：Admission adapter/projection fence；新增 `G/execution_tool_reader.go`/integration tests，窄接 AIFI-45 decider 与 `gate_projection.go` | Given ACK、平台 receipt、伪 Git pass 但 T 尚未 commit；When wake；Then 无 passed/root/task；T commit 后只创建绑定下一步，重复 wake 不增加任务 | missing-T 分支改 permit，或移除 strict projection fence | **002、003 完整正向**；006 收尾 |
| S7：action effect；改 `execution-sensitive-action.mjs` store seam；新增真实 T→reader→test-executor E2E | Given 普通 grant 与 exact 专项；When 同 operation 重投、target/environment 改变；Then 普通拒绝，exact 一次消费/一次 effect，replay 返回原引用 | 删除现有 target equality，或 replay 重新调用 executor | **010 完整正向** |

- S5 不在 M 实现 repair/no-progress 规则；既有规则锚点为 `T/lib/repair-governance.mjs:217–252,350–410`。S7 的 exact matching 锚点为 `T/lib/execution-sensitive-action.mjs:89–108`。
- S6 必须走真实 auth route、真实 T worker、真实 DB reader/decider，并有成功 owner 对照及调用观测；恒拒 stub/未启用 admission 的“零任务”不能计 TC。该防 vacuous 要求见 `P:108–118`。
- 现有 repair tests 使用 signed-looking、未验签 fixture；保留其规则单测，但不得计为新 trusted-path E2E。`T/test/repair-governance.test.mjs:14–35`。
- 验证：Node 新 tests + 现有 execution/repair 回归；Go codec/worker/ingest/race/Runner integration；migration up/down、immutable triggers、真实 UPDATE/DELETE races、workspace deletion 分类。
- DB 验证沿用 `M/scripts/aifi45-db/run.mjs` 的 approved packages/flags/migration 参数，逐次独占 disposable DB；非零 leaf、无全 SKIP、原库摘要与 cleanup 证据必需，不改 runner whitelist 让测试变绿。`M/scripts/aifi45-db/run.mjs:39–43,63–69,105–132,165–188`。
- 外部 action executor 必须以稳定 operation ID 持久幂等；执行结果未知时查原 operation，不能换 ID 再做。通道只保证许可与消费幂等，不保证外部系统事务。

## 8. AIFI-45 依赖与必须留下的接缝
- **F4 先行**：当前 helper 只 `FOR SHARE` 锁 CR，不锁 referenced approval head；真实许可前必须按 `CR → approval head → scope/resource → tool cursor/command → dispatch root` 统一锁序，并测 UPDATE/DELETE。`G/execution_head_lock.go:27–40`；修复要求见 `P:95–101`。
- **dispatch seam**：AIFI-45 留下 `AdmissionDecider`、单 effect helper、可注入 `CommittedTReader`，nil 直接 legacy，不创建控制请求/worker/wake；接口与隔离要求见 `P:24–27,81–90`。
- **事务 primitives**：留下 `admitDispatchRootTx`、fixed-ID `EnqueuePipelineTaskTx`、post-commit notification；现有 root 自开 Tx，enqueue 使用 service queries 并立即通知，不能直接组合。`G/execution_dispatch_root.go:112–150`；`M/server/internal/service/task.go:417–460`。
- **本 change 插件接口**：`ControlCommandPlanner.EnsureRequestTx(candidate)`、`CommittedTReader.ReadCommitted(tx,key)`、`GenerationBindingResolver.ResolveSourceAndTarget(tx,candidate)`、`ExecutionProjectionFence`；未配置 reader 返回 unavailable，不以空值走 legacy。
- AIFI-45 必须固定 candidate ID、subject/contract-selection 来源及 source-generation→run/node 映射；不要把完整 CLI response/任意 JSON 塞入 `AdmissionRequest`，不要让 reader 自行 enqueue。
- **UNVERIFIED**：上述新 seams、authoritative contract-selection 读源、冷启动 control-generation 建立协议均未在本次读到现成实现；不能以这个计划假定已完成。先让 AIFI-45 提供拒绝型 stub 与真实 mapping 测试，再接本 change。

## 9. 人工决策、风险与 residual limitations
| 决策 / 风险 | 推荐 |
|---|---|
| H1：能否提供真实 daemon/agent 隔离？当前仅验证到目录外置及 same-UID 风险，不是 containment | **强制前置条件**；真实 agent 身份攻击探针不过不启用 C；无法隔离则选 B，不能降级为签普通 CLI 输出 |
| H2：attestation key enrollment/rotation、ledger owner 迁移与灾备 | operator out-of-band pin，禁止 agent enrollment；绑定 store epoch；数据丢失/回滚 freeze，人工核对后迁移，不从空 ledger 恢复额度 |
| H3：首次 admission 尚无合法 source/control generation | AIFI-45 明确独立、不可执行代码的 control-generation/reservation 协议；现有 active-task claim 不被偷偷放宽。本 change 默认 `WAIT_CONSUMPTION`，此决定前不宣称冷启动全链路完成 |
| H4：历史 ledger cutover | 仅新合同、可证明新建的 lineage 自动启用；历史 untrusted JSON 不导入为可信余额。历史迁移另行人工批准，不能靠重新签 grant 清零 |
| H5：evidence 与 reviewer 的“真实性”上限 | 通道认证生产者、attempt 归属与 subject，不保证 reviewer 判断正确或测试覆盖充分；当前 evaluator 也明确 independence 是过程约束。更强 evidence completeness 另订 T 合同，不能由 M 猜测。`T/lib/evidence-delivery.mjs:49–56,73–100` |
| H6：signed resume 后 no-progress epoch 语义、追加额度 grant | 本期不悄悄改变既有 no-progress算法；人工明确新 epoch 规则后只改 T。initial/revoke 之外的增额签发仍不冒称可用，未知 purpose 拒绝。现有限制见 `T/lib/execution-authorization.mjs:346–348`、`G/execution_authorization_http.go:33–35` |
| H7：production rollout 与 retention | 独立 review/Gate3 后显式 composition wiring，不新增 env admission switch；先 shadow 验证但无 effect，再启用新 lineage。审计增长/compaction 暂不自动删除，容量不足 fail-closed |

- residual：OS/admin/server/DB-superuser compromise 不在本通道防护内；T 与 M 不是分布式事务；撤销不能收回已经执行的外部 effect；拒绝发生在 T 已消费之后也不退款。
- **验收底线**：只有“可信 T 提交 → 可验证、完整绑定、顺序一致的 verdict → 同 Tx admission effect mapping”才解锁正路径；任何一环未知，保持 None effect，而不是以更多平台 receipts 补齐证据。
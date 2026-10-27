# 设计偏离记录 — 2026-10-27-trusted-verdict-channel

> BUILD 期起用。每条记录「原设计 → 实际做法 / 原因 / 影响范围 / 结论是否受影响」。
> 未经 Gate 2 批准的范围变更不在此处顺手改，须回规格修订。

## ADJ-1（协调，2026-10-27）：EVD-007 已由 AIFI-45 会话先落到 tools 交付 gate

- **事实**：tools `f3946ce`（2026-10-27 15:41）把 `evaluateComponentReadiness` 接进 `collectEvidenceDeliveryFacts`/
  `evaluateEvidenceDelivery`，观测来源是 `dir-graph.yaml#workspace.components` 声明 + tools marker digest +
  `MULTICA_COMPONENT_*`；改动文件为 `crctl.mjs`、`lib/evidence-delivery.mjs`、`test/evidence-delivery-gate.test.mjs`。
  该提交自述「不是部署就绪（隔离/Runner 二进制/已安装版本归 G8/M002）」。multica `CUSTOM.md` 已登记到 **#219**。
- **原设计**：plan §7.1 假定 `component-readiness.mjs` 只有测试调用、无生产 caller，本 change 直接加固并新增严格入口。
- **实际做法**：
  1. 本 change 的 T-S8 **不改** EVD-007 的 opt-in 语义（未声明组件的工作区行为必须不变），只在
     `component-readiness.mjs` 内新增「严格入口 / strict 模式」，宽松结果照旧只作诊断，不得签发 deployment verdict。
  2. 不重写 `evidence-delivery.mjs`；如需把严格 readiness 折入交付 gate，另行规格修订，不在本 change 顺手改。
  3. `CUSTOM.md` 新登记从 **#220** 起（原计划 #219 已被占用）。
- **影响范围**：SC-TR-012（求值器加固）与 SC-DR-001..006（D7 路径）的实现边界；不影响必达 leaf 名单。
- **结论是否受影响**：否。范围与 S8 目标不变；变的是「严格入口与既有宽松路径共存」这一实现约束，已写入规格与任务。

## ADJ-2（单一写者，2026-10-27）：AIFI-45 会话仍在两个源码仓活动

- **事实**：tools 最近 6 个提交与 multica 最近 6 个提交均属 AIFI-45 会话（B16/EVD gate/G1/G2/G3/G5/NTF-003/EVD-007）。
- **实际做法**：本 change 先做「新增文件」类切片（`lib/execution-control-*`、新增 Go 包内文件、648 迁移），
  对共享文件的插入（`workspace-transactions.mjs` 的 merge 插入点、`repair-governance.mjs`、
  `execution-sensitive-action.mjs`、`component-readiness.mjs`）在动工前先核对方是否有未提交改动；
  检测到同文件在途即停手，不并行写同一文件。
- **影响范围**：切片顺序（不改变依赖 DAG），与 Gate 3 的证据完整性无关。
- **结论是否受影响**：否。

## ADJ-3（实现命名，2026-10-27）：`ResolveCandidateTx` → `CreateReservationTx`

- **原设计**：design §5/§6、proposal 与 canonical proposal 均写 `ResolveCandidateTx`「固定候选」。
- **实际做法**：实现名 `CreateReservationTx`（`execution_control_reservation.go`），语义未变——只接受 strict 选择、
  冻结候选字节为 digest、proposed task id 固定、表内无 dispatch 列、不写 `agent_task_queue`；并新增同一 Tx 内
  回读 selection 行（mode/lineage/scope）这一步，伪造的 `Selection` 结构体不被信任。
- **原因**：原函数名暗示「解析」，实际动作是「写入一条不可变预约」，且与 SC-VC-003 的 `AdmitDispatchRootTx`
  命名拉不开距离，测试里出现过两个同名 leaf。
- **影响范围**：只影响函数名与 tasks 2.2 表述；spec/CP/leaf 名单不变。
- **结论是否受影响**：否。
- **附**：预约测试的冲突断言用 savepoint 包裹（Postgres 23505 会中止整个事务）。该写法会让诊断信息缩减为
  「conflict」，因此断言仍精确匹配 `ErrReservationConflict`；`expectReservationConflict` 已注明。

## ADJ-4（实现边界，2026-10-27）：严格 readiness 只从新入口出，不动 EVD-007 opt-in 语义

- **事实**：tools `design.md` §S8 与 `tasks.md` 7.1 原写「加固 `evaluateComponentReadiness`：空/缺/重复/unknown/NA 绕过全拒」，
  与 ADJ-1 第 1 条（不改 opt-in 语义）在同一函数上给出相反要求。
- **实际做法**：以 ADJ-1 为准。`component-readiness.mjs` 内**新增** `evaluateStrictComponentReadiness`（fail-closed），
  既有 `evaluateComponentReadiness` 保留宽松语义、只作诊断，不签发 deployment verdict；`evidence-delivery.mjs` 不重写。
- **影响范围**：SC-TR-012 的实现方式；SC-DR-001..006 的 strict 反例仍归新入口。
- **结论是否受影响**：否；本轮已同步修正 tools `design.md`/`tasks.md` 的措辞。

## ADJ-5（数据落点，2026-10-27）：merge effect 的持久点

- **原设计缺口**：SC-VC-034 要求「同事务重验后写 issued command」，SC-VC-036 又要求 `merge_publish` 每次独立且
  **不新增表**；但 `control_command` 的键含 `lineage_id,reservation_id`，CR 级 merge effect 没有这两者。
- **实际做法**（不新增表，也不复用 execution lineage）：
  1. `merge-effects op=reserve` 落 `cr_execution_control_reservation`：`scope='merge:'+workspaceID+':'+crID`，
     `lineage_id = uuidv5(merge-effect namespace, scope+'|'+effectKind+'|'+baseSHA+'|'+inputDigest)`，
     候选字节即冻结的 merge 请求体；同 lineage 第二次 reserve 走既有唯一约束拒绝。
  2. `op=report` 落 `cr_execution_control_settlement`：`kind ∈ {effect,no_effect}`、`effect_kind='merge_publish'`、
     `fixed_candidate_digest` 与 reservation 的 digest 相等才接受。
  3. 因这两张表的 guard 是「只插入、不更新、不删除」，同事务重验后退回 `report` 等于写入一条新结算行，
     不产生 UPDATE，因此不需要为 merge 新增表或放宽不可变约束。
- **影响范围**：SC-VC-034/035/036 的落表方式与 tools `merge-effects` 客户端的 `input_digest`/`halted.reason` 载体。
- **结论是否受影响**：否；表数仍为 14，约束不变。

## ADJ-6（门控豁免，2026-10-27）：P0 未绿时允许跑的 DB 专例

- **冲突**：`slices.md` 写「required profile/隔离身份未定时不跑迁移、不跑 DB 用例」，而 M-0 迁移专例与
  S1 的 selection/reservation 属「两条路径都适用」组（门控表已把 P0 只绑到 C 路径片）。
- **实际做法**：以门控表为准——M-0、M-S1、M-R2/R3、tools 纯函数/规则/merge 三族在 P0 未绿时照常实施与验收，
  但必须经 `scripts/aifi45-db/run.mjs` 独占 nonce 库、`original_unchanged=true`、`owned_resources_cleaned=true`、`skip=0`，
  且结论只写「该库该轮通过」，不声称隔离成立。
- **影响范围**：`slices.md` 正文措辞；P0 仍阻塞 C 路径片（M-S2 daemon trust、S3/S4、S6、S7、S8）。
- **结论是否受影响**：否。

## ADJ-7（口径裁决，2026-10-27，**用户已确认**）：merge-facts 的两处规格冲突

- **404 分层**：SC-MG-009 的 `AUTH_SCOPE_UNVERIFIABLE`（主体不可验证）与 `MERGE_FACTS_NOT_FOUND`（CR 不存在）**都保留**，
  均为 404；只有传输失败/5xx/超时才 `MERGE_FACTS_UNAVAILABLE`。方案 R2.4 的「非 200 一律 UNAVAILABLE」不采用。
- **祖先判定**：用**严格祖先**（`approved_base` 必须是 candidate head 的祖先且不相等），以 SC-MG-010 为准；
  方案 R2.1 的「祖先（含相等）」不采用。
- **影响范围**：merge-facts 客户端与 handler 的判定分支；不影响必达 leaf 名单。
- **结论是否受影响**：否。

## ADJ-8（已解决，2026-10-27）：SC-VC-008 不是规格冲突，是两侧实现把 purpose 合成了两种

- **核对结论**：实施方案 v0.6.5 §2 L86-L87 本来就要求三种 purpose —— `control-command` 签 command、
  `tool-attestation` 只签 verdict/checkpoint/readiness、human-authorizer 只签 resume；L470 复述同一约束。
  在这个矩阵下「attestation 签 command 被拒」自然成立，**SC-VC-008 无需修改**。
- **实际偏差**：tools `execution-control-protocol.mjs` 把 purpose 收成 `{attestation, human}` 两种，
  command 与 verdict 共用 attestation；multica 的 Go 侧为逐字节对齐又照搬了一遍。所以之前 `exact_keys`
  只能覆盖 resume 越权。
- **已修**：两侧 `OPERATIONS` 改为三 purpose（command→`control-command`，verdict/checkpoint/readiness→
  `tool-attestation`，resume→`human`），manifest purpose 闭集同步为三值；Node 把原先「attestation 可签 command」
  的成功断言改成拒绝断言，并补 SC-VC-008 的 attestation→command 反例；Go 侧补同一反例。
- **证据**：Node `execution-control-protocol.test.mjs` 3/3；Go `TestChannelProtocol` 8/8（leaf 6），
  跑次 `af-proto3-*`；共享夹具升到 v2（三把 key、每个 case 自带 `key_id`）。
- **结论是否受影响**：否。规格不动，实现对齐。
- **残留提醒**：方案 §2 L85 要求每 key 带 `domains/scope/valid_from/valid_until`、L88 写
  digest=`SHA256(domain || payload)`，当前实现分别是「只有 pin+path」与「SHA256(payloadBytes)」。
  这两处**尚未逐条核对**，须在 S3 帧链动工前完成比对（帧链依赖 digest 公式）。

## ADJ-9（Node 缺口，2026-10-27）：重复 JSON 属性与 target union

- **事实**：Node 侧 `JSON.parse` 不拒重复属性；现有「重复 key」测试重复的是 `keys[]` 里的 `key_id`，不是 JSON 属性。
  「重复 JSON 属性」与「union 双分支」两条 SC-VC-008 要求，目前**只有 Go 侧实现了拒绝**（Go 用 token 级解码器），Node 侧没有。
- **已做的**：Go 侧拒绝 envelope 与 payload 的重复属性，并有 `exact_keys` 断言；**Node 侧已补齐**顶层重复属性拒绝
  （`assertNoDuplicateTopLevelKeys`，扫描器只覆盖顶层对象，envelope/payload 都是单对象，够用），并新增两条负例断言。
- **影响范围**：跨语言一致性（同一份含重复属性的 envelope，Go 拒、Node 可能接受）。
- **结论是否受影响**：**已消除**——Node 扫描器改为每层一个 key 集合（`assertNoDuplicateKeys`），与 Go 逐层严格解析一致；
  envelope、payload、manifest 任意深度的重复属性两侧都拒，Node 测试 3/3 绿。

## ADJ-10（残余风险，2026-10-27，用户已采纳）：本机环境下对 agent 的隔离不成立

- **事实**：Windows 用户 GOBAO 执行 `wsl.exe -u root` 免密得 uid 0；WSL `user` 属 wheel，`NOPASSWD: ALL`。agent 以 GOBAO 运行。
- **影响**：P0 两身份互隔离有证据（`validation/p0-isolation-evidence.md`，24/24 + execve trace），但 agent 能改 launcher、
  读任一私有根、冒充任一身份。设计要防的正是 agent。
- **处理**：接受为残余风险，不在本机强行关闭（WSL 的设计决定能启动发行版的 Windows 用户即是其 root）。
  C 路径片按 `channel-component` 组件级验收；**不得声称满足 `strict-production`**；Gate 3 报告单列此项。
- **解除条件**：agent 改用无法启动该发行版的 Windows 用户运行，或把 T/worker 放到另一台 VM，然后用
  `validation/p0-run-20261027/scripts/run.sh` 重跑并补一条「agent 身份写 launcher 被拒」的探针。
- **结论是否受影响**：影响 strict-production 声明，不影响组件级契约。

## ADJ-11（已解决，2026-10-27）：方案 §2 L84-L90 对实现的逐条比对，5 处偏差已按规格修

比对对象：实施方案 v0.6.5 §2 L83-L91（作者原文）↔ `execution-control-protocol.{mjs,go}`。

| # | 规格要求 | 比对前实现 | 处理 |
|---|---|---|---|
| 1 | L88 域名 `execution-control-command/v1\0`、**`execution-verdict/v1\0`**、`execution-control-checkpoint/v1\0`、**`execution-repair-resume/v1\0`**；L90 `execution-policy-readiness-request/v1\0`、`execution-policy-readiness/v1\0` | verdict 用 `execution-control-verdict/v1`、resume 用 `execution-resume/v1`、readiness 用 `execution-readiness-*` —— 与规格三个名字都不同 | **已改**为规格名；域名收敛到 `OPERATIONS` 一处，删掉 exported `CONTROL_DOMAIN`/`READINESS_DOMAIN` 避免两套口径 |
| 2 | L88 `digest=SHA256(domain \|\| 原始 payload bytes)` | 前像为 `schema\0 + payload`，**域根本没进签名**；digest 为 `SHA256(payload)` | **已改**：前像与 digest 都改为 `domain \|\| 0x00 \|\| payload`；域因此真的被绑定（拿 checkpoint 域验 verdict envelope 现在撞 `SIGNATURE_INVALID`） |
| 3 | L85 每 key 必带 `domains`、`scope`、`valid_from`、`valid_until`，且**签发、验签两端均检查** | 只有 `key_id/purpose/path/sha256`；域与 scope 只是 payload 里的字段，key 本身不受限 | **已改**：key 条目加四字段并纳入 exact keys；`assertKeyPolicy` 在 `VerifyControlEnvelope` 与 `SignControlEnvelope` 两处调用 |
| 4 | L85 字段表含 `public_key`；L84 要求绝对路径 + 原始 SHA256 pin | 只有 pin 文件形式 | **已改**：两种互斥键材料（`path`+`sha256` \| `public_key`），并存即拒；内联形式按其自身字节算 pin |
| 5 | L88/L90 各域 exact-key、拒绝重复键 | Go 的 `decodeStrictObject` 只查了**顶层**重复键，嵌套对象放行（ADJ-9 里「Go 逐层严格」的说法不成立） | **已改**：新增 `validateStrictValue` 递归拒任意深度重复键；两侧各补一条嵌套重复属性负例 |

- **scope 语义**：规格写「精确限制 workspace/project/CR、daemon/store 与适用 lineage」，实现取**维度集合与取值都相等**的精确匹配（不做通配），这样「声明了 workspace 就隐含全部 project」不成立。
- **时间戳格式**：规格未规定，取 `YYYY-MM-DDTHH:MM:SSZ`（UTC，秒精度），区间左闭右开。
- **未实现（有意）**：L90 的 `execution-deployment-observation/v1` 与 purpose `deployment-observer` 属 D7 观测端，本期无消费者，按 YAGNI 留给 S8；域名在规格里已固定，届时不需要改动本文件以外的任何 wire 约定。
- **证据**：Node 3/3；Go `TestChannelProtocol` 9/9（leaf 7），跑次 `ai-proto4-*`，checker `protocol` OK；共享夹具升 v3（含 domains/scope/有效期/digest）。变异 m9（前像去域）→ 8 红、m10（跳 key scope 检查）→ 2 红、m11（digest 只用 payload）→ 8 红，patch 与 sha256 落 `validation/mutations/`。
- **结论是否受影响**：否。规格不动，实现对齐；S3 帧链可以直接建立在 `digest=SHA256(domain||payload)` 上。

## ADJ-12（已生效，2026-10-27，用户确认）：`binding` 4 条 leaf 从「等上游」改为「跨 change 集成验证」

- **触发**：用户追问「授权」到底指什么。核查后发现我一直在引用两个**已失效**的前提：
  - `plan` §S6「修复本身不属本方案」与 `spec` SC-VC-024「未修时按设计为 RED」；
  - 而 AIFI-45 台账写明 **G1 已修**（增量 44）、**G2 残余决定不做**（增量 46）、**G4 残余移交 M003**（增量 46）。
  且实测 `TestChannelIngestBinding` **根本不存在**（`run:0`）——「未实现」被记成了「按规格 RED」。
- **口径（本次确认）**：
  1. `binding` 4 条 leaf 由本 change 实现，但只从 M003 入口做跨 change 集成验证（真 router + 真 permit + 真 DB），每条前置一条 M003 的 strict selection，以区别于 AIFI-45 自己的同行为用例；
  2. 不重测 AIFI-45 的函数、不把 G1 证据算作 M003 实现、PASS **不回填** AIFI-45 的 41/49（`pending-adjustments.yaml` 的双计禁令不变）；
  3. 通道路径上若变红，作为发现报给 AIFI-45，不在本 change 改其代码；
  4. 不修改 AIFI-45 记录目录，不重做 G1/G3/G5/EVD-007。
- **G4 归属**：G4 残余（strict 强制完整 tuple / 拒绝无代次回调）落在 **reader 片**，不在 `binding`——新增 leaf `TestChannelReader/partial_claim_field_rejected`（m85）兑现 SC-VC-027 的「分别缺少两个 claim 字段」。
- **边界声明**：M003 只验 643→644→645 链路一致；runner 的真正启动属 AIFI-45 的 `TC-RUN-002/003/006/010`，不在本 label 声称范围。
- **证据**：`binding` 跑次 `bi4-20261027T144831Z`（7/7，leaf 6，`skip=0`，checker 6/6）；`reader` 跑次 `rg2-20261027T143755Z`（12/12，leaf 11）。变异 m87–m92 各只红一条（m85 红 reader 新 leaf）。
- **已知非理想**：m86（删 `required && missing` 前一支）**无可观测差异**——后一支 `missing` 已覆盖同一判定，属冗余防线，已记入 `channel-test-expectations.json#mutation_asymmetries`，不伪造变异。
- **结论是否受影响**：Gate 3 仍不能进（还剩 node `worker` 1、node `isolation` 5 与 4 项 UNVERIFIED），但 `binding` 不再是假「blocked」。

## ADJ-13（已生效，2026-10-27，用户采纳）：Windows 平台隔离延后到后续 change

- **事实**：`isolation` 两个侧的 Windows leaf 都拿不到证据，且原因有两层——
  1. **环境**：本机没有第二个受限 Windows 令牌（与 ADJ-10 同源）；
  2. **代码**：Windows 侧驱动没写——node 测试拿到 profile 后只 `assert.fail('…令牌驱动尚未接上')`，Go 侧 `_unsupported.go` 对全部平台原语返回 `EXECUTION_CHANNEL_ISOLATION_UNSUPPORTED`，命名管道与令牌驱动都不存在。
  所以这不是「等一台机器」就能绿的项。
- **决定**：Windows 平台隔离（node 2 leaf / go 3 leaf）**移出本 change 的验收声称范围**，延后到后续 change 做（需建受限 Windows 账号 + 实现令牌/命名管道驱动）。
- **不做的事**：**不删、不改冻结的 leaf 名单**。`channel-test-expectations.json` 保持原样，`verify isolation --platform windows` 继续失败——缺口必须一直可见，不得通过缩减名单把它变绿。
- **与规格的关系**：`SC-TR-013`/`SC-VC-037` 的 AND 子句要求「Linux 与 Windows 各自出证据」。本 ADJ 是**记录的、经用户接受的偏差**，不是规格被修改；Gate 3 材料必须写明「Windows 未出证」。
- **Linux 侧不受影响**：node 3 leaf（`ni-20261027T145815Z`）+ go 5 leaf（`iso-20261027T101534Z`）仍是有效证据。
- **解除条件**：后续 change 建好受限 Windows 身份并实现驱动后，用同一份 `execution-control-isolation.test.mjs` 与 Go isolation 测试出证，并把本条改为已解决。

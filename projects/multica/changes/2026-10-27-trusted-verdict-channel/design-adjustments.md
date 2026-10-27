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

## ADJ-7（口径裁决，2026-10-27）：merge-facts 的两处规格冲突

- **404 分层**：SC-MG-009 的 `AUTH_SCOPE_UNVERIFIABLE`（主体不可验证）与 `MERGE_FACTS_NOT_FOUND`（CR 不存在）**都保留**，
  均为 404；只有传输失败/5xx/超时才 `MERGE_FACTS_UNAVAILABLE`。方案 R2.4 的「非 200 一律 UNAVAILABLE」不采用。
- **祖先判定**：用**严格祖先**（`approved_base` 必须是 candidate head 的祖先且不相等），以 SC-MG-010 为准；
  方案 R2.1 的「祖先（含相等）」不采用。
- **影响范围**：merge-facts 客户端与 handler 的判定分支；不影响必达 leaf 名单。
- **结论是否受影响**：否。

## ADJ-8（未决规格冲突，2026-10-27）：SC-VC-008 与 key-purpose 矩阵矛盾 —— **需规格修订，未擅自改**

- **事实**：SC-VC-008 的 GIVEN 明确要求「用 attestation key 签 command」被拒绝（否则不会把 command 列入反例）。
  但 Node `OPERATIONS`（tools `lib/execution-control-protocol.mjs`）把 `command` 映到 `attestation`，且既有成功测试断言
  attestation 可签 command；multica 侧刚落的 Go 实现为与 Node 逐字节对齐，也采用同一矩阵。manifest 的 purpose 闭集只有
  `{attestation, human}`，若照 SC-VC-008 字面执行，`command` 将**没有任何合法签发者**。
- **已做的**：Go 实现保留与 Node 一致的矩阵（`command→attestation`、`resume→human`），并在
  `TestChannelProtocol/exact_keys` 中断言 human 签 command/verdict 被拒、attestation 签 resume 被拒。
  **没有**实现「attestation 签 command 被拒」——因为那会让 command 不可签，属规格级改动。
- **需要的裁决**（二选一，均由人确认后走规格修订）：
  1. 给 manifest purpose 闭集与 OPERATIONS 增加 `command`（或 `attestation-command`）专用 purpose，Node/Go 同步；
  2. 修改 SC-VC-008，把「attestation 签 command」从反例中移除，只保留 resume 越权。
- **影响范围**：SC-VC-006/008、`protocol` label 的 `exact_keys` 语义、manifest schema、tools 与 multica 两侧实现。
- **结论是否受影响**：**是**——在该裁决落地前，`exact_keys` 只覆盖了 resume 越权与键集/清单形态，**不覆盖** SC-VC-008 的 command 反例；
  Gate 3 必须按「部分验证」记录，不得表述为 SC-VC-008 已闭环。

## ADJ-9（Node 缺口，2026-10-27）：重复 JSON 属性与 target union

- **事实**：Node 侧 `JSON.parse` 不拒重复属性；现有「重复 key」测试重复的是 `keys[]` 里的 `key_id`，不是 JSON 属性。
  「重复 JSON 属性」与「union 双分支」两条 SC-VC-008 要求，目前**只有 Go 侧实现了拒绝**（Go 用 token 级解码器），Node 侧没有。
- **已做的**：Go 侧拒绝 envelope 与 payload 的重复属性，并有 `exact_keys` 断言；Node 侧未改。
- **影响范围**：跨语言一致性（同一份含重复属性的 envelope，Go 拒、Node 可能接受）。
- **结论是否受影响**：是——在 Node 补齐前，不得声称「两侧同语义」；`cross_language_vectors` 只覆盖正常字节与签名域等价性。

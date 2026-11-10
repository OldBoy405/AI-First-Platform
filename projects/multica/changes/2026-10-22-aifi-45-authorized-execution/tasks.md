# AIFI-45 multica — BUILD任务清单

## 2026-11-09 收口（当前；下方“当前实施索引”的未完成表述以此节为准）

- T 侧两个 change 已归档：`2026-10-22-aifi-45-authorized-execution`（11-08，gate 94 文件 / 2217 例 / 0 失败）与 `2026-11-08-aifi45-trust-anchor-chain`（11-09，97 / 2227 / 0 失败 / 0 hold）。本仓只承载 M 侧协作责任。
- M 侧 seam 已提交 `d427d2b68`（CUSTOM #305/#306）：绑定签发只接受六个控制写 operation；daemon 启动门四条件，缺失/撤销/漂移/relay 失败均 fail-closed。`go build ./...`、`go vet ./internal/daemon ./internal/governance` 均为 0；daemon `TestExecutionBinding` PASS。governance `TestExecutionBindingIssue` 需一次性 DB，本轮未重跑，其 11-08 PASS 见归档证据。
- 本 change 的 `.stdd.yaml` 自 2026-10-22 未更新（`build: in_progress`、无 Gate3 回执）。这是**记录未推进**，不是阶段未开始；不手改投影，也不据旧快照宣称已闭。
- 10 条 ADJ 仍 `resolved:false`；2026-11-09 已逐条补 `dispositions_20261109`（类别 / 载体 / 关闭条件），此后不再逐轮重估。
- 2026-11-09 已完成的收口动作：①`main.go` 生产组合注入默认拒绝的 `AdmissionDecider`，并在 `router.go` 加启动门（HEAD 原注释把生产注入留给 Gate3；本次注入 + 强制非空一起落地）；②一次性 PG 上 `TestAdmission` 7 例有通过输出，覆盖 `HEAD_UNAVAILABLE`/`HEAD_REJECTED`/`WAIT_CONSUMPTION`/`WAIT_TRUSTED_T_COMMIT`/`ADMITTED` 阶梯；因无外网隔离未证实，不作为合规验收证据。详见 [admission-composition](validation/2026-11-09-admission-composition/README.md)。
- D2/D3/D4 已落记录：不补 per-verb 平台级正例；`2026-10-30-aifi-45-evidence-delivery-integrity` 并入 `2026-10-29-trusted-verdict-outcome-binding`；外部 owner 不变（平台/Ray/部署）。
- 2026-11-09：`planRecovery` 的 `intent+at_prev` 不再返回 push；通知曾按 approval-required / run-failed / delivered 三类建立候选调用及 pending 启动恢复，未加列/索引/迁移。后续复核发现三类真实生产事实、可信接收者与写前故障恢复均未闭合，不能称为三类通知已完成；`planRecovery` 也尚无生产调用方。详见 [notice-dedupe-and-wiring](validation/notice-dedupe-and-wiring-20261109/README.md)。
- 仍未完成：`M008` 双端 SPEC 配对修订已由 `2026-10-29-trusted-verdict-outcome-binding` 交付归档（两侧 Gate 2 于 2026-11-10 批准），剩余真实恢复入口证据在本 change；`M009` 已移回本 change（[validation/m009-attention-routing-spec-20261110.md](validation/m009-attention-routing-spec-20261110.md)），去重偏离仍待评审；NTF-001～007 真实事实与 DB 故障恢复未验收，消费端对真实载荷形状的模拟重投已有局部验证，不能代替真实链路验收（均在本 change）；`M005` 剩余 ingest 边由本 change 承接，关闭判据见 [pending-adjustments.yaml](pending-adjustments.yaml) 的 `ADJ-AIFI45-M005`；`M006/M007/M010` 已登记 [BACKLOG-M-RESIDUALS.md](BACKLOG-M-RESIDUALS.md) 待开载体；`TC-EVD-008` legacy（占位 change，负责人 Ray）；Windows 身份（部署前置）；M003 记录的四条 RUN TC 真实入口。
- 2026-11-10 通知收件人改按 CR 自身角色：`crsync.applyOwners` 投影 crctl 注册/移交事件里的 `owners.requirement|development|test`（非 `user_id` 值拒绝写入）；授权类通知→requirement owner，维护类→development owner，无 owner 时才退回启动该 run 的任务身份，仍无收件人不发送。Inbox 通知附带 `cr.shell_issue_id` 指向该 CR 的对话。两项 DB 测试已写入但未运行（隔离 PostgreSQL 未获批）；Go build/vet/gofmt 通过，不等于行为已验证。
- 2026-11-10 非名片库复跑：按探针建立 `aifi45_tmp_*`/`aifi45_role_*` + `AIFI45_DISPOSABLE` 注释并设 `AIFI45_TOOLS_ROOT`，干净库单次全量 **403 PASS / 5 FAIL**；NTF 全绿。5 项失败为既有前提（channel 迁移用例要求 648 之前空库；WP4 两例为同 request 前序结算导致返回原映射的 fixture 隔离问题），与本轮改动无关，未扩大范围去改造测试夹具。
- 2026-11-10 真实隔离 PG 回执：本地 `pgvector/pgvector:pg17` 起一次性容器（`--pull=never`、tmpfs 数据、仅 127.0.0.1），`go run ./cmd/migrate up` 到 648 后 `go test ./internal/governance -count=1` 得 **396 PASS / 11 FAIL**；NTF-001～007 与全部通知/owner 路由用例 PASS。11 项失败为环境前提（`aifi45_tmp_*` 非名片库 + `AIFI45_DISPOSABLE` 注释、`AIFI45_TOOLS_ROOT`、WP4 跨用例残留），非本轮改动；容器按 ID 删除并回读为 0。未证明无外网（`NetworkMode=pasta`，DNS 可解析）。
- 2026-11-10 新入口「每选择一个一次性数据库」已落地并实测（`scripts/aifi45-disposable/{provision,run-selection}.mjs` + `selections.json`）：7 个选择里 5 个全绿（notice 9、channel-up 19、channel-down 22、channel-reapply 15、channel-protocol 46），WP4 两个选择仍因测试夹具缺陷失败；容器按 ID 删除、label 回读 0。RUN-001 核查后**未实现**：真实路由只能证明授权签发，跨阶段复用仍读 `tech-design` 审批、verdict ingest 未接线，整条 TC 无法真实通过，不新增缩水测试。CP-RUN-004/005/007/008/009 已按用户 2026-11-10 的明确批准写入 canonical（action 改指 governance/daemon 入口，description 标注部分覆盖与残留；harness 前置从已禁用的旧 runner 改为 `scripts/aifi45-disposable/run-selection.mjs`），YAML 解析通过、24 条 CP 结构不变。**五条命令已在恢复运行时后补跑并全绿**（各自一次性库、0 skip）：CP-RUN-004 `PASS 1`、005 `PASS 1`、007 `PASS 6`、008 `PASS 18`、009 `PASS 3`；期间修复了一个真实夹具缺陷（enqueuer 固定 runtime 常量 → 改取执行 Agent 自身 runtime）。四条部分覆盖的残留未消除，仍不得计为整 TC 通过。详见 [cp-run-revision-proposal-20261110](validation/cp-run-revision-proposal-20261110.md)。
- 2026-11-10 WP4 两条失败已定为夹具缺陷并修复（重复创建同一 CR；`EffectRef` 字节比较受 JSONB 规范化影响，非 VerdictID 差异），断言强度未降。整组 7 个选择在各自一次性库上单次复跑全绿：notice 9、channel-up 19、channel-down 22、channel-reapply 15、channel-protocol 46、wp4-original 1、wp4-concurrent 1，0 skip；容器按 ID 删除、label 回读 0。
- 不做：原生锁、`inbox` partial UNIQUE、第二本送达账、逐文件 hash 隔离（依据见已归档裁决）。

## 当前实施索引：已采纳最小方案（服务端/daemon；实现未完成）

按用户要求核查层层加码并继续实施；用户明确“已经存在的历史CR不迁移处理”，不回填或迁移历史 CR 实例，活动请求的权限、未知结果和现有数据保护仍独立核定。采用[唯一活动方案](../../../tools/changes/2026-10-22-aifi-45-authorized-execution/validation/root-cause-convergence-implementation-plan.md) §3.1/§3.4/§3.5 的既定路线；四项 P1/P2 在其 E2–E3 / WP1 原位收敛为“一条提交路径、一套恢复判据、一处清理责任”。本节只索引 M 的协作责任，不另建 Git 提交权威、index 恢复系统、平行计划、Gate 或验收分母；不同信任接收者保留必要核验，但不按异常名追加机制。已确认方向不重新询问，真正新增合同冲突和无法自行核定的资源身份/负责人按原流程集中处理。

- [ ] **E0/E1＋D1：** 核既有 daemon/Go 承载受保护 T 的实际写入链，复用 `execenv/envlock_windows.go` / `envlock_unix.go` 原语；稳定锁对象、句柄/子进程寿命和所有 writer 同域后才替代旧接管，不照搬为 GC 设置的删除共享，也不新增锁服务。
- [ ] **E2→E3 / WP1 协作：** daemon/Go 配合核定 CR 独立落点、writer 和锁生命周期；T 共同事务入口固定原候选并给出已提交/可信未提交/未知，M 仍按自身信任边界核验可信 T 提交与连续性，不从消息、helper 清理或用户 index 推断已提交。未知不授予新派发，原请求按既有责任对账；不复制 Git journal 或预算规则。approve/resign 迁移不改变人工审批/可信授权。具体步骤及 V2 五组验收只在活动方案维护，本次 Git 收敛不预设新增 M schema。
- [ ] **WP2：** 当前授权、前驱/request/fence 与独立历史锚接入真实准入；T 保持唯一业务裁决，M 不复制预算算法。不足可记录但不执行，消费拒绝先于放宽签发；外部锚的真实设施/负责人尚须核定，不能用同回滚域文件代替。
- [ ] **WP3/WP4：** 启动与撤销排序，实际启动未知不重派；按已采纳动作表保留第六次合法交付、非权威查询故障正例和有界收尾。唯一结算入口绑定原 reservation/attempt，接真实效果 producer；并发同义重放返回原结果，未知不重推、不改 settled。
- [ ] **E4/WP5：** `crsync` 单调投影与 T 旧批补投配对；优先既有 `projected_commit`＋可信前驱/祖先关系及条件推进，所有写游标入口同规，不以时间戳排序。audit 首次落盘固定事件身份，优先评估 `activity_log.id`；同义重放/异义冲突/相同内容独立事件分别验证，不猜测回填旧事件。
- [ ] **WP6：** 真实业务事务调用已有 `DeliverNoticeTx`，复用 646 迁移的 notice 唯一键；提交后广播、失败重投同 Inbox ID。默认不再加 Inbox partial UNIQUE，须配对处理原 design 要求、旧键兼容和既定通知白名单，不用 fixture 代替生产 caller。
- [ ] **E5/WP7：** 仅实际必要 schema 差异走正式迁移，使用获准新 disposable PG/自建旧行验证升级、down/reapply、锁/CAS与并发；正式动作须先排除对历史 CR 实例的迁移、回填或改写，无法排除时停止；与 T 同快照完成原 TC、CUSTOM、B4/C6 和原生 STDD Gate3 前置，不运行旧库/旧 runner/HOLD。

本轮只原位修订活动方案及两仓文档，未修改 M 产品/CUSTOM/迁移、`.stdd.yaml` 或 pending-adjustments，未跑 DB/产品测试、未 commit/push/部署，Gate3 仍 NO-GO；方向采纳不代表合同生效、资源就绪或实施完成。历史 `[x]` 与证据原文保留；下方“当前”、旧索引前提及未决数量均只代表该增量时点，后续派工以活动方案为准。

## 2026-11-04 B 类落地（服务端；历史快照）

- [x] 决定已由用户采纳并记录（tools 变更目录 `validation/b-decisions-adopted-20261104.md`）：D1 复用既有 daemon/service + Agent 低权限；D2 一个外部历史锚；D4 启动事实以 M 侧为权威、未知不重派；D5 单一结算入口、未知不重推；逐批 checkpoint。**记录不等于合同生效**。
- [x] WP2-1 共享分类器：新增 `server/internal/governance/authorizationscope/sufficiency.go`，区分非法 / 有效但不足 / 充分，并附 Go 与跨仓共用的固定字节向量。`go build ./...` exit 0，`go vet ./...` exit 0，`TestSufficiencyGoldenBytes` 16/16 PASS。**签发与 head 仍拒绝不足授权**：Node `repair-admit` 独立解码并写额度账本，真实消费拒绝未证前不放宽。
- [x] `CUSTOM.md` 按现有结构登记（#293）。
- [ ] WP4-2／4-3 **完整配对与生产链未完成**：早期静态记录曾发现先读当前 HEAD、`ON CONFLICT DO NOTHING` 不比语义等问题，部分已由下述只读 mapping 与冲突比较切片修正；当前按 reservation 数量推 attempt、可信 `no_effect`/迟到排除和并发互斥等仍未证明。`SC-MG-015/016` 须先完成配对修订并获适用批准；历史静态记录见 `2026-10-29-trusted-verdict-outcome-binding/validation/aifi45-wp4-2-wp4-3-static-block.md`，不能把其旧源码观察当作当前结论。
- [ ] 未运行 governance 包父级测试（`TestMain` 即使 `-run` 也连 DB）；DB 锁/CAS、并发重放、真实远端迟到执行、跨端兼容均未验证。
- [x] WP4 可立即做的 5 个切片已实装（strong `Gobao/kimi-k3.1-pro:high`）：①`ReadMergeEffectMappingTx` 只读原 mapping（不看当前 HEAD、不授予发布权）；②结算零行/异义不再是静默成功（`ErrMergeEffectReservationGone` / `ErrControlSettlementConflict`，同义重放返回库存原 mapping）；③command 锁后重读 settlement 再判同义；④同一 lineage 存在任一未终结 reservation 即拒绝新开 attempt（unknown 不能靠换 digest 绕过）；⑤reader 收敛为一次冻结字节比较。实跑：`settlementguard_test` 9 顶层 + 16 子例 PASS（离屏、无 DB env）、`go build ./...` PASS、`go vet ./...` PASS、逐包 `go test -c` 98 包编译通过。`CUSTOM.md` 已登记 #294–#298。
- [ ] 上述 5 片段的 DB 侧（并发 reserve/settlement、锁等待、JSONB 比较、撤销交错）与真实远端归属仍未验证；DB 测试仅编译未运行。完整 WP4-2/4-3 仍 BLOCK（`SC-MG-015/016` 未修订）。
- [x] WP5 M 侧（strong `GB-JP/kimi-k3.1-pro:high`）：`crsync.go` 普通事件改为独立接收事务——唯一键 insert、evidence 补齐在 commit **之后**才 accepted；投影与 `processed_at` 失败只记日志并保留未处理记录，不再触发 daemon 重发（原语义把「接收端已持久化」和「业务投影完成」混成一个 ACK，且 insert 已提交但投影失败时返回 `INGEST_FAILED` 也掩盖了「已落盘未确认」）。`crevents.go` 收件顺序改为「**全部批次持久化 ACK → `writeFileAtomic` 持久化 cursor → 删除 accepted 源文件**」，任一阶段失败都不进入后续阶段（原实现逐批 `applyAck` 就删文件、最后才写 cursor，后批失败时前批文件已删而 cursor 未推进）。ACK 校验改为按批内 id 出现次数比对，覆盖漏项、越批、超额重复与同 `commit:<sha>` 多事件。marshal 前失败明确 `not sent`，其余保持 `unconfirmed/send outcome unknown`。新增离线回归：后批失败保前批与 cursor、cursor 写失败保留源文件、删文件失败发生在 cursor 持久化之后、ACK 完整性、not-sent/unconfirmed。`CUSTOM.md` 登记 **#299 / M20**。
- [x] 实跑（`GOPROXY=off GOSUMDB=off GOTOOLCHAIN=local GOFLAGS=-mod=readonly`）：daemon 定向 **15 顶层 + 13 子例 PASS，0 FAIL 0 SKIP**；`go build ./...`、`go vet ./...` 均 exit 0；`internal/daemon` 与 `internal/governance` 的 `go test -c` 编译通过。
- [ ] 未验证：接收事务在真实 PostgreSQL 上的 commit/rollback 与唯一键冲突、并发重送、真实 daemon 联调与 ACK 丢失、断电恢复、跨实例 ordering；`TestMDev002` 等 DB 用例仅编译未运行。通知与业务投影语义本轮未改动，也未验收。

> 下方按时间保留各增量当时的完成/未完成状态和计数；小节标题中的“当前”指该增量时点，不能覆盖后续实现。[历史覆盖台账](validation/tc-coverage-20261025T153000Z.md)的 **44/49 不可靠**：EVD-007 重复计数，RUN-008/009 被漏列。[对账](validation/tc-ledger-reconciliation-20261029.md)分别给出历史 CP 名称去重和 EVD-008 完整能力两种重算口径，均不是当前源码的验收数；EVD-008、RUN-001/003/006/007/008/009 仍缺合格完整证据，其他条目亦未全部重新核验。Gate3 仍 NO-GO，M001–M005 仍未关闭。

## 2026-10-25 执行绑定签发（服务端；当前）

- [x] 新表 `cr_execution_binding_issue`（append-only，拒绝 UPDATE/DELETE 的触发器，唯一键，无 FK）+ 迁移 `643`。
- [x] `POST /api/daemon/crs/{crID}/execution-authorization/binding`：exact 4 键 body；RR 事务内核 task（runtime/代次/active/cr_id/认证 workspace/daemon）、head（复用既有校验）、project、coordinator local_directory+daemon、challenge 摘要；不符 409 不签。
- [x] 签 `execution-binding/v1`（`schema\0+payload`、Ed25519、恰好 20 键），同 challenge 重放逐字节幂等 `changed=false`。
- [x] `SetTaskCRAttributionIfValid` 改首次写入胜出（不允许 daemon 自报覆盖已归属 CR）；删除 `handler/daemon.go` 里重复的 `AttributeTaskToCR` 调用。
- [x] runner `-migration=`（只读时允许目录、记录 sha256），因为临时库是冻结原库 schema-only 克隆。
- [x] 真实 MDT→HTTP→DB 18RUN/18PASS（17 leaf）；**跨语言互通** `TestExecutionBindingEnvelopeInteropWithToolsVerifier` 真调 T 的 `requestExecutionBinding`（3/3，2 leaf；未设 `AIFI45_TOOLS_ROOT` 则 Skip）；strong 首轮 2×P1+3×P2 全修并复核，互通负例 I1 也修正（只改 payload 内 task_id、保留原签名）→ CLOSED。最终冻结 13 项 `final4` 独立回归 governance 900/899（814 leaf）、handler 13/13（10）、daemon 125/124（115）。
- [ ] **未做**：daemon 私有 stdio 中继（把已签 envelope 交给 T 子进程）、T 侧消费事务、不可删 activation 本体、同 UID 隔离控制域、`EXECUTION_CONSUMPTION_REQUIRED` 解除。进程号由 daemon 转述，服务端不可验证；首次 CR 来源仍未证明。互通负例只断言非 0 退出，未断言具体 `cause_code`（已登记 tightening）。
- [ ] 完整旧 claim 锁序/49 业务 TC/5 major/受保护控制域；消费关闭、Gate3/提交/推送/部署边界不变。CUSTOM #171/M11=24。

## 2026-10-25 terminal-fence增量（当前；不关闭M1/M3）

- [x] 公开MDT旧代次fail/complete误终止新代次真实负例→事务CAS最小修复GREEN；精确generation/runtime/workspace/daemon，严格JSON/时间token，legacy无字段兼容，无新增前置锁序。
- [x] strong静态P2 foreign terminal replay真实RED→scoped SQL读重验身份后作者GREEN。
- [x] daemon源claim tuple→所有终态早退/发送/补偿/outbox闭环：tuple随run的context（`handleTask`入口stamp、`reportTerminalTask`读取）、取消taskID缓存、single-flight按`deliveryKey`、outbox record v3 `claim_mode`、`ack`/文件名/temp恢复统一、quarantine补偿复制tuple；仅`mdt_` token升级qualified（PAT保持legacy），strict任务无法fenced时fail-closed不发终态。balanced实际写行为测试，strong四轮F1–F4/N1/N2全CLOSED。
- [x] Complete侧矩阵（10子例）+ Fail矩阵（11子例）+ foreign replay + stale overlay 全绿；`final5` 冻结独立回归 governance 879/878/0/1（795 leaf）、handler 13/13（10 leaf）、daemon 125/124/0/1（115 leaf），五轮原库137表/6228行/82审批均一致，vet exit0。
- [ ] retryable fail 在**有效代次**事务失败时仍可能已创建外部 Composio session（真实 POST，无撤销）；无锁方案已落事实文件但未实现。
- [ ] 动态并发快照 race（CAS vs scoped SELECT）、同代 complete/fail 并发第二条可能不落盘、legacy 无字段仍被服务端接受（PAT daemon 只能走 legacy）。
- [ ] 完整旧claim锁序/49业务TC/5major、受保护控制域/activation/T消费；保留消费关闭、Gate3/提交/推送/部署边界。CUSTOM #170/M11=23，详[本片报告](validation/terminal-fence-20261025T060611Z-report.md)。

## 2026-10-25 当前task/project claim（当前；仍非完整准入）

- [x] 主会话接既有status GET显式claim读面/SDK/daemon根前实际回读；真实MDT认证workspace+daemon、只读RR、冻结queue project与live issue/project、runtime/代次/active状态，首片issue-backed-only。shared时间helper在Go有损截断前限制微秒，DID拒C0/C1；无新增表/迁移/FK/端点/签名nonce；CUSTOM #169/M11=22。
- [x] balanced实际写公开HTTP/SDK矩阵及真实SDK→MDT→DB正反贯通；HTTP1FAIL→1PASS、精度/C0/C1真实RED→21/21、SDK及根前检查39/39。回调真RED发1次task-ID-only→新claim读失败路径0次；作者全治理851/851（770leaf）、daemon112P/1 Windows权限SKIP（106leaf）。SDK中间0RUN编译错保留、不算业务RED。
- [x] 每命令先wx source pin/后无漂移，12次原库137表/6228行/82审批与冻结共同一致、锁session0/精确资源清；独立前19项raw/LF与原字节archive冻结。[本片报告](validation/claim-project-20261025T052646Z-report.md)。
- [x] 非作者balanced三组851/851、13/13、112P/1 Windows权限SKIP（leaf770/10/106），各自先pin19项/后无漂移、每条原库安全/资源清理；DB权明确释放。caller与server+SDK限定strong完成/无新增确证finding，宿主只读最终核15条基线共同未变、37对已知库role不存在，四包vet exit0。
- [ ] 继续完整terminal complete/fail/补偿/outbox代次fence（已确证旧task-ID-only缺口，当前只抑制新claim读失败分支）；再接每repo本机事实、受保护控制域、activation及T消费。旧claim锁序仍INCOMPLETE；完整0/49、5major、消费/Gate3不变。非必要不等新的常规确认。

## 2026-10-25 当前资源元数据读面（前段；不是完整可信绑定/TC）

- [x] 主会话实现既有 daemon workspace repos GET 的显式 project 查询与 SDK 新方法；真实 mdt/认证workspace/只读同快照，descriptor 复用构造器；客户端 scope/集合/唯一ID/自洽/拒redirect/有界严格JSON。旧无query API、旧SDK/head/历史不改，无新增表或消费；CUSTOM #168/M11=21。
- [x] 两个 balanced 实际分别写公开HTTP/SDK测试：公开GET 1FAIL→1PASS、真实矩阵11/11；strong发现大小写别名P2后balanced补3失败leaf，主会话精确键根修25/25（23leaf），strong关闭P2、限定静态完成。中间作者manifest缺pre-run pin已披露，P2和最终独立阶段已每条先pin，不倒签。见[本片报告](validation/current-bindings-20261025T034807Z-report.md)。
- [x] P2后非作者balanced三条828/828、13/13、72P/1 Windows权限SKIP，PASS leaf749/10/67，exit0；每条原库未变/锁session0/精确新库role已清、11源码匹配、DB权释放。宿主最终只读核137表/6228行、82审批未变，本轮13对及前轮9对共22对已知资源均不存在；四包vet exit0。
- [ ] 旧claim strong仍INCOMPLETE：agent/Builder rebind调用者、terminal settlement/system cleanup SQL、wakeup管理/注册事务未尽；新读面未做动态并发快照race，不把限定静态或回归替代这些缺口。
- [ ] 读面只是当前平台声明身份；完整可信claim/project、逐repo本机事实/隔离/activation/防降级/T消费/永久派发仍待接。0/49、5major、消费关闭、BUILD/Gate保持，无commit/push/部署；原库HOLD与原41缺失保持。下方是前段历史，不覆盖本节。

## 2026-10-24 新库恢复（前段；不是事故恢复或完整TC）

- [x] 用户明确授权保留原库/事故证据、另建可丢弃隔离测试库；旧入口HOLD不解除，原41条缺失未恢复，82不视为原83基线。此项只完成新库授权，不勾下方事故恢复项。
- [x] 版本化逐命令schema-only新库/受限role、原表拒读/原行备份/全137表摘要核对/每条锁session0/精确清理；claim fixture自建user/member。Node6/6，runner两finding闭合后限定静态PASS；CUSTOM #167/M11=20。
- [x] 最终非作者balanced3治理817/817、claim13/13、daemon47P/1权限SKIP，exit0，三条各自新库/role已清、原137表/6228行与82审批ID/hash未变、DB权已释放。见[报告](validation/disposable-db-20261024T162608Z-report.md)。
- [ ] 旧claim完整锁序独立审核仍INCOMPLETE，不被runner静态PASS替代；每repo当前descriptor/完整claim/project/隔离控制域/activation/防降级/消费/永久派发继续待办，0/49、5major、消费关闭与Gate保持，不commit/push/部署。下方STOP为事故时快照，原库HOLD仍有效。

## 2026-10-24 STOP：DB历史事故（事故时快照；原历史未恢复）

- [ ] 扩大回归虽exit0，历史83→82/missing41/extra40；原42保护集完整，另外41旧fixture历史缺失，未恢复。只读保全现场后停止后续DB写入/测试和接线，等待原始备份或另建可丢弃测试库的人工授权；不得自动接受82基线。见[事故记录](validation/claim-build-20261024T153817Z-incident.md)。strong INCOMPLETE、0/49、5major、消费/Gate均不推进。

## 2026-10-24 task claim runtime归属（事故前组件过程，非整TC/切片完成）

- [x] 真实DB-backed mdt→DaemonAuth→公开StartTask，外来daemon持精确runtime/generation返回200的真实RED；同一事务runtime归属锁→claim锁后最小GREEN，拒外来首次/重投，owner首次/重投保持200，空daemon403，实际锁等待后归属变更409。作者3/3（父1+子2），不是3条完整TC。
- [x] handler fixture 每进程唯一身份、setup单事务、按exact-owned user/workspace ID清理后，既有 `^TestStartClaim` 13/13、0skip/exit0；CUSTOM #166、M11共19行登记。全83历史ID/整行hash不变、0锁/0其它session后移交唯一独立DB执行者。
- [ ] 非作者strong补全静态锁序/来源复核、balanced独立扩大回归与释放、economy文档核查；INCOMPLETE不默认PASS。详见[claim组件报告](validation/claim-build-20261024T153817Z-report.md)。
- [ ] 完整可信claim/project/每repo当前绑定/隔离控制域/activation/legacy新合同防降级/T消费/永久派发仍未闭合；0/49与5major保持，旧generation缺失路径不能充当新合同可信claim，不推进Gate3/commit/push/部署。

## 2026-10-24 签名revoke子任务（前段快照，非整TC/切片完成）

- [x] 真实Auth五字段请求/21字段签名、execution/reject追加历史+精确record-ID CAS；exact actor/raw重投先于前驱检查且不补head，终止历史防损坏指针回滚再签；head单repeatable-read快照核initial前驱，原source/payload bytes不变。
- [x] 原HTTP404→201真实RED/GREEN保留，覆盖actor/严格JSON/Unicode/并发真实行锁/INSERT与UPDATE及CAS-miss回滚/提交后io.ErrClosedPipe/终止历史；不能称TCP/crash-kill/exactly-once。源码语义增量13、联合29，CUSTOM #165/M11共18行；12仅EOL生成物另列。
- [x] 非作者strong限定静态PASS；balanced以T数字P2修复后快照实际治理550/550、router14/14、拒消费2/2、HTTP→测试临时trust root→真实Node3/3，exit0/0skip；完整83条history前后ID/hash相同、零新增残留，锁/session0释放。主会话vet/scoped格式与diff-check、sqlc78生成物raw/LF不变；详见[T撤销续建记录](../../../tools/changes/2026-10-22-aifi-45-authorized-execution/resume-revoke-build-20261024.md)。
- [ ] **仍未闭合**：extend/可信DB claim/每repo当前绑定/隔离控制域/activation/legacy防降级/T消费/永久派发恢复；完整TC0/49、M17未整体验收、5major不关闭。普通实现由主会话接续、必要独立审核分层保留；不自行Gate3/commit/push/部署。

## 2026-10-24 持久化 initial head 子任务（前段快照，非整TC/切片完成）

- [x] 遵循T wire §3.1：CR行锁同事务保存initial历史+独立记录id指针；真实DaemonAuth head GET、精确scope/当前project/签名/source核对；无backfill，exact replay不补head，旧历史GET保留。
- [x] 642 nullable UUID迁移只应用专用隔离库，671/642、重复up exit0；sqlc v1.31.1离线生成，无手改生成列。实际router默认无signer明确503，配置化真实POST201→head200。
- [x] 公开HTTP两轮真实RED→GREEN；独立strong发现负零P2后两处raw -0先真实RED再按精确整数比较修复，不动签名/原source bytes。增加并发单head、丢响应重试与精确fixture清理，旧manifest/raw未覆盖；本片17文件中的14文件在P2补正未变。详细作者证据见 `validation/initial-head-{report,p2-report}.md`。
- [x] 实际strong/balanced/economy分层实现/评审，CUSTOM #163–164/M11索引登记（新增6文件test-only精确fixture清理）；非作者最终组件治理174/174、实际router5/5、拒消费2/2均exit0/0fail/0skip，strong静态PASS；各轮结果及未验边界见[T恢复记录](../../../tools/changes/2026-10-22-aifi-45-authorized-execution/resume-tiered-build-20261024.md)。不将作者自检当独立评审，不将重复/重叠测试事件累加成完整TC。
- [ ] **仍未闭合**：签名revoke/extend、可信DB claim、每repo当前绑定、隔离控制域、不可删activation、legacy防降级、T消费和永久派发；完整TC仍0/49、M17未整体验收，major不关闭，不Gate3/commit/push/部署。

## 受保护 trust root（ADJ-AIFI45-M002/003，前轮组件）

- [x] 新增 `server/internal/daemon/execution_trust.go`：daemon 自有根 `<home>/.multica/execution-trust/<workspace-uuid>`，0700/0600、CreateTemp+rename、同内容幂等、异内容 `EXECUTION_TRUST_CONFLICT` 拒写；拒工作区内/目录链接根、非UUID、相对 home、越界名称、未知 kind、空内容。
- [x] 测试：新 4 例 PASS、1 例 Windows 目录链接 SKIP（需特权，不当通过）；构建期 `pathWithin` 方向写反被用例捕获后修正。daemon 包相关回归 RUN14/PASS13/FAIL0/SKIP1/exit0。
- [x] 第二轮：daemon 拉取接口 `GET /api/daemon/crs/{crID}/execution-authorization` + `Client.InstallExecutionAuthorization` + 安装器验签/workspace/CR 校验；他 CR 记录真实 RED→GREEN；组件链至真实 crctl `--check --trust-root` PASS；governance 扩大 598/598。
- [x] `handleTask→prepareClaimedPipelineTask` 已接真实 crctl 静态检查，真实 Auth/DB-backed mdt/DaemonAuth 投递链通过；无效合同/source/超大 HTTP/换根/仅根归属准入、缺显式 false 事实、POST/JSONB GET 重投、重复包装键共八类实际 RED 已修；最新 governance 606/606、daemon 36=35P/1S。证据见 `preflight-evidence.md`，不计整 TC。
- [ ] **仍未接**：可信 current-head/撤销/DB claim、隔离控制通道、不可删 activation、新合同 legacy 防降级与永久派发；静态成功仍 `EXECUTION_CONSUMPTION_REQUIRED`。M002 保持 unresolved。

## 本轮安全收口组件（非业务切片完成）

- [x] 本change内稳定复现fixture顺序缺陷，新增实际SQL23505反例，修复共享setup按registry name清理；非生产Runner修改。
- [x] DB测试进程独立session lease及真实失败断言修复；双进程各10轮140/140，扩大包588/588（仅排除LiveGitHub）。初始全量失败保留，不把历史未知上下文反推同源。
- [ ] 固定真实CLI离线隔离PoC完整runtime/清理核验；脚本已入、结果见T isolation-evidence.md，不代证daemon任务。
- [ ] M grant/source/key受保护安装器、current claim/head/revoke、永久logical_dispatch_key/adoption及真实纵向链。

> Gate2已登记，用户选择普通模式；不修改共享DB/真实CR，不自动发布。配套全局切片见tools同change的slices.md。

## 1. 可信授权与隔离环境（P0）

- [x] 1.1 核实并创建仅本change的隔离Postgres/loopback端口，验证DB身份后才运行迁移和集成；不触碰共享multica实例。环境前置完成：专用55432、既有迁移exit=0、1条已有基线真实PASS/0 SKIP；不是业务TC/切片验收。
- [ ] 1.2 与T AUTH-010联合定义原始bytes签名golden，先失败后最小实现，保留stage v1。Go initial/head 对 acceptance/delivery 空数组的非空校验与 T canonical、wire 存在冲突；用户已确认允许签名记录不足但不得执行，先证明真实消费 fail-closed 才放开签发；M ADJ-AIFI45-M007 与 T 对应 major 已登记且未解决；合同对齐、修订生命周期、具体方案决定和 C6 仍待落实，详见 [T 跨语言预检与用户确认](../../../tools/changes/2026-10-22-aifi-45-authorized-execution/validation/authorization-approved-at-20261101/CROSS-LANGUAGE-PREFLIGHT.md)。
- [ ] 1.3 RUN-001～003/010真实认证入口、来源映射、新grant传输与ACK/消费分离（依赖T完整授权）。[settlement 授权链缺失静态分析](validation/settlement-head-chain-static-20261102.md)确认局部未知被当未撤销，但未证明生产越权或修改代码；legacy、合法收尾与未知效果须分别设计。
  - 主线程真实Auth同Mount/handler/Go→Node选择59/59、protocol全包58/58、daemon Root选择8/8，均0skip/exit0。pinned manifest接线进行中；当前head/撤销与私有daemon凭据隔离未闭环，不代证整TC/wake/TaskService。

## 2. 永久逻辑根键、实际四阶段恢复（P0）

- [ ] 2.1 RUN-004/005永久logical_dispatch_key、原根/技术子链/adoption及context保留（依赖T修复receipt）。
- [ ] 2.2 RUN-006/007真实统一wake、四阶段入口与启动发现；余额0仍可验证已准入修复（依赖2.1）。
- [ ] 2.3 RUN-008/009旧run兼容、联合证据身份、生成/安装/pin配套（依赖2.2与T policy/registry）。
- [ ] 2.4 实际代码英文注释，CUSTOM.md按当时结构登记；schema/query/model/生成物配套，索引CONCURRENTLY独立迁移。

## 3. 最小通知与故障恢复（P0/P1）

- [ ] 3.1 NTF-001～004三类主动通知与业务/维护分流（依赖2）。命令分隔符守卫仅完成[局部独立复核](../../../../validation/notice-render-fields-20261029/REVIEW-COMMAND-LINES-V2.md)，正文伪行、兼容性及真实生产者未闭合，不算整项验收。
- [ ] 3.2 NTF-005～007同Inbox身份、pending/delivered、并发/崩溃恢复与客户端去重（依赖3.1）。[X6 静态复核](validation/notice-x6-static-followup-20261029.md)：可信收件人、幂等身份与恢复链路未闭合；关联但非通知的 [Composio 事务前风险](validation/composio-pretransaction-static-20261029.md)待独立确定范围、事实绑定与验证。
  - 主线程core目标25/25、desktop gate18/18，0skip/exit0；client异步失败/超时/late/mute/focus回修已有真实RED。confirmed scope 的[失败/重试内存组件观察](validation/desktop-confirmed-recovery-20261103/README.md)为 5/5（含1项假时钟自检）；[监听注册失败回修](validation/desktop-confirmed-listener-20261103/README.md)有 2 项 RED→GREEN，另复跑上述夹具及 scope 共 11/11。不证明真实 OS 或重启；服务器/mobile/GC/重启/OS展示未验收，不标整TC或切片done。

## 4. 验证（P0）

- [ ] 4.1 每片TC非零且全部通过、完整覆盖、实际产物与相关回归核对；未执行/skip不得计通过。
- [ ] 4.2 隔离真实route→T CLI→wake→TaskService及数据库三路径，前端重复Inbox ID验证。
- [ ] 4.3 全部相关测试/生成/格式/类型/独立评审与14类失败检查；报告真实耗时和未验证边界。
- [ ] 4.4 Gate3等待用户，不自行commit/push、迁移在途CR或生产部署。

### 2026-11-04 续做第七轮（WP6 通知最小切片 + 委托分层）

- [x] **WP6-1 同事务投递原语**：`execution_notice.go` 拆出 `DeliverNoticeTx(ctx, tx, ev)`（在调用方事务内写 notice+inbox，不广播不标记）与 `BroadcastNotice`（提交后广播再置 delivered），`deliverNoticeWith` 降为独立路径包装。顺序刻意：静默检查先于任何接线依赖；内容校验先于接线校验（否则写不通的事件会报 "broadcast is required"）。
- [x] **WP6-2 接收者进入通知身份**：原 `NoticeDedupeKey` 不含接收者，同一事实换人时可能被旧键去重吞掉；现将规范化接收者并入新键，投递期拒绝空接收者。组件测试覆盖键的区分与归一化，尚不证明 TC-NTF-006 的真实投递。
- [x] **未按 design §5 加 inbox partial UNIQUE 索引**：目前采用 notice 唯一键与调用方同事务写入的候选方向，已登记 `ADJ-AIFI45-M009`（`resolved:false`，9 条全 false）；是否足以替代设计索引仍须评审及真实数据库并发验证。旧键不含接收者，升级后的新键重放可能再创建一条 notice/Inbox，兼容策略尚未确定。
- [x] 证据：定向变异 RED 一条（`RECIPIENT_CHANGE_SWALLOWED`，恢复后 SHA 逐字节一致）→ GREEN `noticeguard_test` 顶层 14 / 子例 661 / exit 0，`go build ./...` 与 `go vet ./...` 干净。见 [wp6-notice-tx-20261104](validation/wp6-notice-tx-20261104/README.md)。
- [x] 过程留痕：三次红都是**自己重构顺序错误**（静默检查被后置、空接收者检查抢先、内容守卫被接线检查抢先），已修；未改断言迁就实现。
- [ ] 仍未完成：`DeliverNotice`/`DeliverNoticeTx` **生产调用数为 0**（无业务事实接线，接线点属产品语义，未猜）；DB 级 TC-NTF-001～007、客户端重投、真实广播故障恢复未运行；不保证桌面弹窗/已读。
- [ ] 委托记录：锁释放清点（balanced `OpenAIPersonal/gpt-6.1-terra:high`）与两仓改动复核（strong `GB-JP/kimi-k3.1-pro:high`）均为只读子代理；requested 模型可核，**后端实际 effort 无法自证**。

### 2026-11-04 续做第八轮（WP6 独立复核后的修正）

- [x] strong 复核（`GB-JP/kimi-k3.1-pro:high`，只读）结论 **BLOCK**，三条全部为真并已修：①广播改用解析后的 canonical `wsID.String()`（原样传事件字符串会让非规范 UUID 改变广播入参）；②撤销 `BuildNotice` 的空接收者硬失败——渲染与投递是两件事，4 处只渲染的 DB 用例 fixture 本就不带接收者；改为键内区分 + 投递期拒绝，错误优先级回到原样；③键内按 `uuid.Parse(...).String()` 归一化，避免 32hex 与连字符写法把同一人拆成两条 Inbox。
- [x] 修正后 GREEN：`noticeguard_test` 顶层 14 / 子例 661 / exit 0，`go build ./...`、`go vet ./...` 干净；定向变异仍能精确打红 `RECIPIENT_CHANGE_SWALLOWED`。
- [x] 复核同时确认：`DeliverNoticeTx` 确不提交/不广播/不标记；`merge-effects.mjs` 未见从 expected 推导成功、attestation 旁路或 confirmed 正常路径被误 halt（A 项 PASS_WITH_NOTES）。
- [ ] 复核指出的 A 项观察未处理：`merge-effects.test.mjs` 只钉了 `true` 与缺省，未钉 `false/1/"true"`；若日后放宽成 truthy 放行不会变红。留作待办，不因此再加断言层。
- [ ] 仍未完成同前：旧键与新键重放兼容方案未确定、生产调用方为 0、DB 级 TC 与客户端重投未跑、不保证弹窗与已读。

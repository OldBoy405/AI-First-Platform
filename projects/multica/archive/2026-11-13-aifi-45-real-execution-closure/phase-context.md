# Phase Context — 2026-11-13-aifi-45-real-execution-closure

<!-- 阶段交接摘要，冲突时以各 phase 正式产出物为准。 -->

---

## Phase 1: UNDERSTAND (completed 2026-11-13T20:04:39)

### 关键决策
- 范围收窄为 4 个有限保证：真实来源、真实 daemon+agent 节点证据、撤销后不推进、workspace 删除后 command/reservation。M007 五项裁定、M008 可信 no-effect 与自动重准入、M010 不纳入。
- Q1–Q6 按建议：真实运行只覆盖 requirement/architecture；节点证据生产方式由 SPEC 裁定；现有认证入口签发的授权算真实人类事件；C5 只做 workspace 边界；撤销只取最小闭合；architecture run ≤3 次、模型由用户指定、非 Fable。

### 被否决的方向
- 按 M 编号拆碎片 change；承诺可信 no-effect；改锚 source。

---

## Phase 2: SPEC (completed 2026-11-13T21:38:43)

### 关键技术决策（用户 Gate 2 确认「G2-1～G2-6 按建议」）
- G2-1 D1-B：节点 agent 启动前由 daemon 预消费，生成该任务当前 generation 的唯一回执与自身 effect；authorized 节点 endpoint 至多 2 个不同 challenge（明示修订归档 SC-AUTH-007），第三个 409；run 结束不重复消费。若授权材料可见性必须改 crctl/skill，停下建成对 tools change。
- G2-2 D4-A：`ControlCommandInput.WorkspaceID` + workspace `FOR SHARE`，迁移 33 处测试 fixture；旧探针 `TestWorkspaceDeletionRefusesNewCommand` 断言不变；锁序 workspace→claim→head→lineage→cursor。
- G2-3：2 次 architecture run（A 主链、B 撤销停止），第三次仅止损复跑且重新征得同意；模型、费用、podman/一次性库/backend/daemon 在 BUILD 前单独授权。
- G2-4：CR 由 fixture 种到 requirement-approved，不预置 grant；不做完整 requirement 真实 run。
- G2-5：长程预授权只覆盖普通文件实现与无外部资源测试。
- G2-6：proposal 的 `anchoring.level` 保持 L1，L2 接口锚定写在 design.md「接口锚定（L2）」。

### 模型分层
- design：strong planner `GB-JP/kimi-k3.1-pro:max`（actual=unknown）；事实核对：balanced `GB-JP/deepseek-flash:max`（actual=unknown）；其余为主会话。

### 经验触发记录
- 锁序先于读守卫、真实资源清理覆盖失败路径、独立 subtest、驱动拒绝未知参数，已纳入 SC-REC-006、SC-WSD-006 与 test-plan 原则。

### 产出物清单
- design.md、canonical/specs/code（3 个 capability）与 agent（2 个）、specs/*/spec.md Human View、test-plan.md（10 TC，全 command 型，无 manual），Gate 2 已确认。

### BUILD 前待办
- 节点 agent 的 `.crctl` 授权材料来源未验证；preflight 崩溃重领是否总得新 generation 未验证；podman、镜像、PG17、pi CLI、模型凭据未验证。
- tools 工作树有未提交的 M008 `planRecovery` 改动，归属未明，不吞并。
- Phase 3 执行模式尚未选择（Step 8 须用户选择）。

### 完整上下文文件清单
- design.md、test-plan.md、canonical/proposals/、canonical/specs/

---

## Phase 3: BUILD (in_progress，长程 full_auto，pre_auth 2026-11-13T21:46:45)

### 执行约定
- 长程预授权不覆盖：一次性 PG/podman、真实模型、真实 backend/daemon、tools 仓、提交推送部署、受审文档修改。简单任务可委派 balanced 子代理（`GB-JP/deepseek-flash:max`，pi-web 内置子代理）。
- 8 个切片顺序执行（slices.md）；止损：S5 真实 run A 首次失败只修 S1–S3。
- 环境基线：`go test ./internal/daemon` 在本 Windows 开发机有 27 个既有失败（claude 可执行文件/长路径/ Channel*/ M26*），与 HEAD 基线逐名相同，不属于本 change。（计数口径：27 是失败的顶层测试名数，S9 回归与 2026-11-14 的 C1 后整包回归按失败事件数计为 28，其中多出的一条是子测试；两种口径下与 HEAD 的失败集合均逐名一致。）

### 切片记录
- S1（endpoint 基数）：`startExecutionBindingEndpointLimit`、`Task.ExecutionPreconsumed`（内存，`json:"-"`）、`Task.PipelineExecutionContract`（S2 使用）；新文件 `execution_binding_endpoint_rec_test.go`（TestTC_REC_003 4 个子测试 + 预消费预算 2 个）；TC 覆盖 1/1。
- S3（daemon 预消费）：`prepareClaimedPipelineTask` 读取 claim 的 `PipelineExecutionContract`（`""`=legacy，`authorized-execution/v1`=strict 预消费，其他=`CR_WORKSPACE_BINDING_UNAVAILABLE` 拒绝）；成功后 `Task.ExecutionPreconsumed=true`，`recordDeliveredConsumption` 对其直接 no-op；`executionBindingEndpointForRun` 据此取 limit 2。新文件 `execution_node_preconsume_test.go`（TestTC_REC_001，7 个子测试）。校正 `daemon.go`、`execution_consumption_client.go` 的陈旧注释。TC 覆盖 1/1。
- S2（claim 合同值）：`handler/daemon.go validateClaimedPipelineCarrier` 末尾 EXISTS 查询初始 execution approve；`AgentTaskResponse.PipelineExecutionContract`；`pipeline_execution_contract_test.go`（TestTC_REC_002，5 个用例）已写、vet 通过，**未执行**（需一次性 PG；handler_test.go 默认连 localhost:5432，禁止无 DATABASE_URL 运行）。

### 阻塞（E4，2026-11-13）
- 节点 agent 的 `crctl advance` 读不到 daemon 信任库的 execution-grant：crctl 只接受 `--trust-root`（无环境变量、无默认），SKILL.md 全部不传；daemon 的 trust store 在 `~/.multica/execution-trust/<ws>/`，只喂 daemon 自己 spawn 的 crctl；`crevents.go deliverGrants` 写的是 legacy 人工审批 grant，与 execution-grant 文件名不匹配。
- 因此 D1-B 的"节点自身 advance 走 endpoint 取第二个 challenge"在真实 run 中会先死在读 grant。静态推断，未真实运行验证。
- 裁定（2026-11-13，用户原话「A」）：阻塞走成对 tools change（先例 `2026-10-29-trusted-verdict-outcome-binding`）。tools change 的名称、范围、Gate 待用户确认方案后再建；在其交付前，multica 切片 4–6（真实 run）暂停，切片 7 与已完成的 1/3 不受影响。不采用 B（写入 agent 可写的 `{root}/.crctl`）。
- S2 完成：`selections.json` 新增 rec-001/002/003；rec-002 在一次性 PG 通过(6 通过)，去掉实现后 3 个授权用例失败，实例均 released remaining=0。
- 用户 2026-11-13 确认：tools 成对 change 方案（名称 `2026-11-13-aifi-45-node-trust-root`）、不动 tools 工作树既有未提交改动、授权 run-selection 的一次性 PG（仅限其自管实例）。

### S7 workspace 边界（2026-11-14，完成）

- 实现：`governance.lockWorkspaceKeyShare`，三处取锁点（`ApplyControlCommandTx`、`CreateReservationTx`、`HandleDaemonExecutionConsumption` 在 claim/head 前）；`ControlCommandInput.WorkspaceID` 必填。
- 33 处 fixture 迁移由 balanced 子代理（`GB-JP/deepseek-flash:max`，actual=unknown）完成，主会话核对范围与换行符。
- 一次性 PG（`run-selection.mjs`，remaining=0）：`handler-wsd-race` 6/6、`governance-wsd-lock` 1/1（C1 之后新增锁序交错测试，现 2/2，见 ADJ-C1-1）、`handler-wsd-no-recreate-command` 5/5（原红已转绿）、其余 wsd/m005/wp4 选择全绿、handler 执行相关 196/196。
- 变异：去 Apply 取锁 → command 两交错红；再去 CreateReservation 取锁 → 6/6 红；`FOR SHARE` → governance-wsd-lock 红；去 handler 取锁 → governance-wsd-lock 红。均已逐字节还原。
- governance 整包失败集合与 HEAD 相同（48，既有环境失败）；`TestTC_ATB_009` 在 HEAD 单独跑也会失败，未定位根因。
- **偏离（受审文档未改，待文档同步轮重审 Gate 2；已于 2026-11-14T02:46:19 重审通过）**：见 `design-adjustments.md` 的 ADJ-S7-1（`FOR KEY SHARE`）、ADJ-S7-2（不加生产 hook）、ADJ-S7-3（新增 `governance-wsd-lock`）。
- S8 遗留：`test-ownership.json` known-finding 条目与 `test-ownership.test.mjs` TC-TOR-001 须一并调整；`selections.json` 已补 `handler-wsd-race`、`governance-wsd-lock`。

## 2026-11-14 文档同步轮（Gate 2 stale，待用户重审）
- 用户回复「授权」，AI 解读为授权同步文档，不是 Gate 2 重审，也不是 S4–S6 真实运行授权。
- 已同步：design.md（D1 第 7 条信任根注入、D4 锁模式与探针重写、G2-7/G2-8）、canonical code/agent specs（SC-REC-008、CP-REC-009、CP-WSD-007 及 WSD 三条 and）、test-plan.md（TC-REC-009、TC-WSD-007，证据计划 12 TC）、slices.md（S9）、tasks.md（§9、3.3）。proposal 未动，Gate 1 仍有效。
- `stdd validate` 此刻的结果不构成通过证据（当时 `specs/*/spec.md` 尚未渲染，渲染后即报 TC 案例数少于 Scenario 数，见下方 Gate 2 重审条目与 design-adjustments.md）；`gate status` Gate 2 stale、Gate 1 有效；`agent verify --dry-run`（real-execution-closure）含 CP-REC-009/CP-WSD-007。第二个 agent task 的「证据计划 task 与 runner 不一致」为既有行为（原 test-plan 同样报错，已对照）。
- 差异清单见 design-adjustments.md「同步轮新增与变更清单」；完整 unified diff 在 Temp/gate2-resync.diff（406 行，非记录文件）。
- 实现 S9（daemon 注入）须等 Gate 2 重审通过；S4–S6 仍需用户单独授权。
- **Gate 2 已重审确认（2026-11-14T02:46:19）**：用户原话「确认 Gate 2」，`--reapprove`。首次写入因 code spec 的 Human View 落后于 canonical 被拒（未写入任何状态）；经与改动前 canonical 渲染逐字节比对确认是纯生成物后，用 stdd `_generate_spec` 重建两份 `spec.md`，再次 approve 成功。Gate 1 未重审。
- `stdd validate` 现报「TC 案例数 (12) 少于 Spec Scenario 数 (13)」，原始状态即 10 对 12，非本轮引入，详见 design-adjustments.md；不声称 validate 通过。
- 下一步：S9（daemon 注入，TC-REC-009）可开始；S4–S6 仍需用户单独授权 podman、backend/daemon、非 Fable 模型名、次数、费用。

## 2026-11-14 S9、S4 完成（均未提交）
- 用户授权：S9；真实运行用固定来源的 crctl 副本（ADJ-S5-0，S5 实现）；podman 与 cleanup-smoke（无模型）。
- **S9**（TC-REC-009）：`Task.ExecutionTrustRoot`（`json:"-"`）在预消费成功且 `nodeAuthorized` 时设为 `store.Root`；`injectTaskCRWorkspaceEnv` 开头先 delete，已绑定且该字段非空时发布 `CRCTL_EXECUTION_TRUST_ROOT`。发布判据只有 `ExecutionTrustRoot != ""` 一个（变异 M2 暴露与 `ExecutionPreconsumed` 的重复判断，已删）。`execution_trust.go` 的 daemon-only 注释已校正。5 个变异均红并还原；`rec-009` 经 run-selection 通过；daemon 整包失败集合与 HEAD 逐名相同（各 28，balanced 子代理取证，我核对）。
- **S4**（TC-REC-007）：`scripts/aifi45-real-run/` 驱动、42 个 hermetic 测试、8 个变异、真实 cleanup-smoke 通过。`.gitignore` 加 `scripts/aifi45-real-run/.local/`。细节见 design-adjustments ADJ-S4-1。
- 未做：S5 真实 run A、S6 真实 run B、S8 余项；CI 是否运行 real-run 的 node 测试（ci.yml:1076 只跑 `scripts/aifi45-disposable/*.test.mjs`，加入需改 ci.yml，S8 时请用户定）。
- 真实 run A 的前置：用户给出模型名（非 Fable）、次数（run-config.json 的 max_runs）、cost_ack 原文；S5 先实现 crctl 副本与 architecture-main 场景。

## 2026-11-14 S6 组件层、S8、C1 评审（均未提交）
- **S6 组件层（TC-REC-006，`rec-revoke`）**：经真实授权/撤销路由后，`ResumeActiveRuns`、节点完成路径（`Reconcile`，即 task-completed 事件所调）在原 Runner 与重启 Runner 上都不派发、不推进；writer 停在 `running`/`admission`/`HEAD_REJECTED`，任务与节点行数不变，reviewer 节点行为 0，回执与已有 approval 行不变；「未撤销」对照子测试会推进。无生产改动。变异 4 个均红。**切片整体未完成**（6.3 真实 run B 未做），因此不写入 `.stdd.yaml` 的 `slices_completed`。未覆盖：派发入口 `decideUnderHeadLock`（ADJ-S6-1）。
- **S5 的无模型部分**：`scripts/aifi45-real-run/crctl-stage.mjs`（固定来源 crctl 副本，ADJ-S5-0）已落地并有测试，尚未接入场景；`architecture-main`/`architecture-revoke` 场景未写，`run.mjs` 对它们输出 `INCONCLUSIVE ... SCENARIO_NOT_IMPLEMENTED`。
- **S8**：8.1 台账、8.2 CUSTOM.md（M32 #334–#337）、8.3 全组回归（39/39，remaining=0）完成；8.4 余 C2–C7 与 Gate 3。
- **C1**：code（strong）、test_config（balanced）、docs_skills（economy）三路评审均已返回并逐条处置，见 design-adjustments.md 的 ADJ-C1-1、ADJ-C1-2、ADJ-C1-3。
- **受审文档头部的陈旧措辞（刻意未改）**：`design.md` 与 `test-plan.md` 头部仍写「待 Gate 2 重审」。这两份是 Gate 2 的指纹，改一个字节即 stale；Gate 2 已于 2026-11-14T02:46:19 重审通过，以 `.stdd.yaml` 为准。
- **取证调用方式（解决试跑时的「证据计划 task 与 runner 不一致」）**：证据计划块的 `task` 是 `real-execution-closure`，`tasks` 列表含 `workspace-delete-execution-tables`。正式取证只以第一个 task 调用一次：`stdd agent verify real-execution-closure --change 2026-11-13-aifi-45-real-execution-closure --run <id>`，它会一并覆盖第二个 agent spec 的检查点；单独以 `workspace-delete-execution-tables` 为 runner 调用就会报该错，不是计划写错，也不要改 test-plan（会使 Gate 2 stale）。
- **试跑证据的时效**：此前的试跑（10/12，CP-REC-004/005 因真实 run 未做而红）早于本轮 C1 修复；最终取证须在真实 run A/B 之后、代码稳定时重做。本轮 C1 修复后的全组 `run-selection`：39/39 PASS，remaining=0（`Temp/s8full5.log`）；`scripts/aifi45-real-run` 与 `scripts/aifi45-disposable` 的 node 测试合计 222/222。
- **2026-11-14 第二次同步（A0 发现 B1/B2，待 Gate 2 重审）**：design 新增 D1.8（strict source 任务预检/预消费，S10）、D1.9（tools `workspace inspect --detail` 补 `targetSpecId`/`targetVersion`，并入 tools 的 `node-trust-root`，S11）、G2-9；canonical 新增 SC-REC-009/010、CP-REC-010；test-plan 共 13 TC（新增 TC-REC-010）。重审 Gate 2 前不得写 S10/S11 的代码；tools 侧的 Gate 1/2/3 由 tools change 独立重审。证据见 design-adjustments.md#ADJ-A0-1。
- **2026-11-14 第三次同步（A0 重跑发现 B3，待 Gate 2 重审）**：design 新增 D1.10（预消费信任根按 task generation 取子目录，S12）、G2-10；SC-REC-001 增一条 and、TC-REC-001 增一个子用例、TC-REC-009 期望值随之更新；不新增 SC/TC/CP，共 13 TC。重审 Gate 2 前不得写 S12 的代码；不改 tools 合同、不改平台侧。证据见 design-adjustments.md#ADJ-A0-2。

## Phase 3 BUILD 收尾（2026-11-15）

- 取证 run `bb5a9173-27cf-40fc-bb62-66e3e20c8bd1`：**13/13 CP 通过**（含真实模型 run A 与 run B）。`stdd ci check-failures` 报 TC 覆盖 13/13 (100%)。
- 真实运行的观察层已改为模型无关（账本 + 信任根 generation 目录的执行回执），替身模式保留 trace；诊断日志写到系统临时目录（`<tmp>/aifi45-real-run-logs/`），避免污染取证输入集。
- 关键口径修订（实现层，未改受审文档）：reviewer 节点 `passed` 即视为结论性 PASS（`detail.verdict` 允许缺省）；撤销场景重启后允许 0 消费的被拒重派、禁止 reviewer 任务与任何已发生的消费/effect；撤销后 writer 控制写被 binding 端点 409 拒绝是证据事实。
- test-report.md、code-structure-delta.md、CUSTOM.md M32 #338 已完成。`stdd validate` 仍报 TC 13 < Scenario 15（沿用不处理）。
- **下一步**：Gate 3 等用户确认（选定 run 已可用）；确认后按路径清单提交（multica 一个提交、tools 只提交自己的改动），不推送。

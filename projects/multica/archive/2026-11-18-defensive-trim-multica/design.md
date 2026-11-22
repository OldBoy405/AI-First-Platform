# Multica 防御性编程精简 — 技术设计

## Context

`2026-11-18-defensive-trim-multica` 对应已确认的 Gate 1 Proposal，基线为 Multica `main@0c47c67e7`。范围是源方案第 1 节剩余项、第 2 节、第 3 节进展读取和第 6 节。目标是在输入边界解释一次，在生效处核对仍会变化的事实；防配置错写、选错对象、并发覆盖及中断后重复执行，威胁模型不含操作者故意改库、改账本或用可信密钥重签。

路径缩写（前四个相对 Multica 根）：`G/` = `server/internal/governance/`，`S/` = `server/cmd/server/`，`D/` = `scripts/aifi45-disposable/`，`R/` = `scripts/aifi45-real-run/`；`P/` = 数据仓 `projects/multica/`。行号均指基线。

## Decisions

### C1：一次准备，重放与签发共用冻结字节

- **现状证据：** 签发 HTTP 先补值再比对重放，首发又从原文提取仓库、身份、协调器（`G/execution_authorization_http.go:113–226`）；builder 再补值、解码和解析（`G/execution_authorization.go:259–339,848–857,909–947`）。
- **方案：** 在已有 CR `FOR UPDATE` 内读取同工作区 shell issue 的项目，并由包内 `prepareExecutionAuthorization` 产出已解码字段表、补全后的确切字节和摘要；`completeExecutionContractFields` 消费字段表。缺失或 `""` 才补部署值，合法但不同的首发走原 409 出口；需补值时以现有 `json.RawMessage` 编码、关闭 HTML 转义并移除尾换行（`G/execution_default_contract.go:54–110`），完整请求交付原字节。重放核对原授权人、同冻结字节/摘要和锁内项目，命中即回原记录；非精确重放保留原冲突出口。仅首发校验冻结字节的 UTF-8，再从字段表解析必填字段、作用域及可选身份（区分存在键与省略）；按去重、排序后的 UUID `FOR SHARE` 核对真实资源类型、作用域、绑定摘要，交给包内 `buildExecutionAuthorization` 签发，记录和初始头同事务提交。
- **为什么：** 字节重序列化会改变 CRLF、空白或 `-0` 及其签名。对所有重放重查资源或验当前头，会把找回不可变记录变成重新授权，破坏资源漂移后重试和丢响应恢复；首发才需要当前资源事实。

### C2：读端验证存储协议，消费者接收已验证结果

- **现状证据：** 头查询已连接同 workspace/CR 的指针记录与当前项目（`server/pkg/db/queries/approval.sql:25–35`），但验签后又运行新申请解析和绑定检查（`G/execution_authorization_head.go:95–185`；撤销读端 `G/execution_authorization_revoke.go:344–435`）；绑定、激活、消费、动作还重解码 payload。`validateExecutionContractFields` 仅有测试调用（`G/execution_default_contract.go:112–133`）。
- **方案：** 头校验返回包内 `verifiedExecutionHead`（头摘要、对应 purpose 的已验证 typed payload，撤销原样重放可取已验冻结字节）。每条记录验签、解码一次；按 DB decision 分派时核对有签名的 purpose。按 v1 校验信封/存储对象形状、大小、规范 base64、签名、`SHA256(domain || 原 payload bytes)`、`source_bindings` 及原文 JSON 完整性与字节摘要，再核对记录元数据、指针、workspace/当前项目/CR、lineage/revision、部署合同。撤销读端用已签 payload 验唯一起始根、lineage、前驱、递增 revision 和终止语义；GET 可读有效撤销，执行入口只接受当前 `initial/approve`。绑定、激活、消费和敏感动作直接用已验 payload 和摘要，各自核对会变化的事实；冻结原文不重过申请及资源选择解析器。
- **为什么：** 签发端负责原文到签名事实的映射，读端负责完整性及当前适用性；申请规则收紧不应连带作废历史批准。测试用 v1 有效历史形态夹具模拟旧规则，不把它当作 HEAD 曾签发的证据；原来用可信密钥重签不同 goal 来要求读端重审的断言，移到签发 HTTP 核对原文与实际 payload 的映射。

### C3：动作与撤销使用同一把 CR 排他锁

- **现状证据：** 动作事务先锁 CR `FOR UPDATE`、再锁指针记录 `FOR SHARE`、验头后才结算（`G/execution_sensitive_action.go:76–151`）；结算又锁 CR、查 decision，合成 reject 才走 `no_effect`（`G/execution_control_policy.go:150–174`），唯一生产调用已排除这个分支。
- **方案：** C2 完成后，在现有 `ReadCommitted` 事务中取 CR 排他锁时一并取指针，随后共享锁定其目标记录；有效头在同一事务调用 `applySensitiveActionLockedTx`，按 kind/target/environment 匹配，按 `lineage + action_scope_id` 先查 `operation_id`、再计额度及写回执，提交后响应。撤销同取 CR 排他锁并追加、CAS；撤销先提交时动作在无效头出口终止。双向交错用生产入口：动作方向先占 approval 行，撤销方向用表级 `SHARE` 挡 approval 插入；确认后取对象正在等待，再从独立连接短超时探测 CR 锁、发竞争请求并放行。原合成 reject 测试由该交错替代。
- **为什么：** 已验批准在行锁保护下到提交都有效。通用 `lockExecutionAuthorizationHead` 的 CR `FOR SHARE`（`G/execution_head_lock.go:12–55`）适合并行绑定，但不能串行化两个额度写入者。

### C4：GET 使用同一 run 状态，坏详情按读失败处理

- **现状证据：** GET 的 scope 查询和 `progressOf` 各读一次 status（`G/pipeline_progress.go:84–90,169–195`）；`frontierNode` 将非对象解码错误降为空 map，也接受解码为 nil map 的 JSON `null`（`:50–68`）；未知 status 返回 `idle`（`:91–139`）。生产已挂叶子 GET（`S/router.go:1897–1909`），挂载 helper 只在测试中用。
- **方案：** `progressOf(ctx, runID, status)` 用已核对工作区的同一行 status 推导 GET；POST 的 `receiptProgress` 在提交后经 `readProgress` 取一次状态再调用它。实际读取的前沿 runner 缺键由 SQL `COALESCE` 视为空对象，非对象（含 JSON `null`）及未知状态报错；GET 用既有读失败出口，POST 记录错误，成功回执仅省略 `progress`。实际读取的对象不因未使用字段的数字超出 float64 范围而报错。SC-EWV-101–103 在 `internal/governance` 验证实际 handler：用测试池 pgx query tracer 在 GET 首读后由独立连接推进状态、在 POST 读回执时写入坏详情；未知状态直接调用生产推导函数。SC-EWV-104 在 `cmd/server` 用 `NewRouterWithOptions` 和真实凭证验证生产路由。
- **为什么：** 共用同一 status 足以避免同一响应矛盾；全局一致快照或大型 JOIN 会扩大读取/事务范围。父路径 `Route/Mount` 遮蔽 POST 已由 PA-006 证明，故使用生产叶子 GET。

### C5：pin 严格解析，固定提交和显式 overlay 分流

- **现状证据：** `stackStages` 仅对 pin 做换行替换和 `trim`（`R/stack.mjs:350–358`）；`stageCrctl` 默认为 `HEAD`、固定路径 `assertPureAddition` 自比后还覆盖写 `crctl`（`R/crctl-stage.mjs:86–146`）。CI 已共用 `parsePin`（`D/tools-pin.mjs:22–28`）。
- **方案：** 默认合同 tools 阶段把原始 pin 文本直接送 `parsePin`，非法值在 `TOOLS_FAILED` 边界退出，早于 stage 目录分配或下游阶段；非默认合同显式传 `ref: "HEAD"`。`stageCrctl` 要求显式 ref；固定路径禁用 Git 本地对象替换，经 `git rev-parse --verify <ref>^{commit}` 核对确为指定 commit，并从该 commit 读取树与 blob；两份既有摘要取同一 `crctl` 字节摘要，`addedFiles=[]`；坏对象不回退。只有显式 HEAD 读工作树并走纯追加检查及新增文件白名单。
- **为什么：** 防止 pin 穿透固定验证边界进入 overlay，也使报告的 commit 和实际取材一致。

### C6：行为增量与 fork 台账同步

- **现状证据：** `CUSTOM.md:16–21,78–84` 要求 fork diff 可归因；`CUSTOM-LEDGER.md:429–450` 定义最小追溯项，`:231–236` 有原生 STDD 索引先例。C5 属现行“唯一 Tools pin”消费者约束。
- **方案：** canonical 只记录 C1–C5 的行为增量，交付时按下表定位并入现行条款；台账按 `CUSTOM.md` 更新明细、模块与追溯索引，用实际 change/任务标识。结构清理与交付核对集中在 Phase 3 清单。
- **为什么：** 行为契约说明生产入口的保证；台账说明 fork 的归属和合并口径，两者分开。

## Architecture

```text
人类签发 HTTP → CR 排他锁 → 一份准备结果 ┬→ 重放原记录
                                      └→ 解析首发事实 → 资源共享锁 → 签发 → 记录+头提交
头查询 → 存储/当前事实核验 → 已验证摘要+payload → GET 摘要或执行消费者
敏感动作 → CR 排他锁 → 指针记录共享锁 → 已验初始头 → 查重/计额/回执 → 提交
人类撤销 → 同一 CR 排他锁 → 验头 → 追加+CAS → 提交
GET → 已核对工作区的 status ─┐
POST → 提交 → 一次读取 status ┴→ progressOf(status) → 各自读结果出口
Tools 阶段 → parsePin 或显式 HEAD → 固定提交树或工作树 overlay
```

实施先做 C1、C5，C2 完成后做 C3；C4 可独立实施。

### 逐文件实施范围

`G1–G4`、`B5–B10` 分别指 Proposal `constraints` 原顺序中的四项保证和六项边界；`P1–P8` 为 `success_criteria`（从 1 起）。B5、B8、B10 适用于全表：仅改已标记或登记的 fork 代码，沿用现有安全与恢复边界；上游原有逻辑、历史记录、归档证据和共用框架在范围外。DB 取证均适用 B9。

| 路径 | 允许的改动／边界 | C 项 | 对照 |
|---|---|---|---|
| `G/execution_authorization.go` | 收拢请求准备及签发，输入大小、UTF-8、单一对象、重复键、字段及格式优先级仍属既有入口规则。 | C1 | SC-RUN-201–203；G1、B7、P1/P3 |
| `G/execution_authorization_http.go` | 共享准备结果，人类认证、工作区成员与 owner/admin、CR 项目及真实资源绑定仍走既有边界。 | C1 | SC-RUN-201–203；G1、B7、P1/P3 |
| `G/execution_default_contract.go` | 复用字段表并移除测试比较器，字面 `null` 拒绝及固定默认常量依 PA-008/原合同。 | C1/C2 | SC-RUN-201/203/204；G1、B7/B9、P1–P3 |
| `G/execution_authorization_head.go` | 改为存储验证和包内已验结果，对外仍为原 head、record、公钥及 `Cache-Control: no-store`。 | C2 | SC-RUN-204/205；G1、B7、P2/P3 |
| `G/execution_authorization_revoke.go` | 读端按已签撤销字段验链，写端申请解析、签名 reason 编码、同快照验根、锁、追加/CAS 与重放仍按原协议。 | C2 | SC-RUN-205；G1/G2、B6、P2 |
| `G/execution_binding_issue.go` | 复用已验头，绑定的协调器及挑战仍由原入口核验。 | C2 | SC-RUN-204/205；G1、B6、P2 |
| `G/execution_activation.go` | 换 payload 来源，claim、task/runtime/generation、消费前置、回执幂等仍归激活入口。 | C2 | SC-RUN-204/205；G1、B6、P2 |
| `G/execution_consumption.go` | 换 payload 来源，现有锁序与 daemon、任务和回执核对仍由消费入口负责。 | C2 | SC-RUN-204/205；G1、B6、P2 |
| `G/execution_sensitive_action.go` | 复用已验头并合并取锁与读指针，结算走同一事务。 | C2/C3 | SC-RUN-204–207；G1/G2、B6、P2/P4 |
| `G/execution_control_policy.go` | 精简敏感动作结算，repair、resume、merge 等其他 `no_effect` 在范围外。 | C3 | SC-RUN-206/207；G2、B6、P4 |
| `G/execution_authorization_test.go`、`G/execution_authorization_http_test.go` | 迁移签发调用，用冻结样本、实际 crctl 互操作及既有 HTTP 用例验证；首发拒绝坏 UTF-8，非精确重放仍报冲突。 | C1 | SC-RUN-201–203；G1、B7/B9、P1/P3/P8 |
| `G/execution_default_contract_test.go` | 移除测试比较器依赖并迁移默认值、确定性用例。 | C1/C2 | SC-RUN-201/203/204；G1、B9、P1–P3/P8 |
| `G/execution_default_contract_http_test.go` | 经签发 HTTP 验空串、冻结、重放和零写入。 | C1/C2 | SC-RUN-201–204；G1、B7/B9、P1/P2/P8 |
| `G/execution_fixture_export_test.go` | 只迁移夹具内部签发调用，跨包夹具契约照旧。 | C1 | SC-RUN-203；G1、B7/B9、P1/P8 |
| `G/execution_authorization_head_test.go` | 复用重放/字节用例，区分历史可读与存储损坏。 | C1/C2 | SC-RUN-202–205；G1、B9、P2/P3/P8 |
| `G/execution_control_policy_test.go` | 删合成 reject 分支，既有作用域、额度桶和回执组件回归继续使用原测试。 | C3 | SC-RUN-206/207；G2、B9、P4/P8 |
| `S/execution_run_010_test.go` | 使用生产 router 验双向交错和额度，继续运行 `ordinary_grant_has_no_effect`。 | C3 | SC-RUN-206/207；G1/G2、B9、P4/P8 |
| `G/pipeline_progress.go` | 改状态来源及所读 runner 顶层对象校验，巡检、嵌套字段校验、DB CHECK、终态/活动任务/原等待原因及合法 idle 语义在范围外。 | C4 | SC-EWV-101–104；G3、B6/B7/B9、P5/P6 |
| `G/pipeline_progress_test.go` | 迁移既有推导矩阵并断言未知状态报错。 | C4 | SC-EWV-102；G3、B6/B7/B9、P5/P8 |
| `G/pipeline_progress_route_test.go` | 移除手工挂载夹具；直接验证 GET handler 的首读交错与坏详情，鉴权矩阵迁到生产 router 测试。 | C4 | SC-EWV-101/104；G3、B6/B7/B9、P5/P6/P8 |
| `G/pipeline_progress_receipt_test.go` | 用两个 POST handler 验证已提交后的读失败只省略进展。 | C4 | SC-EWV-103；G3、B6/B7/B9、P5/P8 |
| `G/requirement_shape_default_contract_test.go` | 既有 requirement 形态回归迁移到 `readProgress`，原断言不变。 | C4 | SC-EWV-102/103；G3、B9、P5/P8 |
| `S/pipeline_runs_route_coexistence_test.go` | 用真实成员和任务凭证在生产 router 验证 GET 鉴权、Runner 开关及两条 POST 的业务拒绝码。 | C4 | SC-EWV-104；G3、B7/B9、P6/P8 |
| `S/router.go`、`G/{runner,runner_requirement_entry}.go` | 只验证既有叶子挂载、成员鉴权/跨工作区 404、Runner 开关、启动/恢复 POST、回执形状及 CLI 兼容，生产挂载和调用点原位。 | C4 | SC-EWV-101/103/104；G3、B7、P5/P6 |
| `R/stack.mjs` | 实跑 Tools 阶段严格解析 pin，按模式显式传 ref。 | C5 | SC-CBE-101；G4、B9、P7 |
| `R/crctl-stage.mjs` | 分离固定树与 overlay，路径/blob/模式/必需文件保护及输出/清理协议照旧。 | C5 | SC-CBE-102；G4、B9、P7 |
| `R/stack.test.mjs` | 用临时 Git 仓库跑真实 Tools 阶段验证 pin。 | C5 | SC-CBE-101；G4、B9、P7/P8 |
| `R/crctl-stage.test.mjs` | 迁移到显式 ref 并验证坏对象和 overlay。 | C5 | SC-CBE-102；G4、B9、P7/P8 |
| `D/selections.json` | Phase 3 定向登记实际包、`run` 和 `expected`；既有基线按包执行口径另行适用。 | C1–C4/C6 | SC-RUN-201–207、SC-EWV-101–104；G1–G3、B9、P1–P6/P8 |
| `CUSTOM-LEDGER.md` | 登记本 change 的 fork 明细和索引，Pi `#102` 等共享文件 hunk 单独核对。 | C6 | SC-RUN-201–207、SC-EWV-101–104、SC-CBE-101/102；B5/B10、P8 |
| `P/changes/2026-11-18-defensive-trim-multica/canonical/specs/code/{authorized-runner,execution-wait-visibility,ci-backend-environment}.yaml` | 只写受影响行为增量，Proposal 为已确认输入。 | C6 | SC-RUN-201–207、SC-EWV-101–104、SC-CBE-101/102；G1–G4、B7–B9、P1–P8 |
| `P/specs/authorized-runner/spec.md` | 交付时合并历史头读取与 SC-RUN-010 敏感事务增量，默认合同、无锚点准入及 daemon/CLI 链仍依现行契约。 | C6 | SC-RUN-201–207；G1/G2、B6/B7、P1–P4/P8 |
| `P/specs/execution-wait-visibility/spec.md` | 交付时合并同一状态、坏详情和 SC-EWV-007 失败回执增量。 | C6 | SC-EWV-101–104；G3、B6/B7、P5/P6/P8 |
| `P/specs/ci-backend-environment/spec.md` | 交付时并入唯一 Tools pin 的实跑消费者，既有 CI/nonce/证据、`real-execution-closure` 及模型验收在范围外。 | C6 | SC-CBE-101/102；G4、B8/B9、P7/P8 |

仅核验：`G/{execution_head_lock,execution_merge_facts}.go`、daemon 准入和实际夹具消费者、SQL/生成物、`D/{tools-pin.mjs,tools-pin.test.mjs,selections.baseline.json}`、pin 文件、CI、`CUSTOM.md`。固定 Tools 互操作用现有 `AIFI45_TOOLS_ROOT`、`CRCTL_MJS`；DB 经 runner 自建 tmpfs、随机环回端口/密码、受限 nonce 角色及 TTL 的一次性实例。

### 验证

验证以 `test-plan.md` 的 13 个 Scenario、6 个 TC/CP 为准；既有受影响回归复用实际入口，在真实入口证明保证后即停止。测试仅在测试侧安排夹具和交错，无生产测试钩子或新增导出。

## 与方案/Proposal 不符之处

- 业务范围无偏离；源方案所述字面 `null` 缺陷已由上一 change 处理。`CUSTOM-LEDGER.md` 的 #346 已记生产叶子 GET，#353 记录测试迁移；旧手工挂载不是生产入口。
- Proposal 风险举例中的单个 CRLF 实际由 `parsePin` 接受；额外空白、多行及 `HEAD` 等才会失败。
- 原 `sensitive_revoke_interleaving` 只是合成 reject，原共存测试也未证明两个 handler 均到达业务出口；分别改用双向交错和真实凭证业务码，验收保证相同。

## Phase 3 验收清单

- 跟 C1 调用链核对包内只产一份字段表和冻结字节/摘要，签发函数无二次补值或原文提取，重放不读当前资源绑定。
- 全仓搜索 `validateExecutionContractFields`、`decodeExecutionBindingHeadPayload` 应无定义或调用；跟 C2 调用链确认验证结果由消费者复用。
- 改 `BuildExecutionAuthorization` 等公共入口签名前后须跨包核对全部生产和测试调用点（含 `cmd/server`、daemon 及 `governance_test` 夹具消费者），确认全部迁移。
- 跟 `applySensitiveActionLockedTx` 的唯一生产入口确认先验头再结算，函数内无第二次 CR 锁、决定重查或不可达 `no_effect`。
- 全仓核对 `MountPipelineRunProgressRoute` 和手工挂载夹具已移除，鉴权用例转至生产 router。
- 跟固定提交分支核对每个文件只物化一次、不读工作树，且无自比纯追加检查或覆盖写 `crctl`。
- 对照 `CUSTOM.md` 逐处核对 fork diff 在 `CUSTOM-LEDGER.md` 的稳定明细、真实 change/任务标识和最小验证命令，修正 #346 残留的旧挂载描述；格式不接受真实标识时停止并确认，不编造 CR。
- 在 `selections.json` 新登记 `run-authorization-head`、`run-sensitive-action`，扩展 `run-default-contract-issue`、`ewv-progress`、`ewv-route` 的 `expected`，逐项核对实际父/叶非零匹配、`skip=0`，被替换的保证有实际通过的叶子。
- 改前用 `git status`、工作树及暂存 diff 对照范围并核对 `CUSTOM-LEDGER.md` 等文件与 Pi `#102` 的 hunk；提交前复核，重叠未隔离则停止提交。

## 验证状态

- `ewv-progress` 与 `ewv-route` 分属 `./internal/governance` 与 `./cmd/server`；保留 6 个既有 TC/CP，不拆新 selection。
- Phase 3 已在独立 worktree 完成字节、事务交错、生产路由及固定 Tools 的定向验证（见 `phase-context.md`）。尚未生成最终同次证据；PA-001 的冻结输入见 `test-plan.md` §六，待补测和项目级质量检查见 `pending-adjustments.md`。

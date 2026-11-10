# AIFI-45 M005 consumption-effect — 测试方案

> STDD Phase 2 / Gate 2 草案。新增 4 个 TC、全部待 Gate 2 后 RED→GREEN；既有 TC-RUN-003 作回归，不新增测试。

## 一、测试策略

### 1.1 一组保证，一个入口

| 保证 | 内容 | 唯一入口 |
|---|---|---|
| G1 原子且可达 | 首次 consumption 在同一事务内产生该 task 的完整 effect 链，准入由 WAIT_CONSUMPTION 变 ADMITTED；签发失败则回执也不落库。 | `bindingIssueFixture` 的真实路由（`/api/daemon/crs/{crID}/execution-authorization/consumption`）+ 真实库 |
| G2 身份与链 | 链记录以 task id 为 request_id，command_digest 绑定冻结命令；同一 CR 的链连续；重放与新 generation 不重复。 | 同上 |
| G3 不放宽 | 伪造或未验签的行仍不能让准入放行；本 change 不改判定。 | **既有** CP-RUN-003-A…N 与 TC-RUN-003，只作回归 |

### 1.2 原则

- 每个保证只设一个检查层：真实路由 + 真实库。不另写 mock 层，不单测私有函数。
- 链的形状（seq、prev_digest、request_id、command_digest）直接查表断言，不查签发函数的返回值；不信任被测对象自己的计数。
- 失败路径只测设计承诺的一条：回执与 effect 同生同死。不为每个可能的内部错误各写一个用例。
- 所有用例经 `scripts/aifi45-disposable/run-selection.mjs` 的新选择 `m005-consumption-effect` 执行，每个选择一个一次性库；零匹配、skip、整包失败均不算通过。
- 不触碰共享库、不运行数据库迁移（本 change 无 schema 变更）。

### 1.3 已有资产与拟新增文件

| 资产（相对 multica 仓） | 作用 | 本轮处理 |
|---|---|---|
| `server/internal/governance/execution_binding_issue_test.go`、`execution_consumption_test.go` | `bindingIssueFixture`：真实路由、授权头、绑定证明、`consume` 辅助 | 复用，不改 |
| `server/internal/governance/execution_task_claim_project_test.go` | `taskClaimHarness.newTask`：同项目内造第二个 task | 复用 |
| `server/cmd/server/execution_run_003_test.go` | TC-RUN-003：准入只信已验签入链的 verdict（直接种行） | 回归，结果须不变 |
| **拟新增** `server/internal/governance/execution_consumption_effect_test.go` | TC-CE-001～004 | 新增 |
| `scripts/aifi45-disposable/selections.json` | 一次性库选择清单 | 新增 1 个选择 `m005-consumption-effect`（新 4 例 + 既有 consumption 用例族） |

## 二、详细测试案例

状态统一为**待实现 / 未运行**。

### consumption-effect（REQ-CE-001～002；4 例）

| 字段 | TC-ID | 对应 Scenario | 优先级 | Arrange | Act | Assert |
|---|---|---|---|---|---|---|
| **ID** | TC-CE-001 | SC-CE-001 | P0 | approve 授权头，T1 的认领行与绑定证明有效，CR 无 consumption；先断言准入为 WAIT_CONSUMPTION | 经真实路由为 T1 提交回执 | 201；`cr_execution_control_command` 有 1 行（state=settled_effect，request_id=T1）；`cr_execution_tool_verdict` 有 1 行且其 payload 的 `command_digest`=sha256(command_bytes)；`cr_execution_control_settlement` 有 1 行（kind=effect，effect_kind=consumption，request_id=T1）；准入为 ADMITTED |
| **ID** | TC-CE-002 | SC-CE-002 | P0 | 预置同 request_id（T1）、内容不同的 command | 经真实路由为 T1 提交回执 | 响应非 201；`cr_execution_consumption` 无 T1 回执行；该 lineage 的 verdict 行数为 0，cursor 不存在或 last_seq 为 0 |
| **ID** | TC-CE-003 | SC-CE-003 | P0 | CR-A 的 T1 已 consume（链 seq=1）；同项目内新建 T2；另起一个 CR-B（第二个 `bindingIssueFixture`）及其 T3 | 分别为 T2、T3 提交回执 | 均 201；T2 的 command.seq=2 且 prev_digest=T1 verdict 的 digest，CR-A 的 cursor.last_seq=2；T3 的链 seq=1、prev 为空，与 CR-A 互不冲突；两个 CR 的准入均为 ADMITTED |
| **ID** | TC-CE-004 | SC-CE-004 | P0 | T1 已 consume 且已有 effect | (a) 同一回执重放；(b) 将 T1 的 dispatched_at 换为新 generation 后重新签发绑定证明并提交 | (a) 200、changed=false；(b) 201、回执行 +1；两次后 command、verdict、settlement 行数均与之前相同；新 generation 后准入仍为 ADMITTED（同一 task 两行回执）|

### authorized-runner 回归映射（不新增测试）

| 字段 | TC-ID | 对应 Scenario | 优先级 | Arrange | Act | Assert |
|---|---|---|---|---|---|---|
| **ID** | TC-RUN-003 | SC-RUN-003 | P0 | 授权 grant 已投递并 ACK；先无 consumption，再分别构造无完整可信链、伪造 verdict 和已验签入链的状态 | 经真实 ACK 路由及 `WakeGrant` 唤醒 | 在可信链提交前不派发、不完成业务 gate；伪造 verdict 被拒；可信链提交后派发一次、重复唤醒不重复派发。既有用例直接种入回执和 `dispatch` 结算，并非通过真实 consumption 路由验证 effect 后的 wake；真实签发与准入由 TC-CE-001 覆盖，但两者未在同一条 wake 流程中串测 |

### 回归（不新增）

| 既有用例 | 为什么要跑 | 通过标准 |
|---|---|---|
| TC-RUN-003（cmd/server） | 保护 G3：准入只信已验签并入链的 verdict | 与改动前相同，0 skip |
| 既有 consumption 用例族（`TestExecutionConsumptionReceipt`、`…RefusesMovedAuthority`、`…IsRaceFree`、`…HoldsTheHeadLockAcrossValidation`） | handler 被改动；既有断言不得变化 | 全绿，0 skip |
| 准入与 CP-RUN-003-A…N | 判定逻辑未改，须保持 | 全绿 |

## 三、测试执行矩阵

| 范围 | 层次 | 入口 | 状态 |
|---|---|---|---|
| TC-CE-001～004 | 真实路由 + 真实库 | `run-selection.mjs`，选择 `m005-consumption-effect` | 待实现 |
| 既有 consumption/准入回归 | 同上 | 同一选择或既有选择 | 待执行 |
| TC-RUN-003 | cmd/server 真实路由 + wake | 既有选择 `run-routes` | 待执行 |
| 构建与静态检查 | `go build ./...`、`go vet`（governance、cmd/server） | 本机 | 待执行 |

## 四、回归风险矩阵

| 区域 | 风险 | 保护 |
|---|---|---|
| consumption handler 热路径 | 多写行拉长事务；同 CR 并发 consumption 在链上串行 | 沿用既有 lineage advisory lock；TC-CE-003 覆盖第二个 task；不加新锁 |
| 新 generation | 同 task 再次提交回执撞 command 主键 | TC-CE-004(b)；守卫在 lineage 锁之后、只跳过同 task 的 consumption effect，其余占用整笔回滚 |
| 跨 CR | verdict 唯一键是 (store_id, epoch, seq)，不含 lineage；常量 store 会让第二个 CR 的首帧冲突 | store_id 按 lineage 派生；TC-CE-003 的 CR-B |
| 准入语义 | 首个 consumption 后即 ADMITTED，被误读为「T 已被核实」 | spec/design/代码注释写明；TC-CE-001 断言 effect_kind=consumption |
| 既有用例对「consumption 后无链行」的隐含假设 | 回归失败 | 既有 consumption 用例族纳入选择；失败即暴露 |
| 签名密钥 | 复用审批服务的 execution 密钥 | 签名域由 `controlPreimage(domain, …)` 区分；不引入新密钥 |

## 五、建议补充顺序

1. **P0** TC-CE-001（证明可达）→ TC-CE-002（证明原子）→ TC-CE-003（链连续）→ TC-CE-004（重放与新 generation）。
2. 回归：既有 consumption 用例族 → TC-RUN-003 → 整组 `selections.json`。
3. 本期不补：并发压力用例、历史行回填用例、密钥轮换用例（均在 non_goals）。

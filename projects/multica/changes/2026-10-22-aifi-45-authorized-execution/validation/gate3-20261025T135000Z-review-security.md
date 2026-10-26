> 产出方式：独立安全轴评审代理（只读，未改代码、未跑库、未跑测试）；turn 上限后由本代理自身落盘。

# Gate 3 安全轴复核 — AIFI-45 授权执行（native STDD）

**Verdict: INCOMPLETE**
（fail-open 主因已在三处端点关闭；但仍存在未验证项与两个可测的语义缺口，不能给 PASS。本轮为只读复核：未改动产品代码、未执行任何数据库命令、未运行任何测试。）

## 1. 不变量逐项裁定

| # | 不变量 | 裁定 | 代码路径（证据） |
|---|---|---|---|
| I1 | 签发不能越过撤销（issuance cannot outlive revocation） | **PARTIAL（写窗口已 CLOSED）** | `internal/governance/execution_head_lock.go:28-40`；`execution_binding_issue.go`（`q := db.New(tx)` 之后、`GetExecutionBindingClaim` 之前调用 `lockExecutionAuthorizationHead`，事务 `pgx.ReadCommitted`）；`execution_consumption.go`、`execution_activation.go` 同位置同一调用 |
| I2 | 消费不能先于签发 | **DELIVERED** | `execution_consumption.go`：`SELECT EXISTS (... FROM cr_execution_binding_issue WHERE workspace_id/cr_id/grant_digest/challenge)` → 未命中即 `409 EXECUTION_BINDING_NOT_ISSUED` |
| I3 | 激活不能先于消费 | **DELIVERED** | `execution_activation.go`：`SELECT id, challenge FROM cr_execution_consumption` → `ErrNoRows` 即 `409 EXECUTION_CONSUMPTION_REQUIRED_FOR_ACTIVATION`；`consumedChallenge != challenge.Challenge` → `409 EXECUTION_ACTIVATION_CONFLICT`；无 DELETE 路由 |
| I4 | 已签 binding 在服务端绑定 task/runtime/generation/CR | **DELIVERED（有一处 replay 键缺口，见 F2）** | `execution_binding_issue.go`：签名前的 claim 复核（`claim.CrID == crID`、`claim.ID == request.TaskID`、`claim.ProjectID == payload.ProjectID`）、coordinator 复核（`local_directory`/workspace/project/`daemonOfBinding(identity)`）、challenge 与 head 一致性（`GrantDigest`/`Revision`/`PolicyDigest`/`TemplateDigest`） |
| I5 | 自报字段不得当作事实 | **PARTIAL（见 F3）** | 服务端推导：task/runtime/CR/workspace/project/daemon/head_digest/revision/policy/template；`challenge.InstallRoot/OperationalRoot/ProcessID/ParentProcessID/ToolsDigest` 仅做格式与非空校验后被原样签入（`decodeExecutionBindingRequest`） |
| I6 | JSON null 被拒绝 | **DELIVERED** | `executionBindingNotNull` 覆盖 challenge/schema 外全部字段；`decodeExecutionBindingObject` 用 `len(object) != len(fields)` 拒绝未知键/缺失键；`ValidateExecutionJSON` 先行 |
| I7 | 写失败不得记录投递 | **DELIVERED（端点层）/ PARTIAL（daemon 层）** | `execution_binding_endpoint.go`：`if _, err := w.Write(...); err != nil { return }` 之后才写 `e.delivered`；`daemon.go:852 d.recordConsumptionAfterDelivery = true`，`execution_consumption_client.go:56-59` 注释声明为「delivery 之后」，未读到调用点全文 |

## 2. Findings（按严重度）

**F1 — HIGH（残余风险，非代码缺陷）：per-run 端点为 bearer 能力，无调用方认证**
- 证据：`execution_binding_endpoint.go:89` `net.Listen("tcp","127.0.0.1:0")`；`:82-87` 16 字节随机 nonce 拼入 URL；`serve` 无任何身份校验；URL 经 `ExecutionBindingEndpointEnv` 注入子进程环境。
- 谁能触达：本机任意进程（loopback 无防火墙语义），只要拿到 URL。
- 同 UID 进程可做什么：读子进程环境（Linux `/proc/<pid>/environ`，受 hidepid 限制；Windows 同用户可经进程环境/调试/日志）后可 POST 一次，取得一张**真实签名**的 envelope，且能抢先烧掉该 run 的唯一名额（`claim` 首次即置位）。
- URL 授予的能力：仅「为这一个 CR/这一 run 的 claim 签一张 binding」，不含消费/激活（端点无法写 receipt）。
- 跨 run 重放：nonce 路径绑定单一端点实例；换 run 需另一 nonce。同一挑战的重放被 `claim`/`bytes.Equal` 允许（服务端幂等重放）——这本身是设计，但也意味着「一次性」只对**不同**挑战成立。
- 记录是否误述：**未误述**。`validation/gate-20261025T113000Z-test-report.md:123`、`validation/stdio-relay-20261025T091500Z-endpoint-independent*.md:72/97` 均明确写「URL 是 bearer 能力、不构成隔离」。**但** `execution_binding_endpoint.go` 头部注释 properties 写「exactly one accepted request」，与 `claim()` 允许同挑战重试矛盾（见 F5）。
- 关闭条件：端点侧调用方认证（每 run 一次性 secret 且不落 env / Unix domain socket + peer credential）；或把该能力降级为「拿到 URL 也只能取回服务端已封存的 envelope」。

**F2 — MEDIUM：replay 分支的回放键不含 task/runtime，可能返回他 run 的 envelope**
- 证据：`execution_binding_issue.go` replay 分支 `GetExecutionBindingIssue{WorkspaceID, CrID, GrantDigest, Challenge}` → `writeExecutionBindingResponse(existing.Envelope, false)`；键中无 `task_id`/`runtime_id`。
- 残余：同一 daemon、同一 head 下，持 task B claim 的调用方若提供 task A 的 challenge，会取回**签名内 task_id/runtime_id 为 A** 的 envelope，HTTP 200 且 `changed=false`，不报错。跨 daemon 被 `daemonOfBinding`/claim 拦截，故非跨租户。
- 关闭条件：replay 查询加 `task_id`/`runtime_id` 条件，或在返回前比对 `existing.TaskID/RuntimeID` 与本次 claim，不一致回 `409`。

**F3 — MEDIUM：安装根/操作根/进程号/工具摘要为自报值，服务端无对照**
- 证据：`decodeExecutionBindingRequest` 只校验绝对路径、非控制字符、非负整数、64-hex；`signExecutionBinding` 原样签入。
- 残余：「binding 绑定 install_root/operational_root」只保证「签过这几个字符串」，不保证它们是平台认可的根。tools_digest 同理。语义上可被理解为「服务端事实」，属于**表述强于实现**。
- 关闭条件：head/contract 中固化允许的根集合或工具摘要白名单，签发前比对；否则在记录中明确降级为「run 自述」。

**F4 — MEDIUM：head 锁只覆盖「经由 `cr` 行」的写入**
- 证据：`execution_head_lock.go:28-40` 为 `SELECT ... FOR SHARE` on `cr`；撤销事务 `execution_authorization_revoke.go:205-211` `FOR UPDATE OF c` + `:301 CompareAndSetExecutionAuthorizationHead`；首签 `pkg/db/queries/approval.sql:19-21 SetInitialExecutionAuthorizationHead`。二者都 `UPDATE cr`，与 FOR SHARE 冲突，故**互斥成立**。
- 残余（须显式声明）：任何不触碰 `cr` 行的 head 变更路径不受保护——直接 SQL/运维脚本、绕过 `UPDATE cr` 的触发器、未来新增的「删除 `approval_record` 头部行」路径。删 `approval_record` 目前会 fail-closed（`GetExecutionAuthorizationHead` 的 JOIN 返回 `ErrNoRows` → `409`），但这是**巧合式安全**，不是锁保证。
- 关闭条件：把「head 只能经 `UPDATE cr` 变更」写成 DB 层约束（trigger/权限），或在 `approval_record` 上加删除保护触发器（activation 已有同类触发器）。

**F5 — LOW：签发上限注释仍描述 REPEATABLE READ，与实际 ReadCommitted 矛盾**
- 证据：`execution_binding_issue.go` 上限注释块写「The transaction took its REPEATABLE READ snapshot before it acquires the advisory lock … real bound is `limit + concurrent issuers`」；同一函数上方事务注释已改为 ReadCommitted。
- 影响：文档/代码不一致；且按现实现（advisory lock 后再 `count(*)`，ReadCommitted 每语句新快照），cap 对**同样取该 advisory lock 的写入者**实际是精确上限，注释反而低估了强度。非漏洞，但属记录失准，会误导后续复核。
- 关闭条件：改注释，并说明「精确性依赖所有插入方都取该 advisory lock」这一前提。

**F6 — LOW：activation 无 race 测试钩子，撤销竞态未被确定性覆盖**
- 证据：`ExecutionBindingValidationTestHook`、`ExecutionConsumptionValidationTestHook` 存在；activation 路径无对应 hook（`execution_activation.go` 全文无 hook 变量）。
- 残余：I1 在 activation 上的窗口只能靠 FOR SHARE 推理，缺确定性反证测试。
- 关闭条件：补 `ExecutionActivationValidationTestHook` 与对应 `execution_revocation_race_test.go` 用例。

**F7 — INFO：relay 未接线（与记录一致，非缺陷）**
- 证据：`execution_binding_relay.go`（271 行）除 `execution_binding_endpoint.go:19` 注释引用与 `internal/daemon/*_test.go` 外，无 `handleTask`/`runTask` 调用点（grep `execution_binding_relay` 仅命中 endpoint 文件与测试）。
- 结论：relay 是死代码路径，当前**不扩大**攻击面；同时也不提供任何缓解。

## 3. 上一轮未闭合项的现状

**CLOSED**
- 「签发用 REPEATABLE READ 快照 + advisory lock + count，无行锁、提交前不复验」→ 现为 `FOR SHARE` 于 `cr` 行 + ReadCommitted，且在 head 读取之前（`execution_head_lock.go`，三端点同序）。撤销的 `FOR UPDATE OF c` 与之互斥，因此**签发提交时所见 head 仍是提交时的 head**。
- 「激活无同事务复验」→ 已复验 head/claim/coordinator/challenge 并要求同 generation 的 receipt 且 challenge 一致（`execution_activation.go`）。
- 「activation 可删」→ 无 DELETE 路由 + 触发器（`execution_activation_test.go:186/190` 断言 DELETE/TRUNCATE 失败）。
- 「消费无签发前置」→ `EXISTS cr_execution_binding_issue` 强制（`execution_consumption.go`）。

**OPEN**
- F1（same-UID bearer 能力 → **进程隔离未验证，保持 OPEN**，记录中已被正确描述为「非隔离边界」）。
- F2（replay 键缺 task/runtime）。
- F3（自报 install/operational root、tools_digest）。
- F4（锁只覆盖 `cr` 行写入路径）。
- F6（activation 撤销竞态无确定性证据）。

## 4. 我未验证的内容（一律不写 PASS）

1. **未运行任何测试**：`execution_revocation_race_test.go` 的 FOR SHARE 阻断断言、`execution_consumption_adversarial_test.go`、`execution_binding_issue_test.go` 上限用例，本轮均只读不执行。所有「DELIVERED」均为**静态可读性裁定**，不是运行时证据。
2. **未执行任何数据库命令**：`FOR SHARE` 与 `FOR UPDATE` 的实际互斥、`cr_execution_binding_issue_once` 唯一键、`ON CONFLICT` 目标列、activation 删除触发器是否真实存在于迁移中——均未在库上核实；本文只引用代码与 SQL 文件文本。
3. **未核实 `recordConsumptionAfterDelivery = true` 的调用点**是否严格位于「delivery 成功之后」：只读到 `daemon.go:852` 赋值与 `execution_consumption_client.go:56-59` 注释，未读完整函数。
4. **未核实 per-run 端点在生产装配中是否真的被 `executionBindingEndpointForRun` 调用并 `Close()`**（「随 run 消失」依赖 `Close`，其调用点未确认）。
5. **未验证进程/UID 隔离**：同 UID 进程能否取得 URL 取决于宿主 OS 与 `hidepid`/`ptrace_scope`，本轮无任何运行时探测 → **保持 OPEN**，不得据本文认定隔离成立。
6. **未验证 trust-root 探测证据**：`validation/trust-root-20261025T084600Z-report.md` 与其 probe JSON 未读，不下结论。
7. **未做跨租户渗透**：workspace 隔离仅按 SQL 参数化阅读判断，无实测。
8. **未覆盖除 `binding`/`consumption`/`activation`/`revoke` 之外的 head 消费者**（如 `execution_authorization_http.go:118` 的读取路径）是否也需要 head 锁。

## 5. 结论

上一轮的 fail-open（撤销并发提交后仍发出签名 binding）在**三条写路径的代码层面已闭合**，证据是 `cr` 行的 `FOR SHARE` 先于 head 读取、撤销侧 `FOR UPDATE OF c` 与之冲突、且事务隔离级别已改为 ReadCommitted。但整体仍为 **INCOMPLETE**：存在 F2/F3 两个可测语义缺口、F4 的锁覆盖面局限需要显式声明，以及第 4 节全部未验证项（尤其是进程隔离与运行时证据）。在这些项被实测或明确降级记录之前，不应给 PASS。

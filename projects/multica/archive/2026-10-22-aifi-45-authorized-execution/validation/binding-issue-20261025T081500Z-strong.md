# AIFI-45 执行绑定签发（server）限定静态评审

## 结论与方法

**本轮静态评审完成；发现 2 项 P1、3 项 P2，不能签本片“真实任务绑定已闭合”。** 20 字段及签名域与所读 T 实现相符，但签名格式相符不等于 claim/CR/任务身份正确。

- 业务仓：`C:/Users/GOBAO/Downloads/AI/multica`；下文未特别标注的路径均相对此仓。
- T 实现：`C:/Users/GOBAO/Downloads/AI/tools/skills/shared/crctl/scripts/lib/execution-binding.mjs`。
- 计划：`binding-issue-20261025T081500Z-plan.md`。唯一跨仓合同源：`C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/tools/changes/2026-10-22-aifi-45-authorized-execution/wire-contract.md`，尤其 §3.4、§3.6。
- 仅阅读指定改动、必要直接 helper 和已存在的证据。**未访问 DB，未运行测试、vet、编译、生成器，未修改源码/测试，未使用子代理。** 报告以独占创建方式发布。
- 主冻结依据：`binding-issue-20261025T081500Z-green3-source-manifest.json`，时间 `2026-10-25T08:01:19.681Z`。指定九个改动文件已逐一核对 raw SHA-256；发布前再次核对。支持 helper/T/合同不冒充该 manifest 的已测覆盖。
- 模型背景沿用交接：schema1 / configured strong `OpenAIPersonal/gpt-6.1-sol/high`；**actual backend unknown**，本轮没有重新核验 backend。

## 一、确证问题

### F1 — P1：只核 project，不核当前 task 与目标 CR 的可信关联，能给其他 CR 的任务签出本 CR 的绑定

**位置**：`server/pkg/db/queries/execution_binding.sql:6–15`；`server/internal/governance/execution_binding_issue.go:137–140,175–195,214–222`。

claim SELECT 仅按 runtime、dispatched_at、active、认证 workspace/daemon 取 `t.*`，完全没有目标 CR 条件或 task→issue/CR 关联。handler 随后只比较 `claim.ProjectID == payload.ProjectID`，检查 ID 有效、coordinator 与 daemon 匹配，并核 head 摘要；既不比较 `claim.CrID`，也不证明任务 issue/context 与 URL 中 CR 的关系。head 自己属于目标 CR 的检查不能补上这一缺口。

**可复现输入关系（静态推演，未执行）**：同 W/P/daemon 下，CR_A 有有效当前授权 H_A；该 daemon 持有属于 CR_B 或其他 issue 的 active task T_B 的当前 R/G。提交 `/crs/CR_A/.../binding`，body 携 R/G 与 H_A 的合法 challenge。所有现有谓词可通过，签出的 payload 同时声称 `cr_id=CR_A` 和 `task_id=T_B`。不要求伪造 MDT 或跨 workspace。

T 的 `requestExecutionBinding` 在 `execution-binding.mjs:104–124` 对 CR 与 grant 精确比较，但对 `task_id/runtime_id` **只核 canonical UUID 形状**，没有独立预期 task 身份，因此这类错误关联不能靠 T 的现有校验纠正。计划要求 claim/head 同 workspace/CR/project；当前 wire §3.6 只写 project equality，文档也不足以消除任务归属缺口。

**影响边界**：可签出没有验证过的 CR↔真实任务关系；不是已证明可以启动 Agent、消费或越过隔离域。消费仍关闭，不降低本项对签发事实完整性的优先级。

**建议**：在同一事务中使用明确的可信 CR/task 关联规则核验（依已支持来源核 task.cr_id、issue/CR shell 或可信 pipeline 映射，不靠同名/同项目猜测）。无关联、关联冲突或来源不支持均拒绝。补同 project 不同 CR/issue 的真实 MDT 负例；同步唯一 wire 源。不要简单要求非空 task.cr_id 而破坏合法 issue-backed 来源，也不要把 head 的 CR 校验当 task 的 CR 校验。

### F2 — P1：用 (runtime, dispatched_at) 反推 task 不唯一；QueryRow 会静默选中任一匹配任务

**位置**：`execution_binding.sql:1–15`；生成文件 `server/pkg/db/generated/execution_binding.sql.go:66–99`；请求结构 `execution_binding_issue.go:44–50,291`；签名取 task `:222`。必要直接依据：`server/pkg/db/queries/agent.sql:1053–1099`，`ReclaimStaleDispatchedTasksForRuntimes`。

body 根本不带 task_id；查询也没有 t.id 条件、唯一性验证或多匹配拒绝。sqlc 的 `:one` 生成 `QueryRow(...).Scan(...)`，**不代表数据库有唯一约束，更不检查是否返回多行**。

这不是只靠假想时钟碰撞：现有批量 reclaim 在一条 UPDATE 中对最多 max_tasks 条任务执行 `SET dispatched_at = now()`，按 runtime 集合筛选，没有“每 runtime 只选一条”的分组限制。一个 runtime 上可同时匹配的多条任务被该语句重领后可合法拥有同一 R/G。即使不诉诸该生产路径，新查询自身也未建立唯一性不变量。

**结果**：同一 R/G 的请求可能被归到另一 task；可能错误签署 task_id，也可能因取到另一 project 的任务而误拒绝。增加 ORDER BY/LIMIT 1 只能稳定挑错，不能证明真实 child 属于哪一个任务。即便补 F1 的 CR 过滤，也仍须处理同 CR 多 task 或拒绝歧义。

**建议**：由 daemon 的本次 run 传入明确 task_id，服务端按完整 T/R/G/认证 scope 查询并核 CR 关联；或者在协议更改前至少对多候选 fail closed。增加同 runtime 同代次多 task 的负例；不能把 timestamp 当 task 的全局唯一身份。更改外层三键 body 需先更新 wire；签名 payload 已有 task_id，无需为此扩成第 21 键。

### F3 — P2：PID 的 JSON null 被接受，并被改写成数字 0 签入，不是严格回答原 challenge

**位置**：`execution_binding_issue.go:52–64,217–218,335–341`。

两个字段向零值 int64 执行 `json.Unmarshal`，只检查 error 和 `<0`。Go `encoding/json` 对非指针标量解码 `null` 不报错且不赋值。因此提交 `process_id:null` 或 `parent_process_id:null`，其余条件合法、challenge 新鲜时，decoder 可成功，随后把 **0** 签进 payload。exact key set/ValidateExecutionJSON 不会拒绝语法合法的 null。

这违反计划的“非负整数”类型及“回答 exact daemon challenge”的声明。真实 T 正常发出自己的数字 PID，且对回包严格比较；本项**不证明能骗过真实 T 的进程比较**，更不意味着服务端本来能验证 PID 真实性。它仍是可独立确认的 server strict-body 缺陷。

**建议**：在 raw token 层拒 null/非整数并做明确范围校验，再赋值；补两个 PID 各自 null 的 400/no-row 用例。若采用跨语言安全整数限制，也应与唯一合同源明确一致。

### F4 — P2：runtime_id 未强制 canonical，计划/§3.6 声称的严格请求实际可接受别名

**位置**：`execution_binding_issue.go:295–310`；`server/internal/util/pgx.go:19–27`；`server/go.mod:18` 指定 pgx v5.11.0。

这里只调用 `util.ParseUUID(runtimeID)`，不匹配 canonical 小写连字符 regex，也不比较原文与规范化回写值。该 helper 调 pgtype.UUID.Scan；所读已安装 v5.11.0 `pgtype/uuid.go` 的 parseUUID/Scan 接受 32 位去连字符格式并用 hex.DecodeString 解码（大小写 hex 均可），输出再编码为 canonical。故真实 runtime 的去连字符/大写表示可以命中同一 DB UUID 并获签，不会按计划的 canonical 要求返回 400。

输出 payload 的 runtime_id 经 UUIDToString 转为 canonical，T 格式校验仍可通过；**没有证明这会绕过 workspace、daemon 或 generation 校验**。本项限于严格 wire/alias 拒绝不一致，不能描述为认证突破。

**建议**：解析前核小写 canonical 或解析后比对 UUIDToString 与原字符串，补大写、32hex 等别名的 400 用例。不要只依赖 UUID 可解析。

### F5 — P2（条件性可用性缺陷）：唯一冲突重读前未结束失败事务，可能耗尽自身连接池并等待到取消

**位置**：`execution_binding_issue.go:129–135,238–253`，尤其 `:243`；唯一识别 helper `:433–435`。

INSERT 唯一冲突后，旧事务已失败但连接仍被占用；唯一的 rollback 是 handler 返回时的 defer。代码却先用 **a.pool.QueryRow** 申请另一连接做“fresh”重读。

**明确触发条件**：一个实例的 pool MaxConns=1，已开始的事务读到该 challenge 不存在；另一个实例/连接随后插入并提交 winner；本实例 INSERT 冲突，然后持有自己唯一连接等待自己的 pool 重读。defer 必须等该等待结束才释放旧连接，故无法正常即时幂等返回，直到 context/连接等待结束。更大池在相同跨实例冲突及饱和条件下也有资源等待风险。不是断言同一个单连接 pool 自己能同时运行两个事务，也不是已运行的竞态证明。

**建议**：进入冲突分支后先显式 rollback/release，再在新事务/连接重读；仍保持 W/CR/grant/challenge 全量限定。使用 pgconn.PgError 的 SQLSTATE 23505 + 确切 constraint name，而不是仅匹配 err.Error 子串。补跨 pool 唯一冲突及小连接池/取消负例。当前串行 replay 绿例不覆盖此分支。

## 二、fail-closed 与事务范围核对

| 输入/状态 | 当前静态结果与边界 |
|---|---|
| service nil、合同未配置/无效、pool/queries 不可用、签名 key 长度/key_id 无效 | `execution_binding_issue.go:101–106` 返回 503；`approval.go:151–156` 的 ExecutionContract 对 nil receiver 安全，短路避免随后解引用。新 POST 始终挂载于 `execution_authorization_routes.go:42–54`。 |
| PAT/JWT fallback、无认证 daemon、控制字符 daemon、workspace 非 canonical UUID | `:107–113` 要求真实 DaemonAuthPathDaemonToken 及认证 context，403；不信 body 中自报 daemon/workspace（body 也无这些键）。 |
| R/G 在快照中不存在、已终态、错 workspace/runtime workspace/daemon | SQL `execution_binding.sql:6–15` 不命中，`:141–143` 为 409；但不等于完整 T/R/G 或 CR 归属，见 F1/F2。 |
| head 缺失、撤销/损坏、签名或冻结来源/部署合同不符 | `:150–168` 拒绝，不进入 sign。直接 helper `execution_authorization_head.go:95–200` 验 Ed25519、key IDs、W/P/CR、initial revision/lineage、policy/template、source 原 bytes/digest/逐字段映射及 descriptor；没有退回历史 initial。 |
| coordinator 非 local_directory、W/P 不符、identity 内 daemon 与认证 daemon 不同 | `:183–191` 返回 409；resource_id 取经验证的冻结 descriptor，不取 challenge 自报。 |
| grant_digest/revision/policy/template 错误 | `:193–197` 返回 409；head_digest 取已验 head，不使用其他摘要替代。 |
| timestamp 精度/别名 | `:303–308` 要求 UTC canonical 回写相等及微秒精度，拒 comma/+。即使 time.Parse 会截掉超长小数，回写不等仍会拒绝；本轮未确认旧精度 P2 在此复现。runtime canonical 则有 F4。 |
| malformed JSON/多文档/duplicate/未知键/大小写别名/半参 | `:285–293,313–318,366–381` 调既有 ValidateExecutionJSON 并 exact 三键/十二键；这不是所有类型都严格的证明，见 PID null。 |

**快照**：`:129` 开启一个读写 REPEATABLE READ，claim、head、首次 ledger lookup、insert 都走 `db.New(tx)`；head 的 SQL（`generated/approval.sql.go:561–572`）在同一 statement 连接 CR head pointer、审批行、live issue/project，非按时间挑历史记录。正常新建 commit 后才响应 envelope。

**不是持续 freshness/线性化证明**：普通 SELECT 没有锁住 claim/head 到提交；另一事务在初次快照之后完成 reclaim/撤销，不会自动使本事务所有旧读失效。当前结论是“一致旧快照中的事实”，不是“响应/提交瞬间仍为当前”或“撤销与签发存在已证明的全局顺序”。并发唯一冲突的 pool 重读更是另一个 statement 快照；没有在重读点重新验 head/claim。没有动态执行这些交错，也不据此单独断言业务要求已被违反；后续消费必须有自己的 current-head/claim 约束。

## 三、与 T 的 20 字段逐项核对

服务端声明顺序 `execution_binding_issue.go:70–90`，赋值 `:214–222`；T `execution-binding.mjs:104–124` 构建 expected 和 identities。**集合、拼写及正常输入的值一致。T 校验集合和逐值，不要求 JSON 对象键序**；服务端 json.Marshal(struct) 使用下列声明顺序。runtime/task 是 T 在 expected 末尾补的两个身份键，并非缺失字段。

| 顺序 | 字段 | server 的来源/类型 | T 对照 |
|---:|---|---|---|
| 1 | schema | string 固定 execution-binding/v1 | 同固定值 |
| 2 | key_id | string 服务 a.keyID | 等于 envelope.key_id；envelope 由安装公钥验签 |
| 3 | workspace_id | string，MDT 认证 context | 等于 grant.payload.workspace_id |
| 4 | project_id | string，验证后 head payload | 等于 grant.payload.project_id；task 只核 project 仍不足，F1 |
| 5 | cr_id | string，URL CR 经 head 校验 | 等于 grant.payload.cr_id |
| 6 | resource_id | string，冻结 coordinator.ResourceID | 等于 grant coordinator resource_id |
| 7 | daemon_id | string，认证 context，并与冻结 identity 比较 | localCoordinator.daemon_id 精确相等，且非空无 C0/C1 |
| 8 | challenge | string，12-key challenge 的 64lowerhex | 等于本次 32 random bytes hex |
| 9 | install_root | string，daemon 转述，绝对且无控制字符 | 等于 T 的 realpath install root |
| 10 | operational_root | string，daemon 转述，绝对且无控制字符 | 等于 T 的 realpath workspace |
| 11 | process_id | int64→JSON number，daemon 转述 | 严格等于 process.pid；null 输入漏洞见 F3 |
| 12 | parent_process_id | int64→JSON number，daemon 转述 | 严格等于 process.ppid；null 输入漏洞见 F3 |
| 13 | operation | string，canonical operation regex | 等于本次 operation |
| 14 | head_digest | string，head.GrantDigest；已与 challenge.grant_digest 比较 | 等于 grant.grantDigest；不是 source_digest 或 binding_digest |
| 15 | authorization_revision | int64→JSON number，已验证 head 的 revision | 等于 challenge revision；当前 head validator 仅 initial=1 |
| 16 | policy_digest | string，已配置合同；head/challenge 都核对 | 等于 challenge/grant policy_digest |
| 17 | template_digest | string，已配置合同；head/challenge 都核对 | 等于 challenge/grant template_digest |
| 18 | tools_digest | string，daemon challenge 的 64lowerhex | 等于 T toolsRuntimeDigest；服务端不独立测量它 |
| 19 | runtime_id | string，request UUID canonical 回写 | T 只核小写 canonical UUID，没有预期 runtime 比较；F2/F4 |
| 20 | task_id | string，所选 claim.ID | T 只核小写 canonical UUID，没有预期 task 比较；F1/F2 |

`signExecutionBinding(:262–276)` 用 `json.Marshal(payload)` 的**原 bytes**，签名输入为 `execution-binding/v1\0 || raw_payload_bytes`（`:93–95`），Ed25519，标准 base64；与 T 直接 helper `execution-authorization.mjs:286–309` 的域分离/验签/原 payload 解析一致。key_id 在 payload/envelope 均为服务 key，head validator 还核同一配置 key。没有新增 issued_at、dispatched_at 或签发 row ID 到 payload，恰好 20 键。

正常 T 的 PID 是本机数字，revision 目前只支持 1；并未签 server int64 全范围都可无损映射为 JS Number。绝对路径的形状检查也不等于 realpath/设备 inode 身份检查：T 在本机做后者，server 只能转述。

## 四、重放、并发、隔离与台账

1. **唯一性/返回值**：迁移 `643...up.sql:5–19` 的唯一键为 W/CR/grant_digest/challenge；两个查询和冲突重读均有完整四项限定（SQL `:19–23`、handler `:243–246`）。没有看到这两条重读跨 W/CR 取 envelope 的分支。不因此签其他 middleware 或全局数据隔离。
2. **同 challenge 是否不同 envelope**：正常串行先查后返已有记录，changed=false；并发各自可能先本地 sign，但唯一键只让一个 row commit，失败者只返回查到的 winner 或错误，不返回其未提交 envelope。若 payload 完全相同，固定 struct bytes + Ed25519 也是确定性的。若同 nonce 伴不同 roots/PID/operation/tuple，则可能先算出不同签名；正常 DB 返回仍选唯一 winner，而不是保证所有内部 sign 调用都只发生一次。F5 说明并发路径的成功/及时重读尚有缺陷。
3. **幂等不是请求全量相等检查**：`:202–208` 命中只比较四项唯一键，不核 stored runtime/task/daemon 或 challenge 其余字段与本请求一致；因此重用 nonce 改其他字段会拿到旧 envelope，仍 changed=false。真实 T 会对 challenge/roots/PID/operation 等拒绝不匹配，并且 nonce 是 256-bit random；这可在“唯一 nonce 表示同一逻辑请求”的前提下接受，但不能称对恶意 nonce 复用也逐字段验证。建议冲突 payload/tuple 返回明确 409，或文档写明返回 winner 语义；不要以此证明响应始终对应本次 body。
4. **JSONB**：envelope 外层可被 JSONB 重排；base64 内原 payload 与签名 bytes 不被重序列化。首次返回的是 INSERT RETURNING 的 JSONB，后续也是存储值；串行测试比较外层 envelope 字符串可成立，但不应将外层 JSON 排列当密码学身份。
5. **append-only 的窄覆盖**：up migration `:27–35` 无条件 BEFORE UPDATE OR DELETE、FOR EACH ROW，对命中行的普通 UPDATE（包括值未变）/DELETE 都抛异常；相应无行语句无触发行但也不改变数据。指定 query 只有 SELECT/INSERT，generated model (`models.go:694–706`) 与表列一致。测试只证明这两种 DML 被拒，不是任何角色都不可删。
6. **可接受风险 / 必须保留的权限边界**：没有 BEFORE TRUNCATE trigger/REVOKE TRUNCATE，也没有阻止 table owner ALTER TABLE DISABLE/DROP TRIGGER、DROP TABLE 等 DDL。runner `:124–138` 创建 NOSUPERUSER 临时 role 并以它导入/迁移，故测试应用凭据还是表 owner，非 superuser 不等于不能绕过这类自有对象触发器。对“普通 DML append-only”可接受；对“应用凭据失陷仍不可删/activation”**不构成证明**。生产应用/迁移 role 是否分离、实际 ACL/DDL/TRUNCATE 能力未访问 DB 核验，保持未验证。
7. **无 FK**：保留历史签发不随 task/CR/workspace 删除级联，符合计划窄形态；代价是可以留下孤儿记录，数据库不独立保证 W/CR/task/runtime/daemon 引用一致，直接 INSERT 也未在表层验证 envelope 签名。challenge/digest CHECK 仅长度，不是 hex；API 层更强，但不能由此证明所有写入者都合规。这里是审计事实表，不是消费/预算/外键隔离账本；F1/F2 更不能被“应用已核关系”的注释覆盖。
8. **down migration**：`643...down.sql:4–6` 只明确 DROP 本 trigger/function/table，无 CASCADE、无改其他表；会主动销毁该签发审计表，已交付的签名仍不可撤回。需管理流程控制，不得把 down 当 revoke 或不可删激活。不是本轮执行过的回滚验证。

## 五、runner -migration= 的边界

- `scripts/aifi45-db/run.mjs:49–69` 仅接收 `server/migrations/NNN_[a-z0-9_]+.(up|down).sql`，拒绝绝对路径、`..`、反斜杠、任意目录与其他 flags 形式。`goFlags` 明确过滤 `-migration=`，`:150–151` 的 go test argv 不带它。**词法目录穿越及传给 go test 的问题未见。**
- `:124–138` 建 nonce 临时库/受限角色、观察名称/OID/marker，migration 读仓内文件后只以 target.database/target.role 传入 psql；原库在正常所读 643 migration 下没有成为迁移目标。`:137–141` 记录应用文件的 sha256。`:174–205` 比较原库记录并仅清理通过身份校验的临时对象。
- **可接受的本地受信文件假设，而非强沙箱**：`readFileSync(resolve(repositoryRoot,path))` 没有 realpath/打开句柄后的目录归属检查，合法名字的 symlink/junction 可使读取越出真实 migrations 目录；path regex 只约束字符串。被读内容整体送给 psql，角色/起始数据库限制不能替代对受信迁移内容（含 psql meta-command/外部动作）的审查。仓内 643 文件本身只有新表/触发器及对应 down，没有主动切原库的内容。
- 因此仅能认可**受信仓库、无恶意链接、使用所审 migration 内容**下的目标选择；不能保证任意本地恶意 SQL 或元命令都无法影响保留库/宿主。若需要“真实文件绝不越界”，应做 realpath/链接约束及相应静态/隔离回归。本轮未操作 runner、未访问保留库，也未证明恶意文件能力。

## 六、提供证据与未验证项

只读复核 `green3.meta.json` 和 `green3.stdout.jsonl`：事件为 **11 RUN / 11 PASS / 0 FAIL / 0 SKIP，10 leaf**，argv 为 governance 的 `^TestExecutionBindingIssue$`；包含 happy path、串行幂等、不同 challenge、stale claim、revoked head、错 policy/grant digest、非 MDT、畸形请求、普通 UPDATE/DELETE。该记录标注 migration 已应用、exit=0、原库 unchanged/released、临时对象 cleaned；`green3.original-before.json` 与 after 文件也逐字节相等。**这只证明提供的证据文件内容一致，不是本评审者运行 DB/测试或独立确认原库真实状态。**

所读测试 (`execution_binding_issue_test.go:321–514`) 未提供上述 F1/F2、PID null、runtime UUID aliases、实际并发 unique winner/池饱和、并发撤销/reclaim、TRUNCATE/禁用 trigger 的独立执行证明。fixture 通过 CR.shell_issue_id 关联自身 task issue (`:58–88`)，happy path 不会暴露同项目错误 CR；malformed mutations 不含 PID null/UUID 值别名。

`binding-issue-20261025T081500Z-sqlc-result.json` 记载 v1.31.1、exit=0，changed 为 models.go/execution_binding.sql.go；已见 generated header/参数/扫描与所审 SQL 对应。没有亲自运行 sqlc、复现 archive 或验证工具供应链，不能把元数据当独立生成证明。

### 明确未验证 / 不签署

- 未动态验证 F1–F5 推演；静态缺陷结论与运行证明分开。并发 race/rollback/当前性顺序没有独立测试。
- 服务端**不能验证** PID/PPID 属于哪个 OS 进程、该进程是否是 daemon 私有子进程、是否存在、实际 roots/部署 bytes 是否相符；tools_digest/两 root/PID 都来自 daemon 转述。签名是服务对认证 daemon 所报事实的响应，不是远程进程证明。
- daemon 私有 stdio relay、本机凭据隔离、T 消费事务、receipt、不可删 activation、同 UID 隔离控制域及旧合同防降级，不在本片完成范围。
- 不复评/签完整 terminal 链、Complete/server closure 或既往 Fail replay-scope finding；他人 final5 证据不自动变成本 reviewer 的 closure。legacy/no-claim 请求仍可被服务端接受，普通 PAT daemon 仍是 legacy；有效代次 retry-overlay 外部资源泄漏及 DB rollback 不撤销外部活动的边界保留。
- **无生产准入、无消费开放、无 activation/隔离域签字、无全局 C1 或 Gate3 结论。旧 claim 锁序 INCOMPLETE；业务 TC 0/49；5 major 未关闭；消费 closed/off。**

## 附：主审文件身份（raw SHA-256）

| 文件 | bytes | SHA-256 |
|---|---:|---|
| server/internal/governance/execution_binding_issue.go | 17915 | 93e75d32c59417066e6bad9822415d729031bae78957e7e73665efc51ea964e8 |
| server/internal/governance/execution_authorization_routes.go | 4029 | 4be183d44cd419660d273a4f7dec6aa503f0c911e1527d7b3288d53253bce5e3 |
| server/migrations/643_cr_execution_binding_issue.up.sql | 1632 | 495ec3c0ee54d1a29b3ad376a2f7d0cbd5844960c9035685a7821fb612cfcbbe |
| server/migrations/643_cr_execution_binding_issue.down.sql | 417 | 91b9c2773b8f8499b1b011c26889f19b5234bfbeda615591142e33cc984a1187 |
| server/pkg/db/queries/execution_binding.sql | 1493 | 8a108cdab49a1556f6053e9fe54bfb08cde36de67d1e8f68c108b34c28c53369 |
| server/pkg/db/generated/execution_binding.sql.go | 6657 | eb657095a528d9eb708257697686fc4b769cd7816c04deb892245ccd291d4551 |
| server/pkg/db/generated/models.go | 98581 | 766ef44b820d94d6248a243e386fe22f2d87ff558dd5e0cab5046754b5a193b2 |
| scripts/aifi45-db/run.mjs | 15409 | 5a156a3b0535597ee01b087b3947b81b5a36346eb44e952fbd2681599cd62ee9 |
| server/internal/governance/execution_binding_issue_test.go | 19022 | 89737cf46a971cbebec7d343ca6774c5f0fa188b35c2a873cbc9633ae0040238 |

### 支持文件发布时取样（不是 green3 已测冻结的扩展）

发布前核对时间：`2026-10-25T08:12:00.442342+00:00`。下列哈希仅标识发布时读取的辅助文件；不构成动态覆盖或跨文件持续冻结证明。

- `C:/Users/GOBAO/Downloads/AI/multica/server/internal/governance/execution_authorization_head.go` — 10791 bytes；SHA-256 `710a709793df4cb1079f95db517f3eeb5d0f724f6764a3df551a3ec9e3260512`。
- `C:/Users/GOBAO/Downloads/AI/multica/server/pkg/db/generated/approval.sql.go` — 30451 bytes；SHA-256 `f122f2194fe6a511d9c47d6c26ca1c0e3381c1b0bd1ba6ded3df636bbaef7894`。
- `C:/Users/GOBAO/Downloads/AI/multica/server/internal/governance/approval.go` — 31923 bytes；SHA-256 `9a17a271a26c8f32c5e42de9b1e6c50510ac592a6ac8b518f56c318d397d3743`。
- `C:/Users/GOBAO/Downloads/AI/multica/server/internal/util/pgx.go` — 5003 bytes；SHA-256 `ace6740a6e609fd1fb072308d3b8e0ac78c4e6489242c57aed256ba0f1ebce12`。
- `C:/Users/GOBAO/Downloads/AI/multica/server/pkg/db/queries/agent.sql` — 148164 bytes；SHA-256 `6a372e24c77de1233ad3dd2b32b6f151d2bf72658a65d0e32786887b27fd9429`。
- `C:/Users/GOBAO/Downloads/AI/tools/skills/shared/crctl/scripts/lib/execution-binding.mjs` — 7262 bytes；SHA-256 `8fe71e0f5fc48a524763a63641a43052fff78fc25868017669516297b03ba95d`。
- `C:/Users/GOBAO/Downloads/AI/tools/skills/shared/crctl/scripts/lib/execution-authorization.mjs` — 22367 bytes；SHA-256 `71437e20ddfdf33b74d3490c7129359562443555d1abc0a44886b27f32c34abc`。
- `C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/tools/changes/2026-10-22-aifi-45-authorized-execution/wire-contract.md` — 34779 bytes；SHA-256 `1d4ee135434c168f77621a890676a1a11e9e9fa46a9696e3d84f3131a4273e72`。

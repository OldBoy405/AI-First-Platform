# AIFI-45 控制准入信任锚链 - 技术设计

> STDD Phase 2 / SPEC 草稿；Gate 2 尚未确认。本文规定目标行为，不声明实现、部署或 ADJ 已完成。
> `T` = `C:/Users/GOBAO/Downloads/AI/tools`，`M` = `C:/Users/GOBAO/Downloads/AI/multica`。
> 锚定等级为 L4；安全关键与跨系统变更的最低要求为 L3，当前等级满足要求。锚点是下列既有实现，不另造信任体系。

## Context

### 已核实的现状与缺口

- `T/skills/shared/crctl/scripts/lib/workspace-transactions.mjs:60-76` 的 `deriveInstallRoot` 只定位 Git 安装根；`:58` 的作者注释也明确它不证明根的物理身份。
- `T/skills/shared/crctl/scripts/crctl.mjs:5767-5797` 的 `bindTaskWorkspace` 从三条环境变量取根，没有来源认证；现有判据只有 `:5742-5749` 的目录存在与 `:5807-5822` 的路径居留。因此环境变量、sidecar 和路径只能定位，不能成为 workspace/project/cr 归属证明。
- `T/skills/shared/crctl/scripts/lib/execution-binding.mjs:130-152` 已把安装根 realpath 与签名 grant 的 `coordinator_binding.identity_b64.local_path` 做 dev/ino 比对，`:181-203` 已验证 daemon 取得的 `execution-binding/v1` 签名；但它只保护 `requestExecutionBinding` 的调用者。
- `T/skills/shared/crctl/scripts/lib/execution-authorization.mjs:95-117` 的 `installDirectory(workspace, trustRoot)` 已要求 trustRoot 绝对、可访问、为目录，且不得位于或包含工作区安装根（`:108-114`）；`:96-97` 明确它是“a seam, not isolation proof”。
- 同文件 `:558-578` 的 `readExecutionSource` 已复核 `structured-human-request/v1`、`digest === grant.payload.source_digest`、`bindings` 深等以及 `raw_b64` 原 bytes 的 SHA-256；`:249-259` 与 `:277-283` 已分别覆盖 scope source bindings 与 revoke profile。
- `.crctl/` 首次使用写入 `.gitignore="*"`（`crctl.mjs:504-505`），所以其中内容既不进 Git，也没有内容签名，不能升级为独立事实源。
- M 已有可复用落点：`server/internal/governance/execution_authorization.go` 的 `BuildExecutionAuthorization`、`server/internal/governance/execution_binding_issue.go` 的 `HandleDaemonExecutionBinding`、`server/internal/daemon/execution_trust.go` 的 `OpenExecutionTrustStore` / `InstallAuthorizationRecord`，以及 `server/internal/daemon/execution_verifier.go` 的真实 crctl 安装后检查。

### 约束

- 仅修改 `execution-authorization`、`repair-governance`、`evidence-delivery-contract` 三个既有 capability；不新增 capability。
- 不建第二本账，不引入原生依赖、CA/PKI、新密钥管理体系或普通读路径改造。继续使用平台认证、DB 归属、Ed25519 签名、daemon 投递和 T 的业务裁决。
- 签名 payload 与 `structured-human-request/v1` 原 bytes 不做 CRLF 归一化或重序列化。普通仓库文本的 CRLF→LF 规则不得应用到这两类字节。
- 新信任语义只适用于显式选择 `authorized-execution/v1` 的控制写；legacy 不因安装新版工具而自动获得新信任语义，也不被新字段追溯阻断。
- 任一独立事实缺失、不可信、过期、跨 scope 或不可复核时失败关闭；测试辅助校验、路径 pin、同 UID 权限位均不等于隔离证明。

## Decisions

### 1. 用一个共用控制准入编排器闭合三类事实，不把三个检查拼成三份规则

**方案**：在 T 新增内部 `lib/control-admission.mjs`，导出唯一的 `requireControlAdmission` 编排入口。它复用而不是复制三处锚点：

1. 通过现有 grant 读取与 `installDirectory(workspace, trustRoot)` 定位 daemon 安装的信任目录，以 envelope/payload 的 `key_id` 精确选择公钥并验签；缺失或不匹配的 key 直接拒绝。
2. 调 `readExecutionSource`，从来源原 bytes 独立重提取 `structured-human-request/v1`，核对 `source_event_id`、SHA-256 digest、逐字段 `json-pointer` bindings 与已签 payload。
3. 调 `requestExecutionBinding(workspace, grant, operation)`，验证本次随机 challenge、认证 daemon 当前 claim/head、`execution-binding/v1` 签名、当前 workspace/project/cr/scope、operation、policy/template/tools digest，以及实际安装根 dev/ino。
4. 返回只供本次写事务使用的 admission 对象；该对象不是新账本、长期凭据或新的预算来源。提交前在既有 CR/操作锁内按原事务规则复核 head、文件 bytes 与 write-set CAS。

共用入口只接受由 daemon 启动控制子进程时注入的 trustRoot 与受保护绑定通道。`bindTaskWorkspace` 的 env、`MULTICA_EXECUTION_BINDING_ENDPOINT`、sidecar 与 CLI 路径继续只作定位；它们不能选择另一套信任规则，也不能在证明不可用时降级到本地验签通过。

**为什么**：三条 ADJ 的共同根因是验证者缺少独立事实源；只有根归属、来源和公钥同时成立，控制写才具有可验证的准入链。一个编排入口也避免五个调用方各自漏掉 source 或 root 检查。

**备选方案及排除原因**：
- 只扩展现有 env/sidecar 字段：仍由被管进程提供事实，不能关闭 ADJ-001/003。
- 只做 `installDirectory` 路径隔离或 dev/ino pin：只能证明路径/目录身份的一部分，不能证明谁有权声明归属，也不能证明 agent 无写权限。
- 各入口分别组合 helper：容易再次出现只验签、不验源或只覆盖部分调用者的断层。
- 新建归属总账或另一套预算：违反“不建第二本账”，且会与平台 DB 和 T 既有历史漂移。

### 2. 平台在签发前独立验源，daemon 在受保护身份下安装并递送信任材料

**方案**：M 在现有认证人类请求与 DB 归属链上完成签发，不接受 Agent 候选摘录作为来源事实：

- `BuildExecutionAuthorization` 及其真实 HTTP 调用方在签名前解析完整 `structured-human-request/v1` 原 bytes，生成平台 `source_event_id`，计算 `source_digest=SHA256(raw_request_bytes)`，由平台构造每个语义字段的 `json-pointer` binding；同时从认证 scope/DB 解析并冻结 workspace/project/cr 与 coordinator/repository bindings。映射不符、重复 JSON 键、机器凭据冒充人类或资源跨 project 时不签发。
- `HandleDaemonExecutionBinding` 继续只向真实 DaemonAuth 且与 DB 当前 claim/head/project 匹配的 daemon 签发本次 challenge。operation 必须属于本设计五个写入口的固定词汇，不能让调用方自报任意 operation 获得通用证明。
- daemon 的 relay/launcher 只中继其亲自启动的控制子进程 challenge，并传入实际安装根、操作根和当前 task/runtime 代次；Agent 自报的 expected root、project 或任意 nonce 不作为签发事实。
- `OpenExecutionTrustStore` / `InstallAuthorizationRecord` 在 daemon 服务身份下安装 key/grant/source；同名同 bytes 幂等，异 bytes 冲突。T 只从该 trust root 读取与 `key_id` 匹配的公钥。
- 部署前置条件按 OS 落地：Linux 的 daemon 与 agent 使用不同 UID；Windows 的 daemon service 与 agent 使用不同服务/用户身份。agent 必须能读公钥但不能写，实际覆盖尝试必须由内核返回 `EACCES`/`EPERM` 或 Windows Access Denied。每个拟启用平台均须留存身份、命令、内核错误和覆盖前后 digest 证据。

**为什么**：签名只证明“某把钥匙签过这些 bytes”；平台独立验源和 OS 身份边界分别回答“来源是否可信”和“钥匙是否可信”。

**备选方案及排除原因**：
- 让请求自携 `source_bindings` 后仅验签：会把作者解释冒充平台提取，不能关闭 ADJ-002。
- 同 UID 下设置 `0700/0600`、硬链接或只读 bind 的路径检查：同 UID 可替换文件，不能作为 ADJ-003 关闭证据。
- 引入 CA、证书链或新 KMS：超出范围，且不会自动解决本机 agent 写权限问题。

### 3. 五个控制写入口接线；普通读与已提交恢复不接新准入

**方案**：下表是完整接线边界。所有“首次产生新业务写入”的路径在任何 write-set、receipt、任务、stop 状态或注册/归档事实变化之前调用同一准入缝；事务提交前按既有锁/CAS 再复核。拒绝只允许 stdout/stderr 诊断，不得改变 CR/Git/index/worktree、registry、repair ledger、授权消费、平台任务或 trust root。

| 控制写入口 | 接线函数与事务位置 | operation 与特别约束 |
|---|---|---|
| `authorization-bind` 非只读 | `crctl.mjs:cmdAuthorizationBind`；移除“子集核验后仍只返回待消费”的旁路，真实准入成功与既有消费事务连接 | `authorization-bind`；`--check` 不属于本行，不产生准入 |
| `advance` | `preflightAdvanceAuthorization` / `consumeAdvanceAuthorization`；门禁前后保持 head 一致，在现有消费与状态事务内复核 | `advance`；只有业务 gate 也通过才消费/推进 |
| `repair-admit` 与 `repair-resume` | `cmdRepairAdmit` / `cmdRepairResume`；先通过同一缝，再调用既有 repair admission/resume | 分别为 `repair-admit` / `repair-resume`；不重置额度、streak、stop 或 origin，不新增恢复预算 |
| `register` | `cmdRegister` 与 `lib/workspace-transactions.mjs:registerCr` 的候选 CR 解析后、首个 write-set 前 | `register`；平台当前 claim 的 CR、registration key 与本地候选 CR 必须相同，不能先注册再补证明 |
| `archive` | `cmdArchive` 与 `lib/workspace-transactions.mjs:archiveCr` 的首个新业务 write-set 前 | `archive`；归档目标 project/CR 与当前证明一致，已提交 journal 的恢复不另造一次准入 |

`register` 的时序是显式设计约束：daemon 必须已经持有平台分配的 CR/claim 与对应注册授权；T 在本地候选 CR 确定后、任何持久化之前核对二者。若现有流程无法提供该平台事实，则 register 失败关闭，不以“本地还没有 CR”为由跳过。

**明确不接线的入口**：

- `authorization-bind --check`、`--check --check-source` 仍是只读检查，返回 `bound=false`，不获得新准入语义；`status`、`next`、`gate`、`history`、`workspace inspect` 等普通读路径不新增 trust root、daemon 或授权要求。
- 已提交 register/archive/advance/repair 的幂等重放、内部 rollback、merge/cleanup 与崩溃恢复不重新发起一次业务准入；已提交 repair 重放沿原 journal 返回原 repair_id/receipt 且不重新消费，崩溃恢复按已提交事实恢复、未提交写入回滚，不能成为未准入首次写入的备用入口。
- 未列出的 legacy 写命令和非控制类调用保持原合同。本 change 不扩大到自由文本、comment、附件或 `issue_source_context`，也不改造普通文件读取/哈希路径。
- `repair-assess`、`repair-outcome`、授权 extend/migrate 和 sensitive-action 不在本次新增接线清单；其既有能力与拒绝边界不变，不能借本 change 获得新的准入或额度语义。

**为什么**：proposal 明确限定五个控制写入口；同时区分首次业务写入与已提交恢复，既闭合绕过，又不破坏幂等恢复和普通读。

**备选方案及排除原因**：
- 所有 crctl 命令强制 daemon：会改造普通读并破坏 legacy/恢复。
- 只接 `advance`：repair、register、archive 可绕过同一信任链。
- archive 每次重放都要求新证明：cleanup 后可能无法读取旧现场，破坏既有 journal 恢复；因此只保护首次新业务写入。

### 4. 保留既有业务权威和失败原子性，不用信任链替代业务裁决

**方案**：信任链只回答“谁能在哪个根、哪个 project、以哪份来源执行这次控制写”。T 仍裁决状态机、scope、修复预算、独立证据和交付门禁；M 仍保存认证、DB 归属与当前 claim/head。repair 复用原 `review-loop`/receipt 历史，register/archive 复用原 workspace transaction 与 journal。

所有针对尚未提交新业务写入的无效证明负例均在准入阶段失败，不通过“先写再回滚”制造可观察副作用。门禁或绑定在锁外完成后，锁内必须复核 grant/head/当前 scope 与 write-set；head 前移、撤销、platform 失联、trust root/key 变化、root 替换均拒绝。成功重放沿原 receipt/journal，不重复消费；已提交 repair 重放返回原 repair_id/receipt，崩溃恢复按已提交事实恢复或回滚未提交写入。

**为什么**：外部信任与业务授权是不同维度；合并成新总账会破坏既有历史、额度和恢复语义。

**备选方案及排除原因**：
- 以有效 execution-binding 直接推进或恢复：会跳过业务 gate、预算与停止条件。
- 失败后靠补偿清理：崩溃窗口仍可能留下 registry/任务/消费副作用，不满足 ADJ 判据。

### 5. 组件 CP 与真实闭环证据分层，缺真实证据不得关闭 ADJ

**方案**：SPEC 为 10 个 SC 各定义一个精确 TAP CP/TC。Node 测试驱动真实公开 crctl、隔离 Git/workspace 与签名 fixture；M 的真实 HTTP/DB/daemon 链和目标 OS 身份测试作为同一 TC 的必需闭环证据，不用 mock signer、静态源码检查或组件 helper 替代。

- ADJ-001：两个真实 project 使用同一平台签名 key，把 B 的有效证明/安装材料复制给 A；五个首次写入口均拒绝且无业务副作用。
- ADJ-002：真实平台签发前独立提取并保存来源；随后仅改 `accepted_rules` 一个字符而保留原签名，真实控制准入拒绝且无业务副作用。
- ADJ-003：每个拟启用 OS 都以真实 agent 身份覆盖 daemon 安装的公钥，内核拒绝且 digest 不变。Linux 不同 UID、Windows 不同身份缺一不可；同 UID chmod、路径 pin、组件校验不算证据。

**为什么**：TAP 的 `exit_code=0` 只说明所选测试通过，不能自动证明外部部署事实；分层能防止历史上的“匹配 0 条测试”和“组件通过冒充隔离通过”。

**备选方案及排除原因**：
- 只用 Node fixture 宣称三条 ADJ 关闭：没有真实控制面/内核证据。
- 缺身份或平台时 skip 后仍计 CP PASS：会产生假通过；本规格要求 fail/skip/todo 都为 0，并将未取得的部署证据明确标为未验证。

## Architecture

### 信任链与调用链

```text
认证人类 structured-human-request/v1 原 bytes
  → M 认证 actor + DB 解析 workspace/project/cr/resource
  → M 签发前独立提取 json-pointer bindings、source_event_id、SHA-256
  → execution-authorization/v1 签名（原 payload bytes）
  → 认证 daemon 在独立 OS 身份下安装 key/grant/source 到 trust root
  → daemon 启动控制子进程；env/路径仅用于定位
  → T requireControlAdmission
       ├─ key_id + trust root + Ed25519 验签
       ├─ readExecutionSource：原 bytes / digest / bindings / scope
       └─ requestExecutionBinding：当前 claim/head + 签名 challenge + 根 dev/ino
  → 对应既有业务事务与锁内 CAS 复核
       ├─ authorization-bind / advance
       ├─ repair-admit / repair-resume → 原预算、历史、停止裁决
       └─ register / archive → 原注册/归档事务与 journal
```

任一箭头缺事实、跨 project、复制到另一安装根、来源 bytes 改一字、key 不可信或当前 scope/head 不符，均在业务 write-set 之前终止。

### 实现落点

| 仓库 / 文件 / 函数 | 本 change 落点 |
|---|---|
| T `scripts/lib/control-admission.mjs`（新内部编排文件） | `requireControlAdmission` 统一组合三项既有校验、固定 operation 词汇、返回一次性 admission；不持久化第二本账 |
| T `scripts/lib/execution-authorization.mjs` | 复用 `installDirectory`、grant/envelope 校验、`readExecutionSource`；补齐共用入口需要的明确错误与 trustRoot 传递，不改变原 bytes 规则 |
| T `scripts/lib/execution-binding.mjs:requestExecutionBinding` | 复用签名/challenge/root dev/ino；收紧五个 operation 与当前 scope/head 的组合校验，不将 env 当身份证明 |
| T `scripts/crctl.mjs` | 上表五个入口及 `readRepairGrantPayload` / `reverifyRepairAuthorization` 的 trustRoot 与共用准入接线；只读分支保持原样 |
| T `scripts/lib/workspace-transactions.mjs:registerCr/archiveCr` | 在首个 write-set 前接收并核对已验 admission 的候选 CR/project/root；沿用现有锁、CAS、journal 和恢复 |
| M `server/internal/governance/execution_authorization.go:BuildExecutionAuthorization` 及真实 route | 签发前独立验源、生成来源事件与 bindings、冻结当前 DB 归属；不从 Agent 候选映射签发 |
| M `server/internal/governance/execution_binding_issue.go:HandleDaemonExecutionBinding` | 五个 operation 白名单，当前 claim/head/project/CR 校验后签名；不开放任意 nonce 代签 |
| M `server/internal/daemon/execution_binding_{relay,client,endpoint}.go` 与 task launcher | 仅中继 daemon 亲启子进程的实际 challenge/root/task；向五个入口传同一 trustRoot 和受保护通道 |
| M `server/internal/daemon/execution_trust.go` / `execution_verifier.go` | daemon 身份安装与读取 trust root，保持异内容冲突和真实 crctl 检查；部署身份隔离是启用前置 |
| T `scripts/test/{trust-anchor-chain,repair-trust-anchor-chain,delivery-trust-anchor-chain}.test.mjs`（BUILD 新建） | 10 个精确顶层 TC；公开 CLI、跨端负例、业务零副作用；不在此 SPEC 阶段创建 |
| M 既有 governance/daemon 测试与目标 OS 部署验证 | 真实 route/DB/daemon、跨 project/篡改/复制负例及内核拒绝；证据与组件 CP 分开记录 |

## 迁移与兼容

- 新合同控制写必须显式配置 daemon-owned trust root、独立 OS 身份与可用绑定通道；缺配置或缺目标平台身份证据时不得启用。没有“配置缺失则回退 `.crctl` 自报文件”的兼容分支。
- legacy CR 保持原 gates/pin/历史，不自动获得新信任语义。显式迁移仍走既有授权与迁移合同，本 change 不清空消耗、不重置 stop、不复制交付账。
- 已安装的同 key_id 同 bytes 材料可幂等重读；异 bytes 不能静默覆盖。key rotation 不在本 change 中发明 CA/PKI，只能沿现有认证 daemon 重新安装并在准入时与签名 envelope 精确匹配。
- 已提交事务重放使用原 journal/receipt；未完成且没有可信证明的旧 sidecar、env 或路径 pin 不得转为准入事实。
- 普通读、普通文件证据哈希与签名/来源字节边界分离；前者可沿用仓库文本规范化，后者绝不规范化。

## Risks / Trade-offs

| 风险 | 缓解措施 |
|------|----------|
| `register` 在本地 CR 写入前没有可绑定的平台 CR/claim | 把平台预分配 CR/claim、registration key 与本地候选 CR 一致性设为前置；无法满足则失败关闭，并在 TC-TAC-009/010 做真实时序验证 |
| daemon 与 agent 实际仍同 UID/同 Windows 身份 | 部署预检拒绝启用；按每个目标 OS 取得真实内核覆盖拒绝，不能用目录 mode 或路径检查代替 |
| 五个入口在锁外验证后发生 head/root/key 漂移 | 既有锁内重读 grant/head/scope 与 write-set CAS；漂移、撤销和失联均无新业务写入 |
| repair 为绕信任链复制一套预算/恢复逻辑 | 只调用共用准入，后续仍走原 origin、额度、历史、停止与幂等规则；TC-TAC-007/008 同时断言历史不变 |
| archive 已提交重放被新证明要求卡死 | 仅首次新业务 write-set 需要准入；journal 已提交后的恢复沿用原事实，不重复消费 |
| Node CP 通过被误写成真实平台或 ADJ 已关闭 | CP 精确匹配与 TAP 汇总之外，强制真实 M 链和目标 OS 补充证据；缺证据明确未验证，不允许 skip 记 PASS |
| 为五个 operation 开放通用签名能力 | 服务端固定 operation 白名单、DB claim/head/project 校验、daemon 亲启子进程中继；拒绝任意 nonce/scope 代签 |
| 信任链被误认为可抵御平台或 daemon 自身被接管 | 明确信任基包含平台签名服务、DB、daemon 和部署控制工具；本 change 不声称防御这些可信组件被攻破 |

## SPEC 审查结论

- C1 由决策 1/2 与 REQ-TAC-001 覆盖；C2 由决策 3/4 及三个 capability 的入口 Scenario 覆盖；C3 由决策 5、TC-TAC-002/004/005/008/010 与真实证据要求覆盖。
- 三个 modified capability 均有 Canonical code/agent YAML；每个 Requirement 至少一个 Scenario，每个 Scenario 对应一个 CP 与一个 TC。
- 所有 10 个 TC 使用新 `TC-TAC` 编号空间，CP 的精确正则、测试文件和 test-plan 一一对应；本阶段不执行这些尚不存在的测试。
- 设计未引入第二本账、原生依赖、CA/PKI 或普通读改造。Gate 2 未确认，真实平台、生产启用和三条 ADJ 关闭均未声明。

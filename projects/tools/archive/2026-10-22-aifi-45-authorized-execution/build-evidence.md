# BUILD 组件证据 — AIFI-45

## 当前：daemon 生产静态核验接线（第三轮，非准入）

- STDD 三路独立分工（code/test_config/docs_skills）已执行；项目缺 tier/model_tiers，按 C1 规则默认回退，不猜档位、不改配置，不称模型分层已生效。首轮 incomplete 如实保留；补跑发现逐项处置。
- M `handleTask→prepareClaimedPipelineTask→Client.InstallExecutionAuthorization→verifyInstalledExecutionGrant` 已接真实 crctl `--check --trust-root`；真实 Auth/隔离DB/DB-backed mdt/DaemonAuth 投递验证，无 daemon context/cache 注入。
- source/HTTP 超限/换根/无效合同/仅根归属/缺显式 false 事实均实际 RED 后修；Windows Stat 惰性 ID 首修仍失败，句柄 Stat 根因修复后换根20/20。另有 POST/JSONB GET 同包重投冲突与重复包装键联合实际3FAIL后修7PASS；仅固定未签名运输包装，原签名 payload/人类请求 bytes 不变。最新 governance606/606、cmd/server6/6、daemon36=35P/1S，均exit0；事件与命令存 [M regression](../../../multica/changes/2026-10-22-aifi-45-authorized-execution/preflight-regression.json)，说明见 [M evidence](../../../multica/changes/2026-10-22-aifi-45-authorized-execution/preflight-evidence.md)。
- 新合同静态成功仍拒 `EXECUTION_CONSUMPTION_REQUIRED`；可信 current-head/撤销/DB claim、不可删激活/实际隔离/消费事务尚缺，完整业务 TC 仍0/49，major不解决。T 代码本轮未改；以下106/164/14等为此前实际回归，不冒称本轮重跑。

## 历史：执行授权 HTTP→daemon trust root 投递（第二轮）

| 对象 | 真实结果 | 边界 |
|---|---|---|
| M `InstallAuthorizationRecord` 拒绝他 CR 记录 | 旧实现实测 `install err = <nil>`（1 FAIL）→ 增 CR 校验后 PASS | 首个 install/fetch 用例为占位桩 RED（缺行为），不冒称业务 RED |
| 组件链：真实 `HandleExecutionAuthorize`→隔离DB→`GET /api/daemon/crs/{crID}/execution-authorization`→`Client.InstallExecutionAuthorization`→真实 crctl `--check --trust-root` | `TestDaemonFetchesAndInstallsExecutionAuthorization` 及 2 子例 PASS；digest = `ExecutionGrantDigest`；不带 `--trust-root` 时 crctl 找不到该 grant；跨 workspace 404、无 daemon 绑定 403、缺记录 404，均不落文件 | daemon 绑定由 `WithDaemonContext` 注入，未走真实 daemon token；非整链 TC |
| 回归 | governance `^TestExecution\|^TestDaemon` 69/69；扩大 `-skip ^TestReconcileLiveGitHub$ -shuffle=on` **RUN598/PASS598/0F/0S/exit0**（=588+新增10）；cmd/server 路由 6/6；daemon `^(TestExecution\|TestMKey\|TestGrant)` 33=32P/1S（Win 目录链接）；`go vet`、`go build ./cmd/server` exit0 | LiveGitHub 仍排除 |

- 安装器：先以随记录下发的服务公钥验签，再要求 payload `workspace_id`=store、`cr_id`=请求CR、`key_id`=envelope、`grant_id` 为 UUID；按 keys→source→grant 顺序写，grant 最后可见；`os.Link` 发布不覆盖已有名（并发安装不能互相替换，未构造并发 RED）。
- 接口只做投递：只返回该 workspace 冻结初始记录与服务公钥，不置 `delivered_at`、不代表 current head/撤销/claim。
- **第二轮时未接（历史）**：daemon 在 claim/当前 head 路径以 `--trust-root` 驱动 crctl（需新合同 opt-in 信号，避免追溯阻断 legacy）、不可删 activation、current-head/撤销/claim、消费事务；T 仍 `EXECUTION_CONSUMPTION_REQUIRED`。

## 历史：trust root 安装器首轮（非隔离证明）

| 对象 | 真实结果 | 边界 |
|---|---|---|
| T `authorization-bind --trust-root` | 旧码实测 **2 FAIL**：`--trust-root` 被忽略 → ①带声明的 trust root 时仍返回被篡改工作区包的 digest（与合法包不等）、②指向工作区 `.crctl` 的 trust root 反而 exit0 | 修复后同文件 **106/106 PASS/0 FAIL/0 SKIP/exit0**（约43.5s） |
| T 三文件联合（授权+事务+durable） | 164 选中 / 163 PASS / 0 FAIL / 1 SKIP / exit0 | 唯一 SKIP 仍是 Windows 文件 symlink EPERM，非本次新增 |
| T 旧 grant 选择回归 | 14 / 14 PASS / 0 SKIP / exit0 | 未受安装目录参数化影响 |
| M `ExecutionTrustStore` 安装器 | `go test ./internal/daemon -run '^(TestExecutionTrust\|TestExecutionRoot...)'`：RUN14 / PASS13 / FAIL0 / SKIP1 / exit0 | 4 个新断言真实PASS；SKIP 为 Windows 建目录链接需特权（不是通过） |

- 实现要点（T）：`installDirectory()` 统一解析安装目录；声明 trust root 时必须是绝对路径、可 realpath 的目录，且**不得位于或包含工作区安装根**（`EXECUTION_TRUST_ROOT_INVALID`）；`installedFile()` 改为以“安装目录”为锚做 realpath 包含校验，grant/公钥/来源 sidecar/`execution-binding/v1` 证明共用同一目录。
- 实现要点（M）：`OpenExecutionTrustStore(daemonHome, workspaceID, forbiddenRoots...)` 派生 `<home>/.multica/execution-trust/<ws-uuid>`；0700 目录、0600 文件、`CreateTemp`+`Rename` 发布；同内容幂等返回同路径，**异内容 → `EXECUTION_TRUST_CONFLICT` 且原文件不动**（对抗“换公钥自签”）；拒绝非 UUID workspace、相对 home、越界名称（`../`、分隔符、隐藏名）、未知 kind、空内容。
- 构建期实际失败（非编造RED）：`pathWithin` 参数顺序写反，`TestExecutionTrustRefusesRootInsideWorkspace` 实际返回 `nil` 错误 → 修正方向后 PASS。
- **首轮时未闭合（历史）**：daemon 尚未以 `--trust-root` 调用 crctl；HTTP 授权包尚未落盘安装；legacy `{root}/.crctl/{keys,grants}` 与 T 默认读路径仍存在；同 UID 下“不可写”仍依赖执行侧挂载集不包含该目录（隔离PoC已验证不挂载 HOME）。故 ADJ-003/M002 仍 `resolved:false`，消费仍 `EXECUTION_CONSUMPTION_REQUIRED`。

> 普通模式；Gate 1/2 已确认，用户已采纳可信绑定/原始来源补正并要求继续。不是 Gate 3、上线或扩权批准。**完整业务 TC = 0/49；完成切片 = 0**。本页只记真实组件执行，不用函数/子断言数替代 TC。

## 主线程独立复跑快照

| 对象 | 真实执行结果 | 边界 |
|---|---|---|
| T `execution-authorization.test.mjs` | 103 选中 / 103 PASS / 0 FAIL / 0 SKIP / exit 0；约46.2秒 | 原bytes签名、严格schema/source、目标仓/控制根descriptor、nonce/proof子集；不是实际平台签发或业务消费 |
| T AUTH当前（撤回不可信消费） | 104 选中 / 104 PASS / 0 FAIL / 0 SKIP / exit 0；约46.8秒 | 新增真实RED→GREEN：fresh proof/source仍缺平台current-head/revoke/claim时必须拒绝，预置receipt不能激活。独立receipt writer已删除，live终点为EXECUTION_CONSUMPTION_REQUIRED |
| T AUTH + execution-transaction + durable-tx 当前三文件联合 | 162 选中 / 161 PASS / 0 FAIL / 1 SKIP / exit 0；57151.3239ms | AUTH104/exec41/durable17；显式--test-reporter=tap获取真实统计。file-symlink因Windows EPERM未执行；非整TC |
| T `durable-tx.test.mjs` 全文件（联合前独立） | 17 选中 / 17 PASS / 0 FAIL / 0 SKIP / exit 0 | 前一次lowercase lock空匹配wrapper的1 PASS已丢弃，不当回归证据 |
| M `pkg/protocol` 全包 | RUN 58 / PASS 58 / FAIL 0 / SKIP 0 / exit 0 | 资源描述符构造；不证明远端clone/本机realpath/freshness |
| M core `use-realtime-sync-inbox.test.tsx` + `system-notification.test.ts` | 2 files / 25 PASS / 0 SKIP / exit 0 | 客户端claim、confirmed/void分流、workspace tag、异步失败、mute/focus竞态 |
| M desktop `notification-gate.test.ts` | 1 file / 18 PASS / 0 SKIP / exit 0 | main gate的超时/late-attempt/稳定workspace隔离；没有实际OS展示验证 |
| M governance 当前Auth/handler/签名/真实Node选择 | RUN 85 / PASS 85 / FAIL 0 / SKIP 0 / exit 0 | 真实Auth/handler/Node59 + manifest26；非cmd/server→wake→TaskService全链，作者旧广选择74勿混计 |
| M governance最初完整包（历史保留） | RUN 581 / PASS 578 / FAIL 3 / SKIP 0 / exit 1 | MDispatch001顶层+子例、ReconcileLiveGitHub失败。现已稳定复现并修复MDispatch同名fixture/ownID不存在的顺序缺陷及并发污染；初次原错误上下文缺失，不能反推全部同源。LiveGitHub未重发PAT、仍未收口 |
| M governance最新扩大复跑（排除LiveGitHub一个顶层） | RUN 588 / PASS 588 / FAIL 0 / SKIP 0 / exit 0；最新-shuffle=3 | 既有580+新增fixture lease/phase-order回归8，真实Go→Node互操作同跑。显式排除不是覆盖/修复LiveGitHub，不篡改首次全量exit1事实 |
| M daemon两Root顶层+子例 | RUN 8 / PASS 8 / FAIL 0 / SKIP 0 / exit 0 | 可信Task.ProjectID选择与provenance投影；不证明当前freshness |
| T 旧grant选择回归（最新主线程） | 14 PASS / 0 SKIP / exit 0 | 当前14个真实匹配执行，不是tools全量 |

主线程T复跑使用真实 `node`，不是沙箱 `process.execPath`；M前端显式 `NODE_ENV=test`。T每个fixture均独立临时Git/workspace/测试key，未提交真实仓库或操作实际CR。

## 本轮真实行为 RED → GREEN

| 缺失行为 | 修复前实际失败 | 修复后 |
|---|---|---|
| 逻辑repo名不能独立证明物理资源 | 1选中/1失败/exit1：缺repository_bindings的签字包原被`--check`接受 | 必填服务端冻结descriptor，原反例及完整包正例通过 |
| 只冻code仓不能保护CR控制根 | 1选中/1失败/exit1：缺coordinator_binding原被接受 | 原始coordinator_selection与已签coordinator_binding双向核对 |
| proof必须匹配具体资源与本地daemon | 3选中/3失败/exit1：另一合法UUID资源/daemon原到达消费占位；合法opaque daemon反被UUID检查拒绝 | 6选中/6 PASS/0 SKIP/exit0：固定coordinator资源ID、本地daemon值，opaque类型与现有平台一致；仍拒业务消费 |
| 严格schema的C1控制与scope ID歧义 | 3选中/3失败/exit1：C1路径及重复action_scope_id原被接受 | C0/C1控制拒绝，敏感scope ID唯一；包含于76/76复跑 |
| 原授权/原文一起复制仍不能换安装根 | 1选中/1失败/exit1：另一安装目录原到达消费占位 | 本机native fully-qualified路径、词法规范路径和dev/ino同目录检查；linked worktree通过Git common-dir锚回InstWS |

- 本地根检查后，一次完整复跑发现旧proof fixture仍把coordinator指向tools源码根而非fixture InstWS，导致部分用例在challenge前被拒。已修测试给定的根，不放宽生产校验；最后完整选择为76/76。
- source回归矩阵另覆盖：14语义字段、两个原始selection、错UUID/版本、缺字段、额外root声明、重复选择键；这些是回归补充，不编造其逐项test-first RED。
- T `--check` 始终 `bound=false,current_head_verified=false,source_verified=false`，只读、不建receipt。即使当前proof子集和source通过，仍 `EXECUTION_CONSUMPTION_REQUIRED`。

## 隔离事务组件（尚未接消费）

- 作者回修的真实失败包含：跨worktree丢journal、callback切同SHA branch、CR目录junction、ledger:null、mode/stage第三值、精确trailer/intent/写集/receipt查找。
- 原生index锁的真实RED：未锁最后一次读取后，真实Git成功stage的第三值被随后update-index覆盖，数据保持断言失败；新实现持Git原生index.lock，在锁内复制/更新候选index再发布，竞争Git被原生锁拒绝，不覆盖用户stage。
- EXEC-22已真实复现最后HEAD检查后切same-SHA B，A仍被推进；作者补偿回退虽GREEN但不构成安全闭环，主线程拒绝当原子保证。EXEC-23/24/25真实busy/drift/split维护回归作者25选中/24PASS/1symlink-SKIP，尚非最新独立kernel结果。
- 纯temp实证：HEAD symref-verify+referent单事务被Git2.54拒duplicate；跨worktree伪ref在stdin被拒bad-name；prepared hook stdin不含HEAD，EEXIST不能证明本事务owner，均不采纳。成立的原生组合为**parent自己独占原HEAD.lock，锁内核sym+oldSHA，再从同common-dir detached helper做native CAS**；main/linked均发布成功不自锁，锁期间原目录真switch失败，释放后恢复。已用既有ledger beforeApply接缝先落native/helper intent，再加原HEAD锁；恢复也锁内验ref，实际token匹配native/recovery记录、同机dead PID才回收。abort/recover全部deferFinalize，经统一cleanup释放/定向清helper后discard；helper缺证不丢journal、无全局prune。applyStarted=false不碰工作区，rolled-back/complete持久终态避免二次rollback；fd归handle关闭。消费试作前联合161/160PASS/1EPERM，撤回后最新162/161PASS/0FAIL/1EPERM/exit0。未知/0字节锁/无证helpermanual maintenance，不用事后补偿；真实SIGKILL全边界未全部覆盖。
- 文件自身symlink的EPERM不通过提权绕过。不能把真实目录junction用例当该文件symlink分支已执行。
- 旧advance/merge/checkpoint/archive/writeback/sync等写入口的CR互斥域与权威policy guard仍未统一；不以基础lock 5/5或此adapter快照冒充RPR-006完成。

## M作者证据及待独立核验

- 新协议已主线程真实再跑：隔离容器label/55432/DB/user先核，URL仅内存，GOPROXY=off；`go test ./internal/governance -run '^TestExecution(Authorization|Authorize|GrantCheckAgainstRealCrctlCLI)' -count=1 -v` 59/59 PASS、0skip、exit0。包括同生产Mount真实JWT/Auth/workspace、owner/member/无token伪header/跨ws/默认及nil503/真实task_token拒绝，真实Node正例+保留签名重序列化负例。作者74是更广旧回归选择，不混计。历史同步窗口的63P/1S与FAIL不追补为PASS；自动源码猜测SKIP门已删除。
- 新HTTP handler复用approval_record，CR FOR UPDATE与所选资源UUID去重排序FOR SHARE；同actor+原bytes返回原包，不因成员改resource_ref重新签包/重置。异actor/原文/project冲突；execution不进入旧pending/ACK推进。
- Auth路由已执行但不代证完整cmd/server→wake→TaskService；之前注入可信context的handler测试不代证真实认证。cloudPAT真实Fleet verifier未测。显式pinned manifest startup接线已实现未配置，默认503；主线程Auth59+loader26联合85/85（0skip/exit0）、router公开面回归1/1、server build exit0。loader初版直接GREEN；后续canary/非规范SHA和case-fold alias实际RED→GREEN，UNC只改诊断不算缺失路径拒绝RED。不启用消费。
- 实际daemon追链只读发现：child虽过滤MULTICA_*并有0700独立config root，仍同UID/HOME可读daemon profile token。缺OS隔离证据，private stdio不能当凭据隔离；不提供任意nonce代签API，当前head/撤销/所有资源当前回读仍未闭环。
- 资源descriptor纯API的初始RED仅缺API编译失败，**未执行业务断言**；不计行为RED。handler只编译不冒充执行。
- daemon根选择已保留真实Task.ProjectID、resource ID与snapshot来源；作者执行字段补全后5个行为失败断言再修绿。主线程daemon两Root顶层及子例独立8/8、0skip/exit0；Source=snapshot不是freshness证明。
- 客户端六项回修作者真实RED：core 7 fail/18 pass、desktop 4 fail/13 pass，均exit1；当前主线程已独立25+18 PASS。作者相关100/100与类型/ESLint通过；本轮未复跑全core。早前desktop全量61 files/673 tests passed但另有未改package.test.mjs解析失败exit1，不能称全量通过。

## 隔离可行性实证（本机 Podman 5.8.3 rootless，linux/amd64）

零仓库改动，仅临时目录+`alpine:3.21`（本地已有，`--pull=never`）。固定 argv 由可信侧拼装，被测方不能影响 flags：`--rm --network=none --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges -v <worktree>:/ws -w /ws`。

| 断言 | 结果 | 证据边界 |
|---|---|---|
| 仅挂载授予工作树时看不到宿主 daemon 凭据目录 | PASS：`SECRET_ABSENT`，canary未泄漏 | canary是临时目录下伪造的`mdt_`值，不是真实凭据 |
| 宿主 HOME/`~/.multica/config.json` 在容器内不可见 | PASS：`HOME_MULTICA_ABSENT`；宿主该文件实际存在 | 只证明未挂载则不可见 |
| bind mount 只暴露子树，不是整盘 | PASS：`ls /ws` 仅工作树内容，`/ws/Windows` 不存在 | 9p `aname=drvfs;path=C:\` 只是 share根标签，实际挂载被限定到子路径 |
| 工作树内由宿主建目录 junction 指向外部秘密，容器能否穿越 | PASS：`/ws/escape` 在容器内根本不存在 | 仅 Windows junction；未测容器内自建链接/文件symlink（本机EPERM） |
| rootfs 只读 | PASS：写 `/etc/pwned` 返回 `Read-only file system` | `test -w /` 因user namespace内uid=0而假阳，**不作证据**；以真实写入尝试为准 |
| 断网 | PASS：`--network=none` 下 DNS 不可解析 | 未测开启网络时的出站限制策略 |

**结论与限制**："容器仅挂授予工作树"足以把宿主凭据挡在不可见侧，且 junction 不穿越；但这只是**可行性**，不是已接入。未证：真实 agent CLI 镜像（属新增依赖，需授权）、容器内自建符号链/挂载逃逸、资源限额与耗时、Windows 9p 下的文件模式/dev-ino 语义与 T 的绑定检查是否一致。

## 新发现（未修复，已登记 ADJ-AIFI45-003）

1. **执行授权文件磁盘安装步骤尚不存在**：M 只经 HTTP 返回 envelope，T 只从 `.crctl/grants/` 读文件；缺安装器即缺落地路径审查，未来安装点必须落 daemon 自有 trust root，不能进工作树。
2. **legacy grant 与公钥落在可能被 agent 写入的树内**：M `crevents.go:246,317` 写 `{root}/.crctl/{keys,grants}`，而 T 读 `deriveInstallRoot(workspace)/.crctl`；当 agent 直接在安装根工作时，两者是同一目录，被管进程可替换公钥后自签。
3. **尚未获得已落地隔离能力的证据**：已读`profileLaunchSpec`为`path/version/fixedArgs`，`process-group/JobObject`仅生命周期，Codex配置不等于与daemon隔离。后次调查未完整核profile migration/handler、部署内容或统一argv/env/cwd，不能把“未定位”写成证明不存在。

## 准入消费 receipt（历史试作，已撤回）

**以下四条仅保留历史，不描述当前实现。** 104组件绿色不能证明消费权威：当时仍`current_head_verified:false`，另写无既有事务/CR锁的receipt，存在并发覆盖和可写trust-root风险。现新增公开CLI拒绝断言实际运行1FAIL/exit1（旧实现返回exit0）；删除独立writer及import/caller后104/104。当前仍按grant→fresh proof→source逐项验，但最终`EXECUTION_CONSUMPTION_REQUIRED`，不创建receipt、不改变HEAD，预置旧receipt也不能激活。尚未接完整平台链及既有消费事务。

- 历史live（非`--check`）路径在验签→必需`--binding-stdio`→challenge/根/daemon/head绑定→来源逐字段映射**全部通过后**，写 `<installRoot>/.crctl/execution-consumptions/<scope_hash>-<grant_id>.execution-receipt.json`；九字段固定顺序，`input_digest=SHA256("execution-consumption/v1\0"+grant_digest+runtime_id+task_id+daemon_id)`。
- 幂等/冲突：同绑定重放返原 receipt 且字节不变（`reused:true`）；同 grant 异绑定 → `EXECUTION_CONSUMPTION_CONFLICT`，**零写入**。不新建 journal/预算/总账；不改 execution-transaction/durable-tx。
- **RED 诚实边界**：四条旧断言原本编码的是 `status=1 + EXECUTION_CONSUMPTION_REQUIRED`（旧行为本身即“无 receipt”），我把它们改为要求 receipt；**新断言未在旧代码上实跑过**，只有 fsync 失败那一次是实际运行失败（NTFS 目录 fsync EPERM，已按仓内 `durable-tx` 的 best-effort 惯例修）。冲突用例与实现同批，**非 RED**。
- **未证**：M 侧永久幂等/`logical_dispatch_key`、current head 与撤销、真实平台下发链、`repair_limit` 扣减与无进展停机、敏感动作执行。因此仍不算任何完整 TC。

## MDispatch本change内定因与回归

- 并发两个旧Go进程使用同一固定workspace/agent/CR fixture，实际复现`agent_workspace_name_unique`/SQLSTATE23505等；独立PG session advisory lease覆盖seed→m.Run→cleanup，第二session取锁断言在旧版实际1FAIL后修绿。不加sleep/skip/force。
- 更重要的单进程顺序反例：先seed architecture fixture，再跑原四阶段MDispatch，requirement自己的reviewer ID不存在，旧清理用`SELECT name ... WHERE id=ownID`得到空集，遗留同名quality-reviewer-agent，随后INSERT实际23505（3层FAIL）。改为从已解析registry取名字，放入共享`setupRequirement`供全部caller复用，不改生产Runner/Enqueuer。
- 最新两个独立Go进程各10轮原MDispatch+顺序反例+lease断言：各RUN140/PASS140/0FAIL/0SKIP/exit0；扩大包588/588。历史首次日志不足，确定修复的是可复现fixture缺陷，不宣称证明原始全部失败同源。

## CP验收防误认


- T 32个canonical CP改为精确顶层完整TC名称和TAP成功行，另要求fail/skip/todo为0；带后缀的组件标题不满足整TC。
- 实测不存在完整TC-AUTH-001时，Node可把空匹配的文件wrapper报成1 PASS，但没有`ok 1 - TC-AUTH-001`，新CP断言拒绝该结果。不能只看exit0/测试文件PASS，也不能把ctx代码回显当子进程stdout。
- 两仓最新native validate/canon verify均exit0（proposal各2/2），T2/M1文件级AND警告；只读YAML结构核19REQ/49SC/49TC/49CP唯一对应、每SC AND max4、T32 CP exact guards通过。checker首轮错用shall键失败，改真实then键后通过，不冒充规格RED。
- M完整CP仍要求精确`TestTC_RUN_NNN`/真实PASS行；handler/Root等组件不代替真实route→T CLI→wake→TaskService/隔离DB。

## 仍未关闭的安全/业务链

1. 平台真实claim、daemon_token与私有控制子进程、当前授权head/撤销及每个目标repo当前身份；不能提供Agent任意nonce代签API。
2. trusted manifest/实际安装工具、registry、权限/隔离和运行二进制一致性；源码SHA不是部署证明。
3. T实际准入/敏感额度/累计修复/进展/resume、所有旧写入口防删字段降级及共用CR锁。
4. M永久logical_dispatch_key、adoption及四阶段实际wake/恢复；不在M再建预算。
5. 内容型门禁、独立交付和legacy兼容；服务器Inbox pending/delivered、mobile、GC/重启恢复。
6. 完整49TC、相关全量回归、14类失败、独立审查、隔离三路径与Gate 3。

T的ADJ-AIFI45-001/002/003及M对应major继续resolved:false；方向已采纳不等于验证闭环，也不是暂停等重复确认的理由。真实CLI/临时镜像依赖PoC已获授权，原npm180s与官方单文件fetch600s两次下载超时均不是行为RED/隔离PASS；原生curl完整112589966 bytes/SHA/tar/镜像构建已过；授权调machine systemd可拿到cpu/io/memory/pids委派，但podman machine WSL API proxy pipe失效，已完整回退并恢复三容器/专用DB。最终PoC exit0：真实`codex-cli 0.163.0`、六项边界实测、`resourceLimitsEnforced:false`（本机无委派控制器，资源耗尽未受控）、资源定向清理；不接daemon任务/claim，准入仍关。未触碰真实CR/生产DB/真实仓库commit/push/上线/全局权限；不调用付费模型。

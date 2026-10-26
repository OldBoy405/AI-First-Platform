# Phase Context — AIFI-45 multica

## 2026-10-25 执行绑定签发（当前；消费仍关闭）

- T 侧 `requestExecutionBinding` 早已实现 challenge/stdin 证明校验，**服务端签发缺失**导致消费无法开始。本片补上：`POST /api/daemon/crs/{crID}/execution-authorization/binding`，body exact 4 键（task_id/runtime_id/dispatched_at/challenge），同一 RR 事务核 task（runtime+代次+active+cr_id+认证workspace+daemon）、head（复用撤销/scope/policy/template/source 校验）、project、coordinator local_directory+daemon、challenge 摘要；不符 409 不签。[计划](validation/binding-issue-20261025T081500Z-plan.md)。
- 签名输入 `UTF8("execution-binding/v1\0")||payload`，Ed25519，payload 恰好 20 键（与 T 期望字段集一致）；新表 `cr_execution_binding_issue` append-only（唯一键 + 拒 UPDATE/DELETE 触发器，无 FK，迁移 643），同 challenge 重放逐字节 `changed=false`。
- strong 首轮 2×P1+3×P2（task↔CR 关联缺失、代次不唯一、JSON null、非 canonical runtime、冲突重读未释放事务）→ 修（body 增 task_id、SQL 主键精确取行 + cr_id 条件、null 拒、canonical）、复核 F2–F5 CLOSED；F1 残余（`task.cr_id` 可被 daemon 自报覆盖）→ `SetTaskCRAttributionIfValid` 改首次写入胜出、删重复 `AttributeTaskToCR`，复核 **CLOSED**。
- runner 新增 `-migration=server/migrations/NNN_x.(up|down).sql`（只允许该目录、记录 sha256），因为临时库是冻结原库 **schema-only 克隆**；没有它新表不存在。node 测试 9/9。
- 证据：`red1` 11FAIL 全是 fixture CR-ID 形状错（不计 RED）、`green1` 0RUN 编译错（不计）、`green3` 11/11（10 leaf）、`green4` 16/16（15）、`green6` 18/18（17）。**跨语言互通**（REQ-AUTH-004/SC-AUTH-010）：新测试真实拉起 Node 调 T 的 `requestExecutionBinding`（challenge→HTTP→回写 envelope），断言 T 接受且 20 键、篡改 payload（保留签名）被拒；需 `AIFI45_TOOLS_ROOT`，未设则 Skip。strong 首轮判正向成立、负例缺陷 I1（用旧 challenge 不能隔离签名失败）→ 改用自身 challenge 后 **CLOSED**；仍余一项 tightening（负例未断言具体 `cause_code`）。
- 最终冻结 13 项 → `final4-independent-report.md`（`a080127a…`）：governance **900/899/0/1（814 leaf）**、handler 13/13（10）、daemon 125/124/0/1（115）；13 项前后一致、原库 137 表/6228 行/82 审批不变、vet exit0。CUSTOM **#171 / M11=24**。
- **未做**：daemon 私有 stdio 中继、T 侧消费事务、不可删 activation 本体、同 UID 隔离控制域、`EXECUTION_CONSUMPTION_REQUIRED` 解除。进程号由 daemon 转述、服务端不可验证；首次 CR 来源仍未证明。旧 claim 锁序 INCOMPLETE、业务 TC 0/49、5 major 未关闭；原库 HOLD；Gate3/提交/推送/部署未授权。

## 2026-10-25 终态代次fence（当前BUILD；全链进行中）

- 沿用户“继续，非必要不停下来”进入下一必要纵片，不另等普通BUILD批准。[计划](validation/terminal-fence-20261025T060611Z-plan.md)。MDT fail/complete旧gen1对已重领gen2都真实误终止：分别200/failed和200/completed；现原CAS位置增加可选exact runtime/generation/认证workspace/daemon谓词，实际事务回滚/ErrNoRows严格分类，均真实RED→GREEN。无新增前置task/runtime锁、表/迁移/FK；legacy无字段路径暂保留。
- balanced实际写公开MDT HTTP矩阵及事实报告。strong分段评审：fail 1项P2已修；daemon F1–F4（早退降级/缓存串代/single-flight丢代/缓存耗尽）→ N1（PAT daemon 被误升级导致403）→ N2（strict 无 fenced 时不发终态，含解析出错残余），四轮后全部 CLOSED。当前实现：tuple 随 run 的 context 而非 taskID 缓存，single-flight 按 `deliveryKey`，仅 `mdt_` token 升级 qualified。最终 `final5` 冻结独立回归 governance 879/878/0/1（795 leaf）、handler 13/13（10 leaf）、daemon 125/124/0/1（115 leaf），五轮原库均一致、vet exit0。HTTP 矩阵 Fail 11 + Complete 10 子例全绿，只算组件，不签完整终态/业务TC。
- make sqlc在GOPROXY=off因deprecation lookup失败未生成；核本地sqlc v1.31.1和二进制hash，与Make固定同版后原生离线生成。首次ambiguous id失败0生成，显式qualify后成功；原字节生成前archive保留，规范化仅agent.sql.go变化。CUSTOM #170/M11=23。
- 截至 `n2b-green1`，本片共 27 条 runner 命令均 schema-only 独占新库/role，执行前 wx 实际source pin、执行后原137表/6228行/82审批与冻结共同相同、session/锁0、精确资源清理；含两次 fixture unique-key 失败与三次 runner 参数位置错误（均不计业务 RED，已如实记录）。主会话单DB权，调查/作者无DB权。原库HOLD/missing41/extra40不解除。
- **未完成**：retryable fail 在**有效代次**事务失败时仍可能已创建外部 Composio session（真实 POST `/tool_router/session`，无撤销）；无锁方案已落 `terminal-fence-20261025-retry-overlay-facts.md` 但未实现。动态并发快照 race、同代 complete/fail 并发第二条可能不落盘、legacy 无字段仍被服务端接受（PAT daemon 只能走 legacy）。旧 claim 锁序 INCOMPLETE。完整0/49、5major、消费关闭/Gate3/提交/推送/部署边界不变。

## 2026-10-25 当前task/project claim（前片；消费继续关闭）

- 用户明确“继续，非必要不停下来”“继续”；普通实现持续推进，不因组件结束重新等确认。主会话产品、balanced真实测试/事实调查与独立回归，strong必要分段审核；每次派发前实际原生models读取，actual unknown。
- wire §3.4已实现：既有status GET显式query、MDT/认证workspace/无控制字符daemon、同RR只读快照，冻结queue task.project_id与live issue/project同scope、runtime/代次/active状态；新SDK exact八键/运输/微秒token精度，daemon在根准备/授权安装前实际回读及比本机daemon。首片仅issue-backed，其他来源fail closed，legacy旧status/path不变。不是签名/持续freshness/本机隔离/准入。
- HTTP真实1FAIL→1PASS；strong发现10位小数秒截断P2，balanced补真实case，连C0/C1真RED→21/21；SDK/根前检查39/39。新claim读失败旧callback发1次真RED→抑制；作者全治理851/851（770leaf）、daemon112P/1 Windows权限SKIP（106leaf），含真实SDK→MDT→DB正反贯通。中间SDK0RUN编译错不算业务RED。CUSTOM #169/M11=22。
- 12条每命令pre-run source pin/后核，原137表/6228行/82审批与冻结共同相同、session锁0/精确资源清；19项raw/LF与archive在独立前冻结。非作者三组851/851、13/13、112P/1 Windows权限SKIP（leaf770/10/106）完成，各自19项先pin/后同；DB权释放，主会话期间未并DB。caller/server+SDK限定strong完成/无新增确证finding；宿主只读最终核本片15条基线共同未变、37对已知库role不存在，四包vet exit0。原库HOLD/missing41/extra40不解除，82不是83恢复。[本片报告](validation/claim-project-20261025T052646Z-report.md)。
- server+SDK static完成/时间P2关闭；旧claim锁序仍INCOMPLETE。已独立确证完整terminal回调/重放缺代次CAS，当前仅封新claim读失败分支，下一片继续而非假称全链关闭。完整0/49、5major未解，消费/Gate3/提交/推送/部署不推进。

## 2026-10-25 当前资源元数据读面（前段；消费继续关闭）

- 按用户要求实际给两个balanced独立测试writer任务，主会话接产品服务端/SDK；不是只让balanced提建议。复用既有repos API的显式project读，真实mdt+认证workspace+非空daemon、同一repeatable-read/read-only快照及现有workspace-scoped查询，输出身份descriptor而非raw resource_ref。SDK新方法核scope/字段存在/唯一ID/自洽，禁redirect/1MiB/完整严格JSON；无query旧API/SDK/head历史不变，CUSTOM #168/M11=21。
- 作者真实HTTP 1FAIL→1PASS，真实矩阵11/11（10leaf，含SDK→MDT→HTTP→DB）；独立strong发现大小写别名P2，balanced补3失败leaf真实RED2，主会话按canonical键/descriptor exact六键根修GREEN2 25/25（23leaf），strong关闭P2、限定静态完成，无剩余确证finding。动态并发快照race未验证。中间作者manifest未全pre-run已披露，P2及最终独立已每条先pin；不倒签历史。详见[本片报告](validation/current-bindings-20261025T034807Z-report.md)。
- P2后非作者balanced最终治理828/828、claim13/13、daemon72P/1 Windows权限SKIP，PASS leaf749/10/67，均exit0/每条原库未变/锁session0/精确资源清理/11源码匹配；DB权已释放。宿主最终只读核原137表/6228行、82审批ID/hash与13条本轮before/after共同一致，共22对已知新库/role实际不存在；四包vet exit0。原库HOLD/missing41/extra40不解除，82不是83恢复。
- 旧claim strong单独仍INCOMPLETE、暂无确证新finding；明确未尽agent/Builder rebind、terminal settlement/system cleanup SQL、wakeup管理/注册事务，不借新metadata组件完成替代。
- 这只是当次平台DB元数据，不证明task/project claim、本机路径/进程、新鲜度、控制域或activation；未接消费或启动Agent。当前仍普通BUILD/in_progress、0/49、5major unresolved，无Gate3/commit/push/部署。下一片完整可信claim/project和逐repo本机事实比较，之后才隔离/activation/防降级/T消费/永久派发；本节优先，下方均前段历史快照。

## 2026-10-24 新授权：仅新可丢弃库恢复 BUILD（前段）

- 用户明确授权保留原库/事故证据不动、另建可丢弃隔离测试库继续。原库拒跑与旧入口 `AIFI45_DB_HOLD` 保持，原事故证据未改；保留事故后82条不等于恢复原83条，missing41/extra40仍在，未补造/清除历史。
- 新版本化入口 `multica/scripts/aifi45-db/run.mjs` 每命令schema-only新库/受限role，真实空表/身份/原审批拒读，原表原行备份与137表内容比对，逐条锁/其它session=0，OID/owner/marker清理后catalog确认不存在。claim fixture自建user/member，不借旧残留；CUSTOM #167/M11=20。
- Node守卫6/6，strong首轮两finding经真实纯Node RED→GREEN后限定runner静态PASS；最终非作者balanced3：治理817/817、claim13/13、daemon47PASS/1 Windows权限SKIP，均exit0，每条原库137表/6228行摘要与82审批ID/hash不变、0锁/0其它session、临时库/role已清，DB权已释放。中间批次与首次失败保留，不把旧执行追认为最终源码。见[新库恢复报告](validation/disposable-db-20261024T162608Z-report.md)。
- 旧claim锁序审核仍INCOMPLETE；新runner审核不替代它。完整TC0/49、5major、消费关闭、BUILD/in_progress保持，不Gate3/commit/push/部署。下一片仍为每repo当前descriptor及完整claim/隔离/activation/防降级/消费/永久派发恢复。
- 下方“STOP/等待授权”是事故时历史快照；新授权只允许本节的新库，不解除原库HOLD，也不自动接受82为原历史基线。

## 2026-10-24 STOP：扩大回归历史事故（事故时快照；原库HOLD仍有效）

- 独立治理817/817、handler claim13/13、daemon47PASS/1环境SKIP虽然exit0，批后历史83→82：41原ID缺失/40新增/0原行改动。原42保护ID全在、整行hash与本轮开始相同；缺失另外41已映射到CR-9002/9006/9008旧fixture。源码5/5与作者manifest一致，不是源码漂移；不可据全绿验收。
- 源码显示resetCR/resetGateProjection按cr_id删approval_record，而cleanup不清该表；主会话错误扩大测试范围且只有hash而无原始行备份。已停止所有DB测试/写入和后续接线，只读保存完整差集与事后approval_record原行导出；未伪造恢复/删新增/重建旧ID，锁0/session0已释放。
- 需要人工提供原始备份路径，或明确授权保留原库现场、另建可丢弃隔离测试库；未授权前不写原库。strong仍INCOMPLETE，0/49、5major与消费关闭保持，BUILD/in_progress不推进、不commit/push/部署。详见[事故记录](validation/claim-build-20261024T153817Z-incident.md)。以下claim记录为事故前组件过程，不是当前安全验收结论。

## 2026-10-24 task claim runtime归属（事故前组件过程）

- 继续已批准普通BUILD，普通实现归主会话；并行只读claim/每repo调查已完成。新增带generation的StartTask由真实DaemonAuth身份对照当前runtime归属，同一事务runtime锁→task claim锁，拒外来首次/重投与空daemon，PAT兼容但不当可信绑定；无新迁移/receipt/消费。实际RED是同workspace外来合法mdt拿精确claim返回200；作者GREEN3/3含实际PG锁等待后归属变更拒绝、既有claim13/13。见[claim组件报告](validation/claim-build-20261024T153817Z-report.md)。
- 跑handler回归前，fixture改每进程唯一email/slug、setup单事务、仅exact-owned ID清理；全83历史ID/整行hash不变。2026-10-24T16:07:13Z锁0/其它session0后交balanced唯一DB执行权；主会话/strong不并跑DB。CUSTOM #166、M11共19行；strong首轮INCOMPLETE已同会话补全，balanced扩大回归与最终释放待回，不提前计PASS。
- 下一片每repo当前descriptor可复用平台资源构造器/API；当前project/完整claim、每repo绑定/隔离控制域/不可删activation/legacy防降级/T消费/dispatch恢复仍未闭合。0/49、5major、消费关闭、BUILD/in_progress保持；不Gate3/commit/push/部署。历史快照中的“下一步”以本节为准。

## 2026-10-24 签名 revoke / 前驱 CAS（前段快照）

- 详见[T撤销续建记录](../../../tools/changes/2026-10-22-aifi-45-authorized-execution/resume-revoke-build-20261024.md)。按用户纠正，普通实现归主会话，不为展示三档另派strong作者；先前强作者已保留成果/失败记录并安全交接，独立审核保留。T数字精度P2由主会话真实RED/GREEN修复，原model请求历史不改、actual仍unknown。
- M真实Auth revoke五字段请求/21字段签名，CR锁追加execution/reject历史+精确record-ID CAS，同事务rollback；exact actor/raw replay在新前驱检查前且不补head，终止历史拒指针回滚再签。head单repeatable-read快照核revoke/initial前驱；旧initialGET/replay不复活。语义增量13、旧23联合29；CUSTOM #165/M11共18行，无新migration/预算表。
- 非作者strong限定静态PASS；balanced以当前T修复后快照独立治理550/550、实际router14/14、拒消费2/2、真实HTTP→临时trustroot→Node3/3，exit0/0skip；T218=217P/1EPERMskip。主会话vet exit0，sqlc v1.31.1重复生成78文件raw/LF全部不变；scoped格式/语法/diff-check通过。不相加重叠事件，不声称全M suite/race或生产安装。
- 完整83条历史前后ID/hash不变、新残留0；13:28:09Z锁0/其他session0释放，随后无DB测试。四质量/binding、main/原HEAD/staged0保持。完整TC仍0/49、M17未整体验收、5major未关闭，BUILD普通模式不变。
- 下一步可信DB task claim、每repo当前绑定/隔离控制域/不可删activation/legacy防降级/T消费与永久派发恢复仍未闭合。M不凭head或静态签名启动Agent；无commit/push/Gate3/部署/真实CR。原12份sqlc仅EOL改写另留证据，不能恢复覆盖既存逻辑修改。
- 隔离环境已解阻并实测：`/etc/wsl.conf` 加 `[boot] systemd=true` 并重启后，rootless默认cgroupfs路径下真实拿到 `cpu.max=25000 100000`、`pids.max=16`（第16进程fork失败）与 `memory.max=32m` 下 SIGKILL（512m正例对照exit0/oom_kill=0）。专用库83行聚合`ced5ac21…`维护前后一致，3容器原ID恢复、数据卷保留。遗留：`podman machine list` 仍显 Running:false（就绪检查报 ssh error，疑与锁/Podman Desktop竞争，未证），容器无自动重启，重启后需 `wsl.exe -d podman-machine-default` + `podman start <原ID>`。详见 T `validation/cgroup-authorized-20261024T141533Z-maintenance-result.md`。资源强制执行不等于准入，消费仍关闭。
- 自动恢复已落地：3 容器 `restart=always` + 已启用的用户级 `podman-restart.service`（此前被拒因 `/home/user/.config/systemd` 为 root 拥有，已修），发行版重启后容器自行回到 running。`podman machine start` 仍 exit125（状态文档 rename `Access is denied` 在 podman 进程内部；同名临时文件 20/20 与副本 200/200 均成功，删文档则不重建），外部不可修。WSL 会回收空闲发行版，已恢复 Podman Desktop 并加本地保活会话（未全局 shutdown）。sshd/连接/状态统一 59669。隔离 PoC 重跑 exit0、`resourceLimitsEnforced:true`。

## 2026-10-24 分层恢复与 initial current-head（前段快照）

- 按用户要求真正分层委派：strong负责M核心TDD实现及另一个非作者strong代码审查，balanced负责真实Auth/隔离DB与独立复跑，economy负责文档/Skill核查。配置/委派/actual unknown及各轮证据统一见[T本次恢复记录](../../../tools/changes/2026-10-22-aifi-45-authorized-execution/resume-tiered-build-20261024.md)；未改业务质量配置/Gate/历史requested。
- 第一段已实施：CR `execution_authorization_head_id` 指向独立 approval_record.id，同原初始签发CR行锁事务提交；新真实DaemonAuth `/execution-authorization/head` 仅从持久化指针回读并校验scope/当前project/签名/原payload/source。无默认、FK/cascade、索引或backfill；exact replay/ACK/新历史不能补写head。实际router缺signer明确503，旧历史GET语义保留。专用隔离库671/642，sqlc v1.31.1离线生成，CUSTOM #163–164登记，后者仅6测试文件的精确拥有性fixture清理。非作者最终组件复跑治理174/174、实际router5/5、拒消费2/2，exit0/0fail/0skip；strong静态PASS。42条baseline历史逐条保留、新残留0；不等同完整TC。
- 两轮真实HTTP RED分别为新GET404→200、默认关闭router404→503。独立strong随后发现负零P2，作者用repair_limit与敏感动作limit的原始`-0`重现POST201→GET409，最小修复按精确整数比较且不改签名字节；补配置化实际router200、并发单head与丢响应重放/精确fixture清理。证据 `validation/initial-head-report.md`、`initial-head-p2-report.md` 与新旧独立manifest，未覆盖旧失败。
- 第一段组件通过不等于可信完整head/撤销/claim或准入；P2后最终分层复核见T恢复记录。**完整TC仍0/49，M17未整体验收，5major未关闭，BUILD/in_progress普通模式保持**。实际隔离、不可删activation、每repo当前绑定、签名撤销/扩展、DB claim、T消费与永久派发仍未实施闭环，T继续 `EXECUTION_CONSUMPTION_REQUIRED`，M不依head响应启动Agent；不commit/push/Gate3/生产/真实CR。

## 前轮 trust root 安装与只读核验（历史组件，非隔离证明，ADJ-AIFI45-M002/003）

- **当前运行路径**：`daemon.handleTask` 已接 `prepareClaimedPipelineTask→Client.InstallExecutionAuthorization(ctx, store, crID, workspace)→verifyInstalledExecutionGrant`。真实 crctl 由生产 Client 自行启动，现有 controlled-shell resolver 解析 node/mjs；输出、时间、env 受控。新合同最终仍 `EXECUTION_CONSUMPTION_REQUIRED`，静态成功不启动 Agent、不写 receipt；legacy 保留。
- GET 路由由生产/测试共用 `MountDaemonExecutionAuthorizationRoute`。新增真实 Auth + membership→隔离DB→真实 DB-backed mdt/DaemonAuth→安装→crctl 的只读测试，不再只靠注入 context；旧组件用例仍是组件证据。
- source 原 bytes/digest/bindings、公钥 ID、签名、workspace/CR 在安装前核对；HTTP 有界且不跟 redirect；硬链接不覆盖，根身份用打开句柄 Stat 冻结（Windows 路径版 Stat 惰性 ID 的第一次修复仍失败，根因修复后换根 20/20）。目录 0700/文件 0600 与身份 pin 不是同 UID Agent 隔离证据。
- **最新回归**：governance `-run . -skip '^TestReconcileLiveGitHub$' -shuffle=45045` 606/606；cmd/server 6/6；daemon 36=35P/1S（Windows 目录 symlink 权限），均 exit0。实际动作与命令存 `preflight-regression.json`，模型分工/RED/边界见 `preflight-evidence.md`；588、598、581 等保留为历史不同批次，不混算。
- **未接**：不可删除 activation、current-head/撤销/可信 DB claim、每 repo 当前身份、独立域绑定、T 消费事务、永久派发/wake/TaskService；实际隔离 executor 未接产品路径。M002 保持 `resolved:false`，完整业务 TC 仍 0/49；不提供任意 nonce 代签端点。

- change `2026-10-22-aifi-45-authorized-execution`，原生STDD、非CR开发流程。Gate1原文“确认这份 Gate 1”、Gate2“确认 Gate 2”由原生CLI登记；用户选“普通模式”，long_range.enabled=false/mode=normal，CLI推进BUILD/in_progress。
- 用户后续“采纳你的建议，继续别停下来等指令”并再次“继续”，允许已采纳的来源/可信绑定补正，不重问同方向；不是full_auto/扩权/Gate3。原Gate evidence不改，major验证未闭环仍resolved:false。
- 真实源码sibling `C:/Users/GOBAO/Downloads/AI/multica`，不是知识库记录目录。本仓2 code/2 agent spec、design/test-plan及原生Human View；7REQ/17SC/17TC/17CP，P0=12/P1=5。**完整业务TC/切片完成均0**，组件数另记。
- 跨仓协议唯一源：[T wire-contract](../../../tools/changes/2026-10-22-aifi-45-authorized-execution/wire-contract.md)；当前进展/风险见[T Phase Context](../../../tools/changes/2026-10-22-aifi-45-authorized-execution/phase-context.md)与[组件证据](../../../tools/changes/2026-10-22-aifi-45-authorized-execution/build-evidence.md)。不另复制预算/授权引擎。
- Gate2设计不变：原始人类请求+字段映射，T先receipt/M后幂等派发，准入消费不退款，当前head撤销+有界收尾，adoption跨run，最后修复可验证交付，旧CR不静默迁移，Inbox唯一+at-least-once恢复。

## 组件现状

- initial handler复用approval_record，CR行FOR UPDATE、资源UUID去重排序FOR SHARE；14语义字段+原repo/coordinator两selection逐项核版本，六字段descriptor冻入签名，原bytes/actor/project幂等返回原包，不因改resource_ref重签/清零。重复JSON键、C1控制、敏感scope ID唯一已实际RED→GREEN。execution不进入旧pending/ACK推进。
- 同生产Mount接真实middleware.Auth+RequireWorkspaceMemberFromURL，router的workspace crs子路由总挂新入口；contract/nil service默认503。主线程隔离DB独立 **RUN85/PASS85/FAIL0/SKIP0/exit0**（原Auth/Node59+manifest26），覆盖真实JWT owner/member、无token伪header、跨ws、503无mint、真实task_token拒绝；Go→真实Node正例/重序列化篡改负例均实际跑通。manifest最初直接GREEN未编造RED；后续secret-canary/非规范hash及case-alias键有实际行为RED，UNC改诊断不算曾接受非法路径。作者广选择74/74另含旧回归，勿混计。cloudPAT依赖真实Fleet verifier，本轮未测。历史完整governance首次581RUN/578PASS/3FAIL/0skip/exit1保留；MDispatch现已在本change稳定复现并修复同名fixture/ownID不存在时清理空集的顺序缺陷，另PG session lease阻断同DB测试进程互踩。新增顺序反例实际SQL23505/3层FAIL、lease新断言实际1FAIL后修绿；双进程各10轮140/140。最新扩大588/588、0fail/skip/exit0（显式ownID缺失前态加强后-shuffle=3，显式排除LiveGitHub一个顶层）。原始首次错误上下文缺失，不反推全部同源；LiveGitHub未重发PAT，排除绿色不代称全量PASS。
- 完整pkg/protocol主线程58/58、0skip/exit0；UNC/空hostname四实际失败和v1不支持zone一实际失败后修绿，普通IPv6/SCP保留；handler只加omitempty元数据，不收紧CRUD。描述符不证明远端clone、本机realpath或当前freshness。
- daemon保留project/resource ID，用真实Task.ProjectID筛新policy snapshot根，缺身份/多根/config拒绝；作者有字段补全后的5个行为失败再修绿。主线程两个Root顶层+子例独立8/8、0skip/exit0；Source=snapshot不是fresh绑定，真实current-proof签发尚未实现。实际child虽过滤MULTICA_*、独立config root，仍同UID/HOME可读daemon profile token；只读核无现成OS隔离executor/profile：process-group/JobObject仅生命周期，runtime profile仅command，Codex配置不隔离凭据。整daemon+child同一VM/container仍非两者隔离；不把private stdio/同UID0700/新flag当证明，不建任意nonce代签API。
- core通知主线程独立25/25、desktop gate18/18，0skip/exit0。新policy confirmed、稳定workspace ID和attempt token隔离late失败、web error释放、mute/focus复查均回归；legacy void保留。作者相关100/100及两侧typecheck/ESLint通过，未代证server/mobile/GC/重启/OS实际展示。历史desktop全量673 PASS但package解析exit1不是全量PASS。
- **用户本轮决定已执行推进**：真实CLI/临时镜像隔离PoC依赖已授权，固定Codex0.163.0官方release SHA、本地Alpine digest脚本已入库；两次下载超时保留，原生curl完整下载/SHA/tar/镜像构建已过；真实启动曾因crun memory.max缺失失败。授权调machine systemd后控制器委派成功但WSL API proxy pipe失效，已完整回退并恢复三容器/专用DB（身份复核）。最终PoC exit0：真实`codex-cli 0.163.0`、六项边界检查、`resourceLimitsEnforced:false`、资源定向清理；CLI/canary已真实执行，但CPU/内存/PID限额未强制，不接daemon任务/claim，准入仍关。MDispatch依前项在本change处理、不另立项。
- T已撤回未具current-head/revoke/claim时的消费放行，删除独立receipt writer；公开CLI实际1FAIL后修复，最新授权104/104。现fresh proof/source仍EXECUTION_CONSUMPTION_REQUIRED，不造receipt，预置receipt不可激活。M永久logical_dispatch_key/adoption、平台→daemon→T仍未通。
- CUSTOM #154–159、M11索引/位置与前端清单由主线程按实际结构登记。新增仅测试harness/共享fixture与隔离实验脚本；无migration或真实仓库commit/push。

## 未完成与隔离纪律

- pinned manifest startup接线已实现（两个显式flag、raw SHA/64KiB/exact四键/秘密安全诊断），未实际配置保持503；主线程router回归1/1与server build exit0。manifest不是授权或凭据隔离；不能把fixture signer/context或route子组件代证cmd/server→T CLI→wake→TaskService。T source/proof子集虽通过，仍拒消费；T kernel同SHA切branch窗口已用自有原HEAD.lock+detached helper nativeCAS修到组件，最新主线程T三文件显式TAP联合162选中/161PASS/0FAIL/1文件symlinkEPERM/exit0（AUTH104/exec41/durable17），另旧grant14/14、0skip/exit0，deferFinalize/never-applied/恢复token及终态已收口到组件，不以此或事后补偿当完整业务闭环。
- pipeline_run无直接project_id；node detail/execution_context需保留execution字段，活动node-run唯一键不足永久幂等。logical_dispatch_key、adoption和四阶段实际恢复未实施；CONCURRENTLY索引拟独立迁移，不建第二预算。
- server Inbox pending/delivered、三类业务通知、mobile/GC/重启恢复未完成。完整49TC、14类失败、隔离三路径、安装/pin/权限一致性与Gate3均待验收。
- 仅本change容器stdd-aifi45-20261022-pg（ID666bfec52ac3，label同change），127.0.0.1:55432，DB stdd_aifi45_20261022/user stdd；既有迁移670条/最新641_issue_context_refs_gin。每次核label/端口/DB/user，再内存构造DATABASE_URL；GOPROXY=off，凭据不打印/落盘。共享multica实例不动，缺DB/依赖/零选中/skip不当PASS。
- Gate2前proposal validate/canon verify各2/2是历史结构证据，最新两仓validate/canon verify均exit0（proposal各2/2），T2/M1文件级AND警告；独立结构核49SC/TC/CP一一对应、AND每SC max4通过，原生RUN Human View已重生。运行二进制/开关/安装版本/真实试点未知，不用源码SHA冒充部署。
- 普通模式继续，不做真实CR/生产/破坏性数据/全局权限修改/模型支出/commit/push/STDD产品修改；真实CLI/临时镜像PoC依赖已获授权，不扩大其他授权，不自行批准Gate3。

## 2026-10-25 本片收口（签发上限 + trust-root 实证）

- **签发上限**：`cr_execution_binding_issue` append-only 无回收 ⇒ 同一 head 的新证明上限 256（按 `(workspace,cr,grant_digest)`，超出 429 `EXECUTION_BINDING_LIMIT_REACHED`），同 challenge 重放不受限。strong 两轮判定后**已放弃"硬上限"表述**：RR 快照在取 advisory lock 之前建立，真实边界是 `256 + 并发签发者数`；它把无上限增长变成有界增长，精确上限需 SERIALIZABLE+重试或跨事务 session 锁（未实现，已写进注释）。
- **trust-root 实证**：同 UID 可替换公钥（`same_uid_rewrite_possible:true`），容器只读 bind 下 9 向量全未成功、新路径写入 EROFS、公钥摘要未变、无控制通道、无宿主工作卷。只证明边界可成立，**未**把 daemon 执行路径容器化。
- **最终回归**：final6 独立（治理 904/903/0/1 = 817 leaf、handler 13/13 = 10、daemon 125/124/0/1 = 115），final7 冻结仅含注释/探针断言变更（`issuelimit-green4` 25/25 = 22 leaf）。原库三条命令均 137 表/6228 行/82 审批无漂移，`sessions=0`、`locks=0`。
- **仍未变**：消费/准入关闭，旧 claim 锁序 INCOMPLETE，业务 TC 0/49，5 个 major 未关闭，原库 HOLD，Gate3/提交/推送/部署未授权。

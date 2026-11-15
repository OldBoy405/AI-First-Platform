# Phase Context — AIFI-45 授权内自治执行

## 2026-10-25 服务端绑定签发（当前BUILD；消费仍关闭）

- T 早已有 `requestExecutionBinding`（challenge/stdin/签名校验）；服务端签发侧之前为空。本片补 wire §3.6：[M报告](../../../multica/changes/2026-10-22-aifi-45-authorized-execution/validation/binding-issue-20261025T081500Z-report.md)。
- 关键约束：temp 测试库是冻结原库 schema-only 克隆，新表必须靠 runner `-migration=`；而生产迁移正常跑。**签发不等于准入/消费**：进程号来自 daemon 转述，平台不可验证；daemon 私有 stdio 中继与 T 消费事务未实现，`EXECUTION_CONSUMPTION_REQUIRED` 未解除。
- strong 两轮：首轮 2×P1+3×P2（task↔CR 关联、代次不唯一、null、非canonical、冲突重读未释放事务）→ 复检 F2–F5 CLOSED；F1 残余（`task.cr_id` 可被自报覆盖）→ 首次写入胜出 + 删除重复调用 → **CLOSED**。首次 CR 来源仍未证明。
- 最终 13 项冻结独立回归：governance 900/899/0/1（814 leaf）、handler 13/13（10）、daemon 125/124/0/1（115）；原库 137 表/6228 行/82 审批五轮均一致，vet exit0。业务 TC 仍 0/49。
- **跨语言互通已实证**（REQ-AUTH-004/SC-AUTH-010）：Node 子进程调 T 真实 `requestExecutionBinding`，服务端真实 HTTP envelope 被接受且 20 键；篡改 payload（保留签名）被拒。需要 `AIFI45_TOOLS_ROOT`，未设即 Skip（不算证明）。

## 2026-10-25 终态代次fence（当前BUILD；M联动进行中）

- 不停在普通组件结束，按用户既有继续指令进入M terminal callback。公开MDT旧代次fail/complete误终止新代次均真实RED→GREEN，原CAS位置增加可选runtime/generation/认证workspace/daemon谓词，不加新锁序；legacy无字段暂保留，不假称activation防降级完成。
- strong 四轮：fail 1项P2 → daemon F1–F4（早退降级、缓存串代、single-flight丢代、缓存耗尽）→ N1（PAT daemon 被误升级→403）→ N2（strict 无fenced时不发终态，含解析出错残余），**均CLOSED**。实现要点：tuple 随 run 的 context（非taskID缓存）、single-flight 按 `deliveryKey`、outbox record v3、仅 `mdt_` token 升级qualified。
- 原生sqlc离线生成有前字节archive，规范化仅agent.sql.go变；make离线lookup失败、第一次ambiguous id、三次runner参数位置错误、两次fixture唯一键冲突均保留，不算业务RED。本片共27条runner命令，每条独占nonce库/role，五轮原库137表/6228行/82审批与冻结共同不变、session锁0。原库事故HOLD不解除。
- final5 冻结独立回归：governance 879/878/0/1（795 leaf）、handler 13/13（10）、daemon 125/124/0/1（115），vet exit0。CUSTOM #170/M11=23；[M报告](../../../multica/changes/2026-10-22-aifi-45-authorized-execution/validation/terminal-fence-20261025T060611Z-report.md)。
- daemon sender/outbox尚未携带代次；retryable fail CAS前Composio POST副作用明确待收口。当前不是完整terminal安全验收，旧claim锁序INCOMPLETE、完整0/49、5major未关闭，T消费仍EXECUTION_CONSUMPTION_REQUIRED。无Gate3/提交/推送/部署。

## 2026-10-25 M当前task/project claim（当前；消费继续关闭）

- 用户要求持续推进且非必要不停。wire §3.4明确并接M既有status GET显式claim读面、SDK及daemon根前实际回读；MDT真实认证scope/只读RR/冻结queue project与live issue/project/runtime/代次/active状态，首片issue-backed-only。shared helper先核微秒token再Go解析、DID拒C0/C1；旧无query/path保留，T源码与签名字节不变，不把快照当持续freshness/隔离/签名/准入。
- 两个balanced实际写HTTP/SDK矩阵与真实SDK→MDT→DB正反贯通，强审时间P2真RED→修后HTTP21/21、SDK/前置39/39；新claim失败旧callback实发1次真RED→抑制。作者治理851/851（770leaf）、daemon112P/1 Windows权限SKIP（106leaf），中间SDK0RUN编译错保留且不计RED；CUSTOM #169/M11=22。
- 12条执行各pre-run pin/后核、原137表/6228行/82审批共同相同、锁session0/精确资源清；19项raw/LF+原字节archive先冻结再独立。非作者三组851/851、13/13、112P/1 Windows权限SKIP（leaf770/10/106），各自19项先pin/后同、原库/资源逐条安全；DB权释放。caller/server+SDK限定strong完成无新增确证finding，宿主只读最终核15条基线共同未变、37对已知库role不存在，四包vet exit0。[M本片报告](../../../multica/changes/2026-10-22-aifi-45-authorized-execution/validation/claim-project-20261025T052646Z-report.md)。原库HOLD/missing41/extra40保持，82不是83恢复。
- server+SDK限定static完成/时间P2关闭；旧claim锁序仍INCOMPLETE。终态全链callback/outbox确证缺代次CAS，现只封新claim失败分支，下一片继续；完整0/49、5major与消费/Gate3/commit/push/部署不推进。

## 2026-10-25 M当前资源元数据读面（前段；消费继续关闭）

- wire §3.3落实当前平台资源回读的最小读面，不把head改成资源准入：既有daemon repos API显式project查询、真实MDT/认证workspace/同一只读快照，新增descriptor字段；SDK新方法核scope/存在/唯一ID/自洽并禁redirect/限1MiB/严格完整JSON。无query旧API/SDK/head/历史不改，无新schema/nonce/receipt，T源码与签名字节未动。
- 主会话负责产品，两位balanced实际写HTTP/SDK测试；真实HTTP 1FAIL→1PASS/矩阵11/11后，strong发现大小写别名P2，balanced补3失败leaf→主会话canonical键根修25/25（23leaf），strong关闭P2、限定静态完成，无剩余确证finding，CUSTOM #168/M11=21。中间作者manifest缺pre-run pin已披露；P2及最终11文件冻结、逐条pre-pin不倒签。见[M本片报告](../../../multica/changes/2026-10-22-aifi-45-authorized-execution/validation/current-bindings-20261025T034807Z-report.md)。
- P2后非作者balanced最终治理828/828、claim13/13、daemon72P/1 Windows权限SKIP，leaf749/10/67、exit0；原库/精确资源/锁session及源码逐条安全，DB权已释放。宿主最终只读核原137表/6228行、82审批及13条before/after共同一致，共22对已知库role不存在；四包vet exit0。原库HOLD/missing41/extra40保持，82不是83恢复。
- 旧claim strong仍单独INCOMPLETE，明确未尽agent/Builder rebind、terminal settlement/system cleanup SQL、wakeup管理/注册事务；新读面动态snapshot race未验，不用metadata/runner/静态结果替代。
- 当前仍普通BUILD/in_progress、0/49、5major unresolved、EXECUTION_CONSUMPTION_REQUIRED，不Gate3/commit/push/部署。元数据不能证明完整claim/project、每repo本机事实/隔离/activation；下一步仍这些绑定与防降级/T消费/永久派发，而非用读面开放Agent。下方为历史快照，以本节为准。

## 2026-10-24 新授权：仅新可丢弃库恢复 BUILD（前段）

- 已获用户明确授权：保留原库与事故证据不动，另建可丢弃隔离测试库继续。原库/旧入口HOLD不解除；82只是事故后现场，不恢复原83，missing41/extra40不抹去，不补造签名或删新增。
- M新增版本化 `scripts/aifi45-db/run.mjs`，逐命令schema-only新库/受限role，空表/真实身份/旧审批拒读，原行备份、137表摘要与82审批ID/hash比对、每条0锁/0其它session、精确OID/owner/marker及末catalog清理证明。claim fixture改自建user/member；CUSTOM #167/M11=20，T源码/原签名字节未改。
- 最终非作者balanced3治理817/817、claim13/13、daemon47PASS/1 Windows权限SKIP，均exit0，每条原库未变且新库/role已清，DB权释放。Node守卫6/6；strong两finding修复后限定runner静态PASS，不替旧claim锁序INCOMPLETE。见[M新库恢复报告](../../../multica/changes/2026-10-22-aifi-45-authorized-execution/validation/disposable-db-20261024T162608Z-report.md)。
- 完整TC0/49、5major、消费关闭、BUILD/in_progress保持，不Gate3/commit/push/部署；每repo当前descriptor、完整claim/project、隔离控制域、activation、防降级及消费/永久派发仍待实现。下方事故时“STOP/待授权”不覆盖本节，仅新库获许，原事故HOLD与历史事实仍保留。

## 2026-10-24 STOP：扩大回归历史事故（事故时快照；原库HOLD仍有效）

- M独立扩大治理/handler/daemon批次虽exit0，批准库历史83→82：missing41/extra40/changed0；原42受保护ID及本轮开始整行hash42/42仍一致，另外41缺失已映射到旧测试CR-9002/9006/9008。source5/5与作者manifest一致，非源码漂移；全绿不抵消安全失败。
- resetCR/resetGateProjection按cr_id删除approval_record、cleanup不清该表，是已核破坏性fixture边界；主会话扩大选择前未识别、只有hash无可还原原行备份。停止所有后续DB测试/写入和接线，只读保全差集/当前原行，未重建旧ID/删新增；锁0/session0已释放。
- 现需用户指定原始备份，或授权保留原库现场、另建可丢弃隔离测试库；未授权前不写原库。strong仍INCOMPLETE，完整TC0/49、5major、消费关闭、BUILD/in_progress与Gate保持，不commit/push/部署。详见[M事故记录](../../../multica/changes/2026-10-22-aifi-45-authorized-execution/validation/claim-build-20261024T153817Z-incident.md)。历史“下一步”不再构成继续DB执行许可。

## 2026-10-24 M task claim runtime归属（事故前组件过程）

- 用户要求持续主线、能并行则并行；主会话继续普通实现，balanced只读调查claim/每repo接缝完成，不另派普通作者。M带generation的StartTask补真实认证daemon→runtime归属→同事务claim校验；实际RED外来同workspace合法mdt拿精确claim返回200，修后作者3/3（父1+子2，含实际PG锁归属竞态）与既有claim13/13。T源码/原签名字节不改。详见[M claim报告](../../../multica/changes/2026-10-22-aifi-45-authorized-execution/validation/claim-build-20261024T153817Z-report.md)。
- handler harness先改每进程唯一身份、setup单事务、exact-owned ID清理；83历史ID/整行hash完全不变，2026-10-24T16:07:13Z锁0/其它session0后交balanced唯一DB执行权。strong首轮INCOMPLETE同会话补全中，balanced扩大回归/释放待回，不据局部无finding计PASS；CUSTOM #166/M11共19行。
- 下一片回读每repo当前descriptor；完整claim/project/隔离控制域/不可删activation/legacy防降级/T消费/永久派发恢复仍未闭合，旧generation缺失路径不能提供新合同可信claim。0/49、5major与消费关闭保持，不Gate3/commit/push/部署；历史节的“下一步”服从本节。

## 2026-10-24 签名 revoke / 前驱 CAS / T整数 P2（前段快照）

- 最新证据与模型执行纠正见[撤销续建记录](resume-revoke-build-20261024.md)。不把“使用分层”扩大为三档各派作者：原强作者已安全交接，后续普通实现由主会话承担，strong只保留必要非作者审核；T数字精度P2已由主会话真实6RED→8GREEN/调用者11GREEN修复，strong独立F1关闭，原签名字节不变。
- M签名revoke/独立record-ID前驱CAS/终止历史及repeatable-read head已实施；T按purpose精确21字段、来源initial14/revoke5，显式只读source-check，revoke非check在challenge前拒绝。M13文件语义增量、联合29，CUSTOM #165/M11共18行；不开放claim/消费，生产daemon仍取initial历史。
- 非作者P2后复跑：T218项=217P/0F/1 Windows file-symlink EPERM SKIP；M治理550/550(count2)、实际router14/14(count2)、拒消费2/2、真实HTTP→当前T CLI3/3，均exit0。全部是重叠组件事件，不累计整TC；M/T独立strong限定范围静态PASS。主会话vet/gofmt/语法/scoped diff-check与sqlc78生成物重生成raw/LF零漂移；原12份生成物EOL噪声单列，未当语义增量。
- 专用DB完整83条历史逐ID/hash前后不变、新增/删除/改动0，13:28:09Z锁/session0后释放；之后仅静态检查。四质量/binding保持，两仓main/原HEAD/staged0。完整TC0/49、5major未关闭、普通BUILD/in_progress保持，不Gate3/commit/push/部署/真实CR。
- 下一步核真实DB task claim/每repo当前绑定及保护控制域；activation、legacy防降级、T消费/永久派发/恢复仍未闭合，继续失败关闭。不会用任意nonce代签、mdt持有人、缓存head或0700假装可信准入。
- 资源隔离已实际执行并通过内核强制验证：`/etc/wsl.conf` 追加 `[boot] systemd=true`（`97fa04e3…`）后 `user@1000.service` 有效控制器 `cpu io memory pids`；默认cgroupfs下 `cpu.max=25000 100000`、`pids.max=16`（第16个进程fork失败）、32m下写200MiB被SIGKILL（137）而512m正例对照exit0/oom_kill=0。专用库83行聚合`ced5ac21…`与维护前一致，3容器按原ID恢复、卷保留。**遗留**：`podman machine list` 仍显 `Running:false`，容器无自动重启，重启后需 `wsl.exe -d podman-machine-default` + `podman start <原ID>`（已走通）；不声称CLI已修。详见 `validation/cgroup-authorized-20261024T141533Z-maintenance-result.md`。资源强制执行不能替代49条业务TC/可信claim/准入。
- `podman machine start` 仍 exit125：debug 日志显示失败点在写机器状态文档（`.tmp-…json→podman-machine-default.json` `Access is denied`），而用同名临时文件做20次原子替换、对副本做200次替换均0失败，关掉 Podman Desktop 后亦失败，删掉文档后 podman 判机器不存在且不重建（已回滚）——定位为 podman 进程内部 Win 侧实现问题，外部不可修。替代恢复路径：`wsl.exe -d podman-machine-default` + `restart=always` + 已启用的 `podman-restart.service`（此前 enable 被拒因 `/home/user/.config/systemd` 为 root 拥有，已修），实测发行版重启后容器自行回 running。WSL 约2分钟内回收空闲发行版，已恢复 Podman Desktop 并加本地保活会话；未做全局 `wsl --shutdown`。sshd/连接/状态已统一为 59669。
- isolation PoC 已按真实限额重跑 **exit0，`resourceLimitsEnforced:true`**（首两次因 API 不可达失败，保留且不合并计数）；其 boundary 仍写明 daemon task/claim/receipt 未验证。

## 2026-10-24 分层恢复与 initial current-head（前段快照）

- 用户要求继续 AIFI-45，并明确“使用stdd模型分层委派任务”。两仓有效配置已真实读取并保存 `validation/resume-20261024-config-models.json`；strong/balanced/economy 分别按用户级 model+effort 实际委派，含非作者 strong 独立代码评审。harness 三元组匹配请求，后端 actual 仍 unknown；未回改旧默认回退记录/业务质量配置。
- M 完成持久化 initial head 第一段：既有 CR 行锁事务保存历史+记录 id 指针、真实 DaemonAuth 只读 head GET、642 nullable UUID迁移与sqlc生成。无 backfill，旧 replay/ACK/较新历史不能重建或抢 head。仅专用隔离库671/642；不代表整套 current-head/revoke/claim/绑定已闭环。
- 真实公开HTTP RED→GREEN后，独立strong找出负零P2（POST201但head409）。作者已用两处原始`-0` HTTP重现再修复，保持payload/source原bytes并精确整数比较；补配置化实际router200、并发与丢响应重放、精确fixture清理。首轮原版绿色不作为修复版证据，P2后的分层复核状态以[本次恢复记录](resume-tiered-build-20261024.md)为准。
- T 本次真实三文件基线164项/163PASS/0FAIL/1 Windows file-symlink EPERM SKIP/exit0；M组件原始证据分别在 `initial-head-report.md` 与 `initial-head-p2-report.md`（M同change validation）。计数有重叠，不累计为整TC。CUSTOM #163–164/M11索引已登记（含6文件test-only精确fixture清理）。最新非作者组件复跑治理174/174、实际router5/5、拒消费2/2均exit0/0fail/0skip，strong静态PASS；仍非完整TC。
- **完整TC仍0/49、5major仍unresolved、普通BUILD/in_progress不变**。撤销/扩展链、DB claim、每repo当前绑定、实际隔离、不可删activation、legacy防降级、T消费/永久派发尚未闭合，继续拒绝消费；不自行Gate3/commit/push/部署或真实CR试点。下一段是签名revoke前驱CAS/当前head回读与T严格purpose分支；目前仅设计。

## 前轮 trust root 安装与只读核验（历史组件，非隔离证明，ADJ-AIFI45-003）

- **当前**：M 的生产 `handleTask→prepareClaimedPipelineTask→Client.InstallExecutionAuthorization→verifyInstalledExecutionGrant` 已接真实 crctl `--check --trust-root`。真实 Auth→隔离DB→DaemonAuth（DB-backed mdt，无 context/cache 注入）→安装→daemon 自行调用 crctl 的只读链通过。新合同即使静态检查通过也返回 `EXECUTION_CONSUMPTION_REQUIRED`，不启动 Agent、不写 receipt；legacy 保留。
- M 安装器在落盘前核 source 原 bytes/digest/bindings、公钥 ID/签名与 workspace/CR；有界 HTTP、不跟 redirect、硬链接不覆盖、文件类型/大小检查。根身份用打开句柄 Stat 冻结，Windows 换根真实 RED 后 20/20。0700/0600、路径 pin、env 过滤均不构成同 UID 隔离边界。
- **最新回归**：governance `-skip '^TestReconcileLiveGitHub$' -shuffle=45045` RUN606/PASS606/0F/0S；cmd/server 6/6；daemon 36=35P/1S（Win 目录 symlink）。实际逐测试事件和命令见 M change `preflight-regression.json`，说明见 `preflight-evidence.md`。此前 588/598 是历史不同批次，不改写其失败记录。
- T 代码本轮未改：授权 106/106；三文件 164=163P/1S（Win file-symlink EPERM）；旧 grant 14/14 为此前实际回归，本轮不冒称重跑。`--trust-root` 未声明仍 legacy；声明后四类材料共用根。
- **未闭合**：不可删除 activation、current-head/撤销/可信 claim、每 repo 当前绑定、独立域 binding 与 T 消费事务仍缺，实际隔离 executor 未接产品；因此 major 保持 `resolved:false`、完整业务 TC 0/49。不得以触发文本可删的合同当不可降级激活事实。

## 当前阶段与授权

- 原生STDD，不是CR开发流程；不注册、推进或改写实际CR。
- Gate1原文 **确认这份 Gate 1**、Gate2原文 **确认 Gate 2** 均由两仓原生CLI登记。用户选 **普通模式**；两仓原生推进BUILD/in_progress；thorough/task_type=code/complexity=17/preliminary，long_range.enabled=false/mode=normal。
- 用户随后原文 **采纳你的建议，继续别停下来等指令**，并再次要求 **继续**。可信绑定/来源补正已获采纳，不重问同方向；不是full_auto/扩权/Gate3/上线批准。保留原Gate evidence，T三个/M两个major仍resolved:false，技术验证闭环后才关闭。
- 真实源码：`C:/Users/GOBAO/Downloads/AI/tools`、`.../multica`；知识库`projects/{project}`仅记录。两仓`.stdd/binding.yaml`解析本change `2026-10-22-aifi-45-authorized-execution`。早期锁子任务误根导致“源码缺失”推测已撤回；outside-root工具限制不是物理不存在。
- 不执行真实仓库commit/push、生产部署/DB、CR迁移、全局权限修改、模型支出或STDD产品修改；仅真实CLI/临时镜像隔离PoC新增依赖已获授权，其他依赖边界不变。保留用户既有文档与tools原有.crctl。

## 权威与设计

- T canonical proposal、3 code/3 agent spec及wire-contract.md为跨仓协议归口；M 2 code/2 agent spec引用。proposal.md/specs/*/spec.md为原生渲染，不手改生成物。
- 全轮5能力/19REQ/49SC/49TC/49CP；T=12REQ/32TC，M=7REQ/17TC；P0=41/P1=8；SC高37/中12。**完整业务TC=0/49，完成切片=0**。
- Gate2确认：准入提交即消费、不退还、receipt恢复不重扣；累计6次/两次无进展、跨阶段/cycle继承，最后修复仍可验证交付；签名head撤销+失联不新准入；无时钟expiry；精确stop/resume CAS；T裁决、M永久逻辑根幂等/adoption；Inbox唯一+at-least-once而非物理exactly-once。
- 新合同opt-in，legacy不追溯阻断；已启用不能靠删字段/旧TTY/grant降级。不得新增第二预算/状态引擎、中央总账或全局通知去重账本。
- 当前original body=14语义字段+repository_selections/coordinator_selection。DB锁定资源与版本后冻结6字段repository_bindings/coordinator_binding进签名。label/可编辑graph不是授权；原bytes与已签payload不做CRLF规范化或重序列化验签；普通源码/文档解析hash先LF规范化。
- T静态--check始终check_only=true,bound/head/source=false；合法source+proof子集仍EXECUTION_CONSUMPTION_REQUIRED。真实消费未开放。

## 当前独立证据（组件，不是整TC）

- T授权边界最新主线程独立 **104/104 PASS、0 FAIL/0 SKIP/exit0**（约46.8秒）；已撤回不可信live放行并删除独立receipt writer。公开CLI新拒绝断言在旧实现实际1FAIL/exit1，修复后fresh proof/source仍因缺current-head/revoke/claim明确EXECUTION_CONSUMPTION_REQUIRED；预置receipt不能激活，HEAD不变。历史receipt104绿不算可信消费。
- **用户本轮决定已执行推进**：真实CLI/临时镜像隔离PoC新增依赖已授权；精确版本/官方SHA已固定，原生curl完整下载/SHA/tar/临时镜像构建通过；真实启动因crun memory.max缺失失败。rootless cgroup v2/cgroupfs/controllers=[]；授权尝试启用machine systemd后控制器委派成功但 podman machine WSL API proxy pipe 失效，已完整回退并恢复三容器/专用DB。最终PoC exit0：真实`codex-cli 0.163.0`、6项边界的`resourceLimitsEnforced:false`、资源定向清理；不接daemon任务/claim，准入仍关。MDispatch本change已稳定复现并修复同名fixture在ownID缺失时清理空集的顺序缺陷，公共setupRequirement复用修复；另PG session lease防同DB两进程互踩。两进程各10轮140/140，扩大588/588（仅显式排除LiveGitHub）。原始历史错误上下文缺失，不反推全部同源。
- T授权跨语言边界（含消费前）跨语言URL/UNC/实际C1 linked-worktree向量现27例；初轮19例实际12fail/7pass RED，另SCP两例、UNC尾一例、原authority一例有各自真实RED，再完整GREEN；包括SCP无用户名、空userinfo/password/query/hash、incomplete UNC、本机两根控制字符。正常linked worktree通过common-dir回主根。此前76版因旧probe fixture根未同步发生失败，仅修fixture，未放宽生产检查。
- M真实Auth同生产mount+handler/签名/Node互操作与显式pinned manifest loader，主线程隔离DB独立 **85 RUN/85 PASS/0 FAIL/0 SKIP/exit0**（原Auth/Node59+manifest26）；含真实JWT owner/member、无token伪header、跨workspace、默认/nil503、真实task_token拒绝，Node正例/保留签名重序列化负例实际执行。作者旧广选择74/74勿混计；cloudPAT真实Fleet verifier未测。扩大governance全包首次581RUN/578PASS/3FAIL/0skip/exit1，MDispatch001+其子例和真实GET GitHub用例失败；安全定向6/6及显式排除LiveGitHub一项的扩大580/580再跑转绿，未改代码/未定首次根因，不能称全量PASS。
- M完整pkg/protocol最新主线程58/58、0skip/exit0；UNC/空hostname四实际失败及不支持zone一实际失败后修绿。普通IPv6/SCP保留，v1不支持zone在两端明确拒绝。M handler原始context注入测试不代证真实Auth；新路由测试用了真实middleware.Auth+RequireWorkspaceMemberFromURL与隔离DB。startup两个显式参数→pinned raw bytes/精确四键manifest→RouterOptions注入已实现；主线程router公开面回归1/1/server build exit0。未实际配置，生产默认503；manifest不等于授权/激活/凭据隔离。
- M core通知主线程25/25、desktop gate18/18，均0skip/exit0；作者相关100/100和类型/ESLint通过。confirmed仅新policy，旧bridge不假成功、workspace稳定ID、attempt归属、web失败/超时/late/mute/focus已回归；server/mobile/GC/重启/OS实际展示未闭环。旧desktop全量673 PASS但package解析exit1，不能称全量PASS。
- T最新主线程显式TAP三文件联合162选中/161PASS/0FAIL/1 file-symlink EPERM SKIP/exit0（57151.3239ms）：AUTH104、exec-tx41、durable17；真实目录junction、reftable unsupported、busy/drift/split、main/linked原HEAD锁与helper回归执行。durable全文件17/17 PASS/0skip/exit0；一次lowercase lock模式空wrapper已丢弃不计。
- **新实证P1尚未关闭**：最后HEAD检查与branch CAS之间切same-SHA分支，A仍被推进。作者先补偿回退虽测试绿，主线程不采纳其为原子保证；仍可能被并发消费者观察。普通HEAD symref-verify+referent事务在Git2.54因duplicate HEAD失败；限定伪ref在stdin被bad-name拒绝；prepared hook的EEXIST也不能证明自己持锁，均未采纳。最新temp main+linked实验成立：parent自己独占原HEAD.lock并锁内verify，由同common-dir detached helper做native CAS，不自锁且原目录switch被拒。已用existing beforeApply接缝先落native/helper intent，保护恢复与新写，释放/定向helper cleanup先于finish，移除全局prune并核实例token/FD。退出调用已审统一deferFinalize、清资源后丢journal，恢复以实际token匹配native/recovery记录；applyStarted=false拒绝回滚，rolled-back/complete终态防二次回滚。真实SIGKILL全边界未验；空0字节/未知锁、缺失helper实例证据仍manual maintenance，不开放消费。
- 最新主线程旧grant选择回归14/14（0skip/exit0）；这与基础lock回归均不代证旧writer统一；legacy各scope仍不同，test还取OpWS。只读调用图已定位dispatcher共享guard/锁接缝，尚未改；没有可信activation record，不能把可删sidecar/单纯“grant文件存在”当永久激活事实。
- CUSTOM #154–157、M11和前端清单已按实际结构登记，主线程唯一编辑。详细历史及边界见[build-evidence](build-evidence.md)，当前快照以本段为准。

## 原生规格工具差异

- Gate2前两仓proposal validate/canon verify均exit0；canon verify各2/2仅proposal，不能代替spec/TC验证。结构检查曾核YAML/唯一ID/一一REQ-SC-TC-CP及AND每SC≤5；tools原2条AND聚合警告为validator整文件口径差异。
- extract-proposal空capabilities/错误what_changes、canon generate --type spec仅proposal为已核CLI差异，不改STDD产品。用原生canon.py::_generate_spec对本change显式output_dir渲染；最新AUTH/RUN Human View已重生。最新两仓validate/canon verify均exit0（proposal各2/2）；文件级AND警告T2/M1，独立YAML核19REQ/49SC/49TC/49CP唯一/一一对应、每SC AND max4、T32完整TC guards均通过。自写只读checker首轮错用shall键失败，按真实then键修正，不是规格失败。
- T32 CP要求exact完整顶层TC名+真实TAP成功行和fail/skip/todo=0。实测空匹配文件wrapper可报1 PASS但没有TC成功行，CP拒绝；ctx代码回显不是子进程证据。

## 接续

先读 wire-contract 与 M preflight-evidence/preflight-regression，再读两仓 pending/canonical/design/test-plan/tasks/slices。HTTP→daemon 安装与生产静态 crctl 调用已接，但不是可信准入。真实 Codex Linux CLI 的容器可见性 PoC 已获授权并跑通，**仅证明挂载/网络/canary 组件行为；resourceLimitsEnforced:false，未接产品任务隔离 executor**。同 UID/HOME 下过滤 MULTICA_*、私有 stdio、0700、独立 config root 均不阻止 Agent 读取 daemon 凭据；整个 daemon 和 child 同放 VM/container 不等于彼此隔离。下一顺序为当前授权 head/撤销/可信 DB claim 与每 repo 当前身份，再到独立域绑定与 T 消费/幂等派发；缺部署凭据/权限边界时继续关闭，不提供任意 nonce 代签 API。

DB仅本change容器stdd-aifi45-20261022-pg，ID 666bfec52ac3，label同change，127.0.0.1:55432，stdd_aifi45_20261022/stdd；每次先核身份，在内存构造URL，凭据不打印/落盘，GOPROXY=off。共享实例不动。核心单writer，协议与CUSTOM主线程归口；独立审查只读。普通模式继续，不等待已采纳方向重复确认，不自行Gate3。

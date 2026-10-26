# AIFI-45 multica — BUILD任务清单

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
- [ ] 1.2 与T AUTH-010联合定义原始bytes签名golden，先失败后最小实现，保留stage v1。
- [ ] 1.3 RUN-001～003/010真实认证入口、来源映射、新grant传输与ACK/消费分离（依赖T完整授权）。
  - 主线程真实Auth同Mount/handler/Go→Node选择59/59、protocol全包58/58、daemon Root选择8/8，均0skip/exit0。pinned manifest接线进行中；当前head/撤销与私有daemon凭据隔离未闭环，不代证整TC/wake/TaskService。

## 2. 永久逻辑根键、实际四阶段恢复（P0）

- [ ] 2.1 RUN-004/005永久logical_dispatch_key、原根/技术子链/adoption及context保留（依赖T修复receipt）。
- [ ] 2.2 RUN-006/007真实统一wake、四阶段入口与启动发现；余额0仍可验证已准入修复（依赖2.1）。
- [ ] 2.3 RUN-008/009旧run兼容、联合证据身份、生成/安装/pin配套（依赖2.2与T policy/registry）。
- [ ] 2.4 实际代码英文注释，CUSTOM.md按当时结构登记；schema/query/model/生成物配套，索引CONCURRENTLY独立迁移。

## 3. 最小通知与故障恢复（P0/P1）

- [ ] 3.1 NTF-001～004三类主动通知与业务/维护分流（依赖2）。
- [ ] 3.2 NTF-005～007同Inbox身份、pending/delivered、并发/崩溃恢复与客户端去重（依赖3.1）。
  - 主线程core目标25/25、desktop gate18/18，0skip/exit0；client异步失败/超时/late/mute/focus回修已有真实RED。服务器/mobile/GC/重启/OS展示未验收，不标整TC或切片done。

## 4. 验证（P0）

- [ ] 4.1 每片TC非零且全部通过、完整覆盖、实际产物与相关回归核对；未执行/skip不得计通过。
- [ ] 4.2 隔离真实route→T CLI→wake→TaskService及数据库三路径，前端重复Inbox ID验证。
- [ ] 4.3 全部相关测试/生成/格式/类型/独立评审与14类失败检查；报告真实耗时和未验证边界。
- [ ] 4.4 Gate3等待用户，不自行commit/push、迁移在途CR或生产部署。

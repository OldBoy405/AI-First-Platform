# AIFI-45 tools — BUILD任务清单

## 2026-10-25 terminal-fence跨仓进度（当前；M纵片未全完）

- [x] wire §3.5对应M严格终态body/事务CAS最小实现：旧代次fail/complete真实RED→GREEN，foreign terminal replay与stale Composio overlay、daemon sender/outbox 三组也各自修复；最终冻结final5独立回归governance 879/878（795 leaf）、handler 13/13（10）、daemon 125/124+1 Windows SKIP（115）；五轮原库137表/6228行/82审批一致、vet exit0。不计业务TC/非全局验收。
- [x] daemon侧：tuple随run的context（非taskID缓存）、single-flight按deliveryKey、outbox record v3 `claim_mode`、仅`mdt_` token升级qualified、strict无fenced时fail-closed不发终态；strong F1–F4/N1/N2 全CLOSED。
- [x] wire §3.6服务端绑定签发：`POST .../execution-authorization/binding`（exact 4 键 body、RR 事务内 claim/task↔CR/head/project/coordinator/daemon/challenge 摘要全核，条不符 409），签 `execution-binding/v1`（`schema\0+payload`、Ed25519、20 键），新表 `cr_execution_binding_issue` append-only（无 FK）、同 challenge 重放幂等。真实 MDT→HTTP→DB 18/18（17 leaf）；strong 首轮 2×P1+3×P2 全修并复核，最终 13 项冻结独立回归 governance 897/896（812 leaf）、handler 13/13（10）、daemon 125/124（115）。
- [x] 配套：`SetTaskCRAttributionIfValid` 改首次写入胜出（禁止自报覆盖已归属 CR）；runner 新增 `-migration=`（因临时库为冻结原库 schema-only 克隆）。
- [ ] **未实现**：daemon 私有 stdio 中继（把服务端签好的 envelope 交给 T 子进程）、T 侧消费事务、不可删 activation 本体、同 UID 隔离控制域、`EXECUTION_CONSUMPTION_REQUIRED` 解除。进程号/根由 daemon 转述，服务端不可验证；首次 CR 来源仍未证明。
- [ ] retryable fail在**有效代次**事务失败时仍可能已建外部Composio session（真实POST，无撤销）；动态并发race、同代complete/fail并发第二条可能不落盘、legacy无字段仍被服务端接受（PAT daemon只能legacy）。
- [ ] T消费、activation与受保护控制域保持原未完项，不借M组件证据关闭。完整0/49、5major/旧claim锁序INCOMPLETE，原库事故HOLD，Gate3/提交/推送/部署仍需分别授权。

## 2026-10-25 M当前task/project claim（当前；仍非完整准入）

- [x] wire §3.4与M产品接既有status GET显式claim mode/SDK/daemon根前实际回读，MDT真实scope、冻结queue project/live issue/project/runtime/代次/active状态；首片issue-backed-only，shared微秒token前验与DID C0/C1拒绝，无新表/迁移/FK/端点/nonce。T源码/签名字节不改，metadata仍非admission。
- [x] balanced实际写HTTP/SDK矩阵及SDK→MDT→DB正反贯通；真实RED→HTTP21/21、SDK/前置39/39，新claim失败旧callback实发1次→抑制。作者全治理851/851（770leaf）、daemon112P/1 Windows权限SKIP（106leaf），中间0RUN编译错不算RED。CUSTOM #169/M11=22。
- [x] 12条pre-run source pin/后核、原137表/6228行/82审批共同冻结相同、锁session0/精确新资源清；19项archive在独立前保存。见[M本片报告](../../../multica/changes/2026-10-22-aifi-45-authorized-execution/validation/claim-project-20261025T052646Z-report.md)。
- [x] 非作者三组851/851、13/13、112P/1 Windows权限SKIP（leaf770/10/106），各自19项先pin/后同，原库/资源逐条安全；DB权释放。caller/server+SDK限定strong完成无新增确证finding，宿主只读最终核15条基线共同未变、37对已知库role不存在，四包vet exit0。
- [ ] 继续terminal全链代次fence/outbox（确证旧task-ID-only缺口，现只封新claim失败分支），每repo本机事实/控制域/activation/T消费；旧claim锁序仍INCOMPLETE，完整0/49、5major、消费/Gate3不变；不因常规阶段结束停下来。

## 2026-10-25 M当前资源元数据读面（前段；不是完整可信绑定/TC）

- [x] wire §3.3明确复用现有daemon repos API显式project查询，元数据不升格为execution-binding/claim/admission；主会话接M产品，两位balanced实际写独立HTTP/SDK测试。作者公开HTTP 1FAIL→1PASS、SDK21/21（20leaf）、真实HTTP矩阵11/11（10leaf，含SDK贯通）；CUSTOM #168/M11=21，T源码/签名字节不改。
- [x] strong发现大小写别名P2后balanced补3失败leaf，主会话精确键根修25/25（23leaf），strong关闭P2、限定静态完成。11文件raw/LF/原字节archive与模型配置保存；中间作者pre-run manifest缺口已披露，P2及最终独立先pin，不倒签。见[M本片报告](../../../multica/changes/2026-10-22-aifi-45-authorized-execution/validation/current-bindings-20261025T034807Z-report.md)。
- [x] P2后独立balanced治理828/828、claim13/13、daemon72P/1 Windows权限SKIP、leaf749/10/67、exit0；每条原库/资源/锁session安全与源码匹配，DB权释放。宿主只读最终核原137表/6228行/82审批及13条before/after共同一致，共22对已知库role不存在，四包vet exit0。
- [ ] 旧claim strong仍INCOMPLETE，明确未尽agent/Builder rebind、terminal settlement/system cleanup SQL、wakeup管理/注册事务；新读面动态并发snapshot race未验，不借限定静态/回归自动补齐。
- [ ] T仍待完整可信claim/project、每repo本机事实和保护控制域/activation/legacy防降级/消费事务/永久派发接线；DB声明元数据不能开放消费。0/49、5major与Gate保持，原库HOLD/原41缺失不解除；无commit/push/部署。下方历史不覆盖本节。

## 2026-10-24 新库恢复（前段；不是事故恢复或完整TC）

- [x] 已获用户新可丢弃隔离库明确授权；原库与事故证据保留不写，旧入口HOLD保持，missing41/extra40不改写，不以82冒充原83恢复。下方待授权为事故时快照，不解除原库HOLD。
- [x] M版本化逐命令schema-only新库/受限role、原表拒读/原行备份/137表摘要及82审批ID/hash比对/每条锁session0/精确清理，fixture自建身份；Node6/6，runner两finding闭合、限定静态PASS，CUSTOM #167/M11=20。
- [x] 最终balanced3治理817/817、claim13/13、daemon47P/1 Windows权限SKIP，均exit0；每条原库未变、临时资源已清、DB权释放。T源码/签名字节未改。见[M报告](../../../multica/changes/2026-10-22-aifi-45-authorized-execution/validation/disposable-db-20261024T162608Z-report.md)。
- [ ] 旧claim完整锁序独立审核INCOMPLETE、每repo当前descriptor与完整claim/project/隔离/activation/防降级/T消费/永久派发继续待办；完整TC0/49、5major/消费关闭/Gate保持，不Gate3/commit/push/部署。

## 2026-10-24 STOP：M DB历史事故（事故时快照；原历史未恢复）

- [ ] 独立扩大回归后历史83→82/missing41/extra40，原42保护集完整；另外41旧fixture历史未恢复。主会话暂停后续DB测试/写入与接线，只读保存现场，待用户给原始备份或授权另建可丢弃测试库；不改82为合格基线。见[M事故记录](../../../multica/changes/2026-10-22-aifi-45-authorized-execution/validation/claim-build-20261024T153817Z-incident.md)。strong INCOMPLETE、完整TC0/49/5major/消费/Gate保持。

## 2026-10-24 M task claim runtime归属（事故前组件过程，非整TC/切片完成）

- [x] 主会话继续普通实现，balanced并行只读核claim和每repo身份。M公开StartTask真实mdt越权200的RED→同事务runtime归属锁/claim锁GREEN，作者3/3及既有claim13/13，0skip/exit0；CUSTOM #166登记，T源码/签名字节未改。见[M claim组件报告](../../../multica/changes/2026-10-22-aifi-45-authorized-execution/validation/claim-build-20261024T153817Z-report.md)。
- [x] DB全83条历史ID/整行hash不变、0锁/0其它session后移交唯一独立复跑者；质量/binding/Gate未改。
- [ ] 独立strong补全复核、balanced扩大回归/释放、economy文档核查；不将局部无finding或INCOMPLETE写PASS。
- [ ] T当前绑定仍待每repo当前descriptor/完整claim/隔离控制域/activation/legacy防降级/消费事务接线；不据M runtime归属组件或资源限额PoC开放消费，0/49、5major不变。

## 2026-10-24 revoke与整数P2子任务（前段快照，非整TC/切片完成）

- [x] 明确wire §3.2 purpose-specific revoke/来源profile，M真实Auth签名revoke/前驱CAS/只读head链与T严格来源验证；CUSTOM #165登记。证据见[撤销续建记录](resume-revoke-build-20261024.md)。
- [x] 主会话补T数字舍入/下溢6条真实RED，最小GREEN8/8、跨binding调用者11/11；独立strong F1关闭，不修改原source/payload bytes。按用户纠正同档普通实现不凑三档派作者，独立审核仍保留。
- [x] 非作者真实T218=217P/1EPERMskip/0F；M治理550/550、router14/14、拒消费2/2、HTTP→当前T3/3，全部exit0；count/父子/重叠不累计业务TC。strong限定静态PASS；主会话vet/格式/语法/diff-check、sqlc78重生成零漂移。
- [ ] **整链仍未闭合**：当前已实现窄revoke不代表extend/可信DB claim/每repo当前绑定/实际隔离/activation/legacy防降级/T消费/永久派发恢复；业务TC0/49、5major不关闭，不自行Gate3/提交/推送。

## 2026-10-24 分层恢复组件（前段快照，非整TC/切片完成）

- [x] 按原生有效配置实际委派strong/balanced/economy；配置JSON、harness/requested/actual unknown及独立评审会话见[恢复记录](resume-tiered-build-20261024.md)。保留两仓测试命令/质量门槛/Gate与历史派发记录。
- [x] T 三文件基线164项/163PASS/1 symlink EPERM SKIP/0FAIL/exit0；M真实Auth基线10/10；两仓validate/canon verify均exit0（proposal各2/2，不代TC）。
- [x] 细化wire §3.1并由M实施持久化initial head/真实只读回读、642隔离迁移/sqlc生成；旧历史不能补head。独立strong发现负零P2后，作者真实HTTP RED→GREEN修复，不改原签名字节；组件证据及复核状态见恢复记录，CUSTOM #163–164已登记，含test-only精确fixture清理。非作者最终组件174/174、实际router5/5、拒消费2/2，exit0/0fail/0skip；strong静态PASS，仍不计完整TC。
- [ ] **整链仍未完成**：revoke/extend签名head链、DB claim、每repo当前绑定、隔离控制域/不可删activation/legacy防降级/T消费/永久派发；完整业务TC0/49，5major未闭合，不勾整片，不自行Gate3或提交推送。

## 受保护 trust root（ADJ-AIFI45-003，前轮组件）

- [x] 新增真实 RED：`--trust-root` 在旧码被忽略 → ①带声明根仍返回被篡改工作区包的 digest（与合法包不等），②指向工作区 `.crctl` 的根反而放行；两例实际失败。
- [x] 实现 `installDirectory()`：声明根必须绝对、可 realpath、不得位于或包含工作区安装根；grant/公钥/来源sidecar/`execution-binding/v1` 证明统一只看该目录（`EXECUTION_TRUST_ROOT_INVALID`）。未声明时保持 legacy。
- [x] 回归：授权文件 106/106、三文件 164/163PASS/1 SKIP、旧 grant 14/14，均 0 FAIL/exit0。
- [x] M 侧 HTTP 授权包→daemon trust root 投递已接，真实 crctl `--check --trust-root` 读到 daemon 安装的记录（T 代码本轮未改）。
- [x] M 的 `handleTask` 已经生产 helper 执行静态 `--check --trust-root`；真实 Auth/DaemonAuth 投递测试通过，新合同最终仍拒消费。详见 M `preflight-evidence.md`。
- [ ] **仍未完成**：可信 current-head/撤销/DB claim、隔离控制通道、不可删 activation、legacy 新合同防降级与消费事务。不得据静态核验完成 AUTH-004/006/008 或整 TC。

## 本轮安全收口组件（不计业务切片完成）

- [x] 公开CLI新增实际拒绝RED，撤回fresh proof子集后的live消费；删除独立receipt writer/调用，预置receipt不激活。
- [x] 最新真实TAP AUTH+transaction+durable 162/161PASS/0FAIL/1文件symlink EPERM/exit0；旧grant真实选择14/14/0skip/exit0。
- [ ] 真实CLI隔离PoC完整runtime/清理验证及daemon真实任务接线（当前runtime缺cgroup委派而fail-fast，需操作者协助，见isolation-evidence.md）。
- [ ] 受保护trust root/安装器、不可删activation、当前平台验证及既有事务消费。不得据上述组件勾完成AUTH/RPR/整TC。

> Gate2已确认；用户原文“普通模式”，long_range.enabled=false/mode=normal。阶段推进仅走原生CLI。每项完成即登记，不以部分TC冒充整个切片完成。

## 1. 可信执行授权（P0）

- [x] 1.1 公共authorization-bind篡改/错误域负例子任务完成RED→GREEN；仅TC-AUTH-003子断言，不登记整个TC完成。当前auth/source/binding公开组件边界103/103，0跳过/exit0（含Go/Node URI共同子集与native路径）；新nonce与来源缺失/重复键均有真实失败证据。
- [ ] 1.2 TC-AUTH-010跨语言签名字节与严格payload/schema/key输入验证；旧v1 grant回归保持（依赖1.1及M签名资产）。M主线程真实Auth/Node选择59/59、protocol全包58/58已执行；该TC完整标题/整链仍未验收，保持未完成。
- [ ] 1.3 TC-AUTH-001/002/004/007/008/009完整绑定、来源/scope/head、ACK分离及durable隔离提交/恢复（依赖1.2）。T已核对结构化原文bytes/14映射和fresh proof子集，但真实daemon链/目标仓库身份仍待闭环，消费保持拒绝。
  - 最新主线程AUTH103+exec41+durable17联合161选中/160PASS/1 file-symlink EPERM SKIP/exit0，旧grant14/14。原HEAD独占锁+detached nativeCAS拒同SHA切branch；beforeApply意图/never-applied、恢复token、deferFinalize与终态防重复rollback、helper实例/无全局prune已组件收口。未知锁/缺证helper维护保留，未统一旧入口scope/真实消费，不计RPR-006/整片。
- [ ] 1.4 TC-AUTH-005/006敏感动作聚合额度、精确操作幂等和续签继承（依赖1.3）。

## 2. 累计修复与独立进展（P0）

- [ ] 2.1 TC-RPR-001～004首次/纠正分类、消费6次、失败计次、跨阶段cycle（依赖1.3）。
- [ ] 2.2 TC-RPR-005/006同origin准入、共用CR锁/CAS/隔离index、崩溃与adoption（依赖2.1）。
- [ ] 2.3 TC-RPR-007/008追加head CAS与无权继续拒绝（依赖2.2）。
- [ ] 2.4 TC-RPR-009～012独立assessment、两次无进展和签名resume（依赖2.2）。

## 3. 门禁、产物与兼容（P0/P1）

- [ ] 3.1 TC-EVD-001～005内容型产物、独立交付与机械例外；同步真实writer/writeback脚本（依赖1/2）。
- [ ] 3.2 TC-EVD-006～010旧合同/旧入口防旁路、迁移、版本配套与发布恢复（依赖3.1、M实际调度）。
- [ ] 3.3 registry/policy/权限/模板/索引/Agent/Skill和生成消费配套，长期规则归现有权威源（依赖3.1）。

## 4. 验证、审查与交付（P0）

- [ ] 4.1 每个切片新增测试>0且全部执行通过、TC覆盖完整、实际产物存在，全量相关回归无新失败（每片即时执行）。
- [ ] 4.2 联合M真实认证/wake/TaskService与隔离DB三路径失效验证，禁止fake walker代证或skip冒充PASS。
- [ ] 4.3 tools全量测试、lint/矩阵/合同/生成校验；14类失败模式和独立多路评审。
- [ ] 4.4 汇总真实test-report/调整，更新phase-context，等待Gate3；不自行commit/push/生产部署/真实CR试点。

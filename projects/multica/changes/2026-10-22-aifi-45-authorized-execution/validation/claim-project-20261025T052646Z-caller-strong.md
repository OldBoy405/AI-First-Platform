# Claim/project production caller 独立 strong 静态审查

## 判定与限域

限定caller顺序/错误分类/legacy兼容静态评审完成；无新增确证Finding。

本片只审 `execution_verifier.go:prepareClaimedPipelineTask` 的新claim顺序、daemon.go中对应prepare-error分支及必要直接helper/test。server+SDK已完成五文件不重新评审；仅按冻结hash复用此前SDK校验与错误包装结论。不签静态verifier输出解析器全局正确性、root选择器完整admission、runtime-offline/runTask早退/complete/fail/outbox或生产消费。

原生模型provenance沿宿主派发前M/tools final-review models回读：schema1/configured strong/high（OpenAIPersonal/gpt-6.1-sol/high），actual无后端回执，unknown。本片未重查配置/切换模型。无DB访问、无测试执行、无产品/测试源码修改、无子代理。唯一写入为本报告，Python open('x')独占创建（wx），不覆盖旧报告。

## 可复核的caller结论

### 1. strict → 真实平台claim → 根准备/安装

`execution_verifier.go:23–43`：nil task返回；先在27行运行strictExecutionContract；strict错误直接返回。仅strict=true时新增平台回读门禁：

- nil client在33行返回包裹errExecutionTaskClaimUnavailable的错误；没有转legacy或借collector缓存替代。
- 35行直接使用concrete `d.client.GetTaskExecutionClaim(ctx, task.WorkspaceID, task.ProjectID, task.ID, task.RuntimeID, task.DispatchedAt)`，不是test注入的claim helper，也不是heartbeat/旧Task字段自证。SDK已在前片审核：expected四UUID/代次/status、schema/exact8键与scope检查；本片只核hash未改，不重复审。
- SDK错误原样上返；39行把返回claim.DaemonID与cfg.DaemonID精确比较，不做trim/fold或以task/header声明取代；不符也包同一sentinel。错误expected project/tuple会由SDK拒绝，不能用wrapper覆盖服务DB冻结ProjectID。
- 43行才调用preparePipelineTask；之后才校resolved root、打开trust store、60行InstallExecutionAuthorization。读取失败、nil client、daemon mismatch均不会走到这些步骤。没有缓存/legacy projection成功降级的代码分支。

已读直接helper `pipeline_task.go:558–599`：无新声明为legacy；未知/多个声明报错，不将其当支持合同。此处沿用既有policy识别器，不重新签它的全部YAML来源或不可移除activation守卫。读636行起确认preparePipelineTask是路径/编译pipeline校验与根选择的入口；其具体工作在新claim门禁之后，不在本片重审根算法。

### 2. unavailable错误链在terminal callback前被截断

`daemon.go:5780–5792`：prepare返回错误后先记log，再用`errors.Is(err, errExecutionTaskClaimUnavailable)`，匹配即return；`reportTerminalTask`及attachPipelineRecovery仅在其后的另一分支调用。前片已核SDK每个失败出口均含sentinel（直接返回或errors.Join）；caller新增nil-client和daemon-mismatch用%w包它，均能被errors.Is识别。

因此本片具体保证：**已经到达这次prepare、且返回claim-unavailable类别时，不发送这里的taskID-only terminal callback，也不进入后续agent路径**。它不是“所有strict失败都不会回调”的保证：strict解析错误、通过回读后root/install失败/EXECUTION_CONSUMPTION_REQUIRED仍走原普通错误处理；这些不因此获得代次CAS。不得把一次成功回读当锁或持续lease。

### 3. legacy无client测试兼容

strict=false时不访问d.client；仍调用preparePipelineTask，成功后47行返回nil，不走trust store/授权安装。nil task保持nil返回。旧`execution_preflight_test.go:43–65`明确构造无client Daemon：strict必须以EXECUTION_BINDING_UNAVAILABLE失败，legacy preparation仍成功。新nil-client错误保留该字符串并新增sentinel，故旧断言兼容；作者日志也有该旧测试pass。本片不宣称legacy是新合同的降级方案，它只是没有该声明的原路径。

### 4. 不是claim签名或准入

返回metadata只在本caller作当前tuple/project/daemon校验；未签challenge、未创建receipt、未激活或保留额度。成功执行静态安装后66行仍明确返回EXECUTION_CONSUMPTION_REQUIRED，不因根存在/检查成功启动strict任务。此处文本中“claim未connected”应理解为完整可信消费链未收口，不能将现有metadata回读夸成签名attestation。

## 已知范围外terminal fence：不隐瞒，不重复报新Finding

已完整读本change的terminal-fence-facts.md。该记录是修改前事实快照，其中“SDK无生产caller”及prepare stale-error会回调已被本片这两个接线修正，不能把这两条旧状态当当前结论。

其余已知缺口仍保留：runtime-offline分支在prepare之前，runTask其他早退及普通prepare错误、complete/fail和持久outbox仍没有完整代次CAS。本片实际读到daemon.go:5737–5797，明确看到runtime-offline仍先走既有taskID-only回调；这是用户已确认的下一片范围，**不是本片新发现、不是已修、也不是本报告签署对象**。本片的两个有限断言不因这些已知缺口混成全仓INCOMPLETE；更不能反向声称整个terminal链安全。

## 现成RED/作者GREEN证据

已完整静态读execution_claim_preflight_test.go：第一个用真实concrete Client→httptest HTTP409，计claim读取与other requests并断言未写根路径；第二个通过生产handleTask和terminalReportSend seam计数，runtime已tracked，HTTP409后要求reads=1/callbacks=0。它们是caller组件HTTP seam，不是实际服务DB鉴权/并发reclaim测试。

已核原始stdout：

- daemon-red2 的旧顺序失败为 `claim=0 other=1`；作者后续ReadPrecedesRootPreparation有pass。
- callback-red1为1RUN/1FAIL，具体输出 `unverified claim sent 1 task-ID-only terminal callbacks`；作者后续FailureDoesNotSendUnfencedTerminalCallback有pass。
- 作者旧nil-client/legacy兼容测试有pass。

已读作者meta：governance 851RUN/851PASS/0SKIP（770leaf pass）；daemon 113RUN/112PASS/0FAIL/1SKIP（106leaf pass）。raw skip原因是Windows缺少创建directory symlink权限，对应ExecutionTrustRefusesLinkedRootInsideWorkspace；不是零匹配或本次caller测试skip。

上述均为读取作者已存证据，非我重跑；广泛套件数字不当49TC/major完成。meta原库不变/lock session0/资源清理仅为作者记录，未连DB核实。冻结stage明确在作者GREEN之后、独立回归之前；不倒签成pre-author manifest。独立balanced当前三组仍在执行，**不读取零散进行中事件当PASS，不提前计独立回归成功**。

## Finding / 建议 / 未验证属性

- 已确认新增运行时Finding：无（仅上述限定caller断言）。
- 非阻塞注释建议：execution_verifier.go:20–22仍说path preparation是first step，已与当前claim先行实现相反。建议之后改注释，不改变本片代码结论；本轮未动源。
- 可补但不是本片缺陷：正向claim成功后的root调用顺序，以及nil-client、DID mismatch、取消/网络错误各类sentinel的callback=0直接回归。当前通用errors.Is分支静态成立；现成两个重点RED主要覆盖409。
- 动态未验证：读后并发换代、根准备期间变更、lease/reclaim恢复、跨进程outbox、Windows未跑link用例、独立三组最终结果。metadata read不等于防TOCTOU或generation CAS；不签这些动态性质。

## 实际read范围

完整可见并定向审核prepare：execution_verifier.go（整个文件工具返回；仅23–67 caller在本次结论范围）；execution_claim_preflight_test.go；execution_preflight_test.go；terminal-fence-facts；新19项source-manifest；callback-red1与author-daemon/author-governance三份meta。
部分：daemon.go:5737–5797及prepare-error grep；pipeline_task.go:550–709（strict与prepare入口/邻接views helper）；daemon-red2/callback-red1/author-daemon raw stdout定向失败/pass/Windows skip；caller直接引用检索。未重新审核server+SDK五文件、旧task锁序或terminal service/SQL。模型配置沿宿主回读，不重复。

## 实算源码SHA及冻结范围

本次只读哈希校验manifest全部19项；匹配19项。差异：无。这仅证明当前字节与本次冻结相同，不代表评审了19文件全部代码；archive未逐份核对，不声称部署attestation。以下列本片caller/test及复用SDK错误链的重要hash。

| 文件（业务根相对） | raw SHA-256 | CRLF→LF SHA-256 | 长度及hash对照 |
|---|---|---|---|
| `server/internal/daemon/execution_verifier.go` | `9ece30aa7369782ebe424fac0c6a989d6144098f653a5e8955fc3b7a54b25a46` | `9ece30aa7369782ebe424fac0c6a989d6144098f653a5e8955fc3b7a54b25a46` | MATCH |
| `server/internal/daemon/daemon.go` | `46f4ca377a273de255d8a192b67ff049b40b60ca1227f1692fb95e3faa3d69f4` | `46f4ca377a273de255d8a192b67ff049b40b60ca1227f1692fb95e3faa3d69f4` | MATCH |
| `server/internal/daemon/execution_claim_preflight_test.go` | `bb286a7cde879c35a90b7944b5292f18a778a700cdeadb08ab5ff13e27d60662` | `bb286a7cde879c35a90b7944b5292f18a778a700cdeadb08ab5ff13e27d60662` | MATCH |
| `server/internal/daemon/execution_task_claim.go` | `ad8de9adb8c443ab64522e3a568e5bd46d267fdbbb97d9316a2bc2f2a55d7452` | `ad8de9adb8c443ab64522e3a568e5bd46d267fdbbb97d9316a2bc2f2a55d7452` | MATCH |

不签全局C1/Gate3、old claim锁序、完整terminal fence或生产准入。

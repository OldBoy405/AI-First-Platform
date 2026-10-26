# Claim/project server + SDK 独立 strong 静态复核

## 判定、限域和provenance

原server精度P2 CLOSED；限定server+SDK静态代码复核完成，未发现新增确证Finding。

本片只审server claim/project读面、protocol.ParseExecutionClaimTime与daemon.GetTaskExecutionClaim。明确不签正在修改的execution_verifier、handleTask、terminal callbacks或根准备前调用接线，不将已知terminal-fence下一片工作报为本片新Finding。旧metadata P2、旧claim锁序、旧StartTask时间解析不重审。

未访问DB、未跑测试、未修改源码、未启动子代理。唯一写入是本报告，以Python open('x')独占创建（wx），不覆盖旧报告。宿主本轮原生模型配置为schema1/configured strong OpenAIPersonal/gpt-6.1-sol/high；实际后端回执没有，actual=unknown，未自行切换/重读配置。

这不是全局C1、49TC/5major或生产消费签署。metadata不是fresh attestation、持续lease、进程身份、签名binding、receipt或activation，不解除EXECUTION_CONSUMPTION_REQUIRED。未测动态race另列，不将已读完的限定静态代码泛化为INCOMPLETE。

## 原P2关闭：有损Parse前拒绝精度

`pkg/protocol/execution_task_claim.go:11–25`：先找到小数点/逗号，完整扫描后续ASCII数字；comma或超过6位立即拒绝，然后才time.Parse，仍保留Nanosecond%1000检查。原 `.1234560001Z` 在截断发生前即因10位小数失败；7/8/9位及超长全零也按本片最多6位合同拒绝。伪造第二个分隔符/藏额外尾数字不能形成合法RFC3339时间，后续Parse失败；未发现原截断缺陷的等价绕过。

server `daemon_execution_claim.go:46`、SDK请求 `daemon/execution_task_claim.go:31`、SDK响应79行全部调用此helper。响应还须精确等于解析值UTC().Format(RFC3339Nano)，不能用offset/非规范时间字符串代替服务端canonical回显；请求可用合法offset，同一instant用Equal比对。未改旧StartTask，不将新严格度强加旧API。

此判断针对精度与本片时间协议，不声称把Go time.Parse所有容错行为重写成另一套完整RFC语法解析器。

## Server与opaque daemon身份

当前server完整新文件已读：真实DaemonAuthPathDaemonToken、trim非空daemon、认证workspace非空仍是前置；新增unicode.IsControl拒绝C0/C1等控制字符，直接403。opaque daemon不是UUID，不擅自trim/改写其身份值，随后与DB runtime.daemon_id精确匹配。

任务canonical UUID、runtime绑定、DB有效dispatch代次/active状态、冻结Task.ProjectID、同workspace live issue同项目、实际project存在的检查保留；只支持issue-backed。四查询仍使用一个RR READ ONLY事务内的WithTx q。具体generated SQL/参数/Scan/WithTx及生产TxStarter接线沿前片已核，不重复全量读；不把读取快照描述成读取后的持续保证。header/body不产生workspace/daemon事实，调用者expected project只供SDK比对，不覆盖server冻结列。

GetTaskStatus无execution_claim时原status polling分流与错误语义保留。新API无nonce/任意签名/预算或receipt写入。当前server门禁/错误仍是固定文本，不输出任务context或DB详细错误。

## SDK精确解析、租户source与降级边界

完整读`internal/daemon/execution_task_claim.go`：

- 请求前四个expected UUID均须canonical；dispatch时间先过共享helper；之后才检查初始URL并发网络请求。url.Values正确转义时间offset的加号，task路径由canonical UUID组成。请求使用现有token、identity及本次workspace header。
- 请求project不由caller写入服务端DB归属；响应workspace/project/task/runtime逐一精确等于expected，时间须与expected generation同instant，status只许3个active值。未知/终态失败，不猜测其他source或借缓存补字段。
- raw body先过完整JSON/原始UTF8/重复键scanner，再map要求恰8个键，逐一确认8个exact canonical key后才typeddecode。额外alias使len=9；用alias替换键即required缺失；escaped同名键由scanner按解码键查重。不能重现旧metadata的case-fold覆盖路径。
- 旧服务只有status：键数/required集失败；缺失、null及异类型关键字段在解析/非空/scope/时间/enum检查中拒绝。没有legacy status、heartbeat、旧claim包或缓存的成功降级。
- daemon_id须非空且不含C0/C1，保留其opaque原值。方法没有expectedDaemonID参数，故**不宣称SDK独立把返回DID与本机配置比较**；身份事实依赖真实服务在mdt与runtime DB上的核验。此metadata边界不是受保护本机daemon证明，不能据它开放admission。

## Transport与错误数据

初始URL复用validateTrustedServerURL，当前helper已重读：HTTPS或指定loopback HTTP可用，remote plaintext拒绝。既有helper也允许ws/wss，但标准http.Client不因此执行WebSocket GET，失败不是claim成功；本片不扩大该旧helper策略。

复制http.Client后覆盖CheckRedirect，拒绝所有redirect；3xx走非200失败，不向target转发token。非200分支只返回HTTP状态，位于ReadAll前，不主动读取/echo错误body；defer Close不是将其解析成成功响应。200最多读1MiB+1，超限/读失败/scanner失败均返回unavailable；无无限body读或多文档接受。初始URL策略不是证书pinning或独立freshness证明。

## 测试证据口径与未验动态属性

本轮完整静态读execution_task_claim_client_test.go；它覆盖正常path/query/token、active status、wrong四scope/代次、nanosecond、终态、DID空/C0/C1、缺失/null、重复JSON、alias、第二文档、超限、无效请求0hits、非200不echo、disconnect与redirect目标0hits。非200测试断言不echo，不应将其描述成专门的Body.Read次数测试；代码分支本身在读取前返回。

定向读Gov测试399行至EOF：包括2个后增真实SDK调用（正常贯通、live issue漂移失败）、原10位小数与C0/C1负例。两个后增SDK用例没有从较早HTTP-GREEN2的21RUN中凭空计入通过。control测试接受403或409；当前实现403是源码核实，不说测试严格断言了403。

已读4份meta及raw stdout定向失败/pass行：

| 现成作者证据 | RUN/PASS/FAIL | leaf口径 |
|---|---|---|
| HTTP-RED2 | 21/17/4 | 时间1leaf、control2leaf及其父失败 |
| HTTP-GREEN2 | 21/21/0 | 19 leaf pass |
| daemon-RED2 | 39/36/3 | SDK时间input leaf、matrix父及root前置leaf失败 |
| daemon-GREEN3 | 39/39/0 | 38 leaf pass；包含root前置，不等于本片签署其接线 |

原时间HTTP 200而期望400、SDK非法时间竟成功的raw失败输出与后续pass对应。计数不是我运行结果；root前置只识别计数归属，不审其实现，不签它。meta报原库不变、sessions/locks0、清理成功，本片未访问DB核实，亦未全面复验历史pre-run/归档链。

未验证：并发读中状态/资源/issue/runtime变化的动态snapshot表现，部署/缓存撤销、完整transport故障矩阵，以及正在改的verifier/terminal callbacks。SDK响应10位小数/comma、alias替换而非追加、invalid UTF8等可补专门回归；共享helper和exact gate/scanner已有静态拒绝链，这些是建议，不是未关闭Finding。

## 实际阅读与hash边界

完整读：新server helper、protocol helper/DTO、新SDK文件、新SDK client test、本轮daemon-green3 source manifest。部分读：Gov测试399至EOF及用例grep；crevents.go:122–156 URL guard；本轮4份meta、raw日志定向行；共享helper调用点符号检索。原有server auth/generated SQL/WithTx/legacy分流沿前片已读范围；未重开service/task、StartTask或旧metadata评审。

以下为本次实算工作树raw/LF SHA和长度对照。hash全文件不代表评审整份daemon.go/client.go。Gov后增贯通若标TEST DRIFT，只限制其测试证据归属，不推导产品代码INCOMPLETE；未检查snapshot中正在修改的verifier等其他文件，不对其漂移下结论。

| 文件（业务根相对） | raw SHA-256 | CRLF→LF SHA-256 | 对指定manifest |
|---|---|---|---|
| `server/internal/handler/daemon_execution_claim.go` | `7164b743495d61ca4c6e3273ba0d0c03ba3bbed65724fcd9a2ea3797b9a08282` | `7164b743495d61ca4c6e3273ba0d0c03ba3bbed65724fcd9a2ea3797b9a08282` | MATCH |
| `server/pkg/protocol/execution_task_claim.go` | `83ce1f6ae20e3e48622f8112f96b5b43580880344c4454555b122b1a90178eb7` | `83ce1f6ae20e3e48622f8112f96b5b43580880344c4454555b122b1a90178eb7` | MATCH |
| `server/internal/daemon/execution_task_claim.go` | `ad8de9adb8c443ab64522e3a568e5bd46d267fdbbb97d9316a2bc2f2a55d7452` | `ad8de9adb8c443ab64522e3a568e5bd46d267fdbbb97d9316a2bc2f2a55d7452` | MATCH |
| `server/internal/handler/daemon.go` | `c879eb89ab44a4e5b9901262ebf36a66d40f714528671cfff9f0424f2e36144a` | `c879eb89ab44a4e5b9901262ebf36a66d40f714528671cfff9f0424f2e36144a` | MATCH |
| `server/internal/daemon/client.go` | `bb13526940e87e86ccb32b4cb2602552fd71b07289e74d479232b677ca548ee1` | `bb13526940e87e86ccb32b4cb2602552fd71b07289e74d479232b677ca548ee1` | MATCH |
| `server/internal/daemon/execution_task_claim_client_test.go` | `04ff36224e673d8b0c45cb4c667d2eebef3627f3ed10732fcf4455f262f2818f` | `04ff36224e673d8b0c45cb4c667d2eebef3627f3ed10732fcf4455f262f2818f` | MATCH |
| `server/internal/governance/execution_task_claim_project_test.go` | `415bbb191f612148b8b29d27b7ea5a79ec2a1b891c149857bd4490084636abce` | `415bbb191f612148b8b29d27b7ea5a79ec2a1b891c149857bd4490084636abce` | TEST DRIFT: not a product finding |

结论仅为原server精度P2关闭及上述server+SDK静态范围无新增确证Finding；无生产准入、全局C1或terminal回调签署。

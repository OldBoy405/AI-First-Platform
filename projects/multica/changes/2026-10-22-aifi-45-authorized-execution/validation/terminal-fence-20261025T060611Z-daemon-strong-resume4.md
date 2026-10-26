# AIFI-45 terminal-fence daemon resume4：限定评审收尾

## 范围与执行约束

业务根：`C:/Users/GOBAO/Downloads/AI/multica`。未另注的代码文件在 `server/internal/daemon/`。

仅判断本轮两处守卫是否关闭 N2 残余，并汇总此前报告的限定评审状态；没有展开新的广度审查。未访问 DB、未运行测试/vet/编译/生成器、未改产品源码或测试、未使用子代理，不使用另一代理的 DB 单执行权。仅只读必要代码/既有记录、计算哈希并实际创建报告。

模型声明沿用交接：configured strong `OpenAIPersonal/gpt-6.1-sol/high`；actual backend model unknown，未重新发现模型。

## 1. N2 残余判定：CLOSED（限定静态范围）

### 两处代码均已修正

1. **runtime-offline 分支**：`daemon.go:5767–5770` 现为 `(strictErr != nil || strict) && !d.canFenceTerminalReport(task)`，满足时记日志并 return；不再因 parser error 跳过保护。原 report 在5772，guard先于它。
2. **prepare 失败分支**：`daemon.go:5801–5814` 在既有 errExecutionTaskClaimUnavailable 退出之后、构造失败报告之前，也使用同样条件（5811），记日志后在5813 return。parser错误返回的普通error不会再绕开这层保护去发legacy failure。
3. **可携 tuple 的粗判与实际验证分层不变**：`execution_terminal_claim.go:80–82` 的 canFenceTerminalReport 要求 MDT形态 client、RuntimeID/DispatchedAt 非空；`67–75` 在入口为完整T/R/G stamp（daemon.go:5747–5749）。`86–97` 只给匹配taskID、尚未required的report附原tuple。
4. **非空不等于格式合法，但不会降级**：`execution_terminal_claim.go:17–40` 校验canonical UUID和精确微秒时间；`daemon.go:6490–6493` 在flight、落盘、网络之前验证persistedTerminalReport，错误即返回，没有剥tuple重发legacy。空taskID也由persistedTerminalReport拒绝。

### 组合结论

| 合同判定/凭据与tuple | offline或prepare-error行为 | 结论 |
|---|---|---|
| strict=true 或 strictErr!=nil；PAT/nil client | canFence=false，两处guard均拒绝回调 | 不发legacy，关闭N2的非MDT触发。 |
| strict=true 或 strictErr!=nil；MDT但缺RuntimeID/DispatchedAt | canFence=false，两处guard均拒绝回调 | 不发legacy，关闭缺tuple/错误合同残余。 |
| strict=true 或 strictErr!=nil；MDT且完整合法T/R/G | 允许提交report，入口ctx保留本次tuple，随后qualified发送 | 允许安全失败报告，不误降legacy；服务端仍须认证/检查fence。 |
| strict=true 或 strictErr!=nil；MDT且非空但畸形tuple | 粗判可能允许，但后续格式校验拒绝，网络前返回error | 可接受fail-closed，不借格式错误回退。 |
| 普通注释，无合同：false,nil | `(strictErr != nil || strict)`为false，guard不拦截 | **不误伤普通non-strict任务的legacy回调**；PAT保留legacy兼容。 |

prepare strict claim 真正不可得时，原 unavailable 分支已经记日志退出；新guard不迫使其用legacy终结。上述“不回调”是拒绝不安全终态，不表示已经验证lease/reclaim必定及时恢复。

### parser error 的精确范围

`pipeline_task.go:558–592`：无识别出的声明返回false,nil（582–583）；单个不支持版本在586返回false,error；多于一个声明在590返回false,error。因此原resume3反例（未知版本/重复声明 + PAT或MDT缺tuple）现在进入保护条件，而不再误作legacy。

yaml.Unmarshal失败的block仍在569–574附近被continue跳过，可能最终得到false,nil。**本次CLOSED限于该parser已经识别为strict或error的输入**，不是承诺任意损坏YAML/所有合同意图都能被识别，也不因此关闭legacy防降级major。该行为按本轮给定边界保留，不另展解析器审查。

两处guard均是在“不得安全发送时拒绝”的条件下生效。普通false,nil不满足左侧，故不会因PAT、缺时间或无法fence就被这个新guard误退；其它既有错误、网络与运行逻辑不在此作全量保证。

### 证据与未验证区分

只读既有记录：n2-red1为3 RUN/1 PASS/2 FAIL；n2-green1为84 RUN/84 PASS、78 leaf；本轮n2b-green1.meta.json为91 RUN/90 PASS/0 FAIL/1 SKIP、84 leaf，argv包含ExecutionTrust组。Windows-symlink为交接所述skip原因；本轮未独立执行或验证该平台场景。

n2b的generation测试文件hash与上一pin相同，不能仅凭91/90计数宣称所有parser-error组合新增了动态回归。本次N2关闭依据是两处guard实际控制流及后续校验，既有green是其它actor证据，不冒充reviewer并发/DB验证。限定范围未发现需新编号的确证P0/P1/P2。

## 2. 本片限定结论（共11行）

1. 范围仅为此前已审claim读面、qualified terminal写面及daemon sender/outbox的限定静态复核，不是完整执行准入。
2. CLOSED：daemon原F1–F4、N1、N2（含错误合同两处guard）及复制锁vet源码根因；这些关闭均保留各报告的输入/调用前提。
3. 已完成原读面字段/精度、qualified body及Fail CAS事务接线的静态检查；不外推为整个Complete/terminal回放身份链已CLOSED。
4. 旧fail-strong回放scope P2本reviewer未独立复核关闭，评审状态仍OPEN/未签；这不是断言最新源码仍有原漏洞，Complete server闭环亦未补签。
5. OPEN边界：服务端仍接受无claim字段的legacy请求；兼容分支不是legacy防降级major关闭。
6. OPEN边界：普通PAT daemon仍走legacy；已识别strict/error输入无可用fence时拒绝回调，不能由此宣称所有旧调用已迁移。
7. 未验证：真实并发reclaim、双终态、故障回滚/外部副作用等动态竞态；其它actor green不等于本reviewer独立动态证明。
8. OPEN限制：同代complete/fail共用终态key，第二条并发报告可能不落盘；不承诺两条都durable或全链exactly-once。
9. OPEN（交接已知、本轮未重验）：retry overlay有效代次的外部资源泄漏未修；DB回滚不等于外部活动可撤销或为零。
10. 不签完整terminal链/生产准入/全局C1；旧claim锁序仍INCOMPLETE，不以本片证据补签。
11. 业务TC **0/49**；**5 major未关闭；消费关闭**。

## 3. 快照及实际落盘

最终采用 `terminal-fence-20261025T060611Z-n2b-green1-source-manifest.json`（2026-10-25T07:36:56.001Z）。六个相关文件读时匹配，创建前再次核验；pipeline_task.go作为必要直接helper单列raw hash，不冒称manifest已覆盖该文件。hash整文件不等于全文件已审。

最终目标由临时评审文本通过Python open('xb')（wx/exclusive create）创建并读回核验，不覆盖此前报告，不改产品树。

### Final raw SHA-256 snapshot

| File | Bytes | SHA-256 | Status |
|---|---:|---|---|
| `server/internal/daemon/daemon.go` | 489018 | `0e88027e6b21860332c100f0843cca0983c267d8d25b1b2f07b07e63328dcc85` | MATCH |
| `server/internal/daemon/execution_terminal_claim.go` | 4056 | `dfd5d25d220f6a4922e6e287161cb18602e20c8b9a5b60c34c4616c778e0658e` | MATCH |
| `server/internal/daemon/execution_terminal_generation_test.go` | 19685 | `2ca150e828f1715f2016bca29959a9fea2cc97f5d9402da135b760aedc8438bc` | MATCH |
| `server/internal/daemon/execution_verifier.go` | 5580 | `f4796e3f8b9a1186abc1ca46eb08df352a094a034ae31f5bcf209bcdbd5e1161` | MATCH |
| `server/internal/daemon/client.go` | 61517 | `916edf84ef90c6749d026a9de7ca478d9e6b788360ddf98ce0ccdbfb68eaa01d` | MATCH |
| `server/internal/daemon/terminal_report_queue.go` | 37999 | `da15ba13c4a9728613fe64ef75d30e356b0a5450c4676efe3e7b82feb2816f6f` | MATCH |
| `server/internal/daemon/pipeline_task.go` | 48809 | `8cb7171798f7ee53923658f73751213860bf9caf861f4830f83ad27193e04922` | supporting read |

Creation UTC: 2026-10-25T07:39:48.855543+00:00

# AIFI-45 current-head：C1 P2 负零修复与补充组件覆盖

## 结论与边界

- C1 静态 P2 已经真实公开 HTTP RED → 最小生产修复 → GREEN。仅两条负零用例被动态证明曾 RED；新增数值边界、router、并发、丢响应及清理用例均为补充组件回归，不称为曾 RED，不新增业务 TC。
- 本轮只改 3 个源文件：`server/internal/governance/execution_authorization_head.go`、同目录 `execution_authorization_head_test.go`、`server/cmd/server/execution_authorization_head_test.go`。没有修改协议、其他生产模块、共享 fixture、CUSTOM、旧证据或旧 manifest。没有实现 revoke。
- 最终选中测试全部 PASS，零 SKIP、退出 0；没有 full-suite、race、crash-kill、部署或永久调度验证。五个 major 仍未解决，完整业务 TC **0/49**；无 commit/push/Gate 推进。
- 源 HEAD 未变：`f6e90ab8090c8a712c7fe2a324e977f10a39499c`。本报告不能代替主线程或独立评审确认。

## 1. 真实 RED → GREEN

在收到 DB 已释放通知后，先只增加 `TestExecutionAuthorizationHeadHTTPPreservesNegativeZeroSource`，再运行原生产代码。两个子用例分别把 literal token 直接插入实际 HTTP 请求 buffer：

- `repair_limit:-0`
- `sensitive_actions[0].limit:-0`

其余 fixture 可由 JSON 构造，但负零替换后没有再 Marshal 请求。测试核对冻结 source 与请求逐字节一致、payload 的对应 int64 为 0；通过真实 Auth POST、真实 DB-backed DaemonAuth GET，并再次 exact replay 原 bytes。

RED 原码 head 哈希 `6500eb93...7404f` 与原 manifest 完全相同。raw 中两例均为：

```text
before replay: initial POST=201, head GET=409
before replay head GET = 409, want 200 after accepted negative-zero initial:
{"error":"EXECUTION_AUTHORIZATION_HEAD_INVALID"}
after exact replay: initial POST=201, head GET=409
```

exact replay 本身返回 200/reused 原记录，但不能使原码 head 可读。期待始终是合法 issuance 后 GET 200，没有改成期待拒绝。

| 运行 | RUN/PASS/FAIL/SKIP | Go exit | 子进程墙钟 | Go package |
|---|---:|---:|---:|---:|
| `20261024T120130Z-head-p2-negative-zero-red` | 3/0/3/0 | 1 | 5.081s | 1.623s |
| `20261024T120233Z-head-p2-negative-zero-green` | 3/3/0/0 | 0 | 4.760s | 1.480s |

计数含 1 个父测试和 2 个子测试。RED 与首次 GREEN 的测试文件哈希均为 `6f6af2ae...4bedbf9`，只有生产 head 实现变化；不是编译失败、无 DB 或零选中。每次原始 stdout、stderr、直接捕获 argv/status/计数/源码哈希均另存对应 `.go.jsonl/.stderr.log/.meta.json`，未覆盖旧轮证据。

## 2. 最小生产差异

位置：`execution_authorization_head.go:202–253`。

- 保留 UseNumber，比较前显式 `ValidateExecutionJSON`；重复键、非法 JSON、多文档、非 UTF-8 仍拒绝。
- 在独立解码的比较值树中递归处理 `json.Number`，复用 `executionSafeInteger(..., min=0)` 的严格整数词法、ParseInt 和 JS-safe 上限，再以精确 int64 值 DeepEqual。故 `-0 == 0`，没有 float64 舍入。
- 不将字符串、null、boolean 转为整数，不接受小数/指数/负数/越界。外层精确对象解码及原 scope/parser 校验仍保留。
- 不写数据库、不重签、不重新编码存储包或原始 source/payload。既有 round-trip Marshal 仍仅用于类型/字段一致性检查，绝不作为验签或 digest 输入；新整数处理只作用于独立比较树。

## 3. 新增覆盖与代码位置

`internal/governance/execution_authorization_head_test.go`：

- `:456`：29 个严格比较/解码子用例；含 -0/0、最大安全整数、相邻大整数不相等，以及 string/null/bool、小数/指数、负数、越界/int64 overflow、重复键、缺键/别名/未知键、多文档等拒绝。`00/01/-00` 本来不是合法 JSON，明确继续拒绝，不类比负零放行；比较不修改原 buffer。
- `:520`：上述两条真实 HTTP 负零回归，持续验证原 bytes、原签名包、head 和 exact replay。
- `:599`：两个整数位置各 7 条真实 Auth POST 边界（合计 14 个子用例）。最大安全值 POST 201/GET 200 且精度不丢；string/null/0.0/超安全上限/重复键/00 返回 400、没有 history/head。
- `:667`：同 raw、异 raw 两条并发 initial。先在独立事务持有真实 CR 锁，观察两个实际 HTTP 事务均已进入 `FOR UPDATE OF cr` 锁等待，再释放；同 raw 为 201+200/reused 同记录，异 raw 为 201+409，仅一 history/head，daemon GET 读取唯一胜者。
- `:767`：真实 HTTP middleware/handler 在提交后 201 response writer 写入时返回 `io.ErrClosedPipe`；确认 DB 已提交，再原 bytes 重试，得到 200/reused，history 数、record、source_event/package 和 head ID 均不重建。这里是 response-writer 故障注入，不声称 TCP 断线/进程 crash 证明。
- `:300`：原有 missing-pointer/CR-reconstruction exact replay 不复活测试继续保留，无需重复补写。

`cmd/server/execution_authorization_head_test.go:28`：新 `TestExecutionAuthorizationHeadRouterConfigured`。生成仅测试内的 Ed25519 key，经 `RouterOptions.ExecutionContract` → `NewRouterWithOptions` 的真实配置路径；真实人类 JWT POST 201，再真实 DB-backed daemon-token GET 200，核验包不变、签名、identity、head digest、purpose 和 no-store。不是只调用共享 mount。原 default-off 测试现在位于 `:148`，未改其期望。

原测试没有这两种补充覆盖，因此补写，不提供错误的“已精确覆盖”行号，也不将它们的首次 GREEN 编造为 RED。

## 4. 本片 fixture 清理

问题核实：共享 `resetCR`/`gateProjectFixture` 有按 CR 名跨 workspace 清理的路径，且 history 可能在 CR 删除后残留。本轮不改其他模块/shared fixture/TestMain。

本片改用 `:26–89` 的本地 helper：

- 用完整随机 UUID 的十进制表示构造每次运行唯一且满足现有 CR grammar 的 ID；精确 workspace/CR 必须未占用，否则报错，不清理占用者。
- 只清理本次 workspace/CR 的 history/CR；issue/project/resource 按本次创建的 ID 清理，并检查 own CR/history 剩余为 0。
- foreign-CR/foreign-workspace 负例移动的记录，按事先捕获的本次 record ID 加精确目的 scope 清理；取消本片原先按 `CR-9061-999` 名全删的 cleanup。
- `:427` 的 scoped cleanup 测试在另一 workspace 先建同名 CR/history sentinel；子 fixture 清理后自有两者为 0，foreign 两者仍为 2，随后 sentinel 由其创建者精确清理。

保留一次实际失败的中间检查：`20261024T120505Z-head-p2-head-boundaries.*` 为 80/38/42/0、exit 1，5.417s。新增安全 guard 检测到旧固定 ID 的既存 history，报 `head fixture scope must be unused`；它不是业务/数值 RED。没有为了过 guard 扫删，随后改用唯一 CR ID。修正后组件运行 `20261024T120700Z-head-p2-head-boundaries-cleanup.*` 为 88/88/0/0。

最终回归前/后只读 DB 证明：

- `20261024T120957Z-head-p2-db-before-final.json`
- `20261024T121106Z-head-p2-db-after-final.json`

前后 `CR-9061*` history 均为 **38**，逐条 ID/内容 SHA256 **完全相同**，匹配 CR 均 0。38 是评审留下的 36 条，加首次 P2 GREEN 在旧共享 fixture 下留下的两条本轮记录；没有宽泛扫删这些旧残留。新 scoped fixture 不再新增残留。该证明只覆盖最终组合回归的前后，不倒推成整轮所有时刻完全无残留。

收尾为 **0 advisory lock、0其他 client session**；migration ledger 仍 671/latest `642_cr_execution_authorization_head`。本轮没有 DB migration/schema 修改。DB 已于只读收尾后通知释放，没有后续 DB 访问。

## 5. 最终实际运行结果

全部顺序、单 Go test 进程，沿用未修改的专用 runner 的容器/标签/loopback/DB身份校验、GOPROXY=off 和环境密钥剥离。捕获 wrapper 只存新增证据，不更改 runner 或 argv。

| 新证据前缀 | 选中范围 | RUN/PASS/FAIL/SKIP | 顶层 RUN | exit | 子进程墙钟 | Go package |
|---|---|---:|---:|---:|---:|---:|
| `20261024T120846Z-head-p2-head-final` | head，shuffle/count2 | 210/210/0/0 | 32 | 0 | 8.409s | 4.920s |
| `20261024T120855Z-head-p2-auth-narrow-final` | Auth/initial 窄回归，shuffle/count2 | 14/14/0/0 | 14 | 0 | 3.743s | 2.053s |
| `20261024T120957Z-head-p2-governance-final` | head/Auth/source/crctl/delivery，shuffle/count2 | 344/344/0/0 | 60 | 0 | 10.160s | 8.041s |
| `20261024T121008Z-head-p2-router-final` | 真实配置化＋default-off router，shuffle/count2 | 10/10/0/0 | 4 | 0 | 4.343s | 1.937s |
| `20261024T121013Z-head-p2-consumption-final` | daemon 继续关闭消费 | 2/2/0/0 | 2 | 0 | 6.711s | 2.129s |

上述范围有重叠，**不得相加冒充独立 TC**。head 是 105 个不同测试事件各执行两次（16 个顶层名称）；组合 governance 是 172 个事件各两次（30 个顶层名称）。首轮 head 原 51 个事件，本轮增加 54 个组件事件；其中只有负零 2 个子用例及其父事件被证明曾 RED。

精确基础命令（最终 extras `-shuffle=on -count=2`；runner 固定先放 `-count=1`，实际最终 argv 完整保存在 meta）：

```text
go test ./internal/governance -run '^TestExecutionAuthorizationHead' -count=1 -json -shuffle=on -count=2
go test ./internal/governance -run '^(TestExecutionAuthorizationRoute|TestExecutionAuthorize)' -count=1 -json -shuffle=on -count=2
go test ./internal/governance -run '^(TestExecutionAuthoriz|TestExecutionGrantCheckAgainstRealCrctlCLI|TestDaemonAuthenticatedDeliveryRunsCrctl|TestDaemonFetchesAndInstallsExecutionAuthorization)' -count=1 -json -shuffle=on -count=2
go test ./cmd/server -run '^TestExecutionAuthorizationHeadRouter' -count=1 -json -shuffle=on -count=2
go test ./internal/daemon -run '^(TestExecutionVerifierRequiresExplicitNegativeFacts|TestClaimedExecutionTaskCannotStartOnRootAttributionAlone)$' -count=1 -json
```

额外首次 router 运行 `20261024T120707Z-head-p2-router-configured.*` 为 5/5、exit 0、9.196s，亦保留。所有 stderr 为空。原始 JSONL 有真实选中 run/pass、shuffle seed 和 package elapsed，没有将 skip/空选中当作绿。

静态证据 `20261024T121137Z-head-p2-static.*`：三文件 gofmt-l 无输出（0.022s），`go vet ./internal/governance ./cmd/server` 退出 0（1.394s），三文件无尾随空白。没有安装全局依赖。

## 6. 版本化证据与剩余风险

- 新 manifest：`initial-head-p2-source-manifest.json`（schema v2），引用原 `initial-head-source-manifest.json` 及其 LF-normalized SHA256 `3af26aa2ec5293fcf987b2ac54624f4fcc0fe0d0bc0064a720e4b5268598dce0`；原文件保留。
- 17 个初片文件中，恰好本轮 3 文件改变，其余 **14/14** 与原 manifest 一致；SQL、生成物、迁移、router 生产接线、initial POST 均未变。
- 只对普通源码/文档哈希做 CRLF→LF；原 signed payload/source buffer 从未因此归一化。
- 最终 raw/meta 的源码 hash 与 v2 manifest 相同；P2 RED 的生产 hash 与 v1 相同。
- 旧残留 38 条保留，清理其他模块的 TestMain/fixture 不在本轮修改范围。并发测试证明正常提交下 CR 锁串行化，不证明故障恢复或所有分布式 exactly-once 性质。
- 当前 GET 仍只读 snapshot，不是 claim/binding/revoke 或 freshness admission；消费继续关闭，revoke 方案仅保留，不实施。
- harness 元数据仅：`PI_PROVIDER=OpenAIPersonal`、`PI_MODEL=gpt-6.1-sol`、`PI_REASONING_LEVEL=high`；真实 backend 身份仍未知。

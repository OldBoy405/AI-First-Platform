# 精确恢复空 origin/digest 守卫：独立 strong 复审

**结论：这项局部改动限定 PASS。** 只适用于 `CheckDeploymentAccessTx` 在 STOP_NEW 或 ACTIVE 过期时的恢复分支：origin/digest 的持久值为空时拒绝。

本审核**不**宣称以下任何一项已经解决：
- 带空白字符的字符串（比如 `" "`）是否合法；
- 恢复字段是否绑定到 DB 中的请求；
- `in.Now` 是否可信；
- head/STOP_NEW 的锁竞态；
- 签名认证。

本审核也不构成 RUN-006 或任何 RUN/TC 的验收，不是 DB 证据。

- 方式：静态阅读和 diff，另外跑了一次不连 DB 的子包测试（见 §4）。没有改源码，没有连 DB 或容器，没有操作 CR。旧报告一律没动，本文是新文件。
- multica HEAD：`81e5293adc758e392a045026cf81ec5cc1bac72d`，工作区不干净。

## 1. 审核对象（本次 `sha256sum` 独立复验）

| 对象 | 原始 SHA-256 |
|---|---|
| live `server/internal/governance/execution_deployment.go`（**reviewed**） | `0d9773985591f63035c7bc706d9e406e1a929f2bed990235b5d0d287cea96e0a` |
| live `server/internal/governance/deploymentaccess_test/execution_deployment_test.go`（**reviewed**） | `e556f9b8e532669cfbec72fb34b364d991842cb3d2aadb15d2a459d75d758032` |
| `source-recovery-zero-final/execution_deployment.go`，即上一轮审过的版本 | `449216c3469c48cdc7bb33fd9e138bd632bfabf0c95815f891fb00bab446178a` |
| `source-recovery-zero-final/execution_deployment_test.go` | `2a5bcd5fae7d965a74a96263940c30aa32d36775882fbacdd7ac1cbfbd9a0de5` |
| `AUTHOR-RECOVERY-EMPTY.md` / `RECOVERY-EMPTY-PLAN.md` | `f537d8a0…59a8` / `a3a1813a…790d` |
| 上一轮报告 `UNKNOWN-MODE-RECOVERY-ZERO-REVIEW-STRONG.md`（没改） | `5e58e850a0eaa52761d6865e86a046a54001f5a776f3405db672daf04dcbc96c` |

## 2. diff 的内容（忽略 CR 差异的 `diff -u`）

- **源码只改了一处**，在 L537–538。
  - 改前：`if P_o != O || P_d != D { Denied }`
  - 改后：`if P_o == "" || P_d == "" || P_o != O || P_d != D { Denied }`
  - 记号：P_o 为 `PersistedOriginRef`，O 为 `OriginRef`，P_d 为 `PersistedDigest`，D 为 `Digest`。
  - 其他行都没变，Generation、IssuedAt、未知 mode 的检查和上一轮审过的版本完全相同。
- **测试只在 `TestRecoveryRejectsMissingOrInvalidIdentityFacts` 的用例表里加了两行**：`both_origins_empty` 和 `both_digests_empty`。每行在 STOP_NEW 和 ACTIVE 过期两种状态下各跑一次，共 4 个新子例。旧用例都没改。

## 3. 布尔表达式逐项核对

改后的放行条件（取上面拒绝条件的反面）是：`P_o != "" && P_d != "" && P_o == O && P_d == D`。由于要求相等，这也意味着 `O != ""` 且 `D != ""`。

| 情形 | 结果 | 由哪一项拒绝 | 测试覆盖 |
|---|---|---|---|
| origin 两边都空 | Denied | `P_o == ""` | 有（新增 2 个子例） |
| digest 两边都空 | Denied | `P_d == ""` | 有（新增 2 个子例） |
| 只有持久值为空（`P_o=""`，`O="x"`） | Denied | `P_o == ""`，同时也不相等 | **没有专门用例**，只是静态推导 |
| 只有输入值为空（`P_o="x"`，`O=""`） | Denied | `P_o != O` | **没有专门用例**，只是静态推导 |
| digest 只有一边为空 | Denied | 同上 | **没有专门用例**，只是静态推导 |
| 都非空但不相等 | Denied | `!=` | 有：现有的 `changed_origin`、`changed_digest` |
| 都非空且相等，Generation 也有效 | ExactRecovery | — | 有：现有的 `complete_original`、`bind_original` 正控 |
| `" "` 这类带空白的值，两边相同 | **放行** | — | 不检查空白和格式，本审核**不宣称合法** |

- 单侧为空的情形不可能放行：要么被 `== ""` 拒，要么被 `!=` 拒。但测试只覆盖了两侧同时为空，单侧为空靠的是表达式本身。建议补 4 个用例（只是提议，未实施）：origin 和 digest 各自的"只有持久值为空"和"只有输入值为空"。
- 新增用例只用了 `complete_unsettled_request`。`bind_existing_mapping` 和它在同一个 `case` 分支（L535），按代码结构结果相同，但没有专门测试。
- **原有语义是否保持：**
  - 非空且相等的恢复正例仍然返回 `ExactRecovery`（§4 实际运行通过）。
  - ACTIVE 且未过期时，两个恢复 op 仍然返回 `NewAdmission`，不检查 origin 和 digest。这是有意保留的旧语义，本次没有评估。
  - 未知 mode、审计、denyOps 这几条路径都没变。

## 4. 是否运行了测试：**运行了一次，只跑不连 DB 的子包**

- 环境：去掉 `DATABASE_URL` 和 `PGHOST`/`PGPORT`/`PGUSER`/`PGPASSWORD`/`PGDATABASE`，设置 `GOPROXY=off`、`GOWORK=off`，Go 版本为 go1.27.1 windows/amd64。
- 命令：在 `multica/server` 下执行 `go test -count=1 -v ./internal/governance/deploymentaccess_test`。
- 运行前确认过三点：子包里没有 `TestMain`，不读环境变量，`governance` 包没有非测试的 `init()`。
- 结果：
  - exit 0；
  - 顶层 `--- PASS` 7 个，子例 `--- PASS` 79 个；
  - `--- FAIL` 0，`--- SKIP` 0；
  - 4 个新子例（`stop_new|active_expired / both_origins_empty|both_digests_empty`）都通过。
- 运行前后，源码和测试的 SHA 都没有变化。
- 运行日志只写在临时文件 `/tmp/dacc-review.log`（SHA-256 `892ddcd000f7499303e70db9ab87d7dc51a5ef781b8dd092f24f0d8e72cf6d76`），没有归档进仓库。
- **这只证明 fakeTx 层的行为**：不涉及 DB、签名、锁或生产接线。**我没有复跑作者的 overlay 变异测试**，所以"去掉守卫测试就变红"仍然只是作者证据。不过它和静态推导一致：旧表达式在两侧都为空时成立相等，会返回 ExactRecovery。

## 5. fakeTx 与 schema 中的条件

- **fakeTx：** `accessTx` 的查询步骤只有 head、event，以及 ACTIVE 时的 readiness。origin、digest、generation、IssuedAt、AdmissionSeq 全部来自 `input()` 构造的调用方输入，**没有任何一个经过假 DB 查询**。新用例也没有改 fakeTx。
- **schema（migration 648，SHA `89f0c3f0…5b61`）：** 有多处 `length(digest) = 64` 之类的 CHECK（例如 L133、L234、L307）。但 `CheckDeploymentAccessTx` **不从任何表读取** `PersistedOriginRef` 或 `PersistedDigest`。所以这些 schema 约束**约束不到**本函数的输入。持久值实际对应哪张表、哪一列，没有核实。
- 因此，这次的"非空"检查只是对调用方输入的形状检查，不能当作 DB 原事实或权威事实。

## 6. 仍未解决（都不属于本切片，全部维持 BLOCK）

1. 恢复字段由调用方传入，`RequestID` 在函数里没有用到，也没有回查 DB。
2. `in.Now` 由调用方控制（L470–473），可以把已过期的 ACTIVE 判成未过期。
3. head 和 event 的查询没有 `FOR UPDATE`，head/STOP_NEW 存在竞态。
4. readiness 签名和 `signedReadinessTx` 的正文没有审。
5. 没有任何生产调用方。

**RUN-006 仍为 MISSING，Gate3 不受影响。**

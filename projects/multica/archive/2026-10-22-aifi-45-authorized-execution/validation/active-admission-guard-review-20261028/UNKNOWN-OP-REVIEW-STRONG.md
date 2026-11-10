# ACTIVE 未知操作默认拒绝：独立 strong 审核（只读、有界）

**结论：对本切片的局部改动限定 PASS。** 只适用于 `CheckDeploymentAccessTx` 在 ACTIVE 且未过期分支对未知 op 的分类，并且只在假事务测试的层面成立。**不构成** RUN-006 或任何 RUN/TC 的验收，**不证明**生产入口已经接通、签名认证、DB 语义或锁竞态。

- 方式：静态阅读和 diff。没有改代码，没有跑测试，没有连 DB 或容器，没有操作 CR。本文是本次唯一新写的文件。
- multica HEAD：`81e5293adc758e392a045026cf81ec5cc1bac72d`，工作区不干净。行号按下表 SHA 对应的工作区文件计。

## 1. 指纹（本次 `sha256sum` 独立复验）

| 对象 | 原始 SHA-256 | 是否与委托一致 |
|---|---|---|
| live `server/internal/governance/execution_deployment.go`（544 行） | `dc6407f98b07fbd63d7c039a5db497a9540b3dd674206b320b3e31cd92a18e7b` | 一致 |
| live `server/internal/governance/deploymentaccess_test/execution_deployment_test.go`（252 行，已全文读完） | `8dd07c9609f5657d39b45a991cc6ba2d18be8f9bd2167437187b09f2d5d69adf` | 一致 |
| `source-unknown-op-before/execution_deployment.go` | `f1e719d9388c09eadecc9da17aa21bdafb080265237fabd8b58dc0f50b728811` | 与作者声明一致 |
| `source-unknown-op-before/execution_deployment_test.go` | `c30f2816bd0f48359941f1993f85273feb481bc2169b6abc688d0b5f68b573f0` | 与作者声明一致 |
| `AUTHOR-UNKNOWN-OP-MUTATION.md` | `d1c253be723b63bc8cd1dfa94d1b28da60ab2134eec3979d216935c85a58ad41` | — |
| `AUTHOR-UNKNOWN-OP.md` | `0eb25de8b04808a37cc9219eba09acf31be2c52f45300f48abbb7c3efe4453bf` | — |
| `UNKNOWN-OP-PLAN.md` | `54e12c1304b3bbd2ea354e4d972b3a805a30319713128c3db034fa6fd993613b` | — |

## 2. diff 的实际内容（忽略 CR 差异的 `diff -u`）

- **源码只有一处改动**，在 L512–515。ACTIVE 且未过期、op 不属于 auditOps 时：
  - 改前：无条件返回 `AccessNewAdmission`。
  - 改后：只有 `denyOps[in.Op]`，或 op 为 `complete_unsettled_request` / `bind_existing_mapping` 时，才返回 `AccessNewAdmission`；其余一律返回 `AccessDenied`。
  - 其他行都没有变。
- **测试只在文件末尾追加**（L227 起），旧测试没有改动：
  - `TestKnownRecoveryOperationsOnActiveDeployment`：ACTIVE 状态下两个恢复 op 仍然返回 `NewAdmission`，这是保留行为的正控。
  - `TestUnknownOperationIsDenied`：`future_operation` 在 4 种状态下都要求 `Denied`。

## 3. 逐项核对

1. **ACTIVE 未知 op 是否 fail-closed：通过。**
   - 按 L508–515，ACTIVE 且未过期时，op 先查 audit，再查 7 个已知动作，剩下的返回 Denied。
   - op 按字符串精确匹配，没有做大小写或空白归一化。所以变体写法（比如 `New_Admission`、带尾随空格）会被拒绝，方向是 fail-closed。
   - 空 op 在 L467 就报 `ErrDeploymentInvalid`，走不到这里。
2. **允许列表有没有漏掉已知动作：在代码内部的闭集里，没有漏。**
   - 函数里出现的 op 一共 12 个：denyOps 5 个（L454–457）、auditOps 5 个（L460–463）、恢复动作 2 个（L532）。
   - 改后的 ACTIVE 分支覆盖了全部 12 个：audit 5 个返回 AuditOnly，其余 7 个返回 NewAdmission。
   - 全仓 `.go` 文件里，这些 op 字符串只出现在本文件和两个测试文件里。平台仓 `projects/multica` 下（不含 validation）的规格和设计文档里，**找不到这些 op 名**。
   - **限制：** op 集合没有规格层面的权威来源，"没有漏掉"只是相对代码自身的闭集而言。如果以后加了新 op 却忘了登记，它会被拒绝（fail-closed，可能影响可用性），不会被误放行。
3. **其他状态是否保持不变：通过（逐行核过）。** 缺 head（L479–486）、非 ACTIVE 或已过期（L517 起，含精确恢复的 switch）都没有改动。
   - 未知 op 在这些状态下，改前就已经落到 `default: AccessDenied`（L541–542）或 L485。所以新测试的 stop_new、active_expired、missing_head 三个子例改前改后都通过，**只有 active_unexpired 能起到 RED 作用**。
   - mode 不是 `ACTIVE`/`STOP_NEW` 的未知值（L30–31 只定义了这两个）会走非 ACTIVE 分支，未知 op 同样被拒。这一点没有测试覆盖。
4. **正式生产调用是否存在：不存在。** 在非 test 的 `.go` 文件里 `git grep CheckDeploymentAccessTx`，只命中定义本身（L466）。直接调用方只有 `deploymentaccess_test` 和 `execution_deployment_retirement_test.go`。因此本修复**没有接到任何生产入口**，不能据此声称线上准入已经 fail-closed。
5. **所依据的信任与生命周期限制（本切片都没有处理）：**
   - `DeploymentAccessInput` 的注释（L435）说 op 和原事实"由服务端路由 + DB 原事实解析"。但目前没有生产调用方，Op、AdmissionSeq、IssuedAt、Persisted*、Generation 实际上都是调用方传入的值。精确恢复里的零值放行（比如 L536 在 Generation 为 0 时跳过比较；L527 在 IssuedAt 为零时跳过比较）仍然存在。
   - head 和 event 的查询（L474–477、L493–495）没有 `FOR UPDATE`，head 与 STOP_NEW 的竞态不在本切片范围。
   - readiness 的提取（`signedReadinessTx`）、签名认证、activation 身份都没有审。
   - ACTIVE 状态下两个恢复 op 返回的是 `NewAdmission` 而不是 `ExactRecovery`，也没有逐字段比较。这是改前就有的语义，本切片有意保留，没有评估它是否合理。
6. **对作者变异证据的评估（只作为作者证据）：**
   - `AUTHOR-UNKNOWN-OP-MUTATION.md` 写的是：用 overlay 只把源码换回旧 SHA `f1e719d9…`，测试用新 SHA `8dd07c96…`，结果 exit 1，失败信息为 `future_operation = NewAdmission, want Denied`，另外 3 个状态通过；移除 overlay 后 1 个顶层、4 个子例 PASS。
   - 这和本次静态推导完全一致：旧源码在 ACTIVE 下返回 NewAdmission，另外 3 个状态改前就是 Denied。所以它在逻辑上**能够**证明"去掉 guard 后测试会变红"，而且失败原因是断言不符，不是编译错误。
   - **但本次没有复跑。** 运行日志、overlay JSON 和 exit code 都没有作为文件保留（作者写明已删除），所以无法独立复核，只能算作者自述的证据。
   - `AUTHOR-UNKNOWN-OP.md` 声称"61 个 leaf PASS"。我按测试源码静态数了一遍：20 + 20 + 15 + 2 + 4 = 61，与声称一致，但同样没有复跑。
   - CUSTOM.md L923 有 #271 的登记条目。

## 4. 本次完全没审的对象（不得引申）

- governance 包里其他未提交改动的文件：`execution_admission_gate.go`、`execution_control_store_state.go`、`execution_notice.go`、`runner.go` 等。
- `execution_deployment_retirement_test.go`（DB 集成测试）、`signedReadinessTx`、migration、cursor 和初始 fence。
- 任何真实部署的状态。

**RUN-006 仍然是 MISSING，Gate3 结论不受本审核影响。**

## 5. 解除剩余 BLOCK 的条件（不属于本切片）

1. 在规格里定下 op 合同（闭集，以及谁来负责登记新 op）。
2. 有生产调用方之后，审它如何从服务端路由和 DB 原事实得出 Op 和恢复字段，确认这些值不是调用方自报的。
3. 收紧零值恢复语义，处理 head/STOP_NEW 的锁竞态。
4. 由非作者实际复跑变异测试，并留存日志。

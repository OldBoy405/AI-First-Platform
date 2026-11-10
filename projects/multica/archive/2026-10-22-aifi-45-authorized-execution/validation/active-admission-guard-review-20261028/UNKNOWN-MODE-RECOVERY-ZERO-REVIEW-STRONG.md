# 未知 mode 拒绝与恢复零值收紧：组合最终源码的独立 strong 审核（只读）

**结论：两项局部改动都限定 PASS，但恢复路径仍有未闭合的零值缺口（见 §3.1），整体继续 BLOCK。**

- **未运行任何测试。** 没有改源码，没有连 DB 或容器，没有操作 CR。本文是本次唯一写入的文件。
- 不构成 RUN-006 或任何 RUN/TC 的验收，不是 DB 证据。下文中"非零""相等"都只是**调用方输入的形状检查**，不是权威事实。
- multica HEAD：`81e5293adc758e392a045026cf81ec5cc1bac72d`，工作区不干净。行号按下表 live SHA 对应的文件计。

## 1. 审核对象（本次 `sha256sum` 独立复验，都与委托一致）

| 对象 | 原始 SHA-256 |
|---|---|
| live `server/internal/governance/execution_deployment.go`（**reviewed**） | `449216c3469c48cdc7bb33fd9e138bd632bfabf0c95815f891fb00bab446178a` |
| live `server/internal/governance/deploymentaccess_test/execution_deployment_test.go`（**reviewed**） | `2a5bcd5fae7d965a74a96263940c30aa32d36775882fbacdd7ac1cbfbd9a0de5` |
| `source-unknown-mode-final/execution_deployment.go` | `feab73bd1f79bba2661f8db3808ddaf306c7a854e11664047c83e45651fbfd9b` |
| `source-unknown-mode-final/execution_deployment_test.go` | `65bc2ea93b22ddbbf118f5875cf17413587e6d0b12791eecb118a4eef2adb496` |
| `source-unknown-mode-before/execution_deployment.go` | `dc6407f98b07fbd63d7c039a5db497a9540b3dd674206b320b3e31cd92a18e7b` |
| `source-unknown-mode-before/execution_deployment_test.go` | `8dd07c9609f5657d39b45a991cc6ba2d18be8f9bd2167437187b09f2d5d69adf` |
| `server/migrations/648_cr_execution_control.up.sql`（只读了 L335–349） | `89f0c3f061c73dae188f99ada0accd13ab770e72e7a96130eb70c3c8c07b5b61` |
| 作者材料：`AUTHOR-UNKNOWN-MODE.md` / `AUTHOR-RECOVERY-ZERO.md` / `UNKNOWN-MODE-PLAN.md` / `RECOVERY-ZERO-PLAN.md` | `b5b03031…44dc7` / `d6c329bf…390256` / `bf4f00b8…ef32` / `cf23ac6c…cb5cb` |

## 2. diff 的内容（忽略 CR 差异的 `diff -u`）

- **before → final（未知 mode）：**
  - 源码只有一处改动，在 event 查询之后（live L497–499）插入：`if mode != ACTIVE && mode != STOP_NEW { return AccessDenied }`。
  - 测试只新增 `TestUnknownActivationModeIsDenied`：在 `UNKNOWN_MODE` 下，2 个恢复 op、`checkpoint_ingest`、`new_admission` 都要求 `Denied`。
- **final → live（恢复零值）：**
  - 源码有两处改动：
    - L531：改为 `IssuedAt.IsZero() || (!expiresAt.IsZero() && IssuedAt.After(expiresAt))` 时拒绝。
    - L540：改为 `PersistedGeneration <= 0 || Generation <= 0 || 两者不相等` 时拒绝。
  - 测试只新增 `TestRecoveryRejectsMissingOrInvalidIdentityFacts`：STOP_NEW 和 ACTIVE 过期两种状态，各 5 个用例，共 10 个子例。
- 其他行都没有改动。按测试源码静态数子例：61 + 4 + 10 = 75，与作者声称的 75 个 leaf 一致（没有复跑）。

## 3. 逐项核对

### 3.1 恢复零值逻辑（L527–545）

- **IssuedAt：** 零值现在会被拒，正确。
  - 但 `expiresAt` 为零时（`verdict_ref` 为 NULL，L509–511；fake 测试里 STOP_NEW 就是这种情况），只剩"非零"这一条检查，**任何非零时间都能通过**。
  - IssuedAt 不和 `now` 比，也不和 STOP_NEW 的生效时刻（event 的 `committed_at`）比，也不和 cutoff 对应的签发时刻比。
  - 比较用的是严格的 `After`，所以 IssuedAt 恰好等于 expiresAt 时放行。这一边界的语义没有规格依据，也没有测试。
- **Generation：** 0 和负数现在会被拒，两者必须相等，正确。
  - 但两个值**都由调用方传入**，没有和 DB 中 activation event 或 deployment 的 generation 比较。只要调用方传两个相等的正数，就能通过。
- **【未闭合，当前缺陷】origin 和 digest 的零值：** L537 只比较相等，**空字符串等于空字符串**。
  - `PersistedOriginRef == OriginRef == ""` 且 `PersistedDigest == Digest == ""` 时，这一关会放行。
  - 再配合 AdmissionSeq 在 cutoff 内、IssuedAt 非零、两个 generation 相等且为正数，就会返回 `ExactRecovery`。
  - 本次零值收紧没有覆盖这两个字段，测试里也没有空 origin 或空 digest 的用例。这是"零值恢复"的同类缺口，应当以 fail-closed 方式补上 RED/GREEN。下面是提议，未实施：
    - 在 STOP_NEW 和 ACTIVE 过期两种状态下，四个字段分别置空、以及两两同时置空，都应返回 `Denied`；
    - 当前实现预计会返回 `ExactRecovery`，也就是 RED。
- **AdmissionSeq：** `<= 0` 或 `> cutoff` 时拒绝（L527）。下限正确。cutoff 取自 DB head（L474–479），但 AdmissionSeq 本身由调用方传入，也不和 `RequestID` 回查。`RequestID` 在函数里**完全没有用到**，空值也能通过。
- **两个恢复 op 走同一条代码路径**，测试只用了 `complete_unsettled_request`，`bind_existing_mapping` 没有单独的零值用例。按代码结构，两者结果相同，这一点只是静态推断。

### 3.2 未知 mode 分支（L497–499）

- 判断是精确字符串比较。空串、小写 `active`、其他任何值都返回 `Denied`，fail-closed。判断发生在读 readiness 之前，因此不会对未知 mode 发起 readiness 查询；fake 测试的步数检查也与此相符。
- **行为变化：** 未知 mode 下，审计 op 从 `AuditOnly` 变成了 `Denied`。而缺 head 时（L480–485），审计 op 仍是 `AuditOnly`。这种不对称是 fail-closed 方向，作者测试也明确断言了 `checkpoint_ingest` 为 `Denied`。它是否符合"审计永远可读"的规格意图，**没有规格依据**，留作设计确认。
- 这修复了我上一份更正报告 `UNKNOWN-OP-REVIEW-STRONG-CORRECTION.md`（SHA `2ef9bae1…2f59`）指出的"未知 mode 被当作 STOP_NEW 处理、可能返回 ExactRecovery"的问题，至少在函数层面已不再依赖 DB CHECK 兜底。
- **schema：** 648 L347 有 `CHECK (mode IN ('ACTIVE','STOP_NEW'))`。在受约束的 DB 里，这个分支本来就走不到。fake 测试构造的异常状态不代表 DB 里出现过这种状态。实际部署是否应用了 648，没有核实。

### 3.3 ACTIVE / STOP_NEW / 审计 是否保持不变

- 在 ACTIVE 且未过期（L512–520）、denyOps 拒绝（L521）、审计放行（L525）这几处，本次两项改动都没有碰。
- ACTIVE 过期和 STOP_NEW 共用恢复分支，只受 §3.1 的收紧影响。
- ACTIVE 下两个恢复 op 仍然返回 `NewAdmission`，没有逐字段比较。这是有意保留的旧语义，本次没有评估。

### 3.4 信任来源、调用方可伪造、锁、签名、过期事实（都是改前就有、本次未修的问题）

- **调用方可伪造：**
  - `DeploymentAccessInput` 的全部恢复字段都由调用方传入，包括 Op、AdmissionSeq、IssuedAt、Persisted*、Generation、RequestID。
  - L435 的注释说这些值"由服务端路由 + DB 原事实解析"，但没有生产调用方，这个说法**没有落地**。
- **过期事实可伪造（重要）：** `now` 取自 `in.Now`（L470–473），只有零值时才用服务器时钟。
  - 调用方传一个过去的 `Now`，就能让已过期的 ACTIVE 被判为未过期（L508）。这样新动作会拿到 `NewAdmission`。
  - 这条缺口不属于本次两个切片，但它直接削弱了"过期后只允许精确恢复"的保证，应当单独 RED。
- **锁：** head（L476–479）和 event（L492–494）的查询都没有 `FOR UPDATE`。readiness 查询按 fake 测试的片段带 `FOR UPDATE`，但 `signedReadinessTx`（L73）的正文本次没有读。head/STOP_NEW 竞态仍然未闭合。
- **签名：** readiness 的签名是否被认证、manifest 从哪里来，本次都没有审。fake 测试直接提供 `verdict_bytes`，不证明签名。
- **生产接线：** 在非 test 的 `.go` 文件里 `git grep`，只命中定义本身（L465–466），没有生产调用方。

### 3.5 作者证据（只作为作者证据，没有复跑）

- `AUTHOR-UNKNOWN-MODE.md`：在旧源码上，两个恢复 op 返回 `ExactRecovery`，`checkpoint_ingest` 返回 `AuditOnly`，`new_admission` 返回 `Denied`。这与我对 `dc6407f9` 源码的静态推导一致，说明 RED 是断言不符，可信度合理。
- `AUTHOR-RECOVERY-ZERO.md`：用 overlay 分别换回旧的 IssuedAt 检查和旧的 generation 检查，结果分别有 2 条和 8 条断言失败。
  - 静态核对：2 种状态 × 1 个 issued 用例 = 2；2 种状态 × 4 个 generation 用例 = 8。数字一致。
  - 运行日志没有留存，无法独立复核。

## 4. 本次完全没审的对象

- `signedReadinessTx` 的正文、readiness 签名和 manifest；
- migration 648 除 L335–349 以外的部分；
- `execution_deployment_retirement_test.go`（DB 集成测试）；
- governance 包里其他未提交改动的文件；
- cursor 和初始 fence；
- 任何真实部署的状态。

**RUN-006 仍为 MISSING，Gate3 不受影响。**

## 5. 解除 BLOCK 的条件（不属于本次两个切片）

1. 对 origin/digest 的空串补上 fail-closed（§3.1），并提交 RED→GREEN 证据。
2. 过期判断改用服务器时钟，或者对 `in.Now` 做可信约束（§3.4），并提交 RED→GREEN 证据。
3. 恢复字段改为在服务端由 `RequestID` 回查 DB 原事实，不再由调用方传入；generation 要和 DB 中当前的 deployment/activation generation 绑定。
4. 处理 head/STOP_NEW 的锁竞态，审 readiness 签名的来源。
5. 规格确认两点：未知 mode 下审计 op 是否也应拒绝；IssuedAt 恰好等于 expiresAt 时的边界语义。
6. 由非作者实际复跑变异测试，并留存日志。

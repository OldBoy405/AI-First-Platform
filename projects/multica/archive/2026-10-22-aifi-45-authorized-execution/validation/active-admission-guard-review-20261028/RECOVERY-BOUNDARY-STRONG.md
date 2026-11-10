# AIFI-45 RUN-006：CheckDeploymentAccessTx 恢复边界只读安全审查

结论：**BLOCK，不改代码。**

在本次查阅的文档范围内，未知 op 的处理和恢复时的零值语义都没有可以直接实现的明确条文。

## 审查限制

- 只读审查：结论来自读源码、测试和文档。
- 没有修改任何源码或既有证据，没有跑 go test、DB 或容器，也没有连接外部服务。
- 文中说"按读代码推断"的地方都没有实际运行确认。
- 没有审读 `ActivatePolicyTx` 的加锁顺序；`execution_deployment_test.go` 只取了哈希，未审读。
- 不对生产上线状态做任何推断。

## 依据快照

multica 仓 HEAD：`81e5293adc758e392a045026cf81ec5cc1bac72d`

### 源码与测试（路径相对 `multica/server/internal/governance/`）

| 文件 | sha256 | 状态 |
|---|---|---|
| `execution_deployment.go` | `f1e719d9388c09eadecc9da17aa21bdafb080265237fabd8b58dc0f50b728811` | 有未提交改动：HEAD blob `416912ec6554ff42f6d0a0d73dcaae904664a981`，工作区 blob `42a8af04f0c8eac15f2d0e9d393fa0fabf37e391` |
| `deploymentaccess_test/execution_deployment_test.go` | `c30f2816bd0f48359941f1993f85273feb481bc2169b6abc688d0b5f68b573f0` | 未纳入 git |
| `execution_deployment_retirement_test.go` | `2719644677c3e1c66272a3e166376f92bb1f45fb9f9298a8262d2105535d9e81` | 与 HEAD 一致 |
| `execution_deployment_test.go` | `31a114d7b822b52b48dcedcb877dabb1165430b537f4cba2674c8e662aed2520` | 只取了哈希，未审读 |

`execution_deployment.go` 的未提交改动只有一处：把 `denyOps` 判断挪到 ACTIVE 分支之后。改动前先判 `denyOps`，会导致 ACTIVE 状态下的 `new_admission` 等动作被拒绝。

### 文档（路径相对 `projects/multica/`）

| 文件 | sha256 |
|---|---|
| `archive/2026-10-27-trusted-verdict-channel/design.md` | `73834bd4bfbbb6b16384387e05ee09a899bbde034170ccf25a33e709c02586f8` |
| `archive/2026-10-27-trusted-verdict-channel/design-adjustments.md` | `ba5dadd66212a2f156a8f18cd3e587db9da25b793e16de0f4c26b98e4e377382` |
| `archive/2026-10-27-trusted-verdict-channel/specs/deployment-readiness/spec.md` | `d8efbf32e3d110936aa9a92f3646d30adcf15e2a5542b140283fe6262abf05f8` |
| `archive/2026-10-27-trusted-verdict-channel/canonical/specs/code/deployment-readiness.yaml` | `9bf51e01797cb1b57277065b75bef7a44e6c153db51f976fb9df222c6d02a010` |
| `archive/2026-10-27-trusted-verdict-channel/validation/aifi45-run-tc-rerun-prerequisites.md` | `98f1e0512516dcb0cc7011d2462a215fdb432208fcba16b409ff9c7a57f8013d` |
| `changes/2026-10-22-aifi-45-authorized-execution/design.md` | `c97d10135d1f3ad1783ac2d39d3343123e89428b415e1579436fd8084bcfec3b` |
| `changes/2026-10-22-aifi-45-authorized-execution/activation-semantics.md` | `eb0a084a231b4c2cf3efc15e514b14792ce2e89356df3c39c494ee98d789a4a6` |

## 发现

行号以上述 `execution_deployment.go` 的工作区版本为准。

### 1. ACTIVE 状态下未知 op 默认放行（L508-513）

**代码行为**

- ACTIVE 且未过期时，凡是不在 `auditOps` 里的 op 都返回 `NewAdmission`。
- 拼错的 op、任意字符串都算在内；恢复类 op `complete_unsettled_request` 也会拿到 `NewAdmission`。
- L467 只拦住空字符串。

**规范情况：查到的闭集条文都不覆盖 access op**

- `design.md` §7（L117）的「未知 code 拒绝」只管 verdict 错误码。
- `design.md` §8（L129）的 action 闭集只管 readiness action（`verify-channel|enable-policy|retire-legacy-relay`）。
- SC-DR-006（`spec.md` 约 L48-55；canonical yaml L57-67）只规定 issued 请求精确恢复、新候选拒绝、换 origin 拒绝，没有列举 op 集合，也没说未知 op 该怎么处理。
- 两份 `design.md` 和 `design-adjustments.md` 都检索不到 access op 闭集。

**缺口**

- 未知 op 该返回 `Denied` 还是 `ErrDeploymentInvalid`，没有定下来。
- ACTIVE 状态下恢复类 op 该映射成什么，也没有定下来。

### 2. 零值让恢复校验失效

**generation（L534）**

- 任意一侧为 0 就跳过比较。例如 `PersistedGeneration=1, Generation=0` 会得到 `ExactRecovery`。
- 部分依据：SC-DR-006 AND 条款写的是「不移除 cutoff/pin/generation 校验」，代码注释也写「换 generation 都不是恢复」。
- 缺口：0 是否可能合法地表示「旧请求没有 generation」，文档没有说。

**issuedAt（L525）**

- `IssuedAt` 为 0 时跳过检查。
- `StopNewAdmissionsTx` 写 STOP_NEW 事件时不写 `verdict_ref`，因此 `expiresAt` 是零值，这条检查在 STOP_NEW 下整体不生效，只剩 cutoff 序号检查（L521）。
- 正常签发时 `IssuedAt` 一定有值（L301）。
- 缺口：零值是否必须拒绝，文档没有规定。

### 3. 输入完全由调用方提供，这条路径也没有验签

- `in.RequestID` 在函数里没有被使用。
- `AdmissionSeq`、`IssuedAt` 和 `Persisted*` 字段全部来自调用方，不会去 DB 回查 admission 与 request 的绑定关系。这与 `DeploymentAccessInput` 注释「由服务端路由 op + DB 原事实解析」不符。
- `signedReadinessTx`（L73-92）只做 `json.Unmarshal`，没有验签。
- access 路径不检查 verdict 的 action/code/ready/generation，过期时间直接用 DB 的 `expiry` 列。
- 函数完全不读 `cr_execution_deployment_head`，部署 generation 不在这里核对。

### 4. 与 `StopNewAdmissionsTx` 的锁竞态

- Check 读 `cr_execution_policy_activation_head` 时没有 `FOR UPDATE`（L476-479）；Stop 读同一行时加了 `FOR UPDATE`（L216-219）。
- 在 READ COMMITTED 下，Check 可能先读到 ACTIVE，随后 Stop 提交，Check 仍然返回 `NewAdmission`。
- 能否兜住，要看调用方会不会在锁内再走一次 `IssueAdmissionTx`。目前没有生产调用方，无法核实。
- Check 不持有 head 锁，看起来不会和 Stop 形成死锁。`ActivatePolicyTx` 的加锁顺序未审读，这一点未核实。

### 5. 调用方

- 非测试代码里**没有任何调用方**，生产路径没有接入这个函数。
- 测试调用：
  - `execution_deployment_retirement_test.go`：L166 调 `StopNewAdmissionsTx`，L190-258 调 `CheckDeploymentAccessTx`（这组要连 DB）。
  - `deploymentaccess_test/execution_deployment_test.go`：L132 用 fake tx 调 Check，不连 DB。
- 现有测试都用已知 op 和 `Generation=1`，`IssuedAt` 取真实签发值，**没有覆盖未知 op 和零值**。

## 待裁定点（三项，裁定前暂不实施）

1. **op 闭集的范围。** 候选范围是现有 `denyOps`、`auditOps`，加上 `complete_unsettled_request` 和 `bind_existing_mapping`。同时要定：未知 op 返回 `Denied` 还是返回 error。
2. **恢复零值。** 恢复时 `generation` 和 `IssuedAt` 是否必须大于 0 且严格相等。
3. **ACTIVE 下恢复类 op 的映射。**

## 裁定后的最小切片（不连 DB）

**改动范围**：只改 `CheckDeploymentAccessTx` 的分支，不改函数签名。

**红绿测试**：加到 `deploymentaccess_test`，复用其中的 fakeTx。STOP_NEW 模式下只有 2 次查询。

| 用例 | 当前结果（红） | 目标结果（绿） |
|---|---|---|
| ACTIVE 未过期 + `"bogus"` | `NewAdmission` | `Denied` 或 error（按裁定点 1） |
| ACTIVE 未过期 + 恢复类 op | `NewAdmission` | 按裁定点 3 |
| STOP_NEW + `PersistedGeneration=1, Generation=0` | `ExactRecovery` | `Denied`（按裁定点 2） |
| STOP_NEW + `PersistedGeneration=0, Generation=2` | `ExactRecovery` | `Denied`（按裁定点 2） |
| ACTIVE 已过期 + `IssuedAt` 为零 | `ExactRecovery` | 按裁定点 2 |

**对现有 API 的影响**

- 签名不变，只是部分返回值从 `NewAdmission` / `ExactRecovery` 变成 `Denied`。
- 没有生产调用方，所以没有运行期影响。
- 按读代码推断，现有 fake 测试和 DB 测试不受影响；未实际运行确认。

## 剩余风险

- 发现 3、4（输入由调用方提供、没有验签、不读部署 head、锁竞态）属于接线和设计层面的问题，这个无 DB 切片解决不了。须在接入生产调用方之前另外立项定案。
- 当前未提交的 `denyOps` 顺序调整应当保留：去掉它会让 ACTIVE 状态下的 `new_admission` 被误拒，而 `TestNewOperationsByActivationState` 预期这时返回 `NewAdmission`。

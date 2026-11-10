# ACTIVE 准入守卫局部修复 — 独立审查（STDD strong）

> 范围：仅 `CheckDeploymentAccessTx` 中 `denyOps` 判定顺序的局部修复及其伪 Tx 单测。
> 不是 TC 证据：**不计 TC-RUN-006**，不改变台账 MISSING、BUILD 状态或 Gate3 NO-GO。
> 审查者未修改任何源码 / 测试；未运行 DB、容器或其他包。

## 1. 被审对象（审查者独立计算 raw SHA-256）

| 文件（相对 `C:/Users/GOBAO/Downloads/AI/multica/server`） | 独立计算 SHA-256 | 与作者值 |
|---|---|---|
| `internal/governance/execution_deployment.go` | `f1e719d9388c09eadecc9da17aa21bdafb080265237fabd8b58dc0f50b728811` | 一致 |
| `internal/governance/deploymentaccess_test/execution_deployment_test.go` | `c30f2816bd0f48359941f1993f85273feb481bc2169b6abc688d0b5f68b573f0` | 与作者更正后完整值一致（作者首次给出值为 63 位、缺 `57`，已由作者更正） |

- 两文件均 0 个 CR（纯 LF）；测试文件 225 行。
- 实跑后复算两 SHA，未变化。
- 工作树状态：`execution_deployment.go` 为 `M`（相对 HEAD `81e5293adc758e392a045026cf81ec5cc1bac72d`，HEAD blob `416912ec6`，工作树 blob `42a8af04f`）；`deploymentaccess_test/` 未跟踪。均未提交。

## 2. 改动审查

`git diff` 仅 ±3 行：将

```go
if denyOps[in.Op] {
	return AccessDenied, nil
}
```

从 `if mode == ActivationModeActive && !expired { ... }` 之前移到其后（现第 514 行），其余未变。

| 维度 | 结论 |
|---|---|
| ACTIVE + 未过期的 `new_admission/new_selection/command_issue/new_candidate/new_effect` | Denied → NewAdmission；缺陷修复 |
| STOP_NEW / 过期 | 上述 deny op 仍在 audit 与精确恢复之前返回 Denied；**未放宽** |
| audit op（`checkpoint_ingest/verdict_ingest/original_bytes_query/no_effect_settlement/resume_intent`） | 各状态结果不变（AuditOnly） |
| 未知 op | 与修复前一致：ACTIVE 未过期 → NewAdmission；STOP/过期 → `default` Denied |
| 精确恢复（`complete_unsettled_request` / `bind_existing_mapping`） | 判定代码未改 |
| 注释 | 第 453 行 “denyOps 是 STOP_NEW/过期之后一律拒绝的动作” 现与代码一致 |

结论：改动只修复 ACTIVE + 未过期被 `denyOps` 提前拒绝，最小且方向正确。

## 3. 伪 Tx 测试能否假绿

- 抗假绿：`fakeTx.QueryRow` 逐步校验 SQL 片段、参数 `reflect.DeepEqual`、调用顺序；`fakeRow.Scan` 校验目标数量与类型可赋值；`t.Cleanup` 校验查询次数恰好耗尽；`fakeTx` 嵌入 nil `pgx.Tx`，任何未预期方法调用会 panic 而非静默通过。
- 修复前应 RED：**仅为静态推断，旧版未由审查者复跑**。依据：`active_unexpired` × 5 个 deny op 期望 NewAdmission，旧代码在 ACTIVE 判断前返回 Denied，这 5 个子测必然失败。
- 不能作为下列证据：
  - **签名**：被测路径的 `signedReadinessTx`（`execution_deployment.go:73-92`）只读行、解析 JSON、取 `expiry`，不验签；fake 塞入的 `verdict_bytes` 不是签名。
  - **锁 / 并发**：fake 只匹配 SQL 文本中的 `FOR UPDATE`，不证明任何行锁语义。`CheckDeploymentAccessTx` 读 `cr_execution_policy_activation_head` 不加锁，与 `StopNewAdmissionsTx`（`FOR UPDATE`）的 TOCTOU 风险仍需调用方串行化，未被测试覆盖。
  - **真实 schema / 迁移 / 事务语义**：均未涉及。

## 4. 实跑结果（审查者独立执行，一次）

- 环境：cwd `server`；`DATABASE_URL` 与全部 `PG*` 已清空；`GOPROXY=off`；`go1.27.1 windows/amd64`。
- 命令（唯一运行）：`go test -v -count=1 ./internal/governance/deploymentaccess_test`
- 退出码 0；`ok ... 0.927s`。

| 层级 | PASS | FAIL | SKIP |
|---|---|---|---|
| top-level | 3 | 0 | 0 |
| 子测试 | 55 | 0 | 0 |

- `TestNewOperationsByActivationState`：4 状态 × 5 op = 20
- `TestAuditOperationsRemainAuditOnly`：4 状态 × 5 op = 20
- `TestExactRecoveryAfterStopOrExpiry`：2 状态 × 7 例 + `expired_issued_after_expiry` 1 = 15
- 未运行其他包、DB、容器；未运行旧版对照。

## 5. 现存风险（修复前即存在，非本次引入，均未被测试钉住）

1. **unknown op 放行面**：ACTIVE 未过期时，任何不在 `auditOps` 的 op（含未知 op、`complete_unsettled_request`、`bind_existing_mapping`）返回 NewAdmission；需设计确认是否应改为闭集 / 默认拒绝。STOP 下未知 op → Denied 亦未测。
2. **零 generation 绕过**：精确恢复中 `PersistedGeneration == 0` 或 `Generation == 0` 时跳过 generation 比较，未测。
3. **零 IssuedAt 绕过**：`IssuedAt` 为零值时跳过 “issued 晚于 expiry” 检查，未测。
4. **签名**：readiness verdict 在该读取路径不验签，依赖写入侧。
5. **并发锁**：activation head 无锁读取，与 STOP_NEW 存在 TOCTOU；伪 Tx 无法证明。
6. `CheckDeploymentAccessTx` 仍无生产调用方（见 `../run006-007-source-analysis-strong-20261028.md`），修复对生产行为暂无影响。

## 6. Verdict

**PASS（局部修复范围内）**：改动最小，仅修复 ACTIVE + 未过期被 `denyOps` 提前拒绝；STOP/过期未放宽，unknown op 与精确恢复保持既有行为；伪 Tx 单测 3/55 PASS、0 FAIL、0 SKIP。

不构成：真实签名证据、并发 / 锁证据、隔离 DB 证据、TC-RUN-006 通过或其任何部分回填。

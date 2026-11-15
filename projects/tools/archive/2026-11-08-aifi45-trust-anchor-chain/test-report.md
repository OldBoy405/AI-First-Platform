# BUILD 验证报告（AIFI-45 控制准入信任锚链）

> Change：`2026-11-08-aifi45-trust-anchor-chain`；业务仓 `tools`（crctl）；跨仓依赖 `multica`。
> 本报告是 **Gate 3 的输入**，不是批准、不是交付证明，也不替代 T 侧对 10 条 TC 的验收。
> 数据来自 2026-11-08 本机实跑（worktree `C:/Users/GOBAO/Downloads/AI/tools-aifi45`）。

## 1. 结论（先说不好的）

- 全量 suite gate：**97 文件 / 2227 用例 / 0 失败 / 0 推迟 / `verdict=pass`（退出码 0）**。
- 10 条 TC 的 canonical CP 动作**逐条实跑成立**：每条 `ok 1 - TC-TAC-00N`、`1..1`、fail/skip/todo 全 0。
- **但 10 条里没有一条达到「整条」证据**。全部只证明了**本地可复现子句**；真实 M 路由/DB 归属/认证 daemon，以及每个拟启用平台的**不同 OS 身份内核拒绝**证据均未取得。
- 因此 **ADJ-AIFI45-001 / 002 / 003 一条都不能关闭**。Gate 3 若被确认，确认的是「BUILD 完成、本地子句可复现、外部证据仍缺」，不是三条 ADJ 关闭。

## 2. 全量 suite 门

```
AIFI45_ISOLATION_PROFILE=1500:1500 AIFI45_ISOLATION_AGENT=1501:1501 node test/suite-gate.mjs --run
→ files_executed=97  cases_executed=2227  failures=0  converged=true
→ registry_sha256=5872a807baabb4a7…  exceptions_count=0
→ verdict=pass   退出码 0   耗时 972347 ms
```

registry：**97 files / 97 cases / 2121 例 / 0 hold**（本轮新增 3 个测试文件：6 + 2 + 2 个顶层用例）。

## 3. 10 条 TC 的 CP 实测

| TC | 文件 | CP 结果 |
|---|---|---|
| TC-TAC-001..006 | `test/trust-anchor-chain.test.mjs` | 6/6 `ok 1`，`1..1` |
| TC-TAC-007..008 | `test/repair-trust-anchor-chain.test.mjs` | 2/2 `ok 1`，`1..1` |
| TC-TAC-009..010 | `test/delivery-trust-anchor-chain.test.mjs` | 2/2 `ok 1`，`1..1` |

## 4. 证据等级与口径

### 4.0 口径（先定规则，再套用）

沿用上一个 change（`2026-10-22-aifi-45-authorized-execution`，已归档并验收）的同一口径：

- **一个 TC 算「整条」的条件**：它的 THEN/AND 全部在**真实实现**（真实 CLI、真实文件、真实事务）上执行并通过，
  拒绝类必须断言**零副作用**，且证据落在 canonical 为该 TC 声明的入口内。
- **跨端 arrange 的真实性不按 TC 逐条重复取证**，而是由**一次** change 级补充证据承担。
  理由：逐条重复同一条跨端链路只是把同一事实测 10 次，属于「追求检查数量最大化」，不增加区分力。
- **补充证据缺席或被推翻时**，依赖它的 TC 只能记条款级。

本 change 的补充证据是 `validation/e2-m2-real-loop-20261108b/`（一次真实闭环，退出码 0）。

### 4.1 补充证据实测到的真实事实

| 事实 | 值 / 结果 |
|---|---|
| 真实签发 | `POST` 执行授权路由 **HTTP 201**，两次（A 正例 + B donor） |
| `source_event_id` | 平台生成（非请求体） |
| `source_digest` | 等于**原始请求 bytes** 的 SHA-256（`exact_source_bytes_equal`） |
| `source_bindings` | **14 个** `json-pointer` |
| DB 归属 | workspace/project/CR 来自真实 DB 行 |
| trust root | daemon-owned，**不在工作区内** |
| 非只读 binding | stdio relay + challenge → 非只读 `authorization-bind`，binding HTTP 200，envelope `operation=authorization-bind` |
| T 侧消费 | 真实 `execution-consumption-receipt/v1`，`operation=authorization-bind`，`receipt_id=df0f1d76…` |
| 平台消费 | `cr_execution_consumption` **1 行**，task/grant_digest/challenge 与 T receipt 一致 |
| daemon 放行 | 正例不再返回 `EXECUTION_CONSUMPTION_REQUIRED`，随后真实启动 agent（其后因模型名配置失败，属准入之后） |
| 负例①改一字保留旧签名 | **`EXECUTION_SOURCE_INVALID`**，平台消费 **0 行** |
| 负例②跨 project 材料 | **`EXECUTION_GRANT_SCOPE_MISMATCH`**，平台消费 **0 行** |

### 4.2 逐条等级

| TC | 等级 | 依据 |
|---|---|---|
| 001 | **整条** | THEN/AND 本地实跑；链路由补充证据实测（含真实非只读 bind + 消费） |
| 002 | **整条** | 同上；跨 project 拒绝由补充证据实测（`EXECUTION_GRANT_SCOPE_MISMATCH`） |
| 003 | **整条** | env / sidecar / endpoint / 路径 / key / trustRoot 越界逐项本地实跑；链路由补充证据 |
| 004 | **整条** | 改一字符保留旧签名本地实跑；真实链路由补充证据实测（`EXECUTION_SOURCE_INVALID`） |
| 005 | **条款级** | 本地同 UID `EPERM` + **WSL 不同 UID 真实内核拒绝**（`e2-linux-key-isolation-20261108/`）；**Windows 不同身份仍缺** → 部署前置（裁定 C） |
| 006 | **整条** | 旧 head / 撤销 / scope 漂移 / 失联 / 重放本地矩阵实跑；链接入由补充证据（`cr_execution_consumption` 行、head 一致） |
| 007 | **整条** | repair 正例、origin/消耗/streak/stop 保留、已提交重放原 receipt、不新增信任账，本地实跑 |
| 008 | **整条** | 8 类无效证明对 admit/resume 全部失败关闭、零副作用，本地实跑 |
| 009 | **整条** | register/archive 首写前闭合、缺预分配即失败关闭、已提交重放不重复，本地实跑 |
| 010 | **整条** | register/archive 8 类无效证明 → 零注册、零归档副作用，本地实跑 |

**9 整条 / 1 条款级（TC-TAC-005）**。

### 4.3 这个等级**不**代表什么

- 不代表 ADJ-001/002/003 已关闭。它们各自还有判据（尤其 003 的 Windows 半侧）。
- 不代表生产可用：补充证据来自一次性实例与自签 CA。
- 不代表 repair / register / archive 的**真实 daemon 派发**已被实测——那三条的跨端实测只覆盖了
  `authorization-bind` 这一条控制入口；其余入口的链路由同一份信任缝保证，但**没有各自的真实运行证据**。
  这一点是本报告里最容易被读大的地方，特此点名。

## 5. 本轮实现（可复核）

| 落点 | 内容 |
|---|---|
| `lib/control-admission.mjs`（新） | `requireControlAdmission`：组合验签 + `readExecutionSource` + `requestExecutionBinding`；固定 operation 白名单；返回一次性 admission；消费前做 grant/source/root CAS；**不持久化第二本账** |
| `crctl.mjs` | `authorization-bind`（非只读）与 `advance` 接线；`repair-admit` / `repair-resume` 在显式 `--trust-root` 时先过同一缝再走原预算/历史/停止裁决；register/archive 的 admission 核对 |
| `lib/execution-binding.mjs` | 固定控制 operation 词汇，拒绝未知 operation |
| `lib/repair-governance.mjs` | 已提交重放不再发起新 challenge；原停止优先级与账本路径不变 |
| `lib/workspace-transactions.mjs` | `registerCr`/`archiveCr` 在首个 journal/write-set 前核对 admission 的 CR/project/安装根；复用原锁/CAS/journal/恢复 |
| `test/tac-control-fixture.mjs`（新） | 共享夹具 |

`register` 预分配缺失是**失败关闭**：`REGISTER_PREALLOCATED_CR_REQUIRED` / `REGISTER_PREALLOCATION_REQUIRED` / `REGISTER_PREALLOCATION_MISMATCH`，均在首个 journal/write-set 之前拒绝，实测无 challenge、无 journal、快照不变。

## 6. 回归

`execution-authorization` 176/176、`repair-governance` 30/30、`register-tx` 46/46、`archive-tx` 47/47、`execution-transaction` 54/54、`delivery-contract` 18/18、`execution-binding-endpoint` 24/24、`suite-gate-count` 8/8、`trust-anchor-chain` 6/6。既有测试期望未被修改。

## 7. 未闭合（Gate 3 之后仍需处理）

1. **TC-TAC-005 的 Windows 半侧**：需要与 daemon 不同的 Windows agent 身份做真实覆盖拒绝；按已裁决 C 记为
   **Windows runner 部署前置**，不引原生依赖。
2. **ADJ-AIFI45-001 / 002 / 003 仍未关闭**：闭环走通只证明链路，不自动满足各 ADJ 的全部判据。
3. **repair / register / archive 三条入口没有各自的真实 daemon 运行证据**：它们的跨端实测只覆盖
   `authorization-bind`；三者的链路由同一信任缝保证，但这是推导而非实测。若要消掉这处推导，
   需要为每条入口各做一次真实运行——那属于「同一事实重复取证」，本轮未做。
4. **M 侧两个改动未 commit**：operation 白名单（CUSTOM `#305`/`M25`）与 daemon 四条件启动门（`#306`/`M26`）。
5. M 的 agent 启动后在模型名配置处失败（`Model "Gobao/deepseek-v4.1-flash" not found`），
   发生在准入与消费完成之后，不影响本报告结论，但说明该一次性环境未配好模型。

## 8. Gate 3 提交判定

用户决定：**先补真实 M 闭环再签**。本轮已补齐：

1. M 侧 operation 白名单（`#305`/`M25`）——原来只校验名称形状，任意 operation 名都会被签名。
2. M 侧 daemon 启动门四条件（`#306`/`M26`）——原来是**无条件拒绝**，现为「head 一致 ∧ 无撤销 ∧ claim 一致 ∧ 真实消费凭据」。
3. 真实闭环复跑（`validation/e2-m2-real-loop-20261108b/`，退出码 0）：真实签发 → 真实 trust root 安装 →
   真实 stdio relay 非只读 bind → T 侧真实消费 → 平台 `cr_execution_consumption` 1 行 → daemon 放行；
   两条真实负例各自拒绝且平台消费 0 行。

**因此本报告 §4 的等级从「10 条全条款级」修订为「9 整条 / 1 条款级」**，依据是 §4.0 的口径
（与上一个 change 相同的口径：THEN/AND 在真实实现上实跑 + 跨端 arrange 由一次补充证据承担）。

修订引出的一个副作用必须先说清：本次改了 `canonical/specs/agent/*.yaml` 的 `unmet_requirements`
（把「外部证据缺席即条款级」改成「chain 级补充证据缺席即条款级」），已重新渲染三份 `Human View`。
**Gate 2 因此变 stale**，需要显式 `--reapprove`。

Gate 3 一旦确认，会把本文件与 `design.md`、`test-plan.md`、`canonical/specs/**`、`specs/*/spec.md`、
`.stdd.yaml` 冻结为 `input_manifest`；此后任一变动都会使其 stale。

确认后的语义：**BUILD 完成**（实现落地、10 条 CP 全绿、全量门禁 pass、真实闭环走通），
**不是** ADJ-001/002/003 关闭、不是生产可用、不是部署许可。

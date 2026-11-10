# AIFI-45 TC-RUN-003 可信裁决链独立安全调查（STDD strong，第二份报告，基于当前工作树）

- 范围：Node producer → Go `AppendVerdictFrameTx` → `AdmissionDecider`
- 源：`C:/Users/GOBAO/Downloads/AI/multica`（HEAD `81e5293ad` + 工作树改动）与 `C:/Users/GOBAO/Downloads/AI/tools`（HEAD `75ec007` + 工作树改动）
- 方式：只读。未运行任何测试、DB 或容器，未修改源码，未接触生产。下文的"覆盖"都只是读测试代码得出的。
- 本报告取代第一份报告（口头交付，未落盘）中的错误结论，明确纠正见第 1 节。

**最重要的结论：** Node producer → Go `AppendVerdictFrameTx` → `AdmissionDecider` 这条链，在生产源码里不存在，只在测试里搭起来过。所以 G1–G9 都只是库 API 层面的静态推论，生产上目前都触达不到。

## 0. 每个文件在工作树还是 HEAD
| 文件 | 状态 |
|---|---|
| `governance/execution_control_store_state.go` | **工作树改动，未提交**（diff +177/−?） |
| `cmd/server/execution_run_003_test.go`、`governance/execution_verdict_attestation_test.go`、`daemon/execution_control_worker_test.go` | 工作树改动 |
| `governance/crosslang_test/interop_test.go`、`governance/execution_control_command_attestation_test.go` | **未跟踪的新文件** |
| `execution_admission.go`、`execution_control_protocol.go`、`execution_control_settlement.go`、`daemon/execution_control_worker.go`、`migrations/648_cr_execution_control.up.sql` | 和 HEAD 一致 |
| tools 侧 `execution-control-store.mjs` 及其测试 | 工作树改动；`execution-control-protocol.mjs`、`execution-control-worker.mjs` 和 HEAD 一致 |

（路径前缀：`governance/` = `multica/server/internal/governance/`，`daemon/` = `multica/server/internal/daemon/`，`cmd/server/` = `multica/server/cmd/server/`，`migrations/` = `multica/server/migrations/`，tools 侧 = `tools/skills/shared/crctl/scripts/lib/`。行号均指当前工作树。）

## 1. 对上一份报告的明确修正
1. **"HEAD 已交付"说错了。** 下面这些只存在于工作树：
   - command 验签（`verifyControlCommand`，L74–129）
   - prev_digest 进入签名绑定（L394–398）
   - 字段名从 `seq` 改成 `sequence`（L390）
   - 拿锁后按服务器时钟再验一次（L203–207、L462–466）
   - 精确比对的重放（L417–447）
   - lineage 级的 advisory 锁（L134–146）

   HEAD 只绑定了 request_id、epoch 和 `"seq"`，而且 HEAD 的重放分支不比对字节，直接返回已存的 digest。另外 HEAD 用的是 `"seq"`，和 Node、crosslang 测试用的 `"sequence"` 对不上。
2. **"可以写纯单测（不需要 DB）"说错了。** governance 包有 `TestMain`（`crsync_test.go` L32–50），没有 `DATABASE_URL` 就直接 `os.Exit(1)`。不需要 DB 的测试只能像 `crosslang_test` 那样放在外部包，也就只能调导出函数。`verifyVerdictAttestation` 不是导出的，但 `AppendVerdictFrameTx` 在碰事务之前就先验签（L404–413），所以负例可以从外部包传 nil 或假 tx 来触发。
3. **G7 说"谁都能插 revoke"说错了。** 实际可达性见第 3 节，级别降到 P2，而且它导致的是拒绝服务（fail-closed），不是越权。
4. **G8 部分修正。** 结算后 `verdict_id` 不能为空，已经由 DB CHECK 和触发器保证（migration L101–103、L458–460）。但 verdict 是否存在、是否属于同一个 request，没有 FK（L6–7 写明"关系由应用层验证"），应用层也不查。
5. **G5/G6 级别修正。** 过期 key 的重放只会命中已经存在的行，返回 `Replayed`，不会产生新的事实。真正的旧 key 缺口是：已经入库的行，在签名 key 被撤换以后，裁决方仍然永远认它（裁决时不复验，也没有吊销机制）。

## 2. 真链能不能走通（证据）
- **裁决方生产上没接：** `router.go` L253–257 注释写明生产保持 nil，接不接是 Gate3 的人工决定。`NewAdmissionDecider` 只在测试里被调用。
- **以下导出函数都没有非测试调用方：** `ControlWorker.ApplyTx`、`ApplyControlCommandTx`、`ApplyControlPolicyEventTx`、`OpenControlRequestTx`、`LoadControlTrustManifest`。`SettleControlCommandTx` 只被 `SettleCandidateTx` 调用（`execution_channel_reader.go` L41–64），而 `SettleCandidateTx` 自己也没有非测试调用方。
- **Node producer 和 Go 写入方之间没有衔接：**
  - Node 的 `applyOnce`（`execution-control-store.mjs`）产出的帧格式是 `{sequence, previous_digest, request_id, command_digest, result_b64, signature, digest}`。digest 是对 `JSON.stringify(body)` 算的；签名只检查是不是 64 字节（L13–16 的注释也承认它不做认证）。
  - Go 写入方要的是 `key_id/payload_b64/signature` 形式的信封，payload 里要有 epoch 和 `previous_verdict_digest`（等于 payload 字节的 sha256）。
  - 源码里找不到把 Node 帧转成 `VerdictFrameInput` 的转换代码。Node 的 `signControlEnvelope` 也只被它自己的测试和 crosslang 测试调用。
- **crosslang 测试（未跟踪）证明的范围有限：**
  - 它证明了 Node 签名、Go 验签，原始字节和摘要（含域分隔）一致，篡改过的签名两边都拒绝。
  - 但它的 scope 是 `{workspace_id, cr_id}`，而 `AppendVerdictFrameTx` 要求 store_id 和 lineage_id（L355）。所以这份 fixture 送进写入方会被拒，**没有证明 Node → Append 能走通**。manifest 也是内存里构造的，没走 `LoadControlTrustManifest`。
  - payload 里的 `result:"pass"` 字段，Go 端根本不读。
- **RUN-003（工作树版本）实际怎么搭的：**
  - consumption、settlement、cursor 三张表都是**直接 SQL 插入**（L332–351）；settlement 的 `kind='effect'` 是手写的。
  - verdict 用 Go 签名、内存 manifest，走真实的 `AppendVerdictFrameTx`（L361–397）；有一个冒名 key 被拒的负例。
  - 没覆盖：Node producer、worker 的 fence、settlement 写入方、manifest 加载、outcome 绑定。

## 3. G1–G9 重新定级
统一前提：生产上都触达不到。信任边界上，"调用方"指同进程里拿着 `pgx.Tx` 的受信代码；"DB 写入者"的权限模型在 migration 里没有 GRANT/ROLE，所以**未核实**。

| # | 现状（工作树源码） | DB 或调用方有没有补上 | 级别、可达性 |
|---|---|---|---|
| G1 信任根由调用方提供 | `Manifest`、`AttestationScope` 都是入参（L330–333）；源码里没有任何生产代码把 `LoadControlTrustManifest` 接进写入方 | 没有 | 静态 P0，等接线时必须先闭合 |
| G2 主体和 outcome 没绑全 | 签名覆盖 request/epoch/sequence/prev；不覆盖 VerdictID、Scope、CommitRef、ReceiptRef、outcome。settlement 的 `Kind` 是调用方给的（settlement.go L31–39），从不和 verdict payload 比对；裁决方读 `s.kind`（admission L180）。lineage 和 CR 的对应关系裁决方也不查 | 精确重放只防止事后改标签（测试 L321–354），**挡不住第一次写入时**的未签字段。VerdictID 到 consumption 的关联靠签过名的 request_id 加 `v.request_id=s.request_id`，所以 VerdictID 没签影响不大。outcome 没绑是实打实的缺口 | 静态 P0（outcome）、P1（lineage↔CR） |
| G3 cursor、open slot、epoch | 追加帧时不检查 `open_request_id`（L450–454），之后无条件清空；不检查 epoch 是不是当前的 | 生产代码只会建 epoch 1（worker L58–60），其他地方没有新建 epoch 的代码，所以旧 epoch 这条目前是理论风险 | 静态 P1 |
| G4 fence | `assertFenceTx`（worker L250–263）用 `FOR UPDATE` 锁住同一 cursor 行再核 fence，有效；但 `AppendVerdictFrameTx` 自己不核 | **新发现：** `OpenControlRequestTx`（L504–510）可以把 `owner_fence` 设成任意值，包括回退，把 fence 的单调性破坏掉 | 静态 P1，无调用方 |
| G5 时钟 | 新帧会按服务器时钟复验；`created_at` 取调用方的 Now（L473） | 裁决方不读 `created_at` | P2，只影响审计 |
| G6 旧 key | 没有吊销机制，裁决时不复验；"历史重放策略未定"（L4–5） | 没有 | P1 |
| G7 无签 revoke/stop | `ApplyControlPolicyEventTx`（L249–280）不验签。插入者要么是同进程的调用方（当前没有），要么是 DB 写入者（权限未核实）。影响：堵住后续 command、占掉 `(lineage_id,seq)` 唯一位；裁决方和 settlement 都**不读**这些事件，所以不会导致放行 | `verdict_id` 被写成了 ReservationID（L271），语义不对 | P2，拒绝服务 |
| G8 状态转换 | 不校验 verdict 是否存在、是否匹配 | 非空由 DB 保证；匹配关系没人保证 | P2 |
| G9 裁决粒度 | 按 CR 计数；consumption 只在 `(ws,cr,runtime,task,dispatched_at)` 上唯一（644 L22），task_id 不是全局唯一 | 没有 | P2 |

**其他新发现：**
- **N1 · cursor 表没有守卫触发器。** migration 注释 L14 说 cursor 有窄守卫，但 L598–644 的触发器列表里没有 cursor，所以 `last_seq`、`owner_fence` 可以被任意 UPDATE 甚至 DELETE。裁决方的 `c.last_seq >= v.seq` 正是靠 cursor 判断。前提是 DB 写入者有写权限（未核实）。
- **N2 · 唯一键没包含 lineage。** `chain_once UNIQUE(store_id,epoch,seq)`（L137）不含 lineage_id，而 cursor 的主键含。两个 lineage 共用 store_id 时会互相冲突，属于拒绝服务。
- **N3 · settlement 的撤销检查遇到断链会放行。** `controlAuthorizationRevoked` 查不到这条链时返回"未撤销"（settlement.go L165–167），settlement 照常写 effect。
- **N4 · 关键关联没人建立。** 没有任何生产代码能保证 `command.request_id == consumption.task_id`，RUN-003 是靠直接插行绕过去的。**未核实。**

## 4. 最小 test-only 闭合路径（按依赖排）
每步先写红测试钉住缺口，再修产品代码。

**① 外部包，不需要 DB**（仿照 `crosslang_test`，传 nil 或假 tx，验签失败会在碰事务前返回）：
- **a）scope 对齐：** 用 Node 签出一份 scope 为 `{store_id,lineage_id}` 的 verdict，送进 `AppendVerdictFrameTx`。正例用假 tx 跑到 cursor 查询之前，验签那一步应当通过；同时保留现有 `{workspace_id,cr_id}` 版本，期望被拒。
- **b）信任根：** 调用方自造 manifest、攻击者 key，期望拒绝。要先把写入方改成从固定的信任源取 manifest（闭合 G1）。
- **c）outcome 绑定：** payload 写 `result:"no_effect"`，期望不能作为 effect 入库或被裁决方认可（闭合 G2 的前半）。

**② 用授权的一次性 DB 跑**（`scripts/aifi45-db/run.mjs`）：
- **a）G3：** open slot 是 R1 时追加 R2，期望冲突。
- **b）G4：** `OpenControlRequestTx` 把 fence 设成 fence−1，期望拒绝；直接调 `AppendVerdictFrameTx` 绕过 worker，期望核 fence。
- **c）N1：** `UPDATE cursor SET last_seq=99`，期望被触发器拒绝。
- **d）G2/N3：** settlement `kind=effect` 配签名 outcome 为 no_effect 的 verdict，期望裁决方返回 `WAIT_TRUSTED_T_COMMIT`；断链时撤销检查期望拒绝写 effect。
- **e）lineage↔CR：** 用 lineage A 的 key 去证明 CR B 的消费，期望不放行。
- **f）G6：** key 撤换以后旧行期望不再被认可（需要先定吊销策略）。

**③ 真链：** 补上 Node 帧到 `VerdictFrameInput` 的转换（或者让 Node 直接产出信封），RUN-003 改为由 Node 产出、`ApplyTx` 写入、`SettleControlCommandTx` 结算，不再直接插行。

**④ 最后**才是 Gate3 接线：生产注入 decider，manifest 从固定位置加载。

## 5. 仍未核实
- DB 的角色和 GRANT 模型：决定 G7、N1 实际谁能利用。
- 是否有部署脚本或其他仓库插入新 epoch 或写 cursor。
- 有没有 HTTP 路由能间接写到这些表（我只 grep 了 Go 的函数调用方）。
- 生产语义上 `command.request_id` 和 `task_id` 应该怎么对应（N4）。
- 现有测试是否真的能跑通（全部没跑）。

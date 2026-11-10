可验证性裁决：INCOMPLETE

判定依据：5 个用例里 4 个（77/78/79/81）不在 TC-RUN-003 的 CP `go test ./cmd/server -run ^TestTC_RUN_003$` 的 leaf 内；且「registry 派生夹具」不是变更探测器，另有两处保证（nil manifest、帧位置签名覆盖）没有任何可执行 leaf。业务事实断言本身总体成立，但不是全部。

（前置披露：台账 `tc-coverage-20261025T153000Z.md` 在本机被识别为二进制/非 UTF-8，我未能读出增量 77–81 的原文，故第 2 问只按提交信息 + 测试源码判定，符合 brief 允许的口径；行号为源码定位，个别为近似区间。）

---

## 1. 哪些断言打到业务事实，哪些只打到 helper

**`server/internal/governance/execution_admission_failure_branch_test.go`**
- 业务事实：`pipeline_run.status` 读库（≈:139-148，`SELECT status FROM pipeline_run`）；节点 `detail->'runner'->>'admission'` 读库（≈:158-190，comment 明说「read every node row once」）。这两条能区分「把等待写成 failed」。
- 只打 helper：`fake.count`（≈:80、96、152-154）是 `insertingPipelineEnqueuer`/fake 的计数，只证明假 enqueuer 未被调用，不证明 DB 里没有任务行；本次改动也没为它新增读库断言。
- 另：本用例的「等待」由测试自带 decider `refuseBetweenHumanGateAndDispatch`（:26-51）产生，所以它只证明哨兵管道，不证明真实 `executionAdmissionDecider` 会在这个窗口返回 wait（那一点由 human_gate 子测 (2) 覆盖）。

**`.../execution_admission_human_gate_test.go`**
- 业务事实：四个子测的 `readNode`（≈:109-118）都读 `pipeline_node_run` 的 `status/approval_id/detail.runner.admission`；(1) `rows==1`+passed+approval_id（≈:140-156），(2) `errors.Is(err, errAdmissionWaiting)` + 未 passed + admission 原因（≈:162-185），(4) 终态节点 0 行且仍 `failed`（≈:218-233）。
- 只打 helper／自证：(3) 正向对照先用 `admitTrustedConsumption`（≈:191）直接写「可信消费」行，再断言 admitted（≈:193-212）。它证明的是「decider 读得到 helper 写的那几行」，不是「真实摄取链路写出的行会被认」，这是 brief 弱点 #4 的具体落点。

**`.../execution_admission_requirement_enqueue_test.go`**
- 业务事实：`wait_reason` 读 `pipeline_node_run.detail`（≈:145-153）。
- 只打 helper：`enqueuer.calls`（≈:139、162）来自 `countingEnqueuer` 假件；正向对照只断言「调用 1 次」，**没有**断言 `agent_task_queue` 行（node_run_id/agent_id/cr_id）。故「入队给错误 actor/错误节点」在这条路径上不可观测。

**`.../execution_verdict_attestation_test.go`**
- 业务事实：`errors.Is` 两条哨兵（:49-51、:93-95、:107-109、:120-122）＋ `cr_execution_tool_verdict` 行/`payload_bytes` 读库（:70-77、:129-142）。这是「有行即已验签」的直接证据。
- 只打测试自身：:66-69 的 `applied.Digest` 重算来自输入而非 DB（低价值但无害，:75 的 stored payload 比较才是业务面）；signer/manifest（:144-203）是测试自建信任根，属不可避免。

**`server/cmd/server/execution_run_003_test.go`**
- 业务事实：回读真实列 `agent_id / issue_id / pipeline_node_run_id / context`（≈:374-390），重复唤醒同 `taskID`（≈:420-427）。这是本轮把「计数」换成「身份」的关键改进。
- 仅计数（弱）：`tasks(t) != 1`（≈:415）单独不可变异（见第 4 问）。

## 2. 台账记录的变异是否真的命中对应断言

- **77 去守卫**：命中。守卫去掉后 approve-reject 分支走 `failRun`，`Reconcile` 返回错误或 `pipeline_run.status='failed'`，≈:139-148 必红。
- **78 恒 legacy**：命中子测 (2)，期望 `errAdmissionWaiting`（≈:162-170）会变成 nil/其它错误。**去 status IN**：命中子测 (4)，`failed` 节点会被更新成 passed，`rows!=0`（≈:224-231）必红。
- **79 三条**：
  - 去 chain/scope 绑定 → `verdict_for_another_chain_is_refused`（:115-124）红。
  - 去验签（回退 `controlEnvelopeHasSignature`）→ 主要由 `forged_signature_is_refused`（:81-97）红：该子测经 `attest` 设了 scope，能走到 `VerifyControlEnvelope`，旧检查会放行并落行，`assertNoVerdictRow` 抓到。
  - 去逐字节比较 → `payload_not_the_signed_bytes_is_refused`（:101-111）红。
  - 注意一处**归因错误**：`placeholder_envelope_is_refused`（:27-53）构造的帧既无 `Manifest` 也无 `AttestationScope`，因此它在 `verifyVerdictAttestation` 的**第一道 scope 检查**就返回了，根本没走到签名验证。它不能证明「占位签名被验签拒绝」，只能证明 scope 检查拒绝。属于命名/注释与事实不符，不是夹具错误也不是代码先报错。
- **80 入队到源作者**：命中。测试显式 seed 了独立 `run003-author` 并给它授 skill（execution_run_003_test.go ≈:151-163），使「作者≠PipelineOwner」两条路径都能成功执行，因此错挂作者会走到 `taskAgent != agentIDs[core.PipelineOwner]`（≈:383）红，而不是先报 skill 缺失。
- **81 短路 gate**：命中。去 gate 后 `enqueuer.calls` 由 0→1，≈:139 红；`wait_reason` 断言是第二道保险。
- 无法判定项：我未能读出台账文字，以上「是否与台账逐条一致」只按提交信息（`9d0f6f556`…`a929e4438`）与用例语义对齐，未做逐字比对。

## 3. registry 派生夹具能否随 registry 变更而失败

**不能。它是自适应，不是变更探测器。**
- `execution_admission_requirement_enqueue_test.go:36-44` 用 `parseRequirementRegistry()` 取 `Nodes[0]` 与 `PipelineOwner`，:100-104 用 `registry.PipelineOwner` 建 agent，:44-48 用 `registry.Inputs` 生成 inputs。registry 改名/换 skill ref/加 input 时，夹具跟着改，测试仍绿。文件头 :5-7 的「shows up as a fixture failure instead of a silently untested path」是**过度声明**。
- 它真正会红的条件只有：首节点不再是带 ref 的 skill 节点（:42-44）、或 input 变成非字符串导致 `map[string]string` 崩。也就是说它保证「gate 打在真实首节点上」，不保证「registry 变了有人知道」。
- `execution_run_003_test.go` 的 skill 播种循环（≈:151-163）同理：按 `core.Pipeline.Nodes` 遍历，节点重排/增删都会被静默吸收；断言用的是 `core.Pipeline.Nodes[0].ID`（≈:368），重排后仍然自洽。
- 最小可测化要求：断言一个**写死的期望值**（registry digest 或 `PipelineIDs.RequirementAuthoring`+首节点 id/ref 的字面量），registry 一变即红；或加一条 goldens 测试比对 `parseRequirementRegistry()` 的输出。

## 4. 仍写不出可执行 leaf / 写不出 mutation 的断言（含最小可测化要求）

1. **nil manifest fail-closed**：`verifyVerdictAttestation` 把 nil 交给 `VerifyControlEnvelope`，但没有任何用例传「其余全合法、仅 `Manifest=nil`」的帧（:27-53 是 nil scope，被第一道守卫先拦）。
   最小要求：新增子测，`signer.attest(...)` 后置 `in.Manifest=nil`，期望 `ErrControlStoreInvalid` 且 `assertNoVerdictRow`；对应变异 = 删掉 `VerifyControlEnvelope` 内的 nil-manifest 拒绝。
2. **帧位置（seq/prev_digest）不在签名覆盖内**：无 leaf、也无法写 mutation，因为 payload schema 未定义（brief 已登记）。最小可测化要求：在 `execution-control-verdict/v1` 里把 `seq/prev_digest` 纳入被签字节，并加一帧 `Seq=2` 且 `PrevDigest` 错位的用例。在此之前该保证不可验证，应留在未闭合清单。
3. **requirement 正向对照没有 DB leaf**：只断言 `countingEnqueuer.calls==1`。最小要求：admitted 后查 `agent_task_queue`（`cr_id`、`pipeline_node_run_id=nodeRunID`、`agent_id=agentID`），变异 = `enqueueRequirementNode` 换 actor/换 node_run。
4. **`fake.count`（failure_branch ≈:152-154）无独立 mutation**：任何能改它的生产变异都会被 `wait_reason`/`run.status` 断言同时抓到，它是重复证据。最小要求：删掉，或改成查 `agent_task_queue` 计数。
5. **`tasks(t)` 计数（run_003 ≈:415）单独无 mutation**（同 id 断言已覆盖替换）。保留无害，但不得单独计入覆盖面。
6. **CP leaf 不覆盖 4/5 新用例**：`go test ./cmd/server -run ^TestTC_RUN_003$` 只跑 `execution_run_003_test.go`；77/78/79/81 在 `internal/governance`。最小要求：把 `go test ./internal/governance -run 'TestAdmissionWaitingIsNotPersistedAsRunFailure|TestPassHumanApprovalNodeIsGated|TestVerdictWriterVerifiesAttestation|TestRequirementEnqueueIsGated' -count=1 -v` 作为并列 leaf 写进台账，否则「CP 跑通」不能支撑这四个提交的闭合主张。

---

**结论**：断言主体确实落在 DB 业务事实上（run_003 的身份回读、verdict 的行/字节回读、human gate 的节点状态回读），台账四条变异的命中关系也基本成立；但 (a) 一条子测的拒绝原因被错误归因到验签，(b) registry 派生夹具只是自适应而非变更探测器（文件头声明不实），(c) 两处保证无 leaf，(d) CP 命令与四个用例不在同一 leaf。故按可验证性判 **INCOMPLETE**，不能据此单独支撑 TC-RUN-003 记 PRESENT。
TC-RUN-003 裁决：BLOCK
验签接线成立，但“被签名的 verdict 属于本次消费 request”仍未建立，现有正向夹具绕过这一关联，尚不足以证明“T 提交适用消费后才放行”。

## [阻断]

- **验签未绑定准入实际使用的 `RequestID`，存在同链移植缺口。**  
  `verifyVerdictAttestation` 只将签名 scope 绑定到 `StoreID/LineageID`，并比较 payload 原字节；写入时的 `RequestID`、`Epoch`、`Seq/PrevDigest` 均来自独立输入，未与已验签 payload 核对。与此同时，判定器正是依赖 `v.request_id = s.request_id = cc.task_id` 将该行解释为本次消费的可信提交。  
  因而，一个合法签名的同链 payload 可以配上另一个新 `RequestID` 和合法下一格位置，经唯一生产写入者入库；**无需直接写表，也无需伪造签名**。这不同于已登记的“同 CR 旧代次复用”：这里连被认可的 request 本身都没有签名关联。  
  证据：`server/internal/governance/execution_control_store_state.go:259–270, 285–336`；`execution_admission.go:169–178`。测试签发的 payload 只有 schema/purpose/domain/scope/frame，也实际展示了写入者允许这种未绑定形式：`execution_verdict_attestation_test.go:171–180`。  
  **闭合要求：**定义最小 verdict 合同，并由写入者核对签名主体与落库 request 的关系；增加“签名不变、替换 request”的拒绝用例及正确关联正控。不能仅要求未来生产者“自行把字段放进 payload”。

## [应改]

- **验签拒绝用例存在第三类“测到别处”。**  
  `placeholder_envelope_is_refused` 同时缺少 `AttestationScope` 和 `Manifest`，会首先命中链 scope 不匹配，未抵达 manifest 检查或签名验证。因此它不能单独证明“nil manifest fail-closed”或“占位签名被验签拒绝”。应拆为 scope 正确且签名有效、仅 manifest 为 nil 的用例，以及 scope/manifest 正确、仅签名非法的用例。  
  证据：`execution_verdict_attestation_test.go:26–53`；`execution_control_store_state.go:260–265`。

- **正控能排除恒拒绝，但不能证明可信提交的完整关联。**  
  增量 78/81 对真实节点状态、approval 和入队次数的断言有效，不是单纯调用 helper 后检查 helper 返回值；但 `admitTrustedConsumption` 直写事实只适合测试“给定可信事实后的门控”。CP 测试甚至以空 envelope、任意 digest 直插 verdict，再插 cursor 放行，完全绕过本轮新增写入者。独立 writer 正控又未覆盖上述 request 关联，因此两者尚未构成充分的组合证据。  
  证据：`execution_admission_human_gate_test.go:134–178`；`execution_admission_requirement_enqueue_test.go:140–165`；`server/cmd/server/execution_run_003_test.go:344–360`。  
  建议保留非法中间态分相测试，另加一次通过真实写入者提交正确关联 verdict、再驱动 Runner 的桥接正控。

- **“拒绝零副作用、零行”必须限定对象。**  
  拒绝不会执行这里的 passed UPDATE，但 `waitAdmissionAt` 明确更新节点 detail，并返回等待哨兵；因此只能表述为“零被拒业务效果／零新派发”，不能表述为数据库零写入。其注释“不是 error”也应明确是业务语义，不是 Go 返回值。  
  证据：`execution_admission_gate.go:143–150, 153–176, 203–204`。

## [可登记]

- **三道验签守卫本身未发现跳过路径。**  
  `AppendVerdictFrameTx` 在 replay 查询和 INSERT 前强制调用 verifier。scope 正确时，nil manifest 会被 `VerifyControlEnvelope` 明确拒绝；多 `%w` 在本仓 Go 版本下保留两个错误分支，`errors.Is` 可同时命中 `ErrControlStoreInvalid` 和验签哨兵，伪签名测试也同时断言了两者。  
  证据：`execution_control_store_state.go:264–285`；`execution_control_protocol.go:608–630`；`execution_verdict_attestation_test.go:82–101`；`server/go.mod:3`。

- **`ApplyTx` 的覆写顺序正确，不会必然恒拒绝。**  
  它先检查 fence，再覆写 `LineageID/StoreID/Epoch`，最后调用写入者验签。调用者提供与 fence 一致的签名 scope 可以通过；不一致被拒是预期防移植行为。若改成验签后覆写，反而会允许把已验证的另一条链的内容写到当前链。  
  证据：`server/internal/daemon/execution_control_worker.go:263–280`。

- **seq/prev 未签名，单独不足以判 BLOCK；但不能据此声称链位置已获签名认证。**  
  当前数据库 cursor 锁与连续性检查可以承担追加排序；是否必须由签发者认证位置，需要合同明确。真正阻断本轮的是上述签名主体与消费 request 脱节，而不只是“签名没有 seq”。  
  证据：`execution_control_store_state.go:296–318`。

- **等待与锁边界的已见证据有效，但不应扩大结论。**  
  `decideUnderHeadLock` 拒绝前释放锁，允许时交出仍持锁事务；human approval UPDATE 位于该事务内。增量 77 驱动公开 `Reconcile`，检查 run 未失败、未额外派发且等待落在 approve 节点，确实打到业务分支。它证明该分支，不等于所有四处调用链均无哨兵泄漏。  
  证据：`execution_admission_gate.go:83–124, 199–215`；`execution_admission_failure_branch_test.go:104–147`。

本次仅作静态阅读，未运行 CP、测试或数据库操作，也未读取其他 lane 输出。**生产未接线等已登记事项不是本次 BLOCK 理由；补齐 request 关联合同、写入者校验及反例／桥接正控后，才具备重新判 PRESENT 的条件。**
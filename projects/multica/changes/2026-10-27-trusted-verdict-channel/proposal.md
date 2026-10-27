# 可信 T committed verdict channel：受保护裁决 store、merge facts 与撤销线性化（multica 侧）

<!-- source_hash: 6657da0a3e5ae56a -->
<!-- generated_at: 2026-10-27T15:15:13.657846 -->
<!-- canonical: canonical/proposals/2026-10-27-trusted-verdict-channel.yaml -->

## Why

准入正路径需要可信 T 已提交裁决，但平台侧当前没有可核验的落点：crctl 的准入在
`crctl.mjs` 仍返回 `EXECUTION_CONSUMPTION_REQUIRED`，repair CLI 只解码 payload，
agent stdout、磁盘 JSON、平台收据、Git 通过与否都不能作为裁决证据。merge 侧的
「批准后写集」也取自 agent 可写的 `approval.yml`，核对区间小于实际发布区间。
结果是 AIFI-45 的 6 条 RUN TC 只能测拒绝侧（vacuous），AIFI-45 台账结构性停在 41/49。


## What Changes

- 单个 proposed migration 648 内的 14 张 `cr_execution_*` 表（业务通道 8 + D7 5 + merge facts 1 `code_source_freeze`）：不可变/append-only 约束、部分唯一索引、 `ChannelTableNames` 精确 14 个 DB 全名清单，以及 up/down/reapply/protected-data 四组迁移专例。
- 可信 selection 与冷启动：operator-pinned scope policy 冻结的 `contract_selection`、 不可执行的 `control_reservation`、`ResolveCandidateTx` 固定候选，以及 `AdmitDispatchRootTx`/`EnqueuePipelineTaskTx` 的同 Tx root+task+settlement 与 commit 后通知。
- 受保护裁决 store：`control_command`/`tool_verdict`/`tool_cursor`/`control_settlement` 状态机（created→issued→result_ready→settled_effect|settled_no_effect、uncertain 冻结）、 持久 owner fence、固定锁序、原字节重放与恢复表。
- 5 个 daemon 端点：`GET /api/daemon/execution-control/commands`、 `POST /api/daemon/crs/{crID}/execution-verdicts`、 `POST /api/daemon/execution-control/checkpoints`、 `GET /api/daemon/execution-control/merge-facts/{crID}`、 `POST /api/daemon/crs/{crID}/merge-effects`（`op=reserve|report`）； 仅 MDT + enrolled key/owner scope，拒绝 PAT/JWT/task-token 回退。
- 可信 facts 与执行接线：`control_fact` 的权威 origin/历史覆盖、`ResolveFactsTx` typed facts、 `IngestTx`/`SettleCandidateTx`、真实 task 启动前的 643–645 全量匹配与 generation binding、 `CommittedTReader` 只读已验签 DB facts，以及 projection fence 覆盖 `gate_projection.go`/`crsync.go`/`ApplySnapshot`/strict task preflight 与终态上报。
- D7 部署就绪控制面：`deployment_head`/`deployment_snapshot`、`policy_readiness`/ `policy_activation_head`/`policy_activation_event`、`RecordReadinessTx`/`ActivatePolicyTx`/ `StopNewAdmissionsTx`/`BeginLegacyDrainTx`/`FinalizeLegacyRetirementTx`、 `CheckDeploymentAccessTx` 与 `PrepareLaunch`/`CommitLaunch` 固定快照。

### New Capabilities

- **verdict-channel**：可信 T 裁决的落点与效力：持久 selection、不可执行 reservation、受保护 store 与线性化 settlement、merge 事实端点与撤销线性化写端点、DB-only reader 与 projection fence。
- **deployment-readiness**：部署就绪控制面：唯一 T readiness 求值结果的持久化、generation fencing、原子启用与 停新准入、旧继电器的 drain/retire，以及 strict 启动的固定快照。

## Success Criteria

- [ ] 迁移：648 up 后 14 张表（8 业务 + 5 D7 + 1 merge facts）及其触发器/索引/约束齐全；down 全部撤销；reapply 无残留业务行；对 643–647 夹具零改动——四组专例各有 ≥14 PASS leaf。
- [ ] Foundation：合法 source/固定 candidate 提交得唯一真实 root/task；rollback 得零持久新增且零通知；control reservation 永不 runnable；adoption/terminal 竞争只认 55P03 且有正对照。
- [ ] 协议：purpose/domain/scope 任一错用即拒；Go↔Node 原字节双向向量通过；attestation key 签 resume、human key 签 command、重复键、union 双分支均拒绝。
- [ ] Store：同请求并发/rename 前后 kill 只产生一次业务变化且原 bytes 相同；断链、跳号、占位签名一律拒绝；fsync 失败无 frame。
- [ ] 恢复：恢复表每行有对应用例；普通 restart 保持 epoch/seq 并重发原 bytes；旧 fence、缺 store、落后/分叉全部 freeze，不猜「未消费」。
- [ ] Facts/repair/resume：自报 reviewer、未验签 payload、专项改 target、账本来源不可核实均拒；signature resume 只一次 epoch；追加 CAS 只接受一份。
- [ ] Ingest/Settlement：T commit/M rollback 重送原 bytes；effect commit 后响应丢失只返回既有 mapping；撤销先提交则 no_effect；ingest ACK 不释放 slot 不发 task；启动前 643–645 全匹配。
- [ ] Reader/fence：无 committed T 时零 root/task；重复 settle 只返回原 mapping；Strict 删投影字段仍 strict、Unknown 不降 legacy、`fence_required` 任务缺 claim 409、重领后仍 409。
- [ ] merge-facts：R2.5 的 11 条必达 leaf 全绿（认证主体解析、拒绝 PAT/JWT/task-token、当前冻结行唯一、批准下界须为候选祖先、仓库集合精确相等、current_binding 三态、legacy 证明、失败码优先级、不可用、撤销、head 前移），每条有对应 mutation。
- [ ] merge-effects：R3.5 的 16 条必达 leaf 全绿（共享锁探针、撤销/reserve 双向排序、journal 三态与远端分类、attempt 语义、base 漂移、finalize 也 reserve、码序、正常前进不判改写），每条有对应 mutation。
- [ ] D7：真实 component profile 只得 READY_COMPONENT 且 activation head/event 不变；strict 缺 AdmissionDecider 必 NOT_READY；STOP_NEW 后旧 issued 请求精确恢复、新候选与换 origin 不能；RETIRED 前 work revision 漂移必拒。
- [ ] 证据：`validation/channel-test-expectations.json` 冻结必达 leaf 全名，`channel-evidence.mjs` 按名单校验真实非 skip PASS leaf；缺组、全 skip、只父 PASS 一律判未验证。
- [ ] 残余风险写实：交付后文档与回复均不得声称「merge 已强制」或「strict 生产已启用」。

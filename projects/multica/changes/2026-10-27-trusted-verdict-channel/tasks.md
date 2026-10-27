# 可信 T committed verdict channel — multica BUILD 任务清单

> Gate 2 已确认，BUILD 进行中（长程模式）。`[x]` 由实跑证据支撑，证据入口 `validation/evidence-index.md`；未勾项即未实现。
> Gate 2 确认后才进入 BUILD；每片按 RED→GREEN 推进，不横向先写全部实现。

## 0. SPEC 阶段已完成的文档交付

- [x] 0.1 `validation/channel-test-expectations.json` 已在 SPEC 冻结（41 label / 215 leaf，逐 leaf 标 SC；原排 BUILD 的 9.1，按方案改回 SPEC）。
- [x] 0.2 `channel-component` profile v1 已写入 design §8.1；`strict-production` profile 与实例清单记 UNVERIFIED。

## P0. 隔离证明（排第一；只阻塞依赖方案 C 的片）

- [ ] P0.1 `server/internal/daemon/execution_control_isolation_test.go`：`TestChannelIsolation` Linux 5 leaf（pidfd、`SO_PEERCRED`、私有 socket、CLOEXEC、拒 SCM_RIGHTS）。
- [ ] P0.2 同顶层 Windows 3 leaf（命名管道 client pid + 令牌 SID + launch 登记）；两平台分别出证，缺 profile 必须 `t.Fatalf`。
- [ ] P0.3 mutation：改回信任请求体 pid、改回数字 PID 查 `/proc`，分别 RED。
- [ ] P0.4 获隔离环境与 profile 授权前不执行；未执行即 UNVERIFIED，不以组件 PASS 替代。

## 1. 迁移与 schema（P0，阻塞全片）

- [x] 1.1 新增 `server/migrations/648_cr_execution_control.up.sql`：14 张 `cr_execution_*` 表 + 7 个共享 guard 函数 + 30 个触发器（append-only / no-delete / no-truncate / 命令状态机 / head 单调 / freeze 终态 / readiness 写一次）、部分唯一索引、无新 FK/cascade。表级不可变由行级 + 语句级双重拦截：行级触发器对 TRUNCATE 不触发，缺语句级 guard 就是真窟窿。
- [x] 1.2 新增 `648_cr_execution_control.down.sql`：按逆序撤销 14 表并显式 DROP 7 个 guard 函数，无 cascade。
- [x] 1.3 `server/internal/governance/execution_control_tables.go`：`ChannelTableNames`（14 全名，创建序）+ `ChannelTriggerFunctions`（7）。
- [x] 1.4 `execution_control_migration_test.go`：`TestChannelMigrationAfterUp/Down/Reapply` 各表一个 `t.Run` + 逐表清单（先声明后断言，不由实测反推）。清单按**对象语义**断言而非仅名字：CHECK/UNIQUE 按 `pg_constraint.contype` 匹配，部分索引必须带谓词、普通索引必须不带，触发器按事件集合匹配（`pg_get_triggerdef` 会按字母序渲染成 `BEFORE DELETE OR UPDATE`，字面串比会假红）。真跑：up 15/15（leaf 14）、down 22/22（leaf 21）、reapply 15/15（leaf 14），均 skip=0、original_unchanged=true、owned_resources_cleaned=true。
- [x] 1.5 `TestChannelMigrationProtectedData`：造 643/644/647 夹具并**向 648 表写入真实行** → 648 down/up → 断言夹具行摘要不变、643–647 表仍在、14 张 648 表零残留。down 侧残留枚举按**归属**排除既有台账与其自带索引/序列（按名字前缀扫会把 643–647 自己判成残留），对象差集见 `channelUnexpectedObjects`。真跑 4/4（leaf 3）。证据见 `validation/{g,h,i,l}-*`。
- [x] 1.6 648 号未被占用：647 是既有最大迁移，648 由本 change 新增，无需顺延。
- [x] 1.7 破坏性探针前置 **DB 身份闸门**：连接后立即断言库名 `^aifi45_tmp_[0-9a-f]{16}$`、角色 `^aifi45_role_[0-9a-f]{16}$`、非 superuser、库注释等于 `AIFI45_DISPOSABLE:<nonce>`，任一不符即 fatal——先证这是可丢弃 nonce 库，再执行 648 down。

## 2. S1 选择、候选与派发根（P0）

- [x] 2.1 `execution_contract_selection.go`：`ResolveSelectionTx` 只读持久选择；strict+投影缺失/空/不同 → `T_VERDICT_BINDING_MISMATCH`（不降级）；无选择且目录未证明 → `EXECUTION_SELECTION_UNKNOWN`。legacy 只认 `deployment_head.legacy_catalog_ref` **钉住**的那份目录（不取最新行）、校验 gate/kind/scope/`catalog_version`，且整份目录先验重后才采信单条（重复条目=不可解事实）。缺行→目录的竞态由 `pg_advisory_xact_lock` 关掉。`TestChannelFoundationSelection` 真跑 6/6（leaf 5），含「未钉住的新目录不得改变裁决」「持久 legacy 行仍需证明」两条反例。证据 `validation/i-selection-*`、`j-selection-*`。
- [x] 2.2 `execution_control_reservation.go`：`CreateReservationTx` 只接受 strict 选择、候选 bytes 冻结为 digest、proposed task id 固定；表内无任何 dispatch 列（结构上不可 claim/执行），且不写 `agent_task_queue`。**同一 Tx 内回读** selection 行校验 mode/lineage/scope，伪造的 `Selection` 结构体不被信任。`TestChannelFoundationReservation` 真跑 4/4（leaf 3），含伪造 selection id、跨 CR、跨 lineage、跨 scope 四条反例。证据 `validation/i-reservation-*`。注：green 首跑因测试自身事务中止写法失败，改 savepoint 后通过。
- [x] 2.3 **原语层**：`execution_dispatch_root.go` 抽出 `admitDispatchRootTx`（不自提交）+ `AdmitDispatchRootTx`；新增 `execution_channel_admission.go`（`AdmitAndEnqueueTx`：同 Tx 写 root+`agent_task_queue`+`control_settlement(kind=effect,effect_kind=dispatch)`，固定 ID 冲突逐字段等同才接受，通知句柄只在调用方 commit 后可用）。`TestChannelFoundationReservation/fixed_id_conflict_and_rollback` 与 `TestChannelTaskTx/commit_then_notify|rollback_no_notify` 真跑绿。**未做**：`service/task.go` 生产接线与 sqlc 生成（留给 S6），因此该 CP 只证明原语契约，不证明生产装配。
- [x] 2.4 adoption/terminal 并发探针：`root_adoption_terminal_race` 在 `after-read` 故障钩子里让另一连接以 `lock_timeout=250ms` 抢写终态，断言**只认 55P03**（超时文本/连接错误/成功都不算），并附无锁正对照；`root_terminal_not_adopted` 断言终态根不可 adopt 且同逻辑根未被重建。m6（删 `FOR UPDATE`）只打红该 leaf。
- [ ] 2.5 `execution_fresh_work.go`：`RegisterFreshWorkTx`、origin/fresh-work/legacy-catalog 三型 fact、partial unique；`TestChannelFoundationFreshWork`。
- [x] 2.6 `service/execution_channel_task_tx_test.go`（外部测试包，避开 governance→service 的循环导入）：`TestChannelTaskTx/commit_then_notify`、`rollback_no_notify`。真跑 3/3（leaf 2）。

## 2A. 数据库不变量复核修复（P0，strong 复核 BLOCK 后新增）

- [x] 2A.1 选择/预约行级不可变 + 语句级 TRUNCATE 拦截（B1）；其余保活表（verdict/settlement/binding/fact/snapshot/activation_event/freeze）全部补 TRUNCATE guard（M2）。
- [x] 2A.2 命令状态机 `created→issued→result_ready→settled_*|uncertain`、终态出不去、身份与签名字段恒冻结、admission 边界在 issued 后冻结、`verdict_id` 终态（M1）。
- [x] 2A.3 deployment head `scope` 不可改、generation/registry/work revision 单调、RETIRED 终态（M3）；freeze 的 supersede/revoke 戳只能 NULL→值且须晚于 approved_at（M4）。
- [x] 2A.4 `origin-registration` 必须带 origin（CHECK + `(scope,origin_id)` 部分唯一）（M5）；readiness 请求字段冻结、observation slots 只追加、verdict 写一次（M10）。
- [x] 2A.5 `TestChannelStoreGuards` 9 leaf 真跑 10/10（leaf 9）；m1–m4 四个变异各自只打红目标 leaf（m1 打红 selection+reservation 两行不可变，因其共享同一个 append-only 函数），恢复后 up.sql sha 与基线一致（`89f0c3f0…`）。
- [x] 2A.6 冻结清单按复核结论扩充 +4 条 leaf（`store-guards` 新增 label、selection 2 条、reservation 1 条），改动记入 `validation/channel-test-expectations.json#revisions`。
- [x] 2A.7 证据链闭环：`scripts/aifi45-verify/channel-evidence.mjs`（verify/record）+ 9 条自测；green 跑次记录 10 个源文件 sha256；一次真实变异证明「改过的树」会被判 FAIL、恢复后同一前缀回到 OK。`validation/evidence-index.md` 为唯一证据入口，旧前缀作废。

## 3. S2–S4 协议、store 与恢复（P0）

- [x] 3.1 `execution_control_protocol.go`：`VerifyControlEnvelope`（与 Node 侧同错误码同判定序）、`LoadControlTrustManifest`（绝对路径/大小上限/PEM sha256 pin/agent 可写根拒绝/Ed25519/重复声明）、`SignControlEnvelope`+`SignControlPayloadBytes`；严格 base64 与**重复 JSON 键拒绝**（Go 默认保留最后一个）。`TestChannelProtocol` 真跑 6/6（leaf 4，含 `cross_language_vectors/verdict|command`）；共享夹具 `tools/.../test/fixtures/control-vectors.json` 由 Node 生成、Go 验签并复现同一签名，副本存 `validation/control-vectors.copy.json`。m7（签名域去掉 `schema `）打红 `purpose_domain_scope`+`cross_language_vectors`；m8（允许重复键）只打红 `exact_keys`。
- [ ] 3.2 `execution_control_command.go`/`store`：状态受限转换、单 open、fence、settlement kind；`TestChannelStoreState`（7 leaf）。
- [ ] 3.3 `execution_control_recovery.go`（daemon）：checkpoint 字段、恢复表五类动作、旧 fence 隔离；`TestChannelWorker`+`TestChannelRecovery`（7 leaf，见 expectations `worker` label）。
- [ ] 3.4 key rotation 只影响新 verdict；历史帧仍用旧 key 验证（并入 3.3 与 3.2 断言）。

## 4. S5 facts、repair/resume、sensitive action（P0）

- [ ] 4.1 `execution_control_fact.go`：`ResolveFactsTx` typed facts，只认已验签来源；`TestChannelPolicyFacts/repair_admit_fact_refs_verified`。
- [ ] 4.2 `execution_repair_resume.go`：追加域只扩额度、CAS 单份、replay 原结果、signed resume 一次 epoch；`TestChannelPolicyResume`（4 leaf）。
- [ ] 4.3 sensitive action 四支：新 operation EXHAUSTED、同 operation 原 receipt、撤销交错 `no_effect`、旧账本不可核实拒（`TestChannelPolicyFacts/sensitive_*`）。
- [ ] 4.4 不新增 Go 预算分支；quota deny 只消费 T 裁决（代码审查项，无独立 TC）。

## 5. S6 ingest、settlement 与 binding（P0）

- [ ] 5.1 `execution_tool_ingest.go`/`execution_control_settlement.go`：ingest→settle、原字节重放、不退款；`TestChannelIngestSettlement`（4 leaf）。
- [ ] 5.2 `BindDeliveredGenerationTx`：启动前 643–645 全匹配、不二次消费；`TestChannelIngestBinding`（6 leaf，含 G1/G2/G4 前置）。
- [ ] 5.3 `execution_control_client.go`（daemon）：commands/checkpoints/verdicts 三端点 client；`TestChannelWorkerClient`。
- [ ] 5.4 三端点 handler 与认证：只 MDT+enrolled key/owner scope；拒绝 PAT/JWT/task-token。

## 6. S7 reader 与 projection fence（P0）

- [ ] 6.1 `execution_tool_reader.go`：`ReadCommitted` 只读已验签 DB facts；`TestChannelReader`（8 leaf）。
- [ ] 6.2 `execution_projection_fence.go` + `gate_projection.go`/`crsync.go`/`reconcile.go`/strict preflight/终态上报：unsigned 只写诊断区。
- [ ] 6.3 终态 fence 并集规则：`fence_required`、409、重领、读失败、STOP_NEW 收尾。
- [ ] 6.4 `cmd/server/execution_control_composition_test.go`：`TestChannelComposition`。

## 7. R2/R3 merge 端点（P0）

- [ ] 7.1 `GET /api/daemon/execution-control/merge-facts/{crID}`：认证主体解析 workspace、闭集响应、`repos_digest` 自洽、绑定三态、`head_revoked`；`TestChannelMergeFacts`（6 leaf）。
- [ ] 7.2 `code_source_freeze` 追加写与撤销同事务置位（与 1.1 的索引配套）；`source_freeze_append_only`。
- [ ] 7.3 `POST /api/daemon/crs/{crID}/merge-effects`：`op=reserve|report`、CR 行 `FOR SHARE`、`input_digest` 重验、attempt 四支、码序；`TestChannelMergeEffects`（4 leaf）。
- [ ] 7.4 与 tools 侧 `merge-facts`/`merge-effects` 客户端的跨语言联调（契约以 R2.4/R3.1 为准）。

### 5A. 由冻结 label 反查补齐的归属（原 tasks 遗漏）

- [ ] 5A.1 `TestChannelIngestRevokedPermit`（label `revoked-permit`，SC-VC-013）：撤销 permit 生效后不再改动任何 control 行，未受影响行保持原字节。
- [ ] 5A.2 `TestChannelRecoveryD8`（label `d8-recovery`，SC-VC-016/005）：同 lineage 重启保留原字节；regrant 不得把 origin 计数清零。
- [ ] 5A.3 `TestChannelReadinessFreshWork`（label `readiness-fresh-work`，SC-VC-005）：部署就绪侧同 origin 不被 D8 重置。

## 8. S8 D7 部署就绪（P0/P1）

- [ ] 8.1 `execution_deployment_observer.go`（daemon）：受保护观测、全实例 inventory、generation 递增；`TestChannelDeploymentObserver`（4 leaf）。
- [ ] 8.2 `execution_policy_readiness_protocol.go` + readiness 路由：request/verdict exact-key、slot CAS、原字节不可改；`TestChannelReadinessProtocol`。
- [ ] 8.3 `execution_deployment.go`/`execution_policy_activation.go`：`RecordReadinessTx`/`ActivatePolicyTx`/`StopNewAdmissionsTx`/drain/retire；`TestChannelPolicyActivation`、`TestChannelReadinessRetirement`。
- [ ] 8.4 `execution_deployment_fence.go`（governance）+ `execution_launch_snapshot.go`（daemon）：`CheckDeploymentAccessTx`、`PrepareLaunch`/`CommitLaunch`；`TestChannelDeploymentAccess`（governance）、`TestChannelDeploymentLaunch`（daemon）。
- [ ] 8.5 `TestChannelReadinessComponentBoundary`（READY_COMPONENT 不得启用生产）与 `TestChannelCompositionReadiness`。
- [ ] 8.6 真实 `strict-production` 正例**不在本 change**：留 AIFI-45 下游集成，本 change 只交组件正例与 strict 反例。

## 9. 证据与收尾（P0）

- [x] 9.1 已移至 0.1（SPEC 冻结）；BUILD 期只允许经规格修订改动名单。
- [x] 9.2 `scripts/aifi45-verify/channel-evidence.mjs` + `.test.mjs`：只读校验真实非 skip PASS leaf；含「summary 看似成功但缺 leaf」反例。另有 `audit` 子命令核对「每个冻结 label 都有 CP 引用」与 `record` 子命令固定被测源码 sha256。自测 9/9。
- [ ] 9.3 每条 mutation 保存 patch hash、基线与恢复后 source hash、argv、失败 leaf 与条件断言；恢复后换 nonce 跑 green。已做到：源文件 sha256 前后一致（checker `record`/`verify` 判据）+ 失败 leaf；**未做**：统一 diff 的 patch sha256 落盘（见 `validation/test-report.md` 的缺口表）。
- [x] 9.4 `CUSTOM.md` 从 **#220** 起登记新文件与 `// AIFIRST:` 挂钩点（按当时结构；#219 已被 AIFI-45 的 EVD-007 占用，见 ADJ-1）。
- [ ] 9.5 deliver 产物写明 AIFI-45 `TC-RUN-001/002/003/006/007/010` 的重跑前置（含 M002 隔离根证据、EVD-007/008 入口选择），不写成「已回填」。

## 10. 明确不做

- [ ] 10.1 不改 AIFI-45 两个 change 目录、不动 `change-requests/`、不提交 12 个 `pkg/db/generated/*.sql.go`。
- [ ] 10.2 不部署、不启用、不做真实 CR、不 push。
- [ ] 10.3 不实现 AdmissionDecider、四阶段/resume 单 effect Runner、RUN-009 修复、legacy 业务迁移。
- [ ] 10.4 不改 EVD-007 已落地的 opt-in 语义（见 design-adjustments.md ADJ-1）；`CUSTOM.md` 从 #220 起（#219 已被 AIFI-45 占用）。

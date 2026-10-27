# 可信 T committed verdict channel — multica BUILD 任务清单

> STDD Phase 2 / Gate 2 草案。**全部任务未开始**：本文件是计划，不是执行记录。
> Gate 2 确认后才进入 BUILD；每片按 RED→GREEN 推进，不横向先写全部实现。

## 1. 迁移与 schema（P0，阻塞全片）

- [ ] 1.1 新增 `server/migrations/648_cr_execution_control.up.sql`：14 张 `cr_execution_*` 表（业务 8 + D7 5 + `code_source_freeze`）、不可变/append-only 触发器、部分唯一索引、无新 FK/cascade。
- [ ] 1.2 新增对应 `648_cr_execution_control.down.sql`：按依赖逆序撤销全部表/触发器/索引。
- [ ] 1.3 定义 `ChannelTableNames`（14 个 DB 全名，无重复），迁移专例与 schema 断言只用该清单。
- [ ] 1.4 `TestChannelMigrationAfterUp/Down/Reapply`：分别在新 nonce 库的 up、up→down、up→down→up 执行，每表一个 `t.Run`（≥14 leaf/例）。
- [ ] 1.5 `TestChannelMigrationProtectedData`：先造 643–647 夹具，再做精确 648 down/up，断言原行/对象不变、无 648 孤儿。
- [ ] 1.6 若实施时 648 已被占用：先改本清单与规格中的全部编号再顺延，不覆盖既有迁移。

## 2. S1 选择、候选与派发根（P0）

- [ ] 2.1 `execution_contract_selection.go`：`Selection` tagged union、严格不可降级、Unknown 拒绝路径；`TestChannelFoundationSelection`。
- [ ] 2.2 `execution_control_reservation.go`：`ResolveCandidateTx`、不可执行 reservation、固定候选；`TestChannelFoundationReservation/control_reservation_not_runnable`。
- [ ] 2.3 `execution_dispatch_root.go` + `service/task.go` + `queries/agent.sql`（固定 sqlc 版本生成）：同 Tx root/task/settlement、固定 ID 冲突逐字段等同、commit 后通知；`fixed_id_conflict_and_rollback`。
- [ ] 2.4 adoption/terminal 并发探针（`55P03`）与顺序语义：`root_adoption_terminal_race`（green 前置：AIFI-45 G5 已修）。
- [ ] 2.5 `execution_fresh_work.go`：`RegisterFreshWorkTx`、origin/fresh-work/legacy-catalog 三型 fact、partial unique；`TestChannelFoundationFreshWork`。
- [ ] 2.6 `service/execution_channel_task_tx_test.go`：`TestChannelTaskTx` 承接 `task-tx` 模板。

## 3. S2–S4 协议、store 与恢复（P0）

- [ ] 3.1 `execution_control_protocol.go` + `execution_control_trust.go`：`VerifyEnvelope`、trust manifest exact keys、双 key-purpose；`TestChannelProtocol`（3 leaf）。
- [ ] 3.2 `execution_control_command.go`/`store`：状态受限转换、单 open、fence、settlement kind；`TestChannelStoreState`（5 leaf）。
- [ ] 3.3 `execution_control_recovery.go`（daemon）：checkpoint 字段、恢复表五类动作、旧 fence 隔离；`TestChannelRecovery`（2 leaf）。
- [ ] 3.4 key rotation 只影响新 verdict；历史帧仍用旧 key 验证（并入 3.3 与 3.2 断言）。

## 4. S5 facts、repair/resume、sensitive action（P0）

- [ ] 4.1 `execution_control_fact.go`：`ResolveFactsTx` typed facts，只认已验签来源；`TestChannelPolicyFacts/repair_admit_fact_refs_verified`。
- [ ] 4.2 `execution_repair_resume.go`：追加域只扩额度、CAS 单份、replay 原结果、signed resume 一次 epoch；`TestChannelPolicyResume`（4 leaf）。
- [ ] 4.3 sensitive action 四支：新 operation EXHAUSTED、同 operation 原 receipt、撤销交错 `no_effect`、旧账本不可核实拒（`TestChannelPolicyFacts/sensitive_*`）。
- [ ] 4.4 不新增 Go 预算分支；quota deny 只消费 T 裁决（代码审查项，无独立 TC）。

## 5. S6 ingest、settlement 与 binding（P0）

- [ ] 5.1 `execution_tool_ingest.go`/`execution_control_settlement.go`：ingest→settle、原字节重放、不退款；`TestChannelIngestSettlement`（2 leaf）。
- [ ] 5.2 `BindDeliveredGenerationTx`：启动前 643–645 全匹配、不二次消费；`TestChannelIngestBinding`（5 leaf，含 G1/G2/G4 前置）。
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

## 8. S8 D7 部署就绪（P0/P1）

- [ ] 8.1 `execution_deployment_observer.go`（daemon）：受保护观测、全实例 inventory、generation 递增；`TestChannelDeploymentObserver`（3 leaf）。
- [ ] 8.2 `execution_policy_readiness_protocol.go` + readiness 路由：request/verdict exact-key、slot CAS、原字节不可改；`TestChannelReadinessProtocol`。
- [ ] 8.3 `execution_deployment.go`/`execution_policy_activation.go`：`RecordReadinessTx`/`ActivatePolicyTx`/`StopNewAdmissionsTx`/drain/retire；`TestChannelPolicyActivation`、`TestChannelReadinessRetirement`。
- [ ] 8.4 `execution_deployment_fence.go` + `execution_launch_snapshot.go`：`CheckDeploymentAccessTx`、`PrepareLaunch`/`CommitLaunch`；`TestChannelDeploymentAccess`、`TestChannelDeploymentLaunch`。
- [ ] 8.5 `TestChannelReadinessComponentBoundary`（READY_COMPONENT 不得启用生产）与 `TestChannelCompositionReadiness`。
- [ ] 8.6 真实 `strict-production` 正例**不在本 change**：留 AIFI-45 下游集成，本 change 只交组件正例与 strict 反例。

## 9. 证据与收尾（P0）

- [ ] 9.1 `validation/channel-test-expectations.json`：按命令 label 冻结必达 leaf 全名（含 R2.5 11 / R3.5 16 / S5 19 的跨仓归属），不由实测反推。
- [ ] 9.2 `scripts/aifi45-verify/channel-evidence.mjs` + `.test.mjs`：只读校验真实非 skip PASS leaf；含「summary 看似成功但缺 leaf」反例。
- [ ] 9.3 每条 mutation 保存 patch hash、基线与恢复后 source hash、argv、失败 leaf 与条件断言；恢复后换 nonce 跑 green。
- [ ] 9.4 `CUSTOM.md` 从 #219 起登记新文件与 `// AIFIRST:` 挂钩点（按当时结构）。
- [ ] 9.5 deliver 产物写明 AIFI-45 `TC-RUN-001/002/003/006/007/010` 的重跑前置（含 M002 隔离根证据、EVD-007/008 入口选择），不写成「已回填」。

## 10. 明确不做

- [ ] 10.1 不改 AIFI-45 两个 change 目录、不动 `change-requests/`、不提交 12 个 `pkg/db/generated/*.sql.go`。
- [ ] 10.2 不部署、不启用、不做真实 CR、不 push。
- [ ] 10.3 不实现 AdmissionDecider、四阶段/resume 单 effect Runner、RUN-009 修复、legacy 业务迁移。

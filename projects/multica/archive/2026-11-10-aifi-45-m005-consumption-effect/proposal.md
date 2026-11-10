# AIFI-45 M005：平台在 consumption 提交时签发可信 effect，使生产准入可达 ADMITTED

<!-- source_hash: 886dd7b6d88333fd -->
<!-- generated_at: 2026-11-10T22:13:59.025079 -->
<!-- canonical: canonical/proposals/2026-11-10-aifi-45-m005-consumption-effect.yaml -->

## Why

准入决策器 DecideAdmission 只认「该 consumption 的 task 有一条 effect 结算，且结算指向一条已入链、
签名通过、command_digest 与冻结命令一致的 v2 verdict」。这条链的写入口
（ApplyControlCommandTx / AppendVerdictFrameTx / SettleControlCommandTx）已建成并有测试，
但生产里没有任何调用方，所以生产准入永远停在 WAIT_TRUSTED_T_COMMIT。
AIFI-45 的信任模型（2026-11-10 已批准）规定：T（含 crctl）是非可信客户端，签发者在服务端，
服务端只对自己能核实的事实签发。服务端现在唯一已经在核实并提交的事实，是
HandleDaemonExecutionConsumption 里的 consumption 回执：认领行、授权头、已签发的绑定证明
都在同一事务里重验过。


## What Changes

- 新增服务端签发函数：在 consumption 回执首次落库的同一事务内，按既有写入口冻结 command、入链 v2 verdict（effect）、结算为 effect；request_id 取 consumption.task_id。
- HandleDaemonExecutionConsumption 在回执 INSERT 成功路径（首次写入）调用该函数；签发失败则整笔事务回滚，不留下「有回执无 effect」。
- 用平台已有的 execution Ed25519 密钥签名，信任清单在进程内由该密钥按链作用域现生成；不引入清单文件、pin 仪式或第二把密钥。
- 校正 execution_admission.go 中「写入口无生产调用方」的陈旧注释；登记 CUSTOM；selections.json 增加一个一次性库选择。

### New Capabilities

- **consumption-effect**：平台提交 consumption 回执时同事务签发该 task 的可信 effect，并保证链连续、重放与新 generation 不重复、失败整体回滚。

### Modified Capabilities

- **authorized-runner**：SC-RUN-003 中「可信 T 事务已提交」在 execution-consume 上由「平台已提交的 consumption effect」满足；其余场景不变。

## Success Criteria

- [ ] 一次经真实路由的 consumption 请求成功（201）后，该 task 恰有 1 条 command(settled_effect)、1 条 verdict、1 条 effect 结算，三者 request_id 均等于 consumption.task_id，command_digest 等于冻结 command 字节的 sha256；DecideAdmission 由 WAIT_CONSUMPTION 变为 ADMITTED。
- [ ] 同一 CR 的第二个 task 的 consumption 使链连续（seq=2，prev_digest 等于第一条 verdict 的 digest）；同一 task 的重放（200，changed=false）与新 generation 的 consumption 不新增 command/verdict/settlement。
- [ ] 签发失败时（预置同 request_id 的冲突 command）consumption 请求失败且 cr_execution_consumption 无该行。
- [ ] 既有 consumption、准入、TC-RUN-002/003/010 与 NTF 用例在一次性库上结果不变（0 FAIL、0 skip）。
- [ ] diff 内无迁移文件、无新路由、无 T 或 daemon 文件改动。

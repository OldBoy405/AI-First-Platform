# multica 执行恢复与证据闭环

<!-- source_hash: 2c674f1250c9d490 -->
<!-- generated_at: 2026-11-16T10:13:24.796211 -->
<!-- canonical: canonical/proposals/2026-11-16-multica-execution-evidence-closure.yaml -->

## Why

2026-11-16 核对基线：multica main 与 origin/main 均为 294d793a91c8f1dce2f97a549b41cf468e562b1a；tools 已发布含快照读取规则的 7a0a2ab57f3f5e2c583c3523bc69d67e7be115c1。
sqlc 重新生成和 pg 的 CJS 导入已有提交，不重复纳入。当前残余在同一执行与证据链上：Runner 在锁住 run A 后按 CR 重读，可能继续执行 run B；selection 对账器的字段集合不接受本机 Go 1.27.1 官方 TestEvent 的 OutputType 等字段，部分 selection 因而撤回 expected，少跑一个测试仍可能 PASS。
.github/aifirst-tools-pin 仍为 e52b8081f159d581bf62f82447c76f818fc52426，backend-tests 未设置 MULTICA_CONTROLLED_SHELL_RULES，已有六项本地权威规则通过记录不能证明 CI 接线成立。
backend-tests-green 的最新实际 CI run 43727687773 因账单/额度未启动；原 change 经用户裁定 TC-BTO-005 为 N/A 后已归档，本 change 不重开它，也不把该裁定继承为新的 CI 通过证据。
CUSTOM 已登记部分局部修复，但前三数基线和状态文字仍需与实际落点对齐；packages 第四数缺测量口径，用户明确确认本次暂不收口。


## What Changes

- Runner 恢复时被执行的 run 必须与被锁 run 一致；目标切换不得借旧锁继续执行新 run，正常推进与取消语义仍成立。
- 精确选择对账接受已核实受支持 Go 版本的合法测试事件，所声明测试缺失、失败、跳过或流不完整时拒绝；为 governance-run-lock 恢复明确的 expected 名单。
- multica CI 接线读取已发布的唯一 tools pin 与权威 controlled-shell 规则（pin、env、必需文件与离线接线测试本轮已交付并验证）；六项现有规则测试在真实 CI 实际读取该规则的权威验证本轮经用户裁定延期（接受风险），不以本地/fixture 回落冒充。
- CUSTOM 登记本次改动、实际验证边界与交付状态，重算追加前三数基线；第四数口径保持明确未决，不猜测、不改写历史。

### Modified Capabilities

- **governance-runner-run-lock**：恢复执行的 run 身份与锁身份一致，保留既有串行、取消和有限连接池保证。
- **selection-reconciliation**：合法 Go 事件可对账，声明的测试选择完整且全通过才成功。
- **ci-backend-environment**：backend-tests 使用唯一已发布 tools pin 的权威规则，并以实际 runner 结果形成证据。

## Success Criteria

- [ ] 一组真实库并发回归证明：目标未变时正常执行；目标从 A 换成 B 时不能在 A 锁下执行 B；同一 run 不并发推进，取消仍释放等待。
- [ ] 一组事件流矩阵证明：支持版本的合法事件被接受；声明测试缺一个、失败、跳过或流不完整均拒绝；governance-run-lock 的两个既有测试均被 expected 明确列出。
- [ ] 权威目标合同：最终业务提交的实际 CI 中 pin 检出与完整性检查通过、backend-tests 实际执行成功，六项规则测试实际读取该 pin 的权威 rules.json，不能以 skipped、fixture 或本地结果替代。本轮因账单/额度阻塞（run 43752944966）经用户明确裁定延期，记为接受风险并保持未验证，额度恢复后另行验证；不以本地/离线结果冒充权威闭环。
- [ ] 一次 CUSTOM 人工核对可追溯本次改动与证据，前三数按明确口径追加，第四数明确保持未决；不改写历史或把测量数当产品通过保证。

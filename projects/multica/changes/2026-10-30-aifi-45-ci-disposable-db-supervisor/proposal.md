# AIFI-45 隔离测试环境与资源监督

<!-- source_hash: f7a236a9b1c67abf -->
<!-- generated_at: 2026-11-10T20:02:51.770365 -->
<!-- canonical: canonical/proposals/2026-10-30-aifi-45-ci-disposable-db-supervisor.yaml -->

## Why

AIFI-45 的数据库、进程和受控工具链验证需要可证明归属且可恢复的隔离环境。现有假引擎与纯内存测试不证明真实容器、进程树退出或资源清理；测试包装器还存在 TMPDIR 含冒号时 PATH 被拆分的静态风险。历史事故库仍为 HOLD，不能拿它作为可丢弃测试库。


## What Changes

- 评审并实现安全的隔离数据库执行及监督能力，覆盖资源身份、持久记录、lost-ack 恢复、进程退出和基于所有权证据的清理；AIFI-45 验收使用版本化入口，入口在同一资源信封内替换时只在 AIFI-45 test-plan 登记，不另走 Gate2 设计调整。
- 审查并修复 test-go 包装器及其测试的临时目录和 PATH 边界，保持已确认的调用和空 TMPDIR 行为兼容；先取得独立认可的安全复现条件。
- 将实际隔离、测试运行及资源处置证据交回 AIFI-45；未授权的数据库、真实 CR、外部服务及未知资源保持不操作。

### Modified Capabilities

- **isolated-test-supervision**：为测试环境与资源生命周期提供可核验的隔离、恢复和所有权边界。

## Success Criteria

- [ ] 资源信封一次获批，明确资源身份、权限、故障恢复、进程退出证据和未知资源处置，并完成独立安全评审。
- [ ] 在获准隔离环境中复现并验证 TMPDIR/PATH 的拒绝与正常路径兼容，不调用真实 agent CLI 或未经授权的 DB。
- [ ] 满足条件后，以同一源码快照取得可复核的真实隔离与资源清理证据，交由 AIFI-45 独立验收。

# 未知操作默认拒绝：作者证据

按 `UNKNOWN-OP-PLAN.md`，原版保存在 `source-unknown-op-before/`：源码 raw SHA `f1e719d9388c09eadecc9da17aa21bdafb080265237fabd8b58dc0f50b728811`；原 fake-Tx 测试 SHA `c30f2816bd0f48359941f1993f85273feb481bc2169b6abc688d0b5f68b573f0`。

清除 DB/PG 环境、`GOPROXY=off`、`GOWORK=off`，先在未修复源码执行新测试 `go test -count=1 -run '^TestUnknownOperationIsDenied$' -v ./internal/governance/deploymentaccess_test`，exit 1：ACTIVE/未过期实际返回 `NewAdmission`、预期 `Denied`；其他三种状态均通过。随后将 ACTIVE 的 NewAdmission 限定为已知五个新增操作或两个恢复操作，未知操作拒绝；补 ACTIVE 两个恢复操作的行为保留正控。

修后同一独立 no-DB 子包 `go test -count=1 -json ./internal/governance/deploymentaccess_test`，exit 0：5 顶层，61 个 leaf PASS，0 fail、0 skip；输入文件前后 SHA 相同。源码 SHA `dc6407f98b07fbd63d7c039a5db497a9540b3dd674206b320b3e31cd92a18e7b`；测试 SHA `8dd07c9609f5657d39b45a991cc6ba2d18be8f9bd2167437187b09f2d5d69adf`。变更已登记 multica `CUSTOM.md` #271。

本结果只覆盖假事务和操作闭集，未验证 DB、签名、当前 activation 身份、异常 mode、零字段恢复或锁竞态；无真实生产调用，RUN-006 仍 MISSING。待独立审核；不覆盖既存报告及旧快照。

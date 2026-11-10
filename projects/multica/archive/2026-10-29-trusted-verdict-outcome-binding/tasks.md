# 2026-10-29-trusted-verdict-outcome-binding — multica（M 消费侧）任务清单

> 切片依据 [design](design.md)（S2）与 [T design](../../../tools/changes/2026-10-29-trusted-verdict-outcome-binding/design.md)。不加表、不加列、不加迁移：冻结命令字节与 verdict 行已分别落在 `cr_execution_control_command.command_bytes` 与 `cr_execution_tool_verdict`，绑定所需事实齐全。

## 1. verdict-channel / 可信裁决验签（P0）

- [x] 1.1 协议常量升级：verdict schema → `execution-control-verdict/v2`，domain 不变
- [x] 1.2 v2 verdict payload 闭集校验（`schema/purpose/domain/scope/frame/request_id/epoch/sequence/previous_verdict_digest/result/effect/command_digest`），未知或缺失字段拒绝
- [x] 1.3 新增 `VerifyTrustedVerdictEffect`：给定 envelope、期望 scope、trust manifest、冻结命令字节，返回 result 与 digest；v1、未知 effect、`command_digest` 与 `sha256(command_bytes)` 不符、scope 不符、签名无效一律拒绝
- [x] 1.4 准入接线：`DecideAdmission` 在 trusted 计数成立后追加 1.3 的校验，任一失败回落 `WAIT_TRUSTED_T_COMMIT`
- [x] 1.5 `CUSTOM.md` 按现有结构登记（token 沿用 `AIFI-45`，行内标注本 change id；不新造 CR 身份）

## 2. 测试与验证（P0）

- [x] 2.1 TC-VM-003/004/005 → 纯函数负例：v1、未知 effect、错 request/scope、错 `command_digest`、多余字段
- [x] 2.2 TC-VM-018 → 准入状态表驱动测试（不含 DB）
- [x] 2.3 TC-VM-014 → 既有 `interop_test.go` 动态调用 Node 模块，确认 v2 向量双侧一致
- [x] 2.4 `go build ./...` 与 `go test ./internal/governance/` 通过

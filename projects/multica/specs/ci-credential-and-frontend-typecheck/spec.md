# Spec: ci-credential-and-frontend-typecheck

> Change: 2026-11-12-fork-ci-test-evidence-trust | Auto-generated Human View

## Requirements

### Requirement: transitions 的 tools 凭据失败原因可区分且不泄漏凭据；packages/views 的 typecheck 恢复。

#### Scenario: SC-CCF-001

- **GIVEN** tools-access 可注入 fetch，
- **WHEN** 分别返回：凭据为空、401、403、404、200、网络异常、其他状态。
- **THEN** SHALL 映射为 missing、rejected、no-access-or-pin-not-found、ok、inconclusive，非 ok 时非 0 退出；SHALL 任何输出与错误信息不含 token 值；请求头 SHALL 仅在 fetch 调用内使用。

#### Scenario: SC-CCF-002

- **GIVEN** packages/views 的 use-logout.test.ts 改用 @multica/core 包导入，
- **WHEN** 运行 @multica/views 的 typecheck 与该测试文件。
- **THEN** SHALL typecheck 0 条 TS6059；use-logout.test.ts SHALL 全部通过；其断言 SHALL 与改前等价（不删除、不放宽）。
- **AND** 若修好 typecheck 后暴露其他前端失败，SHALL 先报告再裁定范围（design U4）。

#### Scenario: SC-CCF-003

- **GIVEN** 管理员已按最小权限更新 AIFIRST_TOOLS_READ_TOKEN，
- **WHEN** 重跑 transitions-contract-check。
- **THEN** SHALL 该 job 通过；管理员未完成更新时 SHALL 如实列为未闭合。
- **AND** 本 change SHALL NOT 读取、创建或轮换凭据。

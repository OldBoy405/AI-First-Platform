# Spec: execution-wait-visibility

> Change: 2026-11-18-defensive-trim-multica | Auto-generated Human View

## Requirements

### Requirement: 状态与进展使用同一个 run 状态；读取失败按 GET 和已提交 POST 的各自出口处理。

#### Scenario: SC-EWV-101

- **GIVEN** 同工作区的 run 可在首读后由 running 转为 completed，实际读取的前沿 runner 详情也可分别为缺失、对象或非对象。
- **WHEN** 经生产 GET 读取 run 状态与进展。
- **THEN** SHALL 用同一行 status 填顶层并选择进展分支，首读为 running 时不答 progress.state=completed。
- **AND** 缺 runner 键可正常读取；实际读取的 runner 为数组、标量或字面 null 时，running 与 failed 分支均返回 500 query failed。

#### Scenario: SC-EWV-102

- **GIVEN** run 状态是未知值，或是 running 且无 running 前沿。
- **WHEN** 以该状态调用生产进展推导。
- **THEN** SHALL 对未知状态返回错误而非 idle；对无 running 前沿的 running 状态返回 idle。

#### Scenario: SC-EWV-103

- **GIVEN** architecture start 或 requirement resume 已成功提交，回执的进展读取失败。
- **WHEN** 生成 POST 回执。
- **THEN** SHALL 返回成功状态、已提交的 run_id 与 changed，记录读取错误并省略 progress。

### Requirement: 生产进展叶子 GET 与同前缀的启动、恢复 POST 共存。

#### Scenario: SC-EWV-104

- **GIVEN** NewRouterWithOptions 装配生产路由，有真实成员 JWT 和 POST 的真实 mat_ 凭证。
- **WHEN** 切换 Runner 开关查询同一 run，并在开启时用各自正确的请求体对不存在的 CR 发两个 POST。
- **THEN** SHALL 对同一成员 GET 在 Runner 关时返回 404、开时返回 200；开启时两个已认证 POST 均抵达各自 handler 并返回 400 RUNNER_CR_NOT_READY。

# Spec: ci-backend-environment

> Change: 2026-11-12-fork-ci-test-evidence-trust | Auto-generated Human View

## Requirements

### Requirement: fork CI 的 backend-tests 为 nonce 门禁包提供真实的一次性库，且门禁每个拒绝条件都被独立测试；不放宽 nonce 门禁。

#### Scenario: SC-CBE-001

- **GIVEN** 给定一个可连接的 Postgres 管理员 URL（本地用注入的假连接），
- **WHEN** 执行 ci-provision up 再 down，以及 up 未完成时执行 down。
- **THEN** SHALL 由 up 用既有 createDisposableDatabase 建出符合 TestMain 全部身份检查的库与角色（库名 aifi45_tmp_<nonce>、角色 aifi45_role_<nonce>、库与角色 marker、非超级用户），并把 DATABASE_URL、AIFI45_DISPOSABLE_NONCE 写入环境文件且先对口令发出 ::add-mask::；SHALL 由 down 在 marker 匹配时删除库与角色；marker 不符 SHALL 拒绝删除并非 0 退出。
- **AND** handle 缺失（up 在写出前失败）时 down SHALL 以 0 退出并说明无资源可清理。
- **AND** 任何日志、stdout/stderr 与 handle 文件 SHALL NOT 含明文口令；GITHUB_ENV 中的 DATABASE_URL 承载 job 级一次性角色口令，写入前 SHALL 先对该口令发出 ::add-mask::，且该口令 SHALL NOT 被复用于任何非一次性资源。

#### Scenario: SC-CBE-002

- **GIVEN** cmd/server 与 governance 各自的 verifyDisposableTestDatabase，
- **WHEN** 对 nonce 格式、库名、角色名、session_user 不等于 current_user、库非所有者、库 marker、角色 marker、superuser、createdb、createrole、bypassrls 逐条单独构造失败。
- **THEN** SHALL 每一条单独退化都被拒绝，且该条件由独立命名的子测试逐条归因；合法的 nonce 库 SHALL 通过。
- **AND** 该测试 SHALL 在 runner 自建一次性库内真实执行，skip 为 0 且至少一个叶子 PASS。
- **AND** 门禁本身 SHALL NOT 被放宽。

### Requirement: tools 依赖只有一个 pin 来源；CI 与本地不依赖开发机路径；缺依赖是失败而不是 skip。

#### Scenario: SC-CBE-003

- **GIVEN** 仓库存在 .github/aifirst-tools-pin（单行 40 位 hex），ci.yml 的两个消费者从它读取 ref，
- **WHEN** 运行 tools-pin 的 read 与 check：pin 文件合法或非法，检出目录缺少 execution-control-protocol.mjs、control-vectors.json 或 crctl.mjs 之一。
- **THEN** SHALL read 对非 40 位 hex 或多行文件硬失败；SHALL check 在任一必需文件缺失时非 0 退出并打印 pin 与缺失文件名；全部存在时 SHALL 退出 0；ci.yml 中 SHALL 不再出现 tools 的字面 commit。
- **AND** 对 ci.yml 字面 ref 的检查 SHALL 逐行解析（split(/\r?\n/)），解析失败硬失败。

#### Scenario: SC-CBE-004

- **GIVEN** server/internal/governance 与 crosslang_test 下的 *_test.go，
- **WHEN** 静态契约检查：搜索 C:/Users/ 开发机绝对路径，以及依赖 AIFI45_TOOLS_ROOT 或 CRCTL_MJS 的测试在环境变量缺失时的处理。
- **THEN** SHALL 源码中不含开发机绝对路径默认值；SHALL 缺失 CRCTL_MJS 或 AIFI45_TOOLS_ROOT 的测试以 Fatal 结束而不是 Skip；契约检查本身 SHALL 能对注入了旧默认路径或 t.Skip 的样例变红。

#### Scenario: SC-CBE-005

- **GIVEN** CI 的 backend-tests 在修复后的 ci.yml 下运行（需推送授权与 tools pin 可用，见 design U1），
- **WHEN** 查看该 run 的 Test 步骤与 ci-evidence 步骤。
- **THEN** SHALL cmd/server、governance、crosslang_test、handler 各自有通过的测试且无名单外 skip；若走 U1 路径 β（tools 未推送），SHALL 如实记录 tools 相关测试未验证并使 pin 完整性检查失败，不得 skip 或报绿。
- **AND** 验收报告 SHALL 记录 run id、commit、各 job 结论。

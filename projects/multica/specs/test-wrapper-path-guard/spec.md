# Spec: test-wrapper-path-guard

> Change: 2026-10-30-aifi-45-ci-disposable-db-supervisor | Auto-generated Human View

## Requirements

### Requirement: 测试包装脚本在创建临时目录和改写 PATH 之前，拒绝含 `:` 的临时根；空 TMPDIR 的 `/tmp` 回退不变。

#### Scenario: SC-TWG-001

- **GIVEN** `TMPDIR` 指向一个存在且路径含 `:` 的私有目录；待执行命令是以绝对路径给出的假命令，被执行时会写标记文件。
- **WHEN** 通过 `go-test-with-agent-cli-guard.sh` 执行该假命令。
- **THEN** 脚本 SHALL 以非零退出，stderr 说明临时根含 `:`，且假命令 SHALL NOT 被执行（标记文件不存在）。
- **AND** 修复前同一用例 SHALL 观察到标记文件（用以证明该用例能发现问题）。

#### Scenario: SC-TWG-002

- **GIVEN** `TMPDIR` 是一个不存在且路径含 `:` 的值。
- **WHEN** 运行 `test-go.test.sh`。
- **THEN** 脚本 SHALL 在 `mktemp` 之前以退出码 2 退出，stderr 说明临时根含 `:`。
- **AND** 该用例只在修复后验证；它 SHALL NOT 依赖运行修复前的行为。

#### Scenario: SC-TWG-003

- **GIVEN** `TMPDIR` 为空，待执行命令是会写标记文件并以固定码退出的假命令。
- **WHEN** 通过 `go-test-with-agent-cli-guard.sh` 执行该假命令。
- **THEN** 假命令 SHALL 被执行（标记文件存在），脚本 SHALL 返回该命令的退出码，且既有的 `test-go.test.sh` 用例 SHALL 仍然通过。

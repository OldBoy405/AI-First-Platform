# Spec: backend-tests-ownership

> Change: 2026-11-15-multica-backend-tests-green | Auto-generated Human View

## Requirements

### Requirement: bigm 用例在受限角色的一次性库上通过（读统计用 `pg_stats`）。

#### Scenario: SC-BTO-001

- **GIVEN** 一次性库与 `NOSUPERUSER NOCREATEDB` 的一次性角色，已迁移
- **WHEN** 运行 `TestIssuePropertiesBigramIndexBuildsOnlyWherePGBigmExists`
- **THEN** SHALL 通过
- **AND** 角色权限与改前相同（不加 CREATEDB、不加 pg_read_all_stats）

### Requirement: 4 个测试的归属被声明且通过检查：3 个 `ci-admin`、1 个 `independent`（`DownRoundTrip`）；它们都被共享 run 的 skip 正则排除。

#### Scenario: SC-BTO-002

- **GIVEN** 改后的 `test-ownership.json`
- **WHEN** 运行 `test-ownership.mjs check` 与 `test-ownership.mjs skip-regex`
- **THEN** SHALL `check` 退出码为 0，且 skip 正则同时包含这 4 个测试名
- **AND** 原有的 4 个 independent 条目与 allowed-skips 仍在

#### Scenario: SC-BTO-003

- **GIVEN** podman 可用；`selections.json` 的 `governance-migration-roundtrip`
- **WHEN** 运行 `run-selection.mjs --selections selections.json --only governance-migration-roundtrip`
- **THEN** SHALL 该 selection 通过（自己的一次性库上，单独运行）

### Requirement: claim deadline 用例有定性记录，不修也不 skip，除非复现并确认根因。

#### Scenario: SC-BTO-004

- **GIVEN** C1–C4 已落地；`--cpus=2` 的 Go 容器与一次性库
- **WHEN** 对 `TestClaimTasksByRuntime_PartialSuccessFitsClientDeadlines` 重复运行至少 20 次
- **THEN** SHALL `design-adjustments.md` 记录运行次数、失败次数、失败的错误全文与是否带 `-race`，并写出结论（复现并修复，或无法复现及依据）

### Requirement: 真实 CI 与台账：落地后 backend-tests 不再出现原 7 个失败；`CUSTOM.md` 登记本 change 的定制。

#### Scenario: SC-BTO-005

- **GIVEN** 本 change 的提交已推送（另行取得授权），CI 对该提交跑完 backend-tests
- **WHEN** 对比该 run 的失败集合与 run 43687569973 的 8 例
- **THEN** SHALL 原 7 例（4 个权限、`DownRoundTrip`、`TestMTick003` 超时、`DeleteWorkspace`）不再出现；claim 用例按 SC-BTO-004 的结论处理，run id 记入 test-report

#### Scenario: SC-BTO-006

- **GIVEN** 改后的 `CUSTOM.md`
- **WHEN** 检查本 change 的登记行与换行
- **THEN** SHALL 登记行列出本 change 触达的 multica 定制，文件为 CRLF 且无裸 LF

# Spec: controlled-shell-git-show-shapes

> Change: 2026-11-15-controlled-shell-snapshot-read-shapes | Auto-generated Human View

## Requirements

### Requirement: `controlled-shell/rules.json` 的 `git[sub=show]` 放行 5 种形状：原有 2 种（review-annotations/*.yml， 以及 _backlog.yml／_history.yml／CR-…/cr.md）与新增 3 种（`--name-only --format= <40hex>`、 `<40hex>:change-requests/CR-…/test-report.md`、`<40hex>:change-requests/CR-…/trace.tests[.yml|.yaml|.json]`）。

#### Scenario: SC-001

- **GIVEN** 真实 `rules.json` 的 `git[sub=show]` 形状，按 `crctl.mjs controlledGit` 的方式构造（`new RegExp`）， 匹配对象为 `args.join(' ')`
- **WHEN** 对放行表中每个参数组合做匹配
- **THEN** SHALL 每个都被放行
- **AND** 放行表含：`--name-only --format= <40hex>`；`<40hex>:change-requests/CR-2026-002/test-report.md`；`…/trace.tests`、`.yml`、`.yaml`、`.json` 四种后缀；账本式 KEY（`CR-FS-2026-003`、`CR-AFP-2026-1000`）
- **AND** 原有 2 种形状各至少 1 个正例（`review-annotations/requirement.yml`、`_backlog.yml`、`_history.yml`、`CR-2026-002/cr.md`）

### Requirement: 放宽不得放宽到近似形状：简写 sha、rev 或分支名、路径穿越、非批准文件、后缀松弛、大小写或长度不合法的 KEY 一律拒绝。

#### Scenario: SC-002

- **GIVEN** 同 SC-001 的匹配方式与真实 `rules.json`
- **WHEN** 对拒绝表中每个参数组合做匹配
- **THEN** SHALL 每个都不被任何 show 形状放行
- **AND** 拒绝表为 11 种：`HEAD:…/_backlog.yml`；7 位简写 sha；`_backlog.yml/../_history.yml` 路径穿越；`CR-2026-002/prd.md`；`trace.tests.exe`；`test-report.md/../cr.md` 路径穿越；`approval.yml`；`package.json`；`_backlog.yml_extra`；小写 KEY `CR-fs-2026-003`；9 位 KEY `CR-ABCDEFGHI-2026-003`

### Requirement: 本 change 对 `rules.json` 的修改范围只有 `git[sub=show].shapes`，不改 callers、其他子命令、 forbiddenFlags、protectedPaths。

#### Scenario: SC-003

- **GIVEN** 改前（HEAD）与改后的 `rules.json`
- **WHEN** 对两个版本做逐字段比较（把 `git[sub=show].shapes` 排除在外）
- **THEN** SHALL 其余全部相同
- **AND** `git[sub=show].shapes` 相对改前只增不减，原两条形状逐字保留

### Requirement: 在 multica 仓用本仓已提交的 `rules.json` 运行其 6 个依赖该规则的测试，全部通过。

#### Scenario: SC-004

- **GIVEN** multica 工作区，`MULTICA_CONTROLLED_SHELL_RULES` 指向本仓已提交的 `rules.json`
- **WHEN** 运行 `go test ./internal/daemon -run '^(TestM26B2TestFactsPayload|TestM26B2TestFactsPreserveFailures|TestM26B4CollectorKeepsBothReviewStages|TestM26B4ScanEmitsIndependentTestEvent|TestM26B4ScanTestOnlyAndReviewOnly|TestProposedSnapshotReadShapes)$'`
- **THEN** SHALL 6 个测试全部通过，且 multica HEAD sha 与命令输出记入 test-report

### Requirement: 文档与规则一致：`controlled-shell/SKILL.md` 的 `show` 说明列出 5 种形状；CUSTOM-TODO-017 的描述与 rules.json 相符， 并说明 `callers` 当前仅声明、不强制。

#### Scenario: SC-005

- **GIVEN** 改后的 SKILL.md、CUSTOM.md 与 rules.json
- **WHEN** 人工逐条对照 `show` 的形状清单与 TODO-017 的描述
- **THEN** SHALL 清单与描述和 rules.json 逐条一致，且不含相互矛盾的说法

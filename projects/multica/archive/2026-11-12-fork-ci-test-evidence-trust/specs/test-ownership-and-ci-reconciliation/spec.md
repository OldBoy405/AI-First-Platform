# Spec: test-ownership-and-ci-reconciliation

> Change: 2026-11-12-fork-ci-test-evidence-trust | Auto-generated Human View

## Requirements

### Requirement: 每个专项测试有唯一验收归属；归属表与源码、CI 实际执行互相核对，缺跑或静默跳过即失败。

#### Scenario: SC-TOR-001

- **GIVEN** test-ownership.json 列出独立入口承担的测试（package、test、entry、reason），
- **WHEN** 运行 check：条目对应真实的 func TestX(、拼错的条目、缺 reason 的条目、重复条目。
- **THEN** SHALL check 对不存在、缺 reason、重复的条目非 0 退出并指名；通过时 SHALL 输出名单与数量；SHALL skip-regex 输出 ^(A|B|…)$ 且名称中的正则元字符被转义。
- **AND** 初始条目 SHALL 含 daemon.TestChannelIsolation 与 governance 的两个状态敏感探针，其余条目 SHALL 由整包基线证据加入。
- **AND** 归属表 SHALL 允许 owner=known-finding 的条目承载经用户裁定不在本 change 内修复的已知失败；该条目 SHALL 指名后继议题与复现命令，SHALL 与其他条目一样被 check 核对真实 func、被 skip-regex 排除、被 ci-evidence 核对排除生效，且 SHALL NOT 被计为覆盖。

#### Scenario: SC-TOR-002

- **GIVEN** scripts/test-go.sh 新增 --skip-regex 与 --json-out（上游文件挂钩点），
- **WHEN** 带与不带这两个参数运行 test-go.test.sh；被测 go 以假命令代替。
- **THEN** SHALL --skip-regex 原样传给 go test -skip；SHALL --json-out 同时落盘事件流并透传 go test 的退出码（pipefail）；缺参数值 SHALL 拒绝；不带新参数时行为 SHALL 与改前一致。

#### Scenario: SC-TOR-003

- **GIVEN** ci-evidence 读取 go test -json 事件流及声明（必需包、skip 允许名单、排除名单），
- **WHEN** 分别喂入：必需包 0 个通过测试、包无事件（TestMain 静默 exit 0）、名单外 skip、排除项出现在事件流、半截 JSON 或缺包级结论、全部合规。
- **THEN** SHALL 前五种每一种单独非 0 退出并指明包或测试；合规流 SHALL 退出 0；SHALL 逐行解析且解析失败硬失败（不取首行、不静默忽略）；SHALL 打印排除名单与数量。
- **AND** 对 handler TestMain 在库不可达时 exit 0 的情形，SHALL 以必需包 0 通过测试判红。

#### Scenario: SC-TOR-004

- **GIVEN** D1 的独立入口：TestChannelIsolation 经 WSL AIFI-ISO（root 加 AIFI45_ISOLATION_PROFILE），两个状态敏感探针经 run-selection 的 down/reapply 初始状态，
- **WHEN** 本地在授权后真实执行并保存输出。
- **THEN** SHALL 每项通过数不少于 1、skip 为 0，并把命令、退出码、通过数记入验收报告；任一项不能执行（如 WSL profile 失效）时 SHALL 如实列为未覆盖，不得以同 uid 对照代替。
- **AND** 执行前 SHALL 先向用户说明并征得同意（WSL 启动、podman 实例）。

#### Scenario: SC-TOR-005

- **GIVEN** change 的验收报告 validation/acceptance-report.md，
- **WHEN** BUILD 结束时检查。
- **THEN** SHALL 逐项列出实际执行的 CI run 与本地命令、退出码、通过/失败/跳过数、测试范围与未覆盖项；对 skip 大于 0 的包 SHALL 逐个说明；SHALL NOT 出现未执行却标通过的项。

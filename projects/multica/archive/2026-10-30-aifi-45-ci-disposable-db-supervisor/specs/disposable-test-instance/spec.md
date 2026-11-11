# Spec: disposable-test-instance

> Change: 2026-10-30-aifi-45-ci-disposable-db-supervisor | Auto-generated Human View

## Requirements

### Requirement: 一次性库测试入口只使用自己按固定资源信封创建的实例，不接受外部给定的 admin 连接。

#### Scenario: SC-DTI-001

- **GIVEN** 入口需要创建一个一次性库实例，实例 nonce 为 N，生命周期上限为 T 秒。
- **WHEN** 构造 `podman run` 的参数。
- **THEN** 参数 SHALL 包含 `--pull=never`、`--rm`、`--timeout=T`、仅绑定 127.0.0.1 的随机宿主端口映射、覆盖 `/var/lib/postgresql/data` 的 tmpfs、名称 `aifi45-disposable-N` 与标签 `aifi45.disposable=N`、镜像 `docker.io/pgvector/pgvector:pg17`。
- **AND** 参数 SHALL NOT 含 `-v`、`--volume`、`--mount`、`--privileged`、host 网络或 `--publish-all`。
- **AND** 随机密码 SHALL NOT 出现在参数数组里，只经子进程环境传入。
- **AND** T 大于 3600 或不是正整数时 SHALL 拒绝构造。

#### Scenario: SC-DTI-002

- **GIVEN** 调用方传入 `--admin-url`，不论是否同时设置了环境变量 `AIFI45_ADMIN_URL`。
- **WHEN** 运行 `run-selection.mjs`。
- **THEN** 入口 SHALL 在创建任何容器或连接任何数据库之前以非零退出，并说明不接受外部 admin 连接。

### Requirement: 释放实例只按创建时返回的完整容器 ID，且回读名称与标签都匹配才删除；释放后读回为零。

#### Scenario: SC-DTI-003

- **GIVEN** 完整 ID 为 ID 的容器，名称为 `aifi45-disposable-N`，标签集合含 `aifi45.disposable=N`（可含其他标签）。
- **WHEN** 调用 `releaseInstance({id: ID, nonce: N})`。
- **THEN** SHALL 对 ID 发出 `podman rm -f -v`，随后按 ID 和按标签读回，二者都为空才返回成功。
- **AND** 读回仍有容器时 SHALL 抛错，不报告成功。

#### Scenario: SC-DTI-004

- **GIVEN** 按 ID 读回的名称不等于 `aifi45-disposable-N`，或标签集合不含精确的 `aifi45.disposable=N`（含仅子串相同的情形），或按 ID 查不到容器。
- **WHEN** 调用 `releaseInstance({id: ID, nonce: N})`。
- **THEN** SHALL 抛错并说明保留实例，且 SHALL NOT 发出任何 `podman rm` 命令。

### Requirement: 实例有生命周期上限：入口被强杀、没有机会释放时，实例在上限内自毁。

#### Scenario: SC-DTI-005

- **GIVEN** 用上限 T（短值）真实创建了一个 detached 实例，持有它的入口进程尚未释放。
- **WHEN** 强杀该入口进程，不执行释放。
- **THEN** 按完整 ID 读回 SHALL 在 T 加宽限时间内为零。
- **AND** 实例已创建且入口被强杀时，除该实例及其匿名资源外，其他容器与卷的集合 SHALL 不变。

### Requirement: 入口在成功和失败的选择之后都释放自己创建的实例，并输出可核对的读回证据。

#### Scenario: SC-DTI-006

- **GIVEN** podman 与本机镜像可用；清单里有一个会真实通过的选择和一个会失败的选择。
- **WHEN** 运行 `run-selection.mjs`。
- **THEN** 入口 SHALL 逐个选择在其库上跑完，整体退出码非零（因为有失败的选择），并在退出前释放实例，输出该实例容器 ID 前 12 位与读回为零的证据。
- **AND** 运行前后其他容器与卷的集合 SHALL 不变。
- **AND** 至少一个选择 SHALL 真实通过（skip 不算通过）。

### Requirement: governance 的 Go 集成测试在写任何 fixture 之前核验一次性库身份。

#### Scenario: SC-DTI-007

- **GIVEN** governance 包的 TestMain 连上的库带有一次性身份（nonce、库名、角色名、库与角色标记、属主、无特权位）。
- **WHEN** 用错误或缺失的 `AIFI45_DISPOSABLE_NONCE` 重新执行该测试二进制。
- **THEN** 进程 SHALL 在 15 秒内以非零退出，输出含 `governance integration test disposable identity mismatch`，且 fixture workspace 的 `updated_at` SHALL 保持不变。
- **AND** 用正确 nonce 时 TestMain SHALL 照常继续，既有 governance 选择不受影响。

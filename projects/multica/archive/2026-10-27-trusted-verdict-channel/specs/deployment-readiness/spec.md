# Spec: deployment-readiness

> Change: 2026-10-27-trusted-verdict-channel | Auto-generated Human View

## Requirements

### Requirement: 部署就绪的可信 expected/observed 与全副本闭包，不以自报值或单副本代替。

#### Scenario: SC-DR-001

- **GIVEN** 存在受保护 trust manifest 中批准的 required profile，同时出现 agent 可写的安装根、环境变量自报、Git SHA 或仅 marker 一致的观测。
- **WHEN** 采集 deployment 快照并校验 expected 与 observed 的闭包。
- **THEN** SHALL 拒绝任何自报值作为观测，缺失/空/损坏/删必需项都不得产生可信 READY。
- **AND** 观测必须由受保护 supervisor/installer 绑定已登记实例与实际进程/安装根，并对 nonce/generation 签名。

#### Scenario: SC-DR-002

- **GIVEN** inventory 含多个仍有资格的实例，其中一个离线旧副本；以及滚动更新或多实例并存。
- **WHEN** 生成 `deployment_snapshot` 并递增 generation。
- **THEN** SHALL 覆盖全部仍有资格的实例与安装目标，按稳定 ID 分别比较，先撤销离线实例接单资格或核实其状态。
- **AND** 新副本/重启/配置或信任根变化先在 deployment 锁内递增 generation，使旧 verdict 失效。

### Requirement: readiness 结果持久化且类型受控，component 结果不得当作生产启用。

#### Scenario: SC-DR-003

- **GIVEN** worker 求值 `verify-channel` 得到 READY_COMPONENT，或 `strict-production` 缺 AdmissionDecider 得到 NOT_READY。
- **WHEN** 调用 `RecordReadinessTx` 持久化结果。
- **THEN** SHALL 只记录原字节 signed result 且 immutability 生效，READY_COMPONENT 不得用于生产 activation。
- **AND** profile/action/摘要入签名；`not-applicable` 只允许 profile 明确批准的项目。

### Requirement: 原子启用、停新准入与退役由持久 generation、CAS 与 append-only 事件约束。

#### Scenario: SC-DR-004

- **GIVEN** 两个并发启用、签后部署变代、response 丢失重试、nonce 重放、DB 失败。
- **WHEN** 调用 `ActivatePolicyTx` 与 `StopNewAdmissionsTx`。
- **THEN** SHALL 以同一 CAS/锁点原子推进 revision 与 event，STOP_NEW 固化已 issued 边界且不改历史或预算。
- **AND** activation event append-only；generation 不得删除归零。

#### Scenario: SC-DR-005

- **GIVEN** 旧 run 仍存活、存在未知未决任务、签发后新增 legacy 工作或恢复导致 work revision 漂移。
- **WHEN** 调用 `BeginLegacyDrainTx`/`FinalizeLegacyRetirementTx`。
- **THEN** SHALL 拒绝在未纳管 writer 或未知未决任务存在时出 drain 证明，并在 revision 漂移时拒绝 RETIRED。

### Requirement: strict 启动与换代共用 fence 和固定快照，不重签 ID、不盲重启。

#### Scenario: SC-DR-006

- **GIVEN** 原 issued 请求在 STOP_NEW 或过期后恢复；新候选或换 origin；preflight 与 backend.Execute 之间发生换代。
- **WHEN** 调用 `CheckDeploymentAccessTx` 与 `PrepareLaunch`/`CommitLaunch`。
- **THEN** SHALL 对原 issued 请求精确恢复原 command/receipt bytes，对新候选与换 origin 拒绝，换代时只能拒绝或加载原已批准固定快照。
- **AND** created 未 issued、新候选、换 origin 均不能恢复；不移除 cutoff/pin/generation 校验。

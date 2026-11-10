# Spec: attention-routing

> Change: 2026-10-22-aifi-45-authorized-execution | Auto-generated Human View

## Requirements

### Requirement: 主动通知只覆盖授权、需责任人处置的阻断和交付，普通进度可查询。

#### Scenario: SC-NTF-001

- **GIVEN** 正常节点完成、ACK、status/next变化或额度内有进展的常规修复。
- **WHEN** Runner记录进度。
- **THEN** SHALL 不创建机械主动通知，只保留可查询运行记录和必要证据引用。

#### Scenario: SC-NTF-002

- **GIVEN** 当前需要补授权、业务取舍、有界恢复后仍阻断，或已完成约定交付。
- **WHEN** 产生主动通知。
- **THEN** SHALL 通知必要接收者，包含结论、必要错误、canonical证据链接和明确所需动作，不复制整份JSON或报告。

### Requirement: 授权问题找有权者，维护故障有界恢复后找维护责任人。

#### Scenario: SC-NTF-003

- **GIVEN** 凭据、部署、环境或绑定故障且存在适用有界恢复路径。
- **WHEN** 恢复耗尽或无法安全恢复。
- **THEN** SHALL 带已试路径与具体维护动作通知维护者，不把命令搬运或技术排查交给业务方。

#### Scenario: SC-NTF-004

- **GIVEN** 额度耗尽或无进展阻断需要追加业务授权；维护者与授权者可能为同人也可能不同。
- **WHEN** 按根因分流。
- **THEN** SHALL 将授权决定交给有权者，维护权限不替代业务授权，通知明确剩余阻断和所需判断。

### Requirement: 复用现有执行和Inbox身份抑制重放，不吞重要变化，不新建全局去重账本。

#### Scenario: SC-NTF-005

- **GIVEN** 同一稳定原因、证据摘要和接收者的阻断被重复投递或换commit重放。
- **WHEN** 通知持久化事务并发执行和重启恢复。
- **THEN** SHALL 复用既有run/node引用与同一Inbox记录，不新增用户可见提醒，不新增全局账本。
- **AND** 键含workspace/project/CR和非空受众；不同CR不能因同原因互吞通知。
- **AND** 已delivered事件不重播；pending故障恢复可重投同Inbox ID，消费端幂等展示。

#### Scenario: SC-NTF-006

- **GIVEN** 旧阻断已通知后出现新失败、重要证据变化、接收者变化或交付完成。
- **WHEN** 新事件进入同一通知入口。
- **THEN** SHALL 正确生成新的必要通知，不因旧root cause或读侧issue聚合而吞掉变化。

#### Scenario: SC-NTF-007

- **GIVEN** 业务事实已提交，Inbox持久化或外部触达失败，随后重试。
- **WHEN** 沿原通知身份有界恢复。
- **THEN** SHALL 不回滚业务事实、不重签授权、不重复扣额或派writer；按既有记录pending/delivered恢复同一内部通知，不丢失提交后尚未广播的提醒。
- **AND** 不把内部唯一记录保证扩大为任意第三方触达exactly-once承诺。

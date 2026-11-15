# Spec: execution-authorization

> Change: 2026-11-08-aifi45-trust-anchor-chain | Auto-generated Human View

## Requirements

### Requirement: 控制写准入必须由外部信任链同时证明根归属、原始来源与验钥身份。

#### Scenario: SC-TAC-001

- **GIVEN** 认证控制面已从真实DB归属与structured-human-request/v1原bytes独立提取并签发当前workspace/project/cr授权，认证daemon已在独立身份保护的trust root安装匹配key_id的公钥、grant和来源，实际安装根与当前claim一致。
- **WHEN** daemon启动authorization-bind非只读或advance控制写并请求共用准入。
- **THEN** SHALL 在同一准入缝完成签名、原bytes来源digest与json-pointer绑定、当前scope/head及安装根dev/ino复核后，才允许既有业务事务继续。
- **AND** 平台签发前SHALL独立生成source_event_id、source_digest和source_bindings，不采信Agent自报摘录或映射。
- **AND** 环境变量、sidecar、endpoint和路径SHALL只用于定位，不得替代任何签名或归属事实。
- **AND** 签名payload与来源原bytes SHALL不做CRLF归一化或重序列化。

#### Scenario: SC-TAC-002

- **GIVEN** 两个真实project各自具有签名有效但归属不同的授权与execution-binding证明，其中一份证明或整套安装材料被复制到另一project或另一安装根。
- **WHEN** 对当前project请求authorization-bind非只读或advance首次业务写入。
- **THEN** SHALL 因workspace/project/cr、当前claim或实际安装根dev/ino不匹配而失败关闭，且不产生CR、Git、授权消费、平台任务或trust root变化。
- **AND** 即使使用同一平台签名key且签名数学验证通过，SHALL不得把其他project的证明当作当前根归属。

#### Scenario: SC-TAC-003

- **GIVEN** 调用方只有bindTaskWorkspace环境变量、可编辑sidecar、自报路径、路径pin、缺失或不可信公钥，或trustRoot位于/包含工作区安装根。
- **WHEN** 请求authorization-bind非只读或advance首次业务写入。
- **THEN** SHALL 拒绝准入且不产生任何业务副作用，不得回退到本层自写文件或仅有静态验签的兼容路径。
- **AND** installDirectory的路径检查SHALL只作为trustRoot缝，不得被报告为agent身份不可写的隔离证明。

#### Scenario: SC-TAC-004

- **GIVEN** 平台已按structured-human-request/v1原bytes签发授权并冻结source_event_id、source_digest及每个字段的json-pointer绑定，随后accepted_rules原bytes仅改一个字符而签名与grant保持不变。
- **WHEN** T侧重新提取来源并请求真实authorization-bind非只读或advance控制准入。
- **THEN** SHALL 因原bytes SHA-256、来源结构或json-pointer绑定与已签payload不一致而拒绝，且不产生CR、Git、授权消费或平台任务变化。
- **AND** 平台在签发前遇到来源结构、字段映射、认证actor或DB归属不一致时SHALL拒绝签发，而不是签出候选解释；真实M route/DB签发证据缺失时，SC-TAC-004只登记条款级且不得记整条通过，拟启用新合同SHALL失败关闭。

#### Scenario: SC-TAC-005

- **GIVEN** 每个拟启用平台均由认证daemon安装验签公钥，Linux使用不同daemon/agent UID，Windows使用不同daemon/agent身份，agent具有读取授权材料所需的最小权限。
- **WHEN** 以真实agent身份尝试覆盖、替换或追加已安装公钥并随后请求控制准入。
- **THEN** SHALL 由操作系统内核拒绝每次公钥写尝试，公钥digest保持不变，且任何未取得该身份级证据的平台不得启用新合同；外部证据缺席时SC-TAC-005只登记条款级，不得记整条通过。
- **AND** 同UID权限位、路径pin、硬链接发布、组件校验或只读路径检查SHALL不得被登记为ADJ-003隔离证据。

#### Scenario: SC-TAC-006

- **GIVEN** 授权签名有效但当前scope、policy/template/tools版本或head已变化、已撤销或无法由平台证明，另有普通只读命令与已提交事务重放。
- **WHEN** 分别请求authorization-bind非只读、advance、普通读取及已提交事务恢复。
- **THEN** SHALL 对不适用或无法证明当前性的首次写准入失败关闭且不产生业务副作用，普通读不增加trustRoot或daemon要求，已提交恢复只沿原journal/receipt完成而不重复消费。
- **AND** authorization-bind --check与--check --check-source SHALL保持bound=false，不得被当作准入成功。

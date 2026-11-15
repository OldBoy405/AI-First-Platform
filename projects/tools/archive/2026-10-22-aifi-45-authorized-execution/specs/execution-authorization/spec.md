# Spec: execution-authorization

> Change: 2026-10-22-aifi-45-authorized-execution | Auto-generated Human View

## Requirements

### Requirement: 充分的可信原请求直接绑定授权，不重复阶段人工确认。

#### Scenario: SC-AUTH-001

- **GIVEN** 新合同CR具有有权者原始请求及完整目标、正向范围、交付位置、验收、禁止项和已接受执行上限。
- **WHEN** 正常阶段请求绑定及消费授权。
- **THEN** SHALL 验签并在适用业务门禁通过后推进，不产生额外阶段人工确认。
- **AND** 系统消费记录明确basis=execution-authorization，不伪造人类阶段批准。
- **AND** 原始授权、消费receipt及当前subject可追溯。
- **AND** 来源按wire-contract.md冻结完整原bytes；重复JSON键拒绝，独立核对14语义字段与原始目标仓/控制根选择。
- **AND** 服务端从已认证scope核验资源UUID/身份版本并冻结到已签repository_bindings及coordinator_binding；不增加阶段批准。

#### Scenario: SC-AUTH-002

- **GIVEN** 原请求缺少决定性验收或交付边界，但环境中的仓库事实可查。
- **WHEN** 执行方判断授权充分性。
- **THEN** SHALL 自查事实并仅请求必要业务取舍，未授权部分无状态变化或执行任务。

### Requirement: 可信来源、scope和敏感动作边界不能由作者、转述或参数豁免。

#### Scenario: SC-AUTH-003

- **GIVEN** 请求来自task-token或cloud_pat、伪header/自报actor/comment ID、未知公钥、篡改payload或旧阶段grant。
- **WHEN** 尝试绑定execution授权。
- **THEN** SHALL 拒绝且不产生授权消费、状态推进或修复准入。

#### Scenario: SC-AUTH-004

- **GIVEN** 已绑定授权仅允许指定仓库、路径、交付目标和验收版本。
- **WHEN** 候选变更扩大范围、放宽验收、跨仓或通过相对路径及符号链接逃逸。
- **THEN** SHALL 阻断未授权部分并要求明确新授权，不能先改文档事后追认。
- **AND** graph仅定位；目标仓库逐项匹配原授权冻结的资源UUID/身份及当前平台绑定，不按可变label猜测。
- **AND** 控制根或目标资源删除、改绑、跨项目或graph换根不得扩大旧授权；复制旧账本不重置累计状态，迁移保留lineage/消耗/证据。

#### Scenario: SC-AUTH-005

- **GIVEN** 仅有普通实施授权，未明确生产发布、破坏性数据、权限扩大或对外承诺与支出。
- **WHEN** 逐项请求这些敏感动作。
- **THEN** SHALL 分别拒绝，即使作者声称低风险或维护者具有运维权限。

#### Scenario: SC-AUTH-006

- **GIVEN** 原始可信授权已明确某敏感动作的对象、环境及次数或额度。
- **WHEN** 对该动作提交匹配operation_id，随后重试同一操作。
- **THEN** SHALL 仅在明确边界内消费一次，不重复要求同一授权，也不允许换对象或扩大动作。
- **AND** 不同operation_id共享同lineage与动作对象环境的授权额度，换ID或续签不重获满额。
- **AND** 已授权动作的扩额必须显式签增量，操作幂等键与额度聚合键分开。

### Requirement: 授权和消费必须适用于当前scope、版本及租户，ACK不等于消费。

#### Scenario: SC-AUTH-007

- **GIVEN** grant已送达并ACK，但crctl消费事务尚未提交。
- **WHEN** 查询授权状态或尝试推进。
- **THEN** SHALL 保持未消费且不误推进，历史送达记录仍可查询。

#### Scenario: SC-AUTH-008

- **GIVEN** grant签名有效但复制到其他安装根/worktree，属于其他workspace/project/同名CR或不同policy/template/tools/scope版本，或旧challenge/revision/撤销及陈旧资源投影。
- **WHEN** 在当前权威workspace消费或重新绑定旧包。
- **THEN** SHALL 拒绝不适用复用且不回滚活动授权head，未启动任务遇撤销停止，累计消耗保留。
- **AND** 失联无法证明当前head时无新准入或敏感动作；已运行只允许有界安全收尾。
- **AND** 首版无时钟到期协议，不宣称即时回滚已发生不可逆副作用。
- **AND** 当前控制证明绑定本进程随机challenge、实际进程/根和真实任务；可编辑sidecar/env不构成身份。
- **AND** 平台仅向经现有daemon_token认证且与DB当前claim匹配的可信daemon控制子进程签发，不提供Agent任意nonce代签。

#### Scenario: SC-AUTH-009

- **GIVEN** 相同阶段授权消费已提交，响应或发布丢失，当前subject未变。
- **WHEN** 重放同一消费请求。
- **THEN** SHALL 返回同一已提交receipt且changed=false，不重复消费或生成伪审批。
- **AND** 同键不同subject或语义必须报冲突，不能覆盖旧记录。

### Requirement: 跨语言签名必须处理同一原始字节而不是各自重序列化。

#### Scenario: SC-AUTH-010

- **GIVEN** Go签出的授权包含中文、分隔符、换行及显式key_id，另有域/字节/key_id篡改样本。
- **WHEN** Node消费同一payload_b64并验签。
- **THEN** SHALL 接受合法原始字节，拒绝全部篡改、旧签名域及未知版本，不暴露私钥。
- **AND** key_id内外一致，字段类型、整数及路径均经边界校验。
- **AND** 普通文件证据哈希仍先CRLF规范化，不因签名传输修改已签payload字节。

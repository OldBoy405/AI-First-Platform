# Spec: agent-prompts

> Change: 2026-10-19-aifi-45-runner-contracts | Auto-generated Human View

## Requirements

### Requirement: 作者、reviewer、delivery仅执行当前节点，协调者不再承担正常跨阶段接力。

#### Scenario: SC-T-PROMPT-001

- **GIVEN** 五个现有Agent提示词及相关模板仍含mention reviewer、作者自行start或按next跨阶段继续的职责。
- **WHEN** 根据统一Runner责任模型修订提示词与既有合同断言。
- **THEN** SHALL 删除评论委派、审批转述和阶段自启，Agent只返回当前节点可归因业务结果或技术错误。
- **AND** 协调者保留入口、异常汇总和必要人类输入职责。
- **AND** crctl status/next保持事实查询，不变成模型跨节点派发授权。
- **AND** 不新增Agent、Skill、运行时检查或复制路由表。

#### Scenario: SC-T-PROMPT-002

- **GIVEN** 源提示词、README、active索引与matrix由同一tools版本维护。
- **WHEN** 修改职责/权限引用并准备与multica协同交付。
- **THEN** SHALL 通过既有lint/Agent合同/Skill矩阵测试，并使源文件与待部署instructions同源；checkout更新不能被报告为线上已生效。
- **AND** 只改必要索引关系，不扩展作者review权限绕过独立审查。
- **AND** 证据摘要留PR/Issue，STDD过程文档只写集中记录根。

### Requirement: 保留必要业务交互与最简失败回执，不转交有权限CLI给人复制。

#### Scenario: SC-T-PROMPT-003

- **GIVEN** 需求评审前待确认真实版本，或当前节点产生带registration key与recovery的失败。
- **WHEN** Agent请求必要人类业务输入或返回异常摘要。
- **THEN** SHALL 只请求必要业务确认并由已授权Agent执行现有CLI；失败回执包含CR-ID或registration key、错误与影响摘要。
- **AND** 原始输入、机器错误与recovery保留在现有run记录。
- **AND** key只是同键同输入幂等标识，不被当成全部恢复参数。
- **AND** 不让模型代签审批，不要求人类运行有权限的普通CLI动作。

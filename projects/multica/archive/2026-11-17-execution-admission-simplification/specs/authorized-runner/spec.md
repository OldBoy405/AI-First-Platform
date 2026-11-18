# Spec: authorized-runner

> Change: 2026-11-17-execution-admission-simplification | Auto-generated Human View

## Requirements

### Requirement: grant 送达并 ACK 后的唤醒与周期唤醒，只在 CR 当前授权头有效时才推进业务 gate 或派发；不再等待锚点任务的 consumption 回执与 effect。

#### Scenario: SC-RUN-101

- **GIVEN** grant 送达落盘并 ACK；CR 当前头为 approve，且没有任何锚点任务回执或 effect。
- **WHEN** ACK 回调及周期唤醒发生。
- **THEN** SHALL 依授权头放行并推进；同一 CR 无头或头被撤销时 SHALL 只唤醒核验、不完成业务 gate、不直接派发。
- **AND** ACK 回调与周期唤醒重复发生时不重复派发，不产生第二个任务。
- **AND** 新控制链仍须真实 daemon_token 与 DB 当前 claim；普通 PAT/JWT 兼容认证不自动获得新控制签发能力（SC-RUN-003 对应条款保持）。

### Requirement: 默认部署（不传任何契约启动参数）在存在审批签名服务时，使用内置默认契约即可签发人工执行授权；显式 manifest、半配置失败与无签名服务时功能关闭的既有行为不变。

#### Scenario: SC-RUN-102

- **GIVEN** 审批签名服务存在；未传 manifest 路径与 sha256；工作区 owner 已认证；CR 有可解析的 project。
- **WHEN** 提交授权请求，且省略 policy_version、policy_digest、template_digest 三个字段。
- **THEN** SHALL 返回 201 并设置该 CR 的授权头；签名 payload、冻结请求与部署契约三者的三个值一致， 随后读取该头为有效（不得出现 EXECUTION_AUTHORIZATION_HEAD_INVALID）。

#### Scenario: SC-RUN-103

- **GIVEN** 同 SC-RUN-102 的部署与 CR。
- **WHEN** 提交授权请求，三个字段显式给出且与部署契约逐一相等。
- **THEN** SHALL 返回 201 并设置授权头。

#### Scenario: SC-RUN-104

- **GIVEN** 同 SC-RUN-102 的部署与 CR。
- **WHEN** 提交授权请求，三个字段中任意一个给出了格式合法但与部署契约不同的值。
- **THEN** SHALL 返回 409 EXECUTION_CONTRACT_MISMATCH，不写入任何授权记录，不改变头。
- **AND** 字段显式给出空字符串按省略处理；多出未知字段仍被拒绝。
- **AND** 格式非法的值（非字符串、非小写 64 位 hex）在契约比较之前先按 EXECUTION_SOURCE_INVALID / EXECUTION_SCOPE_INVALID 拒绝，不被补齐为默认值。

#### Scenario: SC-RUN-105

- **GIVEN** 未配置审批签名密钥，也未传 manifest。
- **WHEN** 服务启动并收到授权请求。
- **THEN** SHALL 正常启动，授权端点返回 503 EXECUTION_AUTHORIZATION_DISABLED，不因默认契约而启动失败。
- **AND** 已传 manifest 但无签名密钥时仍拒绝启动（既有行为）。

#### Scenario: SC-RUN-106

- **GIVEN** 传了显式 manifest 与匹配的 sha256，且签名服务存在。
- **WHEN** 服务启动并签发授权。
- **THEN** SHALL 以 manifest 的契约为准，默认契约不生效；只传其中一个参数、路径非原生绝对路径、sha256 不匹配或字节超限时 SHALL 仍拒绝启动，不回退到默认契约。

### Requirement: 授权签发的入口边界不放宽：只有经认证的人类 owner/admin 可签发，project 范围只取自 CR 到同 workspace shell issue 的关系。

#### Scenario: SC-RUN-107

- **GIVEN** 默认部署，签名服务存在。
- **WHEN** 分别以 task token、cloud PAT、非 owner/admin 成员的身份提交授权请求；以及对一个 shell issue 缺失或无 project 的 CR 提交请求。
- **THEN** SHALL 对 task token 与 cloud PAT 返回 403 EXECUTION_HUMAN_SOURCE_REQUIRED；对非 owner/admin 返回 403 FORBIDDEN_AUTHORIZER； 对无法解析 project 的 CR 返回 409 EXECUTION_SCOPE_UNRESOLVED；以上均不写入授权记录。
- **AND** project 不取自请求体；请求体里的 workspace/project/CR 与可信范围不一致时仍为 400 EXECUTION_SCOPE_INVALID。

### Requirement: 默认契约签发的头能走通 daemon 的 strict 预验证链（binding、crctl 检查、节点预消费）；这是联调证据，不是对 daemon 的修改。

#### Scenario: SC-RUN-108

- **GIVEN** 一次性隔离环境；真实 server（默认契约，无 manifest 参数）、真实 daemon、可用的 crctl 与 node、不消耗模型的 stub 执行器；CR 的授权头经省略字段的请求签发。
- **WHEN** 运行 architecture 流水线直到首个节点任务被 daemon 认领并启动。
- **THEN** SHALL daemon 的 strict 路径对该节点完成 grant 安装、crctl 检查、binding 与平台 receipt，节点任务启动并完成； 任一环节因 policy_digest 或 template_digest 不一致被拒绝时 SHALL 判定本变更失败并停下复核设计，不得继续堆实现。
- **AND** 该场景不触碰现网数据库与现网 daemon；实例与容器由驱动自建并按 nonce 释放。

#### Scenario: SC-RUN-109

- **GIVEN** 与 DAYA-5 同形的 requirement run：源任务是从未消费的普通任务，CR 起初无头；授权头经真实授权路由（默认契约）签发。
- **WHEN** 发现路径运行：writer 任务入队，完成并投影后再次发现。
- **THEN** SHALL writer 任务带 cr_id 与 pipeline_node_run_id 入队，完成后 review-requirement 节点的任务被派发；全程不出现对源任务消耗回执的等待。
- **AND** 不接触现网数据；与 SC-RUN-108 合起来共同支撑提案成功标准第 8 条。

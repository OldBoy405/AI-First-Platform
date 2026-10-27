# Spec: four-phase-runner-dispatch

> Change: 2026-10-19-aifi-45-four-phase-runner | Auto-generated Human View

## Requirements

### Requirement: 四阶段共用声明驱动的节点执行，不以投影代替实际运行

#### Scenario: M-SC-DISPATCH-001

- **GIVEN** 四个既有 pipeline 模板和可用的已授权执行者，分别为每阶段建立隔离 CR 夹具
- **WHEN** 各阶段已有入口或合法交接触发 Reconcile 并完成一个可执行节点
- **THEN** SHALL 对四个阶段分别产生匹配 pipeline/nodeId/digest 的 claim、真实 task、canonical 结果与恢复归属，JSON nodeId 与 DB/Go 内部 node_id 对应
- **AND** SHALL 不把仅有投影 run 当作已执行，也不新增独立 Runner 或节点表

#### Scenario: M-SC-DISPATCH-002

- **GIVEN** task completed、CLI 退出 0 或模型自报 PASS，但当前节点所需权威账本/评审/审批证据缺失
- **WHEN** Runner 消费节点结果
- **THEN** SHALL 不推进节点，按原输入或证据错误合同保留可诊断结果
- **AND** SHALL 不在 Runner 复制 crctl 业务判据或补造证据

### Requirement: 公共执行切片尊重各模板的节点、输入与回修语义

#### Scenario: M-SC-DISPATCH-003

- **GIVEN** 四模板含不同节点数量、人工 gate、reviewLoop/replayNodes，交付模板无评审 loop
- **WHEN** parser 与 Runner 解释声明并遇到等待或业务 BLOCK
- **THEN** SHALL 按声明入队、等待、重入和重放，不以固定四/六节点 walker 限制其他阶段
- **AND** SHALL 保留三类人工审批，交付无声明 loop 时不造 loop，不恢复默认 dev-start 卡

#### Scenario: M-SC-DISPATCH-004

- **GIVEN** 同一 dirty 工作目录分别供允许 dirty-start 的节点、要求 clean 的节点及不同业务轮次使用
- **WHEN** 检查当前节点输入合同
- **THEN** SHALL 仅在该节点及轮次既有合同允许时接受 dirty-start，要求 clean 的节点仍阻断
- **AND** SHALL 不复制需求例外到所有阶段，不新增遗留 dirty 放行白名单

### Requirement: registry 导出、生成、claim carrier 四阶段一致且失败关闭

#### Scenario: M-SC-DISPATCH-005

- **GIVEN** tools 四阶段目标导出和原 generate-gate-nodes 生成链，变更完整 pipeline.inputs 的类型/required、绑定/授权或节点执行声明，并另造顶层 inputs 不一致负例
- **WHEN** 比较四 schema、导出 body/digest、生成产物和 parser 消费结果，区分基线现状与目标
- **THEN** SHALL 原生成链消费同一目标合同，保留 architecture-core-v1/requirement-core-v1，新增 code-core-v1/writeback-core-v1（均属 ai-first.pipeline-registry），未知或不完整合同失败关闭
- **AND** SHALL 将完整 pipeline.inputs、节点执行声明及 nodePermissions 绑定/授权/executor 纳入 digest body，任一变化改变 digest；固定 JSON 字段顺序并先规范 CRLF，运行时仍校验输入能力
- **AND** SHALL 顶层 inputs 仅为 pipeline.inputs 同源派生兼容 key 列表，不一致拒绝，不建第二输入/节点事实源或新生成器，存量 digest 不覆盖

#### Scenario: M-SC-DISPATCH-006

- **GIVEN** 四阶段任务的 source、workspace、pipeline、node-run、attempt、digest 和执行绑定已持久化
- **WHEN** handler claim、daemon carrier 与 canonical 回报往返
- **THEN** SHALL 无损保留节点执行与来源归属，拒绝 workspace/digest/node 不匹配的回报
- **AND** SHALL 不以 executor_agent_id 历史字段重新选择执行者

### Requirement: 验收基线必须实际执行，完整跨仓质量范围不缩水

#### Scenario: M-SC-DISPATCH-007

- **GIVEN** governance TestMain 可在 DB 不可达时退出 0，另有显式隔离且已迁移的测试库夹具
- **WHEN** 未来分别验证 DB 不可达负例和隔离库的实际 case 输出
- **THEN** SHALL 将无实际 case 的整包执行判作未验证，不以退出 0 空跑作为通过或 Gate 证据
- **AND** SHALL 仅使用显式隔离测试库并确认目标 case 真正运行，不回退默认共享数据库
- **AND** SHALL 在本 Phase2 不连接数据库或执行这些测试

#### Scenario: M-SC-DISPATCH-008

- **GIVEN** 主会话只读诊断Agent实测（用户已确认范围）：crctl整文件358.14s自然exit1，294 case=288 pass+6 fail/0 skip；短预算与输出延迟非挂死，5项payload fixture根错位及1项cmdTaskDone已知TxError被总catch改为INTERNAL_ERROR，仅tools修，非人类提供或批准6失败结论
- **WHEN** 未来按 test 基线→tools 合同→multica 消费→执行恢复→ack 去续接完成修复回归与联合验收
- **THEN** SHALL 将上述结果记为已诊断但整套未通过，6项修复仅归同次tools C7，保留完整发现范围、真实退出码/耗时/case/skipped
- **AND** SHALL 对5项fixture根错位及1项TxError保真分别先写失败回归再修复，不在multica掩盖tools缺陷
- **AND** SHALL 不通过排除文件、削弱断言或仅提高超时制造绿灯，不重启挂死假说、不半套启用
- **AND** SHALL 本回合只记录设计，不修改tools或multica业务源码

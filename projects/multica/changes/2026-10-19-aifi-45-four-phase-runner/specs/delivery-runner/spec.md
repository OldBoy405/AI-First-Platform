# Spec: delivery-runner

> Change: 2026-10-19-aifi-45-four-phase-runner | Auto-generated Human View

## Requirements

### Requirement: 代码批准授权既有交付链且输入来自 authority

#### Scenario: M-SC-DELIVERY-001

- **GIVEN** 当前代码审批匹配且 spec_id/target_version 可由 crctl authority 机器输出继承
- **WHEN** Runner 接管 feature-writeback
- **THEN** SHALL 自动执行既有 merge、PRD/SDD/TASK 回写、traceability 和归档，不另求启动/发布指令
- **AND** SHALL 授权不包含生产部署、安装包或商店发布，不新增交付执行器

#### Scenario: M-SC-DELIVERY-002

- **GIVEN** 新模式交付元数据分别完整、缺 spec 或缺真实版本，legacy milestone 不适用
- **WHEN** 模板/Skill 与 daemon 组装深原语输入
- **THEN** SHALL 仅继承 authority 的 spec_id/target_version，缺值阻断，不从标题猜、不生成占位、不强填 legacy milestone
- **AND** SHALL 不要求用户交付时重复填写，不新增查询命令

### Requirement: merge 业务回退和工作根切换按实际机器结果分流

#### Scenario: M-SC-DELIVERY-003

- **GIVEN** merge 退出 0 但机器结果 phase=release-drift 且 advanced 表明已回退，另有部分发布后漂移夹具
- **WHEN** Runner 消费结果
- **THEN** SHALL 前者停止交付并按 code-approved→developing 持久接回修复/测试/评审/代码重批，后者保留原阻断
- **AND** SHALL 不沿旧 code grant 继续、不技术重试 merge、不把退出 0 当合并成功

#### Scenario: M-SC-DELIVERY-004

- **GIVEN** merge 正常完成，后续节点的 operational workspace 与旧 task 工作根不同
- **WHEN** preparePipelineTask/inspectPipelineWorkspace 准备下一交付节点
- **THEN** SHALL 结束旧 task 后创建新 task，由 daemon 本机重新解析并绑定正确 operational workspace
- **AND** SHALL 不修改运行中 task env 跨根续跑，不由 server 猜绝对路径

### Requirement: 归档清理不破坏收尾，Runner 拥有最终完成权

#### Scenario: M-SC-DELIVERY-005

- **GIVEN** archive 将清理 txws，随后需要重入或 terminal settle
- **WHEN** daemon 启动归档及清理后的恢复
- **THEN** SHALL 从不会被清理的安装根启动并由 crctl 解析业务 authority，安装根承载现有审计/outbox/settle
- **AND** SHALL 重入不再要求已删除 txws 存在，也不绕过 authority

#### Scenario: M-SC-DELIVERY-006

- **GIVEN** archive 业务结果为 cleanup-pending，但 terminal settle 暂时失败
- **WHEN** Runner 和 daemon 分别消费归档业务事实及技术终态
- **THEN** SHALL cleanup-pending 按业务成功，不另派清理或重归档，settle 失败保留技术恢复且不伪报已收尾
- **AND** SHALL 最终执行完成仍等待所需 canonical 与任务/settle 结果汇合

#### Scenario: M-SC-DELIVERY-007

- **GIVEN** Runner 所有的交付 run 尚待最终节点结果，archived 或跨阶段投影事件先到，另有投影自有 run
- **WHEN** projectGateTransitionErr/completeRun 和 archived 投影处理事件
- **THEN** SHALL 只更新可归属的 CR 投影，不抢先关闭 Runner run；Runner 汇合最终事实后仅完成自己的执行
- **AND** SHALL 保留原投影自有 run 的合法更新，不跨阶段抢改 ownership

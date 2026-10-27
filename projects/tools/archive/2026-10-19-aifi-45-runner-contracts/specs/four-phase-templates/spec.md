# Spec: four-phase-templates

> Change: 2026-10-19-aifi-45-runner-contracts | Auto-generated Human View

## Requirements

### Requirement: 输入继承authority而非重复填写或猜测，业务结果不等于进程退出码。

#### Scenario: SC-T-TPL-001

- **GIVEN** 合法CR元数据含spec_id和真实target_version，或注册时版本为unassigned。
- **WHEN** 进入需求评审与后续coding/writeback节点。
- **THEN** SHALL 在需求评审前由负责人确认真实版本并由Agent用现有version-set更新，后续节点继承authority不重复询问或猜tbd。
- **AND** new模式不要求milestone_file，legacy遵循既有合同不猜填缺失元数据。
- **AND** 缺真实spec/版本失败关闭，不生成同义占位值。
- **AND** 不新增表单、查询命令、审批节点或CLI flag。

#### Scenario: SC-T-TPL-002

- **GIVEN** merge返回exit0且phase=release-drift与advanced业务回退对象，或testCr返回exit0且status=block。
- **WHEN** 节点结果被模板/平台carrier消费。
- **THEN** SHALL 按真实业务分支停止正向链，分别接回既有开发回修或测试回修，不能当merge成功或测试通过。
- **AND** release-drift不沿旧code grant继续，不作为技术retry merge。
- **AND** 测试必须真实执行testCr并使用commandDigest/attempt/reviewLoop等已有结果。
- **AND** code评审使用release-subjects而非设计单一subject_sha256。

#### Scenario: SC-T-TPL-003

- **GIVEN** merge成功返回operationalWorkspace，后续归档可能清理事务worktree。
- **WHEN** Runner接续writeback/archive任务并遇到cleanup-pending或重入。
- **THEN** SHALL 让merge结束后新task重新解析operational根，archive从不会被自身清理的安装根启动，cleanup-pending保持既有业务成功语义。
- **AND** 模板消费实际camelCase字段，不维护snake_case同义副本。
- **AND** 不修改运行中task环境跨目录执行，不由server猜本机路径。
- **AND** 清理后重入不要求已删除txws存在，不能绕过authority解析。

### Requirement: 上游回修与结构化恢复保留既有业务与权限边界。

#### Scenario: SC-T-TPL-004

- **GIVEN** 计划评审返回upstream-design-blocker及repair-target，或crctl返回结构化recovery。
- **WHEN** Runner根据当前节点合同与权威结果恢复。
- **THEN** SHALL 先进入tech-design-review-pending复评，再按既有结果必要修订重审审批；恢复只消费原授权内的安全幂等动作。
- **AND** 不直接退tech-designing，不沿旧PASS审批，不重置轮次。
- **AND** 保留recovery.executable/args/cwd/requiresTTY/promptFor和机器错误码。
- **AND** 人工驳回、认证/权限/签名/证据冲突不以文本猜测或技术retry兜底。

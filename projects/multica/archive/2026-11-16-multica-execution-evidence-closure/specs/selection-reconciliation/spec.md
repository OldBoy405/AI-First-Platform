# Spec: selection-reconciliation

> Change: 2026-11-16-multica-execution-evidence-closure | Auto-generated Human View

## Requirements

### Requirement: 接受已核实 Go 1.26.9 系列旧六字段流及 Go 1.27.1 的合法可选元数据，不放宽未知键、状态机或失败拒绝。

#### Scenario: SC-MEC-003

- **GIVEN** 既有 selection.test.mjs 合法 fixture，以及按官方八字段合同添加或退化元数据的表驱动样本
- **WHEN** 以真实 verifyGoTestSelection 及 decideSelection 对账，不手写旧 matched/blocked 返回形状
- **THEN** SHALL 原六字段合法流及合法 output 元数据流 matched；非法类型、值域、事件位置或未知键为 blocked/EVENT_INVALID；含合法 FailedBuild 的失败事件仍被拒绝，不能 matched
- **AND** OutputType 可省略；存在时为 output 事件的字符串，值仅为空串/frame/error/error-continue；它不替代最终测试结论
- **AND** FailedBuild 可省略；存在时仅允许 fail 事件的非空合法字符串；进程非零的既有 PROCESS_UNCONFIRMED 拒绝优先级不改
- **AND** 缺失/额外测试、重复键/事件、skip/fail、截断、signal、未知退出及错序继续拒绝；旧 expected 未配置时的 totals 规则及输出行不变
- **AND** 返回值不包含原始 Output、异常消息或秘密形态 fixture 内容；不新增版本协商、解析框架或静默 fallback

### Requirement: governance-run-lock 使用明确 expected 名单，所列测试缺一个也不能因其余通过及 exit0 而成功。

#### Scenario: SC-MEC-004

- **GIVEN** selections.json 的 governance-run-lock 声明四个完整测试名：TestWithRunLockSerialisesSameRun、TestWithRunLockCancelReleasesWaiter、TestReconcileRunIdentity、TestMTick003；package 为 github.com/multica-ai/multica/server/internal/governance、leaf 均为 true
- **WHEN** 在离线矩阵中对完整合法流与删除任一测试全部事件的流执行真实对账和 selection 决策
- **THEN** SHALL 完整流 matched 且 ok=true；每个缺测流即使 exit0、其余测试 pass 仍 blocked/SELECTION_MISMATCH 且 ok=false
- **AND** run 为这四个测试的完整锚定 alternation，expected 集合精确相等，不从观测流反向生成期望
- **AND** 保留原 governance-mtick003 入口及其它 selection 的无 expected 行为，不扩围迁移所有名单

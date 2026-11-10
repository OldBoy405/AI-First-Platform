# AIFI-45 通知与恢复收敛实施计划

> 执行参考，非任务账本、批准或 Gate 证据；正式状态仍以所属 STDD 流程为准。实施与测试只覆盖已批准方向，不通过记录代替验收。

**Goal:** 在原有范围内收紧未知效果恢复，并以已有持久事实、notice 唯一身份和既有恢复路径完成必要通知。

**Architecture:** M008 保持未知时停住，不接入未经证实的 `no_effect`。M009/NTF 只依据真实持久事实及可信接收者生成通知，复用 `cr_execution_notice` 和 Inbox 的事务与现有恢复；消费者复用 workspace+Inbox ID 幂等保护。事实或身份无法重建时停止，不猜测。

**Tech Stack:** tools Node.js；multica Go/PostgreSQL、TypeScript/Vitest；现有 STDD。

**Spec:** [M009 草案](m009-notice-identity-amendment-draft-20261109.md)、[M008 草案](wp4-sc-mg-015-016-paired-amendment-20261104.md)、`../canonical/specs/code/attention-routing.yaml` 与现有 `../test-plan.md`。草案未获 Gate 2 批准，不覆盖归档合同。

## 全局约束

- 不新增数据库表、列、索引或迁移，不建新调度器、全局事件平台、第二通知账及历史回填；不改 TC 分母。
- 保留原规格的写前故障后恢复要求；业务已提交后通知失败不能回滚业务。
- 不将 starter/member/owner、错误码、run ID 或调用方布尔值单独当作可信授权者、事实身份、证据或 `no_effect` 证明。
- 不访问事故库/HOLD、不读取或运行旧 `scripts/aifi45-db/run.mjs`，不运行 `stdd.cmd`；真实数据库测试须先证明新实例独占、无外网、不会自动下载且清理仅针对本轮资源。
- 不修改 Gate 或其投影，不代批、不提交、不推送、不部署；尊重各仓已有脏工作树与 CUSTOM 追溯规则。

## 四项验收保证

用户已采纳以下分工：沿用现有 TC，不另造更大的检查清单，也不因分组减少原合同或 Gate 要求。此确认不指定具体生产者或接收者，不代替合同审议、人工 Gate 或真实资源授权。

1. **恢复判定**：效果未知不重推；允许新尝试须有可信的无效果依据及旧执行者不会迟到的证明，已有结算和原映射不被改写。
2. **事实与路由**：三类通知只依据可追溯的真实事实和权限发送；同事实重放复用身份，重要变化不被吞掉。
3. **通知责任恢复**：业务提交后、写 notice 前及后续广播或标记前故障均可按原身份恢复，不重复业务副作用；消费端按原 Inbox ID 幂等。
4. **会话隐私**：退出不因清理失败阻断本机身份失效；同 profile 旧窗口可能写入或重启状态未知时不放行新会话，不强关窗口、不自动删除归属不明数据。远端凭证撤销未确认不得报告成功。

## Task 1：M008 恢复判定

**Files:** tools 仓的 `skills/shared/crctl/scripts/lib/merge-effects.mjs` 和 `skills/shared/crctl/scripts/test/merge-effects.test.mjs`。

- [x] 已核实现有调用方及仅由布尔值驱动的重试分支；定向测试覆盖未知与不可信 no_effect。
- [x] 本地仅在公共判定处安全停住，定向测试 21/21；未新建调用方或可信效果框架。此为 helper 局部结果，不证明生产恢复；配对合同仍待合法重审。

## Task 2：已有事实与通知身份

**Candidate files:** multica `server/internal/governance/execution_notice_wiring.go`、`execution_notice.go`、`runner.go`、`gate_projection.go`、`runner_code.go` 及对应现有测试。仅在核实真实事实来源和范围后决定实际改动，不为列表引入无关重构。

- [x] 已沿真实授权、阻断、交付路径核对已有事实；当前仍缺待授权请求与决策者、恢复耗尽与责任、可信交付验收与接收者，未猜测身份或把任务完成等同验收。
- 用户认可由真实授权请求生产者、实际恢复执行者、实际交付生产者分别提供事实、责任与证据；同一人可兼任，但每项权限须有独立依据。缺失时在现有业务记录保存可追溯快照，不新增表、列、索引或调度；此方向并未指定具体人员，也不是合同或实施批准。
- 只读核实：`HandleExecutionAuthorize` 保存的是已签发授权而非当前待决请求与决策者；`exhaustDelegatedFailureRecovery` 和 tools `recordAssessment` 有各自的真实停止记录，但均未证明 M009 环境故障及其维护责任；`deliveryFactsConverged` 检查 run/投影状态，未证明约定交付凭证及收件人。具体生产者、权限依据和记录位置仍需业务／系统责任方确认。
- `StartupScan` 当前只恢复已有 pending notice 并扫描 active run，不枚举 failed/completed 事实或无 notice 的事件；`detail.runner`、`execution_context` 的替换写入也不能保证单槽快照保留多事件。事实与责任须可靠随业务提交保存，并在通知写前故障后可逐事件重建；单槽、日志或现有 pending 扫描不能代替该证明。
- [ ] 以一个共享入口及现有恢复路径处理可证明的事实，复用 notice/Inbox 原子事务，不新增持久化架构；M009 唯一身份替代草案尚未批准，不覆盖原设计。
- [ ] 通过现有四组验收验证成功、失败、并发和边界；真实 DB 命令先通过隔离与资源归属核实。

## Task 3：消费者同 ID 幂等

**Files:** multica `packages/core/inbox/ws-updaters.ts` 及其现有测试。

- [ ] 对真实 `cr_execution_notice` 载荷复用原有 workspace+Inbox ID 保护，保持既有标记载荷及普通消息行为。
- [ ] 覆盖同 ID 重投、不同 ID 和兼容行为，不把展示幂等扩大为第三方投递保证。

## Task 4：评审与记录

- [ ] 分别核对合同草案、实际生产接线、CUSTOM 与测试来源；记录未能证明的缺口。
- [ ] 对批准前条款保持 draft；所有强制验证及人工批准未完成时不宣称切片/Gate 已完成。

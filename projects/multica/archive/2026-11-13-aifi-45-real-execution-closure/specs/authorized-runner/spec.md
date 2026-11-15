# Spec: authorized-runner

> Change: 2026-11-13-aifi-45-real-execution-closure | Auto-generated Human View

## Requirements

### Requirement: （MODIFIED，仅 SC-RUN-001）实际认证入口绑定充分授权。

#### Scenario: SC-RUN-001

- **GIVEN** 认证 owner/admin 原请求包含完整授权包，且新 policy 配套已就绪。
- **WHEN** 通过真实认证入口启动 requirement 或 architecture 类普通变更，并由真实 daemon 与真实 agent 执行其节点。
- **THEN** SHALL 绑定原授权并经 crctl 适用裁决自动推进，不要求重复阶段人类确认。
- **AND** 原 SC-RUN-001 的其余 AND 条款（原请求字节与资源选择冻结、实际数据库校验、初始已签 repository_bindings 与 coordinator_binding、同原请求返回原包）保持不变。
- **AND** 范围收敛：开发（code）与回写阶段在生产中没有 run 启动入口，不在本场景保证内。本 change 的真实运行证据只覆盖 architecture；requirement run 的真实运行仅在 Gate 2 另选时才产生，否则只有静态节点表与组件测试。

### Requirement: （MODIFIED，仅 SC-RUN-006 的「撤销后不推进」分支）

#### Scenario: SC-RUN-006

- **GIVEN** 已授权的 architecture run 在运行中被撤销授权，即 execution 授权头已前移为 reject。
- **WHEN** Runner 经下一次认领、节点完成或 ResumeActiveRuns 发现路径处理该 run，包括服务重启之后。
- **THEN** SHALL 不派发新的节点任务、不推进节点，等待原因可被查询为 admission（HEAD_REJECTED）；已有历史行（CR 更新、审批记录、任务、回执、effect）SHALL NOT 被删除或改写，run 不被伪造成 completed 或 failed。
- **AND** 原 SC-RUN-006 的其余分支（新修复拒绝、最后名额修复的测试与交付、已运行任务有界收尾、signed resume）不在本 change 保证内，保持原文，列后继登记。

### Requirement: （MODIFIED，仅 SC-RUN-007）唯一 Runner 的真实发现与重启恢复，范围收敛到有生产启动入口的 run 类型。

#### Scenario: SC-RUN-007

- **GIVEN** 新 policy 的普通已授权变更的 architecture run（或 requirement run）推进到节点交接处，服务在该处重启。
- **WHEN** 经真实认证入口、统一 Reconcile、periodic 发现和真实 TaskService 驱动。
- **THEN** SHALL 每个节点恰有一个任务（无重复、无遗漏），已推进的节点不回退，不依赖人工命令或直接调用 walker。
- **AND** 范围收敛：开发（code）与回写阶段在生产中无启动入口，ResumeActiveRuns 只扫描 requirement 与 architecture；原 SC-RUN-007 对这两个阶段的要求不在本 change 满足，不得宣称。

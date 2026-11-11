# Spec: authorized-runner

> Change: 2026-11-11-aifi-45-admission-task-binding | Auto-generated Human View

## Requirements

### Requirement: （MODIFIED，仅 SC-RUN-003）实际认证入口绑定充分授权，ACK 与已提交业务消费分离。

#### Scenario: SC-RUN-003

- **GIVEN** grant 送达落盘并 ACK，但该受保护动作的锚点 task 当前 generation 的平台 consumption 回执或它自己的 effect 尚未提交。
- **WHEN** ACK 回调及 periodic wake 发生。
- **THEN** SHALL 只唤醒核验，不完成业务 gate 或直接派旧 continuation；该锚点 task 的 effect 提交后才依实际状态推进。
- **AND** 锚点由 admission-task-binding 能力规定：派发、人工门及无 own-task 的完成为 run 的 source task，完成有 own-task 的节点为其当前任务；CR 内其他 task、其他 CR 或旧 generation 的消费事实不得放行。
- **AND** 其余既有 AND 条款（包括 consumption-effect 对「提交」的定义、daemon_token 与 DB claim、投影不等于 fresh 证明、verdict 写入的验签与逐项绑定）保持不变。

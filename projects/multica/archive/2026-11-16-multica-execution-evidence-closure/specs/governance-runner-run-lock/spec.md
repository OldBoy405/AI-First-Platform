# Spec: governance-runner-run-lock

> Change: 2026-11-16-multica-execution-evidence-closure | Auto-generated Human View

## Requirements

### Requirement: 三个恢复入口仅在锁后活动 run 的 ID 等于已取锁 ID 时推进；对象消失或切换时本次无效果返回。

#### Scenario: SC-MEC-001

- **GIVEN** 一次性迁移库；architecture/requirement/code 三个入口各有合法 A；独占 Runner 池上限 4；控制连接持 A 锁，恢复调用已完成锁前查询并进入取锁路径
- **WHEN** 分别保持 A 不变、使 A 终态且创建同归属合法 B、使 A 终态且无后继；changed 情形另持 B 锁再释放 A，随后另一次恢复并释放 B
- **THEN** SHALL unchanged 推进 A；changed 的第一次恢复返回且 B 的节点/任务/状态不变，第二次恢复等待 B 锁后推进 B 恰好一次；no-active 无效果返回
- **AND** 三种入口均走原生产恢复函数、原 digest/admission 与假 enqueuer；不加生产 hook，不以替身身份判定函数代替
- **AND** B created_at 使用明确顺序；architecture 至少三次、requirement/code 至少两次 Runner 独占池新增获取证明交错已达取锁边界，全部等待有 deadline
- **AND** 换目标不增加业务 attempt、不将 B 标为 failed；下一次既有唤醒负责恢复，不承诺同次立即推进
- **AND** 非 ErrNoRows 的查询错误与 digest 错误继续传播；writeback 和 requirement 创建锁不被扩大修改

### Requirement: 保持现有同 run 串行、释放、取消、等待不占连接，以及池 4 并发唤醒只派发一次的保证。

#### Scenario: SC-MEC-002

- **GIVEN** 同一次 governance-run-lock selection 包含两个原锁测试、TestReconcileRunIdentity 与 TestMTick003，带 race，governance TestMain 的池上限为 4
- **WHEN** 经既有 run-selection 执行与精确对账
- **THEN** SHALL 四个顶层测试完整通过，pass=4/fail=0/skip=0；同 run 回调最多一个并发进入、取消返回 ctx.Err、等待不占用持锁者需要的连接、释放后可再次进入
- **AND** TestMTick003 派发任务数和 run 任务数恰好为 1，首节点 attempt 为 1；不改既有断言
- **AND** 新身份测试内部用普通表循环，不产生名单外子测试事件；runner 本轮只执行这一个 selection，不重复运行原 governance-mtick003 入口

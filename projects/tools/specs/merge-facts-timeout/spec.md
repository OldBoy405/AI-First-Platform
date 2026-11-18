# Spec: merge-facts-timeout

> Change: 2026-11-18-merge-facts-timeout | Auto-generated Human View

## Requirements

### Requirement: 挂起请求具有可兑现的现有超时，不改变正常响应或已有传输分类。

#### Scenario: SC-MFT-001

- **GIVEN** merge-facts 等待一个不会完成的合法测试请求，等待超时是进程唯一待处理任务。
- **WHEN** 既有超时阈值到达。
- **THEN** 客户端 SHALL 返回 MERGE_FACTS_UNAVAILABLE 以及超时原因，而不是提前退出。

#### Scenario: SC-MFT-002

- **GIVEN** merge-facts 已收到正常响应或可分类的错误响应。
- **WHEN** 客户端处理结果。
- **THEN** 客户端 SHALL 按原有传输分类返回结果。

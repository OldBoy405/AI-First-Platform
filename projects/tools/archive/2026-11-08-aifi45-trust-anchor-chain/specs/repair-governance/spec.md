# Spec: repair-governance

> Change: 2026-11-08-aifi45-trust-anchor-chain | Auto-generated Human View

## Requirements

### Requirement: 修复与恢复先复用控制准入信任缝，再执行原有额度与停止裁决。

#### Scenario: SC-TAC-007

- **GIVEN** repair-admit或repair-resume具有与当前workspace/project/cr、实际安装根、原bytes来源、key_id和当前head匹配的认证daemon证明，且既有origin、独立评估、额度和停止条件满足；另有已提交repair-admit/repair-resume重放及提交边界崩溃恢复。
- **WHEN** daemon请求修复准入或停止恢复，并分别执行已提交重放与崩溃恢复。
- **THEN** SHALL 先通过同一控制准入信任缝，再按既有修复事务准入或恢复，不另建信任、额度或历史账。
- **AND** 成功恢复SHALL保留原origin、累计消耗、streak与stop历史，且不得跳过预算准入或重复消费；已提交重放与崩溃恢复SHALL沿原repair_id/receipt/journal恢复，重放返回原receipt且不重新消费，未提交写入按既有事实回滚。

#### Scenario: SC-TAC-008

- **GIVEN** repair-admit或repair-resume使用缺失/跨project/跨安装根复制的证明、改一字的来源、不可信公钥、错误scope、旧head或已撤销授权。
- **WHEN** 逐项对尚未提交的新业务写入请求修复准入或恢复。
- **THEN** SHALL 全部失败关闭，不产生修复receipt、额度消耗、任务派发、stop/progress_epoch变化或Git/write-set副作用。
- **AND** 无效恢复SHALL不得退化为模糊继续口令或仅本地验签，已有消耗、streak和stop历史保持不变。

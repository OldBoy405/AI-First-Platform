# Spec: repair-governance

> Change: 2026-10-22-aifi-45-authorized-execution | Auto-generated Human View

## Requirements

### Requirement: 以纠正性执行准入计次，默认CR累计最多6次，正常实施与技术重试不误计。

#### Scenario: SC-RPR-001

- **GIVEN** 当前由crctl裁决为首次正常实施，自测含多条失败，但尚未启动因阻断触发的纠正性执行。
- **WHEN** 正常实施及自测运行。
- **THEN** SHALL 不按测试条数、提交或命令扣修复额度，不能把未解决阻断的新run伪装首次实施。

#### Scenario: SC-RPR-002

- **GIVEN** 当前授权总额6，已有5个不同origin的已提交修复准入。
- **WHEN** 准入第6次修复并验证，之后请求第7次。
- **THEN** SHALL 允许第6次完成验证与PASS交付，拒绝第7次新修复且不派发任务。

#### Scenario: SC-RPR-003

- **GIVEN** 一次修复已准入，执行失败后发生同次有界命令或技术重试。
- **WHEN** 记录失败、重试及最终验证。
- **THEN** SHALL 已失败的修复仍消费1次，内部有界重试不另扣，不返还名额也不无限重试。

#### Scenario: SC-RPR-004

- **GIVEN** 修复消耗分布在多个阶段与cycle，当前额度已耗尽。
- **WHEN** 阶段切换、reset cycle或supersede后再次请求修复。
- **THEN** SHALL 继承累计历史并拒绝新准入，不因局部attempt归零获得新额度。

### Requirement: 同逻辑修复幂等、跨操作锁内裁决，失败与崩溃不产生重复消费。

#### Scenario: SC-RPR-005

- **GIVEN** 同一已接受阻断origin被并发投递、换ID重投或跨cycle恢复。
- **WHEN** 多次请求repair-admit。
- **THEN** SHALL 只提交一条消费记录并返回原repair_id/receipt，换ID不能制造第二次逻辑准入。
- **AND** 跨run采纳原结果必须有可信adoption映射与当前适用性重验；无映射旧证据不推进。
- **AND** 映射保留原根任务和origin，不新增消费或覆盖原任务归因。

#### Scenario: SC-RPR-006

- **GIVEN** 准入写入、commit、返回响应三个边界分别注入失败，另有授权更新和无关已暂存改动。
- **WHEN** 重启并恢复原操作，或同键提交不同origin/subject。
- **THEN** SHALL 按已提交事实恢复或回滚本次write-set，冲突明确停止，不夹带或覆盖无关改动。
- **AND** 提交前在同一CR锁复验CAS和授权；未提交receipt不能触发派发。
- **AND** 同键不同语义拒绝，不新增消费；提交结果未知不自行再开一次修复。

### Requirement: 额度追加必须明确授权且保留历史，不能由继续口令或篡改默认替代。

#### Scenario: SC-RPR-007

- **GIVEN** 已消费6次，有权者签发引用原授权的追加2次凭据。
- **WHEN** 绑定并重放追加授权。
- **THEN** SHALL 总额成为8、已消费仍6，追加仅生效一次，完整旧授权与消耗历史保留。
- **AND** 同一前驱head并发追加最多一份CAS成功，另一份须重新明确授权。
- **AND** 总额由初始额加唯一已接受增量推导，旧包重绑不恢复旧scope或重复加额。

#### Scenario: SC-RPR-008

- **GIVEN** 已耗尽或已停止，只有模糊继续、无签名增量、负数/溢出整数或改写本地默认规则。
- **WHEN** 请求扩额或解除停止。
- **THEN** SHALL 拒绝新增额度和修复派发，不清零累计历史。

### Requirement: 连续两次同根因无实质进展停止，只有适用独立证据才支持继续。

#### Scenario: SC-RPR-009

- **GIVEN** 剩余额度仍有，两次纠正性尝试后同根因持续阻断，独立评估均无验证改善或有效假设排除。
- **WHEN** 请求第三次该阻断修复。
- **THEN** SHALL 停止并升级，通知包含根因、已试路径、证据、剩余额度和所需动作，不只要求回复继续。

#### Scenario: SC-RPR-010

- **GIVEN** 同一blocker仍在，但独立评审核验了当前subject的测试结果实质改善，且额度未耗尽。
- **WHEN** 评估后续修复。
- **THEN** SHALL 允许授权内下一次准入，不能仅因blocker同名或数量未减判无进展。

#### Scenario: SC-RPR-011

- **GIVEN** 尚无测试改善，但诊断有效排除相关假设且独立评审指出新证据如何改变后续判断。
- **WHEN** 核验assessment及证据适用性。
- **THEN** SHALL 将该证据作为实质进展，不要求只用blocker数量下降证明。

#### Scenario: SC-RPR-012

- **GIVEN** 无效进展反例为作者自报、日志扩写、旧subject、同输入、根因改名或缺assessment；另有绑定stop version的明确恢复授权与独立新证据正例。
- **WHEN** 通过继续口令或repair-resume请求恢复，并重投同一请求。
- **THEN** SHALL 拒绝全部无效分支；仅对适用正例在CR锁内CAS解除精确stop并新建progress_epoch，同恢复只生效一次。
- **AND** 旧streak、stop与累计消耗完整保留，恢复不跳过预算准入。
- **AND** 停机只读取证有界，需要纠正性执行或副作用仍需恢复授权与额度，不能另开无限诊断。

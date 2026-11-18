# Spec: writeback-source-consistency

> Change: 2026-11-18-defensive-trim-tools | Auto-generated Human View

## Requirements

### Requirement: 候选正文与 beforeSha256 来自同次读取，只有文件不存在才记为 null，读取失败不等于不存在。beforeSha256 使用 UTF-8 解码后、换行归一化前的文本计算。

#### Scenario: SC-WSC-001

- **GIVEN** 已有目标的 CRLF 底稿为 A。
- **WHEN** 固定生成器首次读出 A 后，目标文件换成 B。
- **THEN** SHALL 按 A 生成候选正文，并用 A 的 SHA-256 填写 beforeSha256。

#### Scenario: SC-WSC-002

- **GIVEN** 目标分别缺失、已有空底稿、零字节任务索引或零字节规格索引。
- **WHEN** 运行对应的固定生成器。
- **THEN** SHALL 对缺失目标记 beforeSha256 为 null，已有空底稿和零字节任务索引使用空内容的 SHA-256。
- **AND** 零字节规格索引以 STRUCTURE_MISMATCH 拒绝。

#### Scenario: SC-WSC-003

- **GIVEN** 目标读取遇到非 ENOENT 错误。
- **WHEN** 生成候选或经应用预检与 CR 归档写集合共用的读取边界读取目标。
- **THEN** SHALL 上抛含目标路径和原因的读错误，不当作文件不存在或误报 before 冲突。

### Requirement: 应用端独立读取当前目标，不覆盖生成候选后改变的目标。

#### Scenario: SC-WSC-004

- **GIVEN** 以 A 生成候选并在建 journal 后、应用前中断，随后目标改成与 before 和 after 均不同的 B。
- **WHEN** writeback-apply 续办并应用候选。
- **THEN** SHALL 报告 TX_RECOVERY_CONFLICT 及路径、before、after、actual，B 字节不变，origin 不前进。

### Requirement: 新事务比较当前固定生成器 SHA，journal 续办只认冻结候选。 journal 续办不比较当前生成器 SHA。 SDD.md:476 的描述对新事务仍成立，不修订平台 SDD。

#### Scenario: SC-WSC-005

- **GIVEN** 事务中断已有 journal，之后仅升级固定生成脚本。
- **WHEN** 使用原参数续办 writeback-apply。
- **THEN** SHALL 以同一 txId 完成，只发布一次且发布原候选内容。

#### Scenario: SC-WSC-006

- **GIVEN** 中断事务的 manifest 字节改变且冻结摘要失配，但自摘要仍有效，或仅 blob 内容改变。
- **WHEN** 使用原参数续办 writeback-apply。
- **THEN** SHALL 分别以 TX_INPUT_CONFLICT 或 WRITEBACK_BLOB_HASH_MISMATCH 拒绝续办。
- **AND** 两种情况均无重生成、目标不变。

#### Scenario: SC-WSC-007

- **GIVEN** 事务没有 journal，候选声明的生成器 SHA 与当前固定脚本不符。
- **WHEN** writeback-apply 校验新事务的候选。
- **THEN** SHALL 以 WRITEBACK_GENERATOR_MISMATCH 拒绝且不建立 journal。

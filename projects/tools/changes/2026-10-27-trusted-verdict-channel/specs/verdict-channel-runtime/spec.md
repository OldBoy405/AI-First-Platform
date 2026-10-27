# Spec: verdict-channel-runtime

> Change: 2026-10-27-trusted-verdict-channel | Auto-generated Human View

## Requirements

### Requirement: T 侧协议只接受原字节与 exact keys，key-purpose 不得混用。

#### Scenario: SC-TR-001

- **GIVEN** 分别以正确三元组、错 purpose、错 domain、错 scope 与缺字段的 envelope 调用验签；另有 Go 侧产出的合法向量。
- **WHEN** 调用 `VerifyEnvelope` 并比较 digest。
- **THEN** SHALL 只接受三元组完全匹配的原字节，并与 Go 侧对同一字节得到相同 digest。

#### Scenario: SC-TR-002

- **GIVEN** trust manifest 含 attestation 与 human 两组 key；以及重复键、union 双分支、指向 agent 可写路径的条目。
- **WHEN** 加载 manifest 并验签。
- **THEN** SHALL 拒绝越用途签名、重复键与非法路径，只接受绝对路径+原始 SHA256 pin 的 exact keys。
- **AND** attestation key 不得签 human 动作；禁止 agent enrollment。

### Requirement: 受保护 store 只允许一次提交与不可篡改的冻结帧链。

#### Scenario: SC-TR-003

- **GIVEN** 同一 admit/assessment/resume 请求并发；rename 前后 kill；fsync 前注入 I/O 错误。
- **WHEN** 执行 `ApplyOnce(command,fn)` 并在恢复后重投。
- **THEN** SHALL 只产生一次业务变化并返回与首次相同的 bytes，fsync 失败不留 frame。
- **AND** 重投不得重算 `replayed`；提前发布 frame 视为失败。

#### Scenario: SC-TR-004

- **GIVEN** repair/action 记录出现断链、跳号、`previous_verdict_digest` 不指向前一帧，或占位签名（如 `signature=AA==`）。
- **WHEN** 校验冻结 envelope 链。
- **THEN** SHALL 拒绝入账，且不把该链当作追加授权的证明。

### Requirement: 固定 worker 与恢复只承认当前 fence 与一致 checkpoint。

#### Scenario: SC-TR-005

- **GIVEN** 旧 owner 持有旧 fence；以及新 owner 已取得递增 fence。
- **WHEN** 旧 worker 尝试接单或写操作。
- **THEN** SHALL 拒绝旧 fence 的新操作，只有持当前 fence 的 worker 可写。

#### Scenario: SC-TR-006

- **GIVEN** tail 相同、T 恰领先一项、journal prepared 且 bundle 完整、store/checkpoint 缺失或分叉。
- **WHEN** 执行 `ReconcileOwnerTx(checkpoint)`。
- **THEN** SHALL 按恢复表给出恢复原 request、导入原 bytes、重放原 command 或 freeze，且 freeze 时不建空 store、不清 slot。

#### Scenario: SC-TR-007

- **GIVEN** 普通 restart、key rotation，以及 checkpoint 字段缺失。
- **WHEN** 重启 worker 并继续服务。
- **THEN** SHALL 保持 epoch/sequence 并重发原 bytes，新 verdict 用新 key、历史仍用旧 key 验证。
- **AND** checkpoint 至少含 schema/key_id/scope/lineage/store/epoch/accepted_fence/last_seq/last_digest/after_state_digest/journal_state/open_request_id/open_command_digest/result_digest。

### Requirement: facts 与 repair/resume/sensitive 规则只消费已验签内容。

#### Scenario: SC-TR-008

- **GIVEN** repair-admit 请求携带未验签 payload 或解码后自带的额度。
- **WHEN** 规则函数处理准入。
- **THEN** SHALL 拒绝未验签 payload，且额度不来自解码内容。

#### Scenario: SC-TR-009

- **GIVEN** 同一追加请求被并发提交两份。
- **WHEN** 处理追加授权。
- **THEN** SHALL 让 CAS 只接受一份，另一份按原结果返回。

#### Scenario: SC-TR-010

- **GIVEN** `cr.md` 合同字段与受保护 store 不一致（被删、改空或改写）。
- **WHEN** 读取合同判定 strict/legacy。
- **THEN** SHALL 以 store 为准并拒绝该请求，字段缺失不得改判 legacy。

#### Scenario: SC-TR-011

- **GIVEN** 专项动作指向非精确 target/environment；复制安装/信任根后用新 operation；同 operation 原字节重放。
- **WHEN** 执行 sensitive action 规则。
- **THEN** SHALL 只允许 exact target/environment，新 operation 计为已耗尽，同 operation 重放返回原 receipt。

### Requirement: readiness 求值器拒绝宽松输入，只产出受控结果类型。

#### Scenario: SC-TR-012

- **GIVEN** 空/缺 components、重复 declared/observed、unknown 或 `not-applicable` 绕过、仅 marker 一致但 runtime/安装变化、恢复能力未知。
- **WHEN** 调用 `EvaluateDeploymentReadiness`。
- **THEN** SHALL 一律 NOT_READY，且合法非空 profile 为正例。
- **AND** `verify-channel` 只产出 `READY_COMPONENT`，不得调用生产 activation。
- **AND** request/verdict schema 为 exact-key，同 request 丢响应或重启只返回原 bytes。

### Requirement: P0 隔离证明（T 侧）：受限服务身份可签发，agent 身份不能取得 key、store、IPC 或服务环境。

#### Scenario: SC-TR-013

- **GIVEN** 同 UID 或同令牌 SID 的 profile；以及在真实不同受限身份下的 agent 尝试读 key、写 store、连 IPC、替换 Node/模块或注入 env/F1。
- **WHEN** 用 actual launcher 运行隔离探针。
- **THEN** SHALL 判同身份 profile 不合格，让 agent 侧全部攻击不能产生 accepted verdict，并以受限服务身份签发验证成功作正对照。
- **AND** Linux 与 Windows 各自出证据；只有「全部拒绝」的 mock 不算通过。

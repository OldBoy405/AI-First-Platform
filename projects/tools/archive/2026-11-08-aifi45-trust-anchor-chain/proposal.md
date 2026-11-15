# AIFI-45 控制准入信任锚链

<!-- source_hash: 7887be18555da6e3 -->
<!-- generated_at: 2026-11-08T19:19:58.144595 -->
<!-- canonical: canonical/proposals/2026-11-08-aifi45-trust-anchor-chain.yaml -->

## Why

验证者读到的安装根归属、授权来源与验签公钥事实在本层没有独立可信来源，三处证据最终都依赖本层自己写的文件或同 UID 能改的路径。

## What Changes

- 复用 execution-authorization 的 trustRoot、execution-binding 与 readExecutionSource，把受保护控制面认证并签发的 workspace/project/cr 与实际安装根绑定、structured-human-request/v1 原始来源及 key_id 组成同一条准入信任链；平台须在签发前独立提取并核对结构化来源，T 须从认证 daemon 安装且 agent 身份不可写的 trust root 读取与 key_id 匹配的公钥，环境变量、sidecar 与路径只用于定位。
- 将 authorization-bind 的非只读准入、advance、repair/resume、register、archive 这五个控制类写入口统一接到该缝，在共用准入点复核签名、来源 digest 与 json-pointer 绑定、当前 scope 和安装根 dev/ino；证明缺失、跨 project、从其他安装根复制证明或公钥不可信时失败关闭，普通读路径不变。
- 增加跨端篡改、替换、复制负例，并按目标部署平台取得 Linux agent UID 或 Windows 上与 daemon 不同的 agent 身份的真实内核拒绝证据，三条 ADJ 分别由 success_criteria 的对应场景关闭；测试不得将组件校验、路径 pin 或同 UID 权限位记作隔离证明。

### Modified Capabilities

- **execution-authorization**：以同一条外部可信链验证授权来源、安装根归属与验签公钥，并作为控制准入的唯一信任缝。
- **repair-governance**：repair/resume 复用同一控制准入信任缝，保留既有额度、历史与停止语义，不另建信任或预算机制。
- **evidence-delivery-contract**：register/archive 控制写复用同一安装根与授权证明，防止把交付记录写入未被证明归属的 project。

## Success Criteria

- [ ] ADJ-001：安装根归属事实是否由受保护控制面独立提供、获取路径不依赖被管进程可写文件，并且在替换成签名有效但属于另一 project 的证明时真实控制准入失败且不产生副作用？（预期：是）
- [ ] ADJ-002：平台是否在签发前独立核验 structured-human-request/v1、生成 source_event_id、按原 bytes 计算 source_digest 并提取每个字段的 json-pointer 来源绑定，T 侧是否从原 bytes 重新提取核对，且在 accepted_rules 改一个字符而签名不变时拒绝真实控制准入且不产生副作用？（预期：是）
- [ ] ADJ-003：在每个拟启用平台上，验签公钥是否位于 agent 身份无写权限的位置，且以 agent 身份尝试覆盖已安装公钥时被操作系统内核拒绝（Linux 以不同 UID 验证，Windows 以与 daemon 不同的身份验证）？（预期：是；任何拟启用平台未取得真实拒绝证据即不满足）

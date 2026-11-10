# CI intent snapshot RED（作者）

命令：`node --test --test-reporter=tap <multica>/scripts/aifi45-db/instance-intent-snapshot.test.mjs`；通过 context-mode 在内存捕获输出，仅提取计数和固定诊断，不保存原 stdout/stderr。环境只传系统必需的白名单变量；未使用 DB 或容器，未证明 OS 级网络隔离。

- exit 1：6 个测试、0 pass、6 fail、0 skip/cancelled。
- 共享 backing 测试中，校验后通过测试专用 TextDecoder 插桩替换 payload；旧实现确实返回了替换后的合法公开字段，因「shared backing 不应接受」断言失败。这是确定性时序模拟，不是实际并发攻击或生产资源误删证明。
- 伪造真实超限 view 的 own length 导致旧实现调用输入自身 `indexOf`，暴露非固定异常；prototype 冒充、非 byte view/proxy、resizable、非零 offset 的自有方法污染也未满足新防护断言。
- 仅以失败汇总定位，不包含实际 payload、expectedEnv、canary 或原始异常。

原始字节 SHA-256：

| 文件 | SHA-256 |
|---|---|
| `instance-intent-record.mjs` | `d69334f5a419f6725553cdacab1704f1dd947aec3eada63d5b65c6e0a0eaefbc` |
| `instance-intent-record.test.mjs` | `7f2e5f40580d6126e5e1b5104f9b0dd4ee76bfc1ecea8d31d4e2bd35e3eb4787` |
| `instance-intent-snapshot.test.mjs` | `4bb84e20d39359a5cece2f889472624dab1a6ab384b774d4a487c6d665433484` |
| `instance-ownership.mjs` | `5c4785ae4a03a951a00a72248528ba97b11163caf5675c8304e6a8c656e05288` |

`source-before/` 是未经换行归一化的独占快照。测试文件在追加后经原始字节重建并核对上述 SHA，连同前版源码和依赖存于 `source-red/`，可复现该 RED；不得将其当作 gate、已发生的真实竞态或当前实现的复跑结果。

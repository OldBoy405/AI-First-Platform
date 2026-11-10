# AIFI-45 受控事件收集器独立测试复跑

- Session ID：`01a18578-ba99-7020-aecc-d22fd3363878`
- 请求模型（会话环境 `PI_MODEL`）：`gpt-6.1-terra`；实际 backend：未知。
- Node：`v24.15.0`（Windows）
- 工作目录：`multica` 根目录
- 测试命令：`node --test --test-reporter=tap scripts/aifi45-db/supervisor-collector.test.mjs`
- 测试标准输出捕获于内存；exit `0`；tests `16`、pass `16`、fail `0`、skipped `0`。

## 原始文件 SHA-256

下列 SHA 为测试前和测试后对原始文件分别计算的值；三者前后均不变。

| 文件（相对于 `multica` 根目录） | 测试前 SHA-256 | 测试后 SHA-256 |
| --- | --- | --- |
| `scripts/aifi45-db/supervisor-collector.mjs` | `340403a916e68b4eef6be4f17831414de100220c4bd422a76d55fda0eca2ca7a` | `340403a916e68b4eef6be4f17831414de100220c4bd422a76d55fda0eca2ca7a` |
| `scripts/aifi45-db/supervisor-collector.test.mjs` | `5350526362ffd81069a291a2272e54532b77e7528b489b654c07a74b810f0e33` | `5350526362ffd81069a291a2272e54532b77e7528b489b654c07a74b810f0e33` |
| `scripts/aifi45-db/supervisor-protocol.mjs` | `bed82664f2f17918b47302a94255e3061cbce9f516f578a074a997671b75452c` | `bed82664f2f17918b47302a94255e3061cbce9f516f578a074a997671b75452c` |

## 证据边界

测试直接向收集器注入纯模拟事件，不验证真实目标子进程、进程树、操作系统退出状态、传输认证或清理权限。Node 测试运行器自身使用进程执行测试，不等于验证真实目标子进程。本次未运行 DB、容器或真实 CR，因此不对这些集成作通过声明。

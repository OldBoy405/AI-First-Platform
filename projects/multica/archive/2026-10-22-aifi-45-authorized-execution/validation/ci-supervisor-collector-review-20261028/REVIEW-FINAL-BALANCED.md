# AIFI-45 supervisor 最终快照独立复核

- Session ID：`01a1859e-2679-7020-aecc-d237c8a5bfb4`（`PI_SESSION_ID`）。
- 请求模型：未知；会话环境 `PI_MODEL=gpt-6.1-terra` 仅为环境标记，不证明实际请求模型。后端 receipt：未知。
- 环境：Windows、Git Bash，Node `v24.15.0`。
- 范围：下列五文件的最终快照；本次为独立复核，不解除现有 BLOCK，也不构成执行或清理授权。

## 基线执行及 SHA-256

在 `C:/Users/GOBAO/Downloads/AI/multica/scripts/aifi45-db`，仅对指定三个测试文件执行：

```text
node --test --test-reporter=tap supervisor-protocol.test.mjs supervisor-collector.test.mjs supervisor-erase.test.mjs
```

子进程 stdout 的原始 TAP 仅捕获在内存中，未输出原始内容；stderr 0 字节，退出码 0。精确 TAP 行断言确认 **tests 42、pass 42、fail 0、skipped 0**。基线辅助脚本的通用汇总提取正则存在转义错误，输出 `UNAVAILABLE`；上述四个数值是通过独立精确行断言复核，不是通用提取器的结果。suites、cancelled、todo 未由该脚本提取。执行时排除了 `NODE_OPTIONS` 和 `NODE_V8_COVERAGE` 环境影响。

下表为测试前后分别对原始字节计算的 SHA-256，均一致；之后变异实验结束也再次确认五个原文件未变。路径相对 `multica/scripts/aifi45-db`。

| 文件 | 测试前 raw SHA-256 | 测试后 raw SHA-256 |
| --- | --- | --- |
| `supervisor-protocol.mjs` | `8c83e4f1e6d4b0f248a58ee505d542b404e18cf5aee3c70f6a7dc3fb942caa30` | `8c83e4f1e6d4b0f248a58ee505d542b404e18cf5aee3c70f6a7dc3fb942caa30` |
| `supervisor-collector.mjs` | `340403a916e68b4eef6be4f17831414de100220c4bd422a76d55fda0eca2ca7a` | `340403a916e68b4eef6be4f17831414de100220c4bd422a76d55fda0eca2ca7a` |
| `supervisor-protocol.test.mjs` | `b7d4dd793cb6cf69d6cdd93c293cee3363d4c1d3deed44cda41af7c2b9c77705` | `b7d4dd793cb6cf69d6cdd93c293cee3363d4c1d3deed44cda41af7c2b9c77705` |
| `supervisor-collector.test.mjs` | `5350526362ffd81069a291a2272e54532b77e7528b489b654c07a74b810f0e33` | `5350526362ffd81069a291a2272e54532b77e7528b489b654c07a74b810f0e33` |
| `supervisor-erase.test.mjs` | `30c10cb3ce9bf571d49299ec721a0606929fadd5da36b7ed0104c4ab8b11eee3` | `30c10cb3ce9bf571d49299ec721a0606929fadd5da36b7ed0104c4ab8b11eee3` |

## 擦除断言和变异实测

基线擦除测试捕获私有分配，确认测试数据实际进入待擦除缓冲，并检查调用方输入未被修改及私有缓冲清零。decoder 覆盖成功、缺 terminal、截断和尾随数据；collector 覆盖成功、解码失败、abort、stdout/stderr 超限、无效输入、缺 EOF、EOF 后数据、重复 EOF、空块、错误事件参数个数和重入。

对独占临时目录内的副本分别注入变异，每次仅用同一 `supervisor-erase.test.mjs` 和 `node --test --test-reporter=tap` 重跑；stdout 保存在内存，未输出原始 TAP。每次均为 tests 2、pass 1、fail 1、skipped 0，退出码 1，且命中对应预期断言：

| 变异 | 实测 |
| --- | --- |
| P3：解码期运行时额外 `Buffer.from(view)` | 被禁止额外 `Buffer.from` 的断言检出。 |
| P3：导入时捕获并绑定 `Buffer.from`，解码期额外调用 | 被同一断言检出。 |
| C4：collector 的 `fail()` 仅在 `ABORTED` 时擦除 | 被私有缓冲清零断言检出；按测试顺序首先命中 `stdout-limit`。 |

临时目录使用随机独占创建；三个临时文件逐一删除，核实目录零项后移除目录。原始源码和测试未修改。

## 证据边界

- `Buffer.from` 监测断言的是受监控期间的调用，并非证明所有可能的分配或复制方式均被检测，也不单凭调用次数证明每次调用确实使用共享池。
- C4 变异在首个失败断言处停止；基线通过说明各列举模式均执行并断言清零，但该次变异不能单独证明每个后续模式的变异敏感性。decoder 测试也不是所有异常及解析分支的穷尽证明。
- 未运行真实目标进程、DB、容器或真实 CR；Node 测试运行器自身使用的进程不等同于真实目标进程。未验证真实流泵、来源认证、进程树、操作系统退出状态或清理权限；`reportedOutcome` 只是协议报告。

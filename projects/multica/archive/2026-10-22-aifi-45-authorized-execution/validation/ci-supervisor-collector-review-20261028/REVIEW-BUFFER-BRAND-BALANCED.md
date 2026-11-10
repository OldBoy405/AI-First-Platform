# AIFI-45 supervisor Uint8Array 检查：独立复核

- Session ID：`01a1859e-2679-7020-aecc-d237c8a5bfb4`（会话环境 `PI_SESSION_ID`）。请求模型未知；`PI_MODEL=gpt-6.1-terra` 是环境标记，不证明实际请求模型。后端 receipt 未知。
- 环境：Windows、Git Bash，Node `v24.15.0`。
- 性质：当前六文件快照的独立测试复跑和有限代码检查；不解除现有 BLOCK，不构成真实执行或清理授权。

## 当前快照：四文件测试

在 `C:/Users/GOBAO/Downloads/AI/multica/scripts/aifi45-db` 运行：

```text
node --test --test-reporter=tap supervisor-protocol.test.mjs supervisor-collector.test.mjs supervisor-erase.test.mjs supervisor-buffer-brand.test.mjs
```

结果：**45 个 top-level，pass 45，fail 0，skip 0**；TAP plan `1..45`，cancelled 0，todo 0，suites 0；退出码 0。stdout 原始 TAP（9309 字节）仅捕获在内存，stderr 0 字节；未保存或输出原始 TAP。测试子进程环境排除 `NODE_OPTIONS` 和 `NODE_V8_COVERAGE`。本次不需要临时目录，未创建临时目录。

以下是运行前后分别对原始文件字节计算的 SHA-256；六文件前后均一致。路径相对 `multica/scripts/aifi45-db`。

| 文件 | 测试前 raw SHA-256 | 测试后 raw SHA-256 |
| --- | --- | --- |
| `supervisor-protocol.mjs` | `92329bb48d9eed2b97eabd26b1b883dfb2b1684278ce91f593ecf3d95e3ea5c8` | `92329bb48d9eed2b97eabd26b1b883dfb2b1684278ce91f593ecf3d95e3ea5c8` |
| `supervisor-collector.mjs` | `a880d23c1ea0c05d1554dd2d4ff83fce6cbebff7e9355f8d33796288e87e1b28` | `a880d23c1ea0c05d1554dd2d4ff83fce6cbebff7e9355f8d33796288e87e1b28` |
| `supervisor-protocol.test.mjs` | `b7d4dd793cb6cf69d6cdd93c293cee3363d4c1d3deed44cda41af7c2b9c77705` | `b7d4dd793cb6cf69d6cdd93c293cee3363d4c1d3deed44cda41af7c2b9c77705` |
| `supervisor-collector.test.mjs` | `b82fc48bfabb50c50ab934d1151470eef11978de01c2e5cf0d96c57c27f79924` | `b82fc48bfabb50c50ab934d1151470eef11978de01c2e5cf0d96c57c27f79924` |
| `supervisor-erase.test.mjs` | `30c10cb3ce9bf571d49299ec721a0606929fadd5da36b7ed0104c4ab8b11eee3` | `30c10cb3ce9bf571d49299ec721a0606929fadd5da36b7ed0104c4ab8b11eee3` |
| `supervisor-buffer-brand.test.mjs` | `abaa1f9ffe6cce3dab655054ba21763d642e722999402e186a54cc75caf55448` | `abaa1f9ffe6cce3dab655054ba21763d642e722999402e186a54cc75caf55448` |

## 旧快照与新快照分开

同目录 `REVIEW-FINAL-BALANCED.md` 独立归档旧快照五文件前后哈希和旧 **42/42** 结果；复核其 raw SHA-256 为 `2b7259cd3381e19d4b0709202c2d2d196c247822659b56bb43652736732a805a`，与当时写入后的值一致。本文件单独归档新快照的 **45/45**；旧 42/42 和旧变异结果不作为新快照的实测结果。

旧归档中的 protocol SHA 为 `8c83e4f1e6d4b0f248a58ee505d542b404e18cf5aee3c70f6a7dc3fb942caa30`、collector 为 `340403a916e68b4eef6be4f17831414de100220c4bd422a76d55fda0eca2ca7a`、collector test 为 `5350526362ffd81069a291a2272e54532b77e7528b489b654c07a74b810f0e33`，均与上表当前值不同。旧报告还记录了旧版 protocol test 与增强 erase test 的完整哈希。

`source-erasure-review/` 中旧 protocol、collector、protocol test、collector test 的原始文件哈希与旧报告相应值一致；其中 erase test 为更早的 `faa42abf0135a9ef7fd8098416b418b6a779d07da509c5dc7dec4a623c48718f`，并非旧报告所测增强版 `30c10cb3ce9bf571d49299ec721a0606929fadd5da36b7ed0104c4ab8b11eee3`。因此这里验证的是旧增强版哈希的报告归档，不声称该目录保全了旧报告对应的全部五个文件副本。

## 输入检查及证据边界

protocol 和 collector 均要求 `Buffer.isBuffer(input)` 且 `types.isUint8Array(input)`。新测试实际覆盖：伪装为 Buffer 的 `Uint16Array` 在 decoder 及 collector 两通道被拒绝；修改原型的 `Uint8Array` 仍可通过两项检查并被 decoder 接受。**这两项检查不证明 Buffer 来源真实性，不认证输入来源或与真实进程的绑定。** 测试结果仅证明所测情形，不证明所有输入、同进程内建篡改或全部异常路径安全。

本次未运行真实目标进程、DB、容器或真实 CR；Node 测试运行器自身使用的进程不等于真实目标进程。未验证真实传输、来源认证、进程树、OS 退出或清理权限。未修改源码或测试。

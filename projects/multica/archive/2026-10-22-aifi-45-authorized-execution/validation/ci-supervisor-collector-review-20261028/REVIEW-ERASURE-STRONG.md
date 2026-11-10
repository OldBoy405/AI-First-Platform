# AIFI-45 decoder 擦除修复：STDD strong 独立复审（仅限指定快照）

- 性质：只读独立复审归档。未修改 multica 源码或测试；未运行 DB、容器、真实引擎或真实 CR；未接 CI。
- **不解除、不升级现有 BLOCK；不构成任何进程、进程树、退出状态或清理能力的证明或授权。**
- Session ID：`01a18578-ba89-7020-aecc-d22c79a783ca`；请求模型（会话环境 `PI_MODEL`）：`claude-opus-5-5`，`PI_REASONING_LEVEL=high`；实际 backend 未知。
- 环境：Node `v24.15.0`（Windows，Git Bash）。
- 前序：同目录 `REVIEW-STRONG-INITIAL.md`（旧快照 protocol `bed82664…` 上的 M1 池泄漏与 M2 擦除漏测）。

## 0. 复审快照（原始 SHA-256，`sha256sum` 计算，未归一化）

| 文件（相对 `C:/Users/GOBAO/Downloads/AI/multica`） | 复审时 SHA-256 |
|---|---|
| `scripts/aifi45-db/supervisor-protocol.mjs` | `8c83e4f1e6d4b0f248a58ee505d542b404e18cf5aee3c70f6a7dc3fb942caa30` |
| `scripts/aifi45-db/supervisor-protocol.test.mjs` | `b7d4dd793cb6cf69d6cdd93c293cee3363d4c1d3deed44cda41af7c2b9c77705` |
| `scripts/aifi45-db/supervisor-erase.test.mjs` | `faa42abf0135a9ef7fd8098416b418b6a779d07da509c5dc7dec4a623c48718f` |
| `scripts/aifi45-db/supervisor-collector.mjs`（保持旧版） | `340403a916e68b4eef6be4f17831414de100220c4bd422a76d55fda0eca2ca7a` |
| `scripts/aifi45-db/supervisor-collector.test.mjs`（保持旧版） | `5350526362ffd81069a291a2272e54532b77e7528b489b654c07a74b810f0e33` |

实验结束后复核上述 5 个 SHA 均未变。

**范围限定：** 本报告只覆盖上表快照，尤其是 erase test `faa42abf…` 与 protocol `8c83e4f1…`。归档时（写入本文件前）磁盘上的 `supervisor-erase.test.mjs` 已变为 `30c10cb3ce9bf571d49299ec721a0606929fadd5da36b7ed0104c4ab8b11eee3`；**该后续版本未被阅读、审查或运行**，本报告不构成对它的复核，下文 M2 漏测结论只描述 `faa42abf…` 当时的事实。同目录 `AUTHOR-ERASURE.md`、`AUTHOR-ERASURE-RECHECK.md`、`source-erasure-review/` 未被阅读或依赖。

## 1. 执行方式

- 测试：`node --test supervisor-protocol.test.mjs supervisor-erase.test.mjs supervisor-collector.test.mjs` → tests 42、pass 42、fail 0；`node --throw-deprecation --test supervisor-erase.test.mjs` → pass 2、fail 0，无弃用警告。
- 实验目录：`mktemp -d` 生成的唯一目录 `/tmp/tmp.CW9DdaDDfM`，结束后已删除（`test ! -e` 确认）；未使用固定 `/tmp` 文件。
- canary 只用 `Buffer.alloc` 逐字节写入非池化内存；脚本只打印布尔值和计数，**从未打印 canary**。
- 原始模块以 `file:///` 绝对 URL 只读导入；变异只在临时目录的副本上进行。
- 标注约定：[实测] 指本次已运行；[静态] 指读码推断、未运行。

## 2. 结论摘要

- **M1（池泄漏）在本快照上已解决**：成功、四种解析失败、共享内存拒绝三类路径都不再把明文留在 Buffer 池里，调用方输入也不被修改。
- **M2（擦除漏测）只解决了一部分**：删掉 decoder 或 collector 的清零会被测试抓到，但"多出一份池化副本"（P3，即 M1 复发）和"collector 只在 abort 时清零"（C4）在 `faa42abf…` 下仍能存活。
- **新增 Medium**：collector 如果在被丢弃前没有调 `result()` 或 `abort()` 收尾，内部 64 KiB 缓冲区的明文不会被清零，释放后的内存可被后续分配读到（实测）。

## 3. M1 复核：清零覆盖

- **非池化分配**
  - [静态] `allocatePrivate = Buffer.allocUnsafeSlow.bind(Buffer)` 在导入时绑定；先判 TOTAL_LIMIT 再分配，超限输入不会被复制。
  - [实测] 直接调 decoder，以及经 collector 走 ok / MISSING_TERMINAL / TRUNCATED / TRAILING_DATA，在 `Buffer.from(Buffer.allocUnsafe(1).buffer)` 中都查不到 canary（全部 false）。
  - [实测] 灵敏度对照：P3 变异体用同一套探测，8 个探测点全部命中，说明探测本身有效。
- **finally 清零**
  - [静态] 成功、所有 reject、内层 try 中的异常都会经过 `finally { clearBytes.call(bytes, 0) }`，而且清零发生在返回值交出之前。
  - [静态] 分配之前就失败的路径（非 Buffer、共享内存、detached、超限）没有私有副本。
  - [实测] 在栈临界点跑 3 轮、每轮约 4000 次：留下的非零私有副本为 0，含 canary 的副本为 0。
  - [未覆盖] 内层 try 的异常路径在正常条件下基本走不到，没有测试覆盖，只能靠 finally 的语义保证。
- **调用方输入不被修改** [实测]：decoder 的 ok / missing / truncated / trailing / 共享内存拒绝；collector 的 ok、四种解析失败、STDOUT_LIMIT、DATA_AFTER_EOF、abort，调用方 Buffer 都保持原样。
- **collector 缓冲区** [实测]：成功以及 STDOUT_LIMIT、DATA_AFTER_EOF、DUPLICATE_EOF、EMPTY_CHUNK、STDERR_LIMIT、INVALID_INPUT、INVALID_EVENT、REENTRANT、MISSING_*_EOF、ABORTED 之后，内部 64 KiB 缓冲区都不再含 canary。

## 4. M2 复核：变异测试（全部实测，基于 erase test `faa42abf…`）

| 变异 | 结果 |
|---|---|
| P1 删除 decoder 的 finally 清零 | 被杀（erase） |
| P2 只在成功路径清零 | 被杀（erase） |
| P4 改用池化分配器 `allocUnsafe` | 被杀（erase、protocol） |
| P6 只清一部分 | 被杀（erase） |
| P7 清零时把输入视图也清掉 | 被杀（erase、protocol） |
| C1 删除 collector 在 `result()` 中的清零 | 被杀（erase） |
| C2 删除 collector 在 `fail()` 中的清零 | 被杀（erase） |
| C3 删除 collector 全部清零 | 被杀（erase） |
| C5 collector 改用池化分配 | 被杀（erase） |
| **P3 另做一份 `Buffer.from(view)` 池化副本用于解析（M1 复发）** | **存活**（三个测试文件全部通过） |
| **P5 退回 `Buffer.from(view)`，另加一次空的私有分配** | **存活** |
| **C4 collector 只在 ABORTED 时清零** | **存活** |

存活原因（`faa42abf…` 当时的事实）：

- **P3 / P5**：decoder 擦除测试只检查"分配了一次私有内存"和"这块内存全是 0"，没有检查 canary 确实被复制进了这块私有内存，也没有直接扫描 Buffer 池。分配次数只是间接指标，用一次空分配就能骗过。P5 本身的 finally 会清掉那份池化副本，算不上真泄漏，但同样暴露了这一点；P3 经实测确实会在池中留下 canary。
- **C4**：collector 擦除测试只覆盖成功、解析失败和 abort；`fail()` 的其他调用路径没有断言。真实代码在这些路径上确实清零了（§3），但退化不会被测试发现。

## 5. 剩余风险

- **Medium（实测）：collector 被丢弃前没有收尾，导致内存残留。** 50 个 collector 喂入 canary 后，不调 `result()` 或 `abort()` 就丢弃；`--expose-gc` 回收后，200 次 `allocUnsafeSlow(65536)` 中有 2 次命中 canary。对照组（丢弃前先 `abort()`）为 0 次。结果依赖 GC 和分配器，不一定能稳定复现。接入方必须保证每条路径都以 `result()` 或 `abort()` 收尾；本切片没有提供兜底。
- **Low（实测）：same-realm 篡改仍然有效。** 预先 patch `Buffer.prototype.readUInt32BE`，可以在清零前拿到含 canary 的私有副本。[静态] 在导入之前替换 `Buffer.allocUnsafeSlow` 也能截获——测试自己就是这么做的；`Buffer.isBuffer`、`util.types` 同样没有固定。按设计复核，恶意同权限代码不在防护范围内。
- **Low（实测）：栈限制。** 栈临界时 decoder 每轮向外抛出 4 次，违反"从不抛出"的契约；都发生在私有分配之前，没有留下残留。collector 的同类问题见初审 L2。
- **范围外（静态，未验证）**：
  - 客户端或调用方自己的输入块（例如真实 Node 管道/流的读缓冲）不由本切片清零。
  - collector 在累积期间按设计持有明文。
  - 真实管道的排空、超时、来源认证，与 OS 退出状态或进程树的绑定都没有建立。
  - 测试 fixture 用 `Buffer.from` 造的 canary 本身就在池里，只影响测试。

## 6. 建议（未实现）

- decoder 擦除测试加一个非空性检查：例如截获 `setBytes` 或 `readUInt*` 的接收者，确认 canary 确实复制进了私有内存；再直接扫描 Buffer 池，断言里面没有 canary。
- collector 对每一条 `fail()` 路径都断言内部缓冲区已清零。
- 在集成契约中写明：丢弃 collector 之前必须调用 `abort()` 或 `result()`。

## 7. BLOCK

现有 BLOCK 全部保持。本复审只覆盖受控事件 decoder/collector 的内存擦除切片，不涉及事件来源、真实管道、进程树、退出状态、持久日志或清理授权；不得据此创建或清理容器，不得运行 DB、容器或真实 CR。

*本文件为新建文档；未覆盖同目录任何既有材料。*

# AIFI-45 Buffer 输入品牌校验：STDD strong 独立复审（仅限指定快照）

- 性质：只读独立复审归档。未修改 multica 源码或测试；未运行 DB、容器、真实引擎或真实 CR；未接 CI。
- **不解除、不升级现有 BLOCK；不构成任何进程、进程树、退出状态或清理能力的证明或授权。**
- Session ID：`01a18578-ba89-7020-aecc-d22c79a783ca`；请求模型（会话环境 `PI_MODEL`）：`claude-opus-5-5`，`PI_REASONING_LEVEL=high`。
- **后端 receipt：未知。** 本次没有可核验的后端回执，实际服务模型无法确认；上面两项只是会话环境变量的记录。
- 环境：Node `v24.15.0`（Windows，Git Bash）。
- 证据来源：本次重新阅读源码、与旧快照做 diff，并重新运行全部实验。前序报告（`REVIEW-STRONG-INITIAL.md`、`REVIEW-ERASURE-STRONG.md`）没有当作本快照的证据。同目录 `AUTHOR-BUFFER-BRAND.md`、`REVIEW-BUFFER-BRAND-BALANCED.md` 未被阅读或依赖。

## 0. 复审快照（原始 SHA-256，`sha256sum` 计算，未归一化）

| 文件（相对 `C:/Users/GOBAO/Downloads/AI/multica`） | SHA-256 | 角色 |
|---|---|---|
| `scripts/aifi45-db/supervisor-protocol.mjs` | `92329bb48d9eed2b97eabd26b1b883dfb2b1684278ce91f593ecf3d95e3ea5c8` | 审查对象 |
| `scripts/aifi45-db/supervisor-collector.mjs` | `a880d23c1ea0c05d1554dd2d4ff83fce6cbebff7e9355f8d33796288e87e1b28` | 审查对象 |
| `scripts/aifi45-db/supervisor-buffer-brand.test.mjs` | `abaa1f9ffe6cce3dab655054ba21763d642e722999402e186a54cc75caf55448` | 审查对象 |
| `scripts/aifi45-db/supervisor-collector.test.mjs` | `b82fc48bfabb50c50ab934d1151470eef11978de01c2e5cf0d96c57c27f79924` | 参与运行；相对旧快照只改了测试名 |
| `scripts/aifi45-db/supervisor-erase.test.mjs` | `30c10cb3ce9bf571d49299ec721a0606929fadd5da36b7ed0104c4ab8b11eee3` | 参与运行与变异，仅作补充观察，未做完整审查 |
| `scripts/aifi45-db/supervisor-protocol.test.mjs` | `b7d4dd793cb6cf69d6cdd93c293cee3363d4c1d3deed44cda41af7c2b9c77705` | 参与运行 |

实验前、实验后以及写入本文件前，三次复核上述 6 个 SHA，均未变化。

**与旧快照的差异**（对照 `source-erasure-review/` 中的 protocol `8c83e4f1…` 与 collector `340403a9…`）：两个源文件各只改了一行。

- protocol：`if (!Buffer.isBuffer(input) || !types.isUint8Array(input)) return reject('INVALID_INPUT');`
- collector：`if (!Buffer.isBuffer(input) || !types.isUint8Array(input) || failure) return fail('INVALID_INPUT');`

## 1. 执行方式

- 实验目录：`mktemp -d` 生成的独占目录 `/tmp/tmp.PTnrLDQDep`，结束后已删除，并用 `test ! -e` 确认不存在；未使用固定 `/tmp` 文件。
- canary 只用 `Buffer.alloc` 逐字节写入非池化内存；脚本只打印布尔值和计数，**从未打印 canary**。
- 原始模块以 `file:///` 绝对 URL 只读导入；变异只在临时目录的副本上进行。
- 标注约定：[实测] 指本次已运行；[静态] 指读码推断、本次未运行。

## 2. 结论摘要

- `types.isUint8Array` 达到了目的：所有用 Buffer 原型伪装的非字节类型数组都会被拒绝。
- 在本次实测覆盖的路径上，没有观察到新的重入入口，也没有观察到 shared/detached、拦截、上限或敏感信息方面的回归。**这不等于已经证明所有情况都没有回归**；尤其是同 realm 篡改、栈临界、真实管道等没有覆盖（见 §6）。
- 用 Buffer 原型伪装的**真实 Uint8Array 仍然被接受**。这只说明输入是字节视图，**不认证它的来源**；brand test 本身也写明了这一点。

## 3. 测试（实测）

`node --test supervisor-protocol.test.mjs supervisor-collector.test.mjs supervisor-erase.test.mjs supervisor-buffer-brand.test.mjs` → **tests 45、pass 45、fail 0**。

brand test 的非空性：[静态] Uint16Array 夹具共 26 字节，按字节解读本身就是一段合法 wire（一个数据帧加 EXITED_ZERO 终结帧）。所以如果校验失效，测试会因为"被接受并解码成功"而失败，不是空过。§5 的变异 B3/B4 实测确认了这一点。

## 4. 输入矩阵（实测）

decoder、collector 的 stdout 通道、collector 的 stderr 通道三列结果一致；越界视图一行除外，已在表中单独注明。

| 输入（除 Buffer 与普通对象外，均为把原型设成 `Buffer.prototype` 后的结果） | 结果 |
|---|---|
| 真实 Buffer | 接受（EXITED_ZERO） |
| Uint8Array | **接受** |
| Uint8Array 的子类 | **接受** |
| 跨 realm（`vm.runInNewContext`）创建的 Uint8Array | **接受** |
| 带伪造 `length`/`byteLength`/`byteOffset`/`buffer` 访问器、并把 toStringTag 设成 `Uint16Array` 的 Uint8Array | **接受**（伪造的属性被忽略） |
| 建在可调整大小 `ArrayBuffer` 上、长度跟随的 Uint8Array | **接受** |
| 26 字节、本身是合法 wire 的 Uint16Array | INVALID_INPUT |
| Uint8ClampedArray | INVALID_INPUT（行为变化：同为字节数组，现在被拒绝） |
| Int8Array、Float64Array、BigUint64Array、DataView | INVALID_INPUT |
| 只有 `Buffer.prototype` 的普通对象 | INVALID_INPUT |
| Proxy 包装的 Buffer；Proxy 包装的伪装 Uint8Array | INVALID_INPUT |
| 普通 Uint8Array 外包 Proxy，`getPrototypeOf` trap 声称是 Buffer 原型（`Buffer.isBuffer` 为 true） | INVALID_INPUT |
| detached 的伪装 Uint8Array | INVALID_INPUT |
| 建在 SharedArrayBuffer 或可增长 SharedArrayBuffer 上的伪装 Uint8Array | INVALID_INPUT |
| 越界的可调整大小视图 | decoder 报 MISSING_TERMINAL；collector 报 EMPTY_CHUNK（归类不统一，但都会失败） |

## 5. 其他专项（实测）

- **重入：**
  - 用"记录所有 trap"的 Proxy 检查：decoder 和 collector 都只会触发 `getPrototypeOf`，来自 `Buffer.isBuffer` 内部的 instanceof；`isUint8Array` 不会运行任何用户代码。这条路径上 decoder 没有分配私有内存。
  - trap 在不抛异常的情况下（返回 `Buffer.prototype`）重入 stdout / stderr / stdoutEOF / stderrEOF / abort / result：外层和内层都得到 REENTRANT，之后一直保持。
  - decoder 没有状态：在 trap 里嵌套调用 decode 正常返回 EXITED_ZERO，外层得到 INVALID_INPUT。
- **上限：**
  - 伪造 `length`/`byteLength` 为 1 的 65537 字节伪装 Uint8Array：decoder 得到 TOTAL_LIMIT，期间分配 0 次；collector 两个通道分别得到 STDOUT_LIMIT / STDERR_LIMIT。
  - 先喂 65536 字节，再喂 1 字节：STDOUT_LIMIT。
- **敏感信息：** 用 Buffer 和伪装 Uint8Array 两种输入，各走 ok / missing / trailing，同时经过 decoder 和 collector：
  - 写标准流次数为 0；调用方输入没被修改；Buffer 池里没有 canary；返回值里没有 canary。
  - 返回值只出现固定字段：EXITED_ZERO、ok、MISSING_TERMINAL、TRAILING_DATA、INVALID_INPUT。
  - 伪装的 Uint16Array 和抛异常的 trap 都只得到固定的 INVALID_INPUT。

## 6. 变异测试（实测，在临时副本上运行 4 个测试文件）

| 变异 | 结果 |
|---|---|
| B1/B2 删除 protocol / collector 中的 `isUint8Array` | 被杀（buffer-brand） |
| B3/B4 把 protocol / collector 中的检查换成 `isTypedArray` | 被杀（buffer-brand） |
| B5 把 protocol 中的检查换成 `ArrayBuffer.isView` | 被杀（buffer-brand） |
| B6/B7 只保留 `isUint8Array`、去掉 `Buffer.isBuffer` | 被杀（collector / erase 测试，protocol 测试） |
| P1 删除 decoder 的 finally 清零 | 被杀（erase） |
| P3 另做一份 `Buffer.from(view)` 副本用于解析 | 被杀（erase） |
| P3b 导入时预先保存 `Buffer.from`，再用它另做一份副本 | 被杀（erase） |
| C1 删除 collector 在 `result()` 中的清零 | 被杀（erase） |
| C4 collector 只在 ABORTED 时清零 | 被杀（erase） |
| **P3c 另做一份 `Buffer.copyBytesFrom(view)` 副本用于解析** | **存活**（4 个测试文件全部通过）；实测 Buffer 池中**能**查到 canary |
| **P3d 另做一份 `Buffer.concat([view])` 副本用于解析** | **存活**；实测池中**能**查到 canary |
| **P3e 另做一份 `Buffer.allocUnsafe(length)` 再 `set` 的副本用于解析** | **存活**；实测池中**能**查到 canary |
| 对照：真实源码 `92329bb4…` | 同一探测下池中**查不到** canary |

**P3c/P3d/P3e 说明的是测试盲区，不是当前源码引入的副本。** 当前源码不会产生这些副本，同一探测在真实源码上为 false。这三项说明 erase test `30c10cb3` 只拦截了 `Buffer.from` 这一条复制路径；以后如果源码改用其他池化复制路径，这些测试发现不了。建议（未实现）：直接扫描 Buffer 池断言没有 canary，或者对所有池化分配路径都做观测。

## 7. 剩余风险与范围外

- **Medium [静态，本次未重跑]：collector 被丢弃前没有收尾，导致内存残留。** collector 如果既没调 `result()` 也没调 `abort()` 就被丢弃，内部 64 KiB 缓冲区里的明文不会被清零；释放后的内存可能被后续分配读到。本次 diff 只在输入校验处加了一个条件，没有触及这条路径，所以按读码推断问题仍然存在；实测证据见前序 `REVIEW-ERASURE-STRONG.md`（针对另一快照）。
- **Low [静态]：同 realm 篡改。** `Buffer.isBuffer`、`util.types.isUint8Array` / `isSharedArrayBuffer`、`Buffer.prototype.readUInt*`、全局 `Uint8Array` 都是运行时可以替换的；`allocUnsafeSlow` 在导入时绑定，在导入之前替换也能截获。按设计复核，恶意同权限代码不在防护范围内。新增的 `types.isUint8Array` 同样可以被替换。
- **Low [静态，本次未重跑]：栈临界时向外抛出。** 相关代码路径没有变化。
- **Info [实测]：** 来源不认证——任何真实 Uint8Array 换上 Buffer 原型都会被接受；越界视图的错误归类不统一。
- **范围外 / 遗漏 [静态]：**
  - 调用方或客户端自己的输入块（例如真实 Node 管道或流的读缓冲）不由本切片清零或认证。
  - collector 在累积期间按设计持有明文。
  - 真实管道的排空、超时、来源认证，以及与 OS 退出状态、进程树的绑定都没有建立；本组件不是进程能力。

## 8. BLOCK

现有 BLOCK 全部保持。本复审只覆盖受控事件 decoder/collector 的 Buffer 输入品牌校验切片；不得据此创建或清理容器，不得运行 DB、容器或真实 CR。

*本文件为新建文档；未覆盖同目录任何既有材料。*

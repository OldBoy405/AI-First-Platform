# AIFI-45 受控事件收集器：STDD strong 独立审查（初审，仅旧快照）

- 性质：只读独立审查归档。未修改 multica 源码或测试；未运行 DB、容器、真实引擎或真实 CR；未接 CI。
- **不解除现有 BLOCK，不构成任何进程、进程树、退出状态或清理能力的证明或授权。**
- Session ID：`01a18578-ba89-7020-aecc-d22c79a783ca`；请求模型（会话环境 `PI_MODEL`）：`claude-opus-5-5`，`PI_REASONING_LEVEL=high`；实际 backend 未知。
- 环境：Node `v24.15.0`（Windows，Git Bash）。

## 0. 审查快照（原始 SHA-256，`sha256sum` 计算，未归一化）

| 文件（相对 `C:/Users/GOBAO/Downloads/AI/multica`） | 审查时 SHA-256 |
|---|---|
| `scripts/aifi45-db/supervisor-collector.mjs` | `340403a916e68b4eef6be4f17831414de100220c4bd422a76d55fda0eca2ca7a` |
| `scripts/aifi45-db/supervisor-collector.test.mjs` | `5350526362ffd81069a291a2272e54532b77e7528b489b654c07a74b810f0e33` |
| `scripts/aifi45-db/supervisor-protocol.mjs` | `bed82664f2f17918b47302a94255e3061cbce9f516f578a074a997671b75452c` |

**范围限定：本报告仅针对上表旧快照。** 归档时（写入本文件前）复核磁盘：collector 与 test 的 SHA 未变；`supervisor-protocol.mjs` 已变为 `8c83e4f1e6d4b0f248a58ee505d542b404e18cf5aee3c70f6a7dc3fb942caa30`。**该新版本未被阅读、未被审查、未被复现**，下文 M1 等结论对新版本既不确认已修复，也不确认仍存在。

参照材料（只读）：同目录 `REVIEW-EXECUTION-BALANCED.md`（仅为测试复跑 16/16，非独立审查）；`validation/ci-supervisor-design-review-strong-20261028.md`（不解除 BLOCK、恶意同权限代码不在防护范围）；multica `CUSTOM.md` #267（TEST-ONLY DRAFT）。

## 1. 执行方式与证据

- 测试：`node --test supervisor-collector.test.mjs supervisor-protocol.test.mjs` → tests 40、pass 40、fail 0。
- 实验目录：`mktemp -d` 生成的唯一目录 `/tmp/tmp.1empDb6GM3`，实验结束后已删除；未使用固定 `/tmp` 文件。实验脚本以 `file:///` 绝对 URL 只读导入原始模块；变异测试与诊断均在临时目录中的**副本**上进行，原文件未被改动（collector/test SHA 归档时复核不变）。
- 全部复现均为纯模拟事件注入，不涉及真实子进程。

## 2. 结论摘要

未发现返回伪造成功、或经返回值/异常/标准流泄露秘密的 Critical/High 问题。存在 2 个 Medium（同进程敏感残留；擦除逻辑测试假绿）、3 个 Low、若干 Info。

## 3. Medium

### M1 解码器副本将 stdout 明文留在共享 Buffer 池（实际复现）

- 机制：collector 在 `result()` 解码后及 `fail()` 中对内部 64 KiB stdout 缓冲 `fill(0)`；但旧快照 protocol 中 `Buffer.from(new Uint8Array(backing, offset, length))` 另行复制一份且从不清零。小于约 4 KiB 的 wire 由 Node 从共享 8 KiB 池分配；任何池化 Buffer 的 `.buffer` 都暴露整块 slab。更大的 wire 不入池，但副本在堆上存活至 GC，同样未清零。
- 复现（排除测试夹具自身入池的对照）：wire 与秘密仅用 `Buffer.alloc` 逐字节构造（不入池），喂入后调用者清零自身输入；执行 `stdout(wire)`、`stdoutEOF()`、`stderrEOF()`；在 `Buffer.from(Buffer.allocUnsafe(1).buffer)` 中用非池化 needle 搜索秘密：
  - 对照（不调用 `result()`）：`secret in pool slab: false`
  - 调用 `result()` 后（返回 `{"decoded":true,"reportedOutcome":"EXITED_ZERO"}`）：`secret in pool slab: true`
  - 解码失败路径（仅 `frame(2, secret)`，返回 `MISSING_TERMINAL`）：同样可见。
- 影响范围：同进程可读残留；非跨进程，不进入返回值、异常或标准流。collector 的 `fill(0)` 造成"已擦除"的错误印象。
- 修复方向（建议，未实现）：protocol 不复制直接在受控视图上解析，或复制后在所有返回路径清零；并补充能捕获该行为的测试。

### M2 测试假绿：擦除逻辑零覆盖（变异测试）

在临时副本上逐一变异并运行 collector 测试：

| 变异 | 结果 |
|---|---|
| 删除全部 `stdout.fill(0)` | pass 16 / fail 0（**存活**） |
| 仅删除 `fail()` 中的 `fill(0)` | pass 16 / fail 0（**存活**） |
| 删除 view 构造后的 `if (failure) return failure;` | pass 16 / fail 0（存活；冗余代码） |
| `!Buffer.isBuffer(input) \|\| failure` 去掉 `\|\| failure` | pass 16 / fail 0（存活；任何 Proxy 都会在内建 getter 处失败，检查冗余） |
| 删除 `busy` 重入检查 | fail 1（被捕获） |
| 删除 SharedArrayBuffer 检查 | fail 1（被捕获） |
| 去掉 `decoded` 缓存 | fail 1（被捕获） |
| 删除 `EMPTY_STDOUT` | fail 1（被捕获） |
| 以 `input` 代替新建视图 | fail 1（被捕获） |
| 空块改为接受 | fail 1（被捕获） |
| 成功后封存终态 | fail 1（被捕获；测试把"不封存"固化为契约） |

canary 测试只断言返回对象与标准流写入，不能证明内存无残留（M1 即反例）。

## 4. Low

- **L1 终态未封存 / 终态竞态。** `result()` 返回 `decoded:true` 后再 `abort()` 或非法事件，后续 `result()` 变为 `ABORTED`（实测），而先前返回的冻结成功对象仍是有效令牌，无法撤销；测试"completion is not immune…"将此固化。反向地，EOF 未齐即调用 `result()` 会粘滞失败：若泵在子进程 `exit`（可早于 stdio `close`）时调用，会把正常运行永久判失败（fail-closed，但属集成陷阱）。接入方必须将 `result()` 视为时点快照而非终裁。
- **L2 栈临界时向外抛出，违背"从不抛出"契约。** 在逐层递归深度调用：`stdout()` 抛出 8 次，事后状态为 `EMPTY_STDOUT`（调用未生效）；`result()` 抛出 6–35 次（视运行而异）。经诊断副本（仅加只读 `_peek`）确认这些抛出均发生在 `decoded` 赋值之前，正常深度重试得到成功且缓冲已清零。未观察到状态损坏或秘密进入异常；"`decoded` 已赋值但 `fill(0)` 未执行"窗口未命中，**不能排除**。
- **L3 同 realm 篡改防护不一致。** 已固定 TypedArray 内建 getter，但 `Buffer.isBuffer`、`Buffer.prototype.fill/subarray`、全局 `Uint8Array`、`util.types` 及 protocol 的 `Buffer.from` 未固定。实测：预先 patch `Buffer.prototype.subarray` 可截获内部 64 KiB 缓冲并读到明文；patch `fill` 可使擦除失效。按设计复核，恶意同权限代码不在防护范围内；此处仅指出代码/测试命名可能暗示了不存在的部分防护。

## 5. Info

- 输入接受面宽于测试名"only genuine Buffer"：原型改为 `Buffer.prototype` 的 `Uint16Array`、可调整大小的 `ArrayBuffer` 上长度跟随的 view 被接受（字节复制正确，无危害）；越界 view 被归为 `EMPTY_CHUNK` 而非 `INVALID_INPUT`。
- 已逐项验证可靠：SharedArrayBuffer 拒绝（能识破伪造的 `buffer` 属性）；detached（含零长度）拒绝；revoked Proxy 与包裹 Buffer 的 Proxy 拒绝；重入（trap 抛出、trap 不抛出并返回 `Buffer.prototype`、经 `abort`/`result` 重入）均为 `REENTRANT`；参数个数检查不触碰多余参数；EOF 后先判 `DATA_AFTER_EOF` 不检查 hostile 输入；上限含边界值；`set` 前读取长度，无 TOCTOU；第一个失败始终保持。
- 外部集成前提（组件均未建立）：无 deadline、无来源认证、不与 OS 退出状态或进程树绑定，`reportedOutcome` 仅为 wrapper 声明；stderr 超限为致命失败，与设计"继续排空、不再缓存"不同，失败后泵仍须自行排空管道；`EMPTY_CHUNK` 致命（Node 流不发空 `data`，其他泵可能会）；65536 上限在 collector 与 protocol 中重复定义、未相互引用；仓库内无任何代码引用该 collector，未接 CI。

## 6. 剩余 BLOCK 与风险

- 现有 BLOCK 全部保持：本组件不是进程/进程树/退出/清理能力；事件来源、真实流排空与超时、进程树为空证明、持久日志、清理授权均未建立；不得据此创建或清理容器，不得运行 DB/容器/真实 CR。
- M1、M2 在旧快照上成立；protocol 已变更为 `8c83e4f1…`，需对新快照重新审查与复现后方可判定。
- L2 窗口未完全排除；L1 需接入方显式约定 `result()` 语义。

*本文件仅为文档写入；未覆盖同目录既有材料（`AUTHOR-EXECUTION.md`、`REVIEW-EXECUTION-BALANCED.md`、`source-review/`）。*

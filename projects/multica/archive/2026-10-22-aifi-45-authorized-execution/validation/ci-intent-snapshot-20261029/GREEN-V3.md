# CI intent snapshot V3 GREEN（作者）

独立 balanced 初版审查指出迟换 decoder 后，先执行 `RED-LATE-DECODER.md` 的 RED，再捕获初始化时的 UTF-8 decoder 方法；对旧 fatal 与擦除观察器测试改为在测试模块加载前注入，避免因捕获方法而丢掉正控。旧 `GREEN.md` 和 `MUTATIONS.md` 仅适用于 V2，原样保留。

在 `source-final-v3/` 精确运行两个 Node 测试文件：exit 0，**36 tests / 36 pass / 0 fail / 0 skip / 0 cancelled**。四文件测试前后 raw SHA 相同：

| 文件 | SHA-256 |
|---|---|
| `instance-intent-record.mjs` | `9022344328d8f8c64894c26cbd3910f0c001954a8be31ea80b4641e8191680bf` |
| `instance-intent-record.test.mjs` | `482f822294931519d44873acd966ca2977528f4b123391f5d99344c131e7563e` |
| `instance-intent-snapshot.test.mjs` | `b3c185393e3fae007f921e59b28d46d70cdf394a418bcda557e361da3d9a6bcd` |
| `instance-ownership.mjs` | `5c4785ae4a03a951a00a72248528ba97b11163caf5675c8304e6a8c656e05288` |

原 stdout/stderr 仅在内存解析计数；环境白名单不能证明 OS 级网络隔离。`MUTATIONS-V3.md` 记录最终版本的十一项作者变异。私有缓冲清零是可捕获失败时的尝试，失败不发布成功，不证明其他副本清除；捕获 decoder 防的是初始化后替换该方法，不防模块加载前或其他任意同 realm 篡改。SHA 校验不认证、未接真实 journal/引擎；不构成 DB、容器或 Gate3 证据。本 GREEN 产生时 strong 独立复核尚未完成；后续限定范围静态复核见 `REVIEW-STRONG-V3.md`，未重算 SHA 或动态复跑，actual backend unknown。

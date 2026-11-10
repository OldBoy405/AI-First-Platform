# CI 实例归属：必需环境键一致性计划

**目标：**固定 PGDATA 与三个必需 POSTGRES 键必须在可枚举的实例环境映射中，不能由继承或不可枚举属性满足，却不进入实际 Config.Env。归属校验仍仅限内部纯函数及合成 inspect。

**依据与边界：**`ci-instance-ownership-review-20261028/REVIEW-CORRECTION.md` 的 expectedEnv/Config.Env 全键精确匹配约束；`instance-lifecycle.mjs` 先复制 expectedEnv，尚无证据普通调用路径触发此缺陷。该修复不新增清理授权，不接真实引擎/DB/网络，不解决异步失联、恶意代理/可变对象、同 realm 篡改或进程树。

**文件：**从平台工作区根解析 sibling 源码仓 `../multica/scripts/aifi45-db/instance-ownership.mjs`；同目录 `instance-ownership.test.mjs` 增加负例；`../multica/CUSTOM.md` 登记。现有 codec/lifecycle 不修改。

1. 对每个必需键，将它改为非可枚举且合成实际环境同步删该键，其余字段均有效；分别断言 intent 和 ownership 拒绝。另测 PGDATA 从原型继承但合成实际环境缺失。普通 fixture 已有正控。
2. 在旧源码运行目标 `node --test`，确认各缺陷用例因未抛出目标错误而 RED；不要保存环境值、原始敏感输出，记录选中/失败/skip 与哈希。
3. 最小修复让四个必需键均为自身可枚举属性，仍要求值正确并复用已有全键/值比较；如需约束 getter/Proxy 或新任意环境键语义，先独立讨论而非据此声称完整信任边界。
4. V1 strong 独立复核发现 hidden 非枚举额外键可代替合法枚举键绕过集合比对（详见 `REVIEW-STRONG-V1.md`）：先加入仅替换键的合成负例，在 V1 真正运行 RED，再让检查实际 Config.Env 的键也必须是 expectedEnv 的自身可枚举键。该步骤仍不扩展到 getter/Proxy、可变对象或真实引擎。
5. 重跑 ownership/intent/lifecycle 的相关纯内存测试，并请求配置中的 strong 静态和 balanced 测试独立复核，固定 raw 源码 SHA。不能将组件绿计入 Gate。

旧源码 raw SHA-256：ownership `5c4785ae4a03a951a00a72248528ba97b11163caf5675c8304e6a8c656e05288`，test `c692885d1e81f8b41429e20c955691f1d5bc46f4174949bdf565333740a26b13`，lifecycle `8bf026671ffe6b57825848dafc397bdd36cf5df61892fcad0cdad6cbb0e67a88`，intent codec `9022344328d8f8c64894c26cbd3910f0c001954a8be31ea80b4641e8191680bf`。

# 独占实例归属检查初稿 — 作者证据

本次用户授权创建并销毁一个全新独占临时 PostgreSQL 容器及其内部资源；截至本记录**尚未创建该容器、未执行任何新数据库操作**。已有 pinned 保留容器仅做只读 inspect 字段名调查。完整实施计划见 `ci-disposable-db-implementation-plan-20261028.md`。

新增 `../multica/scripts/aifi45-db/instance-ownership.mjs` 与 `instance-ownership.test.mjs`，纯函数尚未接入 `run.mjs`，不能用于实际清理授权。它对指定候选的完整 ID/名称/nonce/创建时间/镜像及配置做静态检查；合成 inspect 不证明 Podman 真机形状、引擎身份、来源绑定或 TOCTOU 安全。

- 第一版可运行空函数 33 测试中 32 个断言失败、1 个正例通过；实现后通过。追加 7 个独立负例，其中 6 个先失败（3 个缺失字段、2 个 null binding、运行时网络绕过），修正后 40/40，skip 0。
- 分别去掉 ID 相等与实际 host 回环检查，各自命中目标独立测试 `Missing expected exception`；逐次恢复源码原始 SHA 后，连同旧 runner 测试合计 51/51、skip 0。
- 初审快照 raw-byte SHA-256：源码 `ac6ffb765843813be50bac8dfce5d0fe5a2eaac231988592401e78c2faef4478`；测试 `fdb71e49ac7897e4a3da98a1bee429f6af3e6097898727c5748640854d57c614`。原审核与其二审及正则语义纠错完整保存在 `ci-instance-ownership-review-20261028/`，不改变原文；二审对无 `m` 正则尾换行的判断被审查者独立 Node 语义探针撤回。
- 按审查意见补状态枚举、cap/security/entrypoint、实际端口、严格日期及与可信期望环境的匹配。target/expectedEnv 的固定来源和真实引擎兼容仍未证明；内存期望环境包含 secret，不得写日志。复审前四文件作者组合测试 103/103、skip 0：ownership SHA `8f2b968cd09757278efe2c54c193544bbdcbb29f288df4d386e1efd66b2038fb`，测试 SHA `c692885d1e81f8b41429e20c955691f1d5bc46f4174949bdf565333740a26b13`；lifecycle SHA `90ede1f5801274f6623b0e5abfc2012e0b8448d5078217c7d689eda34b7b9478`，测试 SHA `f443d7eee98de22927ffdc47fc02d9270adef6c9daae894bbd4bb50468949f7b`。
- lifecycle 初稿首次可运行 stub 在 12 个独立测试 12/12 RED；后续 14/14 GREEN；删除清理前复验、删除 ID 缺席判断分别导致对应测试 RED，逐次恢复当时源码 SHA。独立审查维持 BLOCK，原文与快照见 `ci-instance-lifecycle-review-20261028/`；针对发现增加同步 journal ack、意图冻结、危险环境预检、明确进程退出回执和端口漂移 fail-closed，尚待完整复审。

- 二次静态复审维持 BLOCK，并指出退出回执 getter/thenable 及停止前后端口漂移问题；五个独立反例先 RED，修正后作者组合测试 108/108、skip 0。最新 lifecycle 源码 SHA `5c66296136393ccbccfba0718cbee681e679a3deaf6de83b2970d1161efdbf25`，测试 SHA `7a9d278de1ee49e5f312ef59fc0c0491d1f923ec2d525fa556898c03a68eb706`；此更新未被该原复审核对，不能改变其结论。

- 再次独立复审发现空错误可能假绿、Promise rejection 未处理；两个空字符串异常和普通 rejected Promise 各自 RED→GREEN，禁用普通 Promise rejection handler 的变异 RED，恢复 lifecycle SHA `7c42f86a5616ea8396deefa84b9119b59766f668ac18889ef0b1bd704dcf4e47`。created inspect 固定端口另有 RED→GREEN，当前 ownership SHA `5c4785ae4a03a951a00a72248528ba97b11163caf5675c8304e6a8c656e05288`。对应后续静态复审确认空错误反例及普通 Promise 场景修补，但保留 **Promise subclass/constructor/species** 的拒绝仍可 unhandled 而泄漏的阻塞，以及 created→running 端口语义未证实；原报告和 SHA 见 `ci-instance-lifecycle-review-20261028/REVIEW-FAILURE-RECHECK.md`。
- 作者用仅含假密码的隔离 Node 子进程确认 species getter 抛错反例：`--unhandled-rejections=strict` 返回 1，stderr 包含假密码；此不是最终 lifecycle 端到端回归，也不涉及容器/数据库。仅依赖注入的 probe 返回对象不构成可信同步进程适配，必须阻断真实接线。
- 本次作者将 intent 公共字段编码草稿与协议测试登记 `multica/CUSTOM.md` 第 257 项；独立审查维持 BLOCK，详细作者与审查证据见 `ci-instance-intent-review-20261028/`。`ci-instance-journal-design-20261028.md` 记录 Windows 临时空目录只读打开的 fsync 返回 EPERM、读写打开的 fsync 返回成功的单机对照；后者不证明断电命名空间持久性。

- 本轮 failure journal ack=false/抛错反例各自 RED：先前即使无法记录故障也会继续清理；现撤销 cleanup trust，变异撤销动作时两项 RED。异常、options/target getter 的假 secret 反例 RED→GREEN；错误及 journal 仅写固定 phase，不读取原异常，访问 message 的变异 RED。移除截断字符串 scrub 不表示能控制 adapter 自行输出或异步拒绝。
- created→首次 running 的请求端口漂移反例 RED→GREEN；分别对异步 `start`/`stop`/`remove` 返回 Promise 的假绿反例 RED→GREEN，三个同步 `true` 回执检查的定向变异均 RED，逐次恢复源码 SHA。结果仅证明拒绝该合成异步返回，**不处理其后续 rejected Promise 或证明真实引擎操作完成**；实际 inspect 两阶段可能如何报告动态端口仍未验证。
- 四文件作者测试 **149/149、fail 0、skip 0**；lifecycle 源码 raw SHA `8bf026671ffe6b57825848dafc397bdd36cf5df61892fcad0cdad6cbb0e67a88`，当时测试 `47a0636661fc2667df79c73aedd4f72defe6875bc3911d021b893e1b98692eb8`。独立复审 `ci-instance-lifecycle-review-20261028/REVIEW-GUARD-RECHECK.md` 核实该快照、独立运行 42/42、skip 0，并仅认可同步 ack、请求端口连续和 failure journal 三项局部改动；真实引擎、异步拒绝及持久 journal 的整体 BLOCK 不变。
- 按复审建议又补 failure journal 返回 resolved Promise 的负例，并对 start/stop/remove 的 false、undefined、truthy 字符串和数字逐项设独立负例；四文件作者组合 **162/162、fail 0、skip 0**，新测试 SHA `9a628afcde61bdd1b0a2c47ad0ab8f2c9656db04943c196c1c8cc6b614f5b5f4`，未被前述复审覆盖。此处 resolved Promise 测试不覆盖 rejected Promise 的异步输出。先前完整审核针对 `9c7bbb2308ee4533e5d68dedf0819ed22b85b67fc86934d06590e8b033ae37f8` 保持 BLOCK，不因后续修改自动升级。

未建立持久化 intent/cidfile、丢失 ack reconciliation、临时实例创建与安全清理、host TCP readiness、正式 provisioner、正式迁移、CI 路由和真实生命周期验证。同步 ack 和进程退出对象只是抽象契约，不证明 fsync 或真实进程结束；最新源码没有实际引擎 adapter，也未接入 runner。即使未来纯函数审查通过也不能替代这些门禁；CI BLOCK、TC-RUN-003、BUILD 44/49 和 Gate3 NO-GO 均不变。

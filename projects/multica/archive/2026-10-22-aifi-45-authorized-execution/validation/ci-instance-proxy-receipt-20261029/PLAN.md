# 退出回执 Proxy 防误用计划

## 目标与依据

`../multica/scripts/aifi45-db/instance-lifecycle.mjs`（相对平台工作区根）现有合同要求同步退出回执才允许进入身份复查与清理；原生 Promise、thenable 或未确认退出均保留实例。Proxy 包装 Promise 隐藏 `then` 并伪报退出时，当前类型判定可能误认同步退出。本计划只修 fake-engine 可测的误用边界；不证明真实进程退出、资源安全或防御恶意适配器。

## 范围和步骤

1. 在 `instance-lifecycle.test.mjs` 使用现有 fake engine：用 pending Promise Proxy 隐藏 then、伪报退出，断言固定失败、无 trap 读取、无 cleanup inspect/stop/remove、无 cleaned 事件。透明普通 Proxy 与已撤销 Proxy 也明确拒绝；沿用已有普通同步回执正控。测试不执行 DB、容器、网络或真实探针。
2. 对目标测试执行旧源码 RED，必须确认命中缺失拒绝或副作用断言；已撤销 Proxy 本来可能被拒绝，不计为漏洞复现。
3. 最小修改：读取回执属性前使用 `node:util.types.isProxy` 拒绝所有 Proxy，维持原生 Promise/thenable 处理和固定错误；README 限定说明兼容收紧。不保证能消费代理内部 rejected Promise，不尝试 inspect/unproxy，不把普通对象回执当作认证。
4. 运行相关纯内存测试，固定 raw SHA 与快照；strong 安全、balanced 测试及 economy 文档独立复核。登记 multica `CUSTOM.md`。不得清理真实资源、接真实 adapter、修改 Gate 或声称生产进程树已受保护。

## 结论

**A 的两个假绿路径已在代码层封堵；B 对普通原生 Promise 已修补，但对 Promise 子类或被修改的 Promise 仍不完整；created 阶段已拒绝固定非零请求端口。原 BLOCK、gate 均保持不变。**

仅只读审查四文件及测试断言，**未执行测试、容器或 DB，未修改文件，不授予真实操作授权。**

### 快照核验

审查前后逐个计算 raw-byte SHA-256，均与给定值一致：

```text
instance-lifecycle.mjs
7c42f86a5616ea8396deefa84b9119b59766f668ac18889ef0b1bd704dcf4e47
instance-lifecycle.test.mjs
2a924f411992098f741976b77580ceafcf0cc422f03d96084c9a833467889772
instance-ownership.mjs
5c4785ae4a03a951a00a72248528ba97b11163caf5675c8304e6a8c656e05288
instance-ownership.test.mjs
c692885d1e81f8b41429e20c955691f1d5bc46f4174949bdf565333740a26b13
```

以下路径均相对 `../multica/scripts/aifi45-db/`。

## 1. A：失败状态不再依赖错误文本，具体修复成立

出处：`instance-lifecycle.mjs:21,67–71,89–98`。

- 主流程和清理流程的 catch 都先置 `hadFailure=true`。
- 空错误文本有 fallback。
- 最终检查 `hadFailure || !cleaned`，而非错误文本的 truthiness。
- 即使 `cleaned=true` 后 `record('cleaned')` 抛错，也不能返回成功。

因此此前两个反例——`start` 抛空字符串、cleaned 事件抛空字符串——均不能再假绿。

**测试源码覆盖：**
- `instance-lifecycle.test.mjs:160–164`：空 start 异常，要求抛错且未运行 probe。
- `:166–171`：空 cleaned-record 异常，要求已 remove 但整体仍失败。

范围限制：这证明的是异常不会因空文本被吞成成功；不证明 journal 持久化。`scrub` 自身仍可能因异常对象的 getter/字符串转换等抛错，但那会传播异常，而不是正常返回成功。

## 2. B：普通 Promise rejection 已处理；子类副作用仍有缺口

出处：`instance-lifecycle.mjs:56–64`。

### 已成立的部分

对未被特殊修改、使用标准 constructor/species 的原生 Promise：

- `types.isPromise(result)` 将其识别出来；
- 内建 `then` 注册 rejection handler；
- 随后同步报 `probe exit unresolved`；
- `trusted` 保持 false，不 stop/remove。

普通 `Promise.reject(new Error(password))` 的原 rejection 因而不再保持未处理状态；标准派生 Promise 会正常完成。这修补了此前 B 的普通 Promise 反例。

测试 `instance-lifecycle.test.mjs:198–204` 确实创建了真实 rejected Promise，断言同步失败、不清理，并等待一个 `setImmediate`。但它没有显式检查 journal、stderr 或其他输出中的 secret；对未处理 rejection 的检查主要依赖测试框架行为。**本次未执行，不能确认通过。**

### 仍存在的中风险：内建 `then.call` 并非无副作用

`Promise.prototype.then.call(result, …)` 虽绕过了 `result.then` 的覆盖，仍会读取 `result.constructor`、处理 `constructor[Symbol.species]`，并构造派生结果。

静态反例，未执行：

```js
class ProbePromise extends Promise {
  static get [Symbol.species]() {
    throw new Error('species failed');
  }
}
// probe 返回 ProbePromise.reject(new Error(password))
```

该对象能通过 `types.isPromise`。但第 59 行会在**给原 Promise 安装 rejection handler 之前**因 species getter 抛错：

- 同步 species 错误进入外层 catch；
- 原始含密 rejection 仍可能成为 unhandled rejection；
- 原始错误仍可能绕过 `scrub` 输出，或依运行配置终止进程。

此外，自定义 species constructor 可执行额外代码、制造拒绝结果；第 59 行返回的派生对象被忽略，不能据此声称“所有实际 Promise 均已安全消化”。普通 Promise 自有的 constructor 属性也能触发类似问题，不限于子类。

**限定判断：B 部分修复，不能整体关闭。** 当前没有 constructor/species 抛错、副作用或派生拒绝测试。该缺口不恢复清理许可，但仍影响错误通道和泄密控制。

## 3. Dynamic port：created 请求判定成立，端到端结论须收窄

出处：

- `instance-ownership.mjs:66–72`：created 模式仅接受 requested HostPort 为 `''` 或 `'0'`。
- `instance-lifecycle.mjs:49–51`：先做 created 核验，再 start；不匹配会撤销 trusted，阻止 start 和清理。
- `instance-lifecycle.test.mjs:110–115`：注入固定请求端口 `'39421'`，要求失败且不 start/stop/remove。

所以，**“created inspect 已报告固定非零请求端口却仍获准启动”的具体路径已封堵。**

但不能扩大为“动态分配全过程已证明”：

- running/stopped 模式仍接受合法固定 requestedPort。
- requestedPort 的比较基准到首次 running inspect 后才保存（`:52–55`）；created 到首次 running 之间的请求值变化没有与 created 快照比较。
- created 检查不强制实际 `NetworkSettings.Ports` 必须为空。
- ownership 测试文件未更新；已有 `:152–155` 覆盖空请求端口的 created 正例，尚无 `'0'` 正例及新增规则的独立负例。

上述限制不否定 created 请求值检查，但真实 create argv、引擎报告语义及首次启动期间的行为，仍需可信 adapter 和独立证据。

**最终限定：A 具体关闭；B 普通场景改善、子类/constructor/species 风险未关闭；dynamic port 仅确认 created 请求标记检查。没有测试通过回执，不改变原 BLOCK 或任何 gate。**
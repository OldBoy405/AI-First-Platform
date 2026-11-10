## 结论

**原 BLOCK 保持不变。** 当前源码已修补 RECHECK 所列的探针 thenable、回执 getter 异常及停止态端口漂移具体缺口；已退出非零探针仍会在重新核验归属后清理，并使调用失败。但另发现两条失败处理风险，且真实 adapter、进程等待、journal 持久化等证明仍缺失。

本次仅静态只读复核：**未执行测试、未访问容器或数据库、未修改文件，不授予任何真实操作授权。**

## 1. Raw SHA-256

先逐个计算源码 raw-byte SHA-256，复核结束再次计算，结果一致。路径前缀为 `../multica/scripts/aifi45-db/`：

```text
instance-lifecycle.mjs
5c66296136393ccbccfba0718cbee681e679a3deaf6de83b2970d1161efdbf25

instance-lifecycle.test.mjs
7a9d278de1ee49e5f312ef59fc0c0491d1f923ec2d525fa556898c03a68eb706

instance-ownership.mjs
8f2b968cd09757278efe2c54c193544bbdcbb29f288df4d386e1efd66b2038fb

instance-ownership.test.mjs（补充读取）
c692885d1e81f8b41429e20c955691f1d5bc46f4174949bdf565333740a26b13
```

已完整读取指定目录的 `REVIEW-STRONG.md`、`REVIEW-RECHECK.md`、`REVIEW-RECEIPTS.json`，并读取实施计划。两份报告的 raw SHA 均与 receipts 一致；当前 ownership 两文件与 RECHECK 快照一致，lifecycle 两文件已变化。

下文源码路径均相对上述脚本目录。

## 2. 最近修复的独立限定结论

| 检查项 | 当前控制流结论 | 测试源码实际覆盖 |
|---|---|---|
| thenable 携带伪造退出字段 | **具体绕过已封堵。** `instance-lifecycle.mjs:55–60` 先撤销 `trusted`，读取字段后明确拒绝 callable `then`，不会凭 `exited:true/code:0` 恢复清理许可。 | `instance-lifecycle.test.mjs:166–170` 确实构造该 thenable，断言抛错且不 stop/remove。 |
| 回执 getter 抛错 | **此前误清理路径已封堵。** 读取 `then/exited/code` 均发生在 `trusted=false` 之后；任何读取异常都会跳过清理。 | `:172–176` 覆盖 **exited getter**。then、code getter 尚无各自测试，但静态控制流同样保持关闭。 |
| 确认退出后非零 | **符合当前契约。** 完整验证 `exited===true`、整数码 0..255 后恢复许可，再因非零码失败；finally 重新核验并清理，最后仍抛错。 | `:153–158` 使用 code 1，断言失败、remove 及名称 exists 查询；未逐一覆盖其他边界码。 |
| 清理前 running 端口漂移 | **具体缺口已覆盖。** 首次 running inspect 后固定 runtime/requested HostPort，清理前重新比较。 | `:117–122` 改成另一个合法 loopback 端口，断言不 stop/remove。 |
| 清理前已 stopped，仍报告漂移端口 | **此前缺口已覆盖。** 比较不再限定 running；ownership 检查结构，lifecycle 检查固定值。 | `:124–129` 将第三次 inspect 改为 exited 并改变端口，断言不 remove；该测试未额外断言不 stop。 |
| stop 后端口漂移 | **此前缺口已覆盖。** `:73–75` stop 后 inspect 再进入同一 `check`。 | `:131–136` 在第四次 inspect 注入合法但不同的端口，断言不 remove。 |
| requested HostPort 漂移 | **具体缺口已覆盖。** `:33` 比较保存的 requestedPort，而不只是判断当前端口是否合法。 | `:138–143` 将空请求端口改成与实际端口相同的固定值，仍要求失败且不 stop/remove。 |

`instance-ownership.mjs:65–96` 仍负责 loopback、binding 数量、端口格式与状态检查。停止后端口正常清空可以通过；正常生命周期测试也覆盖了 `Ports=null` 的路径。

**以上是源码与断言覆盖结论，不是 GREEN、RED→GREEN 或变异有效性回执。**

## 3. 本次新识别的漏洞

以下不代表已证明由本轮修改引入。

### A. 中：用错误文本的真假表示失败，可能产生假绿

位置：`instance-lifecycle.mjs:10,63,81–91`。

`scrub('')` 返回空字符串，而最终使用 `if (failed || !cleaned)` 判断失败。

两条可静态推导的反例，均未执行：

- `engine.start()` 同步 `throw ''`：此时 `trusted=true`，finally 可以核验仍为 created 的实例并清理；`failed===''`、`cleaned===true`，最终返回成功，**尽管 probe 根本没有执行**。
- `record('cleaned', ...)` 执行 `throw ''`，其他事件返回 true：`cleaned` 已提前置 true，cleanup catch 又通过 `filter(Boolean)` 丢弃空错误，最终可能成功返回，**尽管 cleaned journal 未确认**。

失败状态应独立于诊断字符串。当前测试没有空字符串异常或其他可转换为空文本的异常覆盖。

### B. 中：拒绝 Promise 探针时，原 rejection 没有被处理，可能绕过脱敏

位置：`instance-lifecycle.mjs:56–59`；对照 journal 的 `:24`。

例如 probe 返回一个尚未被处理的 `Promise.reject(new Error(password))`：

- 当前检查会拒绝它，并保持实例不清理——这一点正确；
- 但这里只读取 `.then`，**没有处理原 Promise 的 rejection**；
- 该 rejection 可能在调用已同步抛错之后成为 unhandled rejection；依 Node 配置，可能输出原始含密错误或终止进程。它不经过 `scrub`。

现有 thenable 测试只有空 `then(){}`，没有真实 rejected Promise，也未覆盖该错误通道。后续需单独设计 rejection 处置，不能把处理 rejection 等同于确认进程退出。

## 4. 原问题的剩余边界

- **意图与快照：具体修复有效。** create 前校验、复制冻结 target/env、拒绝危险 env 键均在；仍不证明镜像来源和允许环境值可信。嵌套 env 外部变更缺直接测试。
- **journal：同步 ack 门槛有效，但受上述空异常漏洞影响。** 严格 `true` 不等于落盘或 fsync；后续事件 ack 失败缺针对性测试。
- **丢 create ack：仍保守但不可恢复。** 不重试、不凭名称误删；仍无候选定位及重新证明归属的恢复流程。
- **动态端口要求未完全落实。** ownership 仍接受合法固定非零 requested HostPort；固定首次观察值只证明“后续未漂移”，不证明最初采用动态分配。
- **真实操作信任根仍缺。** 注入 engine/probe 的声明不能自行证明固定本地引擎、普通非 force stop/remove、真实子进程及子进程树已结束。
- **absence 与 secret 仍非端到端证明。** ID 和名称严格 false 的门槛保留，但无 adapter 可证明 false 仅代表明确 not-found；有限错误替换也不覆盖所有输出通道。
- **inspect 失联测试仍不足。** post-start inspect 抛错后可能在 finally 重验成功再清理；普通非空错误仍使调用失败，并非未经核验直接删除，但各阶段失联策略尚未充分测试。

**最终判断：可以限定确认上述具体控制流修复，不能据此宣告安全生命周期验收完成。原报告、BLOCK、CI gate、既有 verdict 与授权边界均不改变。**
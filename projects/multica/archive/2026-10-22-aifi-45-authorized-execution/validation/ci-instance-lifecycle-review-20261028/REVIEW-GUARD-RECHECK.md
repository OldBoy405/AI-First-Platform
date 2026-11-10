## 结论

**当前快照中，你列出的三项修正均成立；在这些小范围内，未发现残留的假绿或意外 cleanup 路径。** 结论以同步、可信的适配器契约为前提，不代表真实进程或容器安全认证。

只读完成，无文件更改、无 DB／容器操作。两份目标文件目前均为 Git 未跟踪文件，且未提供上次审查快照，因此以下确认的是**当前实现及测试行为**，不是历史逐字 diff。

目录：`C:/Users/GOBAO/Downloads/AI/multica/scripts/aifi45-db/`

### 三项修正

| 项目 | 实现依据 | 测试依据 |
|---|---|---|
| **failure journal 不确认则禁止 cleanup** | `instance-lifecycle.mjs:15–20` 只接受同步严格 `true`；`:70–76` 在 failure 记录失败时清除 `trusted`，阻断 cleanup。 | `instance-lifecycle.test.mjs:225–240`：已完成但失败的 probe，遇 failure record 返回 `false` 或抛异常，均不 stop/remove。`:218–223` 则确认 failure record 成功时可清理，但仍抛失败。 |
| **created → running 请求端口连续** | `instance-lifecycle.mjs:47–56` 在 created 校验后保存 `requestedPort`；`:24–28` 在首次 running 及后续检查中严格比较请求端口，并检查已知运行端口漂移。 | `instance-lifecycle.test.mjs:129–134`：首次 running inspect 改变请求端口，即禁止 probe/stop/remove；`:143–169` 覆盖后续端口漂移。 |
| **start/stop/remove 必须同步严格 `true`** | `instance-lifecycle.mjs:52–53、84、90` 均为 `!== true` 拒绝；start 前已撤销信任，stop 未确认不 remove，remove 未确认不报 cleaned。 | `instance-lifecycle.test.mjs:274–293`：即便 fake 操作已发生，返回 `Promise.resolve(true)` 仍失败，并阻断后续危险动作或成功声明。 |

### 假绿／意外清理检查

- `instance-lifecycle.mjs:60–69`：未确认退出的 probe 不恢复信任；非零退出码即使成功清理也保持失败。
- `instance-lifecycle.mjs:79–94`：cleanup 前及 stop 后重验 ownership；remove 后要求 **ID、名称均严格不存在**。
- `instance-lifecycle.mjs:95–108`：cleaned journal 确认后才设置 `cleaned`；`hadFailure || !cleaned` 始终抛错，不会因清理成功掩盖前面的失败。

**覆盖缺口，不是已发现的实现漏洞：** failure record 的异步确认尚无直接用例；start/stop/remove 尚未逐项覆盖 `false`、`undefined`、其他 truthy 值。源码严格比较已拒绝这些值，但不能把现有测试通过描述为穷尽覆盖。

### 明确不解决的边界

1. **任意 Promise 的 unhandled rejection**：`:61–63` 处理直接返回的原生 probe Promise，`:18` 尝试消费 journal thenable；但 start/stop/remove 等返回的 rejected Promise 没有通用消费机制。现有异步操作测试使用的是 resolved Promise。
2. **实际进程退出／引擎信任**：`:65–68` 接受 `{ exited: true, code }` 这一回执；它不独立证明真实进程退出。inspect、操作确认及 exists 也依赖引擎如实报告，未消除检查与操作之间的竞态。
3. **Durable journal**：`:16–20` 的同步 `true` 只是确认契约，不证明落盘、fsync、崩溃恢复或记录不可丢失。

### 实测与原始 SHA-256

运行 `node --test …/instance-lifecycle.test.mjs`，Node **v24.15.0**：**42 passed，0 failed，0 skipped**。两份目标文件测试前后哈希一致；SHA-256 按原始文件字节计算，未规范化换行。

```text
instance-lifecycle.mjs
8bf026671ffe6b57825848dafc397bdd36cf5df61892fcad0cdad6cbb0e67a88

instance-lifecycle.test.mjs
47a0636661fc2667df79c73aedd4f72defe6875bc3911d021b893e1b98692eb8

instance-ownership.mjs（只读核对的直接依赖）
5c4785ae4a03a951a00a72248528ba97b11163caf5675c8304e6a8c656e05288
```

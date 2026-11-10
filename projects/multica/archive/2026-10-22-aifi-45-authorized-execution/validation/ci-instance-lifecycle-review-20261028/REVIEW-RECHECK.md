## 复审结论

**原 BLOCK 保持不变；不改变 CI gate，也不授予任何实际操作授权。**

先行自行计算的四个 **raw-byte SHA-256 全部与新 snapshot 完全一致**，未规范化行尾。已只读阅读四个文件及实施计划；**未修改文件，未执行 DB、容器或测试**。以下是静态复核，不是测试通过回执。

下列路径均相对 `../multica/scripts/aifi45-db/`。

## 原 finding 的覆盖情况

| 原问题 | 本 snapshot 的覆盖与限制 |
|---|---|
| 无效 intent 到 create 后才完整检查 | **代码层已覆盖此前主要缺口。** `instance-lifecycle.mjs:33–36` 在 intent 事件和 create 前调用 `assertInstanceIntent`；校验名称/nonce、image 格式、创建时间窗、必要环境及允许键。固定镜像来源、固定引擎仍不在其证明范围。 |
| target 可被修改，比较基准跟着变 | **对当前接受的数据类型已覆盖。** `instance-lifecycle.mjs:5–7` 复制选定字段、单独复制并冻结 `expectedEnv`，再冻结 target；校验通过后相关值均为字符串。修改原始 target 或原始 env 不再改变基准。 |
| expected 与 observed 同时加入危险 env 可通过 | **此前具体绕过已覆盖。** `instance-ownership.mjs:4–5,20–29` 增加键允许列表，`POSTGRES_HOST_AUTH_METHOD=trust` 即使出现在 expected 中，也会在 create 前被拒绝。但 `PATH` 等允许键的值仍来自调用者，并未证明来自固定镜像。 |
| record 返回结果被忽略 | **同步返回契约已覆盖。** `instance-lifecycle.mjs:21–26` 要求严格返回 `true`；Promise、false、undefined 均失败，适用于 intent、created、cleaned 等所有事件。**这不证明真实写入或 fsync 已完成。** |
| probe 未退出也可能进入清理 | **普通返回场景明显改善，但仍有验票缺口，见下文。** 现在要求 `{ exited: true, code: 0..255整数 }`；已退出非零码会清理并失败，调用抛错或普通无效回执会保留实例。 |
| 合法 loopback 端口发生漂移仍通过 | **运行态清理前已部分覆盖。** 首次 running inspect 后保存端口，清理时仍 running 则比较；停止态及 post-stop 路径仍有遗漏。 |
| create 成功丢 ack 无恢复链路 | **未改变。** 仍不重试、不误删，但没有定位候选对象并重新证明归属的恢复流程。 |

## 仍需保留的具体 finding

### 1. 高：probe 的“同步退出回执”验证尚未完全 fail-closed

位置：`instance-lifecycle.mjs:48–55,61`

有两条静态可见的遗漏：

- **不再显式拒绝 thenable。** 普通 Promise 因缺少退出字段会被拒绝，但一个同时带有 `exited: true`、整数 `code` 的 Promise/thenable 会通过当前条件。因此仍不能说严格执行了“只接受同步回执”的契约。
- **回执读取异常没有撤销清理许可。** 内层 try 只包住 `runProbe(id)`。若返回对象的 `exited` 或 `code` getter 抛错，异常进入外层 catch，而 `trusted` 仍为 true；finally 可能在重新核验容器后 stop/remove，尽管退出回执未验证完成。

应将“容器归属可信”和“probe 已确认退出”分开控制；进入 probe 前撤销后者，只有完整验证回执后才恢复。即便如此，回执仍只是可信 adapter 的声明，不能自行证明真实进程及其子进程已经结束。

### 2. 中：port drift 仅覆盖清理时仍 running 的分支

位置：`instance-lifecycle.mjs:66–73`、`instance-ownership.mjs:71–94`

以下情况仍可通过：

- 清理前已是 stopped/exited，仍报告另一个合法 loopback binding；
- stop 后的 inspect 报告另一个合法 loopback binding；
- requested HostPort 从动态值变为合法固定值，而实际端口仍匹配。

当前比较只在 `mode === 'running'` 时执行。停止态端口正常清空应允许，但**若仍报告 binding，应核对已固定的端口**。此外 ownership 仍接受固定非零 requested HostPort，不能宣称已强制动态分配。

### 3. 未关闭：操作安全的真实信任根仍不存在

冻结 snapshot 修复的是**比较基准漂移**，不是来源可信：

- image 仍只验证为 64 位 hex，没有固定批准镜像；
- engine 仍是注入对象，没有实际固定本地引擎、固定 argv、普通非 force stop/remove 的实现可审；
- 环境值是否来自固定镜像及显式 create，而不是抄录待验证 inspect，仍需可信调用层保证。

不能将字段匹配升级为真实操作安全证明。

### 4. 未关闭：持久化、absence 与 secret 的端到端保证

- **record**：严格 `true` 是新增且有效的 API 门槛，但 fake record 只是 push 到内存数组后返回 true，不能证明完整写入、fsync 或崩溃后证据可恢复。
- **exists**：仍正确要求完整 ID 和名称都严格为 false；未知值或抛错不算 absence。但没有 adapter，不能证明 false 仅代表明确 not-found，而不是失联、权限或解析错误。
- **secret**：冻结 env 避免了原先“凭据变化但 scrub 仍使用旧密码”的问题；事件仍未直接序列化整个 target。但 engine 收到明文凭据，是否进入 argv、日志、诊断输出，仍无实现可审。有限字符串替换不是全面脱敏证明。

## inspect、state 与资源保留

此前保守行为仍在：

- ownership mismatch 阻止清理；
- 清理前重新 inspect，stop 后再次验证 stopped；
- stop 失败不继续 remove，remove 失败不报成功；
- probe 抛错或普通无效退出回执时，不 stop/remove，保留资源。

post-start inspect 抛错时，`trusted` 仍可能保持 true，finally 会再次 inspect；只有重新核验通过才清理，且原错误仍使运行失败。**这不是直接误删，但该恢复策略及各检查点失联仍缺测试覆盖。**

## 测试证据边界

新增测试源码覆盖了异步/false intent ack、原 target 名称变更、无效时间窗、危险 env、运行态端口漂移、已退出失败及未确认退出时保留实例。

尚缺上述 thenable/回执读取异常、停止态端口漂移、嵌套 env 变更、后续事件 ack 失败、各阶段 inspect 失联等覆盖。fake inspect 与单一 exists 布尔模型的限制也仍在。

**本次未运行这些测试，不确认 GREEN、RED→GREEN 或变异有效性。当前改进可收窄若干原 finding，但不能替代真实 adapter 审查、持久化证据、进程等待证明或引擎 absence 证明；原 BLOCK、CI gate 与既有授权边界均保持不变。**
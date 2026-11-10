## 结论

**该草稿尚不足以通过“安全实例生命周期”验收，应继续保持 BLOCK。** 当前可确认的是 fake-I/O 控制流程与归属字段检查，不是真实引擎操作安全、落盘可靠性或清理完成的证明。**本审查不授予任何容器操作授权。**

### 输入与范围

先行计算的四个文件 **raw-byte SHA-256 全部与给定值一致**：

| `../multica/scripts/aifi45-db/` 下文件 | 结果 |
|---|---|
| `instance-lifecycle.mjs` | 一致：`3cfdbf97…9b4e035` |
| `instance-lifecycle.test.mjs` | 一致：`df7a912b…be9d19e` |
| `instance-ownership.mjs` | 一致：`d1f64caf…b38f81c` |
| `instance-ownership.test.mjs` | 一致：`c692885d…a26b13` |

已完整阅读计划：
`projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/ci-disposable-db-implementation-plan-20261028.md`。

没有执行 DB、容器、项目测试，也没有修改文件。以下均为静态审查结论。

## 主要问题

### 1. 高：归属字段一致，不等于操作安全的信任根成立

位置：`instance-lifecycle.mjs:20–28`、`instance-ownership.mjs:8–11,43–55`

- `engine` 和 `target` 均来自调用者，没有固定本地引擎、固定镜像或固定 create 参数的实现。
- `engine.create(target)` 获得可变原对象，后续检查再次读取同一个 `target`。调用层或回调若改变名称、镜像、环境、时间窗，比较基准也随之改变。
- `expectedEnv` 只要求几个必要键，其余键由调用者决定。因此若调用者将 `POSTGRES_HOST_AUTH_METHOD=trust` 同时放进 expected 和 observed，当前检查会接受；现有测试只覆盖“仅 observed 多出该键”。
- 时间窗和完整环境校验发生在 create **之后**，无效意图也可能先产生资源。

**所需边界**：可信调用层生成独立、不可变的意图快照；环境允许列表来自固定镜像及显式创建参数；固定引擎、argv、凭据传递方式需要单独审查。不能用此断言函数替代这些前提。

### 2. 高：`record` 不保证同步完成，更不能证明意图已落盘

位置：`instance-lifecycle.mjs:18,26–28,33,62–63`

`event()` 直接返回 `record()` 的结果，但所有调用都忽略结果：

- 异步 record 尚未写入、甚至稍后拒绝时，create 仍会发生。
- record 返回 `false` 也被当作完成。
- 最终 `cleaned` 记录异步失败，函数仍可能返回成功。

同步抛错的 intent 测试只证明“同步异常阻止 create”，不证明“意图落盘后才 create”。当前没有 journal adapter，无法核实完整写入、持久化及写入失败传播。

### 3. 中：create 成功丢 ack 的处理保守，但恢复链路缺失

位置：`instance-lifecycle.mjs:28–34,48`；对应 lost-ack 测试

create 抛错或返回畸形 ID 后，`id` 不可用，最终不会 inspect、stop 或 remove。**不重试 create、不凭名称直接删，是正确的保守行为。**

但尚无按已记录意图定位候选对象、取得完整 ID、核验归属后收尾的路径；只能留下 unresolved 状态等待后续人工处理。现有测试验证的是“不误删”，不是“丢 ack 后可安全恢复”。任务 1 的相关能力不能据此记为完成。

### 4. 高：同步 probe 返回，不足以证明子进程已经结束

位置：`instance-lifecycle.mjs:38–41,48–58`

只识别 thenable，不能识别“同步返回 ChildProcess/句柄、实际工作仍在运行”的情况。probe 返回 `false` 或 `{ exit: 1 }` 也不会被解释为失败，除非调用契约要求其抛错。

因此目前不能证明计划要求的“结束并等待本次子进程后再清理”。需要明确且可验证的 probe 完成/失败契约；不能把非 Promise 返回值等同于进程已退出。

### 5. 中：inspect 重新校验存在，但未固定运行期观察结果

位置：`instance-lifecycle.mjs:34–37,50–56`、`instance-ownership.mjs:56–84`

动态申请端口时，只检查“当前仍为合法 loopback 端口”，没有固定首次运行 inspect 得到的端口。后续从 `39421` 改成另一个合法 loopback 端口仍会通过。请求端口也接受固定非零值，不能据此证明计划中的“动态分配”。

inspect 错误需准确区分：

- 返回身份不匹配对象会令 `trusted=false`，阻断后续清理。
- post-start inspect **抛错**时，调用尚未进入 `check()`，`trusted` 仍可能为 true；finally 会再 inspect，只有新检查通过才清理，原错误仍导致失败。

后一分支不等于“未核验就删除”，但其重验策略和各检查点失联场景尚无测试覆盖，不应笼统宣称全部 uncertainty 已被验证。

### 6. 中：secret 保护有局部措施，尚无端到端保证

位置：`instance-lifecycle.mjs:5–15,26–28`、`instance-ownership.mjs:43–55`

正面事实：正常事件没有直接序列化整个 target；错误消息尝试替换原始密码及若干 URL/form 编码。

限制：

- 完整含密 target 交给 engine，engine 是否把它写入 argv、日志或错误，没有实现可审。
- target 可变，而 scrub 只捕获最初的密码，后续凭据变化不受其覆盖。
- 替换有限表示形式不能证明任意引擎诊断输出都不泄密。

现有密码测试只能支持其中固定错误字符串的脱敏断言。

## state、stop/remove 与 exists：哪些处理是正确的

`instance-lifecycle.mjs:50–61` 有明确的保守控制：

- 清理前重新核验；running 才 stop，随后要求 stopped 再 remove。
- created/stopped 可直接进入 remove；未知或不一致状态会被 ownership 检查拒绝。
- stop 抛错不继续 remove；remove 抛错不会报成功。
- ID 与名称必须**都严格返回 `false`**；`undefined`、Promise、其他值以及抛错都不能证明缺席。

但这些结论限于抽象调用流程。**没有实际 adapter，不能证明 stop/remove 是普通非 force 操作，也不能证明 `exists(false)` 仅代表明确 not-found，而非把失联、权限错误或解析失败折叠成 false。**

## 测试掩盖与实际接线状态

fake engine 自己生成与断言完全吻合的 inspect，且用一个布尔值同时表示 ID 和名称是否存在。这掩盖了真实 inspect 格式、独立名称状态及引擎错误分类。还缺少异步 record、target 变更、各阶段 inspect 抛错、合法端口漂移、probe 未退出等关键场景。**本次没有运行测试，也没有 RED→GREEN 或变异运行证据。**

目录中确有旧 `run.mjs`，但读取确认它仍是 pinned 保全实例内的 disposable-DB runner，**没有接入这两个生命周期模块，也不是新独占实例入口**。

因此不能将本草稿视为真实生命周期、provisioner、CI 路径或安全清理已验证；CI BLOCK、既有 verdict 与 Gate 3 均不应因此改变。
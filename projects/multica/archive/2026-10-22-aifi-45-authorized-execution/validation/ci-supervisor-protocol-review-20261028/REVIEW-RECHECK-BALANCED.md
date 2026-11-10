## 复跑结果

仅运行 `supervisor-protocol.test.mjs`：`node --test --test-timeout=30000`。Node v24.15.0；退出码 **0**；共 **21** 项，通过 **21**、失败 **0**、skip **0**、取消 **0**、todo **0**。未运行 DB、容器或真实被监督进程。

运行前后 raw SHA-256 一致：

| 文件 | SHA-256 |
|---|---|
| `scripts/aifi45-db/supervisor-protocol.mjs` | `bed82664f2f17918b47302a94255e3061cbce9f516f578a074a997671b75452c` |
| `scripts/aifi45-db/supervisor-protocol.test.mjs` | `98c1b388a6818821a3120d2953f631196872e9c35bf9344b5e2ab7f72266aa6c` |

## 旧缺口复核

- **非 Buffer 的 `length` getter：已针对性修正。** `:149-157` 用计数器断言读取次数为零；即使 decoder 吞掉异常，也不能掩盖一次读取。新增的伪造 Buffer 属性测试还检查实际 view、offset、backing 和共享内存判断。
- **捕获输出：仅部分修正。** `:249-267` 不再保存写入内容，断言失败时不会因展示捕获数组而回显 canary；本次输出也未回显。但五次调用仍未断言各自返回值，且只拦截当前 `stdout.write`/`stderr.write`，未覆盖缓存写函数、底层写入或异步写入。源码静态检查未发现输出操作。
- **错误类别假绿仍在。** `:270-286` 将各输入的实际错误码与一个共同集合比较，再以该实际码验证结果形状；不同错误码之间串换仍可能通过该测试。其他测试对各错误类别有独立精确断言。

## Remaining

- `:158` 只断言 proxy trap 次数是安全整数，**零次也通过**；`:160` 的抛错 trap 也没有调用计数，不能单凭该负例证明异常分支实际命中。非 Buffer `length` 计数器不证明所有 Buffer 自有 getter 均未被访问。
- 返回契约已从旧版的 `ok` 改为冻结、null-prototype 的 `decoded` 结果；`decoded: true` 只表示协议解码成功。调用方兼容性未在本次测试中验证。
- 仍是完整缓冲解析，不提供流式收集限制、来源认证、真实进程树或 OS 退出证明；多错误优先级也未穷尽。未做插桩或变异测试。

旧归档未覆盖，raw SHA-256 仍为 `4d3fa81f8182768524703122b03b52bfa7806cfcd8ba44d025b6fccd6e0fa2e7`。

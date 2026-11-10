# Current resource bindings — independent strong static review

## 结论与 provenance

**INCOMPLETE；不签 PASS、不签全局 C1、不签生产准入。** 本次因会话轮次上限结束，已追到真实路由和认证、handler 内事务与 SDK 校验，但未完成生产 Handler 构造器的 TxStarter 赋值追踪、第三组回归测试定位及全部错误分支穷尽。下面的已确认问题为源码静态推导，不声称动态复现。

评审模式：只读源码/记录，不连接 DB、不运行测试、不启动子代理、不改源；唯一写入为本报告，以 exclusive-create (`open(..., 'x')`，对应 wx) 创建。末尾 SHA 由本次本地只读文件哈希计算，不仅转录 manifest。未执行模型切换或另起评审；按委托的 configured strong = OpenAIPersonal/gpt-6.1-sol/high，actual 后端模型没有回执，**unknown**，不得将配置当实际模型证明。

范围仅本轮 `GetDaemonWorkspaceRepos` 的 project 查询分支、两个 omitempty 字段、新 SDK 方法及新增测试；旧 AIFI 修改不是本次重新验收对象。数据库 runner、旧 claim 锁序、任务准入、宿主隔离不在本次签署范围。

## 已确认 Finding

### F1 — P2：SDK 大小写别名覆盖允许通过语义重复的当前集合

位置：`server/internal/daemon/client.go:1174–1186`；依赖 `server/internal/governance/execution_authorization.go:449–508`。

新方法先调用 `ValidateExecutionJSON`，其 scanner 以 JSON 字段原名作为 seen-map 键；然后 `json.Unmarshal` 到 struct。Go struct 解码会不区分大小写匹配 JSON tag，故两个阶段使用不同的字段等价关系。

可触发输入（W/P 为请求的规范 UUID）：

```json
{"workspace_id":"W","project_id":"P","project_resource_bindings":[{"resource_id":"invalid"}],"PROJECT_RESOURCE_BINDINGS":[]}
```

scanner 看见不同键，不拒绝；struct 解码先得到非法集合，随后被大写别名覆盖成非 nil 的空 slice。顶层 scope 检查通过，循环没有元素，方法返回空集合且 error=nil。甚至仅提供 `PROJECT_RESOURCE_BINDINGS:[]` 而缺少合同精确字段名，也会被当作字段存在。类似覆盖可发生于 workspace/project 和 descriptor 字段。

影响是当前集合存在性/歧义拒绝边界不严，非法 canonical 集合被静默丢弃；不能据此宣称跨 workspace 读取、攻破 TLS 或开放消费。触发者必须能供应该响应（例如错误/非规范服务响应或测试 transport）。现有真实服务输出不会自行产生大小写别名。

建议：对已知合同字段精确取键并解码，或显式拒绝与这些字段大小写折叠冲突的别名；不要为了兼容旧字段而让同一逻辑字段被后者覆盖。保留允许未知增量字段的兼容策略，但不应让未知字段实际修改已知字段。添加上述响应及 descriptor/顶层 scope 别名用例。现有 duplicate 两例只覆盖完全相同的键，不能发现此问题。

## 非确证建议 / 未验证项（不是另报已确认安全漏洞）

- HTTP 测试缺少真实 PAT/JWT/cloud-PAT 对显式 query 的拒绝、跨 workspace **path**、单键重复/空/畸形 query、whitespace daemon ID、unsupported 类型跳过、非法 local identity 以及混杂 workspace resource 行的直接断言。代码中的 auth-path 检查和双 scope SQL 支持这些边界，但这不等于测试已验证。
- `r.URL.Query()` 会丢弃 ParseQuery 错误；例如带非法 percent/未转义分号的 project pair 可被丢弃并进入 legacy 分支。现有 SDK 正确构造 query 且会拒绝缺失新字段，因此未把它定性为新 metadata 越权；建议明确解析错误应返回 400，并补公开 HTTP 回归，避免错误 project 请求表现成 legacy 成功。
- SDK fake 用例未覆盖非规范 request UUID、初始 remote plaintext URL、无效 UTF-8、大小写别名、未知 resource type、非法 descriptor UUID、local identity、base64 换行/非规范尾位、恰好 1 MiB 与读中途失败。源码显示重算后整 struct 比较能挡住非规范 base64/identity 的多类变化；未动态确认。
- 同快照一致性当前主要由语句接线证明，测试是串行变更后重新读取，未证实在读中途并发重绑仍无混合快照；未运行任何并发/DB 验证。
- 成功响应仍携带 legacy repos/settings；不应把“descriptor 不含 secret”写成整个响应全面脱敏保证。本次未审计所有 workspace settings 的存储内容与 legacy 暴露策略，不将旧行为误报为新增泄露。

## 已实际追踪的实现事实

1. `cmd/server/router.go` 的 NewRouterWithOptions 使用 `handler.New(...)`，`/api/daemon` 组挂真实 `middleware.DaemonAuth(...)`，repos GET 指向本 handler（约 414–459、1646–1669）。尚未继续读 `handler.New` 证明 TxStarter 注入，故生产可用性结论留空。
2. `middleware/daemon_auth.go` 已完整阅读：mdt hash 经 DB `GetDaemonTokenByHash` 或既有身份缓存恢复 workspace/daemon；私有 context key 存 auth path。PAT/JWT/cloud-PAT 标记各自 path，不从 X-Daemon-ID/X-Workspace-ID 生成 mdt context。测试用 WithDaemonContext 不等于公网可伪造 header。`daemon_token.sql` 确认过期筛选。本次未重新审计缓存撤销。
3. `daemon.go:57–85,912–1004`：显式 query 先要求 daemon-token auth path 与 trim 非空 daemon ID，再与认证 workspace 精确比 path；项目参数仅一个；Begin 后先 SET REPEATABLE READ READ ONLY；同一个 WithTx 查询 workspace、GetProjectInWorkspace、ListProjectResourcesInWorkspace。scope SQL 同时过滤 workspace 和 project。无写操作，defer Rollback 释放只读事务不是漏提交写事务。
4. 支持类型用既有 constructor，坏身份统一 409、不回显 ref/error；不支持类型跳过。`make(...,0,...)` 加 slice 指针保证空 [] 不被 omitempty 省略。legacy 无 query 路径不主动填两个新字段。SDK 旧四字段 struct 和旧 GetWorkspaceRepos 在已读代码中保留。
5. SDK 新方法做 canonical UUID、初始 URL guard、token/identity/workspace header、复制 http.Client 后禁 redirect、非 200 失败、1 MiB+1 有界读取、完整 JSON scanner、scope/集合检查、重复 resource ID、base64 解码、constructor 重算及六字段 struct 比较。未使用缓存/heartbeat fallback。初始 URL guard 为既有 helper；未把它等同于远端 identity pinning。
6. 本轮方法只返回元数据；已读新增路径没有 claim、nonce 签发、receipt/activation 或预算写入。不能将其直接用于准入，不能解除 EXECUTION_CONSUMPTION_REQUIRED；本轮不要求按资源漂移使历史 head 无效。

## 测试证据口径

完整静态阅读两个新测试文件。governance harness 自建 Chi 路由，真实 DaemonAuth + DB token lookup + 公开 handler，含真实 SDK 贯通；不是直接注入角色/context，但也不是生产 NewRouter 的启动测试。SDK 文件使用 httptest HTTP 服务，不是纯 parser 单测。

只阅读作者已存在 meta：matrix-green1 为 run/pass 11/11、10 leaf；sdk-green1 为 21/21、20 leaf；较早 green1 为 1/1，不把它当另一整套独立覆盖。未重跑、未验证日志/DB 残留陈述、未获得本轮 balanced 独立回归结果；第三组待核。上述数字不是49TC，业务5major/0TC口径不变。

## 实际 read 范围

- 完整：业务根 CLAUDE.md、AGENTS.md；指定 plan.md/source-manifest.json；两个新增 execution_current_resource_binding_test.go；protocol/project_resource_binding.go；middleware/daemon_auth.go。
- wire 唯一源：`C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/tools/changes/2026-10-22-aifi-45-authorized-execution/wire-contract.md`，实际阅读 §2.1、§3、§3.1–3.3、§4（62行起至 EOF），非整个 wire 文件。
- 部分：handler/daemon.go 1–105、220–304、912–1056；daemon/client.go 1–270、1120–1229；daemon/crevents.go 100–199；governance/execution_authorization.go 420–579。
- grep 接线：cmd/server/router.go 的构造及 daemon 注册；pkg/db/queries 下相关 workspace/project/project_resource/daemon_token SQL。未完整读 router 或全部 SQL/生成器实现；server 下 AGENTS.md glob 未发现嵌套文件。
- 三份作者 meta：green1、matrix-green1、sdk-green1。未读 DB 快照/approval 内容，未连接 DB。
- manifest 的其余六文件只见清单；不声称完整阅读或审计11文件。归档副本未逐文件比对；以下是工作树所读核心五文件与冻结 manifest 的哈希比对。

## 本次实算源码 SHA-256

| 文件（相对业务根） | raw SHA-256 | CRLF→LF SHA-256 | 对冻结 manifest |
|---|---|---|---|
| `server/internal/handler/daemon.go` | `708e840a8797459430ebef3bd015f25636bfa76ea5c10a6d3f7ba887f8aa8577` | `708e840a8797459430ebef3bd015f25636bfa76ea5c10a6d3f7ba887f8aa8577` | MATCH |
| `server/internal/daemon/client.go` | `d85a35e5c817eff108a4da4be74f1c7ca1b45719f476cf20febdce723d4cc521` | `d85a35e5c817eff108a4da4be74f1c7ca1b45719f476cf20febdce723d4cc521` | MATCH |
| `server/internal/governance/execution_current_resource_binding_test.go` | `7a86a7a8de383fb2b77684b5868b7ee23d9c0453ce61babc9934413f9a84ae78` | `7a86a7a8de383fb2b77684b5868b7ee23d9c0453ce61babc9934413f9a84ae78` | MATCH |
| `server/internal/daemon/execution_current_resource_binding_test.go` | `3381811b2f5ab25b892e03b51861ca480205a83d600e7b78ac64022138ee019f` | `3381811b2f5ab25b892e03b51861ca480205a83d600e7b78ac64022138ee019f` | MATCH |
| `server/pkg/protocol/project_resource_binding.go` | `54d500179399567302c3855ebb716b465ed8d29c26fe5567d4a46dcdbf0d0e93` | `54d500179399567302c3855ebb716b465ed8d29c26fe5567d4a46dcdbf0d0e93` | MATCH |

以上 MATCH 仅表示本次取 hash 时的五份字节匹配指定 manifest；不证明其余源码无变更，也不替代运行证据。报告未评审旧 claim 锁序、全局 C1 或生产准入。

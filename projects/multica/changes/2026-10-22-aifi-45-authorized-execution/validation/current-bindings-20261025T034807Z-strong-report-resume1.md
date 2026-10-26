# Strong review — resume 1 / two core functions

## 文档关系和结论

本片接续既有 `current-bindings-20261025T034807Z-strong-report.md`，不是重新启动评审。主报告已于上一片以 exclusive-create / wx 实际落盘；本片不覆盖它。本续片同样以 wx 独占创建，补齐原报告中生产 TxStarter / WithTx 的接线缺口。主报告仍保留当时的 INCOMPLETE 状态和实际范围；涉及该缺口的事实以本续片为准。

**结论：两个新增核心路径静态核查已完成至下述边界；保留一项确证 P2，未确认第二项 bug。整体仍为 INCOMPLETE，不作 PASS 或全局 C1 签署。** 没有因六轮截停而把未读项判成通过。无 DB 访问、无测试执行、无子代理/委派、无源文件修改。唯一写操作为评审记录；本地 Python 仅作报告独占创建与只读 SHA 计算。

配置 provenance 沿用委托已核的 strong OpenAIPersonal/gpt-6.1-sol/high，未重读/重查模型配置；实际后端型号无回执，actual=unknown。不以配置替代实际执行模型证明。

## 已确认 F1 / P2：JSON 精确键检查与 struct 的大小写折叠不一致

位置：`server/internal/daemon/client.go:1174–1186`，相关检查在 1187–1213；scanner 实现在 `internal/governance/execution_authorization.go:449–508`。

触发条件：响应供应方返回以下单文档 JSON（W、P 替换为本次请求的规范 UUID；不需要合法 descriptor）：

```json
{"workspace_id":"W","project_id":"P","project_resource_bindings":[{"resource_id":"invalid"}],"PROJECT_RESOURCE_BINDINGS":[]}
```

确证链：

1. scanner 的 `seen[key]` 按原键字符串比较，两个集合键不同，所以通过；无无效 UTF-8、重复原名或第二文档。
2. `json.Unmarshal` 到带 JSON tag 的 struct 时，对键作大小写不敏感匹配。后置大写键覆盖先前集合；pointer 最终指向非 nil 的空 slice。
3. workspace/project 匹配，集合非 nil，descriptor 循环零次，返回空集合且 error=nil；原本必须失败的非法 descriptor 被静默丢弃。仅有大写集合键、缺合同精确小写键的响应也可被接受。

这是 Go 解码语义与已读源码的静态确证，**未运行复现**。影响是 metadata 响应存在性/歧义校验失效；不声称攻击者可直接改真实服务响应、跨租户、攻破 transport 或绕过准入。不能把“攻击者需要控制响应”误写成无需任何条件的公网攻击。

修复建议（只建议，不改源）：已知字段精确键名读取；或拒绝与这些已知键大小写折叠冲突的别名，同时可继续接受真正未知的增量字段。不要让所谓未知字段实际覆盖已知 scope/集合/descriptor 字段。增加上述非法集合被覆盖、缺小写集合键及 descriptor/scope 别名负例。已有两个 duplicate-key 测试都是相同原名，不能覆盖这一语义差异。

## 核心路径可复核结果

### Handler.GetDaemonWorkspaceRepos

- 已读 `daemon.go:912–1004`：只有 query 中出现 `project_id` 才走新分支；真实 DaemonAuth path 必须为 `DaemonAuthPathDaemonToken`，认证 daemon ID 经 TrimSpace 后非空。随后 `requireDaemonWorkspaceAccess` 比较 path workspace 和 context workspace；mdt 正常路径不采信 X-Workspace-ID/X-Daemon-ID/X-User-ID 所报身份。
- 已读完整 DaemonAuth：mdt 身份来自 hash 查询或既有 DB 派生身份缓存，私有 context key 写入 workspace/daemon/auth path；PAT/JWT/cloud-PAT 走各自标记。不能通过请求头自行写入 Go context；不得把测试 `WithDaemonContext` 当公网鉴权。缓存有效期/撤销不是本片新实现，也不代表本次 fresh attestation。
- 参数只能一个，parseUUIDOrBadRequest 的调用后均立即处理 ok；认证先于项目查询，foreign path 不先探测项目。helper 本身的完整实现本片未另读，不扩张其输入接受性结论。
- `Begin` 成功后先 `SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY`，再 `q := h.Queries.WithTx(tx)`，三次读取都用 q，不混用池级 h.Queries。已新读 `pkg/db/generated/db.go:1–32`：WithTx 返回 db=tx 的 Queries，无暗中回落池。SQL 已见 workspace GetWorkspace、项目 ID+workspace 条件、资源 project+workspace 双条件。
- 生产可达性补核：上一片已见 router 的 pool→`handler.New(queries,pool,...)`、DaemonAuth 组及 repos handler 注册；本片新读 `handler/handler.go:436–553` 的完整 New，503 行保存 `TxStarter:txStarter`，返回前无覆盖。因此正常 NewRouter 注入不会使新分支恒因 TxStarter nil 返回500。手工构造且不填 TxStarter 的 handler 仍按新分支设计返回500，不是生产漏接。
- 支持资源只调用既有 NewProjectResourceBinding，合法身份输出六字段 descriptor；不支持类型跳过。constructor 错误统一409，不把 raw ref 或具体 secret 放进该错误。输出继承的 legacy repos/settings 仍需按旧接口暴露策略理解，不能笼统说整个响应绝无 secret。
- 空集合使用 make 非 nil slice 加指针，产生 `[]`；legacy 无 query 不填两个 omitempty 字段。资源顺序不是授权事实。只读事务 defer Rollback 合理，不能误报“没 Commit 所以读无效”；所有输出前读取已完成，但不承诺响应发出后资源持续不变。

### Client.GetProjectResourceBindings

- canonical UUID 参数校验先于网络；path/query 由校验后的 UUID 构造。身份 token/header 来自现有 Client，workspace header 按本次参数单独设置，不使用全局 workspace 缓存。
- 初始 URL 使用既有 validateTrustedServerURL，拒远端明文；该 guard 是配置源传输策略，不是独立服务器 pinning 或 freshness。它还允许 ws/wss，但 http.Client 标准 transport 不会因此成功做 WebSocket GET；不将 fail-closed 的请求错误误报成消费放行。
- 复制 http.Client 后本方法覆盖 CheckRedirect，所有 redirect 不跟随，3xx 经非200分支失败，不会把 token 带到 redirect target；不修改共享 client 的 redirect policy。正常网络/读失败向上传错，不 fallback 旧响应或 heartbeat。
- 只对200读取 body，最多1MiB+1；超限拒绝。scanner 检查完整文档、UTF-8 和每层精确重复键，但不等于 schema 精确键检查（F1）。非200只返回状态型 requestError，不回显服务端 body 中可能的 secret。
- 已知 scope 必须与参数精确相等；nil 集合（缺失/null）拒绝，空数组成功。重复 resource UUID 拒绝。base64 解码后复用同 constructor，六字段完整 struct 比较，规范 base64/identity 和 digest 任一变化都不能只靠自填 hash 过关。未知资源类型及非法 UUID 在 constructor 层拒绝。字段之外的未知增量内容目前忽略，不能把整 struct 比较说成验证任意附加 JSON 键。
- constructor 已在上一片完整阅读，所见仅提取约定身份：local 的 daemon_id/local_path/execution_mode，github 的 url/ref/default_branch_hint；不采 label/任意 ref metadata，不在此验证真实本地 inode/remote 可达性。这是合同定义的元数据，不缺这些事实就误报为完整 admission 未实现。

本片未发现新路径将数据接成 task claim、签名 binding、receipt、activation 或预算写入；**这不是对全仓“绝无其他消费接线”的穷尽证明**。元数据不得直接用于准入，EXECUTION_CONSUMPTION_REQUIRED 保持，历史 head 也不因资源漂移在本片被重新解释为无效。

## 范围、未读符号和下一片边界

本片不重读 AGENTS、模型配置、manifest 或两个测试文件。复用上一片已读的 core/DaemonAuth/constructor/scanner/transport helper 和路由上下文；只新增两个直接 helper 的阅读：

1. `pkg/db/generated/db.go` 完整（WithTx）。
2. `internal/handler/handler.go:436–660`，覆盖完整 New 及工具返回的 writeJSON/writeError/部分 UUID wrappers；其中 New 之外的 incidental 可见内容不算全面 handler 审计。

仍未读/未核：各 generated 查询方法的具体 Scan 与全部 DBTX 调用（已见其 SQL 条件，但未重开 generated project/workspace/resource 文件）；parseUUIDOrBadRequest 完整实现；缓存实现和撤销链；第三组独立 balanced 回归的具体结果；并发读中变更快照的动态行为；初始URL配置规范化的全部上游调用。两核心方法之外的新 SDK 真实业务 caller 未穷尽；不据此宣称它已接入消费或根本不可调用。

上一片已完整静态阅读两个新增测试文件，本片不重新逐行穷尽。HTTP 10 leaf、SDK 20 leaf 为作者记录口径；本片无新运行结果。具体未覆盖项仍是建议/待核，不升级成额外确证漏洞。若继续下一片，优先核 SDK F1 的精确回归与 generated query 直接接线/指定第三组结果；旧 claim 锁序交由独立评审，不扩大到全局C1。

## 本片实算 SHA-256

两核心文件与上一片已核冻结 SHA 再比较；依赖仅记录当前 hash，不冒充新增冻结清单。计算读取文件 bytes 不代表将整份依赖全部审阅。

| 文件（相对业务根） | raw SHA-256 | CRLF→LF SHA-256 | 说明 |
|---|---|---|---|
| `server/internal/handler/daemon.go` | `708e840a8797459430ebef3bd015f25636bfa76ea5c10a6d3f7ba887f8aa8577` | `708e840a8797459430ebef3bd015f25636bfa76ea5c10a6d3f7ba887f8aa8577` | MATCH |
| `server/internal/daemon/client.go` | `d85a35e5c817eff108a4da4be74f1c7ca1b45719f476cf20febdce723d4cc521` | `d85a35e5c817eff108a4da4be74f1c7ca1b45719f476cf20febdce723d4cc521` | MATCH |
| `server/pkg/db/generated/db.go` | `0c9302e79a855e76de414411e9c730a96b56c46782e65d19f7f4b919a7771799` | `0c9302e79a855e76de414411e9c730a96b56c46782e65d19f7f4b919a7771799` | dependency; no new freeze assertion |
| `server/internal/handler/handler.go` | `649efbf37fd426eb571d01ea1ae18334efbe085f27d689b34f1a8fb6f63087be` | `98959d74b9243ff718230d6eddbbd04d43a6270286c91c3e6e41b51c5df25d37` | dependency; no new freeze assertion |
| `server/internal/middleware/daemon_auth.go` | `2b1a7f534c6fd637ece96a29c14280b4f8615ba1e2fb5ed2dd5c2297eb275ca0` | `cddd1cb745c0377395f708931ffc8ecf0628a8c6d643bb9b3fcc32ef37b95395` | dependency; no new freeze assertion |
| `server/pkg/protocol/project_resource_binding.go` | `54d500179399567302c3855ebb716b465ed8d29c26fe5567d4a46dcdbf0d0e93` | `54d500179399567302c3855ebb716b465ed8d29c26fe5567d4a46dcdbf0d0e93` | dependency; no new freeze assertion |
| `server/internal/daemon/crevents.go` | `620b7646d55c60e13cdd7cce4f982ebf52c3d5bca737b854cc5be45ccf685715` | `620b7646d55c60e13cdd7cce4f982ebf52c3d5bca737b854cc5be45ccf685715` | dependency; no new freeze assertion |
| `server/internal/governance/execution_authorization.go` | `0c68aca15dd2a57e8a407e5f76a98df264ceec52b31a38433a618cf4ba96a074` | `0c68aca15dd2a57e8a407e5f76a98df264ceec52b31a38433a618cf4ba96a074` | dependency; no new freeze assertion |

续片创建前既有主报告 SHA-256：`d7f4ed71b1b4517fc65909f252be2ca04ee083792d42017ada88c2fdf07722fa`。原报告不覆盖、不改写；不存在用新结论追改原始 provenance 的操作。

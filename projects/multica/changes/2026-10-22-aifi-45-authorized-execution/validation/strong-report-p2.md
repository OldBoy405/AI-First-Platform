# Strong 限定静态复核：P2 修复与 current-resource metadata

## 判定

**原 F1/P2：CLOSED（静态复核确认修复）。** 对本次限定的 `Handler.GetDaemonWorkspaceRepos` 新 project 分支、响应两个增量字段、`Client.GetProjectResourceBindings` 及所需真实认证/事务/descriptor/transport 接线，**静态代码评审完成；没有剩余确证 finding**。此判定不是“穷尽全仓后 PASS”，也不因未做动态 race 或未重读所有旧测试而泛化成整个代码 scope INCOMPLETE。

当前冻结依据：`current-bindings-20261025T034807Z-p2-source-manifest.json`，stage 为 pre P2 GREEN and final independent regression。本次实算工作树全部11项 raw/LF SHA及长度均匹配新冻结。相对已读旧清单，变化仅 client.go 和 daemon 的新测试文件；另9项相同。原报告及 resume1 不改写；本报告更新其 P2 状态并补齐 generated 查询和直接调用点的有限缺口。

边界：不签全局 AIFI-45 C1、不评旧 claim 锁序、不批准生产准入、不把 metadata 当 fresh attestation、claim 或 receipt/activation，不解除 EXECUTION_CONSUMPTION_REQUIRED，不把资源漂移解释成历史 head 自动失效。未访问 DB、未运行测试、未启动子代理、未改产品或测试源码。只独占创建本报告（Python open mode x，对应 wx）并只读计算哈希。

模型 provenance 沿用本轮宿主原生回读：schema1/configured strong OpenAIPersonal/gpt-6.1-sol/high；未重查配置、未切换/另起模型。actual 无后端回执，unknown，不能以 configured 冒充实际型号。

## P2 关闭依据及同源 alias 路径

位置：`server/internal/daemon/client.go:1174–1235`，核心修复在 scanner 后的精确键提取和 descriptor 键检查。

### 1. 顶层 scope 和集合

现在先解码为 `map[string]json.RawMessage`，只取精确的 `workspace_id`、`project_id`、`project_resource_bindings`。不再把顶层响应解码成会折叠大小写的 struct：

- canonical 坏 bindings + 后置 `PROJECT_RESOURCE_BINDINGS:[]`：仍读取坏 canonical 集合，逐项重算会拒绝。
- canonical 错 workspace + 后置正确 `WORKSPACE_ID`：仍比较 canonical 错 scope，拒绝。
- 同理覆盖 project_id 的 alias 也无效。canonical 键缺失时 nil RawMessage 解码失败；scope 为 null 时字符串保持空，与非空请求 UUID 不符；集合缺失/null 均失败，精确 `[]` 仍返回非 nil 空 slice。
- 顶层 canonical 正确时，可以忽略另一个大小写 alias；这不是重新开放覆盖，而是按既有响应增量兼容策略忽略未知键。不能把“必须拒绝所有额外顶层键”当作本次合同未要求的新约束。

### 2. descriptor 六字段

每项先读 RawMessage map，要求恰好六键，并逐一确认 `resource_id,workspace_id,project_id,resource_type,identity_b64,binding_digest` 的精确存在，然后才 typed decode。

- 六个 canonical 键外再附大写 digest/ID/scope alias：len=7，拒绝。
- 用 alias 替换 canonical 键以保持len=6：对应精确键缺失，拒绝。
- escaped JSON key 解码后若与 canonical 重复，既有 scanner 按解码后的键查重，不能靠不同转义拼写绕过。
- 这也挡住 Unicode 大小写折叠别名；任何非 exact key 不能占据六个 required key 中的一格。

### 3. identity_b64 内的同源问题

constructor 内仍有 struct 解码，但 SDK 并非只信其解析值：重构规范身份 JSON、base64 和 digest 后，要求完整六字段 `canonical == binding`。带 alias、额外字段、重复/非规范转义/字段次序等的 identity 原 bytes，只要与 constructor 规范输出不同，就不能满足 IdentityB64 精确相等；不能用自填新 digest 绕过该比较。base64 换行或其他非规范表示同样不能仅靠成功 DecodeString 通过。

结论：在本新方法从 HTTP body→精确顶层→精确六键descriptor→规范 identity 重算的路径内，**未发现仍可重现原 F1 覆盖效果的同源 alias 路径**。未将这一结论扩大成旧 DTO/getJSON 或全仓 JSON 解析器都已加固。

## 新增三个负例及现成运行证据

本轮定向静态读 `internal/daemon/execution_current_resource_binding_test.go:339–389`；以前已完整读过旧版本的其余测试和 helper，本次不重复。三个新增负例都通过真实 SDK 方法发 HTTP 请求，断言 err 非 nil：

1. canonical descriptor digest 被置零，后置大写集合 alias 空数组。
2. canonical 顶层 workspace 换成 foreign workspace，后置正确的大写 workspace alias；snapshot helper 的顶层 workspace 在 descriptor 前，所以替换目标确为顶层。
3. canonical digest 置零，再向同一 descriptor 增加正确的大写 digest alias。

已读作者 `sdk-red2.meta.json`、`sdk-green2.meta.json`，并定向核对对应 stdout JSONL 的三个失败断言/三条 leaf pass：

| 作者记录 | RUN/PASS/FAIL/SKIP | leaf | 静态核对的意义 |
|---|---|---|---|
| SDK-RED2 | 25/20/5/0 | 3新增leaf失败 | 三条具体输出都是SDK错误接受alias，不是编译失败/零匹配；5个test fail=3leaf+2父，另有包级fail事件不当额外TC |
| SDK-GREEN2 | 25/25/0/0 | 23 leaf pass | 三条新leaf均有对应pass |

这是读取既有证据，不是我独立重跑。meta 报原库不变、sessions/locks=0、owned resources清理完成；本次未连 DB 验证这些陈述，也未检查所有原库快照/清理事实。未重验 RED2 pre-run manifest 或源码归档的全部历史链，不以本次 hash 倒签 RED2 来源。新11项 freeze 已在本次实际比对，且其 stage 时间早于所读 GREEN2 meta。

## 真实 SQL / WithTx 接线补核

已补读源 SQL 与 generated 方法，排除“SQL scoped 但运行用另一份生成实现/池”的具体缺口：

- `pkg/db/queries/project.sql:8–10` 与 `pkg/db/generated/project.sql.go:103–135`：`WHERE id=$1 AND workspace_id=$2`；generated 的 QueryRow 用 `q.db`，参数顺序 ID、WorkspaceID；Scan 正确读取项目 ID/workspace。
- `pkg/db/queries/project_resource.sql:6–12` 与 `pkg/db/generated/project_resource.sql.go:277–319`：`WHERE project_id=$1 AND workspace_id=$2`；generated Query 用 `q.db`，参数顺序 ProjectID、WorkspaceID；扫描同序字段，检查 Query、Scan、rows.Err 错误，不吞读取失败当空集合。
- 顺带补读 `pkg/db/generated/workspace.sql.go:232–257`：GetWorkspace 的 QueryRow 也用 `q.db`，按 ID 查询并扫描 repos/settings，没有另外向池查询。
- 前片已完整读 `pkg/db/generated/db.go:1–32`，WithTx 返回 `&Queries{db:tx}`；本片不重复。结合已读 handler 的 `q:=h.Queries.WithTx(tx)`，三次读取确实同 tx。handler 在 Begin 后首个 tx SQL 是 `SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY`，此后所有 scope 与资源查询都用 q，无池级混入。
- 前片已核 router→handler.New→TxStarter=pool 的生产注入，本片未重复构造器。mdt Auth context/认证workspace比 path、非空trim daemon ID 的检查沿用已读且9项冻结未变的代码。读事务 defer Rollback 不需要 Commit 才能让读取结果有效；没有 metadata 写入。

同快照有真实静态接线依据；**没有**“我运行了并发快照测试”的结论。

## 直接 caller 和兼容/transport 范围

本片对 `server/**/*.go` 全范围精确符号搜索 `GetDaemonWorkspaceRepos|GetProjectResourceBindings`（未截断）：

- handler 生产调用点只见已读 `cmd/server/router.go:1668` 的真实 DaemonAuth 路由。另一注册点是已读 governance harness。另有旧 daemon_test.go 的 legacy 直接测试调用，不是未读生产接线；本次未扩大重审这些旧测试。
- SDK 新方法调用点只见新 daemon 测试与已读 governance 的真实SDK贯通测试；未发现生产消费 caller、隐藏新增 endpoint 或其他未读直接生产调用点。作为新增内部 SDK 读能力尚无业务消费接线，符合本片“不开放消费”，不是应补 admission 的缺陷。
- 此搜索结论限定本工作树 server Go 源码和直接符号引用，不声称验证任意外部仓/反射/二进制部署。

新 SDK 的 canonical 请求UUID、初始URL策略、复制client后禁任意redirect、非200失败、1MiB有界body、完整JSON scanner、scope/唯一ID/constructor六字段比较均保留。旧 WorkspaceReposResponse 四字段、GetWorkspaceRepos 和 getJSON 非本次修复目标；本次全文件hash确认冻结，未以扩大改造这些旧面来修 F1。handler 无 query 旧返回路径以及两个 omitempty 字段的兼容结论沿用前片已读代码。

## Finding 分类与未验证属性

- **已确认旧 Finding：F1/P2，关闭。** 上述静态修复和现成 RED→GREEN 对应。
- **新确证 Finding：无。** 限定代码 scope 没有待补读直接生产 caller / 两个指定generated query 的阻塞缺口；本报告不再仅因轮次/测试未穷尽把此代码 scope 标成 INCOMPLETE。
- **建议，不是缺陷或关闭条件**：可加 project_id alias、缺 canonical 键仅有alias、descriptor alias替换而非追加、identity 内alias的回归，防止以后取消exact gate或整struct比较时退化；本轮3例没有逐一动态覆盖这些变体，但静态拒绝链已说明。
- **动态属性未验证**：读中途并发删除/reparent/重绑时的快照表现、完整HTTP auth/error矩阵、独立balanced最终三组回归/清理事实。本片不访问 DB、不运行测试，不能用静态接线冒充动态证明。它们与“本次限定静态代码评审完成”并列，而非改写成全局通过。
- 旧报告提到 malformed query 的 ParseQuery 错误被legacy处理，是未升级的输入处理建议；未证明它可返回成功的新metadata或经SDK冒充当前集合，不当作仍未关闭的 P2。需要时另给专门HTTP异常参数测试，不借此扩到准入评审。

## 实际阅读范围与 provenance

本片新增阅读：新freeze全文；client.go:1135–1314（含完整新方法及邻接工具输出）；daemon新测试:339–389及定向grep；上述两个SQL源片段与三个generated方法；handler.go:697–713 UUID wrapper；server Go符号引用检索；SDK red2/green2两份meta及raw JSONL定向失败/pass行。未重读 AGENTS/模型配置/wire/handler.New/WithTx/旧manifest，均沿用前片已读上下文。前片已读 handler新分支、DaemonAuth、constructor、scanner、URL guard、SDK header/client构造及wire §3.3。

以下hash是本次只读全文件计算，不代表把列出的旧 service/task、claim测试和DB runner全部做了代码评审；归档副本未逐一比对。不覆盖/删除任何旧报告。

## 当前工作树 vs 新11项冻结：实算 SHA-256

| 文件（相对业务根） | raw SHA-256 | CRLF→LF SHA-256 | 长度及hash比对 |
|---|---|---|---|
| `server/internal/handler/daemon.go` | `708e840a8797459430ebef3bd015f25636bfa76ea5c10a6d3f7ba887f8aa8577` | `708e840a8797459430ebef3bd015f25636bfa76ea5c10a6d3f7ba887f8aa8577` | MATCH |
| `server/internal/daemon/client.go` | `bb13526940e87e86ccb32b4cb2602552fd71b07289e74d479232b677ca548ee1` | `bb13526940e87e86ccb32b4cb2602552fd71b07289e74d479232b677ca548ee1` | MATCH |
| `server/internal/governance/execution_current_resource_binding_test.go` | `7a86a7a8de383fb2b77684b5868b7ee23d9c0453ce61babc9934413f9a84ae78` | `7a86a7a8de383fb2b77684b5868b7ee23d9c0453ce61babc9934413f9a84ae78` | MATCH |
| `server/internal/daemon/execution_current_resource_binding_test.go` | `3c557a7961740a441acc074774390af1a5a5f5169c105a5250981353855799b9` | `3c557a7961740a441acc074774390af1a5a5f5169c105a5250981353855799b9` | MATCH |
| `server/internal/service/task.go` | `c5e543f880b907059ac1a02f6fda60b1e6e200703a0c70cc9efd967d0b57f118` | `c5e543f880b907059ac1a02f6fda60b1e6e200703a0c70cc9efd967d0b57f118` | MATCH |
| `server/internal/handler/daemon_start_claim_test.go` | `12f1061c455b923a1928f5c4d59e583d6723a93c4505f2f4d7f193fdda549a23` | `12f1061c455b923a1928f5c4d59e583d6723a93c4505f2f4d7f193fdda549a23` | MATCH |
| `server/internal/handler/handler_test.go` | `e910e128f94f0ea5a0783754133ad5333a6bc85a5d697cca3338801d1167c91b` | `e910e128f94f0ea5a0783754133ad5333a6bc85a5d697cca3338801d1167c91b` | MATCH |
| `server/internal/governance/execution_start_claim_test.go` | `44e9291b033eb754430f45faf8767c7af2446907e41ad646b9793997267be619` | `44e9291b033eb754430f45faf8767c7af2446907e41ad646b9793997267be619` | MATCH |
| `server/pkg/protocol/project_resource_binding.go` | `54d500179399567302c3855ebb716b465ed8d29c26fe5567d4a46dcdbf0d0e93` | `54d500179399567302c3855ebb716b465ed8d29c26fe5567d4a46dcdbf0d0e93` | MATCH |
| `scripts/aifi45-db/run.mjs` | `b4d70ae10ee5c0eabc51fc3cb897410ebfcee2816bdf097e93c147fc09a9df00` | `b4d70ae10ee5c0eabc51fc3cb897410ebfcee2816bdf097e93c147fc09a9df00` | MATCH |
| `scripts/aifi45-db/run.test.mjs` | `0c6b605388421acfbae73584b34f687d0221d2622e5c3e36ba11ef7de9ee8a79` | `0c6b605388421acfbae73584b34f687d0221d2622e5c3e36ba11ef7de9ee8a79` | MATCH |

本报告只关闭限定 P2 并完成所述静态代码范围；不是49TC或5major完成证明、全局C1签字、old claim锁序结论或生产激活授权。

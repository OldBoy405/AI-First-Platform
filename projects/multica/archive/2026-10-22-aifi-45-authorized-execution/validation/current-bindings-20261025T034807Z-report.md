# AIFI-45 当前 project 资源读面 — BUILD 子任务

## 当前结论

已实现既有 daemon workspace repos API 的显式 project 元数据读面与 SDK 新方法。独立 strong 发现的大小写键别名 P2 经3个真实失败 leaf→GREEN修复并关闭；限定静态代码评审完成、无剩余确证 finding，P2后非作者三组回归通过。**不是完整 claim/project、每 repo 本机事实或消费准入闭环，不关闭完整 TC/major，不推进 Gate 3。**

- 方向与边界：[实施计划](current-bindings-20261025T034807Z-plan.md)、[wire §3.3](../../../../tools/changes/2026-10-22-aifi-45-authorized-execution/wire-contract.md)。
- `GET /api/daemon/workspaces/{workspaceId}/repos?project_id=<UUID>`：只接受真实 DB-backed `mdt_` 认证路径与非空 daemon ID，path 必须匹配认证 workspace；同一 repeatable-read/read-only 事务查 workspace、该 workspace 内 project 及资源。空集合显式 `[]`，非法支持类型身份失败关闭，不返回新增资源字段的原始 `resource_ref`/秘密。
- SDK `Client.GetProjectResourceBindings`：请求 UUID、可信初始 URL、禁止重定向、1MiB body 上限、复用完整/UTF-8/重复键 JSON scanner；核响应 scope/集合存在/唯一 resource UUID/identity base64/六字段 descriptor 自洽。1MiB 是运输安全上限，不是业务资源条数上限。
- 没有 query 的旧 API 与旧 SDK `GetWorkspaceRepos`/四字段 DTO 不变；`/execution-authorization/head` 与历史/revoke 回读不因资源漂移失效。新增读面是当次 DB 快照元数据，不是签名新鲜度、task claim、受保护控制通道、目录/cloneability/进程或 activation 证明。
- 没有新增端点、表、迁移、生成 SQL、任意 nonce 签发、receipt/预算写入；`EXECUTION_CONSUMPTION_REQUIRED` 保持，未启动 Agent。

## 实际分工

| 角色 | 实际工作 | 会话 / 身份边界 |
|---|---|---|
| 主会话 | 计划、wire、服务端/客户端实现、作者测试及台账 | 普通产品实现，不另凑三档作者 |
| balanced 作者一 | 实际编写 governance 新文件：真实 mdt→HTTP、资源变化/跨租户/兼容边界、真实 SDK 贯通 | `01a1712c-a7d9-77b9-a3c5-0ee2ce56920b`；不 DB/不改产品 |
| balanced 作者二 | 实际编写 daemon 新文件：scope/descriptor/无旧服务降级/运输边界；另做旧 claim SQL/FK 事实调查 | `01a1712d-2ee1-77b9-a3c5-0ee4fc221846`；不 DB/不改产品 |
| 非作者 balanced | P2前后两轮各三组独立新库串行复跑；DB权已释放 | `01a17158-a034-77b9-a3c5-0eed780e9d5f` |
| 非作者 strong | 新读面限定静态完成/P2关闭；旧claim单独仍INCOMPLETE | 新读面 `01a17158-a01c-77b9-a3c5-0eea6fbcaf49`；旧 claim `01a16ea6-cece-77b9-a3c5-0ed3fe85bcac` |

派发前在两个业务根实际读取原生 `stdd config models --format json`，均 exit0/schema1/configured；见 `current-bindings-20261025T034807Z-review-{multica,tools}-models.json`。requested balanced=`Gobao/deepseek-flash/max`、strong=`OpenAIPersonal/gpt-6.1-sol/high`；没有后端实际模型回执，**actual=unknown**。

## 作者执行证据（各条独立新库；不累计为业务 TC）

以下文件均为同名前缀 `current-bindings-20261025T034807Z-<标签>.{meta.json,stdout.jsonl,stderr.log,events.jsonl,...}`，原始 stdout/stderr/失败未覆盖。

| 标签 | RUN / PASS / FAIL / SKIP | PASS leaf | 结论 |
|---|---|---:|---|
| `red1` | 1 / 0 / 1 / 0 | 0 | 旧公开 GET 返回200但 `project_id=nil`，真实行为 RED；不是编译失败 |
| `green1` | 1 / 1 / 0 / 0 | 1 | 最小服务端路径 GREEN |
| `sdk-red1` | 16 / 6 / 10 / 0 | 6 | 本轮新加的最小运输基线缺响应守卫，9个失败 leaf + 1失败父项；不是声称旧生产 SDK 存在这个新方法漏洞 |
| `sdk-green1` | 21 / 21 / 0 / 0 | 20 | scope/descriptor 与运输守卫 GREEN；fake HTTP 单元不单独证明真实认证/DB |
| `matrix-green1` | 11 / 11 / 0 / 0 | 10 | 真实 mdt→HTTP→DB；其中含真实 SDK→mdt→HTTP→DB 正例 |
| `sdk-red2` | 25 / 20 / 5 / 0 | 20 | 独立发现的P2：三个大小写别名覆盖失败leaf+两个失败父项；完整pre-run manifest已先存 |
| `sdk-green2` | 25 / 25 / 0 / 0 | 23 | 顶层canonical键精确提取、descriptor exact六键后再typed decode，P2根修 |

### P2后最终非作者回归

| 新标签（各自新库） | RUN / PASS / FAIL / SKIP | PASS leaf | 结果 |
|---|---|---:|---|
| `independent2-governance` | 828 / 828 / 0 / 0 | 749 | exit0，无SKIP |
| `independent2-handler` | 13 / 13 / 0 / 0 | 10 | exit0，无SKIP |
| `independent2-daemon` | 73 / 72 / 0 / 1 | 67 | exit0；唯一SKIP为Windows symlink权限 |

唯一SKIP `TestExecutionTrustRefusesLinkedRootInsideWorkspace`：`A required privilege is not held by the client`，未计PASS。见[实际独立报告](current-bindings-20261025T034807Z-independent2-report.md)。P2前 `independent-*` 的828/828、13/13、68P/1S仍原样保留，不追认为修后最终源码；父子/重复/两轮重叠不累计业务TC。

HTTP矩阵覆盖身份改变/label-position不改digest/reparent/删除/跨 workspace伪header/明确空集合/空daemon/旧无query响应/含秘密的非法URL拒绝。SDK另覆盖旧服务缺字段/null、错 scope、跨 scope条目、重复UUID、digest/identity篡改、503/失联、redirect目标零请求、超限body、第二JSON文档、重复键。

### 源码证据边界

- `preflight.json` 保存原库只读比对与实施前4项源码 hash；`balanced-writer-source.json` 是首个200行HTTP用例的运行前 hash。
- **中间若干作者命令未逐条在执行前另存完整源码 manifest。** SDK-RED1 的239行用例与最小运输实现有会话读写工具记录，但没有完整的 contemporaneous pre-run manifest，不能拿后来源码冒充它；后续transport用例也不是另一次声称的 RED。
- `source-manifest.json` 和 `source-archive/` 是作者首轮 GREEN 后、第一次独立回归前的11文件 raw/LF hash与原字节副本；不倒签为前面五条命令的 pre-run pin。正式独立每条已先另存实际源码 manifest，运行后核无漂移。
- P2新增负例先存 `sdk-red2-source-manifest.json` 再跑真RED；修后先存 `p2-source-manifest.json` / `p2-source-archive/` 再跑GREEN2与最终独立回归。相比前冻结包仅 `daemon/client.go` 与 `daemon/execution_current_resource_binding_test.go` 两项变，其他9项相同；独立三条各自pre-run raw/LF与该11项一致，宿主最终再次核同。
- `claim-lock-facts.md` 已由宿主核文件存在与 SHA；其调查没有签锁序安全 PASS。所有最终报告也已实际存在/hash核对，未把代理文件声明冒充实物。

## 数据库与权限边界

- 原库仍 HOLD；测试仅通过版本化 `multica/scripts/aifi45-db/run.mjs`，每条 schema-only 新数据库和受限 role，原数据不复制到测试库。
- 本轮开始的只读事务已与前轮最终只读证据完全一致：137表/6228行摘要、82审批 ID/整行 hash、session0/lock0。**82只是事故后现场；原83未恢复，missing41/extra40不抹去。**
- 上列每条作者命令的 meta 均 `original_unchanged=true`、`original_release={sessions:0,locks:0}`、`owned_resources_cleaned=true`；原行备份/全表内容摘要/精确 catalog 结果留在各条证据，不据 exit0 单独宣称安全。
- 非作者两轮分别独占DB权，主会话/strong未并跑；P2后已明确释放。宿主接回后只加一次 `REPEATABLE READ READ ONLY` 事务，复核本轮13条命令全部before/after与当前137表/6228行、82审批ID/hash共同一致，0锁/0其它session；本轮13对及前轮9对、共22对已知精确库/role在catalog均不存在。见 `final-readonly.json`，之后没有DB测试/SQL写入。

## 审核、台账及剩余项

- CUSTOM **#168 / M11=21** 登记本增量；没有把原 #166/#167 的事故/恢复历史改写成本轮结果。
- 新读面 strong：原F1/P2已关闭，限定核心及直接认证/事务/SQL/transport接线静态完成，无剩余确证finding；动态并发快照race未验证，不能用静态结论冒充它。实际报告名是 [strong-report-p2.md](strong-report-p2.md)，不是原先拟定的带前缀文件名；宿主已核实际13,258字节及SHA，没有伪造缺失路径。
- [旧claim strong](current-bindings-20261025T034807Z-old-claim-strong-report.md) 仍 **INCOMPLETE**，暂无确证新finding；未尽符号明确为agent/Builder rebind调用者、terminal settlement/system cleanup底层SQL、wakeup管理/注册事务。它不能被新读面静态完成或回归替代。该报告披露写工具无原子wx、创建前确认不存在；不将此声明升级为原子发布凭据。
- 主会话 `go vet ./internal/handler ./internal/service ./internal/governance ./internal/daemon` exit0（原始stdout/stderr/argv另存）；源码11项、四份binding/quality保护文件、两仓main/原HEAD/staged0核验无漂移。新项目Skill保存了当前读面与精确JSON键/逐条证据流程。
- 原生仍普通 BUILD/in_progress；完整业务 **0/49**，**5 major unresolved**。完整可信 claim/project、逐 repo 本机事实比较、隔离控制域、不可删 activation、legacy 新合同防降级、T消费事务与永久派发恢复继续待办。
- 无 Gate3、commit、push、部署、真实 CR 试点授权；本轮没有执行这些动作。全部切片完成后仍须真正 C1–C7，再请求人类 Gate3。

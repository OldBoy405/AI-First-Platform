# AIFI-45 授权内自治执行 — 规范轴只读评审（标准，不评需求）

对象：multica 仓 `server/internal/governance/{execution_binding_issue,execution_consumption,execution_activation,execution_authorization_routes}.go`、`server/internal/daemon/{execution_binding_client,execution_consumption_client,execution_binding_relay,execution_binding_endpoint}.go`、`server/migrations/643|644|645_*.up.sql`、`CUSTOM.md` #165–#177。
依据：`CLAUDE.md`→`AGENTS.md`（注释英文、不加 FK/级联、索引 CONCURRENTLY、workspace 查询带 workspace_id、sqlc、无冗余兼容开关）。

## A. 迁移与 DB 硬规则

1. `server/migrations/643_...up.sql:21-22` — **违规**：`CREATE INDEX cr_execution_binding_issue_scope_idx` 非 CONCURRENTLY，且与建表/函数/触发器同文件；AGENTS.md《Database and Migration Rules》要求每个索引 `CREATE [UNIQUE] INDEX CONCURRENTLY` 且**单独一条语句一个文件**。
2. `server/migrations/644_...up.sql:25-26` — **违规**：同上（非并发索引，并与建表同文件）。
3. `server/migrations/645_...up.sql:27-28` — **违规**：同上（非并发索引，且该文件已有多条 DDL）。
4. `643:5-19`、`644:8-22`、`645:9-24` — **合规**：仅普通列 + UNIQUE/CHECK，无 `REFERENCES`/`ON DELETE`/级联，注释明写“application checks, no FK or cascade”，与“不加 FK/级联”一致。
5. `645:20`、`645:38-44` — **合规**：`consumption_id` 无 FK（应用层校验），UPDATE/DELETE/TRUNCATE 三向触发器齐备，与 CUSTOM 645 条目描述一致。
6. `644:34-36` — **合规（但与 645 不对称）**：仅拒 UPDATE/DELETE，无 TRUNCATE；CUSTOM 该条目也只声明两向，台账与代码一致。
7. `644:22`、`645:24` — **合规**：唯一键粒度＝(workspace, cr, runtime, task, dispatched_at)，与“一代次一行”一致。

## B. 注释语言与注释内容

8. 全部被审文件（如 `execution_consumption.go:19-33`、`execution_activation.go:19-28`、`execution_binding_client.go:11-20`、`execution_binding_endpoint.go:17-28`、`644:1-7`）— **合规**：注释与 SQL 注释均为英文，无中文残留；`CUSTOM.md` 中文属台账惯例，非代码注释。
9. `execution_activation.go:21-22` — **提示（非硬违规）**：注释把语义事实源指向 change 目录内 md，属可失效的计划/推导引用；AGENTS.md 要求注释只留非显然理由与约束，不留被取代的计划。
10. `execution_authorization_routes.go:46-48` — **违规（注释与代码矛盾）**：注释称“current-head 无 signer 也显式 503”，但该行未做任何 nil/disabled 判定，注释描述的保证在代码中不存在。

## C. 错误处理

11. `execution_authorization_routes.go:43-61` — **违规（吞掉 nil 安全）**：只有 GET `execution-authorization` 在 `service != nil` 内挂载；`/head`、`/binding`、`/consumption`、`/activation` 四条在 `service == nil` 时直接调用方法。这些 handler 首行即 `a.ExecutionContract()` 解引用，nil service 会 panic 而非文档承诺的 503。
12. `execution_consumption.go:59-65`、`execution_activation.go:53-57` — **合规**：body 解码错误显式映射 400，未静默放行。
13. `execution_consumption.go:76-80`、`execution_activation.go:66-70` — **合规**：事务开启失败返回 500，`defer rollbackTx(tx)` 兜底。
14. `execution_consumption.go:176-196`、`execution_activation.go:171-189` — **提示**：重放分支在未提交事务内直接返回（`defer rollback` 会回滚空事务）；结果正确但读与响应跨事务边界，未在注释中说明。
15. `execution_binding_endpoint.go:109-112` — **违规（吞错）**：`_ = endpoint.server.Serve(listener)` 丢弃 Serve 错误且不记日志；监听器崩溃后每个 run 只会得到连接拒绝，链路无任何痕迹。
16. `execution_binding_endpoint.go:70-74` — **提示（吞错）**：`_ = e.server.Close()` / `_ = e.listener.Close()` 静默；且 `time.After(5*time.Second)` 与 96/107 行常量 `executionBindingEndpointLinger` 的 5m 语义分叉，超时值散落。
17. `execution_binding_endpoint.go:160-162` — **合规**：只在 `w.Write` 成功后记录 delivered，与 CUSTOM #177 的“写成功后才记录”一致。
18. `execution_binding_issue.go` 全部 5xx 分支（`"execution binding failed"` 多处，如并发重读失败后回落）— **提示**：统一裸错误串、无 `err` 日志、无 cause 透出；唯一性冲突重读失败被静默折叠成 500，无法与真实故障区分。
19. `execution_binding_issue.go`（`isExecutionBindingUniqueViolation`）— **违规（重复实现 + 脆弱判定）**：以 `strings.Contains(err.Error(), "cr_execution_binding_issue_once")` 判唯一冲突，仓内已有 `isUniqueViolation`（SQLSTATE 23505）惯例（CUSTOM #94 记录的同款复用）；此处另起字符串匹配实现。

## D. 重复实现 / 既有 helper / ponytail 过度抽象

20. `execution_consumption.go:84-141` ≈ `execution_activation.go:74-131`（claim+head+payload+scope+coordinator+challenge 六段逐字重复）≈ 签发 handler 同段落 — **违规**：同一校验序三份拷贝，一份漂移即产生两套准入口径；仓规要求复用既有模式。
21. `execution_consumption.go:138-141`、`execution_activation.go:128-131` — **违规（无效校验）**：`InstallRoot/OperationalRoot == ""` 不可能成立（`decodeExecutionBindingRequest` 已拒空/非绝对路径），属重复且恒假的守卫。
22. `execution_consumption.go:122`、`:119-121` — **提示（无效校验）**：`!claim.RuntimeID.Valid` 与 claim 查询参数重复，claim 行由 (task,runtime,generation) 定位；该分支不可达。
23. `execution_consumption.go:35` — **违规（重复常量）**：`executionConsumptionMaxBodyBytes = 64*1024` 与签发侧 `executionBindingMaxBodyBytes` 同值另立，且解码实际走签发侧常量，本常量在路径上无用。
24. `execution_consumption.go:146-150`、`:166-181`；`execution_activation.go:137-141`、`:161-177` — **违规（绕过 sqlc）**：handler 内手写 SQL（EXISTS/INSERT ON CONFLICT/SELECT 重读），而本切片已有 `pkg/db/queries/execution_binding.sql` + 生成物；未走 sqlc 查询层，与“server 用 sqlc 查询”及 `make sqlc` 流程不一致。
25. `execution_consumption_client.go:58-59` — **违规（无用开关）**：`recordConsumptionAfterDelivery` 默认 false 且生产代码无任何赋 true（CUSTOM #177 自述），整条消费调用在产品路径上是死的；AGENTS.md《Change and Delivery Rules》禁“未被要求的兼容/回退路径与死开关”。
26. `execution_binding_endpoint.go:180-189` — **提示（过度状态机）**：`claimed` + `once` + `delivered` + `guard` 四字段承载“一次签发 + 同 challenge 重试 + 交付记录”，等于在同一对象内实现两层幂等；CUSTOM 671 条目称用 `atomic.Bool.CompareAndSwap`，实际是 mutex+bool，台账与实现不符（见 #30）。
27. `execution_binding_endpoint.go:194-195` — **合规**：`UsesDaemonToken()` + `PipelineCrID` + `DispatchedAt` 三重前置，与 CUSTOM 671“否则不注入任何变量”一致；失败仅 warn、run 继续（211-215）与台账一致。
28. `execution_binding_client.go:45-66`、`execution_consumption_client.go:34-50` — **合规**：空 CR/空 challenge 早退、`null`/非对象 envelope 判错、receipt 缺失判错，均未吞错。
29. `execution_binding_endpoint.go:169-177` — **合规**：`DeliveredChallenge()` 返回副本；无多余接口层。但 `startExecutionBindingEndpoint`/`serve` 依赖的 `executionBindingSigner` 在生产只有 `*Client` 一个实现（195 行唯一传入点），属单实现接口，仅测试需要。

## E. CUSTOM 台账一致性

30. `CUSTOM.md:668` — **违规（错序）**：#177 排在 #170 之后、其余六行之前，编号顺序被打断。
31. `CUSTOM.md:669`（645 行）、`:670`（644 行）、`:671`（endpoint 行）、`:672`（relay 行）、`:673`（binding client 行）、`:674`（binding issue 行）— **违规（漏登编号）**：六行表格均缺 `| 17x |` 列，#171–#176 六个编号整体缺失，台账无法被编号检索/引用。
32. `CUSTOM.md:671` — **违规（错登）**：条目写“`atomic.Bool.CompareAndSwap` 保证只签一次”，代码 `execution_binding_endpoint.go:51-53,180-189` 为 `sync.Mutex` + `claimed bool`；台账描述的机制与实现不符。
33. `CUSTOM.md:668` vs `execution_consumption_client.go:58-59` — **一致**：默认关闭、无生产赋值，台账自述相符（但见 #25 的规范问题）。
34. `CUSTOM.md:670` vs `execution_consumption.go:76,172-181` — **一致**：READ COMMITTED、ON CONFLICT DO NOTHING + 同事务重读、必须有签发记录、同代次异 challenge → 409，均逐条对上。
35. `CUSTOM.md:669` vs `execution_activation.go:142-154,161-177`、`645:38-44` — **一致**：receipt 必需、无 receipt 409、三向触发器、无 DELETE 路由（`execution_authorization_routes.go:61` 只有 POST）。
36. `CUSTOM.md:671-674` 的**源码清单**与落树一致（endpoint/client/relay/issue 文件均在），但六行均未登记 `643/644/645` 的非并发索引，属“描述与增量一致、遗漏规范项”，与 #1–#3 并列计。

## 结论

规范轴 **不通过**：3 处迁移索引硬违规（#1–#3）、1 处 nil service panic 与注释矛盾（#10–#11）、1 处死开关（#25）、3 份重复校验序（#20–#22）、handler 内手写 SQL 绕 sqlc（#24）；CUSTOM 台账 #171–#176 编号整体缺失且 #177 错序、671 条目机制描述与代码不符（#30–#32）。
合规面：注释全英文（#8）、无 FK/级联（#4–#5）、workspace 过滤齐备（消费/activation 全部 SQL 带 `workspace_id`，`execution_consumption.go:149,179`、`execution_activation.go:139,174`）、客户端空入参与空证明判定未吞错（#28）。
剩余风险：`execution_binding_relay.go` 未纳入本轮逐行核对（仅对照 CUSTOM #672 描述），其“deadline 被杀返回 error”“reader EOF 受 ctx 保护”两点未验证；本评审未跑任何 DB/测试，未触库、未改源。

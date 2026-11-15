# BUILD并行核查：授权信任链缺口

> 首次发现时按普通BUILD B4暂停并登记major；后续用户原文“采纳你的建议，继续别停下来等指令”已明确采纳补正并授权继续。本文保留发现时快照，不抹去Gate1/Gate2，不改普通模式、不推定Gate3。当前实现/证据见phase-context.md与wire-contract.md，重大信任链仍未整体验收。

## 1. 已核实的边界

- [T deriveInstallRoot / resolveRepositories](../../../../../tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs)：Git根与dir-graph仓库解析是路径/配置事实，不是平台workspace/project UUID身份证明。
- [T bindTaskWorkspace](../../../../../tools/skills/shared/crctl/scripts/crctl.mjs)：环境/显式路径做包含校验，未认证env来源、未验证平台workspace/project；不能仅增加几个env字段就宣称可信。
- [M认证middleware](../../../../../multica/server/internal/middleware/auth.go) 与 [workspace middleware](../../../../../multica/server/internal/middleware/workspace.go)：提供认证user、凭据来源及真实workspace成员；可复用，不需扩大权限。
- [M project_gates](../../../../../multica/server/internal/governance/project_gates.go) 的canApprove查询真实member owner/admin。
- [M pipeline claim](../../../../../multica/server/internal/handler/daemon.go) 的validateClaimedPipelineCarrier交叉检查DB/run/node/attempt/CR、runtime workspace、executor与模板；queue/execution_context不是独立身份证据。
- [M project资源投影](../../../../../multica/server/internal/handler/project_resource.go) attachLocalDirectorySnapshot及对应SQL原有workspace/project/resource信息；[daemon crevents](../../../../../multica/server/internal/daemon/crevents.go) 的crRootViewEntry只保留workspace/daemon/root/source，不能等价为当前project绑定。失败保留旧投影也不是freshness证明。
- 旧stage grant只签CR/stage等字段，服务公钥不是每workspace独占，不能由旧域包推导新执行授权。
- daemon既有投递、安装key冲突拒绝、原子落盘和落盘后ACK可复用；ACK只表示送达，也不等于Agent不可修改文件的权限隔离。
- [M governance requireHumanActor](../../../../../multica/server/internal/governance/approval.go) 现只排除task_token；新入口不能漏掉已标记cloud_pat等机器凭据，应复用严格human actor判据，而非新增弱判据。当前未修改旧入口。
- [M source_context服务](../../../../../multica/server/internal/service/source_context.go) 与 [SQL](../../../../../multica/server/pkg/db/queries/source_context.sql) 的snapshot有历史上下文用途限制。captured_by_user_id/InitiatorID/originator不是授权人证明；comment可变，trigger_summary截断，不能当完整不可变授权原文。

## 2. 最初提出的两项方向（用户随后采纳，实施/验证中）

### ADJ-AIFI45-001：当前安装根/资源绑定证明

保留平台认证→DB归属→daemon真实资源这条已有链，明确哪个可信组件签发/核验安装根与workspace/project/resource/daemon的绑定；补定root规范化、替换/撤销、当前head及失联拒绝合同。环境变量只作定位。必须检验复制grant/sidecar、同名CR、错误project/worktree/daemon与旧投影，不新增第二预算总账，不靠用户可编辑文本断言可信。

需先选择并定义真正可核验的传输/信任边界，再进入实现；不能把“签出一个可复制JSON”当问题已经解决。本方向不默认授权修改全局工具权限或新增基础设施。

### ADJ-AIFI45-002：不可变人类来源合同

明确可作为授权的真实事件类型，认证actor与owner/admin校验，持久化完整原文/附件版本、digest的字节规则、source_bindings字段映射和已接受默认规则版本。历史snapshot只作旁证，独立提取验证不能增加语义。新增签名域仍按原始bytes，不能改成各语言重序列化。

以上不改变业务目标、累计6次/两次无进展、消费不退款、legacy显式opt-in或原禁止项。补正方向已获用户后续明确采纳，现按wire contract继续实施；原批准原文保持，未整体验证的信任链仍记unresolved，不把方向采纳当验收。

## 3. 首次失败关闭实现的证据（历史快照）

- 两仓原生CLI：SPEC→BUILD退出码0；long_range.enabled=false/mode=normal，依据用户原文“普通模式”。
- T新增公开authorization-bind边界：只读安装包/公钥、原始bytes新域验签与输入/路径保护；有效签名仍明确EXECUTION_BINDING_REQUIRED，**未实现正例绑定/未消费/未启用新policy**。
- 首条RED：1选中/1失败，实际BAD_ARGS对预期EXECUTION_GRANT_SIGNATURE_INVALID；最小实现后1/1通过。
- junction RED：2选中/1通过/1失败，实际EXECUTION_BINDING_REQUIRED对预期EXECUTION_GRANT_KEY_INVALID；补安装根包含关系后通过。
- 首次边界测试：`node --test skills/shared/crctl/scripts/test/execution-authorization.test.mjs`，6选中/6通过/0失败/0跳过，exit=0（约2.9秒）。只覆盖AUTH-003/004/010的部分负例，**不计整TC或切片完成**，Go签字节正例、身份/来源与业务准入尚未实现。
- legacy选择回归：`node --test --test-name-pattern=grant|Grant skills/shared/crctl/scripts/test/crctl.test.mjs`，14选中/14通过/0跳过，exit=0（约20.8秒）；不是全量回归。
- 沙箱JS使用Bun，首次误用process.execPath运行Node test未形成有效RED；已改用实际node.exe，以上RED/GREEN均为Node runner。
- 前端独立线程仅完成约束读取，因该次子会话轮次上限退出；**未改代码、未执行RED/GREEN、不报通过**。
- 锁调查首轮把知识库当源码根，错误报告文件缺失/分支错位；此推测已撤回。源码是知识库sibling `../tools`，`projects/tools/`仅STDD记录；交接改用明确绝对源码根后已实际读到durable-tx.mjs与workspace-transactions.mjs。主会话ctx_execute_file有知识库根限制，outside-root不是不存在；宿主read已确认原授权sibling源码可读，未修改权限。
- 修正后的既有锁测试：在tools根真实node.exe运行`node --test --test-name-pattern="lock|锁|stale" skills/shared/crctl/scripts/test/durable-tx.test.mjs`，5选中/5通过/0跳过/exit=0（约431ms）。只证明已有锁行为，不证明共用CR准入已经实现。
- 复用结论：durable-tx.mjs的acquireLock返回token/release，scope与op受值域限制，release按token核对；无TTL/force-unlock，仅同机ESRCH可接管。beginLedgerTransaction持有ledger锁直到finish/abort/recover释放。现有scope多为per-op、部分root取workspace而非installRoot，同CR不同操作不互斥；应由调用方统一根与准入scope，不必新增锁引擎。crctl.mjs调用方持锁/隔离index区间尚须联合验证，不能将本次5例当RPR验收。

## 4. 隔离环境（不是功能验收）

专用容器stdd-aifi45-20261022-pg，标签stdd.change=2026-10-22-aifi-45-authorized-execution，127.0.0.1:55432，DB stdd_aifi45_20261022 / user stdd。实测current_database/current_user与映射一致。仅用已有pgvector:pg17，未拉镜像。

迁移使用既有`go run ./cmd/migrate up`，exit=0，schema_migrations共670条、最新641_issue_context_refs_gin。基线`go test ./internal/governance -run '^TestAuditUnknownActionRejected$' -count=1 -v`选中1/真实PASS/0 SKIP，exit=0，GOPROXY=off。每次后续测试仍必须先核验DB身份并在内存显式构造DATABASE_URL；凭据仅在专用容器环境，不写本记录或repo文件。

共享multica-postgres/backend未改动。专用测试容器保留供续接，不是部署；未commit/push、未操作真实CR、未运行生产或共享库迁移。

# AIFI-45 wire contract — 授权与当前执行绑定

> **ADJ-AIFI45-003 当前进展（BUILD）**：T `authorization-bind --trust-root <绝对目录>` 仅从声明根读取 grant/公钥/来源/绑定证明，并拒绝位于或包含工作区安装根的目录。M 已接 HTTP→daemon 安装→真实 crctl `--check --trust-root`：`handleTask→prepareClaimedPipelineTask→Client.InstallExecutionAuthorization→verifyInstalledExecutionGrant`，新合同静态检查通过后仍返回 `EXECUTION_CONSUMPTION_REQUIRED`，不启动 Agent、不写 receipt；legacy 路径未追溯阻断。安装器同内容幂等、异内容拒写，source 原 bytes/digest/bindings 对照签名，公钥 ID 对照 envelope，硬链接发布不覆盖，根身份由打开句柄取快照。**0700/0600、目录身份检查、过滤 env 与私有 stdio 均不是同 UID 隔离证明**。真实认证投递链已验证，但 current-head/撤销/可信 claim、不可删除激活与消费事务仍缺，major 保持未解决。
>
> **投递（第二轮）**：daemon 以 `GET /api/daemon/crs/{crID}/execution-authorization`（DaemonAuth，按 daemon 绑定 workspace）拉取 `{record: execution-authorization-record/v1, public_key: {key_id, pem}}`；安装器先用该公钥验 `execution-authorization/v1\0||payload` 签名，再要求 payload `workspace_id`=daemon workspace、`cr_id`=请求CR、`key_id`=envelope、`grant_id` 为 UUID，然后写 `<trust-root>/keys/<key_id>.pub` → `grants/<scope_hash>-<grant_id>.execution-source.json`（record.source）→ `grants/<scope_hash>-<grant_id>.execution-grant.json`（record.envelope）。同名同内容幂等、异内容 `EXECUTION_TRUST_CONFLICT`。该接口只投递冻结初始记录，不表示 current head/撤销/claim，也不置 delivered。

> **重投字节边界**：首次 POST 与 JSONB-backed GET 可能重排 envelope/source **运输包装**的字段；daemon 验签/来源核对仍使用解出的原 payload/原人类请求 bytes，落盘仅固定运输包装编码以保持同包幂等。固定前拒重复键/非 UTF-8/多文档，并核原与编码对象语义相等，避免吞字段或大小写别名；不能通过重签、重序列化 payload 或改 source raw bytes 修复冲突。

> BUILD补正依据：用户已采纳修订方向并明确“继续别停下来等指令”。普通模式保持；本文件细化既有可信接口，不改Gate2原审批原文，不视作Gate3批准。T为跨仓字段源，M消费同合同。原始签名/来源字节不适用仓库文本CRLF归一化规则。

## 1. 静态授权包与只读检查

- envelope严格只有`key_id,payload_b64,signature`；规范base64；公钥Ed25519。签名输入=`UTF8("execution-authorization/v1\0") || raw_payload_bytes`，不重新序列化。
- `grant_digest=SHA256(signature_input)`；scope hash=`SHA256(UTF8("execution-scope/v1\0"+workspace_id+"\0"+project_id+"\0"+cr_id))`。
- 安装文件名`<scope_hash>-<grant_id>.execution-grant.json`，安装根`.crctl/grants/`。key_id限定安全文件名，文件及目录realpath均不得逃出安装根，包最大1MiB。
- `authorization-bind --check`仅公开检查验签、字段、文件归属；返回`check_only=true,bound=false,current_head_verified=false,source_verified=false`。成功不表示已获准执行；不写ledger/状态/准入，不依此派发。

### payload v1字段词汇（必填集按 purpose）

下表是全量设计词汇，不是所有 purpose 共用的必填集。initial 使用现有 scope/repository/coordinator 字段、不含前驱或增量；revoke **仅使用 §3.2 的21键**，不继承 initial 的 scope/预算/资源字段，也不把 initial 必填项全局改成 optional。其余 purpose 仍未实现，不因列入枚举就放行。

| 字段 | 精确类型/约束 |
|---|---|
| schema / issuer / key_id | `execution-authorization/v1` / `multica` / 与envelope完全一致 |
| grant_id / lineage_id / workspace_id / project_id / source_event_id / authorizer_user_id | 小写UUID；初始lineage_id=grant_id；身份由可信服务产生/核验 |
| purpose / authorization_revision / scope_revision | initial/extend/migrate/sensitive/revoke/repair-resume；revision为正安全整数，初始authorization_revision=1 |
| cr_id / approved_at | 共享CR-ID语法；服务端UTC RFC3339时间 |
| source_digest / policy_digest / template_digest | 小写64位SHA256 hex |
| goal / target_version / target_spec_id | 非空字符串；spec ID保持现有命名语法 |
| allowed_repositories | 非空、不重复的logical repo ID字符串数组，不是本机目录 |
| allowed_paths | `{repo_id:[relative_prefix,...]}`，键精确属于allowed_repositories；规范POSIX相对前缀，无glob/反斜杠/绝对路径/空段/`..`；`.`表示已明确列出的整repo |
| repository_bindings | 服务端解析并冻结的`{logical_id:{resource_id,workspace_id,project_id,resource_type,identity_b64,binding_digest}}`；位于**原始已签payload内**，不是仅放可编辑wrapper。集合与allowed_repositories精确一致，身份/digest规则见2.1 |
| coordinator_binding | 同六字段descriptor，服务端从原始coordinator_selection解析并冻结到已签payload；固定CR控制/账本根身份，不能仅冻结业务code仓后允许控制根迁移清零 |
| delivery_targets / acceptance / prohibitions | 字符串数组；delivery_targets/acceptance非空；prohibitions即使空也不隐含敏感授权 |
| sensitive_actions | 数组；每项`action_scope_id,kind,target,environment,limit`，action_scope_id唯一；kind为production/data-destructive/permission/commitment-spend，limit非负安全整数；未列明即不授权 |
| policy_version | `authorized-execution/v1`，且policy/template摘要须匹配实际服务器部署和T安装合同 |
| repair_limit | initial的非负安全整数；不得在extend中用它重置额度 |
| supersedes_grant / previous_head_digest / additional_repairs | 后续revision引用精确前驱UUID+digest；extend增量正安全整数；初始无前驱/增量 |
| source_bindings | 逐scope字段引用可信原文/已接受规则；结构化直接请求的形状见下节 |
| reason | 仅 revoke；精确字段集与文本规则见 §3.2 |

安全整数上界9007199254740991。执行合同中的原始数字 token 必须是 JSON 十进制整数；允许 `-0` 表示整数0，但不接受小数、指数或越界值，不能先经浮点舍入/下溢后冒充整数。未知字段、未知purpose/schema、类型不符、溢出、非规范路径全部拒绝；功能尚未接通的purpose不得仅因验签通过而消费。

### 显式部署manifest（默认关闭）

- M启动参数 `--execution-contract-manifest`（native absolute path）及 `--execution-contract-manifest-sha256`（小写64hex）必须同时显式提供；literal空/空才为nil，缺一个/非法输入启动failclosed，不回退。无新env/global变量、task/context/graph/resource_ref来源，不热reload。
- JSON exact四字段：`{schema:"execution-contract-manifest/v1",policy_version:"authorized-execution/v1",policy_digest:<64hex>,template_digest:<64hex>}`。≤64KiB、一个JSON文档、重复键/未知字段拒绝；一次读取同一buffer的原bytes做pinned SHA，不是普通仓库文本hash，不做LF改写。
- main将已验证对象显式经 `RouterOptions.ExecutionContract` 注入服务，配置后无签名服务则启动拒绝；零值保持503。诊断不回显manifest key/value或秘密。manifest仅部署合同，不是人类授权/激活/Gate3，当前没有实际配置或启用消费。

## 2. 人类来源合同

以下14个 scope 字段及资源选择描述的是 **initial source profile**。revoke 复用同一 wrapper/format，但精确五字段 profile 以 §3.2 为准，不引用 initial 的资源选择或 scope 映射；读取端必须按已签 purpose 选择 profile。

首条可运行路径为`structured-human-request/v1`：经真实认证owner/admin提交的完整结构化请求，本身就是原始授权，不重复确认。task_token、cloud_pat、伪造actor/header及Agent转述不得签为人类来源。project来自同workspace CR→shell issue→project的真实关联；不能由请求自报替换。

服务端冻结收到的完整HTTP原始bytes，`source_digest=SHA256(raw_request_bytes)`，保留base64、实际actor/workspace/CR及字段映射；要求有效UTF8、单JSON、所有层重复键拒绝、严格字段/类型和大小界限。source_event_id/grant_id由服务端可信记录产生；批准时间由服务端产生。14个scope字段映射由服务端构造：通常`{kind:"json-pointer",pointer:"/field"}`；`allowed_repositories`另必须有`resolution_pointer:"/repository_selections"`，把原文逻辑ID与原始人类请求已选资源UUID/版本连接。不是采信作者提供映射，服务端身份/绑定事实不冒充人类原文。

复用`approval_record.grant_json`保存内部wrapper：`{schema:"execution-authorization-record/v1",envelope,source:{format:"structured-human-request/v1",raw_b64,digest,bindings}}`，stage为execution。来源投递文件`<scope_hash>-<grant_id>.execution-source.json`只存source四字段，是**不可信传输**，不是根身份凭证；T按已签source_digest核原bytes、14字段及资源选择，不重序列化或规范化原文。source文件上限2MiB，原文上限1MiB，签出envelope也须≤1MiB。

旧stage pending/ACK不得消费execution记录。原请求重投返回原envelope/time/source及原repository_bindings，不按可变当前行重算、不重新批准。服务端policy/template合同必须来自可信部署配置；请求引用只用于精确比较，未配置时新入口503且默认不启用。

### 2.1 原始资源选择与不可变仓库解析

平台现有resource.label可空/不唯一，resource_ref可由成员更新，**不能自动把label或作者graph当身份**。第一条结构化原请求须含`repository_selections:{logical_id:{resource_id,binding_digest}}`及`coordinator_selection:{resource_id,binding_digest}`，来自人类该次请求的目标仓/CR控制根选择；资源UUID/digest由平台读取面提供，Agent不得用自己的task凭据伪造人类选择。仅需首次原请求携带这些事实，不增加阶段批准。控制根可与一个目标repo复用同资源。服务端在同一授权事务按已认证workspace/project对全部所选resource UUID去重排序锁定，比对版本后冻结；找不到/多义/版本变化拒绝，不猜测。

source_bindings仍为14个语义scope字段；coordinator_selection按此schema固定指针`/coordinator_selection`由T独立读取比较，不冒充第15个语义scope字段。当前proof.resource_id必须等于已签coordinator_binding.resource_id。仅看当前可编辑resource行不够：首次冻结控制根版本后，成员把控制根改指旧ledger副本也必须拒绝，不能借此初始化另一套累计计数。

`binding_digest=SHA256(UTF8("project-resource-binding/v1\0") || UTF8(JSON.stringify(P)))`；P字段顺序固定为`resource_id,workspace_id,project_id,resource_type,identity_b64`，各值皆ASCII（UUID/枚举/base64），Go序列化一次，T按同投影核对。`identity_b64`保留服务端构造的身份JSON原bytes：local_directory精确`{daemon_id,local_path,execution_mode}`（空mode归in_place，不含无关label）；github_repo精确`{url,ref,default_branch_hint}`，不得含URL密码/token/query/fragment；先检查原字符串分隔符，空password、空HTTP userinfo、空query/hash也不能被URL规范化吞掉。SSH/SCP用户名可省略；SCP按同一first-colon/first-@规则解析，保留路径内部Unicode非控制字符，不以Node额外空白字符类约束收紧Go签出包。URL原authority及hostname须非空。v1采用Go/WHATWG共有URL子集，普通IPv6保留，IPv6 zone当前两端一致拒签/拒收（未声称zone本身非法；真正需要时以共享向量升级，当前不手写第二套URL解析器）。只把这些冻结身份事实放入已签repository_bindings，不签全量任意resource_ref或秘密。

T只把graph作为定位视图；实际每个目标repo须与已签resource UUID/身份及当前平台确认逐项匹配。当前控制根或目标资源删除、改绑、跨project或graph换根均拒绝新准入；普通成员改资源不能扩大旧授权或重置累计状态，只会使当前绑定失效。无需因此收紧全部legacy资源CRUD权限。纯资源标签变化不改身份digest；真正迁移走显式协议，继承原lineage/消耗/证据，不能初始重签清零。此解析/当前回读仍在实施，不因初始签字节互通就算完成。

自由文本路径另用可信原始事件和不可变附件snapshot，逐字段span/已接受规则引用，由独立验证者核对“不增加语义”；不能把历史snapshot或capture人当授权。尚未实现/无法证明的来源不得假装已覆盖，只补问真实业务缺口。第一条结构化路径通过不等于整个来源TC完成。

## 3. 当前绑定证明：仅可信daemon链允许消费

静态授权包只证明人类允许什么，不证明当前进程/安装根是谁。新policy的控制写操作必须来自平台已验证claim与本机可信daemon的控制调用；裸CLI仅能check，不能用env或可复制sidecar自行宣布已绑定。

复用既有平台认证、DB任务/项目归属和daemon资源链，保留workspace/project/resource/daemon/runtime/queue task/CR身份。daemon从其实际已验证资源和实际子进程取得规范安装根/进程身份，不接受Agent提供的“expected UUID/root”作为事实。未知/多义根、错误project/resource或旧投影拒绝，不按同名CR猜根。当前CR根证明还不代替每个目标repo的repository_bindings核验，不能只给作者自报graphDigest代签。

控制调用使用每次crctl进程内部生成的随机challenge，证明绑定`challenge、实际安装根、workspace/project/resource/daemon/runtime/task/CR、当前grant head/revision、operation、policy/template/tool版本`。证明由现有服务签名密钥在独立域`execution-binding/v1\0`签原始bytes；服务只对真实认证daemon和DB匹配的当前claimed task签发，不能让task-token/普通body自填证明。daemon仅转发其亲自启动控制子进程的challenge，不能提供任意nonce代签接口。接收方必须校验本次challenge、实际进程/根、签名与当前任务，而非只验证一个复制文件。

可信计算基包括既有平台签名服务、认证daemon凭据、安装公钥和实际部署的控制工具；合法Agent子进程必须不能读取daemon凭据或调用等价代签能力，env过滤/另一个config root/私有stdio不能替代实际权限隔离。只读核查当前同UID/HOME仍可读取daemon profile，未有隔离证据，故不得把mdt_持有人直接当不可伪造的可信本机daemon、不得提供任意nonce签发端点或开放消费。不声称能防御宿主被接管或这些既有可信组件被篡改。不得为实现此合同静默扩大Agent/全局工具权限。任何需要新受保护通道的实际依赖必须显式验证，不能在测试中用self-reported env/sidecar代替。

路径/身份拒绝C0/C1控制字符。本地coordinator的daemon_id为现有平台opaque ID（不是强行UUID）；T精确比较其原冻结值与proof。注册的本地控制路径须指向InstWS主checkout；T在实际执行主机校验native fully-qualified路径、规范路径以及dev/ino同目录（Windows须盘符绝对或完整UNC server+share，不能让不完整UNC依当前盘补全；UNC拒混合/重复分隔符、可保留一个末尾分隔符），challenge发出前亦拒绝实际安装/操作根的C0/C1字符，复制到不同安装根失败，linked worktree按Git common-dir回到同主根。此本地检查不是远端clone或每个目标repo的当前证明，不能替代平台DB版本回读。

当前T子实现的JSONL通道：`--binding-stdio`输出`{binding_challenge:{schema:"execution-binding-challenge/v1",challenge,install_root,operational_root,process_id,parent_process_id,operation,grant_digest,authorization_revision,policy_digest,template_digest,tools_digest}}`一行；stdin只接单个≤128KiB envelope，15秒无响应拒绝，这是控制传输超时、不是grant时钟expiry。challenge由当前进程随机产生，不能用env/flag指定。tools_digest覆盖实际控制mjs、gates/状态图/权限矩阵、pipeline JSON、agents与SKILL.md，仓库文本先CRLF→LF，按排序POSIX文件名+各文件SHA汇总，不把Git SHA当部署证据。

现有证明校验子集要求schema/key_id、workspace/project/CR、resource/daemon/runtime/task ID、challenge/实际两根与PID/parentPID、operation、head_digest/revision、policy/template/tools摘要；它尚不构成完整可信绑定协议实现，当前资源/每repo映射与真实daemon签发未收口。即使该子集和来源均通过，CLI仍以EXECUTION_CONSUMPTION_REQUIRED拒绝，不写receipt。

T仍是额度/状态权威：共用CR锁内复验授权、当前证明与head，CAS提交receipt；证明不是第二份预算。复制包/整sidecar、跨workspace/project、同名CR、旧challenge/旧head、失联和机器凭据冒充人类授权来源均为必测负例（真实daemon凭据在绑定链本身是有条件正例，不能混淆）。第一次结构化grant和只读check通过后，必须继续真实daemon→crctl→TaskService链验证，不能以helper/walker替代。

### 3.1 BUILD 分段：持久化 current-head（initial 第一段快照，未开放准入）

本节 initial-only 是前轮实施快照；revoke 扩展合同见 §3.2，extend 等其他 purpose 仍关闭。

本段先细化 ADJ-AIFI45-001/003 的平台事实源；不把当前 head 回读等同于 execution-binding 或完整撤销/claim 协议。

- 在既有 `cr` 行增加 nullable `execution_authorization_head_id`，指向既有 `approval_record.id`（不新增预算表、FK/cascade）。首次 initial 的插入和 head 设置必须同属现有 CR 行锁事务；响应丢失后的 exact replay 返回原历史记录，不重新签发、不重建缺失 head。
- **不自动 backfill 历史 initial**，也不能按 `created_at`、最大 revision、投递 ACK 或 grant 文件存在推断活动 head。缺指针或指向缺失/异 scope/非法签名记录时失败关闭。历史 GET 仍只投递冻结 initial，不改变其语义。
- 新增 `GET /api/daemon/crs/{crID}/execution-authorization/head`，使用真实 DaemonAuth 与 DB 绑定 workspace，从持久化指针读取精确同 workspace/CR/stage 的记录，核 CR 当前 project 与已签 payload 的 project、record/envelope/payload 身份和服务公钥。未配置合同、身份不符或旧记录无 head 时不得返回可用 head。
- 正例响应复用 `{record, public_key}`，另给出 `head:{grant_id,lineage_id,grant_digest,authorization_revision,purpose}`；`grant_digest` 仍按 §1 原 bytes 带域计算。它只是这次 DB 回读事实，**不是**可复制的本机绑定、每 repo 当前资源证明、可信 task claim 或准入凭据。不得新增自报 challenge/nonce 代签端点；不把网络成功或 `Cache-Control` 当独立新鲜度证明。
- 该第一段实施仅支持 initial head。后续签名 revoke/extend 必须仍走同 lineage 前驱 CAS 与追加历史，另有完整契约和真实 RED→GREEN 后才宣称支持。没有这些能力时，T 继续以 `EXECUTION_CONSUMPTION_REQUIRED` 拒绝消费，M 不凭此响应启动 Agent；5 个 major 与完整 49 TC 完成口径不变。

### 3.2 BUILD 分段：签名 revoke、前驱 CAS 与只读验证（不开放消费）

沿 Gate2 的签名撤销方向实施，不新增时钟 expiry、预算表或任意 nonce 代签通道。§3.1 的 initial-only 是前轮实施快照；本段约束 initial/revoke 分支扩展；是否通过真实 RED→GREEN 以 validation 证据为准，不预先宣称实现完成。未实现的 extend/migrate/sensitive/repair-resume 继续拒绝。

**人类请求与精确字段**：`POST /api/workspaces/{workspaceID}/crs/{crID}/execution-authorization/revoke`，沿真实 Auth、membership、owner/admin 和严格 human actor 判据；task-token/cloud-pat/伪 header 不可签发。body 精确五键：`lineage_id,supersedes_grant,previous_head_digest,authorization_revision,reason`，无 actor/workspace/project/预算自报键。UUID 和 digest 按现有小写 UUID/64hex；revision 是请求的**新 revision**，必须为前驱+1且在安全整数范围内。reason 为非全空白 Unicode 标量文本（拒未配对 surrogate），UTF-8 ≤4096 bytes，允许 TAB/CR/LF，其他 C0/C1 控制符拒绝；不 trim、重写或规范化其原文。JSON 重复键、非 UTF-8、多文档、未知字段/超限请求均拒绝。

**签名 payload** 精确字段（不使 initial 字段全局 optional）：`schema,issuer,key_id,grant_id,lineage_id,workspace_id,project_id,cr_id,purpose,authorization_revision,supersedes_grant,previous_head_digest,authorizer_user_id,source_event_id,source_digest,source_bindings,approved_at,reason,policy_version,policy_digest,template_digest`。`purpose=revoke`；schema/issuer/key_id、身份、源事件、时间由服务按既有基础产生/核验；policy/template 继承已验证前驱。仍签 `UTF8("execution-authorization/v1\0") || raw_payload_bytes`，digest 同 §1。revoke 不携带新范围、额度、退款或恢复语义。

record 与 source wrapper 不变：`execution-authorization-record/v1` / `structured-human-request/v1`，完整 raw_b64/digest 冻结原 bytes。source_bindings 精确五键，各为 `{kind:"json-pointer",pointer:"/<请求键>"}`；`authorization_revision` 映射新 revision，其余键逐项对应 payload。本段不支持自由文本提取。

**事务与幂等顺序**：在既有 CR 行锁内验证真实当前项目、已签前驱和合同；只允许 initial→revoke。以当前独立 `approval_record.id` 为 CAS 前驱，先追加 revoke 历史再 CAS head，同一 DB 事务提交，失败整体回滚。revoke 映射 `stage=execution,decision=reject`，不混入旧 GET 对 initial approve 历史的选择，不推旧阶段审批。不存在 initial、head 缺失/漂移、前驱 grant/digest/lineage/revision 不符、签名/合同无效均拒绝，不按时间/文件或最大revision推断。

认证/当前 scope 校验后，**先查已提交的 exact replay，再要求新请求的前驱等于当前 head**：同 actor+完整原 raw bytes+同 lineage/前驱/新revision 的唯一已提交 revoke 返回原 envelope/source/UUID/时间/源事件、`reused=true`，不补写缺失 head。另一个 owner 即使 raw 相同也不能借用原回执；不同 raw/actor 同前驱最多一条成功，其他409；同 actor/raw 并发可一条新建、一条复用。响应丢失重投只返回原历史，不重新签发或恢复活动 head。旧 initial replay 保留历史语义但不得撤销 revoke；本段 revoke 为终止态，其他 revoke/extend/migrate/resume/新 initial 不恢复它。消耗历史保留不退款，不承诺瞬间回滚已开始的不可逆动作。

**当前回读**：§3.1 的 `/head` 按指针严格区分 initial 与 revoke purpose；revoke 必须核所引 initial 的真实历史/签名/source、同 scope/lineage 与前驱 digest/revision/policy/template。返回五字段 head 中 `purpose=revoke` 只表示已撤销，不是 active、claim 或新鲜度凭据。原 initial 历史 GET 不改；无配置/缺凭据保持关闭。平台失联不能由缓存/旧 initial/旧 ticket 代替 current-head 证明。

**T 静态验证**：按 purpose 精确校验 initial/revoke 字段，未知 purpose 不放行。`authorization-bind --check` 仍只读验签/schema，`bound=false,current_head_verified=false,source_verified=false`；增加 `purpose` 字段区分撤销历史。显式 `--check --check-source` 才独立核对原来源 bytes/digest/按 purpose 的映射（initial 为14 scope 字段及资源选择，revoke 为五个请求字段），并返回 `source_verified=true`，其余否定事实不变；`--check-source` 不带 `--check` 为 BAD_ARGS。该读面不声称前驱链/当前 head 已验证；T 尚无可信本机当前证明时不能据它写活动 head 或 receipt。revoke 的非 check 调用在发 challenge/写文件之前明确 `EXECUTION_AUTHORIZATION_REVOKED` 拒绝，不能把撤销包当授权绑定。initial 仍受 `EXECUTION_CONSUMPTION_REQUIRED` 约束。

M 的初始专用安装器不因为本段静态 verifier 支持 revoke 就暗中启用 revoke 安装/任务准入；Go→Node 可用隔离临时 trust root 直接安装**测试** record/public key，调用真实 T `--check --check-source`。这是互操作组件检查，不冒充真实 daemon 安装/claim/隔离闭环。普通源码 CRLF→LF，签名/原请求 bytes 一律不改。

### 3.3 BUILD 分段：当前 project 资源元数据回读（不开放消费）

沿已批准的当前平台资源回读方向复用既有 `GET /api/daemon/workspaces/{workspaceId}/repos`：仅显式提供单个 `project_id=<UUID>` 时增加当前 project 读面。没有该查询的请求/响应和旧客户端语义不变；不把 §3.1/3.2 的 `/head`、历史安装或重投改为资源准入，也不新增任意 nonce/证明签发入口。

显式 project 读取只接受真实 DaemonAuth 的 `mdt_` 路径与非空 DB daemon identity；workspace 来自该认证绑定，path/header/body 不能改写它。project 必须在同 workspace 内真实存在；project 与其资源在同一 repeatable-read、read-only DB 快照回读。复用 workspace-scoped 查询及 `project-resource-binding/v1` 构造器；新增资源字段只输出 `local_directory`/`github_repo` 的身份 descriptor，不通过这些字段输出原始 `resource_ref`、凭据或 ref 额外 metadata。既有 repos/settings 不因此取得新可信含义，SDK 新读面不使用它们作证明。支持类型的非法身份失败关闭；不支持类型不作为可绑定资源返回。

成功响应保留旧字段，并增加 `project_id` 与 `project_resource_bindings:[<§2 descriptor>]`。空 project 集合显式为 `[]`，字段缺失不等于空集合。新客户端必须按 canonical 精确键提取 workspace/project/集合，descriptor 要求 exact 六键后才 typed decode，再核 scope/唯一 resource UUID/descriptor 自洽；Go struct 大小写别名不能覆盖 canonical 字段。可信读取拒绝 redirect、限1MiB响应并检查完整UTF-8 JSON/重复键（运输上限，不是资源数上限）。旧服务忽略查询、读取失败或响应不符均不得借缓存/heartbeat/旧授权包冒充当前回读。标签/position不改身份digest，删除/reparent使旧selection不在当前集合，身份变化产生不同descriptor；后续真正准入仍须逐项与已签selection核对。

这是一次平台 DB 快照的元数据，不是签名的 execution-binding、任务claim、受保护控制通道、本机根/进程事实或持续新鲜度保证。`Cache-Control: no-store` 只避免缓存，不证明可消费；本段没有 receipt/activation/预算写入，不使 `EXECUTION_CONSUMPTION_REQUIRED` 失效，不关闭5 major或完整49 TC。新源码的实际验证只以独立证据为准。

### 3.4 BUILD 分段：冻结 task/project 的当前 claim 读面（仍非准入）

复用 `GET /api/daemon/tasks/{taskId}/status` 的显式 `execution_claim=1&runtime_id=<canonical UUID>&dispatched_at=<RFC3339 microseconds>` 模式。三项query均恰一次；任务/运行时UUID为小写canonical，时间小数最多六位、拒comma和有损截断后再比较。无execution_claim query的旧polling API不变。旧服务只回status时新SDK必须拒绝，不能靠旧claim/消息wrapper/缓存降级。

只允许真实MDT认证路径、非空且无C0/C1的认证daemon，workspace仅来自认证绑定，不信X-Workspace-ID或body。一个repeatable-read/read-only事务内复用既有workspace-scoped task/issue/project与runtime查询：精确task/runtime/dispatched_at、当前active状态dispatched/waiting_local_directory/running、runtime属于同workspace和daemon；冻结queue task.project_id非NULL，live issue同workspace同项目，project在同workspace实际存在。第一片明确只支持issue-backed任务，其他来源/删除/NULL/项目漂移/错代次fail closed，不按同名CR猜项目，也不重写冻结列。

成功exact八键：`schema=execution-task-claim/v1,workspace_id,project_id,daemon_id,runtime_id,task_id,dispatched_at,status`，时间以DB实际UTC值回显。SDK限制可信URL/no redirects/1MiB/完整UTF-8 JSON与重复键，exact八键后typed decode，核预期namespace/代次/状态与opaque daemon。daemon新合同在根目录解析/准备和授权安装前实际回读，且核daemon与本机配置一致；取不到当前claim不得发task-ID-only终态回调去影响后来重领的任务，留给lease/reclaim。

该响应仍只是当次平台DB快照：不是CR归属/人类来源、持续freshness、当前资源descriptor、本机进程/根、签名execution-binding、受保护控制通道、receipt或activation；MDT本身不证明本机凭据隔离。尚未解决全部complete/fail/outbox代次CAS、其他来源、持久激活及消费事务，不解除EXECUTION_CONSUMPTION_REQUIRED、不关闭完整49TC/5major。

### 3.5 BUILD 分段：终态callback代次fence（本片已收尾到组件级，非消费准入）

复用 `POST /api/daemon/tasks/{taskId}/{complete|fail}`。body增量为 exact `runtime_id`（小写canonical UUID）和 `dispatched_at`（RFC3339、最多6位小数、禁止comma/截断伪等值）；两者必须同时有/无，任一保留字段的大小写别名、duplicate/半参/null/非字符串/尾随JSON拒绝400。无字段暂走旧legacy解码/语义，不因此获得新可信声明，也**不代表不可删activation或legacy防降级major已完成**。

含字段请求必须真实MDT+认证workspace+非空无控制字符daemon，不能采信body/header自报owner。新strict path要求实际事务；原Complete/Fail CAS位置增 `enforce_claim`（false保持旧调用）与exact runtime/dispatched_at、task-agent workspace/runtime workspace/daemon owner谓词。CAS零行回滚前置数据库写；仅正确同代且经单条scoped SELECT重新认证的终态记录可幂等200，active/mismatch/foreign owner为409 `TASK_TERMINAL_CLAIM_REJECTED`。不加新的前置task/runtime锁，不改签名字节/head/历史。

当前公开MDT负例：Fail 矩阵 11 子例、Complete 矩阵 10 子例、foreign replay、stale Composio overlay 均真实 RED→GREEN；daemon 侧 tuple 随 run 的 context 传递（**取消 taskID 缓存**）、single-flight 按 `deliveryKey`、outbox record v3 `claim_mode=generation|legacy`、仅**持 `mdt_` daemon token** 才升级 qualified（PAT 保持 legacy，否则服务端 403 会让回调永不落地）、strict 任务无法 fenced 时 fail-closed 不发终态。最终 `final5` 冻结独立回归：governance 879/878/0/1（795 leaf）、handler 13/13（10）、daemon 125/124/0/1（115，SKIP 为 Windows symlink 权限，不计 PASS）。

**尚不签完整链**：retryable fail 在**有效代次**事务失败时仍可能已创建外部 Composio session（真实 POST `/tool_router/session`，DB 回滚不撤销外部资源）；动态并发快照 race 未验证；同代 complete/fail 并发时第二条可能不落盘；legacy 无字段仍被服务端接受，PAT daemon 只能走 legacy（防降级仍依赖后续 activation major）。无 qualified 生产准入、无全局 C1 结论；完整 TC/major 与消费关闭边界不变。

### 3.6 BUILD 分段：执行绑定签发（服务端；仍非消费/准入）
`POST /api/daemon/crs/{crID}/execution-authorization/binding`（DaemonAuth 组，仅 `DaemonAuthPathDaemonToken`）回答 T 的 `execution-binding-challenge/v1`。body exact **四键**：`task_id`、`runtime_id`（均 canonical UUID）、`dispatched_at`（当前 claim，canonical 且 ≤6 位小数）、`challenge`（exact 12 键，与 T `execution-binding.mjs` 一致）。未配置合同/无签名 key ⇒ 503；非 daemon token/无 daemon/workspace 非 UUID ⇒ 403；CR-ID 非法或 body 非严格（含 `null` 字符串/数字）⇒ 400。

同一 `REPEATABLE READ` 事务内：只接受 `task_id` 指名的行，且该行必须同时满足 runtime/代次匹配、active、`cr_id` = URL 的 CR、认证 workspace、所属 daemon 匹配；head 必须存在且通过既有撤销/scope/policy/template/source 校验；该行 `project_id` 必须等于 head payload 冻结的 project；`coordinator_binding` 必须为 `local_directory` 且其 `daemon_id` = 请求 daemon；challenge 的 `grant_digest`/`authorization_revision`/`policy_digest`/`template_digest` 必须等于 head 事实。任一不符 ⇒ 409，不签、不落行。`task_id` 由 daemon 按自己正在处理的 run 填写；服务端仍逐项复核，不把自报当事实。

签名：`UTF8("execution-binding/v1\0") || raw_payload_bytes`，Ed25519，`key_id` = 服务签名 key；payload **恰好 20 键**（`schema,key_id,workspace_id,project_id,cr_id,resource_id,daemon_id,challenge,install_root,operational_root,process_id,parent_process_id,operation,head_digest,authorization_revision,policy_digest,template_digest,tools_digest,runtime_id,task_id`）。响应 `{envelope:{key_id,payload_b64,signature}, changed}`，`Cache-Control: no-store`。

`cr_execution_binding_issue` 是 append-only 台账（唯一键 `(workspace,cr,grant_digest,challenge)` + 拒 `UPDATE`/`DELETE` 的触发器，无 FK/级联）：同 challenge 重放逐字节返回原 envelope 且 `changed=false`（SC-AUTH-009）；不同 challenge 各落一行（可追溯）。临时测试库由冻结原库 **schema-only 克隆**，新迁移用 runner 显式 `-migration=server/migrations/NNN_x.up.sql`（只允许该目录、记录 sha256）。

**边界（不得外推）**：签发只证明「此平台在 head/claim 事实上回答了这串 challenge」。`process_id`/`parent_process_id` 来自 daemon 转述，服务端**无法验证**；daemon 私有 stdio 中继、T 侧消费事务、不可删 activation、同 UID 隔离控制域、`EXECUTION_CONSUMPTION_REQUIRED` 解除均**未实现**，消费保持关闭。

**资源边界**：该台账 append-only、无回收，故同一 head 的**新**证明上限 256（按 `(workspace,cr,grant_digest)` 计数，超出 429 `EXECUTION_BINDING_LIMIT_REACHED`）；同 challenge 重放不受上限影响（先命中幂等分支）。实际边界是 `256 + 并发签发者数`，**不是**精确 256（RR 快照在取 advisory lock 之前建立）。

**三条传输/交付链路（都不等于准入）**：

1. `crctl authorization-bind --binding-stdio`——daemon spawn 子进程、用 stdin/stdout 交付裸 envelope（daemon 私有 stdio）；
2. daemon `runTask` 给本 run 注入 `MULTICA_EXECUTION_BINDING_ENDPOINT`，T 向该 loopback 端点 POST `{challenge}` 取裸 envelope（**端点不认证调用方，URL 是 bearer 能力；同 UID 可读环境，不构成隔离**）；
3. daemon 端点对**同一 challenge** 的重放放行（服务端幂等，返回同一 envelope），因此 T 超时后可用**同一串 challenge 字节**重试一次；**换 challenge 则 409**。

**隔离执行域的实证（非集成）**：`scripts/aifi45-isolation/trust-root-probe.mjs` 实测同一 UID 可 append/替换验签公钥，而 `--read-only` 只读 bind 的容器内 9 类写尝试全部被拒、且容器内看不到引擎 socket/控制通道与宿主工作区。这只证明该边界**可以**成立，**不**等于 daemon 已把 agent 跑进容器（执行模型变更，未做）。

## 4. 并行所有权与未变约束

T主线程维护协议、CLI、policy和共用准入事务；M服务器线程只维护人类来源/签名/持久化与其HTTP测试；M客户端线程只维护Inbox消费及其公共测试。CUSTOM由主线程统一登记。源码根从知识库看是sibling `../tools`与`../multica`，所有交接写明绝对根。

仍累计6次/两次无进展、准入即消费不退款、旧合同不静默迁移、当前head撤销与失联拒绝；不新增时钟expiry、中央总账/通知总账或第二预算。不commit/push、不碰真实CR/共享库/生产部署。业务TC/切片仅在完整真实路径验证后才计完成。

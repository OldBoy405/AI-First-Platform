# AIFI-45 新本地独立 disposable PG：BUILD 重大设计偏离草案

> 文件名中的 `gate2` 是历史命名，不表示原 Gate2 可以重开或已经重新批准。

> **第一阶段设计与实现范围已确认；真实资源执行未批准。** 用户决定及精确边界见 [确认记录](new-disposable-pg-first-stage-confirmation.md)。本草案的历史审阅未创建或连接 PG、未运行 DB/Podman/网络/测试命令，亦未查询已有容器、环境变量、会话或凭据；不假定新实例已有密码、管理身份、镜像或端口。
>
> 用户先前同意新建独立 disposable PG、仅清理本次可证明归属资源的原则，并对 A 方向回复 **“同意”**：正式迁移从空库建立全新独立测试库，不读取事故库，不以证明新旧库完全等价为前置。随后用户确认了第一阶段设计与实现范围；该确认不代表资源计划、探针或实际创建获批，也不证明细节和安全边界已落实。既有 Gate1/Gate2 历史不撤销、不复用为新实例批准；不改 approved canonical、status，不创建 approval token、不代签、不推进 Gate3。
>
> 具体范围与分步确认见 [方案简报](new-disposable-pg-decision-brief.md) 和 [用户确认](new-disposable-pg-first-stage-confirmation.md)。

## 1. 范围、约束与结论

**已选方向与最小提案**：以全新独占 PG 集群和正式迁移建立的 fresh-install 基线设计封闭的测试入口，内部拟逐命令创建 nonce DB/受限 owner，保留现有测试范围、断言和验收强度。实例不得是原 PG 中的另一库、共享服务、既有卷的重用或改名。现有 `../multica/scripts/aifi45-db/run.mjs` 会读取事故库，本轮不得运行或改向；替代入口第一阶段范围已获确认；具体实现位置和行为仍须按本草案及安全约束核实，不能以本草案替代真实资源执行审批。

本草案本身不实施入口、不执行探针，也不扩展到泛用 CI、部署、真实 CR、真实 Agent、第三方服务或全局权限维护；后续可在已确认的第一阶段范围内实施。项目 `AGENTS.md` 的共享 worktree DB 常规路径不能直接作为本事故后的例外依据；例外须显式审议，不能借 `.env.worktree` 或默认服务发现连接已有实例。

原 Gate2 已确认设计和测试方案，但批准时的逐文件快照尚未在本轮核定；现行 RUN-003 补充回归对旧 runner 的约束不能直接称为 Gate2 原始批准内容。现有方案本轮保持不动。复核 STDD 3.0.7 后，原 Gate2 无已核实的中途重开入口：`gate approve` 对已确认 Gate2 不改确认时间或审计字段，不记录新证据，但仍可能检查顺序、检查或重渲染 Human View，漂移时可能非零退出，因此不是只读探针，本轮不运行。

按 `build.md` §B4「处理设计偏离」处理：原文要求普通模式下登记 `pending-adjustments.yaml`、暂停并向用户报告；用户现已确认第一阶段具体变更，记录不等于真实资源授权。C6 要求汇总调整、生成 `design-adjustments.yaml`，其检查表又写 `design-adjustments.md`，文件名不一致；项目 `config.d/gates.yaml` 要求 Gate3 审议 test-report 与 design-adjustments。仅报告用户不等于 B4 已登记。

工作区 `AGENTS.md` 第 7 条现区分执行账本与人工设计记录：执行状态、额度及权威索引只能经合法入口和入库版本化脚本操作；仅供人工审阅的 STDD `pending-adjustments.yaml` 可按模板精准维护，保留原记录和扩展字段，并核对 YAML、归属和差异。此前 `ADJ-AIFI45-M006` 直接编辑与当时适用规则冲突，不能因现行规则或用户确认追认其历史合规，也不能把用户同意视为豁免当时规则。STDD `state --set`、其他账本 CLI 和 YAML 文本编辑函数不是该历史问题的修复或执行账本的合法入口；不得借此改 `.stdd.yaml`。任何登记都不证明资源身份、业务验收或 Gate3。

**当前结论：不能直接换端口/URL后运行旧入口。** schema 来源已选正式迁移方向，但完整源码快照、实际重建结果、既有测试所需行为与多初态兼容，以及新实例身份/凭据/清理的技术证明仍缺证据。不得把证明与事故库完全等价设为已选 A 的前置，也不得降低原有测试合同；所需设计、批准和证据未齐时新入口验收保持 BLOCK，不回读原事故库。

## 2. 静态核实：当前入口的绑定与缺口

以下是所读源码/文档的行为，不是本轮对运行环境的观察。

| 当前绑定 | `run.mjs` 的静态行为 | 对本次迁移的含义 |
|---|---|---|
| 固定旧实例 | 常量完整容器 ID `666bfec52ac3c3d13b43389891f50c4105833198eab7e4167b76f014a774e823`；核 running、`stdd.change`、`POSTGRES_DB`、`POSTGRES_USER`、loopback `55432` | 这是旧授权对象，不是通用 PG 选择器；不支持环境覆盖选择另一服务 |
| 固定管理通路 | 管理 SQL 经该容器内 `psql`，默认角色 `stdd`；测试 DSN 固定 `127.0.0.1:55432` | 旧角色名/容器本地连接能力不是新实例凭据；不能假定复制用户名即可获得同等权限或授权 |
| 原库基线 | `original=stdd_aifi45_20261022`；先核原库其它 session/全局 advisory lock，再读所有非系统表摘要及审批 ID/整行 hash | “新 disposable DB”仍依赖读取原事故库，不符合本次禁读边界 |
| 原始行与 schema 导出 | 每次导出原审批表 data-only 敏感证据和原库 schema-only；schema 以新受限 owner 导入 | 不搬业务行不等于不读原库；旧 schema dump 也不等于经过正式迁移重建 |
| 空库补种及迁移 | 从 `template0` 建库；补 migration 101 的 rollup singleton 默认行并核字段；按参数顺序直接执行指定 SQL、记录 hash | 只恢复局部默认状态；`-migration` 不调用正式迁移 hooks/conditions，也不建立完整迁移账本证明 |
| 隔离负例 | 新受限角色实际连接原库，执行原审批表 `SELECT ... LIMIT 0`，要求 permission denied | 即使预期拒绝也是原库访问；本次新模式必须完全禁止，不能原样搬用 |
| 结果与清理 | `finally` 回读原摘要及释放状态；`unchanged` 是删除 nonce DB/role及最终成功的条件 | 不能仅删掉原库读取再硬设 `unchanged=true`；须重设计新模式证据与清理前提 |
| 测试选择 | 六个单包白名单；`-run`、`-count=1`、JSON；受限的 skip/shuffle/timeout/migration 参数 | 新模式不应变成任意 URL/任意命令执行器；不能因迁移改窄选择或默默加 skip |
| 验收守卫 | exit/包失败/测试失败/零选中/无 PASS leaf/任何 skip/发现本次生成密码泄漏均拒绝通过 | 至少一个 leaf 并不能证明完整选择；新模式仍需逐项选择清单核对 |

补充边界：`testEnvironment` 继承后替换部分环境、清已知黑名单，不是完整秘密清洗或 OS 沙箱；marker/OID 是可信本地操作者模型下的防误连/误删，不是恶意同 UID 隔离。`cmd/server` TestMain 在 setup 前校验实际库名、current/session role、owner、双 marker及部分受限属性，**不是 teardown 前再次校验**，不能夸大其保证。

README 已明确 `instance-lifecycle.mjs`、supervisor collector 仅为 fake-I/O/受控事件组件；这些文件存在不代表已接真实引擎、进程树退出证明或清理 authority。本文未运行或升级这些组件的结论。

## 3. 历史事故与 HOLD：不因迁移消失

以入库事故记录为依据：扩大 governance 回归后审批历史从 83 条变为 82 条，**missing41 / extra40 / changed0**；原 42 个保护 ID 保留不等于完整 83 条保留。事故时没有定位到能直接还原缺失 41 条完整原行的事前备份；事后导出不能充当事前备份。本文不重新检查该库、不宣称其当前行数或已恢复。

2026-10-24 后续授权允许保留现场、在同一旧实例内逐命令创建 disposable DB；历史报告的“137 表/6228 行/82 审批未变”是**事故后快照保全**证据，不是恢复证明，也不是新独立实例的 schema 或授权证据。过去允许的原库只读取证不转化为本轮许可。

本调整的 HOLD 范围：

- 原事故库、其所在旧容器/集群、原数据卷和事故证据继续保全；不启动、停止、重启、修改配置、迁移、reset、restore或清理它们。
- **禁读原事故库**：不连库、不查 catalog/session/锁、不做拒读探针、不 dump、不前后快照比较；亦不通过旧容器 inspect/env、既有 DSN、凭据或会话侧路取得信息。本轮也不打开原审批行 SQL dump 等敏感原始数据文件。
- 旧临时入口 `AIFI45_DB_HOLD` 是历史已记录的拒跑保护，保持不解除；它不是全局数据库 ACL，本轮未复跑其负例，也不声称其它入口被技术上全面封锁。
- 新实例成功不抵消事故，不授权修复原历史、不自动接受 82 条为原始基线。恢复原历史仍是另行授权与原始恢复源问题。

## 4. 待审议的最小入口合同

### 4.1 身份与授权证据（不是填写假值）

未来真实执行前，需由有权人明确确认并绑定以下**非秘密**清单；当前均未取得本调整的完整证据：

1. 该 change、本草案/后续正式设计的确定版本、操作者和资源责任人、授权时间/有效期、允许的创建与销毁范围、失败保留及人工接手人。已选 A 的用户方向、具体变更决定、资源执行授权与 B4 调整记录分别留证；后几项不得由方向确认推定。
2. 明确采用的本地引擎/执行适配器与固定实现版本；新实例专用命名、随机 nonce、change/run 标签、已审定不可变镜像标识、PG/extension 版本与配置。不能沿用旧容器 ID、端口或权限；镜像不可用时 BLOCK，不自动联网下载或变更主机。
3. 全新空数据目录/临时存储，无既有 named volume、宿主业务目录、源码、HOME、daemon配置、容器引擎 socket 或其它实例数据挂载；无 privileged、host network或自动重启。只允许必要本地 loopback 端口，优先动态分配并记录实际结果；网络/出站边界须显式约束，不把 loopback 等同于隔离。
4. 创建前以独占文件/受控权限落 durable intent（nonce、期望配置、范围，**无密码/DSN/完整环境**）；创建后只核本次新对象的完整 ID、名称、label、镜像、存储、端口和配置，并关联新 PG 集群身份。标签不是自证授权；不能从观察到的配置反抄成“期望值”。
5. 每个测试 DB 的实际 server/集群身份、DB/role 名与 OID、owner、双 marker、current/session role和权限必须与本轮 intent 一致。名称/marker alone 不足以区分不同 PG 集群。

拟设计单独可审计的封闭入口；是新增版本化入口还是其他实现位置仍须评审，不能把现有旧入口改向或在本轮调用。新旧路径不得相互 fallback；新入口不得接受任意实例 ID、URL、host、管理命令或原库备份作为隐式输入。设计尚未实现，现有命令行不具备此能力。

### 4.2 凭据与数据库最小权限

| 身份 | 拟允许 | 明确禁止/待验证 |
|---|---|---|
| 新实例 bootstrap/资源管理身份 | 只在本次新集群创建/核验/精确删除本轮 DB/role；必要时预置已审批 extension | 不来自既有环境或旧容器；不交给 Go 测试；不跨集群；不提供到日志/argv/证据 |
| schema 建立身份 | A 方向采用正式迁移；拟由该 nonce DB 的受限 owner 执行，确需 extension 特权则由 bootstrap 在新实例精确预置并记权限理由 | 不因迁移失败给测试 role 临时 superuser；不能跳迁移或伪造账本；具体 extension 清单/权限尚待确定 |
| 普通测试 login/owner | 保留 `aifi45_tmp_<nonce>` / `aifi45_role_<nonce>` 与 `AIFI45_DISPOSABLE:<nonce>` 合同，仅本库所需 DDL/DML/连接 | NOSUPERUSER、NOCREATEDB、NOCREATEROLE、NOINHERIT、NOREPLICATION、NOBYPASSRLS；无管理角色成员资格/SET ROLE 提权；核 PUBLIC/schema/function/extension 权限 |
| 特殊建子库/迁移生命周期测试 | 单独审议、独占新实例或单独授权 provisioning 身份，按其真实初始状态运行 | 不静默从普通包剔除；不普遍授予 CREATEDB，不把不同迁移初态塞进同一已迁移库 |

拟在**本次新集群内**显式收紧 ACL：测试库撤销 PUBLIC 的 CONNECT/TEMP、仅向本轮角色按测试需要授予；维护库/对照库撤销该测试角色及 PUBLIC 的连接通路；public schema 不向无关角色开放 CREATE。对象/sequence/function 的授权只覆盖本库所需集合，检查默认权限、可执行的特权函数及角色成员资格，不能只核角色属性。具体授权差集与反例须入证；不得对旧集群执行这些 REVOKE/GRANT。

测试 owner 能改其本库对象，且 owner 本身可能绕过表级 RLS，不能把 NOBYPASSRLS 描述成生产级租户隔离。保留现有 TestMain 的 owner 合同，不通过普通共享库加 marker、放宽校验或新增 bypass 适配。

未来凭据只可为新实例专门生成、经受控秘密通路传递；测试只获本轮受限 DSN，管理秘密不继承。禁止假设既有密码、trust 认证或环境变量可复用。环境采用审议后的最小允许集，Go/Node/tools/临时 HOME 等依赖缺失应阻断；离线依赖、真实 Agent 禁用、第三方凭据不进入测试。对应的本地 pgx 版本源码包含环境参数、默认用户目录、passfile 和客户端证书等解析路径；仅清除数据库相关环境项不足以证明不会读取用户文件。待审入口须控制这些路径并核实际构建依赖与生效配置，不读取既有用户文件或凭据；模块声明和本地缓存本身不证明实际运行解析。生成秘密检测到泄漏时脱敏并 FAIL；不输出完整 inspect、环境、DSN、原始异常或可能含 bootstrap secret 的回执。无法证明没有泄漏时不判绿。

`server/go.mod` 声明 Go 1.26.9；支持自动切换的工具链在允许切换且当前版本不足等条件下可能尝试获取工具链，是否实际切换、联网或失败取决于运行环境。待审构建计划须明确工具链与依赖来源，并证明离线隔离；仅禁止工具链自动切换不能证明其他依赖或进程不会联网。

## 5. 空实例 schema 来源与迁移基线：核心阻断

**已选 A 的拟定来源**：冻结的 `../multica/server/migrations/` 完整文件集 + 同一源码快照的正式 `cmd/migrate` 及其 hooks/conditions；不用原库 schema-only clone。具体冻结、资源与执行方法仍待批准：先固定源码/工作目录/迁移解析路径与有序清单、逐文件摘要、PG/extension 配置和建立程序版本，再仅在新集群从空 DB 建立。

静态已知：

- `cmd/migrate`、handler TestMain 及 service 的 `openSharedTestPool` 等路径缺少 URL 时存在默认连接回退；service 还有其他测试级回退，handler 数据库不可达时 TestMain 可能 exit 0。governance 的 TestMain 当前缺 URL 会失败，但不校验目标是否属于本次 disposable 实例。test-plan 与 design 中关于 governance 可能缺省连接共享库的表述是历史状态，不应当作当前源码事实。新入口必须在启动迁移与每个 Go 测试进程前注入并核验本轮专用目标，`DATABASE_URL` 缺失或不匹配直接失败，绝不能落入默认值；本草案不复制默认 DSN。
- 正式 runner 使用 pinned session advisory lock、前置 hooks、条件执行和 `schema_migrations`，CONCURRENTLY 文件不包在整体事务内。条件为 false 仍登记 version，应区别记录“SQL按正式条件不适用”与“测试被 skip”。当前源码的 139、140、469 up SQL 无条件跳过；371 和 446 分别取决于索引形状/可用性和操作符类及扩展等条件，并非单看扩展存在。hook 先于条件判断，故跳过 SQL 不代表没有 hook 副作用。032 的 `pg_bigm` 与 076 的 `pg_cron` 创建含异常捕获，成功记账不证明扩展或索引已创建；捕获也不保证整个迁移必然成功，普通 notice 不一定由 runner 输出。实际扩展、对象和条件原因须在新库中核验，不能仅凭注释断言 fallback 存在，不能通过逐文件 `psql` 近似替代。
- **自动重试与停损（待审候选）**：当前正式入口默认启动预算为 3 分钟，首次迁移遇到被分类为 transient 的错误后可能重新执行整轮 `runMigrations`，不是只重跑未完成 SQL；若配置预算大于零但剩余预算已耗尽，仍可能再执行一次 Ping，只有 Ping 成功才再次调用迁移。首次迁移及部分重试操作不受该预算的硬截止约束，单次连接超时也不等于迁移、锁等待或 hook 的总超时。对“失败后不盲目重试”的候选是在审定的独占子进程环境中显式设 `MULTICA_DATABASE_STARTUP_TIMEOUT=0`，使该次迁移器进程的初始 Ping 和迁移各最多调用一次；不继承内部启动时间戳作为额外环境卫生措施，但配置为零时该时间戳不是单次调用的决定因素。外层启动器/监管器也不得在失败后自动重启；另行计划的成功后重复启动验证与失败重试不同。这不限制一次迁移内的 SQL/hook 数量，也不能确保快速退出。
- 上述候选仅在经批准的**外部墙钟超时、进程树身份与退出证明、失败状态隔离和精确清理**均建立后才可评审；等待锁、hook 或强终止后的服务端连接/锁释放均须真实核验，不能凭发送信号宣称停止。持有迁移锁的连接之外，需访问数据库的 pending hook 还需要可用连接，不能一律将池上限设为 1；具体超时、连接上限和退出后处置待决定。任何中断、超时或账本回执不明均冻结该阶段库，不能自动重跑或手工补账。
- runner 的错误或无效配置日志可能含敏感内容；证据只保留审定的非敏感结果，原始输出不直接写入仓库或终端。秘密通路、输出脱敏、canary 检查及失败保全须先按具体执行计划审阅，不读取既有环境或凭据。上述风险是静态分析，不代表本轮已运行、已确认新环境或改变既有合同。
- `internal/migrations.ResolveDir` 会按 cwd/可执行位置向上找目录；只核 Git SHA 或最大 version 不足。须核实际解析目录与完整文件集，含未提交变更、较小编号新增文件；readiness 关注全版本集合。`ExtractVersion` 使用去除 `.up.sql`/`.down.sql` 后缀的 basename，重复数字前缀不等于重复 migration ID；不能仅比数字前缀或账本行数。静态清单与局限见 `new-disposable-pg-schema-static-recheck.md`。
- migration 101 本身创建并补种 rollup 状态；后续 hook 可合法改变它。新模式应验证**完整正式迁移后的预期状态**，不机械套用旧 schema clone 补种的 epoch 断言或复制旧库行。

### 5.1 未来需给出的 fresh 基线与测试兼容证明

- 空实例初始无业务数据；迁移产生的字典/seed/账本行按冻结源码列明允许集合，不把“空实例”误写成“迁移后所有表零行”。审批/workspace等无测试 fixture 时的预期零行必须实测；所有测试 fixture 自建，不借事故遗留。
- 正式迁移逐项结果、完整 version 集合、条件不执行理由、必要 extension、关键表/列/索引有效性、触发器/函数/权限与测试所需对象；禁止只按表数或最大编号验收。
- 再次启动迁移无意外 DDL/数据变化；迁移失败/中断不被补写成功账本掩盖。前向、重复启动、旧行兼容及安全回退/重应用仅在专属新库中按原测试要求验证；在迁移前状态用自建 fixture 构造旧行，不能借事故遗留数据，不回退整个保全集群。正式 `cmd/migrate up` 也未提供停在指定目标版本的参数；为前/中阶段测试构造初态的文件子集、测试 harness、SQL 或目标版本能力均是待审候选，须各自证明账本与对象一致性，并与完整 fresh readiness 库分开，不得当成已获准方案。
- 新实例上的 readiness 与既有选定测试真实通过，含迁移生命周期各自所需初态。handler 的 `TestWorkspaceDeletionManifestCoversPublicSchema` 比对 public schema 的表及 workspace_id 分类，静态清单未含 `cr_execution_*`；若选中该测试、pool 可用且 643 表仍存在，测试将报 unclassified。所知历史 handler 选择锚点之一 `^TestStartClaim` 不选中该测试；test-plan 的完整相关包要求仍须单独核实。须评审真实表删除/保留及清理顺序，不能只为绿测改清单；变更测试须遵循适用授权并登记 `multica/CUSTOM.md`。旧 schema clone 缺账本导致的 readiness 问题不能通过关 readiness、造 ledger、改 TC 或跳选解决。

#### 5.1.1 初态与测试的待审矩阵

下表仅把静态冲突拆开；不批准具体构造方式、运行命令或改测试，也不以此缩小完整测试范围。涉及破坏性 DDL 或不同阶段状态的用例须在各自隔离的专用库中设计顺序，不能借一个 ready 库的绿灯证明其他初态。

| 所需状态 | 已检索源码中的约束 | 待审处置与验收边界 |
|---|---|---|
| 完整 fresh | 空库经同快照完整正式迁移后，须核全部版本、条件及关键对象；`cmd/server` readiness 的迁移检查按账本中的版本计数判断，不证明对象存在或形状正确 | 冻结真实解析路径、完整清单、extension 和对象断言；仅账本计数或组件绿灯不能替代真实验收 |
| 648 up 后洁净状态 | `TestChannelMigrationAfterUp` 检查目标表零行、清单内对象和部分形状，并在限定 schema、名称与 relation 类型内排查额外对象；它不证明全部对象构成闭集。其他测试可能写入相关表，共库有顺序污染风险，是否全部回滚未核实 | 须明确干净初态与测试间隔离，并核实际选择；不能凭包级 exit 0 推断该初态已验证 |
| 648 down / reapply | `AfterDown` 要求相应对象不存在；`AfterReapply` 检查目标表零行及清单内约束、索引和触发器等形状，但不独立证明此前真的 down。正式 CLI 的 up/down 均不能选单版本；直接执行 SQL 可能使账本与对象暂时不一致 | 单独设计和审批初态构造、实际先后证据、账本一致性与失败处置；任何不一致专用库不得用作 readiness 验收，不能把 fresh 的 `AfterReapply` 绿灯当作真实回退重应用证据 |
| 生命周期与旧行保护 | `TestChannelMigrationProtectedData` 自建业务行并直接执行 648 down/up；`TestExecutionMigrationDownRoundTrip` 会执行 down/up 和对象检查，但对三张旧表只比较行数，未自建旧行 fixture，因此 fresh 零行不能证明非零旧行受到保护 | 每类生命周期/旧行用例分别明确真实前态、fixture 和数据保护断言；失败后隔离库状态未知时保全或清理由经批准计划决定，不能盲目复用或宣称证明了旧行保护 |
| 迁移前阶段与中断恢复 | 测试计划要求前向、重复启动、旧行兼容及安全回退；现有正式 CLI 未提供目标版本参数 | 对前态、失败注入、账本/对象核对和所需 harness 提交具体设计；未经测试不推断事务回滚结果，也不把跳测、fake 或伪造账本计为业务证据 |

**阶段选择待审**：当前源码中 `TestChannelMigrationAfterUp`、`TestChannelMigrationAfterDown`、`TestChannelMigrationAfterReapply`、`TestChannelMigrationProtectedData` 和 `TestExecutionMigrationDownRoundTrip` 无统一的初态切换接口。应将它们与其余相关包测试按上述初态划分，分别记录真实选中集合及非零 PASS leaf，最终核对集合并集等于获批范围；广选、空选或同一库顺序污染不能代替该核对。具体选择参数、测试依赖、独立库映射和是否需要修改测试仍待审批，不因划分少测，不先引入无依据的 skip。

独立只读调查 session `01a18cc4-2025-7468-8217-4a517493af13` 请求 `GBClaude/claude-opus-5-5:high`；另经独立只读复核 session `01a18cca-c28a-7468-8217-4a53ac7aeb82` 请求 `OpenAIPersonal/gpt-6.1-sol:high`，已修正 up 的对象闭集及 reapply 的断言范围。两者 actual backend 无回执，记 unknown；表内事实仍以实际冻结源码和获准测试为准。

#### 5.1.2 单版本迁移的待审候选：受控文件集

正式 `cmd/migrate` 没有“指定版本”的 CLI 参数，但当前源码的 `migrations.ResolveDir` 会先从工作目录查找 `migrations/`，再回退到祖先或可执行文件所在目录；`migrations.Files` 按该目录中对应方向的 SQL 文件取集合。`cmd/migrate` 使用该集合及其内建 hook/condition 映射运行，并维护迁移账本。因此，可**研究**在新集群的专用阶段库中提供冻结快照的受控文件子集，让正式 runner 只看到所需方向的文件，以构造 648 down/reapply 等阶段。此为静态候选，不是 CLI 官方选版本功能，不宣称与完整迁移等价，也未运行或获批。

若后续采用，设计至少须先证明：首选的独占稳定目录被实际解析，目录缺失、不可访问或不匹配时不能静默回退；up/down 成对内容、完整文件名、顺序及 hook/condition 与冻结源码一致；操作前后核验账本和对象，不手工伪造账本；与完整 fresh/readiness 验证使用隔离状态。当前源码文件集未见 648 以后的迁移，但该观察不适用于未来快照或其他版本；runner 本身不检查依赖闭包，不能推断任意早期版本都能单独回退。

| 阶段 | 待验证的账本集合 | 待验证的对象和数据 |
|---|---|---|
| 完整 up | 完整冻结版本集合 `V` | 648 对象及其所需业务初态存在 |
| 专用库仅 648 down | `V` 去除 **648 完整文件版本 ID** | 648 对象消失；其他对象与受保护数据未改变 |
| 同一专用库 648 reapply | 恢复 `V` | 648 对象重建并满足测试的空表/形状要求；不要求原 `applied_at` 字节相同 |

执行需核精确集合与内容、实际执行目标、账本和对象差集；空文件集、目标被 skip 或单独的 exit 0/`Done` 不代表迁移发生。正式 runner 的 DDL 与账本更新并非整体原子，中断或失败后的状态未知；须停止该阶段库后续验收，按获批方案保全、精确清理或从空库重建，不能盲目重试或手工补账。现有直接执行 SQL 的生命周期测试和状态探针也不能冒充正式 runner 的账本往返证据。

`cmd/migrate` 在缺少明确 `DATABASE_URL` 时有默认连接，且建 pool 发生在解析文件集之前，因此**先确认连接身份和禁止默认回退**是必备前置，不能用目录隔离代替数据库隔离；建 pool 不等于已证 TCP 连接。第一阶段入口范围已确认；具体资源及可能连库的命令和测试仍须单独批准，不得对旧 runner 改向或读取事故库。

另有静态工程纪律差异待单独核定：当前 `multica/AGENTS.md` 要求迁移创建索引使用 `CONCURRENTLY` 且每个索引单独文件，而既有 `648_cr_execution_control.up.sql` 含多条非 concurrent 索引。此观察不证明该迁移运行失败，也不授权修改已存在的迁移或改变本次测试验收；若考虑处理，须先审查历史已应用状态、合同与适用流程。

该候选由只读调查 session `01a18d17-0d0c-7468-8217-4a71318de9af` 提出，请求 `GBClaude/claude-opus-5-5:high`；独立只读复核 session `01a18d1e-1d9d-7468-8217-4a797a014528` 请求 `OpenAIPersonal/gpt-6.1-sol:high`。两者 actual backend 无回执记 unknown；协调者核对 `server/internal/migrations/migrations.go` 和 `server/cmd/migrate/main.go` 的对应静态控制流，未核定实际执行结果。

### 5.2 已确认 A 方向与历史候选

用户对 A 建议回复 **“同意”**；该方向转述为：正式迁移建立全新独立测试库、不读取历史事故库，不以证明与旧库完全等价为目标或前置，也不声称等价。这是**当时 A 设计方向的确认**，当时不代表具体设计、资源创建或执行计划批准；后续第一阶段确认另见 [用户决定](new-disposable-pg-first-stage-confirmation.md)。现行 test-plan 的 RUN-003 补充回归段要求其 DB 用例经旧 runner 执行；该段在当前相对 HEAD 的 diff 中为新增内容，是否属于 Gate2 原始批准快照及此前是否登记尚未核实，不能冒称其已获 Gate2 批准。第一阶段已有具体变更决定，不能据此更改现行入口合同或冒称其已获真实运行批准；M006 保持未解决，最终设计调整仍需按原生流程在 Gate3 审议。

- **A（已选方向）：可重建 fresh-install 基线。** 明确与旧现场的已知/未知差异，保留原 TC、断言和验收强度；需要旧行兼容时用专用新库自建 fixture 验证，不访问事故库。无需证明与旧 schema clone 完全等价，但也不能以 A 为由豁免原合同要求的兼容测试。
- **B（历史未选候选）：若未来确需旧基线等价证据**，须由人类另行审议并提供不访问原库即可使用、来源可信且获准的无业务数据 schema/迁移规范与差异证据；审批行 dump 不在候选输入内。
- **C（历史保守候选）：证据不足时保持 BLOCK。** 当前执行仍因具体设计、审批、资源和迁移/测试证据未齐而 BLOCK，这不代表用户改选 C；不能以放宽配置、只跑无 DB 子集或 fake-I/O 代替真实验收。

完整迁移链尚未冻结或实际验证。**历史最大编号、schema hash、137 表及组件全绿都不证明 A 已可执行或既有测试兼容。** 不得为补证连接原库，也不假定历史 schema dump 是脱敏、获准可用的规范。

## 6. 生命周期、并发与精确清理

- 每次只允许一个 DB 执行者，入口需有跨调用的受控互斥/lease；旧 runner 依赖人工串行，不能沿用为自动互斥证明。每命令独占 nonce DB/role；不同初态/包不可混用。
- CREATE 前 intent 落盘；成功、失败、超时、丢 ACK、父进程中断分别记录。创建回执丢失不等于未创建，不能盲目重建；只能在本次新引擎范围按预先 intent 查证完全匹配的新对象，归属不明即保留/人工接手。
- 清理前先证明本次测试、迁移及全部子进程已停止并等待退出；fake exit receipt、EOF、collector 清空或单一 PID 消失不等于进程树已退出。真实适配器/持久 journal 的证明尚待设计和审查。
- 在新集群重核 nonce/OID/owner/marker/权限及本次连接释放；只精确 DROP 本轮 DB/role，再核 catalog 不存在。无前缀扫删、DROP OWNED、REASSIGN、FORCE、全局 terminate 或清别人 session。
- 销毁新实例前再核完整容器/进程身份与存储，只有归属和退出证据齐备才普通 stop/remove 本次完整 ID；逐项证明精确 ID/名称/本次存储已不存在。连接/引擎不可达、超时、not-found 以外错误均是 UNKNOWN，不是 absence。不可通过 prune 或删除已有卷补救。
- schema/测试失败但归属及退出可证明时，可按批准策略精确清理；归属漂移、进程未决、秘密泄漏或保留策略触发时停止后续调用并保留本次资源供人工处理。保留不是 PASS；SIGKILL/宿主崩溃不承诺自动清理。
- DB/role释放与整个实例销毁分别判定；后者成功不能将前者失败升级为成功。journal/evidence 只追加、独占创建、不覆盖事故或旧运行证据。

新模式证据须使用独立格式：记录 `source_database_access=forbidden`、原库比对“不执行/不适用”及依据，不伪造 `original_unchanged=true`、原库 session=0 或“已拒读原表”。本轮不访问原库只能证明遵守访问边界，不能证明原库现状未变。

## 7. 测试选择与 TC 不降级

迁移只换基础设施，不改变正式能力验收。执行前需冻结每条现有调用的 package、run 正则、skip（含理由）、shuffle、timeout、migration 顺序、工具依赖和预期命名测试/leaf 集合；实际 JSON 结果逐项对账。采集入口须证明事件流、完整 EOF、退出码及信号来自同一次受控调用，并以适用的调用参数和证据排除缓存结果重放；自报调用 ID 或孤立的对账 `matched` 不证明这两点。若无法证明来源、完整性或本轮真实执行，阻断，不把缓存或伪造事件计入 TC。新入口的第一阶段设计与实现范围已获确认，但真实资源执行须另行获批；不能将本草案当可执行参数说明。

- 覆盖 test-plan §三列出的 DB 包和需要 DB 的被修改包；旧 runner 的六包白名单（governance、handler、daemon、service、cmd/server、pkg/protocol）是实现边界，不是全部合同或新入口上限。新增包及其命令须显式审议，不把入口变成任意命令执行器；前端/mobile、race、generator/sqlc/lint 等仍按原合同验证，不把单包 runner 扩写为“全套已覆盖”。
- 不能只保留方便的 claim/无 DB 子集，去掉 readiness、并发、真实 Auth/Node/tools CLI、wake/TaskService、失败恢复或权限反例。冻结调用清单须明确测试的 `CRCTL_PATH` 与 daemon 使用的 `MULTICA_CRCTL_PATH` 指向本轮 tools，并核验实际生效；依赖缺失、零匹配、TestMain 整包 skip、任何意外 skip、编译失败/超时均不计通过。
- 历史恢复报告可核选择包括 governance `^Test`（显式排除 LiveGitHub）、handler `^TestStartClaim`、daemon `Test.*Execution`；phase-context 还记有 governance `-run . -skip '^TestReconcileLiveGitHub$' -shuffle=45045`。这些是历史选择锚点，不是本文签发的新执行清单；迁移前仍须冻结适用于当前源码的完整调用，任何增删都显式评审，不把 exact case 的绿色替代原广选择。已查历史调用直接应用 643–648 的 SQL，这些建表语句不是幂等的；若正式完整迁移已建对象，重放预期报错但尚未实测。642 是否出现在历史调用中未确认；必须审议新的初态与选择，不伪称原调用等价。
- 正式 `cmd/migrate down` 不提供单版本选择，按倒序处理已登记迁移，不能构造只回退 648 的初态。直接执行 648 down SQL 不更新 `schema_migrations`，将使该 nonce DB 账本与对象不一致、可能误导账本式迁移完整性检查；是否允许该受控初态及如何记录，或另行批准目标版本能力，须人类决定，不得静默作为 readiness 验收。
- 既有显式 LiveGitHub 排除是排除，不是全包覆盖；不得为新环境追加隐藏 skip。历史 Windows 权限 skip 仍是未验证项，不因过去报告 exit0 自动获豁免；当前 runner 已拒绝有 skip 的 verified 结果。
- M 侧 17 TC、全轮 49 TC及每个 SC 的 AND 不删、不重编号、不改成纯组件或单边拒绝。`TC-RUN-003` 的 `CP-RUN-003-A..N` 补充不能替代真实 route/wake/writer/TaskService，现有补充未证明 periodic scheduler 的限制保留。
- phase-context 的 0/49 是其阶段快照，不当作本轮新统计；较新的台账更正指出历史 44/49不可靠，43/49或42/49仅是不同口径重算，均非当前源码验收。新环境不得继承旧 PASS、合并父子事件、跨 change 双计或重置失败记录。
- governance 的 `TestChannelMigrationAfterUp`、`AfterReapply` 均检查 648 对象存在，`AfterDown` 检查不存在；测试自身不证明 Reapply 之前确实 down。`TestChannelMigrationProtectedData` 自建 643–647 业务表行并执行 648 down/up，未看到它清理这些行；`TestExecutionMigrationDownRoundTrip` 的注释以 schema-only clone 为前提，逻辑要求 643–647 已 up，测试期间 down/up 这些对象，仅比较三张旧表行数且未自建旧行 fixture。历史广选择是否包含阶段测试未确认；须逐调用设计专属初态和执行顺序，不把冲突变为隐藏 skip。需要建子库的特殊包、`test-go.sh` CLI/race/agent-only无数据库访问及 CI 路由问题维持未决；本次不顺带接 CI或削弱 TestMain。无法保留原测试范围、断言或验收强度时显式报告 BLOCK，交人类决定；这与是否证明事故库完全等价是不同问题。

## 8. 具体验收矩阵（全部待执行，不是本轮结果）

以下 V 编号只用于基础设施验证，不新增或替换业务 TC。

| ID | 后续在批准范围内的验证 | 必须取得的证据/失败判据 |
|---|---|---|
| V01 授权绑定 | 留存 A 方向及第一阶段具体变更决定；记录 B4 重大偏离；真实资源/操作者/期限/清理权与执行计划须另行确认 | 方向、调整记录、第一阶段决定和资源执行授权分别留证；缺资源授权时不启动真实资源，不改本轮 status；最终调整随 Gate3 审议 |
| V02 禁触旧资源 | fake 适配器记录完整调用路由；原库/旧 ID/旧端口输入、缺配置、新模式失败均硬拒；检查所有异常/finally路径 | 无旧 inspect/SQL/dump/session/凭据访问，无新旧 fallback；后续真探针只面向本次新实例，不接触旧库证明“拒读” |
| V03 实例身份 | fake 故障矩阵后仅创建一次新实例，核 intent 与完整 ID/镜像/端口/存储/权限/集群身份 | 错 label/镜像/挂载/名字冲突/ID变化全部拒绝；不能重命名已有实例凑合 |
| V04 SQL最小权 | 真实受限 TCP login；核 current/session role、owner、OID、双marker、角色属性/成员资格；用本次新集群内自建对照库/表做连接/读写/提权负例 | 不读原库；跨库拒绝与 SQLSTATE/实际失败原因可区分，错误端点或认证失败不冒充表权限验证；管理秘密未给测试 |
| V05 空库建立 | 按 A 在新库执行冻结清单对应的正式完整迁移，核真实解析目录、全部 ledger版本/条件/对象/索引/extension、合法 seed 和业务空表；旧行兼容在经批准的专用旧初态自建 fixture | readiness通过且证据可重建；前向、重复启动、旧行兼容及专库安全回退按合同；失败不补造账本、不跳文件 |
| V06 选择不降级 | 用相同源码/依赖快照冻结经审批的准备步骤、argv、初态和预期测试集合，逐条检查真实事件及原业务断言；不机械照搬旧 schema clone 或非幂等 SQL | exit0、fail0、skip0、命名目标全选中且全部通过、PASS leaf>0；排除另列，不能只按总数比较 |
| V07 失败生命周期 | fake 覆盖 CREATE/COMMENT丢ACK、迁移失败、证据落盘失败、超时/信号、引擎断联、stop/remove失败；受控真探针验证正常/有限失败路径 | UNKNOWN时保留并非零；不得借故接旧库；fake与真实证明分别标注，无法安全注入的场景列未验证 |
| V08 精确清理 | 真实进程树退出、连接释放，再核 DB/role OID/owner/marker后删除；重核新实例身份后销毁 | DB/role catalog缺席与新实例/本次存储缺席分别证明；丢ACK不能虚报 cleaned；外部不可达不算成功 |
| V09 秘密及证据 | 合成 canary 检验输出/错误/子进程/journal脱敏和FAIL传播；真实流程核仅允许的非秘密投影 | 不使用已有秘密；不记录密码/URL/完整环境/原审批行；证据不可覆盖，仓库文本的摘要先规范化 CRLF→LF，不以哈希代证部署 |
| V10 独立复核 | 非作者审查冻结入口/基线/选择/清理证据并独立重复批准的最小真流程 | 只对实际完成的层级判定；基础设施成功不关闭 M001–M005、不计业务 TC、不批准 Gate3/生产 |

实施顺序：记录已获确认的第一阶段具体变更并保留 M006 历史问题 → 在该范围内完成安全设计与受控 fake 验证并独立复核 → 拟定资源和精确执行计划并另行获批 → 新实例最小真实身份/迁移/权限/清理探针 → 原测试范围逐条回归 → 独立复跑 → C6 汇总、Gate3 审议。每层失败即停止，不以 fake GREEN 跳过真实层。本草案的历史审阅未执行数据库、实现或业务测试层。

## 9. 关键未决项 / 人类决策清单

1. **BLOCK：真实资源及执行计划尚无批准。** 第一阶段设计与实现范围已确认。现有 `ADJ-AIFI45-M006` 的历史直接编辑与当时第 7 条冲突，不能追认为合规；条目存在本身不等于批准。仍需决定身份、权限、销毁与事故保全例外的准确边界；不能挪用历史 Gate2、伪称 Gate2 重开或跳过 Gate3。
2. **BLOCK：A 方向已选，实际 fresh 基线及测试兼容性未证明。** 所需 PG/extension、正式完整迁移、fixture 和不同迁移初态均未实测；具体技术证明及真实执行计划仍未完成或批准。无需证明事故库完全等价，但原合同的旧行兼容与全部测试强度不能省略。
3. **BLOCK：新实例身份、管理/受限凭据通路和异常清理适配器没有真实证据。** 不假定宿主可用、镜像已在、已有变量可借；需绑定操作者及故障接手人。
4. **BLOCK：现入口必读原库，尚不能满足禁读合同。** 第一阶段已获准实施封闭新模式及独立证据设计；不是改常量或把原比较置 true，真实执行仍待批准。
5. **BLOCK：测试清单与特殊包隔离策略未冻结。** 不同迁移初态/建子库权限、readiness、完整选择与工具依赖不能靠少跑放行；CI修复单独审议。
6. **继续保留：历史事故、原库 HOLD、业务 major和当前 TC 证据缺口。** 原历史恢复源、最终 TC统一口径/Gate3偏差须有权人分别处理；新 PG 不替它们作决定。

### 9.1 B4 条目现状（写入方式待合规处理）

- **ID／级别：** 存在 `ADJ-AIFI45-M006`／major；此前直接编辑与当时的第 7 条冲突，该历史事实不能因当前确认改变。第一阶段决定单独留证，不由条目存在推定。
- **原设计引用与现行补充：** `design.md` 的显式隔离测试 DB；`test-plan.md` §一的隔离 DB、URL 核验和迁移验证，以及 §三的完整包回归；现行 RUN-003 补充回归段指定 `scripts/aifi45-db/run.mjs`，其 Gate2 原始快照归属及此前登记状态未核实。
- **变更决定：** 使用全新独立实例和正式迁移形成 fresh-install 基线，专用入口保留原 TC、断言和验收强度。用户先前对方向回复“同意”，现又确认第一阶段设计与实现范围，原话见 [确认记录](new-disposable-pg-first-stage-confirmation.md)。具体资源、真实迁移初态、权限探针、清理及实际命令未获执行授权，也无真实效果证据。
- **原因与影响：** 原入口会访问处于 HOLD 的事故库，不能运行或改向；替代入口和多初态需审议。不能以用户选择 A 推定新旧库完全等价、降级兼容测试或豁免 Gate3。
- **状态：** M006 仍为 `resolved: false`；第一阶段具体变更已获确认，旧写入方式的历史问题不因确认而追认。此处为说明，不替代真实资源审批或 Gate3。

## 10. 核实来源与本轮操作记录

路径口径：`../multica/` 是相对知识库根的源码 sibling；下列项目内相对链接均以本文所在 `validation/` 为基准。未读任何运行时环境/会话/凭据或审批行 dump；后续只读源码核对时输出了源码中的示例默认凭据，已向用户披露，详见 [静态复核安全说明](new-disposable-pg-schema-static-recheck.md)，不在本文重复。

| 来源 | 本文核实内容 |
|---|---|
| 知识库 `AGENTS.md`、`dir-graph.yaml`、`CONTEXT.md`；`../tools/{AGENTS.md,dir-graph.yaml,agent-skill-matrix.yml,README.md}` | 仓库与权限、单一事实源、禁止代批/手改状态、测试运行不是只读检查；本 change 用原生 STDD，不套用 CR 推进 |
| `../multica/CLAUDE.md` → `AGENTS.md` | 常规托管环境与 worktree DB纪律、迁移/测试/交付限制；本 PG 调整未改迁移或测试代码 |
| 工作区 `AGENTS.md` 第 7 条；项目 `projects/multica/config.d/{project,gates,guard,quality}.yaml`；`../stdd/.stdd/skills/build.md` §B4/C6；`../stdd/stdd/cli/commands/{gate,init}.py`；工作区及 `tools`/`stdd`/`multica` 当前工作树相关脚本限定检索 | 原 Gate2 已确认且重跑不写新确认但可能重渲染；BUILD 重大偏离登记及 Gate3 审议；`pending-adjustments.yaml` 作为账本的保守解释和登记入口限制；常规 make test/check 会触环境，不能作为本轮静态命令 |
| [限定授权清单](aifi45-long-range-auth-20261030.md) 之 B4 脚本执行行及[确认记录](aifi45-long-range-auth-confirmation-20261030.md) | YAML 账本脚本须版本化并事先列明授权；此 B4 是授权表编号，不是 STDD 的 §B4「处理设计偏离」 |
| [phase-context](../phase-context.md)、[test-plan](../test-plan.md)、[design](../design.md)相关段落 | 原实例身份、事故/后续授权、隔离及TC/依赖/公开入口要求；阶段快照不冒充最新验收 |
| `../multica/scripts/aifi45-db/{README.md,run.mjs,run.test.mjs}`（静态，未运行） | 固定旧容器/原库、snapshot/dump/拒读/finally绑定、seed、迁移参数、环境/选择/清理守卫；fake组件不代证真实引擎 |
| `../multica/server/cmd/server/integration_test.go:46–132` | TestMain前置实际身份校验及cleanup顺序，无旁路适配许可 |
| `../multica/server/cmd/migrate/main.go`、`server/internal/migrations/migrations.go`、`server/internal/dbstartup/startup.go`（均在源码 sibling）及 `server/migrations/101_task_usage_hourly_schema.up.sql` | 正式迁移 hooks/conditions/账本/非整体事务、自动重试预算与独立超时、默认连接回退、文件目录解析和 seed 来源；真实运行未验证 |
| `../multica/server/internal/{governance/crsync_test.go,governance/approval_crosscheck_test.go,handler/handler_test.go,service/main_test.go}`、`server/internal/daemon/terminal_report_queue.go` | governance TestMain 缺 URL 失败但不验证 disposable 身份；handler TestMain 及 service 测试路径存在默认连接回退；`CRCTL_PATH` 缺省可搜索候选路径，daemon 的 tools 路径变量为 `MULTICA_CRCTL_PATH` |
| `../multica/server/internal/{governance/execution_control_migration_test.go,governance/execution_migration_roundtrip_test.go,handler/workspace_delete_manifest_test.go,taskusagebackfill/backfill.go}`、`server/migrations/642_*` 至 `648_*` | 迁移阶段的对象初态、非幂等 up、业务 fixture 与 handler public 表清单的静态风险；未经 DB 验证 |
| [事故记录](claim-build-20261024T153817Z-incident.md)、[旧实例内disposable恢复报告](disposable-db-20261024T162608Z-report.md) | 83→82、missing41/extra40、事后快照与恢复不同、旧 HOLD、当时授权范围；未复查数据库 |
| [CI调查待办](ci-disposable-db-followup-20261028.md)、[CI disposable实施计划](ci-disposable-db-implementation-plan-20261028.md) | 现 runner非泛用 provisioner；正式迁移/readiness/特殊包/清理未决，计划不能当实施或本调整审批 |
| [pending-adjustments](../pending-adjustments.yaml)、[TC台账更正](tc-ledger-reconciliation-20261029.md) | 当前 M001–M006 均为未解决 major；M006 的直接登记方式存在合规问题，旧 TC 计数不能作当前验收；不静默少 TC、不跨 change 双计 |

**本调整的操作范围：**静态起草及后续原位修订本文，并新增 `new-disposable-pg-schema-static-recheck.md`；协调者用 Node 只读统计 sibling migration 文件名并计算名称清单摘要，未哈希完整源码。针对 RUN-003 补充段，协调者另以只读 `git diff` 核对当前工作树相对 HEAD 的新增内容；这不证明 Gate2 审批时的快照或补写时间。独立静态复核 session `01a18c76-7675-725c-98fc-912ad2b0daac` 请求 `GBClaude/claude-opus-5-5:high`，复核后已修正 Gate2 快照推断、B4 与审批区分和多初态限制；登记入口限定检索 session `01a18cc4-200f-7468-8217-4a4e0e2eace4` 请求 `OpenAIPersonal/gpt-6.1-sol:high`。两者 actual backend 均无回执，记 unknown。扩展条件和 pgx 解析的后续独立静态复核沿用 session `01a18db6-7d06-7468-8217-4adf897fdbb2`，本地依赖源码不证明实际构建解析。自动重试调查 session `01a18dae-4c77-7468-8217-4ad955c510e4` 和独立复核 session `01a18db6-7d06-7468-8217-4adf897fdbb2` 的请求模型待核，actual backend 均无回执记 unknown；已按复核区分配置零与剩余预算为零。此前执行了 `stdd validate`（exit 0）；PG 调整未执行代码测试、DB/容器/网络探针或原生审批/状态命令。没有创建 PG，没有取得新凭据，没有产生业务测试通过或清理成功事实。

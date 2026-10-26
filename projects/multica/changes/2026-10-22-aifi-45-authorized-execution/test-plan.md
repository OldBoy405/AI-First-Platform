# AIFI-45 授权内自治执行 — multica 测试方案

> BUILD新增fixture回归：`TestMDispatch001AfterArchitectureFixture`显式保证requirement ownID不存在，先种architecture同名reviewer后跑真实原四阶段测试；旧版实际SQL23505/3层FAIL。共享setup修复按registry name清理。`TestGovernanceFixtureLeaseExcludesOtherSessions`旧版真实1FAIL后修绿。双进程各10轮140/140；扩大governance 588/588/0fail/skip/exit0仅显式排除LiveGitHub。详见mdispatch-diagnosis.md；原始首次错误上下文缺失不反推全部同源，排除不是覆盖，组件不是17完整TC。

> STDD Phase 2 / Gate2草案。2份code spec + 2份agent spec，所有新增TC为待Gate2后实现/未运行。
> 跨仓tools协议与32个TC见[配套测试方案](../../../tools/changes/2026-10-22-aifi-45-authorized-execution/test-plan.md)。

## 一、测试策略

### 1.1 金字塔与已确认前待审测试边界

优先公开入口级隔离集成：真实认证route → 原审批/pending/daemon通道 → 临时tools CLI；真实统一wake/ResumeActiveRuns → 真实TaskService和Postgres；真实通知入口 → 原Inbox与广播。签名golden和query/schema局部测试补充边界，不用fake enqueuer/直接walker代替端到端。

### 1.2 安全与执行原则

- Gate2后逐个TC RED→GREEN。当前只生成设计和规格，不运行数据库迁移或业务测试。
- **必须显式创建隔离测试DB并核验DATABASE_URL中的库名/归属**；缺URL、指向默认共享multica库或未能证明隔离时fail fast，不执行cleanup。已有governance TestMain可能缺省连共享DB，不可直接照旧命令跑。
- 使用测试用户/Agent/密钥、临时Git/workspace和受控本地HTTP测试server；禁止真实敏感动作、真实CR派发及第三方通知。测试fixture内部Git提交只限临时目录。
- `CRCTL_PATH`明确本轮tools；必需跨工具/DB依赖缺失、TestMain整包skip、目标TC零选中、任何意外skip不算通过。`go test`退出0或出现`[no tests to run]`不足以验收。
- 并发/崩溃用确定barrier和事务故障点，不靠随机sleep。断言逻辑根任务数、实际队列归因、子链、T消费历史、状态及Inbox/广播，不只看HTTP200。
- 负例断言无新grant/receipt/任务/敏感副作用。独立review真实UUID与当前diff/证据同时核验。
- migration按实施时下一个顺序号，列/每个CONCURRENTLY索引独立文件，无新FK/cascade；在隔离DB验证前向、重复启动、旧行兼容及安全回退。不得对共享服务执行down或reset。
- P0/P1都须Gate3前完成；测试报告区分文件数、case数、断言、skip、失败、耗时和实际部署未知。

### 1.3 已有资产与拟新增文件

| 资产（相对M仓） | 当前作用及限制 | 本轮处理 |
|---|---|---|
| `server/internal/governance/approval_crosscheck_test.go` | Go/Node旧stage签名、相邻重放；依赖缺失可skip | 保留旧域回归，新增execution域golden |
| `four_phase_dispatch_cp_test.go`（同目录） | 直接walker与fake enqueuer，不能证明统一wake闭环 | 保留但不作本轮代表路径主证据 |
| `runner_periodic_resume_test.go`、`approval_ack_cp_test.go`（同目录） | 恢复与ACK已有回归 | 扩展新policy receipt及旧合同兼容 |
| `server/internal/daemon/crevents_test.go` | 公钥/传输基础回归 | 加新域与不适用scope负例 |
| **拟新增** `server/cmd/server/authorized_execution_integration_test.go` | RUN组10例 | 真路由、实际wake、真实TaskService、隔离DB及临时CLI |
| **拟新增** `server/cmd/server/execution_notifications_test.go` | NTF组7例 | 真实通知入口、Inbox事务、受众和广播故障 |
| `packages/core/realtime/use-realtime-sync-inbox.test.tsx`及core Inbox/system-notification消费边界 | 已有Vitest资产 | 为NTF-005/007补同Inbox ID重投不重复可见提醒的断言；启用的新policy客户端逐一验证，包括mobile实际入口 |

旧case数与本轮环境未运行统计，不引用此前报告当当前证据。新增辅助fixture尽量复用现有测试工具，不引入新框架。

## 二、详细测试案例

状态统一为**待实现 / 未运行**；每个SC的THEN及AND均需真实断言。

### authorized-runner（REQ-RUN-001～004；10例）

| 字段 | TC-ID | 对应Scenario | 优先级 | Arrange | Act | Assert |
|---|---|---|---|---|---|---|
| **ID** | TC-RUN-001 | SC-RUN-001 | P0 | owner/admin原请求完整、policy就绪、测试签名 | 真实入口启动并跨阶段 | 充分授权自动执行、无重复阶段确认；实际任务与Treceipt匹配 |
| **ID** | TC-RUN-002 | SC-RUN-002 | P0 | task-token/伪header/越权/Agent候选包 | 真实认证route授权请求 | 无有效grant，无执行任务，actor不能自报 |
| **ID** | TC-RUN-003 | SC-RUN-003 | P0 | grant落盘ACK、T未消费，随后T事务提交 | ACK回调及periodic wake | 未消费前只wake不推进/旧continuation；提交后才按实际状态 |
| **ID** | TC-RUN-004 | SC-RUN-004 | P0 | 同receipt跨run及终态根，有/无显式adoption映射 | TaskService入队及旧结果采纳 | 永久key仅一个根，显式映射重验后可接管；无映射不推进，execution引用不被覆盖 |
| **ID** | TC-RUN-005 | SC-RUN-005 | P0 | Git准入后DB前及DB提交后响应前故障 | 重启恢复和技术retry | 同根及有界子链，不再次扣额，不复活终态根 |
| **ID** | TC-RUN-006 | SC-RUN-006 | P0 | T拒绝/无进展/不可达、额度刚耗尽且已有receipt、撤销revision | 新准入、原任务验证恢复及resume | 拒绝新根但允许最后已准入任务收尾；撤销只安全收尾，签名resume才可恢复，不能自算预算 |
| **ID** | TC-RUN-007 | SC-RUN-007 | P0 | 普通已授权隔离CR，四阶段交接重启 | 真入口→统一Reconcile→发现/恢复→真实队列 | 四阶段唯一派发可恢复，不靠手敲命令或直接walker |
| **ID** | TC-RUN-008 | SC-RUN-008 | P0 | legacy活任务与未就绪新版本矩阵 | 切换/显式迁移/回退 | 不双派、不清历史，不删除旧恢复；回退仅停新准入 |
| **ID** | TC-RUN-009 | SC-RUN-009 | P0 | run/node/attempt/cycle/subject/template/policy/receipt/UUID逐项漂移 | 投影迟到review及assessment | 仅留历史，不推进；同作者及缺diff/测试不能交付 |
| **ID** | TC-RUN-010 | SC-RUN-010 | P0 | 普通授权、精确专项授权及对象变化反例 | 具体敏感action请求/重投 | 缺专项无动作；精确授权正例只一次消费，不额外同事实确认 |

### attention-routing（REQ-NTF-001～003；7例）

| 字段 | TC-ID | 对应Scenario | 优先级 | Arrange | Act | Assert |
|---|---|---|---|---|---|---|
| **ID** | TC-NTF-001 | SC-NTF-001 | P1 | 正常节点/ACK/有进展修复事件 | 真实通知入口处理 | Inbox无机械提醒，运行记录仍可查 |
| **ID** | TC-NTF-002 | SC-NTF-002 | P1 | 授权请求、需处置阻断、已交付三类事件 | 持久化并投递通知 | 必要接收者，结论+错误+证据链接+动作，不复制JSON全文 |
| **ID** | TC-NTF-003 | SC-NTF-003 | P1 | 环境/凭据/部署/绑定故障，恢复有限 | 恢复耗尽后通知 | 找维护者，附已试路径，不让业务方搬运命令 |
| **ID** | TC-NTF-004 | SC-NTF-004 | P1 | 额度/无进展根因，维护者与授权者同人/异人 | 异常分流 | 授权决定交有权者，维护角色不自动获业务授权 |
| **ID** | TC-NTF-005 | SC-NTF-005 | P0 | 同原因/证据/受众跨commit重放并发，另有不同CR同根因 | Inbox事务与广播 | 同CR同Inbox、不新增可见提醒；不同CR不互吞，delivered不重广播，pending按稳定ID恢复 |
| **ID** | TC-NTF-006 | SC-NTF-006 | P1 | 已通知后分别新增失败/证据变化/受众变化/交付 | 同一通知入口 | 每项必要变化均通知，不被旧root或读侧聚合吞掉 |
| **ID** | TC-NTF-007 | SC-NTF-007 | P0 | 业务已提交；Inbox写前、提交后广播前、广播后标记前分别故障 | pending扫描及同Inbox ID重投 | 不回滚/重签/扣额/派writer；不丢通知，可能重广播但消费端幂等不重复提醒 |

## 三、测试执行矩阵

| 范围 | 局部回归 | 主集成边界 | 跨仓证据 | 状态 |
|---|---|---|---|---|
| 授权/ACK | 旧v1签名、middleware、公钥传输 | RUN-001～003/010 | T AUTH-001～010真实CLI | 待实现 |
| 逻辑派发/恢复 | SQL约束、retry lineage、旧node-run键 | RUN-004～008实际wake与TaskService | T RPR准入/上限/停止及receipt | 待实现 |
| 证据/独立性 | 现有UUID与review schema | RUN-009联合身份 | T EVD当前subject/机械例外 | 待实现 |
| 通知/分流 | Inbox原读写和listeners | NTF-001～007 | committed CR事件与canonical链接 | 待实现 |
| 生成/部署 | generator/check/CI pin | 隔离版本不匹配与未就绪拒启 | T registry/policy/安装digest | 本地待验，线上未验证 |

客户端重投也是NTF-005/007的必需断言，不以服务端唯一行数替代：M根执行`pnpm -C packages/core test realtime/use-realtime-sync-inbox.test.tsx -t NTF-005`及对应007筛选；沿用已有Vitest，不加依赖。正式TC-ID只在详细案例表定义一次，命令示例中的测试筛选标签以NTF组序号定位（实现时使用同名标签）。mobile等每个启用客户端也要按其已有测试入口验证stable Inbox ID；未验证者不得宣称已覆盖或启用。

执行：从`multica/server`按agent CP运行`go test ./cmd/server -run ^TestTC_RUN_001$ -count=1 -v`等具体TC；先核隔离DB。最终完整相关package回归包括`./internal/governance`、`./internal/daemon`、`./internal/service`、`./cmd/server`及被修改包；test/race工具与依赖可用性在报告记录。Generator实际`--check`、sqlc生成一致性、gofmt和仓库既有lint按真实脚本执行，不靠编译通过代替集成测试。

## 四、回归风险矩阵

| 区域 | 风险 | 保护 |
|---|---|---|
| 人类认证、stage v1和execution新域 | 高 | 旧签名/权限测试＋RUN-001/002/010及Tgolden |
| ACK与消费投影 | 高 | 原ACK回归＋RUN-003，故障后T状态仍是权威 |
| queue唯一键、终态、跨run、retry | 高 | 新partial永久键/旧活动键联合＋RUN-004/005，真实DB并发 |
| wake/router/启动扫描 | 高 | RUN-007实际生产链，不能只测独立walker |
| migration与context覆盖 | 高 | 旧行NULL、CONCURRENTLY、无FK、反向安全检查＋RUN-004/008 |
| 不适用证据与作者自评 | 高 | RUN-009逐字段负例＋T独立证据回归 |
| Inbox及广播重放 | 高 | NTF-005/006/007事务边界及新旧通知共存 |
| 安装/版本与legacy | 高 | 新旧run矩阵，生成及实际二进制/开关未核实不启用 |

## 五、补充顺序和代表路径

先可信授权跨语言→ACK/消费分离→Treceipt与永久根任务键→真实四阶段wake→联合证据→通知与故障→三条隔离路径及独立评审。共享源文件单writer，合同由T唯一源生成，不能两个仓并行各改一套协议。

普通路径：RUN-001/003/007＋NTF-001/002＋T AUTH/EVD正例。
高风险路径：RUN-002/009/010＋T敏感动作/签名/扩围负例。
失败恢复路径：RUN-004～008＋NTF-003～007＋T RPR/EVD故障，覆盖额度到6、无进展、并发、重启和发布失败。

本仓17 TC：P0=12、P1=5、P2=0。全轮49 TC，P0=41、P1=8。当前完整业务TC通过数0，已跑Auth/签名/资源/客户端子断言另见phase-context，不代证真实route→T→wake→TaskService整链；生产部署、真实新CR试点和存量迁移需另行授权，隔离回放不代替这些验收。

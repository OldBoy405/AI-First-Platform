# AIFI-45 授权内自治执行 — tools 测试方案

> BUILD新增安全回归：公开CLI在缺可信current-head/revoke/claim时拒绝fresh proof/source消费、零receipt/HEAD写；预置receipt不激活。新断言真实RED后撤回独立writer。最新显式TAP三文件162/161PASS/0FAIL/1文件symlink EPERM/exit0，旧grant选择14/14/0skip/exit0；这不是49个完整TC通过，完整TC仍0。真实CLI PoC的下载/环境故障与runtime结果分列`isolation-evidence.md`，不把下载timeout当行为RED。

> STDD Phase 2 / Gate 2 草案。对应3份canonical code spec及agent spec；所有新增TC均待Gate2后实施，当前未运行、不宣称PASS。
> 行为源：`canonical/specs/code/`；检查动作源：`canonical/specs/agent/`。每行完整表达Arrange/Act/Assert；预期来自需求与spec，不从实现反算。

## 一、测试策略

### 1.1 金字塔与公开边界

优先真实公开CLI＋临时Git/workspace的行为集成；签名golden补充跨语言边界；registry/模板/生成物复用现有合同测试。跨仓真实认证、wake和TaskService由配套multica测试负责，tools单仓通过不代表运行时或上线通过。不为私有helper、函数调用顺序或猜想的内部实现写测试。

### 1.2 原则

- Gate2确认后按单个TC纵向RED→GREEN，不先写业务代码或批量伪造通过的测试。
- 测试仅用临时CR/Git/密钥、假远端和故障点；不读取真实grant私钥、不派发实际CR、不commit/push本工作区。测试fixture内部Git提交是隔离行为，不是交付发布。
- 文件哈希/跨行解析先CRLF→LF，跨行匹配失败硬报错；签名验签则处理原始已签bytes，不重序列化。
- 成功断言同时检查业务状态/已提交receipt及副作用数量；负例检查账本、状态、任务未变化，不能只断言进程退出。
- 每个TC须有真实选中且执行的测试；禁止零测试、只出现名称、skip、超时或未运行伪称通过。agent spec的exit/stdout只是定位入口，实际THEN由测试内部断言与报告复核。
- 故障注入覆盖写前、write-set应用、commit前后、事件发布前后及恢复；并发用可控barrier/fixture，不依赖sleep碰运气。
- 既有慢测试不因超时排除。首次全量运行先记录HEAD、环境、发现文件和case数，区分既有失败、新失败、基础设施阻断；未知不编造根因。
- P0和P1均必须在Gate3前完成；P1不是允许上线后补。

### 1.3 已有资产与拟新增文件

路径均相对tools仓；用例数未在本阶段运行统计，不引用旧报告数量。

| 资产 | 作用 | 本轮处理 |
|---|---|---|
| `skills/shared/crctl/scripts/test/{crctl,test-cr,trace-outbox,pipeline-structure}.test.mjs` | 现有状态、事务、测试CR、事件与模板回归 | 保留并按实际发现全量运行 |
| `pipeline-templates/emit-registry.test.mjs` | 节点权限、输入/输出及digest | 加入新policy/gate元数据漂移负例 |
| `output-guard/test/*.test.mjs` | 输出约束 | 不因新流程删除回归 |
| **拟新增** `skills/shared/crctl/scripts/test/execution-authorization.test.mjs` | AUTH组10例 | 公开CLI、已签bytes和隔离fixture |
| **拟新增** `skills/shared/crctl/scripts/test/repair-governance.test.mjs` | RPR组12例 | 准入、CAS/commit、assessment与恢复 |
| **拟新增** `skills/shared/crctl/scripts/test/delivery-contract.test.mjs` | EVD组10例 | 内容gates、独立证据、legacy及发布恢复 |

## 二、详细测试案例

当前状态统一：**待实现 / 未运行**。SC与TC序号一一对应；每个SC的所有AND也必须断言。

### execution-authorization（REQ-AUTH-001～004；10例）

| 字段 | TC-ID | 对应Scenario | 优先级 | Arrange | Act | Assert |
|---|---|---|---|---|---|---|
| **ID** | TC-AUTH-001 | SC-AUTH-001 | P0 | 完整可信原请求、新policy、当前证据 | CLI绑定并消费正常阶段 | 推进且无重复人工确认，basis非伪造人类批准，receipt可追溯 |
| **ID** | TC-AUTH-002 | SC-AUTH-002 | P0 | 缺关键验收/交付但事实可调查 | 执行授权preflight | 只列必要业务缺口，未授权无状态/任务副作用 |
| **ID** | TC-AUTH-003 | SC-AUTH-003 | P0 | task-token/自报身份/未知公钥/篡改/旧域表驱动负例 | 逐项绑定 | 全部拒绝，账本、状态、准入不变 |
| **ID** | TC-AUTH-004 | SC-AUTH-004 | P0 | 指定仓库/路径/验收/交付scope | 扩围、放宽验收、跨仓、../和symlink逃逸 | 阻断未授权部分，不能改文档追认 |
| **ID** | TC-AUTH-005 | SC-AUTH-005 | P0 | 仅普通实施grant | 逐项请求生产/数据/权限/承诺支出 | 四类分别拒绝，无真实敏感副作用 |
| **ID** | TC-AUTH-006 | SC-AUTH-006 | P0 | 精确专项grant与operation ID | 合法请求、重投及目标变化负例 | 合法只消费一次，重投同receipt，目标变化拒绝 |
| **ID** | TC-AUTH-007 | SC-AUTH-007 | P0 | delivered/ACK但无committed消费 | status/gate/next | 未消费、不误推进，送达历史仍在 |
| **ID** | TC-AUTH-008 | SC-AUTH-008 | P0 | tenant/project/CR/policy/template/scope不适用，旧revision重绑或签名撤销 | 消费、活动head检查、失联/撤销后准入 | 逐项拒绝不回滚head；未启动任务停止，已消费保留，只允许有界安全收尾 |
| **ID** | TC-AUTH-009 | SC-AUTH-009 | P0 | 消费commit成功、响应/发布故障 | 原请求重放和异义同键 | 原receipt/changed=false；异义明确冲突 |
| **ID** | TC-AUTH-010 | SC-AUTH-010 | P0 | Go签字节golden含中文/分隔符/CRLF/keyID | Node验签并逐字节/域/版本篡改 | 正例通过、负例全拒绝，类型/路径/整数检查，无私钥泄漏 |

### repair-governance（REQ-RPR-001～004；12例）

| 字段 | TC-ID | 对应Scenario | 优先级 | Arrange | Act | Assert |
|---|---|---|---|---|---|---|
| **ID** | TC-RPR-001 | SC-RPR-001 | P0 | 真首次实施及多条失败自测；另有未解决阻断新run | 正常实施及尝试冒充首次 | 真首次不扣；命令/测试数不计次；阻断分支不能绕准入 |
| **ID** | TC-RPR-002 | SC-RPR-002 | P0 | limit=6、consumed=5 | 准入第6并PASS，再请求7 | 第6可验证交付；第7拒绝且无新任务 |
| **ID** | TC-RPR-003 | SC-RPR-003 | P0 | 一次已准入修复 | 失败、内部命令、技术重试 | 已消费恰1不返还；内部重试不另扣且受原上限 |
| **ID** | TC-RPR-004 | SC-RPR-004 | P0 | 多阶段/cycle累计耗尽 | reset、切阶段、supersede再准入 | 总消耗不变，第7仍拒绝 |
| **ID** | TC-RPR-005 | SC-RPR-005 | P0 | 一个origin，并发/换ID/跨run与adoption映射 | 准入、显式接管及当前适用性重验 | 一条消费同repair/根键；有映射可收原结果，无映射旧证据不推进 |
| **ID** | TC-RPR-006 | SC-RPR-006 | P0 | 无关staged变化、授权并发变更、提交边界故障 | 准入/恢复/异义冲突 | 锁内CAS；commit前回滚、commit后复用；不夹带、不覆盖，无未提交派发 |
| **ID** | TC-RPR-007 | SC-RPR-007 | P0 | consumed=6，签出+2，另有并发同前驱grant及旧包 | 追加、重复投递、head CAS和旧包重绑 | limit=8/consumed=6；同前驱最多一份成功，重放不加额不回退head |
| **ID** | TC-RPR-008 | SC-RPR-008 | P0 | 无签名继续、负/溢出数、改本地默认 | 扩额/解除停止 | 拒绝新消费，历史不清零 |
| **ID** | TC-RPR-009 | SC-RPR-009 | P0 | 同根因两次纠正均无进展但仍有余额 | 请求下一次修复 | stopped:no-progress；无任务；升级有证据/路径/余额/所需动作 |
| **ID** | TC-RPR-010 | SC-RPR-010 | P0 | 同名blocker但独立证明测试改善 | assessment后准入 | 可继续且仍累计，不按名称/数量误停 |
| **ID** | TC-RPR-011 | SC-RPR-011 | P0 | 无测试改善但假设被有效排除并改变判断 | 独立核验诊断 | 算进展，保留具体artifact/判断影响，不接受空泛其他进展 |
| **ID** | TC-RPR-012 | SC-RPR-012 | P0 | 无效进展反例；另有引用stop version的签名恢复与独立新证据 | 继续/repair-resume并发重放/有界取证 | 无效不放行；有效CAS只恢复一次、新epoch保留旧stop与消耗，取证不能无界或新增未授权副作用 |

### evidence-delivery-contract（REQ-EVD-001～004；10例）

| 字段 | TC-ID | 对应Scenario | 优先级 | Arrange | Act | Assert |
|---|---|---|---|---|---|---|
| **ID** | TC-EVD-001 | SC-EVD-001 | P1 | 内容与长期更新完整、无固定套餐 | 公开gates及writeback | 按内容放行，累积基线不覆写，平台文档不搬家 |
| **ID** | TC-EVD-002 | SC-EVD-002 | P1 | 文件齐全但缺授权/证据/长期源更新 | 请求交付 | 按具体内容阻断，不能以文件数通过 |
| **ID** | TC-EVD-003 | SC-EVD-003 | P0 | 实质diff仅作者自报或同真实UUID | 请求交付gate | 独立验证缺失，禁止交付 |
| **ID** | TC-EVD-004 | SC-EVD-004 | P1 | 独立执行、当前subject的无语义确定性证明 | 申请机械例外 | 仅完整适用证明可替代Agent review，证据链保留 |
| **ID** | TC-EVD-005 | SC-EVD-005 | P0 | 可复现但规则/输入/工具/授权/验收语义改变 | 申请机械免审 | 每项拒绝，要求独立review及测试 |
| **ID** | TC-EVD-006 | SC-EVD-006 | P0 | 真实旧合同夹具无opt-in | 新版本gates/default校准 | 旧合同不被新字段追溯阻断，不获新预算 |
| **ID** | TC-EVD-007 | SC-EVD-007 | P0 | 源/生成/安装/Runner/恢复任一未知或不一致 | 试点preflight/删旧路径 | 未就绪、旧恢复保留，无上线通过声明 |
| **ID** | TC-EVD-008 | SC-EVD-008 | P0 | 明确新授权且历史可核实；另有不可核实反例 | 显式迁移 | 正例保留授权和消耗、算剩余；反例拒绝不清零 |
| **ID** | TC-EVD-009 | SC-EVD-009 | P0 | 验收后发布事务各边界故障 | 原checkpoint/merge/writeback恢复 | 同事务，不再审批/扣修复/reset，业务事实不重复 |
| **ID** | TC-EVD-010 | SC-EVD-010 | P0 | scope未变但tree/cycle变化 | 用旧证据交付 | 不适用拒绝，旧记录保留，最小必要重验 |

## 三、测试执行矩阵

| 能力 | CLI/Git集成 | 跨语言/跨仓 | 合同/生成 | 本阶段状态 |
|---|---|---|---|---|
| AUTH | 10 TC，正反例及无副作用 | Go→Node签名、pending/ACK与消费 | schema/新旧签名域 | 待实现 |
| RPR | 12 TC，锁/恢复/并发/历史 | M持久化根任务与T准入receipt | status/next/loop兼容 | 待实现 |
| EVD | 10 TC，内容/独立/legacy/发布 | M联合证据身份及实际版本 | registry/policy/generator/安装版本 | 待实现 |

执行入口（Gate2后）：三个新文件按CP命令逐条执行；再运行tools质量配置中发现的全量测试。合同命令：`node pipeline-templates/emit-registry.mjs`、`node --test pipeline-templates/emit-registry.test.mjs`、`node skills/shared/crctl/scripts/check-agents-contract.mjs`、`check-skill-matrix.mjs`、`check-pipeline-contracts.mjs`及`lint-prompts.mjs`（后三者也从同scripts目录运行）。M generator以实际help/CI参数为准并执行`--check`，不得伪造某次临时digest为发布固定值。

## 四、回归风险矩阵

| 区域 | 风险 | 已有保护与新增证据 |
|---|---|---|
| v1 stage审批、TTY与Ed25519 | 高 | 现有approve/签名测试 + AUTH-003/008/010，旧grant不可变新grant |
| ledger锁/CAS/index/恢复 | 高 | review/durable事务回归 + RPR-005/006，多操作并发 |
| loop/cycle与PASS上限 | 高 | 既有review-loop回归 + RPR-002/004/012 |
| 内容gates/writeback/累积基线 | 高 | writeback现有测试 + EVD-001/002/006/009 |
| 权限、节点executor和digest | 高 | emitter/矩阵/pipeline合同 + 新policy元数据篡改及M生成校验 |
| 文档/通知输出 | 中 | output-guard与prompt lint + M NTF测试；不能只做字符串删除 |

## 五、补充顺序与跨仓验收

先AUTH签名/边界 → RPR单次准入/六次上限/事务 → 独立进展 → EVD内容/旧合同 → M真实派发与通知 → 全量/故障/独立审查。每个切片失败先定位根因，不把历史缺陷一概重修。

三条代表路径均在隔离环境完成：普通授权（AUTH-001/009＋RUN-001/007＋EVD-001/009＋NTF-001/002）；高风险（AUTH-003～006/008＋RUN-002/009/010）；失败恢复（RPR-002～012＋RUN-003～008＋NTF-003～007）。真实线上版本、真实新CR试点和存量迁移另需专项授权；未执行明确未验证。

本仓32 TC：P0=29、P1=3、P2=0；配套M 17 TC。完整业务TC通过数仍0；已执行组件子断言见phase-context/build-evidence，不冒充本表TC或切片验收。CP必须精确完整标题+真实成功行及零fail/skip/todo，规格校验不等于业务通过。

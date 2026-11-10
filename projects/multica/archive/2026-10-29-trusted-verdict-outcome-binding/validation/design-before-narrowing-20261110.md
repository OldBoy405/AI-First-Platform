> **2026-11-10 收窄前原样副本**（只读历史，现行设计见 `../design.md`）。正文相对链接以 change 根目录为基准；其中 M009 段已移回 AIFI-45（`projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/m009-attention-routing-spec-20261110.md`）。

# 可信 verdict 结果与命令绑定：multica 消费侧设计草案

> **SPEC thorough；Gate2 BLOCK，未批准实施。** 用户已确认两侧 proposal、thorough 模式，并以“采纳建议，继续”确认隔离裁决、受保护名单、效果分离和优先核旧协议四条方向；证据见 `../2026-10-22-aifi-45-authorized-execution/validation/verdict-authority-acceptance-20261030.md`。这不代表用户批准本文全部技术细节或 Gate2，也不证明真实签发者、信任根、部署及历史存量。签名字段、版本和接口名均未定。

Agent 检查点的非执行映射草案见 `validation/agent-cp-planning.md`；当前 agent-spec 仍为占位，不代表已定义安全执行入口或通过任何 CP。

## Context

现有 Go 验证器认证原始 payload 和 domain/purpose/scope；`verifyVerdictSubject` 还将 request、epoch、sequence、前序摘要与入帧匹配，但不认定裁决结果或冻结命令的授权语义。`SettleControlCommandTx` 的 kind 来自调用方，`execution_admission.go` 按关联 verdict 和 `kind=effect` 计数；该查询自身不确立 manifest 来源或结算权威。源码静态发现不证明生产调用可达或旧数据状态。

结果必须分为五层：签名覆盖的字节、经授权的裁决、permit、实际业务 effect、effect/no_effect 结算。permit 不是 effect；结果及 effect 均不能由调用方自报、签名存在或帧 checksum 推导。本变更不替代 AIFI-45 的 generation、行锁、真实入口、RUN 验收与 Gate3。

证据及源码 SHA：`../2026-10-22-aifi-45-authorized-execution/validation/verdict-outcome-pre-spec-evidence-20261030.md`、`../2026-10-22-aifi-45-authorized-execution/validation/verdict-outcome-contract-20261029.md`。tools 同名 change 提供对等方案；两份草案不表示跨仓接口已经达成一致。

## Decisions（候选，须经 Gate2 裁决）

### D1. 已认证的裁决才能成为新增 effect 的必要前提

**方案：** 按用户采纳的方向，以归档的方案 C（受保护 daemon control 服务内隔离 T/Node worker）作裁决签发的目标分工，M 独立验证签名和经批准契约语义；管理员维护受保护、可信固定的名单，普通 agent 不得修改名单或接触私钥。归档 SC-VC-008 / SC-TR-002 约束密钥用途、路径/pin 与禁止 agent enrollment；ADJ-11 第 4 项的内联 key 和路径 pin 的兼容关系须一并核清。归档 `projects/multica/archive/2026-10-27-trusted-verdict-channel/design.md` §8.1 将 trust-manifest 的原始字节 SHA-256 加绝对路径 pin 列为 `channel-component` 的版本/观测语义，由 operator 的受保护路径提供；该 profile 只能声明组件就绪，不是生产 activation 的证明。管理员对应归档 operator 信任根，恶意 operator 不在其保证范围；实际 pin 的来源、校验及隔离仍须证明。这是设计目标和依赖，不表示当前部署满足。可信 signer、manifest 来源及预期 pin、key purpose/scope、命令、主体、链位置与结果均须有权威可验证事实；未知、过期、不匹配或不能认证的输入不得促成新增 effect。permit 仍需 AIFI-45 的当前授权、代次、锁及入口检查。识别拒绝、取消与 no_effect 时遵循既有合同，不将“不能授权 effect”等同于所有恢复操作都失败。

**为什么：** 签名字节、数据库一条 verdict 或 kind 都不足以证明授权；未知来源不能通过本地自报补齐。2026-10-27 归档 ADJ-10 记录本机 agent 隔离不成立，作为组件级验收残余风险接受；ADJ-13 将 Windows 隔离移出该 change 的验收声称并延至后续 change。本次未复测或推断生产主机现状。按已采纳方向，未取得目标环境隔离证据前不承载生产签名私钥或可信名单；归档 P0 门控另要求 P0 失败停止方案 C 相关切片、转 B 须另行提审，禁止运行时静默降级。

**备选：** 仅判 verdict 非空或 caller 的 effect，均不足；直接按 CR 级计数替代 task/generation 绑定也不足。认证接口及是否复验历史签名尚未选择。

### D2. 先核既有合同，再定签名方案

**方案：** 按用户采纳的优先级，先核对已批准合同、已签原字节与实际调用链，验证 (W-A) 现有版本和字段是否足够；只有不足或无法满足经批准的要求时才提出 (W-B) 经人审的兼容证明/限定范围方案或 (W-C) 新 schema/domain。W-* 仅指 wire 备选，不是归档 P0 隔离方案 B/C。核查须逐项覆盖权威来源、明确的结果语义、命令/主体/链及代次绑定、两侧验证和负面向量；缺少资料表示**尚未证明**，不能单独断言不存在生产格式或必须升级。结果闭集、未知字段及跨 operation 语义须双方人审，不能追溯赋予未批准字段效力。

**为什么：** 归档规格规定未知字段不产生授权事实；既有 fixture 不是完整生产合同。

**备选：** 在实现期自行将 payload 的 `verdict` 等字段解释为 permit、仅增加未经认证的 version 或强制所有旧数据升级，均不能作为已批准方案。

### D3. 双端共同定义绑定与 effect 证据

**方案：** 合同必须明确 request、服务端冻结命令及摘要原像、权威主体、store/lineage、链位置和任务/generation 的对应规则，比较源自服务端可信记录，而非只比较两个调用方输入。核实当前 `request_id=task_id` 假设；协议、store frame、M 链和命令的 digest 前像及字段映射须分别明确，不可无依据互换。归档 ADJ-11 称帧链可直接建立在域分隔 payload digest 上，当前 M `last_digest` 使用 payload-only digest；两者是否指同一合同字段须核清，不能预设差异合理。实际 effect 按类型取证：数据库内 dispatch 仅证明同事务提交的入队，不证明 agent 已启动或后续工作完成；其他本地效果需按各自事务核认证、锁和结算。远端 effect 不与数据库原子，须设计可信回执或具备充分条件的远端对账、attempt 关联、幂等与未知结果冻结；远端仅包含目标提交未必证明由本次 attempt 导致。用户已同意准备“目标达成但本次待核、不重推、不自动发出下一受保护动作”的修订方案；归档 SC-MG-015 在特定 unknown + 远端含目标情形要求结算成功；SC-MG-016 对特定 prev/终态组合规定 not_attempted 和新 attempt。改变这些结算或重试前置须由两侧配对修订并审批；获批前归档合同仍有效；本 change 对冲突分支的合同收敛、测试与 Gate2 标记 BLOCK，不以草案覆盖归档。此 BLOCK 不是运行时冻结指令，也不证明现码或线上已实现或未实现归档行为。

**恢复合同适用性（待双端评审）：**merge publish 对照归档 SC-MG-015～017；store/journal/frame/head 中断对照 SC-VC-015 / SC-TR-006 的恢复表，该表包含导入原 verdict bytes、重放原 command 等动作，不能一概改成冻结。SC-VC-022 的后续 effect 前判决结算按原合同验证，不连带列为待批远端修订。对其他未识别出已有适用合同的外部 effect，本 change 的默认冻结是**拟议规则**，待 Gate2/适用合同批准；尚不能据此声称现行合同或运行时行为。跨类型归属、可信终态和恢复动作的判定仍须在 `validation/remote-recovery-contract-matrix-20261101.md` 中逐格闭合。

归档 SC-MG-015 的 unknown+远端含 expected 按祖先关系判断，要求不重推并结算成功；SC-MG-016 的 intent+prev、settled_no_effect+unknown+prev 要求先以 not_attempted 结算旧 attempt、再以 attempt+1 reserve，不得直接 push 或复用旧 attempt。两个归档用例 TC-MG-015/016 的实际回归执行与归属待定，当前不以引用代替覆盖。另有 `settled_no_effect + unknown + 远端含 expected` 与 settlement immutable、SC-VC-035 原 mapping/新 attempt 的衔接待合同核定；不得把候选“保全矛盾证据”或任一结算结果冒称该组合已获批准。归档 SC-VC-022 的已认证 pending/deny/stopped、过时或撤销 permit 的 no_effect 与 issued 结果未知冻结须按各自适用条件区分，不以这里未定的远端证据要求静默收紧原合同。

**为什么：** 有效 permit 重放到另一命令、主体或代次仍可能误放行；签发前的 permit 不证明执行结果。

**备选：** 仅根据 request ID 或 caller 提供 digest 直接允许，排除；具体字段表、receipt 及事务方案未决，不得先行实现。

### D4. 所有入口与撤销竞争必须闭合

**方案：** 先逐项审计 `execution_channel_admission.go`、`execution_control_policy.go`、`execution_control_settlement.go`、`execution_merge_effect.go` 的 settlement 写入及 AIFI-45 的准入读取；按下表逐类确认权威对象、真实调用链和 scope，再明确 outcome change 与 AIFI-45 各自负责的合同与实现。不可假设所有 `verdict_id` 都引用同一种 verdict。任何未知写入者或证据缺口不得宣称闭合。撤销与 effect 的线性化和锁序须维持归档合同；链接缺失、head 缺失或读失败不能默认为当前授权有效。重放不得制造第二次 effect，旧已提交事实不追溯改写。

**为什么：** 当前非测试代码有多个 settlement INSERT；`controlAuthorizationRevoked` 在无匹配链或 decision 为 nil 时返回 false。仅加固单个 helper 不足。

**备选：** 仅修改 `SettleControlCommandTx`、只看最终 SQL 或单靠无锁读，均不能证明整体闭合。

### D5. 历史数据和部署

**方案：** 不假定不存在旧 verdict 或旧格式；未知/不可认证对象不支持新增 effect，不擅自改写、删除或重签历史。存量兼容、已在途 slot、no_effect、恢复与安全回滚/前滚在权威事实可得后另定；变更不能使已有拒绝保障降级。

**为什么：** 整体按版本冻结可能影响在途恢复；保留历史又不代表可据其授予新权限。

**备选：** 凭源码未发现调用方推断生产为空、静默将旧字段升级为 permit 或承诺无条件自动回滚，均排除。

### 范围、规格责任与实现归属（待人审）

| 项目 | 本 change 草案职责 | 不在本草案中自动授权的实现 |
|---|---|---|
| REQ-VM-001/002/004 | 定义可信裁决、绑定和撤销等跨仓合同约束及验证目标 | 默认拒绝、代次、锁和实际入口属于 AIFI-45 原范围；本 change 不自动授权修改它们 |
| REQ-VM-003/005/006 | 定义不同写入者/恢复/回滚需满足的合同并识别证据缺口 | 实际各写入路径归属须逐项决定；跨语言执行证据拟由 M 的 VM 014 唯一计数，T 引用，待人审 |
| D2 的现有合同 / 兼容证明 / 新版本候选 | 用户已选先核现有合同、不足再提出备选；字段及 W-B/W-C 仍未定 | 涉及签名合同的实际修改须满足独立变更评审与真实 Gate；若超出已确认 proposal，须修订并重新人审 |
| readiness | 先依据原合同由 AIFI-45 评估消费侧修复 | 如需改变 readiness 签名合同，另行评审，不在此预授权 |

这里的场景是合同级目标和交叉验收条件，不等于全部实现归本 change；工程路径、测试资产与是否需要另立变更未最终决定。

## Architecture（边界图，不是已存在的生产调用链）

```text
隔离 T worker + 经保护的信任名单 → 已认证裁决            [目标，部署待核]
        │ 已批准原字节 / 命令 / 主体 / 链绑定
        ▼
M 独立验签与语义检查 → 当前授权 / 代次 / 锁              [候选]
        ├─ 本地效果：同事务执行并结算；提交后形成该效果事实
        └─ 远端效果：受控执行 → 可信回执或对账 → 结算；未知冻结
        ▼
AIFI-45 的后续入口与 admission 独立核验                  [独立验收]
```

### 时序与效果种类（避免循环）

| 顺序 | 事实 | 与后续的区别 |
|---|---|---|
| 1 | 权威主体认证对冻结命令的 permit 或其他结果 | permit 只许可按原合同继续，不证明效果已发生 |
| 2 | 在批准事务内产生并结算 `dispatch` 等本次效果 | 此效果的证据在提交边界形成；不是要求 effect 在执行前已发生 |
| 3 | 后续 task/agent 的启动或其他独立 effect | 它们不能仅凭步骤 2 自动获准，继续执行原 generation/锁/真实入口门禁 |
| 4 | 外部 push 或其他远端效果 | 回执、未知状态和恢复独立设计，不与本地 DB 事务冒充原子 |

**拒绝与恢复区别：** 尚未创建的新请求无效可拒绝；created 且从未 issue 才可按既有合同取消；issued 或 uncertain 的结果未知、证据不可信或丢失时冻结 slot/lineage。result_ready 依据已认证裁决及可信 effect/no_effect 事实和合同结算，仍未知则冻结；settled 只重放原记录。归档 SC-VC-022 对可信 pending/deny/stopped、过时或已撤销 permit 要求按合同结算 no_effect；SC-VC-013 对撤销与 effect 竞争要求按先提交者线性化。不得仅因缺少验签信息或 ACK 直接释放 slot；`no_effect` 的可信证明和边界仍需共同定义，并保留上述既有合同。

### Settlement 写入事实清单（静态，scope 未定）

| 文件 / 函数 | 当前写入及输入含义 | 后续责任 |
|---|---|---|
| `execution_channel_admission.go:192` `settleChannelTask` | `dispatch`；`verdictID` 为传入参数 | 核实际调用链、permit 和 task/transaction 绑定 |
| `execution_control_policy.go:219,301,370` `ApplySensitiveActionTx`、`AppendRepairExtensionTx`、`ConsumeResumeEpochTx` | 专项动作/repair/resume；`verdict_id` 写入 `req.GrantID` | 核 grant 权威及消费侧边界，不能笼统当 tool verdict |
| `execution_control_settlement.go:140` `SettleControlCommandTx`（`execution_channel_reader.go:48,64` 调用） | 输入的 kind/verdict 与 command digest | 核调用者、认证来源、重放和撤销错误语义 |
| `execution_merge_effect.go:217` `ReportMergeEffectTx` | push 报告传入 kind、`headRecordID` | 核权威远端效果证据与未知/恢复，不能笼统当 tool verdict |

上述文件存在不证明均可达，也不授权本 change 修改它们；各路径具体由本 change、AIFI-45 还是另行变更承担仍待人审。源码另显示 `execution_authorization_routes.go:65` 在 service 非空时注册 sensitive-action 路由，`execution_sensitive_action.go:141` 在验证 head 后调用 `ApplySensitiveActionTx`；实际部署挂载、所有分支的撤销检查及能否匹配 admission JOIN 仍需另核，不因这一源码链断言现网可达。相关源码 raw SHA-256 已记入 `verdict-outcome-pre-spec-evidence-20261030.md`。

M 事务不能自动覆盖 T 的 journal 或外部服务。崩溃、重复投递和未知外部结果须能保留原始签名与不可变记录，不得靠重试重复 effect 或虚构 no_effect；是否复验签名及安全时间语义待裁决。Go↔Node 互操作以相同签名前像与原字节为依据，不以各自 JSON 重序列化代替。

## Risks / Trade-offs 与 Gate2 阻塞

| 风险 / 未决项 | 当前约束或下一步 |
|---|---|
| 生产 signer、私钥持有者、manifest 来源/pin 和认证时机未知 | 按用户采纳的隔离控制服务和管理员受保护名单设计，部署角色及事实仍须核实；未知不允许新增 effect，不读取历史事故库 |
| 历史本机 agent 隔离失败，当前目标环境未知 | 不把组件级 Gate3 视为生产隔离证明；部署/readiness 前需重新出证，未经验证不承载生产私钥或信任名单，不虚构逐请求的隔离状态接口 |
| 前序链 digest 与归档 ADJ-8/11 存疑 | ADJ-8 要求开工前核公式；ADJ-11 描述域分隔协议摘要及链可用该摘要。M 的 Go/Node fixture 显式使用 payload-only 前驱，但该前驱由 M 测试脚本构造，不能当作 T 生产方证明。先冻结现状、核批准字段/存量及正负向量，再评审保留或变更；详见工作区 `projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/verdict-recovery-digest-decision-20261030.md` |
| 清单用途/恢复身份可能不兼容 | Go 支持的 `deployment-observer` 不在 Node 当前用途闭集；归档 human resume 与当前 DB grant 路径的衔接、manifest 是否拆分待双方评审，不把当前差异当目标合同 |
| cursor 与 command 状态的恢复一致性 | 入链清空 cursor open 字段、issued 结算状态转换等静态差异须按完整入口及事务独立核对；不推断现网可达或槽位已泄漏 |
| 结果闭集、版本、精确键、命令摘要/prev 摘要、主体与 generation 绑定未定 | 双仓合同表和正负向量先评审；不得把候选字段写成事实 |
| 不同 settlement 写入路径、外部 effect、撤销/锁序未闭合 | 逐路径静态与隔离测试，保持 AIFI-45 原验收；M 同输入重放和 report 冲突行为与 T 恢复、新 attempt 的完整适配待核。远端目标状态及服务端 no_effect 的可信性与 SC-MG-015/016/017 须协调：改变已批准结算或收紧条件须按原合同变更流程审议，不能静默替代；详见工作区 `projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/verdict-recovery-digest-decision-20261030.md` |
| 老格式、key 轮换/泄露、签名时间、重放/恢复的策略未知 | 用户对“真实业务使用或可能已有旧数据”答“是”，不拆推两项分别成立；按可能有存量与在途设计，保留历史证据并禁止静默降级，详见工作区 `projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/remote-merge-recovery-amendment-proposal-20261030.md` |
| key 轮换/撤销/泄露与历史判定 | 新 effect 停止条件、可信签发时间、已提交证据有效性与回溯边界需按权威 key 事件裁定，不一概认定历史自动失效 |
| 双仓测试或本 change 与 AIFI-45 重复计数 | 跨语言执行拟归 M、T 引用；DB 与真实入口另归属。各归属待人审，确认及验证前不算已验收 |
| 范围和 Gate2 交付责任 | 将签名契约调查/变更与 AIFI-45 消费侧修复划清；若需扩大已确认 proposal，走真实修订与重审，不靠新草案授权实施 |

**Gate2 不可提交为已完成：** 以上事实、共享 wire/信任与恢复方案、各写入口及 effect 证据来源必须有可验证决策；本草案不授权源码、测试数据库、部署或自动审批。

## M008 配对修订草稿（未批准）

用户已选择本 10-29 change 承载 M/T 恢复合同的 SPEC 配对评审；这是对原已确认 proposal 的范围增量，不是 Gate1 重签、Gate2 或 BUILD 授权。原依据见 [AIFI-45 M008 草案](../2026-10-22-aifi-45-authorized-execution/validation/wp4-sc-mg-015-016-paired-amendment-20261104.md)，生产侧见 [T 配对草案](../../../tools/changes/2026-10-29-trusted-verdict-outcome-binding/design.md)。

- **SC-VC-012/035 拟议配对**：远端包含 expected 不证明本 attempt 成功；effect 和 no-effect 均无可信依据且尚未结算时，不新写 settlement，保留未决排他约束并停止下一受保护动作。可信 no-effect 按适用合同处理，新发布另须排除旧执行者迟到。
- `SC-VC-035` 保留四支：同 attempt 原字节重放返回 `200` 原结果；前 attempt 已 settled 的新 attempt 返回 `200` 原 mapping；无未终结前 attempt 返回 `201` 新 command；前 attempt 未终结返回 `409`。`200` 原 mapping 不是新 command 或新发布授权。
- 若观察到 `settled_no_effect + unknown + prev` 或 `settled_no_effect + expected`，先读权威 settlement、确定原 attempt 与证据归属，保持已 settled 不变，停止不受证据支持的自动动作；原 mapping、人工对账及后续准入如何衔接待评审，不宣称数据库仍占有已结算 slot。
- 保留 `SC-VC-022` 对 pending/deny/stopped 等已有合法 no-effect 的适用范围，以及 `SC-VC-015/SC-TR-006` 按各自恢复表逐类处理；不把未知远端效果的冻结泛化为全部恢复。
- 配对原 `TC-MG-015/016` 与 M 原 mapping、settlement 和再准入场景，覆盖可信效果、未知、旧执行者迟到、并发及混版；沿用既有验收分母。可信 producer、fencing、存量与回滚、真实入口和数据库验证均待核定。

两侧 Gate1 为历史无指纹确认，现行重签入口未证明能绑定本次范围增量；Gate 输入也不会因链接自动纳入 M008 条款页或 T 侧 MERGED-SCOPE。须先由 STDD 维护者明确合法、可审计的修订、人审及完整输入绑定入口。不修改归档 canonical 或任何 Gate 投影。

## AIFI-45 本轮承接增量（待批准）

本节将用户口头确认的 M008／M009 方向纳入本载体的 design 与 specs，供后续正式评审；不是合同生效、实施授权或验收结论。前文、原 `specs/verdict-channel/spec.md`、AIFI-45 原 design/specs/test-plan 及 validation 草案均保留为历史和来源。本节明确的是本轮待审文本，不追溯改写历史，也不将早期「尚待核定」描述当作当前已实现事实。

### 1. M008 双端恢复合同：同一语义，分别守住真实入口

完整拟议 SC-MG-015/016 与 SC-VC-035 配对条款见 [trusted-merge-gate 增量规格](specs/trusted-merge-gate/spec.md)；[T 同文规格](../../../tools/changes/2026-10-29-trusted-verdict-outcome-binding/specs/trusted-merge-gate/spec.md)保持 Requirements 逐条相同。来源为 [M008 条款草案](../2026-10-22-aifi-45-authorized-execution/validation/wp4-sc-mg-015-016-paired-amendment-20261104.md) §3–8，不各自推导另一套恢复语义。

| 情形 | 本轮拟议必须行为／双端分工 | 现有机制为何不足 |
|---|---|---|
| `unknown + expected`（含后继） | T 不重推，只记录目标达成观察；M 不把观察当本 attempt effect。effect/no-effect 均无可信证据且尚未结算时不新写 settlement，保持未决排他约束，停止下一受保护动作；可信 no-effect 按适用合同处理 | 远端位置不证明本 attempt 的因果归属，不能直接从目标达成推出成功结算 |
| `intent + prev` 或请求再次尝试 | 不直接 push、不复用旧 attempt；允许新尝试必须同时有可信且绑定该 attempt 的 no_effect、旧执行者不会迟到的证明及完整重新准入；任一不足禁止新 reserve/push | prev、intent 或 caller 布尔值都不能排除仍在途的旧 push |
| 已有 settlement，包括 `settled_no_effect + unknown + prev/expected` | M 保留原结算及 mapping，T 只重放原结果；不再写 not_attempted、不改成 effect。SC-VC-035 四支 `200 原结果/200 原 mapping/201 新 command/409` 保留；200 原 mapping 不授权新发布 | 当前查询把 settlement 视为占槽结束，原 mapping 或 slot 结束本身并不证明可安全再执行 |
| 已结算但新动作安全条件不足 | 在真实准入／发布入口另行阻断新 effect；不得声称已结算数据库 slot 仍被占用。具体持久观察、互锁与混版机制待配对审议 | 未结算 reservation 的占用保护不能覆盖已有 settlement 的记录，T helper 也没有生产调用方证明 |

无冲突分支仍保留：confirmed 正常前进不动作、回到 prev 按 history rewrite 转 uncertain、分叉禁新 publish；SC-VC-022 合法 no-effect、撤销线性化和 SC-VC-015/SC-TR-006 其他恢复表不被一概冻结。人工对账不等于 effect 证明、解锁或重推授权；本节不预设新状态、终态重开、迁移或安全重试已实现。

### 2. M009 通知身份与 CR 角色责任来源

完整拟议文本见 [attention-routing 增量规格](specs/attention-routing/spec.md)，沿用 SC-NTF-001～007。来源为 [M009 身份草案](../2026-10-22-aifi-45-authorized-execution/validation/m009-notice-identity-amendment-draft-20261109.md)四项替换方向，加上本轮用户补充的角色 owner／run 启动身份／CR 对话事实；早期草案对责任来源未知的判断保留作历史，不再用来否定已经存在的 CR 角色投影。

- **身份与并发**：复用 `cr_execution_notice (workspace_id, dedupe_key)` 既有唯一约束；notice/Inbox 同事务持久化，冲突返回原 notice／Inbox ID。规范身份继续覆盖可信 workspace/project/CR、稳定原因／事件、重要证据、非空受众和规范接收者；跨 run/commit 重放不变，重要变化不互吞。原因是 commit 级 cr_sync 去重与读侧聚合都不能保证发送侧的同事实唯一性。
- **不再采用旧候选存储位置**：原 AIFI-45 design §5 的 Inbox details 键、partial UNIQUE 及相应迁移保留为历史；本轮待审方案明确不新增这些字段、索引或迁移，也不另建通知账、调度器或回填。原因是既有 notice 已能持久标识内部通知，无需再造一套身份。
- **角色事实链**：crctl 注册／交接的 `owners.requirement|development|test` 经 owners outbox 由 `crsync.applyOwners` 投影到 `cr.owners`；角色对象的 `id` 必须是本 workspace 成员的 `user_id`，不是 `member.id`、显示名或 Agent ID。授权类→requirement，维护类→development；现有非维护交付受众沿 requirement 路由，test 仅保留投影、不新增受众。原因是 workspace 管理角色不是该 CR 的责任归属。
- **回退与权限边界**：有可用 CR owner 就优先使用；只有无可用 owner 才退回启动该 run 的任务身份（`pipeline_run.started_by` 的有效成员 user_id），仍无则不发送；读取出错停止发送，不任选 workspace owner/admin。owner/starter 只确定提醒对象，不因此获业务授权。原因是成员身份或收到通知本身不能替代原审批与权限校验。
- **会话与投递**：Inbox `issue_id` 取同 workspace/CR 的 `cr.shell_issue_id`，无 shell issue 时不伪造链接；pending/delivered 和稳定 Inbox ID 保存在 notice，提交后广播，pending 按原 ID 恢复，消费者按 workspace+Inbox ID 幂等。原因是裸消息不能定位原对话，而广播与标记无法物理 exactly-once。
- **保留写前恢复保证**：业务提交后通知失败不回滚业务、不重签／扣额／派 writer；即使 notice 尚未写入，也须从可靠既有持久事实逐事件重建原身份，不能以无 pending 行豁免 SC-NTF-007。原因是 pending 扫描不覆盖 notice 写入之前的故障。

### 3. M009 静态代码核对：已接入与偏差分开记

以下路径均相对 `../multica/`，仅为本轮只读源码事实，不是测试或生产验收：

| 位置 | 当前可核事实及与待审文本的关系 |
|---|---|
| `server/internal/governance/crsync.go#applyOwners` | 已接 owners 事件，投影 requirement/development/test 的角色对象并检查 `id` 的 UUID 形状；这里本身不查询成员表。接收资格由下游按 workspace/user_id 再核，不能把形状检查写成已证明成员资格 |
| `server/internal/governance/execution_notice.go#noticeOwnerRole/#ResolveNoticeOwner` | 已映射维护→development、非维护→requirement；按 `member(workspace_id,user_id)` 校验 owner，缺失／无效／非成员返回无可用 owner；不是取 `member.id` |
| `server/internal/governance/execution_notice_wiring.go#notifyFact/#runNoticeIdentity` | 已先查 CR owner，查不到才进入回退；run 身份来自 `pipeline_run.started_by`，查询错误时停止通知 |
| `server/internal/governance/execution_notice.go#ResolveNoticeRecipient` | **具体偏差**：授权类回退会验证传入 starter 的成员身份；维护类却忽略 starter，按创建顺序挑 workspace owner/admin。因此「维护类无 CR owner→starter→仍无不发」尚不能宣称与当前源码一致；本轮只写规定与差距，不改代码，也不把旧分支纳为合同例外 |
| `server/internal/governance/execution_notice.go#DeliverNoticeTx`、`server/migrations/646_cr_execution_notice.up.sql` | 已用 `(workspace_id,dedupe_key)` 冲突取原 notice/Inbox，notice 与 Inbox 同事务；Inbox `issue_id` 已取 `cr.shell_issue_id`，没有依赖新 details 键或新 partial UNIQUE 的必要 |
| `server/internal/governance/execution_notice.go#NoticeDedupeKey`、`runner.go#failRun` | 当前 key 含 CR/cause/证据摘要/audience/规范 recipient，workspace 由唯一约束覆盖；尚未证明可信 project 覆盖。失败接线对错误码求摘要，不能据此声称同码新失败／重要证据变化已不互吞 |
| `server/internal/governance/execution_notice_wiring.go#notifyFact/#recoverPendingNotices` | 业务事实与 notice 事务分离，恢复扫描仅覆盖已有 pending；notice 写前故障的逐事件重建仍未证明。保留 SC-NTF-007，不把缺口降为可接受的不丢通知保证 |

`execution_notice_wiring_test.go#TestNoticeGoesToTheRecordedRoleOwnerAndItsConversation` 已有 development owner 优先与会话链接的测试源码，但不覆盖无 owner 的维护回退；本轮未执行，不能据测试存在宣称其通过或全链完成。

### 4. 仅沿用现有验收，边界不外扩

分组来源为 [收敛计划「四项验收保证」](../2026-10-22-aifi-45-authorized-execution/validation/notification-convergence-plan-20261109.md#四项验收保证)：

| 保证 | 本轮对应范围／原编号 |
|---|---|
| 1 恢复判定 | M008 的 SC/TC-MG-015/016 与原 M mapping、settlement、再准入验收；覆盖未知、可信 no_effect、迟到、并发、混版。既有 VM/VT 对归档分支的排除仍为历史边界，不计作已覆盖 |
| 2 事实与路由 | TC-NTF-001～004，005/006 的规范事件及重要变化；补核 owner 投影/成员 user_id、owner 优先、无 owner 才回退、仍无不发、CR 对话链接，均归原 TC，不另编号 |
| 3 通知责任恢复 | TC-NTF-005/007 的并发唯一、写 notice 前及广播/标记前故障、原身份重建与消费者同 Inbox ID 幂等；真实调用链和消费端仍需证据 |
| 4 会话隐私 | 保留收敛计划中的既有保证，本轮 M008/M009 不修改其合同、不新增会话实现或验收项，不以通知恢复替代会话隐私出证 |

仍需人工落实：合法的双端增量重审及完整输入绑定；可信 no_effect/迟到排除、持久观察与混版互锁的具体生产机制；M009 可信 project/逐事件事实与写前重建来源、旧键兼容。维护回退偏差已有本轮明确规则，不重新询问路由方向，但须后续在相应实施范围补齐并验证。

本轮不改 proposal、test-plan、canonical、`.stdd.yaml`、pending-adjustments 或任何状态；不运行 Gate／测试、不提交，不借链接或文档登记推进阶段。

## M005 生产接线（AIFI-45 承接项）：当前事实与最小约束

**核查结论（2026-11-10，静态）**：可信 T 通道在 multica 侧**没有任何生产生产者**——`ApplyControlCommandTx`、`SettleControlCommandTx`、`ControlWorker.ApplyTx` 三个写入入口的非测试调用方均为 0，`ControlWorker` 只在测试中构造。因此生产链路上 `Admitted` 不可得，准入稳定停在 `WAIT_TRUSTED_T_COMMIT`，这属预期而非缺陷。

**实现时必须一次定清的四点**（本次不实现，仅记录约束）：

1. **单一写者**：由一个持有当前 owner fence 的消费者按 seq 顺序追加帧；不允许多实例并发写同一 lineage，也不允许绕开 `AppendVerdictFrameTx` 直接插表。
2. **身份统一**：当前准入查询假设 `cr_execution_control_settlement.request_id = cr_execution_consumption.task_id`，但 `ControlCommandInput` 没有 task id 字段、`RequestID` 由调用方给。实现时必须在「生产者把 RequestID 设为 task id」与「准入查询改为按真实关联键」之间**选定一个**，不得两处各自解释。
3. **游标与帧原子**：`AppendVerdictFrameTx` 已在同事务内校验 seq/prev_digest 并推进 cursor；消费者不得另建游标，否则恢复语义会分裂。
4. **失败与重放**：帧追加失败即整体回滚并重试；同一帧重放必须落到原行（唯一键 + seq 校验），不得产生第二条 verdict 或第二次 settlement。

**未完成即不得宣称**：`TC-RUN-001` 的「实际任务与 T receipt 匹配」、`CP-RUN-001` 的真实通过，均以本条落地为前提。

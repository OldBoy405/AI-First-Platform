> **2026-11-10 收窄前原样副本**（只读历史，现行设计见 `../design.md`）。正文相对链接以 change 根目录为基准；其中 M009 段已移回 AIFI-45（`projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/m009-attention-routing-spec-20261110.md`）。

# 可信 verdict 结果与命令绑定：tools 生产侧设计草案

> **SPEC thorough；Gate2 BLOCK，未批准实施。** 用户已确认两侧 proposal、thorough 模式，并以“采纳建议，继续”确认隔离裁决、受保护名单、效果分离和优先核旧协议四条方向；证据见 `../../../multica/changes/2026-10-22-aifi-45-authorized-execution/validation/verdict-authority-acceptance-20261030.md`。这不是 Gate2，也不证明实际生产者、签发者、信任根、现网与存量；字段、版本和部署接线仍未定。multica 同名 change 独立设计，双方接口尚未达成一致。

Agent 检查点的跨仓非执行映射草案见 `../../../multica/changes/2026-10-29-trusted-verdict-outcome-binding/validation/agent-cp-planning.md`；当前 agent-spec 仍为占位，不代表已定义安全执行入口或通过任何 CP。

## Context

`skills/shared/crctl/scripts/lib/execution-control-protocol.mjs` 的 verdict 操作使用 `execution-control-verdict/v1`、`execution-verdict/v1` 和 `tool-attestation`；验证器对 `domain || NUL || payloadBytes` 验签并检查基本 schema/purpose/domain/scope，不因此解释额外字段的授权语义。当前 `signControlEnvelope` 的 `manifest` 参数可选；提供时只检查相应域、范围与有效期等策略，不在此 helper 中核用途或私钥是否对应所列公钥，验签端须独立检查。不能仅凭此函数推定生产签发者或可信 manifest。`execution-control-store.mjs` 的帧摘要检查一致性，文件头明确其本身不认证签名、不串行化并发写者。

现有 Node verdict fixture 带 `verdict=permit`、`seq`；multica 入帧还要求 `epoch`、`sequence` 和 `previous_verdict_digest` 等。fixture 的基础验签不能证明它直接满足生产入帧，更不证明可信实际 effect。静态观察不证明部署、存量、调用方或不存在其他合法向量。证据与快照：`../../../multica/changes/2026-10-22-aifi-45-authorized-execution/validation/verdict-outcome-pre-spec-evidence-20261030.md`、`verdict-outcome-contract-20261029.md`。

五层事实必须分开：签名覆盖的字节、经授权的裁决、permit、实际 effect 和结算。permit 不能证明 effect；store checksum、签名长度、调用方声称的 kind 或 signer 自报身份均不能单独构成授权。

## Decisions（候选，须经 Gate2 裁决）

### D1. 先证明可信来源与权限，再决定签发协议

**方案：** 按用户采纳的方向，以归档的方案 C（受保护 daemon control 服务内隔离 T/Node worker）作为裁决签发的目标分工，M 独立验证；管理员维护受保护、可信固定的名单，普通 agent 不得修改名单或接触私钥。归档 SC-VC-008 / SC-TR-002 约束密钥用途、路径/pin 与禁止 agent enrollment；ADJ-11 第 4 项的内联 key 和路径 pin 的兼容关系须一并核清。归档 `projects/multica/archive/2026-10-27-trusted-verdict-channel/design.md` §8.1 将 trust-manifest 的原始字节 SHA-256 加绝对路径 pin 列为 `channel-component` 的版本/观测语义，由 operator 的受保护路径提供；该 profile 只能声明组件就绪，不是生产 activation 的证明。管理员对应归档 operator 信任根，恶意 operator 不在其保证范围；实际 pin 的来源、校验及隔离仍须证明。具体谁控制私钥、实际签发/部署和环境隔离仍未知，本 change 的 proposal 不授权接真实生产者。须明确何时基于何种权威事实形成裁决和 effect 证据，以及 key 用途、scope、时间、轮换/撤销权限与可信 manifest 的来源/pin。无可验证来源时不输出可用于新增 effect 的可信证明；不可由 agent、fixture 或普通 caller 自报替代。

**为什么：** 即使语法上成功签名，也不证明签名者有权证明业务结果；通用签名 helper 本身不是受信服务。2026-10-27 归档 ADJ-10 记录本机 agent 隔离不成立，作为组件级验收残余风险接受；ADJ-13 将 Windows 隔离移出该 change 的验收声称并延至后续 change，本次未复测。目标环境须重新出证；按已采纳方向，未验证环境不承载生产私钥或可信名单；归档 P0 门控另要求 P0 失败停止方案 C 相关切片、转 B 须另行提审，禁止运行时静默降级。

**备选：** 单以 key_id、环境变量、测试 key、任意 manifest 或合法 Ed25519 签名推断授权，排除。归档目标分工不等于现网已有该服务，不预设真实 signer 是 Ray 或某个现存部署。

### D2. 先核旧合同，再比较 wire 方案

**方案：** 按用户采纳的优先级，双方先核已批准版本、结果语义、原始签名字节及真实字段，逐项评估权威来源、命令/主体/链及代次绑定、接收方验证和负面向量，证明 (W-A) 现有合同是否足够；不足时才提出 (W-B) 经审批的兼容证明或限定范围方案，或 (W-C) 新 schema/domain。W-* 仅指 wire 备选，不是归档 P0 隔离方案 B/C。缺少材料表示尚未证明，不能单独断言生产没有其他格式。版本、字段、结果闭集与确切 bytes、拒绝/旧格式策略均需双方一致并经人审；v2 不是预选答案，不得把未知 payload 字段直接授予新权限。

**为什么：** 一端单方面扩展结果语义，可能与另一端归档规格冲突；无存量证据不能声称兼容或无迁移。

**备选：** 重签旧 payload、仅改 verifier、在 v1 静默解释任意字段、或预先冻结全部旧记录而不设计 no_effect/恢复，均不足。

### D3. 绑定权威请求、冻结命令与主体

**方案：** 在方案获得证据后明确 request、scope、store/lineage、epoch/sequence/prev、冻结命令字节或经批准摘要、权威主体与 generation 的逐字段绑定。producer 必须核验这些值与可信源的一致性；consumer 独立核验，不能只比较 caller 两份自报。不同算法/前像（协议摘要、store frame 摘要、M 链摘要和 command 摘要）及字段映射须分别命名并测量，不可无依据互换。归档 ADJ-11 称帧链可直接建立在域分隔 payload digest 上，而当前 M `last_digest` 用 payload-only digest；是否同一合同字段待核，不能预设差异合理。

**为什么：** 合法签名若能换命令、主体、请求或轮次，仍会错误授权。

**备选：** 仅保存未认证摘要、从新 JSON 重序列化取得签名 bytes 或只检查 request UUID，均不充分。规范化方法与字段名尚未确定。

### D4. 实际 effect、恢复与并发边界

**方案：** 对每类 effect 指明真实权威事实来源、执行点和可验证回执；permit 只表达批准，不预言外部系统已发生 effect。数据库 dispatch 只证明同事务入队，不代表 agent 启动或后续工作完成。能对应到 SC-VC-015／SC-TR-006 恢复表所列观察的，按表逐类处理，包括原 bytes 导入和原 command 重放（适用性待双端评审）；不得一概改成冻结。其他未识别到既有适用合同的情形默认冻结仅为拟议规则，待批准；幂等重放返回已认证原结果，不重复执行。外部 effect 与数据库不是天然原子，超时/丢回执须保持不确定并阻止新增 effect；须设计可信回执或在足够可信的远端对账条件下识别结果，不能仅凭普通 caller 自报、单次目标状态或盲目重试推断本次 attempt 成败。锁和防整链回滚另行设计、测试。用户已同意准备“目标达成、本次待核、不重推、不自动发出下一受保护动作”的修订方案；归档 SC-MG-015 对特定 unknown + 远端含目标情形要求结算成功，SC-MG-016 对特定 prev/终态组合规定 not_attempted 和新 attempt。改变这些分支须两侧配对修订并审批，获批前归档合同仍有效；本 change 对冲突分支的合同收敛、测试与 Gate2 标记 BLOCK，不以草案覆盖归档。此 BLOCK 不是运行时冻结指令，也不证明现码或线上已实现或未实现归档行为。

**恢复合同适用性（待双端评审）：**merge publish 对照归档 SC-MG-015～017；store/journal/frame/head 中断对照 SC-VC-015 / SC-TR-006 的恢复表，该表包含导入原 verdict bytes、重放原 command 等动作，不能一概改成冻结。SC-VC-022 的后续 effect 前判决结算按原合同验证，不连带列为待批远端修订。对其他未识别出已有适用合同的外部 effect，本 change 的默认冻结是**拟议规则**，待 Gate2/适用合同批准；尚不能据此声称现行合同或运行时行为。跨类型归属、可信终态和恢复动作的判定仍须在矩阵中逐格闭合。

归档 SC-MG-015 的 unknown+远端含 expected 按祖先关系判断，要求不重推并结算成功；SC-MG-016 的 intent+prev、settled_no_effect+unknown+prev 要求先以 not_attempted 结算旧 attempt、再以 attempt+1 reserve，不得直接 push 或复用旧 attempt。两个归档用例 TC-MG-015/016 的实际回归执行与归属待定，当前不以引用代替覆盖。另有 `settled_no_effect + unknown + 远端含 expected` 与 settlement immutable、SC-VC-035 原 mapping/新 attempt 的衔接待合同核定；不得把候选“保全矛盾证据”或任一结算结果冒称该组合已获批准。SC-MG-016 与 SC-MG-020／SC-VC-035 的衔接、已 settled 时与不可变 settlement 的对应，以及 SC-MG-016 的候选收紧，见工作区 `projects/multica/changes/2026-10-29-trusted-verdict-outcome-binding/validation/remote-recovery-contract-matrix-20261101.md`。SC-VC-022 的已认证 no_effect 与 issued 结果未知的冻结按各自适用条件区分，未定的远端证据要求不能静默收紧原合同。

**为什么：** 本地 frame checksum 不保证跨进程互斥、生产签名或防回滚。

**备选：** 凭 store 内存状态声称 exactly-once、仅靠 checksum 防恶意替换或把签名后的 permit 当效果回执，均不足。

### D5. 兼容、撤销与跨仓验证

**方案：** 不假定旧 verdict/数据不存在；未知、旧格式或无法认证内容不支持新增 effect。已在途状态、no_effect、历史查询、轮换、恢复和前滚/回滚分别设计，不能追溯伪造事实。先形成共享正负向量和精确协议清单，以 Go↔Node 的原始 bytes、purpose/scope 与结果绑定为准；仅组件互验不替代 AIFI-45 的真实入口、代次、锁及数据库 RUN 验收。

**为什么：** 静态未发现生产调用链不证明现网无存量，示例向量不构成完整协议。

**备选：** 直接删除历史、暗中迁移/重签或者让两仓重复将同一跨语言证据计入独立验收，排除。

### 范围、规格责任与实现归属（待人审）

| 项目 | 本 change 草案职责 | 不在本草案中自动授权的实现 |
|---|---|---|
| REQ-VT-001/002 | 调研可信来源、签发责任、wire 和命令绑定，定义跨仓合同约束 | 本草案不更改签名代码、不接真实生产者；若将来超出已确认 proposal，须先修订并重新人审 |
| REQ-VT-003/004/005 | 列出重放、恢复、历史和 key 事件的合同级目标 | 生产效果执行、部署和 AIFI-45 消费侧修复不由此草案自动授权 |
| 共享跨语言向量 | 定义双方可复核的原 bytes 和负面语义 | 拟由 M 的 VM 014 唯一计数，T 的 VT 007 引用同一证据；归属待人审，不重复计数 |
| readiness | 不预定签名合同修改 | 消费侧先由 AIFI-45 依据既有合同评估；若须修改 readiness 签名合同，另行评审 |

用户已确认先核 W-A 的方向，不等于已证明 W-A 足够或选定 W-B/W-C；不能把调查和比较当作实现或部署批准。

## Architecture（待验证候选，并非已存在的生产链）

```text
受保护的隔离 T worker + 已固定信任名单                  [目标，实际待核]
                 │ 核权威事实并签裁决；保留原 bytes
                 ▼
M 独立验签 / 绑定 / 当前授权 / 代次与锁                 [候选]
        ├─ 本地效果：在批准事务内执行并结算
        └─ 外部效果：受控执行后取得可信回执或对账；未知按适用合同处理，无适用合同则冻结（拟议）
                 ▼
AIFI-45 真实入口、环境证据与 Gate3                       [独立验收]
```

不假设 tools 本地 store 是唯一生产执行者或外部操作的权威见证者。实际 effect 证据可能来自不同可信来源，必须由权威负责人和双方设计明确。

### 按效果类型区分时序与恢复

1. 签发被认证的 permit 只允许按既有合同继续，不是效果已发生的证据。
2. 某个 T 或 M 事务内的 `dispatch` 等效果，在执行及结算边界形成对应可信事实；不能要求该效果在执行之前已发生。下一次 task-start、publish 或其他效果是不同事件，继续受自己的准入与代次门禁约束。
3. 尚未创建的无效请求可拒绝；created 且从未 issue 可按既有合同取消；issued 或 uncertain 的未知结果冻结。result_ready 依据认证裁决、可信 effect/no_effect 事实及合同结算，仍未知则冻结；settled 只重放原记录；不能因未知或 ACK 推断 no_effect 或释放 slot。
4. 已认证的 pending/deny/stopped 或过时/撤销 permit 按既有归档 SC-VC-022 与撤销线性化合同处理 no_effect；unknown 的证明、失败关闭与释放条件另须双仓设计，不由未认证状态文字触发。

M 的 `settlement.verdict_id` 在不同写入者中可能承载传入 verdict、grant ID 或 head record ID；具体见 M 同名 change 的写入清单。双方必须逐类型确定权威对象和责任边界，不能把同名列直接视为同一种 tool verdict。

## Risks / Trade-offs 与 Gate2 阻塞

| 风险 / 未决项 | 当前约束或下一步 |
|---|---|
| 生产者、key 控制与 manifest 权威未知 | 沿用已采纳的隔离控制服务与管理员固定名单方向，但须核实际责任、隔离、信任和签发时机；未知时不能签发可放行证明 |
| 历史本机 agent 隔离失败，当前目标环境未知 | 不把组件级验收当生产隔离出证；部署/readiness 前重新取得目标身份边界证据，不在未验证环境承载生产私钥或可信名单，不虚构逐请求的隔离状态接口 |
| 前序链 digest 与归档 ADJ-8/11 存疑 | ADJ-8 要求开工前核公式；ADJ-11 描述域分隔协议摘要及链可用该摘要。M 的 Go/Node fixture 显式使用 payload-only 前驱，但该前驱由 M 测试脚本构造，不能当作 T 生产方证明。先冻结现状、核批准字段/存量及正负向量，再评审保留或变更；详见工作区 `projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/verdict-recovery-digest-decision-20261030.md` |
| Go/Node 的 key purpose 和恢复身份待协调 | Go 接受 `deployment-observer`，Node 当前不接受；human resume 与 M 数据库 grant 的关系、清单作用域及兼容待审，不能预设同一文件可直接通用 |
| 远端对账与已批准恢复合同需逐项协调 | 用户已同意准备“目标达成但本次待核、不重推、不自动发出下一受保护动作”的修订方案；SC-MG-015/016 若改变须按原合同变更流程审批。unknown+远端 prev+服务端 no_effect 须核可信性与迟到 push；helper 的 replayed/意外 reserve/report 及 `mergeCr` 接线均待核，不能静默替代归档。方案见工作区 `projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/remote-merge-recovery-amendment-proposal-20261030.md` |
| 两仓 wire、结果、digest、主体/generation 与 producer 时序未定 | 共审字段/前像/算法/错误矩阵及负面向量；不得假设现有 fixture 是入帧证明 |
| 现存 signer 可不提供 manifest；store 不验签、不串行化 | 确认真实生产调用与所需策略后设计受控入口；不把现有库能力当完整生产授权 |
| 外部 effect 与崩溃恢复无法简单原子化 | 用户对“真实业务使用或可能已有旧数据”答“是”，不拆推两项分别成立；按可能有存量与在途设计。明确可靠证据、未知态、旧入口/副本限制和人工恢复；不重写历史、不承诺透明自动回滚 |
| 旧格式、撤销、历史数据和部署状态未知 | 权威存量/部署事实与兼容、回滚方案齐备后再实施，不读取历史事故库 |
| key 泄露或签发时间未知 | 新 effect 停止条件、可信时间与既有证据是否受影响由权威 key 事件决定，不预设历史全部有效或失效 |
| 两仓和 AIFI-45 证据范围不清 | 给跨语言向量、真实入口和数据库验证分别指定单一计数归属，未指定前不算已验收 |
| 提案范围与交付责任不清 | 区分签名合同与消费侧修复；若需扩大已确认 proposal，走真实修订与重审，不把草案当实现授权 |

**Gate2 不可提交为已完成：** 双方需共同确定上述权威事实、共享合同、外部效果和兼容恢复方案；本草案不批准真实签发、源码修改、数据库、部署或自动审批。

## M008 配对修订草稿（未批准）

用户已选择本 10-29 change 承载 M/T 恢复合同的 SPEC 配对评审；这是对原已确认 proposal 的范围增量，不是 Gate1 重签、Gate2 或 BUILD 授权。原条款及依据见 [AIFI-45 M008 草案](../../../multica/changes/2026-10-22-aifi-45-authorized-execution/validation/wp4-sc-mg-015-016-paired-amendment-20261104.md)，消费侧见 [M 配对草案](../../../multica/changes/2026-10-29-trusted-verdict-outcome-binding/design.md)。既有 [MERGED-SCOPE](MERGED-SCOPE-20261109.md) 另行保留，不由本节替代。

- **SC-MG-015 拟议边界**：给定原 attempt 的效果未知，即使远端包含 expected，也不能仅由目标状态认定该 attempt 已产生效果；effect 和 no-effect 均无可信依据且尚未结算时，不新写任一 settlement，保留未决排他约束，停止自动重推及下一受保护动作。已有适用合同认可的可信 no-effect 可按其合同处理，但再发布仍需另行证明旧执行者不会迟到。`confirmed` 正常前进及 history-rewrite 分支保持原条款。
- **SC-MG-016 拟议边界**：给定 `intent + at_prev` 或其他无法排除旧执行者迟到的观察，仅有远端位置或调用方自报不能证明本 attempt 无效果，不能据此结算 `not_attempted` 后进入下一 attempt。可信 no-effect 与旧执行者围栏均未接通时保持自动重试关闭；不把这一规则泛化为禁止所有合法的 no-effect。
- 对已有 `settled_no_effect + unknown + prev` 或 `settled_no_effect + expected`，先读取 M 侧权威 settlement 和原映射，不更改已 settled；返回原映射不等于新发布获授权。人工对账与后续准入条件待双方评审，不能声称已结算数据库 slot 仍被占用。现有 `planRecovery` helper 没有生产调用方，不证明生产恢复安全。
- 需配对原 `TC-MG-015/016` 和 M 的 settlement/mapping 覆盖可信效果、未知、迟到、并发及混版恢复；沿用原验收分母，真实入口和可信证据 producer、fencing、存量与回滚均待核定。

两侧 Gate1 为历史无指纹确认，现行重签入口未证明能绑定本次范围增量；Gate 输入也不会因链接自动纳入 M008 条款页或 MERGED-SCOPE。须先由 STDD 维护者明确合法、可审计的修订、人审及完整输入绑定入口。不修改归档 canonical 或任何 Gate 投影。

## AIFI-45 本轮承接增量（待批准）

本节把用户口头确认的 M008／M009 方向纳入现有载体供正式评审，不表示合同生效、实施授权或验收结论。前文、原 `specs/verdict-channel/spec.md`、MERGED-SCOPE、AIFI-45 及归档合同均保留作历史和来源；不由本增量覆盖，也不将早期摘要中的未定项冒称已经实现。

### 1. M008 配对条款进入 specs，不再只有 design 摘要

完整待审 SC-MG-015/016 与 SC-VC-035 配对条款见 [trusted-merge-gate 增量规格](specs/trusted-merge-gate/spec.md)，与 [M 同文规格](../../../multica/changes/2026-10-29-trusted-verdict-outcome-binding/specs/trusted-merge-gate/spec.md)的 Requirements 逐条相同。来源为 [M008 条款草案](../../../multica/changes/2026-10-22-aifi-45-authorized-execution/validation/wp4-sc-mg-015-016-paired-amendment-20261104.md) §3–8；T 守恢复决策／发布入口，M 守权威 settlement／mapping／真实准入，不能各自定义另一份语义。

| 情形 | 本轮拟议必须行为／双端分工 | 现有机制为何不足 |
|---|---|---|
| `unknown + expected`（含后继） | T 不重推，只记目标达成观察；M 不将其当作本 attempt effect。effect/no-effect 均无可信证据且尚未结算时不新写任一 settlement，保留未决排他约束，停止下一受保护动作；可信 no-effect 按适用合同处理 | 目标状态不证明由本 attempt 达成，原成功结算路径会伪造效果归属 |
| `intent + prev` 或请求新尝试 | 不直接 push、不复用旧 attempt；新尝试须同时有可信且绑定该 attempt 的 no_effect、旧执行者不会迟到的证明及完整再准入，缺一禁止新 reserve/push | intent、prev、caller 布尔值和 no_effect 终态都不能单独证明旧 push 已停止 |
| 已有 settlement，包括 `settled_no_effect + unknown + prev/expected` | M 原结算/mapping 保留；T 只读／重放原记录，不再以 not_attempted 结算、不改成 effect。SC-VC-035 的 `200 原结果/200 原 mapping/201 新 command/409` 四支保留；200 原 mapping 不授权新发布 | 已结算使当前查询认为 slot 结束，旧 mapping 返回也不等于新 command 或安全执行许可 |
| 已结算而安全再尝试条件仍不足 | T/M 在各自真实入口另行阻断新 effect，不虚称已结算数据库 slot 仍占用；持久观察、互锁和混版机制待配对审议 | 未结算 reservation 的占用保护不能覆盖已有 settlement，helper 局部 halt 也没有生产调用方证明 |

confirmed 正常前进、退回 prev 的 history rewrite、分叉禁新 publish 等无冲突分支保留；SC-VC-022 合法 no-effect、撤销线性化及 SC-VC-015/SC-TR-006 其他恢复表不被一概冻结。人工对账不证明效果、不解锁也不授权重推。本次不预设新终态、终态重开或迁移；`planRecovery` 局部实现不能证明生产恢复或安全重试能力。

### 2. M009 对应 M 的唯一通知身份与角色事实链

完整通知要求在 [M attention-routing 增量规格](../../../multica/changes/2026-10-29-trusted-verdict-outcome-binding/specs/attention-routing/spec.md)，T 不另写通知账或第二套去重判定。来源为 [M009 身份草案](../../../multica/changes/2026-10-22-aifi-45-authorized-execution/validation/m009-notice-identity-amendment-draft-20261109.md)与本轮用户补充；原草案关于责任来源未知的结论保留为历史，收件路由现在有明确 CR 角色来源，但不以通知赋权。

- **事实生产与投影**：crctl 注册／交接记录 `owners.requirement|development|test` 的角色对象，经 owners outbox 交给 `crsync.applyOwners` 投影到同 workspace/CR 的 `cr.owners`；其中 `id` 必须是该 workspace 成员 `user_id`，不是显示名、Agent ID 或 `member.id`。原因是 workspace 管理角色和任意 UUID 不能表达该 CR 的角色责任。
- **对应路由**：授权类→requirement、维护类→development；仅无可用 CR owner 才退回启动该 run 的任务身份，仍无则不发，读取出错停止。交付沿现有非维护 requirement 路由，test 保留投影而不新增受众；路由不改变实际审批／执行权限。原因是 owner/starter 可作提醒对象，但不自动获得授权资格。
- **唯一身份与会话**：M 复用既有 `cr_execution_notice (workspace_id,dedupe_key)`，notice/Inbox 同事务、冲突复用原 ID；Inbox `issue_id` 取该 CR 的 `cr.shell_issue_id`。不新增 Inbox details 键、partial UNIQUE、迁移、调度器或回填。原因是 commit 级事件去重与读侧聚合不足，但既有 notice 已能持久标识内部通知，无须另造结构。
- **不降低恢复保证**：规范身份覆盖可信 workspace/project/CR、稳定事件、重要证据、非空受众及规范接收者；同事实跨 run/commit 不变，重要变化不吞。pending/delivered 保存在 notice，提交后广播、原 Inbox ID 恢复及消费端幂等；notice 写前失败仍须从既有持久业务事实按原身份重建，不回滚业务或重做副作用。原因是 pending 扫描不能补造尚未写入的通知意图。

与当前代码的核对以 [M design 源码事实表](../../../multica/changes/2026-10-29-trusted-verdict-outcome-binding/design.md#aifi-45-本轮承接增量待批准)为准：owner 优先和 CR 会话链接已有接线；`applyOwners` 仅核 UUID 形状，成员资格在通知解析时按 workspace/user_id 核验；维护类无 owner 的现有 fallback 仍挑 workspace owner/admin，而不是 starter，与本轮规则存在明确偏差。可信 project／新失败证据和 notice 写前重建也未证明完整；T 不以引用 M 规格或局部测试存在宣称这些缺口已闭合。

### 3. 沿用四项保证与原编号，不扩张任务

来源为 [收敛计划「四项验收保证」](../../../multica/changes/2026-10-22-aifi-45-authorized-execution/validation/notification-convergence-plan-20261109.md#四项验收保证)：第 1 项由原 TC-MG-015/016 及 M 原 mapping／settlement／再准入验收承接；第 2、3 项由原 TC-NTF-001～007 承接 CR owner/member user_id、fallback、会话链接、规范身份与写前／广播故障恢复；第 4 项会话隐私保证保留，本轮不增改其合同、实现或 TC。既有 TC-VT-009/014、TC-VM-009/016/018 对归档分支的排除保留为历史边界，不因此重复计数或宣称覆盖。所有补充分支标明 AIFI-45 M008/M009 来源，不另立 TC 编号体系。

仍需人工落实与 M 相同的三组事项：合法的双端增量重审与完整输入绑定；可信 no_effect／迟到排除及持久观察、混版互锁的具体机制；M009 可信 project／逐事件事实与写前重建来源、旧键兼容。维护 fallback 的既定规则不重开方向选择，留待所属实施范围补齐验证。

本轮不改 proposal、test-plan、canonical、`.stdd.yaml`、pending-adjustments 或状态，不运行 Gate／测试、不提交。文档承接、链接和同文不代替人工评审或真实入口证据。

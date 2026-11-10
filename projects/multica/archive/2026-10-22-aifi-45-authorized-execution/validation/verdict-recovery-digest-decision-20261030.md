# 远端恢复与摘要兼容：候选方案及协助清单

**状态：方案草稿，非批准或现网安全结论。** 用户已采纳“隔离签发、保护信任名单、区分授权与效果、未知时暂停及先评估旧合同”的方向；那不是对下面具体业务取舍的确认，也不是 Gate2。两侧 `2026-10-29-trusted-verdict-outcome-binding` 仍为 SPEC/thorough，Gate2 pending；原 AIFI-45 Gate3 NO-GO。本文件不改变已归档要求、生产代码、CR 状态或资源 HOLD。

## 1. 远端发布：建议将「目标已达成」与「本次尝试的结果」分开

目标分支已经包含期望提交，能说明目标**当前**已达成，前提是远端身份、仓库、分支、观察时点及祖先关系均有可信证据；它本身未必能说明是哪次推送导致。这两件事涉及用户显示、命令结算、配额及后续动作，不能自动视作同一事实。

**建议的保守行为，待业务与已有合同共同审定：**

| 情况 | 建议 | 影响及未决 |
|---|---|---|
| 可信远端当前已包含目标，但本次尝试的发生与否不明 | 候选：向使用者报告「目标当前已达成、此次尝试待核」；不重复推送，也不把目标状态直接冒充该尝试的可信效果或自动发放下一次授权 | 归档 SC-MG-015 对 `unknown` + 远端含 expected 要求不重推并**结算成功**；若把此成功结算改成待核，将改变该已批准要求，须按原合同的变更流程审议和审批。如何结算与释放槽位未定 |
| 已发出或可能发出 push，远端仍在旧位置 | 候选：无可信证据排除迟到 push 时保持未知、不重推；服务端写了 `settled_no_effect` 但来源不能认证，也不足以自动重试 | 可能需要人工介入。SC-MG-016 已将服务端 `settled_no_effect` 作为重试条件之一；若新增可信证明前置，属于收紧已批准要求，须按原合同变更流程审议和审批 |
| 确已证明本次未发生，且证明覆盖未决、迟到、并发和撤销/代次 | 候选：在符合批准的授权、旧 attempt 结算和新 attempt 规则后才允许重试 | 可信证明来源、格式、远端能力及槽位释放均未定；单次读到旧 SHA 不足以证明。若增加证明前置而收紧 SC-MG-016，须正式修订并审批，不自行重解释已批准条款 |
| `confirmed` 后远端正常前进 | 不做新动作 | 对照 SC-MG-015；不能借此给后续独立 effect 授权 |
| 已确认后远端退回 prev，或不论确认与否远端出现合同所述分叉 | 进入 uncertain，禁止任何新 publish 并转核查 | 分别对照 SC-MG-015/017；不把历史改写算作本次 no_effect |

原 SC-MG-016 对 `intent` + 远端 prev 已有旧 attempt 结算和新 reserve 的明确要求。候选方案希望增加可证明写盘、迟到和实际网络调用的前置，**这是拟收紧合同，不是对原条款的单方面解释**；正式修订前仍须保留原文与差异。批准前，该表只是候选安全边界，不替代完整恢复矩阵。

### 静态实现核对，不能推断现网

- T `skills/shared/crctl/scripts/lib/merge-effects.mjs:77-119` 的 `planRecovery` 只返回决策，`intent+at_prev` 返回 PUSH，`unknown+at_prev+server settled_no_effect` 返回 `RESERVE_NEXT_ATTEMPT`；该函数不完成旧 attempt 结算与新 reserve。`merge-effects.test.mjs:135-143` 标题称须重新 reserve，却只断言该决策值是 PUSH，不能证明 SC-MG-016 所要求的先结算、再 reserve、不得直接 push 已兑现。限定检索未发现生产代码消费该 action；动态调用、其他仓或部署仍未知。`intent+contains_expected` 也返回 SETTLE_SUCCESS，超出 SC-MG-015 的 `unknown` given，是否另有批准要求覆盖待核。
- T 同文件 `:168-200` 的 `runMergeEffect` 对 reserve 的 revoked、conflict、`ok===false` 有分支，但未见对 `replayed` 的处理；成功路径继续保存 unknown、push、report。它等待 report promise，但未检查 report 返回值；report 抛错会中断，不能一概说 report 失败都被忽略。仅从返回值角度未证明持久结算成功。
- M `server/internal/governance/execution_merge_effect.go:143-168,202-228` 当前对相同 lineage/digest 的已结算记录返回旧 reservation、`Replayed=true`；report 接受 caller 提供的 kind，本函数不认证远端事实，插入遇到 request 冲突使用 `DO NOTHING` 且未检查影响行数。`server/migrations/648_cr_execution_control.up.sql:64` 对 `(lineage_id,candidate_digest)` 唯一约束。M 测试 `execution_merge_effect_test.go:125-158` 静态断言同输入结算后重放、换输入才开 attempt 2；T 本地 `resolveAttempt` (`merge-effects.mjs:128-144`) 对未结算同输入和已结算的分支与 M 函数不同。限定范围内，这些断言不能证明归档 SC-MG-016 的同输入新 attempt 行为；是否有别处账本或适配仍待核。
- M 当前 report 的 kind 和 settlement 表只接受 `effect` / `no_effect`（`execution_merge_effect.go:202-204`、`648_cr_execution_control.up.sql:180`），没有单独的 `not_attempted` kind。SC-MG-016 要求的该事实能否通过别处或附加内容表达，须核完整合同与适配，不能仅凭此断言一定需要新增表或字段。
- **假设性组合风险，未证明存在实际接线：** 若将来的调用方先把 journal 转出 unknown（helper 会直接拒绝 unknown），并且适配器把 M 的已结算 no_effect 旧 reservation 作为 T 可继续的成功 reserve，而 T 不检查 replayed，则可能继续 push；若 report 用同 request 且冲突被忽略，账本仍保留旧 no_effect。上述状态转移、接线、push 成功及 report 输入均为假设，不是现网事实或已运行测试。
- **reserve 边界也待定义：** T 的 helper 若收到 `null` 或未满足三类拒绝条件的非预期对象，静态上会继续 push；Go 结果结构与 T callback 的适配合同未见，因此不能据此推断两者已在运行中直接连接。若 reserve 已提交但 durable journal 未写成 unknown 时崩溃，重入后的安全恢复亦须按最终适配、事务与持久化链核验；不能用 helper 的单元模拟代替完整证明。
- T `skills/shared/crctl/scripts/crctl.mjs:5373-5391` 的 `cmdMerge` 检查状态/已有 gate 后调用 `mergeCr`；`lib/workspace-transactions.mjs:2159-2200` 可见直接 lease push，push 返回后才设置 `pushed`；rebuild 分支会改变 base/mergeSha，须与 SC-MG-018 按真实前置逐项核对。对 T 仓 `*.mjs` 的限定文本检索，`runMergeEffect` / `planRecovery` 除模块内封装外只见测试引用；不能由此否认动态调用、其他分支/仓、外层控制或已部署产物。当前源代码可见的这条路径尚未证明接入所述 reserve/report；旧 gate 存在也不等于该路径已满足新合同。
- **以上是静态代码和假设条件，不是已证实线上可利用漏洞，也不是可直接部署的修复计划。** 没有连接数据库或服务，没有运行测试。

## 2. 不同摘要：先核清合同与存量，不擅自改写或双算法降级

已核的不同用途：

| 目的 | 当前前像/证据 | 建议 |
|---|---|---|
| 验签协议摘要 | `SHA256(domain UTF-8 bytes || 0x00 || raw payload bytes)`；归档 ADJ-11 明确协议前像，SC-VC-007 要求两端对同一签名字节得到相同 digest | 保持已批准协议定义和原始字节验签，不以重序列化替代 |
| M verdict 链前驱 | 当前 `execution_control_store_state.go:414-415,461-470,493-497` 使用 `SHA256(raw payload bytes)`；M 仓的 Go/Node fixture `crosslang_test/interop_test.go:86-103,236-245` 静态将前驱设成 payload SHA 且断言不是协议摘要 | fixture 中 Node 使用 T 协议库签验，但前驱字段由 M 测试脚本构造；不证明 T 生产方已采用该选择。保留现状不改历史，先与归档 SC-VC-010 和 ADJ-8/11 核对，再由双方审定字段及兼容策略 |
| T 文件 store 帧链 | 当前 `execution-control-store.mjs:145-181,251-264` 对 frame body 的 JSON 字节求摘要 | 作为 T 内部帧摘要单独记录，不直接当作 M 的前驱或协议摘要 |

归档 ADJ-8 `design-adjustments.md:101-103` 要求 S3 动工前核对 digest 公式；ADJ-11 `:133,142` 明确协议摘要域分隔，同时用「可以」描述 S3 帧链直接建立在该摘要上。SC-VC-010 要求前驱指向上一帧，却未在该 SC 中写公式。**这些证据尚不能判定 payload-only 已获批准，也不能仅凭「可以」推断必然冲突。** 核对完成前冻结现状、不改写存量；先审字段、两侧生产者和迁移，再选保留或变更。不应把不同前像当作同一字段无条件互换。若以后确需改公式，须另审版本/epoch 切换、可信历史和在途命令的处理，并先取得隔离测试及部署证据；不能默认无数据、承诺无条件回滚或自动接受两种公式。

另外，当前 `ApplyControlCommandTx` 自身未见新 command `prev_digest` 与 cursor、`expected_seq` 的比较（`execution_control_store_state.go:71-73,98-105,148-220`）；注释将该责任交给调用方。可能有其他层约束，需追完整调用链并按批准合同测试，不据此宣称线上已可绕过。

## 3. 真正需要人的协助

1. **凭据处置（优先，若尚未完成）。** 此前一次容器信息检查使数据库应用账户密码及开发验证码进入工具输出和模型上下文，并作为请求输入发送到模型服务；该账户与共享服务的具体关联未经独立核验。两项应按**已泄露**处理：建议由有权限的人评估维护窗口、轮换/失效，并向模型服务方确认日志留存及删除政策；按组织政策处理留存。详情见 `container-inspect-credential-exposure.md`。只需告知「已处理 / 已安排 / 不确定」，**不要发送密码、验证码、连接串或容器环境变量**。历史事故库及容器仍 HOLD，我不会代为操作。
2. **业务取舍：是否研究收紧已批准的自动恢复？** 不是重新询问已采纳的「未知时暂停」方向。现有 SC-MG-015 对 `unknown` + 远端含目标写的是结算成功；SC-MG-016 在指定前提下要求先以 `not_attempted` 结算旧 attempt，再以 attempt+1 重新 reserve，不得直接 push 或复用旧 attempt。建议研究更保守的方案：显示目标已达成但未证实本次尝试时不重复发布，保留待核、不自动开展下一次受保护动作；这可能需要人工核查，且若改变成功结算或增加重试条件，必须正式修订相关已批准要求并审批。此处只请求是否认可**研究该取舍**，不是批准修订、Gate2 或忽略原合同。
3. **部署事实，无需猜测技术负责人。** 若用户知道该功能是否已服务真实业务、是否可能存在旧数据，请只答「是 / 否 / 不确定」；不知道时建议按「可能有存量」设计，先冻结不兼容情形，不读取、改写或删除旧数据。后续需要真正启用前，由有权人员提供不含秘密的环境/隔离及清单保护证明；不需在聊天里提供密钥。

两侧摘要公式和测试细节由工程侧继续核对、提出方案；不要求用户选择散列算法。应制定并在获批隔离环境中验证：相同输入 no_effect 后重 reserve、reserve 提交后/写 unknown 前崩溃、reserve 意外返回结构、report 冲突或无匹配行、intent + prev 的完整结算与新 reserve，以及真实 merge/finalize 入口与远端对账。当前均未运行；Go governance 父包的测试初始化依赖数据库，本任务中须先证明初始化安全并使用获批的隔离环境，不能直接运行。完整 Gate2 材料准备好后另行呈审；方向赞同不代替 Gate2，亦不允许调整旧事故库、原 runner、生产部署或任何 CR 审批。

## 4. 本轮证据边界

两项只读研究请求 `GBClaude/claude-opus-5-5:high`，对应 session `01a18be3-fd51-7020-aecc-d4e2160fc8cf`（摘要）与 `01a18be3-fd5e-7020-aecc-d4e409469cc5`（恢复）；独立复核 session `01a18bed-7ec2-7020-aecc-d4e675327791` 同请求模型；实际 backend 均无回执，记 unknown。初审指出摘要倾向性、归档修订的呈现、恢复路径及凭据事故描述；协调者修订后定向复核未发现妨碍用户决定的事实错误，建议补充的假设前提及表述细节已同步。复核为草案层面，不构成生产安全签核或审批。未运行测试、连接服务/数据库、检查容器、读取密钥或修改产品源码。限定检索和本地工作树不证明部署状态。批准未完成。

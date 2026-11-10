# 已有 verdict 合同复用评估（静态，未定方案）

## 问题及结论

用户采纳“先验证已有签名格式，确实不够再提兼容方案或新版本”的方向，原文及边界见 `verdict-authority-acceptance-20261030.md`。现有归档合同和当前两个工作树提供了可复用的验签、用途和链检查构件，但**现有材料不足以证明完整生产裁决合同能安全满足新增 effect 的要求**。这不是“证明旧协议必定不够”，更不是“已选 v2”：其他获批字段、生产适配路径、部署、信任配置、存量及格式均未知。两侧 Gate2 pending；不改变归档合同或实施范围。

`W/` 为本工作区，`M/` 为 sibling multica，`T/` 为 sibling tools。已批准要求、当前源码和生产事实分开判断。

## 验证矩阵

| 必要问题 | 已有证据 | 当前结论 / 下一步 |
|---|---|---|
| 谁可签及验证的密钥用途 | 归档 SC-VC-008 禁错 purpose；T 的 `verifyControlEnvelope` 和 M 的 `VerifyControlEnvelope` 依据给定 manifest 检查 key、purpose、domain、scope、有效期和签名。 | **组件能力存在，生产权威未证。** 两侧 loader 返回 manifest 摘要本身不核预期 pin；须由受保护上层证来源、pin、签发身份和隔离。2026-10-27 本机隔离不成立，本次未复测。 |
| 人审赋予何种结果语义 | 归档 SC-VC-006 要求未知字段不产生授权事实；当前 T 一个测试向量有 `verdict=permit`，M `verifyVerdictSubject` 的相关检查是请求和链字段。 | **未证明现有合同已经批准完整结果字段/闭集、以及两侧据此授权的语义。** 测试字段或签名字节不自动成为授权；仍须查是否存在其他权威合同和适配。 |
| request/链与冻结命令、主体、generation | M 入帧验证 signed `request_id`、`epoch`、`sequence`、`previous_verdict_digest`，并检查调用者提供的 store/lineage scope；当前 admission 查询中的 request/task 关系仍是待核假设。 | **有部分字段绑定，不等于所有权威绑定完成。** 逐字段确定服务端可信来源、同次交易与验收方式，不能只比较 caller 提交的相等值。 |
| 双端能否直接交互 | T 某基础 fixture 用 `seq`，缺 M 入帧要求的部分主体字段。Go 与 Node 均有原字节签名/验证能力。 | **该 fixture 不能证明可直接入帧或真实放行。** 仍可能有其他有效向量或适配；应在双方批准合同后建立原字节正负例及入帧测试。 |
| 摘要是同一种事实吗 | T 协议验签摘要采用 domain+NUL+原始 payload；M 入帧计算 payload 摘要并写入 cursor 链；T store 对固定顺序的 frame body JSON 做摘要；命令还有自己的摘要。归档 ADJ-11 写帧链可直接建立在域分隔 payload digest 上。 | **现码与归档说法的对应关系待核。** 分别命名来源、前像和被引用字段，再核 M 前序链与协议 digest 是否必须相同；不能把差异自动解释为合理分层，也不将不同前像无依据互换。首帧和跨链映射须依获批合同另证。 |
| 真实 effect / no_effect | permit 是许可；M 部分业务效果在本地事务内提交；通用 settlement 和远端 merge report 可接收 caller 输入；远端不在 DB 事务内。 | **不能以签名 permit 或 caller kind 单独证明实际效果。** 按本地/远端分别定义可信事实、事务/对账和未知处理；AIFI-45 的入口、generation 和锁单独验收。 |
| 恢复、旧签名与部署 | 归档要求未知不推断 no_effect、不凭 ACK 放槽；旧数据及部署未核实。 | **尚未证明安全恢复或防降级。** 明确历史记录只读与新 effect 判定、key 轮换/可信时间、在途 slot 与版本切换；不假定无旧数据。 |

## 双端待审绑定表（非已批准 wire）

下表把行为要求转为双方需回答的最小接口问题；最后一列列出的权威来源必须独立证明，不表示该生产入口已经存在。尚未核清的项不能用 caller 自报、两个相等输入或测试 fixture 自行填定。

| 判定事实 | 当前可复用部分 | Gate2 前必须确定 |
|---|---|---|
| request 与链位置 | M 验签后比对 signed `request_id`、`epoch`、`sequence`、`previous_verdict_digest` 与入帧参数，并在游标锁下核序号及前驱连续性 | 连续性不等于 slot/open/fence 已绑定；参数如何与受信命令及当前链独立绑定，`request_id=task_id` 仍是待核假设 |
| scope 与签发权限 | 双端验签核 key 的 manifest scope、payload scope 与验证函数调用方传入的期望 scope；T 签发侧 key policy 仅在传入 manifest 时检查 | 三种 scope 分别由谁授权；可信 signer、私钥控制、manifest 来源/pin、用途及 key 撤销/泄露的权威时间；有效签名不证明可信部署 |
| 冻结命令与代次 | 归档 SC-VC-023/027 和 `design.md` 的 task binding 已有 generation 绑定要求；T store 对输入命令算摘要 | M admission 当前按 CR 而非指定 generation 计数。双端须确定批准字段、摘要前像及从受信任务/命令记录独立核对 task/runtime/`dispatched_at` 的时点；不得单凭 caller 对齐字段 |
| 结果语义 | 归档已有 permit 与 deny/pending/stopped 的行为要求，验签可认证载荷字节 | 哪个已批准字段及闭集可授权 permit；未知字段不产生授权事实，不能把测试向量字段自动升级为合同 |
| 实际 effect 与 no_effect | 归档要求 ACK 不释放 slot，未知不释放，settlement 提交才释放；M 有事务 settlement，远端 report 与本地事务分离 | 各写入口的权威对象、实际效果证据和事务/远端边界；既有静态审查发现 M 追加 verdict 帧即清空 cursor `open_request_id`，其是否等于合同 slot 尚待确认，见 `verdict-cursor-boundary-20261028/REVIEW-STRONG.md`；不能由 caller kind 或目标状态自证本次结果 |
| 多种 digest 与恢复 | 协议摘要、M 链 payload 摘要和 T frame 摘要各有现有实现 | 各字段原像及映射，包括归档 SC-TR-007 的 T checkpoint `last_digest` 与 M `design.md` 中 cursor tail 是否同义；版本/旧数据兼容，以及获批恢复合同与真实入口如何衔接；不自行合并或改写历史 |

此表不替代部署/readiness 的隔离证明，不新增签名版本或服务；另须核 command 的 store/epoch 与 fence 签名覆盖、verdict 到达时的 command 状态及事务、settlement/admission/dispatch 锁序、cursor 与 command 顺序及约束修改的规格依据、Go/Node `deployment-observer` purpose 差异、human resume 与 DB grant 衔接、readiness 权威、key 泄露与历史有效性；详见 `verdict-cursor-boundary-20261028/DESIGN-CANDIDATE-STRONG.md`。双方须按实际调用链及既有合同补正负向量、逐入口测试并经人工 Gate2。

## 本轮复核：复用现有签验，但不能把存储帧直接当作可信 verdict

本节为当前工作树的限定只读复核，不是批准后的生产契约。使用 UTF-8 文本经 CRLF→LF 后的 SHA-256，与文末历史 raw 摘要口径不同，不能直接比较并据此断言源码变更。

- T `execution-control-protocol.mjs:410-430` 的 `signControlEnvelope` 在传入 manifest 时检查 key 的 domain/scope/有效期，但 manifest 为可选，且该签发函数未检查 key purpose；`test/execution-control-protocol.test.mjs:165-193` 有意省略 manifest 构造错 purpose 的攻击输入，再要求验证器拒绝。归档 ADJ-11 第 3 项记录签发、验签两端都应检查 domain/scope/有效期；现状与该记录的适用关系须评审，不能只用测试造包解释掉。purpose 的依据另见 ADJ-8 与 SC-TR-002，签发侧应否拒绝越用途仍须厘清，不能将 ADJ-11 第 3 项当作 purpose 依据。该函数本身不是已建立的可信生产签发入口；如何区分攻击造包与受控生产签发是候选设计，须与归档合同及所有调用者一起审定，不能预设保留或取消可选 manifest。实际生产入口、key/manifest/pin 的控制者尚待证。
- T `execution-control-store.mjs:186-205,237-269` 的 `applyOnce` 原样接受 `request.signature`（该函数自身未建立它是 command 还是 verdict 签名），把 `produce` 返回的 bytes 存入 `result_b64` 后计算本地 frame 摘要；`assertFrameChain` 在 `:146-179` 只检签名形状与链自洽，不验签。其规范长度检查会拒绝 `AA==`，但不证明签名真实。归档 SC-TR-004 所称冻结 envelope 链是否与本地 frame 链相同仍待证。M `execution_control_store_state.go:351-368,380-396` 的 `verifyVerdictAttestation` 则要求 envelope 的**被签名 payload 字节**等于入帧字节，并核对 request/epoch/sequence/previous digest。静态读取尚未证明 T 的本地 frame 或其 `signature` 是可直接传给 M 的 verdict envelope；也不能由此断言不存在其他适配器。需先沿真实签发/入帧调用链证明关系，再设计最小复用。
- M 首帧 `previous_verdict_digest` 按当前 `verifyVerdictSubject` 必须是非 null 字符串，与入参 `PrevDigest` 相等；当前 M 自带 Node 跨语言 fixture 使用空字符串作为第一帧值、第二帧使用第一份 raw payload 的 SHA-256。T 本地 store 第一帧的 `previous_digest` 则来自空 head，为 `null`，且其 frame digest 是另一种前像。**这是不同组件和字段的静态事实，不足以单凭数值不同判定协议冲突或自动互换**；应确认实际生产映射、获批合同和历史后再编制双端原字节正负向量。
- M `execution_admission.go:179-197` 的当前组件查询按 CR 计数，并检查 settlement `kind='effect'`、verdict 行及 cursor seq；它本身不解析签名结果字段或绑定到指定 generation。`server/cmd/server/router.go:1616-1622` 要求 runner 启用时传入非 nil decider；限定读取的 `main.go` 未发现传入 `NewAdmissionDecider`。非 nil 只证明依赖存在，不证明来源、业务结果或效果，且限定检索不是全局不可达证明。不可为消除启动拒绝提前注入该组件。

本轮采样 LF 规范化文本 SHA：T protocol `345eaa6037fc36a2eb5a40243581e78a4578ca18a30018032785d877f8ad38d8`、store `1533dffc3206b8cd3a50119652efa62c49c195a24c328c19c35b864b6bab6a69`；M store-state `70751a7a197026e61ce5f88094962cafeeafc8952f8c7c0d4243fd2e46c7ca00`、admission `23cac3ae674b5aa7e93676bc3c2f04c691e5dde27a695ad0e347a0b266c5a92e`、router `0ee5c8cfeafd688a851c8604d2382354f2fb2171d7facbe18a5185eee7b18f87`。本节未执行测试、签发、服务启动或访问数据库，不证明部署状态、生产密钥隔离或 Gate。独立只读复核 session `01a19704-55b2-7468-8217-4d067b352735` 两轮仅对照工作区文档并指出 scope、ADJ-11/purpose 和 cursor 边界等问题，已据报告修订；本次续用已有 session，原 requested model/effort 和 actual 无回执，均记 unknown。复核不代表业务验证或 Gate。

## 远端发布：已有合同与静态实现须协调

- 已归档 tools `SC-MG-015`：`unknown` 且远端包含 expected 时，按其祖先关系规则不重推并结算成功；`SC-MG-016` 对 **`intent`+远端 prev** 及 **服务端已 `settled_no_effect`+`unknown`+远端 prev** 两种情况，要求先以 `not_attempted` 结算旧 attempt，再 reserve 新 attempt。`SC-MG-017` 对 `unknown`、无服务端终态且远端 prev 的情况，因旧 push 可能延迟而保持 uncertain、不重推。不能静默改写这些已批准场景。
- 当前 M `ReportMergeEffectTx` 接受 caller 提供的 `no_effect`，该函数本身不验证远端回执；不能仅因为有服务端终态就认定“本次未发生”已有可信证明。未认证的 no_effect 不能解除新草案中未知结果的冻结。SC-MG-016 的终态前提如何在不误判迟到 push 的条件下成立，须与已批准合同及完整链路共同评审；不据此断言线上可达或所有可能签发路径不可信。
- 当前 T `merge-effects.mjs` 的 `classifyRemote` 从调用方传入远端 SHA 和 `isAncestor`；`planRecovery` 对 `intent`+`at_prev` 返回 PUSH，对 `intent`+`contains_expected` 返回 SETTLE_SUCCESS，对 `confirmed`+`contains_expected` 返回 NOOP。其中 `intent`+`contains_expected` 超出已列 SC-MG-015 的 given（该场景写 `unknown`）；是否由其他获批要求覆盖尚待核实。它们是函数的**静态返回值**，不是对完整调用链、线上可达性或实际 publish 的证明。
- 静态查看 `test/merge-effects.test.mjs:135-143`：标题写“intent 且远端未变须重新 reserve”，断言却只检查 `planRecovery(...).action == PUSH`；该单个断言未证明旧 attempt 已按 `SC-MG-016` 结算或重新 reserve。限定检索 `tools/skills/shared/crctl/scripts/**/*.mjs` 的模块名与函数名，仅发现定义、同模块 finalize 包装及该测试的引用；这不能排除其他路径、动态调用或已部署组件。本次未运行测试。
- 必须明确远端观测是谁认证、是证明“目标状态已满足”还是证明“本次 attempt 做了该动作”；仅看目标状态可能无法区分其他执行者或历史变化。也需检查 SC-MG-016 的 not_attempted/reserve 是否由完整调用链其他步骤保证、归档 confirmed 无服务端终态的分支如何衔接。上述问题可能要求单独合同评审或原 change 调整，当前不预断与已批准合同必然冲突，不把候选 freeze 规则静默替代归档。

**待评审的拆分建议（非新合同）：**

1. 若业务所需事实是“可信远端目前已包含批准的目标”，可研究以经认证、绑定仓库/ref/目标及读取时点的远端观测证明**目标状态达成**；它不自动证明本次 attempt 发出了 push，也不自动成为该 attempt 的额度消费凭据。能否映射归档 SC-MG-015 的“结算成功”仍须评审。
2. 若业务所需事实是“本次 attempt 确已执行或确未执行”，须另有能关联 attempt 的可信回执或足以排除迟到、并发和历史改写的权威证据；证据不足则保持未知并冻结，不因远端暂在 prev 或未经认证的服务端终态就重试。
3. 上述两类事实不能混写在一个笼统的 success/no_effect 上。实际远端提供方、身份认证、历史和证据可获得性尚未知；这只是候选取证边界，不指定新字段、签名版本、实现归属或取代已归档合同。

## 可执行的 SPEC 下一步（均未运行）

1. 两侧列出已批准的签名原像、字段权威来源与每个校验者；不确定字段标未证，保留 raw signed bytes 与不同 digest 的独立定义。
2. 为旧合同建立正负向量矩阵：同一 request/命令/主体/链/代次的成功例；各项错绑、未知结果、错用途/域、无受信名单与无隔离证据的失败例；分别标环境证明或纯组件替身，不能把替身冒充生产隔离证明。
3. 对本地事务的结算/slot 与外部 push 的 report/recovery 分开列测试；盘点归档恢复合同与完整调用链，再由双方确定跨 change 的实现和测试归属。不能直接运行旧 AIFI-45 runner，也不能读取历史事故库。
4. 在合同、可运行测试入口和审定归属明确后补齐 agent-spec 和计划测试命令，进行完整的 Gate2 展示并等待用户确认；未知时保留 BLOCK，不进行生产授权或部署。

## 主要一手证据与 raw SHA-256

- W `projects/multica/archive/2026-10-27-trusted-verdict-channel/canonical/specs/code/verdict-channel.yaml:57-80,107-147,201-208`：`9be455730dd4584069cd0d4cab071ae1f6a7a330e18acceda9014151153ba6a2`；`design-adjustments.md:125-146` 的 ADJ-11 记录域分隔 digest 与帧链关系。
- W `projects/tools/archive/2026-10-27-trusted-verdict-channel/canonical/specs/code/trusted-merge-gate.yaml:125-150`：SC-MG-015–017。
- T `skills/shared/crctl/scripts/lib/execution-control-protocol.mjs:340-431`：`345eaa6037fc36a2eb5a40243581e78a4578ca18a30018032785d877f8ad38d8`。
- T `skills/shared/crctl/scripts/lib/execution-control-store.mjs:145-181`：`1533dffc3206b8cd3a50119652efa62c49c195a24c328c19c35b864b6bab6a69`。
- T `skills/shared/crctl/scripts/lib/merge-effects.mjs:58-118,165-200`：`e8fb2b62f4301e96b33cc65a0bdb0506531d689c41624c53d3047b1abad6a2d4`。
- T `skills/shared/crctl/scripts/test/merge-effects.test.mjs:128-143`：`c367bf8d34fc2467b3152d881a146ac26c1d3b6534767fbf258ed723f4290765`（仅静态查看，未执行）。
- M `server/internal/governance/execution_control_protocol.go:614-723`：`6a767571cdd7961a01c84da385361398c6563a7409d06aeafa95001ffb885dda`。
- M `server/internal/governance/execution_control_store_state.go:354-415,493-496`：`f437aa2e2a29e26e0744d68d6da226101de6af618043e3a3d14bddafe86d684f`；`execution_merge_effect.go:200-227`：`7ced7b43f560289cd2cbc427e1fea3db7d88edb39aa0f8bb6a97e323c3f87679`。
- 其他来源、静态事实与边界见 `verdict-authority-source-research-20261030.md`、`verdict-outcome-pre-spec-evidence-20261030.md`。

本评估只读取源码和文档、比较 raw 文件摘要，没有运行测试、访问服务/数据库/容器、修改产品源码、签发或部署；旧库、旧容器与卷继续 HOLD。

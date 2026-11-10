# 可信 verdict outcome：跨仓 Agent 检查点规划（非执行稿）

**状态：SPEC 草案，Gate2 BLOCK；无可执行 CP，也没有执行测试。** 本表只建立计划编号与现有 Canonical SC / test-plan TC 的追溯，不改已确认 proposal，不替代逐案例预置、输入及预期，不作为测试通过或 Gate2 审批证据。前缀 `CP-VM`/`CP-VT` 为拟议编号，具体执行接口和断言尚未确定。本轮对两个 code canonical 的 SC ID 和 test-plan 表格 ID 做限范围静态匹配：M 19/19、T 15/15，均无重复或缺号；这不是 YAML 严格解析、原生 STDD 检查、语义覆盖或执行结果，两侧 agent canonical 仍各有 6 处 TODO。

## multica 侧计划映射

每一行依次对应同编号 `SC-VM-*` 和 `TC-VM-*`；对应案例的全部负例、正控和断言仍以 `../test-plan.md` 为准。

| 拟议 CP | 关联 SC/TC 尾号 | 覆盖主题 |
|---|---|---|
| CP-VM-001 | 001 | 认证结果与完整原门禁 |
| CP-VM-002 | 002 | 来源或结果缺失；未知按适用合同处理，区分原 issued 精确恢复与规定条件下的安全收尾 |
| CP-VM-003 | 003 | 非 permit 与 caller 自报 effect |
| CP-VM-004 | 004 | 错请求、主体或范围 |
| CP-VM-005 | 005 | 错冻结命令或 generation |
| CP-VM-006 | 006 | 帧链不匹配 |
| CP-VM-007 | 007 | permit 不证明 effect |
| CP-VM-008 | 008 | 每个结算写入入口负例 |
| CP-VM-009 | 009 | 外部效果未知 |
| CP-VM-010 | 010 | 撤销与 effect 竞争 |
| CP-VM-011 | 011 | 授权 head 或链缺失 |
| CP-VM-012 | 012 | 重放及中断 |
| CP-VM-013 | 013 | 旧格式与未知历史 |
| CP-VM-014 | 014 | Go↔Node 原字节互操作 |
| CP-VM-015 | 015 | 可信 no_effect；按归档 SC-VC-022 原条件，不另加效果未发生前提 |
| CP-VM-016 | 016 | 已 issue 的未知结果 |
| CP-VM-017 | 017 | 密钥事件与历史 |
| CP-VM-018 | 018 | issue 前后错误状态 |
| CP-VM-019 | 019 | 回滚防降级 |

## tools 侧计划映射

每一行依次对应同编号 `SC-VT-*` 和 `TC-VT-*`；该侧逐案例内容以 `../../../../tools/changes/2026-10-29-trusted-verdict-outcome-binding/test-plan.md` 为准。

| 拟议 CP | 关联 SC/TC 尾号 | 覆盖主题 |
|---|---|---|
| CP-VT-001 | 001 | 经授权的裁决来源 |
| CP-VT-002 | 002 | 缺失或不可信签发权限 |
| CP-VT-003 | 003 | permit 不证明 effect |
| CP-VT-004 | 004 | 未知字段、结果或签名域 |
| CP-VT-005 | 005 | 绑定来源不一致 |
| CP-VT-006 | 006 | 签发方绑定检查 |
| CP-VT-007 | 007 | 双向原始字节互操作 |
| CP-VT-008 | 008 | 幂等重放 |
| CP-VT-009 | 009 | 中断和远端未知 |
| CP-VT-010 | 010 | checksum 不等于可信历史 |
| CP-VT-011 | 011 | 未知旧格式 |
| CP-VT-012 | 012 | 升级、回滚和在途状态 |
| CP-VT-013 | 013 | 可信 no_effect |
| CP-VT-014 | 014 | 已 issue 未知结果 |
| CP-VT-015 | 015 | 密钥轮换、撤销与泄露 |

`CP-VM-014` 与 `CP-VT-007` 的 Node↔Go 执行证据拟由 M 唯一计数、T 引用，归属仍待人审。二者各自的 SC/TC 不因共享证据而消失；不能用组件向量取代 AIFI-45 真正的 RUN、generation、真实入口和 Gate3。

## CP-VM-008：结算写点调查清单

`TC-VM-008` 要求逐入口注入该入口适用的不可信权威对象或错绑，未测试入口保持 BLOCK。以下仅是当前源码中已定位的写点，不代表穷尽、生产可达或已接线可信裁决；每行的正控、逐负例、可观察结果和责任归属均待审。

| 已定位写点／入口（`../multica/server/internal/governance/`） | 静态观察 | 需核对的权威事实 |
|---|---|---|
| `execution_channel_admission.go::settleChannelTask` | 内部 helper，插入 dispatch effect settlement；从 `AdmitAndEnqueueTx` 调用 | verdict 与任务、reservation、事务及冻结候选的绑定 |
| `execution_control_policy.go::ApplySensitiveActionTx` | 写专项额度 effect settlement，`verdict_id` 使用 `SensitiveActionRequest.GrantID`；路由从已验证 head 填入 | 上游签名验证、grant 和当前 head 的绑定及适用负例 |
| `execution_control_policy.go::AppendRepairExtensionTx` | 写 repair extension effect settlement，通过 `ResolveVerifiedGrantTx` 查询 approval record | record、当前 head、追加权限与对象范围的绑定 |
| `execution_control_policy.go::ConsumeResumeEpochTx` | 写 resume epoch effect settlement，通过 `ResolveVerifiedGrantTx` 查询 approval record | record、当前 head、停止事实和 epoch 的绑定 |
| `execution_control_settlement.go::SettleControlCommandTx` | 写结算并推进 command；已有结果返回及 `ON CONFLICT DO NOTHING` 均需检查冲突语义 | 可信结果、输入一致性及 caller kind 的处理 |
| `execution_channel_reader.go::SettleCandidateTx` | 导出包装入口，调用 `SettleControlCommandTx`，不另写一条 insert | 候选与冻结 command 的绑定及重复调用 |
| `execution_merge_effect.go::ReportMergeEffectTx` | reservation `INSERT … SELECT`，`ON CONFLICT DO NOTHING`；`kind` 和 `remoteSHA` 来自调用方 | reservation 不存在或冲突时的回执、head、attempt 与远端效果证据的绑定 |

上述路径相对**工作区根**的 sibling `../multica/`；`verdict_id` 字段在不同写点可能关联不同对象，不得凭列名统一解释。敏感动作路由传入的是签名 payload 的 grant ID，repair/resume 则以 `approval_record.id` 查询；二者不能预先视为同一标识。`ResolveVerifiedGrantTx` 自身读取记录、decision 和 payload，但未在该函数内验签，完整信任链仍待核实。`AdmitAndEnqueueTx` 当前对 `VerdictID` 做 UUID 格式解析；`controlAuthorizationRevoked` 遇到缺链或空 decision 时返回“未撤销”，与 CP-VM-011 的缺链负例相关。这些是局部静态观察，不证明实际调用可达或整条链没有其他校验。还须另行核对所有写法和实际调用链；本表不是执行结果或可执行 CP。

## CP-VM-014 / CP-VT-007：摘要及共享证据边界

以下 sibling 路径均相对**工作区根**，分别记录摘要用途，而非将差异简单归为 Go 与 Node：

- T `../tools/skills/shared/crctl/scripts/lib/execution-control-protocol.mjs::verifyControlEnvelope` 与 M `../multica/server/internal/governance/execution_control_protocol.go::VerifyControlEnvelope` 的协议摘要均使用 `SHA256(domain || 0x00 || 原始 payload)`。
- M `../multica/server/internal/governance/execution_control_store_state.go::verifyVerdictSubject` 绑定 request、epoch、sequence 与前序摘要；`AppendVerdictFrameTx` 另以 `SHA256(原始 payload)` 更新帧链 `last_digest`。
- T `../tools/skills/shared/crctl/scripts/lib/execution-control-store.mjs` 的帧摘要是固定 frame body 的 `JSON.stringify` UTF-8 字节摘要；命令摘要则对对应 command 字节计算。帧摘要、命令摘要、协议摘要与 M 帧链摘要用途各异。
- 已检索的 tools 工作树未发现 `previous_verdict_digest` 字段生产方；这不是对部署、生成代码或其他仓库的穷尽证明。各前像、字段映射及 M 前序链与归档 ADJ-11 的关系仍须核实和审议，不能据静态差异认定生产不兼容或互换摘要。共享原字节向量、唯一计数归属和真实入口验收仍待批准；基础验签不等于真实效果。
- `TC-VT-004` 要求未知字段不能产生授权事实；是否一律拒绝整个 payload 仍待合同决定，不能预先写死。
- 既有 M `server/internal/governance/crosslang_test/interop_test.go:186-215,337-379` 值得优先复用：它让 Node 实签并由 Go 验原始 bytes，而非完整生产链或 Go→Node 双向证明。限范围静态预检发现该包自身无显式 `TestMain`，父 governance 包的 `crsync_test.go` 是被导入包的测试文件，不据此断言被本包运行；传递初始化尚未全审。该案例用 `t.TempDir()` 写 Node 脚本、从 PATH 查找 Node、继承环境运行子进程，未设子进程独立超时；`AIFI45_TOOLS_ROOT` 若设置会改变导入目标。Node 随后导入真实 T 模块及其依赖。Go 构建缓存、工具链/网络、环境、临时资源及后代进程隔离与清理均未闭合，**未执行**；必须完成具体预检并取得适用授权后才能运行。采样文件 LF 规范化 SHA-256 `bcec35e7f885ca209e03d3ccc0000cc73dae95d44e467be28e8a7aeb2317bed4`，不能证明其他文件或运行环境。候选仅选择该叶测试：`go test -run '^TestCrossLanguageVerdictEnvelope$' -count=1 ./internal/governance/crosslang_test`（在 `../multica/server`）；执行前须审核绝对 Go/Node 及完整传递导入，使用显式最小环境、明确固定的 tools 根、独占临时/缓存根和离线工具链/依赖，禁止自动下载及继承 `NODE_OPTIONS`。须先证明超时能终止全部自有后代、临时目录归属及安全清理；隔离缓存为空而依赖不可用时停止，不能回退真实 HOME/缓存。上述是待审预检而非允许运行或已证明隔离；提出资源测试时仍须取得适用授权。

## 不能提前编造的前置

各 CP 的签发主体、manifest/pin 与密钥用途、环境隔离、权威绑定、wire/摘要前像、effect/no_effect 证据、旧状态及回滚合同、执行入口和观测断言均未完成审批或实证。已确认的是 proposal 和设计方向；Ray 是协调负责人，不据此推定签发者。远端目标达成但本次待核的候选恢复方案不自动替代既有 `SC-MG-015/016`。

真正可执行 CP 应在对应合同、入口和安全环境审定后逐条定义：具体非破坏动作、正控及逐负例断言、真实非零选中、可审计结果、超时/隔离、失败退出与清理边界。多个 settlement 写入口、远端 attempt、撤销竞争和旧数据不能以一个泛化断言覆盖。所有拟议 CP 目前均为**计划／未执行／入口待审**。

远端恢复的已归档 given、候选分歧、迟到 push 和归档 TC 归属待决项集中见 `remote-recovery-contract-matrix-20261101.md`；该矩阵未选择结算结果、未修改归档合同，不能解除本 change 的 BLOCK。独立复核发现 T `design.md` D4 原有“一律冻结”与下段恢复表逐类动作矛盾，已在 D4 原位改为区分既有表和待批拟议冻结；该更正不代表 Human View 已同步、STDD validate 已通过或 Gate 已批准。

## STDD 3.0.7 执行器边界

静态阅读源码 sibling `../stdd/stdd/cli/commands/agent.py`（此路径相对工作区根）：当前 `agent verify` 使用 shell 执行 action，未设置 timeout；缺少或空 `assertions` 时仅因动作结束就记 PASS，不检查退出码；空 steps 或未命中指定 CP 可能得到零失败但没有任何验证；`meta.preconditions` 不自动执行，rollback 不自动运行。未知 assertion 类型在动作执行后才被拒绝。该执行器从数据根 `canonical/specs/agent/<task>.yaml` 寻址，不能假定会直接使用两侧 change 内文件。

因此当前两侧带 TODO 的 agent-spec 不得当作可执行验证规格，也不添加空 action、空 assertions 或占位成功命令制造绿灯。设计与执行入口须先单独审阅，禁止将 `validate`/`canon verify` 的静态成功解释为 CP 已通过或 Gate2 已确认。

## 依据

两侧 `canonical/specs/code/2026-10-29-trusted-verdict-outcome-binding.yaml`、`test-plan.md`、现有 `canonical/specs/agent/` 占位文件，以及 STDD 3.0.7 agent 模板与 `agent.py`。独立只读调查 session `01a18d17-0d1b-7468-8217-4a72139cfce2`（含续查），请求 `OpenAIPersonal/gpt-6.1-sol:high`，actual backend 无回执记 unknown；协调者核对执行器源码和 TC 标题，未调用 agent verify 或业务测试。结算写点及摘要对照另经只读调查 session `01a18d92-6304-7468-8217-4acf748d1056`，请求 `OpenAIPersonal/gpt-6.1-terra:high`，actual backend 无回执记 unknown；协调者核对所列源码写点与摘要表达式；独立 strong 只读审查 session `01a18d9d-a4d3-7468-8217-4ad362d0eaca` 请求 `GBClaude/claude-opus-5-5:high`，actual backend 无回执记 unknown，指出跨语言摘要口径及写点权威对象须澄清，已在原位修订。本轮另有独立只读复核 session `01a19704-55bf-7468-8217-4d0851d8644c` 检查过期与未知分支，指出须依据适用合同确认效果且不能静默收紧归档 SC-VC-022；原 requested model/effort 与 actual 无回执，均记 unknown。该复核未独立读取归档原文；协调者随后限定读取原文并将适用边界标为待审。未执行验证。

本轮对两侧 design 草案及归档的独立只读复核 session `01a19723-185b-7468-8217-4d12e7c243a2`（requested `GBClaude/claude-opus-5-5:high`，actual 无回执记 unknown）指出 §8.1 是 component profile 而非 production activation、归档 key path/pin 与 ADJ-11 inline key 的关系须核清、P0 转 B 规则与不承载生产私钥的方向须分开引用；协调者核对原文后在两侧 design 原位更正。复核续查认为 SC-VC-022 和 SC-MG-015/016 的冲突表述无实质误引，但指出“冲突分支 BLOCK”可能被读成运行时指令；协调者随后改为仅阻断本 change 合同收敛/测试/Gate2，保留归档有效性，**该最后措辞未再经独立复核**。复核未执行测试、未验证部署或 Gate，也不代表已批准候选恢复合同。

该审阅者后续对 Canonical/TC 指出原文无条件冻结可能与归档 MG-015/016 冲突、两侧 VM/VT-015/013 对 SC-VC-022 额外加了确认效果前提、恢复表与“重放原 command”边界未展开，以及 TC 引用不等于归档回归执行。协调者已分别修改双端 code canonical、test-plan 和 design：排除并列明三组归档输入、还原 VC-022 条件、区分本 change 拟议默认冻结与归档恢复动作，并明确 MG 回归及 VC-035 衔接待核。`settled_no_effect + unknown + 远端含 expected` 的不可变结算冲突仍须合同决策；不能据草案判定其已批准行为。后续只读复核又指出 `settled_no_effect + unknown + 远端含 expected` 同时涉及 SC-MG-015 和不可变结算，及 SC-MG-016 与 SC-VC-035 在 M 侧的衔接不能仅按一侧推定；协调者已在双端相关 canonical 单列待合同核定，明确不是运行时指令或已选择的结果，并在 T 的 TC 补上待核说明。审阅者再次复核确认 VM/VT-009、VM-016、VT-014 已标出两处待核，但发现 VM-018 的 settled 重放表述可能隐含选择其中一边；协调者已同步修改 VM-018 和 TC-VM-018，明确不推定两组待核结果。该审阅者最终仅针对这两处只读复核，认为均未隐含选边；未执行原生 STDD 校验，也未证明 Human View 已同步。

复核归档 SC-VC-022 后，双端 canonical/TC 和相关 design 将“过期”改为原文的“过时”；两词不等同、彼此关系待合同审定。TC 的“已过时但未到期”仅在批准合同允许该状态时适用，过时定义待核；撤销按归档线性化合同判定。独立复核会话 `01a1977d-5f08-7468-8217-4d3d93ea42a6` requested `GBClaude/claude-opus-5-5:high`、actual `unknown`；指出 TC-VM-002 仍附加效果前提，并遗漏归档 SC-DR-006 对过期后的原 issued 恢复及 SC-VC-027 的条件性安全收尾，协调者核对原文后修正 SC/TC；审阅会话续查认为关键冲突已消除，并指出 SC-DR-006 的路径和换代/新候选限制、SC-VC-027 条件范围及归档测试归属应进一步明确，协调者据原文再次补充；最后精度修订未再独立复核。该复核还发现双端 `specs/verdict-channel/spec.md` Human View 保留旧的效果前提、过期措辞和无条件冻结，与 canonical 不一致；生成入口的宿主拒绝尚未解除，不手工假称已同步，仍为 Gate2 BLOCK。

再次对两侧 code canonical 使用已安装 PyYAML SafeLoader 做语法解析及递归重复标量键检查，未见错误或重复标量键（M LF-SHA256 `db20c2691ea26434401e9b8284682cb35149458470abe7fad03425093d797ab3`、T `f72eef396496d78b26fcc3e026b1b0fb15f3f1467513c6aacd9bf532361e2304`）；静态 ID 对应仍为 M 19/19、T 15/15、无重复或缺号，逐 SC 观察到的 `and` 最大项数分别为 4、3。只证明这些文本检查，不是 schema/native STDD 验证、内容一致性、语义覆盖或执行测试。

Human View 尚未同步本轮 Canonical 修改。尝试预检版本化定向生成入口时，`ctx_execute_file` 对 sibling `stdd/stdd/cli/commands/canon.py` 返回项目根外访问阻止；用户在 Windows PowerShell 以其账户检查该文件返回 `READ_OK` 后，同一工具只读重试一次仍明确返回“resolves outside the project root”，并给出 host allow rule 示例。此结果确定是该工具的工作区边界阻止，不足以判断 Pi 是否支持示例中的权限配置；已停止，没有换其他工具读取该受阻文件、未运行生成器或绕过此边界。用户随后对 `canon.py` 增加精确读取规则；同一 `ctx_execute_file` 重试成功，LF-SHA256 `d74e687891b44defc06be8a5dd092d3343fe860d5310301ed0d92f2522c082a1`。用户进一步授权读取整个 STDD 项目后，`paths.py`（LF-SHA256 `dcc1fb5e4ae71ee44cf32e8eeb8bb6b99ce9cf9c0f89796afb157fca693ae708`）与 `finder.py`（`c8e8c94f9a8929dd3d332251b3372efd7f51a0f2ccfb0c1a3dcc0cc595851fb7`）只读预检成功。当前 `canon.py` 的 `--all` 对其发现的多个 proposal/spec 均可能写入；单次指定 change 的 `_generate_one` 无论 `gen_type` 均走 proposal 路径，故不可把 `--type spec` 视为已验证的定向 spec 渲染。`_generate_spec` 和 gate 用的渲染函数可写目标，但它们的调用条件、完整传递依赖和写入范围尚未核完，不能通过 gate approve 代执行。两侧现有目标 `specs/verdict-channel/spec.md` 均为未跟踪文件，LF-SHA256 分别为 M `abf8cc1c555f40da4cefb2b9415b0304850e4a0c8b0e9a2949e9887ea61b981f`、T `8429261893d3dac9ff0d8c54f3a0d0a27247679ac4899d44a4c9843f876ad75b`；格式扫描无额外自由文本，但不能因此证明没有人工编辑。以内存对照发现两者均与当前 canonical 不同，尚未运行生成器或覆盖目标；完成独占输出、快照保全、批准入口及传递依赖预检前不得生成，也不得以旧 Human View 代表当前 Canonical。

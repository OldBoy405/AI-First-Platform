# 可信 verdict：现有资料结论与建议（供讨论）

**状态：仅为调研和建议，不是当前部署事实，也不是 Gate2 审批。** 用户表示不了解签发主体、信任根和 effect/no_effect 的权威依据，要求先查现有资料并提出建议。两侧新 change 仍处于 SPEC / thorough，Gate2 pending；原 AIFI-45 Gate3 仍 NO-GO。

## 1. 已查到什么

- **已有设计方案，无需从零指定一名签发人。** 2026-10-27 归档通道设计已有人工 Gate1/2/3 记录，设计由受保护的 daemon control 服务持有隔离的 T/Node worker 生成并签发裁决，multica 独立验签；三类用途分别是命令授权、工具裁决、人工恢复授权。签发裁决不是执行效果的证明。[1][2][3] 归档 Gate3 的实际口径是 `channel-component`，没有声称 `strict-production` 或 Windows 隔离已满足。2026-10-27 当时本机的 agent 隔离已被证实不成立，并作为残余风险接受；本轮未复测，也不能据此断言现网环境。[4]
- **已有公钥清单机制，但部署侧信任来源尚未证明。** 归档设计要求管理员保护并固定清单的路径和原始 SHA-256，清单为不同用途和范围指定允许的公钥；普通 agent 不能修改清单或持有签名私钥。[2][3] 当前 Node/Go loader 能加载清单并返回摘要，但调用者必须另行确保来源、预期摘要和保护边界；不能因 loader 存在就认定已完成固定和隔离。[5]
- **源代码有验签和记账构件，但还不是可证明的生产闭环。** 当前 M 能验证签名原字节和一些请求/链字段，但这不证明签名结果的业务语义，也不证明真实效果。通用结算的 `kind` 由调用者传入，且还有其他直接写入结算的路径。[5][6]
- **本地任务入队与远端发布是不同的效果。** `AdmitAndEnqueueTx` 在同一数据库事务中写队列和 dispatch 结算，入队不等于 agent 已启动或工作完成；远端 push 与本地事务不是原子操作，现有 `ReportMergeEffectTx` 接受调用方报告，函数本身未验证远端回执。[7][8]
- **槽位实现需核实。** 归档合同要求确认收到裁决（ACK）不能释放未结算槽位，但当前 `AppendVerdictFrameTx` 入链时清空 cursor 的 `open_request_id`；另有未结命令约束。完整路径是否违反合同仍需核验，不能据此认定真实可利用问题。[2][6]
- **不能从源码推断部署和存量。** 本次没有访问实际服务、数据库或容器；真实签发者、私钥控制者、清单来源、线上版本、数据存量以及完整生产调用链仍未知。Ray 是草案负责人，不据此认定他是签发人。[5]

## 2. 建议采取什么方案

### A. 裁决由谁签：沿用归档方案作为设计起点

由**受保护的控制服务内的隔离 T/Node worker**核对受信来源及服务端冻结的命令，再对本次裁决签名；multica 自己验证签名、用途、范围、命令/主体/请求和当前代次的对应关系，再按既有授权与锁规则处理。工具的签名 helper 由调用者提供私钥，不能把任意 agent 能调用的通用签名函数视为可信签发服务。[2][3][5]

这是推荐的目标分工，**不代表它已在现网接好**。控制服务、私钥和清单必须与可被 agent 修改的 workspace、日志和参数隔离；2026-10-27 的本机隔离失败不能被假定已经解决，须有新的隔离证据，未经验证的环境不应承载生产私钥或信任清单。如果隔离、事实来源或签发身份无法验证，不允许据此产生新增受保护效果。不要因为方案 C 未就绪就静默降级成另一方案；若确需换方案，须另审。[4][5]

### B. 信任谁：管理员固定清单，密钥分用途

建议沿用既有 `execution-control-trust-manifest/v1`，由有权限的系统管理员固定受保护的清单及其摘要；其作用像“允许信任哪些签发者及用途的名单”，不是把私钥发给用户。分别控制**命令授权、工具裁决、人工恢复授权**的密钥用途，验签侧检查用途、范围、有效期与原始字节；明确历史验证、轮换和撤销规则。[2][3][5]

这里的“管理员”是待落实的职责，不是指要求用户自行保管密钥，也不是认定现网已完成部署。现有 loader 不会自行证明预期清单哈希已被固定。当前 Go 还接受独立 deployment-observer 用途而 Node 不接受该用途，含此类条目的同一份清单不能直接假定两侧通用；兼容策略须明确。归档要求 human 用途签 resume，而当前 `ConsumeResumeEpochTx` 读取数据库 grant，两者如何衔接须单独核实。[5]

### C. 怎么判断效果：按操作类型分别取证

| 情况 | 建议依据 | 不可误认为 |
|---|---|---|
| **数据库内的任务入队** | 只有当验签、当前授权/代次检查、队列写入和对应结算在批准的事务及锁规则下成立，才能以该事务的提交记录证明**入队**。 | 入队不证明 agent 已启动，也不证明后续业务完成。现有函数本身不证明整个生产授权链已接好。 |
| **远端 Git push 等外部效果** | 由受保护执行者结合经认证的远端回执或权威远端状态及必要操作历史进行对账；先明确能证明什么、如何关联本次尝试和并发/重试。 | 本地 caller 自报 `effect` 或 `no_effect`、一个本地 SHA、ACK 或普通日志，都不自动证明本次 push 已发生或未发生；单次远端状态也未必证明是哪次尝试造成。 |
| **明确未发生** | 已认证的拒绝/停止等，或撤销先于**该次本地效果提交**，并按已批准合同确认该次效果未发生，结算 `no_effect`；原有已提交效果不回撤。 | `no_effect` 只指这一次具体效果未发生，不代表历史上从未执行任何操作。 |
| **结果未知** | 已发出操作后超时、回执丢失或权威证据不足：保留未决状态和必要槽位，暂停新增效果，按批准的恢复/对账流程处理。 | 不能因没收到成功消息就记为 `no_effect`，也不能盲目重试可能已发生的外部操作。 |

依据：归档 SC-VC-012/013/015/022 及 SC-VC-034–036。[2] 具体远端回执来源和可证明边界仍待确定，不能把此建议当成已有实现。

### D. 协议与上线：先验证，再决定是否变更

先检查现有签名合同能否表达并认证上述必要事实；如果不能，再提交双方评审兼容证明或新版本。**不凭一个测试示例就推断完整生产格式，也不静默赋予旧字段新的授权意义。** 旧数据和已部署版本未知，须先有兼容、迁移/冻结及防降级方案；不能假设现网为空或承诺无条件回滚。[2][5]

## 3. 接下来可做什么

不需要用户现在提供密钥或猜测负责人。若认可上述方向，可继续在两侧 SPEC 中细化来源、合同、远端对账和每类写入口的范围及测试，确认哪些事实仍需部署侧非敏感证明；在完整材料准备好后，再单独向用户申请真正的 Gate2 审阅和确认。用户对原则的意见不自动批准 Gate2，也不解除历史事故库、容器/卷的 HOLD。

本轮只读源码和文档，未运行测试、访问服务/数据库/容器、签发、部署或修改源码；不能声称实际生产链路安全。独立只读调研请求 `OpenAIPersonal/gpt-6.1-terra:high`，无实际 backend 回执；effect 调研同请求模型且 actual unknown。独立 reviewer（续会话 `01a18b79-e38c-7020-aecc-d4cf98737e9a`，原请求 `GBClaude/claude-opus-5-5:high`，actual unknown）指出历史隔离失败、用途兼容、槽位和调用方自报 no_effect 四项文档风险；修订后四项判 `RESOLVED-FOR-DRAFT`，不构成生产安全签核。详细主源索引、行号与 SHA 限制见 [5]。

## 引用（主源优先）

相对 `AI First Platform/`；`../multica/`、`../tools/` 指 sibling 源码仓。

1. `projects/{multica,tools}/archive/2026-10-27-trusted-verdict-channel/.stdd.yaml`：归档及 Gate 记录。
2. `projects/multica/archive/2026-10-27-trusted-verdict-channel/design.md:25-65` 与 `canonical/specs/code/verdict-channel.yaml:57-80,107-147,201-208,309-332`：信任模型、key purpose、ACK、撤销和恢复。
3. `projects/multica/archive/2026-10-27-trusted-verdict-channel/design-adjustments.md:87-97`；`projects/tools/archive/2026-10-27-trusted-verdict-channel/design.md:55-75`：三种 key 用途、受保护 store 与清单。
4. `projects/multica/archive/2026-10-27-trusted-verdict-channel/validation/gate3-readiness.md:103-111,142-166`：归档验收范围及未声称项。
5. `projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/verdict-authority-source-research-20261030.md`：主源索引、当前 Node/Go 代码、静态事实、未知与源码变化；其中 `execution_control_protocol.go` 当前 raw SHA 为 `6a767571cdd7961a01c84da385361398c6563a7409d06aeafa95001ffb885dda`，不同于旧副本。
6. `../multica/server/internal/governance/execution_control_store_state.go:320-399,493-496`、`execution_control_settlement.go:31-69,72-148,157-179`、`execution_admission.go:151-195`：验签字段、结算输入及消费查询。
7. `../multica/server/internal/governance/execution_channel_admission.go:71-147,179-195`：本地入队与 settlement。
8. `../multica/server/internal/governance/execution_merge_effect.go:108-182,200-227`；`projects/tools/archive/2026-10-27-trusted-verdict-channel/design.md:38-53`：先 reserve、网络 push 后 report、未知/恢复。

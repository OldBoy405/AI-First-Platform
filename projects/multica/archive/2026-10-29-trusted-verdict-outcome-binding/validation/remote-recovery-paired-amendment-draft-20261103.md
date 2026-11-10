# 远端发布恢复：双端配对修订草案（DRAFT，未批准）

**状态：草案，仅供评审；不修改任何 canonical、不改测试计划、不构成 Gate2/实施授权。归档条款在获批前继续有效。** 针对“无法证明效果归属时保留原 attempt 并等待对账；不重推、不编造结果，也不改写已 settled 记录”的提问，用户原话为“第二条同意”。这一具体取舍已确认，不再重复请求选择；它不等于批准本草案的全部候选、状态转换、证据来源、身份映射、迁移、资源或 Gate。该决定已登记于 AIFI-45 的 T `ADJ-AIFI45-006` 与 M `ADJ-AIFI45-M005`，均 unresolved；归档条款与其冲突处须履行适用流程配对修订后才变更现行合同。

本草案把[合同矩阵](remote-recovery-contract-matrix-20261101.md)里"需成对修订"的格子写成可逐条讨论的条款文字，并标出每格的**最小结论**与**仍需跨端决定**的部分。经 strong 评审后已修正以下三处原则性问题：本草案的条款表只是**摘要**（第 1 节）、`pending-verification` 能否"M 不改"取决于 M 当前状态（格 1）、格 2 必须先读权威 settlement 再分流（格 2）。

## 1. 条款摘要（不是完整原文；完整 given/when/then/and 与行号见各条引用）

| 侧 | 条款 | 摘要 |
|---|---|---|
| T | `SC-MG-015`（`trusted-merge-gate.yaml:126-133`） | `unknown`+远端含 expected → 不重推并结算成功；confirmed+后继 → 不动作；confirmed+退回 prev → history rewrite 转 uncertain；祖先关系而非精确相等。 |
| T | `SC-MG-016`（`:134-139`） | `intent`+远端 prev；`settled_no_effect`+`unknown`+远端 prev → 先 `not_attempted` 结算旧 attempt，再 `attempt+1` reserve，不得直接 push 或复用旧 attempt。 |
| T | `SC-MG-017`（`:140-147`） | 分叉 / `unknown` 无终态且远端 prev → uncertain、禁止新 publish、不结算 no_effect、不重推；**且**"确认旧 effect 不授权后续 effect"。 |
| T | `SC-MG-018`（`:148-155`） | 部分发布后 base 漂移 → `halted.reason=base_drift`；base 与授权 head 均不变而候选 HEAD 变 → `input_mismatch`；不得换 base、`input_digest` 不同即拒绝恢复。 |
| T | `SC-MG-019`（`:156-161`） | finalize 同样先 reserve 再 push；撤销时返 REVOKED 且不推送。 |
| T | `SC-MG-020`（`:162+`） | 四支 reserve 结果的 halted 记录；head/摘要优先级、非授权失败不写 halted、409 body 不含 reason 等细则以原文为准，本草案不压缩。 |
| M | `SC-VC-012`（`verdict-channel.yaml:107-115`） | 只允许 `created→issued→result_ready→settled_effect\|settled_no_effect`；uncertain 冻结 lineage；`tool_verdict` 拒绝 UPDATE/DELETE/TRUNCATE，settlement 与 task_binding immutable。 |
| M | `SC-VC-015`（`:140-147`） | `ReconcileOwnerTx` 按恢复表逐类动作：恢复原 request、导入原 verdict bytes、返回原 mapping、重放原 command，或 freeze；freeze 不猜未消费、不清 slot、不建空 store。 |
| M | `SC-VC-022`（`:201-208`） | ACK 只确认持久化、不释放 slot、**不发 task**；pending/deny/stopped、permit 过时/撤销 → 结算 `no_effect`；issued/超时未知不得推断未消费、不释放 slot。 |
| M | `SC-VC-035`（`:317-324`） | 四种 reserve 情形 → 200 原结果 / 200 原 mapping / 201 新 command / 409；前 attempt 已 settled 的新 attempt 不新建 command；未终结时不接受并行 attempt。 |

不可动的前提：`unknown`/`uncertain` 下不发起新 publish；不编造 `no_effect`；**不追溯改写**已 settled 记录（但不禁止对"新发现的矛盾证据"作出处置）；ACK 不是业务消费、effect、任务派发/启动或 slot 释放的证明（它确认的是原合同范围内的持久接收）；不把单侧组件返回值当生产证明。SC-VC-013/020/022 的既定 no_effect 正例、撤销排序及未知不释放 slot 继续按原合同适用，不因本次远端归属取舍增设统一的远端归属证明前提；认证授权层的 no_effect 也不证明已在途的远端 push 未发生。

文内 `../multica/`、`../tools/` 源码路径以 AI First Platform 工作区根为基准，不是相对本文目录的链接。

## 格 1：`unknown` + 远端包含 expected

**问题**：`SC-MG-015` 直接要求"结算成功"，但"远端含目标"只证明目标可达，不证明**本 attempt** 造成。写进不可变的 settlement 就把不可归因事实固化为成功；仅凭目标已达成且归属不明，也不足以新结算本 attempt 为 `no_effect`。这不否定已具备可信依据的既有 `no_effect`：另一 writer 发布目标与本 attempt 未发布可以同时为真。

**候选 1A（首选讨论对象）— T 侧收紧"结算成功"的前提；M 是否要改取决于 M 当前状态**

T 侧新增 `SC-MG-015a`：
> 仅在存在**归属证明**时 SHALL 结算成功。归属证明只可来自：(i) 本 attempt 的发布回执或服务端事实；(ii) 该 commit 只可能由本 attempt 发布的独立证据，且须同时满足：唯一 writer、观察到的基线与该 attempt 签发时的 prev 一致、期间无旧 attempt/旧 owner 的在途发布。
> 无归属证明时 SHALL 进入 `pending-verification`：不重推、不发下一受保护动作、不结算 success 也不结算 no_effect，并持久记录观察证据（远端 SHA、祖先判定方式、观察时刻、观察来源、attempt 身份）。

**`pending-verification` 的定位（评审 P1-1 修正）**：它是 **T 侧 journal/halted 的处置态，不是 verdict，也不是 settlement**。因此：

| M 当前状态 | 是否需改 M | 说明 |
|---|---|---|
| issued / result_ready（未结算） | **否** | M 无新状态需求；T 只记录观察并保持未结算。 |
| uncertain（已冻结 lineage） | **否，但功能受限** | M 不允许再从 uncertain 转 settled（`SC-VC-012` 受限转换 + `648_cr_execution_control.up.sql:438-446` 的 guard）。此时"之后拿到归属证明再结算"**做不到**，只能转人工。 |
| 已 settled_no_effect | 见格 2 | 若匹配格 2 条件则讨论其候选处置，不改写既有 settlement。 |
| 已 settled_effect | 无需追溯修改 | 保留/重放既有记录；对新观察的审计或冲突处置另按适用合同，不直接套用格 2。 |

若要允许"uncertain 之后凭归属证明结算"，必须配套修改 M 的转换规则与 SQL guard——那就**不能再说"M 不改"**。本草案因此把 1A 的结论改为：**"M 可能不改"仅对 issued/result_ready 成立；uncertain 情形下的恢复能力属未决，需单独立项。**

**适用前提仍待配对**：此表描述的是已核实与原 effect/attempt 匹配的 M command，不能把 reservation 直接当成 issued command。当前 `../multica/server/internal/governance/execution_merge_effect.go:145–182` 的 reserve 路径只写 reservation；须先定义并验证 effect → reservation → request/command → attempt 的身份映射及真实生产调用链，无法建立映射时不得套用表格认定状态或结算。

**不得选 1B（M 新增 `settled_pending_verification` 终态）作为本轮默认**：它扩展 `SC-VC-012` 的受限转换，需要双端设计、迁移与旧数据解释。

## 格 2：`settled_no_effect` + `unknown` + 远端包含 expected

**评审 P1-2 修正：此格必须"先读权威 settlement，再分流远端观察"，且它优先于"未结算 unknown"分支。** 当前实现的缺口是：reserve 响应不含 settlement kind，冲突 report 又可返回 nil（`../multica/server/internal/governance/execution_merge_effect.go:101-229,202-214`），T 可能据此假确认成功而 M 仍是 `no_effect`。

候选 2A（推荐）：
- T：先以**可核验来源**读取该 attempt 的既有 settlement；若确认 `settled_no_effect` 且观察到远端含 expected，记录 `halted.reason=observed_target_after_no_effect`，进入 uncertain 的 T 侧处置态，禁止新 publish、禁止同 `effect_id` 新 reserve，转人工；保留全部观察证据。
- M：**不新增状态、不改 settlement**。若需留痕，用既有审计/日志或新增**只读**查询（返回既有 settlement kind 与原 mapping），不得让 200 原 mapping 变成"可再次发布"。
- 若两侧无法提供可信的 settlement kind 读取，本格**无法按上述处置**——必须先补只读查询或扩 reserve 响应，否则只能停在人工。

**评审同时指出草案原文过强**：另一 writer 已发布 expected、而本 attempt 被拒绝且确实未发布时，"目标存在"与"本 attempt no_effect"可以同时为真。因此本格结论不是"目标存在就不能 no_effect"，而是"**不得据此推断本 attempt 成功，也不得据此重发**"。

## 格 3：`SC-MG-016` 收紧

**问题**：`intent+prev` 与 `settled_no_effect+unknown+prev` 都据"远端仍是 prev"决定 `not_attempted` + `attempt+1`；远端观察是瞬时事实，不证明在途 push 不会之后落地。

候选 3A：为两支加前置——SHALL 先证明无可归因的在途发布（本 attempt 从未取得 push 通道 / 已确认连接未建立 / 服务端 fact 表明未 effect），否则按 `SC-MG-017` uncertain 处理并等待对账窗口。

**评审 P1-3 补充（必须写进条款，不能只靠收紧）**：
- `SC-VC-035` 的"200 原 mapping"**不授予发布授权**。若旧 attempt 已 settled 且确无在途发布，新 attempt 仍只能拿回原 mapping 与原 command，不因此获得"可再次发布"。
- 现状核对：`../tools/skills/shared/crctl/scripts/lib/merge-effects.mjs:95-152` 中 `intent+prev` 目前返回 PUSH；**未找到完整的 `not_attempted` 结算 + `attempt+1` 跨端重试链**，因此本格不是"已有能力的收紧"，而是**待实现能力 + 合同修订**。
- 必须定义 `not_attempted` 的落点（settlement kind？halted reason？仅审计事实？），以及已 settled 旧 attempt **不得再次结算或改写**。
- 原 attempt 身份必须来自受保护的原持久映射；当前 M `execution_merge_effect.go:153–158,185–196` 重放旧 reservation 时返回的是当前 lineage 的 reservation 总数，不足以在后续 attempt 存在后证明原 attempt 编号。需确定真实持久来源并按 SC-VC-035 返回原结果/映射，不用当前计数重算旧身份；原 mapping 本身不授予新的发布权。
- 若确实需要"新可发布 attempt"，须正式配套修订 `SC-MG-016/020` 与 `SC-VC-035`（含 effect_id/attempt/原 mapping/新 command 的身份与可消费规则），并在获批前保持归档行为。

## 格 4：`intent` + 远端包含 expected（未列组合）

**评审 P1-5 修正：不能笼统说"journal 未落"，两条实现路径不同。**

- `lib/merge-effects.mjs:204-213` 的三态 helper 在 **push 前**就 `await` 保存 `unknown`；崩溃后应按 `unknown` 恢复。
- `lib/workspace-transactions.mjs:2149-2238` 的 `mergeCr` 是 `prepared → push → 保存 pushed`，属另一套 schema；若 `pushed/confirmed` 尚未保存，恢复 prepare 可能**先重算 mergeSha**，之后才进入发布观察，从而丢失按原 expected 分流的机会。

候选 4A：显式归入格 1（目标已观察为可达，但本 attempt 是否发布未证）→ `pending-verification`；**不得**视为 `not_attempted`、不得重推、不得按 016 走 attempt+1。条款必须写明：先保全并核对**原 expected 与原 attempt**，再决定是否 prepare/rebuild；旧路径（`pushed/confirmed` schema）接入本处置属**待实现能力**。

## 格 5：混跑、回滚与存量（评审 P1-6）

必须在条款层决定，不能只列风险：
1. 版本/能力 pin 与 owner fencing：`projects/multica/changes/2026-10-22-aifi-45-authorized-execution/design.md:62` 已要求新旧版本不得同时接管同一动作；本草案沿用该约束并要求明确实现点。
2. 新版留下 `pending-verification` journal 后，旧 reader 若按旧 `unknown+contains_expected` 处理，可能成功结算；若不认识新增编码，也可能拒绝。须按具体版本、状态编码和恢复入口核验，不能预设兼容或安全回滚；可能需要阻断混跑或排空旧版本。
3. 回滚路径：撤回新条款后，`pending-verification` journal 如何被具体旧版本解释，须验证并给出可执行方案；不能预先断定必定重推、结算或安全拒绝。
4. **存量禁令收窄**："不得把新规则套到已 settled 记录"仅指**不追溯改写历史 settlement**，不禁止对"新发现的矛盾证据"作出处置（否则格 2 自相矛盾）。

## 归属证明与升级（评审 P1-4）

草案原三条件（唯一 writer + 基线为 prev + 观察晚于签发）**不充分**：旧 attempt A 延迟落地时，B 的观察同样满足三条件却不该归因给 B。必须补：
- 受保护的裁决主体（谁有权认定归属成功）与认证证据来源（服务端事实 / 受保护控制面记录，而非调用参数）。
- repo / ref / attempt / commit 的绑定，以及**旧 attempt、旧 owner、旧 effect 的排除条件**。
- 等待期限、重查策略、通知与人工升级权限；**超时不得自动 no_effect、也不得自动重发**；归属成功也不授权下一 effect。
- 现状：`execution_merge_effect.go:202-214` 的 report 参数（kind/attempt/remoteSHA）来自调用方，本身不是可信发布证明。

## 必测（双端配对，未执行）

- 迟到 push 在 uncertain/pending 期间落地；观察失效（先 prev 后 expected）；并发第三方写入目标 ref。
- `pending-verification` 下不产生新 publish、不发下一受保护动作、不结算任一终态。
- `settled_no_effect` 之后出现目标：settlement 字节不变、审计留痕、禁止新 reserve；reserve 响应/查询能否如实返回 settlement kind。
- `SC-VC-035` 四支 + `SC-MG-020` halted 记录；旧 attempt 已 settled 时不重复结算。
- 崩溃注入：两条 journal 路径各自的写入顺序；`intent+expected` 的分类；prepare 重算 mergeSha 的窗口。
- 真实 Git/DB/网络测试须先有隔离与资源授权；组件测试不能替代跨端证据。

## 不得据此声称

- 未改任何 canonical/test-plan，归档 `SC-MG-015/016/017/018/019/020`、`SC-VC-012/015/022/035` 仍是现行规则。
- 未证明该组合在线上发生过，也未证明当前实现按归档条款执行；引用实现行号只是现状证据，不是行为验收。
- 不解除任何 BLOCK，不构成 Gate3 或部署依据。

## 独立评审

**strong 只读评审**（requested `OpenAIPersonal/gpt-6.1-sol:high`，session `01a1a031-3c47-7374-9f4d-45a13b377031`，actual backend unknown；未执行命令/测试/Git/DB）：P0 0 项，P1 6 项，P2 2 项。本版按其意见修正：

| 编号 | 问题 | 本版处理 |
|---|---|---|
| P1-1 | 1A「不改 M」只在特定 M 状态成立 | 新增 M 状态三分表，明确 uncertain 后结算做不到、需单独立项 |
| P1-2 | 格 2 缺权威 settlement 读取与分流优先级；"目标存在即不能 no_effect"过强 | 改为"先读 settlement 再分流"、格 2 优先于未结算 unknown、并收回过强表述 |
| P1-3 | 收紧 016 未闭合 not_attempted/attempt+1/原 mapping | 新增：200 原 mapping 不授予发布授权、现状无完整链路、需正式配套修订 |
| P1-4 | 归属证明三条件不足 | 新增裁决主体、认证来源、旧 attempt 排除、超时与升级约束 |
| P1-5 | 格 4 混用两条 journal 路径 | 分列 helper（push 前写 unknown）与 mergeCr（prepared→push→pushed） |
| P1-6 | 混跑/回滚缺决定、存量禁令与格 2 冲突 | 新增格 5（pin/fencing/回滚/收窄禁令） |
| P2-1 | 条款表被标为"原文摘录"实为改写且漏引 | 表头改为"摘要"、补 `SC-MG-018/019`、`SC-VC-015`、漏引字段与细则说明 |
| P2-2 | "不把 ACK 当送达"混淆持久化与业务效果 | 改为"不是业务消费/effect/派发/启动/slot 释放的证明" |

修正后的文本**未再经独立复核**。评审明确要求：本草案只能作为方向和逐项合同的评审输入。此后用户已确认本文件开头所列具体取舍；其余候选合同仍待逐项决定，不能把这一确认扩大成整份草案获批。

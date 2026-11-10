# WP4 配对修订草案：SC-MG-015 / SC-MG-016（2026-11-04）

> **状态：DRAFT / 未批准 / 未全链实施。** 用户已批准「推进 WP4 恢复合同配对」这一方向，并已确认取舍「无法证明效果归属时保留原 attempt，不重推、不编造结果、不改写已 settled」。本文件把该方向落成**可评审的条款级修订文本**；T/M 存在局部实现，但这不是合同生效、不是 B4 已闭合、不是生产链完成，更不是 Gate3 证据。

用户后续选择现有 `2026-10-29-trusted-verdict-outcome-binding` 承载配对 SPEC 评审，见 [M 侧草案](../../2026-10-29-trusted-verdict-outcome-binding/design.md)及其 T 侧引用。两侧既有 Gate1 属历史无指纹确认，当前未找到可将本范围增量绑定为新批准的重审入口；选择载体不是 Gate1/Gate2 批准，须由 STDD 维护者确认合法处理办法。

## 1. 现行条款（原样引用，不改归档）

`projects/tools/archive/2026-10-27-trusted-verdict-channel/canonical/specs/code/trusted-merge-gate.yaml`

- **SC-MG-015**（L126–132）
  - given：journal `unknown` 且远端含 expected（等于或其后续）；`confirmed` 且远端为 expected 后继；`confirmed` 且远端退回 prev。
  - then：SHALL **在含 expected 时不重推并结算成功**，在正常前进时不动作，在退回 prev 时判 history rewrite 转 uncertain。
- **SC-MG-016**（L134–139）
  - given：journal `intent` 且远端等于 prev；以及服务端已 `settled_no_effect` + journal `unknown` + 远端 prev。
  - then：SHALL **先以 `not_attempted` 结算旧 attempt 再以 `attempt+1` 重新 reserve**，不得直接 push 或复用旧 attempt。

配对用例：`projects/tools/archive/2026-10-27-trusted-verdict-channel/test-plan.md` TC-MG-015（L218–226）、TC-MG-016（L230–238），两者当前状态均为「❌ 测试缺（Gate 2 草案，未实施）」。

## 2. 冲突在哪（只有两处，不扩大）

| # | 现行条款要求 | 现行事实能力 | 冲突性质 |
|---|---|---|---|
| C1 | `unknown` + 远端含 expected → **结算成功** | 远端含 expected 只能证明**目标状态已达成**，不能证明**是本次 attempt 达成的**；迟到旧 push、他人达成、先前 attempt 都可造成同一状态 | 把「目标达成」当成了「本次 effect 已证实」 |
| C2 | `intent` + 远端等于 prev → `not_attempted` + `attempt+1` | 「远端仍是 prev」不排除旧 push **仍在途/迟到**；只有可信 `no_effect` 才能证明未发生 | 把「还没看到结果」当成了「确定未发生」 |

其余分支（confirmed 正常前进不动作；confirmed 退回 prev → history rewrite → uncertain；分叉 → 禁新 publish）**无冲突，全部保留**。

## 3. 拟议条款（替换文本，最小改动）

### 3.1 SC-MG-015 拆成「目标状态」与「本次归属」两件事

> **given**：journal `unknown` 且远端含 expected（等于或其后续）。
> **then**：SHALL **不重推**；SHALL 记录「目标当前已达成」这一可核观察。若本 attempt 的 effect 和 no-effect 均无适用合同认可的可信证据，尚未结算的 attempt SHALL NOT 新写任一 settlement，其未决排他约束持续有效，SHALL NOT 自动继续下一受保护动作。若已有可信 no-effect，按适用合同处理，不因目标由他人达成而否定该证据；新发布仍须另行证明旧执行者不会迟到并满足再准入条件。已有 settlement SHALL 保留原样。人工对账可核查、记录和展示，不因人工确认本身证明效果、释放未决排他约束或授予重推权。
>
> **given**：`confirmed` 且远端为 expected 后继 / 退回 prev。
> **then**：（原文保留）正常前进不动作；退回 prev 判 history rewrite 转 uncertain。

### 3.2 SC-MG-016 加一个证明前置

> **given**：journal `intent` 且远端等于 prev。
> **then**：SHALL **不直接 push**、不复用旧 attempt。SHALL 先判定旧 attempt 是否可被证明「确未发生」：
> - 尚未结算，且有来源可信、绑定该 attempt 的 `no_effect` → 按适用合同处理该事实；只有另外排除旧执行者迟到并满足完整再准入条件，才可研究 `attempt+1`，不能以单纯 `intent` 或远端 prev 制造 `not_attempted`。
> - effect 和 no-effect 均无可信证明 → 保持未决（`unknown`），SHALL NOT 新写任一 settlement、SHALL NOT 递增 attempt、SHALL NOT 释放未决排他约束。
> - no-effect 已被可信证明但旧执行者迟到尚未排除 → 可按适用合同结算 no-effect，但 SHALL NOT 自动进入下一受保护动作；不得声称已结算的数据库 slot 仍被占用。
>
> **given**：服务端已 `settled_no_effect` + journal `unknown` + 远端 prev。
> **then**：SHALL 读取／重放已有的原 mapping，SHALL NOT 再次以 `not_attempted` 结算、删除或改写旧 settlement。`settled_no_effect` 本身不证明旧执行者不会迟到，也不授予新发布权；只有来源与 attempt 绑定可信、迟到已被排除，且完整满足 `SC-MG-016` 适用条件及 `SC-VC-035` 身份/重新准入合同后，才可研究新 attempt。否则禁止新 reserve/push，保留原 attempt 与已有事实并等待对账。当前 M 查询会把已有 settlement 当作占槽结束，必须另在获批准的真实入口证明如何阻断后续 effect，不能声称该数据库 slot 仍被占用。

## 4. 影响（必须连同条款一起评审）

- **C1 改变一条已批准的成功结算路径**：`unknown` + 远端含 expected 从「结算成功」变为「目标达成；本次 outcome 按可信证据判断，证据不足则未决」。已 settled 事实不改写；仍在途旧 attempt、混跑和回滚如何按可信事实衔接，尚须配对决定，不能假定一律按旧路径继续或直接按新路径处理（见 §7）。
- **C2 收紧一条已批准的重试路径**：原来「远端 prev 即重试」变成「可信 no-effect、排除旧执行者迟到及再准入条件均成立才可研究重试」。任一前置不足时，自动下一受保护动作**停住**并需要对账。
- 最小候选是不增加结算终态、不新增预算账本：未决时沿用既有 journal／观察记录并保留未结算 reservation。仍须审查并发互斥、attempt 的持久身份、恢复/混版切换；如果需要新增终态或状态转移，应另经合同与迁移评审，不能预称完全不改状态机。

## 5. 与 `SC-VC-035` 的衔接（只声明，不裁定）

`SC-VC-035` 管 M 侧原 mapping 与新 attempt 的关系。C2 修订后，`not_attempted` 只在更窄条件下出现，因此**新 attempt 的触发点也更窄**；这不等于与 `SC-VC-035` 冲突，也不等于其自动满足。两者关系须在 M 侧配对修订时一并核定，本草案不导出 M 侧结果。

## 6. 代码跟进（T/M 局部已做，配对生产链未完成）

| 侧 | 位置 | 状态 |
|---|---|---|
| T | `tools/skills/shared/crctl/scripts/lib/merge-effects.mjs#planRecovery` | **2026-11-04 历史快照，no_effect 分支已被下行替代**：「不重推」与「是否结算本次 effect」已拆成两个事实——`unknown`/`intent` + 远端含 expected → `halt`/`target_satisfied_unverified`；当时 `settled_no_effect` 要求 `noEffectAttested === true` 才 `reserve_next_attempt`；`ACTIONS.SETTLE_SUCCESS` 已删。定向变异 RED 3/21 → GREEN 21/21，证据 `validation/wp4-pairing-20261104/` |
| T | 同上，`intent` + 远端 `at_prev` | **已改（2026-11-09）**：不再返回 `push`，改为 `halt`/`uncertain`（「无法证明旧 push 未在途」）。仍无生产调用方，不因此声称真实恢复已受保护。 |
| T | 同上，`unknown` + `at_prev` + `settled_no_effect` | **后续收紧，未提交**：调用方自报 `noEffectAttested`（包括 `true`）无法证明同 attempt 无效果且旧执行者不会迟到，返回 `halt`/`no_effect_unverified`；当前判定没有返回 `push` 或 `reserve_next_attempt` 的分支。定向测试 21/21，无 skip；不证明真实生产链保护或安全重试。 |
| M | `multica/server/internal/governance/` 原 mapping、merge effect reserve/report 及结算 CAS | **局部已改**：存在原 mapping 读取、已 settled 重放、缺 reservation 拒绝及冲突语义比较；这些不证明远端 effect 可信、并发 reserve 互斥或 SC-MG-015/016 的配对生产接线，属 `ADJ-AIFI45-M008` 的 impact_scope |
| M | 同上的 `not_attempted` 前置 | **未闭合**：可信 no_effect 来源、attempt 绑定及迟到执行者排除尚无完整生产链 |

**T helper 未接生产入口**：有界检索中 `planRecovery` 仅有定义和测试引用，且 `noEffectAttested` 无可信生产者；当前 helper 的 halt 不能视为真实链路的保护，也不提供安全「换 attempt」能力。真实 CLI 另有发布路径，尚未证明其 fail-closed 或支持可信重试。

## 7. 已确认约束与仍需配对决定

**已确认**：effect 和 no-effect 均无可信依据时保留原 attempt 和未决动作的排他约束，不重推、不编造结果，不改写已 settled；不重复询问是否释放未决 slot。当前 M 查询把任何 settlement 当成 reservation 已结束，不能用现有 `effect`/`no_effect` 加标记表达未决，否则会释放占用。最小候选是在原 journal／观察事实中记录目标状态，对两种结果均无可信依据且尚未结算的 attempt 不新写 settlement；已有可信 no-effect 则按适用合同处理。对已有 settlement 但未证明可重试的旧记录，须保留原行且另在真实入口阻断新 effect，具体机制待配对审议。此候选不证明现有数据库 slot、并发互斥或可信事实已实现。

| # | 待决定 | 约束 |
|---|---|---|
| D-a | 未决观察的存储与人工对账是否能使用现有 journal 和事实；如不能，具体增加什么状态及恢复转换？ | 不得写伪造的 effect/no_effect；新增状态、迁移或终态重开须另行评审。 |
| D-c | 旧版/新版混跑、旧在途 attempt、回滚和切换如何互锁、核对可信事实并处理未知？ | 不改写已 settled；这不等于旧在途可沿旧路径继续，更不授权自行迁移或补造历史。 |
| D-d | 谁生产并验证与具体 attempt 绑定的 no_effect，以及如何排除旧执行者迟到？ | 任一项未被证明时均不得新 reserve 或 push；不可把 caller 自报、远端 prev 或已有未经验证的结算当证据。 |

## 8. 验证边界

- 原草案当次未连接数据库、创建实例、运行 merge effect 测试或访问真实远端及事故资源；后续仅有上表所述 helper 定向测试，不证明真实入口。
- 「可信 no-effect」的生产者与 attempt 绑定、以及独立的旧执行者迟到排除机制均**尚未定义并接通**。不能因此推翻其他已批准合同中的合法 no-effect；本 helper 当前对不可信自报保持 halt，不能解释为生产链已实现可重试。
- 任何 fake pgx / 内存夹具只能证明代码形状，不证明并发、迟到或结算幂等；真实验收须在经批准的隔离库与自有临时远端上进行。原 mapping 和当前局部重放修正不代替这项验收。

## 9. 与既有材料的关系

- 更完整的事实模型、并发/部署前置与候选矩阵见 `../../2026-10-22-aifi-45-authorized-execution/validation/remote-merge-recovery-amendment-proposal-20261030.md`（DRAFT）。
- 本文件是它的**条款落地页**：只回答「SC-MG-015/016 改成什么字、影响哪些既有路径、批准后改哪三处代码」。
- 历史静态阻断记录：`../../2026-10-29-trusted-verdict-outcome-binding/validation/aifi45-wp4-2-wp4-3-static-block.md`；局部源码已有后续更改，不能把历史缺陷当成当前源码结论。

## 10. 待 STDD 维护者答复：历史 Gate 最小重审

用户认可继续使用两侧现有 `2026-10-29-trusted-verdict-outcome-binding`，保留历史审批并分别对新增范围进行合法人审；这不是 Gate1/Gate2 批准或 BUILD 授权。请维护者确认：

1. 当前受支持入口如何为两侧历史 `unfingerprinted` Gate1 分别记录新的人工确认和当前输入指纹，同时保留原历史？若现有入口不支持，请提供最小合法处理方案；不清除状态、不伪造 stale、不补造历史指纹。
2. 如何确保 Gate1 的各侧 canonical proposal 和 Human View，以及 Gate2 设计、规格、测试方案与完整 M008 条款、T 侧 `MERGED-SCOPE-20261109.md` 等实际评审范围均被可核验地绑定？链接不会自动纳入输入；可由维护者确定将完整有效内容纳入现有受审产物或采用受支持的显式输入。
3. 请明确任一受审内容变更、缺失时的重审规则；不自动推进 Gate2/BUILD，也不因此批准数据库、Git 或部署操作。

依据当前源码的只读核查，历史 Gate1 上 `--reapprove` 幂等返回，不能证明该增量已绑定；未运行 CLI，尚无维护者答复。

# 远端发布恢复：双端合同收敛矩阵（待审）

**状态：SPEC 合同冲突待核，不是生效规则、实施授权或 Gate2 批准。** 本文将独立只读复核的静态条款和候选问题集中列出；不因候选而改写归档合同，也不据此断言当前实现或线上行为。用户同意准备“目标达成、本次待核”的修订方向，不等于已批准具体条款。

## 现行归档条款与需协调的组合

引用：T `projects/tools/archive/2026-10-27-trusted-verdict-channel/canonical/specs/code/trusted-merge-gate.yaml` 和 `projects/tools/archive/2026-10-27-trusted-verdict-channel/canonical/specs/code/verdict-channel-runtime.yaml`；M `projects/multica/archive/2026-10-27-trusted-verdict-channel/canonical/specs/code/verdict-channel.yaml`。以下只摘录所列场景的相关 given/then/and，不将其扩展为全部状态机。

| 观察组合 | 归档适用内容 | 需闭合的问题 |
|---|---|---|
| `journal=unknown`，远端包含 expected | T SC-MG-015 要求不重推、按祖先关系结算成功；不是仅做 SHA 精确相等。 | 远端含目标仅证明目标可达，不自动证明本次 attempt 造成。用户同意准备的候选方向若改变成功结算，需成对走适用合同变更审批。 |
| `journal=confirmed`，远端为 expected 后继 | T SC-MG-015 要求正常前进、不动作。 | 候选／待评审：明确可信远端观察和历史事件的证据；不能将单独组件返回值当生产证明。 |
| `journal=confirmed`，远端退回 prev | T SC-MG-015 要求 history rewrite 转 uncertain。 | 候选／待评审：明确保全证据、责任与恢复权限；不自动 force。 |
| `journal=intent`，远端包含 expected | SC-MG-015～017 所列 given 未明确列出此组合；这不证明其他归档条款没有覆盖。 | 与 push 成功、journal 更新前中断的可能窗口有关；须先核 journal 实际写入时序、其他适用条款及 attempt 身份，再确定合同与测试归属，不预判结算或重试。 |
| `intent+prev`，或 `settled_no_effect+unknown+prev` | T SC-MG-016 要求旧 attempt 先按 `not_attempted` 结算，再以 attempt+1 reserve，不直接 push 或复用旧 attempt。 | 对齐 `not_attempted` 在 M 终态模型的表达、结算调用与新 attempt；已 settled 时“先结算旧 attempt”与 settlement 不可变及原 mapping 如何对应，待合同核定。**候选收紧**：不单凭远端 prev 推断旧 push 绝不会迟到；若改变 SC-MG-016 前置条件须双端配对修订审批，获批前归档仍有效。 |
| 分叉，或 `unknown` 无服务端终态且远端仍 prev | T SC-MG-017 要求 uncertain、不得新 publish；后一种不得结算 no_effect 或重推。 | 确认迟到 push、锁与远端对账顺序，验证无新副作用。 |
| `settled_no_effect+unknown+远端包含 expected` | SC-MG-015 的 unknown+包含目标与 M SC-VC-012 的 settlement immutable 同时相关；两侧材料尚未说明本组合如何协调。 | 是陈旧观察、另一 attempt、迟到 effect 等哪种原因无法仅凭组合断言。需规定事实核验、后续动作、审计及既有不可变终态如何保留；不得预先选择结算结果。 |
| M 已 settled，T 请求新的 attempt | M SC-VC-035 对四类 reserve 返回 200 原结果、200 原 mapping、201 新 command、409；明确前 attempt 已 settled 的新 attempt 不新建 command。T SC-MG-020 规定对应四支及 409 的 halted 记录。 | 与 SC-MG-016 的 attempt+1 reserve 如何连接：effect_id、attempt、原 mapping、新 command/permit 的身份和可消费规则均需两侧正式界定，不能假定 200 意味着新授权。 |
| SC-VC-015 / SC-TR-006 恢复表所列观察 | M SC-VC-015 与 T SC-TR-006 的既有恢复表包含恢复原 request、导入原 bytes、重放原 command 和 freeze；返回原 mapping 见 M SC-VC-015。 | 按原合同分类；远端发布的候选冻结不能扩写为所有本地恢复一律冻结。 |
| pending/deny/stopped，或过时/撤销 permit；issued/超时未知 | M SC-VC-022 分别要求对所列判决结算 no_effect，以及未知不推断未消费、不释放 slot；ACK 只证明持久化。 | 不得为 SC-VC-022 静默增加“先证明该次 effect 未发生”的新前提；与其他 effect 的映射须核适用条件。 |

## 候选决策的边界与必测项

1. **目标达成、本次待核**是候选观察/处置方向：不重推、不自动发出下一受保护动作；须在 SC-VC-012 settlement 不可变前提下界定待核信息的权威归属及其与当前 API/存储模型的兼容性；若拟改变不可变性须双端配对修订并审批。禁止把候选文案冒充现行终态或直接覆盖历史结算。
2. 对旧 attempt 的 `not_attempted`、原 mapping 与 attempt+1，分别确定谁签发、谁消费、effect 身份和请求幂等边界；SC-MG-016 与 SC-MG-020／SC-VC-035 无明确衔接前不要声称满足这些条款。
3. 设计双端配对修订与适用审批、切换点、在途请求和旧证据解释、回滚及旧版本混跑；用户对“真实业务使用或可能已有旧数据”的合并提问答“是”，不能拆推成两项事实均已证实，按可能存在存量保守设计；原确认范围见 `projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/verdict-authority-acceptance-20261030.md`。
4. 按身份与时间注入迟到 push、远端其他写入、观察失效、冲突 report、已 settled 后重放和 process crash；检查实际远端 ref、服务端不可变事实、旧/新 attempt、零额外受保护动作。真实 Git/DB/网络测试须预审隔离和适用授权。
5. 归档 `TC-MG-015/016` 的回归执行环境、承担端和结果登记位置仍待确定；测试引用或候选设计不是执行证据。不先承诺某端可独立验证跨端语义。

## 已观察到的实现边界

`projects/tools/changes/2026-10-22-aifi-45-authorized-execution/validation/release-recovery-ancestry-exit-code-20261101.md` 记录了独立只读复核提出的 push 成功、journal 保存前崩溃窗口：receipt 检查可观察到已发布却未据此冻结 per-repo prepare，后者可能因远端 base 变化重算 mergeSha 并再进入 push。这是静态风险而非已复现事故；现有祖先退出码组件测试不覆盖该窗口。可信 selection、生产入口、锁与实际 signer/效果证据均未由本矩阵证明。

双端主设计和测试计划仍以对应 change 下 `design.md`、`test-plan.md` 和 code canonical 为准；本矩阵仅供收敛，不能单独解除 BLOCK。候选方案原稿见 `projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/remote-merge-recovery-amendment-proposal-20261030.md`；本矩阵只做对照，不另立第二套候选方案；原稿亦为 DRAFT、未获批准。

**后续条款化草案（2026-11-03）**：`validation/remote-recovery-paired-amendment-draft-20261103.md` 把本矩阵中“需成对修订”的格子写成可逐条评审的条款文字（格 1 `pending-verification`、格 2 先读 settlement、格 3 收紧 `SC-MG-016`、格 4 `intent+expected`、格 5 混跑/回滚），并记录 strong 评审提出的 6 项 P1 与逐项修正。该草案同样是 DRAFT、未改任何 canonical，仍须双端配对审批。独立审查会话 `01a1976a-18fc-7468-8217-4d365277c2db` requested `GBClaude/claude-opus-5-5:high`（plan profile），actual 无模型回执，记 `unknown`；委派约束为只读，协调者未见其执行记录，不据此证明。第二轮复核会话 `01a1977d-5f08-7468-8217-4d3d93ea42a6` requested 同档、actual `unknown`；协调者核对并采纳 given/then/and、SC-TR-006、SC-MG-020、SC-MG-016 候选收紧和源码窗口转述等更正；同一审阅会话再次指出草案批准措辞、不可变 settlement 表述及 D4 适用性等问题，协调者已更正。同一审阅会话再次只读核对更正后的矩阵及 T design D4/图示，报告所列问题已纠正、未见新增误称批准或改写归档；该复核不覆盖 M design、原生校验或运行证据。

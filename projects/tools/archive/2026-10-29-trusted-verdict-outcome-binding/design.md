# 可信 verdict 结果与命令绑定：tools 生产侧设计（收窄版）

> **状态（2026-11-10）**：用户采纳收窄建议，本文按收窄方案重整；Gate 2 已于 2026-11-10T14:39 按现状重新确认，本文档已进入 BUILD；C1 的实施分层见 M `pending-adjustments.yaml` ADJ-TVOB-001。本文不授权签名代码修改、真实签发、数据库或部署。
>
> **单一事实源**：保证 G1–G3、检查 C1–C4、决定 K1–K5 只在 [M design](../../../multica/changes/2026-10-29-trusted-verdict-outcome-binding/design.md) 定义，本文只写 T 侧职责，不复述、不另起一套。收窄前全文原样保留于 [validation/design-before-narrowing-20261110.md](validation/design-before-narrowing-20261110.md)，其中的签发权威调查、旧合同核对与阻塞表仍是事实来源。

## T 侧职责

| 职责 | 内容 | 对应 |
|---|---|---|
| **v2 签发** | 签发的 payload 为 K1 定义的闭集字段（版本、结果、冻结命令摘要、主体、`epoch/sequence/previous_verdict_digest`；generation 无独立字段，见 M `pending-adjustments.yaml` ADJ-TVOB-002）；结果只取 K2 闭集。v1 签发路径保留读取能力用于历史，不再产生可放行新 effect 的证明。 | G1、K1、K2 |
| **产出共享向量** | 由真实 v2 签发代码生成 C2 向量（正例 + 规定反例），提交到 M 侧共享位置；T 侧只引用 M 的计数（TC-VM-014），不另计验收。 | C2、K4 |
| **远端恢复决策** | 按 [trusted-merge-gate 规格](specs/trusted-merge-gate/spec.md)（与 M 同文）：`unknown + expected` 不重推、只记观察；无可信 effect/no_effect 证据时不结算、不新 reserve/push。原 TC-MG-015/016 编号沿用。 | G3、K5 |

T 侧签发前不再单独建设「拒签」防线作为验收项：放行的唯一判定在 M 的 C1，T 拒签是纵深防御，可实现但不计入本 change 的保证。

## 范围

- **纳入**：上表三项的合同与组件级验证。
- **不在本 change**：真实入口与 DB 证据（归 AIFI-45，见 M design §范围）。
- **移出到上线就绪清单**：生产 signer 与私钥持有者、manifest 来源与 pin、隔离环境重新出证、key 轮换/撤销/泄露与历史有效性、升级/回滚与在途策略。缺失时 M 侧 G3 保持拒绝。
- **M009**：T 侧原承接段一并移出，随 M 侧规格移回 AIFI-45。
- **MERGED-SCOPE（D3）**：并入项的落点见 M design §范围；唯一载体决定不变。

## 原 D1–D5 去向（供 canonical `evidence: design#Dx` 追溯）

| 原候选 | 去向 |
|---|---|
| D1 先证明可信来源与权限，再决定签发协议 | 来源与权限 → 上线就绪清单；协议 → K1 |
| D2 先核旧合同，再比较 wire 方案 | K1（v2） |
| D3 绑定权威请求、冻结命令与主体 | G1、K3、C2 |
| D4 实际 effect、恢复与并发边界 | G2、G3、K5 |
| D5 兼容、撤销与跨仓验证 | G3（v1 永不放行）、C2；撤销与 key 生命周期 → 上线就绪清单 |

## BUILD 切片

T 只参与 S1（v2 签发 + 向量）。S1 先于 M 侧 S2；T 的 v2 签发在 M 验证端上线前不会放行任何 effect。

## 风险

- v2 需与 M 同步发布；M 验证端先上线时只会拒绝，顺序安全。
- 上线就绪清单负责人未定前，不承载生产私钥或信任名单。

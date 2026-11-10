# 可信 verdict 结果与命令绑定：multica 消费侧设计（收窄版）

> **状态（2026-11-10）**：用户采纳收窄建议，本文按「3 条保证 + 4 项检查 + 5 项决定」重整。决定 K1–K5 是用户采纳的方向；Gate 2 已于 2026-11-10T14:39 按现状重新确认，本文档已进入 BUILD；C1 的实施分层见 `pending-adjustments.yaml` ADJ-TVOB-001。本文不授权 BUILD、数据库、部署或签名代码修改。
>
> 收窄前全文原样保留于 [validation/design-before-narrowing-20261110.md](validation/design-before-narrowing-20261110.md)；其中的调查依据、静态写入口清单、ADJ-8/11 分析与阻塞表仍是事实来源，本文不重复。生产侧对应文档见 [T design](../../../tools/changes/2026-10-29-trusted-verdict-outcome-binding/design.md)。

## Context

AIFI-45 准入查询以 `settlement.kind=effect` 为通过条件，而 `settlement.kind` 由调用方输入；现有验签绑定原字节、scope 与帧字段，但不覆盖裁决结果语义及其与冻结命令的对应关系。

**当前生产态是失败关闭的（2026-11-10 静态核查）**：`ApplyControlCommandTx`、`SettleControlCommandTx`、`ControlWorker.ApplyTx` 的非测试调用方为 0，`ControlWorker` 只在测试中构造，生产链路上 `Admitted` 不可得，准入稳定停在 `WAIT_TRUSTED_T_COMMIT`。因此本 change 要解决的是「如何安全地放行」，不是修补已暴露的放行漏洞；任何信任前提未满足时继续拒绝，不影响安全。

## 保证（本 change 只承诺这三条）

| 保证 | 内容 |
|---|---|
| **G1 可信绑定** | 新增 effect 只能由一份签名覆盖「版本、结果、冻结命令摘要、主体（request/task、scope、lineage）、`epoch/sequence`（无独立 generation 字段）」的可信裁决放行；`settlement.kind`、caller 自报值或签名形状本身不构成放行依据。 |
| **G2 单写入者、重放幂等** | 每个 lineage 只有一个持当前 owner fence 的写入者，经 `AppendVerdictFrameTx` 按 seq 追加；同一帧重放落到原行，不产生第二条 verdict 或第二次 settlement。 |
| **G3 不确定即拒绝** | 结果未知、版本未知、旧格式（v1）、证据缺失、读取失败、仅有远端观察时：不写 settlement、不放行新 effect、不回退旧路径。已有合法 no_effect（归档 SC-VC-022）与已批准恢复表（SC-VC-015/SC-TR-006）照常适用。 |

G3 统一覆盖原先分散的特例：M008 远端恢复、旧数据、防删除降级、异常不回退 legacy。这些情形不再各自设计检查。

## 检查（每条保证由尽量少且职责单一的检查支撑）

| 检查 | 职责 | 支撑 | 归属与计数 |
|---|---|---|---|
| **C1 单一验证点** | 写入端 `AppendVerdictFrameTx` 验签（既有）；准入端 `DecideAdmission` 对已入表的 payload 复核 effect 闭集、`command_digest` 与冻结命令字节一致、scope 包含；失败回落 `WAIT_TRUSTED_T_COMMIT`（分层理由见 ADJ-TVOB-001）。 | G1、G3 | 本 change（M） |
| **C2 共享黄金向量** | 一个向量文件，Go/Node 共读：1 个正例；错主体、错命令摘要、未知结果、未知版本、篡改字节、未知字段各 1 个反例。同时冻结 digest 公式。 | G1 | 本 change；**M 唯一计数**（TC-VM-014），T 引用 |
| **C3 准入状态表** | 一张表驱动测试：pending / deny / stopped / unknown / v1 旧格式 / 仅远端观察 / 可信 effect，只有最后一种放行。 | G3 | 本 change（M） |
| **C4 真实入口端到端** | 隔离 PostgreSQL：生产者 → 帧 → 准入 → effect；同帧重放无第二次 settlement。 | G2 | **AIFI-45**（proposal 规定真实入口与 DB 证据由各自变更提供）；本 change 只定义合同 |

现有 TC-VM-001～019 全部归入 C1–C4 或上线就绪清单，见 [test-plan](test-plan.md) §三；不新增编号。

## 决定（用户 2026-11-10 采纳方向，待 Gate 2 重审）

- **K1 签名合同升 v2**：现有签名不覆盖结果与冻结命令，故新增 v2，签名内容即 G1 所列字段（代次由 `epoch/sequence` 表达，无独立 generation 字段），字段为闭集，含未知字段的 payload 整体拒绝。v1 只作历史保留、永不放行新 effect；不迁移、不重签、不删除。
- **K2 结果闭集**：`effect`、`no_effect`；其余（含缺失）一律按 unknown 处理，适用 G3。
- **K3 关联键**：沿用现有准入查询对 `cr_execution_control_settlement.request_id = cr_execution_consumption.task_id` 的假设，由唯一写入入口强制 `RequestID = task_id`，不一致拒绝；不同时改查询与生产者。
- **K4 digest 公式**：由 C2 向量冻结现行公式（含前序链摘要，ADJ-8/11 分歧在此收口）；Go/Node 结果不一致即停止，走修订，不在实现中各自适配。
- **K5 M008 远端恢复**：批准 [trusted-merge-gate 规格](specs/trusted-merge-gate/spec.md) 的 SC-MG-015/016 修订，核心一句——**远端状态是观察，不是结算**；无可信 effect/no_effect 证据时不新写 settlement、保持排他、停止下一受保护动作。SC-VC-035 四分支保留，`200` 原 mapping 不是新发布授权。

## 范围

**纳入本 change（合同 + 组件级验证）**：G1–G3 的合同条款；C1–C3；T 侧 v2 签发（见 T design）。

**不在本 change，但为 G2 的前提（归 AIFI-45）**：M005 生产接线（单写入者、K3、游标与帧同事务、失败回滚与重放落原行）与 C4。未落地前 `TC-RUN-001`「实际任务与 T receipt 匹配」及 `CP-RUN-001` 真实通过不得宣称。若要改为本 change 实施，须修订 proposal 并重走 Gate 1。

**移出**：
- **M009 通知身份**：与本 change 无共同保证、代码或验收，移回 AIFI-45，见 `../2026-10-22-aifi-45-authorized-execution/validation/m009-attention-routing-spec-20261110.md`。
- **上线就绪清单**（生产启用前的门禁，不计本 change 验收；缺失时由 G3 保持拒绝，不降低安全）：生产 signer 与私钥持有者、manifest 来源与 pin、目标环境隔离重新出证、key 轮换/撤销/泄露处置及历史证据有效性、升级/回滚与在途请求策略。**负责人待指定。**

**并入范围（T 侧 MERGED-SCOPE D3）的落点**：subject 绑定 → C1；防删除降级、异常不回退 legacy、合同选择 → G3 / C3（按版本字段显式选择，无回退）；机械例外包装器 → 仅当该路径实际存在时经 C1 校验，否则不做。

## 原 D1–D5 去向（供 canonical `evidence: design#Dx` 追溯）

| 原候选 | 去向 |
|---|---|
| D1 已认证裁决是新增 effect 的必要前提 | G1 |
| D2 先核既有合同，再定签名方案 | K1（v2） |
| D3 双端共同定义绑定与 effect 证据 | G1、K3、K4、C2 |
| D4 所有入口与撤销竞争闭合 | G2（单写入者使「每个入口」收敛为一个）；撤销锁序沿用 AIFI-45 验收（C4） |
| D5 历史数据和部署 | G3（v1 永不放行）；部署与 key 生命周期入上线就绪清单 |

## BUILD 切片（Gate 2 重审通过后）

| 切片 | 内容 | 归属 |
|---|---|---|
| S1 | C2 共享向量 + T 侧 v2 签发 | 本 change（T 产出、M 计数） |
| S2 | C1 单一验证点 + C3 准入默认拒绝 | 本 change（M） |
| S3 | M005 单写入者接线 | AIFI-45 |
| S4 | C4 隔离 PG 端到端 | AIFI-45 |

顺序固定：先合同（S1），再安全（S2），最后可用性（S3–S4）。S1–S2 完成后生产仍失败关闭，可独立交付。

## 风险

- K1 升 v2 需 M/T 两仓同步发布；先发 M 验证端（只认 v2，拒 v1）不会放行任何东西，顺序安全。
- 「合同完成」不等于「可上线」；上线就绪清单未指定负责人前，生产保持失败关闭。
- 两侧 Gate 1 为历史无指纹确认；本次收窄未扩大 proposal，故不需重签 Gate 1，但 M008 承接是否属于原 proposal 范围仍由 Gate 2 重审时人工确认。

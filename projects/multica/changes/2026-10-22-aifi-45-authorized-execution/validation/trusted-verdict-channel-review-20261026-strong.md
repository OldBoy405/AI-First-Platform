# 通道方案 v0.1 独立安全复核

- 对象：`trusted-verdict-channel-plan-20261026.md`，原始作者草案（提取时 SHA256 前缀 `9d3e8827593773af`）。本文件为主会话归纳，原始全文在子会话记录。
- 非作者只读 reviewer：`01a17703-a5bb-77b9-a3c5-0f4ff7cbead9`；STDD `code/strong`，requested `OpenAIPersonal/gpt-6.1-sol:high`，actual 未获后端回执，记 unknown。
- 未执行测试、未访问 DB、未写源码。结论 **BLOCK（针对 v0.1，不等同于 Gate 决议）**。

## Findings 与修订要求

| # | 严重性 | v0.1 行号 | Finding | 修订要求 |
|---|---|---|---|---|
| 1 | blocker | 59–61,72–74,150–152,176 | C 的真实隔离仍未证明，却已排定后续实施 | 前置 S0：不同 OS 身份/等价隔离边界的攻击探针与正对照；不通过则不可选 C，需转 B 重新完成部署设计。不是运行时降级。 |
| 2 | blocker | 87,106,135–137,178 | 首次任务不存在，而旧 643–645 接口要求实际 active task generation，永远等待 | 独立不可执行代码的 control reservation，exact-key tagged union：control reservation 或 actual task generation。不放宽旧 active-claim 查询，不借无关 active task。643–645 在实际任务派发后、代码启动前按真实 generation 校验。 |
| 3 | blocker | 146,155–156,167–171 | Channel 等 AIFI-45 decider，而 AIFI-45 正向 TC 等 Channel | 基础接缝必须有独立真实验收；通道组件不等完整 decider，业务 E2E 留 AIFI-45。reviewer 建议第三个 Foundation change；主会话选择更小的等价分层：基础切片归入新 Channel change，形成 Channel(S1→核心) → AIFI-45 集成，无第三个 change。此归属须 v0.2 复核。 |
| 4 | major | 96,111–114,119,124,126 | 规则返回会改变 replayed/诊断累计值，重新包装导致同 request 签名字节冲突 | 首次 protected commit 冻结完整 payload、序号、前驱摘要、key ID；传输重投不改变签名内容；verdict digest 固定为 SHA256(domain + 原始 payload)。 |
| 5 | major | 78,107,125,128,177 | “回滚 freeze”缺可执行检测与 restart fencing | M 持久单调 owner fence；重启接单前 reconcile cursor/checkpoint/journal/open command。普通重启不重置 store epoch/sequence；缺失、落后、分叉等一律 freeze。 |
| 6 | major | 118–126,153 | revoke/stop/effect 线性化点与卡死 slot 恢复未定义 | revoke 不等 slot；effect 同 Tx 重验 current head。stop 按 T sequence，不追溯撤销已 settled effect。超时不能推断未消费、释放 slot；恢复原 request 或冻结。pending/deny 明确 no_effect settlement。 |
| 7 | major | 79–81,139 | domain allowlist 不等于 key-purpose 权限 | operator manifest 同时绑定 key→purpose/domain/scope，签发与验签均执行。优先独立 command key；复用 approval key 需显式双用途授权，attestation key 不能签 human grant/resume。 |
| 8 | major | 121,126,138,167–171,182 | 可信合同选择读源未交付，nil/legacy/replay 边界不完整 | 持久化可信合同选择，unknown/读取失败不等于 legacy；strict composition 缺 reader 拒绝。settled replay 只返回旧 effect，未 settled 只提交原固定候选，不允许借旧 receipt 新动作。 |

## 已发生的基线变化

- F4 已实现并通过 strong 源码复核；此轮 test-config 复核后又补强 SQLSTATE 锁探针。v0.1 “当前只锁 CR”是历史快照，不再作为实施任务。
- 最终锁回归证据 `f4-lockstate-20261026-regression-v2.meta.json`：256/256、0 fail、0 skip、229 PASS leaf；主会话执行，非本 reviewer 复跑。
- v0.2 必须补可复制的 Node/Go runner 命令、迁移清单、跨仓环境、真实 positive controls、业务 RED 断言，以及批准 DB 单执行者约束；具体来自 balanced 测试复核。

## 复核边界

v0.1 被否决，原文保留作历史。修订稿另存 `trusted-verdict-channel-implementation-plan-20261026.md`；不能仅因已按建议修订便称为 reviewer PASS，必须独立复核或明示尚未复核。

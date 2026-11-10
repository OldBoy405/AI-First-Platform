# 可信 verdict 结果绑定：提交用户审阅

> **状态：用户已审阅确认，两侧 Gate1 已按原生 STDD 记录。** 用户对上列 multica/tools 两侧 proposal 与 canonical 的原话为“审阅确认”；本次在对应业务仓分别用 `--gate 1 --confirmed-by dialog --evidence 审阅确认` 登记。CLI 记录执行方 `confirmed_actor: ai`，不能将其误记为真实签发者身份。Gate2/3 仍 pending。文件名保留原历史名称；Ray 仍是草案列明的负责人，用户审阅确认不证明生产签发者、信任根或实际部署。

## 请同时阅读

- multica proposal：`projects/multica/changes/2026-10-29-trusted-verdict-outcome-binding/proposal.md`
- multica canonical：`projects/multica/changes/2026-10-29-trusted-verdict-outcome-binding/canonical/proposals/2026-10-29-trusted-verdict-outcome-binding.yaml`
- tools proposal：`projects/tools/changes/2026-10-29-trusted-verdict-outcome-binding/proposal.md`
- tools canonical：`projects/tools/changes/2026-10-29-trusted-verdict-outcome-binding/canonical/proposals/2026-10-29-trusted-verdict-outcome-binding.yaml`

Human View 不展示全部约束、非目标及利益相关方信息，不能替代 canonical。旧 trusted-verdict-channel change 的批准也不能继承到本 change。

用户确认前两仓 Gate1/2/3 均 pending；以下为交付审阅时的 raw SHA-256。确认后 Gate1 自动重渲染 proposal，仅 `generated_at` 发生字节变化，canonical 原文不变；两仓 `stdd canon verify` 均 2/2（仅源哈希与字段引用，不证明语义或生产事实）。

| 仓 | proposal.md | canonical YAML |
|---|---|---|
| multica | `132563469890db5989a7002f2646a4efe82a05e553ba053d82bf8faba74a4626` | `a0821fc558d8647a35f53dc2a638e7148fd1c22b3b92f449aec01a78ce5bf936` |
| tools | `e468b87b82d22b6c37220565e810d2999e58bb311a8cf8be9ac93efc4aa99024` | `1db813510c93a647107a892a5b75a59064a420f0b29b72f49dc0b3ee8b0c37ff` |

确认后的 proposal raw SHA-256：multica `3345ecc56590b5be5fe19cb0f3f4c3e1c4ce7d0dae88b07784a3dfcbd1d40ec9`，tools `a6ee2ac9a9271166eb64eba09f0d623b73db36ccb1b336d3dcdf078c6f0c89e7`；将其生成时间恢复到审阅快照后，两份文件分别与表中审阅原始字节的哈希一致。若之后发生其他变化，需重新核对。

**时间性说明：** 两份已确认 canonical 原文中的“当前为 understand 草案，所有 Gate 均 pending”是确认前快照，现已过时；没有静默改写已确认的 canonical。当前阶段与 Gate 状态以两仓各自 `.stdd.yaml`/`stdd gate status` 为准。

## 生产事实与来源（未决，不要求猜测）

如已知，请指出可核验的文档、实际配置或代码入口；未知项可保持待核，不要在本仓或回复中粘贴私钥、密码或其他秘密。审阅草案范围不等于确认这些事实。

1. 哪个生产组件在哪个入口生成 verdict，所依据的事实如何取得？调用方输出或自报是否可能影响结果？
2. 实际签发组件、私钥持有进程及身份是什么？其 key ID 与持钥方式由哪个权威来源确认？方案中的隔离 T worker 是设计意图，尚不是已部署事实。
3. 生产验签信任根由谁管理？请给出可供有权限人员核验的 manifest 标识、摘要、key purpose/domain/scope、有效期及轮换和历史 key 处理；不公开秘密。
4. 签名如何绑定 permit/deny/pending/stopped 与 settlement 的 effect/no_effect？谁有权执行映射，如何防止 caller 自报 `Kind` 代替签名结果？
5. 如何绑定 frozen command/candidate、request、subject、lineage、task/runtime、`dispatched_at` 与 daemon generation？现有 v1 是否足够，或有证据表明必须变更版本？
6. 实际生产调用、历史 verdict、旧格式兼容、密钥轮换、恢复与重放的事实和限制是什么？

## 已知边界

- 仓内已有 operator-pinned trust manifest 与 `tool-attestation` 等验签机制，但本次只读检查未找到足以确认生产签发者、实际 key ID、生产 manifest 或私钥持有进程的证据。
- 当前 settlement 的 `Kind` 是调用方输入，准入查询检查已记录的 `effect`；这不等于签名结果与 effect 已完成可信语义绑定。
- 已归档通道的验收仅覆盖其声明的组件范围，不等于 strict-production 接线已完成。
- 独立静态评审仅作辅助，不能冒充用户的人工审阅或 Gate1 确认。

## 审阅结论与后续边界

用户已就两侧 proposal 与 canonical 作“审阅确认”。这确认的是提案的问题、范围、分工和约束，不自动确认签发者、信任根、现网或历史数据；这些生产事实继续待核。后续设计须另提交 Gate2，不得将 Gate1 扩大为实现、部署或 Gate3 批准。

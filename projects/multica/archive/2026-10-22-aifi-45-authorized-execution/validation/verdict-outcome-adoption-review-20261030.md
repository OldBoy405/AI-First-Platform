# 已采纳方向的两侧 SPEC 草案：独立复核

> **历史快照：** 以下 SHA 与复核范围是上一轮的冻结材料，之后两侧 design 已根据 `verdict-recovery-digest-decision-20261030.md` 更新风险说明；本页不能作为当前文档字节或当前完整评审结果。

## 范围及结果

用户方向确认的精确范围见 `verdict-authority-acceptance-20261030.md`，不是 Gate2。两侧 thorough planner 分别只读给出修订建议，会话 M `01a18b6c-b66e-7020-aecc-d4cbbef725c9`、T `01a18b6c-b67e-7020-aecc-d4cd356aa107`；独立 reviewer 为 `01a18b79-e38c-7020-aecc-d4cf98737e9a`。请求 strong `GBClaude/claude-opus-5-5:high`，实际 backend 无回执，记 unknown；均未执行程序、访问服务/DB/容器/密钥或改写源码。协调者根据意见编辑文档。

reviewer 初审确认方向边界、permit→本次效果→后续准入的时序及 proposal non-goal 无所核范围内问题，但提出四项草案缺口：

| 项 | 问题 | 草案修订与复核 |
|---|---|---|
| F1 | 归档 SC-MG-016 的 unknown + `settled_no_effect` 分支和当前 caller 报告未核回执，未充分披露 | 复用评估补两分支与证据边界；M SC-VM-009 / T SC-VT-009 及各自 TC 覆盖未认证 no_effect 冻结；reviewer 判 RESOLVED-FOR-DRAFT，不代表真实可达或归档已变更 |
| F2 | 远端含 expected 只证明目标状态还是能归因本次 attempt，尚无决定；SC-MG-015/016/017 与 intent 分支需协调 | reviewer 判 RESOLVED-FOR-DRAFT **仅为阻塞披露，问题未解决**；已补两个候选事实分类与 intent 分支范围，现有 canonical evidence 显式引用归档及待审评估，不假装合同已选 |
| F3 | 归档 ADJ-11 指向域分隔摘要，M 当前链用 payload-only，不能预设差异合理 | 双方 design、SC/TC 和评估列为待协调，比较已批准字段映射，不无依据合并或互换；reviewer 判 RESOLVED-FOR-DRAFT，具体公式和兼容未决定 |
| F4 | 隔离证据误写为已有逐请求信号 | 已从逐请求 SC 删除，作为部署/readiness 前置；reviewer 判 RESOLVED-FOR-DRAFT。后续补引用 M 归档 SC-VC-037 / T SC-TR-013，不能把 mock 当真实隔离证据 |

reviewer 未独立计算下列最终文件摘要；其最后定向复核之后，协调者仅补了 F2 的 canonical evidence/候选事实说明及 F4 的归档引用。下列 raw SHA 是协调者的当前快照，不冒称 reviewer 对这些最终字节逐项签核。

## 文档检查，不是业务测试

- `stdd validate`：M/T 均 exit 0；`stdd canon verify`：M/T 均 2/2，仅覆盖其报告的源哈希与字段引用。
- 独立严格 YAML 重复键检查及 ID 映射：M 6 REQ / 19 SC / 19 计划 TC；T 5 REQ / 15 SC / 15 计划 TC；SC 与 TC 唯一映射，Human View 与 canonical 当前渲染一致。逐 SC 检查 G/W/T、confidence、evidence、SHALL、AND 上限。
- 两侧 agent-spec 均仍为 TODO；所有 TC **未运行**。以上绿灯不等于可执行计划完整、业务通过或 Gate2 已批准。
- Gate1 confirmed，Gate2/3 pending，两侧保持 SPEC / thorough；未实施业务代码、访问历史事故库/容器、执行原 runner、签发或部署。

## 上一轮草案快照 raw SHA-256

路径相对于 `projects/{multica,tools}/changes/2026-10-29-trusted-verdict-outcome-binding/`：

| 侧 | 文件 | SHA-256 |
|---|---|---|
| M | `design.md` | `e1f4c8ab386f3c8e84673f332ebd56266ab7ae62b7bd56e19a6ead2ab5a6d300` |
| M | `canonical/specs/code/2026-10-29-trusted-verdict-outcome-binding.yaml` | `53605dd181c840e79ca0f9f59617febd084bea7285c3006bd4f55f631cfc9fb9` |
| M | `test-plan.md` | `ca3cde26be2dd6eba657f1ec21dc254db1f33bff5a1307b0b3f29a3af7042bef` |
| M | `specs/verdict-channel/spec.md` | `aa264599d91001402188b13d6c0d52cbb9e57f538e947e69940d9358023ae1b2` |
| T | `design.md` | `7d05c0893bf2d0b12189338306cb56bce1a6913535bb24ff240f4d9c708a5e7f` |
| T | `canonical/specs/code/2026-10-29-trusted-verdict-outcome-binding.yaml` | `0ee5e5cbd5505461675acd63a62d4c952354999a4437237da7a9e334a2e5dd5a` |
| T | `test-plan.md` | `95a88c12c2d4c451cb99822a497f702b781183efdfefe6a8e315817e720ec9e7` |
| T | `specs/verdict-channel/spec.md` | `50daa37bbdcc0305edf343aa589143752c728f32f83a44e5e2358a34fe937b1a` |

## 后续阻塞

由两侧确认前序摘要映射与远端证据语义及其与归档恢复合同的关系；完成生产签发者、名单、隔离、存量、key 事件和实际入口的权威证明或安全前置条件；明确跨 change 职责及测试入口，补齐 agent-spec，形成完整 Gate2 材料并等待用户明确确认。不能凭此次方向确认进入 BUILD，或解除数据库 HOLD。

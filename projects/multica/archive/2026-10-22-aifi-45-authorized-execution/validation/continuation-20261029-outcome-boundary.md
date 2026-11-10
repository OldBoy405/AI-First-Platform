# 2026-10-29 续接：生产组合与 verdict 结果边界

## 用户决定

授权 AIFI-45 内按默认拒绝接真实生产入口，消费侧修复留在 AIFI-45；如果必须修改已归档通道签名字段/readiness 签名契约则分流独立 change。授权登记 EVD-008 占位、负责人 Ray、三项触发条件。授权不是部署、真实 CR、Gate3 或未通过 Gate 的签名契约实施。

## 本轮实际结果

- `2026-10-29-legacy-execution-migration` 在 multica 项目下登记 proposal draft，负责人 Ray，三项条件完整，四阶段 pending；D8=A 不变、TC-EVD-008 MISSING，偏差待实际审批。
- `execution_deployment.go` 对 ACTIVE 未知 op / 未知 mode / 精确恢复缺时间、无效 generation、双侧空 pin 拒绝；补充单侧空字段与两个恢复 op 覆盖。独立 fakeTx 最新 7 顶层、109 leaf PASS、0 skip，绑定源码 SHA `0d9773985591f63035c7bc706d9e406e1a929f2bed990235b5d0d287cea96e0a`、测试 SHA `646f5214e424d08f66dac5fae0cb59ffeac20a7acc3b581f445ef90191fc4c59`，证据 `active-admission-guard-review-20261028/`。
- `router.go` 在启用 architecture runner 的分支构造 runner 前拒绝 nil/typed-nil decider。`main.go` 目前未传 decider：开启开关将终止整个 server，未部署。此 guard 只检查形状，不认证非 nil decider；其他构造路径和上游 effect 不由此防护。不要将现有 CR-level decider 提前注入 main；它尚未绑定 generation、可信 outcome 和完整链路。
- 作者与独立 no-DB 复跑两包分别 1 顶层/13 leaf 与 3 顶层/3 leaf，skip 0；真实启动未执行。AST 变异检出传 nil、guard 后改 opts、exit 前 return、alias 及 `:=` 遮蔽，但 AST 只检查当前 router 文件，不是执行时、安全或其他路径证明。最终 AST raw SHA `897b8192b6eb47704822cc2ed23775e8356a33f878f32dc91adf81aa46da8026`，独立报告 `production-admission-composition-20261029/REVIEW-LHS-BALANCED.md`。精确快照在同目录 `source-first-green/`、`source-recheck/`、`source-final/`，注意 raw SHA 不应行尾归一化后再比对。
- `execution_admission.go` SHA `23cac3ae674b5aa7e93676bc3c2f04c691e5dde27a695ad0e347a0b266c5a92e`，`runner.go` SHA `d8898444d260d2f674d84b2709ac3f4c622b00d502013a2cd0626c0ad4552811`，后续只改注释降低过度表述；`router.go` SHA `0ee5c8cfeafd688a851c8604d2382354f2fb2171d7facbe18a5185eee7b18f87`。server 和 CLI 单独 build 成功，未运行可执行文件；CLI 最终 help SHA `9829b5d606d9e70ab3bd7c6d1592f78e1faea44634b3edfac22d75991e3a5a33`，见 AUTHOR-CLI-WORDING。multica CUSTOM #275。
- 静态分析发现当前 `settlement.kind` 由调用方输入，验签未验证可信裁决语义或冻结命令；不能把签名原字节、未知字段或 caller kind 当 permit。不能推断生产无 v1 历史、没有攻击面或结论必需 v2。19 个源码/契约字节快照与 SHA 见 `verdict-outcome-contract-20261029.md` / `verdict-outcome-source-20261029/`。
- 对可能涉及签名契约的问题在 workspace 的 multica/tools 各登记同 ID `2026-10-29-trusted-verdict-outcome-binding` 草案，负责人待指定，所有阶段 pending；须先评审现有契约是否足够，不能预断必须扩展、v2 或迁移为空。两侧 YAML 与索引可解析、各3目标均存在；`stdd validate` 均 exit 1，缺 `proposal.md`（Gate1 Human View 未生成），不是通过。审阅和两版快照见 `verdict-outcome-proposal-review-20261029.md`。reviewer 无哈希工具且原始 backend receipt 不可用。

## 事故与环境

独立复核者用 shell `> /tmp/dacc-review.log`，事前未确认是否存在，也没有独占创建。若该路径原有文件，内容可能被截断，实际事前状态未知；已向用户披露并记录 `active-admission-guard-review-20261028/INCIDENT-RECOVERY-REVIEW-TEMP.md`。该路径未删除或再次写入，不能冒认归属。未来所有子代理明确禁止固定临时文件，使用独占目录或内存。

本轮未运行 DB、容器或真实 CR，未提交、推送或部署。三仓 git diff --check 通过但不覆盖所有 untracked 文件；multica CUSTOM LF、tools CUSTOM CRLF。既有脏树不重置、不 stash。新容器仍未创建。

## 未完成 / 下一步

Gate3 仍 NO-GO，TC-EVD-008、RUN-001/003/006/007 仍 MISSING；M001–M005 unresolved（历史 accepted 风险与完全 resolved 不同）。必要工作包括 outcome 身份与兼容契约、generation 真相、writer→admission 事务及锁、未门控 effect 和 readiness、真实入口、独立安全审查的临时库/进程生命周期，以及真实隔离库证据。先确认跨仓契约草案负责人，按 STDD 推进设计/审批；不可仅为解除启动失败把已知不完整 decider 传给 main。

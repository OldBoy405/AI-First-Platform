# 用户决策：AIFI-45 接线和 EVD-008 后续登记

用户在本次对话明确回复：

> 授权 AIFI-45 内的生产入口接线。同意通道问题按上面「契约是否改变」的规则分流。EVD-008：登记占位 change，负责人 Ray，上面三个触发条件可以。继续完成待完成项。

## 接线范围与边界

AIFI-45 内接最小真实入口的 AdmissionDecider，默认拒绝；消费侧问题在本 change 处理。若需更改已归档通道的签名字段或 readiness 签名契约，另立通道加固 change，不能以接线授权改写既有契约。通道组件测试不双计为 AIFI-45 RUN TC。真实入口实现仍须先解决可证明的可信事实、权限、锁与事务边界，完成 RED/GREEN 和独立复核；用户授权不等于安全性已证明，不等于 deployment、真实 CR、提交推送或 Gate3 批准。

更正前次 `continuation-20261028-supervisor-admission.md` 关于「通道是用户负责的独立后续 change」的表述：已有 change `2026-10-27-trusted-verdict-channel` 处于 archive，phase state 记录了 deliver completed；应区分它的组件交付、当前 AIFI-45 真实接线和独立完整验收，不能据归档或组件 PASS 推断安全闭环。保留前次记录原样作历史，新的本决策为当前依据。

## EVD-008 独立占位 change

仅登记 proposal 占位，不自行启动 SPEC/BUILD。负责人 Ray；满足下列任一条件应启动该 change：

1. D8 变更为迁移 legacy 业务历史；
2. 准备对包含在途旧授权或旧消耗历史的 workspace 生产启用；
3. 拟给 `evaluateExplicitMigration` 接生产入口。

需要可核实的授权 lineage、历史消耗、未决任务三类可信事实源。占位登记不意味着迁移已完成，不改变 D8=A，也不将 TC-EVD-008 改为 PRESENT；Gate3 的偏差接受必须按现有流程真实履行。

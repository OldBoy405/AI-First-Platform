# AIFI-45（multica）限定长程预授权

- 用户先确认 **“确认以上限定授权”**，后对扩大执行范围明确回复 **“同意以上授权”**。两次原话及范围见 [用户确认记录](validation/aifi45-long-range-auth-confirmation-20261030.md)；后续授权取代原逐条命令限制，但不改变安全与审批边界。
- 当前原生状态：BUILD `in_progress`，`long_range.enabled=false`、`mode=normal`；**没有登记为 STDD 原生 full_auto**。用户确认的是更严格的限定授权，不改变 Gate、major、真实资源 HOLD 或状态机。
- STDD 3.0.7 的模式选择说明仅定义在 Gate2 确认时启用，未定义 BUILD 中途启用；Guard 保护 `.stdd.yaml`，当前 CLI 没有对应的模式切换命令。不得以手改状态或重复审批冒充原生登记。
- 在普通模式及后续授权范围内独立工作；安全或审批阻塞只如实记录，不能绕过。历史事故库和固定旧 runner 继续 HOLD；已授权建立全新独立隔离 DB，具体入口须安全验证，和原合同的差异按 B4/C6/Gate3 处理，不静默豁免，相关 TC 仍未完成，Gate3 仍 NO-GO。
- pi 宿主不写 Claude Code 权限文件；M001–M006 仍为 unresolved major，M006 的直接登记方式合规处理仍待核，不因授权或格式检查关闭。

## 后续用户请求

用户原话：**“同意，启用全自动长程模式，或者告诉我在哪里可以修改，我自己修改为全自动长程模式”**。其中“同意”针对 tools `readHash` 的提前独立实施及经审查的内存 RED→GREEN；另请求启用原生全自动长程。当前 BUILD 中途尚无已确认的原生启用入口，本记录不变更 `.stdd.yaml`，不重放 Gate2；原生状态仍为 normal。该请求不自动解除既有事故资源 HOLD、Gate3 人工确认或其他明确限制。

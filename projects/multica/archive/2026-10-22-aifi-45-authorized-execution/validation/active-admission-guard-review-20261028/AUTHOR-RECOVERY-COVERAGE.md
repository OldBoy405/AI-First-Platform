# 精确恢复补充覆盖（作者）

针对 `RECOVERY-EMPTY-REVIEW-STRONG.md` 的测试建议，保全该审阅时源码及测试至 `source-recovery-empty-final/`，然后**只改测试**：分别将 origin、persisted origin、digest、persisted digest 单侧置空，并在 STOP_NEW/过期 ACTIVE 两种状态下，对 `complete_unsettled_request` 和 `bind_existing_mapping` 两种恢复操作运行全部缺失事实案例。单侧空原先理论上已被相等比较拒绝；这不是新生产行为或宣称新的 RED。

作者无 DB 重跑 `go test -count=1 -json ./internal/governance/deploymentaccess_test`，7 顶层、109 leaf PASS、0 fail、0 skip；源码 SHA 仍为 `0d9773985591f63035c7bc706d9e406e1a929f2bed990235b5d0d287cea96e0a`，新测试 SHA `646f5214e424d08f66dac5fae0cb59ffeac20a7acc3b581f445ef90191fc4c59`，运行前后未变。已归档的 79 leaf 独立结果只对应先前测试 SHA；此测试快照待独立复核。

仍未验证输入来自权威 DB、RequestID 绑定、可信时间、签名或并发；不用于 RUN/Gate3 验收。

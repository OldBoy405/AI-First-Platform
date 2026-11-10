# TAB 通知守卫：测试准备与静态复核

状态：**未执行，BLOCK**。生产守卫未改；不是 RED/GREEN、TC-NTF-003、DB、广播、X6 或 Gate3 证据。strong 静态复核请求 `GBClaude/claude-opus-5-5:high`，无 actual backend 回执。

**2026-10-31 更新**：下文审阅范围、叶子数预测与“最终”哈希均为此前快照的历史记录，不适用于本轮测试增量。本轮移除 TAB 反例的 nil-pool 路径、补边界测试，并完成真实依赖图的离线仅编译；没有新独立审阅或测试执行，详见 [预检交接](notice-tab-preflight-20261031/REPORT.md)。

独立复核覆盖初版测试：40 个字段/命令/分隔符组合，对 Build 和无 DB 的 Deliver 分别检查拒绝、零返回及不广播；已有人类文本、错误优先级和静默对照。旧源码的 TAB 分支预期会因 Build 未拒绝而触发固定标记；nil-pool panic、编译错误、空选中或 skip 均不能充当 RED。这是静态预测，不是已执行结果。审阅期间未运行命令或测试。

按复核意见，随后修正 CUSTOM 计划路径并补了普通 TAB 双受众、标识符优先级、1200/1201 字节边界、超长 TriedPaths 错误优先级以及换行/连续 TAB；独立复核这些增量静态有条件通过。其预计 48 个叶子中旧代码 23 fail、25 pass 仅是静态预测，尚未执行。复核后计划又澄清 nil-pool 标记口径与超长 authorizer 条目局限。最终 raw SHA-256：

| 文件 | raw SHA-256 |
|---|---|
| `multica/server/internal/governance/noticeguard_test/execution_notice_test.go` | `3f76ed137658f7c76fc8103a68a6ac99c218e66d978169154cb505ed5500a266` |
| `multica/server/internal/governance/execution_notice.go` | `9be5120bef4fb80ab2b4973c44cd0c032d7c43ca6406969297f255d0843611db` |
| `multica/CUSTOM.md` | `3b2b7984d89a321c5b9e96e104efb6e8957d560a31bbdf349fc78564895980ea` |
| `validation/notice-tab-guard-slice-plan.md` | `540876d829b2f5ad9c52d08cbfcc97a743e96df88f31e88f9bfd709cdda60ec9` |

作者使用固定本机 `gofmt.exe -d`，退出 0 且无格式差异；仅证明语法可由 gofmt 解析及格式一致，不编译或运行测试。离线 `go list` 与隔离限制见计划。

新增拒绝可能影响历史带 TAB 的输入与调用方重试；authorizer 的不渲染 TriedPaths 也会受影响。维护者超长 TriedPaths 的错误可能从 VERBATIM 改为命令错误；独立复核更正了初版关于合法 JSON 含原始 TAB 的误判。既有子串匹配可能误报（例如 `pseudo\t`），原有输入总量也未限制。本切片不声称这些风险已解决。

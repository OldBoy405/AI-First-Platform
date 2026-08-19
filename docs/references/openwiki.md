# openwiki

- 仓库：https://github.com/langchain-ai/openwiki.git
- 分支：main
- 引用 commit：`a0e28a30fba1c80bc883711eab48292c5f8c398d`（2026-08-19 刷新；`fix: harden error classification and run accounting (#604)`，2026-08-06；前值 `d70003587a0e5fa1496942037b6fdd98d76e377a`）
- 本地路径（评审/开发时按需 clone）：`C:\Users\GOBAO\Downloads\AI\openwiki`
- 用途：**仅借鉴设计理念与实现模式，不接入依赖**（用户明确决策）。核心借鉴点：docs-only write boundary（工具层写边界）、三段式确定性中间件（beforeAgent/wrapToolCall/afterAgent）、gitHead 增量更新 —— 详见[《Wiki子系统设计.md》](../product/Wiki子系统设计.md)
- 最后核对日期：**2026-08-19**（本次仅刷新 commit 指针，**未重做源码级调研**；上次全面核对 2026-07-30，详见[平台方案评审报告.md](../analysis/平台方案评审报告.md) §1.2，含一处 shell 逃逸护栏缺口的警示记录）
- 读法提醒：本仓不接入依赖，故 pin 漂移**无工程风险**，只影响“借鉴结论是否仍对应上游现状”。上述两个 pin 相差约一个月，四项借鉴点（docs-only 写边界、三段式中间件、gitHead 增量、prompt 方法论）均为架构级模式，不随补丁级 commit 变动；真要重做调研应在 Wiki 子系统立项时一并做（该子系统当前仍为条件触发候选）

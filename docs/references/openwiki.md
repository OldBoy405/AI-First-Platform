# openwiki

- 仓库：https://github.com/langchain-ai/openwiki.git
- 分支：main
- 引用 commit：`d70003587a0e5fa1496942037b6fdd98d76e377a`
- 本地路径（评审/开发时按需 clone）：`C:\Users\GOBAO\Downloads\AI\openwiki`
- 用途：**仅借鉴设计理念与实现模式，不接入依赖**（用户明确决策）。核心借鉴点：docs-only write boundary（工具层写边界）、三段式确定性中间件（beforeAgent/wrapToolCall/afterAgent）、gitHead 增量更新 —— 详见[《Wiki子系统设计.md》](../product/Wiki子系统设计.md)
- 最后核对日期：2026-07-30（详见[平台方案评审报告.md](../analysis/平台方案评审报告.md) §1.2，含一处 shell 逃逸护栏缺口的警示记录）

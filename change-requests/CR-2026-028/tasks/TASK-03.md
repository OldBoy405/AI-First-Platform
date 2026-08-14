---
id: CR-2026-028-TASK-03
type: TASK
cr-ref: CR-2026-028
plan-ref: "change-requests/CR-2026-028/plan.md"
sdd-ref: "change-requests/CR-2026-028/sdd.md"
title: 四 loader 收敛到 Tools Root（M2b）
slug: converge-loaders-to-tools-root
status: pending
estimate: 6h
depends-on: [CR-2026-028-TASK-02]
created: "2026-08-10T18:10:38+08:00"
---

# TASK-03 四 loader 收敛到 Tools Root

## 1. 任务描述

将 `loadStateMachine`/`loadPipeline`/`loadGates`/`loadShellRules` 四个 loader 统一改为显式接收 ws 并调用 `resolveToolsRoot(ws)`，配置来源全部收敛到 `{toolsRoot}/...`；删除固定 `GATES_PATH` 与默认 `RULES_PATH` 常量；保留 `CRCTL_RULES_PATH` 唯一覆盖入口。FR-4 核心。

## 2. 涉及文件 / 模块

- tools 包 `skills/shared/crctl/scripts/crctl.mjs`：四个 loader 重构、`main()` 的 eager `loadGates(ws)`、`controlledGit` 内 `loadShellRules(ws)`

## 3. 实现要点

- SDD §3.2 签名：
  - `loadStateMachine(ws) -> {sm, source}`，source 恒为 `{toolsRoot}/dir-graph.yaml`
  - `loadPipeline(ws, id) -> {doc, source}`，source 恒为 `{toolsRoot}/pipeline-templates/{id}.pipeline.json`
  - `loadGates(ws) -> gates`，恒为 `{toolsRoot}/skills/shared/crctl/gates.json`
  - `loadShellRules(ws) -> rules`，默认 `{toolsRoot}/skills/shared/controlled-shell/rules.json`；`CRCTL_RULES_PATH` 存在时优先
- 删除常量 `GATES_PATH`、默认 `RULES_PATH`（相对执行脚本的定位废弃）；`_shellRules` 保持独立三态缓存（`undefined|null|object`），不与 `toolsRootCache` 混用（SDD §4.3）。
- `main()`：help 在 workspace 解析前返回；其余命令 detectWorkspace → eager `loadGates(ws)`。
- 目标文件仍由消费者按需校验，沿用 `PIPELINE_NOT_FOUND`/`GATES_NOT_FOUND` 既有错误码（FR-3 边界）。

## 4. 验收条件

1. 四类 sentinel 行为断言（AC-6）：状态机用仅 fixture 存在的合法转换 advance 成功、Pipeline 用仅 fixture 存在的 nodeRef、gates 用仅 fixture 要求的 evidence、rules 用仅 fixture 允许的 git shape；执行脚本换 checkout 结果不变。
2. `CRCTL_RULES_PATH` 指向自定义 rules 时优先加载（AC-7）。
3. `loadGates`/`loadShellRules` 均显式接收 ws；无 module-scope workspace 全局（代码审查断言）。

## 5. 完成标志

四 sentinel 用例绿 + CRCTL_RULES_PATH 覆盖用例绿 + 既有套件无回归 + commit 完成。

## 6. 接口契约

- **消费**：TASK-02 产出 `resolveToolsRoot(ws)`。
- **产出**：
  - `loadStateMachine(ws: string): {sm: object, source: string}`
  - `loadPipeline(ws: string, id: string): {doc: object, source: string}`
  - `loadGates(ws: string): object`
  - `loadShellRules(ws: string): object`
  - 下游 TASK-04 消费上述签名；TASK-09 测试消费 sentinel 场景。

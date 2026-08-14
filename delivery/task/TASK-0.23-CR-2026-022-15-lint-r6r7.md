---
spec-id: ai-first-platform
version: "0.23"
id: CR-2026-022-TASK-15
type: TASK
cr-ref: CR-2026-022
plan-ref: "change-requests/CR-2026-022/plan.md"
sdd-ref: "change-requests/CR-2026-022/sdd.md"
title: 批 3.5 — lint-prompts R6/R7 + 豁免范围修复 + 测试向量（FR-24~26）
slug: lint-r6r7
status: pending
estimate: 8h
depends-on: [CR-2026-022-TASK-01, CR-2026-022-TASK-02]
assignee: ""
created: "2026-08-06T08:30:00+08:00"
---

## 任务描述

FR-24~26（根因级元发现）：lint-prompts 补 R6/R7 规则（校验范围扩到 backlog-set 与 --template 编号规则）；修复豁免注释整段生效 bug；补三类测试向量。**必须在批 4（TASK-16~18）之前落地**。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/lint-prompts.mjs`：R6/R7 + `isIgnored` 收窄
- `skills/shared/crctl/scripts/lint-prompts.test.mjs`（或同目录测试文件）：三类向量

## 实现要点（SDD §3.2/§4.4）

1. **R6**（命令参数形态）：触发面 = 行内含 `crctl advance` / `backlog-set` / `git commit --template`；advance 必须匹配 `--to\s+\S+` 与 `--trigger\s+\S+`；`LITERAL_BLACKLIST` 追加 `trigger=`/`expected_current_status=`/`commit_mode=` + 全角 `，`/`、`/`）`；`backlog-set --field` 取值 ∈ BACKLOG_SET_FIELDS（直读 crctl.mjs 常量）；`--template` 的 subject 必须含 `CR-\d{4}-\d{3}`（`--cr` 显式传入时豁免）
2. **R7**（inbox-emit）：函数式 `inbox-emit(` 直接判违例；CLI 形态 `--event` 取值 ∈ inbox-emit/SKILL.md 声明枚举（直读）
3. **豁免收窄**：`isIgnored(lines, i, radius=1)` 逐行判定，只豁免注释所在行 ±1 行；`splitPipelineJson` 的 node.prompt 按行拆分后逐行跑规则，不再整段布尔放行；**radius 在测试向量中固化为契约**
4. 判据直读源文件（crctl.mjs 常量 / SKILL.md 枚举），不建快照
5. 行尾纪律：规则执行前 `replaceAll('\r\n','\n')`；跨行解析失败硬失败

## 验收条件

1. 三类测试向量全绿：R6 违规（全角字符/反引号旗标/缺 --to 或 --trigger/backlog-set 字段越界/--template subject 缺编号）、R7 违规（函数式/枚举外 event）、豁免范围（豁免注释与违规行同段时违规行仍命中，复现 product-planning.pipeline.json:109 场景；±2 行外不豁免）
2. 全仓复扫：批 1/2/3 改动面（TASK-01/02/09 等已修文件）零误报零命中
3. `product-planning.pipeline.json:109` 的 R5 违规在修复后命中（不再被连带豁免）

## 完成标志

验收 1~3 通过 + lint-prompts.test.mjs 全量绿 + pre-commit enforce 模式全仓扫描零命中。

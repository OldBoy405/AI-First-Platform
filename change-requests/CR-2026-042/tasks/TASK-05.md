---
id: CR-2026-042-TASK-05
type: TASK
cr-ref: CR-2026-042
plan-ref: "change-requests/CR-2026-042/plan.md"
sdd-ref: "change-requests/CR-2026-042/sdd.md"
title: lint-prompts 扩展 R10-R13
slug: extend-lint-prompts-rules
status: pending
estimate: 6h
depends-on: []
created: 2026-08-16T15:34:15+08:00
---

# 1. 任务描述

按 SDD §2.5.1 扩展 `lint-prompts.mjs`：扫描对象加入 `agents/*.md` 与 `README.md`，新增 R10-R13 确定性规则，并补正反例与 CRLF 测试。CLI interface 不变。

# 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/lint-prompts.mjs`
- `skills/shared/crctl/scripts/test/lint-prompts.test.mjs`

# 3. 实现要点

- `walkFiles` 扩展：`skills/**/SKILL.md`、`pipeline-templates/*.pipeline.json`、`agents/*.md`、`README.md`；
- R10 废弃公开 interface：可执行形态 `cr-init`、`crctl test --cmd/--cwd/--timeout`、Pipeline input `review_llm`；
- R11 已退役 Skill active 引用：`change-impact-analysis`、`feedback-writeback`（在 Agent/Skill/Pipeline/README 中阻断）；
- R12 Agent/README 状态机副本：同一段出现 ≥3 个权威具名状态即阻断（Skill/Pipeline 不适用）；
- R13 Agent backlog 状态推断：Agent 同段 `_backlog.yml` + status/状态判断即阻断；
- 全部文本先 CRLF→LF；权威状态机解析复用 `loadAuthorityTransitions`，缺失/重复/截断保持硬失败；
- 不做自然语言语义分类；规则均为字面量/集合判断。

# 4. 验收条件

1. `walkFiles` 返回集含 `agents/*.md` 与 `README.md`；
2. R10-R13 各有正例命中与合法反例不误报的测试向量；
3. 每条规则的 LF/CRLF 输入产生一致结果；
4. `lint-prompts:ignore` 仍只豁免所在行 ±1 行；
5. 现有 R1-R9 测试全绿，无回归。

# 5. 完成标志

R10-R13 落地并有正反例/CRLF 测试；`node skills/shared/crctl/scripts/test/lint-prompts.test.mjs` 全绿。

# 6. 接口契约

- 消费：无上游 TASK 产出；复用 `loadAuthorityTransitions` 与现有规则结构。
- 产出：`lint-prompts.mjs` 支持 `--mode report|enforce`、扫描 `agents/*.md`+`README.md`、R10-R13；下游 TASK-06 消费「enforce 模式」接入 CI，TASK-07 消费做全量验证。

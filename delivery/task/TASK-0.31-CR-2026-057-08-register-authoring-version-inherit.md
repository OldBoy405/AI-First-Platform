---
spec-id: ai-first-platform
version: "0.31"
id: CR-2026-057-TASK-08
type: TASK
cr-ref: CR-2026-057
plan-ref: "change-requests/CR-2026-057/plan.md"
sdd-ref: "change-requests/CR-2026-057/sdd.md"
target-version: unassigned
title: 注册与需求/设计写作 Skill 版本继承（FR-13、FR-5/FR-6）
slug: register-authoring-version-inherit
status: pending
estimate: 5h
depends-on: []
created: 2026-08-31T22:00:00+08:00
---

## 任务描述

修订 `requirement-register`、`write-requirement-prd`、`write-tech-design` 三个 SKILL：注册阶段人工确定 target_version（FR-12/FR-13 提示词侧）、后续产物继承 cr.md 值禁止 tbd（FR-13）、write-tech-design 补批准范围必填契约（FR-5/FR-6）。代码侧硬校验在 TASK-02/04（本 TASK 只改 Skill 文本）。

输入条件：tools CR worktree；纯文档修订，可与 M3 并行。

## 涉及文件 / 模块

- `skills/requirement/requirement-register/SKILL.md`
- `skills/requirement/write-requirement-prd/SKILL.md`
- `skills/develop/write-tech-design/SKILL.md`

## 实现要点

1. **requirement-register**（SDD §8 表第 1 行）：参数表 `target_version` 由可选改**必填**；补值域说明（真实版本 `MAJOR.MINOR[.PATCH]` 或 `unassigned`）；禁止 `tbd` 及同义值（11 项）；未排期先向用户确认再写 `unassigned`（沿用 `origin`「填写前确认、不自行推测」先例）；补 `crctl version-set` 为唯一更正入口（unassigned → 真实版本，禁止反向/改真实版本）；Step 2 命令示例含 `--target-version`；Step 3 结果分类表补 `REGISTER_VERSION_INVALID` 行。
2. **write-requirement-prd**：补「继承 cr.md target-version，禁止写 tbd、禁止自行改写」措辞（PRD frontmatter 已含该字段，不新增字段）。
3. **write-tech-design**：frontmatter 增 `target-version: {cr.md 值}`（从 cr.md 读取，禁止 tbd/改写）；补 FR-6 批准范围节契约：SDD「批准范围」为契约必填章节（四字段 scope_in/scope_out/zero_diff/follow_up；空字段显式写 `无` 或 `N/A` 加理由，不得省略）；写明 approve-tech-design 通过后该节对 PLAN/TASK/code 只读，PLAN/TASK 发现冲突只能经 review-dev-plan 双轨回 write-tech-design/write-dev-plan，不得静默扩范围。
4. 文本约束（R8）：requirement-register 新文本不得匹配既有断言禁串（`recoverable write-set`、`三账本（`）；write-requirement-prd 不得匹配 `crctl validate` 或 `Commit：`，且须保留既有 frontmatter 必填字段/七章节/未替换占位符等值校验措辞；write-tech-design 新文本不含 contract-scan 四串。

## 验收条件

1. requirement-register 参数表必填 + 值域 + 禁止 tbd 同义值 + unassigned 确认先例 + version-set 入口 + `REGISTER_VERSION_INVALID` 行齐备。
2. write-requirement-prd 含继承禁止措辞；write-tech-design 含 frontmatter 字段与批准范围必填契约、审批后只读语义。
3. 既有静态断言（crctl.test.mjs「已知 Skill 越界文本零命中」等）不新增失败；contract-scan 零命中（AC-4）。
4. AC-5 的 write-tech-design 契约侧与 AC-13 的继承侧文本核对通过。

## 完成标志

三 SKILL 文本核对通过；contract-scan/lint-prompts 零命中；提交 `[cr] implement CR-2026-057 TASK-08`。

## 接口契约

- 消费：cr.md frontmatter `target-version`（唯一继承源）；`crctl register --target-version`、`crctl version-set --to`（TASK-02/04 实现，本 TASK 仅引用契约）。
- 产出：三 SKILL 文本契约；frontmatter 新字段仅 `write-tech-design` 的 `target-version`（值 = cr.md 值，恒 `unassigned` 或真实版本，永不 `tbd`）。
- 不产出新 CLI、新 schema 字段、新状态。

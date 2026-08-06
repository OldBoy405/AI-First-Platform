---
spec-id: ai-first-platform
version: "0.24"
id: CR-2026-023-TASK-02
type: TASK
cr-ref: CR-2026-023
plan-ref: "change-requests/CR-2026-023/plan.md"
sdd-ref: "change-requests/CR-2026-023/sdd.md"
title: 块 B — R9 测试向量（FR-12）
slug: r9-test-vectors
status: pending
estimate: 3h
depends-on: [CR-2026-023-TASK-01]
assignee: ""
created: "2026-08-07T00:40:00+08:00"
---

## 任务描述

为 R9 规则追加四类测试向量到 `lint-prompts.test.mjs`，沿用既有 R7/R8 的 `makeFixture`/`runLint` 黑盒基建（`node:test` + `spawnSync`，fixture 落临时目录）。fixture 路径必须落在 CR 上下文域才会触发 R9（现有 `skills/x/SKILL.md` 会被跳过，不能复用）。违例文本用**真实 skill id**（如 `review-requirement`），因判据源固定读 tools 仓 `skills/_index.yml`（SDD §5.2），fixture 无需自带索引。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/test/lint-prompts.test.mjs`

## 实现要点（SDD §4.1 + PRD FR-12）

1. **正向**：fixture `skills/requirement/x/SKILL.md` 含「下一步 : 执行 review-requirement 或 push-progress」→ 断言 stdout 含 `R9` 与 `CONTRADICTS`；同文件含「下一步 : 以 `crctl next {cr_id}` 为准」的合规行不误报。
2. **反向（域外）**：fixture `skills/planning/x/SKILL.md` 含「下一步 : 执行 write-planning-entry」→ 断言 stdout 不含 `R9`。
3. **pipeline 名捕获**：fixture `skills/develop/x/SKILL.md` 含「下一步：执行 writeback pipeline」→ 断言命中 R9（approve-code 指向 pipeline 而非 skill 的场景）。
4. **记述性豁免（正向不误报）**：fixture `skills/develop/x/SKILL.md` 含 CR 上下文域内记述性「下一步」行——非映射形态，如「下一步建议」标题行、或描述性提及某 skill 但非「下一步→skill」指令（对标存量 write-test-report:58 仅「下一步建议」标题不命中的既有判定）→ 断言 stdout 不含 R9。此用例锁定子串匹配边界，防止短 skill-id 将来撞上记述文本导致回归失守（承接技术评审 S4/T1）。
5. 每个用例 `finally` 里 `rmSync(dir, { recursive: true, force: true })` 清理临时目录（对齐既有模式）。

## 验收条件

1. `node --test skills/shared/crctl/scripts/test/lint-prompts.test.mjs` 新增四条 R9 用例全绿（含记述性豁免正向用例）。
2. 记述性豁免用例：CR 上下文域内非映射「下一步」行（标题/描述性）不命中 R9。
3. 既有 R1~R8 用例不被破坏（全量回归绿）。

## 完成标志

四类 R9 向量通过 + 全量测试绿；与 TASK-01/03 同 commit 1 提交（NFR-1）。

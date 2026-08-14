---
id: CR-2026-021-TASK-11
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: lint-prompts.mjs — R1~R6 漂移检测 + ignore 豁免 + report/enforce 双模式
slug: lint-prompts-linter
status: pending
estimate: 6h
depends-on: []
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

FR-23（SDD §4.3）：新增 `skills/shared/crctl/scripts/lint-prompts.mjs`，扫 `skills/**/SKILL.md` + `pipeline-templates/*.json`，按 R1~R6 判据（直读 `rules.json`/`crctl.mjs` 源码,零派生物）检测 prompt↔crctl 漂移。支持 `--mode report|enforce`、`--json`，段落级 `<!-- lint-prompts:ignore -->` 豁免。

**落地 tech-design 评审 suggestion-3（不阻断,但必须在本任务完成前定义清楚）**：pipeline JSON 的 prompt 是长字符串、无 Markdown 标题结构,「段落」切分粒度在 SDD 中未定,必须在本任务里明确规则并写测试验证边界情况。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/lint-prompts.mjs`（新增）
- `skills/shared/crctl/scripts/test/lint-prompts.test.mjs`（新增，含 R1~R6 各至少 1 个已知漂移 fixture + 1 个 ignore 豁免 fixture + 1 个"正确示范"不误报 fixture）

## 实现要点

1. R1（手写 guard-deny 文件）判据直读 `rules.json#protectedPaths.deny`；R2（裸 git）直读 `rules.json#git`；R3/R4/R5/R6 为字面黑名单（`cr-status-set`/六字段口径/`review-loop` 手写/`test-report.md` 手写）。
2. **段落切分规则（本任务需明确定义,suggestion-3 落地点）**：
   - SKILL.md：按 Markdown 标题（`##`/`###`）切分为段。
   - pipeline JSON：**按 node 边界切分**（每个 `nodes[].prompt` 字符串视为一段），段内再按空行（`\n\n`）细分为子段，用于邻近判定「是否同段/子段内有 crctl 调用」。
   - 用 fixture 验证：同一 node 的 prompt 内既有正确调用（`crctl approve ...`）又有一句手写描述性说明文字时不应误报（R1 邻近判定）。
3. `<!-- lint-prompts:ignore -->` 出现在段落/子段附近即跳过该范围检测。
4. `--mode report`：命中输出但 exit 0；`--mode enforce`：CONTRADICTS/STALE-REF 命中即 exit 1。

## 验收条件

- AC-13（PRD）：对 6 类规则各构造已知漂移 fixture，全部命中且输出 `file:line`；含 `<!-- lint-prompts:ignore -->` 的段落不误报；对「正确示范」文本（教"改用 crctl approve"的说明）不误报。
- pipeline JSON 段落切分规则已文档化（本任务的实现注释或 SKILL 级说明），且有 fixture 覆盖同 node 内正确调用+说明文字混杂的场景。

## 完成标志

`node --test skills/shared/crctl/scripts/test/lint-prompts.test.mjs` 全绿。

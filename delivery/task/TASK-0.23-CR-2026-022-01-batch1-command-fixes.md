---
spec-id: ai-first-platform
version: "0.23"
id: CR-2026-022-TASK-01
type: TASK
cr-ref: CR-2026-022
plan-ref: "change-requests/CR-2026-022/plan.md"
sdd-ref: "change-requests/CR-2026-022/sdd.md"
title: 批 1 — crctl advance 命令串 12 处修正 + 豁免注释外移 + 死引用/措辞订正（FR-1~3）
slug: batch1-command-fixes
status: pending
estimate: 6h
depends-on: []
assignee: ""
created: "2026-08-06T08:30:00+08:00"
---

## 任务描述

批 1 零风险机械修正，纯文本不动逻辑。目标：AI 照抄命令串不再失败、frontmatter 纯净、死引用清零、编号/措辞自洽。

## 涉及文件 / 模块（12 处命令串）

- `skills/cr/cr-archive/SKILL.md:58` → `crctl advance --to archived --trigger cr-archive --expect writing-back --embedded`
- `skills/cr/cr-review-record/SKILL.md:46,47` → `crctl advance --to rejected --trigger cr-review-record:reject` / `--to withdrawn --trigger cr-review-record:withdraw`
- `skills/develop/review-code/SKILL.md:97,98` → `--to code-reviewing --trigger review-code --expect developing`；`--to developing --trigger "review-code:block -> implement-code" --expect developing`（trigger 含空格与 `->` 必须加引号）
- `skills/develop/review-tech-design/SKILL.md:72` → `--to tech-designing --trigger "review-tech-design:block -> write-tech-design" --expect tech-design-review-pending`
- `skills/develop/write-dev-tasks/SKILL.md:79` → `--to task-breakdown --trigger write-dev-tasks --expect tech-design-reviewed`
- `skills/develop/write-tech-design/SKILL.md:47,92` → `--to tech-designing --trigger write-tech-design --expect requirement-approved`；`--to tech-design-review-pending --trigger write-tech-design-complete --expect tech-designing`
- `skills/requirement/review-requirement/SKILL.md:91` → `crctl advance --to requirement-reviewing --trigger review-requirement`（**省略 --expect**：drafting 与 requirement-reviewing 两条合法 current，写死会误拒自环）
- `skills/writeback/merge-feature-branch/SKILL.md:160` → `--to merging --trigger merge-feature-branch --expect code-approved --embedded`
- `skills/writeback/writeback-prd-sdd/SKILL.md:66` → `--to writing-back --trigger writeback-prd-sdd --expect merging`

已正确形态（不改）：`cr-archive:15`、`merge-feature-branch:21`、`cr-status-set:9`（该文件批 2 整体下线）。

## 实现要点

1. 逐处按报告 2.1-A 目标形态替换；先 grep 核对行号再改（报告行号可能漂移）
2. 全角 `，`/`、`/`）` 分隔符一律改半角旗标；`trigger=`/`expected_current_status=`/`commit_mode=` 反引号包裹一律改真旗标
3. 豁免注释外移：`review-code`/`requirement-register:17`/`implement-code:77` 的 `<!-- lint-prompts:ignore -->` 移出 YAML frontmatter（放正文描述行前或删孤立行）
4. 死引用：`pipeline-templates/_index.yml:118` 删 `tools/old/` 行；`agents/knowledge-agent.md:39` 改 `tools/skills/shared/validate-doc/SKILL.md`
5. 措辞：requirement-register「完成以下三件事」→「四件事」且 Step 编号连续；merge-feature-branch「两阶段合并」→「四阶段」；spec-dashboard 状态分布表补齐 requirement-reviewing/tech-designing/tech-design-review-pending/task-breakdown/code-approved/merging

## 验收条件

1. `grep -n "crctl advance"` 全仓不再有 `，`/`、`/`）` 或反引号旗标形态（R6 落地后复扫零命中）
2. 三份 SKILL.md frontmatter 内无 `<!-- lint-prompts:ignore -->`
3. `grep "tools/old" pipeline-templates/_index.yml` 零命中；knowledge-agent 引用路径存在
4. review-requirement 无 `--expect` 字样（91 行附近）

## 完成标志

批 1 全部目标形态落地 + 验收 1~4 通过 + `lint-prompts.mjs`（现有 R1~R5）复扫零新违例。

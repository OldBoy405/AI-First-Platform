---
id: CR-2026-018-TASK-08
type: TASK
cr-ref: CR-2026-018
plan-ref: "change-requests/CR-2026-018/plan.md"
sdd-ref: "change-requests/CR-2026-018/sdd.md"
title: 16 个 skill 文档修订 — status 消费点改指向 cr.md（FR-6+FR-9）
slug: skill-docs-cr-md-migration
status: pending
estimate: 16h
depends-on: ["CR-2026-018-TASK-02", "CR-2026-018-TASK-04"]
assignee: ""
created: "2026-08-04T17:05:00+08:00"
---

## 1. 任务描述

将 SDD §6 FR-6 盘点出的 16 个消费 `_backlog.yml` 条目 `status` 字段的 skill 文档，逐一修订为指向 `cr.md` frontmatter status。这是评审 suggestion #3 特别点名的高风险项——批量文档修订最易漏改，本任务按下方**逐文件 checklist** 执行，完成标志要求每一项独立勾选，不接受"整体过一遍"式的笼统完成声明。

另外 15 个引用 `_backlog.yml` 路径但不消费 status 字段的 skill 文档（如仅引用 `prd-path`/`merge-commits`/`owners` 等注册字段）**不在本任务修订范围**，保持原样。

## 2. 涉及文件 / 模块（逐文件 checklist，16 项）

- [ ] `tools/skills/cr/cr-archive/SKILL.md` — Step 3 条目移动逻辑改为读 cr.md 的 final-status（而非 backlog 条目 status）
- [ ] `tools/skills/cr/cr-dashboard/SKILL.md` — "按 backlog[].status 分组计数"改为扫描 `change-requests/*/cr.md` frontmatter status 分组
- [ ] `tools/skills/cr/cr-inbox/SKILL.md` — status 消费点改读 cr.md
- [ ] `tools/skills/cr/cr-review-record/SKILL.md` — reject/withdraw 时的当前 status 判断改读 cr.md
- [ ] `tools/skills/cr/cr-status-set/SKILL.md` — 契约描述文字更新（该 skill 是 crctl advance 的语义文档，需反映"只写 cr.md"）
- [ ] `tools/skills/develop/approve-code/SKILL.md` — 审批前置 status 校验描述改读 cr.md
- [ ] `tools/skills/develop/approve-dev-start/SKILL.md` — 同上
- [ ] `tools/skills/develop/approve-tech-design/SKILL.md` — 同上
- [ ] `tools/skills/requirement/approve-requirement/SKILL.md` — 同上
- [ ] `tools/skills/planning/analyze-current-product/SKILL.md` — status 消费点改读 cr.md
- [ ] `tools/skills/planning/focus-briefing/SKILL.md` — status 消费点改读 cr.md
- [ ] `tools/skills/requirement/requirement-register/SKILL.md` — **注册新 CR 时不再向 backlog 条目写 status/updated-at 字段**，status 只落 cr.md frontmatter（这是 v2 schema 从源头生效的关键点，遗漏会导致新注册 CR 仍产生双写）
- [ ] `tools/skills/review/review-alignment/SKILL.md` — status 消费点改读 cr.md
- [ ] `tools/skills/shared/crctl/SKILL.md` — 顶层文档同步：advance 行为描述改为"只写 cr.md"，补充 migrate-backlog 子命令说明
- [ ] `tools/skills/spec/spec-dashboard/SKILL.md` — status 消费点改读 cr.md
- [ ] `tools/skills/writeback/merge-feature-branch/SKILL.md` — Step 5 embedded status patch 说明改为"只落 cr.md"；`merge-commits[]` 字段仍写 `_backlog.yml`（注册索引字段，不受影响），需在文档中明确区分这两类写入目标

## 3. 实现要点

- 修订原则：只改"如何读/写 status"的描述性文字，不改 skill 的业务流程步骤顺序或门禁逻辑。
- `requirement-register` 与 `merge-feature-branch` 两项涉及**写**路径描述（不只是读），需要格外仔细核对，是本清单里风险最高的两项。
- 修订完成后建议跑一次 `grep -rn "backlog\[\].status\|_backlog.*status"` 全量扫描 `tools/skills/`，确认命中结果仅剩"迁移说明/历史注记"类段落（对应 SDD FR-6 的验收标准 AC-6）。

## 4. 验收条件

- 上述 16 项 checklist 全部勾选完成。
- AC-6：修订后 `grep -rn "backlog\[\].status\|_backlog.*status"` 在 `tools/skills/` 下仅命中迁移说明/历史注记类段落，无遗漏的"权威读取"描述。
- `requirement-register` 与 `merge-feature-branch` 两项额外交叉核对：新注册 CR 产出的 backlog 条目不含 status 字段；merge-feature-branch 的 embedded patch 描述与 SDD §4.2 的 `result.files` 变化一致。

## 5. 完成标志

16 项 checklist 逐条勾选完成（非整体笼统声明）；AC-6 grep 断言通过；两个高风险项（requirement-register / merge-feature-branch）已交叉核对。

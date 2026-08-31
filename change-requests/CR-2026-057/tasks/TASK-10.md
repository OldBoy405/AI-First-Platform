---
id: CR-2026-057-TASK-10
type: TASK
cr-ref: CR-2026-057
plan-ref: "change-requests/CR-2026-057/plan.md"
sdd-ref: "change-requests/CR-2026-057/sdd.md"
target-version: unassigned
title: SDD-template 批准范围章节与 README 版本规则同步（FR-5、NFR-6）
slug: sdd-template-readme-sync
status: pending
estimate: 4h
depends-on: []
created: 2026-08-31T22:00:00+08:00
---

## 任务描述

`SDD-template.md` 增设「批准范围」固定章节（FR-5）；`README.md` 人读流程同步「目标版本在注册阶段确定 + version-set 唯一更正 + writeback 版本守卫」（NFR-6）。纯文档，不改 crctl 行为。

输入条件：tools CR worktree；纯文档修订，可与 M3 并行。

## 涉及文件 / 模块

- `skills/shared/engineering-docs/templates/SDD-template.md`
- `README.md`

## 实现要点

1. **SDD-template**（FR-5）：新增固定章节「批准范围」，承载且**仅承载**四字段：`scope_in`（当前 CR 必须交付的 FR/AC）、`scope_out`（明确排除的路径和能力）、`zero_diff`（明确不得改动的调用点/签名）、`follow_up`（发现但留给后续 CR 的缺口）；空字段必须显式写 `无` 或 `N/A` 加理由，不得省略章节。不新增独立 ledger 文件、不新增状态、不进 crctl schema。其余既有节不动。
2. **README**（NFR-6，插入位置 SDD §10 #18 所述 §4/§5/§7 附近）：注册阶段人工确定 `target_version`（真实版本或 `unassigned`；禁止 `tbd` 及同义值；未排期先确认再 `unassigned`）；PRD/SDD/PLAN/TASK 继承 cr.md 值；`crctl version-set --to <real-version>` 为唯一更正入口（unassigned → 真实版本，原子同步全链，不改变状态）；`crctl writeback-apply` 入口版本守卫（与 cr.md 规范化全等才放行，版本错误零 candidate/journal 痕迹）。不得在 knowledge-base `dir-graph.yaml` 复刻状态机。
3. 文本约束（R8）：README 既有 8 节 + 权威链接（`dir-graph.yaml`/`agent-skill-matrix.yml`/`crctl.mjs`/`ARCHITECTURE.md`）与既有禁串（`review_llm` 等）的静态断言不得破坏——只做定点插入不重写结构。

## 验收条件

1. SDD-template 含「批准范围」四字段章节与空字段规则；无新增 ledger/schema 表述。
2. README 三处人读同步（注册确定 / version-set 入口 / writeback 守卫）与 FR-12/FR-13/FR-15 一致。
3. 既有 README 静态断言（8 节、权威链接、禁串）不新增失败（cmd-01 除基线红外绿）。
4. AC-5 模板侧：按新模板起草的 SDD 含四字段（本 CR sdd.md §9 即实证）。

## 完成标志

两文件定点增改完成、静态断言不破；提交 `[cr] implement CR-2026-057 TASK-10`。

## 接口契约

- 消费：FR-12/FR-13/FR-15 契约文本（TASK-02/04 代码侧、TASK-08/09 Skill 侧）。
- 产出：SDD-template 新固定章节；README 版本规则人读小节。不产出 CLI/schema/状态变化。

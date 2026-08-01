---
id: CR-2026-005-TASK-01
type: TASK
cr-ref: CR-2026-005
plan-ref: "change-requests/CR-2026-005/plan.md"
sdd-ref: "change-requests/CR-2026-005/sdd.md"
title: deliveryIndexComplete 门禁 + writeback-tasks skill + write-dev-tasks slug 提示
status: pending
estimate: 5h
depends-on: []
assignee: ""
created: "2026-08-01T15:25:00+08:00"
---

## 任务描述
在 `tools` 仓（`custom/main` trunk，直接提交）实现 SDD §3 的全部改动：新 gate check type、gates.json 挂点、新 skill、以及 write-dev-tasks 的 slug 措辞小改（技术评审建议 1）。

## 涉及文件
- `tools/skills/shared/crctl/scripts/crctl.mjs`（`runGateChecks` 新增 `deliveryIndexComplete` 分支 + `checkDeliveryIndexComplete` 函数）
- `tools/skills/shared/crctl/gates.json`（`statusGates.archived[]` 追加一项）
- `tools/skills/writeback/writeback-tasks/SKILL.md`（新建；**明确写入"调用时机：writing-back 阶段，write-test-report 之后，cr-archive 之前"**——技术评审建议 3）
- `tools/skills/develop/write-dev-tasks/SKILL.md`（Step 3 生成 TASK 文件的 frontmatter 模板，`slug` 列为建议填写字段并说明兜底规则——技术评审建议 1）

## 实现要点
- `checkDeliveryIndexComplete`：读 `tasks/_index.yml` 的 done 任务 id 集合，读 `delivery/task/_index.yaml` 的已登记 id 集合（文件不存在按空集处理），集合差非空即 `ok:false`。
- doneIds 为空时直接 `ok:true`（FR-3 边界①）。
- `writeback-tasks` 幂等：判据是"该 id 是否已在全局索引"，已存在则跳过（不重写文件、不重复追加索引行）。
- slug：frontmatter 有 `slug` 字段则用；无则回退 `task-{NN}`。
- 技术评审建议 2（孤儿索引行反向检查）**本任务不实现**——按计划留作独立评估项，不在本 CR 范围。

## 验收条件
1. `node crctl.mjs advance <既有已归档 CR> --to archived ...`（用只读复算，不真的改状态）对 CR-2026-001~004 的现有索引重放，`deliveryIndexComplete` 均返回 `ok:true`（历史数据本身已在 CR-2026-004 归档时手工补全，验证新检查不误报）。
2. 构造一个模拟"done 任务未登记"的临时场景（复现 CR-2026-003 当时状态），门禁返回 `ok:false` 且 `why` 列出缺失 id。
3. 对含 2 个 done 任务的临时 CR fixture 调用 `writeback-tasks`，验证文件生成 + 索引追加 + 门禁转为 `ok:true`。
4. 重复调用步骤 3 的 `writeback-tasks`，索引与文件不产生重复。
5. `write-dev-tasks` SKILL.md 的 frontmatter 模板与 `writeback-tasks` SKILL.md 的"调用时机"章节人工审读确认措辞到位。

## 完成标志
上述 5 项验证通过 + tools 仓 commit（仅暂存本任务改动的具体文件，不动仓内其他未提交的无关文件）+ 完成记录回填本文件。

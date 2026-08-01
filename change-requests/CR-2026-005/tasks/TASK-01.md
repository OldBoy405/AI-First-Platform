---
id: CR-2026-005-TASK-01
type: TASK
cr-ref: CR-2026-005
plan-ref: "change-requests/CR-2026-005/plan.md"
sdd-ref: "change-requests/CR-2026-005/sdd.md"
title: deliveryIndexComplete 门禁 + writeback-tasks skill + write-dev-tasks slug 提示
status: done
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

## 完成记录（2026-08-01）

- **实现 commit**：tools 仓 `custom/main` @ `9d65fb6`（已推 origin，4 文件 +76/-46）。
- **重要发现**：`writeback-tasks/SKILL.md` 早已存在（工具包初始脚手架时生成，`git log` 只有一次提交），但其描述的 id/字段/文件名格式与 CR-2026-001~004 实际采用的格式完全不兼容，从未被真正调用过——本任务按实际数据重写，而非新建。
- **验收条件核验**：
  1. ✅ AC-1 用 CR-2026-001~004 真实历史数据重放 `deliveryIndexComplete`，全部 `ok:true`。**过程中发现并修复一个真实 bug**：`delivery/task/_index.yaml` 顶层是 `{tasks:[...]}` 而非裸列表，初版实现假设错误导致 `TypeError: .map is not a function`；用手造 fixture 测试时因 fixture 恰好符合错误假设而未测出，改用真实数据重放后才暴露——这正是 SDD 里强调"用真实历史数据做 AC-1"的价值所在。
  2. ✅ AC-2：fixture 复现 CR-2026-003 当年漏登场景（done 任务未登记），门禁正确拒绝并列出缺失 id。
  3. ✅ AC-3：手工按 `writeback-tasks` SKILL.md 新版步骤走查——TASK-01 fixture 显式 `slug` 字段与 TASK-02 fixture 无 slug 回退 `task-{NN}` 两条分支均正确；索引追加后门禁转 `ok:true`（自证闭环）。
  4. ✅ AC-4：重复执行同一回写逻辑，0 新增文件、0 重复索引行。
  5. ✅ AC-5：无 done 任务的 CR、全局索引文件不存在两个边界均正确处理，不误报不崩溃。
- **技术评审 3 条建议全部落地**：slug 建议字段已写入 `write-dev-tasks` 模板；孤儿索引行反向检查明确未实现（按计划留作独立评估项）；`writeback-tasks` 调用时机已在 SKILL.md 头部显式写明。
- 提交前确认 tools 仓内其他 9 个无关的未提交文件（`AGENT-SKILL-MATRIX.md` 等）未被触碰——仅精确暂存本任务改动的 4 个文件。

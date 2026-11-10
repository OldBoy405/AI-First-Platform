# EVD-008 后续占位登记复核（REVIEW-ECONOMY）

- 审核对象：`projects/multica/changes/2026-10-29-legacy-execution-migration/`（占位登记，负责人 Ray）
- 关联调整：`projects/multica/changes/2026-10-22-aifi-45-authorized-execution/pending-adjustments.yaml` M003/M004/M005
- 本报告位置：`projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/evd008-followup-registration-20261029/REVIEW-ECONOMY.md`
- 性质：只读复核 + 修复后复核；不创建或修改除本报告外任何文件，不推进 Gate。
- Receipt 声明：此前一轮审核所用模型身份未知；本轮审核的真实 backend receipt 亦无法在会话内核验，均如实标注为未知，不做断言。

## 一、审核时发现（首轮只读审核，未运行 CLI）

以下为首轮审核（只读，未执行 `stdd status/state`）的发现：

1. 原生 STDD 四阶段全部 pending，未进入 SPEC/BUILD。
   - `projects/multica/changes/2026-10-29-legacy-execution-migration/.stdd.yaml:3` `current_phase: understand`；:9/:11/:13/:15 四个 phase 均 `status: pending`；:17 `status: active`；:18 `task_type: data-migration`；:20 `spec_scenarios: 0`。
2. 三个启动触发条件真实列示于 canonical proposal。
   - `.../canonical/proposals/2026-10-29-legacy-execution-migration.yaml:13`：负责人 Ray；任一条件启动——D8 改为迁移 legacy 业务历史 / 对包含在途旧授权或旧消耗历史的 workspace 准备生产启用 / 拟为 evaluateExplicitMigration 接生产入口。:1 首行自述“占位 proposal；不代表需求、方案、迁移或 Gate 已确认”。
3. 权威事实源表述真实：父 change `pending-adjustments.yaml` 头部注释与 M004/M005 `impact_scope` 一致指明以 `validation/tc-coverage-20261025T153000Z.md` 为准（当前台账 44/49），历史叙述计数（42/49）不作数。
4. Gate3/MISSING 表述真实且与旧 adjustment 互证：proposal:30“D8=A 继续有效；TC-EVD-008 保持 MISSING，Gate3 偏差须经实际审批，不得由占位自动通过”，与 M004“Gate3 材料须写明 EVD-008 为已知缺口……最终偏差须经实际 Gate3 审批”一致；M003“禁止换 grant/lineage/store 清旧债”与 proposal constraint 第 3 条对应。未发现与 M003/M004/M005 的冲突。
5. **Scaffold 缺陷（本轮修复的对象）**：`.../canonical/.canon-index.yaml` 曾将不存在的 code spec 写入索引（`specs.code` 条目指向 `specs/code/2026-10-29-legacy-execution-migration.yaml`，该文件不存在）。
6. **CLI 模板遗留（不可当作 SPEC 已完成）**：
   - `.../canonical/specs/agent/2026-10-29-legacy-execution-migration.yaml` 为未填模板：:4 `task_id: "TODO: 任务标识"`、:8 `system: "TODO: 目标系统描述"`、:11/:14/:15/:18 全为 TODO 占位。
   - change 根 `design.md`、`test-plan.md` 为未填 CLI 模板（`<变更标题>`、`<版本> 测试方案…`）；`canonical/designs/` 为空目录；change 根 `specs/` 为空目录。
   - 上述文件的存在不代表任何需求/方案/迁移/Gate 已确认；与 `.stdd.yaml:20` `spec_scenarios: 0` 互证。

## 二、修后复核（本轮只读，未运行 CLI）

用户已手工将占位 `.../canonical/.canon-index.yaml` 的 `specs.code` 条目改为 `code: {}`，未改动 state。本轮逐项复核结果：

1. **索引修复确认**：`.../canonical/.canon-index.yaml:7` 现为 `  code: {}`。原悬挂引用（指向不存在的 `specs/code/2026-10-29-legacy-execution-migration.yaml`）已消除；索引当前内部自洽——`designs: {}`（第 1 行，目录实为空）、`proposals` 条目（第 3 行）指向存在的 proposal 文件、`specs.agent` 条目（第 5–6 行）指向存在的 TODO 模板文件、`specs.code`（第 7 行）为空映射且 `canonical/specs/` 下实际只有 `agent/` 子目录（已列目录核实）。
2. **state 保持不变（未推进 Gate）**：`.../2026-10-29-legacy-execution-migration/.stdd.yaml:3` 仍 `current_phase: understand`；:9/:11/:13/:15 四阶段仍全部 `status: pending`；:17 `status: active`；:18 `task_type: data-migration`；:20 `spec_scenarios: 0`。与首轮记录逐字一致，无任何阶段状态变化。
3. **owner 保持不变**：proposal:13“负责人 Ray”；:33 `stakeholders: - "Ray（负责人）"`。
4. **触发条件保持不变**：proposal:13 三个触发（D8 改为迁移 legacy / 有在途旧授权或旧消耗历史的 workspace 生产启用前 / 为 evaluateExplicitMigration 接生产入口前）与首轮逐字一致。
5. **`specs/agent` 仍只是 TODO 模板**：`.../canonical/specs/agent/2026-10-29-legacy-execution-migration.yaml` :4/:8/:11/:14/:15/:18 仍全部为 `TODO:` 占位，无任何实质内容；与 `.stdd.yaml:20` `spec_scenarios: 0` 一致。该文件及索引中的 agent 条目不得被读作 SPEC 已完成。
6. **修复范围最小**：两轮之间唯一变更是 `.canon-index.yaml` 第 7 行 `code` 条目由悬挂文件引用改为 `{}`；`.stdd.yaml`、proposal、agent spec 模板均未变（本轮已重新逐字读取比对）。

## 三、CLI 执行情况（如实声明）

- 首轮与本轮复核**均未运行** `stdd status/state` 或任何 stdd 命令；本文不对 CLI 输出做任何陈述。
- 两轮均未创建、修改或删除除本报告外的任何文件；未推进任何 Gate。
- 若后续需 CLI 佐证，应在 sibling `C:/Users/GOBAO/Downloads/AI/multica` 目录下以只读方式执行，且不得改变本占位 change 的状态。

## 四、结论

修复正确且最小：`.canon-index.yaml` 的悬挂 code spec 引用已消除（`code: {}`），索引与磁盘实况一致；占位登记的 state（understand、四阶段 pending）、负责人（Ray）、三个触发条件均保持不变；`specs/agent` 与根目录 design/test-plan 仍为 CLI 模板遗留，不构成 SPEC 完成证据。EVD-008 相关的 D8=A、TC-EVD-008 MISSING、Gate3 偏差须实际审批的口径未受本次索引修复影响。

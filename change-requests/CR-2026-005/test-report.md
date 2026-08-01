---
id: CR-2026-005-test-report
type: TEST-REPORT
cr-ref: CR-2026-005
title: delivery/task 回写一致性门禁 + writeback-tasks skill — 端到端验收报告
status: pass
created: "2026-08-01T16:00:00+08:00"
---

# CR-2026-005 端到端验收报告

## 环境

- 改动仓：`tools`（`custom/main` @ `9d65fb6`，已推 origin）。本 CR 不涉及 multica 代码，不需要环境刷新/镜像重建——crctl 是本地 CLI 工具，改动即时生效。
- 验收方式：① 对 knowledge-base 仓的 4 个真实已归档 CR（CR-2026-001~004）只读重放门禁（`crctl gate ... --for archived`，不写任何文件）；② 在系统临时目录构造独立 fixture workspace 验证负向场景与 skill 步骤，不触碰任何真实仓库数据。

## 验收结果

### AC-1 正向（真实历史数据重放）✅
`node crctl.mjs gate {cr} --for archived --spec-id ai-first-platform --workspace <knowledge-base>` 对 CR-2026-001/002/003/004 四个真实已归档 CR 重放，`deliveryIndexComplete` 检查均 `ok:true`，整体门禁 `pass:true`，不误报。

**过程中发现并修复一个真实 bug**：初版实现假设 `delivery/task/_index.yaml` 顶层是裸列表，实际是 `{tasks:[...]}`（与 `tasks/_index.yml` 同构），导致 `TypeError: .map is not a function`。此 bug 在自造 fixture 测试阶段未被发现——因为 fixture 恰好按错误假设手写，直到改用真实历史数据重放才暴露并修复。已修正为 `parseYaml(...)?.tasks || []`，改后四个真实 CR 全部通过。

### AC-2 负向（复现 CR-2026-003 原故障场景）✅
构造临时 fixture（`change-requests/CR-9999-999`）：`tasks/_index.yml` 有 2 个 `status=done` 任务，全局 `delivery/task/_index.yaml` 只登记了 1 个（复现当年漏登 1 项的状态）。执行门禁 → `ok:false`，`missing:["CR-9999-999-TASK-02"]`，`why` 给出可读错误信息。

### AC-3 skill 正向（自证闭环）✅
按重写后的 `writeback-tasks` SKILL.md 步骤，对 fixture 手工走查：
- 任务 TASK-01 frontmatter 显式 `slug: explicit-fixture-slug` → 输出文件名沿用该 slug。
- 任务 TASK-02 无 slug 字段 → 正确回退 `task-02`。
- 两个任务的 frontmatter 均正确追加 `spec-id`/`version`；全局索引正确追加对应行（字段名与历史数据一致：`cr-ref`/`target-version`连字符风格）。
- 回写后重跑门禁，`ok:true`——同一套逻辑完成"制造问题→通过 skill 解决→门禁验证解决"的闭环。

### AC-4 幂等 ✅
对同一 fixture 重复执行回写逻辑：第二次运行 0 新增文件、0 新增索引行（判据是"id 是否已在全局索引"，非文件内容比较，符合 SDD §3.3④ 设计）。

### AC-5 边界 ✅
- 无 `status=done` 任务的 CR：直接 `ok:true`，不读取全局索引文件。
- 全局索引文件不存在但 CR 有 done 任务：正确报告 `missing` 且不抛异常（区别于"无 done 任务"分支，这种情况下有真实缺口，报告缺失是正确行为而非误报）。

## 结论

5 条 AC 全部通过，且在真实数据重放阶段发现并修复了一处实现 bug——AC-1 使用真实历史数据而非纯 fixture 的设计选择被证明是有价值的。技术评审 3 条建议全部落地（slug 提示字段、调用时机文档化、孤儿行范围排除说明）。tools 仓改动已提交并推送，无需部署动作。

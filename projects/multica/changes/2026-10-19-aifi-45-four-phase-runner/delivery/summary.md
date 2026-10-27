# DELIVER — AIFI-45 四阶段统一 Runner（multica 平台侧）

> 本文件为收尾补记（2026-10-27）：该 change 的 BUILD 于 2026-10-20 完成，但 `deliver` 阶段一直停在 `pending`、没有交付记录，因此当时无法归档。

## 1. 范围

`specs/` 下 10 个 capability：

`approval-ack`、`delivery-runner`、`dev-phase-runner`、`four-phase-runner-dispatch`、`kb-resource-adoption`、`node-execution-binding`、`periodic-runner-resume`、`persistent-stage-handoff`、`public-key-grant-delivery`、`task-recovery`

解决的问题（proposal 原文）：四阶段只有需求与技术设计接进 Runner，其余阶段靠协调者转述/作者启动/CLI 续接，导致 KB 未采集、ack 报 leader-missing 拖住同批记录、设计期 `RUNNER_SKILL_MISSING`、一次唤醒失败后长期停住等非业务阻断。

## 2. 证据入口

该 change 早于本工作区的 `validation/` 约定，证据以各切片报告落在 change 根目录：

| 报告 | 覆盖 |
|---|---|
| `M00-db-baseline.md` | 基线 |
| `M10-`、`M11-`、`M12-`、`M13-M15-`、`M20-M22-`、`M23-M25-`、`M26-M28-`、`M30-M34-`、`M35-M39-`、`M40-M43-build-report.md` | 各里程碑 BUILD |
| `M10-review.md`、`M11-review.md` | 评审 |
| `ACK-006-legacy-continuation-drill.md` | ack 续接演练 |
| `implementation-notes.md` | 实现说明 |

## 3. 阶段状态

| 阶段 | 状态 | 记录 |
|---|---|---|
| understand（Gate 1） | completed | `confirmed_by=dialog`，2026-10-19 |
| spec（Gate 2） | completed | `confirmed_by=dialog`，2026-10-19 |
| build（Gate 3） | completed | `confirmed_by=cli`，2026-10-20；**确认原文当时未落盘**（字段留着占位符 `<确认原文>`），本次收尾已改为如实标注，未虚构内容 |
| deliver | 本次补记 | 见本文件 |

## 4. 交付判定

- 任务清单 `tasks.md`：**69/69 全部勾选，无未勾项**；
- 无 `validation/`、无 checker 证据行——该 change 的验收方式是各切片 build/review 报告，不是 M003 那套 `channel-evidence.mjs` label 体系，两者不可混用口径；
- 本次收尾**未新增任何实现或测试**，只补交付记录与状态。

## 5. 与后续 change 的关系

`2026-10-22-aifi-45-authorized-execution` 是接续它的下一段工作（授权执行链），仍停在 `build`（multica 36/65、tools 30/59），**未归档**。本 change 归档不影响那段的状态，也不代表 AIFI-45 整体收口（41/49 仍未回填）。

## 6. 归档

按 M003 的同一口径执行 `stdd archive --yes --skip-specs`：不把 `specs/*.md` 合并进 `projects/multica/specs/`（该目录从未存在，工作区级 `specs/` 才是 CR 回写基线），规格文件随 change 留在归档目录内。

## 7. 还原与残余项（2026-10-27）

本 change 于同一天先被归档、随后**还原**到 `changes/`（`stdd rollback`），原因：归档后复查发现 BUILD 虽全勾，但报告里记着若干**未闭环的残余项**，归档会让它们失去可见性。

`stdd rollback` 把 `current_phase` 重置为 `understand`，与已完成的 Gate 1/2/3 矛盾，已手工改回 `build`；`deliver` 改回 `pending`（下文残余项未闭环前不得记 completed）。Gate 3 的确认原文当时未落盘，仍是如实标注、未虚构。

已核实**已闭环**的旧残余（不再列为待办）：`local_directory_snapshot` 行为已实现；`TestMDispatch001/005` 已存在；batch 常量已落地。

**仍待完成**：
1. `internal/handler` 精确 `TestMKb001`、`TestMKb004` **未新增**（`M35-M39-build-report.md` 自述跨包缺口；handler `TestMKb002` 覆盖了资源隔离/N+1）。
2. 三条断言强度不足：MKey004 未单独注入“写文件失败”、MKey005 未在 daemon 模拟旧 grant 缺 key、MKey006 未断言完整 dirty 集合。
3. 恢复时限仍不可宣称：`design.md` 要求隔离库实测，常量有了但**实测证据没有**。
4. runtime 实际 Agent UUID 隔离仍为“待验证”（`implementation-notes.md`），源码中未见对应实现。


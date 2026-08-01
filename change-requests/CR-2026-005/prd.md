---
id: CR-2026-005-prd
type: PRD
cr-ref: CR-2026-005
title: 治理工具链补丁 — delivery/task 回写一致性门禁 + writeback-tasks 原子化 Skill
target-version: "0.12.1"
owner: Ray
owner-role: requirement
status: draft
created: "2026-08-01T13:10:00+08:00"
updated: "2026-08-01T13:10:00+08:00"
revision: "0.1.0"
---

# PRD — 治理工具链补丁：delivery/task 回写一致性

> 本 CR 是治理链路自身的缺陷修补（工具/流程缺陷，不是产品功能），问题已在诊断阶段定位，PRD 按最小必要篇幅编写。

## 1. 概述

**问题陈述**：CR-2026-003 归档时，`delivery/task/` 回写（把已完成任务的 markdown 从 `change-requests/{CR}/tasks/TASK-0X.md` 拷到 `delivery/task/`，加 `spec-id`/`version` frontmatter，并在全局 `delivery/task/_index.yaml` 追加索引行）是**三个独立的手工动作**，靠执行者记忆保持同步——没有任何 skill 文件把它们绑成一步，也没有任何 crctl gate 校验过结果。CR-2026-003 归档时，3 个任务文件被正确拷贝，但对应的 3 条 `_index.yaml` 索引行被漏加，且**没有任何机制在归档时报错或拒绝**——因为现有 `archived` 门禁只检查 `specs/{spec-id}/{PRD,SDD,traceability.yml}` 是否存在，完全不覆盖 `delivery/task/` 目录的内容一致性。这个漏登直到 CR-2026-004 归档时，因为我偶然扫了一眼 `_index.yaml` 尾部做格式参考才发现并补registered——不是被任何系统性核查发现的。

**根本原因**：这是"检测控制缺失 + 预防控制缺失"叠加的双重空白：
1. 没有 gate 在归档前核对 delivery/task 索引的完整性（检测缺失——错误可以永久静默存在）。
2. 没有 skill 把回写的三个动作原子化（预防缺失——每次回写都重新依赖记忆同步，出错概率非零且会重复发生）。

**解决方案**（两层，defense-in-depth）：
1. **gates.json 新增门禁检查**：`archived` 状态转移的 `passCondition` 增加一条，交叉核对当前 CR 的 `tasks/_index.yaml` 中 `status=done` 的任务，是否每一条都能在全局 `delivery/task/_index.yaml` 找到对应条目（按 `id` 匹配）；不一致则 `GATE_BLOCKED`，列出缺失的任务 ID。
2. **新增 `writeback-tasks` skill**：一次调用完成"读 CR 的 done 任务 → 拷贝 markdown 到 `delivery/task/` 并派生 frontmatter（`spec-id`/`version` 从调用参数或 CR 上下文取，不再手打）→ 追加/更新全局 `_index.yaml` 条目"，消除手工分步同步。

**前置**：无代码依赖，纯工具链（`../tools` 包）+ knowledge-base 治理文档改动；不涉及 multica 代码。

## 2. 用户故事

- **US-1** 作为**执行 CR 回写的角色**（当前是我），我希望回写 delivery/task 时不再需要分别记住"拷文件"和"更新索引"两件事，一次调用就能保证两者同步，以便消除因遗忘导致的索引漂移。
- **US-2** 作为**依赖 delivery/task 索引做治理审计的人**，我希望任何 CR 在归档前，其索引完整性被强制校验，以便"已归档"状态本身就是"回写记账无遗漏"的证明，不需要事后人工抽查才能发现漏登。

## 3. 功能需求

| ID | 需求 | 优先级 |
|---|---|---|
| FR-1 | `gates.json` 的 `archived` 门禁新增 `passCondition` 检查项：对当前 CR `tasks/_index.yaml` 中 `status=done` 的每个任务 `id`，必须能在全局 `delivery/task/_index.yaml` 的条目列表中找到 `cr-ref` 匹配且逻辑对应的一条；缺失时拒绝转移并在错误详情中列出缺失的任务 ID 清单 | P0 |
| FR-2 | 新增 `writeback-tasks` skill（`tools/skills/writeback/writeback-tasks/`），输入 `cr_id` + `spec_id` + `version`，执行：① 读取 `change-requests/{cr_id}/tasks/_index.yaml` 筛出 `status=done` 任务；② 对每个任务，读源 `tasks/TASK-0X.md`，写入 `delivery/task/TASK-{version}-{cr_id}-0X-{slug}.md`（`slug` 从任务标题派生），追加 `spec-id`/`version` frontmatter；③ 在全局 `delivery/task/_index.yaml` 追加对应索引行（`id`/`file`/`title`/`status`/`cr-ref`/`target-version`/`estimate`，字段值从源任务 frontmatter 直接取，不重新输入） | P0 |
| FR-3 | FR-1 的门禁检查必须能处理"CR 没有任何 done 任务"（如纯验收类 CR）与"delivery/task/_index.yaml 不存在"（新仓库首次回写）两种边界，均不应误报 | P1 |

## 4. 非功能需求

- **NFR-1 不改变现有归档语义**：FR-1 只新增一项检查，不改变 `archived` 门禁对 specs 三文件的既有检查逻辑，也不影响非归档路径的状态转移。
- **NFR-2 skill 幂等**：`writeback-tasks` 对同一 `cr_id` 重复调用（例如回写后又新完成一个任务再次调用）应表现为"补齐缺失条目"，不重复写入已存在的索引行或覆盖已回写文件的历史内容。
- **NFR-3 不引入新依赖**：FR-1/FR-2 均用现有 YAML 解析与文件操作能力实现，不引入新的第三方库。
- **NFR-4 向后兼容**：已归档的历史 CR（001-004）不因本次门禁新增而被追溯校验或报错——门禁只作用于本次修复上线后新发起的 `archived` 转移。

## 5. 验收标准

- **AC-1**（FR-1 正向）构造一个 delivery/task 索引完整的 CR 场景（done 任务全部登记），执行 `--to archived` → 门禁通过。
- **AC-2**（FR-1 负向，复现原故障）构造一个 done 任务未登记索引的 CR 场景（模拟 CR-2026-003 当时的漏登状态），执行 `--to archived` → `GATE_BLOCKED`，错误详情列出缺失的任务 ID。
- **AC-3**（FR-2）对一个含 2 个 done 任务的 CR 调用 `writeback-tasks`，验证：`delivery/task/` 下出现 2 个新文件（frontmatter 含正确 `spec-id`/`version`）+ 全局 `_index.yaml` 出现 2 条对应新行；随后 AC-1 场景对该 CR 执行门禁应通过（自证闭环）。
- **AC-4**（NFR-2）对同一 CR 重复调用 `writeback-tasks`（无新增 done 任务），索引与文件不产生重复或覆盖性变更。
- **AC-5**（FR-3）对无 done 任务的 CR 与 `_index.yaml` 不存在的场景分别执行门禁，均不误报。

## 6. 成功指标

- 本修复上线后，任何 CR 归档时，delivery/task 索引完整性由门禁强制保证，不再需要人工抽查发现漏登（如本次 CR-2026-004 归档时的偶然发现）。

## 7. 范围排除

- 不治理 backlog→history 的归档迁移手工步骤（同类空白，但本 CR 聚焦本次已确认复现的 delivery/task 回写问题；该项留作后续独立评估，不在本次范围内新增门禁）。
- 不追溯校验或修复历史已归档 CR（001-004）的索引状态（CR-2026-003 的漏登已在上轮手工补齐）。
- 不改变 delivery/task 文件命名规则本身（`TASK-{version}-{cr_id}-0X-{slug}.md`），只把生成过程原子化。

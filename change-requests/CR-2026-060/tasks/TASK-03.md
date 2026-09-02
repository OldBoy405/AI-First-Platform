---
id: CR-2026-060-TASK-03
type: TASK
cr-ref: CR-2026-060
plan-ref: "change-requests/CR-2026-060/plan.md"
sdd-ref: "change-requests/CR-2026-060/sdd.md"
target-version: "0.33"
title: G3 PLAN/TASK/Coding/test/review 合同与 task-init count-hint
slug: plan-task-coding-test-review
status: pending
estimate: 12h
depends-on: ["CR-2026-060-TASK-01"]
created: 2026-09-03T00:35:00+08:00
---

## 任务描述

落地 G3：两张 PLAN 稳定表合同、恰四 TASK 的三步断言（写入前 preflight + `crctl task init --count-hint 4` + init 后防并发复核）、以及 implement-code / write-test-report / review-code 的 workspace/证据/回修合同。`cmdTaskInit` 只允许新增 `--count-hint` 写入前校验，render/CAS/审计内核冻结。

输入条件：TASK-01 已合入（同文件 `crctl.mjs` 无未合并冲突）；CR status=`developing`。本 CR 自身的 plan/tasks 已按两位补零 id 预分配，作为 count-hint 的正例夹具来源之一。

## 涉及文件 / 模块

- `skills/develop/write-dev-plan/SKILL.md`：PLAN 恰含两张稳定表（交付覆盖表列 = `FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚`；证据命令表列 = `证据ID | repo | cwd | executable | args | timeout`）；target-version 从 cr.md 继承
- `skills/develop/write-dev-tasks/SKILL.md`：+`task_count_hint`（本 CR 固定 4）；执行 SDD §4.5 三步断言；失败码 `TASK_COUNT_MISMATCH`；草稿回滚语义
- `skills/develop/review-dev-plan/SKILL.md`：同口径复核 plan 表与索引双向核对
- `skills/develop/implement-code/SKILL.md`：实现依据只取 SDD/PLAN/TASK/目标仓规范/`resources[].worktreePath`（PRD 非并列合同）
- `skills/develop/write-test-report/SKILL.md`：执行 PLAN 证据命令表 canonical 门禁并发布 `sourceRevision`+日志哈希
- `skills/develop/review-code/SKILL.md`：输出固定五字段 `verdict/blockers/suggestions/dimensions/repair-target`；不重跑测试；不新增 aggregate digest；源码/日志/命令漂移 → block
- `skills/shared/crctl/scripts/crctl.mjs`：`cmdTaskInit`（:1732）新增 `--count-hint` 写入前校验；`loadTaskCards` 文件名正则与 `{cr}-TASK-{nn}`（nn 两位）契约保持不变
- `skills/shared/crctl/scripts/test/crctl.test.mjs`（cmd-03：count-hint 正负向量）
- `skills/shared/crctl/scripts/test/test-cr.test.mjs`（cmd-06：既有 sourceRevision/日志哈希向量，本 TASK 不放宽）

禁止改动：`cmdTaskAppend` / `cmdTaskDone`（zero_diff）；`loadTaskCards` 的两位补零文件名契约；review-code 的 schema 必填字段集。

## 实现要点

1. write-dev-plan：两张表为契约必填节，不是「可选附录」；每条验证命令必须有稳定 `cmd-NN`。
2. write-dev-tasks §4.5 三步：
   - 写入前 preflight（Skill 内，零 crctl 调用）：解析交付覆盖表 → 组映射（每 G 恰一个 TASK、每 TASK 恰属一组）；草稿文件集恰 4 个、id = `{cr}-TASK-01`..`04` 连续无重复。失败 → abort `TASK_COUNT_MISMATCH`，删除本轮草稿，零账本/零状态推进。
   - `crctl task init <cr> --count-hint 4`：在 `renderTaskIndex`/`casWrite`/`createFileExclusive`/`audit` **之前**校验卡片数 == 4 且 id 与 `{cr}-TASK-01`..`04` 一一对应（缺号/重号/第五个 → `TASK_COUNT_MISMATCH` 零写入）。`--count-hint` 缺省时行为与现行完全一致。
   - init 后防并发复核：`taskCount==4` + 磁盘文件集组映射重跑；失败保留现场，只允许重跑同一 `task init --count-hint 4`，通过前不得 `advance --to task-breakdown`。
3. implement-code / write-test-report / review-code 按 SDD §3.2 中段修订；回修链仍为 implement-code → test-report → checkpoint → freshness → review-code（AC-10）。
4. count-hint 的 id 口径 = 现行两位补零，禁止改 `loadTaskCards` 正则去迎合口语「TASK-1」。

## 验收条件

1. write-dev-plan SKILL 正文出现两张稳定表的固定表头（cmd-01 文本抽查 / AC-07）。
2. `crctl task init --count-hint 4` 在卡片数 ≠ 4、缺号、重号、出现第五个文件时返回 `TASK_COUNT_MISMATCH`，且 `_index.yml` 与 audit 零变化（cmd-03 / AC-08）。
3. `--count-hint` 缺省时既有 CR 的 `task init` 行为与基线一致（cmd-03 回归）。
4. write-test-report SKILL 要求发布 `sourceRevision` 与日志哈希；review-code SKILL 列出五字段且写明不重跑测试、漂移 → block（cmd-01 / AC-09 Skill 面；cmd-06 覆盖既有 test-cr 向量）。
5. review-code SKILL 写明 evidence-only 回修仍走 implement-code→test-report→checkpoint→freshness→review-code；blocker 清空前不可达 human approval（cmd-01 / AC-10）。
6. 本 TASK diff 不修改 `cmdTaskAppend`/`cmdTaskDone`/`cmdApprove`。

## 完成标志

SKILL.md 与 `cmdTaskInit --count-hint` 已落盘；cmd-03 新增 count-hint 向量全绿；提交 `[cr] implement CR-2026-060 TASK-03`；`crctl task done CR-2026-060 --task CR-2026-060-TASK-03`。

## 接口契约

- 消费：无 TASK-01 函数符号（本 TASK 不调用 `resolveTargetSpecMode`）。文件序依赖：必须在 TASK-01 对 `crctl.mjs` 的 commit 之后改 `cmdTaskInit`，避免覆盖 register/gate/advance 改动。
- 产出（供 TASK-04 与后续 `write-dev-tasks` 运行时消费）：
  - `cmdTaskInit(ws, cr)` 新增可选 flag `--count-hint <N>`（N 为正整数）。缺省：现行行为。当 `N` 给出：写入前若 `loadTaskCards().cards` 的 id 集合 ≠ `{cr}-TASK-{pad2(1)}`..`{cr}-TASK-{pad2(N)}` → `fail('TASK_COUNT_MISMATCH', ...)`，不写 `_index.yml`、无 audit。成功 JSON 既有键保持：`{ op:'task-init', cr, file, taskCount, totalEstimateHours, changed }`
  - Skill 合同：`write-dev-tasks(cr_id, task_count_hint=4)` 必须执行 §4.5 三步；失败码字面 `TASK_COUNT_MISMATCH`
- 不产出 writeback/archive 符号（TASK-04）。

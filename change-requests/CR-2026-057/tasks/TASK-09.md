---
id: CR-2026-057-TASK-09
type: TASK
cr-ref: CR-2026-057
plan-ref: "change-requests/CR-2026-057/plan.md"
sdd-ref: "change-requests/CR-2026-057/sdd.md"
target-version: unassigned
title: write-dev-plan / write-dev-tasks / write-test-report 契约修订（FR-8/FR-10/FR-13）
slug: dev-plan-tasks-test-report-contract
status: pending
estimate: 6h
depends-on: []
created: 2026-08-31T22:00:00+08:00
---

## 任务描述

修订 `write-dev-plan`（FR-8 覆盖矩阵必填 + FR-13 版本继承）、`write-dev-tasks`（FR-10 流程控制 TASK 禁止 + FR-13 TASK frontmatter）、`write-test-report`（FR-16 机器区 skipped 与 cmd-NN 绑定说明）。本 plan.md 与 tasks/ 即按新契约先行示范（AC-8/AC-10 静态证据）。

输入条件：tools CR worktree；纯文档修订，可与 M3 并行。

## 涉及文件 / 模块

- `skills/develop/write-dev-plan/SKILL.md`
- `skills/develop/write-dev-tasks/SKILL.md`
- `skills/develop/write-test-report/SKILL.md`

## 实现要点

1. **write-dev-plan**：frontmatter 模板 `target-version: {target_version 或 tbd}` 改为 `target-version: {cr.md 值}`（删除 `或 tbd`；参数说明改为从 cr.md 读取、禁止改写）；新增「AC/业务闭环覆盖矩阵」必填节，表头 `| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |`；关键 AC 定义（影响主路径验收可达性、含用户可观察的成功/失败/隔离/幂等）；关键 AC 的验收证据列必须写稳定标识 `cmd-NN`（两位十进制，与 FR-16 全等），不得只写散文命令；非关键 AC 可合并行但必须能追溯到至少一条 TASK；矩阵节示例对齐本 plan.md §6。
2. **write-dev-tasks**：TASK frontmatter 增 `target-version: {cr.md 值}`（从 cr.md 读取，禁止 tbd/改写）；补 FR-10 禁止条款——不得把 Pipeline 控制步骤 `merge`/`writeback`/`archive` 建成交付 TASK（含标题或正文写成「发布准备」「merge 完成」之类）；不得创建完成前置包含 `code-reviewing`/`code-approved`/`merge`/`writeback`/`archive` 的交付 TASK；「实现已就绪、可交评审」类 TASK 的完成边界必须是 developing 内可被 `crctl task done` 登记的事件（实现落盘、关键测试命令已写入 test plan）；merge/审批/checkpoint 审计事实以 `approval.yml`/`merge-commits.yml`/checkpoint 元数据为准，不进 TASK ledger。保留既有「禁止 Agent/Skill 手写 `_index.yml`」与 `crctl task init` 措辞。
3. **write-test-report**：机器区字段说明补 `skipped`（additive 布尔，计算规则引用 FR-16 模式表，review-code 只读）；补 `cmd-NN` 稳定关联说明（NN = 机器区 commands 1-based 下标，与 `test-evidence/cmd-NN.log` 文件名全等，与 plan 覆盖矩阵「验收证据」列全等）。
4. 文本约束（R8）：write-dev-tasks 新文本不得匹配 `/crctl git commit/` 与 `/重新生成.*TASK 与 `_index\.yml`/`（既有断言禁串）；三个文件新文本均不含 contract-scan 四串。

## 验收条件

1. write-dev-plan：无 `或 tbd`；矩阵节契约（四列表头、关键 AC 定义、cmd-NN 证据规则、非关键行追溯规则）齐备。
2. write-dev-tasks：TASK frontmatter 含 target-version；FR-10 禁止条款完整（含「完成于 merge 的发布准备」例外取消的理由说明）；既有 task init/手写禁止措辞保留。
3. write-test-report：机器区 `skipped` 与 `cmd-NN` 绑定说明齐备。
4. 既有静态断言不新增失败（cmd-01 除基线红外绿）；contract-scan 零命中（AC-4）；lint-prompts 通过。

## 完成标志

三 SKILL 文本核对通过；contract-scan/lint-prompts 零命中；提交 `[cr] implement CR-2026-057 TASK-09`。

## 接口契约

- 消费：cr.md `target-version`（继承源）；机器区 `skipped` 字段与 `cmd-NN` 定义（TASK-05 产出，write-test-report 仅引用）。
- 产出：三 SKILL 文本契约；`plan.md` 新必填节（覆盖矩阵）与 `TASK` frontmatter 新字段 `target-version` 的文档契约。
- 不产出新 CLI、新状态、新 ledger。

---
id: CR-2026-073-TASK-04
type: TASK
cr-ref: CR-2026-073
plan-ref: "change-requests/CR-2026-073/plan.md"
sdd-ref: "change-requests/CR-2026-073/sdd.md"
target-version: 0.46
title: 普通 CR 定向验收范围与评审口径
slug: targeted-cr-evidence-scope
status: pending
estimate: 6h
depends-on: []
created: 2026-09-30T13:05:00+08:00
---

## 任务描述

G4 / FR-6～FR-8 / AC-6～AC-7。根据 SDD §3.3 调整三个开发期 Skill 的自然语言合同及定向案例，并补独立评审真实 verdict / 上游同步全量原始证据；不新增 schema、机器门禁、Pipeline 或 multica 修改。

## 涉及文件 / 模块

`tools/skills/develop/write-dev-plan/SKILL.md`、`tools/skills/develop/write-dev-tasks/SKILL.md`、`tools/skills/develop/review-dev-plan/SKILL.md`；`tools/skills/shared/crctl/scripts/test/skill-scope.test.mjs`；只读 `multica/CUSTOM.md` 及真实上游同步全量原始日志/基线。案例原始评审证据入口为隔离测试 CR 的 canonical `review-annotations/dev-plan.yml`，本 CR 留可核查引用/只读副本于 `test-evidence/scope-review/`；上游证据留 `test-evidence/upstream-sync/`。

## 实现要点

plan 两张稳定表仍保持原列，cmd 唯一算法仍在证据命令表；关键 FR/AC 选可观测的最窄定向命令、注明运行范围。TASK 逐项继承证据 ID/真实范围/声称面，不额外加全仓绿色。review 对普通 CR 无批准全量却设置全仓关键命令、或子集冒充全量，反馈 FR/AC、cmd 与 `repair-target=write-dev-plan`；若冲突来自已批准 SDD/AC，用既有 upstream-design-blocker 路由。plan §5 的 U/S/P 三例在隔离的可评审测试 CR worktree 中准备，分别交给新的独立 reviewer run 按 `review-dev-plan` 评审；保留真实 verdict、subject SHA、源 CR/workspace、canonical annotations、review-loop、next 及 reviewer 评论供测试报告核对。上游同步仍按 `CUSTOM.md` 全量并保留 Windows 失败原文和基线对照；本 CR 不执行 merge/rebase，只核查真实同步记录，原始日志缺失则 AC-7 不闭合。

## 验收条件

1. `cmd-06`（plan §6）：仅检验普通 CR 定向证据/不误设全仓的 Skill 合同与夹具断言；它不证明 review 的 BLOCK。独立 reviewer 在 plan §5 的 U/P 测试 CR 快照分别评审：U 实际 block 且反馈 FR/AC、cmd、`repair-target=write-dev-plan`，P 不因缺全仓测试被 block；核对 `test-evidence/scope-review/` 中源 canonical verdict、subject SHA、reviewer 评论及测试报告引用，不得以 Skill 文本测试结果代替。
2. `cmd-07`（plan §6）：仅检验 TASK 继承、子集冒充全量须 blocker 的 Skill 合同与夹具断言；它不证明真实 verdict。独立 reviewer 在 plan §5 的 S 快照实际 block 并指出 FR/AC、cmd、repair-target；核对同一独立评审证据入口。已批准全量不可达时不得局部替代。
3. `cmd-08`（plan §6）：仅检验上游同步全量与 Windows 原始失败/基线对照**文字合同**，不声称执行了 multica 全量。另在 TASK 实现期核查一笔真实上游同步的完整原始运行记录（命令/cwd/commit SHA/时间/exit code/未截断输出）与同条件合并前/纯上游 Windows 基线，逐项比对失败名单及数量；`test-evidence/upstream-sync/` 存原始日志/基线对照并由 test-report 引用。任何原始日志、命令或基线缺失均不得宣称 AC-7 上游场景通过，需补取或等下一次独立授权同步；不把已知失败改成绿色 cmd。另跑已有 lint-prompts / matrix 校验，不代替评审。

## 完成标志

三个 Skill 文件与定向案例落盘，保留 cmd-06～08 运行结果；三个独立 reviewer 案例的真实 verdict 与上游同步原始全量/Windows 基线证据均可由 test-report 追溯（不能核验则如实标未闭合，不以 cmd 绿色代替）。在 developing 内即时用 `crctl task done` 标记 `CR-2026-073-TASK-04`；上游同步全量失败不是本普通 CR 的绿色门槛，但核查证据不可省。

## 接口契约

- 消费：已批准 `sdd.md` §3.3 / §8 的 FR/AC 验收面；plan `| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |` 与 `| 证据ID | repo | cwd | executable | args | timeout |`，`cmd-NN` 为唯一可执行证据 ID；TASK 有 `验收条件`、`完成标志`；review 原有 blockers 与 upstream-design-blocker 双轨。
- 产出：上述三 Skill 在原表/字段/节点内约束“已批准验收面 ≤ cmd 可观测面”、TASK 继承相同 cmd/范围、误设全量或虚称全量判 blocker；普通轨 `repair-target=write-dev-plan`，批准 SDD 冲突仍按既有上游回修。`cmd-06`～`cmd-08` 只出合同断言；真实 reviewer verdict 与上游运行证据分别从 plan §5 的外部入口取证。无跨 TASK 代码接口。

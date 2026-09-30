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

G4 / FR-6～FR-8 / AC-6～AC-7。根据 SDD §3.3 仅调整三个开发期 Skill 的自然语言合同及定向案例；不新增 schema、机器门禁、Pipeline 或 multica 修改。

## 涉及文件 / 模块

`tools/skills/develop/write-dev-plan/SKILL.md`、`tools/skills/develop/write-dev-tasks/SKILL.md`、`tools/skills/develop/review-dev-plan/SKILL.md`；`tools/skills/shared/crctl/scripts/test/skill-scope.test.mjs`；只读 `multica/CUSTOM.md` 的上游全量基线规则。

## 实现要点

plan 两张稳定表仍保持原列，cmd 唯一算法仍在证据命令表；关键 FR/AC 选可观测的最窄定向命令、注明运行范围。TASK 逐项继承证据 ID/真实范围/声称面，不额外加全仓绿色。review 对普通 CR 无批准全量却设置全仓关键命令、或子集冒充全量，反馈 FR/AC、cmd 与 `repair-target=write-dev-plan`；若冲突来自已批准 SDD/AC，用既有 upstream-design-blocker 路由。上游同步仍按 `CUSTOM.md` 全量且保留 Windows 失败原文和基线对照；批准 AC 要求全量时不可用子集绕过。

## 验收条件

1. `cmd-06`（plan §6）：只跑普通 CR 定向案例 `CR073 ordinary CR targeted evidence`，误设全仓 BLOCK，修正后 cmd/TASK 同范围且不宣称全量。
2. `cmd-07`（plan §6）：只跑 `CR073 scope mismatch blocks review`，子集命令冒充全量则 BLOCK 并指出 FR/AC、cmd、repair-target；批准全量不可达时不得局部代替。
3. `cmd-08`（plan §6）：只跑 `CR073 upstream full-suite exception`，核对上游仍全量执行及 Windows 原始失败/基线对照的文字合同；此案例不声称真的运行 multica 上游同步全量。额外运行已有 lint-prompts / matrix 校验，不代替独立评审判断。

## 完成标志

三个 Skill 文件与定向案例落盘，保留运行结果；在 developing 内即时用 `crctl task done` 标记 `CR-2026-073-TASK-04`。上游同步不是本次普通 CR 的全量绿色 TASK 门槛。

## 接口契约

- 消费：已批准 `sdd.md` §3.3 / §8 的 FR/AC 验收面；plan `| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |` 与 `| 证据ID | repo | cwd | executable | args | timeout |`，`cmd-NN` 为唯一可执行证据 ID；TASK 有 `验收条件`、`完成标志`；review 原有 blockers 与 upstream-design-blocker 双轨。
- 产出：上述三 Skill 在原表/字段/节点内约束“已批准验收面 ≤ cmd 可观测面”、TASK 继承相同 cmd/范围、误设全量或虚称全量判 blocker；普通轨 `repair-target=write-dev-plan`，批准 SDD 冲突仍按既有上游回修。无跨 TASK 代码接口。

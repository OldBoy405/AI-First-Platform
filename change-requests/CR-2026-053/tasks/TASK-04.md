---
id: CR-2026-053-TASK-04
type: TASK
cr-ref: CR-2026-053
plan-ref: "change-requests/CR-2026-053/plan.md"
sdd-ref: "change-requests/CR-2026-053/sdd.md"
title: 修改 review Skill 绑定前置步骤
slug: review-skill-bind-step
status: pending
estimate: 2h
depends-on: [CR-2026-053-TASK-01, CR-2026-053-TASK-03, CR-2026-053-TASK-05]
created: 2026-08-28T11:20:00+08:00
---

## 任务描述

在四个 review Skill 的 `review-record` 之前插入同一绑定前置步骤（FR-B7）：

```text
若当前运行具有 Multica task-scoped context（存在 mat_ token 注入的 task 上下文）：
    result = bind-current-task-to-cr(CR-ID)
    if result 失败:
        → 按技术失败中止，不写 canonical review（不转业务 blocker）
否则：
    → 视为普通本地/非 Multica 执行，跳过绑定，继续现有 review-record 行为（FR-A7）
```

## 涉及文件 / 模块

- `../tools/skills/requirement/review-requirement/SKILL.md`
- `../tools/skills/develop/review-tech-design/SKILL.md`
- `../tools/skills/develop/review-dev-plan/SKILL.md`
- `../tools/skills/develop/review-code/SKILL.md`

## 实现要点

参考 SDD §4.2 (FR-B7)：
- 绑定放在 Skill 层（而非 Agent/Pipeline）
- 位置：写临时评审 payload / 调用 `crctl review-record` 之前
- 技术失败硬失败，不静默降级；无 Multica task context 时跳过
- `TASK_ISSUE_REQUIRED` = 创建路径未按 FR-B12 携带 Issue 上下文，修路径后重试

## 验收条件

1. `grep -rn "bind-current-task" ../tools/skills/requirement/review-requirement/SKILL.md ../tools/skills/develop/review-tech-design/SKILL.md ../tools/skills/develop/review-dev-plan/SKILL.md ../tools/skills/develop/review-code/SKILL.md` 四个文件均命中
2. `node ../tools/pipeline-templates/emit-registry.mjs --verify` 通过
3. 绑定步骤位置在 `review-record` 之前（逐个文件核对步骤顺序）

## 完成标志

- 四个 Skill 文件修改已 commit
- 验证 Track B 绑定接口（TASK-05）可用后，端到端测试通过

## 接口契约

**消费**:
- `bind-current-task-to-cr(CR-ID)` 接口（由 CR-2026-053-TASK-05 实现）

**产出**:
- 绑定成功后继续执行 review-record

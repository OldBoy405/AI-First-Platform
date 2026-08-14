---
spec-id: ai-first-platform
version: "0.25"
id: CR-2026-024-TASK-01
type: TASK
cr-ref: CR-2026-024
plan-ref: "change-requests/CR-2026-024/plan.md"
sdd-ref: "change-requests/CR-2026-024/sdd.md"
title: 批次一存量缺口收口（零行为变更：死声明清理 + capabilities 订正 + forbidden 说明 + TDD 悬空删除 + assignee 删除）
slug: batch1-legacy-gap-closure
status: done
estimate: 4h
depends-on: []
created: "2026-08-08T22:00:00+08:00"
---

# TASK-01 批次一存量缺口收口

## 1. 任务描述
按 SDD §4.1 六步执行批次一——纯删除/数据对齐，零运行时行为变更。全部改动同一 commit（commit 1）提交。目标：清除 external 死声明、订正与事实相反的 capabilities、写明 forbidden 声明性边界、删除 implement-code/pipeline 的 TDD 悬空引用并补降级路径、删除 write-dev-tasks 的 assignee 死字段。

## 2. 涉及文件 / 模块（tools 仓）
- `agent-skill-matrix.yml`
- `agents/_index.yml`
- `skills/develop/implement-code/SKILL.md`
- `pipeline-templates/code-implementation.pipeline.json`
- `skills/develop/write-dev-tasks/SKILL.md`
- `AGENT-SKILL-MATRIX.md` + `openwiki/architecture/agent-skill-matrix.md`

## 3. 实现要点（SDD §4.1 步骤 1~6）
1. **死声明删除（FR-1，C-2/C-5）**：`system-orchestrator.external` 删 using-superpowers/writing-plans/verification-before-completion 三项（L217-219，清后为 `[]`）；`dev-agent.external` 删 test-driven-development（L94，随 FR-2/FR-3 删引用后变零引用，须同批清除）；known-gaps 删前两条（knowledge-agent-write-skills、customer-support-feedback-write）。顶层 `external-skills:` 纯文档块（L222-230）不动。
2. **capabilities 订正（FR-4，§2.3）**：knowledge-agent 移出 tech-note-write/insight-write 至 pending；customer-support-agent 移出 unresolved-feedback-record 至 pending。
3. **implement-code 降级（FR-2，§3.4）**：删 L75「必须遵循 external test-driven-development」，补降级文本——**止于「串行 + 注明降级」**，不含 coding-discipline 引用（后半句归 TASK-02，B-2）。
4. **pipeline nodes[5] 同步（FR-3，C-1）**：code-implementation.pipeline.json nodes[5]（implement-code）prompt 同步删 TDD 表述、补同款降级表述。
5. **write-dev-tasks 删 assignee（FR-6）**：删 L59 `assignee: ""` 行；`depends-on` 保留。
6. **forbidden 性质说明（FR-5）**：AGENT-SKILL-MATRIX.md + openwiki 写明 forbidden 为声明性边界（无调用级拦截，执行靠 agent 自觉 + protectedPaths 文件守卫，不加运行时钩子）。

## 4. 验收条件
- 三件套全绿：`check-skill-matrix` + `check-agents-contract` + `lint-prompts --mode enforce`。
- grep 四项名称（using-superpowers/writing-plans/verification-before-completion/test-driven-development）确认 actor 级零残留、顶层 external-skills 块原样。
- 状态机回归：死声明删除仅影响矩阵报告面，行为零变化。

## 5. 完成标志
三件套全绿 + grep 零残留 + 行为回归通过；批次一六步全部落盘并作为 commit 1 提交（commit message 注明方案 v2.6 + CR-2026-024 溯源，FR-24）；任务状态在 `_index.yml` 标记 done。

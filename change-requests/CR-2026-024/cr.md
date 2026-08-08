---
id: CR-2026-024
title: Phase0 Tools 技能整合 — 端到端 Pipeline 最佳实践（六条内化项 + 存量缺口收口 + external 死声明清理）
summary: "按《端到端Pipeline最佳实践技能整合方案》v2.6 实施两批变更：批次一收口（零新增行为）——删除 4 个零引用 external 死声明（using-superpowers/writing-plans/systematic-debugging/verification-before-completion）、implement-code 与 code-implementation pipeline 删 TDD 悬空引用并补 executing-plans/subagent-driven-development 降级路径、agents/_index.yml 三项 capabilities（tech-note-write/insight-write/unresolved-feedback-record）从 supported 挪进 pending 且 known-gaps 前两条删除、AGENT-SKILL-MATRIX.md 与 openwiki 写明 forbidden 为声明性边界（无调用级拦截）、write-dev-tasks 删 assignee 死字段；批次二内化（真实行为变更）——新建 coding-discipline skill（§1 极简阶梯/§2 步骤粒度/§3 根因排查与回归验证）、review-code 第五维度（仅可验证项）与 Step 1 无条件重新执行验证命令、write-dev-tasks 接口契约与类型一致性自查、implement-code 追加 depends-on 拓扑排序与并发边界（§4.8）、code-implementation pipeline 新增 suggestion_policy 触发参数（strict/lenient，default strict）驱动评审期 suggestions 策略化分流并经 record-idea 落 docs/ideas/、approve-code 追加 suggestions 转想法池、write-requirement-prd 优先采纳 summary 已确认边界、AGENTS.md 第 56 条修订"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-08T16:44:35+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-08T16:44:35+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-08T16:44:35+08:00"
target-version: tbd
source: "docs/analysis/端到端Pipeline最佳实践技能整合方案.md v2.6"
status: writing-back
created: "2026-08-08T16:44:35+08:00"
updated: "2026-08-08T16:44:35+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-08-08T16:44:35+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-08-08T16:44:35+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-08-08T16:44:35+08:00", reason: initial-assignment }
handover-history: []
---

---
id: CR-2026-026
title: 开发计划与 TASK 合并评审门禁 — 新增 review-dev-plan 编码前质量门禁
summary: "按《开发计划与TASK合并评审门禁方案》在 code-implementation 的 write-dev-tasks 与开发启动人工审批之间新增 review-dev-plan LLM 合并评审节点：一次评审 SDD→plan→TASK 八类维度（覆盖/可执行性/依赖拓扑/接口契约/验收/范围/风险回滚/估算），PASS 保持 task-breakdown 进入现有开发启动人工审批，BLOCK 经新状态转换回 tech-design-reviewed 并依 write-dev-plan→write-dev-tasks→review-dev-plan 顺序重放（最多 3 轮）；复用既有 review-record 与三账本，仅新增 dev-plan.yml 阶段证据，不新增状态/审批节点/账本类型；approve-dev-start 门禁升级为校验自动评审 passCondition 与 evidence digest。改动面：tools 包（新 Skill、code-implementation pipeline 模板、crctl REVIEW_STAGE 映射、gates.json）+ 本仓 dir-graph.yaml 状态转换。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-09T04:57:35+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-09T04:57:35+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-09T04:57:35+08:00"
target-version: tbd
source: "docs/analysis/开发计划与TASK合并评审门禁方案.md"
status: drafting
created: "2026-08-09T04:57:35+08:00"
updated: "2026-08-09T04:57:35+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-08-09T04:57:35+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-08-09T04:57:35+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-08-09T04:57:35+08:00", reason: initial-assignment }
handover-history: []
---

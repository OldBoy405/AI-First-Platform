---
id: CR-2026-023
title: 治理工具链 — 代码评审 LLM 选择暂停节点 + R9 护栏（CR 上下文下一步收敛 crctl next）
summary: "两个分析文档合一的治理工具链 CR：① code-implementation pipeline 在节点 8 push-progress 与节点 9 review-code 之间插入 human_approval「选择代码评审 LLM」暂停节点（0013），新增触发输入 review_llm 可选预选，review-code prompt 头部追加 reviewer-model 留痕（dimensions 内不改 crctl 契约），replayNodes 不加入选择节点（一次选择全程复用），同步 _index.yml nodes 12→13 与 README 代码编写期节点表；② lint-prompts 新增 R9 规则——CR 上下文域（requirement/develop/writeback/sync/cr）skill 的「下一步」提示必须收敛到 crctl next，禁止手写 skill/pipeline 名映射副本，判据源直读 skills/_index.yml，17 处存量手写副本清零 + push-progress 摘要补下一步 + requirement-writer 映射表前置注记。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-06T23:16:15+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-06T23:16:15+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-06T23:16:15+08:00"
target-version: tbd
source: "docs/analysis/code-review-llm-selection-plan-2026-08-06.md; docs/analysis/review-skip-drift-and-r9-guard-2026-08-06.md"
status: requirement-reviewing
created: "2026-08-06T23:16:15+08:00"
updated: "2026-08-06T23:16:15+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-08-06T23:16:15+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-08-06T23:16:15+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-08-06T23:16:15+08:00", reason: initial-assignment }
handover-history: []
---

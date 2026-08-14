---
id: CR-2026-015
title: P3 组织智能 CR-C — 跨 CR 追溯与漂移检测（E4+E5+E9）
summary: >-
  P3 组织智能第三个 CR（追溯与漂移检测线，E4→E5 走 P1 outbox 通道，E9 依赖 P2.5
  wiki_query_log 已落库）：① E4 trace 事件 + spec_trace 投影 + spec 详情页——
  writeback-traceability 完成时 crctl outbox 发 trace 事件（event_kind 枚举加一项），
  payload 即 traceability.yml 内容；spec_trace 表投影进 PG 支撑查询：这个功能（FR）
  由哪些 CR 演进而来 → 时间线；这次上线的 merge commit / 测试证据 / 评审记录在哪 →
  一跳直达；某个人经手过哪些 spec → 按 owners 反查。② E5 两个巡检 Autopilot +
  drift_finding + bypass-commit 探测——基线对齐扫描（review-alignment 检测 PRD↔SDD↔
  TASK↔代码 drift，每周日夜间每个活跃 spec 一个任务，quality-reviewer-agent 执行只读，
  drift 写 traceability.yml#drift → outbox → drift_finding 投影 → 严重项进 Owner inbox）+
  变更影响扫描（change-impact-analysis，trunk 有非 CR 流程直接提交时触发，下游
  reviews.*.result 置 stale + change-log，同时是「绕过流程写代码」检测器计入治理板块）；
  drift_finding 表（kind: alignment-drift/impact-stale/bypass-commit，severity:
  info/warn/block）。③ E9 知识晋升巡检（双信号源）——信号一：问答日志聚类（近 30 天
  同类问题 ≥3 次且命中文件分散，说明事实源没有一处权威回答，数据源 wiki_query_log）+
  信号二：open-questions 条目（wiki-maintain Skill 维护 Wiki 时发现的缺口记入
  wiki/open-questions.md 的 Active 节）；knowledge-agent 每周与 review-alignment 同批
  执行，两路信号汇总去重 → 自动开普通 Issue「建议将〈主题〉回写事实源」，附问题样本/
  open-question 条目与建议落点（specs/ 或 docs/）——只开 Issue 不动文件，回写仍走人审
  的正常 CR/文档流程。
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-04T06:54:00+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-04T06:54:00+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-04T06:54:00+08:00"
target-version: "0.22"
source: "docs/product/P3-组织智能设计.md §2（E4+E5+E9）"
status: withdrawn
created: "2026-08-04T06:54:00+08:00"
updated: "2026-08-04T06:54:00+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - role: requirement
    from: ""
    to: Ray
    at: "2026-08-04T06:54:00+08:00"
    reason: initial-assignment
  - role: development
    from: ""
    to: Ray
    at: "2026-08-04T06:54:00+08:00"
    reason: initial-assignment
  - role: test
    from: ""
    to: Ray
    at: "2026-08-04T06:54:00+08:00"
    reason: initial-assignment
handover-history: []
---

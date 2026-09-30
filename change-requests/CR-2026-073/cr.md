---
id: CR-2026-073
title: crctl test 长输出与审计归属修复、普通 CR 验收范围约束
summary: "AIFI-38 三项独立验收：A 修复 crctl test 有界长输出的 ENOBUFS 分类及证据完整性；B merge/writeback/archive 审计统一写入 install-root 且保持 actor 与重放去重；C 普通 CR 的 plan/TASK/评审按 FR/AC 定向证据验收，不默认全仓绿色，保留上游同步全量要求。保持既有状态机、账本、门禁与 merge 事务语义，不伪造历史审计。"
owner: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
owners:
  requirement:
    id: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
    assigned-at: "2026-09-30T12:22:15+08:00"
  development:
    id: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
    assigned-at: "2026-09-30T12:22:15+08:00"
  test:
    id: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
    assigned-at: "2026-09-30T12:22:15+08:00"
target-version: 0.46
target-spec-id: ai-first-platform
source: manual
origin: ""
status: tech-design-review-pending
created: "2026-09-30T12:22:15+08:00"
updated: "2026-09-30T12:46:40+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: a0e71a32-509d-4ee9-aea4-d086a5b1ff93, at: "2026-09-30T12:22:15+08:00", reason: initial-assignment }
  - { role: development, from: "", to: a0e71a32-509d-4ee9-aea4-d086a5b1ff93, at: "2026-09-30T12:22:15+08:00", reason: initial-assignment }
  - { role: test, from: "", to: a0e71a32-509d-4ee9-aea4-d086a5b1ff93, at: "2026-09-30T12:22:15+08:00", reason: initial-assignment }
handover-history: []
---

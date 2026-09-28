---
id: CR-2026-072
title: CRCTL_WORKSPACE 跨项目错根防护：显式 workspace 与任务级绑定
summary: "AIFI-37（AIFI-35 为跨项目同名 CR 错根问题来源，不承接其业务门禁）：CR 读写调用方显式绑定经验证的项目 operational workspace；crctl 缺 --workspace fail-closed；daemon 非 Pipeline 任务取消配置列表首根回退，连同调用点迁移与回归同批交付。"
owner: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
owners:
  requirement:
    id: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
    assigned-at: "2026-09-28T22:44:42+08:00"
  development:
    id: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
    assigned-at: "2026-09-28T22:44:42+08:00"
  test:
    id: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
    assigned-at: "2026-09-28T22:44:42+08:00"
target-version: 0.45
target-spec-id: ai-first-platform
source: manual
origin: ""
status: tech-designing
created: "2026-09-28T22:44:42+08:00"
updated: "2026-09-28T23:21:28+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: a0e71a32-509d-4ee9-aea4-d086a5b1ff93, at: "2026-09-28T22:44:42+08:00", reason: initial-assignment }
  - { role: development, from: "", to: a0e71a32-509d-4ee9-aea4-d086a5b1ff93, at: "2026-09-28T22:44:42+08:00", reason: initial-assignment }
  - { role: test, from: "", to: a0e71a32-509d-4ee9-aea4-d086a5b1ff93, at: "2026-09-28T22:44:42+08:00", reason: initial-assignment }
handover-history: []
---

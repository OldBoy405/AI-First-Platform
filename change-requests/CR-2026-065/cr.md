---
id: CR-2026-065
title: CR-S：测试基线与门禁可信化 — 断言去硬编码、4 条基线漂移转绿、CI 全量步骤成为真门禁
summary: "tools 全量测试在基线上自带 5 条红（由 3 次状态机变更、1 次文案变更与 1 次 reader 重构累积而来），使任何在 SDD 里写「全量测试全绿」的 CR 都不可达，只能每个 CR 再签一次例外授权（CR-2026-060 / CR-2026-063 / CR-2026-064 已各付一次）。本 CR 是 CR-2026-064 的前置：把计数/文本类断言从硬编码快照改为从事实源推导并同步 4 条断言漂移使其转绿（BR-1…BR-4）、把 archive-tx 的 RED-7 按「构造改对」修正并把去重比较字段钉成可检查契约（BR-5）、把 CI 全量测试步骤变成真门禁（含 --test-concurrency=2 的收敛决定），残留例外必须登记 owner 与到期。不改产品语义、不改 write-tech-design / review-tech-design 的 SDD 评审合同、不含 CR-2026-064 的恢复合同迁移本身。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-09-13T02:31:20+08:00"
  development:
    id: Ray
    assigned-at: "2026-09-13T02:31:20+08:00"
  test:
    id: Ray
    assigned-at: "2026-09-13T02:31:20+08:00"
target-version: 0.38
target-spec-id: ai-first-platform
source: AIFI-26
origin: ""
status: tech-design-reviewed
created: "2026-09-13T02:31:20+08:00"
updated: "2026-09-13T11:45:53+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-09-13T02:31:20+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-09-13T02:31:20+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-09-13T02:31:20+08:00", reason: initial-assignment }
handover-history: []
---

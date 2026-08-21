---
id: CR-2026-049
title: P3 组织智能 CR-C：跨 CR 追溯与漂移检测（E4 追溯 + E5 漂移）
summary: "目标版本 0.23。E4 追溯：writeback-traceability 完成时 crctl outbox 发 trace event_kind（cr_sync_event.event_kind 无 CHECK 约束，加第 7 个值零迁移），payload 即 traceability.yml 内容，UNIQUE(cr_id,commit_sha,event_kind) 幂等；spec 详情页/全局搜索从 FR 一跳直达 merge commit 与测试证据；不建 spec_trace 投影表（R-10）。E5 漂移：服务端纯 Go 每小时 sys_cron 按 dir-graph.yaml#repositories[].commit_prefixes 白名单扫 trunk 新提交，前缀不符计 bypass-commit(warn)、wip: 计 wip-on-trunk(info)；drift_finding 表含幂等唯一索引(kind,spec_id,evidence->>commit_sha)，at-least-once+唯一索引去重（R-13）；白名单单一事实源在本仓，照抄 governance/gen/generate-transitions.mjs 生成器吐 Go 副本（R-8 模式）；迁移从 375 起、禁新增 FK、索引 CONCURRENTLY 每迁移一条（R-7）。依赖 E4→E5 一条线，开工前置无。范围与验收见 P3 §5.1 CR-C / §5.2 E4+E5，23 项决议见 P3 §7。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-20T19:26:58+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-20T19:26:58+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-20T19:26:58+08:00"
target-version: 0.23
source: "docs/product/P3-组织智能设计.md §2+§5.1+§7; docs/analysis/P3组织智能-开工前代码核对评审.md"
origin: ""
status: archived
created: "2026-08-20T19:26:58+08:00"
updated: "2026-08-21T09:16:06+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-08-20T19:26:58+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-08-20T19:26:58+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-08-20T19:26:58+08:00", reason: initial-assignment }
handover-history: []
---

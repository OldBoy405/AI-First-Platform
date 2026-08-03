---
id: CR-2026-018
title: 治理工具链 — 状态推进单写 cr.md，_backlog.yml 退化为注册索引（T1-full）
summary: >-
  CR-2026-012 收尾复盘确认的最大摩擦源（约占卡点耗时 35%）：crctl advance 每次双写
  _backlog.yml 条目 + cr.md frontmatter 的 status，CR 分支与 master 各有一串状态提交，
  rebase/merge 时必然逐提交冲突（CR-2026-012 生命周期 9 个状态提交全撞同一文件同一区域）。
  本 CR 将状态推进改为只写 cr.md，_backlog.yml 退化为注册索引（保留 id/owners/merge-commits
  等低频字段），从源头消除合并冲突面。改造面：crctl 8 处写入逻辑 + 31 个引用 _backlog.yml
  的 skill + claude-code 适配器（SessionStart 注入）与 CI 适配器（crctl gate）同版本发布，
  crctl 加兼容读（cr.md 优先、_backlog.yml 回退）。是 P2（账本操作 crctl 子命令化）的前置。
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-04T12:00:00+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-04T12:00:00+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-04T12:00:00+08:00"
target-version: tbd
source: "docs/analysis/CR-2026-012-合并回写归档复盘.md §3.1 T1-full"
status: drafting
created: "2026-08-04T12:00:00+08:00"
updated: "2026-08-04T12:00:00+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - role: requirement
    from: ""
    to: Ray
    at: "2026-08-04T12:00:00+08:00"
    reason: initial-assignment
  - role: development
    from: ""
    to: Ray
    at: "2026-08-04T12:00:00+08:00"
    reason: initial-assignment
  - role: test
    from: ""
    to: Ray
    at: "2026-08-04T12:00:00+08:00"
    reason: initial-assignment
handover-history: []
---

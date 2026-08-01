---
id: CR-2026-005
title: 治理工具链补丁 — delivery/task 回写一致性门禁 + writeback-tasks 原子化 Skill
summary: >-
  CR-2026-003 归档收尾核对时发现：delivery/task 回写（拷任务文件 + 更新全局索引）是
  纯手工步骤，无 skill 承载、无 gate 校验，导致 CR-2026-003 的 3 项任务被拷了文件但漏登
  _index.yaml（直到 CR-2026-004 归档时才偶然发现并补registered）。本 CR 治理这一空白：
  ① gates.json 在 archived 门禁新增一条 passCondition，交叉核对每个 CR 的
  tasks/_index.yaml（status=done）与全局 delivery/task/_index.yaml 是否一致，
  不一致则拒绝归档（检测控制/安全网）；② 新增 writeback-tasks skill，把拷文件、
  写 frontmatter、更新索引三个动作收进一次原子调用，消除手工同步出错的可能
  （预防控制/治本）。两层均沿用现有声明式 gate 与 skill 模式，不引入新架构。
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-01T13:00:00+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-01T13:00:00+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-01T13:00:00+08:00"
target-version: "0.12.1"
source: "CR-2026-004 归档收尾核对发现的治理工具链空白（delivery/task 回写无 skill 无 gate）"
status: tech-designing
created: "2026-08-01T13:00:00+08:00"
updated: "2026-08-01T13:00:00+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - role: requirement
    from: ""
    to: Ray
    at: "2026-08-01T13:00:00+08:00"
    reason: initial-assignment
  - role: development
    from: ""
    to: Ray
    at: "2026-08-01T13:00:00+08:00"
    reason: initial-assignment
  - role: test
    from: ""
    to: Ray
    at: "2026-08-01T13:00:00+08:00"
    reason: initial-assignment
handover-history: []
---

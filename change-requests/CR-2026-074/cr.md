---
id: CR-2026-074
title: AI First tools：新 KB 初始化与首次回写兼容方案
summary: "提供显式 crctl kb init 初始化新 KB，支持首次回写缺少 specs/_index.yml 时安全首写，并修正 traceability 对 plan 两张稳定表及 repositories trunk 的解析；同步 worktree 自忽略、使用文档与 controlled-shell 裸提交祖先判定能力。复用现有事务和 CAS，不改变状态机、gates、Pipeline、Agent、注册核心或 multica 代码，按自动化验收发布 tools 修复版。"
owner: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
owners:
  requirement:
    id: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
    assigned-at: "2026-09-30T21:33:16+08:00"
  development:
    id: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
    assigned-at: "2026-09-30T21:33:16+08:00"
  test:
    id: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
    assigned-at: "2026-09-30T21:33:16+08:00"
target-version: 0.47
target-spec-id: ai-first-platform
source: manual
origin: ""
status: tech-design-review-pending
created: "2026-09-30T21:33:16+08:00"
updated: "2026-09-30T23:43:06+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: a0e71a32-509d-4ee9-aea4-d086a5b1ff93, at: "2026-09-30T21:33:16+08:00", reason: initial-assignment }
  - { role: development, from: "", to: a0e71a32-509d-4ee9-aea4-d086a5b1ff93, at: "2026-09-30T21:33:16+08:00", reason: initial-assignment }
  - { role: test, from: "", to: a0e71a32-509d-4ee9-aea4-d086a5b1ff93, at: "2026-09-30T21:33:16+08:00", reason: initial-assignment }
handover-history: []
---

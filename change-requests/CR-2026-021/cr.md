---
id: CR-2026-021
title: 治理工具链 — prompt 对齐 crctl（写入面补齐 S1~S5+inbox-emit + prompt 分阶段收敛 + lint-prompts 漂移防线）
summary: >-
  crctl（CR-2026-019 账本子命令 / CR-2026-020 回写脚本 / FR-2/4/5/8）与 PreToolUse guard 的
  能力跑在了 prompt 前面：guard deny 锁死 _backlog.yml/review-annotations/approval.yml 等
  受控文件，但 crctl 无对应写口 → "guard 锁死但无工具出口"的孤儿写入；20+ SKILL/pipeline
  prompt 仍手把手教手动操作（手写 approval.yml、裸 git、cr-status-set、merge-commits 6 字段
  校验等）。按 docs/analysis/tools包-prompt对齐crctl-修改方案.md 落地：① Phase 0 crctl 新增
  6 个受控白名单写子命令（review-record / review-note / checkpoint-add / owner-set /
  backlog-set / inbox-emit，purpose-specific + 前置态守卫 + CAS + 审计，不做通用 patch，
  S1 review-record 判断/写入分离 + stage→文件名显式映射含 tech-design→sdd.yml）；
  ② Phase 1~4 分阶段把 SKILL/pipeline prompt 收敛为调用 crctl（D7 merge-commits 3 字段、
  approve-* 折叠为 crctl approve、裸 git→crctl git、cr-status-set 清退、账本写入改走新子
  命令、resume-* 状态映射收敛为 crctl next）；③ 根治机制：lint-prompts 漂移 linter（R1~R6
  规则直接读 rules.json/crctl.mjs 源码判据，不做派生快照）+ pre-commit 与 feature-writeback
  gate 两层机械防线 + 回写清单人工残余项（diff 触及 crctl.mjs dispatch 或 rules.json deny 面
  即触发）。落点：tools 仓 crctl.mjs + test/ + skills/ + pipeline-templates/ +
  scripts/lint-prompts.mjs。里程碑 T1.3。
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-05T09:37:00+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-05T09:37:00+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-05T09:37:00+08:00"
target-version: tbd
source: "docs/analysis/tools包-prompt对齐crctl-修改方案.md"
status: drafting
created: "2026-08-05T09:37:00+08:00"
updated: "2026-08-05T09:37:00+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - role: requirement
    from: ""
    to: Ray
    at: "2026-08-05T09:37:00+08:00"
    reason: initial-assignment
  - role: development
    from: ""
    to: Ray
    at: "2026-08-05T09:37:00+08:00"
    reason: initial-assignment
  - role: test
    from: ""
    to: Ray
    at: "2026-08-05T09:37:00+08:00"
    reason: initial-assignment
handover-history: []
---

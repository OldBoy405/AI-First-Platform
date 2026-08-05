---
id: CR-2026-021
title: 治理工具链 — prompt 对齐 crctl（写入面补齐 S1~S11+inbox-emit + prompt 分阶段收敛 + lint-prompts 漂移防线 + D13 溯源）
summary: >-
  crctl（CR-2026-019 账本子命令 / CR-2026-020 回写脚本 / FR-2/4/5/8）与 PreToolUse guard 的
  能力跑在了 prompt 前面：guard deny 锁死 _backlog.yml/review-annotations/approval.yml 等
  受控文件，但 crctl 无对应写口 → "guard 锁死但无工具出口"的孤儿写入；20+ SKILL/pipeline
  prompt 仍手把手教手动操作（手写 approval.yml、裸 git、cr-status-set、merge-commits 6 字段
  校验等）。按 docs/analysis/tools包-prompt对齐crctl-修改方案.md 落地（范围更新：D9~D16
  并入本轮单轮做完，不再拆下一轮）：① Phase 0 crctl 新增 12 项子命令面（S1~S11 +
  inbox-emit：9 个写子命令 review-record / review-note / checkpoint-add / owner-set /
  backlog-set / next-cr-id / task allocate / cr-init / inbox-emit + 2 个只读子命令
  worktree-path / report+cr-metrics + 1 处既有 git commit 扩展 --template，purpose-specific
  + 前置态守卫 + CAS + 审计，不做通用 patch；S6/S8 同属注册流程相邻两步，合并实现共享
  casWrite 事务；S1 review-record 判断/写入分离 + stage→文件名显式映射含 tech-design→
  sdd.yml）；D13（PRD/SDD schema validator v0.4.0 下线）先溯源调查再定复活/不复活，为
  Phase 0 Step 0 门槛任务。② Phase 1~4 分阶段把 SKILL/pipeline prompt 收敛为调用 crctl
  （D7 merge-commits 3 字段、approve-* 折叠为 crctl approve、裸 git→crctl git、
  cr-status-set 清退、账本写入改走新子命令，并扩至注册链路 requirement-register→S6/S8/
  S9/S10、write-dev-tasks→S7/S10、cr-dashboard→S11）。③ 根治机制：lint-prompts 漂移
  linter（R1~R6 规则直接读 rules.json/crctl.mjs 源码判据，不做派生快照）+ pre-commit 与
  feature-writeback gate 两层机械防线 + 回写清单人工残余项（diff 触及 crctl.mjs dispatch 或
  rules.json deny 面即触发）。落点：tools 仓 crctl.mjs + test/ + skills/ +
  pipeline-templates/ + scripts/lint-prompts.mjs。里程碑 T1.3。
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
status: code-reviewing
created: "2026-08-05T09:37:00+08:00"
updated: "2026-08-05T10:11:00+08:00"
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

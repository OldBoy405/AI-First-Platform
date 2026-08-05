---
id: CR-2026-022
title: 治理工具链 — tools 包 prompt 审查修复（命令串畸形 12 处 + inbox-emit 接口对齐 + UUID 撞号 + lint R6/R7 护栏 + 冗余收敛）
summary: >-
  tools 包 prompt 审查（docs/analysis/prompt-audit-report-2026-08-05.md，75 条发现）修复实施：
  批 1 零风险机械修正（crctl advance 命令串畸形 12 处 + frontmatter 注释外移 + tools/old 死引用
  + knowledge-agent 死路径）；批 2 死内容清理（cr-status-set 下线、validate-doc 死维度、
  focus-briefing/report-to-planning-suggestion 反向修、agents/_index.yml pending 清空）；
  批 3 功能修复（inbox-emit 接口对齐含 owner-handover 三处枚举同步、architecture-design
  pipeline UUID 5 节点迁移含 repairNodeId、market-insights 索引统一、sync 手写 owner 改调
  crctl owner-set）；批 3.5 lint-prompts 补 R6/R7 规则与测试向量（先于批 4 落地）；批 4 冗余
  收敛（approve-* 先对齐、writeback 三兄弟抽 shared、sync 免责收敛 + bucket 改调 crctl
  worktree-path、agents/_index.yml constraints 删除、pipeline push-progress 样板抽取）。
  收尾同步三台账 + check-skill-matrix.mjs + pipeline JSON 解析自检。落点 tools 仓 skills/ +
  pipeline-templates/ + agents/ + scripts/lint-prompts.mjs。
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-05T23:32:54+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-05T23:32:54+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-05T23:32:54+08:00"
target-version: tbd
source: "docs/analysis/prompt-audit-report-2026-08-05.md"
status: drafting
created: "2026-08-05T23:32:54+08:00"
updated: "2026-08-05T23:32:54+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-08-05T23:32:54+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-08-05T23:32:54+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-08-05T23:32:54+08:00", reason: initial-assignment }
handover-history: []
---

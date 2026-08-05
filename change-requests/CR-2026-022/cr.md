---
id: CR-2026-022
title: 治理工具链 — tools 包 prompt 审查修复（97 条发现：批 2.5 crctl 核心缺陷修复 + checkpoint-add 承诺兑现 + approve 驳回回退 + lint R6/R7 与豁免修复 + 冗余收敛）
summary: >-
  tools 包 prompt 审查（docs/analysis/prompt-audit-report-2026-08-05.md，97 条发现
  = 原稿 75 + CR-2026-022 注册实录补 4 + 7 条流水线执行走查补 18）修复实施：
  批 1 零风险机械修正（crctl advance 命令串畸形 12 处 + frontmatter 豁免注释外移
  + tools/old 死引用 + knowledge-agent 死路径 + 编号/措辞订正）；批 2 死内容清理
  （cr-status-set 下线、validate-doc 死维度、focus-briefing 反向修、
  report-to-planning-suggestion 降级路径、agents/_index.yml pending 清空、
  record-adr 评估下线）；批 2.5 crctl 核心能力补齐（一次设计评审过 ARCHITECTURE.md §8：
  cr-init 补 --summary/--source/--target-version 旗标并删 cr_id 死参数、--template
  补显式 --cr 旗标、checkpoint-add LEGAL 白名单扩至全部非终态 + push-progress Step 3
  改逐仓调用 + 节点 12 补齐描述 + onFail 改可见告警、cmdApprove decline 分支执行
  {stage}:reject 回退转换含需求阶段驳回转换决策、review-loop 死配置处置、
  requirement-register Step 5 fetch 失败 STALE_BASE 降级）；批 3 功能正确性修复
  （inbox-emit 接口对齐含 owner-handover 三处枚举同步、merge-feature-branch 本地/远端
  HEAD 一致性校验、write-competitive-report 写入目标订正 + 两阶段确认挪到审批后、
  architecture-design pipeline UUID 5 节点迁移含 repairNodeId、market-insights 索引
  统一、sync 手写 owner 改调 crctl owner-set、cmdNext/cr-show/planning 域歧义订正）；
  批 3.5 lint-prompts 补 R6/R7 规则并修复豁免注释整段生效 bug + 测试向量（先于批 4）；
  批 4 冗余收敛（approve-* 先对齐、writeback 三兄弟抽 shared、sync 免责收敛 + bucket
  改调 crctl worktree-path、agents constraints 删除、pipeline push-progress 样板抽取
  以批 2.5 修对为前提、write-insight-brief/run-competitive-analysis 等评估合并下线）。
  收尾同步三台账 + check-skill-matrix.mjs + pipeline JSON 解析自检 + crctl.test.mjs
  全量回归。落点 tools 仓 skills/ + pipeline-templates/ + agents/ + scripts/crctl.mjs
  + lint-prompts.mjs + gates.json。
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
status: requirement-approved
created: "2026-08-05T23:32:54+08:00"
updated: "2026-08-06T06:56:50+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-08-05T23:32:54+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-08-05T23:32:54+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-08-05T23:32:54+08:00", reason: initial-assignment }
handover-history: []
---

---
id: CR-2026-020
title: 治理工具链 — writeback 机械步骤固化为入库脚本（三脚本 + SKILL 改调 + 删 writeback-backups + traceability 单一权威）
summary: >-
  CR-2026-019 实测 writeback 流水线约 30 min，其中"造工具/调试"约 20 min（占三分之二）：
  writeback-prd-sdd / writeback-tasks / writeback-traceability 三个节点的机械步骤仍靠
  会话内现写一次性脚本与试错（docs/product/writeback-流水线耗时分析与优化方案.md，平台级
  治理文档，本 CR 按其 §7 落地建议立项）。范围：三节点机械步骤固化为 tools/skills/shared/
  scripts/ 下版本化独立脚本（specs/_index.yml、delivery/task/_index.yaml、traceability.yml
  类全量重建天然幂等；PRD/SDD 里程碑节保留锚点追加、锚点唯一性断言硬失败；带 dry-run +
  末尾自检），三份 SKILL.md 改为"调用脚本 + 核对 dry-run diff"并补充已核实事实基线
  （里程碑命名/索引格式/参与仓规则）；删除 writeback-backups 备份步骤（git commit 即备份）、
  收敛双份 traceability.yml 为 specs 侧单一权威文件。不做成 crctl 子命令、不接入 CAS 审计
  基础设施（git 即其 CAS），不含状态机与账本结构改动。验收指标：下一个走完整 writeback 的
  CR 流水线耗时 ≤15 min、回写环节零脚本调试循环（基线 CR-2026-019：30 min / 三次调试循环）。
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-04T21:38:00+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-04T21:38:00+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-04T21:38:00+08:00"
target-version: tbd
source: "docs/product/writeback-流水线耗时分析与优化方案.md"
status: drafting
created: "2026-08-04T21:38:00+08:00"
updated: "2026-08-04T21:38:00+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - role: requirement
    from: ""
    to: Ray
    at: "2026-08-04T21:38:00+08:00"
    reason: initial-assignment
  - role: development
    from: ""
    to: Ray
    at: "2026-08-04T21:38:00+08:00"
    reason: initial-assignment
  - role: test
    from: ""
    to: Ray
    at: "2026-08-04T21:38:00+08:00"
    reason: initial-assignment
handover-history: []
---

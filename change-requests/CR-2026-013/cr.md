---
id: CR-2026-013
title: P3 组织智能 CR-A — AI 成熟度看板数据地基与前端（E1+E2）
summary: >-
  P3 组织智能第一个 CR（交付切分 CR-A，唯一硬前置）：① E1 数据地基——department 表 +
  成员归属 + maturity-config.yaml 版本化配置 + maturity_snapshot 快照表 +
  每日 00:30 水位线增量 rollup 任务（照抄 task_usage_rollup_state 模式）。
  ② E2 看板前端——主应用新 route 复用 packages/views 体系：日期区间选择 +
  统计条（活跃成员/Token 总消耗/可选估算成本）+ Token 趋势图（可下钻部门/个人/项目/模型）+
  排名区（部门/个人 Tab，个人榜默认关闭）+ 五维雷达图（AIF/SII/OFI/EPC/ACM 总分 +
  子指标卡片 + 环比箭头）+ 治理板块（门禁一次通过率/证据漂移/追溯完整率/越权尝试）+
  隐私与反 Goodhart 约束（个人排名 Owner 显式开启且全员可见、数量指标与质量护栏强制同屏）。
  不做：独立子域名 iframe（内部平台无隔离发布需要）、精确成本核算（token × 价目表估算，
  UI 明确标注"估算"）。
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-04T06:52:00+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-04T06:52:00+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-04T06:52:00+08:00"
target-version: "0.20"
source: "docs/product/P3-组织智能设计.md §1（E1+E2）"
status: drafting
created: "2026-08-04T06:52:00+08:00"
updated: "2026-08-04T06:52:00+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - role: requirement
    from: ""
    to: Ray
    at: "2026-08-04T06:52:00+08:00"
    reason: initial-assignment
  - role: development
    from: ""
    to: Ray
    at: "2026-08-04T06:52:00+08:00"
    reason: initial-assignment
  - role: test
    from: ""
    to: Ray
    at: "2026-08-04T06:52:00+08:00"
    reason: initial-assignment
handover-history: []
---

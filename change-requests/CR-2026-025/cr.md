---
id: CR-2026-025
title: crctl 守卫与回显收敛（check-skill-matrix external 引用校验 + depends-on 依赖守卫 + gate/advance blockers 回显截断）
summary: "合并三项独立漂移治理项，统一交付：① D-2（源自方案 v2.6 §7）check-skill-matrix.mjs 新增规则——agent-skill-matrix.yml 的 external 声明必须能在对应 SKILL.md/prompt 中找到真实引用点，零引用视为死声明报警，防止 CR-2026-024 修复的『声明蒸发』失效模式复发；② D-5（源自方案 v2.6 §4.8/§7）crctl task done 新增依赖守卫——写 TASK status=done 前校验其 depends-on 列出的前置 TASK 均已 done，把 implement-code 现有的 prompt 层拓扑排序建议升级为机械强制，未提供覆盖时报 DEPENDS_ON_NOT_DONE 拒绝写入；③ gate/advance blockers 回显截断（源自 CR-2026-024 SDD 评审过程实测发现）——evaluatePassCondition 对 isEmpty 失败条件的 actual/why 全量序列化 blockers 长文本，advance 失败路径经 FR-5 摘要再抬一次，同一 payload 三份落地；改为 actual 逐项截断（ITEM_MAX=120 字符，保留数组类型与 file 指针）、why/message 只给条数，全量原文以 file 字段指向的 review-annotations/{stage}.yml 为唯一来源。三项均为 crctl.mjs/check-skill-matrix.mjs 本体改动 + 各自测试向量，不改状态机、不改 owns/can-call 数据模型，符合 crctl 类改动的最小交付单元定义（对齐 CR-2026-021/022 交付粒度先例）。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-08T21:07:25+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-08T21:07:25+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-08T21:07:25+08:00"
target-version: tbd
source: "docs/analysis/端到端Pipeline最佳实践技能整合方案.md v2.6 §7（D-2/D-5）+ CR-2026-024 SDD 技术评审实测发现（gate 回显冗余）"
status: task-breakdown
created: "2026-08-08T21:07:25+08:00"
updated: "2026-08-08T21:07:25+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-08-08T21:07:25+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-08-08T21:07:25+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-08-08T21:07:25+08:00", reason: initial-assignment }
handover-history: []
---

---
id: CR-2026-022-TASK-18
type: TASK
cr-ref: CR-2026-022
plan-ref: "change-requests/CR-2026-022/plan.md"
sdd-ref: "change-requests/CR-2026-022/sdd.md"
title: 批 4 — write-insight-brief/run-competitive-analysis 合并下线 + list-remote 去重 + 跳过检查单份化（FR-32）
slug: skill-retire
status: pending
estimate: 6h
depends-on: [CR-2026-022-TASK-15]
assignee: ""
created: "2026-08-06T08:30:00+08:00"
---

## 任务描述

FR-32（2.3 流水线走查新增评估项 + D-3 后两项决策定案）：write-insight-brief 与 run-competitive-analysis 合并后下线；list-remote-checkpoints/resume-from-remote 存在性校验去重；product-planning 四调研节点跳过检查单份化。

## 涉及文件 / 模块

- `skills/planning/write-insight-brief/SKILL.md` → 下线（PRD §1.3 决策：唯一增量 ≤800 字约束与 `raw→briefed` 状态推进并入 `skills/planning/extract-market-insight/SKILL.md` 附加区块；与 TASK-12 schema 对齐协同）
- `skills/planning/run-competitive-analysis/SKILL.md` → 下线（Step4「规划启示摘要」并入 `skills/planning/write-planning-report/SKILL.md`「市场与竞品信号」章节）
- `skills/cr/list-remote-checkpoints/SKILL.md` vs `skills/sync/resume-from-remote/SKILL.md`：存在性校验去重（resume-from-remote 复用 list-remote-checkpoints 已产出的结论，不重复 ls-remote 预检；保留 checkpoints[] SHA 漂移告警增量）
- `pipeline-templates/product-planning.pipeline.json` 四调研节点 + 对应 SKILL.md：「若 skip_X=true 则输出 SKIPPED 并 return」逻辑只在 SKILL.md 保留一份，pipeline node prompt 改引用
- 台账同步：`skills/_index.yml` 删两下线条目（若批 2 record-adr 同批删，统一引用计数复核）

## 实现要点

1. 下线前引用计数复核（grep 全仓 ref + matrix + _index.yml），证据入 commit message
2. write-insight-brief 的增量能力（≤800 字/状态推进）必须先并入 extract-market-insight 再删，防功能丢失
3. run-competitive-analysis 的 Step4 摘要并入 write-planning-report 后，competitive 雷达流水线三层调用链变两层（pipeline → write-competitive-report 直接）——核对 competitive-radar.pipeline.json 引用
4. resume-cr 流水线节点 1/2 职责：节点 2 不再重复做存在性预检（TASK-14 已处理 cr_id 过滤参数）

## 验收条件

1. 两下线 skill 引用计数清零（grep 全仓 + matrix 无引用）
2. extract-market-insight 含 ≤800 字约束与 briefed 状态推进；write-planning-report 含市场与竞品信号章节
3. competitive-radar.pipeline.json 引用已更新（无 run-competitive-analysis）
4. resume-from-remote 无重复 ls-remote 预检
5. product-planning 跳过检查逻辑单份化（pipeline prompt 引用而非复述）
6. check-skill-matrix.mjs 绿

## 完成标志

验收 1~6 通过 + lint 全量复扫零违例。

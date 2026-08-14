---
id: CR-2026-022-TASK-14
type: TASK
cr-ref: CR-2026-022
plan-ref: "change-requests/CR-2026-022/plan.md"
sdd-ref: "change-requests/CR-2026-022/sdd.md"
title: 批 3 — planning 域八项歧义订正（SKIPPED 文案/onFail 统一/intent-context/6 章节格式/cr_id 过滤/worktree prune/估算交叉校验）（FR-23）
slug: planning-ambiguities
status: pending
estimate: 6h
depends-on: []
assignee: ""
created: "2026-08-06T08:30:00+08:00"
---

## 任务描述

FR-23（2.4 八项流水线走查新增歧义，逐条对照报告目标形态）：

## 涉及文件 / 模块

1. `skills/planning/write-planning-report/SKILL.md`：Step1（L35）"本次调研跳过此维度" vs 错误表（L90）"数据不可用"——统一为一种占位表述（建议：部分跳过与全部跳过统一"本次调研跳过此维度"）
2. `pipeline-templates/competitive-radar.pipeline.json`（:61）与 `market-to-plan.pipeline.json`（:60）：镜像节点 `onFail` 统一 **abort**（D-3 决策）；competitive-radar 下游节点对 node-3.md 写死读取依赖标注"abort 后不会读到空文件"
3. `skills/competitive/report-to-planning-suggestion/SKILL.md`：:47 "传入 brainstorming 结论 + 产品快照"改为如实传 `intent`（=从 brainstorming 结论提炼的一句话规划意图）+ `context`（=产品快照），与 planning-draft 参数表对齐
4. `pipeline-templates/market-to-plan.pipeline.json`：:59 节点 3 输出格式描述改为 planning-draft 真实 6 章节 DESIGN-DOC 格式 + 优先级 P0-P2（现写 P0-P3 与"3-5 条建议列表"凭空发明）
5. `pipeline-templates/resume-cr.pipeline.json`：:44 单 CR 过滤改调 `list-remote-checkpoints` 全量扫描 + 本地筛选，或给 skill 补可选 `cr_id` 过滤参数并如实调用（**建议后者**：resume-cr 语义就是单 CR，补参数比改全量再筛更贴合，且改动面小）
6. `skills/sync/resume-from-remote/SKILL.md`：错误表补"worktree 元数据残留（非 already-exists，报错如 is not a valid path）"分支，指引先跑 `git worktree prune` 清理残留元数据（参照 cr-archive:130 的 Windows Filename too long 先例）
7. `skills/develop/write-dev-plan/SKILL.md`（章节 5）与 `skills/develop/write-dev-tasks/SKILL.md`（:57 estimate）：工时估算交叉校验——write-dev-tasks 生成后核对 plan.md 估算与 TASK 级求和一致，不一致给 WARN
8. `skills/requirement/requirement-register/SKILL.md` L15/60：编号重排（"完成以下三件事"列 4 项 → 改"四件事"；Step 编号连续）——已在 TASK-01 覆盖，此处核对无遗漏

## 实现要点

- 每项改动必须与报告 2.4 对应行目标形态一致；改动前 grep 核对当前行号
- 第 2 项运行时行为变更（skip→abort）在 commit message 中显式标注

## 验收条件

1. write-planning-report 全文只有一种 SKIPPED 占位表述
2. 两条镜像流水线镜像节点 onFail 均为 abort
3. report-to-planning-suggestion 含 `intent`/`context` 参数名；market-to-plan 节点 3 无 P0-P3
4. resume-cr 节点 1 调用与 list-remote-checkpoints 实际接口一致（含 cr_id 过滤参数或全量+筛选）
5. resume-from-remote 错误表含 worktree prune 指引
6. write-dev-tasks 核对 plan.md 估算逻辑（WARN 语义）

## 完成标志

验收 1~6 通过 + lint 复扫零违例。

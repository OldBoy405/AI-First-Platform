---
id: CR-2026-022-TASK-16
type: TASK
cr-ref: CR-2026-022
plan-ref: "change-requests/CR-2026-022/plan.md"
sdd-ref: "change-requests/CR-2026-022/sdd.md"
title: 批 4 — approve-* 四兄弟对齐 + writeback 三兄弟抽 shared（FR-27/28）
slug: approve-writeback-align
status: pending
estimate: 6h
depends-on: [CR-2026-022-TASK-06, CR-2026-022-TASK-15]
assignee: ""
created: "2026-08-06T08:30:00+08:00"
---

## 任务描述

FR-27（2.3 前言原则 1：先对齐不一致，不默认抽 shared）：四份 approve-* 对齐差异点。FR-28（原则 2：样板确实长才抽）：writeback 三兄弟抽「脚本执行约定」shared 片段。**前置：TASK-15（批 3.5 lint 护栏）已落地；抽 shared 前 lint 需已具备引用一致性检查能力（或本任务补上）。**

## 涉及文件 / 模块

- FR-27：`skills/develop/approve-code`、`approve-dev-start`、`approve-tech-design`、`skills/requirement/approve-requirement` 四份 SKILL.md
- FR-28：`skills/writeback/writeback-prd-sdd`、`writeback-tasks`、`writeback-traceability` 三份 SKILL.md + 新建 shared 片段（落点先例：`skills/shared/` 组内）

## 实现要点

1. FR-27：删 approve-dev-start 独有的「前置条件」节与「读取 AGENTS.md/dir-graph.yaml 解析路径」段（其余三个 approve 都没有，且与 crctl approve 门禁校验重复）；四者「3 步执行 + 错误处理表」对齐到一致结构（仅 stage/status 名不同）；对齐后若样板仍长，评估抽 `shared/approve-common`（不默认抽）
2. FR-28：「机械步骤由入库脚本执行」段 + `crctl git commit --template writeback` 骨架 + BAD_ARGS/CR_STATUS_MISMATCH/SELF_CHECK_FAILED 错误表抽为一处 shared 引用；三兄弟改引
3. 抽 shared 后：lint 补「引用是否仍指向真实 shared 片段」一致性检查（FR-24 前置要求，若 TASK-15 未含则本任务补）

## 验收条件

1. 四份 approve-* 结构一致（diff 仅 stage/status 差异）
2. writeback 三兄弟引用同一 shared 片段且 lint 引用一致性检查通过
3. 三兄弟行为等价（回写脚本自检回归通过）
4. lint 全量复扫零违例

## 完成标志

验收 1~4 通过 + writeback.test.mjs（若有）回归绿。

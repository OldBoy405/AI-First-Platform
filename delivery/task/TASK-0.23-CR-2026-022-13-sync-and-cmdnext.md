---
spec-id: ai-first-platform
version: "0.23"
id: CR-2026-022-TASK-13
type: TASK
cr-ref: CR-2026-022
plan-ref: "change-requests/CR-2026-022/plan.md"
sdd-ref: "change-requests/CR-2026-022/sdd.md"
title: 批 3 — sync owner-set 改调 + cmdNext writing-back 修正 + cr-show 收敛（FR-20~22）
slug: sync-and-cmdnext
status: pending
estimate: 6h
depends-on: []
assignee: ""
created: "2026-08-06T08:30:00+08:00"
---

## 任务描述

FR-20（2.1-E）：sync 手写 owner 变更改调 `crctl owner-set`（正确性缺陷：绕过唯一写入口）。FR-21（2.4）：`cmdNext` writing-back 分支误判修复（读开发期工作稿而非 writeback 产物）。FR-22：cr-show 删硬编码映射表改调 `crctl next`。

## 涉及文件 / 模块

- `skills/sync/handover-cr/SKILL.md`：Step3/Step4 手写 owners 段改调 `crctl owner-set`
- `skills/sync/resume-from-remote/SKILL.md`：Step4 owner 更新逻辑改调 `crctl owner-set`
- `skills/shared/crctl/scripts/crctl.mjs`：`cmdNext`（:2219-2222）writing-back 分支
- `skills/cr/cr-show/SKILL.md`：L91-110 硬编码映射表删除，改调 `crctl next`

## 实现要点

1. FR-20：两文件删除手写 `owners.{role}.id`/`assigned-at`/`owner-history`/`handover-history`/`_backlog` 同步的描述，统一为「经 `crctl owner-set <cr> --role <r> --id <id>` 变更」（与 description L3 承诺一致）
2. FR-21（SDD §4.6）：`case 'writing-back'` 改为从文件系统推断 spec_id——扫描 `specs/` 子目录，唯一目录取其名并检查 `specs/{name}/traceability.yml` 存在性；0 个或多于 1 个子目录时输出"无法唯一确定 spec_id，先完成 PRD/SDD 回写"；`_backlog` 无 spec-id 字段（已核实），不可从账本读
3. FR-22：cr-show 删硬编码表（只覆盖到 code-approved 的旧表），改调 `crctl next`；resume-cr.pipeline.json 若有重复映射一并核对

## 验收条件

1. handover-cr/resume-from-remote 无手写 owners 字段编辑指引
2. `crctl next` 在 writing-back 态：specs/ 唯一目录且 traceability.yml 存在 → 建议 cr-archive；不存在 → 建议回写；多目录 → 显式报错不猜
3. cr-show 无硬编码 status 映射表
4. cmdNext 相关 crctl.test.mjs 用例（三分支）通过

## 完成标志

验收 1~4 通过 + crctl.test.mjs 全量绿。

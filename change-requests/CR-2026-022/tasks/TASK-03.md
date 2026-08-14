---
id: CR-2026-022-TASK-03
type: TASK
cr-ref: CR-2026-022
plan-ref: "change-requests/CR-2026-022/plan.md"
sdd-ref: "change-requests/CR-2026-022/sdd.md"
title: 批 2.5 — cr-init 补 --summary/--source/--target-version 旗标 + 删 cr_id 死参数（FR-9）
slug: cr-init-field-flags
status: pending
estimate: 5h
depends-on: []
assignee: ""
created: "2026-08-06T08:30:00+08:00"
---

## 任务描述

FR-9（2.1-F）：cr-init 补三个可选旗标，注册时一次原子写齐 summary/source/target-version，消灭「模型不得手写 cr.md」与「字段无路可写」的矛盾；删 requirement-register 的 cr_id 僵尸参数。触发 ARCHITECTURE.md §8 评审门槛（已随本 CR SDD 过审）。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`：`cmdCrInit`（约 :1711-1751）与 `_backlog` 条目生成段
- `skills/requirement/requirement-register/SKILL.md:28`：删 `cr_id` 参数与对应格式/占用校验

## 实现要点（SDD §2.1/§4.1）

1. 新增旗标：`--summary <s>`（缺省 `""`）、`--source <s>`（缺省 `manual`）、`--target-version <v>`（缺省 `tbd`），缺省值与现硬编码同义、向后兼容
2. summary 写入 cr.md frontmatter 时引号包裹 + `"` 转义（与 title 同款 `replaceAll('"','\\"')`）；source/target-version 同步写 `_backlog` 条目对应字段
3. 三字段与 owners/时间戳同一次 `casWriteMulti` 事务（cr.md + `_backlog.yml` + `_index.yml`）
4. `BACKLOG_SET_FIELDS` **不扩**（三字段属注册一次性写入，不是后续可 set 的标量字段）
5. `requirement-register/SKILL.md`：参数表删 `cr_id`「仅预览/校验用途」行及其 Step 1 的对应校验描述（cr-init 内部 `scanMaxCrNumber+1` 是权威分配）

## 验收条件

1. `crctl cr-init --title T --owner-requirement Ray --summary S --source X --target-version v` 一次写齐三字段（cr.md + _backlog 均正确）
2. 不带新旗标调用与旧行为完全一致（缺省值）
3. summary 含 `:` 或 `"` 时 YAML 不破坏
4. requirement-register 参数表无 cr_id

## 完成标志

验收 1~4 通过 + `crctl.test.mjs` 新增三旗标用例（缺省兼容/覆写/转义）全绿 + 既有注册相关用例不回归。

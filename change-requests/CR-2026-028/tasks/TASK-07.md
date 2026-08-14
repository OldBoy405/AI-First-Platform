---
id: CR-2026-028-TASK-07
type: TASK
cr-ref: CR-2026-028
plan-ref: "change-requests/CR-2026-028/plan.md"
sdd-ref: "change-requests/CR-2026-028/sdd.md"
title: Registration 复用 cr-init 一次传齐元数据（M5）
slug: registration-reuse-cr-init
status: pending
estimate: 4h
depends-on: [CR-2026-028-TASK-05, CR-2026-028-TASK-06]
created: "2026-08-10T18:10:38+08:00"
---

# TASK-07 Registration 复用 cr-init 一次传齐元数据

## 1. 任务描述

将 `requirement-register` 的建档调用改为一次传齐全部注册元数据（title/owner/summary/source/target-version/year），删除“建档后手工补 frontmatter”二次写步骤；合并 `requirement-authoring.pipeline.json` node-1 中重复的 cr-init 描述。FR-6。

## 2. 涉及文件 / 模块

- tools 包 `skills/requirement/requirement-register/SKILL.md`（Step 2 建档指令）
- tools 包 `pipeline-templates/requirement-authoring.pipeline.json`（node-1 prompt）

## 3. 实现要点

- SDD §3.4 调用契约：

  ```text
  crctl cr-init --title "{title}" --owner-requirement {owner}
    [--year Y] --summary "{summary}" --source {source} --target-version {v} --workspace <ws>
  ```

- `cr-init` 本身零改动（已支持全部旗标，B-6 核实）；只改调用方提示词。
- 删除 Step 2 中“建档后直接补全 cr.md frontmatter”指令；合并 pipeline node-1 两段重复描述为一段。
- 不改变 registration 输出文件集（cr.md + _backlog.yml 条目 + worktree 派生）。

## 4. 验收条件

1. 按修订后提示词执行注册，cr.md frontmatter 的 `summary`/`source`/`target-version` 与注册输入一致（AC-11/AC-12）。
2. 提示词中无“建档后手工补 frontmatter”残留；node-1 prompt 无重复 cr-init 描述。
3. `cr-init` 命令本身无 diff（零改动验证）。

## 5. 完成标志

验收 1-3 全过 + commit 完成。

## 6. 接口契约

- **消费**：TASK-05/06 产出的 `{TOOLS_ROOT}` 路径表达。
- **产出**：
  - `crctl cr-init` 完整旗标调用形态（title/owner-requirement/year/summary/source/target-version/workspace），全部为既有旗标，无新旗标。
  - 下游 TASK-09 的 cr-init metadata 测试以此契约为准。

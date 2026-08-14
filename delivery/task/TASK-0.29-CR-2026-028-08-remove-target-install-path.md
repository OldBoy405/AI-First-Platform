---
spec-id: ai-first-platform
version: "0.29"
id: CR-2026-028-TASK-08
type: TASK
cr-ref: CR-2026-028
plan-ref: "change-requests/CR-2026-028/plan.md"
sdd-ref: "change-requests/CR-2026-028/sdd.md"
title: 删除 target_install_path 与 multica 台账核账（M6）
slug: remove-target-install-path
status: pending
estimate: 2h
depends-on: [CR-2026-028-TASK-05]
created: "2026-08-10T18:10:38+08:00"
---

# TASK-08 删除 target_install_path 与 multica 台账核账

## 1. 任务描述

删除 tools 包 `dir-graph.yaml` 中无消费点的 `workspace.target_install_path`（FR-7），同步修订“固定挂载到 tools/”描述；核对 multica `CUSTOM.md` 台账与注册期登记一致（FR-8，登记已随注册提交，本 TASK 只核账不改码）。

## 2. 涉及文件 / 模块

- tools 包 `dir-graph.yaml`：删除 `target_install_path`，修订 `workspace` 段描述
- multica 仓 `CUSTOM.md`：核账（对照其当时实际结构，纪律 #10）；如发现漏登则补登

## 3. 实现要点

- SDD §2.1：`workspace.tools_package_path` 成为唯一安装声明；确认无代码消费 `target_install_path`（实施前已核实无消费点）。
- 修订描述时不得引入新的安装位置声明；`tools_package_path` 值 `"tools/"` 语义不变（本 CR 不动 tools 包自己的安装挂载点，那是知识库侧声明的）。
- multica 核账：对照 CUSTOM.md 现有表格结构与本 CR 相关登记条目（编号、原因、CR/TASK 引用）。

## 4. 验收条件

1. tools `dir-graph.yaml` grep 无 `target_install_path`；`workspace` 段描述无“固定挂载到 tools/”旧口径残留。
2. `rg target_install_path` 全 tools 包零命中（含提示词/测试）。
3. multica `CUSTOM.md` 已含本 CR 登记；如缺失则本 TASK 补登并 commit。

## 5. 完成标志

grep 零命中 + 台账核账结论记录（或补登提交）+ commit 完成。

## 6. 接口契约

- **消费**：无（纯删除/核账任务）。
- **产出**：无新 API；`dir-graph.yaml#workspace` 契约面收窄为仅 `tools_package_path`。

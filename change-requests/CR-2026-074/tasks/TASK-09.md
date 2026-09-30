---
id: CR-2026-074-TASK-09
type: TASK
cr-ref: CR-2026-074
plan-ref: "change-requests/CR-2026-074/plan.md"
sdd-ref: "change-requests/CR-2026-074/sdd.md"
target-version: 0.47
title: 说明/命令发现/计数同步
slug: docs-command-discovery-counts
status: pending
estimate: 3h
depends-on: [CR-2026-074-TASK-01, CR-2026-074-TASK-03, CR-2026-074-TASK-04, CR-2026-074-TASK-05, CR-2026-074-TASK-06, CR-2026-074-TASK-07, CR-2026-074-TASK-08]
created: 2026-10-01T00:55:00+08:00
---

## 任务描述

按 SDD §8 表逐行同步说明文档、命令发现集合与测试计数（FR-8；AC-09），使文档事实与代码事实一致且不互相代替。

## 涉及文件 / 模块

- `skills/shared/crctl/SKILL.md`（dep-20）— 能力表增 kb init；workspace 必填，只有该入口可在无 change-requests 下引导；删 cwd 向上探测说法；写完整成功/失败边界。
- `skills/requirement/requirement-register/SKILL.md`（dep-21）— 加 WORKSPACE_NOT_FOUND/REPO_GRAPH_NOT_FOUND/TOOLS_PACKAGE_NOT_FOUND 引导：人先提供最小 dir-graph、运行显式 kb init；Skill 不自动代跑、不重复注册；补 source 默认空串说明与历史指纹冲突边界。
- `README.md`（dep-23）— 简短"新 KB 先写 dir-graph → 显式 kb init"入口（§1/§4），说明不是新 Pipeline/Skill，不改变八条 Pipeline。
- `docs/QODER-使用指南.md`（dep-24）— 删除 backlog/CR index/specs index/delivery task index 四模板（63–102 行台账模板段）；六种 docs 索引模板（product-planning/competitive/market-insights/feedback/ideas/tech-notes）原文保留；示例补 tools_package_path、KB/code role 与声明 trunk，不写本机路径。
- `skills/shared/crctl/scripts/crctl.mjs` — 代码 HELP 追加 `kb init`（与 TASK-01 同文件顺序编辑）。
- `skills/shared/crctl/scripts/test/caller-contract.test.mjs`（dep-19）— `TWO_WORD`/`CR_DATA_FIRST_WORDS` 两集合加 kb；缺根/空根与文档入口契约用例。
- `skills/shared/crctl/scripts/test/gate-registry.json` — 按新增入口相关用例实际计数同步（不动门禁定义）。

## 实现要点

- 各文档绑定自身事实源（dep-20/21/23/24 与代码分别核验修订），不互相代替；`skills/shared/controlled-shell/SKILL.md` 已由 TASK-07 同步，本 TASK 不再改。
- writer 通用合同不改：`write-requirement-prd/SKILL.md` 的非空 source 路径校验零 diff（dep-14）。
- 不新增 active skill，不改 Agent/Pipeline/矩阵；guard deny 面不变。
- 命令发现按 dep-19 机制：TWO_WORD 组合子命令集合与 CR_DATA_FIRST_WORDS 显式根断言分类，两处同步加 kb。

## 验收条件

1. 在 tools CR worktree 执行 `node --test skills/shared/crctl/scripts/test/caller-contract.test.mjs`（证据 cmd-05）全绿：非 help 命令集合与 two-word 发现加入 kb；缺根/空根与文档入口契约断言；ordinary command 入口负测保留。
2. 执行 `node --test skills/shared/crctl/scripts/test/lint-prompts.test.mjs`（证据 cmd-06）全绿：说明与可执行命令一致；gate-registry 计数一致。
3. AC-09 文档断言：QODER 指南四手工模板消失、六种 docs 模板保留；requirement-register 引导可见且不代跑；未改状态机/gates/Pipeline/Agent/矩阵的 diff 断言。

## 完成标志

- cmd-05/cmd-06 全绿含上述断言；SDD §8 表除 ARCHITECTURE.md 行（属 TASK-10）外的各行逐行落盘。
- 文档不含本机绝对路径；diff 限上列七个文件。

## 接口契约

**消费**：TASK-01 的 kb 形态、KbInitResult 与错误码集合（文档描述与代码逐字一致：BAD_ARGS/WORKSPACE_REQUIRED/KB_INIT_PRECONDITION(reason)/KB_INIT_CONFLICT/CAS_CONFLICT/INTERNAL_ERROR/TX_GIT_FAILED(stage)）；TASK-03 的 source 默认空串语义与历史指纹冲突边界；dep-19 `TWO_WORD`/`CR_DATA_FIRST_WORDS` 两集合；dep-20/21/23/24 各文档现状。

**产出**：文档与命令发现同步事实——SKILL.md 能力表 kb init 行（workspace 必填、无 change-requests 引导、完整成功/失败边界）、`TWO_WORD` 含 kb、gate-registry 新计数、HELP 含 `kb init`；无生产签名变化（HELP 文本除外）。下游消费方 TASK-10（ARCHITECTURE 地图条目与 SKILL/README 口径一致）与 review-code 检查项引用同一事实。

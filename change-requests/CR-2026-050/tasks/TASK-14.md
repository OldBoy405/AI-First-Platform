---
id: CR-2026-050-TASK-14
type: TASK
cr-ref: CR-2026-050
plan-ref: "change-requests/CR-2026-050/plan.md"
sdd-ref: "change-requests/CR-2026-050/sdd.md"
title: FR-13 全量自检 + DD-7 提交前缀扫描断言
slug: full-self-check-acceptance
status: pending
estimate: 2h
depends-on: [CR-2026-050-TASK-07, CR-2026-050-TASK-08, CR-2026-050-TASK-09, CR-2026-050-TASK-10, CR-2026-050-TASK-11, CR-2026-050-TASK-12, CR-2026-050-TASK-13]
created: 2026-08-21T11:57:27+08:00
---

## 任务描述

收尾任务：落地 DD-7 的提交前缀扫描断言，并执行 FR-13 全量自检清单（tools 三命令 + multica check + Skill 自检），形成发布前 checklist 证据（plan §5）。

## 涉及文件 / 模块

- `tools/skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`（DD-7 提交前缀扫描断言）
- 运行验证（tools + multica 两仓），无其他代码改动

## 实现要点

1. DD-7 扫描断言：遍历 `skills/**/SKILL.md` 中所有 `Commit：` 指引，提取前缀并断言命中 `controlled-shell/rules.json` 的 commit shapes（`wip: ` / `[cr] ` / `merge(`）；读文件先 CRLF→LF 归一，匹配失败硬失败（不静默跳过）。
2. tools 三命令：JSON.parse 全量、`lint-prompts.mjs`、`pipeline-structure.test.mjs`（含本 TASK 新增断言）。
3. multica：`generate-gate-nodes.mjs --check`、`go test ./server/internal/governance/`。
4. Skill 自检清单（SDD FR-13.5）：`skills/_index.yml` 与 `agent-skill-matrix.yml` 无漂移（对比本 CR 前基线）、写入型 Skill 有 validate-doc 等价校验、Git/shell 走 controlled-shell、CR 上下文摘要统一「以 `crctl next {cr_id}` 为准」、无直接写受保护账本表述、跨行解析/哈希遵守 CRLF 归一与硬失败。
5. 核对 AC-06/AC-09/AC-10/AC-11/AC-12/AC-13 证据齐全，缺口回对应 TASK 修复。

## 验收条件

1. 前缀扫描断言对三处已修前缀（TASK-08/10/13）全绿，且能对故意构造的反例（如 `feat(`）失败。
2. 两仓全部检查命令退出 0，输出留档。
3. 全仓 `grep -rn "feat(" skills --include=SKILL.md` 的 Commit 指引零命中（除历史反例注释）。
4. 发布前 checklist（plan §5）逐项勾选完成。

## 完成标志

上述 4 条验收全部通过，并更新 `tasks/_index.yml` 本 TASK 为 done（经 `crctl task done`）。

## 接口契约

- 消费：TASK-07～13 的全部产物与各自完成标志。
- 产出：发布前 checklist 证据 + DD-7 扫描断言；本 TASK 完成即 CR 具备进入代码评审（review-code）的完整证据链。

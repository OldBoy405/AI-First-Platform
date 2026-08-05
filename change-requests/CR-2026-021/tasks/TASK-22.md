---
id: CR-2026-021-TASK-22
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: Phase 4 收尾 — D8 状态映射去重 + 冗余精简 + 回写清单新增项 + gate 切换 enforce
slug: phase4-closeout-gate-enforce
status: done
done-at: "2026-08-05T15:30:00+08:00"
estimate: 5h
depends-on: ["CR-2026-021-TASK-17", "CR-2026-021-TASK-18", "CR-2026-021-TASK-19", "CR-2026-021-TASK-20", "CR-2026-021-TASK-21"]
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

FR-20/FR-22/FR-25 + 全 CR 收尾：
- D8：`resume-cr` node-3、`resume-from-remote:99-113`、`pull-progress:64-66`、`implement-code:67` 收敛为"跑 `crctl status`（含 STATUS_DIVERGED）+ `crctl next`"，删两处重复硬编码状态表。
- 其余冗余：`feature-writeback.pipeline.json` inputs/node-2/node-3 冗长 prose 精简；`skills/_index.yml` 各 brief 补齐（含 S1~S11 全部新增/扩展子命令，与 TASK-10 呼应）；`AGENTS.md（主仓）#6` 把"cp 覆盖"危害降为历史注脚；writeback 系 brief 补提 CR-2026-020 脚本。
- **FR-25**：feature-writeback 回写清单新增一条（SDD §6 已定文案）：「本 CR 若 diff 触及 `crctl.mjs` 的 dispatch 或 `rules.json` 的 `protectedPaths.deny`：① 跑 `crctl lint-prompts` 清零 CONTRADICTS/STALE；② 对新增子命令，在 SDD『prompt 采纳影响』小节列出应改为调用它的 skill 清单并逐一改，由评审兜底。」
- **最终收尾**：全仓跑 `lint-prompts --mode report`，确认 0 CONTRADICTS/STALE-REF 后，把 `.githooks/pre-commit` 的 `lint-prompts` 步骤从 `--mode report` 切到 `--mode enforce`（本 CR 的最后一步，早切会拦死本 CR 自身开发期提交，见 plan.md 风险清单）。

## 涉及文件 / 模块

- `skills/cr/resume-cr/SKILL.md`、`skills/sync/resume-from-remote/SKILL.md`、`pull-progress/SKILL.md`、`skills/develop/implement-code/SKILL.md`
- `pipeline-templates/feature-writeback.pipeline.json`
- `skills/_index.yml`、`AGENTS.md`（主仓）
- feature-writeback 回写清单模板（若有独立文件承载，或在 pipeline node prompt 内）
- `.githooks/pre-commit`

## 实现要点

本任务是全 CR 的收敛点，必须在 TASK-17~21 全部完成后才能确认「lint-prompts 输出零漂移」这一切换 enforce 的前提条件。

## 验收条件

- AC-12（PRD）：4 处状态映射硬编码已去重；`skills/_index.yml` brief 含全部新增子命令。
- AC-15（PRD）：回写清单模板中存在该新增条目文本。
- **本 CR 最终验收**：`lint-prompts --mode report` 全仓扫描输出 0 CONTRADICTS/STALE-REF，随后 pre-commit 已切换为 `--mode enforce` 并实测一次（构造一个人为漂移的 commit 尝试）确认被拦截。

## 完成标志

全部文件修订完成；`node --test` 全套（crctl + lint-prompts）绿；pre-commit enforce 切换生效且经实测验证。

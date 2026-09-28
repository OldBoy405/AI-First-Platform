---
id: CR-2026-072-TASK-01
type: TASK
cr-ref: CR-2026-072
plan-ref: "change-requests/CR-2026-072/plan.md"
sdd-ref: "change-requests/CR-2026-072/sdd.md"
target-version: 0.45
title: 调用方迁移：全量 CR 调用点显式 --workspace 与调用形态断言
slug: caller-migration-explicit-workspace
status: pending
estimate: 4h
depends-on: []
created: 2026-09-28T23:52:00+08:00
---

## 1. 任务描述

对 tools 仓全部真实调用 crctl CR 数据读写的调用点做一次清单化迁移：所有可执行 CR 数据读写命令显式携带 `--workspace <本命令已确认的权威路径>`；无法确认权威路径的调用面不得建议无旗标调用。范围（SDD §4.1 清点面）：`agents/{requirement-writer,dev-agent,quality-reviewer-agent,delivery-agent}.md`、`pipeline-templates/*.pipeline.json`、各 `skills/**/SKILL.md`（重点 `skills/sync/push-progress/SKILL.md`、`skills/shared/crctl/SKILL.md`）、`skills/shared/crctl/adapters/claude-code/hooks/inject-cr-status.mjs`、CLI HELP、README；扫描面外 CI/workflow/脚本逐项核对并登记。README 只保留人读流程与一个正确示例。历史叙述、夹具/生成转换脚本不机械改写。安装根用于 `workspace inspect`/`register`；`status/next` 使用 inspect 返回的 operational workspace。本 TASK 先于 TASK-02 进入同一交付批次（FR-5 同批交付门：调用方先迁移，再启用 CLI 强校验）。

## 2. 涉及文件 / 模块

- `agents/*.md`（四个 CR Agent Prompt）
- `pipeline-templates/*.pipeline.json`
- `skills/develop/**/SKILL.md`、`skills/requirement/**/SKILL.md`、`skills/writeback/**/SKILL.md`、`skills/sync/push-progress/SKILL.md`、`skills/shared/crctl/SKILL.md`
- `skills/shared/crctl/adapters/claude-code/hooks/inject-cr-status.mjs`（无可信路径时不注入貌似权威的状态命令建议；有可信路径才给出带 `--workspace` 的可执行建议）
- `skills/shared/crctl/scripts/test/caller-contract.test.mjs`（`REVIEWED_CALLS` / `OUT_OF_SURFACE_CALLERS` 追加显式旗标调用形态条目）
- `README`（人读流程 + 单一正确示例）
- CI workflow（如 `.github/workflows/cr-guard.yml`）仅在实施期核实为真实调用点时调整，并在清单注明

## 3. 实现要点

- SDD §4.1：调用点清单沿用既有 `caller-contract.test.mjs` 追加调用形态检查，不另造扫描框架。
- SDD §8 表格逐行落实：Skill 从 Pipeline inspect 获取当前 CR 权威路径后传旗标；hook 只在有可信项目路径时建议显式命令。
- 双路径写命令（checkpoint/merge/writeback-apply 等）沿用 crctl 既有 `--operational-workspace` 参数语义与门禁，示例核对最终写目标与任务 operational workspace 一致。
- `workspace inspect` 以安装/项目根调用；`status/next` 核对 inspect 返回的 operational worktree/transaction workspace。

## 4. 验收条件

1. `node --test test/caller-contract.test.mjs`（cwd `skills/shared/crctl/scripts`）通过，且包含本 TASK 新增的显式 `--workspace` 调用形态断言条目。
2. `node lint-prompts.mjs --mode enforce`（同 cwd）退出 0，无 CONTRADICTS/STALE-REF 漂移。
3. 清点面 grep 复核：上述文件中可执行 crctl CR 数据读写示例命令均含 `--workspace`；`inject-cr-status.mjs` 在无 CRCTL_WORKSPACE 输入路径时不输出状态命令建议（用例或人工核对记录）。

## 5. 完成标志

caller-contract 新增断言通过 + lint-prompts enforce 零命中 + 本 TASK 涉及文件全部提交（`[cr] ` 前缀 commit）；调用点清单草稿（逐项：文件、命令形态、是否扫描面外）可供 TASK-05 汇总。

## 6. 接口契约

- **消费**：无上游 TASK。
- **产出**：
  - caller-contract 断言清单：`REVIEWED_CALLS` / `OUT_OF_SURFACE_CALLERS` 数组新增条目沿用既有条目结构（命令 argv 数组 + 消费面标注），断言每个 CR 数据读写 argv 含 `--workspace` 及非空路径 token。
  - hook 行为契约：`inject-cr-status.mjs` 仅当存在可信项目 workspace 路径输入时输出形如 `crctl status <CR-ID> --workspace <path>` 的建议；否则不输出任何 crctl 命令建议。
  - 供 TASK-02 消费：迁移完成 = TASK-02 启用入口强校验的发布顺序前置条件；供 TASK-05 消费：调用点清单草稿。

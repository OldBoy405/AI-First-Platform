---
spec-id: ai-first-platform
version: "0.20.4"
id: CR-2026-043-TASK-05
type: TASK
cr-ref: CR-2026-043
plan-ref: "change-requests/CR-2026-043/plan.md"
sdd-ref: "change-requests/CR-2026-043/sdd.md"
title: README 人读段与跨平台集成回归
slug: readme-and-integration-regression
status: pending
estimate: 6h
depends-on: [CR-2026-043-TASK-04]
created: 2026-08-16T01:00:22+08:00
---

# TASK-05 README 人读段与跨平台集成回归

## 1. 任务描述

在 tools `README.md` 增加 workspace freshness 的人读入口段（命令、结果含义、失败后人工动作、权威契约链接），并执行跨平台集成回归：双 gate 场景、全量既有测试在 Windows 与 Ubuntu 各跑一遍。对应 FR-06 文档面与 SDD §7.3 集成层（Phase D）。

## 2. 涉及文件 / 模块

- `README.md`（新增一节）
- `skills/shared/crctl/scripts/test/`（集成用例并入 workspace-freshness.test.mjs 或既有集成入口）

## 3. 实现要点

- README 段内容：`crctl workspace freshness|sync` 两条命令形态；fresh/behind-clean/diverged/unknown 四值含义一句话；behind-clean→显式 sync、diverged/dirty/unknown→人工处理；失败后只重跑同一 sync 命令续跑；链接 `skills/sync/workspace-freshness/SKILL.md` 与 `skills/shared/crctl/SKILL.md` 为权威契约。不复制分类算法、journal 状态或错误实现细节。
- 集成用例（真实 Git fixture，复用现有测试基建）：
  - implement gate：behind-clean worktree → freshness 报 syncable → sync → 重核 allFresh → 允许进入 implement-code 等价路径；
  - implement gate：diverged → abort 且不写任何仓；
  - review gate（可同步轨）：构造 `behind-clean` → review-start 显式 sync → route=`replay`，按 replayNodes 重放实现/测试/checkpoint/freshness/评审（以节点序列断言，不真实跑 LLM 评审）；
  - review gate（人工轨）：实施后 CR 分支已有独有提交且 trunk 前进 → `diverged` → route=`manual`/abort、零自动写入；人工处理使事实恢复为可评审状态后重新进入 freshness gate，再按既有 replayNodes 继续；测试断言不存在自动 merge/rebase 或盲目重试；
  - 回归：`ensureRepoWorkspace`、`pull-progress` 语义、checkpoint、release-subjects 重核用例不受影响。
- 跨平台：Windows 本机 + Ubuntu（CI 或远端）各跑 `node --test skills/shared/crctl/scripts/test/` 全量；记录 CRLF/路径身份结果一致。

## 4. 验收条件

1. README 新段通过人读检查：含命令、四值含义、人工动作与权威链接；静态扫描无 ancestry 算法或 journal 细节复制。
2. 集成用例在 Windows 与 Ubuntu 均通过；既有 crctl 全量测试双平台通过，不新增生产依赖。
3. `git status`/既有 gate 语义抽查确认 ensure/pull-progress/checkpoint 行为未漂移。

## 5. 完成标志

双平台全量测试通过 + README 段合入 + 输出摘要含双平台测试结果。

## 6. 接口契约

- **消费**：TASK-01/02 的 CLI 与深模块函数；TASK-03 的 Skill 输出契约；TASK-04 的 pipeline 节点与 replayNodes 声明。
- **产出**：README 人读段（无机器消费方）；集成测试基线（供后续 CR 回归复用）。

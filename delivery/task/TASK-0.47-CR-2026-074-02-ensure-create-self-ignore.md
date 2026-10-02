---
spec-id: ai-first-platform
version: "0.47"
id: CR-2026-074-TASK-02
type: TASK
cr-ref: CR-2026-074
plan-ref: "change-requests/CR-2026-074/plan.md"
sdd-ref: "change-requests/CR-2026-074/sdd.md"
target-version: 0.47
title: ensure create 自忽略
slug: ensure-create-self-ignore
status: pending
estimate: 1h
depends-on: [CR-2026-074-TASK-01]
created: 2026-10-01T00:55:00+08:00
---

## 任务描述

在 `ensureRepoWorkspace` 的 create 路径实现 `.rayai-worktrees/` 运行时目录自忽略（SDD §4.2；FR-4；AC-04），使 init 后首个 CR 建立 worktree 时主 KB 保持 clean。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` — `ensureRepoWorkspace` create 路径（dep-5：现状建立 repo.worktreePath 后执行 worktree add，创建路径未写 `.rayai-worktrees/.gitignore`，此为 FR-4 的窄修改点）。
- `skills/shared/crctl/scripts/test/register-tx.test.mjs` — AC-04 场景用例；fixture 裁剪 dep-16 为不预装根 runtime ignore 的形态。

## 实现要点

- create 路径顺序（SDD §4.2）：确保 install root 的 `.rayai-worktrees/` 已建 → 写其包自管 `.gitignore` 内容为 `*\n`（UTF-8/LF）→ 再创建下层 repo.worktreePath 并执行 worktree add。
- 只写运行时目录自身文件；根用户 `.gitignore` 原文不动；不扩展到其他目录。
- 新注册 source 缺省值变更属 TASK-03，本 TASK 不触碰 `registerCr` 的 source/inputDigest 路径。

## 验收条件

1. 在 tools CR worktree 执行 `node --test skills/shared/crctl/scripts/test/register-tx.test.mjs`（证据 cmd-02）全绿，且 AC-04 断言覆盖：init 后首 CR → 第一 CR 分配、三仓 worktree 全部建立、主 KB clean（status --porcelain 为空）、`.rayai-worktrees/.gitignore` 内容为 `*\n`、根 `.gitignore` 哈希不变。
2. 同场景重入（register 续跑/noop）后再断言：`.rayai-worktrees/.gitignore` 仍为 `*\n`，根 `.gitignore` 哈希不变，无重复 CR 分配。

## 完成标志

- cmd-02 全绿含 AC-04 断言。
- diff 限 `workspace-transactions.mjs` 的 ensure create 路径与 `register-tx.test.mjs`；`applyWriteback`/`writebackAllowlist`/指纹计算与注册其余行为零 diff（zero_diff 边界）。
- 与 TASK-01 产物联测：init（TASK-01）→ register 首条 CR 的完整场景通过。

## 接口契约

**消费**：dep-5 `ensureRepoWorkspace.create` 现有流程（建立 repo.worktreePath 后 worktree add——本 TASK 在创建下层路径前插入自忽略写入）；TASK-01 的 kb init 入口与 KbInitResult（测试场景前置：init 后 register）。

**产出**：create 路径内部行为——install root 的 `.rayai-worktrees/.gitignore` 内容恒为 `*\n`；无新增导出/签名。下游消费方 TASK-03（同文件顺序编辑）以本 TASK 编辑后的文件状态为基线；TASK-09（requirement-register/SKILL.md 引导描述）引用同一行为事实。

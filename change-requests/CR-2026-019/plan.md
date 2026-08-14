---
id: CR-2026-019-plan
type: PLAN
cr-ref: CR-2026-019
sdd-ref: "change-requests/CR-2026-019/sdd.md"
target-version: tbd
status: draft
created: "2026-08-04T17:35:00+08:00"
updated: "2026-08-04T17:35:00+08:00"
---

# PLAN — YAML 账本操作收敛为 crctl 子命令（P2）+ AC-9 演练入库

> 基于 sdd.md 的开发计划。所有代码改动落在单文件 `skills/shared/crctl/scripts/crctl.mjs` 与其测试 `test/crctl.test.mjs`，外加三份 SKILL.md 文档同步。**不新增文件、不建脚本库**（FR-4）。

## 1. 交付里程碑

| 里程碑 | 内容 | 对应 FR | 估算 |
|---|---|---|---|
| M1 写入原语 | 新增 `casWriteMulti`（双文件全校验→全 temp→连续 rename） | FR-3 支撑 | 0.5 人天 |
| M2 三子命令 | `task done` / `merge-metadata` / `archive-move` + dispatch 三 case + 前置态守卫 | FR-1/2/3/5 | 1.5 人天 |
| M3 测试固化 | `crctl.test.mjs` 新增用例；AC-9 merge-tree 演练从 `_scratch/patch-task10b.mjs` 固化入库 | FR-7 | 1 人天 |
| M4 文档同步 | implement-code / merge-feature-branch / cr-archive 三 SKILL.md 改调子命令 + 明文禁手写 YAML | FR-6 | 0.5 人天 |
| M5 回归验收 | 既有 32 用例 + 新增用例全绿；AC-1..9 逐条核对 | AC-8 全体 | 0.5 人天 |

估算总工时：约 4 人天。

## 2. 任务依赖图

```
TASK-01 casWriteMulti 原语 ─┐
                            ├─→ TASK-04 archive-move（依赖 01）
TASK-02 task done ──────────┤
TASK-03 merge-metadata ─────┤
                            └─→ TASK-05 测试固化（依赖 01-04）
TASK-06 三份 SKILL.md 同步（依赖 02-04 的最终 CLI 契约）
TASK-07 回归 + AC 逐条验收（依赖 05-06）
```

- TASK-02/03 相互独立，可并行；均只用现有 `casWrite`。
- TASK-04 依赖 TASK-01 的 `casWriteMulti`。
- TASK-05 测试依赖三子命令实现定型（02/03/04）。
- TASK-06 文档措辞依赖子命令 CLI 契约冻结（入参/错误码），排在实现之后。
- TASK-07 收口，依赖 05（新测试绿）与 06（文档一致）。

## 3. 资源与分工

单人串行执行（owner: Ray，见 cr.md）。M1→M2→M3 为关键路径（约 3 人天）；M4 可与 M3 部分并行。

## 4. 风险与回滚策略

| 风险 | 影响 | 缓解 / 回滚 |
|---|---|---|
| `casWriteMulti` 两次 rename 间崩溃 → backlog 已删、history 未写的半状态 | archive-move 数据半提交 | SDD §4.3 已判定为可接受天花板：rename 微秒级窗口 + 账本随 `--embedded` 进同一 git 提交，`git checkout` 可整体回滚；单写者不变量下无并发。不引入 WAL（YAGNI） |
| 行级正则锚定不到目标块 → 静默丢数据（T04 复现） | 账本被破坏且无告警 | 所有 edit 纯函数匹配不到一律 `fail(...)` 硬失败（纪律 #1），测试覆盖"块不存在"路径断言文件无变更 |
| 三子命令误改 CR status | 破坏 `advance` 单一状态写者不变量（纪律 #5） | 契约层禁止：子命令只做账本编辑、不发 status 事件；review-code 对照 §1.2 核查 |
| SKILL.md 文档漏改，仍指导手工编辑 YAML | FR-6 未闭环，账本第二写入通道复活 | TASK-06 逐文件 grep "手工编辑/手动改" 确认清零；review 对照 FR-6 |
| 回滚粒度 | — | 本 CR 改动均在 `requirement/CR-2026-019` worktree 分支，未合入 trunk 前可整分支丢弃 |

## 5. 验收与发布策略

- **发布前 checklist**：
  1. `node --test test/crctl.test.mjs` 全绿（既有 32 + 新增用例）
  2. AC-1..9 逐条核对（见 sdd.md §7.2 测试矩阵）
  3. 三份 SKILL.md `grep` 确认无"手工编辑 YAML"残留措辞
  4. `crctl.mjs` 顶部 import 仍只含 `node:*`（NFR-4 零依赖不变量）
- **无 feature-flag**：crctl 为治理工具，新增子命令对既有命令无副作用，直接随 CR 合入生效。
- **发布动作**：走标准 feature-writeback pipeline（merge-feature-branch → cr-archive），本 CR 的 `archive-move` 子命令即为该链路的账本收口工具。

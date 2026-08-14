---
id: CR-2026-019-prd
type: PRD
cr-ref: CR-2026-019
title: 治理工具链 — YAML 账本操作收敛为 crctl 子命令（P2：任务标 done / merge-commits 写入 / 归档移动）+ AC-9 演练入库
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: "2026-08-04T16:20:00+08:00"
updated: "2026-08-04T16:20:00+08:00"
---

# PRD — YAML 账本操作收敛为 crctl 子命令（P2）+ AC-9 演练入库

## 1. 概述

### 1.1 问题陈述

CR-2026-012 收尾复盘（`docs/analysis/CR-2026-012-合并回写归档复盘.md` §3.2 P2）确认：状态推进已由 CR-2026-018（T1-full）收敛为 `crctl advance` 单写 `cr.md`，但**三类账本写入操作仍靠 Agent 手工编辑 YAML**——

1. 任务 `change-requests/{CR-ID}/tasks/_index.yml` 的 `status: pending → done`；
2. `_backlog.yml` 注册条目的 `merge-commits[]` 追加；
3. 归档时把注册条目从 `_backlog.yml` 移动到 `_history.yml`（附 `final-status`）。

这三处是本轮转义事故的高发区：CR-2026-012 一次会话内现写的坏脚本把 9 个 rebase 冲突块原样提交进历史，事后手工修复（纪律 #7 由此固化）。手工/现写脚本编辑绕开了 crctl 已有的 **CAS 写保护 + 审计日志 + 门禁校验**单一写入路径。

同时，CR-2026-018 测试报告 §5.1 / §6 记录：AC-9 的 `git merge-tree --write-tree` 对 `_backlog.yml` 零冲突演练当前是会话内一次性脚本（`_scratch/patch-task10b.mjs` 变体），未纳入 CI 回归，核心不变量缺自动化守护。

### 1.2 解决方案摘要

把上述三类账本操作补成 crctl 子命令（`crctl task done` / `crctl merge-metadata` / `crctl archive-move`），复用 `advance` 已有的写入基础设施（sha256 CAS、`.crctl/audit.log` 追加、门禁校验），**不新建独立脚本库**——复盘明确否决"脚本入库 `tools/skills/shared/scripts/`"方案，因其会在 crctl 之外开第二条账本写入通道，长期必然漂移。账本从此只有一条写入路径：crctl。

配套把 AC-9 merge-tree 零冲突演练从会话内一次性脚本固化为入库测试用例，纳入 `crctl.test.mjs` 回归套件。

### 1.3 事实基线（已核实，纪律 #4）

| 事实 | 位置 / 命令 |
|---|---|
| crctl 现有子命令：`status/gate/advance/approve/validate/attempt/test/next/migrate-backlog/git`——**无** `task`/`merge-metadata`/`archive-move` | `crctl.mjs:1419-1431`（dispatch case） |
| `tasks/_index.yml` 当前仅被**读取**用于 delivery/task 一致性校验，crctl 无写入路径 | `crctl.mjs:560-562` |
| `merge-commits[]` 是 `_backlog.yml` 注册条目字段（CR-018 已定型），当前由 `merge-feature-branch` 手工/embedded patch 写入 | `crctl.mjs:690` 注释 + `merge-feature-branch` SKILL |
| 归档 backlog→history 移动当前由 `cr-archive` skill 手工编辑两个账本文件 | `cr-archive` SKILL；worktree 存在 `_history.yml` |
| `advance` 已具备 CAS（读后被改则 `CAS_CONFLICT`）+ 审计日志 + 门禁，可复用 | CR-2026-018 SDD / `cmdAdvance` |
| AC-9 演练为会话内一次性脚本，未入 CI | `_scratch/patch-task10b.mjs`；CR-018 测试报告 §5.1(1) |
| 前置依赖满足：T1-full（CR-2026-018）已定型；主仓 `_backlog.yml` 已迁移 v2 注册索引布局 | CR-018 测试报告 §6；`_backlog.yml` v2 |

## 2. 用户故事

- **US-1** 作为 CR 开发者，我完成一个任务后用一条 crctl 子命令把 `tasks/_index.yml` 标 done，写入经 CAS 复核并留审计记录，不再手写 YAML（纪律 #8 落到工具层）。
- **US-2** 作为执行合并的维护者，我用一条 crctl 子命令把 merge-commits 追加进注册条目，转义事故高发的手写编辑从流程中消失。
- **US-3** 作为归档执行者，我用一条 crctl 子命令原子完成 backlog→history 的条目移动（附 final-status），任一侧 CAS 冲突则整体中止，绝不产生半移动的账本。
- **US-4** 作为平台维护者，账本只有 crctl 一条写入通道，任何写入都过 CAS + 审计 + 门禁，不存在绕开复核的第二通道。
- **US-5** 作为 CI/回归的维护者，AC-9 merge-tree 零冲突不变量由入库测试用例守护，回归自动执行而非依赖会话内一次性脚本。

## 3. 功能需求

- **FR-1（`crctl task done` 子命令）**：新增 `crctl task done <CR-ID> --task <TASK-ID> [--workspace .]`，把 `change-requests/{CR-ID}/tasks/_index.yml` 中对应任务 `status` 置为 `done` 并记录完成时间戳。经 sha256 CAS 写保护、追加 `.crctl/audit.log`；`--task` 不存在或已 done 时硬失败并说明（不静默）。
- **FR-2（`crctl merge-metadata` 子命令）**：新增 `crctl merge-metadata <CR-ID> --add-commit <sha>[,<sha>...]`，把提交 SHA 追加进 `_backlog.yml` 注册条目的 `merge-commits[]`（去重、保序），经 CAS + 审计。取代 `merge-feature-branch` 手工/embedded 编辑该字段的路径。
- **FR-3（`crctl archive-move` 子命令）**：新增 `crctl archive-move <CR-ID> --final-status <status>`，**原子**地把注册条目从 `_backlog.yml` 移除并写入 `_history.yml`（携带 `final-status` 与归档时间戳）。两个文件均纳入本次 CAS 快照，任一侧读后被改则整体 `CAS_CONFLICT` 中止、不落任何一侧。`final-status` 语义与结构沿用现状（CR-018 FR-9），不新增字段。
- **FR-4（单一写入路径不变量）**：三个子命令一律复用现有账本写入基础设施（CAS 读→写、审计追加、YAML 解析/序列化），**不引入独立脚本库**、不新增第三方依赖、不开第二条写入通道。会话内现写脚本处理账本被工具层面根除。
- **FR-5（门禁与非法调用防护）**：`archive-move` 仅在 CR 处于可归档态时合法（非法态硬失败并给出当前态与期望态）；`task done` 仅在开发相关态合法；所有子命令对缺参、CR 不存在、workspace 探测失败均硬失败。门禁语义引用状态机唯一事实源（`../tools/dir-graph.yaml`），不在本 CR 复刻声明（纪律：禁止复制状态机）。
- **FR-6（skill 文档同步收敛调用）**：`implement-code`（任务标 done）、`merge-feature-branch`（merge-commits 写入）、`cr-archive`（归档移动）三个 SKILL.md 改为调用对应新子命令，并显式禁止会话内手写/现写脚本编辑账本（纪律 #7 从文档约定落为工具强制）。仅引用账本路径而不写入的文档不改。
- **FR-7（AC-9 演练入库为测试用例）**：把 `_scratch/patch-task10b.mjs` 的 merge-tree 零冲突演练（共同祖先注册 → 分支推进 ≥3 次 `cr.md` → master 侧注册另一 CR → `git merge-tree --write-tree` 对 `_backlog.yml` 零冲突）固化为 `skills/shared/crctl/scripts/test/crctl.test.mjs` 的入库用例，纳入 `node --test` 回归。

## 4. 非功能需求

- **NFR-1（行尾纪律，纪律 #1）**：三个子命令对账本文件的读入先 `\r\n → \n` 规范化、解析用 `split(/\r?\n/)`；YAML/跨行解析匹配失败一律**硬失败报错**，禁止静默降级为空/取一侧。
- **NFR-2（原子性）**：`archive-move` 的双文件写入是全有或全无——沿用 `advance` 的 CAS 模式对每个目标文件做读后校验，任一冲突整体回退，绝不产生 backlog 已删而 history 未写（或反之）的半状态。
- **NFR-3（单一写入通道）**：账本写入在改造后有且仅有 crctl 一条路径；审计日志可完整追溯每次账本变更的 actor / 时间 / 前后差异。
- **NFR-4（零新增依赖）**：完全复用 crctl 现有 YAML/CAS/审计工具函数与 Node 标准库，不加第三方包。
- **NFR-5（回归可执行）**：新增用例与 AC-9 入库用例纳入既有 `crctl.test.mjs`，`node --test` 一次运行全绿，不依赖临时目录外部状态。

## 5. 验收标准

- **AC-1**（对应 FR-1）：`crctl task done <CR> --task <TASK-ID>` 后 `tasks/_index.yml` 该任务 `status=done` 且含完成时间戳，`audit.log` 新增一条对应记录；对不存在的 `--task` 与已 done 任务均非零退出且不写文件。
- **AC-2**（对应 FR-2）：`crctl merge-metadata <CR> --add-commit <sha>` 后注册条目 `merge-commits[]` 含该 sha；重复追加同一 sha 不产生重复项；写入经 CAS，`audit.log` 有记录。
- **AC-3**（对应 FR-3）：`crctl archive-move <CR> --final-status archived` 后条目从 `_backlog.yml` 消失、在 `_history.yml` 出现且带 `final-status`；构造 history 侧读后被改场景，命令 `CAS_CONFLICT` 中止且**两个文件都无变更**。
- **AC-4**（对应 FR-4）：`grep` 三个子命令实现，账本写入全部经既有 CAS/审计工具函数；仓库内无为这三类操作新建的独立脚本库目录。
- **AC-5**（对应 FR-5）：对非可归档态 CR 执行 `archive-move`、对非法态执行 `task done`、对不存在 CR 执行任一子命令，均非零退出并打印当前态/期望态或缺失原因；无任何账本文件被写。
- **AC-6**（对应 FR-6）：`implement-code` / `merge-feature-branch` / `cr-archive` 三个 SKILL.md 中账本写入步骤改为调用新子命令，且含"禁止会话内手写/现写脚本编辑账本"明文；`grep` 三文档无残留"手工编辑 YAML"类指引。
- **AC-7**（对应 FR-7 与核心目标）：`crctl.test.mjs` 含 AC-9 merge-tree 零冲突用例，`node --test` 运行该用例 PASS；用例内 `git merge-tree --write-tree` 对 `_backlog.yml` 冲突数为 0、exit 0。
- **AC-8**（回归）：`crctl` 现有测试套件（基线 32 用例，CR-018 定型）全绿，新增用例覆盖 FR-1/2/3/5 与 AC-9 入库。

## 6. 成功指标

- 三类账本操作（任务标 done / merge-commits 写入 / 归档移动）经 crctl 子命令执行的比例达 **100%**；流程文档中手工编辑 YAML 账本的指引数降为 **0**。
- 下一个走完整生命周期的 CR，账本写入相关的转义类返工事故数为 **0**（基线：CR-2026-012 一次坏脚本把 9 个冲突块提交进历史）。
- AC-9 merge-tree 零冲突不变量由 CI 回归用例守护，回归自动执行，不再依赖会话内一次性脚本。

## 7. 范围排除

- **不建独立脚本库**：明确否决"脚本入库 `tools/skills/shared/scripts/`"，账本写入只保留 crctl 单一通道。
- **不改状态机本身**：不增删状态、不改转移与门禁语义、不在本仓复刻状态机/gates 声明（唯一事实源在 `../tools/`）。
- **不改 `_backlog.yml` v2 schema 与 `_history.yml` 结构**：注册索引布局由 CR-2026-018 定型，本 CR 只补写入子命令，不动字段集合与归档记录结构。
- **不重跑迁移**：`crctl migrate-backlog` 与存量 workspace 迁移是 CR-2026-018 的发布动作，不在本 CR 范围。
- **不改兼容读**：CR-018 的 `legacy-source` / `MIXED_LAYOUT_WARN` 回退读路径与其去留由后续版本处理，本 CR 不触碰。
- **不处理非知识库仓**：独立代码仓不含 `change-requests/`，与本 CR 无关。

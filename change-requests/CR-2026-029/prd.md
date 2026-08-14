# PRD — 发布联调移交 merge pipeline 完成证据（发布类任务不落开发 TASK）

- **版本**：v0.1.0
- **cr-ref**：CR-2026-029
- **状态**：drafting

## 1. 概述

### 1.1 问题陈述

CR-2026-028 的 TASK-10（发布与联调，4h）被拆为开发期 TASK，但实际执行（双仓 merge、真实 worktree 走查、台账核账）只发生在代码审批之后、`merging` 状态。`crctl task done` 前置态仅 `developing`，导致：

- TASK-10 永远无法通过权威命令登记 `done`（实测 `ILLEGAL_LEDGER_STATE`，当前 merging）；
- 归档门禁（CR-2026-027 FR-9）检查 tasks 全 done 与 delivery 覆盖，TASK-10 残留 pending 会阻塞 writeback 与归档；
- 发布联调的真实完成证据散落在会话输出与 git 历史，没有结构化落盘。

根因：**"发布联调"是 merge pipeline 的职责，不是开发 TASK**。把发布类工作拆进 `developing` 阶段的 TASK，与 `task done` 前置态、归档门禁的语义冲突。

### 1.2 解决方案摘要

把发布联调从开发 TASK 改为 **merge-feature-branch 的完成证据**：

1. `merge-feature-branch` Skill 在 merge push 成功后新增"发布联调走查"步骤：验证各仓 trunk 的 CR 状态、worktree-path、next，核对 multica CUSTOM.md 台账，把走查结果结构化落盘为 `change-requests/{cr}/merge-verification.md`；
2. `feature-writeback.pipeline.json` 的 merge-feature-branch 节点 prompt 同步该步骤；
3. 明确约定：**发布联调、merge 验证类工作归 merge pipeline，不创建开发 TASK**；
4. 迁移：移除 CR-2026-028 的 TASK-10（tasks/_index.yml 条目 + TASK-10.md），在其变更记录注明移交 merge pipeline（CR-2026-029）。

### 1.3 事实基线

- `crctl task done` 前置态：`developing`（crctl.mjs `cmdTaskDone` LEGAL 数组）；
- 归档门禁：tasks 空/全 pending/部分 done/delivery 缺失均拦截（CR-2026-027 FR-9）；
- CR-2026-028 当前 `merging`，merge 已完成（tools `870f26d`、multica `c8c96e56a`、knowledge-base `24d39f1`），TASK-10 无法登记 done（实测 `ILLEGAL_LEDGER_STATE`）；
- merge-feature-branch Skill 当前 6 步：预检 → 本地合并 → commit → push → 状态推进 → 摘要（无联调走查证据落盘）。

## 2. 功能需求

- **FR-1（merge pipeline 联调走查）**：`merge-feature-branch/SKILL.md` 在"更新 CR status"步骤后新增"发布联调走查"步骤：① 各仓 trunk 拉取后以主 checkout 与 linked worktree 分别执行 `crctl status`/`worktree-path`/`next`，确认无 `STATUS_DIVERGED`/嵌套路径异常；② 核对 `CUSTOM.md` 台账条目与合并后代码一致；③ 将走查结果（各仓 merge-sha、走查命令与结论、异常与处理）结构化写入 `change-requests/{cr}/merge-verification.md`，提交到 knowledge-base trunk。
- **FR-2（pipeline prompt 同步）**：`feature-writeback.pipeline.json` 的 merge-feature-branch 节点 prompt 增加联调走查与 merge-verification.md 产出描述，与 Skill 一致。
- **FR-3（发布类任务约定）**：merge-feature-branch Skill 明确"发布联调、merge 验证类工作归 merge pipeline，不创建开发 TASK"；`write-dev-tasks` 拆分时不得再产生发布/联调类 TASK。
- **FR-4（迁移 CR-2026-028 TASK-10）**：从 `change-requests/CR-2026-028/tasks/_index.yml` 移除 TASK-10 条目、删除 `tasks/TASK-10.md`，在 CR-2026-028 变更记录（cr.md 或 sdd.md 变更记录）注明"发布联调移交 merge pipeline（CR-2026-029）"；CR-2026-028 的 test-report.md TASK 覆盖矩阵同步。
- **FR-5（验证）**：`crctl.test.mjs` 新增 merge-verification 生成断言（或既有 writeback 测试扩展）；CR-2026-028 在迁移后 tasks 全 done、无 TASK-10，归档门禁通过。

## 3. 验收标准

- **AC-1（FR-1）**：对某 CR 执行 merge-feature-branch 后，knowledge-base trunk 出现 `change-requests/{cr}/merge-verification.md`，含三仓 merge-sha、status/worktree-path/next 走查结论与台账核账结果。
- **AC-2（FR-2）**：pipeline JSON 可解析，merge-feature-branch 节点 prompt 与 Skill 步骤一致（含 merge-verification 产出）。
- **AC-3（FR-3）**：merge-feature-branch Skill 明确发布类工作归 merge pipeline；write-dev-tasks Skill/pipeline 无发布联调类 TASK 拆分指引。
- **AC-4（FR-4）**：CR-2026-028 的 tasks/_index.yml 无 TASK-10、TASK-10.md 已删、变更记录注明移交；其 tasks 状态全 done。
- **AC-5（FR-5）**：`node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全绿（含新增用例）；CR-2026-028 归档门禁检查通过。

## 4. 范围排除

- 不改 `crctl task done` 前置态（把 merging 加入 LEGAL）——治标且放宽账本语义，属被否决替代方案；
- 不新增 crctl 子命令、不改归档门禁判定本身；
- 不重跑 CR-2026-028 的 merge（已完成）。

## 5. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-10 | v0.1.0 | Ray | 初稿：发布联调移交 merge pipeline 完成证据 |

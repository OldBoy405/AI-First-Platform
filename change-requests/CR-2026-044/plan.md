---
id: CR-2026-044-plan
type: PLAN
cr-ref: CR-2026-044
sdd-ref: "change-requests/CR-2026-044/sdd.md"
target-version: tbd
status: draft
created: 2026-08-17T00:02:54+08:00
updated: 2026-08-17T00:10:00+08:00
---

# 1. 交付里程碑

基线：`tools@custom/main` commit `8f530589`；生产代码与 Tools 文档写入 tools worktree（`.rayai-worktrees/tools/requirement/CR-2026-044`），ADR-0004 写入 knowledge-base worktree 的 `docs/adr/`；multica 不参与任何改动。

| 里程碑 | 内容 | 依赖 | 估算 |
|---|---|---|---|
| M1 红测试冻结 | TASK-01：失败向量红测试入库，固化 local valid + remote stale、`y/Y` 误 reject 两类回归证据 | 无 | 4h |
| M2 TTY 确认 | TASK-02：共享 `cmdApprove` 接受 `y|yes`，四 stage 参数化转绿 | TASK-01 | 2h |
| M3 本地证据 | TASK-03：release-subjects 构造/重核本地化，精确 KB 白名单转绿 | TASK-01 | 6h |
| M4 发布边界 | TASK-04：merge 全仓 publication preflight 与双 recoverCommand 转绿 | TASK-01、TASK-03 | 8h |
| M5 采用面 | TASK-05：`workspace inspect` authority path、三条 Pipeline checkpoint、Skill 文本、`upgrade-check` 兼容分类与结构测试 | TASK-02、TASK-03、TASK-04 | 6h |
| M6 文档与回归 | TASK-06：ADR-0004/ARCHITECTURE/README 同步与全量回归 | TASK-02~TASK-05 | 4h |

估算总工时：30h（约 3.75 人天）。

# 2. 任务依赖图

```text
TASK-01 (红测试)
  ├─→ TASK-02 (TTY y|yes) ──────────────┐
  └─→ TASK-03 (release 本地化) ─→ TASK-04 (merge preflight) ─┤
                                                        └─→ TASK-05 (Pipeline/Skill/upgrade-check 采用)
TASK-02~TASK-05 ────────────────────────────────→ TASK-06 (两仓文档 + 全量回归)
```

- TASK-02、TASK-03 相互独立，可并行；同仓测试文件冲突时串行。
- TASK-04 复用 TASK-03 的本地 verifier 作为 merge 共同前置。
- TASK-05 消费 TASK-02 的 TTY 合同、TASK-03 的本地 verifier 与 TASK-04 的 publication lag 合同；`workspace inspect` authority 字段由 TASK-05 自己产出。
- TASK-06 只做两仓文档与回归：ADR-0004 在 knowledge-base，ARCHITECTURE/README 在 tools，不改行为。

# 3. 资源与分工

| 角色 | 负责人 | 职责 |
|---|---|---|
| 开发 | Ray | TASK-01~05 实现，逐 TASK 提交并即时在 `tasks/_index.yml` 标记 done |
| 测试 | Ray | 每个 TASK 完成后运行受影响测试文件；TASK-06 执行全量回归命令 |
| 需求 | Ray | 验收对齐 PRD AC-01~23，回写期确认 specs 累积 |

# 4. 风险与回滚策略

| 风险 | 缓解 | 回滚 |
|---|---|---|
| R-01 本地 verifier 收窄后误放真实漂移 | 白名单逐项参数化测试 + non-KB HEAD 精确相等断言 | 恢复旧 remote 判定分支（纯函数回退，无 schema 影响） |
| R-02 publication preflight 与既有 journal 恢复互相干扰 | 共同 verifier 前置；preflight 仅在 `payload.repos.length===0`；rebuild 用冻结 sourceSha | preflight 代码为独立段，删除即回到旧逐仓检查 |
| R-03 已有 merge journal 跨版本切换 | SDD §11：启动版本完成原事务；PRD FR-11/AC-23 | 不回滚事务实现，用原 tools 版本续跑 |
| R-04 Pipeline checkpoint 强制化打断现有流程 | 草稿/TASK checkpoint 保持可选；只有审批后终点改 abort | Pipeline JSON 与 `_index.yml` 可独立回退，无数据迁移 |
| R-05 TTY 放宽误触批准 | 只放宽正向判断；reject/非 TTY/grant/resign 分支零改动 | 恢复 `!== 'yes'` 单行判断 |
| R-06 upgrade 激活分类沿用旧协议 | 参数化覆盖 code-reviewing/code-approved/partial-publish，新合同不扩返回 schema | 恢复 `checkUpgrade` 既有分类分支与测试 |

# 5. 验收与发布策略

- 发布前 checklist：
  1. PRD AC-01~23 全部有对应测试或契约检查证据；
  2. `crctl.test.mjs`、`checkpoint-tx.test.mjs`、`merge-tx.test.mjs`、`writeback-tx.test.mjs`、`archive-tx.test.mjs`、`upgrade-check.test.mjs`、`pipeline-structure.test.mjs` 全绿；
  3. `check-agents-contract.mjs`、`check-skill-matrix.mjs`、`lint-prompts.mjs` 通过；
  4. 状态机/gates/schema/依赖清单零新增（AC-19）。
- 无 feature flag：行为变更即本地/远端边界切换，按 PRD §11（FR-11）启用合同分状态兼容；不新增观察期账本。
- 发布顺序：代码合入 tools custom/main 后，先 `upgrade-check` 只读确认，再让新 CR 走新流程；已启动 merge 事务按 SDD §11.5 用启动版本完成。
- 估算交叉校验：本计划总工时 30h，须与 `crctl task init` 返回 `totalEstimateHours` 一致。

# 6. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-17 | v0.2.0 | Ray | 回修 B-01~B-03：TASK-05 承接 upgrade-check 兼容分类并依赖 TASK-02；明确两仓文档落点 |
| 2026-08-17 | v0.1.0 | Ray | 初始计划：6 TASK、30h、依赖图与回滚策略 |

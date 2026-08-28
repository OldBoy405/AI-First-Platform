---
id: CR-2026-053-plan
type: PLAN
cr-ref: CR-2026-053
sdd-ref: "change-requests/CR-2026-053/sdd.md"
target-version: tbd
status: draft
created: 2026-08-28T11:15:00+08:00
updated: 2026-08-28T13:40:00+08:00
---

# 开发计划 — CR-2026-053 独立评审与人工审批命令闭环

## 1. 交付里程碑

### 阶段划分

| 阶段 | 主要交付物 | 任务 | 工时估算 |
|------|-----------|------|---------|
| **M1: Track A tools 仓基础改造** | matrix/agents/pipeline 改造 | TASK-01~03 | 5h |
| **M2: Track B multica 绑定接口** | 绑定接口 + sqlc 绑定读写 query + CreatePipelineTask 继承 | TASK-05~06 | 6h |
| **M3: 跨仓收口 + Track B 外围** | review Skill 绑定步骤 + 前端审批卡 + CLI + 存量修复 | TASK-04/07/08/11 | 8h |
| **M4: 台账 + 集成验收** | CUSTOM.md 台账 + 集成测试与验收 | TASK-09/10 | 5h |

**估算总工时**: 24h（= 6 人天，按 4h/人天口径；与 `tasks/_index.yml` 各任务 `estimate` 之和逐项一致）。

### 关键路径（DAG，非严格串行）

M1（tools 仓）与 M2（multica 仓）分属两仓、无相互依赖，**可并行启动**：

```
M1 (TASK-01/02/03) ──────────────┐
                                  ├──→ M3 (TASK-08 需 05；TASK-04 需 01/03/05/08；TASK-07 需 05；TASK-11 需 05/08) ──→ M4 (TASK-09 需 05/06/07/08；TASK-10 需全部前序)
M2 (TASK-05/06) ──────────────────┘
```

**阶段依赖规则（与 `_index.yml` depends-on 一一对应，禁止冲突）**：

- M1 任务（TASK-01/02/03）无前置，三者可并行；
- M2 任务（TASK-05/06）无前置，与 M1 并行；
- TASK-08（CLI 薄包装）依赖 TASK-05（消费其绑定接口）；
- TASK-04 依赖 TASK-01 + TASK-03 + TASK-05 + TASK-08（review Skill 绑定步骤通过 **TASK-08 的 CLI 命令 `multica cr bind-current-task <cr-id>`** 执行，该命令消费 TASK-05 的绑定接口）；
- TASK-07 依赖 TASK-05；TASK-11（存量修复）依赖 TASK-05 + TASK-08（其验收步骤直接执行 CLI 命令）；
- TASK-09（CUSTOM.md 台账）依赖 TASK-05/06/07/08（仅登记 multica 仓代码变更，不含 tools 仓 TASK-04 与无代码产物的操作型 TASK-11）；
- TASK-10（集成验收）依赖 TASK-01/02/03/04/05/06/07/08/09/11（全部实现任务）；
- M4 整体需 M1/M2/M3 全部完成（由 TASK-10 的 depends-on 兜底）；TASK-09 仅需其登记范围覆盖的 multica 任务（05/06/07/08）完成。

> **阶段间禁止跨级**：上述 depends-on 是 CR-2026-020 状态机门禁的兜底，文档不得与依赖图冲突。TASK-05/06 与 M1 并行是两仓物理隔离的客观事实，本计划明确承认，不再伪装成 M1→M2 严格串行。

## 2. 任务依赖图

```
Track A (tools 仓):
  CR-2026-053-TASK-01: 修改 agent-skill-matrix.yml (owner 归属调整)                     → []
  CR-2026-053-TASK-02: 修改 agents 文件 (委派合同 + quality-reviewer-agent.md)            → []
  CR-2026-053-TASK-03: 修改 pipeline 节点 prompt (review-* 节点, 含 FR-A6)                → []
  CR-2026-053-TASK-04: 修改 review Skill 绑定前置步骤（经 TASK-08 CLI 执行绑定）          → [01, 03, 05, 08]

Track B (Multica 仓):
  CR-2026-053-TASK-05: 新增绑定接口 POST /api/crs/{cr_id}/bind-current-task (含 sqlc)     → []
  CR-2026-053-TASK-06: 修改 CreatePipelineTask SQL 继承 issue_id/project_id (含 sqlc)     → []
  CR-2026-053-TASK-07: 前端审批卡可见性修复                                              → [05]
  CR-2026-053-TASK-08: CLI 薄包装命令                                                    → [05]
  CR-2026-053-TASK-09: CUSTOM.md 台账登记                                               → [05, 06, 07, 08]
  CR-2026-053-TASK-11: 存量 CR-2026-051/052 修复                                        → [05, 08]

集成:
  CR-2026-053-TASK-10: 集成测试与验收 (含 emit-registry.mjs)                            → [01, 02, 03, 04, 05, 06, 07, 08, 09, 11]
```

**依赖关系（与 `_index.yml` 一致，禁止冲突）**：

- TASK-01/02/03 可并行（M1）；TASK-05/06 可并行（M2，与 M1 并行）
- TASK-04 依赖 TASK-01 + TASK-03 + TASK-05 + TASK-08（绑定步骤经 TASK-08 CLI 执行）
- TASK-07/08 依赖 TASK-05；TASK-11 依赖 TASK-05 + TASK-08（验收直接执行 CLI）
- TASK-09 依赖 TASK-05 + TASK-06 + TASK-07 + TASK-08
- TASK-10 依赖 TASK-01/02/03/04/05/06/07/08/09/11

## 3. 资源与分工

| 角色 | 负责 |
|------|------|
| dev-agent | 全流程开发 |
| quality-reviewer-agent | review-dev-plan 评审 |

## 4. 风险与回滚策略

> **回滚原则**：本 CR 不引入 feature flag，但两仓（tools/multica）回滚完全独立，可按仓分别 revert。每条风险均给出「分仓回滚步骤」「跨仓部分发布处置」「存量绑定失败恢复」三项。

| 风险 | 影响 | 回滚策略 |
|------|------|---------|
| 绑定接口事务失败导致 task 无法推进 | 高 | **分仓回滚**：(1) multica 仓 `git revert <handler/service/agent.sql/sqlc 提交>`，恢复绑定接口前原状；(2) tools 仓不受影响，无需回滚。**部分发布处置**：绑定接口属新增孤立接口，回滚后无其它调用方受影响；review Skill 绑定步骤尚未插入时行为退化为不绑定。**存量绑定失败恢复**：事务失败零部分更新（NFR-1），重试即可；持续失败按 CR_ISSUE_CONFLICT/CR_BIND_FAILED 审计定位后修复。 |
| review Skill 绑定失败静默降级 | 高 | **硬失败不降级**：有 mat_ context 且绑定失败时，**不调用 `crctl review-record`，直接中止**——零绑定写入、不写 canonical review（FR-B7/NFR-6）。`review-record` 是落盘 canonical 结论的唯一命令且无 `--abort` 参数，绑定失败的关闭方式是「不调用它并中止」，而非执行任何落盘命令。**分仓回滚**：tools 仓 revert 四个 review SKILL.md 提交即移除前置步骤。**部分发布处置**：tools 仓单独合入（multica 接口未上线）时绑定步骤硬失败于 5xx，review 流程被阻塞——禁止 tools 仓先于 multica 合入。 |
| 部分发布（仅 tools 仓或仅 multica 仓先行合入） | 中 | tools 仓先行：review Skill 绑定步骤在 multica 接口未上线时硬失败，CR review 流程阻塞 → 需 revert tools 仓或补合 multica 仓；multica 仓先行：绑定接口已就绪但 review Skill 未接入，行为退化为不绑定（不破坏现有 review-record），可独立先合入。**发布顺序约束**：先 multica 后 tools。 |
| 存量 CR 绑定失败（CR-2026-051/052） | 中 | **存量绑定失败恢复（停止/恢复方案）**：(1) `TASK_ISSUE_REQUIRED` → 停止，确认启动 task 的 Issue 携带 `issue_id`（CR-2026-051 来自 AIFI-3 `6a8cd56a-12b3-49d9-80bb-4657da15c3b0`；CR-2026-052 来自 AIFI-6 `1766573d-f7bd-465b-bbc4-bcb65a84c880`），修复 task 创建路径后重试；(2) `TASK_CR_CONFLICT`/`CR_ISSUE_CONFLICT` → 停止，按 FR-B8 表人工核对是否已存在旧绑定，必要时人工清理后重试；(3) 任何失败均不修改 `cr.shell_issue_id`/`task.cr_id`，仅写 `cr_issue_bind_rejected` 审计。 |
| 前端审批卡渲染异常 | 中 | **分仓回滚**：revert `packages/views/projects/components/project-team-agent-chat.tsx` 与 `cr-gate-card.tsx` 提交，恢复 `for (const node of cr.gate_nodes)` 单循环渲染路径；`ApprovalCard` 提取为纯新增，删除无副作用。 |
| sqlc 生成物与 Go 代码不匹配 | 中 | **分仓回滚**：`make sqlc` 后检查 `server/pkg/db/generated/*.go` diff；不匹配时 revert `agent.sql` 与 `generated/` 后重新 `make sqlc`，禁手改生成物。 |

## 5. 验收与发布策略

### 发布前 Checklist

> 命令按**各仓 worktree 根**（`resources[].worktreePath`）为 cwd 执行：tools 仓命令用 tools 仓根相对路径（非 `../tools/`），multica 仓命令用 multica 仓根相对路径。

- [ ] tools 仓：`node skills/shared/crctl/scripts/check-skill-matrix.mjs` 零报错
- [ ] tools 仓：`node skills/shared/crctl/scripts/check-agents-contract.mjs` 零报错
- [ ] tools 仓：`node skills/shared/crctl/scripts/lint-prompts.mjs` 零报错
- [ ] tools 仓：`node pipeline-templates/emit-registry.mjs --verify` 通过（验证 Track A 改造后 registry 一致性）
- [ ] Multica 仓：`go test ./server/internal/service/... -run TestBindCurrentTaskToCR` 通过（7 种错误场景 AC-B1~B11）
- [ ] Multica 仓：`go test ./server/pkg/db/... -run TestCreatePipelineTaskIssueInherit` 通过（AC-B10 负向/正向）
- [ ] Multica 仓：`pnpm exec turbo test --filter='@multica/views'` 覆盖 AC-C1~C6
- [ ] Multica 仓：E2E 验证 `cr.shell_issue_id = 6a8cd56a-12b3-49d9-80bb-4657da15c3b0`（CR-2026-051，AIFI-3）
- [ ] Multica 仓：E2E 验证 `cr.shell_issue_id = 1766573d-f7bd-465b-bbc4-bcb65a84c880`（CR-2026-052，AIFI-6）
- [ ] `crctl approve CR-2026-053 --stage approve-dev-start` 人工审批流程闭环验证
- [ ] 四类 review Skill 各跑一轮独立 reviewer，验证 reviewer 与作者为两个独立 task/run

### Feature Flag 策略

无 feature flag，本次为确定性功能修复。**发布顺序约束**：multica 仓可单独先行合入（绑定接口先就绪），tools 仓 review Skill 步骤必须在 multica 仓绑定接口至少合入后合入；反之 tools 仓先合入会阻塞 review 流程。两仓同周内合入时建议 multica → tools 顺序。

---
id: CR-2026-030-plan
type: PLAN
cr-ref: CR-2026-030
sdd-ref: "change-requests/CR-2026-030/sdd.md"
target-version: tbd
status: draft
created: "2026-08-11T02:34:00+08:00"
updated: "2026-08-11T02:34:00+08:00"
---

# CR-2026-030 开发计划

## 1. 交付里程碑

### M1 - 契约测试基线（8h）

| TASK | 交付内容 | 估算 | 依赖 |
|---|---|---:|---|
| TASK-01 | 为 Registration、Owner handover、grant reject、dev-plan route 与 R7 建立失败优先测试向量 | 8h | - |

退出条件：新增向量在未实现能力上稳定失败，既有 `189` 项 crctl 与 `9` 项 writeback 基线无删除。

### M2 - crctl 核心能力（40h）

| TASK | 交付内容 | 估算 | 依赖 |
|---|---|---:|---|
| TASK-02 | 三 Owner registration、真实提交 SHA 事件与 worktree branch | 8h | TASK-01 |
| TASK-03 | Owner 双投影校验、clean 隔离提交、失败回滚与双 outbox | 12h | TASK-02 |
| TASK-04 | grant v1 共用验证、reject 权威回退、commit 边界与邻接幂等 | 12h | TASK-03 |
| TASK-05 | R7 权威 transitions parser 与 review-dev-plan 三路运行时契约 | 8h | TASK-04 |

退出条件：`crctl.test.mjs` 与 `lint-prompts.test.mjs` 的新增向量全部通过；`crctl.mjs` 保持单文件且无新依赖。

### M3 - Prompt 与跨仓采纳（14h）

| TASK | 交付内容 | 估算 | 依赖 |
|---|---|---:|---|
| TASK-06 | 同步 8 个 Skill、4 个 Pipeline、crctl Skill 与 3 份人读契约 | 8h | TASK-05 |
| TASK-07 | 扩展 Multica grant test-only 跨接缝并登记 CUSTOM.md | 6h | TASK-04 |

退出条件：Prompt lint、Skill/Agent contract、Pipeline JSON 全部通过；Multica 只有两项白名单文件发生变化。

### M4 - 集成验收（4h）

| TASK | 交付内容 | 估算 | 依赖 |
|---|---|---:|---|
| TASK-08 | 执行 AC-1～AC-32 全量验证、diff 白名单审计与测试报告取证 | 4h | TASK-06, TASK-07 |

退出条件：所有必跑命令退出 0，Multica 跨接缝未 skip，changed-files 精确落在 PRD FR-10.1 白名单。

总估算：`66h`（约 `8.25` 人天，单人串行口径）。

## 2. 任务依赖图

```text
TASK-01 red tests
   |
TASK-02 registration
   |
TASK-03 owner handover
   |
TASK-04 signed reject
   +--------------------+
   |                    |
TASK-05 R7/routes    TASK-07 Multica seam
   |                    |
TASK-06 prompts/docs ---+
   |
TASK-08 full verification
```

`TASK-02`～`TASK-05` 均修改 `crctl.mjs`，必须串行。`TASK-07` 只修改 Multica test-only 文件，可在 TASK-04 完成后与 TASK-05/06 并行；最终由 TASK-08 汇合。

## 3. 资源与分工

| 角色 | 负责人 | 工作内容 | 工时 |
|---|---|---|---:|
| 开发 Owner | Ray | tools 实现、Node 测试、Skill/Pipeline/文档同步 | 56h |
| 测试 Owner | Ray | Multica 跨接缝、全量验证与证据核对 | 10h |
| 需求 Owner | Ray | FR/AC 白名单与范围抽查 | 随 TASK-08 复核，不重复计时 |

不新增专职运维或平台 Runner 工作；CUSTOM-TODO-001～006 继续留在范围外。

## 4. 风险与回滚策略

| 风险 | 前置控制 | 回滚策略 |
|---|---|---|
| `crctl.mjs` 单文件多能力交叉回归 | TASK-02～05 串行，每项先红测后实现，保持既有 dispatch 和 helper 风格 | 按 TASK 原子提交逐项 revert，不拆模块 |
| Owner commit 失败污染 index/worktree | 真实 Git fixture 覆盖 staged/unstaged/mixed/untracked、CAS 与 unstage 失败 | 只用候选前快照 CAS 恢复本次两账本并复核 clean；不 reset/checkout 外部变化 |
| reject 把技术失败伪装成业务成功 | 仅 `committed=true` 返回 decline；邻接结果态检查 ledger 已在 HEAD | 返回 `ADVANCE_COMMIT_FAILED`/`GRANT_STATE_UNCOMMITTED`，不发 status outbox |
| R7 在 CRLF 或畸形 YAML 上静默漏检 | 读取后统一 CRLF，严格 parser 对缺失/空/截断 hard fail | revert parser 与对应规则；禁止空集合降级 |
| Prompt 与实现漂移 | TASK-06 静态断言 + `lint-prompts --mode enforce` | 同一 TASK 同步修正，节点数与 index 不变 |
| Multica test 被 skip 或越界修改 production | 显式 `CRCTL_PATH`，检查 verbose 输出与 changed-files | 删除越界 diff；只保留测试和 CUSTOM 台账 |
| outbox 写出失败 | Git commit 先形成权威事实，逐项记录 `EMIT_FAILED` | 不回滚 commit，交既有 daemon/reconcile 后续补偿 |

本 CR 不增加 feature flag。能力按原子提交可独立回滚；若回滚实现，必须同时回滚声明该能力已交付的 Skill/Pipeline/文档文本。

## 5. 验收与发布策略

### 5.1 TASK 级验收

- 每个 TASK 完成后立即把 `tasks/_index.yml` 对应状态更新为 `done`，不得积压到回写期。
- TASK-01～05 运行受影响的 Node 定向测试；TASK-06 运行 Prompt/Agent/Pipeline 静态检查；TASK-07 显式执行 Multica 定向 Go 测试。
- 接口、错误码和 trigger 必须与 SDD v0.1.1 精确一致，不以近似字符串替代。

### 5.2 全量发布前检查

```text
node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node skills/shared/crctl/scripts/check-agents-contract.mjs
node --test skills/shared/crctl/scripts/test/*.test.mjs
node --test skills/writeback/scripts/test/*.test.mjs
node -e <parse all pipeline JSON>
CRCTL_PATH=<tools-worktree>/skills/shared/crctl/scripts/crctl.mjs go test -v ./server/internal/governance -run TestGrantCrossVerifiesWithCrctl
```

另核对：tools changed-files 仅落在 FR-10.1；Multica production 与 CI workflow 零 diff；Pipeline 节点数和 `pipeline-templates/_index.yml#nodes` 不变；三个 worktree 无未登记修改。

### 5.3 发布与回滚

按现有 CR 流程完成 test-report、code review、人工 code approval 后进入 merge/writeback；不在 TASK 中手工绕过审批或状态机。发布顺序为 tools 先合入，再合入 knowledge-base 治理文档；Multica 仅携带测试与 CUSTOM 台账。失败时按 TASK 原子提交逆序 revert，并重新执行受影响验证。

## 6. 变更记录

| 日期 | 版本 | 说明 |
|---|---|---|
| 2026-08-11 | v0.1.0 | 初始开发计划，8 个 TASK、66h，覆盖 SDD v0.1.1 全部实施顺序与 AC-1～AC-32 |

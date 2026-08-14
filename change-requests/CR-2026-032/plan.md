---
id: CR-2026-032-plan
type: PLAN
cr-ref: CR-2026-032
sdd-ref: "change-requests/CR-2026-032/sdd.md"
target-version: tbd
status: draft
created: "2026-08-13T09:52:00+08:00"
updated: "2026-08-13T09:52:00+08:00"
---

# CR-2026-032 开发计划

## 1. 交付里程碑

### M1 - Archive 契约红测（6h）

| TASK | 交付内容 | 估算 | 依赖 |
|---|---|---:|---|
| TASK-01 | 冻结固定返回、必需 emitter、正常 outbox、失败 warning、终态不发送与重放幂等测试 | 6h | - |

退出条件：新增测试在当前实现上按预期失败，失败原因精确指向 SDD v0.2.0 尚未实现的契约；既有 archive 测试不删除、不放宽。

### M2 - Tools Archive 实现（8h）

| TASK | 交付内容 | 估算 | 依赖 |
|---|---|---:|---|
| TASK-02 | 扩展 `archiveCr()` 固定返回和 journal 发送事实，并由 `cmdArchive()` 注入 schema v1 outbox adapter | 8h | TASK-01 |

退出条件：TASK-01 红测全部转绿；origin confirmed、cleanup、outbox 失败和重放路径不新增 authority commit 或第二事务入口。

### M3 - 消费契约与人读语义（4h）

| TASK | 交付内容 | 估算 | 依赖 |
|---|---|---:|---|
| TASK-03 | 同步 `cr-archive` Skill、crctl 用途表（条件项）与 README 的 archive/cleanup 语义 | 4h | TASK-02 |

退出条件：文档只描述固定返回和业务阶段，不复制 cleanup 分类、journal phase、lease push 或 ancestry 算法；Prompt/Skill 静态检查通过。

### M4 - Multica 契约与跨仓验收（6h）

| TASK | 交付内容 | 估算 | 依赖 |
|---|---|---:|---|
| TASK-04 | 增加 Multica test-only archive 投影契约、登记 CUSTOM.md，并执行跨仓验证与 diff 白名单审计 | 6h | TASK-03 |

退出条件：Multica 目标测试实际 RUN/PASS，CR 投影为 archived、feature-writeback run 完成、重复幂等键只处理一次；production Go diff、migration、数据库 schema 和 ARC-02 相关文件零变化。

总估算：`24h`（约 `3` 人天，单人串行口径）。

## 2. 任务依赖图

```text
TASK-01 archive contract red tests
   |
TASK-02 tools archive implementation
   |
TASK-03 Skill / README semantics
   |
TASK-04 Multica contract + full verification
```

四个 TASK 按顺序执行。TASK-01/02 修改同一 archive 测试文件，必须串行；TASK-04 汇总 TASK-01～03 的完整产物并执行最终白名单审计，不提前并发以避免把中间态误判为跨仓契约失败。

## 3. 资源与分工

| 角色 | 负责人 | 工作内容 | 工时 |
|---|---|---|---:|
| 开发 Owner | Ray | tools 红测、archive 实现、Skill/README 同步 | 18h |
| 测试 Owner | Ray | Multica 契约测试、跨仓回归、diff 守卫 | 6h |
| 需求 Owner | Ray | ARC-03/04/05 与 ARC-02 排除边界抽查 | 随 TASK-04 复核，不重复计时 |

不新增数据库、消息队列、第三方依赖、Runner 或发布运维工作。Multica 只允许测试与 CUSTOM 台账改动。

## 4. 风险与回滚策略

| 风险 | 前置控制 | 回滚策略 |
|---|---|---|
| optional emitter 重新引入 FR-03 绕过路径 | TASK-01 先锁 `ARCHIVE_EMITTER_REQUIRED` 且断言 lock/journal/commit/push/outbox 均零副作用 | revert TASK-02；保留红测指示缺口，不允许无 emitter 兼容分支 |
| outbox 在 cleanup 后发送依赖已删除 worktree | 测试断言事件在 origin confirmed 后、cleanup 前从 installation workspace 落盘 | revert发送时序；不恢复已发布 archive commit，重跑同一事务 |
| outbox 文件成功但 journal 标记前中断导致重复 | 确定性 `dedup_name` + `outboxEmitted` + Multica 既有唯一键三层测试 | 删除错误实现并回退到警告+重跑；不新增 ACK ledger 或 exactly-once 协议 |
| cleanup 错误仍只进 journal | fault 测试断言 `lastCleanupError`、真实 commit 和 recoverCommand | 回滚返回 helper 改动；不改 cleanup 删除算法或 authority |
| remote rebuild 事件引用旧 SHA | 事件只消费 classify confirmed 后当前 `payload.commit` | 不发送旧 SHA 事件；按既有 archive 重跑收敛最终 commit |
| Multica 测试整包 skip 造成假绿 | TASK-04 使用 `go test -count=1 -v` 并核对目标测试 `=== RUN`/`--- PASS` | 记录未验证并阻止 test-report pass，不修改 TestMain 绕过数据库 |
| 误提前启用 ARC-02 | changed-files 白名单和既有 traceability fixture 锁定 gates/generator 零 diff | 立即 revert 越界改动，严格 gate 留给 T10A |

本 CR 不加 feature flag。实现按 TASK 原子提交可逆；回滚 tools 行为时必须同步回滚宣称该行为已交付的 Skill/README 文案，Multica test-only 提交可独立回滚。

## 5. 验收与发布策略

### 5.1 TASK 级验收

- TASK-01 先证明新增测试在旧实现上按预期失败，再进入 TASK-02；不得通过改旧断言适配错误行为。
- TASK-02 完成后运行 archive 定向测试与 crctl 回归；实现只使用 Node 标准库。
- TASK-03 运行 Prompt lint、Skill/Agent contract 与 Pipeline JSON parse；不改 feature-writeback 节点或参数。
- TASK-04 显式运行 Multica 数据库契约测试并核对无 skip，再执行最终 tools/Multica changed-files 审计。
- 每个 TASK 完成后立即通过 `crctl task done` 将 `_index.yml` 对应状态标为 done，不积压到回写期。

### 5.2 发布前检查

```text
node --test skills/shared/crctl/scripts/test/archive-tx.test.mjs
node --test skills/shared/crctl/scripts/test/crctl.test.mjs
node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node skills/shared/crctl/scripts/check-agents-contract.mjs
node -e <parse feature-writeback pipeline JSON>
DATABASE_URL=<real-test-db> go test -count=1 -v ./internal/governance/ -run '<CR-2026-032 archive contract test>'
```

另核对：

- archive 正常、cleanup fault、dirty pending、outbox failure/retry、complete replay、rejected、withdrawn 和 remote rebuild 全部有可复现证据；
- tools changed-files 只落在 SDD §1.2 白名单；`gates.json`、`dir-graph.yaml`、traceability generator 零 diff；
- Multica changed-files 只有一个既有 governance 测试文件与 `CUSTOM.md`，所有 production Go、migration、query/generated 文件零 diff；
- TASK 估算合计 `6+8+4+6=24h`，与本 Plan 总估算一致；所有接口消费/产出签名与 SDD v0.2.0 一致。
- 估算交叉校验：Plan 总工时 `24h`；TASK frontmatter 求和 `24h`；差异 `0h`。

### 5.3 发布与回滚

完成开发计划评审与人工开发启动审批后才进入编码。代码完成后按现有 test-report、checkpoint、code review、人工 code approval、merge/writeback/archive 流程发布，不在 TASK 内手工推进状态或审批。失败时按 TASK-04 → TASK-01 的逆序 revert，并重跑受影响验证；Git authority 已发布的 archive 事务不以补偿 commit 回滚。

## 6. 变更记录

| 日期 | 版本 | 说明 |
|---|---|---|
| 2026-08-13 | v0.1.0 | 初始开发计划：4 个顺序 TASK、24h，覆盖 SDD v0.2.0 的 ARC-03/04/05 与 T02，明确排除 ARC-02 |

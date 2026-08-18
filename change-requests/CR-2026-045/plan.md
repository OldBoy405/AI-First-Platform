---
id: CR-2026-045-plan
type: PLAN
cr-ref: CR-2026-045
sdd-ref: "change-requests/CR-2026-045/sdd.md"
target-version: tbd
status: draft
created: 2026-08-17T20:39:31+08:00
updated: 2026-08-18T18:39:17+08:00
---

# 1. 交付里程碑

基线：`tools@custom/main` `462c3e9`、`multica@origin/main` `da1eac2`、`docs@master` `3262dfb`。生产代码只写入 tools worktree（`.rayai-worktrees/tools/requirement/CR-2026-045`）与 multica worktree（`.rayai-worktrees/multica/requirement/CR-2026-045`）；plan/tasks 与 CR 账本写入 knowledge-base worktree。前端、移动端、CR gate UI 零改动。

| 里程碑 | 内容 | 依赖 | 估算 |
|---|---|---|---|
| M1 合同红测试 | TASK-01：tools 侧三组红测试冻结（replayLoop schema / registry 合同 / review outbox payload） | 无 | 4h |
| M2 tools 生成面 | TASK-02 architecture reviewLoop + emit-registry；TASK-03 crctl review outbox 确定性 payload | TASK-01 | 10h |
| M3 Multica 存储与生成 | TASK-04 双 partial unique index；TASK-05 生成 ArchitectureCoreRegistryJSON；TASK-06 CreatePipelineTask sqlc | TASK-04/06 独立；TASK-05 依赖 TASK-02 | 12h |
| M4 Runner 核心 | TASK-07 Start + Reconcile 幂等调度（双后置条件、attempt/replayNodes、loop exhausted、digest mismatch） | TASK-04、TASK-05、TASK-06 | 12h |
| M5 执行与唤醒 | TASK-08 daemon pipeline carrier；TASK-09 唤醒/ACK/router；TASK-10 commit-scan parity | TASK-07、TASK-03 | 19h |
| M6 纵切验收 | TASK-11：五节点 E2E + 手动路线回归 + CUSTOM.md 台账 | 全部 | 8h |
| M7 E2E hardening | TASK-12：review evidence outbox；TASK-13：active pipeline snapshot guard；TASK-14：push-progress workspace contract | TASK-11，顺序执行 | 9h |
| M8 迁移修复 | TASK-15：issue origin constraint 向前修复 migration | TASK-14 | 3h |

估算总工时：77h（约 9.6 人天）。

# 2. 任务依赖图

```text
TASK-01 (tools 红测试)
  ├─→ TASK-02 (architecture reviewLoop + emit-registry)
  └─→ TASK-03 (crctl review outbox payload)

TASK-04 (双 partial unique index)          [独立]
TASK-06 (CreatePipelineTask sqlc)          [独立]

TASK-05 (generate-gate-nodes 扩展)          depends: TASK-02
TASK-07 (Runner Start + Reconcile)          depends: TASK-04, TASK-05, TASK-06
TASK-08 (daemon pipeline carrier)           depends: TASK-07
TASK-09 (唤醒 + ACK + router wiring)        depends: TASK-07
TASK-10 (commit-scan review parity)         depends: TASK-03
TASK-11 (E2E + 回归 + CUSTOM 台账)          depends: TASK-02,03,04,05,06,07,08,09,10
TASK-12 (review evidence outbox)              depends: TASK-11
TASK-13 (active pipeline snapshot guard)      depends: TASK-12
TASK-14 (push-progress workspace contract)    depends: TASK-13
TASK-15 (issue origin migration repair)       depends: TASK-14
```

- TASK-01/04/06 相互独立，可并行；同仓测试文件冲突时串行。
- TASK-05 消费 TASK-02 的 `emit-registry.mjs` 输出，把 registry JSON + canonical SHA 嵌入 `gate_nodes_gen.go`。
- TASK-07 是核心，依赖 registry（TASK-05）、索引（TASK-04）与入队查询（TASK-06）。
- TASK-08/09 是 TASK-07 的执行载体与唤醒面；TASK-10 补齐 review 证据 parity，供 TASK-07 的 review 后置条件消费。
- TASK-11 负责原始纵切 E2E、手动路线回归与根目录 `CUSTOM.md` 对账。
- TASK-12~15 是该 E2E 暴露问题的 hardening 依赖链：先保证 review evidence 同步，再阻止 active pipeline 的 stale snapshot 覆盖，随后删除 workspace 占位符，最后修复独立 migration 回归。

# 3. 资源与分工

CR owners 均为 Ray（requirement/development/test）。单人顺序实施，依赖无环；并行仅在 TASK-01/04/06 三个无依赖块之间可选。

| 分工 | 负责 | 备注 |
|---|---|---|
| Ray | 全部 TASK | development/test owner |

# 4. 风险与回滚策略

| 风险 | 缓解 | 回滚 |
|---|---|---|
| Runner 与 projector 竞态产生双 run/task | 双 partial unique index 兜底；DB unique violation 是正常竞态输家路径，重读不循环 | 迁移纯加索引，`DROP INDEX CONCURRENTLY` 即可回滚 |
| review 证据来源不一致 | TASK-03 与 TASK-10 锁定 outbox/commit-scan parity；旧 payload 对 Runner fail closed | crctl/daemon 改动为纯追加字段，回滚不影响既有 review 投影 |
| attribution 新写路径漂移 | 单一 INSERT 从 source task 复制完整 snapshot + strict CHECK + 列清单测试 | 删除 `CreatePipelineTask` 查询，无 schema 变更 |
| Runner 误写 CR/Git | 职责隔离：Runner 只调度，Skill→crctl 写状态/Git；代码评审覆盖 | 关闭 Runner（feature off）回到手动路线，见 AC-15 |
| 恢复 digest 漂移 | digest 不同即 run failed，不猜旧模板；还原 digest 可继续 | 无多版本模板库，回滚即还原 digest |
| daemon 跨目录写被 sandbox 拒绝 | `workspace inspect` 的 operationalWorkspace 作为现有 LocalWorkDir，复用 realpath/path lock/cleanup | 关掉 pipeline kind 分支，普通任务不变 |
| review outbox 缺 evidence 导致 stale grant | `review-record` 复用已有 `collectOutboxEvidence`，server 不重算 | 回滚 review event 单字段，status/approve evidence 路径不变 |
| installation-root snapshot 覆盖 active pipeline projection | `ApplySnapshot` 复用已有 active `pipeline_run` 事实跳过该 CR | 取消 guard 后恢复旧 reconcile 行为，不改 daemon wire schema |
| workspace 占位符被 Agent 当路径 | Pipeline 只传业务输入，daemon 注入 `CRCTL_WORKSPACE`，crctl 解析仓库 | 回滚模板/生成物即可，手动显式 workspace 路线保留 |
| origin CHECK 重建丢值 | 新增向前 repair migration，完整九值集合，NOT VALID/VALIDATE 分离 | down migration 恢复到 264 后集合并 fail closed |

# 5. 验收与发布策略

发布前 checklist（对齐 PRD §8 验收标准）：

- [x] AC-01~AC-24 全部覆盖（TASK-11 E2E 与 TASK-12~15 hardening 验收逐项对应）
- [x] 数据库集成测试在真实 PostgreSQL 下 `=== RUN` / `--- PASS`，无 TestMain skip 假绿
- [x] 手动路线回归通过（Runner feature off 时行为不变，AC-15）
- [x] 静态检查证明模块职责边界（Agent/Pipeline/Skill/crctl/脚本/README）符合 PRD §2.2（AC-16）
- [x] 生产依赖、运行表、模板表、消息总线、通用 DSL/事务框架新增数量均为 0（AC-17/NFR-08）
- [x] 双周 rebase 前核对 CUSTOM.md 台账逐条成立

发布策略：`Runner` 仅支持 `architecture-design`；feature off 时零接管，feature on 后按 CR 投影 `requirement-approved` 才可启动。无 feature-flag 计划外的新入口——Start endpoint 已由 task-token Auth 约束。

# 6. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-17 | v0.1.0 | Ray | 初稿：11 TASK、65h、tools/multica 双仓纵切 |
| 2026-08-18 | v0.2.0 | Ray | E2E hardening scope amendment：新增 TASK-12~15，按 review evidence → snapshot guard → workspace contract → migration repair 顺序实施 |

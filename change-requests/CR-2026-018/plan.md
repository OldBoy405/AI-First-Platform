---
id: CR-2026-018-plan
type: PLAN
cr-ref: CR-2026-018
sdd-ref: "change-requests/CR-2026-018/sdd.md"
target-version: tbd
status: draft
created: "2026-08-04T16:00:00+08:00"
updated: "2026-08-04T16:00:00+08:00"
---

# PLAN — 状态推进单写 cr.md，_backlog.yml 退化为注册索引（T1-full）

## 1. 交付里程碑

| 里程碑 | 内容 | 估算 |
|---|---|---|
| M1 — crctl 核心改造 | resolveCrState 读路径收敛（FR-2）→ advance 单写（FR-1）→ backlog schema v2 + validate（FR-3）→ migrate-backlog 子命令（FR-5） | 4 人天 |
| M2 — 测试与适配器 | crctl 测试套件扩展（AC-1/2/3/5/9/10/11）→ inject-cr-status.mjs 改造（FR-8） | 2 人天 |
| M3 — 文档同步 | dir-graph.yaml scope 更新（FR-7）→ 16 个 skill 文档修订（FR-6+FR-9） | 2 人天 |
| M4 — 联调与验收 | 双适配器回归（claude-code + CI fixture）→ 端到端 merge-tree 零冲突演练（AC-9） | 1.5 人天 |

总估算 ≈ 9.5 人天。

## 2. 任务依赖图

```
TASK-01(resolveCrState/FR-2)
  └─→ TASK-02(advance单写/FR-1)
        ├─→ TASK-03(schema v2+validate/FR-3)
        │     └─→ TASK-04(migrate-backlog/FR-5)
        │           └─→ TASK-05(测试套件扩展)
        ├─→ TASK-06(inject-cr-status.mjs/FR-8)
        ├─→ TASK-07(dir-graph.yaml scope/FR-7)
        └─→ TASK-08(16个skill文档修订/FR-6+FR-9，依赖 TASK-04 提供迁移命令描述)
TASK-05 ─┐
TASK-06 ─┴─→ TASK-09(双适配器回归)
TASK-02 ─┐
TASK-08 ─┴─→ TASK-10(端到端 merge-tree 零冲突演练/AC-9)
```

关键路径：TASK-01 → TASK-02 → TASK-03 → TASK-04 → TASK-05 → TASK-09（M1+M2 串行部分）；TASK-08 可与 M1/M2 部分并行（一旦 TASK-02/04 落定即可动笔）。

## 3. 资源与分工

单人（Ray）全流程执行，无需跨角色分工。工时分配：M1 42%，M2 21%，M3 21%，M4 16%。

## 4. 风险与回滚策略

| 风险 | 应对 |
|---|---|
| crctl 核心改造引入回归，破坏现有 21 个用例 | TASK-05 先跑现有套件建回归线，M1 每个子任务落地后立即跑一次全量套件 |
| 16 个 skill 文档漏改（历史教训：批量文档修订最易漏项） | TASK-08 附逐文件 checklist（评审 suggestion #3），完成标志要求逐条勾选 |
| 迁移窗口期新旧 crctl 混用（SDD §7 残余风险） | TASK-04 交付 MIXED_LAYOUT_WARN；TASK-09 回归含混版 fixture；发布说明显式提示统一版本 |
| 本 CR 改造完成但未回写前，其他在途 CR 仍用旧布局写状态 | 本 CR 只改 tools 包代码与文档，不强制迁移存量 workspace；`migrate-backlog` 是可选一次性命令，各 workspace 自行择机执行，不阻塞本 CR 回写 |
| 回滚 | 全部改动可整体 revert（crctl 单文件改造 + 文档），cr.md 与 backlog 双写在改造前后均保留数据不丢失 |

## 5. 验收与发布策略

- 发布前 checklist：TASK-05 全绿 + TASK-09 双适配器回归通过 + TASK-10 端到端 merge-tree 零冲突演练通过。
- 不设 feature-flag：crctl 是内部工具链，无生产流量灰度概念；改造对现有 workspace 是可选迁移（`_backlog.yml` 仍含 status 时兼容读继续生效），天然渐进。
- 发布说明需包含：迁移命令用法、混版告警含义、"迁移后统一 crctl 版本"提示（SDD §7 残余风险 + 评审 suggestion #1）。
- 下一步：`write-dev-tasks` 拆解为 TASK-01~10。

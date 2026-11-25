# BUILD 切片执行计划

## Dependency Graph Summary

```text
fork-custom-behavior (zero dependency) ----+
                                           +--> Slice 7 --> Slice 8
upstream-sync-merge (zero dependency) ------+
          |
          +--> Slice 1 --> Slice 2
                      +--> Slice 3
                      +--> Slice 4
                      +--> Slice 5
                      +--> Slice 6
```

- nodes=2，edges=0，cycles=0。
- 并行组 1：Slice 3、4、5、6 在 Slice 1 后技术上可并行；主会话按顺序执行，避免共享 worktree 与 Admin client 文件冲突。
- 并行组 2：Slice 7 依赖 Slice 2-6 的候选信号。
- 并行组 3：Slice 8 依赖全部前置切片。

**执行调整（2026-11-25）**：Slice 6 Graph 缺口位于本次上游窗口未改动的 FORK 文件，属于既有问题，按用户“只拉取上游更新”的指令移出本次范围；不实现、不登记。Slice 5 定向通过，但 Windows 全量 runner 基线导致 B3.4 全量回归未完成，登记保留。Slice 7 以合并面定向批次、`remaining` CP 和 Admin 全套为准。

## Slice Execution Plan

| # | 优先级 | 风险 | 工作量 | 并行组 | TC 覆盖 | 实现目标 | 依赖 |
|---|---|---|---|---|---|---|---|
| 1 | P0 | 高 | L | — | TC-USM-001,002,003 | 隔离 worktree、三方合并、516 路径归因、6 个双边路径裁决 | 无 |
| 2 | P0 | 高 | L | — | TC-USM-004,005,006 | 上游行为、迁移顺序、registry、生成物 freshness/无漂移 | 1 |
| 3 | P0 | 高 | M | 组1 | TC-FCB-001 | Inbox managed/unmanaged 实际写入与 auto-link 守卫 | 1 |
| 4 | P0 | 中 | S | 组1 | TC-FCB-002 | Admin 先鉴权后分派与恰好一条审计 | 1 |
| 5 | P0 | 高 | M | 组1 | TC-FCB-003 | trace.retrieval、MCP/CLI/Admin 诊断保留 | 1 |
| 6 | P0 | 高 | L | 组1 | TC-FCB-004 | Graph 可见性、degree、双引擎元数据与 parity | 1 |
| 7 | P1 | 高 | M | 组2 | TC-FCB-005 | 其余 fork 能力与 Admin 全量回归 | 2,3,4,5,6 |
| 8 | P0 | 高 | L | 组3 | TC-USM-007,008,009 | A/B 归因、全量门禁、台账、分父与交付边界审计 | 7 |

## Rationale

### Slice 1：隔离候选与三方合并

- 依赖：所有后续修改必须建立在可回滚的隔离候选上。
- 风险：Git 无文本冲突仍可能丢行为；生成物和共享文件不能整文件选边。
- 工作量：涉及 6 个双边路径、66 个上游单侧路径和 516 个 fork 路径归因，属于 L。
- 经验库：当前无匹配记录。

### Slice 2：上游行为、迁移与生成物

- 依赖：必须先完成合并，才能验证上游新合同和生成物真源。
- 风险：base-ref skip、Admin dist skip、版本号相同但旧库结构不同均可能制造假通过。
- 工作量：覆盖 persistence/cycle/repair、迁移和多个生成器，属于 L。
- 经验库：当前无匹配记录。

### Slice 3：Inbox managed 内容

- 依赖：需要合并后的 ingest-capture 调用链。
- 风险：只测预处理函数无法证明实际落库；auto-link 必须保留权限守卫。
- 工作量：一个产品路径及两组定向测试，属于 M。
- 经验库：当前无匹配记录。

### Slice 4：Admin 鉴权与审计

- 依赖：需要合并后的路由和 dispatch。
- 风险：鉴权顺序或审计重复属于安全/合同回归。
- 工作量：以现有 route guard 测试为主，属于 S。
- 经验库：当前无匹配记录。

### Slice 5：query.trace 诊断链

- 依赖：需要合并后的 op emit、MCP dispatch、CLI 和 Admin client。
- 风险：trace 与 `_meta` 职责混淆会重复或丢失诊断。
- 工作量：跨根测试、CLI 和 Admin，属于 M。
- 经验库：当前无匹配记录。

### Slice 6：Graph 可见性与 parity

- 依赖：需要合并后的 Graph SQL 和 operation policy。
- 风险：不可见边污染 degree 或 Postgres 未实际执行均属高风险。
- 工作量：双引擎 SQL、op policy、多层测试，属于 L。
- 经验库：当前无匹配记录。

### Slice 7：其余 fork 能力回归

- 依赖：前置修复与生成物必须稳定。
- 风险：keyless skip 和 Windows 既有失败可能被误报为通过或新增回归。
- 工作量：多个台账能力与 Admin 全套，属于 M。
- 经验库：当前无匹配记录。

### Slice 8：综合复核与最终审计

- 依赖：全部 TC 需有候选树实际信号。
- 风险：基线缺口与 merge 回归混淆、whitespace 双亲误判、越权交付。
- 工作量：A/B、全量质量门禁、三路评审和 Git 审计，属于 L。
- 经验库：当前无匹配记录。

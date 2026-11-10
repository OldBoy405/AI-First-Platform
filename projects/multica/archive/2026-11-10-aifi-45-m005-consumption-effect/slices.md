# AIFI-45 M005 consumption-effect — 切片执行计划

## Dependency Graph Summary

```
authorized-runner(MODIFIED 仅文字) ──依赖──> consumption-effect
S1(签发+原子) ──> S2(链连续+守卫+新 generation)
```

两个切片同文件、同事务路径，不并行。

## Slice Execution Plan

| # | 优先级 | 风险 | 预估工时 | 并行组 | TC 覆盖 | 实现目标 | 依赖 |
|---|--------|------|---------|--------|---------|---------|------|
| 1 | P0 | 🟡 Med | M | — | TC-CE-001, TC-CE-002 | `issueConsumptionEffectTx` + handler 接线 | 无 |
| 2 | P0 | 🟡 Med | S | — | TC-CE-003, TC-CE-004 | lineage 锁后守卫、cursor 下一格、跨 CR | 1 |

## Rationale

### Slice 1：签发与原子（先行）
- 风险：触及 consumption 热路径与信任链写入口；经验库无匹配（0 条）；Scenario 4 个、跨模块（handler↔control store）→ 风险分 2。
- 工作量：2 个 TC，新增 1 文件、改 1 文件 → M。

### Slice 2：链连续与守卫
- 依赖 S1 的签发函数。守卫与 seq/prev 读取在设计里属同一函数，S1 可能已一并满足；若 TC 首次运行即绿，如实记为「RED 未失败」，并用变异（去掉守卫/改回常量 store）证明测试能抓到。

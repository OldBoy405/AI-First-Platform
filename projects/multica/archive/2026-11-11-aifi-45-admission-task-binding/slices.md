# AIFI-45 admission-task-binding 切片执行计划

## Dependency Graph Summary

`stdd dependency-graph --format json`：节点 `admission-task-binding`、`authorized-runner`，均为零依赖，edges / cycles 均为空。实现上两者共用准入接口及 fixture，需按以下顺序完成；真实链测试依赖统一门禁实现。

```text
切片 1：任务与代次准入 + 所有受保护动作 + 原回归
    → 切片 2：真实 consumption → discovery 链路和 replay
```

不标记并行组：两个切片共享数据库测试夹具，且第二片依赖第一片的行为；并行会增加不必要的集成风险。

## Slice Execution Plan

| # | 优先级 | 风险 | 估算 | TC 覆盖 | 实现目标 | 依赖 |
|---|---|---|---|---|---|---|
| 1 | P0 | 高（4+） | L | TC-ATB-001～007、TC-RUN-003 | 锚点及当前代次判定、Runner 动作锚点、既有 fixture、`--only` 与选择；保留现有完整回归 | 无 |
| 2 | P0 | 高（跨真实路由与发现） | M | TC-ATB-008～010 | 真实路由、无自动唤醒、重复发现、节点任务消费与 M005 replay；完整回归 | 1 |

## Rationale

### Slice 1：统一准入边界及调用方

- 风险：新增 task / generation 边界，涉及 SQL、锁及各动作；有 EXP-2026-0002（锁后读）和 EXP-2026-0005（拒绝条件独立测试）的 discovered 提醒。经 B2 查询，当前没有 verified/settled Go 经验，不能误记为已验证经验。
- L 粒度不可再安全切开：收紧共享 decider 若不同时迁移 Runner 调用方与旧 fixture，会使完整回归在中间状态必然失败。按功能顺序写 RED、实现，再整体 B3.4 验证，不新增中间兼容层。
- 先为 `--only` 写测试并实现；逐一补 ATB-001～007，每个独立 TC 有独立 selection；执行 slice 测试与全量 selections 后才登记完成。

### Slice 2：真实路由与发现

- 复用既有真实路由 fixture 和 TaskService，分别覆盖 TC-ATB-008～010；不能以直接写回执或模拟 wake 代替真实链。
- 增加本片的 3 个 selection；每个 TC RED → GREEN，最后执行本片与全部 selections；每片核对 TC、产物和真实测试结果后才登记。

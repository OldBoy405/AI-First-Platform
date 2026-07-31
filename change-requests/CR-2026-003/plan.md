---
id: CR-2026-003-plan
type: PLAN
cr-ref: CR-2026-003
sdd-ref: "change-requests/CR-2026-003/sdd.md"
target-version: "0.11.1"
status: draft
created: "2026-07-31T21:00:00+08:00"
updated: "2026-07-31T21:00:00+08:00"
---

# CR-2026-003 开发计划

## 1. 交付里程碑

单里程碑修补 CR，总估算 12h：

| 阶段 | 内容 | 估算 |
|---|---|---|
| 实现 | T01（tools/crctl 占位符）+ T02（multica 双修复 + 防护） | 7h |
| 验收 | T03（端到端 + 历史数据真实收敛） | 5h |

## 2. 任务依赖图

```
T01 (tools: pendingCommitSha)  ──┐
                                 ├──> T03 (端到端验收 + AC-3 历史收敛)
T02 (multica: 服务端防护 +      ──┘
     reconcile 历史快照)
```

T01 与 T02 分属两仓、互相独立可并行；T03 依赖两者全部完成（需要重建 backend 镜像 + 重启 daemon 才能真机验收）。

## 3. 资源与分工

单人（Ray）串行执行，无并行需求。T01/T02 顺序任意。

## 4. 风险与回滚策略

| 风险 | 缓解 | 回滚 |
|---|---|---|
| `pending:` 前缀契约两语言漂移 | 两侧测试锁同一字面量（SDD §4.1） | 单仓 revert 即可（两处改动互相独立，回滚任一侧都退回到"空串碰撞"的已知旧行为，不会产生新故障模式） |
| `_history.yml` 解析失败导致对账整体报错 | 解析失败硬失败（快照该周期作废、下周期重试），不静默吞；文件不存在视为空 map（新仓库无历史是正常态） | 同上，revert multica 侧提交 |
| AC-3 收敛依赖真实对账周期，验收窗口受 RECONCILE_INTERVAL 影响 | 验收环境已配 1m 周期（T11 遗留配置），单周期内可观察 | 不适用（验收动作） |

## 5. 验收与发布策略

- 发布 = 重建 backend 镜像（multica main）+ 重启 daemon（新二进制）——与 CR-2026-002 T11 相同的环境刷新流程，compose 项目已迁至 multica 主检出（cleanup-report side-effects-handled 项），本次直接在主检出操作。
- 发布后验收顺序：AC-1（新 CR 上双 embedded 推进）→ AC-2（历史 CR 快照自愈集成测试已先行）→ AC-3（观察 CR-2026-001/002 在真实对账周期内收敛为 archived，**不允许手工 UPDATE**）。
- 无 feature flag：两处修复都是缺陷修复而非行为开关，且旧行为（事件丢失/无法自愈）没有任何保留价值。

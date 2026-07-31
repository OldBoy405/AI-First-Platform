---
id: CR-2026-004-plan
type: PLAN
cr-ref: CR-2026-004
sdd-ref: "change-requests/CR-2026-004/sdd.md"
target-version: "0.12"
status: draft
created: "2026-08-01T00:50:00+08:00"
updated: "2026-08-01T00:50:00+08:00"
---

# CR-2026-004 开发计划

## 1. 交付里程碑

单里程碑功能 CR，只动 multica 仓（后端 + 前端），知识库仓无代码任务。总估算 18h：

| 阶段 | 内容 | 估算 |
|---|---|---|
| 实现-后端 | T01（迁移 + 守卫 + priority 覆盖 + HTTP 边界 + 撤回权限） | 8h |
| 实现-前端 | T02（packages/views 队列条禁用态 + WS 触发） | 6h |
| 验收 | T03（端到端 AC-1~5 真机验收） | 4h |

## 2. 任务依赖图

```
T01 (multica 后端: 迁移/守卫/429/撤回权限) ──> T02 (前端: 队列条 + 禁用态)
                                          └──> T03 (端到端验收 AC-1~5)
T02 ──────────────────────────────────────────┘
```

T02 依赖 T01 的 API 契约（429 响应体、queue_depth/queue_limit 字段）；T03 依赖两者全部完成（重建 backend 镜像 + 前端构建后真机验收）。

## 3. 资源与分工

单人（Ray）串行执行：T01 → T02 → T03。

## 4. 风险与回滚策略

| 风险 | 缓解 | 回滚 |
|---|---|---|
| 守卫误伤既有入队路径（deferred/retry/autopilot/chat 被错误卡容量） | SDD §1 INSERT 点裁决表锁死范围：只有 CreateAgentTask / CreateQuickCreateTask 两个用户路径过守卫；集成测试逐路径断言不过守卫的路径在满队时仍可入队 | revert multica 提交即回到无上限旧行为，无数据损坏（守卫只拒绝、不改写） |
| priority=100 与未来 upstream 新档位冲突 | 常量集中定义 + 注释标明档位地图（0-4 普通 / 100 治理插队）；fork 合 upstream 时 grep priority 字面量 | 改常量值即可，无数据迁移（priority 只影响 claim 排序） |
| 撤回权限边界破坏既有 owner 停止语义 | 权限检查只加在新/扩展端点，`CancelTaskWithResult` 服务本体零改动；既有 owner 停任意路径回归测试覆盖 | revert handler 层提交，服务层无变化 |
| project.settings 迁移与 upstream 撞号 | 合入时按最新编号取值，rebase 重排（SDD §2） | down 迁移 DROP COLUMN，无数据依赖 |
| 并发窗口超限（弱一致） | PRD NFR-2 已界定接受；测试断言用 ≥ limit 判满 | 不适用（设计内行为） |

## 5. 验收与发布策略

- 发布 = 重建 backend 镜像（multica worktree 构建，与 CR-2026-002/003 同口径）+ 前端构建；daemon 无改动本次不需换二进制。
- 验收顺序：AC-1（满队拒绝）→ AC-3（改配置上限生效）→ AC-2（owner/admin 插队先被 claim）→ AC-4（撤回软删 + 审计行保留）→ AC-5（WS 实时更新，双浏览器会话观察）。
- 数据库审计口径沿用平台惯例：验收查询只 SELECT，禁止手工写投影/队列表。
- 无 feature flag：上限默认 50 且 owner/admin 全豁免，对既有小团队使用形态几乎无感；真出问题 revert 即回旧行为。

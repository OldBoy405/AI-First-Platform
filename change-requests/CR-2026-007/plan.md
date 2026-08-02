---
id: CR-2026-007-plan
type: PLAN
cr-ref: CR-2026-007
sdd-ref: "change-requests/CR-2026-007/sdd.md"
target-version: "0.14"
status: draft
created: "2026-08-02T13:10:00+08:00"
updated: "2026-08-02T13:10:00+08:00"
---

# CR-2026-007 开发计划

## 1. 交付里程碑

后端两块（全读侧 + 一处权限调序）+ 前端三块 + 端到端验收，共 6 任务，总估算 26h：

| 阶段 | 内容 | 估算 |
|---|---|---|
| T01 | 后端：queue-status `include=items`（ListProjectPendingTasks + trigger_summary 直读）+ AgentTaskResponse originator 字段 | 5h |
| T02 | 后端：CancelTaskByUser 权限调序（originator 先行放行）+ 幂等/权限单测 | 3h |
| T03 | 前端 core：items schema/query（queueStatus 前缀 key）+ 撤回 mutation 三分支 + store 过滤字段 | 4h |
| T04 | 前端 views：project-queue-bar 组件（常驻/展开/撤回/停止/占位）+ 四语文案 | 5h |
| T05 | 前端 views：消息流增强（运行卡停止钮/过滤摘要形态/已撤回角标/复制）+ 四语文案 | 5h |
| T06 | 端到端验收：AC-1~6 双浏览器全场景 | 4h |

## 2. 任务依赖图

```
T01 (items 端点 + originator 字段)      T02 (cancel 权限调序)
 └─> T03 (core: schema/query/mutation/store)
        ├─> T04 (queue-bar 组件)
        └─> T05 (消息流增强)
T02/T04/T05 ──> T06 (E2E 验收)
```

T01 与 T02 无相互依赖，可并行开工；T03 需要 T01 定型响应 shape；T04/T05 依赖 T03 的
core 层但相互独立可并行；T06 收尾。

## 3. 资源与分工

单人（Ray）+ 并行子代理：T01/T02 并行 → T03 → T04/T05 并行 → T06。

## 4. 风险与回滚策略（技术评审 7 条 TSUG 全部织入对应任务，见各 TASK 文件）

| 风险 | 缓解 | 回滚 |
|---|---|---|
| **DD-2 权限调序引入越权**（T02） | 只对 `originator==caller` 放行（服务端落库 ID 不可伪造）；非发起人路径原样；单测双向覆盖（private agent 自撤 200 / 他人 403） | 单 if 调序，revert 即回旧行为（回退代价=私有 agent 下自撤回 403，与现状一致） |
| **items 口径与 depth 漂移**（T01，TSUG-004） | 同一 status 过滤复制 + 单测断言 count==len(items)，造数含 NULL originator 任务 | 读侧新增，revert 无副作用 |
| **幂等竞态误报**（T03，TSUG-007） | mutation 三分支：cancelled 静默成功 / 其它终态「已结束」toast / 403 message；测试覆盖三分支 | 纯前端分支 |
| **过滤形态渲染 JSON 垃圾**（T05，TSUG-003） | 摘要形态只渲染 `result.output`，空串占位 | 纯 render 分支 |
| sqlc CRLF 噪音（T01） | `git diff --ignore-all-space --numstat` 甄别（CR-A 流程） | — |
| queue-status 既有消费方回归 | include 为 opt-in，无参响应逐字节一致（T01 对拍单测固化）；T06 回归 D1 sidebar 与 CR-A 满队恢复 | — |

## 5. 验收与发布策略

- 发布：随 CR 合并进 multica main；**无迁移**、无 feature flag——items 为 opt-in 参数、
  新组件为新增路径、cancel 调序为放宽（不破坏既有调用方）。
- 验收顺序：T01/T02 后端单测（对拍/口径/幂等/权限）→ T03/T04/T05 前端联调 →
  T06 按 PRD AC 顺序：实时可见（双浏览器）→ 撤回三路径 + DB 审计 → 停止双权限 +
  被停者对账 → 过滤开关 DOM/网络断言 → 兼容对拍 + 非群聊来源覆盖 → 复制/parity/回归。
- 真机验收沿 CR-A 口径：数据库只 SELECT；daemon 执行段若本机无 runtime，用 synthetic
  runtime 做 API 级验证并如实标注。

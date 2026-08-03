---
id: CR-2026-011-plan
type: PLAN
cr-ref: CR-2026-011
sdd-ref: "change-requests/CR-2026-011/sdd.md"
target-version: "0.18"
status: draft
created: "2026-08-02T12:40:00+08:00"
updated: "2026-08-02T12:40:00+08:00"
---

# CR-2026-011 开发计划

## 1. 交付里程碑

后端四块 + 前端两块 + 端到端验收，共 7 任务，总估算 36h：

| 阶段 | 内容 | 估算 |
|---|---|---|
| T01 | 后端：migration 161（pipeline 两表 + B4 两列）+ retry 克隆清单 + sqlc + CUSTOM.md 登记 | 4h |
| T02 | 后端：门禁节点投影器（状态映射表 + node_id 决议单点函数 + cr:updated 发布） | 6h |
| T03 | 后端：review 事件通道（daemon 第 5 类扫描正则 + git show yml payload + 服务端 kind 放行） | 4h |
| T04 | 后端：gates 端点 + canApprove 角色策略 + pending_advance 派生 + StartTask cr_id 归因 | 6h |
| T05 | 前端：client 层（api/query/cr:updated 三点接线/404 降级）+ CrStatusBadge + 四语文案 | 4h |
| T06 | 前端：CrGateCard 三变体 + 消息流合并插入 + 执行卡迷你门禁条 + 批准/驳回交互 | 6h |
| T07 | 端到端验收：AC-1~7 全场景（含真实 grant 链路无 TTY 实跑） | 6h |

## 2. 任务依赖图

```
T01 (migration 161)
 ├─> T02 (投影器) ──> T03 (review 事件通道)
 ├─> T04 (gates 端点 + 归因)
 │        └────────┬─> T06 (CrGateCard + 交互，依赖 T04/T05)
 └─> T05 (client 层 + 徽标) ──┘
                 T07 (E2E 验收，依赖 T02/T03/T04/T06 全部完成)
```

T01 是唯一硬前置（两表 schema 决定投影器与端点的落点）；T02/T04/T05 可并行；
T03 依赖 T02 的投影 apply 分支；T06 收前端；T07 收尾。

## 3. 资源与分工

单人（Ray）串行执行，按依赖图顺序 T01 → T02/T04/T05 并行 → T03/T06 → T07。

## 4. 风险与回滚策略

| 风险 | 缓解 | 回滚 |
|---|---|---|
| **TSUG-001**：网页批准后到 crctl 推进前的窗口，卡片若退回可批准态会诱导重复操作 | T04 在 gates 响应中 join approval_record 派生 `pending_advance` 服务端状态；T06 按此渲染「已批准，等待推进」跨端一致态；T07 验证刷新/他端一致 | grant 幂等兜底重复点击，退化仅体验问题不损数据 |
| **TSUG-002**：node_id 决议若在投影器与未来 Runner（CR-H）各写一套，同一节点裂成两行 | T02 把决议函数固化为 governance 包公共函数 + 测试向量；任务期核实 tools 模板有无稳定节点 UUID 并把结论写进函数注释 | 决议函数单点，改算法=改一处+迁移脚本重算 node_id |
| **TSUG-003**：gates 是 governance 组首个 project 级路由；cr.shell_issue_id NULL 历史行会从 join 静默消失 | T04 对齐 project 路由组既有成员校验中间件；NULL 行不展示写为显式语义并入 T07 验收说明；存量数据 SELECT 预检 | 端点新增路径，revert 即回到无门禁 UI 状态 |
| review commit message 措辞漂移致扫描 miss | 正则只锚 `[cr] review-{stage} {CR-ID}: verdict=` 前缀段；miss 仅丢 blocked 卡增强，审批卡不受影响（SDD DD-2 降级安全） | 扫描是纯增量通道，关闭正则即回退 |
| 并行 CR-B~E 同期抢 migration 161 编号 | lint 测试强制唯一，冲突编译期即爆；CUSTOM.md 登记即认领，合并序重号 | 重号仅改文件名与登记行 |
| HandleApprove 加角色策略收紧已交付 API | 前端调用方本就不存在、daemon 不调该端点，实际影响面为零；既有 grant/409/幂等单测保持绿 | 单函数校验，revert 即回到"任成员可批" |
| approvalSvc 未配置环境 UI 异常 | T05 落 404→disabled 降级并单测；T07 在未配置环境跑一遍冒烟 | 前端探测分支，无后端耦合 |
| 投影器事件乱序/重放 | UNIQUE(run_id,node_id,attempt) upsert 幂等 + crsync 既有 per-CR 串行消费 | 投影表可清空重放（事件账本在 cr_sync_event） |

## 5. 验收与发布策略

- 发布：随 CR 正常合并/回写进 multica main；migration 161 随部署管道执行。
- 无 feature flag，但有**天然开关**：全部门禁端点挂 `APPROVAL_SIGNING_KEY` 条件组（SDD DD-8），
  未配置环境完全无感——等价于按环境灰度。
- 验收顺序：T01 后先跑迁移回归（AC-5）→ T02/T03 投影单测（映射表全态 + review 事件幂等）→
  T04 三个拒绝路径与 pending_advance 单测 → T05/T06 联调 → T07 端到端
  （依 PRD 顺序：核心链路 → 驳回 → blocker → 徽标 → 迁移回归 → 安全回归 → 双端/locale）。

---
id: CR-2026-010-plan
type: PLAN
cr-ref: CR-2026-010
sdd-ref: "change-requests/CR-2026-010/sdd.md"
target-version: "0.17"
status: draft
created: "2026-08-02T13:57:20+08:00"
updated: "2026-08-02T13:57:20+08:00"
---

# CR-2026-010 开发计划

## 1. 交付里程碑

后端四块（迁移+claim改造、presenter 服务、发送端点接入、通知）+ 前端两块 + 端到端验收，
共 7 任务，总估算 34h：

| 阶段 | 内容 | 估算 |
|---|---|---|
| T01 | 后端：M161-163 迁移（project_id 列+回填+索引、presenter_grant 表）+ claim SQL 改造 + advisory lock 竞态复核 | 6h |
| T02 | 后端：presenter 服务（grant 状态机 6 转移）+ 7 个 API 路由 + 成员移除联动 | 6h |
| T03 | 后端：发送端点控制权守卫接入（403 presenter_required）+ 插队优先级抑制 | 3h |
| T04 | 后端：通知双通道（activity_log + notifyDirect + WS 事件） | 4h |
| T05 | 前端：presenter 数据层（schemas/client/queries/mutations）+ chatHeader 主持人显示 | 3h |
| T06 | 前端：chatControlPanel 权限面板 + 消息流通知卡 + 拒绝呈现 + 四语文案 | 6h |
| T07 | 端到端验收：AC-1~5 + §6.3 四组回归 | 6h |

## 2. 任务依赖图

```
T01 (迁移 + claim 改造，独立成 CR 的风险核心)
 ├─> T02 (presenter 服务 + API)
 │      ├─> T03 (发送端点接入，读 active grant)
 │      ├─> T04 (通知，读转移事件)
 │      └─> T05 (前端数据层，读 API 契约)
 │             └─> T06 (面板/通知卡/拒绝态/文案)
 └──────────────────────────────────────────┴──> T07 (E2E 验收，依赖 T03/T04/T06 全部完成)
```

T01 是唯一硬前置且风险最高（claim SQL 是全平台共享热路径，改动范围严格限定见 SDD §4.1）；
T02 就绪后 T03/T04/T05 可并行；T06 需要 T05 的数据层与组件契约；T07 收尾。

## 3. 资源与分工

单人（Ray）串行执行，按依赖图顺序 T01 → T02 → T03/T04/T05 并行 → T06 → T07。

## 4. 风险与回滚策略

| 风险 | 缓解 | 回滚 |
|---|---|---|
| claim SQL 改写破坏既有三分支语义（本 CR 首要风险，独立成 CR 的主因） | T01 严格按 SDD §4.1 只新增 project 分支、三个既有分支原样保留；`make sqlc` 后 diff 审查限定 agent.sql.go；T07 跑 §6.3 四组回归全绿方可推进 | project 分支可整体 revert 为原 SQL（单个 CASE 分支移除），三个既有分支不受影响 |
| **TSUG-001**：M161 全表回填 UPDATE 在热表上有锁窗口，对终态行（completed/failed/cancelled）回填无意义 | T01 回填限定 `WHERE atq.status NOT IN ('completed','failed','cancelled')`，缩小锁窗口与写入量 | 回填是一次性脚本，缩小 WHERE 范围不影响可回滚性 |
| **TSUG-002**：定向 inbox 的 IssueID 指向隐藏容器 Issue，若沿用默认路由会深链到被隐藏的 Issue 页 | T04 五类 presenter inbox 的路由分支显式改走 `details.project_id` 深链项目 Chat tab（`?tab=chat`），T07 逐类型点击核对落点 | 路由分支是前端 switch-case 一条，回滚不影响后端数据 |
| **TSUG-003**：GET /presenter 对非 owner/admin 过滤 pending 列表时，若连本人的 pending 也一并过滤，前端"申请中"态无数据源 | T02 响应体显式分 `presenter` / `pending_requests`(仅 owner/admin 可见完整列表) / `my_request`(任何角色可见本人) 三段，写入接口契约测试 | 响应体加字段不改变既有字段，纯扩展 |
| claim 竞态复核引入的 advisory lock 与既有 per-agent `FOR UPDATE` 锁交互产生死锁 | T01 严格遵循 SDD DD-4 的加锁顺序（UPDATE 提交后才取 advisory lock，不嵌套等待）；T07 并发测试验证恰一成功且无死锁日志 | advisory lock 调用是独立语句，可整体注释掉退回"仅 per-agent 锁"（接受短暂跨 agent 竞态窗口） |
| presenter grant 表并发写入产生双 active | T02 partial unique 索引（`project_id WHERE status='active'`）DB 层兜底 + advisory xact lock 前置; T07 并发申请/批准测试 | 索引本身是安全网，无需额外回滚路径 |
| 消息流通知卡改动影响既有 activity filter | T06 放宽 filter 仅新增 `presenter_*` action 白名单，不改变既有 comment 过滤逻辑；T07 回归验证既有群聊消息流显示不变 | filter 白名单是一行条件，可整体 revert |
| 前端四语遗漏导致 parity 测试红 | T06 新增 key 与四语同批提交，CI 强制 | 单个 key 的四语可独立补齐，不阻塞其他改动 |

## 5. 验收与发布策略

- 发布：随 CR 正常合并/回写流程进入 multica main；DB migration（M161-163）随部署管道执行，
  M161 回填脚本建议在低峰期执行（TSUG-001 缓解）。
- 无 feature flag：presenter 默认态（`presenter==null`）等价于现状（owner/admin 可发送、
  普通成员被拒引导申请）——这是设计稿既定的默认行为而非新增开关，六转移 API 与 UI 入口
  同批上线即生效。
- 验收顺序：T01（迁移+claim 改造）先完成后端单元/集成测试（并发 claim、advisory lock 无死锁）
  → T02/T03/T04 后端联调（grant 状态机、守卫拒绝、通知双通道）→ T05/T06 前端联调
  → T07 端到端跑 AC-1~5（依 PRD 顺序：单一写者→状态机全覆盖→claim 回归→服务端权威→四语双端）。

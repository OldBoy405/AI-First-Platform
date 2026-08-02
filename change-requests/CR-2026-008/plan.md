---
id: CR-2026-008-plan
type: PLAN
cr-ref: CR-2026-008
sdd-ref: "change-requests/CR-2026-008/sdd.md"
target-version: "0.15"
status: draft
created: "2026-08-02T11:25:00+08:00"
updated: "2026-08-02T11:25:00+08:00"
---

# CR-2026-008 开发计划

> 依据 SDD rev 0.1.1（含 DD-6 修订：Ask-only 需最小强制，非既有语义白拿）。
> 技术评审 3 条建议（SDD-SUG-001/002/003）在本计划的落点：SUG-001 → T02 的发布点全量清单
> （已在拆分期完成 grep，清单固化进 TASK-02 验收）；SUG-002 → 已核实并触发 SDD rev 0.1.1，
> 落为独立任务 T03；SUG-003 → T04 的 tooltip 文案项。

## 1. 交付里程碑

后端三块 + 前端一块 + 端到端验收，共 5 任务，总估算 24h：

| 阶段 | 内容 | 估算 |
|---|---|---|
| T01 | 后端：M1 迁移 + sqlc 查询（get-or-create/排除谓词）+ `GET /api/projects/{id}/private-chat` | 4h |
| T02 | 后端：隐私收敛——Event 收件人字段 + 9 处发布点（含 1 咽喉函数覆盖 17 调用点）+ fail-closed 桥接 | 6h |
| T03 | 后端+daemon：Ask-only 最小强制——ask_only 标记贯穿 enqueue→claim→execenv，brief 省略 Repositories + checkout 拒绝 | 4h |
| T04 | 前端：project-private-ask 面（纯 props 组合）+ 模型只读徽标 tooltip + 四语文案 | 5h |
| T05 | 端到端验收：AC-1~6 全场景（抓包/迁移 up-down/真机 Ask-only/双端） | 5h |

## 2. 任务依赖图

```
T01 (B2 迁移 + get-or-create 端点)
 ├─> T04 (前端 Private Ask 面，依赖 T01 端点)
 ├─> T03 (Ask-only 强制，依赖 T01 的 project_id 列贯穿 enqueue)
T02 (隐私收敛，独立可先行——不依赖 B2，改的是既有 chat 事件路径)
 └────────┬─ T01/T03/T04 ──> T05 (E2E 验收)
```

T02 与 T01 无依赖可并行（隐私收敛作用于既有 ChatSessionID 事件，Private Ask 只是新增消费方）；
T03 依赖 T01（ask_only 判定源是 chat_session.project_id）；T04 依赖 T01 端点；T05 收尾。

## 3. 资源与分工

单人（Ray）串行执行，推荐顺序 T01 → T02 → T03 → T04 → T05
（T02 前置到 T04 之前，前端联调时即在收敛后的推送语义下验证，避免二次回归）。

## 4. 风险与回滚策略

| 风险 | 缓解 | 回滚 |
|---|---|---|
| **隐私收敛回归既有 chat 实时体验**（本 CR 最大风险面，SDD §8 首行） | T02 自带回归清单：浮窗收发/未读徽标/全页流式/pending FAB/多设备/chat:done 直写；Lark 走 bus 层订阅不经 WS 桥（outbound.go:262 已核实）不受影响 | listeners.go 的分支是单点改动，revert 即回到 workspace fanout（隐私回到现状但功能无损） |
| 漏掉 ChatSessionID 任务事件发布点 → 该事件仍进全工作区广播 | 发布点清单已在拆分期 grep 全量固化（TASK-02 §清单，9 处含 broadcastTaskEvent 咽喉点）；AC-1 并行抓包兜底 | fail-closed 设计下漏点表现为"多广播"而非丢事件，按独立小 patch 补 |
| fail-closed 误丢事件（发布点忘填收件人） | ERROR 日志暴露 + 前端 invalidate/refetch 自愈（PR#5018 模式）；T02 单测覆盖"有 ChatSessionID 无收件人"分支 | 不回滚——丢事件是设计选择，宁丢不漏 |
| ask_only 标记 daemon 新旧版本兼容 | claim 响应可选字段，旧 daemon 忽略（降级=现状，弱化约束不破坏功能）；AC-3 要求新 daemon 全链路 | 字段可保留不消费，无需回滚 |
| ReportProgress（task.go:2462）只有 taskID 无 task 结构体，补 ChatSessionID 需调用点或查库 | T02 实施时二选一：调用方传 task / 按 taskID 查一次（进程内缓存 sessionID→creator 不可变映射）；清单已标注该特例 | 该事件仅进度摘要，最坏暂缓收敛并在 T02 记录残余（评审可见） |
| 全局 chat 列表排除谓词遗漏 | T01 实施时 grep chat_session 全部 SELECT 核对；AC-4 三处互不串验收 | 谓词是加法，缺项独立补 |
| 唯一索引与并发 get-or-create | 部分唯一索引 + 冲突重查（CR-A M1 同模式，已验证过） | 索引即安全网 |

## 5. 验收与发布策略

- 发布：随 CR 合并/回写进 multica main；M1 随部署管道执行，存量行零改写（nullable 列）。
- 无 feature flag：get-or-create 端点/前端面/ask_only 均为新增路径；**唯一改既有行为的是 T02
  隐私收敛**——它是红线要求本身，不做开关（开关=留一条泄漏路径），以回归清单代替灰度。
- 验收顺序：T01/T02/T03 后端单测+集成 → T04 前端联调 → T05 按 AC-1（隐私抓包，首要）→
  AC-2（并行）→ AC-3（Ask-only 真机）→ AC-4（三处隔离）→ AC-5（迁移回归）→ AC-6（输入区/双端/四语）。

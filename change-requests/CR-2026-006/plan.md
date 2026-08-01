---
id: CR-2026-006-plan
type: PLAN
cr-ref: CR-2026-006
sdd-ref: "change-requests/CR-2026-006/sdd.md"
target-version: "0.13"
status: draft
created: "2026-08-02T01:10:00+08:00"
updated: "2026-08-02T01:10:00+08:00"
---

# CR-2026-006 开发计划

## 1. 交付里程碑

后端两块 + 前端三块 + 端到端验收，共 6 任务，总估算 29h：

| 阶段 | 内容 | 估算 |
|---|---|---|
| T01 | 后端：migration + 容器 Issue lazy 创建端点 + 5+2 处查询排除谓词 + settings 白名单键 | 6h |
| T02 | 后端：薄发送端点（守卫→落 comment→入队→补偿）+ 优先级对齐 + 双层守卫竞态处理 | 5h |
| T03 | 前端：project-detail 入口 Tabs + 三模式 tab 骨架 + project-chat-store + 四语文案 | 4h |
| T04 | 前端：Team Agent 消息流（timeline+task-runs+TimelineView 组合）+ 输入区 + 满队反馈 | 6h |
| T05 | 前端：模型选择器（绑定 Team Agent 配置）+ 权限态/Runtime 态文案区分 | 3h |
| T06 | 端到端验收：AC-1~7 全场景 | 5h |

## 2. 任务依赖图

```
T01 (容器 Issue + 排除谓词 + settings 键)
 ├─> T02 (薄发送端点)
 ├─> T03 (入口 + tab 骨架)
 │      ├─> T04 (消息流 + 输入区，依赖 T02 的发送端点)
 │      └─> T05 (模型选择器，依赖 T01 的 settings 键)
 └───────────────────────┴──> T06 (E2E 验收，依赖 T02/T04/T05 全部完成)
```

T01 是唯一硬前置（DB 迁移与容器 Issue 语义决定了 T02/T03 的挂点）；T03 骨架与 T02 后端可并行；
T04/T05 需要 T03 的窗口容器就位；T06 收尾。

## 3. 资源与分工

单人（Ray）串行执行，按依赖图顺序 T01→T02/T03 并行→T04/T05→T06。

## 4. 风险与回滚策略

| 风险 | 缓解 | 回滚 |
|---|---|---|
| 排除谓词遗漏查询入口（SDD §6.1 清单来自代码调查，仍可能有漏项） | T06 逐入口核对 + 全局搜索单测验证聊天内容不泄漏 | 缺项按独立小 patch 补，不影响已上线部分 |
| **TSUG-001**：薄端点前置 guard 通过后，`EnqueueTaskForMention` 内部既有 guard 仍可能因并发竞态冒出 `ErrProjectQueueFull`，若补偿分支笼统按 502 处理会把满队竞态误报成系统错误 | T02 对该错误单独 `errors.As` 判断并映射 429（同样执行评论删除补偿），不落入通用 502 分支；T06 构造并发发送验证该路径 | 该判断是 T02 的一个 if 分支，回滚即删除分支退回旧行为（会短暂误报，不影响数据一致性） |
| **TSUG-002**：群聊消息走 mention 路径默认 priority=0，而既有 1:1 chat 任务固定 priority=2，同一 agent 混用时 1:1 会话持续插队项目群聊 | T02 将群聊任务入队优先级对齐为 2（与 1:1 chat 一致）；T06 验收顺带核对同 agent 下两类任务的 claim 顺序符合预期 | 优先级常量回退，不涉及数据结构变更 |
| **TSUG-003**：模型选择器编辑权限沿用 agent 编辑权限，可能与项目 owner/admin 身份错位（项目 owner 对他人创建的 agent 无编辑权时只读），若不区分文案会把权限问题误导成环境问题 | T05 显式区分「无编辑权限（只读徽标，无 CTA）」与「无可用 Runtime（引导文案 + 发送禁用）」两种态；T06 分别构造验证 | 纯前端文案分支，回滚不影响数据 |
| 容器 Issue 并发创建（多标签页同时首次进入 Chat tab） | T01 的部分唯一索引（`WHERE origin_type='project_chat'`）+ `ON CONFLICT DO NOTHING` 后重查兜底 | 索引本身是安全网，无需额外回滚路径 |
| `TimelineView` 导出化影响既有 1:1 chat 渲染 | T04 纯导出无逻辑改动；T06 回归验证浮窗/全页 chat | revert 导出改动即恢复原状 |
| project-detail 主区改动引入 Issue 视图布局回归 | T03 的 Tabs 只包裹不改 `IssueSurface` props；T06 四 modes 目视回归 | Tabs 包裹是单文件改动，可整体 revert |

## 5. 验收与发布策略

- 发布：随 CR 正常合并/回写流程进入 multica main；DB migration 随部署管道执行（`up.sql`），无需手工介入。
- 无 feature flag：新增查询排除谓词、薄发送端点、新前端入口均为新增路径，不影响既有 Issue 页评论 @提及、浮窗/全页 chat 行为（SDD §8 已列回归面，T06 覆盖回归验证）。
- 验收顺序：T01/T02 完成后先做后端单元/集成测试（容量守卫、补偿分支、优先级）→ T03/T04/T05 前端联调 → T06 端到端跑 AC-1~7（依 PRD 顺序：骨架→闭环→回放→满队双角色→容器隔离→回归→模型选择器）。

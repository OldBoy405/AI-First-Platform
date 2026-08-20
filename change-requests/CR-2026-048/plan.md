---
id: CR-2026-048-plan
type: PLAN
cr-ref: CR-2026-048
sdd-ref: "change-requests/CR-2026-048/sdd.md"
target-version: 0.22
status: draft
created: 2026-08-20T14:32:57+08:00
updated: 2026-08-20T14:32:57+08:00
---

# PLAN — CR-2026-048 内部 Skill Market

> **复用基线（已解决基础设施 vs 本次最小改造）**：本 CR 复用 `skill`/`skill_file` 表、`BuildManifest().Hash` 内容哈希、`redact` 的 16 条 patterns、`BuildAgentSkillBundles` 的 builtin 合成 id、`activity_log`+封闭 action、`canManageSkill`/`requireWorkspaceRole` 鉴权、`runtime-local` 覆盖导入、sqlc 生成链、既有 SkillsPage/SkillDetailPage。**本次新增收敛为**：4 个迁移（380–384）+ 2 个纯函数（`redact.Findings`、`PublishGate`）+ 1 个解析扩展（`ParseSkillMetadata`）+ 1 组 sqlc 查询 + 3 个接线点（claim 遥测、UpdateSkill 门禁、market/申诉端点）+ 前端扩展。**不新增任何事务/队列/outbox 框架**——遥测是 claim 路径上的 best-effort 单行 INSERT，申诉记账复用 activity_log 的 append-only 审计语义（与 `governance.ingestAudit` 同款容忍 crash-window 重复），均不引入新抽象。

## 1. 交付里程碑

| 里程碑 | 内容 | TASK | 估算 |
|---|---|---|---|
| M1 数据地基 | 迁移 380–384（三列 + 遥测表 + 三索引 + cleanup 双注册）+ sqlc 查询与生成物 | TASK-01/05 | 14h（≈1.75 人天） |
| M2 检测与解析 | redact 扩展 Findings + 第 17 条个人路径模式 + frontmatter 元数据解析扩展 | TASK-02/03 | 10h（≈1.25 人天） |
| M3 门禁与遥测 | 发布门禁纯函数 + 认领路径遥测接线 | TASK-04/06 | 14h（≈1.75 人天） |
| M4 端点 | UpdateSkill 门禁接线 + 申诉两端点 + Market 读端点 | TASK-07/08 | 16h（≈2 人天） |
| M5 前端与收口 | Market 列表/详情/发布/申诉 UI + CUSTOM.md 台账 + 全量回归 | TASK-09/10 | 18h（≈2.25 人天） |

**估算总工时：72h（≈9 人天）**。

## 2. 任务依赖图

```text
TASK-01 迁移 380–384 ──┐
                       ├──> TASK-05 sqlc 查询/生成 ──┬──> TASK-06 认领遥测接线
TASK-02 redact 扩展 ───┐                              ├──> TASK-08 Market 读端点 ──┐
                       ├──> TASK-04 发布门禁 ────────┤                            ├──> TASK-09 前端
TASK-03 frontmatter ───┘        (依赖 05 的 appeal 查询) └──> TASK-07 发布/申诉端点 ─┘      (依赖 07/08)
                                                                                          │
TASK-10 收口 <────────────────────────────────────────────────────────────────────────────┘（依赖全部）
```

并行度：01/02/03 三条叶可并行开工；05 依赖 01（sqlc schema 源即 migrations/）；04 依赖 02/03/05；06/08 依赖 05；07 依赖 04；09 依赖 07/08。

## 3. 资源与分工

| 角色 | 投入 | 说明 |
|---|---|---|
| 后端（multica） | 54h | TASK-01～08 + 收口回归 |
| 前端（packages/views+core） | 14h | TASK-09 |
| 收口 | 4h | TASK-10（CUSTOM.md + 测试矩阵） |

单人串行 9 人天；前后端可并行的窗口在 TASK-09（依赖 07/08 契约冻结后）。

## 4. 风险与回滚策略

| 风险 | 影响 | 回滚/缓解 |
|---|---|---|
| 迁移 384 建在热表 activity_log | CONCURRENTLY 构建拖慢写入 | 照抄 089 形制；真实 PG 先验证耗时；失败则 DROP INDEX CONCURRENTLY 回滚 |
| claim 遥测写入放大写入量 | 任务认领路径延迟 | 每 Skill 一行（<10/任务），best-effort 失败不阻断；索引走 `(workspace_id, skill_ref, used_at)` |
| builtin ref 合成规则漂移 | 遥测口径错 | TASK-06 加 skill_bundle 测试锁 `builtin:<name>` 断言（与 `TestBuildAgentSkillBundlesAssignsBuiltinID` 同款） |
| sqlc 重生成带出意外 diff | 合并噪声 | `make sqlc` 后 `git diff --stat server/pkg/db/generated/` 只允许预期文件 |
| 发布门禁误拦 | 作者无法发布 | 逐条 structured reason + 脱敏 findings；误报走申诉（appeal_id 绑定内容哈希） |
| 回滚 | 全量 | 迁移 380–384 逆序 down 可全回滚；`skill_usage_event` 是纯观测数据，回滚丢弃无业务影响 |

## 5. 验收与发布策略

- **发布前 checklist**：① `make sqlc` 生成物干净；② `TestEveryConcurrentUpBuildHasCleanup` 通过；③ 真实 PG 下 up/down/up 全回滚 + 三条 EXPLAIN 命中；④ `TaskCompleteRequest`/`sanitizeTaskCompleteRequest` diff 为零（AC-4）；⑤ `packages/core`/`packages/views` typecheck + vitest 全绿；⑥ CUSTOM.md 台账登记。
- **feature-flag**：不引入运行时开关——迁移是纯加列加表（默认值向后兼容），门禁只在 `private→org` 或 org 内容变更时触发，私有 Skill 路径行为零变化。发布即上线，回滚靠迁移 down 文件。
- **验收口径**：以 PRD §5 的 AC-1～AC-17 逐条落证；`skill_usage_event` 观察期口径（派发时物化、completed 去重）在指标定义页标注（PRD FR-7）。

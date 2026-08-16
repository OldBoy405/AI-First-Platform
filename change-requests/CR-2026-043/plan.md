---
id: CR-2026-043-plan
type: PLAN
cr-ref: CR-2026-043
sdd-ref: "change-requests/CR-2026-043/sdd.md"
target-version: tbd
status: draft
created: 2026-08-16T01:00:22+08:00
updated: 2026-08-16T01:00:22+08:00
---

# 开发计划 — CR-2026-043 Workspace 基线新鲜度与 CR Worktree 同步治理

## 1. 交付里程碑

| 里程碑 | 内容 | 任务 | 估算 |
|---|---|---|---|
| M1 只读分类 | `classifyWorkspaceFreshness` + `isAncestorOrThrow` + `workspace freshness` CLI（局部 catch 审计）+ 分类单元测试（Phase A） | TASK-01 | 8h |
| M2 同步事务 | `syncWorkspaceToTrunk`（lock/journal/intent/重核/ff-only/恢复）+ 故障点登记 + `workspace sync` CLI + 事务测试（Phase B） | TASK-02 | 10h |
| M3 Skill 与 Pipeline 接入 | `workspace-freshness` Skill + 台账登记 + code-implementation 双 gate + replayNodes + 契约测试（Phase C） | TASK-03~04 | 10h |
| M4 文档与回归 | README 人读段 + 集成测试 + Windows/Ubuntu 全量回归（Phase D） | TASK-05 | 6h |

**估算总工时：34h（约 4 人天，按 8h/人天）**

## 2. 任务依赖图

```text
TASK-01 (freshness 分类 + CLI) ──► TASK-02 (sync 事务 + CLI)
                                          │
                                          ▼
                                   TASK-03 (workspace-freshness Skill + 台账) ──► TASK-04 (Pipeline 双 gate + 契约测试) ──► TASK-05 (README + 集成回归)
```

- TASK-02 的 preflight 消费 TASK-01 的 `classifyWorkspaceFreshness`。
- TASK-03 的 Skill 只调用 TASK-01/02 产出的两个 CLI，不改 lib。
- TASK-04 引用 TASK-03 登记的 `workspace-freshness` Skill ref。
- TASK-05 依赖全部实现任务，最后执行。

## 3. 资源与分工

| 角色 | 任务 | 说明 |
|---|---|---|
| 开发（Ray） | TASK-01~04 | lib 深原语、CLI、Skill、Pipeline |
| 测试（Ray） | 各 TASK 内嵌测试 + TASK-05 回归 | 分类/事务/契约/集成四层 |

单一 owner，按依赖链串行推进；不并行改 `workspace-transactions.mjs`（TASK-01/02 同文件，必须顺序）。

## 4. 风险与回滚策略

| 风险 | 影响 | 回滚策略 |
|---|---|---|
| ff-only 目标 SHA 捕获错误 | worktree 前移到错误 trunk | 写入前逐仓重核 + `afterSha==targetSha` 断言；audit 记录 beforeSha，误操作时由人工按 beforeSha 恢复（工具不提供自动补偿） |
| journal intent 复用错误 | 旧 complete 被误当新同步 | intentDigest 绑定 before/target；latest complete 且 HEAD 回到旧 beforeSha → WORKSPACE_FRESHNESS_CHANGED 硬阻断 |
| Pipeline 节点插入破坏既有 CR 流 | 所有 coding CR 受影响 | 契约测试断言节点位置/replayNodes/节点数；回滚 = revert pipeline JSON 提交（单一文件） |
| fetch 网络不可用 | gate 全部 unknown 阻断 | 设计即硬阻断不降级；人工恢复网络后重跑 freshness |
| Windows/Linux Git 行为差异 | ancestry/路径判定不一致 | 双平台测试矩阵（TASK-05），解析先 CRLF→LF |
| 新增 CLI 破坏 cmdWorkspace 既有分支 | inspect/ensure/cleanup 回归 | dispatch 白名单扩展不改动既有分支；既有 workspace 测试全量回归 |

## 5. 验收与发布策略

**发布前 checklist：**

1. SDD §7.3 四层测试全部通过：分类单元、事务（含故障注入）、契约、集成。
2. `node --test` 既有 crctl 全量回归通过（workspace resolver/checkpoint/merge/archive/test 等）。
3. 全 fresh 场景零 journal；preflight 阻断全仓零写入；部分完成重跑只使用 journal 原始 intent。
4. freshness/sync 技术失败与业务阻断均在 fail 前写 audit；成功 allFresh freshness 不写 audit。
5. `skills/_index.yml`、`agent-skill-matrix.yml`、`pipeline-templates/_index.yml` 与实现一致（契约测试兜底）。
6. Windows 与 Ubuntu 各跑一遍 active repository 矩阵；不新增生产依赖。

**发布策略：**

- 本 CR 只改 Tools 仓方法论包代码，无 feature-flag（SDD §4.4：Phase A→D 顺序本身即安全落地路径）。
- 交付以 branch `requirement/CR-2026-043` merge 到 `custom/main` 为界，merge 后走既有 writeback/archive 流程。
- 双 gate 对 merge 后所有进入 implement/review 边界的 CR 生效；既有在途 CR 在下一次 gate 时按同一规则处理，无批量迁移。

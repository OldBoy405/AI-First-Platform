---
id: CR-2026-046-plan
type: PLAN
cr-ref: CR-2026-046
sdd-ref: "change-requests/CR-2026-046/sdd.md"
target-version: tbd
status: draft
created: "2026-08-18T20:51:24+08:00"
updated: "2026-08-18T20:51:24+08:00"
---

# PLAN — CR 合并与新注册 Worktree 同步治理优化方案

> 依据 SDD §1.2/§6：两条独立修改线（注册基点 / merge 本地同步），各自"实现 + 测试"成对交付；无跨线依赖，可并行。实现粒度遵循 coding-discipline §1（极简阶梯）与 §2（2-5 分钟步骤，实现期生效）。

## 1. 交付里程碑

| 里程碑 | 内容 | TASK | 估算 |
|---|---|---|---|
| M1 注册基点修复 | `ensureRepoWorkspace` missing 分支 fetch --prune + 重新分类 + 远端 trunk 建分支 + 新错误码 | TASK-01, TASK-02 | 5h |
| M2 merge 本地同步 | `reconcileLocalTrunks` helper + `mergeCr` 接线 + 输出契约 | TASK-03, TASK-04 | 7h |
| M3 全量回归与发布 | 既有 register/merge/checkpoint 等 crctl 测试套件零回归；合并至 tools trunk | 无新 TASK（每 TASK 完成标志内验证） | 1h |

总估算：**13h ≈ 2 人天**（8h/人天）。M1 与 M2 无依赖可并行；M3 依赖 M1+M2。

## 2. 任务依赖图

```text
TASK-01（ensureRepoWorkspace 改造）
   └── TASK-02（register 路径测试，消费 TASK-01 契约）

TASK-03（reconcileLocalTrunks + mergeCr 接线）
   └── TASK-04（merge 路径测试，消费 TASK-03 契约）

TASK-01 ∥ TASK-03（互不依赖，可并行）
```

依赖说明：两条线改的是 `workspace-transactions.mjs` 不同函数区域（L501-524 与 L1491-1497 附近），无共享符号；合并冲突面仅同一文件不同段落，风险低。

## 3. 资源与分工

| 角色 | 分工 | 工时 |
|---|---|---|
| development（Ray） | TASK-01~04 全部实现 | 12h |
| test（Ray） | TASK-02/04 测试用例评审与验证、M3 回归 | 1h |

单仓单实现文件（`lib/workspace-transactions.mjs`）+ 两个既有测试文件，无新增模块边界，无需跨仓协调。

## 4. 风险与回滚策略

| 风险 | 概率/影响 | 缓解 | 回滚 |
|---|---|---|---|
| `fetch --prune` 清理 stale refs 影响其他命令视图 | 低/低 | 仅在两处新调用点启用；既有命令不增加 prune | `git revert` 对应 commit，零数据迁移 |
| `WORKSPACE_TRUNK_UNAVAILABLE` 中断注册事务 | 中/低 | 幂等重跑按 journal `worktrees[]` 续跑（SDD §4.1） | 同左；无本地 branch/worktree 创建，零破坏 |
| helper 每仓 +1 fetch 增加 merge 调用量 | 低/低 | ARCHITECTURE §7a 观测基线已记录；不删 gate/测试 | 无需回滚，观测值 |
| `faultPoint` 注入点在生产路径 | 低/低 | 仅 `CRCTL_FAULT_POINT` 环境变量匹配时抛错，生产环境无该变量 | 同左 |
| 三仓主 checkout 状态不一致（部分 synced/部分 skipped） | 中/低 | 逐仓独立行结果，互不影响；失败不阻断远端已成功 merge | 用户原生 `git pull --ff-only` 补齐 |

## 5. 验收与发布策略

- **每 TASK 完成标志**：对应测试文件用例全绿 + `node --test skills/shared/crctl/scripts/test/register-tx.test.mjs` / `merge-tx.test.mjs` 零回归 + `git diff --check` 干净。
- **M3 全量回归**：`node --test skills/shared/crctl/scripts/test/*.test.mjs` 全绿（既有 register/merge/checkpoint/archive/writeback 等全部套件）。
- **发布前 checklist**：
  1. PRD AC-1~AC-8 逐条由对应测试用例背书（PRD §5 ↔ SDD §8 映射）；
  2. `crctl.mjs`、Pipeline、Skill、README、状态机、gates 零 diff；
  3. 新增错误码 `WORKSPACE_TRUNK_UNAVAILABLE` 在 register 失败路径有测试证据；
  4. `localTrunkSync` 输出契约（SDD §2.2 表）在 happy path 与三类 failed 各有断言；
  5. ARCHITECTURE 硬不变量逐条自检（§5 七条），重点：零第三方依赖、行尾纪律、Git 副作用只经 gitMust。
- **发布策略**：无 feature-flag；改动随 tools 仓 trunk 发布，行为变化对使用方透明（register/merge 输出面只增不减）。
- **估算总工时**：12h（TASK 实现）+ 1h（M3 回归）= 13h。

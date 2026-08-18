---
id: CR-2026-046-plan
type: PLAN
cr-ref: CR-2026-046
sdd-ref: "change-requests/CR-2026-046/sdd.md"
target-version: tbd
status: draft
created: "2026-08-18T20:51:24+08:00"
updated: "2026-08-18T20:57:16+08:00"
---

# PLAN — CR 合并与新注册 Worktree 同步治理优化方案

> 依据 SDD §1.2/§6：两条修改线各自以“实现 + 测试”纵切交付，合并为两个约 1 工作日 TASK，避免把测试拆成独立微任务。实现粒度遵循 coding-discipline §1（极简阶梯）与 §2（2-5 分钟步骤，实现期生效）。

## 1. 交付里程碑

| 里程碑 | 内容 | TASK | 估算 |
|---|---|---|---|
| M1 注册路径纵切 | `ensureRepoWorkspace` missing 分支改造 + register-tx 5 组新增用例与既有回归 | TASK-01 | 5h |
| M2 merge 路径纵切与发布验证 | `reconcileLocalTrunks` + `mergeCr` 接线 + merge-tx 新增用例 + 全量 crctl 回归与发布 checklist | TASK-02 | 7h |

总估算：**12h ≈ 1.5 人天**（8h/人天）。TASK-02 依赖 TASK-01，仅用于确保全量回归在两条修改线完成后执行；代码接口本身无跨线依赖。

## 2. 任务依赖图

```text
TASK-01（注册路径：实现 + 测试）
   └── TASK-02（merge 路径：实现 + 测试 + 全量回归/发布 checklist）
```

依赖说明：两条线改的是 `workspace-transactions.mjs` 不同函数区域，无代码接口依赖；TASK-02 的 `depends-on` 仅确保最终全量回归在 TASK-01 完成后执行，不新增协调层。

## 3. 资源与分工

| 角色 | 分工 | 工时 |
|---|---|---|
| development/test（Ray） | TASK-01~02 纵切实现、对应测试与最终全量回归 | 12h |

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

- **TASK-01 完成标志**：register-tx 新增用例与既有用例全绿 + `git diff --check` 干净。
- **TASK-02 完成标志**：merge-tx 新增用例与既有用例全绿；随后执行 `node --test skills/shared/crctl/scripts/test/*.test.mjs`，确保 register/merge/checkpoint/archive/writeback 等全部套件零回归；最后执行发布 checklist。
- **发布前 checklist**：
  1. PRD AC-1~AC-8 逐条由对应测试用例背书（PRD §5 ↔ SDD §8 映射）；
  2. `crctl.mjs`、Pipeline、Skill、README、状态机、gates 零 diff；
  3. 新增错误码 `WORKSPACE_TRUNK_UNAVAILABLE` 在 register 失败路径有测试证据；
  4. `localTrunkSync` 输出契约（SDD §2.2 表）在 happy path 与三类 failed 各有断言；
  5. ARCHITECTURE 硬不变量逐条自检（§5 七条），重点：零第三方依赖、行尾纪律、Git 副作用只经 gitMust。
- **发布策略**：无 feature-flag；改动随 tools 仓 trunk 发布，行为变化对使用方透明（register/merge 输出面只增不减）。
- **估算总工时**：TASK-01 5h + TASK-02 7h（含全量回归与发布 checklist）= 12h，与 `tasks/_index.yml#estimate` 总和一致。

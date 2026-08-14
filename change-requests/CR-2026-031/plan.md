---
id: CR-2026-031-plan
type: PLAN
cr-ref: CR-2026-031
sdd-ref: "change-requests/CR-2026-031/sdd.md"
target-version: tbd
status: draft
created: 2026-08-11T17:36:00+08:00
updated: 2026-08-11T17:36:00+08:00
---

# 1. 交付里程碑

| 里程碑 | 内容 | TASK | 估算 | 完成判据 |
|---|---|---|---:|---|
| M1 基线与公共内核 | fault harness、冗余删除、resolver、durable transaction | 01-04 | 40h | 红测可复现；公共 journal/lock/write-set 与路径约束通过单测 |
| M2 业务事务 | register/workspace、release snapshot、merge、writeback、archive | 05-09 | 80h | 三 bare remote 与 crash/restart 场景通过；五个深原语可幂等重入 |
| M3 契约与升级 | Skill/Pipeline/controlled-shell、upgrade-check、文档/contracts/CI | 10-12 | 36h | active prompt 仅调用深原语；升级 preflight 与双平台 CI 通过；统一切换 |

总估算：**156h（约 19.5 人日，按 8h/人日）**。排期按依赖和风险推进，不承诺日历日期；同一文件的 TASK 串行执行。

# 2. 任务依赖图

```text
TASK-01 fault harness
  ├─ TASK-02 redundancy cleanup
  ├─ TASK-03 resolver/authority
  └─ TASK-04 durable-tx
       └──────────────┐
TASK-02 + TASK-03 + TASK-04
  ├─ TASK-05 register/workspace
  └─ TASK-06 release snapshot
TASK-05 + TASK-06
  └─ TASK-07 recoverable merge
TASK-03 + TASK-04 + TASK-06
  └─ TASK-08 transaction workspace/writeback
TASK-05 + TASK-07 + TASK-08
  └─ TASK-09 archive
TASK-05 + TASK-07 + TASK-08 + TASK-09
  └─ TASK-10 prompt/controlled-shell convergence
TASK-06 + TASK-07 + TASK-08 + TASK-09
  └─ TASK-11 upgrade-check
TASK-01..TASK-11
  └─ TASK-12 docs/contracts/CI/protocol activation
```

# 3. 资源与分工

| 责任 | Owner | 工作范围 |
|---|---|---|
| 需求/边界 | Ray | PRD、职责不变量、范围变更判断 |
| 开发 | Ray | tools worktree 代码、Skill/Pipeline、测试与 CUSTOM.md 台账 |
| 测试 | Ray | fault matrix、bare remote 集成、Windows/Ubuntu CI 证据 |

实现优先在 `tools` CR worktree完成；knowledge-base CR worktree只承载 plan/TASK/评审/测试报告。multica 本 CR 无业务代码改动，保留参与仓 workspace 以验证多仓 resolver/merge。

# 4. 风险与回滚策略

| 风险 | 预防/探测 | 回滚/恢复 |
|---|---|---|
| 多 remote 部分发布 | intent/observation journal、lease push、远端分类 | roll-forward；history rewrite 硬阻断，不自动 revert |
| write-set 中断半写 | before/after hash、fsync、fault injection | before redo、after skip、第三值 `TX_RECOVERY_CONFLICT` |
| authority/workspace 误判 | graph resolver、realpath containment、固定 Transaction Workspace | 未能证明 ownership 即阻断；不 stash/reset/delete 用户资源 |
| approval 后漂移 | signed release snapshot、approve 重核 | 零 publish 时 code/source/TASK 回 developing；PRD/SDD hard block |
| 新旧协议半激活 | 单 CR 最终切换、upgrade-check | 有 legacy partial 事务时禁止激活；本 CR 仍走旧流程完成 |
| prompt 与 dispatch 漂移 | prompt contract 和旧命令扫描 | TASK-10/12 同一交付内修订，contract 不通过不切换 |
| ARCHITECTURE.md 与实现冲突 | 技术评审已显式记录 | TASK-12 同步修订架构基线；遗漏即 blocker |
| Windows 文件锁/PID 语义 | Windows fault vectors、EPERM/ESRCH 测试 | foreign/不确定 owner 保守阻断，无 force unlock |

不提供 feature flag、compat wrapper 或双写作为回滚手段。中间 commit 只存在 requirement branch；trunk 激活点是 TASK-12 全部 contract 通过后的最终协议切换。

# 5. 验收与发布策略

## 5.1 TASK 级验收

- 每个 TASK 至少两条可执行验证；完成后立即通过版本化 crctl TASK 状态入口登记 done；
- 依赖未 done 不启动下游 TASK；修改同一文件（特别是 `crctl.mjs`）的 TASK 串行；
- 每个 TASK 保留小提交，禁止将 12 个 TASK 压成单一实现提交。

## 5.2 CR 级检查

```text
node --test skills/shared/crctl/scripts/test/crctl.test.mjs
node --test skills/writeback/scripts/test/writeback.test.mjs
node scripts/lint-prompts.mjs --mode enforce
node scripts/check-skill-matrix.mjs
node scripts/check-agents-contract.mjs
node scripts/check-pipeline-contracts.mjs
```

并执行：三 bare remote 真实 Git 测试、kill/restart write-set 测试、manifest/path/symlink 攻击矩阵、锁 ownership matrix、upgrade-check 零写入断言、所有 Pipeline JSON parse，以及 Windows/Ubuntu CI 关键向量。

## 5.3 发布门禁

1. `upgrade-check` 输出 `canActivate=true`，没有 `blocksUpgrade`；
2. 所有 TASK done，测试报告 pass，代码评审与人工代码审批通过；
3. 本 CR 用旧 Installation Workspace 协议完成 merge/writeback/archive；
4. 新协议从下一 CR 生效；不补签历史 snapshot；
5. 所有安装不再存在旧在途事务后，按 CUSTOM-TODO-009 删除临时 `upgrade-check`。

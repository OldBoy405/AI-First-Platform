---
id: CR-2026-039-plan
type: PLAN
cr-ref: CR-2026-039
sdd-ref: "change-requests/CR-2026-039/sdd.md"
target-version: tbd
status: draft
created: 2026-08-15T01:31:31+08:00
updated: 2026-08-15T01:31:31+08:00
---

# 1. 交付里程碑

| 里程碑 | 内容 | TASK | 估算 |
|---|---|---|---|
| M0 集成准备（非 TASK，前置步骤） | tools CR worktree 以 fast-forward/普通 merge 合入最新 `origin/custom/main`（当前 `162fdf0`，含已合入的 CR-2026-038）；禁止 rebase 已发布分支/force push/cherry-pick（SDD §1.3） | — | 含在 TASK-01 内 |
| M1 dev-plan 证据写入与消费 | composite digest 唯一 helper + review-record 写入 + next/gate 双消费点 | TASK-01 → TASK-02 | 7h |
| M2 cr.md 时间字段统一 | `refreshCrMdUpdated` 共享纯函数 + 三个 writer 接入 | TASK-03 | 3h |
| M3 PASS 后审批前 checkpoint | code Pipeline 结构性插入 checkpoint 节点 + suggestion_policy 删除 | TASK-04 | 2h |
| M4 canonical 文本契约收敛 | 三个 CR Pipeline + 相关 Skill 删除废弃字段引用 | TASK-05 | 4h |
| M5 采纳与发布回归 | crctl/review-dev-plan SKILL 采纳修订 + Ubuntu/Windows 全量回归 | TASK-06 | 2h |

**估算总工时：18h（≈2.25 人天）**。

顺序说明：M1 是关键路径（digest 定义先于消费点）；M2/M3/M4 与 M1 之间无代码交叠，可并行但同一 worktree 内涉及同文件的 TASK 串行（TASK-01/02 都改 `crctl.mjs` 与 `crctl.test.mjs`，必须串行）；M5 在全部实现 TASK 完成后执行。

# 2. 任务依赖图

```text
M0 集成准备（162fdf0 合入）
  ├─ TASK-01 digest 写入 ──→ TASK-02 双消费点
  ├─ TASK-03 updated 统一（独立）
  ├─ TASK-04 checkpoint 节点（独立）
  └─ TASK-05 canonical 文本（独立）
              └── 全部 ──→ TASK-06 采纳与回归
```

- TASK-02 depends-on TASK-01（消费 `devPlanCompositeDigest` 精确签名）。
- TASK-06 depends-on TASK-01～TASK-05（全量回归必须覆盖全部改动）。
- TASK-03/04/05 无前置依赖；TASK-04 与 TASK-05 各自拥有独立测试文件，无文件交叠。

# 3. 资源与分工

| 角色 | 职责 |
|---|---|
| 开发负责人（Ray） | 全部 TASK 实现；crctl 核心改动（TASK-01/02/03）优先串行完成 |
| 测试负责人（Ray） | 每 TASK 红→绿测试；TASK-06 执行 Ubuntu/Windows 双平台全量回归并记录证据 |

工时分配见 §1：核心 crctl 改动 10h（TASK-01/02/03），Pipeline/文本契约 6h（TASK-04/05），采纳与回归 2h（TASK-06）。

# 4. 风险与回滚策略

| 风险 | 缓解 / 回滚 |
|---|---|
| tools worktree 落后于已含 CR-2026-038 的 custom/main | M0 前置集成；共享 crctl 文件按功能 seam 修改，code Pipeline 无冲突面（SDD §1.3） |
| legacy 在途 CR（dev-plan PASS 无 digest）被保守判 stale | 有意设计：一次 review-dev-plan 即补齐；合并说明中提示，无数据迁移 |
| TASK 文件竞态消失 | digest helper 返回结构化失败（repairTarget=write-dev-tasks），next 路由重建，gate 阻断；不静默降级（SDD §4.1） |
| suggestion_policy 删除影响触发习惯 | 参数本无实现支撑，删除不改变实际评审行为（SDD §10.3） |
| 任一 TASK 引入回归 | 每 TASK 一个可回滚提交，按序 revert；digest 字段对旧 reader 不可见，pipeline 节点 revert 恢复现状漏洞但不破坏流程（SDD §10.2） |

# 5. 验收与发布策略

**发布前 checklist**：

1. SDD §9.2 用例矩阵全部落为测试并全绿（digest 写入/next/gate、updated、pipeline 结构、contract 扫描、回归）。
2. `crctl` 既有全量测试不回归；Ubuntu 与 Windows 双平台运行（CI）。
3. 三个 CR 生命周期 Pipeline 与相关 Skill 对 `repair-instructions`/`fixed-blockers`/`suggestion_policy` 零命中（TASK-05 扫描测试）。
4. code Pipeline 节点 id 全局唯一、review-code < 新 checkpoint < approve-code 人工审批的顺序断言通过（TASK-04 结构测试）。
5. `crctl SKILL.md` 与 review-dev-plan SKILL 采纳修订完成（TASK-06）。
6. 状态机零变更验证：无新增状态/转移/gate type/错误码/命令（SDD §11）。

发布策略：随 tools 仓常规 CR 合入流程（merge → writeback → archive）；不设 feature flag（全部为收紧型门禁与文本收敛，无放宽路径）。

**估算总工时：18h（≈2.25 人天）**——与 `crctl task init` 返回的 `totalEstimateHours` 交叉校验基准（FR-23，CR-2026-022）。

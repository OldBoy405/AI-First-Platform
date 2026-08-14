---
id: CR-2026-024-plan
type: PLAN
cr-ref: CR-2026-024
sdd-ref: "change-requests/CR-2026-024/sdd.md"
target-version: tbd
status: draft
created: "2026-08-08T21:50:00+08:00"
updated: "2026-08-08T21:50:00+08:00"
---

# 开发计划 — 端到端 Pipeline 最佳实践技能整合

> 输入：`sdd.md`（批次一零行为变更 / 批次二同批原子内化）。目标仓：**tools 方法论包**。
> 本 CR 全部为规则文本 / 配置数据修改，无运行时代码、无数据库、无新增 actor。两个独立 commit（批次一 / 批次二），可分别 revert。

## 1. 交付里程碑

| 里程碑 | 阶段 | 交付物 | 依赖 | 估算 |
|---|---|---|---|---|
| **M1 批次一** | 实现 | SDD §4.1 六步全量（死声明清理 / capabilities 订正 / forbidden 说明 / TDD 悬空删除 + 降级路径 / assignee 删除）→ commit 1 | 无（独立） | 0.5 人天 |
| **M2 批次二** | 实现 | SDD §4.2 a~l 同批原子（coding-discipline 新建 + 六处内化 + suggestion_policy + 台账文档同步）→ commit 2 | M1 完成（降级文本后半句引用 coding-discipline，须同批落盘，B-2） | 1.0 人天 |
| **M3 验证** | 测试/联调 | 每批三件套（check-skill-matrix / check-agents-contract / lint-prompts --mode enforce）+ M2 后 1 个真实 CR 回归（crctl next/status/gate 无越级） | 各 commit 后即时 | 0.3 人天 |
| **M4 回写** | 发布 | feature-writeback：specs/delivery 累积落点 + PRD/SDD 基线同步 | M3 全绿 | 0.2 人天 |

**估算总工时：约 2.0 人天**（单人串行，无并发收益需求——批次二同批原子不可拆）。

## 2. 任务依赖图

```text
M1 批次一（commit 1，§4.1 步骤 1~6 无内部依赖，同 commit 提交）
  ├─ 1 agent-skill-matrix 死声明删除（FR-1）
  ├─ 2 agents/_index capabilities 订正（FR-4）
  ├─ 3 implement-code 删 TDD + 补降级前半句（FR-2，止于串行+注明降级）
  ├─ 4 pipeline nodes[5] prompt 同步（FR-3）
  ├─ 5 write-dev-tasks 删 assignee（FR-6）
  └─ 6 forbidden 性质说明（FR-5）
        │
        ▼ 三件套全绿 + 行为回归
M2 批次二（commit 2，§4.2 a~l 同批原子，禁跨 commit 拆分）
  ├─ a~d coding-discipline 新建链：SKILL.md + _index active + owns/can-call + 矩阵/dir-graph/ARCHITECTURE §8（FR-7/8）
  ├─ e implement-code 引用 §1§2§3 + 拓扑排序 + 降级后半句（FR-9，后半句与 a 同批）
  ├─ f write-dev-plan 引用 §2（FR-10）
  ├─ g review-code 前端质量维度 + 无条件重验 + 策略化分流 + dimensions 留痕（FR-11/12/14）
  ├─ h approve-code suggestions 承接（FR-15）
  ├─ i write-dev-tasks 接口契约（FR-17）
  ├─ j pipeline inputs.suggestion_policy + nodes[1][5][9] prompt（FR-13/19，nodes[9] 承载插值）
  ├─ k write-requirement-prd summary 边界（FR-18）
  └─ l AGENTS.md 第 56 条 + openwiki 同步（FR-20/21）
        │
        ▼ 三件套全绿 + 真实 CR 回归
M4 feature-writeback（specs/delivery 累积）
```

**关键依赖约束**：
- M1 → M2 强序：批次二降级文本后半句引用 coding-discipline，若 M1 先落该引用即悬空（本 CR 要清除的失效模式）；故后半句压到 M2-e 与 coding-discipline 同批。
- M2 内部 a~l 同批原子：a~f 拆开则 check-skill-matrix 报「active skill 无 owns」/孤儿引用；g~j 的 prompt 引用 coding-discipline/suggestion_policy 与 a/§2.1 同批才不悬空。

## 3. 资源与分工

| 角色 | 负责 | 说明 |
|---|---|---|
| dev-agent（Ray） | M1/M2 全部实现 + M3 三件套 | 单人串行；纯文本/配置，无跨 repo 并发需求 |
| quality-reviewer-agent | review-code 节点（M2-g/j 改动对象的自验证） | 改动后以本包语汇回归 |

**无并发拆分**：批次二同批原子性决定不可并行派发；即便装 dispatching-parallel-agents，同 repo 同文件多 TASK 也必须串行（SDD §4.3）。

## 4. 风险与回滚策略

| 风险 | 概率 | 回滚/缓解 |
|---|---|---|
| 批次二同批原子被误拆 commit，三件套自阻断 | 中 | §4.2 a~l 作为单一 TASK 原子单元，禁跨 commit；提交前 git status --short 核对清单 |
| tools 仓删除态外部文件（.qoder/repowiki 等）混提 | 中 | 仅 add 本 CR 文件清单，严禁 git add -A（SDD §4.4/NFR-10） |
| 方案节点编号陈旧改错节点（C-1） | 低 | 以 ref 名（write-dev-tasks/implement-code/review-code）为结构锚点，实施期下标二次核对（SDD §0/§9） |
| 死声明分布与表述不符致多删/漏删（C-2/C-5） | 低 | 清除对象锁定 system-orchestrator.external 三项 + dev-agent.external 的 tdd；实施后 grep 四项名称确认 actor 级零残留、顶层纯文档块原样 |
| lenient 升格耗尽 maxAttempts=3 停 developing（M-2） | 低 | 轮次闸：仅 attempt=1 升格，第 2 轮起一律 suggestions（SDD §3.3） |
| 任一批次整体回滚 | — | 批次一/二为独立 commit，分别 revert；批次二 revert 后 suggestion_policy input 与 prompt 引用同批消失，无残留悬空 |

## 5. 验收与发布策略

**验收 checklist**（对应 PRD AC / SDD §4.4）：
- [ ] M1 三件套全绿（check-skill-matrix / check-agents-contract / lint-prompts --mode enforce）
- [ ] M1 行为回归：状态机行为零变化（死声明删除仅影响矩阵报告面）
- [ ] M1 grep 确认 actor 级死声明零残留、顶层 external-skills 块原样
- [ ] M2 三件套全绿
- [ ] M2 真实 CR 回归：crctl next/status/gate 无越级（strict 默认路径行为与改动前一致）
- [ ] M2 lenient 场景演练：升格判据 + 轮次闸生效、dimensions.suggestion-policy canonical 留痕
- [ ] 全改动无本机绝对路径；commit message 注明方案 v2.6 + CR-2026-024 溯源（FR-24）

**feature-flag**：无运行时 flag——`suggestion_policy` 本身即 pipeline 触发参数（required:false + default:strict），旧触发方式零感知；strict 为默认保守路径，lenient 为显式开启的增量路径（SDD §7）。

**发布顺序**：M1 commit → 验证 → M2 commit → 验证 → feature-writeback。两 commit 均可独立 revert，回滚粒度到批次。

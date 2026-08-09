---
id: CR-2026-026-plan
type: PLAN
cr-ref: CR-2026-026
sdd-ref: "change-requests/CR-2026-026/sdd.md"
target-version: tbd
status: draft
created: "2026-08-09T12:50:00+08:00"
updated: "2026-08-09T12:50:00+08:00"
---

# 开发计划 — review-dev-plan 编码前质量门禁

## 1. 交付里程碑

| 里程碑 | 内容 | 涉及文件 | 估算 |
|---|---|---|---|
| M1 治理工具层（crctl + 门禁 + 状态机） | REVIEW_STAGE 四映射扩展；`resolveDevPlanRoute` 路由判定（bump 前）；repair-target schema/枚举校验与落盘；UPSTREAM 跳过 bump；gates.json 三处变更（dev-start evidence+passCondition、developing 五条件、reviewLoops）；dir-graph.yaml 两条状态转换 | `crctl.mjs`、`gates.json`、`dir-graph.yaml` | 2.5 人天 |
| M2 Skill 与 Pipeline 编排 | `review-dev-plan/SKILL.md` 新建；`write-dev-plan`/`write-dev-tasks` 回修支持（review_feedback/self_repair_attempt/fixed-blockers）；`approve-dev-start` 表述补充；code-implementation.pipeline.json 插入 reviewLoop 节点（onBlock 二分契约）；`skills/_index.yml` + `agent-skill-matrix.yml` 登记 | `skills/develop/`、`pipeline-templates/`、`skills/_index.yml`、`agent-skill-matrix.yml` | 2 人天 |
| M3 文档同步与全量验证 | README/ARCHITECTURE §8 登记/crctl SKILL 用途表；`crctl.test.mjs` 十类向量 + lint/check 回归全绿 | `README.md`、`ARCHITECTURE.md`、`skills/shared/crctl/SKILL.md`、`test/` | 1 人天 |

**总估算：5.5 人天**（M1 2.5 + M2 2 + M3 1）

## 2. 任务依赖图

```text
M1-TASK（crctl 映射+路由+校验+bump 分支）
  └─> M1-TASK（gates.json 三处 + dir-graph 两条转换）
       └─> M2-TASK（review-dev-plan Skill 新建）
            ├─> M2-TASK（write-dev-plan / write-dev-tasks 回修支持）
            └─> M2-TASK（pipeline 节点插入 + 登记）
                 └─> M3-TASK（文档同步）
                      └─> M3-TASK（测试向量 + 全量回归）
```

- M1 先行：M2 的 Skill/pipeline 依赖 crctl 已具备 dev-plan stage 能力
- M2 内部：Skill 新建与回修可并行，登记随 pipeline 插入收口
- M3 收尾：文档与测试在全部代码落地后执行

## 3. 资源与分工

| 角色 | 职责 | 预计投入 |
|---|---|---|
| dev-agent（Ray） | crctl 映射/路由/校验/bump 分支、gates/状态机、Skill 与 pipeline、测试 | 5.5 人天 |
| quality-reviewer-agent | review-dev-plan 评审执行（can-call 角色，登记项） | 纳入评审阶段 |

## 4. 风险与回滚策略

| 风险 | 缓解 | 回滚 |
|---|---|---|
| 路由判定与既有 review-record 顺序冲突（TD-BL-2 已定：bump 前判定） | 实现严格按 SDD §3.2 步骤 1-4；测试向量 ③/④ 断言 bump 分支 | 回退 crctl.mjs 单提交 |
| 状态机口径变化（25→27 声明 / 47→49 展开）连锁 | PRD B-7 已声明；实现期测试固化精确展开数 | 回退 dir-graph.yaml 两条转换 |
| 既有 approve-dev-start 流程回归 | gates 只增条件不删条件；四 stage 回归向量 ⑩ | 回退 gates.json |
| pipeline 分流契约实现歧义 | SDD §3.5 onBlock 二分契约 + 节点 prompt 明确 | 回退 pipeline JSON |

全部改动无数据迁移、无 schema 破坏；回滚均为单次 revert。

## 5. 验收与发布策略

发布前 checklist：
- [ ] `crctl review-record --stage dev-plan` 在 task-breakdown 落盘三账本（测试 ①）
- [ ] repair-target schema 校验（缺省/显式/非法值 → SCHEMA_INVALID 且三账本不变）（测试 ②）
- [ ] UPSTREAM bump 跳过（current-attempt 不变、attempts 不追加）（测试 ③）
- [ ] dev-start approval 无 dev-plan.yml → GATE_BLOCKED（测试 ⑥）
- [ ] developing 目标态删 TASK → 门禁拦截（测试 ⑦）
- [ ] evidence digest 三键 + EVIDENCE_DRIFT（测试 ⑧）
- [ ] 三轮 BLOCK → LOOP_EXHAUSTED（测试 ⑨）
- [ ] requirement/tech-design/write-test-report/code 四 stage 回归（测试 ⑩）
- [ ] check-skill-matrix / check-agents-contract / lint-prompts --mode enforce 全绿
- [ ] ARCHITECTURE.md §8 登记 + README/crctl SKILL 同步完成

发布策略：无 feature-flag（tools 包内部门禁能力，随 crctl 版本发布）；历史 CR 无 dev-plan.yml 不迁移（NFR-4 兼容）。

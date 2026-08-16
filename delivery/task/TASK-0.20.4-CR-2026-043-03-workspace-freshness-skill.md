---
spec-id: ai-first-platform
version: "0.20.4"
id: CR-2026-043-TASK-03
type: TASK
cr-ref: CR-2026-043
plan-ref: "change-requests/CR-2026-043/plan.md"
sdd-ref: "change-requests/CR-2026-043/sdd.md"
title: workspace-freshness Skill 与台账登记
slug: workspace-freshness-skill
status: pending
estimate: 4h
depends-on: [CR-2026-043-TASK-01, CR-2026-043-TASK-02]
created: 2026-08-16T01:00:22+08:00
---

# TASK-03 workspace-freshness Skill 与台账登记

## 1. 任务描述

新增窄 Skill `skills/sync/workspace-freshness/SKILL.md`：只做业务路由（continue / synced-continue / replay / manual），只调用 TASK-01/02 产出的两个 CLI；同步登记 `skills/_index.yml`、`agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md`，并按 SDD §8 更新 `skills/shared/crctl/SKILL.md` 能力面描述。对应 FR-06（SDD Phase C 第一部分）。

## 2. 涉及文件 / 模块

- `skills/sync/workspace-freshness/SKILL.md`（新建）
- `skills/_index.yml`（新增 active 条目）
- `agent-skill-matrix.yml`（system-orchestrator.owns += workspace-freshness；dev-agent.can-call += workspace-freshness）
- `AGENT-SKILL-MATRIX.md`（人读矩阵同步）
- `skills/shared/crctl/SKILL.md`（brief 补 workspace freshness/sync 能力声明）

## 3. 实现要点

- SKILL.md frontmatter 含 `name: workspace-freshness`；参数仅 `cr_id`（必填）、`gate`（必填，`implement-start`|`review-start`）。
- 路由表按 SDD §3.3 原样落地：
  - implement-start：allFresh→`continue`；syncable→调 `crctl workspace sync` 后重跑 freshness，allFresh→`synced-continue`，否则→`manual`；其余→`manual`（abort）。
  - review-start：allFresh→`continue`；syncable→调 sync 后返回 `replay`（review_feedback 注明"基线已前进，需重建实现/测试/checkpoint 证据"）；其余→`manual`（abort，不盲目消耗 reviewLoop）。
- 输出摘要含 `route`、facts 摘要（每仓 classification/freshness/SHA）、manual 时逐仓 blockers。
- Skill 内禁止出现：git 命令、锁/journal/CAS 步骤、状态推进、账本编辑；下一步提示写「以 `crctl next {cr_id}` 为准」（lint-prompts R9）。
- 台账：`skills/_index.yml` 条目 path `./sync/workspace-freshness/SKILL.md`、status active；矩阵唯一 owner=system-orchestrator，dev-agent can-call；不新增 Agent。
- `skills/shared/crctl/SKILL.md` 只在能力描述中补两个窄子命令名，不复制算法。

## 4. 验收条件

1. `skills/_index.yml` 含 workspace-freshness active 条目；`agent-skill-matrix.yml` 中该 Skill 唯一 owns=system-orchestrator 且 dev-agent can-call；AGENT-SKILL-MATRIX.md 与之一致。
2. SKILL.md 静态扫描：无 `git ` 命令字样、无 journal/lock/CAS 算法描述、无 `crctl advance`；仅调用 `crctl workspace freshness` 与条件 `crctl workspace sync`。
3. 路由表四种输入组合（allFresh / syncable / 阻断 / sync 后仍非 fresh）各有可人工核对的示例输出。

## 5. 完成标志

台账一致性检查（skills 索引/矩阵/Agent 文档互查）通过 + SKILL.md 静态扫描零违禁字样。

## 6. 接口契约

- **消费**：CLI `crctl workspace freshness <CR-ID>`、`crctl workspace sync <CR-ID>`（TASK-01/02 产出，签名不变）。
- **产出**：
  - Skill ref `workspace-freshness`（active，供 TASK-04 pipeline `node.ref` 引用）
  - Skill 输出契约 `{ route: 'continue'|'synced-continue'|'replay'|'manual', facts, blockers }`（供 TASK-04 pipeline prompt 分流）

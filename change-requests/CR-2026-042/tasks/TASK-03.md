---
id: CR-2026-042-TASK-03
type: TASK
cr-ref: CR-2026-042
plan-ref: "change-requests/CR-2026-042/plan.md"
sdd-ref: "change-requests/CR-2026-042/sdd.md"
title: 落地确定性治理并完成全量验收
slug: deterministic-governance-validation
status: pending
estimate: 17h
depends-on:
  - CR-2026-042-TASK-01
  - CR-2026-042-TASK-02
created: 2026-08-16T15:34:15+08:00
---

# 1. 任务描述

扩展 `lint-prompts.mjs` 扫描 Agent/README 并新增 R10-R13；将治理检查集中到 `crctl-ci.yml`；增加 Pipeline 固定结构和本 CR 静态合同测试；执行全量回归并定义 OpenWiki 合并后发布检查。

# 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/lint-prompts.mjs`
- `skills/shared/crctl/scripts/test/lint-prompts.test.mjs`
- `skills/shared/crctl/scripts/test/crctl.test.mjs`
- `.github/workflows/crctl-ci.yml`
- `.github/workflows/check-skill-matrix.yml`（删除）
- `.github/workflows/openwiki-update.yml`（只读验证，不改生成机制）

# 3. 实现要点

- `walkFiles` 增加 `agents/*.md`、`README.md`；R10 阻断 `cr-init`/旧 test flags/`review_llm`，R11 阻断 retired Skill active 引用，R12 阻断 Agent/README 状态机副本，R13 阻断 Agent backlog 状态推断；
- 文本先 CRLF→LF，状态集合复用 `loadAuthorityTransitions`；R10-R13 各有正例、合法反例与 LF/CRLF 等价测试；
- 删除 `check-skill-matrix.yml`，`crctl-ci.yml` 保留双 checker、Ubuntu/Windows matrix、全量测试并补齐 paths；
- Pipeline 检查只做 JSON/结构断言：必填字段、node id 唯一、active Skill ref、repairNodeId/replayNodes 引用存在；不解释 prompt 或模拟状态机；
- `crctl.test.mjs` 增加 code Pipeline 16 节点、CI 合并、paths、README/Skill 零残留等静态向量；
- OpenWiki 不手改：确认 `openwiki-update.yml` 保留 `workflow_dispatch`；合并后由发布负责人触发并核验 `openwiki/update` PR。

# 4. 验收条件

1. R10-R13 正例判红、合法反例不误报、LF/CRLF 结果一致，R1-R9 无回归；
2. `.github/workflows/check-skill-matrix.yml` 不存在；`crctl-ci.yml` 调用两个 checker，保留 Ubuntu/Windows 并覆盖 README/AGENT-SKILL-MATRIX/matrix/dir-graph/agents/skills/pipelines/rules/workflow paths；
3. Pipeline 固定断言能阻断坏 JSON、重复 node id、inactive Skill ref 与悬空 replayNodes；
4. `lint-prompts --mode enforce`、两个 checker、全部 Pipeline JSON、crctl 全量测试、writeback 单测全绿；
5. `crctl.mjs`、状态机、gates、账本/schema 与 writeback/archive 生产算法 diff 零触及；
6. `.github/workflows/openwiki-update.yml` 保留 `workflow_dispatch` 和 `openwiki/update` PR 输出；合并后发布 checklist 明确要求触发 workflow，并在生成 PR 中确认 `check-skill-matrix.yml|engineering-docs|MCP|review_llm` 等失效引用归零，失败时不合并生成 PR而修正源文件重跑。

# 5. 完成标志

合并前验收 1-5 全绿且证据记录完成；OpenWiki 验收 6 已作为合并后强制发布后置条件登记；改动作为一个 tools 仓 TASK commit，随后通过 `crctl task done CR-2026-042 CR-2026-042-TASK-03` 即时登记完成。

# 6. 接口契约

- 消费：TASK-01 的 code Pipeline `{ nodeCount: 16 }` 结构及 TASK-02 的 Agent/Skill/README/ARCHITECTURE 最终文本。
- 产出：`lint-prompts.mjs --mode report|enforce` 的 R10-R13 合同、唯一主治理 workflow、Pipeline 静态断言、全量测试证据和 OpenWiki 发布 checklist；无下游 TASK。

---
spec-id: ai-first-platform
version: "0.4"
id: CR-2026-031-TASK-10
type: TASK
cr-ref: CR-2026-031
plan-ref: "change-requests/CR-2026-031/plan.md"
sdd-ref: "change-requests/CR-2026-031/sdd.md"
title: 收敛 Skill Pipeline Agent 与 controlled-shell 契约
slug: prompt-contract-convergence
status: pending
estimate: 12h
depends-on: [CR-2026-031-TASK-05, CR-2026-031-TASK-07, CR-2026-031-TASK-08, CR-2026-031-TASK-09]
created: 2026-08-11T17:36:00+08:00
---

# 1. 任务描述

按 SDD §11 将 active Skill/Pipeline/Agent 文本中的 Git、workspace、账本、恢复算法删除，改为一次深原语调用；同步删除旧 CLI 与 generic destructive Git 面。

# 2. 涉及文件 / 模块

- SDD §11 列出的 10 个 Skill
- `pipeline-templates/{requirement-authoring,resume-cr,feature-writeback}.pipeline.json`
- `agents/requirement-writer.md`
- `skills/shared/controlled-shell/{SKILL.md,rules.json}`
- `skills/shared/crctl/{SKILL.md,scripts/crctl.mjs}`
- prompt/skill/agent/pipeline contract tests

# 3. 实现要点

- Pipeline 只保留节点顺序、mapping、reviewLoop/onFail、operational_workspace handoff。
- Skill 只保留业务前置、一次调用、结果分类；不写 Git 命令序列。
- 删除公开 cr-init/worktree-path/merge-metadata/archive-move/--caller 和已替代 generic Git 模板。
- README 型命令数不复制可计算事实。

# 4. 验收条件

1. active prompt 扫描不含裸 worktree/merge/revert/push、手写账本、`--workspace .` writeback、旧命令或 `--caller`。
2. lint-prompts、skill matrix、agent contract、pipeline contract 全通过，所有 Pipeline JSON 可解析。
3. 每个业务 Skill 只调用 SDD §4 对应深原语，结构化失败路由完整。

# 5. 完成标志

职责边界由 contract 机械保护，旧命令无 active consumer 后删除，任务状态登记 done。

# 6. 接口契约

消费：TASK-05 `register/workspace` 输出、TASK-07 `mergeCr` 输出、TASK-08 `applyWriteback` 输出、TASK-09 `archiveCr` 输出。

产出：Pipeline execution context 字段 `{cr_id:string, operational_workspace?:string, tx_id?:string, phase?:string, recover_command?:string}`；Skill 只透传深原语 JSON，不发明第二套字段。TASK-12 contract tests 精确验证。

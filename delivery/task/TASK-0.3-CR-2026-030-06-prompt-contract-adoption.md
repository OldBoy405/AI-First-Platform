---
spec-id: ai-first-platform
version: "0.3"
id: CR-2026-030-TASK-06
type: TASK
cr-ref: CR-2026-030
plan-ref: "change-requests/CR-2026-030/plan.md"
sdd-ref: "change-requests/CR-2026-030/sdd.md"
title: 同步 Skill Pipeline 与人读契约
slug: prompt-contract-adoption
status: pending
estimate: 8h
depends-on: [CR-2026-030-TASK-05]
created: "2026-08-11T02:34:00+08:00"
---

# TASK-06 同步 Skill Pipeline 与人读契约

## 1. 任务描述

按 SDD §8 和 PRD FR-10.1，把 TASK-02～05 的新原语采纳到 8 个 Skill、4 个 Pipeline、`crctl` Skill 与 3 份人读契约。删除 branch/path/SHA/event、Owner 恢复、approval CLI/reject 算法等文本副本；不得宣称 Runner、consumer 或 CUSTOM-TODO 已交付。

## 2. 涉及文件 / 模块

- tools：`skills/shared/crctl/SKILL.md`
- tools：SDD §8.1 列出的 8 个 `SKILL.md`
- tools：SDD §8.2 列出的 4 个 Pipeline JSON
- tools：`README.md`、`AGENTS.md`、`ARCHITECTURE.md`

## 3. 实现要点

- requirement-register 显式传三 Owner，只消费 cr-init/register/worktree-path 返回的 execution context。
- handover 固定 `owner-set -> push-progress` 且无 `skip_push`；resume 删除 Owner 输入和写入。
- 四 approve Skill 平台默认 grant、本地无 grant 要求 TTY，识别 decline 与技术失败；Pipeline 不拼 grant path/CLI。
- code pipeline dev-plan 节点只保留三路 route/replay；四个 Pipeline 节点数量和 `_index.yml#nodes` 不变。
- 人读契约只描述已交付事实，保留 Git 权威、outbox 非阻断、人工审批无旁路与 15+new/27/49 口径。

## 4. 验收条件

1. 8 个 Skill 与 crctl Skill 均采用新原语且不复制可执行算法；handover/resume/approve 的禁止模式检索为空。
2. 4 个 Pipeline JSON 可解析、节点数不变、输入与路由满足 AC-31；`pipeline-templates/_index.yml` 无 diff。
3. README/AGENTS/ARCHITECTURE 与实现一致，不声称 CUSTOM-TODO-001～006 已交付。
4. `lint-prompts --mode enforce`、Skill matrix 与 Agent contract 检查全部退出 0。

## 5. 完成标志

所有 Prompt/人读契约静态检查通过，changed-files 均在 FR-10.1，`tasks/_index.yml` 中 TASK-06 标记 `done`。

## 6. 接口契约

- **消费**：TASK-02～05 的 public CLI、结构化结果和错误码。
- **产出**：8 个 Skill、4 个 Pipeline、crctl Skill 和 3 份人读契约的唯一一致文本；不产出新运行时接口。

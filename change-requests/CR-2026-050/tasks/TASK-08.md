---
id: CR-2026-050-TASK-08
type: TASK
cr-ref: CR-2026-050
plan-ref: "change-requests/CR-2026-050/plan.md"
sdd-ref: "change-requests/CR-2026-050/sdd.md"
title: write-tech-design / review-tech-design SKILL 收窄（FR-07.1/07.2 + FR-08 + 提交前缀）
slug: narrow-write-review-tech-design-skills
status: pending
estimate: 5h
depends-on: [CR-2026-050-TASK-07]
created: 2026-08-21T11:57:27+08:00
---

## 任务描述

把 SDD §1.1 中 FR-07.1/FR-07.2 的真实漂移落点（write-tech-design SKILL.md 路径约定与「同一 commit」表述）、FR-08 三项能力收窄、FR-08.4 评审维度扩展、DD-7 提交前缀对齐全部落到两个 SKILL.md。

## 涉及文件 / 模块

仓根只允许取 `execution_context.resources[]` 中 `repo=tools` 的 `worktreePath`；以下均为该仓根相对路径：

- `repo=tools: skills/develop/write-tech-design/SKILL.md`
- `repo=tools: skills/develop/review-tech-design/SKILL.md`

## 实现要点

1. **FR-07.1**：删除 Step 1 的 `.rayai-worktrees/{repo.id}/requirement/{cr_id}` / `.rayai-worktrees/knowledge-base/requirement/{cr_id}` 路径约定；改为消费 `operational_workspace` 与 `resources[].worktreePath`（输入表显式声明两个参数）。
2. **FR-07.2**：把「ARCHITECTURE.md 与 sdd.md 同一 commit 提交」改为「各仓在所属 `resources[].worktreePath` 分别提交，架构审批后由同一批 checkpoint 纳入；只为本 CR 实际涉及且缺失的仓懒加载起草」。
3. **FR-08.1 术语硬化收窄**：仅处理进入数据模型/状态机/接口契约，且存在歧义/别名/边界风险（影响 FR/AC/角色权限/验收语义）的术语；每个风险术语至少一个代表性边界场景验证；已有 CONTEXT.md/术语表只读沿用；命名冲突记 `PRD canonical term → 代码别名` 映射；语义冲突不得自行裁决（首次 crctl advance 前停止、要求需求负责人澄清）；术语预检位于首次状态推进前。
4. **FR-08.2 HTTP/REST 条件基线**：仅当 PRD/tech_context/方案表明新增或修改 HTTP API 时触发；优先级 = 目标仓 ARCHITECTURE.md/既有 OpenAPI → 客户端兼容性 → Skill 默认基线；不强制复数名/kebab-case/固定错误结构/全列表分页/固定状态码/全部 201+Location；SDD 只写概要/输入/输出/错误/鉴权与条件性幂等分页，复杂接口附最小 OpenAPI 片段。
5. **FR-08.3 决策记录三判据**：难以逆转 + 无上下文会疑惑 + 有真实权衡替代，同时满足才记录（Decision/Context/Alternatives/Consequences）；不伪造替代、不新增 ADR/审批节点。
6. **FR-08.4**：review-tech-design 评审维度扩展四类（数据模型完整性/接口契约条件基线/架构合理性三判据/多仓架构约束），不新增评审节点。
7. **DD-7**：两个 SKILL.md 的 Commit 指引前缀改为白名单内（`[cr] `）。

## 验收条件

1. write-tech-design SKILL.md 全文无 `.rayai-worktrees/` 拼接表述；输入表含 `operational_workspace`/`resources`。
2. 无「同一 commit」表述；FR-08.1 含「代表性边界场景」要求；FR-08.2 含条件触发与仓库约定优先；FR-08.3 含三判据。
3. review-tech-design 评审维度表含四类扩展维度，且无新增评审节点表述。
4. 两个文件均无 `feat(` 提交前缀；`lint-prompts.mjs` 无新增触发。

## 完成标志

上述 4 条验收全部通过；DD-7 的提交前缀**扫描断言**在 TASK-14 落地（本 TASK 只改前缀，不写断言）。

## 接口契约

- 消费：SDD FR-07.1/07.2/FR-08 收窄文案、TASK-07 产出的 architecture pipeline 最终措辞（两文件不得与其矛盾）。
- 产出：两个 SKILL.md 收窄版；后续本 CR 的 SDD/评审均以这两份 SKILL 契约为准。

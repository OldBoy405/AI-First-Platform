---
spec-id: ai-first-platform
version: "0.25"
id: CR-2026-024-TASK-02
type: TASK
cr-ref: CR-2026-024
plan-ref: "change-requests/CR-2026-024/plan.md"
sdd-ref: "change-requests/CR-2026-024/sdd.md"
title: 批次二最佳实践内化（coding-discipline 新建 + 六处内化 + suggestion_policy 策略化分流，同批原子）
slug: batch2-practice-internalization
status: done
estimate: 8h
depends-on: [CR-2026-024-TASK-01]
created: "2026-08-08T22:00:00+08:00"
---

# TASK-02 批次二最佳实践内化

## 1. 任务描述
按 SDD §4.2 a~l 执行批次二——真实行为变更，**同批原子，禁跨 commit 拆分**（§4.2 原子性依据 / SDD §9）。新建 coding-discipline 兜底事实源并内化六条最佳实践；pipeline 新增 suggestion_policy 触发参数驱动评审期策略化分流。全部改动同一 commit（commit 2）提交。

## 2. 涉及文件 / 模块（tools 仓）
- `skills/develop/coding-discipline/SKILL.md`（新建）
- `skills/_index.yml`
- `agent-skill-matrix.yml`
- `AGENT-SKILL-MATRIX.md` + `dir-graph.yaml` + `ARCHITECTURE.md` §8
- `skills/develop/{implement-code,write-dev-plan,review-code,approve-code,write-dev-tasks}/SKILL.md`
- `skills/requirement/write-requirement-prd/SKILL.md`
- `pipeline-templates/code-implementation.pipeline.json`
- `AGENTS.md`(tools) + `openwiki/`

## 3. 实现要点（SDD §4.2 a~l）
- **a~d coding-discipline 新建链**：新建 SKILL.md（§3.1 定稿骨架：§1 极简阶梯/§2 步骤粒度/§3 根因排查与回归红绿验证 + 甲路线）；skills/_index.yml 登记 active；agent-skill-matrix.yml dev-agent.owns += coding-discipline、quality-reviewer-agent.can-call += coding-discipline；AGENT-SKILL-MATRIX.md 主责矩阵 + dir-graph.yaml + ARCHITECTURE.md §8 代码地图登记（FR-7/8）。
- **e implement-code 内化（FR-9）**：Step 3 引用 §1+§2、自修复分支引用 §3、追加 depends-on 拓扑排序（§3.4/§4.3）；降级文本补后半句「两者均未提供时按 coding-discipline §2 粒度自行拆解执行」（与 a 同批，B-2）。
- **f write-dev-plan 引用 §2（FR-10，C-4 develop 域）**。
- **g review-code（FR-11/12/14）**：Step 3 维度表追加「前端质量」维度（现有 6 行表第 7 行，B-4，按维度名验收）+ Step 1 无条件重验（§3.2）+ Step 3 策略化分流模式无关表述与轮次闸（§3.3，{{inputs.*}} 插值落 nodes[9].prompt 不落 SKILL.md，B-1）+ dimensions.suggestion-policy 留痕与 Step 6 输出两行（§2.5，M-1）。
- **h approve-code suggestions 承接（FR-15，§3.6）**。
- **i write-dev-tasks 接口契约（FR-17，§3.5）**：接口契约小节 + Step 4 签名核对 + 占位符判据。
- **j pipeline（FR-13/19）**：inputs += suggestion_policy（§2.1）；nodes[1] prompt 同步接口契约；nodes[5] prompt 同步拓扑排序；nodes[9] prompt 承载 {{inputs.suggestion_policy}} 插值读取并同步「前端质量」⑤ + 无条件重验 + 升格判据与轮次闸（C-1 下标）。
- **k write-requirement-prd summary 边界采纳（FR-18）**。
- **l AGENTS.md(tools) 第 56 条修订（FR-20，§3.7；第 160 条不动）+ openwiki 页面同步（FR-21）**。

## 4. 验收条件
- 三件套全绿：`check-skill-matrix` + `check-agents-contract` + `lint-prompts --mode enforce`。
- 1 个真实 CR 回归：crctl next/status/gate 无越级，strict 默认路径行为与改动前一致。
- lenient 场景演练：升格判据 + 轮次闸（仅 attempt=1 升格）生效，dimensions.suggestion-policy canonical 留痕。
- grep 确认 coding-discipline/suggestion_policy/record-idea 引用与被引用对象同批落盘，无悬空。

## 5. 完成标志
三件套全绿 + 真实 CR 回归通过 + lenient 演练通过；批次二 a~l 全部落盘并作为 commit 2 提交（同批原子，commit message 注明方案 v2.6 + CR-2026-024 溯源，FR-24）；任务状态在 `_index.yml` 标记 done。

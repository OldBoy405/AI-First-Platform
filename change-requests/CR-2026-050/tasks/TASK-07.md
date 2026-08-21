---
id: CR-2026-050-TASK-07
type: TASK
cr-ref: CR-2026-050
plan-ref: "change-requests/CR-2026-050/plan.md"
sdd-ref: "change-requests/CR-2026-050/sdd.md"
title: architecture-design 收敛 + multica gate_nodes_gen.go 再生 + CUSTOM.md 登记
slug: converge-architecture-pipeline-registry
status: pending
estimate: 6h
depends-on: [CR-2026-050-TASK-06, CR-2026-050-TASK-02]
created: 2026-08-21T11:57:27+08:00
---

## 任务描述

阶段二第 1 项（PRD §18.2 顺序）：收敛 architecture-design 的 node-1/2/4/5 prompt（FR-06.3/FR-07.3/FR-09），修订 `:149` 冲突断言，并**同批**再生 multica 嵌入 registry、登记 CUSTOM.md（SDD §4.2 硬依赖：不再生则运行时执行旧 prompt，FR-01 修复不生效）。

## 涉及文件 / 模块

- `tools/pipeline-templates/architecture-design.pipeline.json`
- `tools/skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`（`:149` 修订 + 溯源注释）
- `multica/server/internal/governance/gate_nodes_gen.go`（**再生，生成产物禁止手改**）
- `multica/CUSTOM.md`（台账登记）

## 实现要点

1. node-1 `write-tech-design`：删除 SDD 章节清单、术语/REST/决策业务规则、`crctl advance` 命令、Git 命令与 commit 算法、blocker 修复算法；保留 §3.0 inspect 入口、execution_context 输出与五要素（cr_id/tech_context/operational_workspace/resources/review_feedback/attempt）。**token 只用 `{{inputs.cr_id}}` 与 `{{inputs.tech_context}}`**（emit-registry ALLOWED 白名单，SDD §4.2 第 5 条）。
2. node-2 `review-tech-design`：删除评审维度正文、临时 payload、`review-record` 调用、annotation/traceability 写入；**不残留任何 deny 路径字面量**（SDD §3.1 lint R1）；保留 reviewLoop 机器字段原样。
3. node-4 `approve-tech-design`：删除 grant/TTY/reject/状态级联细节（TASK-02 已完成主收敛，此处核对不回归）。
4. node-5 `push-progress`：删除 `crctl checkpoint` 命令字面量，只传 cr_id/message、消费 phase；保留「阶段终点 / phase=complete / 失败只重跑 checkpoint、不重新审批」语义。
5. 修订 `:149` 断言为「不含 crctl checkpoint 命令字面量 + 含 phase 消费与阶段终点语义」，并在用例内保留 CR-2026-044 FR-07 溯源注释。
6. 再生链：`node pipeline-templates/emit-registry.mjs --pipeline architecture-design` 验证 → multica 内 `node server/internal/governance/gen/generate-gate-nodes.mjs` → `--check` 通过 → 提交 gate_nodes_gen.go。
7. CUSTOM.md 按当前结构登记本变更（生成产物再生 + 溯源）。

## 验收条件

1. tools 侧：JSON 可解析、`pipeline-structure.test.mjs` 全绿（`:149` 修订后）、`lint-prompts.mjs` 无新增触发。
2. `emit-registry.mjs --pipeline architecture-design` 退出 0 且无 REGISTRY_PROMPT_TOKEN_INVALID。
3. multica 侧：`generate-gate-nodes.mjs --check` 退出 0；`go test ./server/internal/governance/` 通过；digest 已变化且与 registry 内容一致。
4. CUSTOM.md 已登记；node-1 提示不含 `crctl advance`/`git commit` 字面量。

## 完成标志

上述 4 条验收全部通过，且 tools 与 multica 两仓改动在同批提交（SDD §4.2 实施顺序约束）。

## 接口契约

- 消费：`emit-registry.mjs`（tools，canonical registry 输出 + digest）、`generate-gate-nodes.mjs`（multica）、`pipeline-structure.test.mjs:149` 现行断言。
- 产出：architecture-design 5 节点收敛版（machine fields 零改动：UUID/reviewLoop/onFail）；`gate_nodes_gen.go` 新 digest；供 TASK-08（write/review-tech-design SKILL 收窄）对齐的最终 pipeline 措辞。

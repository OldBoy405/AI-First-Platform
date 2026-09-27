---
id: CR-2026-071-TASK-02
type: TASK
cr-ref: CR-2026-071
plan-ref: "change-requests/CR-2026-071/plan.md"
sdd-ref: "change-requests/CR-2026-071/sdd.md"
target-version: 0.44
title: tools requirement-authoring checkpoint 节点恢复与结构测试同步
slug: tools-checkpoint-node-restore
status: pending
estimate: 4h
depends-on: []
created: 2026-09-27T16:45:00+08:00
---

# CR-2026-071-TASK-02 — tools requirement-authoring checkpoint 节点恢复与结构测试同步

## 1. 任务描述

- 目标：按 SDD §4.4，在 `requirement-authoring.pipeline.json` 的 node-2 之后、review 之前恢复独立 checkpoint 节点（复用被 CR-2026-066 删除的 id `...0003`，`ref=push-progress`），并同步 `_index.yml` 与结构测试断言（FR-4）。
- 背景：dep-5 确认 node-2（`...0002`）直连 review（`...0004`）、无 `...0003`；dep-6/dep-7 确认台账与测试基线须同步。
- 输入条件：`plan.md` §1/M2、`sdd.md` §4.4、`cr.md` target-version 0.44；tools CR worktree 已存在且可读。

## 2. 涉及文件 / 模块

tools CR worktree（`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-071`）内：

- 修改：`pipeline-templates/requirement-authoring.pipeline.json`（node-2 `...0002` 之后插入 id `00000000-0000-0000-0011-000000000003` 的 skill 节点，`ref=push-progress`，SDD §4.4 JSON 原文）
- 修改：`pipeline-templates/_index.yml`（`requirement-authoring-v1` 的 `nodes: 5 → 6` + brief 同步）
- 修改：`skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`（`requirement-authoring` 断言更新为 6 节点、恰 1 个评审前 `push-progress` 节点、id `...0003` 在位、审批后 `push-progress` 仍 0）

不触碰其他 Pipeline、其他被 CR-2026-066 删除的 checkpoint（含全部审批后 checkpoint）。

## 3. 实现要点

- 参考 SDD §4.4：节点 `label` 为"提交 PRD 草稿（评审前 checkpoint）"，`prompt` 内 `cr_id: {execution_context.cr_id}`、`message: PRD 草稿评审前发布`，消费 batchId 与三仓 confirmed；`phase` 非 complete 按 Skill 错误语义中止，不进入评审；`onFail=abort`；`timeoutMinutes=10`。
- 语义保持：`reviewLoop` 的 repair 仍指回 node-2，回修后正向流再次经过本节点重新发布再复评；评审 PASS 发布与审批后节点保持 CR-2026-066 既有机制不变。
- 不在 JSON 里内联 CLI 调用；不增改 crctl 子命令与 `controlled-shell/rules.json`（SDD §8）。

## 4. 验收条件

1. `node -e "JSON.parse(require('fs').readFileSync('pipeline-templates/requirement-authoring.pipeline.json','utf8'));console.log('pipeline-json-ok')"`（plan cmd-03）在 tools worktree 根输出 `pipeline-json-ok`。
2. `node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`（plan cmd-02）在 tools worktree 根全绿，且断言含 6 节点 / 评审前 `push-progress` 恰 1 个 / `...0003` 在位 / 审批后 `push-progress` 为 0。
3. 节点顺序为 node-2 → `...0003` → review，可用 JSON 节点序列与结构测试双重核验；文件侧范围核验按 plan.md §6 文件侧范围核验标准执行（B-02 复评；禁止原生 git；双向引用 plan.md §6 FR-4 行）：启动时 `crctl git rev-parse HEAD --cwd <tools CR worktree>` 记 BASE；完成后 `crctl git log --oneline -5 --cwd <tools CR worktree>` 定位本 TASK 提交 C；`crctl git diff --stat BASE C --cwd <tools CR worktree>` 文件集须恰为上述三个文件；`crctl git status --short --cwd <tools CR worktree>` 须干净。

## 5. 完成标志

- 上述三个文件已落盘修改，验收条件 1～3 全部通过；`node --test` 全绿输出已留存；本 TASK 实际产生的文件修改已由本 TASK 落实登记，不预登记 TASK-05 的验证记录。

## 6. 接口契约

- 消费：无上游 TASK 产出。本 TASK 直接消费 SDD §4.4 的节点 JSON 原文与 `_index.yml` 同步要求（Pipeline 编排配置，非代码函数签名；SDD §3 明确不新增 crctl 子命令、不改调用签名）。
- 产出：下游 TASK-05 消费本 TASK 落盘的 Pipeline JSON 节点序列（node-2 → `...0003` → review）与更新后的结构测试断言；产出形态为 JSON/YAML/测试脚本文件，不暴露函数签名。
- 共享契约锁定：节点 id `00000000-0000-0000-0011-000000000003`、`ref=push-progress`、`onFail=abort`、`nodes=6` 四项在 JSON、`_index.yml`、结构测试三处必须完全一致；任一处不一致即实施失败。

---
id: CR-2026-005-plan
type: PLAN
cr-ref: CR-2026-005
sdd-ref: "change-requests/CR-2026-005/sdd.md"
target-version: "0.12.1"
status: draft
created: "2026-08-01T15:20:00+08:00"
updated: "2026-08-01T15:20:00+08:00"
---

# CR-2026-005 开发计划

## 1. 交付里程碑

单里程碑工具链补丁，全部改动落在 `tools` 包（`custom/main` trunk，直接提交，无 worktree——理由见 SDD 头注）。总估算 8h：

| 阶段 | 内容 | 估算 |
|---|---|---|
| 实现 | T01（gate check + writeback-tasks skill） | 5h |
| 验收 | T02（AC-1~5 全场景验证 + 调用时机文档化） | 3h |

## 2. 任务依赖图

```
T01 (crctl.mjs deliveryIndexComplete + gates.json + writeback-tasks skill) ──> T02 (五条 AC 验证)
```

单任务实现（gate 与 skill 是同一份补丁的两半，拆开验收无意义），T02 依赖 T01 完成。

## 3. 资源与分工

单人（Ray）串行执行。

## 4. 风险与回滚策略

| 风险 | 缓解 | 回滚 |
|---|---|---|
| 新 check type 误伤既有 5 类门禁判定逻辑 | `runGateChecks` 只新增一个 else-if 分支，不改动既有 4 类分支代码；AC-1 正向场景验证既有归档路径仍通过 | revert crctl.mjs + gates.json 两处改动，`archived` 门禁退回 5 项检查（旧行为） |
| writeback-tasks 幂等性判断有误导致重复索引行 | AC-4 专门验证重复调用；判据是索引 id 存在性而非文件 diff（SDD §3.3④ 已选定最简判据） | 手工去重 `delivery/task/_index.yaml`（YAML 文本，风险可控） |
| slug 兜底 `task-{NN}` 与历史人工语义化命名风格不一致（技术评审建议 1） | write-dev-tasks skill 同步小改：`slug` 字段列为「建议填写」项（非强制），在 Step 3 生成 TASK 文件时提示填写；本 CR 自己的 3 个历史任务（TASK-01~03）不受影响（已完成，不重新生成） | 不涉及数据风险，纯文档措辞调整，无需回滚 |
| 全局索引出现孤儿行（任务后来被撤销但索引未清理，技术评审建议 2） | 明确不在本 CR 范围内处理——`deliveryIndexComplete` 只做单向检查（done→已登记），不检查反向；孤儿行不影响门禁通过，留作独立评估项 | 不适用 |

## 5. 验收与发布策略

- 发布 = 直接提交到 `tools` 仓 `custom/main` trunk（`[cr] CR-2026-005 TASK-01: ...` commit 风格，同 CR-2026-002/003 先例）；不涉及部署/重启，crctl 是本地 CLI 工具，下次调用即生效。
- **调用时机文档化（技术评审建议 3 落地）**：`writeback-tasks` skill 的调用时机固定在 CR 生命周期的 `writing-back` 阶段、`write-test-report` 完成之后、`cr-archive`（推进到 `archived`）之前——因为 `deliveryIndexComplete` 门禁挂在 `archived` 转移上，若在此之前没跑 `writeback-tasks` 补全索引，`--to archived` 会被拒绝。T01 任务描述与 skill 文件的"调用时机"字段都会写明这一点，避免实现期误放到 archived 之后（那样就失去意义）。
- 验收顺序：AC-1（正向，既有 4 个历史 CR 的索引重放验证不误报）→ AC-2（负向，复现 CR-2026-003 当时的漏登场景）→ AC-3（skill 正向回写，自证闭环）→ AC-4（幂等重放）→ AC-5（边界：无 done 任务 / 索引不存在）。
- 无 feature flag：新增门禁检查即时生效于所有后续 `--to archived` 调用，无需灰度（本地 CLI 工具，无线上流量概念）。

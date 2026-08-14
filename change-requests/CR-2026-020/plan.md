---
id: CR-2026-020-plan
type: PLAN
cr-ref: CR-2026-020
sdd-ref: "change-requests/CR-2026-020/sdd.md"
target-version: tbd
status: draft
created: "2026-08-04T22:21:12+08:00"
updated: "2026-08-04T22:21:12+08:00"
---

# PLAN — writeback 机械步骤固化为入库脚本

## 1. 交付里程碑

| 阶段 | 内容 | 估算 |
|---|---|---|
| 设计 | PRD + SDD（已完成，含 1 轮评审自修复） | — |
| 实现-1（基础） | lib.mjs 公共库 | 4h |
| 实现-2（三脚本，可并行开发但顺序集成） | writeback-prd-sdd.mjs / writeback-tasks.mjs / writeback-traceability.mjs | 17h |
| 实现-3（自检） | test/writeback.test.mjs | 4h |
| 文档改调 | 三份 writeback SKILL.md + merge-feature-branch SKILL + pipeline 三节点 prompt + ARCHITECTURE.md §3/§6 | 7h |
| 跨仓修正 | knowledge-base：优化方案文档 §4.2 traceability 表述修正 | 1h |
| 联调/验收 | 挑一个真实小 CR（或既有已归档 CR 的只读重放）跑三脚本 dry-run + 实跑，核对 AC-1~8 | 3h |

**估算总工时：36h（约 5 人天）**

## 2. 任务依赖图

```
TASK-01 (lib.mjs)
   ├─→ TASK-02 (writeback-prd-sdd.mjs)
   ├─→ TASK-03 (writeback-tasks.mjs)
   └─→ TASK-04 (writeback-traceability.mjs)
           │
           ├─→ TASK-05 (test/writeback.test.mjs，依赖 02/03/04 全部落地)
           └─→ TASK-06 (三份 writeback SKILL.md 改调，依赖 02/03/04 的实际 CLI 契约)

TASK-07 (merge-feature-branch SKILL + pipeline prompt + ARCHITECTURE.md §3/§6)
   — 不依赖脚本实现，可与 TASK-01~06 并行；仅需 SDD 定案的落点路径（已在 §8 D1 定案）

TASK-08 (knowledge-base：优化方案文档 §4.2 修正)
   — 跨仓独立任务，无依赖，可随时插入
```

关键路径：TASK-01 → TASK-02/03/04（并行）→ TASK-05 → 联调验收。TASK-06/07/08 不在关键路径上。

## 3. 资源与分工

单人（Ray）串行执行，按依赖图顺序：TASK-01 → {02, 03, 04} → {05, 06} 并行 → 07/08（穿插）→ 联调验收。

## 4. 风险与回滚策略

| 风险 | 应对 |
|---|---|
| SDD §8 的三处偏差（D1/D2/D3）在实现中发现仍不成立 | 已在 SDD 评审 attempt 1 中人工确认；若编码中发现新证据推翻，回到 write-tech-design 补一轮 reviewLoop，不得在 TASK 里静默改设计 |
| lib.mjs 的定向正则在真实文件（尤其 989 行 traceability.yml）上锚点误判 | TASK-04 验收条件要求对 `specs/ai-first-platform/traceability.yml` 做只读 dry-run 实测（不落盘），确认锚点定位正确后才算完成 |
| 三脚本改动被误用于账本文件 | TASK-01 lib.mjs 不提供任何指向 `_backlog.yml`/`_history.yml`/`cr.md`/CR `tasks/_index.yml` 的写函数，回归测试（TASK-05）显式断言这四类路径不在任何写调用中出现 |
| 回滚 | 全部改动限定在 tools 仓与 knowledge-base 仓的独立 commit，未合并前可随时 `git reset`；已回写的 specs/delivery 文件通过 git revert 单 commit 回退（NFR-1 精神） |

## 5. 验收与发布策略

- 联调阶段挑一个真实场景验证：优先用只读 dry-run 对已归档 CR（如 CR-2026-019）的 specs/traceability 现状跑一遍三脚本，确认无锚点误判、无 diff 意外；不对已归档产物落盘写入。
- 发布前 checklist：AC-1~8（PRD）逐条核对 + `node --test skills/writeback/scripts/test/writeback.test.mjs` 全绿 + `crctl` 既有测试套件不受影响（`node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全绿，确认未误碰账本路径）。
- 无 feature-flag 需求：三脚本是新增文件，不影响现有 SKILL 手工流程的可用性（旧描述性步骤在 SKILL 改调 commit 前仍可用），发布即替换 SKILL 描述，无需灰度。

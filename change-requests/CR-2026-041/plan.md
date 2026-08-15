---
id: CR-2026-041-plan
type: PLAN
cr-ref: CR-2026-041
sdd-ref: "change-requests/CR-2026-041/sdd.md"
target-version: tbd
status: draft
created: 2026-08-15T22:05:40+08:00
updated: 2026-08-15T22:05:40+08:00
---

# 开发计划 — CR-2026-041 归档可信化

## 1. 交付里程碑

| 里程碑 | 内容 | 任务 | 估算 |
|---|---|---|---|
| M1 证据生成 | generator 读 7 份 canonical 证据、注入 `evidence` 块、删 `status`；唯一 validator + `--validate-evidence` 内部模式；trunk/文案事实源修正 | TASK-01~03 | 14h |
| M2 归档证据门 | `archiveCr` pre-authority 分流 + `runFixedEvidenceValidator` 适配；milestone-file 契约去 status | TASK-04~05 | 7h |
| M3 能力退役 | 删除 change-impact-analysis、feedback-writeback 及全部 active 引用 | TASK-06~07 | 6h |
| M4 测试回归 | generator/validator/archive gate 单测、退役静态扫描、FR-03 回归、跨平台全量 | TASK-08 | 5h |

**估算总工时：32h（4 人天，按 8h/人天）**

## 2. 任务依赖图

```text
TASK-01 (evidence 注入) ──► TASK-02 (唯一 validator + --validate-evidence) ──► TASK-04 (archive gate 适配)
TASK-03 (事实源修正) ──────────────────────────────────────────────────────────► TASK-08 (测试回归)
TASK-05 (milestone-file 契约) ──────────────────────────────────────────────────► TASK-08
TASK-06 (change-impact 退役) ───────────────────────────────────────────────────► TASK-08
TASK-07 (feedback 退役) ────────────────────────────────────────────────────────► TASK-08
```

- TASK-01/02/03 同改 `writeback-traceability.mjs`，TASK-02 依赖 TASK-01 的 evidence 块产出契约。
- TASK-04 依赖 TASK-02 的 `--validate-evidence` 内部模式（crctl 通过固定脚本调用唯一 validator）。
- TASK-05 独立（只改 SKILL.md 文本契约），可与 TASK-01 并行。
- TASK-06/07 独立删除+引用收敛，互不依赖，可与 M1/M2 并行。
- TASK-08 依赖全部实现任务，最后执行。

## 3. 资源与分工

| 角色 | 任务 | 说明 |
|---|---|---|
| 开发（Ray） | TASK-01~05 | generator + archive gate + 契约 |
| 开发（Ray） | TASK-06~07 | 退役删除 + active 引用收敛 |
| 测试（Ray） | TASK-08 | 单测 + 回归 + 静态扫描 |

单一 owner，串行推进；退役（TASK-06/07）可在 M1/M2 间隙并行完成。

## 4. 风险与回滚策略

| 风险 | 影响 | 回滚策略 |
|---|---|---|
| generator 改动破坏既有 traceability 幂等/字节保留 | 已归档 CR 的 traceability 段被改写 | 历史 milestone opaque 逐字节保留断言不变；SELF_CHECK 新增断言防回归；改动前跑既有 writeback.test.mjs 全量 |
| `--validate-evidence` 模式误触发生成/写文件 | archive 只读门产生副作用 | validator 模式不生成 candidate、不写文件、不推进状态；SELF_CHECK 验证该模式零输出 |
| `archiveCr` 分流时机错误（journal 先建后验） | 证据门失败仍留 journal 残留 | 用 `loadExistingJournal`（只读）先判 `needsEvidence`，通过后才 `loadOrCreateJournal`；测试断言失败时零 journal |
| 退役清理漏改 active 引用 | 悬空引用/矩阵漂移 | 退役静态扫描测试（active 路径零 `change-impact-analysis`/`feedback-writeback`/`feedback-writeback-done`）兜底；`CUSTOM-TODO-010` 保留 |
| Windows/Ubuntu CRLF 差异 | digest 跨平台不一致 | digest 用 LF 归一内容哈希；CAS 锚点沿用 raw-bytes；双平台全量回归 |
| trunk 去回退后旧数据无 trunk | generator 硬失败 | 缺失即 `TRUNK_UNKNOWN` 硬失败，不静默回退 master；dir-graph 补齐后重跑 |

## 5. 验收与发布策略

**发布前 checklist：**

1. `writeback.test.mjs`、`archive-tx.test.mjs`、`writeback-tx.test.mjs`、`contract-scan`（或新增退役扫描）全部通过。
2. 证据齐全 CR 归档成功；证据缺失/漂移/路径互换/状态未通过 CR 归档硬失败且零 journal/authority 写入。
3. pre-authority 分流：无 journal 校验；pre-authority journal 校验且失败不改 journal；已 commit/push 与 cleanup/complete 恢复跳过；rejected/withdrawn 跳过。
4. 退役静态扫描证明 active 路径零 `change-impact-analysis`/`feedback-writeback`/`feedback-writeback-done` 引用，且 `CUSTOM.md#CUSTOM-TODO-010` 与 `CONTEXT.md` 保留。
5. Ubuntu/Windows 全量通过，不新增生产依赖。

**发布策略：**

- 本 CR 只改 Tools 仓方法论包代码，无 feature-flag（方法论包无运行时用户）。
- 交付以 branch `requirement/CR-2026-041` merge 到 `custom/main` 为界，merge 后走既有 writeback/archive 流程。
- 归档可信化能力随本 CR 的 archive 路径一起生效，不单独开关。

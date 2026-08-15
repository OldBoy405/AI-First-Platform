---
spec-id: ai-first-platform
version: "0.20.3"
id: CR-2026-041-TASK-02
type: TASK
cr-ref: CR-2026-041
plan-ref: "change-requests/CR-2026-041/plan.md"
sdd-ref: "change-requests/CR-2026-041/sdd.md"
title: 唯一证据校验函数与内部校验模式
slug: evidence-validator-internal-mode
status: pending
estimate: 6h
depends-on:
  - CR-2026-041-TASK-01
created: 2026-08-15T22:05:40+08:00
---

# TASK-02 唯一证据校验函数与内部校验模式

## 1. 任务描述

在 `writeback-traceability.mjs` 中新增唯一证据校验函数 `validateMilestoneEvidence`，并支持仅供 `crctl archive` 内部调用的 `--validate-evidence` 模式。正常生成路径在 candidate 后调用同一函数自检；archive 通过该内部模式复用同一函数。对应 FR-01（校验侧）与 FR-04（唯一校验函数归属）。

## 2. 涉及文件 / 模块

- `skills/writeback/scripts/writeback-traceability.mjs`（唯一改动文件）

## 3. 实现要点

- `validateMilestoneEvidence({ traceText, cr, specId, editRoot })`：
  - 按 `- cr: {cr}` 定位当前 milestone（不依赖 `status`）。
  - 解析 `evidence` 块；缺失 / milestone 重复 / evidence key 重复 → 结构化错误。
  - 每条证据 path 必须与 §2.2 固定 map 精确相等，再读文件重算 LF digest 比对；最后校验 status/verdict/四 grant/merge 事实。
  - 失败输出结构化错误码：`EVIDENCE_INVALID` / `EVIDENCE_DUPLICATE` / `EVIDENCE_PATH_INVALID` / `EVIDENCE_DRIFT` / `EVIDENCE_STATE`。
- `--validate-evidence --workspace <ws> --cr <cr> --spec <spec>` 模式：
  - 读既有 `specs/{spec}/traceability.yml`，调用 `validateMilestoneEvidence`。
  - 只输出 JSON 结果（`ok` 或结构化 `error`），不生成 candidate、不写文件、不推进状态、不读 milestone-file。
  - 参数解析与正常生成路径分支分离；缺参 `fail('BAD_ARGS', ...)`。
- 正常生成路径：`buildSegment` 产出的 `traceText` 通过 `validateMilestoneEvidence({ traceText, cr, specId, editRoot: ws })` 自检后才 `writeCandidate`（对齐 SDD §4.1）。
- 不新增 crctl 子命令；该模式只被 TASK-04 的 `runFixedEvidenceValidator` 通过 `spawnSync(shell:false)` 调用。

## 4. 验收条件

1. `--validate-evidence` 对证据齐全的 `traceability.yml` 返回 JSON `ok`，对缺失/漂移/路径互换/verdict 非 pass 的输入返回对应结构化 error 且进程非零退出。
2. 正常生成路径在 evidence 块构造错误时（如测试篡改 path map）自检失败，不产生 manifest。

## 5. 完成标志

`node writeback.test.mjs`（validator + 内部模式用例）通过；`--validate-evidence` 手动运行验证零文件写入、零状态变化。

## 6. 接口契约

- **消费**：TASK-01 的 `readEvidenceInputs` / `buildSegment` 产物；`lib.mjs` 的 `sha256`/`normalize`/`readFile`/`parseYaml`/`matchEntryBlock`。
- **产出**：
  - `validateMilestoneEvidence({ traceText, cr, specId, editRoot }) -> { ok: true } | fail(code, msg)`
  - 内部模式 CLI：`node writeback-traceability.mjs --validate-evidence --workspace <ws> --cr <cr> --spec <spec>`（TASK-04 消费）。

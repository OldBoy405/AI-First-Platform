---
id: CR-2026-025-TASK-03
type: TASK
cr-ref: CR-2026-025
plan-ref: "change-requests/CR-2026-025/plan.md"
sdd-ref: "change-requests/CR-2026-025/sdd.md"
title: 项④ review-record 三账本一致写与 cmdNext drafting 路由
slug: review-record-trace-projection
status: pending
estimate: 8h
depends-on: [CR-2026-025-TASK-02]
created: "2026-08-09T02:30:00+08:00"
---

## 1. 任务描述

重构 `crctl review-record` 为「全校验 → 一次生成 → `casWriteMulti`」，同步生成 canonical annotation、`review-loop.yml` 与 `traceability.yml#reviews.<stage>` 投影（三 stage 同一函数）；requirement 阶段写入被评审 PRD 的 LF 规范化摘要；`cmdNext` 在 drafting 按摘要判定回修/重审路由（PRD 项④，SDD §4.4）。depends-on 指向 M1 批次收口任务 TASK-02（批次原子性）。

## 2. 涉及文件

- 修改：`tools/skills/shared/crctl/scripts/crctl.mjs`（`cmdReviewRecord`、`bumpAttempt` 拆分、新增 `upsertReviewsStage`、`cmdNext` drafting 分支）
- 修改：`tools/skills/shared/crctl/scripts/test/crctl.test.mjs`（FR-21 八类向量）

## 3. 实现要点

- **I-1 拆分**：从 `bumpAttempt` 抽出纯函数 `nextLoopText(loops, loopRef, recordedAt, identity): string`；`bumpAttempt` 改为「read → nextLoopText → write」组合，`crctl attempt` 独立子命令行为不变。
- **cmdReviewRecord 重构**（SDD §4.4a）：全部前置校验（stage 映射/前置态/payload schema/exhausted/trace 结构/CR-ID 一致性）在任何写入之前；`recordedAt = nowIso()` 一次生成三账本共用；构造 annotation/trace/loop 三份文本后交既有 `casWriteMulti`（annotation 首建 `expectedHash=null`）；未带 `--bump-attempt` 时不写 review-loop.yml，只投影既有当前轮次：`current-attempt=0` 时投影空 `attempts`，不得伪造 attempt=1；只有 `--bump-attempt` 创建首条轮次账本。
- **attempts 历史合并**（§4.4a 2b，TD-BL-1/TD-BL-4）：`stageNode = parseYaml(traceText)?.reviews?.[stage]`；仅 `stageNode === undefined` → 首写合法，`oldAttempts = []`；目标 stage 已存在时，`review-loop` 与 `attempts` 均必须存在且分别为映射、列表，缺失或形状不合均为 `TRACE_SHAPE`。bump 追加新条目（重号 → `TRACE_SHAPE`）；非 bump 仅在 `current-attempt>0` 时按该轮整条替换或追加，`current-attempt=0` 保持空历史。历史数据源唯一 = trace 现有投影，禁从 review-loop.yml/annotation 臆造 result/blocker-count。
- **upsertReviewsStage**（§4.4c）：行级定点编辑，风格对齐 `matchEntryBlock`/`editTaskDone`；trace 为 null 返回最小骨架；cr-id 不匹配 / 无 `reviews:` / 重复 stage 键 → `TRACE_SHAPE`；非目标行 LF 规范化后逐字节保留（AC-19 口径，TD-SUG-2）。
- **投影字段**（§2.4）：reviewer/verdict/reviewed-at/blocker-count/annotation/repair-target + review-loop{current-attempt,max-attempts,attempts[]}；repair-target 按 stage 映射 `write-requirement-prd`/`write-tech-design`/`implement-code`；max-attempts 运行时读 pipeline JSON `reviewLoop.maxAttempts`。
- **subject-sha256**（§4.4b）：仅 `--stage requirement`，`sha256(readFileSync(prd).replaceAll('\r\n','\n'))` 全量 hex，annotation 追加 `subject-file`/`subject-sha256` 两标量。
- **cmdNext drafting**（§4.4d）：①prd 缺失→write-requirement-prd；②失败证据且摘要==当前→write-requirement-prd（why 含条数+annotation 路径）；③失败证据摘要不同→review-requirement；④其余（含无摘要旧证据）→review-requirement。禁 mtime。

## 4. 验收条件

1. FR-21 八类向量全过：①三 stage 投影正确；其子场景覆盖“trace 已有 requirement 投影、首次写 tech-design/code”成功、目标 stage 已存在但缺 `review-loop` 或 `attempts` 时 `TRACE_SHAPE` 且三账本不变、以及非 bump 且 `current-attempt=0` 投影空历史不伪造 attempt=1；②`--bump-attempt` 后三账本 attempt/verdict/blocker-count/时间一致，第二轮保留 attempts 历史；③trace 缺失创建骨架、已有其他段保留；④结构错误/注入 CAS 失败时三账本 sha256 均不变且 payload 保留；⑤drafting 同摘要 block→write-requirement-prd；⑥PRD 实质修改→review-requirement；⑦仅 LF/CRLF 差异不视为已回修；⑧无摘要旧证据兼容。
2. AC-19/AC-20/AC-21/AC-22 逐条对照执行证据。
3. `crctl attempt` 独立子命令回归向量全绿；`node --test crctl.test.mjs` 全绿。

## 5. 完成标志

FR-21 八类向量全绿 + 既有用例零回归 + `_index.yml` 登记 done。

## 6. 接口契约

- 消费：既有 `casWriteMulti(writes: {path, expectedHash, newText}[])`、`readAttempts(ws, cr, loopRef, gates)`、`parseYaml`、`sha256`、`REVIEW_STAGE_FILES`/`REVIEW_STAGE_LOOPS`/`REVIEW_STAGE_EXPECT`（均不改语义）。
- 产出：`nextLoopText(loops: object, loopRef: string, recordedAt: string, identity: string): string`；`upsertReviewsStage(traceText: string|null, stage: string, cr: string, blockText: string): string`（形状错误即 `fail('TRACE_SHAPE')`）——均为模块内函数，无新 CLI 子命令/旗标（NFR-2）。

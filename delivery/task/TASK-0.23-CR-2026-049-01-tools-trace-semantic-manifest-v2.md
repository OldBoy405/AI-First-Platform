---
spec-id: ai-first-platform
version: "0.23"
id: CR-2026-049-TASK-01
type: TASK
cr-ref: CR-2026-049
plan-ref: "change-requests/CR-2026-049/plan.md"
sdd-ref: "change-requests/CR-2026-049/sdd.md"
title: tools — trace 语义对象与 candidate manifest v2
slug: tools-trace-semantic-manifest-v2
status: pending
estimate: 12h
depends-on: []
created: 2026-08-20T20:59:46+08:00
---

# TASK-01 — tools：trace 语义对象与 candidate manifest v2

## 1. 任务描述

在 tools 仓（worktree `CR-2026-049`）加固 `yaml-subset.mjs`，使现有 `specs/ai-first-platform/traceability.yml`（191KB、36 个 milestone 段）可被完整解析为语义对象；`writeback-traceability.mjs` 对生成文本做结构化校验，并把 canonical trace payload `{spec_id, traceability}` 以 manifest v2 形式随 candidate 冻结（`payloadSha256` 纳入 `inputDigest`）。crctl 不做第二次自由解析（SDD §2.6，TD-B1）。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/yaml-subset.mjs`（加固）
- `skills/writeback/scripts/writeback-traceability.mjs`（validateTraceSemantic + event）
- `skills/writeback/scripts/lib.mjs`（computeInputDigest 支持 manifest v2）
- 测试 fixture：现有 191KB traceability.yml、CRLF 变体、plain-scalar/flow 用例

## 3. 实现要点

- `parseYaml` 修正：以 `{`/`[` 开头但 `parseFlow` 失败的行回退为 plain scalar；无法解释的结构抛错（`YAML_SUBSET_PARSE_FAILED`），禁止静默降级。
- `validateTraceSemantic(traceDoc, {cr, specId})`：顶层为映射、`spec-id===specId`、`cr-ref===cr`、`milestones` 为数组、YAML 文本中 `- cr:` 数量等于对象数组长度、当前 CR 恰一段、该段含 `frs|fr-chain` 与 `evidence`。
- manifest v2：`event={kind:'trace', payload:{spec_id, traceability}, payloadSha256}`；`computeInputDigest` 的 canonical JSON 覆盖 `event.kind/event.payload/event.payloadSha256`。baseline/tasks 继续 v1；traceability 必须 v2。

## 4. 验收条件

1. Node 测试：现有 191KB 累积 traceability.yml 解析成功，`milestones.length===36`、最后一个 `cr==='CR-2026-048'`；CRLF 输入与 LF 归一后结果一致。
2. 结构校验失败用例（缺 `spec-id`、当前 CR 段数≠1、段数与对象数组长度不等）均非零退出，错误码可断言。
3. 篡改 manifest v2 的 payload 后 `inputDigest` 变化；v1 文件仍被接受。

## 5. 完成标志

`node --test` 全绿；`--check` 风格 fixture 断言通过；diff 仅限上述文件。

## 6. 接口契约

- 消费：无上游 TASK。
- 产出：
  - `parseYaml(text) -> object`（lib/yaml-subset.mjs，行为如 §3）。
  - manifest v2 `event` 结构：`{kind:'trace', payload:{spec_id:string, traceability:object}, payloadSha256:string}`，供 TASK-02 校验与发射。

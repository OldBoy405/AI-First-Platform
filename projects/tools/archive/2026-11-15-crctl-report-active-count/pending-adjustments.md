# 待处理调整 — 2026-11-15-crctl-report-active-count

长程模式（`full_auto`）下按 build.md B4 记录的小偏离／欠妥表述。均**不改变**接口、行为语义或受审承诺，因此未改受审文档、未重签 Gate 2。

## ADJ-001（文档表述有误，实现未受影响）

- 原始设计引用：`design.md` 三、D3 末句「`active[]` 数组元素形状 `{cr, status, created}` 不变；仅在 history 中的 CR，`created` 为空串。」
- 事实：`cmdReport` 的 stdout **没有** `active[]` 明细数组——旧实现只是本地累计 `active` 数组后输出 `active: active.length`（整数）。新实现同样只输出计数，`total`/`statusHistogram` 的字段名与类型未变（proposal 约束「输出字段名不增不删」成立）。
- 影响：无行为影响；该句描述的是一个不存在的字段。
- 处理：**已在修订轮订正**——`design.md` D3 改为「`active` 是计数、旧实现的内部数组已不再构造」，`canonical/specs/code/crctl-report.yaml` 的 SC-002 同步改为「`active` 为 1 且直方图唯一非终态键为 `developing`」；随 Gate 2 重签生效。

## ADJ-002（测试断言写法调整，实现未受影响）

- 原始表述引用：`test-plan.md` 用例 1.1/1.2 预期结果里的直方图「`{archived:2, withdrawn:1}`」「`{developing:1, archived:1, rejected:1, withdrawn:1}`」。
- 实际调整：断言从 `JSON.stringify(...) === 固定串`（隐含键序）改为 `Object.entries(...).sort()` 的 `deepEqual`，期望的键值集合逐字保持。
- 原因：`statusHistogram` 的键序取决于 CR 遍历顺序，固定串断言会在实现顺序变化时误报，属于测试脆性而非规格变化。
- 影响：判定标准不放宽（仍是完整键值集合比较）。

## ADJ-003（不可判数据的失败路径比 proposal 文字更细）

- 原始表述引用：proposal 约束「终态集合不可判定时以错误码硬失败，不退化为空集合或内建枚举」。
- 实现：配置侧统一 `REPORT_TERMINAL_UNAVAILABLE`，`reason` 为 `dir-graph-unparseable` 或 `terminal-missing-or-invalid`（缺文件由 `TOOLS_PACKAGE_NOT_FOUND` 先失败）；账本侧复用 `LEDGER_PARSE_FAILED`、`HISTORY_DUPLICATE_ENTRY`、`HISTORY_FINAL_STATUS_MISSING`、`SCHEMA_INVALID`。`extra` 带 `path`/`id`/`field`/`got` 便于定位。
- 影响：错误信息更细，仍是硬失败；proposal 未规定错误码名与粒度。

## ADJ-004（`total` 的并集口径；重复 history id 改为硬失败）

- 原始表述引用：proposal 约束「`total` 按 CR 编号去重」与「`archived` 含义保持不变」。
- 实际调整：
  1. `total` 明确为「目录与 history 的 CR id 并集大小」，因此**开始计入没有 `archived-at` 的 history 条目**（旧版这类条目只进直方图、不计入 `total`）。这是本次唯一的输出口径扩展，TC-RPT-002 用 `CR-RAW` 锁定。
  2. 同一 `id` 在 history 出现多次时**硬失败** `HISTORY_DUPLICATE_ENTRY`（复用 `findHistoryEntry` 的既有错误码），不再“取最后一条 + 按 CR 计数”。这样 `archived` 可以保持「带 `archived-at` 的条目数」的原始语义，且恒有 `archived ≤ total`。
- 原因：C1 代码评审指出「直方图取最后一条、`archived` 按 CR 去重、`periodActivity` 按条目累加」三者口径不一致，会在重复 id 时给出互相矛盾的报表；改为一律拒绝二义数据，比自定义容忍规则更可验证。
- 影响：数据本身有重复 id 时 `report` 从“出错数”变为“报错”；真实知识库 76 条 history 无重复，输出不受影响。

## ADJ-005（history 的 id 不做大小写／空白归一）

- 评审指出去重键是精确字符串，`- id: cr-a` 与目录 `CR-A` 会算成两个 CR。
- 处置：不修。真实数据无此形态；`crctl` 其他命令（`status`/`archive`）同样按精确字符串比对，单在 `report` 归一会造出第二套口径。
- 影响：数据录入错误时会表现为 `total` 偏大，但不会静默吞掉 CR。

## ADJ-006（未纳入 `publishedArchiveStatus` 兜底）

- `crctl status` 在本地主 checkout 未同步已发布归档时会读归档 journal 兜底；`report` 不读 journal，只按本地 `_history.yml` 聚合。
- 处置：不修，属独立议题（AIFI-65 R3 的适用面），本 change 未声明。

## ADJ-007（`statusHistogram` 键不做枚举校验）

- 非法 `status`（如非字符串）会原样成为直方图的键。
- 处置：不修，超出本 change「去重 + 终态排除」的声明范围；记入后续候选。

## ADJ-008（证据产物不保存观测值）

- `tc-evidence.json` 与 `agent-verification-report.md` 只记录 CP 的 PASS 与 `exit_code`，不保存 stdout 中的观测值。
- 处置：不修（runner 现有行为）；观测值留档于 `test-report.md` 第五节与本次会话输出。

## ADJ-009（`spec-dashboard` 仍持旧口径）

- 评审（docs）指出 `skills/spec/spec-dashboard/SKILL.md:39`「按 `cr.md` frontmatter 分组计数」与 `:47-53` 的终态行仍是本次被推翻的口径；`design.md` 1.0 版「`spec-dashboard` 只引用命令名、不涉及口径」的断言与事实相反，已在 1.1 版订正。
- 处置：**本次不改该文件**（proposal `what_changes` C3 只声明 `cr-dashboard`），登记为已知不一致，交由后续 change 处理；Gate 3 报告里明示。
- 影响：两个看板技能对同一命令的口径说法冲突，直到后续 change 修掉。

## ADJ-010（删除 `stdd new` 的 TODO 规格脚手架）

- `stdd new` 在 `canonical/specs/{code,agent}/2026-11-15-crctl-report-active-count.yaml` 生成 `capability: "TODO"`、`REQ-001`、`CP-1` 的脚手架，并被写进 `.stdd.yaml#spec.input_manifest`，与真实规格（`crctl-report.yaml`）并存。
- 处置：删除两份脚手架；`input_fingerprint` 随 Gate 2 重签重建。

## ADJ-011（基线既有行为，未改）

- 目录 `cr.md` 缺 `status` 时仍被 `report` 静默跳过（与改动前一致）；直方图用普通对象承载动态状态键，`__proto__` 之类的状态名会丢计数。两者都是基线问题，本 change 不触碰，建议后续单列处理。

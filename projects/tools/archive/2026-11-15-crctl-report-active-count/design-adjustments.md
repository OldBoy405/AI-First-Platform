# 设计调整汇总 — 2026-11-15-crctl-report-active-count

> 由 `pending-adjustments.md` 汇总（build.md C6）。7 条均为**不改变接口、行为语义或受审承诺**的小偏离；受审文档未动，Gate 2 未重签。

## 修订需求（供后续迭代）

1. **ADJ-001（已修）**：`design.md` D3 与 SC-002 曾提到不存在的 `active[]` 数组；已在修订轮订正，随 Gate 2 重签生效。
2. **ADJ-002**：直方图断言改为键序无关的 `deepEqual`，期望键值集合不变。无需修订文档。
3. **ADJ-003**：`REPORT_TERMINAL_UNAVAILABLE` 的 `reason` 分三种（`dir-graph-unparseable`、`terminal-missing-or-invalid`，以及被 `TOOLS_PACKAGE_NOT_FOUND` 覆盖的缺文件情形）。属错误信息细化。
4. **ADJ-004**：`archived` 口径由“history 条目数”改为“带 `archived-at` 的不同 CR 数”，避免重复 id 时出现 `archived > total`。真实数据取值不变。
5. **ADJ-005**：CR 编号不做大小写／空白归一，与 `crctl` 其他命令保持一致。
6. **ADJ-006**：`report` 未纳入 `publishedArchiveStatus` 兜底（归档 journal），属独立议题。
7. **ADJ-007**：`statusHistogram` 键不做枚举校验，超出本 change 声明范围。

8. **ADJ-009**：`skills/spec/spec-dashboard/SKILL.md` 仍按旧口径描述，本次未改（proposal C3 只声明 `cr-dashboard`），列为已知不一致。
9. **ADJ-010**：删除 `stdd new` 生成的两份 TODO 规格脚手架，避免同一 change 有两份互相矛盾的 spec 事实源。

## 顺带记录的既有限制

- **ADJ-008**：证据产物只保存 PASS/`exit_code`，不保存观测值；观测值留档在 `test-report.md`。

## 对后续 change 的输入

- 若下次修订 `cmdReport`，可一并处理 ADJ-001（文档句）、ADJ-006（journal 兜底）、ADJ-007（状态枚举校验）。

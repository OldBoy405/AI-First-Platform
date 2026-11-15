# BUILD 偏离记录 — 2026-11-15-controlled-shell-snapshot-read-shapes

> 逐条在本阶段发现时记录；C6 汇总进 design-adjustments.md。

## ADJ-1 新测试须登记到 suite-gate manifest（范围补充）

- **原始设计**：proposal「What Changes」与 design「Architecture」只列 `rules.json`、1 个新测试文件、`SKILL.md`、`CUSTOM.md`。
- **实际调整**：`skills/shared/crctl/scripts/test/gate-registry.json` 的 `manifest.files` 与 `manifest.cases` 各加一条（`controlled-shell-rules.test.mjs`：2）。
- **原因**：`suite-gate.mjs:666-669` 在磁盘测试文件集合 ≠ `manifest.files` 时 BLOCK；CI 的 crctl 全量套件走该门禁（`.github/workflows/crctl-ci.yml`）。不登记会让本 change 的新测试使 CI 在启动前阻断。
- **影响**：仅登记面，无运行时行为变化；影响 TC-CSS-001/002 的 CI 可执行性。

## ADJ-2 SKILL.md 版本与子命令计数校正

- **原始设计**：design 决策 4 只要求「`show` 说明增加三种形状」。
- **实际调整**：除新增 `show` 行外，把「git 三元组 19 条」改为 21 条（表格列为常用 20 条，注明 `symbolic-ref` 未列出）；头部版本 v0.1.0 → v0.3.0 并补一行版本历史；`show` 行顺序按 `rules.json` 排列、补「40 位小写 hex」与「KEY 片段见 rules.json」。
- **原因**：`rules.json` 实有 21 条子命令（实测），加 `show` 行后若仍写 19 条即与表格直接矛盾，撞 SC-005「不含相互矛盾的说法」；头部 v0.1.0 与历史最新 v0.2.0 本就矛盾，本次改同一文件顺带校正。
- **影响**：文档事实修正，不改变受审承诺；spec/design/test-plan 未改。

## ADJ-3 CUSTOM-TODO-017 证据路径改指归档位置

- **原始文本**：`projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/cr-settle-fail-closed-20261030/`。
- **实际调整**：改为 `projects/multica/archive/...`（已核实 `changes/` 下不存在，`archive/` 下存在）。
- **原因**：引用失效；本 change 已改同一行，保留错误引用与 SC-005 的「描述与事实一致」相悖。
- **影响**：仅引用路径。

## ADJ-4 TC-CSS-004 的「已提交 rules.json」留到交付后复验

- **原始 spec**：SC-004 要求 `MULTICA_CONTROLLED_SHELL_RULES` 指向「本仓已提交的 rules.json」。
- **实际处理**：Gate 3 前不提交（提交需单独授权），本次以工作区文件运行 multica 6 个测试并记录 multica HEAD；「提交态」复验在 DELIVER 提交后补跑。
- **原因**：STDD Gate 不授权 Git 提交；不能为满足措辞而先提交。
- **影响**：TC-CSS-004 取证时点后移，验证内容不变；若提交未获授权，SC-004 的「已提交」措辞不成立，须在 test-report 如实标注。

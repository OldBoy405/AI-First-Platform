# 2026-11-15-crctl-report-status-integrity 任务清单

## 1. crctl-report-status-integrity（P0）

- [x] 1.1 RED：`crctl.test.mjs` 新增四个顶层测试 TCRSI001..004（无 status/无 cr.md/空 status；未声明状态与 false/0/数组/带空白；全部合法状态与合法动态键 __proto__/constructor/toString；transitions 缺失/为空/to 非法）；`makeReportToolsFixture` 默认声明补一条 `to: developing` 转移；运行 CP-RSI-001 命令确认红。
- [x] 1.2 GREEN：`cmdReport` 实现 design 决策 1–3——缺 status 显式区分（缺字段/无 cr.md/空串）并 `CR_MD_STATUS_MISSING` 点名 `cr/path/field`，false/0 不得归为缺失；`requireStateMachineTerminalForReport` 返回 `{terminal, known}`（`transitions[].to` ∪ `terminal`；transitions 缺失/为空/to 非法 → `REPORT_TERMINAL_UNAVAILABLE`、reason=`transitions-missing-or-invalid`）；目录与 history 写入 `byCr` 前各调用 `assertKnownStatus` → `SCHEMA_INVALID` 点名 cr/path/field/got；`statusHistogram` 改 `Object.create(null)`。成功输出字段与语义不变。
- [x] 1.3 REFACTOR + 复验：CP-RSI-001 一次 TAP 运行含 TCRSI001..004、`# pass 4`、`# fail 0`、exit 0；既有 TCRPT001–004 与 AC-6 两个用例全部通过。
- [x] 1.4 RED：`archive-tx.test.mjs` 新增顶层 TCRSI005——已发布未同步（本地 dirty 跳过同步、journal pushed=true）时 `crctl status`=archived/terminal，`crctl report` total 1/active 0/statusHistogram {archived:1}/archived 0；未发布（`archive-after-commit`）时 active 1、直方图为本地状态；改前应为红。
- [x] 1.5 GREEN：`cmdReport` 实现 design 决策 4——对「仅目录来源且非终态」的 CR 调用 `publishedArchiveStatus`，非空则以该终态替换；history 覆盖优先级、重复 id/缺 final-status 拒绝及 `archived`（含 archived-at）口径不变。
- [x] 1.6 复验：CP-RSI-005（TCRSI005、`# pass 1`、`# fail 0`、exit 0）与 CP-RSI-001 同次通过；`archive-tx.test.mjs` 与 `crctl.test.mjs` 全量不回归。
- [x] 1.7 TC-RSI-006 准备（required manual）：真实 `AI First Platform` 工作区改后运行 `crctl report`，与 2026-11-15 基线（total 76 / active 0 / archived 76 / {archived:68, withdrawn:8}）逐项比较，差异逐项解释数据来源（git log 与目录清单）；重跑 `crctl.test.mjs` 全部 report 用例。事实交用户确认，不代签。
- [x] 1.8 TC-RSI-007 准备（required manual）：`tools/CUSTOM.md`（LF）「AIFI-45 局部修复登记」节新增一行（日期｜位置｜改动｜边界；位置含 `crctl.mjs#cmdReport` 与 `spec-dashboard/SKILL.md`；边界写明成功输出字段不变、保留 history 重复 id/缺 final-status 拒绝与覆盖优先级、不改其他命令；不编造 CR 编号）。事实交用户确认。
- [x] 1.9 两项 required manual 合并为一次 `stdd agent confirm`（计划级全有或全无，须用户原话），确认后按切片登记。

## 2. dashboard-wording-consistency（P1）

- [x] 2.1 RED：运行 CP-DWC-001 命令记录改前红样本（`bad` 含三项冲突句、`need` 缺 `report.statusHistogram`/`report.active`、lint findings）。
- [x] 2.2 GREEN：按 design 决策 5 改 `skills/spec/spec-dashboard/SKILL.md` 三处（第 40 行改引用 `report.statusHistogram`；删第 56 行表内终态行并补表后说明；第 128 行改引 `report.active`）；`<!-- lint-prompts:ignore -->`（39/127 行）去留以 lint 实测为准；第 61/67/68 行不动。
- [x] 2.3 复验：CP-DWC-001（`0 findings`、`bad [] need []`、`CP-DWC-001 PASS`、exit 0）。

## 3. 测试与验证（P0）

- [x] 3.1 同次执行证据：先 `stdd agent verify crctl-report-status-integrity --change 2026-11-15-crctl-report-status-integrity --dry-run` 预检，再用同一 run id 执行正式 verify（CP-RSI-001/005、CP-DWC-001）与 `stdd ci check-failures --run <同 run>`，中间不跑其它 verify。
- [x] 3.2 C1 三路并行评审（code=strong / test_config=balanced / docs_skills=economy），逐条处置（修复或记录已知问题）。
- [x] 3.3 C3 逐文件 diff 审查；C4 失败模式 a–n 全量；C5 经验库记录；C6 `design-adjustments.md`；C7 `test-report.md`。
- [ ] 3.4 展示 Gate 3 确认框，等用户原话确认（`stdd gate approve … --gate 3 --run <id> --confirmed-by dialog --evidence "<原话>"`）；不代签、不自动批准。

<!--
优先级说明：
- P0：阻塞性任务，完成前无法进入下一阶段
- P1：重要任务，应在当前阶段完成
- P2：可延后到后续版本的任务
依赖标注：(依赖 #N.M) 表示此任务依赖第 N 组第 M 个任务完成后才能开始
-->

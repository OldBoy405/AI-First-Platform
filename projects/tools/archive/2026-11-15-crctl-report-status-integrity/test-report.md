# test-report — 2026-11-15-crctl-report-status-integrity

- change：`2026-11-15-crctl-report-status-integrity`（业务仓 tools，记录根 AI First Platform，project_id=tools）
- 日期：2026-11-16
- 模式：standard / long_range full_auto（范围内一次性预授权）
- 选定 run：**`4338f56c-a380-4ca0-b8df-b1916e0b2145`**（`validation/runs/4338f56c-a380-4ca0-b8df-b1916e0b2145/`）
- 业务工作树：未提交（提交/push/部署不在本阶段授权内，交付时另行授权）

## 1. 选定 run 与结果引用

- `stdd agent verify crctl-report-status-integrity --change … --run 4338f56c…`：CP-RSI-001、CP-RSI-005、CP-DWC-001 **3 passed / 0 failed**（`agent-verification-report.md`）。
- `stdd agent confirm … --run 4338f56c… --statement "确认该两项人工核对"`：TC-RSI-006/007 记为 manual-pass（用户原话，2026-11-16）。
- `stdd ci check-failures … --run 4338f56c…`：**9 通过 / 0 警告 / 0 错误**（含 TC 执行覆盖 5/5、4 个切片证据、契约一致 2 capabilities、覆盖率豁免声明）。
- 前序 run `668a0d47-0b3d-4ad6-bf78-602fce1199a6`（同样 3/3 + 9/9）因 C1 测试评审后补断言使测试输入变化而被取代；保留为历史证据，不参与 Gate 3 绑定。dry-run 输入预览：7 个 project 输入、5 个相对 HEAD 有差异（本轮业务文件）。

## 2. TC 覆盖（planned vs actual）

| TC | 类型 | 计划 | 实际 | 证据 |
|---|---|---|---|---|
| TC-RSI-001 | required command | 1 | 1 | CP-RSI-001：TCRSI001..004、`# pass 4`/`# fail 0`、exit 0；4/4 |
| TC-RSI-005 | required command | 1 | 1 | CP-RSI-005：TCRSI005、`# pass 1`/`# fail 0`、exit 0 |
| TC-RSI-006 | required manual | 1 | 1 | 真实 `crctl report`：total 76 / active 0 / archived 76 / `{archived:68, withdrawn:8}`，与 2026-11-15 基线逐项相同；既有 report 用例全量通过；用户原话确认 |
| TC-RSI-007 | required manual | 1 | 1 | `tools/CUSTOM.md`（LF，0 CRLF）+1 行登记，四列齐全、无编造 CR；用户原话确认 |
| TC-DWC-001 | required command | 1 | 1 | CP-DWC-001：`0 findings`、`bad [] need []`、`CP-DWC-001 PASS`、exit 0 |

覆盖率：**5/5（100%）**；3 项命令型 + 2 项人工，均无 skipped。

## 3. 覆盖率状态

证据计划声明 `coverage.applicability=not_applicable`，理由「Node 栈，仓库覆盖率检查只支持 pytest-cov」；ci (j) 通过。**不声明代码覆盖率保证**。`quality` 未在项目配置中定义 test/lint/typecheck 命令；本 change 的可执行验证为证据计划的三个命令 CP（`lint-prompts` 已含在 CP-DWC-001 内）。

## 4. 切片验证

| 切片 | TC | tc_coverage | new_tests | verified_at |
|---|---|---|---|---|
| 1 状态输入矩阵 | TC-RSI-001 | 1/1 | 4 | 2026-11-16T13:48:26.068237 |
| 2 已发布未同步归档 | TC-RSI-005 | 1/1 | 1 | 2026-11-16T14:04:43.995507 |
| 3 看板口径对齐 | TC-DWC-001 | 1/1 | 0（文档切片，验证为命令型 CP-DWC-001） | 2026-11-16T14:00:21.330648 |
| 4 人工回归与登记 | TC-RSI-006/007 | 2/2 | 0（两项 required manual） | 2026-11-16T14:25:53.714743 |

RED→GREEN 记录：TC-RSI-001 改前 4/4 红（含直方图 `constructor/toString` 原型污染实证）；TC-RSI-005 改前红（已发布归档 active=1，复现 ADJ-006）；TC-DWC-001 改前 `bad 3 项 / need 2 项`。未发生第三轮修复。

全量回归：`crctl.test.mjs` **309/309**、`archive-tx.test.mjs` **48/48**（均 exit 0、0 skip）；C1 补断言后复跑 report 子集 8/8。

## 5. Part C 各步结果

- **C1 三路并行评审**（configured：code=strong、test_config=balanced、docs_skills=economy；actual 未读运行元数据 = unknown）：三路均 **NON-BLOCKING**。已修复：TCRSI002 补 `error.got` 逐样本断言（数组样本实测 `['developing']`）、夹具替换护栏、tasks.md 勾选、slices.md 风险口径。已记录不改：受 Gate 2 冻结的 proposal/design/spec/agent spec/test-plan 字节、`periodActivity` 普通对象（改前遗留）、错误对象 `got` 在缺失分支（spec 未要求）。详见 `design-adjustments.md` §2。
- **C2 全量质量**：同 run 三 CP + `ci check-failures` 9/9；覆盖率按证据计划豁免；无其它项目级 quality 命令可执行。
- **C3 Diff 审查**：5 文件、+268/−16（`crctl.mjs`、`crctl.test.mjs`、`archive-tx.test.mjs`、`spec-dashboard/SKILL.md`、`CUSTOM.md`）；无调试残留、无死代码、无注释旧逻辑；`git diff --check` 通过；均在声明范围。
- **C4 失败模式检查**：见 §6，a–n 全量执行。
- **C5 经验库**：C4 未发现新 agent 失败模式；既有 5 条经验均为 `discovered`（无 verified/settled 可注入），其中「带引号 glob 交 node --test 会 0 用例」与「命令型 CP 判定面窄于 spec」已在设计中预防（显式文件路径 + 测试标识 + 具体断言）。未新增条目。
- **C6 设计调整**：`design-adjustments.md`——无改变受审承诺的偏离，不触发 Gate 重审。
- **C7 测试报告**：本文件。

## 6. 失败模式检查（C4，a–n 全量；run 4338f56c）

CLI 确定性子集（9/9 执行）：(a) 必需文件存在 ✓；(d) TC-ID 唯一(5) ✓；(f) THEN 含 SHALL ✓；(g) AND 数量正常 ✓；(j) 覆盖率义务已声明 not_applicable ✓；(k) 契约一致(2 capabilities) ✓；(l) Non-critical 无需锚定 ✓；TC 执行覆盖 5/5 ✓；4 切片证据 ✓。

人工/语义项：
- (b) scope_creep ✓：5 文件均在声明范围（report 实现、两个测试文件、看板措辞、CUSTOM 登记），无范围外改动。
- (c) cascading_errors ✓：四处改动相互独立；`fail()` 在写 byCr 前触发，错误路径不产生半张报表。
- (e) tool_misuse ✓：verify→confirm→ci 使用同一 run id 且中间无其它 verify；改测试后正确重建 run；未执行 git 写操作。
- (h) content_quality ✓：实现完整可用；真实数据回归与基线一致；文档与登记齐备。
- (i) instruction_decay ✓：长程中保持 Gate 3 不代签、不改受审文档、`.stdd.yaml` 仅经 CLI（long_range 字段按授权例外精准更新）、不 push、不 git add -A。
- (m) agent_cp_failure ✓（命令型）：CP 断言含区分对错的观测值（TAP 标识与计数、错误码、CR/path/field/got、bad/need 数组、findings 数），否定路径断言 JSON=null；无 PASS 标签式断言。
- (n) cross_system_mismatch ✓：CP 结果、run 证据、真实数据基线、CUSTOM 记录相互一致；被取代 run 已如实标注原因。

## 7. 已知问题与未完成项

- 无阻塞项。
- 记录不改（详见 design-adjustments §4）：`publishedArchiveStatus` 回写依赖 dir-graph 声明三终态；`periodActivity` 普通对象属改前遗留；受审文档行号/「当前状态」为 Gate 2 快照；CP-DWC-001 未机器断言表后说明句（文件存在该句，评审已核实）。
- 业务仓未提交；提交/push/部署与 Gate 3 均待用户授权/确认。

## 8. 边界

未修改受审 proposal/design/spec/agent spec/test-plan 字节；未手改 `.stdd.yaml` 的 Gate/切片字段（切片与阶段均用 CLI；仅 long_range 预授权字段按 AGENTS.md 例外精准更新）；未安装依赖、未启动共享服务、未访问真实远端（测试只推本地 bare remote）；未打印或写入任何凭据。

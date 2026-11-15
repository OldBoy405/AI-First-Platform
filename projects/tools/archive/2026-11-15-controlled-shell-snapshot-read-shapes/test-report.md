# controlled-shell git show 形状 — 测试报告

> Change: `2026-11-15-controlled-shell-snapshot-read-shapes`
> 业务仓: `C:\Users\GOBAO\Downloads\AI\tools`（HEAD `4afe0a7`，改动未提交）
> 选定 run: `validation/runs/css-20261115-2/`（`css-20261115-1` 在 SKILL.md 版本表顺序修正后输入指纹变化而作废；run 目录不可复用）
> 生成时间: 2026-11-15T22:40+08:00

## 一、选定 run 与结果

| 项 | 结果 |
|---|---|
| run id | `css-20261115-2` |
| CP-CSS-001（TC-CSS-001 放行表） | PASS：`pass 1 fail 0` + `CP-CSS-001 PASS` |
| CP-CSS-002（TC-CSS-002 拒绝表） | PASS：`pass 1 fail 0` + `CP-CSS-002 PASS` |
| 人工 TC-CSS-003/004/005 | 各 1 次 `stdd agent confirm`，`tc-evidence.json` 记为 `manual-pass` |
| `stdd ci check-failures` | 通过 8 / 跳过 1（(k) 少于 2 个 capability）/ 错误 0 |
| TC 执行覆盖 | 5/5（100%） |

证据文件：`validation/runs/css-20261115-2/{tc-evidence.json,agent-verification-report.md,inputs/}`。

## 二、TC 覆盖率（planned vs actual）

| TC | 类型 | 结果 |
|---|---|---|
| TC-CSS-001 | 命令（CP-CSS-001） | PASS |
| TC-CSS-002 | 命令（CP-CSS-002） | PASS |
| TC-CSS-003 | 人工 | PASS（结构化比较：除 `show.shapes` 外相同；原两条逐字保留） |
| TC-CSS-004 | 人工（跨仓） | PASS（multica 6/6，见下） |
| TC-CSS-005 | 人工 | PASS（SKILL.md / CUSTOM.md / rules.json 逐条一致） |

## 三、覆盖率状态

**not_applicable**：证据计划声明 `coverage.applicability = not_applicable`，理由「Node 栈，仓库覆盖率检查只支持 pytest-cov」。无覆盖保证。

## 四、切片验证

| 切片 | TC 覆盖 | 新增测试 | 状态 | 验证时间 |
|---|---|---|---|---|
| 1（rules.json + 新测试 + SKILL.md + CUSTOM.md + 登记面） | 5/5 | 2 | done | 2026-11-15T22:26+08:00 |

RED → GREEN 记录：

- RED（改 `rules.json` 前）：`✖ TC-CSS-001 …` / `✔ TC-CSS-002 …`，`pass 1 fail 1`。拒绝表在放宽前后都应成立，故 RED 阶段只许放行表红。
- GREEN（追加三条形状后）：`pass 2 fail 0`。
- 变异检查：把 `trace\.tests(?:\.yml|\.yaml|\.json)?$` 临时改为 `trace\.tests.*$` → `✖ TC-CSS-002`（`pass 0 fail 1`）；还原后文件 sha256 回到 `d7489aa4…`，两用例复跑 `pass 2 fail 0`。证明拒绝表能抓到「放宽过头」。
- 原两条形状与 HEAD 逐字一致；`rules.json` 相对 HEAD 仅 1 行变更（1/1）。

## 五、全量质量检查

| 检查 | 命令 | 结果 |
|---|---|---|
| crctl 全量套件（仓库门禁） | `node skills/shared/crctl/scripts/test/suite-gate.mjs --run` | 101/101 文件执行，2243 个用例，耗时 715.7s；`controlled-shell-rules.test.mjs` state=ok（2 用例，206ms）；1 个失败见 §七 |
| output-guard + pipeline-templates | `node --test output-guard/test/*.test.mjs pipeline-templates/*.test.mjs` | 104/104 pass，exit 0 |
| lint | `node skills/shared/crctl/scripts/lint-prompts.mjs` | 0 findings，exit 0 |
| typecheck | `check-agents-contract.mjs`、`check-skill-matrix.mjs` | 均通过（10 agents / 56 skills），exit 0 |
| 跨仓（TC-CSS-004） | multica `server/`：`MULTICA_CONTROLLED_SHELL_RULES` 指向本仓 rules.json，`go test ./internal/daemon -run '^(TestM26B2…|TestM26B4…|TestProposedSnapshotReadShapes)$' -count=1 -v` | 6/6 PASS（含 `crevents_test.go:985 checking the snapshot read shapes against the real rules.json`），3.7s；multica HEAD `b726f5131` |

> 说明：首次用 `cmd /c` 传带引号 glob 的全量命令得到 `tests 0 / exit 0`，属工具误用而非通过，已改用 `suite-gate` 与本机 bash 展开的 glob 重跑；由此记入 EXP-2026-0004。

## 六、C1 多路并行技术评审与处置

三路派发：code=`GB-JP/kimi-k3.1-pro:max`（strong）、test_config=`GB-JP/deepseek-flash:max`（balanced）、docs_skills=`Gobao/deepseek-flash:high`（economy）；均按 `stdd config models` 的 `review.agents.tier` 读取。actual 生效元数据未由平台回传，记为 unknown。

| 发现 | 严重度 | 处置 |
|---|---|---|
| 新测试未登记 `gate-registry.json`，`suite-gate` 会在启动前 BLOCK | high | 已修（ADJ-1）；`suite-gate` 重跑 101 文件无 drift |
| 40 位 hex 不区分 commit/tree/blob，`git show --name-only --format= <blob-sha>` 会输出 blob 内容（已实测） | high | 不修：三条形状由 spec SC-001 与 multica `TestProposedSnapshotReadShapes` 逐字固化，改 `^{commit}` 会破坏消费方；记入 design-adjustments「明确不调整」第 1 条 |
| 拒绝表在改前即通过，需变异检查才能证明其有效性 | medium | 已执行变异（见 §四），通过 |
| test-plan 头部引用的 canonical spec 路径不存在 | medium | 不改（Gate 2 受审字节），记入已知问题 |
| CUSTOM-TODO-017 证据路径指向已归档的 `changes/` | medium | 已修（ADJ-3）→ `archive/` |
| SKILL.md 头部版本与历史行矛盾；19 条计数与新增 show 行冲突 | medium | 已修（ADJ-2）：v0.3.0 + 21/20 口径 |
| SKILL.md show 行顺序与 rules.json 不同、可选后缀表述不清 | low | 已修：按 rules.json 顺序、标明「可带后缀」 |
| JS `$` 与 Go RE2 `$` 的尾换行差异 | low | 不修：真实 daemon 走 Go 侧（更严），crctl 侧只指向不存在路径；记入已知问题 |
| 与 `pipeline-structure` / `cr-id-format` 的样本重叠 | low | 不改 test-plan 措辞（受审字节），记录 |
| CP 固定 `pass 1`，新增同令牌用例会误报 | low | 现状成立（实测 pass 1）；新增用例时需同步改 CP，记录 |

## 七、失败模式检查（C4 全项）

| ID | 类别 | 结论 |
|---|---|---|
| (a) | hallucination | CLI `check_files_exist` 通过（必需文件与 spec 文件存在） |
| (b) | scope_creep | 人工 C3：工作区仅 4 改 1 新（rules.json / SKILL.md / CUSTOM.md / gate-registry.json / 新测试），无越界 |
| (c) | cascading_errors | 人工：登记面改动未引起其他套件失败；本次唯一过程性级联是并行 confirm 覆盖证据（见 §八），已修复并复验 |
| (d) | context_loss | CLI `check_tcid_unique` 通过（5 个 TC-ID 唯一） |
| (e) | tool_misuse | 有一起：`cmd /c` + 带引号 glob 得到 0 用例 exit 0；已改用 suite-gate/bash 重跑并记录 EXP-2026-0004 |
| (f) | runtime_deviation | CLI `check_shall_keyword` 通过（所有 THEN 含 SHALL） |
| (g) | pipeline_break | CLI `check_and_count`、切片完成度通过（1 切片有验证证据） |
| (h) | content_quality | 人工：TC-CSS-005 对照通过；SKILL/CUSTOM 描述与 rules.json 一致 |
| (i) | instruction_decay | 人工：C1–C7 全执行；偏差：C2 首轮在 C1 返回前启动（首轮因 glob 误用无效），C1 结论回来后已按发现修复并重跑，不影响最终判据 |
| (j) | coverage_vacuum | CLI 通过（声明无覆盖义务，理由见 §三）；TC 执行覆盖 5/5 |
| (k) | contract_gap | 跳过：少于 2 个 capability（CLI 判定） |
| (l) | anchor_missing | 通过：Non-critical change，无需锚定 |
| (m) | agent_cp_failure | 人工：CP-001/002 的判定面窄于 SC（只判「该用例通过」），但用例内部逐条断言放行/拒绝；变异检查证明拒绝表非空转。CP-002 单独看改前也绿，属既有局限，记录 |
| (n) | cross_system_mismatch | 人工：multica 6 测试对真实 rules.json 全绿，与 tools 侧对照表结论一致；40hex 对象类型差异见 K1，不构成两系统矛盾 |

## 八、过程记录

- **并行 confirm 竞态**：TC-CSS-004 与 TC-CSS-005 的 `agent confirm` 同时执行，004 的写入被覆盖（命令仍打印 recorded），`tc-evidence.json` 缺该 TC、`check-failures` 报缺失。改为串行重放 004 后 `check-failures` 达 5/5。已记入 EXP-2026-0005。
- **全量套件的读法**：`node --test` 的 reporter 输出在管道/重定向下按块落盘，不能靠日志停滞判断挂起；改用 `--test-reporter-destination` 与 `suite-gate` 的逐文件报告。
- **证据 run 不可续写**：证据 run 取完后又修正了 SKILL.md 版本表顺序（同一次文档修正的后继编辑），输入指纹变化使 run 1 作废；`agent verify` 拒绝复用已有 run 目录，改以 `css-20261115-2` 重跑并重录三条人工确认，`check-failures` 再次达 5/5。

## 九、已知问题与未完成项

| # | 名称 | 原因 | 影响 | 补完计划 |
|---|---|---|---|---|
| K1 | 40 位 hex 不区分 commit/tree/blob | 参数文本无法区分对象类型；形状被 spec 与 multica 测试逐字固化 | 可读出任意 blob 内容（`git show --name-only --format= <blob>`）；与「只读取证」承诺不冲突，但宽于「只列变更文件」 | 需与 multica 同步改调用形态（如 `^{commit}`）后再收窄；本 change 只记录 |
| K2 | JS `$` 尾换行差异 | JS `$` 可在末尾换行前匹配，Go RE2 不行 | crctl 侧可放行带尾换行的参数（指向不存在路径）；gitguard 侧更严 | 不修；如需统一，需两仓同时换绝对尾锚 |
| K3 | test-plan 头部 canonical 路径不存在 | 笔误（写成 change-id 命名） | 不影响执行；Gate 2 受审字节 | 后续修订 test-plan 时改正 |
| K4 | CP 固定 `pass 1` | CP 按令牌过滤，计数写死 | 新增同令牌用例会误报失败 | 加用例时同步更新 CP 与 test-plan |
| K5 | `execution-control-isolation.test.mjs` 失败 | 本机未设 `AIFI45_ISOLATION_PROFILE` / `AIFI45_ISOLATION_AGENT`，测试按设计 `assert.fail`（不接受空跑） | suite-gate 本次 verdict=block；与本 change 无关（未触及该文件） | 在具备真实受限身份的环境（CI Linux）复跑；不为其加例外 |
| K6 | TC-CSS-004 的「已提交 rules.json」 | Gate 3 前无提交授权 | 本次以工作区文件验证 | 交付提交后补跑并记录 |
| K7 | `canonical/.canon-index.yaml` 为空、`traceability` 计数为 0 | 框架现状（归档 change 同样如此） | 无 | 不修 |

## 十、结论

本 change 的 5 个 TC 全部有执行证据，2 个 CP 通过，`rules.json` 改动范围经结构化比较限定在 `git[sub=show].shapes`；跨仓 6 个真实消费方测试通过。全量 crctl 套件 101 文件 / 2243 用例，唯一失败为环境前置缺失的隔离证明（K5），与本 change 无关。未提交、未推送。

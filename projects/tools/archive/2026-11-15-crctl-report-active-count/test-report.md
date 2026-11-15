# 测试报告 — 2026-11-15-crctl-report-active-count

> 模式：lightweight（单隐式切片）
> 报告时间：2026-11-15
> 选定 run：`validation/runs/99d50b37-e758-4e38-82d5-51de30f79240`

## 一、结论

- 证据 run `8636e44c…`：**6 个 CP 全部 PASS**（`agent-verification-report.md`）。
- 整文件回归（CP-RPT-005）：`pass 305 / fail 0`（原有 301 + 新增 4）。
- 真实工作区（CP-RPT-006）：`active 0 / total 76 / hist_sum 76`，与独立重算的不同编号数一致。
- 人工项 TC-RPT-007（`cr-dashboard` 口径文字）已由用户确认，`agent confirm --channel dialog` 记入同一 run（subject `08aeb856f87888ec62ebd08ff3f2edbe4c6cd90f0d2f84ac330807a6d9e7b25f`）。
- 口径修复前同一命令在知识库主 checkout 输出 `active 76 / total 152`（缺陷复现数据见 `proposal.yaml#why.problem`）。

## 二、TC 覆盖（planned vs actual）

| TC | 覆盖方式 | CP | 结果 |
|----|----------|----|------|
| TC-RPT-001 | `--test-name-pattern TCRPT001` | CP-RPT-001 | PASS（`active 0 / total 3 / archived 3 / 直方图 {archived:2, withdrawn:1}`） |
| TC-RPT-002 | `--test-name-pattern TCRPT002` | CP-RPT-002 | PASS（`active 1 / total 5 / archived 2`，含无 `archived-at` 的 `CR-RAW`） |
| TC-RPT-003 | `--test-name-pattern TCRPT003` | CP-RPT-003 | PASS（history 覆盖 frontmatter） |
| TC-RPT-004 | `--test-name-pattern TCRPT004` | CP-RPT-004 | PASS（配置侧 6 例 + 账本侧 5 例，全部退出 1 且错误码符合预期） |
| TC-RPT-005 | 整文件 `crctl.test.mjs` | CP-RPT-005 | PASS（305/305） |
| TC-RPT-006 | 真实工作区 + 独立重算 | CP-RPT-006 | PASS（`active 0 / total 76`） |
| TC-RPT-007 | 人工阅读技能文本 | 无 CP | 已确认（见第一节 subject） |

计划 7 条，已执行 7 条；`ci check-failures` 报 TC 当前执行覆盖 7/7（100%）。

## 三、覆盖率状态

证据计划声明 `coverage: {"applicability": "not_applicable", "reason": "Node 栈，仓库覆盖率检查只支持 pytest-cov"}`。
`stdd ci check-failures` 报 (j)「已声明无覆盖义务」，即**无覆盖率保证**，不是测得 0%。

## 四、切片验证

lightweight 单隐式切片：RED（4 条新用例全红）→ GREEN（5 条不可判夹具 + 去重规则）→ 整文件回归 305/305。
`.stdd.yaml#phases.build.slices_completed["1"]` 记录 `tc_coverage 7/7`、`new_tests 4`。

## 五、冻结输入（LF SHA-256）

| 输入 | SHA-256 |
|------|---------|
| `skills/shared/crctl/scripts/crctl.mjs` | `8f48044085757748c46bae03f27295289943169e3afd0f6fd992522f4e9bbbe4` |
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | `56c23c1f8ff08fae9ef84fc0abccfdb99134c7dfe1974034b0522219a139038b` |
| `skills/cr/cr-dashboard/SKILL.md` | `06e4ee39a2cbe4839701848b41e1dfb4da39998a75702a09cf1fc3bac2b37bde` |
| `dir-graph.yaml` | `a3bc77efe433086b1256318faaf52417b57592c73eccc8ec58964cdc6b74f392` |

## 六、C1 评审与处置

三路并行评审（code=strong `GB-JP/kimi-k3.1-pro`，test_config=balanced `GB-JP/deepseek-flash`，docs_skills=economy `Gobao/deepseek-flash`），均按 `stdd config models` 的配置档位派发；另有一次 balanced 预评审作为交叉核对。

**已修（本轮）**

| 来源 | 发现 | 处置 |
|------|------|------|
| code | `_history.yml` 同一 id 多条时 `archived` 按条目计数，可出现 `archived > total` 的自相矛盾报表 | `archived` 改为按 CR 去重计数（ADJ-004），并在 TC-RPT-001 夹具中加入重复条目 |
| code | `terminal` 元素带首尾空白时静默误判（配置错却当成“无终态”） | 校验改为要求无首尾空白；TC-RPT-004 增加该夹具 |
| code/test | `dir-graph` 解析失败分支无用例 | TC-RPT-004 增加“YAML 解析失败”夹具；解析失败消息带上字段名便于定位 |
| code | 新增 helper 里的 `dir-graph-missing` 分支不可达（`resolveToolsRoot` 已先失败） | 删除该死分支 |
| code | `created` 读进 Map 后从不使用 | 删除该字段 |
| docs | `cr-dashboard` 新注里直接列出 `archived`/`rejected`/`withdrawn`，等于复制终态枚举，违反 SC-006 | 改为只指向 `dir-graph.yaml#change-request-track.state_machine.terminal` |
| code | 重复 history `id` 时三方口径不一致（直方图取最后一条、`archived` 去重、`periodActivity` 按条目） | 改为硬失败 `HISTORY_DUPLICATE_ENTRY`（复用 `findHistoryEntry` 的错误码），`archived` 恢复按条目计数 |
| code | history 的 `String(final-status \|\| 'archived')` 把缺失／空串／`false` 伪装成 `archived`；`md.status` 不校验类型 | 两侧统一要求非空、无首尾空白的字符串；缺 `final-status` 用 `HISTORY_FINAL_STATUS_MISSING`、非法 `cr.md` status 用 `SCHEMA_INVALID` |
| code | `_history.yml` 结构异常（顶层非数组、条目非对象、`id` 非字符串）会抛 `TypeError` 或静默当空历史 | 统一 `LEDGER_PARSE_FAILED`，`extra` 带 `path`/`index`/`field` |
| code/test | `total` 的并集口径（含无 `archived-at` 的 history 条目）没有用例锁定 | TC-RPT-002 增加 `CR-RAW`，`total` 期望改为 5 |

**记录不修**

- history 条目 `id` 大小写／空白不归一：真实数据（知识库 76 条）无此形态，属数据录入问题；`crctl` 别处也不归一，单在 `report` 归一会造成两套口径（ADJ-005）。
- `total` 的并集口径（含没有 `archived-at` 的 history 条目）是本次唯一的输出扩展，已用 `CR-RAW` 锁定（ADJ-004）。
- 目录 `cr.md` 缺 `status` 时仍被静默跳过；直方图用普通对象承载动态键（`__proto__` 之类的状态名会丢计数）。都是基线行为，本次不改（ADJ-011）。
- `publishedArchiveStatus`（AIFI-65 R3）在本主 checkout 未同步时的兜底口径：`report` 未纳入，属独立议题（ADJ-006）。
- `statusHistogram` 键无枚举校验（非法状态会原样成键）：超出本 change 声明范围（ADJ-007）。

## 七、C2 全量质量检查

- `quality.test`：`node --test skills/shared/crctl/scripts/test/crctl.test.mjs` → 305/305（CP-RPT-005 内执行）。
- 相关套件另跑：`contract-scan`、`caller-contract`、`lint-prompts` 合计 102/102 通过（技能文本与 crctl 无漂移）。
- 覆盖率：见第三节（豁免理由）。

## 八、C3 Diff 审查

三处改动，逐文件看过：`crctl.mjs`（新增 helper + `cmdReport` 重构）、`crctl.test.mjs`（新增 4 条用例 + 1 个夹具函数）、`cr-dashboard/SKILL.md`（口径文字）。
无调试残留、无注释掉的旧逻辑、无与 spec 冲突的额外改动；未触碰工作树里既有的 `CUSTOM.md`、`merge-effects.mjs`、golden、`.crctl/`。

## 九、C4 失败模式检查（14 项）

| 项 | 结论 | 依据 |
|----|------|------|
| (a) hallucination | 通过 | `check_files_exist`（run 内 (a) 项） |
| (b) scope_creep | 通过 | C3 只看三文件；评审点出的越界项均未实施（ADJ-005/006/007） |
| (c) cascading_errors | 通过 | 去重与终态只在一处（`cmdReport`）计算，无跨步骤放大 |
| (d) context_loss | 通过 | `check_tcid_unique`：7 个 TC 唯一 |
| (e) tool_misuse | 通过 | CP 全部经 `node --test` 与独立 python 断言，未使用未定义参数 |
| (f) runtime_deviation | 通过 | `check_shall_keyword`：THEN 全部含 SHALL，且实际输出与断言一致 |
| (g) pipeline_break | 通过 | `check_and_count` / `check_slice_completion`：1 个切片有验证证据 |
| (h) content_quality | 通过 | 报告与文档均为完整段落，无占位符 |
| (i) instruction_decay | 通过 | 长程模式全程按 build.md 步骤执行；受审文档未改（ADJ-001 仅记录） |
| (j) coverage_vacuum | 通过 | 6/7 TC 有 run 证据，第 7 条为人工项；覆盖率按计划豁免 |
| (k) contract_gap | 跳过（工具判定） | 少于 2 个 capability |
| (l) anchor_missing | 通过（工具判定） | 非 critical，无需锚定 |
| (m) agent_cp_failure | 检查后无命中 | 6 个 CP 的断言都含可区分观测值（计数/字段值），并由 `p==1`、`p>=305`、`active==0` 等具体值把关 |
| (n) cross_system_mismatch | 检查后无命中 | `crctl report` 的结论与独立 python 重算、与 `crctl status` 的 history 优先判定一致 |

## 十、C5 经验库

本轮未产生新的可复用失败模式；已有 `EXP-2026-0002`（contract_gap）、`EXP-2026-0003`（agent_cp_failure）不涉及本次改动，未新增条目。

## 十一、C6 设计调整

`pending-adjustments.md` 记录 7 条（ADJ-001…ADJ-007），汇总见 `design-adjustments.md`。均为不改变接口/行为语义的小偏离或表述问题，未触发 Gate 2 重签。

## 十一之二、修订轮（文档评审后）

`docs` 评审（economy）指出并经核实的问题，本轮一次同步：`design.md` 补 Context／Architecture／Risks 三节、订正 D1（与 `resolveTerminalForQuery`「方向一致但不等价」）、D2（`extra` 实带字段）、D3（删除不存在的 `active[]` 表述）、D5（`spec-dashboard` 仍持旧口径）；`canonical/specs/code/crctl-report.yaml` 的 SC-002 改为「`active` 为计数 + 直方图唯一非终态键为 `developing`」、SC-004 的 WHEN 改为整文件运行；删除 `stdd new` 留下的两份 TODO 规格脚手架（此前与真实规格并存、且计入 `input_fingerprint`）；`test-plan.md` 状态列改为计划时快照并补两处耦合/快照说明；`cr-dashboard/SKILL.md` 的表下注解改为「`statusHistogram` 含终态键、渲染在途表时只取非终态键」，归档语改为「按条目数、与 `active` 分开统计、不宣称互斥」。

受审文档变动导致 Gate 2 过期，已重新提交用户确认（`--reapprove`）。证据 run 因 `SKILL.md` 变更重跑。

## 十二、已知限制（供 Gate 3 审阅）

1. `tc-evidence.json` 与 `agent-verification-report.md` 只记录每个 CP 的 `PASS`/`exit_code`，**不保存 stdout 里的观测值**；观测值在本次会话输出与本报告第二、五节中留档。这是 runner 现有行为，不是本次改动引入。
2. `design.md` D3 末句提到不存在的 `active[]` 数组（ADJ-001），实现与 proposal 约束一致（输出字段名不增不删）。
3. `skills/spec/spec-dashboard/SKILL.md` 仍按旧口径描述（按 frontmatter 分组、表内含终态行），本次未改，登记为 ADJ-009。
4. `archived` 与 `statusHistogram.archived` 天然不等（前者含 withdrawn 等终态的归档数），TC-RPT-001 把这一既有语义写成了期望（ADJ-004 说明）。

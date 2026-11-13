# C5 经验库记录与更新

- change：`2026-11-12-fork-ci-test-evidence-trust`
- 执行日期：2026-11-13
- 经验库：`<DATA_ROOT>/experiences/`（记录仓，属本 change 记账范围）
- 依据：`validation/c4-failure-modes/README.md` 的逐条实证判定 + `test-plan.md:19-21` 的明文引用
- 结论：既有 5 条按实证更新计数，新增 1 条（EXP-2026-0006）；**未推进任何生命周期状态**，6 条均仍为 `discovered`。

---

## 1. 写入入口（按 AGENTS.md 的合法入口规则）

| 操作 | 入口 | 说明 |
|---|---|---|
| 新增 EXP-2026-0006 | `stdd experience add`（业务仓根执行） | Skill/CLI 为该操作规定了专用入口，故用 CLI，不手写文件。CLI 同时写条目与 `.experience-index.yaml` |
| 既有 5 条的命中/采纳计数 | `Edit` 精准改字段 | 已核实 CLI **无**命中计数入口：`add` 只创建新条目（`experience.py:362-411`，`occurrences` 硬编码 1）；`verify`/`deposit` 是生命周期推进（`:753-754`、`:1027-1034`），不是计数更新，用它们会伪造验证状态。Skill C5 要求「更新既有经验的命中次数」但未指定专用入口，按 AGENTS.md 允许精准 Edit |

**索引一致性已核实**：`.experience-index.yaml` 只存 `by_category/by_language/by_lifecycle/by_severity` 的 ID 列表与 `last_id/total`（`experience.py:269-278`），**不含** `occurrences/adoption_count/last_seen`。本次只改这三类字段，未改分类/语言/生命周期/严重程度，故索引无需同步、也不会失配。实测 `index_ids_match_files = True`，`last_id=6`、`total=6`。

**未做的事**：未调用 `verify`/`deposit`/`retire`/`share`/`curate`；未改 `confidence`、`provenance`、`provenance_weight`、`community_votes_*`、`first_seen`、`source_change`、`root_cause`、`pattern`、`fix_template`、`tags`；对 stdd 资源仓写入次数 **0**（只读 `experience.py` 核实契约）。

---

## 2. 逐条变更与依据

计数口径区分两件事，不混用：

- **occurrences（命中）**：本轮实证**再次观察到该失败模式**。只认真实命中，预防性覆盖不算。
- **adoption_count（采纳）**：该经验的 `fix_template` 被本 change **实际采用**，且 `test-plan.md` 明文引用。

| 经验 | 字段变更 | 依据（C4 实证） | 未改的字段与原因 |
|---|---|---|---|
| EXP-2026-0001 | `adoption_count` 0 → 1 | `test-plan.md:21`「测试数据用随机/唯一键，不用常量 id」明文引用；C4 实测新增行为测试随机 uuid 命中 27 + 3 处，649 迁移未引入任何唯一键或 id | `occurrences` 保持 1、`last_seen` 保持 2026-11-10：C4 判定 **PASS（无适用面）**，模式未复现。ADJ-006 的基线失败经探针证实为 Windows 时钟粒度，**不是**常量 id 撞键，不得记为本经验命中 |
| EXP-2026-0002 | `occurrences` 1 → 2；`last_seen` 2026-11-10 → 2026-11-13 | C4 **命中 1**：`execution_control_reservation.go:88-96` 非锁定 `SELECT EXISTS`，全函数 grep `pg_advisory\|Lock\|FOR UPDATE` 零命中，属 check-then-act；代码注释已主动申报该限制 | `adoption_count` 保持 0：`test-plan.md:19-21` 未引用本经验，其 fix_template（先取序列化锁）本轮**未采用**，按 ADJ-017/U3 裁定留待后续 |
| EXP-2026-0003 | `adoption_count` 0 → 1 | `test-plan.md:19`「多行/流式输入逐行解析、解析失败硬失败」明文引用；C4 实测 `ci-evidence.mjs:110-119` 在取 `matches[0]` 前有 0 匹配与多匹配两道守卫，`:51-52` 解析失败抛错 | `occurrences` 保持 1、`last_seen` 保持 2026-11-11：C4 判定 **PASS**，原始根因 sites（`instance.mjs`/`provision.mjs` 的端口校验）本 change 未触碰，模式未复现 |
| EXP-2026-0004 | `occurrences` 1 → 2；`last_seen` 2026-11-11 → 2026-11-13；`adoption_count` 0 → 1 | 命中：C4 **命中 2**，`provision.mjs createDisposableDatabase` 两段 `finally` 只 `end()` 关连接、不 drop 已建 role/database，部分失败时 `HANDLE_ENV` 从未写入 → `down` 走 no-op → 遗留资源。采纳：`test-plan.md:20` 明文引用，`run-selection.mjs` 三处 `finally`（`:112`/`:155`/`:189`）+ `ci.yml` 清理步骤 `if: always()` 已落地 | 命中归属为**既有文件继承缺口**（`provision.mjs` 不在本 change 的 49 个文件内），影响已被 job service container / podman 实例销毁收敛；本轮未修改该文件 |
| EXP-2026-0005 | `adoption_count` 0 → 1 | `test-plan.md:19`「每个拒绝条件单独退化测试」明文引用；C4 实读两份 214 行文件确认 11 条条件表 + `len(conditions) != 11` 硬断言 + 双阳性对照 + `slices.Equal` 单列退化断言，强于经验最低口径 | `occurrences` 保持 1、`last_seen` 保持 2026-11-11：C4 判定 **PASS**，缺口已在 S7 修好，模式未复现。`grep -c 't\.Run('` = 2 的计数陷阱已排除（循环驱动） |
| **EXP-2026-0006（新增）** | 由 CLI 创建，`occurrences` 1、`adoption_count` 0、`first_seen`/`last_seen` 2026-11-13、`lifecycle_state` discovered、`provenance` ai-inferred | 来源 **ADJ-042**（`validation/c3-diff/README.md` §4.1）：`run-selection.mjs:28-46` parseArgs 的 if/else-if 链无最终 else，拼错 `--evidence-dir` 时选项保持 null，`:176-177` 落盘分支整段跳过，**证据不写而结论仍为 PASS** | 严重程度登记为 `medium`（模式一旦接线即静默丢失证据义务），本实例为 `minor`（ADJ-042）：`ci.yml` 未调用 run-selection，也无 `--evidence-dir` 调用点，CI 不受影响。该区分已写入条目 body |

---

## 3. 新条目内容（EXP-2026-0006）

| 字段 | 值 |
|---|---|
| category | `contract_gap` |
| language / project_type | `javascript` / `javascript` |
| severity | `medium` |
| pattern | 手写 argv 解析用 if/else-if 链且缺最后一个 else：拼错的选项名被静默丢弃，程序照常输出 PASS |
| root_cause | `run-selection.mjs:28-46` 的 parseArgs 逐个匹配已知选项后没有兜底 else；`--evidence-dir` 拼错时该选项保持 null，`:176-177` 的落盘分支被整段跳过，证据不写而结论仍为 PASS |
| detection_trigger | 手写 argv 解析是 if/else-if 链且无最终 else；或某个可选开关控制证据/产物落盘，缺省时静默跳过而不报错 |
| fix_template | 解析链末尾补 else 抛 `unknown argument`（与 `ci-provision.mjs:132`、`ci-evidence.mjs:162` 同口径）；补一个拼错选项名的用例，断言非零退出且不产出结论行 |
| tags | cli, argument-parsing, fail-open, evidence-loss, review-found |
| source_change | `2026-11-12-fork-ci-test-evidence-trust` |

**同仓对照实证**（说明这是口径不一致而非平台限制）：`ci-provision.mjs:132` 与 `ci-evidence.mjs:162` 均对未知参数抛 `unknown argument`；`run-selection.mjs` 的 `--admin-url` 也已被显式拒绝，唯独选项名拼错无兜底。既有断言 `run-selection.test.mjs:131-138` 只覆盖「缺值」与「后随另一个选项」，未覆盖「选项名拼错」。

---

## 4. 核验结果（实测）

```
files 6
EXP-2026-0001 occ 1 adopt 1 last 2026-11-10 state discovered sev high   lang go         cat contract_gap
EXP-2026-0002 occ 2 adopt 0 last 2026-11-13 state discovered sev high   lang go         cat runtime_deviation
EXP-2026-0003 occ 1 adopt 1 last 2026-11-11 state discovered sev medium lang javascript cat contract_gap
EXP-2026-0004 occ 2 adopt 1 last 2026-11-13 state discovered sev medium lang javascript cat runtime_deviation
EXP-2026-0005 occ 1 adopt 1 last 2026-11-11 state discovered sev low    lang go         cat contract_gap
EXP-2026-0006 occ 1 adopt 0 last 2026-11-13 state discovered sev medium lang javascript cat contract_gap
index last_id 6 total 6
index_ids_match_files True
```

6 个条目均可 YAML 解析，索引 ID 集合与磁盘文件集合完全一致，无重复、无孤儿。

**未推进生命周期**：`verify` 要求实证验证、`deposit` 要求 `occurrences>=3` 且 `confidence>=0.8`。本轮 2 项命中均为「已申报限制」与「继承缺口」，**未修复**，不构成验证证据，故 6 条全部保持 `discovered`，不伪造状态。
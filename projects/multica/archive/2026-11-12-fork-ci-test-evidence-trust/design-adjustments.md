# 设计调整说明

- change：`2026-11-12-fork-ci-test-evidence-trust`
- 项目：multica（业务仓 `C:\Users\GOBAO\Downloads\AI\multica`，HEAD=`903a46c5ae9fa6c3ee644fa4740d189d739dcc91`）
- 汇总时间：2026-11-13T13:50:04+08:00（**Gate 3 后续轮更新：2026-11-13T17:32:54+08:00**）
- 阶段：Phase 3 BUILD / Part C 步骤 C6（C7 编制报告时新增 ADJ-044；Gate 3 后续轮新增 ADJ-045 并更新 ADJ-025/030/031/042 的处置；**执行用户 Gate 3 裁定时新增 ADJ-046——approve 被 CLI 拒绝批准**；**用户裁定 B 路径后新增 ADJ-047——范围收窄 + 3 个场景移交后续 change + Gate 2 重签**；**执行人工确认时新增 ADJ-048——`confirm_manual` 抛 `KeyError: 'cp'`**，已同步本文件）
- 来源：Part B 与 C1–C3、C7、Gate 3 后续轮逐条登记的 `pending-adjustments.yaml`，共 **48 条**（ADJ-001…ADJ-048）

## 基线与口径声明

1. **本文件是汇总与修订需求，不是逐字台账。** 每条的 `original_design_ref / actual_change / reason / impact_scope / resolution` 原文逐字保存在同目录 `pending-adjustments.yaml`，本文件按条给出浓缩说明并标注**逐字来源行号**。两者不一致时以 YAML 原文为准。不复制原文是为避免两份真相源漂移。
2. **格式依据（见 ADJ-043）**：资源根 `stdd/.stdd/version.yaml` 为 `stdd_version: 3.0.7`，其 `.stdd/skills/build.md:317` 明写「生成 `design-adjustments.md`……不再生成或读取同名 `.yaml`」，`.stdd/skills/_shared/revision-rules.md:29`（自称 Gate 修订规则唯一来源）明写「调整记录统一为 `pending-adjustments.md` 与 `design-adjustments.md`。同名 `.yaml` 不读、不计入任何 Gate」。业务仓 `multica/.stdd` 只有 `binding.yaml`、无已安装 Skill，按 AGENTS.md 以资源根为权威，故本产物为 `.md`。用户级安装的 `stdd-build` SKILL.md 正文仍写 `.yaml`（frontmatter 却标 3.0.7），该冲突已登记为 ADJ-043，**既有 YAML 台账逐字保留、未迁移、未删除、未双写**，迁移与否待用户裁定。
3. **Gate 影响已核实**：`pending-adjustments.yaml` 与本文件均**不在** Gate 1（`input_manifest` **2 项**）或 Gate 2（**20 项**）内，故新增调整记录不使 Gate 1/2 过期，与 `revision-rules.md` §2「仅新增调整记录 → 仅重审 Gate 3」一致。Gate 1 confirmed `2026-11-13T09:46:15`、Gate 2 confirmed `2026-11-13T09:46:16`，均不 stale；**Gate 3 仍 pending，未推进**。（C7 更正：本项与 ADJ-043 初稿误记 Gate 2 为 19 项，实测 `.stdd.yaml` 的 `phases.spec.input_manifest` 为 **20** 项、`phases.understand.input_manifest` 为 **2** 项；结论不受影响。）
4. **记录不等于批准或执行。** `resolved: true` 只表示该条已按所述处置完成并留证；`resolved: false` 表示仍待裁定或前置未满足。任何未执行、跳过或外部依赖未满足的检查，本文件一律不报通过。
5. 版本自检（Skill Step 0）无法比对：`multica/.stdd` 与 `DATA_ROOT/projects/multica` 均无 `version.yaml`。按「落后时告警但不阻断」处理，告警内容即 ADJ-043。

## 统计

| 维度 | 数量 | 明细 |
|---|---|---|
| 总条数 | 48 | ADJ-001…ADJ-048 |
| 已处置 `resolved: true` | 26 | 001, 004, 008, 010, 011, 012, 013, 014, 015, 016, 017, 021, 022, 023, 025, 026, 027, 030, 031, 034, 035, 036, 039, 042, 045, **047** |
| 未决 `resolved: false` | 22 | 见下两行 |
| 未决 · major | **6** | **ADJ-005, ADJ-024, ADJ-038, ADJ-040, ADJ-046, ADJ-048** |
| 未决 · minor | 16 | 002, 003, 006, 007, 009, 018, 019, 020, 028, 029, 032, 033, 037, 041, 043, 044 |
| 已处置 · major | 8 | ADJ-014, ADJ-017, ADJ-025, ADJ-027, ADJ-034, ADJ-035, ADJ-036, **ADJ-047** |
| 已处置 · minor | 18 | 001, 004, 008, 010, 011, 012, 013, 015, 016, 021, 022, 023, 026, 030, 031, 039, 042, 045 |
| major 合计 | 14 | 未决 6 + 已处置 8 |
| 触发规格修订（revision） | 2 | R4（ADJ-014）、R5（ADJ-017），均已重签 Gate 2 |
| 触发 Gate 1+2 连锁重签 | 1 | ADJ-035（锚定 L3→L4，proposal 为 Gate 1 受审输入） |
| 属 stdd 资源仓待办（本会话写入 0） | 9 | ADJ-015, 032, 033, 037, 038, 040, 041, 044, **046**（另 ADJ-036 同类缺陷由用户自修） |
| 属 multica 台账欠债 | 1 | ADJ-018（CUSTOM.md 四数基线表） |
| 新增经验条目 | 1 | EXP-2026-0006（来源 ADJ-042） |

> 统计以 `pending-adjustments.yaml` 的 `severity` 与 `resolved` 字段实测为准（**2026-11-13 记录 ADJ-048 后重算**）：48 条 = 26 已处置（8 major + 18 minor）+ 22 未决（**6 major** + 16 minor）；id 唯一、YAML 可解析（`yaml.safe_load(...)['adjustments']` len **48**）。**口径更正**：本行此前写作「`yaml.safe_load` → list, len 46」不准确——该文件顶层是 `meta` + `adjustments` 映射，实测 `adjustments` 为 list；结论（条数与唯一性）不变。
>
> **Gate 3 后续轮的 7 处状态变更**：① ADJ-045 新增（清理事故波及依赖树），修复完成后置 `resolved: true`；② ADJ-025 推送 `e52b808` 完成 → 由未决 major 转已处置 major，未决 major 由 5 降为 4；③ ADJ-042 经用户裁定纳入本 change 并修完 → 已处置；④ ADJ-030 / ADJ-031 经用户「其他的项都采纳你的建议」采纳**明确不做** → 置 `resolved: true`，其 resolution 首句明写「处置＝决定不做（不是已修复）」，不得读成缺口已消除；⑤ **ADJ-046 新增（major，未决）——按用户裁定原文执行 `gate approve --gate 3` 被 CLI 拒绝批准，未决 major 由 4 回升为 5**，并据此**更正 ADJ-040 的影响范围**（不只是覆盖指标 0/22，而是硬阻断 Gate 3）；⑥ **ADJ-047 新增（major，已处置）——用户裁定「选B」后执行范围收窄：计划分母 22 → 19、3 个场景移交后续 change、Gate 2 于 18:33:41 以 `--reapprove` 重签**；⑦ **ADJ-048 新增（major，未决）——按用户核对原文执行 `agent confirm` 抛 `KeyError: 'cp'`（`evidence.py:762`），人工结论无法写入，Gate 3 仍被挡**。`resolved: true` 只表示本条处置完成，**不代表本 change 已收口**。
>
> **未决 22 条的归属**：6 条 major 中，ADJ-005 / ADJ-024 属外部前置，ADJ-038 / ADJ-040 / ADJ-046 / **ADJ-048** 属 stdd 侧；本会话一律不修（用户明示 stdd 项不在本次）。16 条 minor 中 ADJ-028 / ADJ-029 属「本轮不做、留待新开 change」，ADJ-018 属 multica 台账欠债，其余见 §A–§E 的可检索留痕。**ADJ-048 是当前唯一的即时阻塞项**：修好它（一行）即可继续 confirm → Gate 3。
>
> **（历史，原文保留）未决 21 条的归属**：该段为 ADJ-046 阶段的口径，已被上一段的 22 条口径取代；保留以对照。原文要点：5 条 major 分属外部前置与 stdd/tools 侧，16 条 minor 分属后续 change / 台账欠债；**ADJ-046 的 CLI 缺陷仍在，其对本 change 的阻塞已由 B 路径解除（ADJ-047）**。

## 调整汇总

| # | 调整类型 | 涉及文档 | 严重程度 | 调整阶段 | 影响 TC | 用户已知 | 处置 |
|---|---|---|---|---|---|---|---|
| ADJ-001 | 归属表条目扩充（规格明文允许） | design.md 决策 4 初始已知项清单 | minor | B / S4 | TC-TOR-001 | 否（Gate 3 知悉） | 已处置 |
| ADJ-002 | 接口新增可选参数（证据留存） | design.md 决策 4 / 决策 5 | minor | B / S4 | TC-TOR-001, TC-TOR-003 | 否 | 未决 |
| ADJ-003 | 规格未指定载体的落地选择 | design.md 决策 5 规则 2 | minor | B / S4 | TC-TOR-002, TC-CBE-005 | 否 | 未决 |
| ADJ-004 | 未验证事实核实（结论与假设相反） | design.md 未验证事实 #2 | minor | B / S4 | TC-TOR-001 | 否 | 已处置 |
| ADJ-005 | 跨仓契约缺口（tools show 白名单） | tools 仓 rules.json（范围外）+ design.md 决策 3 / S13 | **major** | B / S4 | TC-CBE-005, TC-TOR-002 | 是（用户采纳「不放宽白名单、不排除 6 项」） | 未决（移交后续 change：先裁定契约归属，见 §A/§D） |
| ADJ-006 | 平台缺陷定性 + S9 实现约束 | design.md 决策 9 / S9 | minor | B / S4+S8 | TC-WSD-002, TC-WSD-003, TC-CBE-005 | 否 | 未决 |
| ADJ-007 | 未定性失败（待真实 CI 定性） | design.md 决策 4 / 决策 5 规则 2 | minor | B / S4 | TC-TOR-001, TC-CBE-005 | 否 | 未决 |
| ADJ-008 | 实现细节修正（实测驱动，机制未变） | design.md 决策 1 | minor | B / S6 | TC-CBE-001 | 否 | 已处置 |
| ADJ-009 | 规格条款字面不可同时成立（边界澄清） | design.md 修订记录 R1 | minor | B / S6 | TC-CBE-001 | 是（R1 裁定） | 未决 |
| ADJ-010 | selection 拆分（不改 runner 的最小做法） | design.md 决策 2 + test-plan.md TC-CBE-002 命令 | minor | B / S7 | TC-CBE-002 | 否 | 已处置 |
| ADJ-011 | 测试口径修正（单独一个条件 ≠ 单独一列） | design.md 决策 2 | minor | B / S7 | TC-CBE-002 | 是（子测试名承载条件名） | 已处置 |
| ADJ-012 | 命名对齐 canonical（canonical-first） | design.md 决策 8 + Architecture 图 | minor | B / S8 | TC-WSD-001 | 否 | 已处置 |
| ADJ-013 | 挂钩位置与类型转换补记 | design.md 决策 7 | minor | B / S9 | TC-WSD-002, TC-WSD-004 | 否 | 已处置 |
| ADJ-014 | 锁定规格内部冲突 → 裁定修订 R4 | canonical SC-WSD-002/003 + spec.md + test-plan.md + design.md R4 | **major** | B / S9 | TC-WSD-002, TC-WSD-003 | 是（补迁移修缺口） | 已处置 |
| ADJ-015 | 工具缺陷（canon generate 忽略 --type spec） | stdd 仓（只读）+ 手工镜像 spec.md / test-plan.md | minor | B / S9 | 无（工具口径） | 否 | 已处置 |
| ADJ-016 | 覆盖对象扩充（迁移循环纳入 649） | design.md 决策 7 风险表 | minor | B / S9 | TC-WSD-002, TC-WSD-003 | 否 | 已处置 |
| ADJ-017 | 安全缺口 → 裁定修订 R5（只修半句） | canonical SC-WSD-005 / SC-TOR-001 + spec.md + test-plan.md + design.md R5/U3/决策 7/风险表 D2 | **major** | B / S10 | TC-WSD-005, TC-TOR-001 | 是（只修 reservation 半句） | 已处置 |
| ADJ-018 | 台账欠债（四数基线未补行） | multica CUSTOM.md 四数基线表 | minor | B / S10 | 无（台账） | 否 | 未决 |
| ADJ-019 | 长程约束 #3 偏离（new_tests=0） | stdd-build 长程约束 #3 / B3.4 第 3 项 | minor | B / S12 | TC-CCF-002 | 否（Gate 3 知悉） | 未决 |
| ADJ-020 | 既有 flake 上报（U4 范围不扩大） | design.md U4 | minor | B / S12 | TC-CCF-002, TC-CBE-005 | 是（U4 已上报） | 未决 |
| ADJ-021 | 上游行挂钩（CRLF 归一化） | multica AGENTS.md 工程纪律 + CUSTOM.md #330 | minor | B / S13 | TC-SEL-004 | 否 | 已处置 |
| ADJ-022 | CI 默认连接目标收紧（删 job 级 DATABASE_URL） | design.md:38 + R1 连带实现决定 | minor | B / S13 | TC-CBE-001, TC-SEL-004 | 否 | 已处置 |
| ADJ-023 | CI 步骤顺序与条件对齐锁定设计 | tasks.md 13.3 + design.md:40 | minor | B / S13 | TC-TOR-003, TC-CBE-001 | 否 | 已处置 |
| ADJ-024 | 前置缺失 → 隔离半句 UNCOVERED | canonical SC-TOR-004 + design U5 | **major** | B / S13 | TC-TOR-004 | 是（用户采纳「保持 UNCOVERED」） | 未决（规格接受如实标注；本轮不搭 WSL 环境，留待后续变更） |
| ADJ-025 | 跨仓前置未满足（pin 不在 origin） | canonical SC-CBE-003/005 + design U1 | **major** | B / S13 | TC-CBE-003, TC-CBE-005 | 是（用户授权推送 e52b808） | 已处置（pin 已上 origin；真实 CI 仍缺 multica 推送授权与 PAT） |
| ADJ-026 | 计划外回归守卫（不计入 TC 分子） | test-plan.md TC 清单（未改） | minor | B / S13 | TC-SEL-004, TC-TOR-004（守卫另计） | 否 | 已处置 |
| ADJ-027 | C1 评审修复（CRCTL_PATH 别名 → Fatal） | canonical SC-CBE-004/005 + validation/s3 README | **major** | C1 | TC-CBE-004, TC-CBE-005 | 否 | 已处置 |
| ADJ-028 | C1 评审已申报限制（非锁读 TOCTOU） | canonical SC-WSD-005 + 648:51-66 | minor | C1 | TC-WSD-005 | 部分（U3 裁定留待后续） | 未决 |
| ADJ-029 | 规格要求的既有语义保留（两处口径不对称） | canonical SC-SEL-002 vs SC-TOR-002 | minor | C1 | TC-SEL-002, TC-TOR-002 | 否 | 未决 |
| ADJ-030 | 不可达路径不加防御守卫 | 无（拒绝多余错误处理） | minor | C1 | TC-SEL-001, TC-SEL-003 | 是（用户采纳「不做」） | 明确不做（决定不修，非缺口消除） |
| ADJ-031 | 扫描器模式盲区（加固议题） | canonical SC-CBE-004 | minor | C1 | TC-CBE-004 | 是（用户采纳「不扩围」） | 明确不做（G1 由运行时对账承重，非扫描器） |
| ADJ-032 | 工具缺陷（canon 索引指向不存在的聚合文件） | canonical/.canon-index.yaml（Gate 2 输入） | minor | C1 | 无（索引惰性） | 否 | 未决 |
| ADJ-033 | 工具渲染缺陷（CP description 61 字符截断） | canonical/specs/agent/*.yaml（Gate 2 输入） | minor | C1 | 无（action/assertions 完整） | 否 | 未决 |
| ADJ-034 | C1 评审修复（pin ref 接线无断言） | canonical SC-CBE-003 | **major** | C1 | TC-CBE-003 | 否 | 已处置 |
| ADJ-035 | 锚定不足 → 裁定补真实 L4 + 双 Gate 重签 | canonical proposal anchoring + proposal.md | **major** | C1 | 全部 22（锚定前置） | 是（两条裁定原文） | 已处置 |
| ADJ-036 | 外部工具缺陷（verify KeyError，用户自修） | stdd 仓 agent.py:206（本会话写入 0） | **major** | C2 | 全部 22 | 是（用户自行修改） | 已处置 |
| ADJ-037 | 同类残留点（本轮执行路径不可达） | stdd 仓 evidence.py:806 | minor | C2 | 无（本计划 0 条 pytest） | 否 | 未决 |
| ADJ-038 | 外部流程缺陷（Gate 2 不执行锚定检查） | stdd 仓 ci.py:1186-1222 + skills/spec.md:126-134 | **major** | C2 | 全部 22（critical 前置） | 否 | 未决 |
| ADJ-039 | 本机环境失败 → 授权修复 esbuild | 无（依赖声明未改） | minor | C2 | TC-CCF-002 | 是（授权修二进制后重跑） | 已处置 |
| ADJ-040 | 覆盖判定结构缺口（18≠22 → 0/22） | stdd 仓 evidence.py:1033-1034 / :1071 + test-plan 证据计划 | **major** | C2 | 全部 22 | 否 | 未决 |
| ADJ-041 | 外部检查口径缺陷（范围蔓延 WARN 不可采信） | stdd 仓 ci.py:874-906 | minor | C2 | 无（真实范围已手工核对） | 否 | 未决 |
| ADJ-042 | C3 新发现（parseArgs fail-open → 静默丢证据） | canonical SC-SEL-001/003 | minor | C3 | TC-SEL-001, TC-SEL-003 | 是（用户裁定「纳入本 change」） | 已处置（本轮修：RED→GREEN + 三组回归 + CUSTOM.md #333） |
| ADJ-043 | 技能层口径冲突（调整记录格式 .md vs .yaml） | 用户级 stdd-build SKILL.md vs 资源根 build.md:317 / revision-rules.md:29 | minor | C6 | 无（记录格式） | 否 | 未决 |
| ADJ-044 | 外部检查分类口径不一致（「14 类」无权威逐项定义） | stdd 仓 build.md:308 / revision-rules.md:41 / lite.yaml:105 / ci-integration spec.md:48,54,62 / ci.py | minor | C7 | 无（不改断言；影响报告措辞） | 否 | 未决 |
| ADJ-045 | 清理事故波及依赖树（工作树恢复未覆盖 node_modules / pnpm store） | 无（依赖声明未改；design 决策 1 + U4/U5） | minor | Gate 3 后续轮 | TC-SEL-002, TC-CBE-002, TC-WSD-001…005, TC-CCF-002 | 是（U5 授权 npm 安装 pg；实际改用项目钉住的 pnpm `--frozen-lockfile` 重建，只写被 ignore 路径，见详细说明） | 已处置（install exit 0、pg 8.20.0 可解析、pnpm CLI 恢复 10.28.2；**残留义务已履行**：18 条命令 CP 以新 run `dfb7aad8…` 整轮重跑，typecheck/lint 以 `--force` 真跑，views vitest 重跑后如实记 **1 失败 / exit 1，不报通过**） |
| ADJ-046 | **按用户裁定执行 `gate approve --gate 3` 被 CLI 拒绝批准**（ADJ-040 的同一判据经 `gate.py:815-822` 硬阻断批准，不只是覆盖指标） | `test-plan.md` §六 冻结计划 22 条 check 全为 `required`；`gate.py:810-823`；`evidence.py:1033-1034 / 1055-1075 / 697-699 / 740-770` | **major** | Gate 3 后续轮 | 全部 22 个 TC 的覆盖判定 + **Gate 3 批准本身** | 是（用户已给出确认原文；**拒绝执行后如实上报，未绕过**；随后裁定 B 路径） | **未决（CLI 缺陷仍在；对本 change 的阻塞已由 ADJ-047 解除）** |
| ADJ-047 | **执行范围收窄（B 路径）：3 个外部前置场景移交后续 change，证据计划分母 22 → 19，Gate 2 重签** | `test-plan.md` §六 冻结计划 + 用户裁定「选B，将需要移交到后续change的项记录在案，供以后能找回修订。」 | **major** | Gate 3 后续轮 | TC-CBE-005, TC-TOR-004, TC-CCF-003（移交）；其余 19 条留在分母内 | 是（用户裁定 B 路径并授权记录） | **已处置（2026-11-13；`resolved: true` 仅指本条处置完成，不代表 Gate 3 已通过）** |
| ADJ-048 | **执行 `agent confirm` 抛 `KeyError: 'cp'`（`evidence.py:762`），人工结论无法写入** | `evidence.py:20` `_CHECK_FIELDS` 含 `cp`；`:761-764` 用 `item[key]` 强取；manual 计划项无 `cp` | **major** | Gate 3 后续轮 | TC-TOR-005 的人工确认 + Gate 3 批准 | 是（按用户核对原文执行后如实上报） | **未决（当前唯一即时阻塞项；修 stdd 一行即可继续）** |

## 调整详细说明

> 每条末尾的「逐字来源」指向 `pending-adjustments.yaml` 的条目起始行。原文四字段与 resolution 未在本文件复制。

### ADJ-001 — 归属表由 3 条增至 4 条

- **原始设计**：design.md 决策 4「初始已知项」只列 `daemon.TestChannelIsolation` 与 `governance.TestChannelMigrationAfterDown / AfterReapply`；test-plan.md TC-TOR-001 明文「其余条目 SHALL 由整包基线证据加入」。
- **调整内容**：`test-ownership.json` 的 entries 加入第 4 条 `governance.TestChannelMigrationAfterUp`（owner=independent，entry=`run-selection.mjs --only channel-migration-up`）。
- **调整原因**：整包基线实测该测试同样状态敏感（`execution_control_migration_test.go:513` 断言每张 `cr_execution_*` 表起始为空，14 子测试中 12 个失败于「starts with N rows」）；独立入口下 PASS pass=19 fail=0 skip=0。属 TC-TOR-001 明文允许的基线证据加入，非扩围。
- **影响范围**：CI 排除正则多一个名字；S5 的 ci-evidence 规则 3 随之多一项；design.md 决策 4 的初始清单文字需更新。
- **影响 TC**：TC-TOR-001。**调整阶段**：B / S4。**用户已知**：否，Gate 3 知悉。
- **处置**：已处置。独立入口 PASS、真实 check exit 0、skip-regex 含该名；无需裁定。
- **逐字来源**：`pending-adjustments.yaml:8`

### ADJ-002 — 新增 `--evidence-dir`，保留 `go test -json` 原始流

- **原始设计**：design.md 决策 4 / 决策 5 未规定保留原始流；`run-selection.mjs` 原实现只打印一行结论后丢弃流。
- **调整内容**：新增可选参数 `--evidence-dir <dir>`；`runSelection` 改为返回 `{result, ndjson}`（migrate 失败分支 ndjson 为空串）；新增 `selection-evidence.mjs` 的 `writeSelectionEvidence` 落盘 `<name>.ndjson` 与 `<name>.json`。原有 11 项参数/决策测试与输出行格式未改。
- **调整原因**：归属表要求「每项排除都带证据」，而失败原因、skip 理由、耗时只存在于 `-json` 流中；不保留流则 S4 的证据义务无法履行。
- **影响范围**：fork 独有脚本接口新增一个可选参数（不改变既有调用行为）；新增 1 源文件 + 1 测试文件；S5/S13 可复用同一落盘形状。**关联 ADJ-042**：该可选开关正是 fail-open 后果被放大的原因。
- **影响 TC**：TC-TOR-001, TC-TOR-003。**调整阶段**：B / S4。**用户已知**：否。
- **处置**：未决（`exp_id: EXP-2026-0003`）。接口新增本身已实现并验证，登记为偏离待 Gate 3 知悉。
- **逐字来源**：`pending-adjustments.yaml:18`

### ADJ-003 — allowed-skips 名单落在 test-ownership.json

- **原始设计**：design.md 决策 5 规则 2「事件流里所有 skip 必须在允许名单（含 reason）内」，未规定名单存放位置与条目来源。
- **调整内容**：名单落在 `test-ownership.json` 的 `allowed-skips` 字段（package/test/reason），与 entries 同表同校验；初始 4 条 = 3 条基线观测 + 1 条源码推导（`daemon.TestChannelIsolationChild`，reason 明确标注 source-derived, not baseline-observed）。
- **调整原因**：与排除表同放一处可共用「真实 func + 必填 reason + 不重复」校验，避免第二份无人核对的名单；该测试所在文件为 `//go:build linux`，Windows 基线未编译，无法从基线观测。
- **影响范围**：S5 的 ci-evidence 规则 2 消费该字段；名单是 CI-linux 真实 skip 集合的**下界而非终态**，须由 TC-CBE-005 最终确认。
- **影响 TC**：TC-TOR-002, TC-CBE-005。**调整阶段**：B / S4。**用户已知**：否。
- **处置**：未决（下界性质须真实 CI 收口）。
- **逐字来源**：`pending-adjustments.yaml:28`

### ADJ-004 — 未验证事实 #2 核实：TestMTick003 未挂住

- **原始设计**：design.md 未验证事实 #2 假设 `TestMTick003` 挂住，并给出判定树（环境→修、真实缺陷→修或上报、仅慢→写设计调整）。
- **调整内容**：在一次性 podman 数据库上实跑整包 `./internal/governance`，观测 `pass TestMTick003 elapsed=0.06`。
- **调整原因**：事实与假设相反——0.06s 通过，无挂住无超时，判定树四个分支均不触发。
- **影响范围**：不需改超时、不需设计调整；design.md 未验证事实 #2 可关闭。证据 `validation/s4-baseline-ownership/mtick003-elapsed.txt`。
- **影响 TC**：TC-TOR-001。**调整阶段**：B / S4。**用户已知**：否。
- **处置**：已处置，未做任何超时或测试改动。
- **逐字来源**：`pending-adjustments.yaml:38`

### ADJ-005 — 跨仓契约缺口：tools 的 `git show` 白名单不含测试证据形状（major，未决）

- **原始设计**：design.md 决策 3（单一 tools pin）与 S13 计划把 `AIFI45_TOOLS_ROOT / CRCTL_MJS` 交给 backend-tests；AIFI-56 R1 要求 daemon 快照读取三类 `git show` 形状。
- **调整内容**：登记时未修改 tools 白名单、未排除这 6 个测试、未决定 S13 是否设置 `MULTICA_CONTROLLED_SHELL_RULES`。
- **调整原因**：整包基线暴露 6 项失败（`TestProposedSnapshotReadShapes`、`TestM26B2TestFactsPayload`、`TestM26B2TestFactsPreserveFailures`、`TestM26B4ScanEmitsIndependentTestEvent`、`TestM26B4ScanTestOnlyAndReviewOnly`、`TestM26B4CollectorKeepsBothReviewStages`），首个报 `FORBIDDEN_SUBCOMMAND: git show ... test-report.md`。pin 住的 tools `skills/shared/controlled-shell/rules.json` 的 show 白名单只授予 `review-annotations/*.yml`、`_backlog.yml`、`_history.yml`、`cr.md`，未授予 `test-report.md` / `trace.tests*` / `--name-only --format=`。本机因该变量指向真实 rules.json 而暴露；`crevents_test.go` 在变量缺失时回落内联 fixture（已含这些形状），故 CI 目前被掩盖而通过。
- **影响范围**：若 S13 把该变量指向 pin 的 rules.json，这 6 项会在 CI-linux 真实失败。**修法在 tools 仓，不在 multica**；本 change 不静默改 tools 白名单、也不排除这 6 项。涉及 U1（tools `e52b808` 尚未推送）与 S13 接线范围。
- **影响 TC**：TC-CBE-005, TC-TOR-002。**调整阶段**：B / S4。**用户已知**：否，**待裁定**。
- **处置**：未决。需用户裁定：放宽 tools show 形状（另开 tools 仓变更）／S13 不注入该变量（则 CI 继续被 fixture 掩盖）／其他。
- **逐字来源**：`pending-adjustments.yaml:48`

### ADJ-006 — Windows 时钟粒度致唯一键冲突；presenter 受害集合在运行间移动

- **原始设计**：design.md 决策 9（删除实现）与 S9 计划生成随机唯一键；EXP-2026-0001（常量 id 与唯一键冲突）。
- **调整内容**：未修改两个 handler 上游测试、未排除它们；为 S9 增加一条实现约束。
- **调整原因**：基线中 `TestPresenterMemberRemovalLinkage` 与 `TestSearchIndexChangesScopeToWorkspace` 因 `user_email_key / workspace_slug_key` 冲突失败。探针实测本机 `time.Now().UnixNano()` 在 200000 次连续取值中 **199996 次与前一次完全相同**，故属本机平台缺陷而非常量 id 缺陷，Linux 上预期通过，不得进入 CI 排除。S8 补证：受害测试不固定（handler 整包 4506 pass / 5 fail / 47 skip，presenter 家族失败变为另两个子测试）；用 `-run ^TestPresenter` 在一次性库上单独连跑两次（S8 新增测试不在该 run 内），两次均 11 pass / 3 fail / 0 skip、报文同型、受害子测试在两次之间移动 → 判定为非确定性既有 flake，与 S8 无因果关系。
- **影响范围**：S9 生成随机唯一键**不得沿用 UnixNano**，须用 crypto 随机或等价单调来源；两个上游测试本 change 不改。本机 handler 整包回归**不能以「全绿」或失败计数当信号**，S9/S10 须按测试名逐条比对基线。CI-linux 是否复现仍未验证，须 TC-CBE-005 确认，不提前报绿。
- **影响 TC**：TC-WSD-002, TC-WSD-003, TC-CBE-005。**调整阶段**：B / S4+S8。**用户已知**：否。
- **处置**：未决（`exp_id: EXP-2026-0001`；该经验本轮为**采纳**而非命中，见 C5 记录）。
- **逐字来源**：`pending-adjustments.yaml:58`

### ADJ-007 — 一个未定性的 daemon 失败，既不排除也不归因

- **原始设计**：design.md 决策 4「只有带证据的才可加入」与决策 5 规则 2（名单外 skip 即失败）。
- **调整内容**：未排除、未定性、未修改该测试。
- **调整原因**：`daemon.TestHandleRuntimeGone_DistinctDeletionsWithinCoalesceWindowBothRecover` 基线失败于 `runtime_gone_test.go:539`「register called 1 times, want 2」，无平台相关错误信息。可能是真实缺陷（成功路径未清 `reregisterNextAttempt`），也可能是 fake register 异步完成与第二次调用之间的竞态；现有证据不足以判定。
- **影响范围**：须由真实 CI-linux 运行（TC-CBE-005）定性；若为真实缺陷则属上游行为问题，需另行裁定是否纳入范围。与 ADJ-003 共同说明 allowed-skips 只是下界。
- **影响 TC**：TC-TOR-001, TC-CBE-005。**调整阶段**：B / S4。**用户已知**：否。
- **处置**：未决。
- **逐字来源**：`pending-adjustments.yaml:68`

### ADJ-008 — pg 解析器必须用 CJS（NODE_PATH 只被 CJS 读取）

- **原始设计**：design.md 决策 1「pg 用 `npm install --prefix $RUNNER_TEMP/aifi45-node pg@<根 package.json 声明的版本>` 取得并经 NODE_PATH 解析」；未规定用哪种模块解析器。
- **调整内容**：`ci-provision.mjs` 的 `pgConnect()` 用 `createRequire(import.meta.url)("pg")` 而非 `await import("pg")`，并新增第 25 项静态契约用例钉住该写法（读源码、先滤掉 `//` 注释行，断言存在前者且不存在后者）。
- **调整原因**：实测在无 node_modules、祖先链上也没有 pg 的探针目录中，设置 NODE_PATH 后 `await import("pg")` 仍 `ERR_MODULE_NOT_FOUND`，而 `createRequire` 返回 OK。ESM 写法会在开发机通过、CI 的 `--prefix` 隔离安装下必然失败，属会静默漂移的差异。**设计的依赖取得机制未变**，只换解析器。
- **影响范围**：S13 的 CI 步骤必须同时提供 `npm install --prefix` 与 NODE_PATH，且不得改用 ESM import。本机实测 pg 实装 8.23.1（根声明 `^8.20.0`，14 packages / 15s）；ubuntu-latest 的耗时与稳定性仍未测（design 未验证事实 #6）。
- **影响 TC**：TC-CBE-001。**调整阶段**：B / S6。**用户已知**：否。
- **处置**：已处置。变异验证把该行改回 `await import("pg")` 后对应用例变红（mutation-guards.txt 第 8 条 DETECTED）。
- **逐字来源**：`pending-adjustments.yaml:78`

### ADJ-009 — `::add-mask::` 必然把口令送到原始 stdout

- **原始设计**：design.md 修订记录 R1 修订后条款「任何日志、stdout/stderr 与 handle 文件 SHALL NOT 含明文口令；GITHUB_ENV 中的 DATABASE_URL 承载 job 级一次性角色口令，写入前 SHALL 先对该口令发出 `::add-mask::`」。
- **调整内容**：实现按 R1 先发 `::add-mask::<角色口令>` 再写三行 GITHUB_ENV；用例断言的是「除这一条 mask 命令外，没有任何日志行携带角色口令或管理员口令」，而不是「stdout 从头到尾不含口令」。
- **调整原因**：`::add-mask::` 是 GitHub Actions 规定的遮蔽协议，runner 只遮蔽它已经见过的值，因此该命令本身必然把口令送到原始 stdout，与「stdout 不含明文口令」在字面上不可同时成立。R1 已把边界收敛到「mask 生效后的 runner 日志 + handle 文件」，本条把这一不可回避的事实显式登记，避免最终报告把「stdout 全程无口令」当作已验证结论。
- **影响范围**：TC-CBE-001 的安全边界断言口径；最终验收报告须一并呈报。口令仍是 `randomBytes(18)` 生成、job 级、随服务容器销毁，不复用于任何非一次性资源；handle 与本 change 写出的其他文件均不含口令。若要求 stdout 全程无口令，须改用 runner 外部遮蔽机制（超出本 change 范围，需裁定）。
- **影响 TC**：TC-CBE-001。**调整阶段**：B / S6。**用户已知**：是（R1 裁定「收敛规格到日志与 handle」）。
- **处置**：未决（口径已按裁定收敛，登记目的是防止报告夸大）。
- **逐字来源**：`pending-adjustments.yaml:88`

### ADJ-010 — identity 组拆成两条 selection（门禁有两份副本）

- **原始设计**：design.md 决策 2「identity 组由 run-selection 在一次性库里真跑」；test-plan.md TC-CBE-002 的执行命令只写 `--only ci-gate-identity`。
- **调整内容**：登记两条 selection：`ci-gate-identity`（`./internal/governance`）与 `ci-gate-identity-server`（`./cmd/server`），各跑一次；未改 run-selection 的选择形状。
- **调整原因**：runner 契约是「一个 selection = 一个包 = 一个一次性库」（package 单值，`--only` 必须恰好命中一条）。门禁有两份副本，TC-CBE-002 要求两份都被逐条件钉住，单条 selection 只能覆盖一个包；加第二条是不改 runner 的最小做法。
- **影响范围**：TC-CBE-002 的执行命令与证据文件成对出现；S13 若引用 identity 组须同时跑两条。两份测试文件除 package 子句外逐字节相同，由脚本生成并核对，避免手工漂移。
- **影响 TC**：TC-CBE-002。**调整阶段**：B / S7。**用户已知**：否。
- **处置**：已处置。两条均真跑：各 pass=16 fail=0 skip=0，runner exit 0，实例均 released remaining=0。
- **逐字来源**：`pending-adjustments.yaml:98`

### ADJ-011 — 「单独退化」的口径是单独一个条件，不是单独一列

- **原始设计**：design.md 决策 2 要求对 11 个拒绝条件「逐条构造失败并断言被拒，且每条的『单独退化』都变红（不是只测组合）」。
- **调整内容**：条件表字段由 `column string` 改为 `columns []string`；`role-name` 一条同时把 `Role` 与 `SessionRole` 移到同一错值，其余十条仍单列；断言改为「实际变化的列集合 == 声明的列集合」（`slices.Sort`/`slices.Equal`）。**门禁实现未改**。
- **调整原因**：第一轮变异探针实测 `role-name` **NOT DETECTED**（runner exit=0）——门禁的 `sessionRole != role` 会把「只改角色名」一并兜住，因此删掉角色名检查也照样红，该条件当时未被单独钉住，属**真实覆盖缺口而非探针缺陷**。两列同移后角色名检查成为唯一被违反的条件。
- **影响范围**：口径明确为「单独一个条件」；修后 **11/11 条件在两个包里均 DETECTED**，两份门禁逐字节恢复（sha256 核对）。
- **影响 TC**：TC-CBE-002。**调整阶段**：B / S7。**用户已知**：是（裁定「改规格：子测试名承载条件名」）。
- **处置**：已处置（`exp_id: EXP-2026-0005`）。未放宽任何拒绝条件、未改门禁错误串。
- **逐字来源**：`pending-adjustments.yaml:108`

### ADJ-012 — selection 名以 canonical 为准（canonical-first）

- **原始设计**：design.md 决策 8 与 Architecture 图写 `handler-workspace-deletion`。
- **调整内容**：改用 canonical 证据计划锁定的 `handler-wsd-manifest`；未改 canonical、未改证据计划、未改 run-selection。
- **调整原因**：`canonical/specs/agent/workspace-delete-execution-tables.yaml` 的 CP-WSD-001 把 action 与 stdout 断言钉在 `--only handler-wsd-manifest` / `PASS handler-wsd-manifest`（Gate 2 锁定），与 design.md 冲突。同文件还为 S9/S10 钉住 `handler-wsd-delete / handler-wsd-retain / handler-wsd-atomic / handler-wsd-no-recreate`。
- **影响范围**：design.md 决策 8 与 Architecture 图需更正为 canonical 的五个名字；test-plan.md TC-WSD-001 已与 canonical 一致，无需改。
- **影响 TC**：TC-WSD-001。**调整阶段**：B / S8。**用户已知**：否。
- **处置**：已处置。RED exit=1（19 张未分类 + 逐表分类不符）→ GREEN exit=0 且 stdout 含 `PASS handler-wsd-manifest`（pass=2 fail=0 skip=0），满足 CP-WSD-001 两条断言。
- **逐字来源**：`pending-adjustments.yaml:118`

### ADJ-013 — sweep 步骤的插入位置与 uuid 类型转换

- **原始设计**：design.md 决策 7「在 `DeleteWorkspace` 的 `deleteSteps` 里追加一步」未指定位置；canonical SC-WSD-004 given 要求「追加步骤之后的某一步失败」可构造。
- **调整内容**：新步骤 `delete execution control routing` 插在 `delete chat pins` 之后、`lock task usage rollup` 之前（`server/internal/handler/workspace.go:1216-1225`），调用 `governance.DeleteWorkspaceExecutionRows(ctx, tx, uuidToString(requester.WorkspaceID))`；governance 签名与决策 7 一致，两条参数化 `DELETE … WHERE workspace_id = $1::uuid`。
- **调整原因**：按字面追加到末尾（`delete workspace` 之后）其后无任何步骤，SC-WSD-004 无法构造。放在 rollup 锁之前使既有 advisory 4246 竞争成为**真实的生产失败注入器**（`TestDeleteWorkspace_FailsFastWhenRollupLockHeld` 已证明返回 503），无需新增测试专用钩子、无需改上游失败语义。notice/dispatch_root 无外键无触发器，与 rollup/task 删除无顺序依赖。`requester.WorkspaceID` 实为 `pgtype.UUID`（首次 go vet 报类型不符），按 handler 既有惯例 `uuidToString`（handler.go:649）转换，不改 governance 签名。
- **影响范围**：上游 `workspace.go` 净增 11 行 0 删除；无迁移、无 sqlc、无触发器改动。design.md 决策 7 需补记位置与转换。
- **影响 TC**：TC-WSD-002, TC-WSD-004。**调整阶段**：B / S9。**用户已知**：否。
- **处置**：已处置。CP-WSD-002 exit 0 `PASS handler-wsd-delete`（1/0/0）；CP-WSD-004 exit 0 `PASS handler-wsd-atomic`（1/0/0，含 503 回滚后 A/B 逐字节不变 + workspace A 仍在 + 末尾「无竞争必须真删」正向对照）。变异 m4（sweep 自开事务并立即 Commit）使 atomic 变红，证明「在既有事务内」是被断言的保证。
- **逐字来源**：`pending-adjustments.yaml:128`

### ADJ-014 — 锁定规格内部冲突：TRUNCATE 守卫缺失 vs 禁止新增迁移（major，已裁定 R4）

- **原始设计**：canonical SC-WSD-003 then「对 retain 表的普通 DELETE 与 TRUNCATE SHALL 仍被触发器拒绝」+ CP-WSD-003；同文件 SC-WSD-002 and「SHALL 不新增迁移、不新增触发器例外、不改 sqlc 查询」。design.md 决策 7 只写普通 DELETE，逐表映射列名为「DELETE 触发器」，只为 activation 标注「含 no_truncate」。
- **调整内容**：登记时未改 canonical、未放宽任何断言、未新增迁移、未改触发器，按锁定规格原样实现 11 张 retain 表各一个 `truncate_<table>` 子测试，实测 2 张失败，停下上报。裁定后按 R4 新增 `649_cr_execution_truncate_guard.{up,down}.sql`。
- **调整原因**：迁移 643（`cr_execution_binding_issue`）与 644（`cr_execution_consumption`）各只有 `BEFORE UPDATE OR DELETE … FOR EACH ROW`，**没有 BEFORE TRUNCATE 语句级守卫**；645/648 都有。TRUNCATE 不触发行级触发器，故这两张审计证据表可被整表清空。648 自己的头注释（第 11–12 行、第 406 行「every retained table needs this statement guard」）明文声明该不变量——schema 自述规则被两张早于 648 的表违反。grep 全部迁移确认无后续迁移补过。**既有缺陷，与本 change 无因果关系**。canonical 比 design 多要求 TRUNCATE 半句，按 canonical-first 保留断言、如实报红；而满足它必须新增迁移，与 SC-WSD-002 冲突 → **锁定规格内部冲突，须用户裁定，不得由 Agent 选边**。
- **影响范围**：登记时 CP-WSD-003 不满足（exit 1、`FAIL handler-wsd-retain pass=20 fail=3 skip=0`），TC-WSD-003 不得报通过、Slice 9 不得标 done；另两半与 11 张表的普通 DELETE 拒绝全部通过。安全影响：具备数据库写权限者可 TRUNCATE 清空 binding 签发与消费回执两类审计证据而不被拒绝。
- **影响 TC**：TC-WSD-002, TC-WSD-003。**调整阶段**：B / S9。**用户已知**：是（裁定「补迁移修缺口（修订 SC-WSD-002）」）。
- **处置**：已处置。R4 修订 canonical SC-WSD-002 + spec.md + test-plan.md 同步镜像，Gate 2 以裁定原文 `--reapprove` 重签（旧回执 superseded）。649 up 只加两个 `BEFORE TRUNCATE FOR EACH STATEMENT` 触发器并复用 643/644 各自的 `append_only` 函数，down 只 DROP 这两个；**未开任何删除／更新例外**，643/644/645/648 一行未改。实测 CP-WSD-003 exit 0 `PASS handler-wsd-retain pass=23 fail=0 skip=0`；变异 3/3 DETECTED（m1/m2 各只打中对应 truncate 子测试，m3 把 down 改成对错误表 DROP → roundtrip 红于真实 apply，SQLSTATE 42704，证明 down 确被执行）；两文件按 sha256 逐字节还原。
- **逐字来源**：`pending-adjustments.yaml:138`

### ADJ-015 — 工具缺陷：`canon generate --type spec` 被忽略

- **原始设计**：AGENTS.md「Skill 指定 CLI 或版本化脚本入口的操作，必须使用该入口」；Canonical-First 要求 canonical 与 human view 一致。
- **调整内容**：执行 `stdd canon generate --type spec <change>` 后 CLI 只重新生成 `proposal.md`（逐字节未变），`specs/*/spec.md` 未更新；改为按 R1/R2 既有做法用 Edit 手工镜像到 spec.md 与 test-plan.md。**未使用 `--all`**。
- **调整原因**：读 CLI 源码 `canon.py:330 → _generate_one(688-712)`：单变更模式忽略 `gen_type`，永远只渲染 proposal.md；spec human view 只在 `--all` 分支（284-322）生成，而 `--all` 会遍历项目内全部 canonical 并以当前时间重渲染每个 change 的 proposal.md，**会改写他人未提交的记录**。`canon verify` 仍报 2/2（只核对 proposal 的 DC-HASH/DC-BODY），故不能把 verify 通过当作 spec human view 已同步的证据。
- **影响范围**：本 change 的 spec.md／test-plan.md 由手工镜像保持一致；**C6/C7 不得把 canon verify 2/2 当作双轨全量一致的证据**。属工具限制，不改规格内容，未触碰他人记录。
- **影响 TC**：无（工具口径）。**调整阶段**：B / S9。**用户已知**：否。
- **处置**：已处置。generate 前后对变更目录 195 个文件取 sha256 快照逐字节相同；手工镜像后逐字核对三处一致（canonical yaml:29、spec.md:22、test-plan.md:265）；verify 2/2 与 Gate 2 重签都在镜像之后执行。
- **逐字来源**：`pending-adjustments.yaml:148`

### ADJ-016 — 把 649 纳入迁移往返测试的循环

- **原始设计**：design.md 决策 7 与风险表的改动面不含 `execution_migration_roundtrip_test.go`；R4 只授权新增 649 与配套 down。
- **调整内容**：该 fork 独有生命周期测试（AIFI-45，CUSTOM.md #204）的 `executionMigrationFiles` 追加 `649_cr_execution_truncate_guard`，`executionMigrationObjects` 中两张表各追加对应 `_no_truncate` 触发器名，头注释补一句；numstat 净 7 插入 3 删除。另在 `selections.json` 追加 `governance-migration-roundtrip`。
- **调整原因**：该测试按文件顺序 apply 643–647 的 down 再 up。649 的触发器挂在 643/644 的表上：down 阶段 DROP TABLE 连带删掉它们，而 re-apply 只跑 643–647 的 up，不会重建 649 守卫 → **测试自身仍绿，但该库在同一整包运行的后续部分永久缺这两个守卫（静默降级）**。纳入循环既消除降级，也让 649.down 第一次被真实执行。断言强度未改，只扩大覆盖对象。
- **影响范围**：governance 包多一个被修改文件（AIFIRST 标记 + CUSTOM.md #326）；多一条 selection 与一个一次性库。不影响 648 的 down/up 探针对象集合。
- **影响 TC**：TC-WSD-002, TC-WSD-003。**调整阶段**：B / S9。**用户已知**：否。
- **处置**：已处置。`PASS governance-migration-roundtrip pass=1 fail=0 skip=0`（真实 apply 649 down/up，表／触发器／函数／索引存在性逐条断言）；同批 channel-migration-up 19/0/0、down 22/0/0、reapply 15/0/0；node 目录全量 154/0/0 未变。
- **逐字来源**：`pending-adjustments.yaml:158`

### ADJ-017 — 禁新建探针红灯 → 裁定 R5：只修 reservation 半句（major）

- **原始设计**：canonical SC-WSD-005 then「SHALL 被拒绝；若当前代码允许，该测试红灯即为发现，SHALL 停止并向用户上报，由用户裁定是否在本 change 内修复（design U3），不得静默放宽断言或改触发器」。
- **调整内容**：登记时未改任何生产代码／断言／触发器／canonical，按锁定规格原样实现探针（4 子测试 + 父测试）并如实报红。裁定后：探针拆成 `TestWorkspaceDeletionRefusesNewReservation` 与 `TestWorkspaceDeletionRefusesNewCommand` 两个独立函数；selections 改为两条（共 32 条）；`execution_control_reservation.go` 新增哨兵 `ErrReservationWorkspaceGone` 与一次独立 workspace 存在性检查（13 插入 0 删除，纯追加）；`execution_contract_selection_test.go` 的 `insertSelectionWithMode` 补一行真实 workspace（10 插入 0 删除，事务内、随探针回滚、ON CONFLICT DO NOTHING），因该夹具的 `selectionWorkspace` 常量在库里从来没有对应行；`test-ownership.json` entries 追加第 5 条 `owner=known-finding` 承载 command 半句；`test-ownership.test.mjs` 新增 2 项用例并追加第 5 个 skip-regex 名字。**`test-ownership.mjs` 与 `ci-evidence.mjs` 一行未改**。
- **调整原因**：D2 保留 contract_selection 行，而两条创建路径都不检查 workspace 是否仍存在：`CreateReservationTx` 全函数不查 workspace 表，唯一相关语句是对保留下来的 selection 行做过滤（teardown 后依然命中）；`ApplyControlCommandTx` 全文件 workspace 零引用。探针先用生产入口 `TransitionControlCommandTx` 结算 A/B 各自 lineage 的 open 槽（append-only，不用 DELETE 绕守卫），真实删除 A（204），核对 workspace 行消失且 A 的 selection 行逐字节保留，再分别对 A 发起两类创建；B 上同构造请求作为正向对照必须成功。两对照都通过 → A 与 B 唯一差别就是 workspace 是否存在。
- **影响范围**：登记时 CP-WSD-005 不满足（exit 1、`FAIL handler-wsd-no-recreate pass=2 fail=3 skip=0`），TC-WSD-005 不得报通过、Slice 10 不得标 done。安全影响：workspace 删除后仍持有该 selection 标识的调用方可为其新建 reservation 与 command。裁定后 **reservation 半句缺口已闭合，command 半句缺口仍存在**，按裁定不在本 change 修复，登记为可找回的已知发现并保持红灯；TC-WSD-005 覆盖只算 reservation 半句。`CreateReservationTx` 目前**无生产调用方**（仅测试消费），故该修复不改变任何在跑生产路径行为；上游若接线须知道多了一条前置，并按 `errors.Is(ErrReservationWorkspaceGone)` 分支。
- **影响 TC**：TC-WSD-005, TC-TOR-001。**调整阶段**：B / S10。**用户已知**：是（裁定原文「只修reservation半句，command做好记录，待以后可以找回并修订」）。
- **处置**：已处置。先修订再动代码（与 R4 同顺序）：design.md 新增 R5 并更新未验证事实 #3、U3、决策 7、风险表 D2；canonical SC-WSD-005 置信度 low→medium、then 改两半分别处置、and 三项；SC-TOR-001 追加 `owner=known-finding`；**CP-WSD-005 的 action 与两条断言一字未改**；spec.md/test-plan.md 手工镜像；Gate 2 以裁定原文 `--reapprove`（回执 2026-11-12T23:54:09）。实测 `PASS handler-wsd-no-recreate pass=3 fail=0 skip=0 exit 0`；`FAIL handler-wsd-no-recreate-command pass=1 fail=2 skip=0 exit 1` 与声明预期逐字相符。变异 DETECTED（把 `if !workspaceExists` 中和为 `&& false` → 只有 reservation 子测试红，正向对照仍绿），按原字节还原并核对 sha256。拒绝断言额外要求 `errors.Is`，防止「因别的原因被拒」空洞变绿。整包回归**逐名对账**（UUID 规范化）：handler FAIL 新增 4 名 = 2 个声明内 command 名 + 2 个从 PASS 移来的 presenter 受害者（ADJ-006，范围外），FAIL 移除 0，SKIP 逐名不变；governance FAIL 新增 0／移除 0。node 全量 156/0/0；归属表用例 18/18/0；go vet exit 0。已知发现三处找回路径：归属表第 5 条、本汇总、归档基线 SC-WSD-005。9 个一次性实例全部 released remaining=0，容器清单前后 diff 为空。CUSTOM.md #327。未提交、未推送。
- **逐字来源**：`pending-adjustments.yaml:168`

### ADJ-018 — CUSTOM.md 四数基线表欠一行（台账欠债）

- **原始设计**：multica CUSTOM.md 第 11–17 行《核对命令》与四数基线表（文件／命中行／AIFIRST／packages/），口径为 git grep 已跟踪的 `server/`+`packages/` 下五类文件、按匹配行数计；末行 2026-11-10（#312）记 596/1659/736/314，并声明「四个数每次合并后只能升不能降」。
- **调整内容**：S1–S10 只在 M31 明细表登记（#317–#327），未重算或追加四数基线行。S10 登记时按《核对命令》实测当前工作树为 **611 文件 / 1678 命中行 / 755 AIFIRST 行**。
- **调整原因**：三点使本切片无法如实补出一行——①差值跨 2026-11-10 之后全部落码（含已提交的 AIFI-45 批次与本 change 在途改动），不能归因本切片；②git grep 只计已跟踪文件（C1 更正：口径内未计入的新增文件实为 **8 个 = 6 个 .go + 2 个 .sql**，另 19 个新增在口径外；新增 .mjs 全在 `scripts/`，故口径内新增 .mjs 为 0，原表述漏计 2 个 .sql 且误列 .mjs），提交后四数还会再变；③第四数 `packages/` 的测量口径未在《核对命令》中给出，不臆造测量方式。
- **影响范围**：不影响任何规格、代码或测试结论。**风险在合并窗口**：基线表停在 2026-11-10，若合并时直接引用旧四数做「只能升不能降」核对会得出错误结论。已在 CUSTOM.md #327 的合并注意里写明实测值与三点限制。
- **影响 TC**：无（台账）。**调整阶段**：B / S10。**用户已知**：否。
- **处置**：未决。需在合并窗口按当时工作树重算四数并补行，且先明确第四数的测量口径。
- **逐字来源**：`pending-adjustments.yaml:178`

### ADJ-019 — S12 新增测试数为 0，长程约束 #3 未满足

- **原始设计**：stdd-build 长程强制约束 #3「每个切片必须有新增测试 — 新增测试数必须 > 0」与 B3.4 第 3 项；TC-CCF-002 验证方式为命令型 `pnpm --filter @multica/views typecheck`，证据计划 kind=command、applicability=required。
- **调整内容**：S12 未新增任何测试函数，`new_tests` 如实记 **0**。改动只有两处：`packages/core/package.json` 增 1 行 exports（+1/-0），`packages/views/auth/use-logout.test.ts` 导入改写（7 插入/5 删除）。该文件原有 2 条测试标题与全部 expect 断言一字未改，改前改后均 2/2 通过。
- **调整原因**：TC-CCF-002 的断言对象是 tsc 的退出码与错误码计数，不是某个测试函数；SC-CCF-002 三条 then 已分别由命令输出、vitest 输出与 git diff 满足。回归守卫已由 `tsc --noEmit` 本身承担（任何 views 文件再写相对 `../../core` 导入都会立刻让 typecheck 红，本切片 RED 的 60 条 TS6059 正是这样产生的），另造「禁止相对 core 导入」的测试与它重复。**为凑足 >0 而新增冗余测试，会把长程约束的形式置于证据实质之上，故不造。**
- **影响范围**：约束 #3 与 B3.4 第 3 项在 S12 未满足，如实声明为偏离，**不报「B3.4 三项全过」**。约束 #5 的降级条件是「连续 3 切片无新增测试」：S11 新增 15、S13 有新增，故不触发降级。TC 覆盖仍 1/1（由命令证据覆盖）。断言 teeth 由四项替代证据提供：①RED 60×TS6059 → GREEN exit 0 且 0 条任何错误码；②git diff 中 0 条 `expect(` 改动、两条 `it()` 标题不变；③HEAD 版本另存临时文件独立跑亦 2/2（临时文件已删除并核实不存在）；④views 全量 A/B 逐名对账（ADJ-020）。
- **影响 TC**：TC-CCF-002。**调整阶段**：B / S12。**用户已知**：否，Gate 3 呈报请知悉。
- **处置**：未决（偏离已如实声明，不改任何接口或行为语义）。
- **逐字来源**：`pending-adjustments.yaml:188`

### ADJ-020 — views 全量 vitest 的既有 Windows 负载 flake（U4 上报，不扩围）

- **原始设计**：canonical SC-CCF-002 and「若修好 typecheck 后暴露其他前端失败，SHALL 先报告再裁定范围（design U4）」；tasks.md 12.4。
- **调整内容**：未改任何 views 生产代码／测试断言，未调 testTimeout／retry／并行度，未新增任何 skip 或排除。只执行三组测量并按 U4 上报。
- **调整原因**：三组实测（`validation/s12-views-typecheck/full/`，对账脚本 `reconcile.mjs` 可重跑 exit 0）——①HEAD（两个 S12 文件均还原、sha256sum -c 均 OK）views 全量 **6 失败/6366 通过（6372）**，4 失败文件/502 通过（506），202.91s；②带 S12 改动 **11 失败/6361 通过（6372）**，5 失败文件/501 通过（506），202.31s；③把②的 5 个失败文件单独成组重跑 **146/146 通过、0 失败文件、exit 0**，28.41s。两次全量总数完全相同（6372），S12 未增删任何测试。逐名对账：4 条两次都失败、2 条仅 HEAD 失败、7 条仅带改动失败——**受害者集合在两次运行之间移动**，故不是一组固定坏断言。失败以 `Error: Test timed out in 5000ms` 为主；两条 `TypeError: rejectCreate is not a function` 是同一次停顿的下游后果（`create-issue.test.tsx:1097`/`:1125` 的 `let rejectCreate!` 只在 mock executor 内赋值）。core 全量 vitest **2552/2552（180 文件）exit 0**，未受影响。
- **影响范围**：结论是 HEAD 上已存在的 Windows 506 文件并行负载 flake，**非 S12 引入、亦非 typecheck 修复新暴露**（还原两文件后仍红）。S12 自身义务已达成。**未确立的部分如实写明**：两次运行不足以测量 flake 率，不能声称频率未变；未在 ubuntu-latest 跑过 views 全量，不能声称 CI 不受影响。风险在 CI 接线后：若同一负载敏感在 ubuntu-latest 复现，S13 的 evidence 对账会如实判红，届时按新发现处理，**不得预先放宽门禁或加 retry 掩盖**。
- **影响 TC**：TC-CCF-002, TC-CBE-005。**调整阶段**：B / S12。**用户已知**：是（U4「先报告再裁定范围」已上报）。
- **处置**：未决（flake 本身留为未决发现，范围不扩大）。
- **逐字来源**：`pending-adjustments.yaml:198`

### ADJ-021 — ci-scope.test.mjs 的 CRLF 归一化行挂钩

- **原始设计**：multica AGENTS.md 工程纪律「读入后先将 `\r\n` 规范化为 `\n`；逐行解析使用 `split(/\r?\n/)`」；tasks.md 13.1 只要求补 scope 命中用例，未提及修改既有断言的读取方式。
- **调整内容**：`scripts/ci-scope.test.mjs` 第 80 行加 1 处上游行挂钩：读 `ci.yml` 后 `.replaceAll("\r\n","\n")`，带 `// AIFIRST:` 英文注释。既有 45 项断言一字未改、未弱化。另新增 `stepsOf / stepNamed / stepOrder / runBody` 四个辅助函数（103-132 行），`runBody` 只取步骤 `run:` 之后正文。
- **调整原因**：动手前先取基线——该文件改前就是 **44 pass / 1 fail**，失败点是第 208 行的跨行正则。根因是 `core.autocrlf=true` 使工作树为 CRLF 而 HEAD blob 为 LF，跨行断言按提交的 LF 字节写，故 Windows 本地假红（CI 的 Linux 检出不受影响）。不先修基线，13.1 的 RED 就无法把 2 个失败无歧义归因于新断言。`runBody` 的必要性由首轮 GREEN 的一次真实误报证明：`assert.doesNotMatch(test, /--skip-regex "\$\(/)` 命中了我自己写的注释（注释引用被禁形式作为说明），注释是文档不是可执行内容，故把「这一步执行什么」的断言一律指向 `run:` 正文，**而不是放宽断言**。
- **影响范围**：B4 小偏离，只让同一份断言在 Linux CI 与 Windows 本地给出同一结论。基线由 44/45 回到 45/45。合并注意已写入 CUSTOM.md #330：该归一化不要回退。顺带记录工具事实：ripgrep 的 `$` 不匹配 `\r` 之前，核对 CRLF 文件须用 `\r?$` 锚定。
- **影响 TC**：TC-SEL-004。**调整阶段**：B / S13。**用户已知**：否。
- **处置**：已处置。最终 49 tests / 49 pass / 0 fail / 0 skipped、exit 0；`node --check` exit 0；3 条变异各只打中预期的第 46 号测试，其余 48 项保持绿，ci.yml 逐字节还原且 sha256 一致。
- **逐字来源**：`pending-adjustments.yaml:208`

### ADJ-022 — 删除 backend-tests 的 job 级 DATABASE_URL 字面量

- **原始设计**：design.md:38 与 R1 连带实现决定只规定 down 从 job 级新增的 `AIFI45_CI_ADMIN_URL` 取回管理员口令；design.md:40 规定 up → migrate → Test 顺序；SC-CBE-001 then 规定 up 把 `DATABASE_URL` 与 nonce 写入环境文件。**三处均未规定要删除既有的 job 级 DATABASE_URL 字面量**。
- **调整内容**：删除 `DATABASE_URL: postgres://multica:multica@localhost:5432/multica?sslmode=disable` 一行，新增 `AIFI45_CI_ADMIN_URL` 承载同一 URL。最终 job env 键恰为 `AIFI45_CI_ADMIN_URL / AIFI45_TOOLS_ROOT / CRCTL_MJS / REDIS_TEST_URL / GOFLAGS`。`ci-provision.mjs` 与 `provision.mjs` 一行未改，GITHUB_ENV 仍按 SC-CBE-001 写出 DATABASE_URL。
- **调整原因**：保留 job 级 DATABASE_URL 会让任何漏配一次性库的步骤**静默连上共享超级用户库**，正是本 change 要消除的失败模式；删除后测试要连库只能由 up 写入的 nonce URL 提供，与用户约束「不连接 localhost:5432 旧库」同向。已核实 up 之前没有任何步骤需要数据库，且 provision.mjs 以管理员预建 pgcrypto/pg_trgm/vector 并把 public schema owner 改给 nonce 角色，故非超级用户的 nonce 角色能跑迁移。新增断言只针对 job 级 env 块，不影响 GITHUB_ENV 的运行时 DATABASE_URL。
- **影响范围**：B4 小偏离，不改脚本接口，只收紧 CI 默认连接目标。变异 M3 恢复该行即让第 46 号测试红。合并注意已写入 CUSTOM.md #330：**该行是删除而非改值**，rebase 时若上游恢复须重新删除，否则一次性库门禁可被绕过。真实 CI 行为未验证（TC-CBE-005）。
- **影响 TC**：TC-CBE-001, TC-SEL-004。**调整阶段**：B / S13。**用户已知**：否。
- **处置**：已处置。ci.yml YAML 解析通过、17 job；ci-scope 49/49 exit 0；M3 DETECTED 且逐字节还原。未提交、未推送。
- **逐字来源**：`pending-adjustments.yaml:218`

### ADJ-023 — CI 收尾顺序与 if 条件以锁定设计为准，而非草图

- **原始设计**：tasks.md 13.3 草图顺序为 up → migrate → test-go → ci-evidence(always) → down(always) → ownership check；design.md:40「down 放在 `if: always()` 的收尾步骤」；SC-TOR-003 未规定 ci-evidence 步骤的 if 条件。
- **调整内容**：实际收尾顺序为 **Reconcile the Go test evidence → Check the test ownership table → Drop the one-time test database**，三步都在 Test 之后、上游 Prune/Save cache 之前。前两步条件为 `if: !cancelled()` 且 `steps.go-test.outcome != 'skipped'`（不是草图的 `always()`），down 为 `if: always()` 且是最后一步。
- **调整原因**：两处都以锁定设计为准——①design.md:40 明文 down 是收尾步骤，把 ownership check 排在 down 之后会让一次性库多存活一步且与「收尾」矛盾；②ci-evidence 用 `always()` 时，被取消的 run 或根本没走到 Go 的 run 会因缺流而红，**把真正的失败原因盖掉**；`!cancelled()` 仍保证 Test 红时照样对账（SC-TOR-003 的可信性目标不打折），`outcome != skipped` 排除从未产生流的情形。**缺流本身仍硬失败**，已由本地等价第 6 项实测 ENOENT exit 1 证明，不是放宽。
- **影响范围**：B4 小偏离，只调整顺序与条件，不改脚本接口或断言。顺序由 `stepOrder` 断言锁死（10 个步骤名逐个按序），down 的 `always()` 由变异 M2 证明有 teeth。tasks.md 13.3 已按实际顺序改写并保留草图差异说明。真实 CI 上的条件求值未验证（TC-CBE-005）。
- **影响 TC**：TC-TOR-003, TC-CBE-001。**调整阶段**：B / S13。**用户已知**：否。
- **处置**：已处置。ci-scope 49/49 exit 0；本地等价 7 项逐项真实执行（含 down 无 handle 时 exit 0 空转、ci-evidence 缺流 exit 1）；M2 DETECTED 且逐字节还原。
- **逐字来源**：`pending-adjustments.yaml:228`

### ADJ-024 — WSL 隔离半句 UNCOVERED：四项前置全缺（major，未决）

- **原始设计**：canonical SC-TOR-004 then「每项通过数不少于 1、skip 为 0，并把命令、退出码、通过数记入验收报告；任一项不能执行（如 WSL profile 失效）时 SHALL 如实列为未覆盖，**不得以同 uid 对照代替**」，and「执行前 SHALL 先向用户说明并征得同意」；design U5 授权清单含「启动 WSL AIFI-ISO」。
- **调整内容**：TC-TOR-004 前半（两个状态敏感 selection）真实执行并通过；后半 `TestChannelIsolation` 经 WSL AIFI-ISO **未执行，如实记为 UNCOVERED**。只做只读探针：未安装 Go、未创建 995/994 身份、未建 profile 根、未克隆仓库、**未做任何同 uid 或 1500/1501 替代对照**。`test-ownership.json` 与 `ci-evidence.mjs` 一行未改。
- **调整原因**：探针实测（2026-11-13T02:19:23+0800，`wsl-isolation-probe.txt`）：AIFI-ISO 内 uid=0(root) 可用、内核 6.18.58.1-microsoft-standard-WSL2、Ubuntu 24.04.3 LTS，但 `command -v go` 空、`go version` 报 command not found，`/usr/local/go`、`/usr/lib/go*`、`/opt/go` 均不存在，maxdepth 4 搜 go 二进制无结果；`getent passwd 995` 与 `getent group 994` 均空，实际只有 aifi-svc 1500:1500 与 aifi-agent 1501:1501；`/var/lib/aifi45/daemon-iso` 不存在，`/var/lib/aifi45` 存在但空；`/root/multica` 与 `/home/*/multica` 均不存在。历史核准 profile 见 `archive/2026-10-27-trusted-verdict-channel/validation/iso-20261027T101534Z.meta.json`：wsl2-aifi45-v1、uid 995 / gid 994、root `/var/lib/aifi45/daemon-iso`、go1.26.10。**四项前置全缺**。`execution_control_isolation_test.go` 是 `//go:build linux` 且 `requireIsolationProfile` 在无核准 profile 时 `t.Fatalf`（不是 skip），故无法降级为跳过。补齐四项均超出 U5 授权清单（U5 只授权启动 WSL）。
- **影响范围**：**SC-TOR-004 的隔离性证明缺失，不得报通过**；TC-TOR-004 记为部分覆盖。本切片 `tc_coverage` 仍记 2/2 的依据是 SC-TOR-004 明文把「如实列为未覆盖」本身作为要求的处置，**不代表隔离性已验证**。CI 侧不受影响：该测试已由归属表第 1 条 owner=independent 排除，ci-evidence rule 3 核对排除生效，`TestChannelIsolationChild` 的 allowed-skip 已标注为源码推导而非基线观测。恢复覆盖所需：装 Go >= 1.26、按 wsl2-aifi45-v1 重建 uid 995 / gid 994 与 profile 根、准备仓库 checkout，再以 root + `AIFI45_ISOLATION_PROFILE` 等四个变量实跑留证——**须用户裁定是否授权**。WSL 状态无残留：探针把 AIFI-ISO 由 Stopped 拉起为 Running，收尾复测已因空闲超时自动回到 Stopped，与执行前清单一致。
- **影响 TC**：TC-TOR-004。**调整阶段**：B / S13。**用户已知**：是（U5 授权边界）。
- **处置**：未决，待授权。
- **逐字来源**：`pending-adjustments.yaml:238`

### ADJ-025 — tools pin 不在 origin（major，**已处置**；原标题「真实 CI 会在检出步失败」已被实测更正，见下方更正块）

- **原始设计**：canonical SC-CBE-003 then「ci.yml 中 SHALL 不再出现 tools 的字面 commit」；SC-CBE-005 given「需推送授权与 tools pin 可用，见 design U1」与 then「若走 U1 路径 β（tools 未推送），SHALL 如实记录 tools 相关测试未验证并使 pin 完整性检查失败，不得 skip 或报绿」；用户约束「tools HEAD=e52b8081f159，origin/main=f774ffb30770，本地领先 1 且有其他未提交改动。操作前重新核实，绝不夹带这些改动」。
- **调整内容**：ci.yml 两个消费者都改为从 `.github/aifirst-tools-pin` 读 ref（backend-tests 新增 Read the single tools pin → Checkout the pinned tools contract revision → Check the tools pin integrity 三步）。pin 内容仍为 `e52b8081f159d581bf62f82447c76f818fc52426`；本切片未推送 tools 仓、未改 pin、未触碰 tools 仓既有未提交改动。
- **调整原因**：操作前重新核实——tools HEAD 仍是 `e52b8081f159`，origin/main 仍是 `f774ffb30770`，本地领先 1，**该 commit 不在 origin 上**，故真实 CI 的检出步会因拉不到该 ref 而失败。**一处必须如实指出的时序差异**：SC-CBE-005 的预期措辞是「使 pin 完整性检查失败」，而实际失败发生在**更早的检出步**，完整性检查根本不会执行——两者都是诚实红灯、都不 skip 不报绿，但验收报告须按实际失败步骤记录，不能照抄规格措辞。推送 tools 那 1 个提交或把 pin 改回 origin 上已有的 commit，都须用户单独授权（U5 的推送授权指 multica 触发 CI，不自动覆盖 tools 仓推送，且 Git 提交须单独取得授权）。
- **影响范围**：**TC-CBE-005 前置未满足，真实 CI run 未执行，不得声称 CI 已修好**。本切片只做本地等价验证：`tools-pin read` 输出 `e52b808…`（exit 0）、`tools-pin check` 对本地 tools checkout 报 `complete (3 required files present)`（exit 0）——**这只证明本地 checkout 完整，不证明 origin 上有该 commit**。两条路径都未擅自执行。
- **影响 TC**：TC-CBE-003, TC-CBE-005。**调整阶段**：B / S13。**用户已知**：是（U1；推送须单独授权）。
- **处置**：~~未决。需裁定：推送 tools 那 1 个提交（须先逐项列出提交与范围并确认不夹带既有未提交改动）／把 pin 改回 origin 上已有且三个必需文件齐全的 commit。~~（**S13 当时原文，保留**）→ **已处置（Gate 3 后续轮真实执行了用户授权的动作）**。用户 2026-11-13 授权原文：「ADJ-025 授权执行推送 e52b808；同时把 pin 可达性检查前移到 checkout 之前」。
- **Gate 3 后续轮更正与实测（原文保留，只追加更正）**：
  - **推送已完成且只推了被授权的那一个提交**：`git push origin e52b8081f159d581bf62f82447c76f818fc52426:refs/heads/main` → `f774ffb..e52b808`，**exit 0**。推送后三处实测同值：`HEAD` = `origin/main` = `git ls-remote origin refs/heads/main` = `e52b8081f159d581bf62f82447c76f818fc52426`；`git merge-base --is-ancestor e52b808… origin/main` → **YES**；本地领先 **0**。remote 核实为 `https://github.com/OldBoy405/AI-First-tools.git`（与 pin 的 repository 逐字一致，**非代理地址**）。该仓 **6 处**既有未提交改动推送前后逐字一致，**未夹带**；**pin 文件未改**。证据 `validation/gate3-followup/tools-push-verified.txt`。
  - **更正「先在检出步失败」的措辞**：上文「调整原因」称实际失败发生在更早的检出步、完整性检查根本不会执行——**该判断被实测推翻**。两个 tools 消费者中，`Diagnose the tools read credential`（`tools-access.mjs`，GET `api.github.com/repos/OldBoy405/AI-First-tools/commits/<pin>`，404/403 → `no-access-or-pin-not-found` 且 exit 1）都排在 `Checkout the pinned tools contract revision` **之前**：transitions-contract-check 第 **3** 步 vs 第 **5** 步、backend-tests 第 **10** 步 vs 第 **12** 步。故 pin 不可达时**先失败的是诊断步且报错点名 pin**，不是检出步。证据 `validation/gate3-followup/pin-reachability-order.txt:10`、`:35`。
  - **因此用户要求的「把 pin 可达性检查前移到 checkout 之前」＝要求已被现状满足，本轮 `ci.yml` 一个字节未改**（sha256 `72c16f6b9302bb976402a57ddbf8c557e2444881aa8b5b390e9ac26725e1c43e`，与 C1 变异还原后一致）。**此前「建议重排 ci.yml 步骤」的说法同样被实测推翻，已更正。** 残留观察（只记录不改）：backend-tests 的诊断步在 Build/Vet 之后，若要 fail-fast 可移到 Setup Node.js 之后，`ci-scope.test.mjs:266-277` 的 10 步相对顺序断言不受影响，**待用户裁定**。
  - **主义务仍未满足，不提前报绿**：tools pin 前置已闭合，但 **TC-CBE-005 仍为未执行**——multica 推送**未授权**（且消耗私有库 Actions 额度）、管理员 PAT **未更新**（TC-CCF-003）。**本轮真实 CI run 次数 = 0。** SC-CBE-005 的 β 分支（tools 未推送）已不再适用，但「如实记录未验证、不 skip 不报绿」的主义务继续有效。
- **逐字来源**：`pending-adjustments.yaml:248`

### ADJ-026 — 3 个计划外 CI 形状守卫（不计入 TC 覆盖分子）

- **原始设计**：test-plan.md:225 TC-SEL-004 只覆盖 `ci-paths.json` 的 scope 命中；未为「ci.yml 接线形状」单列 TC；tasks.md 13.3 只列出要接哪些步骤，未规定用测试锁住形状。
- **调整内容**：`scripts/ci-scope.test.mjs` 除 TC-SEL-004 的 1 行表驱动用例外，另新增 3 个独立测试：script-checks 跑 harness 且 pg 取失败不能存活、backend-tests 一次性库/对账/收尾的完整接线（env 键、Setup Node.js、10 步顺序、各步 run 正文与 if 条件）、两个 tools 消费者都改为诊断而非只判非空。**新增测试数合计 4**。
- **调整原因**：SC-CBE-001/003/004 与 SC-TOR-001/002/003 的 CI 侧要求此前只有脚本级用例，没有任何东西阻止 ci.yml 被改回旧形状（恢复 job 级 DATABASE_URL、内联 skip-regex、去掉 down 的 always()）。这 3 个测试把锁定规格在 CI 文件里的落点变成可执行断言，属**加强而非替代**：不替代任何既有 TC、不放宽任何断言、不新增规格要求。3 条变异各只打中预期的第 46 号测试。
- **影响范围**：test-plan 的 TC 清单未列这 3 个测试，故**不计入任何 TC 的覆盖分子**，只作为锁定规格的额外回归守卫；本切片 `tc_coverage` 仍按计划记 2/2。长程约束 #3 由这 4 项真实满足。**C7 的 test-report 须如实区分「计划内 TC 覆盖」与「计划外新增守卫」**。
- **影响 TC**：TC-SEL-004, TC-TOR-004（守卫另计）。**调整阶段**：B / S13。**用户已知**：否。
- **处置**：已处置。13.3 RED 49/47/2 → GREEN 49/49/0 exit 0；harness 目录全量接线前后各 171/171/0/0 零回归；3 条变异全 DETECTED 且 ci.yml 逐字节还原。
- **逐字来源**：`pending-adjustments.yaml:258`

### ADJ-027 — C1 代码评审 MAJOR-1：CRCTL_PATH 别名造成三处未申报 CI skip（major，已修）

- **原始设计**：canonical REQ-CBE-002「tools 依赖只有一个 pin 来源；CI 与本地不依赖开发机路径；缺依赖是失败而不是 skip」、SC-CBE-004 then「缺失 CRCTL_MJS 或 AIFI45_TOOLS_ROOT 的测试以 Fatal 结束而不是 Skip」、SC-CBE-005 then「四个包各自有通过的测试且无名单外 skip」；`validation/s3-env-contract/README.md:118`/`:124-125` 已上报该处并写「扩大受管变量集属规格变更，按流程留待用户裁定」。
- **调整内容**：`resolveCrosscheckCrctl`（`approval_crosscheck_test.go:196-220`）改读受管的 `CRCTL_MJS`，删除两条相对 sibling 开发机回落与 `os.Stat` 探测循环，`t.Skip` 拆为两条 `t.Fatal/t.Fatalf`（crctl 缺失、node 缺失）；文件头「Skips when …」注释更正为「Fails when …」（读 `crsync_test.go:34-61` 核实 TestMain 全部 `os.Exit(1)`）。`go-test-env-contract.mjs` 仅把 `goTestFiles` 改为 export（1 词）供守卫复用；`go-test-env-contract.test.mjs` 新增 1 个测试函数钉住「治理范围内不得再出现 `os.Getenv("CRCTL_PATH")`」。**四个扫描正则一字未改**，`:71-80`「其他条件守卫不标记」用例含 CRCTL_PATH 样例原样保留。
- **调整原因**：三个调用方（`approval_crosscheck_test.go:223`、`:394`、`dev_phase_cp_test.go:176`）所在两文件均无 `//go:build` 标签，CI-linux 会编译；`ci.yml:407-408` 只设 `AIFI45_TOOLS_ROOT` 与 `CRCTL_MJS`，tools 检出在仓内 `.aifirst-tools`，两条相对候选指向仓外（runner 上不存在），故 `crctl==""` → `t.Skip`；归属表 allowed-skips 只有 4 条不含这三个、entries 也不含 → **ci-evidence rule 2 命中 3 次 → backend-tests 判红**。本机基线看不见是因为 repo 父目录恰为 `C:/Users/GOBAO/Downloads/AI`，候选 1 命中真实 sibling tools（S4 基线实测这三个测试共 13 个叶子 PASS）。**关键区分**：S3 拒绝的是扩大扫描器受管变量集，本轮是把代码迁到已被受管的名字上，受管集仍是 `{CRCTL_MJS, AIFI45_TOOLS_ROOT}`，扫描器一行未扩，故不属规格变更、不需重签 Gate 2。另 S3 当时只在 README 上报而未落 ADJ，本条同时补该记录缺口。
- **影响范围**：上游测试文件一处最小钩子（numstat 9 插入/19 删除），CUSTOM.md #331 登记。本机跑这三个测试现在必须注入 `CRCTL_MJS`，与 S3 已转换的 4 个同类测试一致；CI 侧该变量本就注入。不放宽任何断言、不改门禁／触发器／迁移。真实 CI 全绿仍属 TC-CBE-005 未验证，且 pin 不在 origin（ADJ-025）会先在 checkout 步失败，**不提前报绿**。
- **影响 TC**：TC-CBE-004, TC-CBE-005。**调整阶段**：C1。**用户已知**：否。
- **处置**：已处置。RED exit 1（12 tests/11 pass/1 fail，唯一红的是新守卫，点名 `:198`）→ GREEN exit 0（12/12/0）；契约 CLI 对真实仓库 exit 0「119 file(s), 0 violations」；go vet exit 0。真库两条件各一次：变量齐备 `PASS crosscheck-crctl pass=13 fail=0 skip=0`（与 S4 基线 7+3+3=13 逐名一致，零回归）；`env -u CRCTL_MJS` 后 `FAIL pass=0 fail=3 skip=0 exit 1`，三个调用方各自打印 `CRCTL_MJS is required`，**skip=0 证明不再走 skip**。变异 1 条 DETECTED，按原字节还原 sha256 match true。harness 全量 172/172/0/0。gofmt -l 点名该文件属既有 CRLF 现象（工作树 2466 个 .go 中 2206 个 CRLF，未触碰的 `cmd/migrate/main.go` 同样被点名），gofmt 输出与去 CR 原文逐字节一致，**未执行 gofmt -w**。容器清单前后相同。
- **逐字来源**：`pending-adjustments.yaml:268`

### ADJ-028 — C1 代码评审 MINOR-1：非锁读的 TOCTOU 窗口（已申报限制）

- **原始设计**：canonical SC-WSD-005（R5 修订后只要求 reservation 半句的**顺序**场景）；`648_cr_execution_control.up.sql:51-52`（reservation 惰性）与 `:54-66`（reservation 无 workspace_id、无 FK，**明文不新增 FK**）；CUSTOM.md #327。
- **调整内容**：`execution_control_reservation.go:90-96` 的 workspace 存在性检查是非锁读 `SELECT EXISTS`，未加 FOR SHARE/FOR UPDATE。本轮**只追加两行英文注释**说明「非锁读，只闭合顺序 teardown 场景；并发未提交 DeleteWorkspace 仍可穿过，SC-WSD-005 不要求该场景」，SQL 与锁语义一行未改。
- **调整原因**：READ COMMITTED 下，并发未提交的 DeleteWorkspace（`workspace.go:1141` 持 FOR UPDATE）与该非锁读之间存在 TOCTOU 窗口，可产生孤儿 reservation。加 FK 违反 648 明文「不新增 FK」，改锁语义属行为变更且超出 SC-WSD-005 锁定范围，**两者都须用户裁定，不在 Part C 自行选边**。
- **影响范围**：实际风险低——`CreateReservationTx` 目前无生产调用方（仅测试消费，#327 已记），且 648:51-52 声明 reservation 惰性。SC-WSD-005 的顺序场景已由 S10 真库证明满足。若将来接线生产调用方或要求并发安全，须先裁定 FOR SHARE 还是 FK，并同步修订 SC-WSD-005 与 648 的 no-new-FK 约束。**C4 判定为 EXP-2026-0002 命中 1**。
- **影响 TC**：TC-WSD-005。**调整阶段**：C1。**用户已知**：部分（ADJ-017/U3 裁定留待后续）。
- **处置**：未决（已申报限制，本轮不修）。
- **逐字来源**：`pending-adjustments.yaml:278`

### ADJ-029 — C1 MINOR-2 / 测试 NIT-3：run-selection 静默丢弃不可解析行

- **原始设计**：canonical SC-SEL-002 then「SHALL 沿用旧判定：test.code 为 0 且 fail 为 0 且 skip 为 0 且 pass 大于 0；PASS 与 FAIL 输出行 SHALL 逐字不变」与 and「既有断言 SHALL 全部保持通过且不被改弱」；对比 SC-TOR-002 的流完整性要求。
- **调整内容**：`run-selection.mjs:79-82` 的 `summarizeEvents` 用 `try { event = JSON.parse(line); } catch { continue; }` 静默丢弃不可解析行，与 `ci-evidence.mjs` 的「流不可解析即硬失败」不一致。**本轮未改**。
- **调整原因**：不修有规格依据——SC-SEL-002 明文要求沿用旧判定且输出行逐字不变、既有断言不被改弱，把解析失败改成硬失败是行为变更，超出该锁定场景，须走 revision 并由用户确认。两处不对称是各自规格要求的：ci-evidence 是本 change 新建、其流完整性由 SC-TOR-002 要求硬失败；run-selection 是既有文件、SC-SEL-002 要求保留旧语义。**C3 已实证该行为 HEAD 既有**（`git show HEAD:` 同一行在 `:76`，本 change diff 中无任何 JSON.parse/catch/continue 增删行）。
- **影响范围**：既有行为，非本 change 引入的回归。风险：`go test -json` 流若被截断或混入非 JSON 行，run-selection 的计数可能偏低而仍报 PASS；ci-evidence 侧不受影响。**残留缺口须如实呈报**：当前 `selections.json` 全部条目未设 `expected`，新的 fail-closed 对账路径不生效，生产路径仍走这条静默跳过的 legacy totals 循环。若要求统一为硬失败，须修订 SC-SEL-002 并重签 Gate 2，同时复核既有断言不被改弱。
- **影响 TC**：TC-SEL-002, TC-TOR-002。**调整阶段**：C1（C3/C4 复核）。**用户已知**：否。
- **处置**：未决。
- **逐字来源**：`pending-adjustments.yaml:288`

### ADJ-030 — C1 NIT-1：不可达路径不加防御守卫

- **原始设计**：canonical SC-SEL-001/002/003（`decideSelection` 的判定与 blocked 原因）；`run-selection.mjs:141-150`（调用点总传入 reconciliation 对象）。
- **调整内容**：`selection-decision.mjs:18-25` 在 `declared(selection)` 为真时直接解引用 `reconciliation.status`，未加 undefined 守卫。**本轮未改**。
- **调整原因**：该路径当前不可达——唯一调用点总会传入 reconciliation 对象。**为不可能发生的状态加防御守卫属多余错误处理，不做。**
- **影响范围**：无当前影响。若将来新增调用点且漏传 reconciliation，会抛 TypeError 而不是给出 blocked 原因；届时应在调用点保证契约，而不是在此加兜底。
- **影响 TC**：TC-SEL-001, TC-SEL-003。**调整阶段**：C1。**用户已知**：~~否~~ → **是**（Gate 3 呈报后用户裁定「其他的项都采纳你的建议」）。
- **处置**：~~未决（记录为「已评估并拒绝」的评审意见，非待修缺陷）。~~（**C1 当时原文，保留**）→ **已处置＝决定不做（不是已修复，缺口本身也不存在）**。用户采纳「不为不可能状态加防御代码」的建议：唯一调用点 `run-selection.mjs:141-150` 总传入 reconciliation 对象，该分支不可达；`selection-decision.mjs` **一行未改**。若将来新增调用点，应在调用点保证契约，而不是在此加兜底。
- **逐字来源**：`pending-adjustments.yaml:298`

### ADJ-031 — C1 NIT-2 / 测试 MINOR-1：env 契约扫描器的模式盲区

- **原始设计**：canonical SC-CBE-004 when/then「搜索 `C:/Users/` 开发机绝对路径，以及依赖 AIFI45_TOOLS_ROOT 或 CRCTL_MJS 的测试在环境变量缺失时的处理」「契约检查本身 SHALL 能对注入了旧默认路径或 t.Skip 的样例变红」；`go-test-env-contract.mjs:18-21`。
- **调整内容**：扫描器存在模式盲区——`ENV_BIND` 不认 `os.LookupEnv`；`EMPTY_GUARD /if\s+(\w+)\s*==\s*""/` 不认内联 `if cli := os.Getenv("CRCTL_MJS"); cli == "" { t.Skip(…) }`、switch/case、`if len(x)==0`；`SKIP` 不认 `t.SkipNow()`。**本轮未扩围**。
- **调整原因**：SC-CBE-004 只要求对「注入了旧默认路径或 t.Skip」的样例变红，上述写法都不是旧写法，扩模式集属超出锁定要求的加固。当前仓库干净：CLI 实测 exit 0「go test env contract OK: 119 file(s), 0 violations」。本轮实际发生的逃逸（CRCTL_PATH 别名）已由 ADJ-027 的新守卫钉住，**不依赖扩扫描器**。
- **影响范围**：盲区意味着将来若有人用 `os.LookupEnv` 或内联 if 形式写 env-guarded skip，契约检查不会变红，可能重现「未验证变绿」。属加固议题，Gate 3 呈报请用户决定是否另开变更；不在本 change 静默扩围。
- **影响 TC**：TC-CBE-004。**调整阶段**：C1。**用户已知**：~~否~~ → **是**（Gate 3 呈报后用户裁定「其他的项都采纳你的建议」）。
- **处置**：~~未决。~~（**C1 当时原文，保留**）→ **已处置＝明确不做（不是已修复，也不是移交后续 change）**。用户采纳「不扩围」的建议，理由按行业口径收敛为一条：**G1「CI 绿 ⇒ 声明的测试真跑过且无未申报 skip」由 `ci-evidence.mjs` 对 `go test -json` skip 事件的运行时对账承重，与测试怎么写无关**；静态扫描器只是提前提示，穷尽模式属规格变更（超出 SC-CBE-004 的 `when`，须**重签 Gate 2**）且收益与运行时对账重复。**四个扫描正则一字未改**，受管变量集仍为 `{CRCTL_MJS, AIFI45_TOOLS_ROOT}`；契约 CLI 对真实仓库 exit 0「**119 file(s), 0 violations**」。本轮真实发生的逃逸（`CRCTL_PATH` 别名）已由 ADJ-027 的**具名守卫**钉住，不依赖扩扫描器。
- **逐字来源**：`pending-adjustments.yaml:308`

### ADJ-032 — C1 文档评审 minor 1：canon 索引指向不存在的聚合文件

- **原始设计**：`canonical/.canon-index.yaml:6` 与 `:8`（Gate 2 input_manifest 内的 logical_path）；ADJ-015（同源 CLI 缺陷）。
- **调整内容**：索引指向不存在的 `specs/agent/2026-11-12-fork-ci-test-evidence-trust.yaml` 与 `specs/code/…yaml`，实际布局是 5 个 per-capability 文件。**本轮未改**。
- **调整原因**：功能上惰性——generate 走 glob、verify 只校 proposal、Gate 2 哈希原始字节，故不影响任何已验证结论。**不修的硬边界**：该文件在 Gate 2 的 input_manifest 内，编辑它会使 Gate 2 失效并须 `--reapprove` 重签，本轮无用户重签授权，**不静默修改锁定输入**。
- **影响范围**：索引与实际布局不符，将来若有人按索引路径读聚合 spec 会落空。修复须与 ADJ-015 一并作为 CLI 缺陷处理，或在取得重签授权后同步修订索引与 Gate 2。
- **影响 TC**：无（索引惰性）。**调整阶段**：C1。**用户已知**：否。
- **处置**：未决。
- **逐字来源**：`pending-adjustments.yaml:318`

### ADJ-033 — C1 文档评审 minor 2：14 个 agent CP 的 description 词中截断

- **原始设计**：`canonical/specs/agent/*.yaml` 的 `checkpoints[].description`（Gate 2 input_manifest 内的 5 个 agent spec）；`stdd canon generate` 的渲染行为。
- **调整内容**：18 个 agent CP 中 **14 个**的 description 在第 61 字符处词中截断（CP-SEL-001 结尾「…含该 re」、CP-SEL-003「…；SHAL」、CP-WSD-002「…cr_execution_dispa」等）。**本轮未改**。
- **调整原因**：边界反证——CP-WSD-004 恰好 61 字符且自然收在「。」，CP-WSD-005（132 字符，R5 手工同步）完整，故属**工具渲染缺陷而非撰写遗漏**。action 与 assertions 均 intact，CP 语义未损。不修的硬边界同 ADJ-032：这些是 Gate 2 输入，编辑须重签，本轮无授权。
- **影响范围**：description 作为人读摘要不完整，但验证语义由 action/assertions 承载，**不影响任何 CP 的可执行性与已验证结论**。修复须走 CLI 缺陷或取得重签授权后手工同步（如 R5 对 CP-WSD-005 的做法）。
- **影响 TC**：无（action/assertions 完整）。**调整阶段**：C1。**用户已知**：否。
- **处置**：未决。
- **逐字来源**：`pending-adjustments.yaml:328`

### ADJ-034 — C1 测试评审 MAJOR-1：tools checkout 的 ref 来源此前无任何可执行断言承重

- **原始设计**：`canonical/specs/code/ci-backend-environment.yaml` SC-CBE-003 given「ci.yml 的两个消费者从它读取 ref」与 then「ci.yml 中 SHALL 不再出现 tools 的字面 commit」；REQ-CBE-002「tools 依赖只有一个 pin 来源」；`test-plan.md` TC-CBE-003。
- **调整内容**：`tools-pin.test.mjs:166-172` 的原断言只检查「某一行含 `aifirst-tools-pin`」「某一行含 `repository: OldBoy405/AI-First-tools`」，**从不检查 checkout 自己的 ref 来自 pin 步骤输出**。本轮**就地强化该测试函数（新增函数数 0）**：对每一个 repository 行按 `/^ {10,}\S/` 收集其所属 `with:` 块，断言块内 ref 行恰好一条且 trim 后等于 `ref: ${{ steps.tools-pin.outputs.ref }}`，失败报文点名 ci.yml 行号。
- **调整原因**：`tools-pin.mjs:57-66` 的 check 只验 3 个必需文件存在、**不验 HEAD==pin**；ci-scope 的新断言钉的是步骤顺序而非 ref 行。故把 ref 改成 `main` 可让全部测试与完整性检查保持绿——单一 pin 来源在 CI 文件里没有任何可执行断言承重。**已用变异实测证明该缺口**：两处 ref 改为 `main` 后旧测试 exit 0、15/15 全绿（含 #15 本身）。
- **影响范围**：属 B4 小偏离中的**加强**：不替代任何既有 TC、不放宽任何断言、不新增规格要求，TC-CBE-003 覆盖分子不变。本轮 C1 合计新增测试函数 **1**（ADJ-027 的那一个），与本条的「强化既有函数」分开如实计数。生产 `ci.yml` 本轮未被改变（变异后按原字节还原）。
- **影响 TC**：TC-CBE-003（分子不变，断言加强）。**调整阶段**：C1。**用户已知**：否（Gate 3 呈报）。
- **处置**：**已修复并四步验证**。① 缺口证明：两处 ref 变异为 `main`（实测命中 2 处），旧测试 exit 0、tests 15 / pass 15 / fail 0，#15 照样绿。② RED：保持变异应用强化断言 → exit 1、15 tests / 14 pass / 1 fail，唯一红的是 #15，报文 `the tools checkout at ci.yml:136 must take its ref from the pin step output`。③ 还原：2 处改回原表达式，sha256 `72c16f6b9302bb97…` 与变异前 match true。④ GREEN：exit 0、15/15/0。回归：harness **172/172/0/0 exit 0**、ci-scope **49/49/0 exit 0**。证据 `validation/c1-review/{triage.md §4.2, mutation-ref-main-old-test.tap, red-ref-main-new-test.tap, green-ref-restored.tap, harness-after-both-fixes.txt, ci-scope-after-both-fixes.tap}`。本轮 C1 的记录更正（ADJ-018 枚举三处、`slices.md:57` 规划断言、s13 README 措辞与 git status 计数、CUSTOM.md CR 索引补行）见 `triage.md §3.11–3.14` 与 CUSTOM.md #332，均保留原文并标注 C1 更正。
- **逐字来源**：`pending-adjustments.yaml:338`

### ADJ-035 — 用户裁定：补真实 L4 基准锚定，Gate 1+2 连锁重签

- **原始设计**：`canonical/proposals/2026-11-12-fork-ci-test-evidence-trust.yaml:147-152`（`anchoring.level` L3、`anchor_implementations` 空）；同文件 `critical.risk_assessment.financial=true`；`.stdd/skills/spec.md:126-134`（financial 要求最低 L4，不足则 Gate 2 阻塞）；`stdd/cli/commands/ci.py:1186-1222` 检查 (l)。
- **调整内容**：按用户裁定「补真实 L4 基准锚定并重签（推荐）」在记录仓落地：`level` L3→**L4**；`anchor_implementations` 填入 **11 条**逐条核实为 multica tracked 文件的基准路径，每条对应一个 capability 必须沿用的现行实现（`provision.mjs` / `instance.mjs` / cmd-server `integration_test.go` / governance `crsync_test.go` / `ci.yml` / `test-go.sh` / `selection.mjs` / `selections.json` / `workspace_delete_manifest_test.go` / `648_cr_execution_control.up.sql` / views `agent-batch-toolbar.test.tsx`）。`critical.risk_assessment` 与 `is_critical` **逐字未改**（financial 仍 true）。`canon generate` 只重写 `proposal.md`（source_hash `dd59ac55294e83a1`），`canon verify` 由 1/2 恢复 **2/2**。
- **调整原因**：financial=true（私有库 Actions 额度）要求最低 L4，原 L3 使检查 (l) 判 FAIL。核实 (l) **只比较等级、不校验 anchor_implementations 内容**，故单升等级即可变绿；按裁定语义**填实真实基准，不做只为过门禁的空升**。候选 `server/internal/governance/execution_contract_manifest.go` 经 git grep 核实 `cr_execution` 命中数为 0、与 C7 无关，**已剔除不凑数**。
- **影响范围**：canonical proposal 与 `proposal.md` 同为 Gate 1 仅有的 2 项受审输入，故本次修订使 **Gate 1 与 Gate 2 同时 stale**。首次 `stdd gate approve --gate 2 --reapprove` 被 CLI **拒绝（exit 1，未写入）**：Gate 1 审批输入已 stale，保留原批准、拒绝新动作、不自动重签，须先取得用户对 Gate 1 重签的明确授权。哈希比对证明 `test-plan.md` / `design.md` / `tasks.md` / `slices.md` / `phase-context.md` 与 `.canon-index.yaml` **逐字节未变**，断言与命令未被改写；`proposal.md` 在记录仓为 UNTRACKED 且只保留了生成前哈希，**故无法给出行级 diff，此点如实记录**。
- **影响 TC**：无直接（门禁输入层面），但锁定全部 22 个 TC 的受审输入。**调整阶段**：BUILD（用户裁定后）。**用户已知**：**是**（两次裁定原文）。
- **处置**：**已修订并重签完成**。双轨一致性核实：YAML 可解析、level L4、11 条锚定、风险分类未改、`canon verify` 2/2。用户就 Gate 1 连锁 stale 追加裁定「同一裁定覆盖两道，依次重签（推荐）」，据此以该裁定原文作 evidence 依次执行 `gate 1 --reapprove`（exit 0）→ `gate 2 --reapprove`（exit 0），**旧批准回执保留**。`gate status` 复核：Gate 1 confirmed `2026-11-13T09:46:15`、Gate 2 confirmed `2026-11-13T09:46:16`，均不再 stale，**Gate 3 仍 pending 未推进**。首次 gate 2 重签被拒绝的事实保留在 impact_scope 中不删改。
- **逐字来源**：`pending-adjustments.yaml:348`

### ADJ-036 — stdd 外部缺陷：manual TC 使 agent verify 崩溃（用户自行修复）

- **原始设计**：`stdd/cli/commands/agent.py:206`（HEAD 原为 `:197`）`planned_here = [item for item in planned if item["cp"] == step["id"]]`；`test-plan.md` 证据计划中 4 条 `kind=manual` 的 check（TC-CBE-005 / TC-TOR-004 / TC-TOR-005 / TC-CCF-003）按规格**不绑定 CP**。
- **调整内容**：外部工具缺陷，**本会话未修**。`stdd agent verify` 遍历全部 22 条 check 时对 4 条无 `cp` 键的 manual 条目抛 `KeyError: cp`，导致 **0 个 CP 执行、TC 覆盖 0/22**，run `97da35cc` 只留下 inputs 与 `tc-evidence.json` 而无 `agent-verification-report.md`。用户本轮**自行在 stdd 侧**将该行改为 `item.get("cp")`，已只读核实到位。
- **调整原因**：用户明令本会话不得再改 stdd 仓库内容，故修复由用户自己执行。原拟的记录仓补 `cp: null` 方案经核实同样可行（`evidence.py:149` 用 `check.get("cp") is not None` 校验 manual，null 与缺键等价），但用户选择了**根因直修**，该方案不再需要，**`test-plan.md` 因此未被改动**。
- **影响范围**：stdd 属共享 RESOURCE_ROOT，该缺陷影响**任何含 manual TC 的项目**。本 change 侧无需修订任何锁定输入。修好后须以**新 run id** 重跑 verify 取真实 18 CP 证据，**旧 run `97da35cc` 的 0/22 结论不得沿用为通过**。
- **影响 TC**：全部 22 个 TC 的覆盖判定与 18 个 command CP 的执行。**调整阶段**：C2。**用户已知**：**是**（用户告知已自行修改）。
- **处置**：**已修复（用户侧）**，本会话只读核实 `agent.py:206` 现为 `item.get("cp")`，**本会话对 stdd 的写入数为 0**。同类未防护访问已逐点扫描：`evidence.py:151/154/155/175` 有 kind 或分支保护；`:596-598` 的 kind 过滤在 `item["cp"]` 之前短路；`:1076` 前有 manual 的 continue（`:1075`）；`:807/836/845` 取单条 planned 必含 cp——**均不可被 manual 触发**（唯一残留点见 ADJ-037）。修复后已以新 run `7cd120df` 重跑，结果见 ADJ-040（**该 run 后又因 ADJ-042 改动受审输入与 ADJ-045 环境重建而失效；现行选定 run 为 `dfb7aad8…`，18/18 同值复现，见 ADJ-040 的更正块**）。
- **逐字来源**：`pending-adjustments.yaml:358`

### ADJ-037 — stdd 同类残留点：_require_argv 在 kind 过滤前解引用 cp

- **原始设计**：`stdd/cli/evidence.py:806` `nodes = [item["nodeid"] for item in plan["checks"] if item["cp"] == planned["cp"] and item["kind"] == "pytest"]`；所在函数 `_require_argv:797-808`。
- **调整内容**：ADJ-036 的同类残留点，**本轮未修（stdd 只读）**。该处 `item["cp"]` 在 kind 过滤**之前**求值且无 `.get` 保护，若计划含 manual 条目会抛同样的 KeyError。
- **调整原因**：本计划 **0 条 pytest check**，且 `_require_argv` 在 `:800-801` 要求 plan 声明 pytest 来源否则先 raise，故**本轮执行路径不可达**，不构成当前阻塞。按用户禁令不写 stdd，只记录。
- **影响范围**：将来任何**同时含 manual 与 pytest 义务**的计划会在此崩溃。属 stdd 侧待办，应由该仓自己的变更处理，不在本 change 范围内修。
- **影响 TC**：无（本轮不可达）。**调整阶段**：C2。**用户已知**：否（Gate 3 呈报）。
- **处置**：未决（stdd 侧待办）。
- **逐字来源**：`pending-adjustments.yaml:368`

### ADJ-038 — stdd 流程缺陷：Gate 2 审批路径不执行锚定等级检查

- **原始设计**：`.stdd/skills/spec.md:126-134`（financial=true 要求最低 L4；`proposal.anchoring.level` < 最低需求 → **Gate 2 阻塞**）；`stdd/cli/commands/ci.py:1186-1222` 的 (l) 检查**只挂在 `ci check-failures` 上**。
- **调整内容**：外部流程缺陷，**本轮未修（stdd 只读）**。Gate 2 审批路径不执行 (l) 锚定检查，导致 L3 在 financial=true 下仍**三次通过 Gate 2**（最后一次 `2026-11-12T23:54:09`），直到 BUILD 阶段跑 `ci check-failures` 才暴露等级不足。
- **调整原因**：Skill 正文声称「不足即阻塞 Gate 2」，**实现与声明不一致**。按用户禁令不写 stdd。本 change 侧以 ADJ-035 的**真实 L4 锚定**满足门禁要求，**不依赖该缺陷是否修复**。
- **影响范围**：任何 critical 变更都可能在锚定不足的情况下通过 Gate 2，把缺口推迟到 BUILD 才暴露。属 stdd 侧待办。
- **影响 TC**：无直接（门禁有效性层面）。**调整阶段**：BUILD/C2。**用户已知**：否（Gate 3 呈报）。
- **处置**：未决（stdd 侧待办，major）。
- **逐字来源**：`pending-adjustments.yaml:378`

### ADJ-039 — 本机 esbuild 二进制缺失使全量 typecheck 失败（用户授权后修复）

- **原始设计**：`config.d/quality.yaml` 的 `quality.typecheck = pnpm typecheck`；canonical proposal SC10（packages/views typecheck 本地 0 条 TS6059）；C2 全量质量检查义务。
- **调整内容**：本机环境失败，经用户裁定「授权修 esbuild 二进制后重跑」后修复。首轮全量 `pnpm typecheck` **exit 1**：`@multica/web:mdx` 与 `@multica/docs:mdx` 在 esbuild `generateBinPath`（`lib/main.js:1739`）抛错，turbo 早退 **Tasks 0 successful / 5 total**，全量日志 **error TS 计数 0**——失败发生在任何 TS 编译之前。实测根因：`node_modules/.pnpm/@esbuild+win32-x64@0.25.12/.../win32-x64/` 只有 `README.md` 与 `package.json`，全 `.pnpm` 下 `find esbuild.exe` 为空。
- **调整原因**：`apps/` 在本 change 的改动文件数为 **0**，未碰 web/docs 的 mdx 管线，故**非本 change 回归**。`pnpm rebuild esbuild` 是**空操作**：exit 0 但 `lib/`、平台包目录、`esbuild.exe`、`downloaded-*` 四项全部无变化，**按实测判定未生效，不以退出码 0 当作修好**。改为直接执行 esbuild 自己声明的 postinstall（`node install.js`），由其自带回退从官方 `registry.npmjs.org` 取包，**未手写或替换任何下载地址**。
- **影响范围**：修复只落在 `esbuild/lib/downloaded-@esbuild-win32-x64-esbuild.exe`（**10617344 字节**、可执行位就绪），平台包目录未改；`package.json` / `pnpm-lock.yaml` / `pnpm-workspace.yaml` 的 git 差异为空、mtime 仍 `2026-10-21`，**依赖声明未被触碰，未重装全部依赖**。重跑全量 `pnpm typecheck`：**EXIT_CODE=0、Tasks 10 successful / 10 total、Cached 0、error TS 计数 0、耗时 1m19s**，为**整图跑完的全量通过而非过滤口径**。原 exit 1 日志保留为历史证据，新结果另存 `pnpm-typecheck-after-fix.txt`。
- **影响 TC**：TC-CCF-002（views 过滤口径，`test-plan.md:338`）；全量 `pnpm typecheck` 属 C2 quality 义务，非独立 TC。**调整阶段**：C2。**用户已知**：**是**（裁定原文「授权修 esbuild 二进制后重跑」）。
- **处置**：**已修复并实测验证**。证据 `validation/c2-quality/{pnpm-typecheck.txt（原 exit 1）, esbuild-rebuild.txt（空操作 exit 0）, esbuild-install.txt, canon-views-before.txt, canon-views-after.txt, pnpm-typecheck-after-fix.txt（exit 0、10/10、0 error TS）}`。typecheck 义务由**环境阻塞转为真实全量通过**。
- **逐字来源**：`pending-adjustments.yaml:388`

### ADJ-040 — 18/18 命令 CP 真实通过，但 CLI 覆盖判定仍为 0/22（结构性不完整）

- **原始设计**：`test-plan.md` 证据计划 22 条 check（**18 command + 4 manual**）；`stdd/cli/evidence.py:1033-1034`（`len(checks) != len(plan["checks"])` 即 raise）；`evidence.py:1071`（confirm 固定写 `result=manual-pass`）；run `7cd120df` 的 REVIEW_PENDING 输出。
- **调整内容**：run `7cd120df-d9d1-4f31-a9b5-e26b5a13606a` **真实执行 18/18 命令 CP 全通过**（`tc-evidence.json` 实测 18 条、全部 `kind=command`、全部 `result=pass`、18 个不同 TC，`agent-verification-report.md` 已生成），但**同 run** 的 `ci check-failures` 仍判 **TC 覆盖 0/22**，理由「缺少或重复必需 check（当前运行未完成）」。核实判定为**严格条数相等**：18 != 22 即**整个 run 无效、覆盖归零**，而不是按已通过条数计 18/22。verify 自身 **EXIT_CODE=1 亦源于 REVIEW_PENDING，非 CP 失败**。
- **调整原因**：4 个 manual TC 前置未满足，**一律不确认**：TC-CBE-005 需真实 CI run（推送须单独授权并消耗私有库 Actions 额度）；TC-TOR-004 需 WSL AIFI-ISO 独立入口（ADJ-024 半句 UNCOVERED）；TC-CCF-003 需管理员更新 PAT；TC-TOR-005 需验收报告，C7 产出后方可如实确认。`agent confirm` 写入的 result 固定为 `manual-pass`，**确认即等于断言通过，故不得为凑覆盖而伪造确认**。
- **影响范围**：~~覆盖指标在 4 项全部如实确认前**恒为 0/22**，无法反映已真实通过的 18 个命令 CP。~~（**C2 当时原文，保留；影响范围判定已被 ADJ-046 实测更正——见下方更正块第 5 点：同一判据还硬阻断 `gate approve --gate 3`，不止是指标**）**Gate 3 必须同时呈报两个数字与各自含义**：命令 CP **18/18 通过**（有报告与产物），CLI 覆盖判定 **0/22**（run 因 4 项人工未确认而结构上不完整）。**不得以 18/18 冒充覆盖通过，也不得把 0/22 说成执行失败。** 一次性实例边界已守住：运行前后容器清单 diff 为 **IDENTICAL**，两个旧容器始终 Exited。
- **影响 TC**：全部 22 个 TC 的覆盖判定；4 个 manual TC（CBE-005 / TOR-004 / TOR-005 / CCF-003）未确认。**调整阶段**：C2。**用户已知**：~~否（Gate 3 呈报，major）~~ → **是**（Gate 3 呈报后用户以「命令 CP 18/18 + 4 个人工 TC 未闭合」确认，即知悉并接受两个数字并存）。
- **处置**：未决（**属 stdd 侧口径缺陷，用户已裁定「stdd的项不在本次完成，我以后单独完成」，本会话写入数 0**）。~~TC-TOR-005 待 C7 验收报告产出后按真实审阅原文确认；其余 3 项在外部前置满足前**不得确认**。~~（**C2 当时原文，保留**）
- **Gate 3 后续轮更正与重执行（原文保留，只追加更正）**：
  - **选定 run 已换为 `dfb7aad8-7539-486b-aa59-297d57a87d1a`**：旧 run `7cd120df…` 因 ①ADJ-042 改动了声明输入 `scripts/aifi45-disposable`（`evidence.py:735-739` 重新快照受审输入并拒绝沿用）②依赖执行环境被清理事故波及后重建（ADJ-045），**已失效不得沿用**。本轮以新 run id **整轮重跑 18 条命令 CP**：`Results: 18 passed, 0 failed`、`tc-evidence.json` checks 18 / inputs 823 / coverage `[]` / manual 0、6 个一次性实例均 `released … remaining=0`、46 个真库叶子测试 fail 0 / skip 0 且与旧 run **逐名一致＝零回归**。
  - **结构性结论在新 run 上原样复现**：`ci check-failures` 仍判 **0/22**，错误项原文仍为「缺少或重复必需 check（当前运行未完成）」；`VERIFY_EXIT=1` 仍源于 **REVIEW_PENDING 列出 4 项人工 TC，不是 CP 失败**。**证明该缺口与具体 run 无关，是 CLI 口径问题。**
  - **更正「TC-TOR-005 可单独确认」的暗示**：读 `stdd/cli/evidence.py:717-770` 实测 `confirm_manual` 是**计划级、全有或全无、一次性**——`:740` 取全部必需 manual（4 条）、`:761-764` 一次全写 `manual-pass` 共用同一 statement、`:745-748` 拒绝二次不同确认。**故不存在单独确认某一项的路径**；验收报告已生成，TC-TOR-005 的人工审阅留痕由报告 + 用户 Gate 3 确认原文承担。**本轮不执行任何 `agent confirm`**（否则等于同时断言另外 3 项通过）。
  - **产物哈希与旧 run 相同属正常**：`agent-verification-report.md` 正文只有 18 行 `CP-xxx: PASS (exit_code=0)`，**不嵌入 run id**（`grep -c "dfb7aad8\|7cd120df"` → **0**），两轮结论相同故逐字节相同。**区分依据是 `run_id` 字段与目录名，不是哈希**；不是复制旧产物。
  - **影响范围判定被更正（ADJ-046，实测）**：本条原先只把该判据的影响写成「覆盖指标恒为 0/22」。按用户裁定原文执行 `stdd gate approve … --gate 3 --run dfb7aad8…` 后，**CLI 直接拒绝批准、`APPROVE_EXIT=1`**，stderr 与本条错误项**逐字同源**（「缺少或重复必需 check（当前运行未完成）」）。读 `gate.py:810-823` 确认：Gate 3 把 `_gate3_selected_evidence` 的 problems 作为批准前置，**同一 `len(checks) != len(plan["checks"])` 判据因此硬阻断 Gate 3，而不只是让指标归零**。**故本条的严重性被低估了**：它不是「呈报两个数字即可」的口径问题，而是**本 change 无法推进到 DELIVER 的阻塞项**。处置路径见 ADJ-046。
- **逐字来源**：`pending-adjustments.yaml:398`

### ADJ-041 — stdd 范围蔓延检查 (b) 的四处口径缺陷（WARN 不可作为证据）

- **原始设计**：`stdd/cli/commands/ci.py:874-906` 的 (b) 范围蔓延检查（文件源 `git diff --stat HEAD~1`、正则 `^\s*([^\s|]+)`、`common_dirs` 与 `specs/<cap>/` 判据）。
- **调整内容**：实测复现该检查的口径缺陷，**本轮未修（stdd 只读）**。`git diff --stat HEAD~1` 报 **38 files changed**，同一正则解析出 **39 个 token**，汇总行的数字 38 被当成文件路径（numeric-looking tokens 实测为 `[38]`），故报出的 37 个超范围文件里**有一个是假路径，真实为 36**。
- **调整原因**：四处缺陷：① 文件源是 HEAD~1→工作树，把**上一提交**（HEAD=`903a46c5a`、HEAD~1=`d5b348a17`）的归档文件混入本 change 的范围判定；② `git diff` **不含未跟踪文件**，本 change **27 个新文件**对该检查完全不可见；③ `--stat` 把长路径截断为 `.../handler/workspace_delete_manifest_test.go`，前缀匹配在**非真实路径**上进行；④ 范围判据只认 `.stdd/ tests/ docs/ .github/` 前缀或 `specs/<cap>/`、`commands/<cap>` 子串，**multica 真实代码路径无一能匹配 capability 名**。
- **影响范围**：**该 WARN 不能作为本 change 范围蔓延的证据。** 真实范围已手工逐文件核对：**49 个文件（22 改 + 27 新）全部可追溯到 C1–C10 或 constraints**；其中 `packages/core/package.json` 仅新增一行 subpath export `./platform/storage`，是 C9 把 `use-logout.test.ts` 的相对导入改回包导入后的必要解析入口；`approval_crosscheck_test.go` 的 9 增 19 删是删除 CRCTL_PATH 别名与开发机相对路径回退、把 `t.Skip` 改为 `t.Fatal/t.Fatalf`，**属收紧而非放宽断言**。属 stdd 侧待办，应由该仓自己的变更处理。
- **影响 TC**：无（范围判定口径，不改任何断言）。**调整阶段**：C2/C3。**用户已知**：否（Gate 3 呈报）。
- **处置**：未决（stdd 侧待办）。
- **逐字来源**：`pending-adjustments.yaml:408`

### ADJ-042 — parseArgs 无最终 else：flag 名拼错则证据不写而结论仍 PASS

- **原始设计**：`canonical/specs/code/selection-reconciliation.yaml` SC-SEL-001 / SC-SEL-003（对账失败使 selection 失败、**不得静默当作未配置**）；`scripts/aifi45-disposable/run-selection.mjs:28-46` 的 parseArgs 与 `:176-177` 的证据写入判定。
- **调整内容**：C3 逐文件审查发现 parseArgs 的 if/else-if 链**没有最终 else**，未知参数被静默丢弃。本 change 新增的 `--evidence-dir` 放大了后果：flag 名本身拼错（如 `--evidence-dirr`）时 `options.evidenceDir` 保持 null，`:176` 的 `if (options.evidenceDir !== null)` 不成立，**证据完全不写，而 selection 仍按测试判定输出 PASS**。**本轮未修。**（**Gate 3 后续轮更正**：用户裁定「ADJ-042 纳入本 change」，已修并验证，见下方「处置」；C3 当时的发现与判断原文保留。）
- **调整原因**：fail-open 与本 change「测试证据可信性」的目标**相反**：证据缺失应当可被发现，而不是静默成功。缺值与后接 flag 两种形态已有断言（`run-selection.test.mjs:131-138` 覆盖 `["--evidence-dir"]` 与 `["--evidence-dir","--only"]`），但「**flag 名拼错**」这一形态**无任何断言**。`--admin-url` 已被显式拒绝，说明已有拒绝危险参数的意图，只是未覆盖一般未知参数。
- **影响范围**：影响面已实测收敛：`.github/workflows/ci.yml` 中**不含 run-selection 或 --evidence-dir 调用**，`test-ownership.json` 的独立入口只传 `--selections/--only`，故 **CI 路径不受影响**，风险限于人工运行独立入口时拼错 flag。修法为给 parseArgs 补最终 else 抛错并加一条断言，**属行为收紧，需用户裁定**是否纳入本 change 或留待后续。审查留痕见 `validation/c3-diff/README.md §4.1`。
- **影响 TC**：**无既有 TC 直接断言该形态**（TC-SEL-004 钉的是 ci-scope 接线与 script-checks，不含 flag 名拼错）；修复须新增断言。**调整阶段**：C3。**用户已知**：是（Gate 3 呈报后用户裁定纳入本 change）。
- **处置**：**已处置（本轮修）**。用户 2026-11-13 裁定原文「ADJ-042 纳入本 change。」
  - **代码**：`run-selection.mjs` 的 parseArgs 在 `--admin-url` 拒绝分支之后补最终 `else`，抛 `unknown argument: ${arg}`，**+3 行**（`:44` 起，throw 在 `:45`），口径对齐同目录 `tools-access.mjs:66` 的既有拒绝语义；既有分支与 `main()` 的证据写入判定一行未改。**修后实测该目录 7 个带参数解析的脚本全部对未知参数硬失败**：`ci-provision.mjs:132`、`ci-evidence.mjs:162`、`test-ownership.mjs:108`、`go-test-env-contract.mjs:75`、`tools-access.mjs:66`、`tools-pin.mjs:45`、`run-selection.mjs:45`。run-selection 的消息带冒号（`unknown argument: `），其余 6 个不带；**语义一致、标点差异未统一**（新断言只匹配 flag 名，不依赖标点）。
  - **测试**：`run-selection.test.mjs` **+1 个测试函数**「an unknown flag is rejected by name before any instance is created」，复用既有 `runRunner` 助手（`:19-32`，空 PATH），以 `spawnSync podman ENOENT` 区分「先拒绝」与「已尝试建实例」；断言 exit≠0、stderr 含 `--evidence-dirr`、stderr 不含 `podman`。
  - **实测退出码**：首次 RED **无效**（失败原因是 `ERR_MODULE_NOT_FOUND: pg`，见 ADJ-045，依赖恢复后重取）；有效 RED `node --test --test-reporter=tap --test-name-pattern="unknown flag" …run-selection.test.mjs` → **exit 1，tests 1 / pass 0 / fail 1**，stderr `disposable runner failed: spawnSync podman ENOENT`；GREEN 同命令 → **exit 0，1/1/0**；`run-selection.test.mjs` 全量 → **exit 0，14/14/0/skipped 0**（修前 13）；harness `node --test "scripts/aifi45-disposable/*.test.mjs"` → **exit 0，173/173/0/cancelled 0/skipped 0/todo 0**（172→173，恰 +1）；`ci-scope.test.mjs` → **exit 0，49/49/0**。原文留存 `validation/gate3-followup/`。
  - **调用方安全（实测）**：`ci.yml` 无 run-selection 或 `--evidence-dir` 调用，`test-ownership.json` 独立入口只传 `--selections/--only`；parseArgs 在 `main():161` 调用，早于 `:170` 的 `startInstance`，故拒绝发生在建实例之前。
  - **连带义务**：`scripts/aifi45-disposable` 是证据计划声明的**受审输入**，本改动使选定 run `7cd120df-…` 失效（`evidence.py:735-739`「受审输入自执行后已变化，需重新执行」），**必须以新 run id 重跑 18 条命令 CP**；未重跑前不得沿用旧 run 的通过结论。
  - **台账**：multica `CUSTOM.md` **#333**（7 竖线 / 6 单元格），M31 索引与标题同步为 `#317–#333 / 17`。**未提交、未推送、未部署。**
  - 已按 C5 登记新模式 **EXP-2026-0006**（`contract_gap` / javascript / medium）。
- **逐字来源**：`pending-adjustments.yaml:418`（resolution 已补本轮实测证据）

### ADJ-043 — 技能层与资源根对调整记录格式的口径冲突（都自称 3.0.7）

- **原始设计**：用户级安装的 `C:\Users\GOBAO\.qoder\skills\stdd-build\SKILL.md` B4「记录到 `pending-adjustments.yaml`（Canonical YAML 格式）」与 C6「生成 `design-adjustments.yaml`（修订需求）」；资源根 `.stdd/skills/build.md:315-317` 与 `.stdd/skills/_shared/revision-rules.md:29`。
- **调整内容**：C6 产物按**资源根口径**生成为 `design-adjustments.md`，**不生成同名 .yaml**；既有 `pending-adjustments.yaml`（本条登记后 **43 条**；C7 新增 ADJ-044 后为 **44 条**；**Gate 3 后续轮新增 ADJ-045 后现为 45 条**）**逐字保留，未迁移、未删除、未双写**。未改任何技能文件，**对 stdd 资源仓写入数仍为 0**。是否把 pending 台账迁移为 `.md` **等待用户裁定**。
- **调整原因**：两处口径冲突且都自称 3.0.7：用户级技能 frontmatter 第 4 行 `stdd_version: 3.0.7`（第 13 行注明「源 frontmatter 保持」），但正文 B4/C6 仍写 `.yaml`，description 又标 V3.0.5；资源根 `.stdd/version.yaml` 为 `stdd_version: 3.0.7`，其 `build.md:317` 明写「生成 design-adjustments.md（修订需求），作为后续迭代的输入；不再生成或读取同名 .yaml」，`revision-rules.md:29`（该片段自称 Gate 修订规则唯一来源）明写「调整记录统一为 pending-adjustments.md 与 design-adjustments.md。同名 .yaml 不读、不计入任何 Gate，也不再由新安装生成」。按 AGENTS.md「从业务仓优先加载当前阶段的已安装 STDD Skill；若对应入口未安装，从已核实资源根的 `.stdd/skills/` 读取」，实测 `multica/.stdd` 只有 `binding.yaml`（81 字节）、**无 skills 目录**，故**资源根为权威**。另 Step 0 版本自检无法比对：`multica/.stdd` 与 `DATA_ROOT/projects/multica` 均无 `version.yaml`。
- **影响范围**：已核实 `pending-adjustments.yaml` **不在 Gate 1（input_manifest 2 项）或 Gate 2（20 项）内**，故新增或迁移调整记录**不会使 Gate 1/2 过期**，与 revision-rules §2「仅新增调整记录 → 仅重审 Gate 3」一致。（C7 更正：初稿误记 19 项，实测 `phases.spec.input_manifest` 为 20 项。）本条不改任何产品代码、规格、断言或触发器。风险与取舍：只留 `.yaml` 则当前工具链不读不计，**C6 产物在 Gate 3 缺位**；同时双写 `.md` 与 `.yaml` 会造成**两份真相源并漂移**，故只生成 `.md`，并在其中逐条指明逐字来源为 `pending-adjustments.yaml` 的对应条目。迁移约 **90KB** 既有台账属**记录搬移，须用户裁定后执行**，不擅自双写或删除原记录。
- **影响 TC**：无。**调整阶段**：C6。**用户已知**：否（Gate 3 呈报，含迁移裁定请求）。
- **处置**：未决（记录格式迁移待裁定；本文件即按资源根口径生成的 C6 产物）。
- **逐字来源**：`pending-adjustments.yaml:428`

### ADJ-044 — 「14 类失败模式检查」在资源根内无权威逐项定义（C7 发现）

- **原始设计**：`.stdd/skills/build.md:308` 与 `.stdd/skills/_shared/revision-rules.md:41`「**14 类检查全量执行**，不得用占位符代替；每项须注明所用 run 的结果或明确标注未执行」；`.stdd/config.d/lite.yaml:105`（thorough 档 `failure_modes`）；`.stdd/specs/ci-integration/spec.md:48/54/62`；`stdd/cli/commands/ci.py` 的字母检查实现。
- **调整内容**：C7 编制失败模式章节时实测发现口径不一致，**本轮未修（stdd 只读）**。四处互不一致：① `build.md:308` 与 `revision-rules.md:41` 称 **14 类**；② `lite.yaml:105` thorough 档 `failure_modes` 只列 **a–l 共 12 个**字母（standard 档 `:72` 同为 12，lite 档 `:42` 为 5）；③ `ci.py` 只实现 **8 个**字母检查 `(a)(b)(d)(f)(g)(j)(k)(l)`，`(c)(e)(h)(i)(m)(n)` **无任何实现**；④ `ci-integration/spec.md:48` 称「**11 类**失败模式的确定性子集」、`:62` 称类别范围 **(a-k)**，且 `:54` 的语义与实现不符——spec 的 (b)=TC-ID 唯一性、(c)=SHALL 关键字存在、(d)=AND 子句数≤5、(e)=TC 数量≥Scenario 数量，而实现的 (b)=**范围蔓延**、(d)=**TC-ID 唯一**、(f)=THEN 含 SHALL、(g)=AND 数量。另 `spec:61` 引用的 `.stdd/templates/failure-check-report.md` **实测不存在（MISSING）**。唯一列出 a–n 全 14 个字母的是 `onboarding/bootcamp/level_3/answer/specs/payment/test-report.md:7`，属**教学示例答案而非分类定义**。
- **调整原因**：**不得为凑「14 类全量执行」而虚构 `(c)(e)(h)(i)(m)(n)` 的通过结论**——这些字母在资源根内既无权威语义定义也无 CLI 实现，任何判定都无依据。按用户「任何未执行、跳过或外部依赖未满足的检查，都不得报通过」，C7 改为**分层如实呈报**：CLI 确定性子集 8 项按选定 run 的原文逐项记；C4 已实读的语义检查（5 条经验 + 锚定缺失 + Agent CP 失败 + 跨系统不一致 + 证据覆盖结构不完整）逐项记取证；无权威定义或无实现的类别明确标注「**未执行（资源根无权威定义）**」并指向本条。
- **影响范围**：不改任何产品代码、规格、断言或触发器，**对 stdd 资源仓写入数仍为 0**。影响的是 Gate 3 报告的**措辞与可核验性**：不能声称「14 类检查全量执行通过」。已执行部分的证据不受影响——run `7cd120df` 的 `ci check-failures` 原文为 **8 通过 / 1 警告 / 0 跳过 / 1 错误、自动化检查覆盖 10/10**，**Gate 3 后续轮的新 run `dfb7aad8…` 逐项同值复现**（`gate3-followup/ci-check-failures-round3.txt`，29 行）；C4 README 记 **8 项检查完成、2 项命中、1 项观察**。属 stdd 侧待办：需该仓自己统一 build.md / revision-rules / lite.yaml / ci-integration spec / ci.py 的**类别数与字母语义**，并补回缺失的 `failure-check-report.md` 模板。
- **影响 TC**：无（不改任何断言）。**调整阶段**：C7。**用户已知**：否（Gate 3 呈报）。
- **处置**：未决（stdd 侧待办）。
- **逐字来源**：`pending-adjustments.yaml:438`

### ADJ-045 — 清理事故波及依赖树：工作树恢复未覆盖 node_modules 与 pnpm store

- **原始设计**：`design.md` 决策 1「pg 用 `npm install --prefix` 取得并经 NODE_PATH 解析，不为此跑全仓 pnpm install」；U4「前端先保证 views typecheck 和本地 vitest，如实报告」；U5 授权动作含「npm 安装 pg」；`test-report.md §9.3.3` 外部删除事故与「先护副本，再原地恢复」裁定。
- **调整内容**：Gate 3 后续轮开始时发现本机依赖树已被**同一次 C 盘清理事故**波及，而工作树恢复只覆盖了受 git 跟踪/未跟踪的仓库文件，**未覆盖被 ignore 的依赖**。实测缺口：`node_modules/pg` 与 `.pnpm/pg@8.20.0` 整个缺失（`.pnpm` 下只剩 `pg-pool@3.13.0_pg@8.20.0` 且其 node_modules 为空）；`.pnpm` **1226 个条目中 62 个 node_modules 为空**；`node_modules/.bin` 不存在；`packages/views/node_modules/.bin` 为空、typescript 链接缺失；pnpm store v10 为 4.0K（空）、v11 仅 19M，`store/v11/links/@pnpm/10.28.2/…` 缺失，导致 **pnpm 连自身版本切换都失败**（`spawnSync … ENOENT`）。
- **调整原因**：`run-selection.mjs:18` 是 ESM `import pg from "pg"`（与 `ci-provision.mjs` 的 createRequire 不同，见 ADJ-008），pg 不可解析时子进程在**模块求值阶段**即 `ERR_MODULE_NOT_FOUND`，根本到不了 parseArgs。实测后果：ADJ-042 的**首次 RED 退出码虽为 1，但失败原因是找不到 pg 而非「未知 flag 被静默忽略」，属无效 RED**，必须在依赖恢复后重取。同时 CP-SEL-002、6 条真库 selection、CP-CCF-002 的 views typecheck 全部无法执行；选定 run `7cd120df-…` 的受审输入又因 ADJ-042 改动 `scripts/aifi45-disposable` 而失效（`evidence.py:735-739`），故**必须恢复依赖后重跑整轮证据**。
- **影响范围**：不改任何产品代码、规格或断言，属**本机环境修复**。**修复手段与授权边界（须如实区分）**：U5 的字面授权是「npm 安装 pg」，但 store 本身被清空、`.bin` 与 views 的 typescript 链接同时缺失，单装 pg 无法恢复前端工具链；而 `npm install pg` 会改动受跟踪的 `package.json`/`pnpm-lock.yaml`（不允许）。故改用**项目 `packageManager` 钉住的 pnpm 10.28.2**（corepack 缓存内仍存：`C:/Users/GOBAO/AppData/Local/node/corepack/v1/pnpm/10.28.2/bin/pnpm.cjs`，`/d/tools/npm-global/pnpm` shim 因 store 链接被清而失效）执行 `pnpm install --frozen-lockfile`：**只写被 ignore 的 node_modules 与 pnpm store，受跟踪清单一行未改**。这是比 U5 字面更宽的动作，范围限于依赖目录，已在此显式申报。
- **影响 TC**：TC-SEL-002、TC-CBE-002、TC-WSD-001…005（真库 selection 依赖 runner 脚本的 pg）、TC-CCF-002（views typecheck / vitest）。**调整阶段**：Gate 3 后续轮。**用户已知**：是（U5 授权 + 本轮申报实际手段）。
- **处置**：**已处置（环境修复完成并实测验证）**。
  - `pnpm install --frozen-lockfile` → **Done in 21m31.4s，INSTALL_EXIT=0**；pg 实测 **8.20.0** 且可被 ESM import 解析；`pnpm-lock.yaml` 与 `package.json` 的 **git status 为空**。日志 `validation/gate3-followup/pnpm-install-restore.txt`。
  - 修复后重取：ADJ-042 **有效 RED**（exit 1，1/0/1，stderr `disposable runner failed: spawnSync podman ENOENT`）→ **GREEN**（exit 0，1/1/0）；`run-selection.test.mjs` 全量 **exit 0，14/14/0**；harness **exit 0，173/173/0/0/0**；`ci-scope.test.mjs` **exit 0，49/49/0**。**这三组均不依赖前端工具链，其通过结论只覆盖 node 侧。**
  - **第二阶段修复（pnpm CLI 自身，依赖装好后仍不可用）**：PATH 上的 `/d/tools/npm-global/pnpm` 是 **pnpm 11.22.0**，它按项目 `packageManager` 钉住值自动切版；切版目标 `store/v11/links/@/pnpm/10.28.2/4672a404…/` 只剩**空壳**（`node_modules/pnpm` 下 `package.json` 与 `dist` 全缺、仅存 `bin/*.cjs`，1307 个条目多为空目录），且 **`store/v11/files` 实测仅 48K**（内容寻址文件被清空），故 `spawnSync …\bin\pnpm ENOENT`。**CP-CCF-002 的命令是 Gate 2 冻结的 `pnpm --filter @multica/views typecheck`，不得改命令，只能修环境。** 处置：把空壳目录**改名隔离**为同级 `hollow-backup-20261113`（**未删除，可回退**），再在 multica 内执行 `pnpm --version` 触发 pnpm 自行从 registry 重装 10.28.2 到 v11 → 实测输出 **10.28.2、exit 0**（`pnpm-cli-restore.txt`）。随后 `pnpm --filter @multica/views typecheck` 预检 → `tsc --noEmit`、**TYPECHECK_EXIT=0、零 TS 错误**（`precheck-views-typecheck.txt`）。**未改 PATH、未装 corepack shim、未降级全局 pnpm 11.22.0、未改任何 pnpm 配置或仓库文件**；写入只发生在 pnpm 自己的 store 缓存内。外层 pnpm 11 打印的「pnpm field … ignored」WARN 属外层配置解析提示，内层 10.28.2 仍按 `package.json` 读取，且事故前同样存在，**非本轮新增条件**。
  - **残留义务（不属本条环境修复，属证据重执行）**：~~CP-CCF-002 的 views typecheck / vitest、CP-SEL-002 与 6 条真库 selection 在依赖恢复后**尚未重跑**，必须随**新 run id** 的整轮证据一并执行；**未执行前一律不报通过**。~~（**登记当时原文，保留**）→ **本轮已全部履行**：18 条命令 CP 以新 run **`dfb7aad8-7539-486b-aa59-297d57a87d1a`** 整轮重执行（`Results: 18 passed, 0 failed`，6 个一次性实例均 `released … remaining=0`，46 个真库叶子测试 fail 0 / skip 0，与旧 run 逐名一致＝零回归）；C2 全量 `pnpm typecheck --force` **10/10、Cached 0/10、exit 0、0 条 TS 错误**、`pnpm lint --force` **7/7、Cached 0/7、exit 0、0 errors**。**views 全量 vitest 重跑后为 1 failed / 6371 passed、exit 1，如实记为未通过**（失败项 `chat-window-messages.test.tsx:84` 属 HEAD 既存具名 flake，单文件重跑 4/4 exit 0；本轮报文是 `AssertionError`，与 ADJ-020 记录的超时模式不同，已区分）。**`--force` 是必需的**：不加时 turbo 报 `Cached: 10 cached / 10 total`＋`>>> FULL TURBO`，属缓存回放而非真实执行，两份日志均留存并如实区分。
  - **边界实测**：未触碰仓库跟踪文件、未连 `localhost:5432`、未操作旧 `multica-postgres` 容器、未读取或打印凭据。`D:\C_Cleanup_Backup_20261113\RESTORE.md §7` 选项 C 把 D04 标为可删缓存，**恢复稳定性确认前不清理**；三份副本中 D04 原件从未写入、`D:\multica-rescue-20261113` 无 node_modules、C: 工作树为本次修复对象。
- **逐字来源**：`pending-adjustments.yaml:448`

### ADJ-046 — 按用户裁定执行 Gate 3 approve 被 CLI 拒绝批准（major，未决＝CLI 缺陷仍在；**对本 change 的阻塞已由 ADJ-047 解除**）

- **原始设计**：`test-plan.md` §六 同次执行证据计划（**Gate 2 冻结**）22 条 check，其中 4 条 `kind=manual`；`stdd/cli/commands/gate.py:810-823`（Gate 3 必须 `--run`，`_gate3_selected_evidence` 返回 problems 即 `sys.exit(1)`）；`stdd/cli/evidence.py:1033-1034`（条数严格相等）、`:1055-1075`（`not_applicable` 分支与 manual 校验）、`:697-699`（`_manual_checks`）、`:740-770`（`confirm_manual`）；用户裁定原文「以「命令 CP 18/18 + 4 个人工 TC 未闭合」确认 Gate 3。」
- **调整内容（实测，非推断）**：按该原文执行
  `stdd gate approve 2026-11-12-fork-ci-test-evidence-trust --gate 3 --confirmed-by dialog --evidence "以「命令 CP 18/18 + 4 个人工 TC 未闭合」确认 Gate 3。" --run dfb7aad8-7539-486b-aa59-297d57a87d1a`
  → **CLI 拒绝批准，`APPROVE_EXIT=1`**，stderr 两行：「当前执行证据无效: 缺少或重复必需 check（当前运行未完成）」「Gate 3 拒绝批准：选定 run 证据不足。」（原文留存 `validation/gate3-followup/gate3-approve-refused.txt`）。**批准前无任何写入**：复跑后 `stdd gate status` 仍 **Gate 3 ⬜ pending**（Gate 1/2 保持 `2026-11-13T09:46:15` / `09:46:16`），`.stdd.yaml` 内 `grep selected_evidence` **零命中**。**这更正了 ADJ-040 的影响范围判定**：同一判据不只让覆盖指标显示 0/22，而是**直接硬阻断 Gate 3 批准**。
- **调整原因（四点，均经实读源码 + 实测解析冻结 fence 确认）**：
  1. `evidence.py:1033-1034` 要求 `len(checks) == len(plan["checks"])`，**18 条命令 CP 即使全通过也判整个 run 无效**；`gate.py:815-822` 把该 problems 作为批准前置。
  2. **无豁免出口**：实测解析 Gate 2 冻结 fence，22 条 check 的 `applicability` 取值集合**只有 `["required"]`**，4 条 manual（TC-CBE-005 / TC-TOR-004 / TC-TOR-005 / TC-CCF-003，均 `case_id=main`）全为 `required`，故 `:1055-1060` 的 `not_applicable` 分支**不适用**。
  3. **`confirm_manual` 计划级、全有或全无、一次性**：`:697-699` 取全部 required manual，`:740` 一次取全 4 条，`:761-764` 把每条 `result` **硬编码为 `"manual-pass"`**，`:767` 的 `manual.checks` 必须等于全 4 条，`:748` 拒绝静默覆盖 → **既不能只确认 TC-TOR-005，也无法记录「已审阅但未通过」或「被外部前置阻塞」**。CLI 没有表达「人工已审阅、结论为未闭合」的状态。
  4. **3 项外部前置未满足**：TC-CBE-005 需真实 CI run（**multica 推送未授权** + 管理员 PAT 未更新，本轮 **CI run 次数 = 0**）；TC-TOR-004 需 WSL AIFI-ISO 独立入口（ADJ-024 四项前置全缺）；TC-CCF-003 需管理员更新 PAT。TC-TOR-005 需用户人工逐项核对验收报告原文。**因此任何确认都等于为未执行或未通过的项断言通过**，属伪造 evidence，被用户「任何未执行、跳过或外部依赖未满足的检查，都不得报通过」与 Skill Gate 3 硬防线明文禁止。
- **影响范围**：**Gate 3 无法在本轮如实批准**；BUILD 停在 C1–C7 全部完成、`test-report.md`（538 行）与 `validation/acceptance-report.md`（482 行）及全部台账已就绪的状态，`current_phase` 仍为 `build`，**不得进入 DELIVER**。**未采取任何绕过手段**：未调用 `stdd agent confirm`（**4 项人工 TC 确认数 = 0**）、未改 stdd 仓（**本会话写入次数 = 0**，用户明令「不要再动 stdd 仓库的内容」）、未改 `test-plan.md` 或任何 Gate 1/2 manifest 项、未伪造 evidence、**未把拒绝写成通过**。`tasks.md` 14.10 **保持未勾选**。
- **影响 TC**：全部 22 个 TC 的覆盖判定 + **Gate 3 批准本身**。**调整阶段**：Gate 3 后续轮。**用户已知**：**是**（用户已给出确认原文；**拒绝执行的结果本轮如实上报，等待裁定**）。
- **处置**：**未决（阻塞项，须用户裁定）**。与其余 4 条 major 不同，本条**不能只靠「留待后续 change」消化**——它挡住的是本 change 自身的阶段推进。三条合法路径：

  | 路径 | 内容 | 需要的授权 / 动作 | 代价与诚实性评估 |
  |---|---|---|---|
  | **A** | 闭合 3 项外部前置后，一次性如实确认 4 项人工 TC，再 approve | ① multica **提交 + 推送**授权（触发真实 CI run，消耗私有库 Actions 额度）；② **管理员更新 PAT**（外部动作，AI 不得读取/创建/修改凭据）；③ **WSL AIFI-ISO 四项前置**安装（go 工具链、uid 995/gid 994、`/var/lib/aifi45/daemon-iso`、`/root/multica`），**超出 U5 现有授权**；④ 用户人工逐项核对 `acceptance-report.md` | **唯一不削弱任何义务的路径**，但 3 项均非本会话可完成；CI 真实结果未知，可能暴露新失败 |
  | **B** | 正式缩小本 change 范围，把 3 个场景移交后续 change，相应修改 plan / canonical 的 check 集或 `applicability`，重签 Gate 2 后 approve | 改 **Gate 2 冻结输入** → `--reapprove` + 非空 evidence；涉业务承诺时再加 Gate 1；旧证据须按 `revision-rules.md` §2 矩阵重跑 | **是合法的工程决策，不是伪造**：缺口以「范围外 + 已登记」形式保留。**但不得把真实义务伪装成豁免**——`not_applicable` 语义是「无覆盖义务」，而 SC-CBE-005 / SC-TOR-004 / SC-CCF-003 是真实要求，直接标 `not_applicable` 属**静默放宽规格**，须以「移交后续 change」而非「豁免」的形式落账 |
  | **C** | 修 stdd：让人工确认可记录非 pass 结论（如 `manual-blocked`），并允许带**显式未决人工项**批准 Gate 3 | 改 `evidence.py` / `gate.py` → **属 stdd 仓修订** | **根因修复**，能同时解掉 ADJ-040 与本条；但用户已明示「stdd 的项不在本次完成，我以后单独完成」，**本会话不得执行** |

- **建议（不代签、不代执行）**：若目标是**尽快让本 change 如实收口**，**B 是唯一在本会话授权边界内可完成的路径**，且必须走 Gate 2 重签、把 3 个场景以「移交后续 change」落账而非标豁免；若目标是**不削弱任何已声明义务**，则只能走 **A**，本 change 保持 `build` 在途直到外部前置闭合。**C 是长期正解但不在本次范围**。**AI 不自行选择，等待用户裁定。**（原文保留）
- **用户裁定（2026-11-13，原文）**：「选B，将需要移交到后续change的项记录在案，供以后能找回修订。」→ 选择 **B 路径**，并要求移交项可检索。执行结果见 **ADJ-047**：计划分母 22 → 19、3 个场景移交并逐字留存、Gate 2 于 `2026-11-13T18:33:41` 以 `--reapprove` + 上述原文重签。**本条 `resolved` 仍为 false**：被拒绝的是 CLI 的表达能力缺陷（`manual-pass` 硬编码 + 全有或全无），该缺陷未修；B 只是让本 change 在**不伪造确认**的前提下继续推进。
- **逐字来源**：`pending-adjustments.yaml:458`

### ADJ-047 — 执行范围收窄：3 个外部前置场景移交后续 change，计划分母 22 → 19（major，已处置）

- **原始设计**：Gate 2 冻结的 `test-plan.md` §六 证据计划 22 条 `required` check（18 command + 4 manual：TC-CBE-005、TC-TOR-004、TC-TOR-005、TC-CCF-003）；`canonical/specs/code` 的 SC-CBE-005 / SC-TOR-004 / SC-CCF-003 / SC-TOR-005 共同构成本 change 的验收面。
- **调整内容（实测）**：
  1. `test-plan.md` §六 fence **移除 3 条 manual check**（TC-CBE-005 / TC-TOR-004 / TC-CCF-003），分母 **22 → 19**（18 command + 1 manual TC-TOR-005）。
  2. 这 3 个 TC 的**原定义在原位以 HTML 注释保留**，机器不解析（`ci.py:733-774` 的 `_visible_test_plan_lines` / `tc_definition_ids` 跳过注释与 fence）；实测 `tc_definition_ids` = **19**，因此 `check_tc_coverage` 的分母与分子都是 19，**不会出现「移交项被算成 100%」的虚高**。
  3. 新增 `test-plan.md` §七「已移交后续 change 的测试案例」可见表格；§三 矩阵与 §五 优先级同步标注移交。
  4. **`canonical/specs/code` 的 3 个 Scenario 保持原样、未删除**：它们是后继 change 的验收对象，本 change 只是不签收；删除会在 DELIVER 合并基线时静默抹掉真实要求。
  5. 新建 **`validation/handoff/handoff-to-successor-change.md`**：逐字保留 3 个 Scenario 与 3 个 TC 定义（已用脚本比对原文一致）、缺失前置、现状、复现命令、后继 change 的 5 条入口判据与取回校验清单。
  6. **Gate 2 于 `2026-11-13T18:33:41` 以 `--reapprove` + 用户原文重签**，`stdd gate status` 无 stale 标记。
- **为什么不能标 `not_applicable`**：`finish_run`（`evidence.py:666-671`）确实支持把非 required 项记成 `not_applicable`，但 `check_tc_coverage`（`ci.py:1174-1186`）用 `tc_definition_ids` 作为分母、用计划中的 TC 集合作为分子 —— 只要 TC 定义仍可见，标 `not_applicable` 就会让覆盖显示 **22/22 = 100%**，把 3 项移交伪造成已覆盖。故必须同时移出**定义**与**check**，才是诚实的收窄。
- **影响范围**：本 change 验收范围缩为 19 条 TC；3 个场景不计入分母、不作通过声明。已实现代码与测试**不回退**，只是其外部前置部分不在此签收。**副作用**：`test-plan.md` 变更使旧 run `dfb7aad8-7539-486b-aa59-297d57a87d1a` 按 `_materials_match`（当前文件摘要 ≠ run 留存快照）**失效**，必须用新 run 重跑 18 条 command CP；新 run 的 `checks` 为 19 条（18 pass + 1 manual）。
- **仍未完成（不得误读为已通过）**：① 18 条 command CP 需在新 run 中重跑并取得同 run 的 `ci check-failures` 结果；② TC-TOR-005 需用户对 `validation/acceptance-report.md` 的核对原文，才能 `agent confirm`（本轮确认数仍为 **0**）；③ Gate 3 需用户按新口径重新确认。
- **影响 TC**：TC-CBE-005 / TC-TOR-004 / TC-CCF-003（移交出分母）；其余 19 条留在分母内。**调整阶段**：Gate 3 后续轮。**用户已知**：**是**（B 路径由用户裁定）。
- **处置**：**已处置（`resolved: true`）**。含义仅限「范围收窄与移交记录已完成」；**不是**「3 个场景已通过」，**不是**「Gate 3 已批准」。
- **逐字来源**：`pending-adjustments.yaml` 末条 `ADJ-047`

### ADJ-048 — `agent confirm` 抛 `KeyError: 'cp'`，人工结论无法写入（major，未决，**当前即时阻塞项**）

- **触发**：用户给出人工核对原文「已核对验收报告 §0/§2/§9.3，未发现未执行项被标为通过」后，按其原文执行
  `stdd agent confirm ci-backend-environment --change 2026-11-12-fork-ci-test-evidence-trust --run add97e96-1676-4191-ae65-2ebd6524d585 --statement "已核对验收报告 §0/§2/§9.3，未发现未执行项被标为通过"`
  → **`KeyError: 'cp'`**，`CONFIRM_EXIT=1`。
- **缺陷位置（实读源码）**：`evidence.py:20` 定义 `_CHECK_FIELDS = ("tc","case_id","requirement","scenarios","cp","kind","applicability")`；`confirm_manual` 在 `:761-764` 用 `**{key: item[key] for key in _CHECK_FIELDS}` 构造人工 check。而 manual 计划项按本 change 的约定**没有 `cp`**（`test-plan.md` §六 明写「manual 不绑定 CP」，Gate 2 与证据计划解析均接受该形状）→ **任何** manual 确认都会崩在这里，不是本 change 的数据问题。
- **同源历史**：ADJ-036 是同一类缺陷（`agent.py:206` 对 manual 条目 `KeyError: cp`），由用户自行改为 `item.get("cp")`。本条是 `evidence.py` 里的**第二处实例**，当时未被同一修法覆盖。
- **未产生任何写入**：崩溃发生在 `_publish` 之前；复核 `tc-evidence.json` 仍为 **18 条 checks、`manual` 为 null**，无第二份 run，`test-plan.md` 未改。
- **建议修法（一行，供用户在 stdd 侧执行；本会话按用户明令不写 stdd）**：
  ```python
  # stdd/cli/evidence.py:761-764
  record["checks"] = [*record.get("checks", []), *({
      **{key: item.get(key) for key in _CHECK_FIELDS},
      "result": "manual-pass", "channel": channel, "statement_sha256": digest,
  } for item in manual)]
  ```
  `item.get("cp")` 得到 `None`；消费者 `:1053` 用 `check.get(key) != planned[key]` 比较，两侧同为 `None` 即相等，不影响校验。**若 `finish_run` 的 `not_applicable` 分支（`:666-671`）也用同一写法，建议一并改为 `item.get(key)`**（本 change 计划无 `not_applicable` 项，当前路径不受影响）。
- **影响范围**：19 条 check 缺第 19 条（TC-TOR-005），`gate approve --gate 3` 必然继续被 `gate.py:815-822` 拒绝；**归档与推送均未执行**。代码已提交 `371e53167`（49 文件），工作树干净；提交后重跑 `ci check-failures` 仍报 18 ≠ 19（输入校验通过，说明提交未改冻结输入）。
- **未采取的绕过**：未改 stdd 仓（本会话写入数 **0**）、未手写或补 `tc-evidence.json`、未伪造人工确认、未把 18/19 说成通过。
- **二次实测（2026-11-13，用户修复 `:762` 后）**：`agent confirm` **成功写入**——run 变为 **19 条 checks**、`manual = [["TC-TOR-005","main"]]`、manual check 含 `cp: null` 与 `statement_sha256`；随后同 run 的 `ci check-failures` 报「当前执行证据无效: **`'cp'`**」，暴露**第二处同源点** `:1053`：`any(check.get(key) != planned[key] for key in _CHECK_FIELDS)` 对 manual 计划项取 `cp`。**仍需一行 `planned.get(key)`**；`:669`/`:679`（`finish_run`）为潜在同源点，本计划不可达。**人工确认不需要重做**——写入已完成，只差校验端修好。
- **逐字来源**：`pending-adjustments.yaml` 末条 `ADJ-048`

---

## 修订需求清单（后续迭代输入）

> 口径：本节只列**需要什么修订、由谁裁定、走哪道 Gate**，不代签、不代执行。依据 `.stdd/skills/_shared/revision-rules.md` §2 矩阵：仅新增调整记录 → 仅重审 Gate 3；改设计/验收/测试选择 → Gate 2（涉业务承诺再加 Gate 1）；改范围/安全不变量/已接受风险 → Gate 1+2 且旧证据须重跑。
>
> **本节即「不在本 change 完成的 multica / tools 修订」的可检索留痕**（用户 2026-11-13 明确要求「记录在案，以后可以找回以便新开 change」）。新开变更时按 ADJ 编号取 `pending-adjustments.yaml` 的逐字四字段 + 本节的「需要的修订 / 触发 Gate」，即可还原背景、缺口与授权边界。**§C 的 stdd 侧条目本会话一律不修**（用户：「stdd 的项不在本次完成，我以后单独完成」），只留背景与问题点。

### A. multica 产品侧（须用户裁定是否纳入本 change 或另开变更）

| 调整 | 需要的修订 | 触发 Gate | 现状 |
|------|-----------|----------|------|
| ADJ-042 | `run-selection.mjs` parseArgs 补最终 else 抛 unknown argument（与 `ci-provision.mjs:132`、`ci-evidence.mjs:162`、`tools-access.mjs:66` 同口径）+ 一条「拼错 flag 名」断言 | 行为收紧、不改锁定场景字面 → **用户已裁定纳入本 change（Gate 3）** | **已修完并验证**：+3 行代码 / +1 测试函数；有效 RED exit 1 → GREEN exit 0；回归 14/14、173/173、49/49 全 exit 0；CUSTOM.md #333 登记。**连带**：受审输入变更 → 须以新 run id 重跑 18 条命令 CP，**本轮已执行**（新 run `dfb7aad8-7539-486b-aa59-297d57a87d1a`，18 passed / 0 failed；旧 run `7cd120df…` 已失效不得沿用） |
| ADJ-029 | 若要求 `run-selection.mjs:79-82` 的不可解析行由静默 continue 改为硬失败，须**修订 SC-SEL-002**（其明文要求沿用旧判定、输出行逐字不变、既有断言不被改弱），并复核 `run-selection.test.mjs` | **Gate 2 重签** | **本轮不做**（有规格依据）；留待新开 change |
| ADJ-028 | 若要求 reservation 并发安全，须先裁定 `FOR SHARE` 还是 FK；加 FK 违反 `648_cr_execution_control.up.sql:54-66` 明文「不新增 FK」，须**同步修订 SC-WSD-005 与 648 的 no-new-FK 约束** | **Gate 2 重签**（涉安全不变量则 Gate 1+2） | **本轮不做**：只追加两行英文注释，SQL 与锁语义一行未改；留待用户裁定后新开 change |
| ADJ-031 | 若要消除扫描器盲区（`os.LookupEnv`、内联 `if cli := os.Getenv(...); cli == ""`、switch/case、`if len(x)==0`、`t.SkipNow()`），须**修订 SC-CBE-004** 的 when 范围 | **Gate 2 重签** | **明确不做（用户已采纳）**：G1「CI 绿 ⇒ 声明的测试真跑过且无未申报 skip」由 `ci-evidence.mjs` 对 `go test -json` skip 事件的**运行时对账**承重，与测试怎么写无关；扫描器只是提前提示，扩围属规格变更且收益重复。仓库实测 119 文件 0 违规 |
| ADJ-030 | **无需修订**：唯一调用点 `run-selection.mjs:141-150` 总传入 reconciliation，为不可能状态加守卫属多余错误处理 | 无 | 明确不做，仅记录 |
| ADJ-018 | multica `CUSTOM.md` 四数基线表补行（台账欠债，非产品行为） | 无（台账） | **本轮不补**（三点理由沿用）；C1 已更正枚举三处并留痕 |
| ADJ-024 | 若要闭合 SC-TOR-004 的隔离半句：按 `wsl2-aifi45-v1` 在 WSL 内装 Go ≥1.26、建 uid 995/gid 994 与 profile 根，真实运行 `TestChannelIsolation` 并把命令/退出码/通过数记入验收报告（每项通过数 ≥1、skip 为 0） | 无（规格已接受 UNCOVERED）；闭合后仅重审 Gate 3 | **本轮不做（用户已采纳「保持 UNCOVERED」）**：规格明文「任一项不能执行时 SHALL 如实列为未覆盖，不得以同 uid 对照代替」，如实标注即合规。**补偿控制为零这一事实须持续呈报**，owner = 隔离独立入口，留待新开 change |
| ADJ-006 / ADJ-020 | presenter flake 与 views 既有 flake 的定性 | 无（U4 不扩大范围） | **本轮不做**：先报告再裁定，留待真实 CI run 定性 |

### B. 记录仓 / 受审输入侧（编辑即须重签，本轮无授权）

| 调整 | 需要的修订 | 触发 Gate | 现状 |
|------|-----------|----------|------|
| ADJ-032 | `.canon-index.yaml:6`/`:8` 的 logical_path 指向不存在的聚合 spec 文件，实际为 5 个 per-capability 文件；须与 ADJ-015 一并作为 CLI 缺陷处理，或取得重签授权后同步修订索引 | 该文件在 **Gate 2 input_manifest** 内 → 编辑须 `--reapprove` | 未改（功能惰性：generate 走 glob、verify 只校 proposal、Gate 2 哈希原始字节） |
| ADJ-033 | 14 个 agent CP 的 description 在第 61 字符词中截断；须走 CLI 缺陷修复，或取得重签授权后手工同步（如 R5 对 CP-WSD-005 的做法） | 5 个 agent spec 在 **Gate 2 input_manifest** 内 → 须重签 | 未改（action/assertions intact，CP 语义未损） |
| ADJ-043 | 是否把 `pending-adjustments.yaml`（登记时 **45 条**，现 **47 条**）迁移为 `pending-adjustments.md`；迁移属记录搬移 | 不在 Gate 1/2 manifest → **仅 Gate 3** | 未迁移、未双写、未删除；本 `.md` 已按资源根口径生成 |
| ADJ-047 | `test-plan.md` §六 证据计划移除 3 条 manual check、分母 22 → 19；3 个 TC 定义原位注释化 + §七 移交表 | 该文件在 **Gate 2 input_manifest** 内 → **用户已裁定 B 并授权**，`2026-11-13T18:33:41` 以 `--reapprove` 重签 | **已执行并重签**；`canonical` 场景未删；移交包见 `validation/handoff/handoff-to-successor-change.md`。旧 run 因此失效，须用新 run 重跑 18 条 CP |

### C. stdd 资源仓侧（本会话禁写，须由该仓自己的变更处理）

| 调整 | 缺陷 | 严重度 | 现状 |
|------|------|--------|------|
| ADJ-038 | Gate 2 审批路径不执行 (l) 锚定等级检查，与 `spec.md:126-134` 声明不一致；L3 在 financial=true 下三次通过 Gate 2 | **major** | 未修；本 change 以真实 L4 锚定满足要求，不依赖该缺陷修复 |
| ADJ-040 | `evidence.py:1033-1034` 严格条数相等：18≠22 使整个 run 无效、覆盖归零，无法反映已通过的 18 个命令 CP | **major** | 未修；Gate 3 同时呈报 18/18 与 0/22 两个数字及含义。**影响范围已被 ADJ-046 更正：同一判据经 `gate.py:815-822` 还硬阻断 Gate 3 批准，不止是指标** |
| **ADJ-046** | **`gate.py:810-823` 把上述条数判据作为 Gate 3 批准前置；`evidence.py:761-764` 把 4 条人工项的 `result` 硬编码为 `manual-pass` 且 `:740/767` 全有或全无 → CLI 无法表达「人工已审阅但未闭合」，导致「18/18 命令 CP 通过 + 4 项人工未闭合」这一真实状态无法被批准** | **major** | **未修**（缺陷仍在，`resolved: false`）。本会话按用户裁定原文执行 approve 被拒（`APPROVE_EXIT=1`），未绕过、未伪造确认、未改 stdd。**对本 change 的阻塞已由用户裁定的 B 路径解除**（ADJ-047 已处置），但 CLI 表达能力缺陷仍需在 stdd 侧修复 |
| ADJ-041 | `ci.py:874-906` 检查 (b) 四处口径缺陷（HEAD~1 混入上一提交、未跟踪文件不可见、`--stat` 截断路径、判据不匹配 multica 真实路径），且汇总行数字被当成路径 | minor | 未修；该 WARN 不作为范围蔓延证据，真实范围已手工核对 49 文件 |
| ADJ-037 | `evidence.py:806` 在 kind 过滤前解引用 `item["cp"]`，manual+pytest 混合计划会崩 | minor | 未修；本轮 0 条 pytest check，路径不可达 |
| ADJ-015 | `stdd canon generate --type spec` 被忽略，spec human view 只在 `--all` 分支生成 | minor | 未修；与 ADJ-032 同源 |
| ADJ-044 | 「14 类」无权威逐项定义：build.md:308 / revision-rules.md:41 称 14，lite.yaml:105 只列 a–l（12），ci.py 只实现 8 个字母检查，ci-integration spec.md:48 称 11 类且 :54 字母语义与实现不符，:61 引用的 failure-check-report.md 模板缺失 | minor | 未修；C7 不虚构 (c)(e)(h)(i)(m)(n) 的通过结论，分层如实呈报并标注「未执行（无权威定义）」 |
| ADJ-036 | `agent.py:206` 对 manual 条目抛 `KeyError: cp` | major | **已由用户自行修复为 `item.get("cp")`**，本会话只读核实、写入数 0 |
| **ADJ-048** | **`confirm_manual`（`evidence.py:761-764`）用 `item[key]` 取 `_CHECK_FIELDS`（含 `cp`），而 manual 计划项无 `cp` → 任何人工确认都抛 `KeyError: 'cp'`** | **major** | **未修；本会话按用户核对原文执行 `agent confirm` 实测崩溃（`CONFIRM_EXIT=1`），无任何写入。修法一行：`item.get(key)`（ADJ-036 同源）。本会话对 stdd 写入数 0，等待用户处理** |

### D. 外部前置 / 授权侧（不是代码修订，须外部动作或单独授权）

| 调整 | 缺什么 | 严重度 | 边界 |
|------|--------|--------|------|
| ADJ-025 | ~~tools pin `e52b8081f159` 不在 origin~~ **已闭合**：用户授权后已推送，`git ls-remote origin refs/heads/main` = `e52b8081f159d581bf62f82447c76f818fc52426`。**仍缺**：multica 推送授权（触发真实 CI）与管理员 PAT | **major** | 推送只发送该 1 个 commit；tools 的 ~~5 个~~ **6 个**未提交改动与 `.crctl/` 推送前后逐字一致，未夹带（**计数更正**：`tools-push-verified.txt:16-17` 实测 `git status --porcelain | wc -l` = **6**，5 是 S2 当时的旧值）；不提前报绿。**更正**：原写「先在 checkout 步失败」，实测可达性诊断步在 tools checkout 之前（`validation/gate3-followup/pin-reachability-order.txt`），故用户要求的「前移」**已满足，本轮未改 ci.yml** |
| **ADJ-046** | **Gate 3 批准被 CLI 拒绝**：4 项人工 TC 中 3 项的外部前置（真实 CI run / WSL AIFI-ISO / 管理员 PAT）未满足，而 CLI 只能全有或全无地写 `manual-pass` | **major** | **本会话不得确认任何一项**（确认即为未执行项断言通过）。**用户已裁定 B 路径**（原文：「选B，将需要移交到后续change的项记录在案，供以后能找回修订。」）→ 3 项移交后续 change（ADJ-047），本 change 不再签收；路径 A 的授权与路径 C 的 stdd 修订均未执行 |
| ADJ-024 | WSL AIFI-ISO 独立入口的 4 项前置缺失 → SC-TOR-004 **隔离半句 UNCOVERED** | **major** | U5 只授权启动 WSL，不等于授权其余前置；TC-TOR-004 不得确认。**用户已采纳保持 UNCOVERED**，详见 §A |
| ADJ-005 | tools 仓 `rules.json` 的 show 白名单缺口（跨仓契约，范围外） | **major** | **用户已采纳「不放宽白名单、不排除这 6 项」**；契约归属待裁定，移交后续 change，详见 §E |
| ADJ-002 / 003 / 007 | 证据留存可选参数、规格未指定载体的落地选择、未定性失败（待真实 CI 定性） | minor | 均依赖 TC-CBE-005 的真实 CI run |
| ADJ-006 / 020 | presenter flake 定性、views 既有 flake | minor | U4：不扩大范围，先报告再裁定 |
| ADJ-009 | 规格条款字面不可同时成立（日志 mask ≠ 文件不含口令），R1 已裁定收敛到日志与 handle | minor | 用户已知（R1）；TC-CBE-001 按修订后口径验证 |
| ADJ-019 | S12 `new_tests=0`，偏离长程约束 #3 | minor | Gate 3 知悉；不伪造新增测试数 |

### E. tools 仓侧（跨仓契约；本轮唯一写入是推送已授权的 commit，不改任何契约）

**ADJ-005 — controlled-shell `show` 白名单缺口（major，移交后续 change）**

- **缺口位置**：`tools/skills/shared/controlled-shell/rules.json` 的 `show` 条目。实测其 `shapes` 只有 2 条，均锚定 `^[0-9a-f]{40}:change-requests/…`：一条授予 `review-annotations/(requirement|sdd|dev-plan|code)\.yml`，一条授予 `_backlog\.yml`、`_history\.yml`、`cr\.md`；`callers: ["system-orchestrator"]`；顶层另有 `forbiddenFlags: ["-c","-C","--exec","--upload-pack","--receive-pack","--config-env"]`。
- **未授予的形状**：`test-report.md`、`trace.tests*`、`--name-only --format=`。
- **重新 pin 不能修复**：实测 pin `e52b808` 与当时的 `origin/main` `f774ffb` **两个修订的 show 都是同样 2 条 shape**，都不含上述路径。故「把 pin 换成 origin 上已有的 commit」这条路无效——本轮推送 `e52b808` 也**不改变**该缺口。
- **受影响的 6 项 multica 测试**（整包基线暴露，首个报 `FORBIDDEN_SUBCOMMAND: git show … test-report.md`）：`TestProposedSnapshotReadShapes`、`TestM26B2TestFactsPayload`、`TestM26B2TestFactsPreserveFailures`、`TestM26B4ScanEmitsIndependentTestEvent`、`TestM26B4ScanTestOnlyAndReviewOnly`、`TestM26B4CollectorKeepsBothReviewStages`。
- **掩盖机制（真正的病灶）**：`crevents_test.go` 在 `MULTICA_CONTROLLED_SHELL_RULES` 缺失时**回落内联 fixture**（fixture 已含这些形状），本机因该变量指向真实 `rules.json` 才暴露；**CI 目前被掩盖而通过**——正是本 change 要消灭的「未验证变绿」。
- **待裁定的唯一问题**：daemon test-facts 所需 `git show` 形状的**权威归属**是 tools 的 `rules.json`，还是 multica 的内联 fixture？
- **两条候选路径（本轮均不执行）**：① 权威在 tools → 在 **tools 仓新开 change** 扩 `show` 白名单；这是**安全控制**变更（controlled-shell 限制任意 git 读写），影响**所有 CR 操作**的攻击面，须走该仓自己的评审与门禁，不得为让测试变绿而削弱。② 权威在 multica → 改 multica 测试索取的形状，并让 fixture 回落**硬失败或显式标注 fixture 模式**，使 6 项诚实地红后再定性。
- **明确不做（用户已采纳）**：不放宽 tools 白名单来让测试变绿；不把这 6 项排除出 CI；不在本 change 注入 `MULTICA_CONTROLLED_SHELL_RULES`（S13 从未打算设置该变量，fixture 回落属既有上游行为）。
- **触发 Gate**：路径 ① 属 tools 仓自己的流程；路径 ② 若改测试索取形状 → multica 侧 **Gate 2 重签**。
- **本轮对 tools 仓的全部写入**：`git push origin e52b808…:refs/heads/main`（用户明确授权）。该 commit 是 OldBoy405 本人 2026-11-10 的 `feat(trusted-verdict): sign the effect and the frozen command digest in verdict v2`，5 文件 260 插入 10 删除，**不含任何 controlled-shell 契约修改**。tools 的 5 个未提交改动（`AGENTS.md`、`CUSTOM.md`、`merge-effects.mjs`、`golden/crctl-detail/workspace-inspect.json`、`merge-effects.test.mjs`）与未跟踪 `.crctl/` **推送前后逐字一致，未触碰、未夹带**。

---

## Gate 3 呈报要点

1. **两个数字必须同时呈报，不得互相冒充**：命令 CP **18/18 通过**（run **`dfb7aad8-7539-486b-aa59-297d57a87d1a`**，`tc-evidence.json` 18 条全 pass、inputs 823、报告已生成）；CLI **TC 覆盖 0/22**（4 项 manual 未确认 → 严格条数相等使整个 run 结构上不完整）。verify `VERIFY_EXIT=1` 源于 **REVIEW_PENDING，不是 CP 失败**。**旧 run `7cd120df…` 已失效不得沿用**（ADJ-042 改动受审输入 + 依赖环境重建），本轮以新 run id 整轮重执行。
2. **4 个 manual TC 一律未确认**：TC-CBE-005（需真实 CI run；tools pin 前置已闭合，仍缺 **multica 推送授权**与**管理员 PAT**）、TC-TOR-004（WSL 隔离半句 UNCOVERED，用户已裁定保持）、TC-CCF-003（需管理员更新 PAT）、TC-TOR-005（验收报告已生成，人工审阅留痕由报告 + Gate 3 确认原文承担）。**`confirm_manual` 是计划级、全有或全无、一次性**（`evidence.py:740/745-748/761-764`），`result` 固定写 `manual-pass`，**确认即同时断言 4 项通过，不得为凑覆盖伪造，也不存在单独确认某一项的路径**。**本轮不执行任何 `agent confirm`。**
3. **5 项 major 未决**：ADJ-005（tools show 白名单）、ADJ-024（WSL 隔离 UNCOVERED）、ADJ-038（Gate 2 不执行锚定检查）、ADJ-040（覆盖归零口径）、**ADJ-046（Gate 3 approve 被 CLI 拒绝批准）**。**16 项 minor 未决**（含 ADJ-043 记录格式、ADJ-044 分类口径）见汇总表。**ADJ-025 已由用户授权推送 `e52b808` 而闭合，从 major 未决移出**；~~4 条 major 全部属外部前置或 stdd/tools 侧，**用户已裁定不在本 change 完成**~~（**原文保留，已被 ADJ-046 更正**）→ 前 4 条确属外部前置或 stdd/tools 侧、用户已裁定不在本 change 完成，**但 ADJ-046 性质不同：它阻塞本 change 自身的阶段推进，不能只靠「留待后续」消化，须用户在 A/B/C 三条路径中裁定**。
4. **已修复并验证**：ADJ-027（CRCTL_PATH 别名 → Fatal，真库两条件各一次 + 变异 DETECTED + 原字节还原）、ADJ-034（pin ref 断言加强，四步 RED/GREEN + 变异证明）、ADJ-035（真实 L4 锚定 + Gate 1/2 依次重签）、ADJ-036（用户侧修 stdd）、ADJ-039（esbuild 修复后全量 typecheck exit 0）、**ADJ-025（推送 e52b808，三处实测同值 + 未夹带 6 处改动；「前移」要求经实测已满足，ci.yml 未改）**、**ADJ-042（parseArgs 补最终 else，+3 行 / +1 测试函数，有效 RED→GREEN，回归 14/14、173/173、49/49）**、**ADJ-045（依赖树与 pnpm CLI 两阶段环境修复，残留义务已随新 run 履行）**。**ADJ-030 / ADJ-031 属「已处置＝明确不做」，不是缺口已消除。**
5. **未执行的检查必须标 NOT EXECUTED / SKIPPED 并写边界原因**：`make test`（`ensure-postgres.sh:71-72` 走 docker compose 连 localhost:5432，违反一次性实例边界）、`bash scripts/check.sh`（`:119`/`:129` 会启动 backend+web）、4 个 Linux-only daemon 文件本机从未编译、TC-CBE-005 / TC-CCF-003 / TC-TOR-004 的外部前置。**`stdd canon verify` 2/2 与 dry-run 可预览不代表业务测试已执行。** **另须单列「已执行但未通过」**：views 全量 vitest 本轮 **1 failed / 6371 passed（6372）、exit 1**，失败项 `chat-window-messages.test.tsx:84` 经名字与行号证明属 HEAD 既存 flake 成员（ADJ-020），单文件重跑 **4/4 exit 0**；**本轮报文是 `AssertionError`，与 ADJ-020 记录的超时模式不同，不得套用旧结论**；按 U4 **未扩大范围**（未加 retry / 未调超时 / 未 skip / 未改上游测试）。**turbo 缓存回放不算执行**：不加 `--force` 时 typecheck/lint 报 `Cached: N cached / N total`＋`>>> FULL TURBO`，本轮已用 `--force` 取得 Cached 0 的真实执行。
6. **C4 失败模式**：8 项检查全量执行，**2 项命中**（EXP-2026-0002 已声明局限：`execution_control_reservation.go:88-96` 非锁读，函数内 `pg_advisory|Lock|FOR UPDATE` 命中 0；EXP-2026-0004 继承缺口：`provision.mjs createDisposableDatabase` 孤儿受 job service-container / podman teardown 约束），**1 项观察**（`run-selection.mjs:82` 既有静默 skip，SC-SEL-002 要求不变；且 `selections.json` 全部条目当前无 `expected`，新 fail-closed 路径尚未激活）。**另：不得声称「14 类检查全量执行通过」**——资源根内「14 类」无权威逐项定义（build.md/revision-rules 称 14、lite.yaml thorough 只列 a–l 共 12、ci.py 只实现 8 个字母检查、ci-integration spec 称 11 类且字母语义与实现不符、引用的报告模板缺失），故 `(c)(e)(h)(i)(m)(n)` 一律标注「未执行（无权威定义）」，见 ADJ-044。
7. **计划外守卫不计入 TC 分子**：三批分开如实计数——ADJ-026 的 **4 个**（含 TC-SEL-004 的 1 个）、C1 两条 MAJOR 修复合计 **1 个**（ADJ-027 的 1 + ADJ-034 的 0）、Gate 3 后续轮 ADJ-042 的 **1 个**。harness 演进 **171 → 172 → 173**，`run-selection.test.mjs` **13 → 14**。TC 覆盖分子仍按 test-plan 的 22 条计，**这些守卫一个都不顶替既有 TC**。
8. **记录格式裁定请求（ADJ-043）**：技能层与资源根都自称 3.0.7 但口径冲突，本轮按资源根生成 `.md`、保留既有 `.yaml` 不双写；**是否迁移约 90KB 台账请用户裁定**。
9. **一次性实例与安全边界已守住**：运行前后容器清单 diff **IDENTICAL**，两个旧容器始终 Exited，未连 localhost:5432、未操作旧 multica-postgres 容器、未读取或打印任何凭据、未改仓库 secret、未部署。**本会话对 stdd 资源仓写入数 0。**
10. **Gate 3 不自动授权 Git 提交、推送或部署**；记录仓存在大量他人未提交改动，**不清理、不混入**。**multica 本轮未提交、未推送、未部署**（49 个文件仍全在工作区：22 `M` + 27 `??`）。**tools 的推送是独立取得的显式授权且已执行**（用户原话「ADJ-025 授权执行推送 e52b808」），**只发送该 1 个 commit**，该仓 6 处既有未提交改动推送前后逐字一致、未夹带；**该授权不延伸到 multica，也不延伸到 tools 的其他改动**。
11. **用户对本轮 Gate 3 的确认口径（原文）**：「以「命令 CP 18/18 + 4 个人工 TC 未闭合」确认 Gate 3。」→ 确认的是**这两个数字并存的事实**，**不是**把 0/22 覆盖判定改写成通过，也**不是**授权提交/推送/部署。同轮裁定：「ADJ-042 纳入本 change。」「stdd的项不在本次完成，我以后单独完成」「其他的项都采纳你的建议，不在本change完成的multica和tools仓库的修订记录在案，以后可以找回以便新开change」→ 取回点为本文 **§A / §D / §E**。**本 Agent 对 stdd 资源仓写入数 = 0。**
12. **URL 纪律**：本轮**未调用任何需要 URL 的工具**；全部网络操作只有 `git push`/`ls-remote` → 已核实的 `https://github.com/OldBoy405/AI-First-tools.git`，以及 pnpm 自行从官方 `https://registry.npmjs.org/` 重取被掏空的切版包。**未替换任何地址为 routify 等临时代理，未改任何 registry 或代理配置。**
13. **⛔ Gate 3 实际状态：approve 已执行但被 CLI 拒绝批准，Gate 3 仍 pending（ADJ-046，major，未决）**。按第 11 点的用户原文执行 `stdd gate approve … --gate 3 --confirmed-by dialog --evidence "以「命令 CP 18/18 + 4 个人工 TC 未闭合」确认 Gate 3。" --run dfb7aad8…` → **`APPROVE_EXIT=1`**，stderr「当前执行证据无效: 缺少或重复必需 check（当前运行未完成）」「Gate 3 拒绝批准：选定 run 证据不足。」（`validation/gate3-followup/gate3-approve-refused.txt`）。**批准前无任何写入**：`gate status` 仍 **Gate 3 ⬜ pending**，`.stdd.yaml` 无 `selected_evidence`。**根因**：`gate.py:815-822` 把 `evidence.py:1033-1034` 的条数判据作为批准前置；冻结计划 22 条 check 的 `applicability` 实测**全为 `required`**（无豁免出口）；`confirm_manual` 全有或全无且 `result` 硬编码 `manual-pass`（无法记录「已审阅但未闭合」）。**故「18/18 + 4 项未闭合」这一真实状态在现行 CLI 下无法被批准**——用户的确认意愿已如实记录，但**流程未通过，不得以文档生效代替 Gate 通过**。**未采取任何绕过手段**：未调用 `agent confirm`（确认数 0）、未改 stdd（写入数 0）、未改 `test-plan.md` 或任何 Gate 1/2 manifest 项、未伪造 evidence。`tasks.md` 14.10 **保持未勾选**，`current_phase` 仍 `build`，**不得进入 DELIVER**。**三条合法路径（A 闭合外部前置 / B 缩小范围并重签 Gate 2 / C 修 stdd）与建议见 ADJ-046 详细说明，等待用户裁定，AI 不自行选择。**
14. **✅ 用户已裁定 B 路径并已执行（ADJ-047，major，已处置）**：用户原文「选B，将需要移交到后续change的项记录在案，供以后能找回修订。」→ 已执行：① `test-plan.md` §六 分母 **22 → 19**（18 command + 1 manual TC-TOR-005），3 条 manual check 移除；② 3 个 TC 定义**原位 HTML 注释保留**（实测 `tc_definition_ids` = 19，`check_tc_coverage` 分母同样 19，**不会把移交项算成 100%**）；③ `canonical/specs/code` 的 3 个 Scenario **未删**；④ 新建 `validation/handoff/handoff-to-successor-change.md`（3 个 Scenario 与 3 个 TC 定义已用脚本逐字比对，取回点明确）；⑤ **Gate 2 于 `2026-11-13T18:33:41` 以 `--reapprove` + 用户原文重签**，`gate status` 无 stale。**随之而来的硬约束**：`test-plan.md` 变更使旧 run `dfb7aad8…` 按 `_materials_match` **失效**，18 条 command CP 必须在**新 run** 中重跑，并与同 run 的 `ci check-failures` 配对；**TC-TOR-005 仍需用户对验收报告的核对原文**才能 `agent confirm`（本轮确认数仍为 0）；**Gate 3 尚未批准**，不得因范围收窄就宣称通过。
15. **⛔ `agent confirm` 被 stdd 缺陷挡住（ADJ-048，major，未决，当前唯一即时阻塞）**：用户已给出人工核对原文「已核对验收报告 §0/§2/§9.3，未发现未执行项被标为通过」，按其原文执行 `stdd agent confirm … --run add97e96…` → **`KeyError: 'cp'`（`evidence.py:762`）、`CONFIRM_EXIT=1`**。根因：`_CHECK_FIELDS` 含 `cp`，`confirm_manual` 用 `item[key]` 强取，而 manual 计划项按约定没有 `cp` —— 与 ADJ-036 同类，但在另一个文件。**无任何写入**（run 仍 18 条、`manual` null）。**代码已提交 `371e53167`（49 文件，工作树干净）**；提交后 `ci check-failures` 仍报 18 ≠ 19（输入校验通过）。**归档与推送均未执行**。修法一行 `item.get(key)`，由用户在 stdd 侧执行；本会话对 stdd 写入数 **0**。
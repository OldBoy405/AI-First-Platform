# 设计调整记录（修订需求，供后续迭代输入）— 2026-11-06-stdd-default-cr-opt-in

> 来源：`pending-adjustments.md` 的 ADJ-001、ADJ-002、ADJ-003，以及 ADJ-003 的“C1 发现中未修复项”。本文件按 build.md C6 汇总，作为后续迭代的修订需求输入。
> **记录不等于批准或执行**：本文件不构成批准、验收或已修复的声明。`resolved` 字段照抄 `pending-adjustments.md`（三条当前均为 true）；该字段只表示对应记录的问题状态，不表示 BUILD 验收通过或相关项已被修复。

## ADJ-001：全局 APPEND_SYSTEM.md 第 2 行措辞与设计基线不一致

| 字段 | 内容 |
|---|---|
| 依据文档位置 | design.md D5 的全局 APPEND_SYSTEM.md 第 2 行；CP-PG-003；TC-PG-003；修改前基线 |
| 实际变更 | Gate 2 确认后写前核对发现全局文件第 2 行已由设计时的“冲突时的优先级：用户明确要求 > 安全与数据完整性 > 正确性 > 简洁。”变为“优先满足用户明确需求；涉及不可逆操作、数据丢失或敏感信息时，先明确影响并取得必要确认。正确性优先于简洁。”用户原话“确认采用这段合并措辞，启用长程模式”已明确同意将第 2 行改为：“安全与数据完整性是底线；在此前提下优先满足用户明确要求。涉及不可逆操作、数据丢失或敏感信息时，先明确影响并取得必要确认。正确性优先于简洁。”随后用户明确要求“暂用普通模式继续”。本 change 当时已按确认措辞修改该行，独立只读替代检查通过，并以写前 LF 哈希核对其余内容不变；长程模式未启用。当时锁定的 CP-PG-003 仍断言旧措辞且实际失败；这是修订前的历史结果，不报告为当时通过，也不保留为当前并行预期。 |
| 原因 | 实施前 LF 规范化 SHA-256 与已确认设计基线不一致；直接写入原定措辞会覆盖较新的用户内容，且可能删除当前关于不可逆操作、数据丢失和敏感信息的确认要求。 |
| 影响 | 仅涉及全局 APPEND_SYSTEM.md 第 2 行及 prompt-governance 的 D5、CP-PG-003、TC-PG-003 与 spec 预期；其他文件仍以已确认范围为准。保留原 CP 失败和合并措辞检查通过的历史事实；2026-11-10 经用户授权原位调整设计与规格后，只保留批准合并措辞这一当前预期，不把历史替代检查冒充修订后 CP 的执行证据。 |
| 受影响能力 | prompt-governance |
| 严重度 | major |
| 处置状态 | resolved: true（2026-11-15 10:27 起）。2026-11-10 采纳 C4：将 D5、Canonical CP-PG-003、TC-PG-003 和 spec 原位统一为已批准的合并措辞，取消并行替代检查预期；保留本条历史，不修改全局文件。受审文档此后被整体重写，旧的 CP-PG-003 与 TC-PG-003 不再存在；第 2 行的批准原文现在只在 design D5 给出，由 CP-PG-001 比较其哈希。2026-11-10 用户原话“为 AIFI-45 和 stdd-default-cr-opt-in 重新确认 Gate 2”，以修订后的 D5/D6/D7、CP-PG-003、TC-PG-003 与 spec 为受审输入。2026-11-15 用户原话“已经审阅 opt-in 的完整差异，重签 Gate 1 和 Gate 2， ADJ-002 ：已知并接受。请按照以上的建议推进”，AI 据此执行 `gate approve --gate 1/2 --reapprove --confirmed-by dialog`，两个 Gate 已带输入指纹重签，旧批准保留为回执。`resolved` 改为 true，仅表示“两套预期、确认缺失”的问题已处理，不表示 BUILD 验收通过。 |

## ADJ-002：知识库 AGENTS.md 使用完整文件写入而非 Edit 精准替换

| 字段 | 内容 |
|---|---|
| 依据文档位置 | design.md 风险表：大量 dirty 与用户 AGENTS 修改仅通过 Edit 精准替换 |
| 实际变更 | 重组知识库根 AGENTS.md 时使用了完整文件写入，而非设计约定的 Edit 精准替换；这是实施方式偏离，不是扩大业务文件范围。写前重读的 LF SHA-256 为 74ae121374ae682307ea69b0845ee13b77decb5a64fdc4327ff97078ad7ee2c0。写后用 HEAD 原文加当前账本条目的文字及其原编号 7 重建写前内容，得到同一哈希，证明写前已有的该条正文逐字保留且写前其他内容与 HEAD 一致；编号标记已为统一列表格式改为项目符号。不能仅凭该比较排除写前检查与写入之间的并发修改。 |
| 原因 | 根入口整体重组时选择了完整重写，但忽略了本 change 在 dirty 风险表中额外要求只使用 Edit；后续现有文件修改均按精准 Edit 执行。 |
| 影响 | 仅为知识库 AGENTS.md 的编辑方法和并发覆盖风险；受保护的账本条款已按写前哈希核验，其他既有 dirty 不属于本次重写。保留记录供人工审阅，不将哈希检查描述为并发锁。 |
| 受影响能力 | prompt-governance |
| 严重度 | minor |
| 处置状态 | resolved: true（用户 2026-11-15 10:27 原话“ADJ-002 ：已知并接受”）。当前 design 已不再要求“仅 Edit”这一实施方式（D2 第 3 点以根入口现行条款为准），该条设计依据已消失；事实仍然存在：整文件写入，写前哈希核验不是并发锁。来源记录建议用户重签 Gate 2 时确认“已知并接受”，用户确认前保持 `resolved: false`；用户确认（2026-11-15 10:27）后改为 true。记录的事实不变。 |

## ADJ-003：tools AGENTS.md 仍含固定计数与状态链，字面违反 SC-PG-001

| 字段 | 内容 |
|---|---|
| 依据文档位置 | design.md D5（tools `AGENTS.md` 只改驳回段）；specs/prompt-governance SC-PG-001 第三条 AND（“tools 入口……不再含复写的状态转换表或固定计数”）；test-plan TC-PG-001 |
| 实际变更 | C1 评审（code=strong）与主会话对照发现：现行 tools `AGENTS.md` 仍含“八条 active pipeline”固定计数、13 态状态链、`tech-design-review-pending` 判据段与终态段，字面不满足 SC-PG-001 第三条 AND，且与同文件“流程事实归属”表（下一步／回修路线唯一归属 `crctl next`）冲突；design D5 的 tools 行只列驳回段。处置：以已批准的 spec 为准修业务文件，不改受审文档——tools `AGENTS.md` 把“八条”改为引用 `pipeline-templates/_index.yml`，删除状态链、判据段与终态段并改为一句引用 `dir-graph.yaml#change-request-track.state_machine` 与 `crctl next`（被删判据在 `approve-tech-design`、`write-tech-design` Skill 与 `crctl next` 中均有归属）。同轮对知识库 `AGENTS.md` 两处措辞：把“身份、目标仓、绑定或归属不明或冲突时停止并询问、不执行受控写入”从 STDD 分支提为所有流程共同的一条；“Gate 不自动授权 Git／部署”扩为“STDD Gate 与 CR 审批都不自动授权 Git 提交、推送或部署，按所属流程另行取得授权”（依据提案成功标准“流程确认不自动授权 Git 提交、推送或部署”）。改后 `contract-scan.test.mjs` 复测 44/44；TC-WFR-001 盲评按改后入口重做。 |
| 原因 | SC-PG-001 是已批准的行为条款，实施与它不符；改业务文件比改受审文档更小，且不使 Gate 2 失效。 |
| 影响 | 仅 tools `AGENTS.md`（“tools 流程总览”首句、“CR 状态约束”节）与知识库 `AGENTS.md` 第 9、11 行；D5 的 tools 行“只改驳回段”因此偏窄，但未列入“明确不改”的任何文件。其余 C1 发现未修复，见下。 |
| 受影响能力 | prompt-governance、workflow-routing |
| 严重度 | major |
| 处置状态 | resolved: true（用户 2026-11-15 原话“ADJ-003：接受；TC-WFR-001 和 TC-PG-001都确认”）。用户接受本条及下列“C1 发现中未修复项”的处置（保留受审文档、不重签 Gate 2、不扩大 G4 冻结面）；未修改任何受审文档。该原话同时是 TC-WFR-001、TC-PG-001 的确认原文（run `f16c6ed3-7c01-40b9-ad07-8a7ff7a110c4`，`agent confirm --channel dialog` 已记录）。记录的事实与残余风险不变，不表示这些项已被修复。 |

## ADJ-003 的“C1 发现中未修复项”（已知，不是批准；后续迭代的修订输入）

以下各项仍为已知问题/待办，逐条保留自 `pending-adjustments.md`，不随 ADJ-003 的 `resolved: true` 变为已修复。

1. **规格口径偏窄，CP 与保证一致（test：F1）**：SC-PG-002 写“`dir-graph.yaml` 除两个 `description` 外与基线完全相等”，而 D5 已含修改顶部注释（已实施）；CP-PG-001 比较解析后的业务字段，不含注释。以 design 保证 G3（“业务配置不变”）为准；主会话另行逐行对照了基线差异，只有两行注释与 tools 仓库的 `description`，记入 test-report。
2. **G4 证据冻结面窄（test：F2）**：CP-PG-002 执行的 `contract-scan.test.mjs` 还读取 tools 工作树的其他文件，证据计划只冻结 `AGENTS.md` 与该测试文件，故这些文件之后变化不会使本次 run 失效；G4 只对 `AGENTS.md` 作承诺。要扩大须改 test-plan 并重签 Gate 2。
3. **CP-PG-002 只判退出码（test：F3）**：`node --test` 在 0 用例时也退出 0；run 目录不记录命令输出，以主会话用同一命令复跑的 `# pass 44`／`# fail 0` 人工复核（见 test-report），不改受审的 Canonical 规格。
4. **workflow-routing 的 agent 规格以 change ID 命名且无 CP（test：F5）**：TC-WFR-001 的人工证据挂在 prompt-governance 的 run 上，该规格不被 runner 加载；不改名。
5. **受审文档中的过时措辞（docs）**：design D5 的“待实施，tasks B1”与 test-plan 的“tasks B1”应为 tasks 2.1；`.canon-index.yaml` 有一条指向不存在的 `specs/code/...` 的旧键（canon verify 2/2 不检查它，早于本次改写）。以 tasks／phase-context／本记录为现状，不动已冻结文件。
6. **知识库 `CONTEXT.md` 的既有陈旧内容（code：F4、F5）**：仍称 `cr-init` 负责注册；写“28 条声明、wildcard 展开后 50 条”（现为 32 条声明）。D5 限定 CONTEXT 只改开头一句，此项不属于本 change，记入后续合并的 change。
7. **交付前须重算知识库四个顶层文件和全局文件的 LF SHA-256，并与 test-report 打印的哈希核对（test：F4；见 tasks 4.1）。**

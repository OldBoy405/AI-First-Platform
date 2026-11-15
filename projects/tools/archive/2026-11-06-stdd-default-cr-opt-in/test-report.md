# 测试报告 — 2026-11-06-stdd-default-cr-opt-in

> 状态：4 个 TC 均已执行（2 命令通过、2 人工已由用户确认）；**Gate 3 待用户确认，尚未批准**。本文不是批准；只写已发生的事实，未发生的标为未执行。
> 本文不在证据计划的冻结输入中；修改本文不使 run 失效，修改 tools `AGENTS.md` 或 `contract-scan.test.mjs` 会。

## 一、选定 run

- run id：`f16c6ed3-7c01-40b9-ad07-8a7ff7a110c4`（2026-11-15 10:43，tools 业务根，`stdd agent verify prompt-governance`）。
- 报告与快照：`validation/runs/f16c6ed3-7c01-40b9-ad07-8a7ff7a110c4/`（`tc-evidence.json`、`agent-verification-report.md`、`inputs/`）。
- 冻结输入：tools `AGENTS.md`（sha256 `b8f84bdb…fe52`）、`contract-scan.test.mjs`（sha256 `c0af1759…5408`）。
- Gate：1、2 于 10:27 重签（带指纹）；Gate 3 pending。

## 二、TC 覆盖（planned 4 / actual 4，`ci check-failures`：TC 当前执行覆盖 4/4）

| TC | 保证 | 种类 | 结果 |
|---|---|---|---|
| TC-PG-002 | G3 | 命令（CP-PG-001） | 通过：exit 0，输出 `CP-PG-001 PASS` |
| TC-PG-003 | G4 | 命令（CP-PG-002） | 通过：exit 0；同命令另跑 44 tests／44 pass／0 fail |
| TC-WFR-001 | G1 | 人工，盲评 | 通过：盲评与 D1 逐行一致（第四节）；用户确认原文已记录（`agent confirm --channel dialog`） |
| TC-PG-001 | G2 | 人工，对照 | 通过：对照表见第五节，八项均保留；用户确认原文已记录（同上） |

用户确认原文（2026-11-15，同一句同时确认两个 TC 并接受 ADJ-003）：“ADJ-003：接受；TC-WFR-001 和 TC-PG-001都确认”；确认时已核对冻结输入与第三节五个文件的 LF SHA-256 均未变化；确认主体 subject `d04b3e9c…fac1`。

覆盖率：豁免（`not_applicable`；无产品代码，覆盖采集仅支持 pytest-cov）。切片：slice 1、2 均已实施并验证（TC 覆盖各 3/3，`new_tests: 0`——文档类变更没有新增测试函数，验收依据是上述 TC 证据）；`phases.build.slices_completed` 已于 2026-11-15 10:50 按 B3.4 精准写入 `.stdd.yaml`，随后 `ci check-failures` 的切片完成项通过。

## 三、TC-PG-002 的五个 LF SHA-256（交付前须重算核对，tasks 4.1）

CP-PG-001 同次运行打印；主会话另用 `tr -d '\r' | sha256sum` 独立重算，五项一致。

| 文件 | LF SHA-256 |
|---|---|
| 知识库 `AGENTS.md` | `fc818ba531fd2fb3cba34d511599b9999b019a7ccca5ada28c79935dad665559` |
| 知识库 `README.md` | `9790ef9b05853d2f83000bd1fc7d4b33abf693c8be12a86612a267455f4db670` |
| 知识库 `CONTEXT.md` | `83dcfd4958ac7b2f743a02b3ab22a5e01e53b385199e279f28a53bf372e5f2ad` |
| 知识库 `dir-graph.yaml` | `9ad8cd9a215ec7ce76c27e100f5403010db8a54adb54d03eb3f7d5af2ebb0b26` |
| 全局 `APPEND_SYSTEM.md` | `4e040e763e34ac92fef6e9071ab4d2a4b1378091ecfc4dcd967818c6077bc81c` |

补充（人工，非机器保证）：`dir-graph.yaml` 相对基线 `1a409847` 的实际差异只有——顶部两行回退注释改写、tools 仓库的 `description` 一行；`ai-first-platform-docs` 的 `description` 未变。CP-PG-001 比较解析后的业务字段、不含注释（见 ADJ-003）。

## 四、TC-WFR-001 — 盲评结果与 D1 比对

- 评审者：独立子代理会话 `01a1dd13-84ee-7314-b2e3-5d1c4f6c1caa`；配置 strong（`GB-JP/kimi-k3.1-pro`，effort `max`），请求同值，会话记录的实际模型同为 `GB-JP/kimi-k3.1-pro`、thinking `max`。只读知识库 `AGENTS.md` 与 tools `AGENTS.md`（工具调用记录核对：仅对这两个文件 read／grep），未读 design、proposal、specs。
- 第一轮盲评（`01a1dd09-c7d8-…`）基于入口修改前的版本，答案同样与 D1 一致；因 C1 后修改了两个入口（ADJ-003），按改后文件重做，**以下以第二轮为准**。第二轮额外覆盖“显式 CR＋目标不明”（D2）与“仅 CR 审批却要求提交／推送／部署”（F4）。

| D1 行 | 盲评答案摘要（行号为答题时文件行号） | 与 D1 |
|---|---|---|
| 只读分析 | 不立项只读；不创建 change／CR／记录，不自动注册（K7） | 一致 |
| 已有 STDD／CR | 沿用原流程，不套 STDD 默认值；CR 用 `crctl status`／`next` 接手；请求与原流程冲突则停止并确认迁移方案（K8、K18） | 一致 |
| 新开发未指定流程 | C1（目标 tools 明确、知识库 cwd 无绑定）：默认 STDD，不因目标是 tools 自动选 CR，先核实 tools 绑定与三根再执行；C2（目标不明）：停止询问（K9、K11） | 一致 |
| 显式 tools CR | D1：选 CR，按 `requirement-register`／`crctl register` 注册，账本只经合法入口；D2（目标不明）：停止询问，不创建任何记录（K10、K11、K27） | 一致 |
| 身份／目标／绑定／归属不明或冲突 | 停止并询问，不执行受控写入，不猜目录、不自动初始化、不回退旧模式、不双写（K11） | 一致 |
| 仅有一个 Gate 或另一流程批准却要求推进 | F1–F4 均停止；Gate 不替代 CR 审批、CR 审批不自动确认 STDD；Gate 与 CR 审批都不自动授权提交／推送／部署，须按所属流程另行取得授权（K12） | 一致 |

- 两份入口有无相反的无条件要求：评审者答“未发现”（K10 与 T5、T60 一致：按任务／阶段加载，不无条件读完整 CR 手册）。第一轮同。
- 评审者标注“文字不足”之处：纯只读的专属停止条件（A④）；提交／推送／部署的具体授权形式（F3、F4，属所属流程）。它们没有给出与 D1 相反的结论。
- 局限：这是静态阅读判断，不证明运行时模型的实际路由。

## 五、TC-PG-001 — 保护点对照（写前基线见 design 末节）

知识库 `AGENTS.md` 行号为当前文件；基线 `74ae1213…`（`1a409847` 原文加当时未提交条款，ADJ-002）。

| # | 保护点 | 成品位置 | 结论 |
|---|---|---|---|
| 1 | 事实断言先核实；读目标仓规范；multica 英文注释与 CUSTOM 登记 | KB L24、L25 | 保留 |
| 2 | 执行账本只经合法入口及入库脚本；禁止现写脚本；版本化不替代权限／CAS／审计／门禁；无合法入口则不改 | KB L27、L29 | 保留（“无合法入口则不改”由“只经其规定的合法入口”表达，语义保留，非逐字） |
| 3 | 人工记录：保留原记录及扩展字段；区分事实／决定／授权／未决；`resolved` 如实；归属不明按账本处理；精准编辑授权范围 | KB L26、L28、L29 | 保留 |
| 4 | 记录不等于批准或执行；Gate 与 CR 审批互不替代；Gate 不授权 Git／部署 | KB L12（本轮扩为 Gate 与 CR 审批都不自动授权，ADJ-003） | 保留并加强 |
| 5 | 哈希／跨行正则／逐行解析前规范化 CRLF；解析失败硬失败 | KB L23 | 保留 |
| 6 | 不覆盖累积发布基线；`docs/product`、`docs/analysis` 不强行搬入 `specs`；历史 CR 与 delivery 保持职责 | KB L19 | 保留 |
| 7 | 不据主 checkout 陈旧快照猜在途 CR 状态；操作根以 crctl 为准，不自拼 worktree | KB L18 | 保留 |
| 8 | 定制台账按目标仓格式登记；追溯用真实流程标识，不为 STDD 编造 CR 编号；格式不接受则停止确认 | KB L25 | 保留 |

八项均为“保留”，没有缺失、没有迁往权威文件的项。

| 对照对象 | 相对基线的差异 | 结论 |
|---|---|---|
| `README.md` | 新增“工作流入口”一节（流程选择指向 `AGENTS.md`；STDD 以目标业务仓 `.stdd/binding.yaml` 确认记录根与项目 ID；资源母本 `../stdd/`；无绑定不猜测） | 仅批准的入口说明；其余未动 |
| `CONTEXT.md` | 仅在开头原句后追加一句：CR 术语只定义领域含义，不自动启用 CR 流程 | 领域定义未变（已知的旧陈旧内容见 ADJ-003，不在本 change） |
| tools `AGENTS.md` | 读取路由改为按任务和阶段加载；CR 与工程作用域分层；CR 驳回段、状态链、固定计数改为引用 `dir-graph.yaml#…state_machine`／`crctl next`／`pipeline-templates/_index.yml`（ADJ-003） | 包边界（L45 起）、单一事实源（L30）、矩阵／索引要求（L36、L41、L51、`修改 Skill／Agent／Pipeline` 各节）、`流程事实归属`表均在；已无状态转换表、状态链、固定计数（grep `八条|四阶段|→|:reject|drafting|tech-design-review-pending` 无命中） |

## 六、C1 三路评审（design 指定分层）

| 路 | 档位／实际模型 | 发现 | 处置 |
|---|---|---|---|
| code | strong／`GB-JP/kimi-k3.1-pro` max | 3 blocker、1 major、1 minor | 第 1 条（失败关闭未成共同前置）采纳，改知识库 `AGENTS.md`；第 2 条（CR 审批与提交／推送／部署）采纳其方向，依据提案成功标准“流程确认不自动授权 Git 提交、推送或部署”；第 3 条（tools 入口仍有固定计数与状态链）采纳，依据 SC-PG-001 第三条 AND，改 tools `AGENTS.md`；第 4、5 条是 `CONTEXT.md` 的既有陈旧内容，D5 限定只改开头一句，转入后续合并 change |
| test_config | balanced／`GB-JP/deepseek-flash` max | 4 major、2 minor、1 nit | 不改受审文档；F1、F2、F3、F5 记入 ADJ-003（保留受审文档、记录残余风险）；F4 加 tasks 4.1；F6 与 code 第 3 条同因，已随业务文件修复；F7、F8 为状态／清单类，已更新 slices、phase-context、spec-review 并在收尾时改 `code-structure-delta.md` |
| docs_skills | economy／`Gobao/deepseek-flash` high | 引用均核实存在；若干受审文档的过时措辞与状态陈旧 | 状态陈旧已在非冻结文件更正；受审文档中的过时措辞（design D5“tasks B1”等）与 `.canon-index.yaml` 旧键不改，记入 ADJ-003 |

各路的“未核实”项：code 路未对基线提交做 `git show`（无 bash）；其余只读核对均已由主会话补做（见第三、五节）。

## 七、失败模式检查（C4）、经验库、设计调整

C4 十四项逐项结果。run 均为 `f16c6ed3-7c01-40b9-ad07-8a7ff7a110c4`；“CLI”指 `stdd ci check-failures` 在该 run 上的确定性检查（9/9 通过，0 警告、0 跳过），“人工”指主会话基于同一 run 的冻结输入与第三至六节做的核查。

| ID | category | 方式 | 结果 |
|---|---|---|---|
| (a) | hallucination | CLI | 通过：必需文件与 Spec 文件存在。另：C1 docs 评审逐个核对入口引用的路径、锚点，均存在 |
| (b) | scope_creep | 人工（C3 diff 审查） | 改动均在 design D5 列出的文件内；超出 D5 文字的两处——tools `AGENTS.md` 删状态链与固定计数、知识库 `AGENTS.md` 两处措辞——依据 SC-PG-001 与提案成功标准，已记 ADJ-003 并经用户接受。知识库 `AGENTS.md` 内含用户在本 change 之外的修改（ADJ-002），未回退；tools、知识库其余 dirty 文件未触碰。无未声明的扩围 |
| (c) | cascading_errors | 人工 | C1 后改了两个入口，随后重跑 `contract-scan`（44/44）、重做盲评、重跑 verify、重算五个哈希，未发现连锁错误 |
| (d) | context_loss | CLI | 通过：TC-ID 唯一（4 个） |
| (e) | tool_misuse | 人工 | 未发现：命令 CP 另以与 runner 相同方式（`shell=True`、tools 根为 cwd）预跑；写文件均用精准替换并核对行尾与差异 |
| (f) | runtime_deviation | CLI | 通过：所有 THEN 含 SHALL |
| (g) | pipeline_break | CLI | 通过：AND 数量正常；2 个切片均有验证证据（`slices_completed` 写入后重跑） |
| (h) | content_quality | 人工 | 盲评、保护点对照与 C1 三路评审后未发现缺失或不可用内容；既有陈旧内容（`CONTEXT.md`）按 ADJ-003 转后续 change |
| (i) | instruction_decay | 人工 | 未发现：普通模式；Gate 重签与两条人工确认均取自用户原话，未代签；未改受审文档；未提交、推送 |
| (j) | coverage_vacuum | CLI | 通过：已声明无覆盖义务；TC 当前执行覆盖 4/4 |
| (k) | contract_gap | CLI＋人工 | CLI 通过（2 capabilities 一致）。人工发现并已处置一处：SC-PG-001 第三条 AND 比 D5 范围表更严（见 ADJ-003） |
| (l) | anchor_missing | CLI | 通过：非关键变更，无需锚定 |
| (m) | agent_cp_failure | 人工 | 已知局限、不是失败：CP-PG-001 判定面窄于 SC-PG-002 措辞（注释不在判定面）；CP-PG-002 只判退出码。已用人工复核补足（五个哈希独立重算一致；`contract-scan` 44/44/0 fail），用户已接受（ADJ-003） |
| (n) | cross_system_mismatch | 人工 | 知识库入口、tools 入口与 `dir-graph.yaml` 状态机的引用关系已核对一致。已知不一致：`CONTEXT.md` 的 `cr-init` 与固定计数（既有，ADJ-003，转后续 change）；`tools/CLAUDE.md` 无条件读 README（范围外，见 phase-context） |

- 经验库（C5）：新增两条（均 `discovered`，severity medium，`provenance: ai-inferred`）：`EXP-2026-0002`（contract_gap：spec 的 AND 比 design 范围表更严，应在 Gate 2 前逐条对照）、`EXP-2026-0003`（agent_cp_failure：CP 判定面窄于 spec 措辞、`node --test` 0 用例也退出 0）。由 balanced 子代理经 `stdd experience add` 写入，主会话核对了内容；写入前 `list`／`search` 无语义重复条目。
- 设计调整（C6）：`design-adjustments.md` 已生成（ADJ-001～003 及 ADJ-003 的 7 项未修项，均为修订需求而非已修复；由 balanced 子代理汇总，主会话核对）。`.stdd.yaml` 的 `design_adjustments.count` 仍为 0，不手改，由 CLI 登记入口负责（未找到登记入口则记为已知）。

## 八、已知问题与未完成项

| 项 | 原因／影响 | 补完 |
|---|---|---|
| tools 全量 `quality.test` 未运行 | design D6：被改的 tools 文件只有 `AGENTS.md`，结构依赖由 TC-PG-003 覆盖；全量套件含受限身份、可能触及宿主的隔离用例 | 由用户在 Gate 3 确认处置 |
| G3 的五个文件无法被 CLI 冻结 | 位于业务根与数据根之外；其后变化不会使本 run 失效 | tasks 4.1 交付前重算核对 |
| ADJ-003 所列未修项 | 用户已接受（2026-11-15）；残余风险不变：G4 冻结面只含 `AGENTS.md` 与测试文件；CP 判定面窄于 spec 措辞 | 后续合并的 change 或另行修订并重签 Gate 2 |
| Gate 3 未批准 | 须用户确认（含上一行的“tools 全量测试未运行”处置） | 用户确认后 `gate approve --gate 3 --run f16c6ed3-…` |
| 提交／推送／部署 | 无授权，未执行 | 交付阶段按用户逐文件授权 |

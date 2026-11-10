# 工作区入口精简与 STDD／CR 流程隔离 — 测试方案与详细案例

> Change：`2026-11-06-stdd-default-cr-opt-in`；日期：2026-11-06；模式：standard；task_type：documentation。
> 本方案已按用户 2026-11-10 决定原位修订，修订版 Gate 2 重新确认待完成；执行结果见 `test-report.md`，未运行不等于通过。
> 唯一规格源：`canonical/specs/agent/2026-11-06-stdd-default-cr-opt-in.yaml`、`canonical/specs/agent/prompt-governance.yaml`。`specs/*/spec.md` 因 BUILD／DELIVER 契约保留为非权威人工评审副本（兼容视图），不是第二来源；评审引用 Canonical CP，不另设同步检查。

## 一、测试策略

### 1.1 测试金字塔

本次不增加运行时代码或新的验证框架。文档层验收目标是只读静态 CP 检查、独立文档场景／差异评审和用户对受审文档的明确批准；tools 原有 quality 检查的真实结果另列，不关闭现有配置。静态检查不证明运行时路由，人工审阅也不证明已部署、实际模型行为或代码执行覆盖。现行 STDD 虽支持 command/manual 与 coverage 不适用声明，但本 change 的跨根输入和 change-local 产物无法接入，故文档层验收尚不能据此闭合 BUILD；详见阶段检查。

### 1.2 测试原则

- 在 Gate 2 和 BUILD 模式确认后，先执行 CP 的只读 action 记录当前缺失，再修改目标文档并复跑；不为得到 RED 人为破坏文件。
- 每个 TC 同时检查条款存在与语义。静态 action 的 `STATIC PASS` 不是整个 TC 通过，人工场景结果和附加差异检查缺一不可。
- 每个场景评审必须回答：选哪套流程、是否创建／修改、还需要何种授权、冲突时如何停止。独立评审者同时读取根和 tools 入口，不能只检索某一句正确短语。
- 文本读入先 CRLF → LF；解析错误非零并报告，不能空数组降级。YAML 用现有 STDD venv 的 PyYAML 解析，不装新依赖。
- 所有检查以 tools 业务根为 cwd；执行已核实的 `../stdd/.venv/Scripts/python.exe`，不能把无绑定的知识库根当业务根。
- 不执行真实 register、approve、merge、writeback 或跨流程迁移来验证文案；不运行项目级 `agent verify`，不把 CP 复制到项目级 canonical。
- 现有 standard 和 quality 配置不改、不关闭。完整测试的超时、失败、跳过与未运行均原样记录；不将其他在途变更修复混入本次。

### 1.3 已有测试资产

| 入口 | 已核实覆盖 | 已知盲区 |
|---|---|---|
| `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` | tools Skill／Agent／Pipeline／README 的漂移规则 | 不扫描根 AGENTS、知识库 graph 或全局文件；enforce 参数已由脚本声明核实 |
| `node skills/shared/crctl/scripts/check-agents-contract.mjs` | tools 原有 Agent 合同 | 不证明本次入口路由 |
| `node skills/shared/crctl/scripts/check-skill-matrix.mjs` | tools 原有 Skill 矩阵 | 不验证跨仓默认流程 |
| `quality.yaml` 的 `quality.test` | 现有 crctl／OutputGuard／Pipeline 测试发现范围 | 本次未运行，不写通过，不把脚本数量固化为断言 |
| `stdd proposal validate <本ID>`、`canon verify <本ID>` | 提案 YAML 与 CLI 生成 proposal 双轨一致性 | 不覆盖两个 CP 人工评审副本 |
| `stdd validate <本ID>` | 现行结构检查 | 退出 0 不等于文档语义、Gate 2 或运行时正确 |

## 二、详细测试案例

每项静态 action 来自对应 Canonical CP；不在此复制另一套实现。两个 CP 文件分别为 `canonical/specs/agent/2026-11-06-stdd-default-cr-opt-in.yaml` 和 `canonical/specs/agent/prompt-governance.yaml`。

### 功能一：workflow-routing

#### TC-WFR-001 — 只读分析

| 字段 | 内容 |
|---|---|
| **ID** | TC-WFR-001 |

- **对应 Spec**：REQ-WFR-001 / SC-WFR-001 / CP-WFR-001；**优先级**：P0。
- **预置条件**：仅问“分析入口来源和风险”，无开发或写入要求。
- **输入**：按实施后的入口说明选择行为。
- **预期**：不创建任何变更；只读资料仍受安全边界约束。静态条款存在，人工能指出不注册规则且找不到相反的无条件流程要求。
- **当前状态**：待 BUILD 验收。

#### TC-WFR-002 — 新开发默认 STDD

| 字段 | 内容 |
|---|---|
| **ID** | TC-WFR-002 |

- **对应 Spec**：REQ-WFR-002 / SC-WFR-002 / CP-WFR-002；**优先级**：P0。
- **预置条件**：从无绑定的知识库 cwd 发起新的 tools 开发请求，但目标 tools 已明确且其业务绑定有效；没有已有 change 身份和流程指定。
- **输入**：说明从哪个 cwd、绑定、记录根及阶段技能开始。
- **预期**：选 STDD；定位 tools 绑定和 `projects/tools`，不从知识库 cwd 直接走旧模式，不声称未注册的 slash command 可用。
- **当前状态**：待 BUILD 验收。

#### TC-WFR-003 — 新变更显式 CR

| 字段 | 内容 |
|---|---|
| **ID** | TC-WFR-003 |

- **对应 Spec**：REQ-WFR-002 / SC-WFR-003 / CP-WFR-003；**优先级**：P0。
- **预置条件**：新请求明确选择 tools CR。
- **输入**：说明注册及后续资料入口，不执行真实注册。
- **预期**：读取 CR 专项，引用 requirement-register／现行 crctl 合同；不手写账本，不用 STDD 默认值拒绝 CR。
- **当前状态**：待 BUILD 验收。

#### TC-WFR-004 — 旧 CR 与默认／新请求冲突

| 字段 | 内容 |
|---|---|
| **ID** | TC-WFR-004 |

- **对应 Spec**：REQ-WFR-003 / SC-WFR-004 / CP-WFR-004；**优先级**：P0。
- **预置条件**：已识别真实旧 CR，入口默认 STDD；再加入“改用 STDD”这一未经迁移确认的请求。
- **输入**：复述两种情况下可做和不可做的操作。
- **预期**：旧 CR 仍按原合同；流程冲突操作暂停，另行确认迁移；不改状态、不双写任务、不把旧 CR 直接标完成。反例也须检查已有 STDD change 不被关键词切成 CR。
- **当前状态**：待 BUILD 验收。

#### TC-WFR-005 — 绑定／归属不明

| 字段 | 内容 |
|---|---|
| **ID** | TC-WFR-005 |

- **对应 Spec**：REQ-WFR-004 / SC-WFR-005 / CP-WFR-005；**优先级**：P0。
- **预置条件**：在无绑定知识库根发出开发请求，目标项目缺失；或显式 ID 与目标仓冲突。
- **输入**：指出下一步和禁止动作。
- **预期**：停止并询问；不 init／install／upgrade，不猜 sibling，不回退旧模式，不选最近的其他在途 change。
- **当前状态**：待 BUILD 验收。

#### TC-WFR-006 — 审批和操作授权隔离

| 字段 | 内容 |
|---|---|
| **ID** | TC-WFR-006 |

- **对应 Spec**：REQ-WFR-005 / SC-WFR-006 / CP-WFR-006；**优先级**：P0。
- **预置条件**：只有 STDD Gate 1，要求据此 approve 真实 CR 或 commit／push／deploy；并反向检查只有 CR approve 的情况。
- **输入**：解释哪些决定仍需单独授权。
- **预期**：Gate 2、BUILD、真实 CR 审批和 Git／部署授权均不能推定；不伪造 evidence、签名、token 或人工确认。
- **当前状态**：待 BUILD 验收。

### 功能二：prompt-governance

#### TC-PG-001 — 常驻分层和字符量

| 字段 | 内容 |
|---|---|
| **ID** | TC-PG-001 |

- **对应 Spec**：REQ-PG-001 / SC-PG-001 / CP-PG-001；**优先级**：P1。
- **预置条件**：根及 tools 入口均已完成定点修改。
- **输入**：分别走查只读、STDD、tools 工程维护和 CR 专项的阅读路径，计算根 LF 字符量。
- **预期**：根小于原 6,287 字符，非 CR 任务无无条件 CR 全量阅读链；维护 Skill／Agent／Pipeline 时仍读取必要矩阵和索引。README 明确当前 STDD、projects 记录及业务绑定入口；CONTEXT 只在开头增加适用范围说明，逐行核对原领域定义未改。不得以达到字符数为由删除安全保证。
- **当前状态**：待 BUILD 验收。

#### TC-PG-002 — CR 事实与 graph 配置

| 字段 | 内容 |
|---|---|
| **ID** | TC-PG-002 |

- **对应 Spec**：REQ-PG-002 / SC-PG-002 / CP-PG-002；**优先级**：P1。
- **预置条件**：说明修改已完成，原 graph 与记录的 HEAD／工作副本基线一致。
- **输入**：核对注册、审批、操作根、Tools Root 引用；用 PyYAML 比较修改前后 graph。
- **预期**：根不再含已知错误说法或固定状态数量；CR 专项引用真实权威入口。逐行检查 graph 顶部旧回退注释被正确替换为 `workspace.tools_package_path` 权威说明，不能只比较解析对象。graph 解析比较仅排除 `repositories[0].description` 和 `repositories[2].description`，其余字典、列表和标量全部相等；所有 YAML 可解析。
- **当前状态**：待 BUILD 验收。

#### TC-PG-003 — 用户改动、底线与全局一行边界

| 字段 | 内容 |
|---|---|
| **ID** | TC-PG-003 |

- **对应 Spec**：REQ-PG-003 / SC-PG-003 / CP-PG-003；**优先级**：P0。
- **预置条件**：写前重读并核对 design 的 LF 哈希；出现后来变更时先停下核对，不覆盖。
- **输入**：对照原工作副本而非仅对 HEAD 审查实际差异。
- **预期**：逐句对照 Canonical CP-PG-003 保护清单与原工作副本第 7 条，不按摘要放行。精准编辑例外仅限记录设计偏离、供人工审阅的 STDD `pending-adjustments.yaml`，不能扩大为一般人工设计 YAML。保留原记录和扩展字段，依据原话或可靠来源区分方向、具体决定、执行授权和未决事项；核对所属 change、YAML 解析与类型、必需字段、编号唯一、冲突标记及差异，失败或归属不明时停止，resolved 如实。其他 YAML 归属不明按执行账本处理；账本仅经合法入口及入库、可测试的版本化脚本，禁止会话内现写脚本处理。保留权限／唯一入口／CAS／审计／门禁、无入口则停、行尾规范化与硬失败、累积基线及 CUSTOM 追溯。全局文件第 2 行的唯一预期为“安全与数据完整性是底线；在此前提下优先满足用户明确要求。涉及不可逆操作、数据丢失或敏感信息时，先明确影响并取得必要确认。正确性优先于简洁。”；其余行保持，不另设旧句或替代检查预期。未更改其他执行账本、历史或在途变更。根已有用户修改不因本次消失。
- **当前状态**：待 BUILD 验收。

#### TC-PG-004 — 不夸大验证和部署结论

| 字段 | 内容 |
|---|---|
| **ID** | TC-PG-004 |

- **对应 Spec**：REQ-PG-004 / SC-PG-004 / CP-PG-004；**优先级**：P1。
- **预置条件**：已有静态／场景／原生检查和阶段文档。
- **输入**：审阅 test-report、Gate 3 摘要及模型／经验说明。
- **预期**：每项说明实际执行、退出码、范围、未覆盖和未完成；不将静态条款报告为运行时路由，不将人工视图说成 CLI 自动生成，不将 configured 模型说成已核实档位，不报未测量的 token 比例或部署成功。
- **当前状态**：待 BUILD 验收。

## 三、测试执行矩阵

| Capability | Requirement | Scenario / CP / TC | 静态 | 独立语义／差异 | 实际运行时 |
|---|---:|---:|---|---|---|
| workflow-routing | 5 | 6 / 6 / 6 | 待执行 | 待执行 | 本次不证明、不部署 |
| prompt-governance | 4 | 4 / 4 / 4 | 待执行 | 待执行 | 本次不证明、不部署 |
| 合计 | 9 | 10 / 10 / 10 | 待 BUILD | 待 BUILD | 未覆盖 |

优先级：P0=7，P1=3，P2=0；置信度：high=10、medium=0、low=0。这里的数值是待验收规格数量，不是已通过测试数量。

### 现有 quality 检查保留

从 tools 根执行现有配置中的命令，记录真实退出码与耗时：

```text
node skills/shared/crctl/scripts/lint-prompts.mjs
node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce
node skills/shared/crctl/scripts/check-agents-contract.mjs
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node --test "skills/shared/crctl/scripts/test/*.test.mjs" "output-guard/test/*.test.mjs" "pipeline-templates/*.test.mjs"
```

保留原 quality 配置，另行运行 enforce，不修改其默认 report 命令。report 退出 0 不等于无漂移，须记录 findings；enforce 结果也须如实报告。静态命令仅覆盖对应文件，不能用上述 lint 的零 finding 代替根入口检查。测试若受当前大量在途代码、环境或时间影响，保持配置不变并原样报告；不得据此宣布本次全套验收通过或自动扩大为修复其他在途工作。

### 阶段检查

本轮仅修订本 change 的记录并执行只读检查，不修改业务入口、不推进阶段或批准任何 Gate。保留兼容视图的原生 `#### Scenario:` 结构和 TC 的 `| **ID** | TC-... |` 定义行供现行 CLI 识别；这些是定义数，不是执行覆盖。规格评审直接引用 Canonical CP，不把两份视图当作第二来源或增加逐项同步验收；canon verify 仅覆盖 proposal。按 SPEC Skill Step 6，修订版设计／CP／测试方案仍待 Gate 2 重新确认；gate status 的 historical/unfingerprinted 不代表当前修订已批准，也不会自动变为 stale。

**原生文档验收支持及适用边界**：`evidence.py:123–150` 的 `stdd-evidence-plan-v1` 支持 `kind: command/manual`，并非仅支持 runtime TC／pytest；`confirm_manual`（429–476）把确认原文绑定当前 run／冻结输入，不鉴别人身身份，也不自动批准 Gate。`coverage_declaration`（563–624）支持 `coverage: {applicability: not_applicable, reason: ...}`，用于没有产品代码面的变更，CI 据此可不要求 coverage.json；它不豁免 TC 必需集和切片记录。`task_type: documentation` 不是门禁开关，当前无 `test_type` 入口。

**本 change 的工具缺口与停止条件**：完整计划校验固定读取项目级 agent canonical（`evidence.py:80–86`），runner 也只从该处取 task（`agent.py:83–89`），当前项目该目录不存在。runner 必写、验证器必查项目共享报告（`agent.py:134–139`、`evidence.py:723–727`）；输入仅支持 project/data 根内相对路径（`evidence.py:29–36`），不能冻结知识库根和用户全局文件。coverage 不适用声明也先调用完整 `_plan`，不能只填一个豁免段绕开这些限制。Gate 3 和 BUILD→DELIVER 仍要求原生切片记录，无 documentation 例外。

用户 2026-11-10 已采纳文档验收方向，不再等待 A/B 选择；但当前没有能在“仅修改本 change 目录”范围内使用的完整合法路径。故本轮不新增不可执行的证据计划、不复制 CP 到项目级、不调用写共享报告的 agent verify、不制造 coverage.json、不手改 `.stdd.yaml`。记录 validate／proposal validate／canon verify／ci check-failures 的真实退出码后停止 BUILD，将未闭合项明确归为 STDD 对跨根、change-local 文档验收的工具缺口；不把静态 PASS 或用户的修订授权冒充当次原生验收通过。

## 四、回归风险矩阵

| 区域 | 风险 | 保护 | 等级 |
|---|---|---|---|
| 已有 CR／审批／操作根 | 默认值误接管或放宽旧门禁 | WFR-003/004/006、PG-002，引用现行合同 | 高 |
| 根 AGENTS 已有用户修改 | 按 HEAD 覆盖导致保护丢失 | 工作副本哈希、定点 Edit、PG-003 | 高 |
| STDD 三根与旧模式 | 写到错误 change／记录仓 | WFR-002/005，显式 ID 和业务 cwd | 高 |
| graph／全局文件 | 文案修改引入配置或权限漂移 | PG-002 的语义比较、PG-003 的一行差异 | 高 |
| 人工视图和静态工具 | 错称自动验证、部署或实际路由 | PG-004、视图标注非权威，评审直引 Canonical CP | 中 |
| tools 维护约束 | 按需读取被解释为不遵守矩阵／索引 | PG-001，tools 入口分层且不删除保证 | 中 |

## 五、建议补充顺序

1. P0：先固定 WFR-001–006 与 PG-003 的预期和差异边界，再实施入口修改。
2. P1：完成 PG-001/002/004；核对跨入口一致性、字符／加载链和证据边界。
3. 运行现有 quality 检查及 standard 要求的评审，汇总未运行／失败／跳过，形成 Gate 3 材料；不自动 commit、push 或 deploy。

# T01–T02 构建证据与第一轮评审回修——已冻结，交还独立复核

## 范围与所有权

本次属于普通 STDD 维护，不使用 tools CR 流程。未创建真实 CR，未执行 Git commit/push/branch、部署、DB 操作、新增依赖或全局设置变更；未修改 matrix/index/README/state/tasks/specs/ADJyaml。主会话负责独立评审和任务勾选，不以本报告代替平台验收或 Gate3。

- 首次 T01/T02 写范围：`pipeline-templates/emit-registry.mjs`、既有 `emit-registry.test.mjs`、原模板中必要的独立评审 `executor` 声明。
- 第一轮评审回修重新获得的写权限**仅限**上述 emitter、既有测试和本报告。四份模板 JSON、AGENTS/三个 Skills/contract-scan 归 T03 worker；pipeline-structure 负向夹具归主会话。本轮未写这些文件，也未编辑主会话的 `T01-T03-review.md`。
- 本 worker 未实现 T03/T04，也未用其他 worker 的施工中合同结果冒充最终验证。最终联合 contract-scan/lint/quality 由主会话在双方冻结后执行。

## 初始核实与原始证据

已读取当前 tasks/slices/execution-policy/design、绑定与导出能力的 canonical code Scenario 和 Agent CP，以及 tools AGENTS/graph/matrix/README/indexes、四份模板、相关 review/test-report Skills 和 tdd/ponytail/karpathy 指引。

进入时已有未提交改动：`.gitignore` 和 S0 的 `crctl.mjs`、`caller-contract.test.mjs`、`crctl.test.mjs`、`writeback-tx.test.mjs`。进入时保存原始 SHA256；本 worker 不修改这五个文件。

- 首次测试前的 emitter 套件：**8 tests / 8 pass / 0 fail / 0 skipped**，自然 exit 0，wall 0.7629s，reporter duration 719.5152ms。
- 首次证据目录：`C:/Users/GOBAO/AppData/Local/Temp/aifi45-t01-t02-duXFTj/`。保留初始/交接 SHA256、所拥有文件原件、命令、原始 stdout/stderr、实际退出码与计时 JSON。
- 验证缝：现有 emitter CLI 的 `--pipeline`，针对真实或 scratch 修改的权威文件执行；不新增 API、flag、依赖或测试框架。
- 独立读取/检查并行，T01→T02 的依赖写入串行。该 worker 无 subagent 工具，独立评审由主会话承担。
- 首次预读发现 `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` 仍以 coding 不受支持为负向夹具，随后原样执行并保留失败；没有改其他所有者测试以掩盖差异。

## T01 首次 RED→GREEN

| 证据标签 | 实际结果 | 自然退出码 / wall | 观察 |
|---|---|---|---|
| `t01-bind001-red` | 1 tests / 0 pass / 1 fail / 0 skipped | exit 1 / 0.1724s | 共享节点权限缺少 nodeId/executor |
| `t01-bind001-green` | 1/1 pass / 0 skipped | exit 0 / 0.1631s | 最小导出绑定后通过 |
| `t01-bind002-003-red` | 14 tests / 1 pass / 13 fail / 0 skipped | exit 1 / 1.1843s | reviewer 默认落作者；非法 actor/system/无权/forbidden/缺失/自审/null/human 绑定及重复/缺失 ID 未拒绝；显式合法执行者被旧 pipelineOwner 限制拒绝。重复 ref 正例原已通过 |
| 首次完整复测 | 23 tests / 22 pass / 1 fail | exit 1 / 2.0136s | 正向备用执行者夹具误把实际 PRD 作者替换为 reviewer，剩余真实 review 正确拒绝自审 |
| `t01-green-final` | **23 tests / 23 pass / 0 fail / 0 skipped/cancelled/todo** | exit 0 / 1.9661s | 将备用执行者夹具移至 checkpoint 槽位，保留真实作者；未弱化校验 |

实现按稳定 node.id 逐节点绑定；普通节点默认阶段 Agent，原 requirement/architecture/coding 的独立评审节点显式声明真实 `quality-reviewer-agent`。维护 owner 保留，包括逻辑 system owner；执行者独立检查 kind=agent、owns/can-call、forbidden 和作者分离。兼容字段 `pipelineOwnerCanCall` 表达 pipelineOwner 的实际权限事实，不替代所选 executor 的校验。没有矩阵授权缺口，无需变更真实权限。

首次并行执行已有入口：`check-agents-contract.mjs` exit 0 / 0.0568s；`check-skill-matrix.mjs` exit 0 / 0.0757s；`lint-prompts.mjs --mode enforce` exit 0 / 0.1296s。这是当时文件状态的结果，不是后续 T03 的最终质量结论。测试 BOM 为 `efbbbf`，未改动区域的 CRLF/历史乱码注释保留。

## T02 首次 RED→GREEN

| 证据标签 | 实际结果 | 自然退出码 / wall | 观察 |
|---|---|---|---|
| `t02-reg001-red` | 4 tests / 2 pass / 2 fail / 0 skipped | exit 1 / 0.2822s | coding/writeback 真实返回 RUNNER_UNSUPPORTED_PIPELINE |
| `t02-reg001-green` | 4/4 pass / 0 skipped | exit 0 / 0.3174s | 仅新增批准的两个 schema ID；原 requirement/architecture schema 字符串保留，节点数仍为 6/4/11/5 |
| `t02-reg002-003-red` | 29 tests / 5 pass / 24 fail / 0 skipped | exit 1 / 2.9838s | 完整 typed inputs/timeout 未受 digest 保护；CRLF 字符串和属性顺序不稳定；损坏 metadata 被接受；四模板均有节点字段丢失。原 loop/executor 摘要变化已有敏感性，继续保留 |
| 首次完整复测 | 55 tests / 54 pass / 1 fail | exit 1 / 5.0171s | 旧无权 Skill 夹具改坏 PRD repair target，新增悬空绑定校验先行拒绝；将该无权变更移至 checkpoint 槽位隔离授权验证，保留退出码/错误码断言 |
| `t02-green-final` | **55 tests / 55 pass / 0 fail / 0 skipped/cancelled/todo** | exit 0 / 5.0791s | 六个 canonical BIND/REG CP 名均实际执行 |
| `t02-structural-red` | 10 tests / 8 pass / 2 fail / 0 skipped | exit 1 / 1.1022s | 空的显式 repairNodeId 错误回退到 ref，空 passCondition 被接受；随后增加非空结构检查，不执行条件表达式 |
| `emitter-final`（首次交接） | **64 tests / 64 pass / 0 fail / 0 skipped/cancelled/todo** | exit 0 / 5.4673s | reporter duration 5418.6232ms；完整套件无 name filter |

实现对嵌套对象键排序并规范 CRLF（含 JSON 转义内的 prompt 文本），保留数组顺序及原始节点所有字段。完整 `pipeline.inputs`、节点执行声明及绑定共同进入 canonical body；顶层 inputs key 列表仅为同源派生兼容视图。结构错误复用 `PIPELINE_JSON_INVALID`；保留 active Skill、唯一 owns、输入 token 与权限校验，不增加表达式引擎或产品接口。

完整节点相等断言覆盖 coding 的三个独立 loop、code_generation、timeout/onFail/approvalPrompt，以及 passCondition/replayNodes/replayPolicy/attemptInput/maxAttempts 等嵌套字段；writeback 不凭空增加 loop。防御回归覆盖悬空 replay、forbidden 优先于 can-call、reviewer 与实际 repair 作者不同、inactive/unindexed Skill、重复维护 owner、inactive pipeline；只修改 scratch 权威文件，不修改真实 matrix。

architecture 测试不再称为 inert：从保存的原件独立导出的原始 digest 是 `sha256:77411d18f4dfaffbac1b601cb0b66bf4850be69edfa99b6f7d21304f29bdbc34`。测试验证 schema 稳定、完整 typed body、digest 确实变化且自洽，不伪称保留旧 digest，不覆盖旧 run 的存储摘要。

## 首次交接的相邻验证与历史失败

- `pipeline-structure.test.mjs` 当时结果：**36 tests / 35 pass / 1 fail / 0 skipped**，exit 1 / 0.2581s。精确失败标题为 `CR-2026-045: emit-registry 残留双花括号 token 硬失败且不输出空 registry`，原位置 lines 358–364；line 361 `assert.notEqual(r.status, 0)` 因 coding 已合法导出 exit 0 而失败，其后的 `RUNNER_UNSUPPORTED_PIPELINE`/空 stdout 期望亦已过时。此为保留的历史失败，不宣称现状仍失败；后续由主会话拥有负向夹具修正，本 worker 未编辑或重新判定其结果。
- 首次交接时并行检查：matrix CLI exit 0 / 0.0826s（56 active Skills，owns 唯一）；Agent CLI exit 0 / 0.0505s（10 Agents）；八份模板 JSON 可解析，exit 0 / 0.0447s；`skill-scope.test.mjs` **3/3 pass**，exit 0 / 0.1120s。Skill-scope 仅为当时文件状态的结果。
- 既有 matrix/Agent checker 测试 `matrix-agents-tests`：**11/11 pass / 0 skipped**，exit 0 / 0.6290s。
- 当时 `git diff --check` 对拥有文件 exit 0。`handoff-audit.json` 证明四个 S0 文件及 `.gitignore` 与进入时字节相同；移除四条新 executor 声明后，四模板对象与原始对象完全一致；writeback 模板字节未变，测试 BOM 保留。首次交接业务 diff 只有 emitter、既有测试、requirement/architecture/code JSON 五文件。
- T03 之前的 lint pass 保留既有 `skills/sync/handover-cr/SKILL.md:59 [OUTDATED] R5: attempts[]` 告警。最终联合 contract-scan/lint/quality 等待主会话在双方冻结后执行。不运行 35 文件/约 35 分钟大套件，不为隐藏差异编辑其他测试。

## 历史 preT03 候选 digest（原样保留，不是当前冻结值）

下表是**首次交接时的精确 preT03 候选**，不是部署、启用或旧 run 迁移证据。T03 已在修改输入/提示词，这些内容会合法改变摘要；不得用下表冻结或回写其他 worker 的字段，也不得覆盖旧存储摘要。

| Pipeline | schema 后缀（namespace `ai-first.pipeline-registry/`） | nodes / bindings | 历史 candidate digest |
|---|---|---|---|
| requirement-authoring | requirement-core-v1 | 6 / 5 | `sha256:fe6e6a3a06c6e26f5e59e3459197a6bf5292f465e571933c21fec0c687f8a7fd` |
| architecture-design | architecture-core-v1 | 4 / 3 | `sha256:d709a3a457279681d90e2ef968255cdcf71daa346d8d2aec788329d7d4b2e4e7` |
| code-implementation | code-core-v1 | 11 / 10 | `sha256:4609bd0e770e8086eb974bfba163682b7973451c264281556641593819ada214` |
| feature-writeback | writeback-core-v1 | 5 / 5 | `sha256:43b996c53ed9ef377a46145f2989d1a4462689029ae86418a6c90bdad6c5af20` |

完整历史 candidate JSON、原件/交接 SHA256 及全部 RED/GREEN 原始日志位于首次证据目录。首次增加的原节点 executor 声明如下；本轮不重写它们：

- requirement `…0011-…0004` / `review-requirement` → `quality-reviewer-agent`。
- architecture `…0016-…0002` / `review-tech-design` → `quality-reviewer-agent`。
- coding `…0015-…0014` / `review-dev-plan` 和 `…0015-…0009` / `review-code` → `quality-reviewer-agent`。
- coding `write-test-report` 不增加独立 reviewer executor；有 reviewLoop 不等于独立评审，仍由 `dev-agent` 执行。

## 第一轮独立 Spec 评审回修：两个 P2

依据主会话转达的独立 Spec 评审，先前真实 **64/64** 验证仍遗漏两处边界；该通过记录保留，不能替代新增反例。用户确认属于正常批准的小范围修复，无需额外人工决策。Standards 评审无问题的记录及最终两轴复核由主会话维护，本 worker 不编辑其评审文件。

本轮证据目录：`C:/Users/GOBAO/AppData/Local/Temp/aifi45-t01-t02-repair1-VgArgQ/`，保存 `entry-sha256.json`、`exit-sha256.json`、两个拥有源文件的进入时原件、`changed-line-anchors.json`，以及下列每次运行的 `.result.json`、原始 `.stdout.log`/`.stderr.log`。计时使用 `performance.now()` monotonic wall time，CLI 通过原生 `spawnSync(..., {shell:false})` 自然结束，不借用管道末端退出码。

### 两项独立 RED 与合法边界

在**同一未修复 emitter** 上并行运行两个独立负向回归，分别真实失败；没有以空匹配或跳过计为 RED：

| 证据标签 | 实际命令（均由 Node 执行） | 实际结果 | 自然退出码 / monotonic wall |
|---|---|---|---|
| `r1-missing-loop-red` | `--test --test-reporter=tap --test-name-pattern="R1: missing independent reviewLoop" pipeline-templates/emit-registry.test.mjs` | **1 tests / 0 pass / 1 fail / 0 skipped** | exit 1 / 0.2388s |
| `r1-ambiguous-ref-red` | `--test --test-reporter=tap --test-name-pattern="R1: ref-only repair" pipeline-templates/emit-registry.test.mjs` | **1 tests / 0 pass / 1 fail / 0 skipped** | exit 1 / 0.2344s |
| `r1-compatible-positives-before` | `--test --test-reporter=tap --test-name-pattern="R1: a unique repairRef\|R1: explicit repairNodeId" pipeline-templates/emit-registry.test.mjs` | **3/3 pass / 0 skipped** | exit 0 / 0.4226s |

1. **缺失 loop 可隐藏自审**：scratch requirement 中移除 review.reviewLoop；仅在 scratch matrix 中给 QA can-call PRD、移除该 Skill 的 forbidden（若存在），并将 PRD executor 与 reviewer 都绑定 QA。修复前实际 emitter exit 0，违反预期 exit 1。新回归名为 `TC-T-BIND-002 R1: missing independent reviewLoop cannot hide an authorized reviewer acting as author`。
2. **ref-only repair 多候选被取首个**：保留原六节点，仅将 checkpoint ref 改为第二个 `write-requirement-prd`，删除 review 的 repairNodeId、replayNodes/replayPolicy。没有 replay 消歧信息；修复前实际 emitter exit 0，违反预期拒绝。新回归名为 `TC-T-BIND-003 R1: ref-only repair with two candidates and no replay disambiguator fails closed`。
3. 保留合法边界三例：唯一 repairRef 不带 repairNodeId；重复 ref 时显式选原 PRD UUID；重复 ref 时显式选原 checkpoint UUID。三例在修复前已经 **3/3 pass**，修复后仍须通过，不允许全局 ref 唯一或要求所有 loop 都带 ID。

### 最小共享声明校验修复及改动位置

`pipeline-templates/emit-registry.mjs` 当前行锚点：

- line 110：`repairByNodeId` 保存每个 loop 唯一、已验证的 repair 节点。
- lines 118–121：独立 `review-*` ref 缺失 `reviewLoop` 即以现有 `PIPELINE_JSON_INVALID` 拒绝；普通无 loop 节点仍合法。已有 loop 必须继续通过原结构及 repair 关系校验，不猜作者或默认替代。
- lines 128–131：显式 repairNodeId 按 UUID 选择并验证 matching ref；不带 ID 则收集 matching repairRef，要求候选数严格等于 1，不再用 `.find` 静默取首个；随后保存该同源目标。
- lines 161–162：作者分离检查复用上述已验证的唯一 repair 节点，不另建与绑定规则可能分歧的 authors[] 推导。

既有测试 `emit-registry.test.mjs:163,254` 的两个 scratch review-code 夹具补齐合法 reviewLoop，以继续分别隔离“无权执行者拒绝”和“显式合法执行者与兼容权限事实分离”；原 status/error/权限断言未删除或弱化。新增五例从 lines 453、465、476、485 起（最后一处生成两例）。只增加版本化 R1 回归，未改写原测试英文标题、历史乱码注释或 BOM。

没有新增错误码、命令、flag、gate、权限、路由表或运行时算法；无真实 matrix 授权变化。当前四份真实模板在完整 emitter 套件中均合法；coding 的唯一 `write-dev-plan` ref 无 repairNodeId 仍合法。

### GREEN、完整验证与冻结

| 证据标签 | 实际命令（均由 Node 执行） | 实际结果 | 自然退出码 / monotonic wall |
|---|---|---|---|
| `r1-targeted-green` | `--test --test-reporter=tap --test-name-pattern=" R1:" pipeline-templates/emit-registry.test.mjs` | **5 tests / 5 pass / 0 fail / 0 skipped/cancelled/todo** | exit 0 / 0.5702s |
| `r1-emitter-full-green` | `--test --test-reporter=tap pipeline-templates/emit-registry.test.mjs` | **69 tests / 69 pass / 0 fail / 0 skipped/cancelled/todo** | exit 0 / 6.7930s |

完整套件显式 `--test-reporter=tap`，不加 name filter；reporter duration 6743.6367ms。原 64 例与新增五例均实际执行。两个负向回归通过既有 `refused` 同时断言 exit 1、`PIPELINE_JSON_INVALID` 和空 stdout；三个兼容正例继续通过。

本轮只读 `git diff --check -- pipeline-templates/emit-registry.mjs pipeline-templates/emit-registry.test.mjs` exit 0。进入/退出 SHA256 对比再次确认四个 S0 文件及 `.gitignore` 字节相同；测试 BOM 仍为 `efbbbf`。本轮未写任何模板 JSON 或其他 worker 文件；它们的并发变更不能当成本 worker 的改动，也不据此冻结其输入/提示词或更新历史 digest。未运行大 35 文件套件或施工中的联合质量任务。

**本轮 emitter、既有测试与本报告已冻结并交还主会话；此后不再写源文件。** 主会话恢复两轴独立评审并确认闭环、勾选 tasks；本报告不声称最终评审完成、整个平台完成或 Gate3 通过。

## 仍由主会话／后续受控流程负责

1. 主会话拥有的 pipeline-structure 负向夹具修正及其最终结果，不由本 worker 越权处理。
2. T03 冻结后的联合 caller-contract/contract-scan/lint/quality 验证，以及按最终输入/提示词重新导出 candidate digest。历史 preT03 候选不代表当前固定值。
3. T01/T02 第一轮回修的两轴独立复核，以及同源 multica generator/parser 消费合同核对；本报告不声称跨仓编译物或运行时验证通过。
4. pinned 旧 run 的迁移、activation 和部署仍需独立受控发布，绝不覆盖旧存储 digest。未执行 commit/push/branch/deploy/真实 CR/DB/新依赖/全局设置操作。

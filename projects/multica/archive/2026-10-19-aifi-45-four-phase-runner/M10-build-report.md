# AIFI-45 M10a / M10b — 生成合同与同源编译产物交接

## 最新收口（覆盖下文首次冻结/阻塞历史）

M10a/M10b 已完成生成动作验收。子代理能力恢复后，真实 Standards/Spec 旧六文件及 source delta 独立审查完成；producer 仅 writer prompt 恢复 inputs.source 非权威核对绑定，原 cr.md 参数/漂移即停/读失败不降空保留，Go renderer/恢复代码未改。新静态assert被caller扫描误报的中间RED亦保留，仅增强完整workspace正则，未改扫描器/白名单；独立窄复核关闭。

最终M10工具源259 manifest `073c75924e21f13c973bfeaa7197a33c98959004d00bab8f47fceafa6e034daa`，req body `f839d28c30ce2dc0eec709589f742abac1f45db96771d80a3ef3ef66a45ea32c`，其它三body不变；未提交BASEa5不冒充新revision。原生成链实际只更新gate来源头与requirement JSON/digest/header，M10闭合时其它四文件原SHA不变；六SHA见M10-source-repair-report修订表（后续M11正常会改变共有parser/test，不能沿用这表宣称后续候选不变）。

Main当前收口整包native0/40.292777400s、195父PASS+108子PASS/1既有LiveGitHubSKIP、304RUN/完结、0FAIL/DBskip；tools8完整213/213 native0/7.095790200s；gen默认check0/0.345544000s；后端build0/8.887457500s。259tools/3594server运行前后不漂移。证据`%TEMP%/aifi45-m10-repair-e4o5e8vm/main-closeout/`；main-final保留中间caller-09 RED，source-producer-repair-evidence保留source真实RED/GREEN。详M10-review.md；ADJ-T-004已minor/resolved，4个M10动作即时勾选，CP005/007及SC003整个runtime义务未因此结束。M11现单writer接权、未完成；33551本批自建PG继续已授权后续测试由Main最终清理。以下保留首次冻结与当时失败/工具禁用历史，不代表当前停点。

## 首次冻结状态与边界（历史）

- **实现与本轮定向验证已完成，源码冻结并释放给 Main；不自动勾选任务。** Main 接收后先唯一执行新候选 governance 整包回归及独立 Standards / Spec 审查，再决定 M10a/M10b 完成登记和交给 M11。本执行者没有再跑整包，也没有把定向绿当整包绿。
- 开工前实际读取 `multica/CLAUDE.md` → `AGENTS.md`、本 change 的 design/tasks/slices、canonical code/agent `four-phase-runner-dispatch.yaml`、implementation-notes I5，以及 tools TREG-handoff 和完整临时 handoff。
- 前置 M00 已真绿：读取 Main 的 `aifi45-m00-repair-izez2oby/governance-full-result.json`，native exit0、单调 20.688403600s、269 run/269 finished、193 顶层 PASS + 75 子测试 PASS + 1 既有 `TestReconcileLiveGitHub` SKIP、0 FAIL、无 DB skip。此为接收的前置证据，不冒称本执行者重跑。
- M10a 支持、M10b 生成部分承载 **TC-MDISPATCH-005 / M-CP-DISPATCH-005**。新增实际函数名为 `TestMDispatch005Generator`、`TestMDispatch005`，均已真跑 PASS，避免未来 `-run` 空匹配。**整个 005 的后续 parser 消费/运行时输入能力义务仍待 M11 等后续切片；M-CP-DISPATCH-007 所需 actual `TestMDispatch001` 也仍待后续实跑，M00 哨兵和本轮 005 不能替代 001。**
- 无 parser/Runner 实现或旧 parser 测试改动；无运行时启用、旧 run digest 更新、schema/CLI flag/新工作流引擎、依赖/安装/系统设置变更；无 commit/push/deploy、真实 CR 或审批操作。

## 独占文件与实际差异

路径相对 `C:/Users/GOBAO/Downloads/AI/multica/`：

| 文件 | 本轮内容 | Git numstat（新增/删除） |
|---|---|---:|
| `server/internal/governance/gen/generate-gate-nodes.mjs` | 扩展原 emit → 校验 → gofmt → 生成/check 链；四 schema、完整 raw 字段对照、Node full-body digest、真实来源头、保留行尾 | 116 / 88 |
| `server/internal/governance/runner_contract_test.go` | 只增加 M10 生成/编译合同与临时夹具 helper；原三函数名称和断言逐字保留 | 377 / 0 |
| `server/internal/governance/gate_nodes_gen.go` | 原三个审批/评审投影不变；更新完整 architecture 快照、digest 和来源头 | 3 / 3 |
| `server/internal/governance/requirement_registry_gen.go` | 原生成链更新 requirement 完整快照与来源说明 | 8 / 15 |
| `server/internal/governance/code_registry_gen.go` | 新增 code 完整快照 | 新文件 13 行 |
| `server/internal/governance/writeback_registry_gen.go` | 新增 writeback 完整快照，无新增 gate/loop | 新文件 13 行 |

本轮唯一过程记录为本文件；没有写 CUSTOM/tasks/phase-context/allphase/adjustments 或 producer。`approval_crosscheck_test.go` 未触碰，其 canonical-LF SHA-256 始终为 `3785cd12d4f7001d000884134efeeb648241d04c07e5bea60c37f00adb011885`。工作树中 Main 的 CUSTOM 和该已释放 fixture 差异不归本轮。现有三个 `runner_contract_test.go` 测试函数体与 HEAD 按 LF 逐字节相同。

## 实现选择

1. 保留原脚本、`--tools`、默认 sibling tools 路径、`--check`、原生 emitter 子进程和 gofmt/source 编译链。四份 export 全部成功并校验完、全部 gofmt 成功后才写产物；读取/解析/导出失败不转空数组、不静默回退。
2. 保留 `ai-first.pipeline-registry/architecture-core-v1`、`.../requirement-core-v1`；新增 `.../code-core-v1`、`.../writeback-core-v1`。拒绝错误 schema/pipeline、缺失 nodeId/executor、重复 nodeId 或权限覆盖错位、错误 digest 和 raw 字段漂移。
3. 完整 `pipeline.inputs`、所有 nodes（含 prompt/approvalPrompt/timeout/onFail/reviewLoop/passCondition/replayNodes 等）与真实模板投影 `{id,name,inputs,nodes}` 对照，不能用不完整 Go struct 计算“等价”快照。顶层 inputs 必须严格等于声明 key 的原顺序列表；输入声明缺失/不完整、重复 key、顶层列表错序均拒绝。
4. Digest **精确匹配实际 emitter 算法**：读取文本先 CRLF→LF，模板字符串递归规范 LF、嵌套对象 key 排序、数组原序；body 外层保持 `pipeline,pipelineOwner,nodePermissions`，pipeline 保持 `id,name,inputs,nodes`，权限对象保持 `nodeId,ref,owner,pipelineOwnerCanCall,executor` 顺序，再由原生 Node `JSON.stringify` + SHA-256 复算。不是 schema-only，也不是把整个外层随意排序后换算法。
5. 最小 provenance：确定性头为 `Source: tools working tree (BASE <HEAD>); <pipeline> <actual body digest>`。gate 文件头列出其三个投影来源 body digest，其余文件列本快照 digest。BASE 仅表示 Git 基点，不声称 dirty body 已提交；无 Git 的临时夹具明确写 BASE unavailable。没有硬编码候选 commit/manifest、新 flag、通用 manifest 框架或运行时账本。`--check` 比较完整生成文本（只规范物理 CRLF），**不再忽略来源头**；四文件各自 header 篡改负例均拒绝。
6. Go 稳定符号保留 `ArchitectureCoreRegistryJSON/Digest`、`RequirementCoreRegistryJSON/Digest`；新增供 M11 消费的 **`CodeCoreRegistryJSON` / `CodeCoreRegistryDigest`、`WritebackCoreRegistryJSON` / `WritebackCoreRegistryDigest`**。JSON 沿既有方式为 var、digest 为 const。仅编译 snapshot，不接通 code/writeback 的运行时 parser/dispatch。
7. **投影数量以原 selector 的实际职责为准，不以“三”作为四阶段编译元数据上限。** 原 `STAGES` 未改：按 pipeline 找第一个指定 `reviewRef`，再找其后第一个 `kind=human_approval`；不存在则硬失败。实际生成的 `ReviewGateNodes` / `ApprovalGateNodes` 仍各 3 项：

   | stage / pipeline | reviewRef / 1-based seq | human approval seq |
   |---|---|---:|
   | requirement / requirement-authoring | review-requirement / 4 | 5 |
   | tech-design / architecture-design | review-tech-design / 2 | 3 |
   | code / code-implementation | review-code / 9 | 10 |

   节点 UUID 与原产物相同（可见 owned.diff）。**code 真实声明的三 loop：seq3 review-dev-plan、seq7 write-test-report、seq9 review-code，全部进入完整 code 快照**，不是只保留旧 ReviewGateNodes 选中的 review-code。writeback 实际 0 human / 0 loop，不造 gate/loop。开发计划/测试/上游新判据的投影消费由 M24 等后续切片实现，本轮不启用 runtime 路由。权限 actor key 的源级真实性承接冻结 TREG（本轮也核对 nodeId/ref/executor 与模板）；workspace Agent UUID/权限解析仍是 M11/M12 后续职责。

## 冻结来源及四份实际 export

- tools BASE：`a5ecb5783fd8f7b5fa1d0d3b328b704199bbe011`，**未提交候选**。
- 259 个 tracked 文件 canonical-LF manifest：`eb99e18aad2292a614a133b35a9265b6505c852a0bf7897c519e4dbf973d6984`。
- 开工、每次 Go/gen 运行前后及最终逐文件对照 `C:/Users/GOBAO/AppData/Local/Temp/aifi45-treg-final-6gl_4tqr/handoff.json` 全部相等，无 producer drift。
- 最终实际执行四次原生命令 `node <tools>/pipeline-templates/emit-registry.mjs --pipeline <id>`；四份完整 export 与新编译 JSON **逐字节相同（去末尾换行）**，与 frozen `<id>.json` **canonical-LF 字节相同**，完整 inputs/nodes 与真实模板相同、顶层 key 列表一致、独立 Node 复算 digest 一致。冻结 JSON 的物理 CRLF 在外部比较器中先规范 LF；首轮外部比较器漏规范导致的字节比较失败已修正，仅属证据脚本，不是产品补丁或合同变化。

| pipeline | schema 尾段 | nodes / permissions / loops | 最终 body digest |
|---|---|---|---|
| requirement-authoring | requirement-core-v1 | 6 / 5 / 1 | `sha256:8d836fc71f1274f035852a7fcf4cf1e28783a5f3584ca68d4acf77370772882d` |
| architecture-design | architecture-core-v1 | 4 / 3 / 1 | `sha256:11970fe3aec6013ff88117eda212617fec4b395e45c52057d157fd8112f2aeb5` |
| code-implementation | code-core-v1 | 11 / 10 / 3 | `sha256:ee6461ff376646dba36f64d57dfd4482c1e6f6532e049ce6547350b1c7175a88` |
| feature-writeback | writeback-core-v1 | 5 / 5 / 0 | `sha256:6a63a222146eb018564cd0487e8b1ab5352f832fd3d972f6c065ff7010c01108` |

合计 26 nodes / 23 nonhuman permissions；不以四个 PipelineIDs 代替四份完整编译合同。

## TDD 与原生验证

### 执行隔离

- Go 仅使用 Main 指定的 `aifi45-m00-repair-izez2oby/private-connection.json`，校验目标为 `127.0.0.1:34131 / aifi45_test / aifi45`，显式取 `DATABASE_URL` 与 `CRCTL_PATH`；没有打印/写入公开记录任何 DSN 或凭据，没有读取 `.env`、默认 DB 或继承的外部连接。
- 子进程环境为 PATH/SystemRoot/Temp/profile/Go cache 等运行必需白名单；显式 `GOTOOLCHAIN=local`、`GOPROXY=off`、`GOENV=off`，Go 命令 `-mod=readonly -count=1 -v -json`。不继承 KNOWLEDGE_BASE_REMOTE_URL/TOKEN、Node 配置、外部任务/认证变量；Git system/global 配置仅在子进程环境隔离，未禁用/修改 repo hooks，也没有提交类命令。
- 本轮是唯一 DB 测试执行者。没有容器/卷/runtime/迁移操作，资源仍归 Main。缺配置或 DB skip/零 case 会使证据采集器停止，不默认回退。
- 工具集中没有可用 context-mode API；用原生 read/edit 检查文件、OS Temp 持久原始日志和小型 JSON 汇总，未绕过路径权限。

### RED → GREEN

全部 Go 命令工作目录 `multica/server`，前缀：

```text
go test -mod=readonly -count=1 -v -json -timeout 900s ./internal/governance/ -run <selector>
```

900s 为从首次运行即固定的进程保护，未为换绿提高 timeout；所有实际运行均远低于该值。

| 运行 / 选择器 | native exit | 单调秒 | 顶层终态 | 子测试终态 |
|---|---:|---:|---|---|
| RED `^TestMDispatch005Generator/four_exports_full_fields_and_check$` | 1 | 3.998693600 | 1 FAIL | 1 FAIL |
| RED `^TestMDispatch005(Generator)?$` | 1 | 8.739734300 | 2 FAIL | 33 FAIL |
| 最小 generator 修复后 `^TestMDispatch005Generator$`（尚未更新业务产物） | 0 | 21.216418500 | 1 PASS | 29 PASS |
| 实际生成/check 后，生成+编译合同+既有 parser 正向组 | 0 | 20.239696100 | 9 PASS | 40 PASS |
| 既有 `^TestReviewMaxAttemptsRefusesInvalidDeclarations$` | 0 | 2.928244800 | 1 PASS | 6 PASS |
| **最终合并定向组（下面精确 selector）** | **0** | **19.864458500** | **10 PASS** | **46 PASS** |

- 首个 RED 明确为 **`code-implementation export was not requested exactly once`**，实际只请求了 architecture/requirement；不是编译/环境/DB 失败。完整 RED 又锁定新阶段缺产物、旧快照缺完整 inputs、新阶段坏导出未被消费等合同缺口。
- 每次上述 Go 运行均有正数实际 run 与全部终态，**0 SKIP、无 `Skipping governance integration tests`**；GREEN 没有删除/减弱旧断言或排除旧测试。最终数不能与前面重复运行相加宣称新增覆盖。
- 最终 selector：

```text
^Test(MDispatch005(Generator)?|ParseCoreRegistryFixedContract|RenderCorePromptOnlyDeclaredTokens|ArchitectureRunnerFeatureFlag|RequirementRegistryIsTheCompiledContract|RequirementDirtyStartNodeIdentities|RenderRequirementPromptRefusesRegistrationInputs|ReviewMaxAttemptsFollowsTheDeclaredRegistry|ReviewMaxAttemptsRefusesInvalidDeclarations)$
```

新增测试重点：临时复制**现有 generator**、四 schema/export/full raw round-trip、重复 ref 但独立 nodeId、executor、三 loop / 无 loop、同源顶层 keys、物理与 JSON 字符串内 CRLF；12 类 full-body 变更（input type/required、executor、prompt/approvalPrompt、timeout、onFail、reviewLoop、node/input 顺序、owner/授权）分别要求 digest 改变且旧 `--check` 拒绝；13 类坏 export（schema/pipeline/topkeys/缺 raw input/raw node drift/缺 nodeId/executor/重复或多余权限/executor drift/stale digest/坏 JSON/导出失败）要求非零且不写任何产物；四文件来源头篡改分别拒绝。编译值通过 Go AST 读取必需的单一字符串 literal，缺匹配/字段硬失败，不用跨行正则猜测或 catch→empty。

### 原生生成 / 检查 / 格式

| 命令 | native exit | 单调秒 |
|---|---:|---:|
| `node internal/governance/gen/generate-gate-nodes.mjs --tools <frozen tools>` | 0 | 0.287509900 |
| 同命令 `--check` | 0 | 0.336384700 |
| 最终从 server 原默认 sibling 路径执行 generator `--check` | 0 | 0.340514000 |
| 最终独立四 export + 字节/模板/Node digest 比较器 | 0 | 0.268959900（总进程；各 export 时间见原始 JSON） |
| `git diff --check` | 0 | 0.132637800 |

所有 Go 定向命令均原生编译整个 governance 包及四份 Go 产物后实际运行目标测试；没有用静态文本检查冒充 source compile。五份 owned Go 文件分别先规范 LF 后送原生 gofmt，全部 exit0 且字节不变；保留原 checkout 的 CRLF。生成器原 UTF-8 BOM 保留，四份产物与测试无 BOM，所有 owned 文件无混合行尾。未运行治理整包/全仓 Go/TS/E2E，不声称对应覆盖。

## 冻结源码内容身份

路径相对 `server/internal/governance/`；完整 raw + LF hash 与 CRLF/BOM/gofmt 结果见 `final-verification.json`。

| 文件 | canonical-LF SHA-256 |
|---|---|
| `gen/generate-gate-nodes.mjs` | `948d8361b61546654027ed770b5e5551619f5f10238f70e0f215d51f69013483` |
| `runner_contract_test.go` | `e3a6024e512c456687d0ff4012167bf03b57b0e648d4ceed1ffdb18117e7b5c2` |
| `gate_nodes_gen.go` | `d03a9b4e92619214c55ee448a5e850e3b4b805e163c9b8df8a8a8c233b8456c5` |
| `requirement_registry_gen.go` | `9d0cacc9553cd0a179ba579881adcb6ea8736e4946f79af5155f21306cd8e060` |
| `code_registry_gen.go` | `3c7404d7ed159c4ae4c1a52c615d93b82568767d92fccbd3d3835b3ad8c94973` |
| `writeback_registry_gen.go` | `34039ae8a1749cda2173bde74146e18eba281af7887e8383cf8fcd09822e9c27` |

## 持久证据与 Main 后续

显式 OS Temp 证据目录（非 ctx sandbox，不依赖会话自动清理）：

```text
C:/Users/GOBAO/AppData/Local/Temp/aifi45-m10-evidence/
  run.py                                  # 显式私密配置、白名单环境、native exit/单调计时/实际事件统计
  red-generator-*, red-all-contracts-*     # RED stdout JSONL、native 可读输出、stderr、结果与源快照
  green-generator-*, green-contracts-*, green-existing-negative-parser-*
  final-focused-*                         # 最终 10 top / 46 sub PASS，0 skip、无 DB skip
  native-generate-*, native-check-*        # 实际原链输出与结果
  verify-exports.mjs, verify.py            # 外部证据核验器，不是产品/测试框架
  <pipeline>-export.json                  # 四份重新实际导出及 stderr
  export-comparisons.json                 # 各 export 自身 native exit/单调时间、digest/字节/模板对照
  final-verification.json                 # 六文件 raw/LF hashes、BOM/CRLF/gofmt、fixture/源不变证明
  default-cli-check-*, verify-exports-*, diff-check-*
  owned.diff, owned-numstat.log
```

1. **文件与 DB 测试执行权现全部交回 Main。** 本执行者返回后不再修改 owned 文件/启动 Go DB 测试。Main 可立即独立审查并在同一已授权目标唯一执行整包；无需等整个 Runner 完成才验 M10 新候选。
2. 正式 CI tools pin 仍为 `9d0a6a7fd7690c5e43b1dab829a20ff430ae9828`，不能复现未提交未来 export；**这是等待另行授权 commit + pin 对齐的发布阻塞，不是本地实现阻塞**。没有改 workflow/pin，也没有用旧 digest/假 commit 隐藏该事实。
3. 已读取 Main 新登记的 implementation-notes **I6**：M11 可依上述四组稳定 JSON/Digest 符号接公共 parser；保留 trusted 编译 JSON/独立预期 digest pair guard（schema/pipeline/envelope/expected digest）及 run context template_digest 校验，保留完整 raw envelope、typed 只作派生视图；**不新造近似 Go canonicalizer，不开放任意请求/DB raw registry-body 信任入口**。保持原 architecture/requirement API 名，按 nodeId 绑定、多 loop/no-loop、完整输入解释，不将本轮 Node 编译期 SHA 校验当运行时载荷真实性或后续执行完成。既有 `TestReviewMaxAttemptsRefusesInvalidDeclarations` 仍断言 code/writeback 暂不被运行时 bound reader 支持，原断言保留；后续正式扩展时由对应切片按合同处理，不能在 M10 偷改它。
4. 建议 Main 在现行 CUSTOM #26 的既有追溯中追加：**AIFI-45 / M10a/M10b：原生成链编译四阶段完整 registry，独立 Node digest 与 raw/export 一致，工作树 BASE provenance 纳入 check；新增实际 TestMDispatch005，定向 10 父/46 子 PASS，无 skip；仅生成合同，不启用运行时、不覆盖旧 digest，整包与后续 parser 验收另列。** 本执行者不写 CUSTOM、不新增 SSOT 编号/metadata。

## Main 冻结候选整包回归：真实 RED，独立审查受权限阻塞（2026-10-19）

接收六文件和唯一 DB 测试执行权后，Main 原样执行全 governance 包，无 `-run` / skip / 文件排除：

```text
go test -mod=readonly -count=1 -v -json -timeout 1500s ./internal/governance/
```

| 项 | 原生结果 |
|---|---|
| native exit / 单调耗时 | **1 / 37.43918269989081 秒** |
| 父测试 | **192 PASS、3 FAIL、1 SKIP** |
| 子测试 | **108 PASS、0 FAIL、0 SKIP** |
| RUN / 完结事件 | **304 / 304**（父/子分层事件，不相加冒充独立父用例） |
| 既有外部 skip | 仅 `TestReconcileLiveGitHub`，没有新增 skip/exclude |
| DB 提前空跑 | 无 `Skipping governance integration tests`，实际正数用例 |
| 内容身份 | 3594 个 tracked+非忽略 untracked `server/` 候选文件前后一致（含两个新增生成物）；tools259文件 manifest仍 eb99e18aad2292a614a133b35a9265b6505c852a0bf7897c519e4dbf973d6984，未漂移 |

失败均为既有 requirement source 记录/传递/恢复契约：

1. `TestRequirementWriteNodeRendersOnlyWithARecordedSource`（`runner_requirement_test.go:477`）：缺 recorded source 仍渲染 writing node。
2. `TestRequirementAdoptsProjectorRunAndRecordsInputs`（同文件 `:1623`）：adopt 后 writer prompt 未携带已记录 source；原生日志可见新模板中的 `{cr.md source 原样值}` 文本。
3. `TestRequirementResumeFreshRunKeepsTheRecordedSource`（同文件 `:2485`）：新 run 恢复后派发 writer 丢失 recorded source。

这是**一次全包运行的三个失败**，不是同一问题连续三轮修复失败；本轮未尝试修它们。需要后续 trace 真实 producer prompt → renderer / run-context → 恢复调用链确定最小根因，不能改断言、伪造 source、回退旧生成物或绕过 recorded-source 保护来求绿。M00 的早先 test-only 绿基线保持为历史候选证据，不拿它替代这次新候选结果。

### 独立审查没有执行，M10 未完成、M11 未开始

Main 在开始上述整包回归时并行请求 Standards 与 Spec 两路独立 reviewer；**两次 Agent 调用均返回原文 `Pi Web built-in sub-agents are disabled`，没有创建 reviewer session**。主会话没有修改权限设置、没有通过其它工具/SDK 绕过该限制、没有用自审或作者报告冒充独立审查。此为环境/工具权限阻塞，需要用户恢复当前会话的内置子代理能力，或明确提供满足作者/评审分离的独立审查方式；不是新增业务审批节点。

因此 M10a/M10b 虽已实现并定向绿，**未在 tasks 标记完成**；M11 parser、M12–M15 与 runtime 业务代码均未开始。作者的原生生成/check 成功证据保留；Main 驱动器在全包失败断言处结束，后置的 Main 默认 generator `--check` 没有执行，不将作者结果混为 Main 结果。

### 本批资源已清理（确切归属验证）

- 在 finally 中先验证 container 与 named volume 的 `io.aifirst.test-run=aifi45-m00-repair-izez2oby` 标签，核对唯一 mount 名称后，仅删除 `aifi45-m00-repair-izez2oby-pg` 与 `aifi45-m00-repair-izez2oby-data`。
- 两次 remove native exit 均 0；随后精确 `container exists` / `volume exists` 均返回 1（不存在）。第一次紧随删除的 TCP 检查仍可连接，后续独立复核 `127.0.0.1:34131` **已关闭**，最终 `cleanup.complete=true`。保留首次检查，不把瞬时端口状态说成数据库还在或擅自停止 Podman machine/代理。
- 只在确认自建资源删除后移除本次 `private-connection.json` 与 `pg.env`；旧 DSN 已失效且私密文件不再存在。没有停止既有 Podman machine/服务、没有 prune、没有触碰任何已有容器/卷/数据库。
- 后续恢复时，Main 须在现有用户授权内再创建并迁移同类专属临时 PG、提供新私密配置，不能重用上述删除的连接文件或默认数据库。

Main 证据根：`C:/Users/GOBAO/AppData/Local/Temp/aifi45-m10-main/`：

- `governance-full.jsonl`、`governance-full.stderr.log`、`governance-full-result.json`、`failures.json`：完整原生事件/分层计数/失败明细。
- `server-before.json` / `server-after.json`：覆盖新增文件的冻结候选哈希。
- `supervisor-result.json`：保留全包断言触发的收尾记录，不代替 native exit。
- `cleanup.json`：含真实 container ID、唯一 volume/mount、标签校验、删除/存在性原生 exit 与最终端口关闭复核；同步到 setup 证据目录。

Main 已在 `CUSTOM.md` 既有 #26 保留 M00 历史，并按当时最大稳定 ID #138 顺延新增 **#139** 登记 M10 六文件，模块 M4/CR索引同步；标记在途/未提交/整包失败/审查阻塞，不冒充已验收。未 commit/push/部署/真实 CR/存量接管/Gate3。

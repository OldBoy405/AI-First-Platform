# AIFI-45 M11 — 四阶段 registry parser 合同与真实行为 RED/GREEN

## Main 最终动作验收（覆盖下文首次冻结/中间修复历史）

原3P及新增REV004均由真实反例RED→GREEN并经两位独立reviewer最终逐项关闭，无新hard P。最终TestMDispatch003 70P、原130邻接P/0skip、原58/50cases与427raw前缀保持；仅三授权Go文件，Raw同源presence校验，不造GoSHA/DSL/新输入或引擎，非空policy无nodes按emitter合法，普通非review无loop不阻。

Main当前独立完整native0/36.797773400s、196父+177子PASS/1既有LiveGitHubSKIP、374RUN/374完结、0FAIL/DBskip，gen default check0/0.345719300s、vet0/0.474851800s、backendbuild0/3.433185000s，3594server/259tools前后稳定。证据`%TEMP%/aifi45-m11-main-final-r2/`；旧354/362/RED及作者目录分开保留，不把模型或旧候选数字替代当前原生结果。

最终LF身份：runner3c7e58d12a6e956bab41bc4c1f16be5a9d0c9533a96b71f2d9e242a8c117ac8f；req-registry27fa7d145e0d8241b2902910ca7ec28788fbdcefd658858d832362594aa5e112；contract5817850ffbcd54961874621d37e74c88f931f679109b4bd262d6d23e192df7a9。tools073c…与四body/生成物保持M10 source修订，未提交BASEa5，不覆盖存量digest。

M11两动作已勾、CUSTOM#140；完整walker/CP003/005/007/最终四阶段验收仍未闭合。M12单writer新会话01a154e9-42d6-75ce-a57c-1bb8277722e4接权，33551本批测试PG继续授权切片/由Main最终清理，无部署/真实CR/Gate3。详M11-review.md最新节。

## 首次冻结点（历史）

- **M11 parser 实现与本轮验证已完成，三份 source/test 已冻结交回 Main；未自动勾选 task、未 commit/push/deploy、未执行真实 CR/Gate3、未删除 PG。**
- 本切片只承载 **TC-MDISPATCH-003 / M-CP-DISPATCH-003** 的 parser 动作，并为 **TC-MDISPATCH-005 / M-CP-DISPATCH-005** 提供 parser 消费证据。M11 不是 SC003 整个 Runner walker、也不是 CP005/007 全链闭环；M12 actor/UUID 绑定、M14/M15 carrier、M20 canonical 结果消费仍 pending。
- 未修改 producer、`gen/generate-gate-nodes.mjs`、四份 `*_gen.go`、handler、daemon、API/CLI flag、权限/业务状态；未新增依赖、schema 或第二套 Runner/validator。
- 唯一过程记录为本文件；`CUSTOM.md`、tasks/phase-context/ledger 未触碰。

## Source 保护与冻结哈希

三份写域在 RED 前已记录 raw/LF 哈希，完成后仍为 UTF-8 无 BOM、全文 CRLF。原始 `runner_contract_test.go` 前 427 行逐字节未变（SHA-256 `5430fb7c86944221eed8a31d8291edf84842cd802236b5548eeafba9e0202b73`），原测试函数与断言全部保留；M11 仅追加 `TestMDispatch003`。

| 文件 | before raw | before LF | after raw | after LF |
|---|---|---|---|---|
| `server/internal/governance/runner.go` | `7b735f24d4faaff5373114bd42eee822487ec929d9153c7d80507faacd6d9e4c` | `f643b595f827d8706eddc8bd76a6099975c09ae1a93501f77c0ab5a4e8523b09` | `07974a799c0eef5415fa3b8b04a95251f315a30aeb17b00c91ad3e17e0d1e668` | `2524e7192fc6fd30d3225602959b63279c26716237084249622773f77b01191f` |
| `server/internal/governance/runner_requirement_registry.go` | `785b0899e9ecb81c274889369575c1631cae868f9a585e4c90186c3fa1d25e49` | `401cfd29da3d2095141a7ff4cba9c242611e9cc87ad7cb1889f80eb8203860de` | `d3a3cd94ea3014766bf8efc52017e443763eb4f5ee1ea027bf9774c4eee719e3` | `16cc22604f497923bcaeb3b8b33f7b43b6876979bee1a7ed2a19f2f1548cc313` |
| `server/internal/governance/runner_contract_test.go` | `5430fb7c86944221eed8a31d8291edf84842cd802236b5548eeafba9e0202b73` | `e3a6024e512c456687d0ff4012167bf03b57b0e648d4ceed1ffdb18117e7b5c2` | `88b085d42f6d4851d99c86acbb381dd2291df59ffc2aa6dbdb32a25e51add5d2` | `18bc44535b9199762553de11fc8835aedde2131ee0b68d91e908454b3d6cce8f` |

M11-only 行数变化（相对已含 M10b 的 pre-M11 工作树）：`runner.go` 1123→1307，`runner_requirement_registry.go` 330→306，`runner_contract_test.go` 427→886。

四份生成物仍为 M10b 冻结值，未重写；native `--check` exit 0：`four registry snapshots and gate nodes consistent (tools working tree, BASE a5ecb57)`。

| 生成物 | file SHA-256 | body digest | nodes/perms/loops |
|---|---|---|---|
| `requirement_registry_gen.go` | `90ee5d1fbfd91ce2677f821e614f6727fa8d3354f2d8593b93a2a50ae5a18951` | `sha256:f839d28c30ce2dc0eec709589f742abac1f45db96771d80a3ef3ef66a45ea32c` | 6 / 5 / 1 |
| `gate_nodes_gen.go` | `e9a923b2754cb6e0e48f82ad9c796a303243acfcab3f2165a80e81d9efabf00e` | `sha256:11970fe3aec6013ff88117eda212617fec4b395e45c52057d157fd8112f2aeb5` | 4 / 3 / 1 |
| `code_registry_gen.go` | `2a19bd871c5a3480936bebad883a61d571509b00829b9e2c4966bf80e3dfe3e5` | `sha256:ee6461ff376646dba36f64d57dfd4482c1e6f6532e049ce6547350b1c7175a88` | 11 / 10 / 3 |
| `writeback_registry_gen.go` | `44819dcb4d0ca80b6cbb595d08c459f30993d7cd5fe8c78b5af460c7350c242b` | `sha256:6a63a222146eb018564cd0487e8b1ab5352f832fd3d972f6c065ff7010c01108` | 5 / 5 / 0 |

## 实现

1. **完整 wire 保留**：`coreRegistry.Raw` 保存 CRLF→LF 后的原始 envelope；`Pipeline.Inputs`、node `executor/approvalPrompt/timeoutMinutes`、完整 `reviewLoop`（repair/replay/passCondition/maxAttempts 等）与五字段 `nodePermissions` 为派生 typed view，不替代 raw。未知字段测试确认 raw 不丢。
2. **共享四 schema 入口**：`parseCoreRegistryFrom` 按 `{schema,pipelineID}` 精确匹配四组编译合同；expected digest 必须等于该组编译常量，body 自报 digest 不具权威性。未知/不完整 schema、pipeline、envelope、digest 均 fail closed。
3. **取消固定节点/唯一 ref 假设**：不再固定 4/6 节点、loop 位置或 ref 唯一；严格唯一 nodeId，重复 ref 由 nodeId 精确关联。权限按 nodeId 覆盖全部非 human 节点，`ref/executor` 必须与节点同源并保留五字段；human 节点不携带执行权限。
4. **loop 声明按原样解释**：保留完整 repair、replay、passCondition、maxAttempts；repair 显式 ID 优先，无 ID 时仅唯一 ref 可用。coding 三 loop 保留，writeback no-loop 不造默认 loop/gate。输入声明要求 key/type/required 完整、key 唯一；顶层 inputs 必须逐项等于 `pipeline.inputs` 派生 key 列表。
5. **requirement 入口复用同一 validator**：`parseRequirementRegistryFrom` 调用共享 parser，仅追加 requirement 状态机实际消费的 node ref、独立 reviewer 与 PRD repair target 语义；不再维护第二套通用校验或 legacy fallback。
6. **边界保持**：requirement `renderRequirementPrompt`/`mergeRecoveryInputs`、架构/需求 Runner 状态机与恢复路径未改；未写 Go canonicalizer，不用丢字段 struct 计算等价 SHA；attempt-bound fixture 的“改 body 保 digest”仍是既有内部受控 seam，未加生产豁免、未删断言。`ReviewMaxAttemptsFromSnapshot` 增加 snapshot 必须声明所请求 pipeline 的检查，避免四 schema 泛化后跨 pipeline 误读。

## 测试与证据

DB 仅使用 Main 指定私密配置 `C:/Users/GOBAO/AppData/Local/Temp/aifi45-m10-repair-e4o5e8vm/private-connection.json`，核实目标为 `127.0.0.1:33551 / aifi45_test / aifi45`，run_id `aifi45-m10-repair-e4o5e8vm`。子进程仅白名单环境，显式 `GOENV=off`、`GOTOOLCHAIN=local`、`GOPROXY=off`、`GOFLAGS=-mod=readonly`，未继承外部 DB/token/KB/.env，未输出 DSN/password。

### RED（真实行为，非 undefined symbol）

- 命令：`go test -mod=readonly -count=1 -v ./internal/governance -run '^TestMDispatch003$'`
- native exit **1**；**11 RUN / 6 PASS / 5 FAIL / 0 SKIP**。
- 真实失败：共享 parser 对 `requirement-authoring`、`code-implementation`、`feature-writeback` 均报 `registry identity or digest mismatch`，仅 architecture 通过；证明固定 architecture contract 尚未泛化。原有 raw 声明子组已 PASS，说明 RED 来自 parser 行为而非测试构造。
- 日志：`red-testMDispatch003.log`。RED 先锁定共享 parser 的初始行为子组；GREEN 后在不改变生产行为的前提下补齐 typed/fail-closed/CRLF/bound 子例，最终同一 `TestMDispatch003` 为 50 个 RUN/PASS。

### GREEN

- 同命令最终 **50 RUN / 50 PASS / 0 FAIL / 0 SKIP**，native exit 0；覆盖四 schema、typed views、重复 ref、显式 repair ID、唯一 ref、requirement 复用、CRLF 规范化、cross-pipeline bound 拒绝及 26 个 fail-closed 子例。
- 原合同/req/attemptbound/renderer 邻接定向回归 **21 RUN / 21 PASS**，含 `TestMDispatch005`、`TestParseCoreRegistryFixedContract`、`TestReviewMaxAttemptsFollowsTheDeclaredRegistry`、`TestRequirementRegistryIsTheCompiledContract`、renderer 原测试。
- 完整治理整包：native exit 0，**354 RUN / 353 PASS / 1 SKIP / 0 FAIL**（196 父 PASS + 157 子 PASS；唯一 skip 为既有 `TestReconcileLiveGitHub`，无 DB skip），Go 报告 32.818s。`TestMDispatch003` 在整包内实际 RUN/PASS。
- `go vet ./internal/governance` exit 0；`go build ./...` exit 0；`git diff --check` exit 0。
- 证据目录：`C:\Users\GOBAO\AppData\Local\Temp\aifi45-m11-evidence\`，含 RED/GREEN/full/targeted 日志、full `-json` native 单调时间证据 `green-full-governance.json`、实际 case 集 `cases.txt`、`gen-check.log`、`vet-governance.log`、`build-backend.log`、`hashes.txt`、`summary.json`。

## 未实现边界 / 风险

- 未实现 M12 的 actor key→workspace Agent UUID、作者/评审分离派发；未实现 M14/M15 完整 claim carrier/handler 校验；未实现 M20 canonical walker/结果消费。`PipelineReviewMaxAttempts` 仍只为 requirement/architecture 提供既有 bound，code/writeback 的运行时分派未接通。
- 共享 parser 只服务内部受控 compiled pair，不开放任意 request/DB body 认证；未新增运行时 SHA 复算。既有 attempt-bound 测试继续以可信回调改 body 保 digest，这是内部 fixture seam，不是生产豁免。
- 四份生成物和 producer 未改；M11 不宣称 SC003 整个 walker、CP005/007、四阶段运行时或 Gate3 完成。
- PG 容器/卷、任务勾选、commit/push/deploy、真实 CR/审批与最终清理均归 Main；本执行者未执行。

---

## Review fixes（Spec 3P 复核后追加，保留上文章节）

Main 独立 full 当前真实 354＝196 父＋157 子 PASS／1 既有 LiveGitHub SKIP／0 FAIL／no DB skip；gencheck/vet/build 均 0；Standards 无硬 P。Spec 提 3 个确认候选（P1 req legacy first-select；P2 repairRef 可空；P2 passCondition 仅 JSON.Valid），两路 reviewer 已完成并释放旧 freeze。本轮重新独占原 3 source＋本报告，DB sole owner 恢复；未改四 generated/tools/renderer/状态机。

### P1 — req legacy 语义 ref 选择歧义

真实 counterexample 使用合法 req wire：在原 `push-progress` 之前插入第二个 `push-progress`，unique nodeId `00000000-0000-0000-0011-000000000099`，匹配 permission，schema/inputs/loops 全合法，digest 保持编译 pair（内部受控 fixture，不是外部请求/DB 入口）。

- RED 实际命中：`nodeByRef` 返回 first match `...0099`；`parseRequirementRegistryFrom` 仍接受歧义声明。同类的 `ownerOf` first-scan 也在本轮改为歧义返回空，并由 GREEN 负例覆盖。
- 第二 counterexample：插入第二个 `human_approval`（unique nodeId `...0098`，合法 approvalPrompt/timeout），`approvalNodeOf` 返回 first match `...0098`，parser 仍接受。
- 修复：requirement mandatory ref validation 要求实际状态机消费的 ref 恰好一个；human approval 恰好一个。`nodeByRef`/`ownerOf`/`approvalNodeOf` 不再返回 first，歧义时分别返回 nil/空。
- 边界：shared generic parser 仍允许 duplicate refs（真实 code registry 继续通过），未加回 generic ref 唯一限制或固定 4/6。此 P1 是受控 fixture/未来合法重复声明的 legacy consumer 缺口，不宣称远程攻击入口；req legacy 语义 ambiguous fail closed 不是新增 gate。

### P2 — repairRef 完整性

- RED：code `write-test-report` loop 删除 `repairRef`、保留合法 `repairNodeId`，当前 parser 接受（`invalid registry accepted`）。
- 修复：loop 必须声明非空 `repairRef`；显式 `repairNodeId` 仍优先用于 disambiguate duplicate ref，但 ID/ref 必须相符。原有显式 ID 消歧正例继续 PASS。

### P2 — passCondition 非空 object

- RED：`{}`、`[]`、scalar `"pass"` 均被当前 parser 接受；`null` 原 case 已被拒。
- 修复：只要求 `passCondition` 能解码为非空 JSON object；不造条件 DSL/eval、不标准化 body、不重算 SHA。`json.RawMessage` 保留完整 unknown keys，正例注入 `vendorCheck` 后仍保留。
- 四个 compiled body 的正常 `passCondition` 全部继续 PASS。

### 本轮 RED / GREEN

- RED：`TestMDispatch003` native exit 1，58 cases＝50 PASS＋8 FAIL；实际失败为 4 个 passCondition/repairRef fail-closed 子例、`nodeByRef` first-match、`approvalNodeOf` first-match、两个父级 fail 汇总。证据：`review-fixes/red-review-fixes.json`。
- GREEN：同测试 native exit 0，58/58 PASS，no skip。
- 原合同/req/attempt/source 邻接定向：native exit 0，118 cases＝16 顶层＋102 子，全部 PASS，no skip；含 `TestMDispatch003`、`TestMDispatch005Generator`、`TestMDispatch005`、原 contract/attempt-bound/requirement registry、renderer 与 source guard 原测试。
- 本轮未重复跑完整 governance；上轮作者 full 354/353/1 仍保留为旧证据，最终整包与两路 delta 归 Main。
- `go vet ./internal/governance` 0、`go build ./...` 0、native `--check` 0、`git diff --check` 0。

### 最新冻结哈希

| 文件 | final raw SHA-256 | final LF SHA-256 | lines | CRLF/BOM |
|---|---|---|---|---|
| `runner.go` | `e0d53e5669718fc93ae03dc55d4d2af8c5c9ecaf0217ca1231e28191267cf719` | `4abdefff807f4b92d4157cc0746885160ab13b385ba7d6e020ec335088a25c1e` | 1315 | 全 CRLF / 无 BOM |
| `runner_requirement_registry.go` | `407434bfa678d33505d7494fce512c37891952868bb3776e516293388bc14ec2` | `27fa7d145e0d8241b2902910ca7ec28788fbdcefd658858d832362594aa5e112` | 335 | 全 CRLF / 无 BOM |
| `runner_contract_test.go` | `a88cff33a7bd771ef224bf897a32b172225d7f5be08ae859764e3f47a4966185` | `9916eb5ec3f022f30c002653abc5873b95722164bd1ad5e9c57f5482055c0f14` | 1068 | 全 CRLF / 无 BOM |

原 contract 前 427 行 SHA-256 仍为 `5430fb7c86944221eed8a31d8291edf84842cd802236b5548eeafba9e0202b73`；上一版 M11 的 50 个 case 全部保留、无 missing，仅追加 8 个 case。四 generated body digest 仍为 `f839…`、`1197…`、`ee64…`、`6a63…`，未重写。

### 证据与最终身份

- 新证据固定 `C:\Users\GOBAO\AppData\Local\Temp\aifi45-m11-evidence\review-fixes\`：`red-review-fixes.json`、`green-review-fixes.json`、`green-targeted-review-fixes.json`、`final-lfsha.txt`、`original-cases-preserved.txt`、`summary.json`、gen/vet/build/diffcheck 日志。旧 RED/full、`hashes.txt`、根 `summary.json` 保留未覆盖。
- 本轮仍用 PG33551 private config、白名单 env、`GOENV=off/GOTOOLCHAIN=local/GOPROXY=off/-mod=readonly`，无外 DB/env/KB/.env/真实 CR；未清理 PG。
- **三 source 再次冻结，DB test owner 释放交 Main；M11 仍未勾选，等 Main 整包与两路 delta 闭合。** 未 commit/push/deploy、未修改工具权限、未提前做 M12 actor/UUID、M14/M15 carrier、M20 walker。架构 Runner 仍按 `Nodes[0..3]` 的既有边界属后续 walker 切片，本轮不扩状态机。

---

## Review fixes round 2（M11-REV-004 追加，保留前两版章节）

Main 当前完整 native 0／37.726270800s，196 父＋165 子 PASS／1 既有 LiveGH SKIP／no DB skip；gen/vet/build 0；Standards delta 无 P。上一轮 3P 已由原 Spec 复核关闭，新缺口为同一 `validateCoreReviewLoop` 的 presence/声明完整性，不是旧 3P 反复失败。本轮继续单 writer/sole DB，未改 Root 4 generated/tools/renderer/RuntimeWalker/ActorBinding/handler/API。

### 实际 emitter 规则（先读后改）

`tools/pipeline-templates/emit-registry.mjs` 当前段实际 predicate：独立评审是 `typeof node.ref === 'string' && node.ref.startsWith('review-')`，不是所有含 loop 节点。若该 predicate 命中且缺少 `reviewLoop` 属性则失败。loop 存在时要求：

- `reviewLoop` 为非 null、非数组 object；
- `maxAttempts` 为整数且 ≥1；`passCondition` 为非空 object；
- `repairNodeId` 属性若出现必须为非空 string；`repairRef`/`feedbackInput`/`attemptInput`/`onBlock` 必须非空 string；
- repair 绑定按显式 ID 优先，否则按 ref 唯一匹配；目标必须存在、非 human、ref 相符；
- `replayPolicy` 属性若出现必须为非空 string；
- `replayNodes` 属性若出现必须为非空 array 且同时有非空 policy；每个目标必须存在、非 human、ref 相符；
- emitter 不枚举 policy 值，也允许非空 `replayPolicy` 在没有 `replayNodes` 时出现；未新增 enum/DSL。
- 非 `review-` 节点可以没有 loop；实际 `write-test-report` 仍是 Dev 自测 loop，不按 `review-*` 加独立 UUID 限制。

### 真实 RED（先于修复）

新 fixture 均保持合法 schema/inputs/permissions/loops 与内部编译 digest pair：

- A：删除 code `review-dev-plan` 的 `reviewLoop`，旧 Go 因 `if loop != nil` 直接接受；RED 实际 `invalid registry accepted`。
- A 变体：`reviewLoop:null` 在独立评审节点和 `write-test-report` 上均被旧 Go 接受，说明 presence 与 null 未区分。
- B：loop 的 `replayNodes` 设为 `[]`/`null` 并删除 policy，旧 Go 以 `len==0` 当 absence 接受；显式空 `replayPolicy` 也接受。
- 同类：显式 `repairNodeId:""` 被旧 Go 当作 absence 后按 ref 接受。
- 反向过度收紧：旧 Go 拒绝“非空 `replayPolicy` 无 `replayNodes`”，但 emitter 明确允许；该 positive 在 RED 中暴露，修复后接受。
- RED：`TestMDispatch003` native exit 1，68 cases＝58 PASS＋10 FAIL（7 fail-closed 变体＋fail_closed 父＋policy-without-nodes positive＋总父）。之后又补两个同 presence 分支的 null 变体，最终用例数 70。

### 最小修复

- 在现有 `coreNode`/`coreReviewLoop` decoder 上增加由同一 raw envelope 派生的 presence flags：`reviewLoop`、`replayNodes`、`replayPolicy`、`repairNodeId`。不新增 runtime ledger、不保存第二 SSOT。
- `review-*` 节点必须有 `reviewLoop`；任何显式 present 的 `reviewLoop:null` 都失败；absence 在非 `review-*` 节点仍合法。
- `replayNodes` present 时要求非空 array 与配套非空 policy；`[]`/`null` 失败，absence 与显式 `[]` 明确区分。
- `replayPolicy` present 必须非空；present 空/null 失败；非空 policy 无 nodes 按 emitter 接受。
- `repairNodeId` present 必须非空；repairRef/feedbackInput/attemptInput/onBlock/replayPolicy 使用与 emitter 一致的 trim-nonempty 判定。
- 移除此前自加的 replay target 唯一限制（emitter 不要求）；不新增 policy enum、不做条件 DSL/eval、不重算 Go SHA。完整 Raw/unknown execution fields 仍只保留在 `coreRegistry.Raw`。

### 本轮 GREEN

- 最终 `TestMDispatch003`：native exit 0，70/70 PASS，no skip；旧 58 个 case 全部保留、无 missing。
- 原合同/req/attempt/source 邻接定向：native exit 0，130 cases＝16 顶层＋114 子，全部 PASS，no skip；含 `TestMDispatch005Generator`、`TestMDispatch005`、原 contract/attempt-bound/requirement registry、renderer 与 source guard。
- 未重复跑完整 governance；最终整包与两路 reviewer delta 归 Main。
- `go vet ./internal/governance` 0、`go build ./...` 0、native `--check` 0、`git diff --check` 0。
- Code 3 loops、duplicate refs、writeback no-loop 与实际 `write-test-report` loop 均继续通过。

### 最新冻结哈希

| 文件 | final raw SHA-256 | final LF SHA-256 | lines | CRLF/BOM |
|---|---|---|---|---|
| `runner.go` | `31379c63078689a7e86c50296afc604ab39a11baa2dab8f44a2739ed4a6c3b49` | `3c7e58d12a6e956bab41bc4c1f16be5a9d0c9533a96b71f2d9e242a8c117ac8f` | 1364 | 全 CRLF / 无 BOM |
| `runner_requirement_registry.go` | `407434bfa678d33505d7494fce512c37891952868bb3776e516293388bc14ec2` | `27fa7d145e0d8241b2902910ca7ec28788fbdcefd658858d832362594aa5e112` | 335 | 全 CRLF / 无 BOM |
| `runner_contract_test.go` | `b92225ce537f3c2d50504da2ec8e6ffe39072f2e95a39ef54506952055574b0d` | `5817850ffbcd54961874621d37e74c88f931f679109b4bd262d6d23e192df7a9` | 1212 | 全 CRLF / 无 BOM |

原 contract 前 427 行 SHA-256 仍为 `5430fb7c86944221eed8a31d8291edf84842cd802236b5548eeafba9e0202b73`。四 generated body digest 仍为 `f839…`、`1197…`、`ee64…`、`6a63…`，未重写。

### 证据与最终身份

- 新证据独立 `C:\Users\GOBAO\AppData\Local\Temp\aifi45-m11-evidence\review-fixes-round2\`：`red-round2.json`、`green-round2.json`、`green-targeted-round2.json`、`final-lfsha.txt`、`original-cases-preserved.txt`、`summary.json`、gen/vet/build/diffcheck 日志。旧 `review-fixes/`、根 RED/full、旧 hashes/summary 均未覆盖。
- 仍用 PG33551 private config、白名单 env、`GOENV=off/GOTOOLCHAIN=local/GOPROXY=off/-mod=readonly`，无外 DB/env/KB/.env/真实 CR；未清理 PG。
- **三 source 再次冻结，DB test owner 释放交 Main；M11 仍未勾选，等 Main 整包与两路最终 delta 闭合。** 未 commit/push/deploy、未修改工具权限、未提前做 M12 actor/UUID、M14/M15 carrier、M20 walker；架构 Runner `Nodes[0..3]` 仍是已明示的后续 walker 边界，本轮未扩状态机。

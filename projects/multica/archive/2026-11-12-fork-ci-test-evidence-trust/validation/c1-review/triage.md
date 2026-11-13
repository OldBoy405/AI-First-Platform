# Part C / C1 三路并行技术评审 — 派发证据与逐条处置

> change：`2026-11-12-fork-ci-test-evidence-trust`｜执行：2026-11-13 本地（UTC+8）｜Windows｜Node v24.22.1
> 本文件是 C1 的落账记录。**评审返回不等于修复完成**；每条发现的处置都附核实证据或明确的不修理由。
> 未执行、跳过或外部依赖未满足的检查一律不报通过。

## 1. 选模派发证据（configured / requested / actual 分记）

按 `_shared/model-dispatch.md` 执行。在业务项目根 `C:/Users/GOBAO/Downloads/AI/multica` 运行
`stdd config models --format json`：**exit 0、`schema_version=1`、`kind=configured`**，随后读取
`values.review` 与 `values.model_tiers.models.<tier>`。派发前重新读取一次，取值如下。

| 代理 | scope（配置原文） | configured tier | configured model | configured effort |
|---|---|---|---|---|
| code | 代码质量：Bug风险、死代码、一致性、错误处理、安全 | `strong` | `GB-JP/kimi-k3.1-pro` | `max` |
| test_config | 测试/配置：测试覆盖、Fixture质量、配置完整性、测试隔离 | `balanced` | `GB-JP/deepseek-flash` | `max` |
| docs_skills | 文档/Skills：版本一致性、引用正确性、模板完整性、Skill正确性 | `economy` | `Gobao/deepseek-flash` | `high` |

`values.review.enabled = true`；`values.model_tiers` 另含 `design=strong`、`retry=strong`、`assist=balanced`（本轮未消费）。

**requested = 无（三项均未指定）**。核实过程：`mcp_get` 读取 `mcp__builtin__create_chat_session`、
`mcp__builtin__create_team_task` 的 inputSchema，以及 `Agent` 工具自身的参数声明，**三者都不暴露原生
`model` 或 `effort` 参数**。按共同规则 §2 第四档「两项都不支持 → 不指定 model/effort，沿用平台默认行为并说明」，
本轮**未传任何选模参数**，`subagent_type` 仅按能力选择（`general-purpose`），不按档位选择。
按 §3，profile/agentId 的默认模型**不计为显式 requested**。

**actual = unknown（三项均未知）**。宿主未返回运行元数据，无法核实后端实际型号与思考强度。
按 §4「参数已配置或已请求不等于已生效」，**不声称已按 strong/balanced/economy 档位执行**，
不以思考多少作证据，不因型号不可用而默换供应商、档位或主会话模型。

**三路独立派发保留**：按 C1「评审始终保留三路独立派发；主会话已是 strong、映射相同、映射全空均不合并或跳过评审」，
本轮派发 3 个并行只读代理，未合并、未跳过、未补造第四个代理、未开启专项 reviewer。
缺少可用原生选模能力**不降低评审标准**：三份 brief 均携带各自配置 scope 原文与硬边界。

**与用户既有选模指令的关系**：核对 `feedback-subagent-model-routing.md`，2026-11-08「当前 change 子代理都和主会话使用一样的模型」
是**针对当时那个 change** 的指定，不自动成为本 change 的默认；本 change 用户未作同款指定，故按项目配置消费。
主会话档位亦未可靠核实，不据此声称任何档位匹配。

### 派发边界（三份 brief 共同）

只读：不得编辑任何文件、不得 git 写操作、不得连接数据库 / podman / psql、不得 `go test` / `make test`、
不得 WSL / npm / pnpm、不得读取或打印任何凭据。test_config 额外**仅**允许
`node --test scripts/aifi45-disposable/*.test.mjs`、`node --test --test-reporter=tap scripts/ci-scope.test.mjs`、`node --check`。

## 2. 返回概览

| 代理 | blocker | major | minor | nit | 实际执行 |
|---|---|---|---|---|---|
| code | 0 | 1 | 2 | 2 | 只读核码（未跑测试，CI 行为属读码推断） |
| test_config | 0 | 1 | 1 | 3 | harness **171/171/0/0**、ci-scope **49/49/0/0**（派发时点），前后 `git status` 一致 |
| docs_skills | 0 | 0 | 4 | 2 | 只读核对；重算 Gate 2 全部 20 个 manifest 哈希 + fingerprint，18 处 raw 逐字节匹配 |

docs_skills 另**强核实 Gate 2 未被 BUILD 产物编辑弄脏**：20 个 `input_manifest` 哈希与 fingerprint 全部重算匹配，
`proposal.yaml` 投影 `ec254f00…`、`proposal.md` 正文投影 `dfe10653…` 按 `gate.py` 复现，3 张旧回执 superseded，
当前批准在 `phases.spec`（2026-11-12T23:54:09）。`tasks.md` / `slices.md` / `phase-context.md` / `pending-adjustments.yaml`
**不在** gate 输入内，故本轮对它们的编辑不使 Gate 2 失效。

## 3. 逐条处置

处置代号：**FIXED** = 本轮已修并附验证；**RECORDED** = 登记为已知问题不修（附理由）；**ALREADY-COVERED** = 评审所指缺口在既有记录中已如实写明。

### 3.1 code MAJOR-1 — `CRCTL_PATH` 三处未申报 CI skip → **FIXED**（详见 §4.1）

核实（全部读码 + 真库实测，非推断）：

- `server/internal/governance/approval_crosscheck_test.go:196-220` `resolveCrosscheckCrctl` 读 **`CRCTL_PATH`**（不是 `CRCTL_MJS`），
  空值时回落两条**相对**开发机 sibling 路径 `../../../../tools/…` 与 `../../../../../../tools/…`，再 `exec.LookPath("node")`，
  `if crctl == "" || err != nil { t.Skip(…) }`。
- 三个调用方：`approval_crosscheck_test.go:223`（`TestGrantCrossVerifiesWithCrctl`，现 :212）、
  `:394`（`TestGrantCrossVerifiesWithCrctlCodeStage`，现 :383）、`dev_phase_cp_test.go:176`（`TestMDev003`，:172 起，
  DB 在 CI 可用故会走到 :176）。**两文件均无 `//go:build` 标签**（实测 grep 无输出）→ CI-linux 会编译。
- `ci.yml:407-408` 只设 `AIFI45_TOOLS_ROOT` 与 `CRCTL_MJS`；tools 检出在 `path: .aifirst-tools`（**仓内**），
  两条相对候选指向仓外（runner 上为 `/home/runner/work/<repo>/tools` 与 `/home/runner/tools`）→ 不存在 → `crctl == ""` → skip。
- `test-ownership.json` 的 `allowed-skips` 只有 4 条，**不含这三个**；`entries` 排除名单也不含 →
  `ci-evidence.mjs` rule 2 会命中 3 次 → `backend-tests` 判红。
- 本机基线为何看不见：repo 父目录即 `C:/Users/GOBAO/Downloads/AI`，候选 1 恰好命中真实 sibling `tools/` → 本机不 skip。
  **S4 基线实测这三个测试共 13 个叶子 PASS**（7+3+3，`baseline-governance.ndjson` 逐名统计），证明本机确实跑到了。
- 契约检查为何漏：`go-test-env-contract.mjs:19` `ENV_BIND` 只覆盖 `CRCTL_MJS|AIFI45_TOOLS_ROOT`；
  `go-test-env-contract.test.mjs:75` 还**显式断言 `CRCTL_PATH` 不被标记**；`DEV_PATH` 只匹配绝对盘符路径，不匹配相对路径。

**这不是新发现，而是 S3 已上报但未落账的遗留**：`validation/s3-env-contract/README.md:118` 已列该处并写
「变量名是 `CRCTL_PATH`，非受管的 `CRCTL_MJS`；是否应统一口径待裁定」，:124-125 写「扩大受管变量集属规格变更，按流程留待用户裁定」。
但 `pending-adjustments.yaml` **当时没有对应 ADJ 条目**（实测 grep `CRCTL_PATH|crosscheck` 无命中）——这是记录缺口，本轮补登 ADJ-027。

**为什么本轮修而不继续等裁定（关键区分）**：S3 拒绝的是**扩大扫描器的受管变量集**（那会超出 SC-CBE-004 `when` 的字面两类）。
本轮做的是**把代码迁到已被受管的名字上**：`resolveCrosscheckCrctl` 改读 `CRCTL_MJS`，于是它自动落入 SC-CBE-004 既有覆盖，
**受管变量集仍是 {CRCTL_MJS, AIFI45_TOOLS_ROOT}，扫描器一行未扩**。这既不改规格，也兑现
REQ-CBE-002 描述「CI 与本地不依赖开发机路径；缺依赖是失败而不是 skip」与 SC-CBE-005「无名单外 skip」。
`go-test-env-contract.test.mjs:71-80`「skips guarded by other conditions are not flagged」**原样保留**，
其中 `CRCTL_PATH` 样例仍断言不被标记——扫描器声明范围未被偷偷扩大。
另加一条**别名回流守卫**（新测试函数）钉住「治理范围内不得再出现 `os.Getenv("CRCTL_PATH")`」，
这是防回归，不是扩扫描器。长程 `full_auto` 下按 B4 记录后继续，不暂停。

### 3.2 code MINOR-1 — reservation 存在性检查非锁读（TOCTOU）→ **部分 FIXED + RECORDED**

核实：`execution_control_reservation.go:90-96` 用 `SELECT EXISTS (SELECT 1 FROM workspace WHERE id = $1::uuid)`，
不加锁；迁移 648:54-66 给 reservation **无 workspace_id、无 FK**；`workspace.go:1141` 的 `DeleteWorkspace` 持 `FOR UPDATE`。
READ COMMITTED 下并发未提交删除存在窗口，可产生孤儿 reservation。

处置：**加两行英文注释**说明「非锁读，只闭合顺序 teardown 场景；并发未提交删除仍可穿过，SC-WSD-005 不要求该场景」。
**不改 SQL、不加 `FOR SHARE`、不加 FK**：648 明文不新增 FK，改锁语义属行为变更且超出 SC-WSD-005 锁定范围，须用户裁定。
reservation 目前**无生产调用方**（#327 已记），且 648:51-52 声明其惰性，实际风险低。登记 ADJ-028（minor，unresolved）供 Gate 3 裁定。

### 3.3 code MINOR-2 / test NIT-3 — `summarizeEvents` 静默丢弃坏行 → **RECORDED（规格锁定，不修）**

核实：`run-selection.mjs:79-82` `try { event = JSON.parse(line); } catch { continue; }`。
与 `ci-evidence.mjs` 的「流不可解析即硬失败」不一致。

**不修的理由有规格依据**：canonical `selection-reconciliation.yaml` SC-SEL-002 `then` 明文
「SHALL **沿用旧判定**：test.code 为 0 且 fail 为 0 且 skip 为 0 且 pass 大于 0；PASS 与 FAIL 输出行 SHALL **逐字不变**」，
`and` 明文「`run-selection.test.mjs` 既有断言 SHALL 全部保持通过且**不被改弱**」。
把解析失败改成硬失败是**行为变更**，超出该锁定场景，须走 revision。
两处不对称是**规格各自要求的**：`ci-evidence.mjs` 是本 change 新建、其流完整性由 SC-TOR-002 要求硬失败；
`run-selection.mjs` 是既有文件、SC-SEL-002 要求保留旧语义。登记 ADJ-029（minor，unresolved）。

### 3.4 code NIT-1 — `selection-decision.mjs` 无守卫解引用 → **RECORDED（不修）**

核实：`selection-decision.mjs:18-25` 在 `declared(selection)` 为真时直接读 `reconciliation.status`；
`run-selection.mjs:141-150` 总会传入 reconciliation 对象，故该路径当前不可达。
为不可达状态加防御守卫属「为不可能发生的场景加错误处理」，不做。登记 ADJ-030（nit，unresolved）。

### 3.5 code NIT-2 / test MINOR-1 — 契约扫描器模式盲区 → **RECORDED（不扩围）**

核实：`go-test-env-contract.mjs:19-21`
`ENV_BIND` 不认 `os.LookupEnv`；`EMPTY_GUARD` `/if\s+(\w+)\s*==\s*""/` 不认内联
`if cli := os.Getenv("CRCTL_MJS"); cli == "" { t.Skip(…) }`、switch/case、`if len(x)==0`；`SKIP` 不认 `t.SkipNow()`。
**当前仓库干净**：CLI 实测 `go test env contract OK: 119 file(s), 0 violations`，exit 0。

不修理由：SC-CBE-004 只要求「对**注入了旧默认路径或 `t.Skip`** 的样例变红」，上述写法都不是旧写法；
扩模式集属超出锁定要求的加固。本轮实际发生的逃逸（别名）已由 §3.1 的新守卫钉住。
登记 ADJ-031（minor，unresolved），Gate 3 呈报请用户决定是否另开变更加固。

### 3.6 test MAJOR-1 — 单一 pin 的 `ref` 接线无断言 → **FIXED**（详见 §4.2）

核实：`tools-pin.test.mjs:166-172` 原断言只检查「**某一行**含 `aifirst-tools-pin`」与「**某一行**含
`repository: OldBoy405/AI-First-tools`」，从不检查 checkout 自己的 `ref:` 来自 pin 步骤输出；
`tools-pin.mjs:57-66` 的 `check` 只验 3 个必需文件存在，不验 HEAD==pin；ci-scope 的新断言钉的是**步骤顺序**不是 ref 行。
生产当前正确（`ci.yml:137` 与 `:494` 均为 `ref: ${{ steps.tools-pin.outputs.ref }}`），
但把 ref 改成 `main` 可让全部测试与完整性检查保持绿。**已用变异实测证明该缺口**（§4.2）。

### 3.7 test NIT-1 — s13 README 称 Drop 为「最后一步」→ **FIXED（措辞）**

核实：`ci.yml` 中 Drop 之后仍有上游 `Prune Go build cache to this run's entries`（:547）与 `Save Go build cache`（:559）。
已把 `validation/s13-ci-wiring/README.md:42` 与 `:175` 改为「**最后一个数据库步骤**」并点名其后两步。

### 3.8 test NIT-2 — `ci-provision.test.mjs:369` 真实 TCP 尝试 → **ALREADY-COVERED（无需改）**

核实：该用例确实向 `postgres://admin:pw@127.0.0.1:1/postgres`（端口 1，立即 ECONNREFUSED）发起一次真实连接，
用于证明 `--env-file` 被接受后走的是连接失败而非 usage 失败。
评审所指「不发网络请求」的表述**在 s6 记录中已带例外**：`validation/s6-ci-provision/README.md:4-6` 原文
「**本切片未运行任何数据库**：全部用例用注入的假连接…唯一一次真实网络尝试是 CLI 用例连 `127.0.0.1:1`（连接被拒，用于证明…）」。
s13 README 全文 grep `网络请求|不发网络请求|未发出任何真实网络` **无命中**，不存在需要更正的绝对化表述。故不改。

### 3.9 docs minor 1 — `.canon-index.yaml` 指向不存在的聚合文件 → **RECORDED（Gate 2 锁定输入，不擅改）**

核实：`canonical/.canon-index.yaml:6` 与 `:8` 指向 `specs/{agent,code}/2026-11-12-fork-ci-test-evidence-trust.yaml`，
实际布局是 5 个 per-capability 文件。功能上惰性（generate 走 glob、verify 只校 proposal、Gate 2 哈希原始字节）。
与 ADJ-015 同源（CLI `--type spec` 被忽略）。

**不修的理由是硬边界**：`canonical/.canon-index.yaml` **在 Gate 2 的 `input_manifest` 内**，
编辑它会使 Gate 2 失效并须 `--reapprove` 重签。本轮无用户重签授权，**不静默修改锁定输入**。
登记 ADJ-032（minor，unresolved），Gate 3 呈报，与 ADJ-015 一并作为 CLI 缺陷上报。

### 3.10 docs minor 2 — 14/18 agent CP `description` 被截断在 61 字符 → **RECORDED（同上，锁定输入）**

核实：CP-SEL-001 结尾「…含该 re」、CP-SEL-003「…；SHAL」、CP-WSD-002「…cr_execution_dispa」等，
均在**第 61 字符处词中截断**；边界反证：CP-WSD-004 恰好 61 字符且自然收在「。」，
CP-WSD-005（132 字符，R5 手工同步）完整。`action` 与 `assertions` **均 intact**，CP 语义未损。
属工具渲染缺陷（`stdd canon generate`）。这些是 canonical agent spec = **Gate 2 输入**，同上不擅改。
登记 ADJ-033（minor，unresolved）。

### 3.11 docs minor 3 — 「6 个新增 .go/.mjs 未计入」枚举不准 → **FIXED（三处更正，原文保留）**

实测 `git status --porcelain`：**27 个 untracked**。按《核对命令》glob 分类：

- **口径内 8 个** = 6 个 `.go`（`server/cmd/server/disposable_identity_conditions_test.go`、
  `server/internal/governance/disposable_identity_conditions_test.go`、`server/internal/governance/workspace_delete_execution.go`、
  `server/internal/handler/workspace_delete_{execution,no_recreate,retention}_test.go`）
  + **2 个 `.sql`**（`server/migrations/649_cr_execution_truncate_guard.{up,down}.sql`）。
- **口径外 19 个** = `.github/aifirst-tools-pin` + `scripts/aifi45-disposable/` 下 18 个。
- 新增 `.mjs` **全部**在 `scripts/`，故口径内新增 `.mjs` 为 **0**；原表述漏计 2 个 `.sql` 且误列 `.mjs`。

已在三处追加**显式 C1 更正并保留原文**：`pending-adjustments.yaml:175`（ADJ-018 reason ②）、
`CUSTOM.md` #327 合并注意、`phase-context.md:245`。**ADJ-018 的结论本身不受影响**（仍不补基线行，三点理由成立）。

### 3.12 docs minor 4 — CUSTOM.md CR 索引缺本 change 行 → **FIXED**

核实：索引（:115–193）无本 change 行，而先例存在（:185 `STDD 2026-11-11-aifi-45-admission-task-binding | ✅ Gate 3 已确认 | #315–#316 | M27+M30`；
:193 `2026-10-27-trusted-verdict-channel | —（原生 STDD，非 CR）| 🚧 BUILD 在途（Gate 3 未过）| #220 | M14`）。
`CONTRIBUTING.AIFIRST.md`（50 行）无强制条款，依据是 CUSTOM.md 自身先例。
已按 :193 同形状追加一行，状态如实写 **🚧 BUILD 在途（Gate 3 未过）**，明细行号 #317–#332，模块 M31，
备注列出四项延后与 ADJ-017/025/018。

### 3.13 docs nit a — `slices.md:57` 规划期断言被证伪 → **FIXED（更正块，原文保留）**

原文「这样每个切片都有 >0 新增自动化测试（长程强制约束 #3）」被 **S12 实测 `new_tests: 0`** 证伪。
已在其后追加引用块写明：S12 为 command 型 TC、ADJ-019 已登记、`.stdd.yaml` 如实记 0、未报「B3.4 三项全过」，
且约束 #5 的降级条件是**连续 3 切片**（S11=15、S12=0、S13=4）故**不触发降级**。

### 3.14 docs nit b — TAP 文件不记退出码 → **FIXED（本轮证据带退出码）**

既有 TAP 证据确实不含退出码、由 README 推断。本轮 C1 的每份证据都在 §5 索引中**显式记录实测退出码**，
不改写既有历史证据文件。

## 4. 两处 MAJOR 的修复与验证

### 4.1 code MAJOR-1：`CRCTL_PATH` → 受管 `CRCTL_MJS`

**改动文件（3 个）**

| 文件 | 改动 | 性质 |
|---|---|---|
| `server/internal/governance/approval_crosscheck_test.go` | `resolveCrosscheckCrctl` 改读 `CRCTL_MJS`；删除两条相对 sibling 回落与 `os.Stat` 探测循环；`t.Skip` 拆成两条 `t.Fatal`/`t.Fatalf`（crctl 缺失、node 缺失）；加 3 行 `// AIFIRST:` 英文注释说明为什么；文件头注释「Skips when node or crctl is unavailable; … TestMain additionally skips」更正为「Fails when CRCTL_MJS or node is unavailable; … TestMain exits non-zero unless DATABASE_URL is a disposable database」（读 `crsync_test.go:34-61` 核实 TestMain 全部 `os.Exit(1)`，从不 skip） | **上游文件**，最小钩子 |
| `scripts/aifi45-disposable/go-test-env-contract.mjs` | `function goTestFiles` → `export function goTestFiles`（1 词），供守卫测试复用既有遍历，不另写一份 | fork 独有 |
| `scripts/aifi45-disposable/go-test-env-contract.test.mjs` | 导入 `readFileSync`/`relative`/`goTestFiles`；**新增 1 个测试函数**「TC-CBE-004 no governance test binds the unmanaged CRCTL_PATH alias」，遍历 `SCOPE_DIRS` 全部 `*_test.go`，断言无 `os.Getenv("CRCTL_PATH")` | fork 独有 |

`filepath` 导入保留（该文件另有 20+ 处使用，实测 grep 核实）。`ENV_BIND`/`EMPTY_GUARD`/`SKIP`/`DEV_PATH`
**四个正则一字未改**，`go-test-env-contract.test.mjs:71-80` 的「其他条件守卫不标记」用例（含 `CRCTL_PATH` 样例）**原样保留**。

**RED → GREEN**

- RED：`node --test --test-reporter=tap scripts/aifi45-disposable/go-test-env-contract.test.mjs`
  → **exit 1，`# tests 12 / # pass 11 / # fail 1`**，唯一红的是新测试 #12，报文点名
  `server\internal\governance\approval_crosscheck_test.go:198`（即旧 `CRCTL_PATH` 绑定行）。
- GREEN：同命令 → **exit 0，12/12/0**。
- 契约 CLI 对真实仓库：`node scripts/aifi45-disposable/go-test-env-contract.mjs`
  → **exit 0，`go test env contract OK: 119 file(s), 0 violations`**（修复后该 helper 已落入受管覆盖）。
- 编译：`cd server && go vet ./internal/governance/` → **exit 0，无输出**。

**真库行为验证（runner 自建一次性 podman 实例，两个条件各一次）**

selection 文件 `selections-crosscheck.json`（放在本证据目录，**不改仓内 `selections.json`**）：
`{"name":"crosscheck-crctl","package":"./internal/governance","run":"^(TestGrantCrossVerifiesWithCrctl|TestGrantCrossVerifiesWithCrctlCodeStage|TestMDev003)$"}`。
`run-selection.mjs:120` 的 `env = { ...process.env, … }` 会透传环境，故用 shell 注入/剔除变量。

| 条件 | 注入 | 实测 | runner exit | 实例 |
|---|---|---|---|---|
| 变量齐备 | `AIFI45_TOOLS_ROOT=C:/Users/GOBAO/Downloads/AI/tools`、`CRCTL_MJS=…/skills/shared/crctl/scripts/crctl.mjs` | **`PASS crosscheck-crctl pass=13 fail=0 skip=0`** | **0** | `e570c9af78b1` released remaining=0 |
| `CRCTL_MJS` 缺失 | `env -u CRCTL_MJS`，`AIFI45_TOOLS_ROOT` 保留（隔离单变量） | **`FAIL crosscheck-crctl pass=0 fail=3 skip=0`** | **1** | `87bc3662fd25` released remaining=0 |

- **无回归**：13 个叶子 PASS 与 S4 基线逐名统计的 7+3+3=13 **完全一致**，且 **skip=0**。
- **skip→Fatal 已证**：缺失条件下三个测试各自 FAIL 并打印
  `CRCTL_MJS is required: the cross-tool approve seam needs the real crctl verifier, so a dev-machine default is not evidence`，
  位置分别为 `approval_crosscheck_test.go:213`、`approval_crosscheck_test.go:384`、`dev_phase_cp_test.go:176`
  ——**三个调用方逐个归因，不是笼统一条**。`skip=0` 证明不再走 skip 路径。

**变异验证（1 条，DETECTED）**

把 helper 内 `crctl := os.Getenv("CRCTL_MJS")` 改回 `os.Getenv("CRCTL_PATH")`（byte 8489，锚点唯一性已校验）
→ 守卫测试 **exit 1，12 tests / 11 pass / 1 fail，只有 #12 红**，其余 11 条不受影响。
按原字节还原后 `sha256sum` = `043054f75b5f1e659266c315952eeb7c11c51182fd1a90bf0dd93e5d038a399a`，**与变异前逐字节一致（match true）**。

**回归**：`node --test scripts/aifi45-disposable/*.test.mjs` → **exit 0，172 pass / 0 fail / 0 skipped**（派发时点 171 → +1 即新守卫）。

### 4.2 test MAJOR-1：pin `ref` 逐 checkout 块断言

**改动文件（1 个）**：`scripts/aifi45-disposable/tools-pin.test.mjs:166-172` 的
「TC-CBE-003 ci.yml takes the tools ref from the pin file」**就地强化**（不新增测试函数）：
保留原有两条存在性断言，再对**每一个** `repository: OldBoy405/AI-First-tools` 行，
按 `/^ {10,}\S/` 收集其所属 `with:` 块（遇 6 缩进的下一步或空行即止），
断言块内 `ref:` 行**恰好一条**且 trim 后等于 `ref: ${{ steps.tools-pin.outputs.ref }}`，
失败报文点名 `ci.yml:<行号>`。加 2 行 `// AIFIRST:` 英文注释说明「两个字符串各自存在不等于单一来源」。

**缺口证明 → RED → 还原 → GREEN（四步，全部实测）**

1. **缺口证明**：先把 `ci.yml` 两处 `ref: ${{ steps.tools-pin.outputs.ref }}` 变异为 `ref: main`（实测命中 **2** 处，非 1 处），
   跑**旧**测试 → **exit 0，`# tests 15 / # pass 15 / # fail 0`**，其中 **#15「ci.yml takes the tools ref from the pin file」照样绿**。
   这就是评审所指的缺口：单一 pin 的 ref 接线被改成 `main` 也无人变红。
2. **RED**：保持变异，应用强化后的断言 → **exit 1，15 tests / 14 pass / 1 fail**，唯一红的是 #15，
   报文 `the tools checkout at ci.yml:136 must take its ref from the pin step output`。
3. **还原**：把 2 处 `ref: main` 改回原表达式，`sha256sum .github/workflows/ci.yml`
   = `72c16f6b9302bb976402a57ddbf8c557e2444881aa8b5b390e9ac26725e1c43e`，**与变异前逐字节一致（match true）**。
4. **GREEN**：`node --test --test-reporter=tap scripts/aifi45-disposable/tools-pin.test.mjs` → **exit 0，15/15/0**。

**回归**：harness **exit 0，172/172/0/0**；`node --test --test-reporter=tap scripts/ci-scope.test.mjs` → **exit 0，49/49/0**。

**新增测试数如实区分**：§4.1 新增 **1 个测试函数**；§4.2 是**强化既有函数**，新增函数数 **0**。
本轮 C1 合计新增测试函数 **1**，不把它夸大为 2。Part C 不是切片，长程约束 #3 的「每切片 >0」按切片口径已在
`.stdd.yaml` 逐切片记录，此处不重复计数、也不冒领切片证据。

### 4.3 容器与凭据边界（本轮全部运行）

- 运行前 `podman ps -a`：只有 `multica-postgres`（`docker.io/pgvector/pgvector:pg17`，Exited）与
  `multica-backend`（`localhost/multica-backend:81e5293adc`，Exited）；`podman volume ls`：只有 `multica-pgdata`。
- 两次 selection 运行后**同一清单、同一状态**，无新增容器、无新增卷；两个实例均 `released … remaining=0`。
- **未连接 `localhost:5432`、未操作旧 `multica-postgres` 容器、未放宽 nonce 门禁**（门禁文件一行未改）。
- **未读取或打印任何凭据**；注入的 `CRCTL_MJS`/`AIFI45_TOOLS_ROOT` 是路径不是秘密。
- tools HEAD 实测 `e52b8081f159d581bf62f82447c76f818fc52426`，与 `.github/aifirst-tools-pin` **逐字一致**；
  tools 仓 6 处既有未提交改动**未触碰、未清理、未混入**。记录仓他人未提交改动同样未触碰。
- multica 工作树本轮结束后实测 **22 modified + 27 untracked**（S13 时点为 21+27，新增的 1 处修改是
  `approval_crosscheck_test.go`）；`ci.yml` 与 `approval_crosscheck_test.go` 的变异均已字节级还原。
- **未提交、未推送、未部署**。

## 5. 本轮证据索引（含实测退出码）

全部位于 `validation/c1-review/`。退出码由执行 shell 的 `echo "exit=$?"` 实测记录，不推断。

| 文件 | 内容 | exit | 关键计数 |
|---|---|---|---|
| `red-crctl-alias.tap` | 别名守卫 RED | **1** | tests 12 / pass 11 / fail 1（#12） |
| `green-crctl-alias.tap` | 别名守卫 GREEN | **0** | tests 12 / pass 12 / fail 0 |
| `mutation-crctl-alias.tap` | 别名守卫变异 | **1** | tests 12 / pass 11 / fail 1（只 #12） |
| `selections-crosscheck.json` | 本轮 selection 定义（仓外） | — | 1 条，3 个测试名 |
| `crosscheck-env-present.txt` + `crosscheck-env-present/` | 变量齐备真库运行 | **0** | pass=13 fail=0 skip=0 |
| `crosscheck-env-absent.txt` + `crosscheck-env-absent/` | `CRCTL_MJS` 缺失真库运行 | **1** | pass=0 fail=3 skip=0 |
| `harness-after-crctl-fix.txt` | §4.1 后 harness 全量 | **0** | 172 / 172 / 0 / 0 |
| `mutation-ref-main-old-test.tap` | **缺口证明**：ref→main 下旧测试 | **0** | tests 15 / pass 15 / fail 0 |
| `red-ref-main-new-test.tap` | ref→main 下强化断言 RED | **1** | tests 15 / pass 14 / fail 1（#15） |
| `green-ref-restored.tap` | ci.yml 还原后 GREEN | **0** | tests 15 / pass 15 / fail 0 |
| `harness-after-both-fixes.txt` | 两处修复后 harness 全量 | **0** | 172 / 172 / 0 / 0 |
| `ci-scope-after-both-fixes.tap` | 两处修复后 ci-scope | **0** | tests 49 / pass 49 / fail 0 |

另实测未单独留文件的命令：`go vet ./internal/governance/ ./internal/handler/` **exit 0，无输出**；
`node scripts/aifi45-disposable/go-test-env-contract.mjs` **exit 0**（119 文件 / 0 违规）；
`sha256sum` 两次还原核对均 **match true**；`gofmt` 见 §5.1。

### 5.1 `gofmt -l` 报警的真实原因（既有 CRLF 现象，非本轮引入）

`gofmt -l internal/governance/approval_crosscheck_test.go` **点名该文件**，但这是 Windows 检出的 CRLF 造成的，不是格式缺陷：

- **内容级证明**：`gofmt <file>` 的输出与「原文件去掉全部 `\r`」逐字节 `diff -q` **完全一致**
  （`approval_crosscheck_test.go` 与 `execution_control_reservation.go` 两个文件各自验过，均 IDENTICAL apart from CR）。
  即本轮改动**本身是 gofmt 干净的**。
- **范围级证明**：工作树 `server/` 下 **2466 个 `.go` 文件中 2206 个是 CRLF**（`core.autocrlf=true` 的正常检出状态），
  260 个 LF-only 是历次会话用编辑工具写过的文件。`gofmt -l internal/governance/` 共点名 **65 个文件**；
  **从未被本 change 触碰**的 `cmd/migrate/main.go`、`cmd/maintenance/main.go` 同样被点名。
- `git diff --numstat` 对该文件为 **9 插入 / 19 删除**（git 按 autocrlf 归一化），**不是整文件 432 行翻动**，
  证明本轮没有把行尾整体翻转。
- **未执行 `gofmt -w`**：那会把该文件行尾整体改成 LF，属与修复无关的改动。CI-linux 检出为 LF，`gofmt` 在该环境下不会因此报警。
- 如实声明：**「`gofmt -l` 无输出」在本机不成立**，不把它写成通过项；成立的是「改动内容 gofmt 干净」与「`go vet` exit 0」。

## 6. 本轮未验证 / 未完成（不得记为通过）

1. **CI-linux 真实行为未验证**。§4.1 的「三处 skip 会让 `backend-tests` 判红」是**读码 + 归属表/门禁规则推断**，
   加上本机真库证明「缺变量即 Fatal」；**未在 ubuntu-latest 上跑过**。修复消除了推断中的 skip 来源，
   但「修复后 CI 全绿」仍属 **TC-CBE-005**，须推送另行授权，**不提前报绿**。
2. **tools pin `e52b8081f159` 不在 origin**（ADJ-025）。即使推送，tools 检出步骤会先失败；
   SC-CBE-005 的 U1 路径 β 适用，验收报告须记**真实失败步骤**（checkout，而非其后的 pin 完整性检查）。
3. **`TestChannelIsolation*` 的 WSL 半句仍 UNCOVERED**（ADJ-024 / TC-TOR-004）。本轮未启动 WSL、未安装任何东西。
4. **管理员 PAT（SC-CCF-003 / TC-CCF-003）未闭合**；本轮未读取、创建或轮换任何凭据。
5. **验收报告（TC-TOR-005）尚未生成**，属 C7。
6. **`make test` 未执行**（U5 排除）。本轮只跑 runner 自建一次性实例下的指定 selection 与 node 测试。
7. **4 个 Linux-only daemon 测试文件从未在 Windows 编译**，首次 CI-linux 运行的失败面未知（test_config 评审指出）。
8. **未修复项**：§3.2 的锁语义/FK、§3.3 的解析硬失败、§3.4 的不可达守卫、§3.5 的扫描器模式扩围、
   §3.9/§3.10 的 Gate 2 锁定输入缺陷——各自理由已写明，全部登记为 ADJ 并在 Gate 3 呈报，**不静默略过**。
9. **`allowed-skips` 只是下界**：它声明的是已观察/已推导的 skip，不保证 CI-linux 上不会出现新的 skip 来源。
   §4.1 正是该下界之外的一例（本机不可见）。**不声称名单已穷尽**。
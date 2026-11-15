# 设计调整说明

> 原始设计基线：Phase 2 产出的 design.md + specs/*.md + canonical/ + test-plan.md（Gate 1 重签 2026-11-13T23:32:41，Gate 2 确认 23:32:42）
> 调整来源：Phase 3 (BUILD) 实现与 C1 三路评审中的发现
> 处理原则：受审文档字节一旦变化，对应 Gate 即 stale（`_shared/revision-rules.md`）。下列调整**均未修改受审文档**，只在此记录；是否勘误并重审 Gate 由用户在 Gate 3 决定。

## 调整汇总

| # | 调整类型 | 涉及文档 | 严重程度 | 调整阶段 | 影响 TC | 用户已知 |
|---|---------|---------|---------|---------|---------|---------|
| 1 | 事实性勘误：`business` 不是 crctl 子命令 | proposal、canonical proposal、canonical code spec（SC-NTR-005 GIVEN）、Human View spec、test-plan §四首行、phase-context | Minor（文字，行为与测试不受影响） | Phase 3 | TC-NTR-005 | 否（待 Gate 3 告知） |
| 2 | 测试偏差：sensitive-action 用离线形态而非「本地 startPlatform 平台替身」 | test-plan（TC-NTR-006 预置条件） | Minor | Phase 3 | TC-NTR-006 | 否（待 Gate 3 告知） |
| 3 | 夹具描述不全：两个 helper 都加了默认关闭 opt-in，另增 `omitGrant` | design.md Decision 6 | Minor | Phase 3 | TC-NTR-001 | 否 |
| 4 | 行号漂移：archive 消费点区间起点 | design.md 调用点清单 | Minor | Phase 3 | — | 否 |
| 5 | 状态字样过时：test-plan 各 TC「当前状态」仍为「测试缺（待实现）」 | test-plan | Minor | Phase 3 | TC-NTR-001..008 | 否 |

## 调整详细说明

### 调整 1: `business` 被当作子命令

- **原始设计**：proposal 的「未受影响命令」清单、SC-NTR-005 GIVEN、test-plan §四首行把 `business` 与 `kb`/`workspace`/`git` 并列为命令。
- **实际情况**：`crctl.mjs` 的分发里没有 `business` 子命令；业务入口是 `planning-entry` 与 `competitive-report`（`BUSINESS_ENTRY_KINDS`，派发在其 `if (BUSINESS_ENTRY_KINDS[cmd])` 分支）。design.md 的 Architecture 表写法是正确的。
- **本次处理**：TC-NTR-005 实际覆盖的是 `planning-entry`、`competitive-report`，没有写 `business` 用例。`crctl.mjs` 里 `resolveTrustRoot` 上方的注释已改为 `planning-entry/competitive-report`（代码注释，非受审文档）。受审文档文字**未改**。
- **影响范围**：纯文字；生效命令集合、测试断言和 SC-NTR-005 的语义都不变。
- **如要勘误**：proposal / canonical proposal 变化 → Gate 1 与 Gate 2 重审；仅 spec/test-plan 变化 → Gate 2 重审。
- **用户已知**：否

### 调整 2: TC-NTR-006 的 sensitive-action 为离线形态

- **原始设计**：test-plan TC-NTR-006 预置条件写「sensitive-action（本地 startPlatform 平台替身）」，design 影响表写「再走现有平台配额请求」。
- **实际情况**：`startPlatform` 定义在 `execution-authorization.test.mjs`，未从 `tac-control-fixture.mjs` 导出；复用需改既有测试文件，与 design Decision 6「不改既有测试文件」冲突。实现改为清空 `MULTICA_SERVER_URL`/`MULTICA_DAEMON_TOKEN`，断言变量通道与同值 flag 通道得到同一个 `EXECUTION_SENSITIVE_ACTION_SERVER_REQUIRED`，并用空信任根探针证明变量真的选中了信任根（读取所选根的 grant 先于平台裁决）。
- **未覆盖**：「读 grant 之后向平台发配额请求」这一段没有用例。该段不经过变量解析，由既有 `execution-authorization.test.mjs`（经 CP-NTR-009 回归）覆盖。
- **影响范围**：SC-NTR-006 的「与同值 flag 一致」仍被验证；覆盖深度比 test-plan 文字浅一层。
- **用户已知**：否

### 调整 3: 夹具改动范围

- **原始设计**：design.md Decision 6 只提 `invokeControl`，并说明如需省略 flag 只加默认关闭的 opt-in。
- **实际情况**：`invokeControl` 与 `invokePlain` 都新增 `trustChannel: 'flag'|'env'`（默认 `flag`）；`invokeControl` 另增 `omitGrant`（默认 `false`），用于覆盖节点 skill 的真实调用形态——`crctl advance` 不带 `--grant`，走 `readGrantForCR` 扫描所选信任根（C1 test_config 评审的中危发现，已补 TC-NTR-001 子测试）。
- **默认值不变**：既有调用点参数序列逐字等价；delivery / repair / trust-anchor-chain 三个文件回归全绿。
- **用户已知**：否

### 调整 4: design.md 行号区间

- design.md 引用 `crctl.mjs` 区间 `7189-7247`；`7189` 起点是 `cmdUpgradeCheck`，archive 的消费点在 `cmdArchive`（起于 7198，消费在 7211/7218/7269）。命令归属结论不受影响。

### 调整 5: test-plan 状态字样

- test-plan 各 TC「当前状态」仍写「测试缺（待实现）」。test-plan 顶部已声明「BUILD 实际结果以 test-report.md 为准」，本变更的实际结果见 test-report.md。

## 记录与处置

- 以上 5 项均来自 C1 评审（docs_skills 与 test_config）并经主会话核实；`business` 与 sensitive-action 两项已对照 `crctl.mjs` 与测试文件确认。
- 评审另提「SC-NTR-006 的 evidence 指向 `proposal#what_changes[2]` 不够贴切」：编号基准（0 起或 1 起）有歧义，主会话未能确认是误指，不记为偏差。
- 未采纳的评审建议：TC-NTR-006 的 `assertTrustRootSelected`（空根结果与真实根结果必须不同）保持不变——变量被忽略时两次结果相同，该断言会红，有鉴别力。

## ADJ-6 并入 multica A0 发现的第二处接缝（2026-11-14，经用户裁定，范围变更而非实现偏离）

- **来源**：multica `2026-11-13-aifi-45-real-execution-closure` 的无模型替身运行（A0）；其 `design-adjustments.md#ADJ-A0-1` 记录 B1（daemon source 路径，multica 内）与 B2（本仓 inspect 缺 authority 键）。
- **用户裁定**：先「B2 选 A」，经只读成本核对（并入 vs 另开）后裁定「并入」本 change（proposal Q5）。
- **影响**：proposal、design（决策 7）、canonical code/agent spec（REQ-NTR-005、SC-NTR-009/010、CP-NTR-010/011）、test-plan（TC-NTR-010/011）已同步，Gate 1/2 因此过期、Gate 3 随之过期；Gate 3 的证据 run `e9c97c8d-…` 将因 `crctl.mjs` 与金样本变化而失配，须在最终代码上取新 run，旧 9 项 + 新 2 项同一个 run。尚未改任何代码、测试、夹具或登记表。
- **既有 5 项调整（ADJ-1..5）**仍只存在于本文件，未落入受审文档；本轮同步没有顺手把它们并入，沿用原处置（并入将是另一次范围扩张）。
- **一并修复**：test-plan 原文「逐行解析」一行里 `split(/\r?\n/)` 被写成了含真实回车换行的坏文本，本轮顺带恢复为字面的 `split(/\r?\n/)`（受审文档本来就要变）。

## ADJ-7 S4（决策 7）实现与受审文档的一处预测偏差：金样本无需改动(2026-11-14,不改受审文档,仅记录)

- **事实**:决策 7、test-plan TC-NTR-011、SC-NTR-010 均预测「`crctl-detail` 金样本 `workspace-inspect.json` 的字段路径集合随之增补(`targetVersion` 必增)」。BUILD 实测(临时脚本复刻 `crctl-summary` 夹具后跑 inspect --detail):该夹具的 `operationalWorkspace` 为 null(`CR_WORKTREE_STATUS_MISSING`,夹具没有 CR worktree 的 cr.md),故两个新键都是 null;金样本 `fieldPaths` 不计 null,路径集合不变。若强行加路径,summary 的双向全等反而失败。结论:**金样本零字节改动**(`git diff HEAD --quiet` 仍为 0),`crctl-summary.test.mjs` 8/8 不改而通过。
- **影响**:受审文档里「同步金样本」的步骤落空,但 TC-NTR-011 的验收(`crctl-summary` 通过、既有键与默认面不变)仍成立且更强(无需改金样本);SC-NTR-010 文字里的「增补这两个路径后」条件为空成立。新键的结构由 TC-NTR-010 的六种真实工作区情形承担,金样本不覆盖它们——这是已知的覆盖空缺,不是新引入的风险。
- **为何只记录**:验收口径与测试选择不变,仅一条预测性实现细节被事实推翻;按 revision-rules 属只新增调整记录,Gate 3 一并确认。若用户认为 spec/test-plan 文字必须同步,可另行裁定并重审 Gate 2。
- **实现摘要**:`crctl.mjs` 对 HEAD 纯插入 15 行(`git diff HEAD` 无删改行),变量名 `specMode`;新测试 `workspace-inspect-authority.test.mjs`(1 个顶层 + 6 子测试),`gate-registry.json` 登记 2 行;`ensureWorkspace` 三处返回均为新建对象字面量,消费者无按完整键集读取者(唯一严格检查是金样本 fieldPaths)。主会话变异检查:去掉 `Object.assign`、去掉 catch、去掉 mode 判断、改写版本值,均使 TC-NTR-010 红并还原(`cmp` 与备份一致)。

## ADJ-8 S5（决策 8）实现与验证记录：与受审文档一致，两处取证口径需如实写明(2026-11-14，不改受审文档，仅记录)

- **实现与 design 一致**：`lib/git-shim-path.mjs`（`stripGitShimDirs`，识别规则、4096 字节上限、空条目与读不到时保留、无移除时返回原字符串）、`crctl.mjs` 纯插入 8 行（1 行 import，`main()` 第一条语句处 2 行注释加 5 行代码；对 HEAD 合计 45 行插入、0 删除，即 S1 的 22 行、S4 的 15 行加本次 8 行）。新测试文件 `crctl-git-shim-path.test.mjs`（TC-NTR-012，4 个子用例）与 `gate-registry.json` 的 files/cases 各 1 行登记。`gate-registry.json` 对 HEAD 的 1 行删除是上一条目补尾逗号，不是改他人条目。
- **取证口径 1（受审文档已预告，此处落实）**：真实进程接线子用例需要执行 POSIX 脚本，本机 Windows 上 skip（4 pass / 1 skip）。为不让接线只靠纯函数子用例，主会话在一次性容器里额外跑了它：`node:22-alpine`（本机已有镜像）、tools 树只读挂载、容器内 `apk add git`、`--rm`，运行与变异检查都在容器内的拷贝上做，宿主文件未动。结果：顶层加 4 个子用例全绿（5 pass）。**该容器取证不在同次执行证据计划（CP-NTR-012 由 `stdd agent verify` 在本机运行，子用例 4 在 win32 skip）之内，不得写成 CP-NTR-012 的证据**；真实栈上的接线仍由 multica 的 A0 与真实运行观察。
- **取证口径 2（变异检查，容器内拷贝）**：M1 不剥离、M3 去标记判定、M4 去大小上限、M5 忽略 delimiter 参数、M6 反转顺序、M7 不识别 git.cmd 均使 TC-NTR-012 红；M2 删除 `main()` 里的调用只使子用例 4 红（证明接线子用例有区分力）。**M8（去掉空条目保护）与 M9 测试无法区分**：M8 只在进程 cwd 里恰好有含标记的 `git` 文件时才有可观察差异，测试进程的 cwd 没有；M9（`+ ""`）是我设计的等价变异，作废。不为 M8 增加测试：空条目的保留写在 design 伪码里，受审口径是「空条目逐字保留」，没有被任何已批准保证依赖 cwd 探测。
- **RED 的真实原因**（子代理 `GB-JP/deepseek-flash:max`，actual = unknown，容器内跑）：子用例 1/2/3 为 `ERR_MODULE_NOT_FOUND`（动态 import）；子用例 4 为 shim 被执行（marker 文件存在，CRCTL 报 `WORKSPACE_GIT_INSPECT_FAILED`，exit=97）。去掉 shim 的对照实验里记录器日志非空、退出码 0，说明断言不会空通过。
- **回归**（子代理报告，本机）：`node-trust-root` 42/42、`workspace-inspect-authority` 7/7、`caller-contract` 16/16（确认注释未踩 `crctl <子命令>` 字面量）、`crctl-summary` 8/8、`suite-gate-count` 8/8、`suite-gate-leaf-memory` 40/40、`contract-scan` 44/44、`crctl` 301/301。全量套件见 test-report。
- **容器使用次数**：子代理 RED 约 3 次、GREEN 约 2 次，主会话变异 1 次（第一次因 Git Bash 把容器内路径 `/m/mut.sh` 转成 `M:/mut.sh` 而没启动，不计运行结果）；均 `--rm`、名称带 `aifi45-ntr012-`，运行后 `podman ps -a` 只有 `multica-postgres`、`multica-backend`。

## ADJ-9 C1 三路评审（S4 + S5 增量）的处置与取证口径(2026-11-14，不改受审文档，仅记录)

评审三路均只读，由 pi-web 内置子代理派发：code=strong `GB-JP/kimi-k3.1-pro:max`、test_config=balanced `GB-JP/deepseek-flash:max`、docs_skills=economy `Gobao/deepseek-flash:high`；configured 来自 `stdd config models --format json`，actual 无运行元数据可核，记 unknown。**code 路第一次派发因模型服务中断（`STOP_ENGINE_ABORT`）没有产出，已原样重派，没有换模型。**

| 路 | Critical | High | Medium | Low |
|---|---|---|---|---|
| code | 0 | 0 | 1 | 1 |
| test_config | 0 | 0 | 1 | 6 |
| docs_skills | 0 | 1 | 4 | 11 |

**已修复（非受审文件，或在已批准保证内补测试）**

1. **test_config Medium（SC-NTR-010「默认面键集不变且不含新增两键」没有可红测试）**：属于已批准保证的测试缺口，不是新增需求，故在原 TC 范围内补。主会话先复现：把 `targetSpecId`、`targetVersion` 加进 `lib/summary-projectors.mjs` 的 `projectWorkspaceInspect` 允许列表（在 `tools_mut` 临时拷贝里做，宿主不动），`crctl-summary` 8/8 与 `workspace-inspect-authority` 7/7 **全绿**（不可区分）。随后在 `test/crctl-summary.test.mjs` 的 summary-04 末尾**纯插入 5 行**（2 行注释、对 workspace inspect 断言默认面不含这两个键），同一变异下 summary-04 红，宿主上 `crctl-summary` 8/8、`caller-contract` 16/16 仍过；`gate-registry` 的用例数不变（断言在既有用例内）。**这是对一个既有（HEAD 已跟踪）测试文件的修改**，不是他人未提交改动的一部分。
2. **docs High（multica `slices.md:71` 仍称 tools「Gate 3 已确认」）与 Medium（multica `design-adjustments.md:70`、tools `slices.md:3`）**：事实与记录不符，均非 Gate 输入（multica `design-adjustments.md` 只影响其 Gate 3）。已改为「Gate 1/2 于 2026-11-14T23:06:22 重签 current，Gate 3 stale」，ADJ-E4-1 行加「后更新」说明且保留原记录；tools `slices.md` 同步，并把「三个切片都改同一个测试文件」限定为 S1–S3。
3. **docs Low（`test-report.md`、`code-structure-delta.md`、`phase-context.md` 停留在 S1–S3）**：本轮 4.6/5.6 已重新生成/更新。
4. **docs Low（ADJ-8「S4 的 37 行」）**：我写错了——37 行是 S1 的 22 行加 S4 的 15 行；已改。

**驳回（引用条款）**

- **code Medium（Windows 带引号的 PATH 条目会漏剥 shim）**与 **code Low（相对 PATH 条目的探测基准与 POSIX 实际执行基准不一致）**：不修。design 决策 8 与 SC-NTR-011 的对象是「daemon 写入并前置到 agent PATH 的 shim 目录」，其来源是 `agentEnv["PATH"] = env.GitShimDir + string(os.PathListSeparator) + agentEnv["PATH"]`（multica `daemon.go:8815-8816`），`GitShimDir` 由 `prepareCRGuard` 的 `envRoot/bin` 拼出（`execenv/crguard_config.go:80`），**是裸的绝对目录，不带引号**。决策 8 同时写明「shim 本来就不是隔离」，agent 手工构造带引号或相对的 PATH 条目不在本保证内（不增加识别规则、不增加形态探测，见 proposal non_goals「不新增 shim 形态探测」）。两项都是假想输入，不为它们加分支。风险：若 daemon 以后改成带引号或相对目录注入，识别会失效，失败方向是回到 B4 失败（失败关闭），由 TC-NTR-012 与 multica A0/真实运行兜底。
- **test_config Low「4096 字节边界未被钉住」**：不加。M4（去掉大小上限）已使子用例 2 红，说明上限本身被钉住；4095/4096 的精确边界是实现细节，受审口径是「小于 4096」，不为一个字节边界单列用例。
- **test_config Low「夹具构造中途失败会泄漏临时目录」**：不改。仅在夹具抛错的路径上泄漏系统临时目录，不影响断言与仓库；与 S1–S3 既有测试写法一致。
- **test_config Low「读文件失败分支未覆盖」**：不加。无法在 Windows 与以 root 运行的容器里可移植地构造不可读文件；该分支只有一行 catch 返回「保留」，失败方向安全（宁可不剥）。
- **test_config Low「CP-NTR-009/011 只断言 `# fail 0`、没有用例数下限」**与**「子用例 4 有第二处 skip（无真实 git）、子用例 1 有 POSIX 条件断言，test-plan 只声明 win32 skip」**：受审文档（canonical agent spec、test-plan）的文字问题，不改文件；是否勘误由用户在 Gate 3 决定。这两条都不改变 CP-NTR-012 在本机的判定：run 里它显示 `ok 1 - TC-NTR-012`，其中子用例 4 在 win32 skip（见 ADJ-8 取证口径）。

**留给用户在 Gate 3 决定（受审文档的文字问题，均不改变行为；勘误需重审 Gate 2，建议不勘误，除第 1 项外）**

1. **docs Medium：canonical code spec 里新增三条 SC 的 `evidence: proposal#success_criteria[N]` 用 0 起编号，同文件 SC-NTR-001..008 用 1 起。** 我复核了 canonical proposal：新增的 `[6]`、`[7]`、`[9]` 在 0 起下分别是 inspect 两键、默认面不变、PATH 剥离（语义正确），旧的 SC-NTR-001..008 按 1 起写。同一文件两种基准并存，读者按任一基准都会指错一部分。**这是一个真实的追溯标签不一致**，成本是重审一次 Gate 2（Gate 3 本来就要重签，Gate 2 与 Gate 3 可在同一次回复里确认）。建议：要么统一后重签，要么接受并在 test-report 注明两种基准。
2. design 决策 7 预测「金样本路径必增」被 ADJ-7 实测推翻，同样的预设残留在 proposal/spec/test-plan 的几处措辞；以 ADJ-7 为准，建议不勘误。
3. design 决策 8 的若干措辞（`cmd/multica/cmd_gitguard.go` 路径写法、Windows 下 shim 目录实际是 4 个文件、接口锚定里「值为 `store.Root`」已被 multica D1.10/S12 改为 generation 子目录）、test-plan 案例 6.1 的「复用 TC-NTR-010 夹具」实际是另建夹具、`proposal.md`（生成物）不含 open_questions/constraints/non_goals/risk_areas：均为文字问题。其中「接口锚定值」一条与 multica 现状不一致，Gate 3 时请知悉。

### ADJ-9 结项：用户在 Gate 3 的决定（2026-11-15）

用户原话：「确认 tools Gate 3；统一后重签；同意重跑真实整栈 A0(13.2b)」。AI 的解读：① 确认 tools Gate 3；② 对上面「留给用户在 Gate 3 决定」第 1 项选择**统一编号后重签**（改受审文档 → 重审 Gate 2）；③ 同意重跑 A0（13.2b，零模型，1 次）。第 2、3 项文字问题用户未要求勘误，因此保持原样（design 决策 7 的金样本预测以 ADJ-7 为准）。

已执行（改的是受审文档的追溯标签，SC/REQ 文字与验收口径不变）：

- `canonical/specs/code/crctl-execution-trust-root.yaml` 三条 evidence 由 0 起改为 1 起，与同文件 SC-NTR-001..008 统一：SC-NTR-009 `success_criteria[6]`→`[7]`、SC-NTR-010 `[7]`→`[8]`、SC-NTR-011 `[9]`→`[10]`。改后逐条对照 canonical proposal 的条目：`[7]` 是 inspect 两键、`[8]` 是默认面不变、`[10]` 是 PATH 剥离，语义对齐；其余 8 条旧 SC 与 SC-NTR-006 的 `what_changes[2]` 复核后本就用 1 起且指向正确，未动。**没有任何 REQ/SC 语句、TC、CP、验收口径、风险或范围发生变化**，所以 Gate 1 不重审。
- `specs/crctl-execution-trust-root/spec.md` 重新生成后**字节完全相同**（`md5 1aded99c43b087e5f6871333e7924c05`，Human View 不渲染 evidence）；`stdd validate` 通过。
- 因受审字节变化，Gate 2 变 stale 并用 `--reapprove` 重签；Gate 3 随后以新 run `c8385d47-d636-43b7-b12f-8db5d8615a16`（12/12 CP）重签。

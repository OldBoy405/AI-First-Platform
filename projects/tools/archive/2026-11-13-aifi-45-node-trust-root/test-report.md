# 2026-11-13-aifi-45-node-trust-root 测试报告

> 测试日期：2026-11-14
> 测试环境：Windows（Git Bash），node v24.15.0，`node --test`；无数据库、daemon、模型或外部网络
> 被测版本：tools 仓 HEAD `e52b808` + 本变更未提交改动（未提交、未推送）；覆盖 S1–S5（2026-11-14 并入 B2、B4 后重做）
> 选定 run：`c8385d47-d636-43b7-b12f-8db5d8615a16`（`validation/runs/c8385d47-d636-43b7-b12f-8db5d8615a16/tc-evidence.json`）；此前 S1–S3 的 run `e9c97c8d-…`（9 项）已被取代，不再引用
> 结果以选定 run 为准；未执行项写明“未执行”。

## 一、总体概况

| 指标 | 数值 |
|------|------|
| 计划 TC（CP） | 12（TC-NTR-001..012 ↔ CP-NTR-001..012） |
| 选定 run 通过 / 失败 | 12 / 0（`stdd agent verify`，`ci check-failures` 报「TC 当前执行覆盖 12/12 (100%)」「5 个切片均有验证证据」） |
| 新增测试 | `node-trust-root.test.mjs`：8 个顶层 + 34 个子测试 = 42；`workspace-inspect-authority.test.mjs`：7；`crctl-git-shim-path.test.mjs`：1 个顶层 + 4 个子测试（本机 win32 子用例 4 skip）；`crctl-summary.test.mjs` 在 summary-04 内加 5 行断言（用例数不变） |
| 回归（TC-NTR-009） | 既有四个 trust 测试文件 186/186 通过（execution-authorization 176、trust-anchor-chain 6、delivery 2、repair 2） |
| 覆盖率 | 豁免：证据计划声明 `not_applicable`（被测对象为 Node 脚本，覆盖率采集目前只支持 pytest-cov）；**无覆盖率数字** |

### 全量套件门禁（`suite-gate.mjs --run`）

**S4、S5 完成后最终一次（`suite-gate.mjs --run`，balanced 子代理运行并汇总，主会话核对 JSON）**：100 个文件、2237 个用例、约 12 分 32 秒，verdict=`block`，**唯一失败**为 `execution-control-isolation.test.mjs`「isolation 需要真实受限身份」（另有 `SUITE_COUNT_BELOW_BASELINE_WARN`：该文件顶层用例数 1 < 登记基线 3，同属这个既有失败）。较 S1–S3 的 98 个文件、2235 个用例多 2 个文件、2 个用例，正好是新增的 `workspace-inspect-authority` 与 `crctl-git-shim-path` 两个测试文件各 1 个顶层用例。

以下 S1–S3 阶段的叙述保留作历史记录：

S1–S3 阶段最终一次（改动定稿后）：98 个文件、2235 个用例、约 12 分 56 秒，verdict=`block`，**唯一失败**为 `execution-control-isolation.test.mjs`。

- 该失败**与本变更无关**：HEAD 干净副本（`git archive HEAD` 导出，未改仓库）上同样 `not ok`；该测试文件不含 `trust-root` 或 `CRCTL_EXECUTION` 字样；失败信息是 Windows 缺受限身份的环境前提。
- 因此门禁 verdict 仍为 `block`，**本报告不声称套件门禁通过**，只声称：除该既有环境失败外，其余 99 个文件全部 ok，包含 `node-trust-root`（8）、`workspace-inspect-authority`、`crctl-git-shim-path`、`caller-contract`（16）和四个 trust 文件。
- 另：同一 S4/S5 工作树上先用裸 `node --test` 跑过一次（不用 `suite-gate`），有 6 个文件失败，其中 5 个是 `*-memory.test.mjs`（门禁对它们加 `--experimental-vm-modules` 运行，裸跑口径不同）、另 1 个是 `execution-control-isolation`；这 6 个在 HEAD 干净副本上用例名集合完全相同，**不是回归**。门禁口径才是本报告所用。
- 过程记录：第二次运行出现 `caller-01`/`caller-09` 两项新失败。根因是新增子测试里一行注释写了 `` `crctl advance <CR> ...` ``，被 `caller-contract.test.mjs` 的字面量扫描当成命令调用（缺 `--workspace`、未登记）。已改注释写法，未动登记表；`caller-contract` 16/16 复跑通过，最终一次门禁中这两项不再出现。

## 二、按模块统计

| 测试模块 | 用例数 | 通过 | 失败 | 跳过 | 说明 |
|----------|--------|------|------|------|------|
| `test/node-trust-root.test.mjs`（新增） | 42 | 42 | 0 | 0 | TC-NTR-001..008（顶层 8） |
| `test/execution-authorization.test.mjs` 等四个既有文件 | 186 | 186 | 0 | 0 | TC-NTR-009 回归，未设置变量 |
| `test/workspace-inspect-authority.test.mjs`（新增） | 7 | 7 | 0 | 0 | TC-NTR-010（六种情形 + 顶层） |
| `test/crctl-git-shim-path.test.mjs`（新增） | 5 | 4 | 0 | 1 | TC-NTR-012；**本机 win32 子用例 4（真实进程接线）skip**（见下） |
| `test/crctl-summary.test.mjs`（既有，+5 行） | 8 | 8 | 0 | 0 | TC-NTR-011；summary-04 补「默认面不含 targetSpecId/targetVersion」 |
| `test/caller-contract.test.mjs` | 16 | 16 | 0 | 0 | 字面量扫描面包含新测试文件 |

## 三、E2E 与覆盖率

- E2E：不适用（tools 仓本地测试，无 E2E 配置）。
- 覆盖率：见上，豁免，无保证。
- Lint / 类型检查：**未执行**（本次未确认该项目有对应配置）；只做了 `node --check crctl.mjs` 语法检查，通过。

## 四、每切片验证状态

| 切片 | TC | 新增测试 | 状态 |
|------|----|---------|------|
| S1 合并规则核心 | 001/002/003/004/008 | 19（后经 C1 加固：TC-NTR-001 增 1、TC-NTR-004 增 1 个子测试） | 完成；RED 阶段 001–004 红、008 本为基线绿 |
| S2 生效范围与威胁边界 | 005/006/007 | 21 | 完成；变异检查见下 |
| S3 回归与登记 | 009 | 2（C1 加固所增子测试） | 完成；`gate-registry.json` 登记 files + cases=8 |
| S4 inspect 补字段（B2） | 010/011 | 7 | 完成；`crctl.mjs` 纯插入 15 行；金样本零字节改动（ADJ-7） |
| S5 PATH 剥离 shim 目录（B4） | 012 | 5（1 顶层 + 4 子用例） | 完成；`lib/git-shim-path.mjs` 新文件 + `crctl.mjs` 纯插入 8 行；本机 4 pass / 1 skip，容器 5 pass |

变异检查（每次均 `cmp` 确认 `crctl.mjs` 已还原）：

| 变异 | 结果 |
|------|------|
| 变量注入除 `git` 外的所有命令 | TC-NTR-005 红（6 个失败） |
| 去掉同值检查 | TC-NTR-003 红（4 个失败） |
| 从集合删去 repair-resume/register/archive | TC-NTR-006 红（4 个失败） |
| 从集合删去 `advance`（加固后复测） | TC-NTR-001 红 |

S4/S5 变异检查（S5 在**一次性容器内的拷贝**上做，宿主文件未动；每次还原后 `cmp`）：

| 变异 | 结果 |
|------|------|
| S5 M1 `stripGitShimDirs` 不剥离 | 子用例 1/2/4 红 |
| S5 M2 删除 `main()` 里的调用 | **仅子用例 4 红**（证明接线子用例有区分力） |
| S5 M3 去掉 `gitguard-exec` 标记判定 | 子用例 1/2/3/4 红 |
| S5 M4 去掉 4096 字节上限 | 子用例 2 红 |
| S5 M5 忽略 delimiter 参数 | 子用例 1 红 |
| S5 M6 反转保留顺序 | 子用例 2/4 红 |
| S5 M7 只识别 `git` 不识别 `git.cmd` | 子用例 1 红 |
| S5 M8 去掉空条目保护 | **不可区分**：只在进程 cwd 里恰有含标记的 `git` 时才有差异，测试进程 cwd 没有；不加测试（见 ADJ-8） |
| S5 M9 `+ ""` | 等价变异，作废 |
| S4 把 `targetSpecId`/`targetVersion` 加进默认面允许列表（C1 复核，临时拷贝） | **补断言前不可区分**（`crctl-summary` 8/8、`workspace-inspect-authority` 7/7 全绿），补断言后 summary-04 红（ADJ-9） |
| S4 其余（去 null 分支、改成抛错等） | TC-NTR-010/011 红（见 tasks 4.5 与 ADJ-7） |

**win32 取证口径（如实）**：TC-NTR-012 子用例 4 需执行 POSIX 脚本，本机 win32 skip，所以**本机 run 里的 CP-NTR-012 通过并不证明真实进程接线**。为不让接线只靠纯函数子用例，主会话另在一次性容器（`node:22-alpine`，tools 只读挂载，容器内 `apk add git`，`--rm`）里跑了它：顶层加 4 个子用例全绿（5 pass）。**该容器结果不属于 `stdd agent verify` 的同次执行证据，不得写成 CP-NTR-012 的证据**；真实栈上的接线由 multica 的无模型替身运行（A0）与真实运行观察。

## 五、功能/测试覆盖对照

| 规格场景 | 测试 | 说明 |
|---------|------|------|
| SC-NTR-001 仅变量时 advance 准入 | TC-NTR-001 | 含节点 skill 的真实调用形态（省略 `--grant`，走信任根扫描分支）；output 与 receipt 均不含通道名 |
| SC-NTR-002 输出字节一致、零副作用 | TC-NTR-002 | authorization-bind --check |
| SC-NTR-003 并存：同值通过、异值先于读取工作区拒绝 | TC-NTR-003 | 含尾分隔符算不同 |
| SC-NTR-004 非法值拒绝、不回退 `.crctl`、不消费分支忽略 | TC-NTR-004 | 8 类非法值各一子测试（含 junction，Windows 上真实创建并通过），含 `.crctl` 正控制与两通道对称的副作用断言 |
| SC-NTR-005 八命令之外不受影响 | TC-NTR-005、009 | 另验非生效命令不做并存校验（repair-assess/outcome） |
| SC-NTR-006 其余生效命令与同值 flag 一致 | TC-NTR-006 | sensitive-action 为离线形态（见 ADJ-2） |
| SC-NTR-007 自造信任根两通道结果一致，不声称平台授权 | TC-NTR-007 | 只断言通道等价，不断言自造根必被拒绝 |
| SC-NTR-008 无变量无 flag 行为不变 | TC-NTR-008 | 仍 `EXECUTION_CONSUMPTION_REQUIRED` |
| SC-NTR-009 inspect --detail 输出 targetSpecId/targetVersion | TC-NTR-010 | 六种情形（有效、legacy、单侧缺失、不一致、无版本、unassigned）；读不到给 null，inspect 仍成功退出 |
| SC-NTR-010 inspect 既有输出与默认面不变 | TC-NTR-011 | `crctl-summary` 8/8 + 金样本三层比对（金样本零字节改动，ADJ-7）；C1 后 summary-04 显式断言默认面不含两键 |
| SC-NTR-011 crctl 进程 PATH 剥离 shim 目录 | TC-NTR-012 | 识别并剥离、保留、无 shim 逐字不变、真实进程接线（POSIX；win32 skip，容器另验，见上） |

**TC-NTR-004 junction 用例**：已用 TAP 逐项核对，`ok 9 - 指向安装根内目录的 junction` 真实执行通过（实现用 `fs.symlinkSync(..., 'junction')`，创建失败会报错而不是跳过）；未单独测试 POSIX 符号链接，该平台行为沿用 `installDirectory` 的既有实现。

## 五-B、多路并行 Review 结果（C1）

| 代理 | 档位 | requested | actual | 范围 |
|------|------|-----------|--------|------|
| code | strong | `GB-JP/kimi-k3.1-pro:max` | unknown | 代码质量 |
| test_config | balanced | `GB-JP/deepseek-flash:max` | unknown | 测试/配置 |
| docs_skills | economy | `Gobao/deepseek-flash:high` | unknown | 文档/Skills |

三路均由 pi-web 内置子代理派发，只读。configured 来自 `stdd config models --format json`；actual 无运行元数据可核，记 unknown。

### 最终 Review 汇总

| 维度 | Critical | High | Medium | Low | 总计 |
|------|----------|------|--------|-----|------|
| 代码质量 | 0 | 0 | 0 | 0 | 0（通过） |
| 测试/配置 | 0 | 0 | 1 | 7 | 8 |
| 文档/Skills | 0 | 0 | 3 | 9 | 12 |

### 已处置的发现

| # | 严重性 | 位置 | 问题 | 处置 |
|---|--------|------|------|------|
| 1 | M | TC-NTR-001 / 夹具 | 节点 skill 实际调用不带 `--grant`，信任根扫描分支无用例 | 已修复：夹具加默认关闭的 `omitGrant`，新增子测试；变异复测红 |
| 2 | L | TC-NTR-001 | 只断言输出不含通道名，未断言 receipt | 已修复 |
| 3 | L | TC-NTR-004 | 「不回退 .crctl」缺正控制；副作用断言只有 env 通道 | 已修复 |
| 4 | L | TC-NTR-005 | repair-assess/outcome 无法区分注入与否；基线错误码强绑定夹具细节 | 已修复（并存探针；主断言改为 `≠ BAD_ARGS`） |
| 5 | M | docs / `crctl.mjs` 注释 | `business` 被当作命令 | 代码注释已修；受审文档**未改**，见 ADJ-1 |
| 6 | M | test-plan TC-NTR-006 | sensitive-action 预置条件与实现不一致 | 未改受审文档，记 ADJ-2 |
| 7 | M | tasks.md | 勾选与事实不一致 | 已修复（非受审文件） |
| 8 | L | design / test-plan | 夹具描述、行号、状态字样、测试名写法等文字问题 | 未改受审文档，记 ADJ-3/4/5 |

### 已驳回

- `assertTrustRootSelected` 无鉴别力（test_config 低）：驳回。变量被忽略时空根与真实根结果相同，该断言会红；依据 design Decision 6 与 SC-NTR-006。

### 第二轮（S4 + S5 增量）

code=strong、test_config=balanced、docs_skills=economy，requested 同上、actual 均 unknown；**code 路首次派发因模型服务中断没有产出，原样重派，未换模型**。计数：code 0/0/1/1，test_config 0/0/1/6，docs_skills 0/1/4/11（Critical/High/Medium/Low）。处置见 `design-adjustments.md#ADJ-9`：已修复 test_config Medium（SC-NTR-010 默认面无可红测试）、docs High 与两个 Medium（Gate 状态描述失实，均为非受审文件）；驳回 code 的 Medium/Low 两项（带引号/相对 PATH 条目，不在决策 8「daemon 写入的 shim 目录」范围）及若干 Low；受审文档的文字问题（含 `success_criteria[N]` 编号基准混用）留给用户在 Gate 3 决定。

### 未处置的已知项

- docs 评审另列：SC-NTR-006 evidence 编号指向、成功标准第 2 条文字缺「其值」二字、`test-plan.md:19` 一处转义被破坏、「不需要网络资源」对 CP-NTR-009 不精确（回环 HTTP 替身）。均为受审文档的文字问题，未改动，见 design-adjustments.md；是否勘误由用户在 Gate 3 决定。
- `.stdd.yaml` 的 traceability 计数为 0（`spec_scenarios`/`tc_cases`/`test_functions`），按 docs 评审说明属 deliver 前生成项，**本阶段未生成**。

## 六、设计调整说明

详见 [design-adjustments.md](design-adjustments.md)（5 项，均为文字或测试深度偏差，未改受审文档，不改变生产行为）。

## 七-B、失败模式检查（C4）与经验库

### 7.1 CLI 确定性子集（选定 run `c8385d47-d636-43b7-b12f-8db5d8615a16`，原文要点；(b) 一行沿用 S1–S3 阶段的说明）

| 检查 | 结果 | 要点 |
|---|---|---|
| (a) 必需文件 + Spec 存在 | PASS | |
| (b) 范围蔓延 | 本次未出现（S1–S3 阶段的 run 曾 WARN） | 本变更触及的文件见 `phase-context.md`；`code-structure-delta.md` 仍会列出 `lib/merge-effects.mjs`、`test/merge-effects.test.mjs`，那是他人未提交改动，未读取、未改动 |
| (d) TC-ID 唯一 | PASS | 12 个 |
| (f) THEN 含 SHALL | PASS | |
| (g) AND 数量 | PASS | |
| (j) 覆盖率义务 | PASS | 已声明无覆盖义务 |
| (k) 契约一致 | SKIP | 少于 2 个 capability |
| (l) Anchoring | PASS | non-critical，无需锚定 |
| 切片验证证据 | PASS | 5 个切片均有验证证据 |
| TC 当前执行覆盖 | PASS | 12/12（run `c8385d47-…`） |

合计（本次 run `c8385d47-…`，`stdd ci check-failures`）8 通过 / 0 警告 / 1 跳过 / 0 错误。**「14 类检查」资源根无权威逐项定义**（沿用 fork-ci 变更 ADJ-044 口径）：`(c)(e)(h)(i)(m)(n)` 标注未执行，不给判定；不声称「14 类全量执行通过」。

### 7.2 C4 语义检查

| 类别 | 判定 | 取证 |
|---|---|---|
| 先序列化锁再读守卫 / 常量 id 多链唯一键 | 不适用 | 无数据库、无并发写 |
| 清理只覆盖成功路径 | PASS | 所有 `mkdtempSync` 均带 `t.after(rm)`；运行前后工作树状态集合不变，未写入 tools 仓 |
| 每个拒绝条件一个独立 subtest | PASS | TC-NTR-004 表驱动按行独立；删同值检查变异使 TC-NTR-003 红 4 项 |
| 驱动拒绝未知参数 | 不适用 | 本变更不是驱动；crctl 对多数命令无 flag 白名单是既有行为，设计声明不改 |
| 逐行解析多行输出 | PASS | 测试文件内无 `split(`、`lines[0]`、`shift()`；按整段 JSON 解析 |
| 锚定缺失 | PASS | non-critical |
| Agent CP 失败 | PASS | 12/12 |
| 默认面/权威键只在 detail 面（S4） | **命中（已修复）** | C1 复核：键进入默认面允许列表时既有测试全绿；已在 summary-04 补断言（ADJ-9） |
| shim 识别依赖字面量与注入形态（S5） | 已知风险，已记录 | 识别靠 `gitguard-exec` 字面量与 daemon 的裸绝对目录注入；形态变化时回到 B4 失败（失败关闭），由 TC-NTR-012 固定字面量，multica A0/真实运行兜底（ADJ-9） |
| 跨系统不一致 | **命中** | docs ↔ 代码 ↔ test-plan 的 5 项文字偏差（ADJ-1..5），未改变行为 |
| 测试夹具恒传某参数→生产形态未覆盖 | **命中（已修复，已入库）** | 见上 #1；新增经验 EXP-2026-0001（`coverage_vacuum`） |

经验库：本次新增 1 条（EXP-2026-0001），复用 0 条，库内原有 0 条。

## 八、结论

- 实现范围：`crctl.mjs` 新增 22 行（变量名常量、八命令集合、`resolveTrustRoot`，在 `main()` 的 `parseArgs` 后、`bindTaskWorkspace` 前调用一次）；夹具与测试按上文。生产代码未触及 `lib/*`、grant/签名/binding/receipt/verdict 合同、状态机与 `gates.json`。
- **S4、S5 并入后**：12 个 CP 全部通过（run `c8385d47-…`），既有 186 个 trust 用例无回归；套件门禁除既有环境失败外全部通过（100 文件、2237 用例，verdict=`block`）。`crctl.mjs` 对 HEAD 共纯插入 45 行（S1 22 + S4 15 + S5 8），0 删除；另新增 `lib/git-shim-path.mjs`。inspect 补 `targetSpecId`/`targetVersion`（B2）；crctl 入口把含 controlled-shell shim 的目录从**自己进程**的 PATH 移除（B4），不改 shim、`rules.json`、crctl 的 git 白名单与调用者名，daemon 不发布规则变量。
- **未验证（如实）**：真实进程接线在本机 win32 skip，只在一次性容器内验证（不属同次执行证据）；真实栈上的 `next`/`workspace inspect`/两次 `advance` 在 shim 环境下的成功，目前只有 multica 的 what-if 观察（替身口径，不是 TC 证据），须由 multica 重跑 A0 与真实运行承担。
- 9 个 CP（S1–S3）的旧结论保留：既有 186 个用例无回归。
- **默认行为不变**：变量未设时与改动前完全一致。变量只是 `--trust-root` 的另一条输入通道，不新增 agent 能力、不提供隔离；本地准入成功不等于平台授权，平台侧预消费回执才是权威（SC-NTR-007，design Decision 4）。
- 对 AGENTS.md「规则只向前」：本变更没有新增或收紧门禁或信任判据，只加一条可选输入通道，未设变量时行为不变。注意 Q3：`register`/`archive` 在变量已设时与同值 flag 一样进入 control admission 并失败关闭。multica 只能对需要的授权 agent 进程注入，不得写入 daemon 全局环境，否则会影响这两个命令的旧调用。
- 未验证项：POSIX 符号链接（本次只在 Windows 跑过 junction）；真实 daemon 注入、真实节点 run（属 multica 成对 change，本变更不覆盖）；Lint/类型检查。
- 风险等级：低。待办：multica 成对 change 的 design/spec/test-plan 同步与其 Gate 2 重审、daemon 注入实现、真实运行；发布顺序为先 tools 后 daemon 注入。

### 8.1 质量信号汇总

| 信号源 | 状态 | 备注 |
|--------|------|------|
| 单元/集成测试 | ✅ | 选定 run 12/12；`node-trust-root` 42/42；`workspace-inspect-authority` 7/7；`crctl-git-shim-path` 本机 4 pass/1 skip、容器 5 pass；回归 186/186 |
| 套件门禁 | ❌（既有环境失败） | 100 文件/2237 用例；唯一失败 `execution-control-isolation`，HEAD 复测同样失败，与本变更无关 |
| E2E | N/A | |
| Lint / 类型检查 | 未执行 | 仅 `node --check` |
| 覆盖率 | N/A | 豁免，无保证 |
| 失败模式 | 命中 3 项，均已处置或记录 | CLI 8 通过 / 0 警告 / 1 跳过 / 0 错误；14 类口径缺口如实标注 |

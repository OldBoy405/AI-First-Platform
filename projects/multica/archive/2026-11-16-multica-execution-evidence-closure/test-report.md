# test-report — 2026-11-16-multica-execution-evidence-closure

- change：`2026-11-16-multica-execution-evidence-closure`（业务仓 multica，记录根 AI First Platform）
- 日期：2026-11-16
- 模式：standard / long_range full_auto（范围内预授权；发布/CI 经用户独立授权）
- 最终业务提交：`f8a23564a0b33ffb36cb535de27d4b515447e255`（已 push origin/main，`294d793a9..f8a23564a`）
- **状态：TC-MEC-003（真实 CI 权威）经用户明确裁定本轮延期为 not_applicable（接受风险），权威 CI 验证仍未完成；受审文档已按 revision-rules 一轮同步修订并重审 Gate 1+2（旧证据已在新 run 重跑）。TC-MEC-001/002 命令 CP 重跑通过，TC-MEC-004 人工已确认、切片3 已登记。CLI 机械覆盖 4/4，但其中 TC-MEC-003 是延期 not_applicable，绝不等于 CI 通过。Gate 3 确认框待展示，须用户原话批准，AI 不代签。**

## 0. 本轮延期修订与 Gate 重审（受审承诺变化）

- 用户裁定（AskUserQuestion 原话「修订计划延期 TC-MEC-003」）：真实 CI 因平台账单/额度阻塞，本轮把 TC-MEC-003 的必需证据延期为 not_applicable（接受风险），先收口其余已验证项。这**改变受审承诺**，按 `_shared/revision-rules.md` 一轮同步修订 proposal.yaml/proposal.md、canonical/specs/code/ci-backend-environment.yaml 及其 spec.md、design.md、test-plan.md（agent spec 核实未变），完整差异一次性展示。
- 用户原话「确认重签Gate 1+2」后，CLI 分别落回执：**Gate 1 confirmed 2026-11-16T10:23:55、Gate 2 confirmed 2026-11-16T10:25:47**（均 confirmed_by=dialog，evidence=「确认重签Gate 1+2」）。Gate 2 因 ci-backend-environment 的 spec.md Human View 漂移先拒绝，删除该派生视图后经 CLI missing→render 路径重生并确认；canonical YAML 为修订真源。
- 旧证据重跑：受审字节变化使旧 run `2d5d4330…` 冻结的是修订前 test-plan，已作废；新 run **`0ccb7130-dbe0-4c0c-b7f4-28aeca9a38a6`** 重跑两个命令 CP，均真实重通过（见第1节）。
- **延期不是豁免、不是绿灯**：TC-MEC-003 记 not_applicable 并保留真实阻塞原因，权威 CI 验证仍未完成，额度恢复后须对最终 SHA 另行验证以满足 SC-MEC-006 全部 SHALL；不继承前驱 TC-BTO-005 的 N/A，非用户裁定的自动 N/A 仍禁止。

## 1. 选定 run 与结果引用

- 同次执行证据 run：**`0ccb7130-dbe0-4c0c-b7f4-28aeca9a38a6`**（`validation/runs/0ccb7130-dbe0-4c0c-b7f4-28aeca9a38a6/`）。
  - `stdd agent verify … --run 0ccb7130…`：**2 passed / 0 failed**。CP-MEC-001 一次性库 `-race -count=1` `PASS governance-run-lock pass=4 fail=0 skip=0`、四项 expected matched、实例 4166e2ba8508 已释放；CP-MEC-002 离线 `# fail 0`/`# skipped 0`、含 TC-MEC-002 event matrix 与 CI wiring 全部断言。23 个 project 输入 sha256 冻结（与提交态一致），test-plan/agent-spec/config 快照冻结，coverage_files=[]。confirm 前 REVIEW_PENDING＝TC-MEC-004/custom-trace（required manual）。
  - `stdd agent confirm … --run 0ccb7130… --statement "执行 confirm 并继续后续流程"`：记录 TC-MEC-004/custom-trace（subject b8d904d418e06c692656e1665c0e21166b0da63bd240db39078ecbb02f10603d）。statement 为用户原话，AI 未代写结论。
  - `stdd ci check-failures … --run 0ccb7130…`（同一 run，其间无其它 verify）：确定性子集 **9/9 执行，9 通过 / 0 错误**；TC 当前执行覆盖 **4/4**（TC-MEC-003 not_applicable 机械计入分子，见第2节诚实标注）。
  - tc-evidence.json 四项处置：TC-MEC-001 pass(required,exit0)、TC-MEC-002 pass(required,exit0)、TC-MEC-003 **not_applicable**（reason＝账单阻塞＋用户裁定延期）、TC-MEC-004 **manual-pass**(required)。
- 真实 CI run（TC-MEC-003 权威，本轮延期未验证）：**43752944966**，https://github.com/OldBoy405/AI-First-multica/actions/runs/43752944966 ，workflow CI、event push、headSha=`f8a23564a`、createdAt 2026-11-15T19:31:59Z（本地 2026-11-16T03:31:59+08:00），conclusion=**failure**。**根因＝GitHub 托管 runner 无法分配（账单/额度），非代码失败**：`changes` job `runner_id=0`/`runner_name=""`/`steps=[]`/2 秒 failure，`backend`/`frontend` 门控同样零步骤 failure，`backend-tests`/`transitions-contract-check`/`frontend-*`/`sqlc-check` 等全部 **skipped**；`--log-failed` 报 `log not found: 132930712183`。六测试、真实 rules.json 日志、backend Test/对账/admin、两个生成 --check **均未执行**。

## 2. TC 覆盖（planned vs actual）

| TC | 类型 | 计划 | 实际 | 证据/缺口 |
|---|---|---|---|---|
| TC-MEC-001 | required command | 1 | 1 pass | run 0ccb7130 CP-MEC-001：一次性库 `-race -count=1` `PASS governance-run-lock pass=4 fail=0 skip=0`，四项 expected matched，实例 4166e2ba8508 已释放；切片2 CLI receipt new_tests=1 |
| TC-MEC-002 | required command | 1 | 1 pass | run 0ccb7130 CP-MEC-002：离线 `# fail 0`/`# skipped 0`，含 TC-MEC-002 event matrix 与 CI wiring；切片1 CLI receipt new_tests=3 |
| TC-MEC-003 | required manual → **本轮 not_applicable（延期，接受风险）** | 1 | **0 执行 / not_applicable** | 真实 CI 43752944966 账单阻塞，runner_id=0、六测试 skipped，**权威验证未完成**；经用户裁定延期，reason 如实保留；不继承前驱 N/A，不以本地组替代，**不等于 CI 通过** |
| TC-MEC-004 | required manual | 1 | 1 manual-pass | 台账事实经交付树 f8a23564a 实测核对（前三数 629/1722/789、5816 文件、+0/+4/+4 归因、第四数未决、CRLF 1126/0），用户原话「执行 confirm 并继续后续流程」确认；切片3 CLI receipt new_tests=0 |

必需 command 2/2 通过；required manual TC-MEC-004 已确认、TC-MEC-003 延期 not_applicable。**CLI 机械覆盖 4/4 把 not_applicable 计入分子——这是处置完整性，不是执行通过；TC-MEC-003 的真实 CI 验证仍未完成，报告与 Gate 3 均显式标注延期/未验证/接受风险。**

## 3. 覆盖率

按证据计划 `coverage.applicability=not_applicable`：Go/Node 被测栈，当前 STDD 覆盖率采集仅支持 pytest-cov。**不声明代码覆盖率保证**（ci check-failures (j) 通过）。`quality` 未在 project.yaml 配置：test 以证据计划两个命令 CP 为本 change 范围命令；lint/typecheck 无配置义务，Go race 编译已对 governance 包做类型检查。governance 全量与 backend 回归由真实 CI 权威验证（TC-MEC-003，本轮延期未验证），不在本地冒称。

## 4. 切片验证

| 切片 | TC | 状态 | 证据 |
|---|---|---|---|
| 1 | TC-MEC-002 | done | CLI tc_coverage=1/1、new_tests=3、verified_at=2026-11-16T02:06:45.731334；run 0ccb7130 复证 PASS |
| 2 | TC-MEC-001 | done | CLI tc_coverage=1/1、new_tests=1、verified_at=2026-11-16T02:55:41.207176；run 0ccb7130 复证 PASS |
| 3 | TC-MEC-004 | done | CLI tc_coverage=1/1、new_tests=0、verified_at=2026-11-16T11:01:56.826748；required manual 经用户原话确认后登记（纯诊断/台账切片，new_tests=0 以已验收 TC 覆盖为据） |
| 4 | TC-MEC-003 | **延期，未登记 done** | MEC-12 提交/push 完成（f8a23564a）；真实 CI 账单阻塞，TC-MEC-003 本轮 not_applicable（接受风险），权威验证未完成。**沿用前驱惯例不登记 done**：前驱 backend-tests-green 含 not_applicable 真实 CI 的 slice 7 同样未登记（仅 1–6 done），本 change 切片4 类比处理，收口经 Gate 3 而非把未验证切片标 done |

未发生第三轮修复；无「第三轮 strong/未升档」记录。切片3 于人工确认后登记；切片4 因权威 TC 延期不标 done，符合「不冒称未验证项通过」。

## 5. Part C 各步结果

- **C1 三路独立技术评审**（按 `stdd config models` 派发，configured/requested/actual 分记，actual=unknown）：代码→strong（守卫正确、withRunLock 未改、pgtype.UUID 可比较、ErrNoRows 处理、无过度设计；2 NIT）；测试→balanced（复跑离线 101/0/0、四事件对账、Acquire 增量、B 锁对照、两处夹具修正合法、manual 不绑 CP；test-report 陈旧 MINOR）；文档→economy（CUSTOM/测量/CRLF/稳定编号/历史全部成立；pending-adjustments BLOCK-MEC-01 陈旧 MAJOR）。三路均 NON-BLOCKING。**发现已处置**：pending-adjustments.md 为 BLOCK-MEC-01/02 与 NOTE-MEC-02 追加带日期指针（保留原文）；test-report 于本 C7 刷新。延期修订后受审文档已重审 Gate 1+2，评审结论针对的实现字节未变（守卫/selection/pin/wiring 同 f8a23564a）。
- **C2 全量质量**：run 0ccb7130 两命令 CP 重跑通过；ci check-failures **9 通过/0 错误**（TC-MEC-004 确认后）；覆盖率 not_applicable；lint/typecheck 无配置义务。
- **C3 Diff 审查**：13 文件逐一审查（+430/-24），无调试残留、无死代码、无注释掉的旧逻辑，变更与 spec 一致；`git diff --check` 通过；仅本 change 文件，按名 stage（非 `git add -A`）。延期修订只改记录根受审文档，未改业务代码字节。
- **C4 失败模式检查**：见第 6 节，a–n 全量执行。
- **C5 经验库**：C4 未发现新 agent 失败模式；既有 `runtime_deviation`（MaxConns=4 小池死锁）经验在身份矩阵设计中以「独占池＋独立控制连接」**预防**，未被命中触发，无失败命中计数可增。CI 账单阻塞属外部基础设施约束（台账 #113），不在经验库失败模式分类内，未为展示造条目。
- **C6 设计调整**：`design-adjustments.md` 已更新——**本轮发生经用户裁定的受审承诺变化（TC-MEC-003 延期 not_applicable），已按 revision-rules 同步受审文档并重审 Gate 1+2**；其余未决项为第四数口径与仓外 rules 副本。
- **C7 测试报告**：本文件。

## 6. 失败模式检查（C4，a–n 全量；run 0ccb7130）

CLI 确定性子集（9/9 执行，9 通过/0 错误）：(a) 必需文件存在 ✓；(d) TC-ID 唯一(4) ✓；(f) THEN 含 SHALL ✓；(g) AND 数量正常 ✓；(j) 覆盖率义务已声明 not_applicable ✓；(k) 契约一致(3 capabilities) ✓；(l) Anchoring L3>=L1 ✓；切片完成证据 ✓（3 切片）；TC 执行覆盖 ✓ 4/4（**TC-MEC-003 not_applicable 机械计入，延期未验证，非 CI 通过**）。

人工/语义项：
- (b) scope_creep ✓：13 业务文件均在声明范围（3 守卫＋1 测试＋selection 元数据＋精确四项＋pin/rules/wiring＋CUSTOM），两处夹具修正属测试文件；延期修订只动记录根受审文档（经用户裁定＋Gate 重审），无范围外业务改动。
- (c) cascading_errors ✓：三入口守卫相互独立；selection 元数据为加法式（不放宽既有拒绝）；CI 接线加法；账单阻塞为外部，非本 change 连锁。
- (e) tool_misuse ✓：agent verify/confirm/ci check-failures 用正确 change/run-id（同 run）；git 按名 stage；gh 只读观测 CI；CP action 在 cgo/race＋tools env 下正确执行；Gate 重审用 --reapprove 非手改状态。
- (h) content_quality ✓：守卫/测试/selection/wiring/CUSTOM 完整可用；唯一未完整为 TC-MEC-003（账单阻塞延期，如实标未验证/接受风险，非内容缺陷）。
- (i) instruction_decay ✓：长程中保持 Gate/人工不代签、无 `git add -A`、无手改 `.stdd.yaml`（切片/Gate/confirm 用 CLI）、CUSTOM CRLF/稳定编号/历史、代码英文注释、不伪造 CI 绿灯、not_applicable 显式标延期。
- (m) agent_cp_failure ✓（命令 CP）：CP-MEC-001 断言 pass=4/0/0＋测试内部 Acquire 增量/B 锁对照/任务计数；CP-MEC-002 断言 fail0/skipped0＋两新测试名＋矩阵具体 reconciliation/decision/秘密不回显，均含可区分对错观测值，非仅 PASS 标签。TC-MEC-003（manual→not_applicable）**未证明**，如实标延期未验证，不冒充；TC-MEC-004 由用户原话确认，非命令输出替代。
- (n) cross_system_mismatch ✓：本地 CP-MEC-001 PASS（范围 selection）与真实 CI 阻塞不矛盾（CI 证全量回归，阻塞≠失败）；CUSTOM 测量与 git 树 f8a23564a 逐位一致（629/1722/789、5816 文件、+4 归因经 commit diff 核实）；pin 7a0a2ab 与已发布 origin/main 一致。

## 7. 已知问题与未完成项

- **TC-MEC-003 真实 CI 延期（外部账单阻塞，接受风险，权威验证未完成）**：run 43752944966 所有 job runner_id=0、零步骤、六测试 skipped。本轮经用户裁定记 not_applicable（接受风险），**不是 CI 通过**。影响：SC-MEC-006 未验证，governance 全量/backend 回归无权威证据。补完：用户解除 Actions 额度（私有库 2000 min/月，台账 #113）后对最终 SHA 重跑 CI，核对六测试（TestM26B2TestFactsPayload、TestM26B2TestFactsPreserveFailures、TestM26B4CollectorKeepsBothReviewStages、TestM26B4ScanEmitsIndependentTestEvent、TestM26B4ScanTestOnlyAndReviewOnly、TestProposedSnapshotReadShapes 输出「checking the snapshot read shapes against the real rules.json」）、backend Test/对账/admin、两个生成 --check，再交用户确认以满足 SC-MEC-006 全部 SHALL。AI 无权改支付/额度。
- **第四数 `packages/` 口径未决**：按用户指示不测量、不沿用 314；待用户取口径。
- **仓外部署 rules 副本未覆盖**：不在本次范围。
- **全量 `make test`/`pnpm lint`/`pnpm typecheck`/e2e 未跑**：共享服务启动与依赖安装不在授权内；由真实 CI 承担（本轮延期）。
- **CUSTOM 写作时快照时效性（用户裁定 A：DELIVER 回填）**：变更追溯第203行与明细 #343/#344 状态列仍写「BUILD 在途…未提交、未推送、未部署」「TC-MEC-004 人工未确认」，系落码前快照，已被实际 commit/push f8a23564a 与本轮延期修订超越；不冒称 CI 通过（仍写 TC-MEC-003 未验证，属实）。按既有惯例（前驱第202行「claim 定性与报告已回填」）于 DELIVER 收口统一回填，不产生额外 commit、不改交付 SHA、计数中性（CUSTOM.md 在仓根，不在五类计数范围）。
- CUSTOM 既有 #338 竖线形状与既有索引合并行问题未顺手修（范围外）。
- tools BUILD 继续暂停；未部署。

## 8. 边界

未改 Qoder/Claude 权限、未代签 Gate/人工确认（Gate 1+2 重审与 TC-MEC-004 确认均用户原话）、未伪造 CI 回执、未连共享库（仅一次性 nonce 库并已释放）、未打印凭据、未改归档、未手改 `.stdd.yaml`（切片/Gate/confirm 用 CLI；仅本 change long_range 字段曾获精准 Edit 例外）。**受审 Phase2 文档本轮经用户裁定延期修订并按 revision-rules 重审 Gate 1+2**（非静默改动）。提交/push 经用户独立授权且仅限本 change 13 文件。账单/额度属用户侧外部状态，未尝试修改。
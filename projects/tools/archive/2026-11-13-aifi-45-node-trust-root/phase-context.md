# Phase Context — 2026-11-13-aifi-45-node-trust-root

<!-- 阶段交接摘要，冲突时以各 phase 正式产出物为准。 -->

---

## Phase 1: UNDERSTAND (completed 2026-11-13T22:51:42；因 proposal 修订于 23:32:41 重签)

### 关键决策
- 成对 change：为 multica `2026-11-13-aifi-45-real-execution-closure` 的 S4–S6 解阻。授权节点内的 `crctl advance` 读不到 daemon 信任库里的 execution-grant（只认 `--trust-root`，无环境变量、无默认信任根）；本 change 只补一个定位通道，不动 grant/签名/binding/receipt/verdict 合同。
- Q1–Q4 经用户「确认」按建议：环境变量；异值拒绝、同值通过；统一生效（SPEC 限定为实际消费者）；变量名 `CRCTL_EXECUTION_TRUST_ROOT`。

### 被否决的方向
- 改所有 SKILL.md 命令行传 `--trust-root`；把 daemon grant 复制到 agent 可写的 `{root}/.crctl/grants`（削弱 G1）；只对 advance 生效；变量与 flag 冲突时静默择一。

---

## Phase 2: SPEC (completed 2026-11-13T23:32:42)

### 关键技术决策（用户 Gate 1+2 确认：「确认 Gate 1 与 Gate 2…」）
- 唯一合并点 `resolveTrustRoot(cmd, flags, env)`，`parseArgs` 之后调用一次；只改 `crctl.mjs`，`lib/` 不动。
- 生效 8 命令：advance、authorization-bind、authorization-scope、sensitive-action、repair-admit、repair-resume、register、archive；其余命令（kb/workspace/business/writeback-apply/git/repair-assess/repair-outcome 等）完全无影响。
- 同值（原字符串逐字相等）通过，异值在读取工作区前 `EXECUTION_TRUST_ROOT_INVALID`；非法值只在被实际选作信任根时拒绝，不回退 `.crctl`；legacy/不消费分支与同值 flag 一样忽略。
- register/archive 在变量已设时与同值 flag 一样进入 control admission，缺输入失败关闭，不设 env 专用旁路（用户接受 Q3 代价）。
- 威胁口径：不新增 agent 能力、不提供隔离；本地准入成功不等于平台授权；测试只断言变量/flag 通道等价。
- 修订 proposal：删除「伪造 grant/公钥不能准入」（与现有代码和 fixture 不符，且新增信任锚超出边界），改为通道等价 + 非授权证明；因此 Gate 1 经 `--reapprove` 重签。
- 版本错位由 multica 成对 change 承担（无条件注入 + 平台回执收尾核验，发布顺序先 tools 后 daemon），crctl 不加能力探测。

### 模型分层
- design：strong planner `GB-JP/kimi-k3.1-pro:max`（actual=unknown）；事实调查：balanced `GB-JP/deepseek-flash:max`（actual=unknown）；其余为主会话。

### 产出物
- design.md、canonical/specs/code|agent/crctl-execution-trust-root.yaml（SC-NTR-001～008）、test-plan.md（9 TC，全 command）；`stdd validate`、`agent verify --dry-run` 通过；CP-NTR-009 基线 186/186。

### 边界与待办
- 未改 tools 代码；工作树既有未提交改动（merge-effects.mjs 及测试、golden、AGENTS.md、CUSTOM.md、.crctl/）不读不依赖不提交。Gate 不授权提交、推送、部署。
- Phase 3 执行模式待用户选择。
- 完成后须按 revision-rules 补 multica 的 design/spec/test-plan（daemon 注入 `CRCTL_EXECUTION_TRUST_ROOT`）并重审其 Gate 2；multica S4–S6 暂停至 tools 交付。

## Phase 3 BUILD（2026-11-14，长程 full_auto，未含提交/推送）

- 切片 S1–S3 全部完成；选定 run `e9c97c8d-4eb1-43e5-a748-12a9eb93c8ca`，9/9 CP 通过；回归 186/186。
- 改动文件（本变更仅 4 个）：`crctl.mjs`（+22）、`test/tac-control-fixture.mjs`、`test/gate-registry.json`、新增 `test/node-trust-root.test.mjs`（42 测试）。均**未提交**。
- C1 三路评审：code(strong) 通过；test_config(balanced) 1 中 7 低，已加固 6 项、驳回 1 项；docs_skills(economy) 3 中 9 低，均为文字/状态勘误。
- 受审文档**未修改**：5 项文字或测试深度偏差记入 `design-adjustments.md`（ADJ-1 `business` 不是子命令；ADJ-2 sensitive-action 离线形态；ADJ-3..5 夹具描述/行号/状态字样）。是否勘误并重审 Gate 由用户在 Gate 3 决定。
- 套件门禁：98 文件除 `execution-control-isolation`（Windows 缺受限身份；HEAD 同样失败）外全 ok。
- 经验库新增 EXP-2026-0001（夹具恒传参数导致生产调用形态未覆盖）。
- 工作树他人未提交改动（AGENTS.md、CUSTOM.md、merge-effects 两文件、golden workspace-inspect.json、`.crctl/`）全程未读未改。
- 下一步：Gate 3 等用户确认；之后回 multica 成对 change（设计/规格/测试方案同步 + daemon 注入）。

## Phase 3 BUILD 续：S4、S5（2026-11-14 23:06 起，长程 full_auto，未含提交/推送）

- 2026-11-14T23:06:22 用户重签 Gate 1/2（原话「确认 tools Gate 1 与 Gate 2。能委派给balanced子代理的委派给他」），AI 解读为同时接受三点收窄：daemon 不发布规则变量；PATH 剥离作用于 crctl 全部子进程（含 `runTestPlan` 声明命令）；win32 子用例 skip。Gate 3 此后一直 stale，**由用户在取证完成后确认**。
- S4（inspect 补字段，TC-NTR-010/011）与 S5（PATH 剥离 shim 目录，TC-NTR-012）完成；`tasks.md` 4.1–4.5、5.1–5.5 已勾，4.6/5.6 合并收尾。
- 本变更触及文件：`crctl.mjs`（对 HEAD 纯插入 45 行：S1 22 + S4 15 + S5 8）、`lib/git-shim-path.mjs`（新）、`test/node-trust-root.test.mjs`（新）、`test/workspace-inspect-authority.test.mjs`（新）、`test/crctl-git-shim-path.test.mjs`（新）、`test/crctl-summary.test.mjs`（+5 行，C1 补默认面断言）、`test/gate-registry.json`、`test/tac-control-fixture.mjs`（S1，夹具选项）。`code-structure-delta.md` 还会列出 `lib/merge-effects.mjs`、`test/merge-effects.test.mjs`，那是他人未提交改动，未读未改。
- 选定新 run：`c8385d47-d636-43b7-b12f-8db5d8615a16`，12/12 CP 通过（`ci check-failures`：TC 当前执行覆盖 12/12、5 个切片均有验证证据）。
- 套件门禁：100 文件、2237 用例，verdict=`block`，唯一失败 `execution-control-isolation`（HEAD 同样失败）；比上轮多 2 文件 2 用例，对应新增两个测试文件。**不得声称套件门禁通过。**
- C1 三路评审处置见 `design-adjustments.md#ADJ-9`；win32 容器取证与变异检查见 ADJ-8。
- 下一步：用户确认 Gate 3（前置 Gate 须 current）；其后回 multica：13.1 `crctl-stage.mjs` 覆盖清单加 `lib/git-shim-path.mjs`、13.2 替身 pi 改回生产形态、重跑 A0（须先征得用户同意）。tools DELIVER、归档、提交、推送均未授权。

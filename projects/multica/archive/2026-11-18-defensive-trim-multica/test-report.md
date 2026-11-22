# Multica 防御性精简 — BUILD 测试报告

**变更**：`2026-11-18-defensive-trim-multica`。**拟选同次取证**：[`d6390f73-b7f7-4750-8369-b60d37526b95`](validation/runs/d6390f73-b7f7-4750-8369-b60d37526b95/agent-verification-report.md)，[TC 证据及 36 项输入](validation/runs/d6390f73-b7f7-4750-8369-b60d37526b95/tc-evidence.json)。6/6 TC 通过；合并 DQB 和测试观察修复后的项目检查及前端文件级例外见下文。

## 最新同次执行与失败模式检查

用户确认 PA-002 后，以 `d6390f73-b7f7-4750-8369-b60d37526b95` 执行 `stdd agent verify authorized-runner` 和同 run 的 `stdd ci check-failures`：**6/6 CP 通过，自动化失败模式 9/9 通过**，无警告、跳过或错误；36 个冻结输入包含工作区并发测试。5/5 切片有验证证据，计划与实际均为 6 个 TC。Go/Node 按证据计划声明 `not_applicable`，无行覆盖率保证。

五项 Go selection 分别为 **32、20、8、45、10 pass**，均 0 fail/skip，数据库及自建实例均报告 `remaining=0`；Node CP 对账 **50 pass、0 fail**。固定 Tools 为干净检出 `71d05871a3f937f29a7f68fbf5b022741ab242e8`。原始 Go 捕获见 [`validation/selection-capture-d6390f73-b7f7-4750-8369-b60d37526b95/`](validation/selection-capture-d6390f73-b7f7-4750-8369-b60d37526b95/)；原 `validation/selection-capture/` 的历史文件已逐文件恢复并比对。日志在 `D:/multica-defensive-trim-dqb-quality/stdd-run-d6390f73-b7f7-4750-8369-b60d37526b95/`。取证前后工作树补丁均与成功的 `backend-final.patch` 一致，故复用下述独立项目质量结果，不把它们误称为同次 CP。

以下 C4 对账均对应 run `d6390f73-b7f7-4750-8369-b60d37526b95`；CLI 结果来自同 run 自动化检查，其余为人工核查：

| 项 | 检查与结果 |
|---|---|
| (a) 事实/产物 | CLI 找到必需文档与 spec；6 个 CP、36 项输入和本报告引用同一 run。 |
| (b) 范围 | C3 已对照批准设计与业务 diff；新增工作区锁观察修复经用户授权，台账 #395 登记，无生产锁或依赖修改。 |
| (c) 级联 | 签发/历史/敏感动作及进展回执由各自 CP 验证；工作区观察修复保留持续错误的失败出口和双向锁序。 |
| (d) 上下文 | CLI 核实 6 个 TC-ID 唯一；CP、原始捕获和失败模式检查引用同一 run。 |
| (e) 工具 | 使用固定 Tools、自建一次性数据库及独立实例；5 个 Go selection 均确认 `remaining=0`，历史捕获已恢复。 |
| (f) 规格 | CLI 核实 THEN 含 SHALL；现有 CP 验证实际签发、历史、动作、进展和取材出口。 |
| (g) 流程 | CLI 核实 AND 数量、5 个切片及 6/6 TC 执行证据。 |
| (h) 内容 | 报告区分同次取证、独立项目质量结果、前端例外和历史失败；不将例外内失败说成全绿。 |
| (i) 约束衰减 | 不接入已有数据库、不运行真实 agent、不将 Gate 2 确认当作 Gate 3 确认；固定依赖与失败出口不变。 |
| (j) 覆盖 | CLI 核实 6/6 TC；Go/Node 覆盖率为 `not_applicable`，无行覆盖保证。输入遗漏采用既有经验 `EXP-2026-0012` 的冻结清单修订与重取证方式。 |
| (k) 契约 | CLI 检查 3 个 capability 的一致性；相关 CP 使用各自生产入口和既有协议。 |
| (l) 锚定 | CLI 判定 non-critical，无强制新增锚定义务。 |
| (m) CP 失效 | 五项 Go 捕获按 selection 预期对账且 0 fail/skip；Node CP 对账退出码及 50 pass/0 fail，不以单独 PASS 字符串代替结果。 |
| (n) 跨系统 | 项目质量与同次 CP 单列；受控 PostgreSQL 错位及原失败日志的证据边界保留，登记 `EXP-2026-0015`，不推断生产锁缺陷。 |

## 合并 DQB 后的历史定向复验

在 `cc236811691d7f6385d2f67a667c89ea9e8748a3` 加本 change 工作树修改的候选上，运行 [`97eba2d2-6876-4957-970c-a3dbbf8c517c`](validation/runs/97eba2d2-6876-4957-970c-a3dbbf8c517c/agent-verification-report.md)：`stdd agent verify authorized-runner` 6/6 通过，`stdd ci check-failures` 自动化子集 9/9 通过；[TC 证据及冻结输入](validation/runs/97eba2d2-6876-4957-970c-a3dbbf8c517c/tc-evidence.json)。五项 Go selection 的原始结果见 [`validation/selection-capture-97eba2d2-6876-4957-970c-a3dbbf8c517c/`](validation/selection-capture-97eba2d2-6876-4957-970c-a3dbbf8c517c/)，均无失败或跳过、临时数据库剩余数均为 0。Tools 使用干净固定检出 `71d05871a3f937f29a7f68fbf5b022741ab242e8`；Node 50 pass、0 fail、1 个既有 Windows skip。此运行尚未选定为 Gate 3 证据。

合并候选的 Linux 项目质量检查：`make ENV_FILE=/dev/null test-ci` **未通过**（exit 2）。regular Go 测试事件 24,574 pass / 2 fail / 20 skip（失败含父测试）；唯一失败叶为未修改的 `internal/handler/TestWorkspaceDeletionWaitsForInFlightWriter/command`，检查到阻塞时 `pg_stat_activity.query` 为 `SET LOCAL lock_timeout = 60000`，与测试期望的工作区锁语句不符。此前 Linux 全量变更版出现过同一断言；基线及变更版各五次定向复验均通过，未定位波动根因，见下文「Linux CI 后端全量对照」。当次本 change 尚未修改该测试或关联实现，不能仅凭这一条日志断定原因或归责于本 change。原命令在 regular 阶段停止；事后以原始 regular JSON 单独执行 `ci-evidence`，因 handler 包失败而 exit 1。随后在同一候选和独立一次性环境补跑余下阶段：管理员 3 pass / 0 fail / 0 skip、管理员证据和 ownership check 均 exit 0；agent race 3,117 pass / 0 fail / 2 skip、exit 0（跳过 helper 进程和 root 专用分支）。这些补跑不能替代失败的完整 `make test-ci`。两轮 Podman 新建库和角色清理后均剩余 `0|0`，容器与网络已清理；日志与 Go JSON 位于 `D:/multica-defensive-trim-dqb-quality/` 及其 `backend-independent/`。

Linux 前端补验使用现有缓存及 `pnpm install --frozen-lockfile --offline`，安装命令 exit 0，但缓存缺少 Linux 原生可选包；`pnpm lint` 因 `unrs-resolver` 缺原生绑定退出 2，质量入口随即退出 1，typecheck 和前端 test 未运行。浏览器准备阶段 API 启动成功，Next 构建因缺 `lightningcss` Linux 原生模块失败，Chromium 测试未运行。安装脚本在 pnpm offline 模式下仍尝试直接下载两个 esbuild 二进制，Turbo 也报告尝试安装本平台二进制；因此不能将本轮描述为完全离线。新建 E2E 库和角色清理后剩余 `0|0`，容器与网络已清理。日志在 `D:/multica-defensive-trim-dqb-quality/frontend/`。

用户随后授权联网按现有锁文件补齐 Linux 原生依赖；同一候选在新隔离环境中安装成功，未改依赖声明或锁文件。`frontend-quality.mjs` exit 0：lint **7/7**、typecheck **10/10**；底层 `pnpm test` **6/7** 任务成功，Views 为 **674/677 文件、8,632/8,639 测试通过**，7 个失败均位于 `inbox-snooze-menu.test.tsx`、`issue-detail.test.tsx`、`project-date-pickers.test.tsx` 三个既有文件级例外内，无未处理错误或异常关闭。该例外不排除例外文件内的新回归，底层 `pnpm test` 不是全绿。生产构建及配置指定的 `e2e/issue-task-history.spec.ts` Chromium 测试 **1/1 通过**。本轮独立 E2E 库和角色回收后剩余 `0|0`，容器与网络已清理；原始日志在 `D:/multica-defensive-trim-dqb-quality/frontend-online/`。前端补验不改变当次完整后端检查失败的结论。

## 并发观察修复后的项目检查

用户授权将该测试修复纳入本 change。受控 PostgreSQL 交错在真实 `wsdWaitBlocked` 上复现同样的 `SET LOCAL` 误报；修复共享观察边界后，同一回归通过，持续不匹配仍在期限内失败并报告所见语句。原有两种锁顺序的 reservation / command 四个子例均通过；不改生产锁。受控实验建立了可导致同症状的机制，但原失败日志不足以证明当次具体时序。测试代码登记为 fork 台账 #395。

最终候选 `make ENV_FILE=/dev/null test-ci` **exit 0**：regular 测试事件 **24,577 pass / 0 fail / 20 skip**，证据对账通过；管理员 **3 pass / 0 fail / 0 skip**，管理员证据通过；agent race **3,117 pass / 0 fail / 2 skip**；ownership check 通过。回归及两种锁顺序均在完整 regular 中通过。一次性库和角色清理后剩余 `0|0`，容器和网络已清理。原始日志及 JSON 在 `D:/multica-defensive-trim-dqb-quality/backend-final/`；定向红、绿证据分别在 `lock-test-red/`、`lock-test-green/`。

最终候选 `pnpm test:scripts` exit 0：**813 pass / 0 fail / 2 skip**；两项因未传 Tools 路径跳过，随后以固定 Tools `71d05871a3f937f29a7f68fbf5b022741ab242e8` 单独补跑 **2/2 通过**。不是单次 815/815。日志分别在 `scripts-final/`、`scripts-skipped/`。上述路径均位于 `D:/multica-defensive-trim-dqb-quality/`。

复验候选与前述前端运行候选相比，仅新增 `workspace_delete_concurrent_test.go` 的测试修改及台账 #395；其余 29 个补丁文件一致，前端、依赖与业务生产代码不变。故复用上述前端和 Chromium 结果，文件级例外的限制仍适用。

**取证边界**：97eba2d2 的 35 项冻结输入不含新增修改的测试文件，其六项 CP 是历史有效证据，不能代表该文件已冻结。修订后的清单和最新 run 已包含此文件；台账依计划仍不作为执行输入，提交绑定仍待交付阶段核对。见 [PA-002](pending-adjustments.md)。

**新增修复的增量评审**：三路独立只读评审分别请求配置的 `OpenAIPersonal/gpt-6.2-sol:high`、`OpenAIPersonal/gpt-6.1-terra:xhigh`、`GB-JP/deepseek-flash:high`；会话未提供独立模型运行元数据，实际模型记为 unknown。代码评审无发现；文档评审指出历史段落的结果时态不清，已统一限定为当次结果。测试评审提出两点：现有 `wsdConn` 对带 `pool_*` 参数的连接串可能失败，属于旧测试夹具配置兼容性，非此次误报根因，按 `design.md` §「逐文件实施范围」B5/B8/B10 不扩修；`handler-wsd-race` 未包含新增观察回归，但该回归已在定向与完整 regular 中执行，按 `design.md` §「验证」复用实际入口后停止，不额外扩大该 selection。

## 历史运行 a9eb2552 的同次执行结果

| 切片 | TC / CP | 结果 | 主要观测 |
|---|---|---|---|
| S1 | RUN-201 | `run-default-contract-issue` 32 pass（29 叶），0 fail/skip | 原字节、签名、重放、资源和身份边界；新增入选的 3 个既有 HTTP 拒绝测试全部通过。 |
| S2 | CBE-101 | Node 50 pass、0 fail；Windows 既有 shell 用例不执行 | 真实 Tools 阶段拒绝坏 pin，固定对象不受 checkout 或本地替换引用影响；显式 HEAD 才走 overlay。 |
| S3 | RUN-202 | `run-authorization-head` 20 pass（19 叶），0 fail/skip | 历史批准可读；篡改原文、签名或撤销前驱/revision 拒绝。 |
| S4 | RUN-203 | `run-sensitive-action` 8 pass（7 叶），0 fail/skip | 实际两种持锁先后；先撤销则动作不查重且零结算，先动作则精确重放只结算一次。 |
| S5 | EWV-101 | `ewv-progress` 45 pass（40 叶），0 fail/skip | GET 首读交错、running/failed 下数组/标量/null、未知状态、两个已提交 POST 不丢成功回执。 |
| S5 | EWV-102 | `ewv-route` 10 pass（9 叶），0 fail/skip | 生产 GET 的真实成员和跨工作区权限、Runner 开关、两个真实任务令牌 POST 各到业务拒绝码。 |

- 5/5 切片已登记。计划与实际 TC 均为 6；覆盖率按当前证据计划为 `not_applicable`（Go/Node，不使用仅支持 pytest-cov 的测量能力），无行覆盖率保证。
- 五项 Go selection 对账通过且均报告 `remaining=0`，记录在 [`validation/selection-capture/`](validation/selection-capture/)。两条 Tools 变量使用同一个干净 pin 检出 `7a0a2ab57f3f5e2c583c3523bc69d67e7be115c1`。没有继承数据库地址，没有接入已有数据库或容器。35 个冻结业务输入均由 Git 跟踪，无 mixed EOL；尚未进行提交绑定。
- C1 已收回三个独立评审：代码的三项问题复现后修复；文档/测试的取证输入和测试矩阵按 [PA-001](design-adjustments.md) 处理。模型配置/请求见 `phase-context.md`，实际模型未独立核验。

## 失败模式（同一取证运行）

`stdd ci check-failures 2026-11-18-defensive-trim-multica --run a9eb2552-7233-419a-b476-b9daf95053a6`：**9 通过，0 警告/跳过/错误**。人工检查与 CLI 结论如下：

| 项 | 检查与结果 |
|---|---|
| (a) 事实/产物 | CLI 找到必需文档与规格；上述结果引用同 run 的证据，旧基线结果未冒充当前结果。 |
| (b) 范围 | C3 对照 `design.md`、业务 diff 和台账 #348–#353，改动属于已批准的签发、头、动作、进展、固定取材及直接测试；本轮补测未改生产逻辑。无上游路由调整、临时日志或新的依赖。 |
| (c) 级联 | 断言非法进展不掩盖已提交 POST 成功；拒绝动作不触及结算，固定 pin 失败不降级到工作树。 |
| (d) 上下文 | CLI 核实 6 个 TC-ID 唯一；报告和证据按同一 run ID 对照。 |
| (e) 工具 | 取证前检查 35 个冻结输入；一次 `agent verify` 后以同一 run 执行 `ci check-failures`；只用 runner 自建实例与固定 Tools。 |
| (f) 规格 | CLI 核实 THEN 含 SHALL；运行断言覆盖签发/重放、历史、并发、GET/POST、取材的实际出口。 |
| (g) 流程 | CLI 核实 AND 数量和 5 个切片均有验证证据。 |
| (h) 内容 | 对账每个 CP 的命令与结果；报告区分已执行、环境未执行和非同次基线。 |
| (i) 约束衰减 | 补测保留原失败出口与隔离限制，不改变签名协议，不启用额外容器、依赖或联网。 |
| (j) 覆盖 | CLI 确认 6/6 TC 执行，覆盖率声明为 not_applicable；实际 selector 已冻结。PA-001 的遗漏模式登记为 `EXP-2026-0012`。 |
| (k) 契约 | CLI 通过 3 个 capability 的一致性检查；生产入口与消费者使用同一头/进展真值。 |
| (l) 锚定 | CLI 判定 non-critical，无强制新增锚定义务。 |
| (m) CP 失效 | 6/6 CP 通过；Go 由 runner 对账实际父/叶和断言，CBE 断言进程退出码及 TAP 总计，背后用临时 Git 字节及拒绝出口断言，不仅匹配 PASS 字符串。 |
| (n) 跨系统 | STDD 6/6 与五项 runner 对账及 Node 检查一致；项目级结果单列，不以它们相互替代。 |

## 项目级对照（独立于同次取证）

用户授权「按上述五包方案执行；未覆盖项保留为缺口，等结果出来再决定 Gate 3。」在干净基线 `0c47c67e7e930ba7d28d4e6efd795e1e3741ecaa` 和当前 BUILD worktree 各执行一次：

```bash
node scripts/aifi45-disposable/run-selection.mjs \
  --selections scripts/aifi45-disposable/selections.baseline.json \
  --evidence-dir "<各自证据目录>"
```

| Go 包 | 基线 pass / fail / skip | 变更版 pass / fail / skip |
|---|---:|---:|
| `internal/governance` | 1416 / 79 / 1 | 1405 / 79 / 1 |
| `internal/governance/crosslang_test` | 19 / 0 / 0 | 19 / 0 / 0 |
| `cmd/server` | 920 / 13 / 0 | 928 / 13 / 0 |
| `internal/handler` | 6126 / 10 / 47 | 6126 / 10 / 47 |
| `internal/daemon` | 2499 / 45 / 94 | 2499 / 45 / 94 |

- **对照条件满足，不是全绿**：两次均 exit 1。十份 Go NDJSON 均有包终结事件，每个已启动测试均有终结事件；按包、测试路径和结果对账，147 个失败、142 个跳过事件两侧完全一致（含父测试）。通过数差异见本 change 的测试增删与迁移，不用通过数抵消红项。
- **隔离/证据**：同一 Windows Go `1.27.1`、Node `24.15.0` 和固定 Tools pin；两次只用 runner 自建实例，均 `remaining=0`，临时基线 worktree 已移除。未联网、安装依赖或使用现有服务。原始 JSON/NDJSON、runner 输出及退出码保留于本机 `%TEMP%/multica-five-packages.zYTaX0/`（`baseline/`、`changed/`），不属于同次 STDD run。
- **全脚本对照**：`pnpm test:scripts` 在同条件基线 `0c47c67e7` 复跑，和已保存的变更版均为 **739 pass / 16 fail / 1 skip、exit 1**；失败与跳过名称完全一致。原始日志：本机 `%TEMP%/multica-script-baseline.FrMur0/baseline.log` 与 `%TEMP%/multica-pa001-test-scripts.tap`。仍不是全脚本通过。

## 项目级隔离补验（独立于前两组证据）

用户授权按锁文件安装依赖并使用项目 CI 的一次性数据库流程。`D:\multica-trim-quality.o41bVk\checkout` 是核对过的 BUILD 补丁副本，安装凭 `pnpm install --frozen-lockfile`，不改锁文件。不读主仓 `.env`，不接现有数据库、Redis 或应用服务。原始日志、NDJSON、退出码保存在该目录的上一级 `D:\multica-trim-quality.o41bVk\`。

| 检查 | 实际结果 |
|---|---|
| 锁文件安装 / `pnpm typecheck` | **通过**，均 exit 0；类型检查 10/10 任务。Node `24.15.0`、pnpm `10.28.2`。 |
| `pnpm lint` | **未通过**，exit 1。6/7 任务通过；未改动的 `@multica/views#lint` 报 21 errors、21 warnings，包括违反限制的 `lucide-react` 导入。没有改业务或依赖来消除该红项。 |
| Go regular CI 命令 `--race --only regular`（含归属表排除） | **未通过**，exit 1。107 包均终结，77 pass / 16 fail / 14 skip（含无测试包）；测试事件 22,638 pass / 299 fail / 122 skip（含父测试）。`ci-evidence.mjs` exit 1，包含未声明跳过。 |
| Go CI 管理员库命令及 `--admin-stream` 对账 | **通过**，两命令均 exit 0，3/3 测试。 |
| Go agent CI 命令 `--race --only agent` | **未通过**，exit 1；测试事件 2,185 pass / 382 fail / 190 skip（含父测试）。 |
| `make test` / `scripts/check.sh` / E2E | **未执行原包装命令或浏览器测试**。`make test` 与 `check.sh` 的普通数据库启动路径未使用；已单列新版 CI 生命周期的 Go 结果。E2E 配置为 `critical_only`，`critical_paths` 为空，不能认定关键路径已覆盖。 |

- 后端沿用 CI 作业的 `ci-provision.mjs up/down`、迁移、Go 归属表和证据对账。PostgreSQL/Redis 使用本次新建、随机回环端口的 Podman 容器；`down` 确认删除专用库和角色，两容器清理后无本次标签残留。
- 与 Ubuntu CI 有环境差异：Windows 获取 Go `1.27.4` 遇 TLS 握手超时，实际为本机 Windows Go `1.27.1`。本轮宽测没有全仓基线；此前五包非 race 对照不用于归因这些失败。下节为随后只对红包做的基线复核。不是 GitHub Actions 作业通过的证据。

## Windows Go race 红项基线复核

在干净提交 `0c47c67e7` 上，仅复核上轮未通过的 16 个常规包和 `pkg/agent`，复用 Windows Go `1.27.1`、固定 Tools、race 参数及归属排除、CI 一次性数据库和本地 PG/Redis 镜像；agent 单独运行不接数据库。只过滤常规包列表，未重跑变更版或其余 91 个常规包，因此不是完整 CI A/B，运行负载也不同。原始证据：`D:\multica-trim-quality.o41bVk\race-baseline.SEwxqW\`；基线临时库和角色已删除，两容器和临时 worktree 已回收。

| 对照范围 | 基线 pass / fail / skip | 变更版 pass / fail / skip | 按包和测试路径对照 |
|---|---:|---:|---|
| 16 个常规失败包 | 16,451 / 287 / 117 | 16,436 / 299 / 117 | 16 个包两边均失败；281 个失败事件相同，基线独有 6、变更版独有 18，差异全在 `internal/daemon/repocache`；117 个跳过相同。 |
| `pkg/agent` | 2,185 / 382 / 190 | 2,185 / 382 / 190 | 通过、失败、跳过路径均相同。 |

- 事件数包含父测试。两组两边均 exit 1，所选包都有终结事件；两边 `internal/daemon/execenv` 的 `TestPrepareOpenclawConfigExpandsTilde` 同样 panic，另有 324 个已开始的测试路径没有终结事件，未计作通过或跳过。日志均未出现 `WARNING: DATA RACE`，不代表 race 套件通过。
- 本次未改 `repocache`；两边该包都出现 Windows Job Object 附加进程被拒绝。Windows 失败路径不完全一致，未归因于本补丁。随后以隔离 Podman、Debian 12、Linux Go `1.27.4` 运行 `go test -race -json ./internal/daemon/repocache`：干净基线和实际补丁两侧均 **149 pass / 0 fail / 0 skip、exit 0**，通过路径及开始/终结逐项一致。Windows 专用测试未在 Linux 编译；这不是整套 Ubuntu CI 通过。初次 Linux 变更版补丁应用失败后产生的错误取证已标为 `invalid-no-overlay`，未计入；有效变更版用逐文件实际字节覆盖后取得。

## Lint 红项基线复核

干净提交 `0c47c67e7` 的 Windows detached worktree 使用相同锁文件和缓存，`pnpm install --offline --frozen-lockfile` 通过；`pnpm lint` 与变更版均 exit 1，失败任务均为 `@multica/views#lint`。按相对路径、行列、严重性和诊断文本对账，**21 errors、21 warnings 完全相同**。当前补丁未改相关前端目录、依赖或配置；红项是已复现的基线问题，不计作 lint 通过。未扩大范围修复。Linux 和 lint 两组日志位于 `D:\multica-trim-quality.o41bVk\linux-quality.0oCecC\`，测试容器及 lint 基线 worktree 已清理。

## Linux CI 后端全量对照（未通过）

使用同一 Debian 12、Go `1.27.4`、Node `22.23.5` 隔离 Podman 环境，按项目 CI 的 regular race、管理员库、ownership/evidence 和 agent race 命令分别执行干净基线与实际补丁。两边使用新建的专用 PostgreSQL/Redis 和内部网络，`ci-provision` 回收成功，容器和网络均已清理；不是托管 GitHub Actions 运行。证据分别在 `D:\multica-trim-quality.o41bVk\linux-ci-baseline.14fSNs\` 和 `D:\multica-trim-quality.o41bVk\linux-ci.6qBBEV\`。

| 范围 | 基线 pass / fail / skip | 变更版 pass / fail / skip | 对账 |
|---|---:|---:|---|
| regular race | 24,248 / 278 / 35 | 24,241 / 282 / 35 | 两边 106 包均终结，83 包通过、11 包失败、12 包跳过；277 个失败事件相同，基线独有 1、变更版独有 5；35 个跳过路径一致。 |
| admin | 3 / 0 / 0 | 3 / 0 / 0 | 两边命令和 admin evidence 均 exit 0。 |
| agent race | 3,103 / 15 / 1 | 3,103 / 15 / 1 | 测试路径和结果完全相同，两边 exit 1。 |

regular 两边 `ci-evidence` 均 exit 1，含未声明跳过；ownership check 均 exit 0。两边所有已开始的包和测试都有终结事件，日志未出现 `WARNING: DATA RACE`。regular 差异中基线独有 `TestConversationRootOwnersReadOnlyRoutingData`；变更版独有 `TestChannelMergeEffects/code_order` 及其父事件、`TestWakeupTickFiresStatusHintBehindManyDueChecks`、`TestWorkspaceDeletionWaitsForInFlightWriter/command` 及其父事件。`code_order` 的未改测试用 `"0" + MergeInputDigest(input)[1:]` 构造错误摘要；生产代码在比较相等时才会继续返回 `OK`。本次报 `got "OK"`，说明该次原摘要首字符就是 `0`、测试没有实际改变摘要，因此这一事件不是实际摘要冲突的回归证据。其余差异：变更版的 wakeup 测试断言单轮后的 reviewer run 为 0、期望 1；workspace deletion 测试观察到阻塞语句为 `SET LOCAL lock_timeout = 60000`，两者在基线对应测试通过。基线独有失败是 conversation root 测试报告丢失最新非空 squad，变更版对应测试通过。当次候选未修改相关测试文件或 service/handler 目录；当时失败根因尚未确定，不宣称等价或零回归。当次 Linux/Windows 全量均未通过；后续候选的结果见上文。

### 两项变更版独有失败：定向复验均未复现

沿用相同 Linux 镜像及 Tools pin，对 `0c47c67e7` 和冻结的 BUILD 补丁分别使用新迁移的一次性数据库，以 `go test -race -json -count=5` 仅运行 `TestWakeupTickFiresStatusHintBehindManyDueChecks` 和 `TestWorkspaceDeletionWaitsForInFlightWriter/command`。两项在基线和变更版均各 **5 pass / 0 fail / 0 skip**，两侧 exit 0。当次定向环境未重现原断言失败，不认定波动根因，也不覆盖原全量运行的并发条件；当次候选未修改相关代码或测试。原始证据：`D:/multica-trim-quality.o41bVk/linux-ci-two-cases.OADOys/{baseline,build}/go.ndjson`；两侧数据库回收及容器、网络清理均 exit 0。当时全量测试和 lint 为红项；后续候选的结果见上文。

## E2E：运行历史冒烟（通过）

用户授权「跑运行历史冒烟，暂不跑评论路由」。对未改动的 `e2e/issue-task-history.spec.ts` 执行 Playwright 1.58.2 Chromium：**1 通过、0 失败、0 跳过，exit 0**。验证议题页只加载紧凑运行数据，展开后获取本议题完整历史，切换后获取子议题历史。此处是 issue `task-runs`，不覆盖执行授权、撤销或 pipeline 进展；这几个接口仍以原同次生产路由集成证据为准。

- 三次尝试均用新建的 Podman 后端和 CI 一次性 PostgreSQL、回环 Web、无真实代理或邮件服务；回收均通过。前两次是临时 runner 误用含大写字母、点号的目录名作为 `E2E_RUN_ID`，分别止于验证码查询和工作区创建，没有跑到页面断言。去掉覆盖值后，原用例用默认标识通过；未改生产代码或测试。原始报告及退出码保留于 `D:\multica-trim-quality.o41bVk\e2e-run-history.OUITtu\`，前两次分存 `attempt-1/`、`attempt-2/`。
- **未执行**评论路由、全套浏览器 E2E 或 `scripts/check.sh`；未改 `critical_paths`，不将冒烟计作原配置全量通过。

C1、C3–C7 和 C2 的同次取证已完成；C2 仍有已复现的基线 lint 红项、未通过的 Windows 全套 race 和原配置未覆盖项。Linux `repocache` 定向通过不替代全套 Go 结果。Gate 3 未发起确认；未改业务代码、质量配置，未提交、推送或部署。

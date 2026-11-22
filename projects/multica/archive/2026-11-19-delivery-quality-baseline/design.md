# 恢复 Multica 交付质量基线 — 技术设计

## Context

- 目标只限解除 `2026-11-18-defensive-trim-multica` 的项目质量阻塞；不修改该变更的补丁、证据或 Gate。起点为 Multica `0c47c67e7` 的干净检出；不得使用含无关改动的主工作树运行正式检查。
- [原变更测试报告](../2026-11-18-defensive-trim-multica/test-report.md) 已确认基线 `@multica/views` 21 个 lint errors：10 个 `lucide-react` 导入各触发两项规则，加 1 个图标按钮缺少可访问名称；Go 全量在本地隔离 Linux 环境未通过。两项定向复验均未复现原全量差异，不据此修改相关用例。现有 Linux 日志中 Claude root 拒绝、root 权限导致的 skip、`umask 077` 的文件模式差异均不能代表正常 CI。优先复核两类实质线索：固定 Tools 规则与 Git 用例契约不一致、若干 fixture 在一次性 `NOCREATEDB` 角色触发 `42501`；不按父/子失败事件逐条打补丁，也不预设这些都属于本变更可改的原因。
- 业务仓 `.github/workflows/ci.yml` 的 `backend-tests` / `backend-agent-tests` 已有全量拆分；`scripts/aifi45-disposable/ci-provision.mjs` 管理一次性库，`test-ownership.mjs` / `ci-evidence.mjs` 负责所有权和事件流对账。记录仓 `config.d/quality.yaml` 的 `make test` / `scripts/check.sh` 会走普通开发环境与 `.env`，后者还可沿用已监听的服务。两条旧命令保留为开发入口，不再作为本项目交付验收命令。

## Decisions

### D1. 正式后端质量入口复用 CI 命令，不启动普通开发栈

**方案**：将 `quality.test` 指向 `make ENV_FILE=/dev/null test-ci`。复用业务仓现有 `Makefile` 的 CI 配方，不新建 runner。hosted workflow 仅改 `backend-tests` 内本轮专用夹具的供给、凭据隔离、回收接线及 regular 包级并发；其余 job、分组、selector 和失败语义保持。配方仅消费由外层本次运行显式准备的主一次性库、夹具库连接（见 D2-B）、`AIFI45_DISPOSABLE_NONCE`、`AIFI45_CI_ADMIN_URL`（本次专用管理员库）、`RUNNER_TEMP`（本次产物目录）以及同一锁定 Tools 检出。缺必需的 job 输入不执行测试、不取 Make 默认数据库；已有 TestMain 和 CI helper 继续负责身份及 pin 校验，不在配方重做。

- 本地正式 `test-ci` 为三个 Go 组固定 `GOFLAGS=-count=1 -mod=readonly`，避免调用环境的选测参数把未执行计作通过；不解析任意 flags、不新增对账器。清除继承的 `PG*` 与 `POSTGRES_*`，只使用下述每组已指定的连接输入。普通 `make test` 和 hosted job 环境不变。
- regular：先独立求 `node scripts/aifi45-disposable/test-ownership.mjs skip-regex`（失败即停止），再执行 `bash scripts/test-go.sh --race --only regular --skip-regex "$skip_regex" --json-out "$RUNNER_TEMP/aifi45-go-test.json"`。本地 `test-ci` 在固定 `GOFLAGS` 后、hosted `backend-tests` 在其既有 job `GOFLAGS` 后追加 `-p=1`，使本次调用的包级测试进程串行；不改包内并发、selector、race、skip、失败传播或对账。追加的设置只作用于 regular 子进程，不传给 admin、agent；普通 `make test` 不变。串行会增加时间，不隔离包内并发或其他进程，也不解决前端失败；完整验证仍按原门槛进行。
- admin：复用 `backend-tests` 现有两个包、三个名称及 `go test -json -count=1 -timeout=10m`，仅该命令从 `AIFI45_CI_ADMIN_URL` 设置 `DATABASE_URL`；记录 `aifi45-admin-test.json`。
- 对账：直接调用 `ci-evidence.mjs --stream` / `--admin-stream`，沿用 `scripts/aifi45-disposable/test-ownership.json`；再执行 `test-ownership.mjs check`。allowed-skips 由 11 补全至 20（新增 9 条平台/helper 合法 skip，见 D2-D）；原来已归独立 owner 的迁移/隔离检查不并回常规库，既有测试义务与负责人不变。
- agent：清除继承的数据库 / nonce / Redis 测试环境（含管理员 DSN、浏览器 DSN、全部夹具 DSN 与一次性 handle），执行 `bash scripts/test-go.sh --race --only agent --json-out "$RUNNER_TEMP/aifi45-agent-test.json"`；保留既有 `-p 2 -parallel 2` 行为。不把其失败或未执行当成通过。入口只要有一步失败即非零；该次质量结果为红，由原步骤产物定位，后续独立诊断按需直接调用相应子命令，不能代替最终入口。

**为什么**：`quality.test` 需要单个可执行命令，薄配方让配置与 STDD 正式 CP 共用一个调用，不重跑同一套 Go 测试。锁定 selector、管理用例和对账沿用现有 CI；既有 hosted CI 除夹具接线边界外仍按原义务执行，不因本地配方通过而省掉该环境的义务。

**不选**：原 `make test` 使用共享开发环境；把 workflow 调用改成先推送会让 pre-Gate-3 验收依赖尚未授权的 Git 写入；另写脚本解释 workflow、重建 ownership 或封装测试结果都不需要。

### D2. 修复真实基线失败，不清扫历史红项

- 前端：十处非法导入改用 `@multica/ui/icons`，保留颜色、大小和交互。缺同名导出时优先等义现有图标：`SendHorizontal` → `Send`、`ArrowDownUp` → `ArrowUpDown`；`ShieldAlert` 所在警示状态用 `AlertTriangle`，已核实的通过/拒绝状态不改。不给 `lucide-react` 新增依赖、不修改 ESLint 规则、不创建图标。`project-chat-panel` 的 presenter 控件复用 `IconButton` 和现有 `chat.presenter.open_panel` 翻译，点击行为不变；扩展现有 `project-chat-panel.test.tsx` 的按角色/名称查询和点击断言，避免新测试文件。
- 后端取证沿用已经完成的一轮非 root Linux 干净基线（`0c47c67e7`、Go `1.27.4`、umask 022，同一固定 Tools、独立 PostgreSQL/Redis）；不重跑。已归因范围见下；未归因的业务断言、Pi/OMP 收尾超时及名单外 skip 只跑有区分力的定向诊断，环境缺件先补等价环境，找到需改业务行为、选择或不变量的原因须再走 revision。不改超时或允许名单把失败计作通过。
- 最终候选对照已捕获的干净基线；复用现有迁移、技能参数、Tools 和按钮断言，仅给新增接线或身份边界补有缺口的测试。

#### D2-A. 采用 Tools main `71d0587`（用户已裁定）

- 用户明确「接受 main 中 agent git show 对 5 种形状全开放」「pin 直接改指向 Tools 最新 main 的 71d0587，不再分叉」。新 pin 为 `71d05871a3f937f29a7f68fbf5b022741ab242e8`，取代 `7a0a2ab57f3f5e2c583c3523bc69d67e7be115c1`。不再从旧 pin 分叉小版本：main 已含编排器准备规则与 crctl 同子命令多条目合并。
- **已接受的安全差异**：main 将 `git show` 的 caller 从仅 `system-orchestrator` 改为 `*`（含 agent），仅限现有 5 种参数形状；全局禁用 flags、受保护路径不变，不授予 agent 编排器写入权限。main 同时继承祖先 `7345df8` 的 `crctl report` 失败行为变化；其后 `7ef9067`、`71d0587` 未改 Git 规则、crctl 规则加载或 git show 调用点。
- 换 pin 后在 `71d0587` 的独立干净 Tools 检出上定向复验：真实规则 orchestrator 准备与 agent allow/deny、execenv 准备、crctl 多条目合并与 report 回归；`AIFI45_TOOLS_ROOT`、`CRCTL_MJS`、`MULTICA_CONTROLLED_SHELL_RULES` 全部取自同一提交，固定 SHA 与输出留证。不重跑已知红的后端全量。最终同次验收核验实际 pin 与同 SHA 工具检出。Multica 侧不改生产代码与 agent show 测试期望（main 已放行）。

#### D2-B. 空库生命周期归外层，保留现有三项 admin 测试

- `IsolatedDB` 直接建库与一次性常规 `NOCREATEDB` 合同冲突。复用 `scripts/aifi45-disposable/ci-provision.mjs` 和底层一次性库创建、身份标记及回收逻辑；只扩现有入口的夹具供给，不新建 runner 或代理。固定选择四个 `TestLegacyReceiptBackfill*`、两个服务 `TestClaim*` 容量用例以及 `TestIsolatedDBCleanup/migrated_database`，各自一座独立的空库和角色，执行正常迁移。按具体测试绑定 DSN，不共享空库、不借用普通库。常规 Go 组无管理员 DSN；夹具角色无 `CREATEDB`、非超级用户，能访问自己的夹具，不能写其他夹具或共享常规库。保留原共享库读/不污染断言；密码只经本轮受保护的临时环境传递，日志和回收句柄不含密码。
- `server/internal/testutil/isolated_db.go` 的 CI 路径只消费本案预置库，不再以测试进程创建/删除数据库；在正式入口，缺失、不匹配或重复目标硬失败，不回退到共享库。保留现有显式开发测试路径，不让它成为 CI 兜底。把 CI 的物理回收义务转给外层；重试回收须有已确认身份与对象 marker，创建进程在收到成功回执时可按现有路径即时回滚其已确认创建的对象。保留迁移、进程 DSN 不变与销毁覆盖。不得改三项现有 `ci-admin` owner 或放松 tests 的独立空库语义。
- 本地 `test-ci` 与 `.github/workflows/ci.yml` 既有 `backend-tests` 共用夹具供给合同；hosted 只改对应现有步骤与 admin 环境作用域，不改组和 selector。夹具 DSN 只给 regular，不传入 admin、agent 或 E2E；agent 继续无数据库。现有 `ci-provision.test.mjs`、`test-go.test.sh`、`ci-scope.test.mjs` 分别覆盖生命周期、入口环境及 hosted 接线，不引入第二个验证器。
- 回收 fail-closed（PA-008；用户接受归属不明时保留并报错，不自动删除）：夹具文件是本轮唯一回收记录，继续包含测试名→DSN 映射（`fixtures`）和主库／夹具的无密码身份（`handles`）。每次创建前为该身份写入 `reserved`，成功创建并收到回执后写入 `confirmed`；预留本身及相同 marker 都不是所有权证明。首份记录以独占方式创建，完整写入后才发出任何建库或建角色命令；若首写中断，可能留下无效文件，但本轮尚未创建资源。之后的更新在同目录以私有权限写完整临时文件并原子替换，失败保留上次完整记录。记录及临时文件中的 `fixtures` 含 DSN 密码，均须保护；日志和句柄不含密码。
- `up` 失败时继续对本进程已确认创建的对象尝试即时回滚；如果记录更新或回滚失败，保留尚未解决的记录，不因内存中的已创建列表为空而报告清理完成。`downAll --fixtures` 只读取该文件；文件缺失、无效或必需身份缺失时失败，不消费环境句柄。对 `confirmed` 身份复用共同删除入口，先分别检查仍存在的库／角色 marker，全部匹配后才能删除任一对象；对 `reserved` 身份直接保留记录并报错，不自动删除，即使 marker 相同或暂未查到对象也不例外：一次查空不能证明服务端不会稍后完成中断的创建请求。已确认资源可以先清理，记录仅在全部身份确认无残留后移除。未传 `--fixtures` 的既有 E2E 回收路径不变。
- 有限边界：现有 CI 为单任务顺序使用单份记录，不支持并发 up/down；受管入口每次选新随机 nonce，旧记录可能仍被使用时不支持人为复用 nonce（同一 nonce 重建的对象与旧 marker 无法区分）。防人和 agent 误操作，不防恶意篡改账本／对象，也不承诺机器断电后的磁盘持久性。无法确认归属的对象可能残留，完整验收仍要求本轮自建资源已回收。夹具映射消费者（`isolated_db.go`）只读 `fixtures`，现有同服务器／≠共享／无重库／必须绑定检查不变，不加库名前缀检查。MAKEFLAGS 不加清洗或新回归（Windows 与 Linux GNU Make 4.3 实验证实命令行覆盖经 unset 后子进程与 sub-make 均不可见，现有 `test-go.test.sh` 已覆盖误删 unset）。

#### D2-C. 已归因的窄修复

- `server/cmd/migrate/migrate_workspace_seam_test.go`：八组文件的 up/down 引用从 613–620 更新到 `689–696`，所有预检、隔离、幂等及回滚断言原样保留；不改 SQL 或 legacy change。
- `server/pkg/agent/pi.go#buildPiArgsFor`：删掉重复的路径追加，保留带 `label == "pi"` 条件的单一显式入口；Pi 同一路径不因双挂钩重复，空格、顺序和绑定不变，OMP 维持原有发现。用已有参数测试验证，若 OMP 无精确反例只补一个；不改 Pi/OMP 的取消、终止、等待兜底或信任逻辑。
- `server/pkg/agent/pi.go` 自然退出管道（用户已批准纳入本 change）：仅在已观察到主进程自然退出（`cleanup.exited`）时，给 stderr 设与 stdout 相同的现有 250ms 读取期限，消除子进程继承 stderr 写端导致 finalize 无限等待的活性 bug。不改取消/终止路径、`WaitDelay`、测试超时或信任逻辑；接受主进程退出 250ms 后迟到子进程 stderr 不再进本次报告（父进程自身 stderr 已在窗口内排空，`ResumeRejected` 不受影响）。用现有 `TestPiCleanupDetachedTool`、`TestPiCleanupSuccessfulBackgroundServiceSurvives`、`TestPiExecuteReportsRefusedResume` 分别守住活动工具回收、成功后台服务留存、stderr 拒绝诊断三条保证，不新增机制。
- claim 测试令牌 owner（用户已批准纳入本 change）：仅给 `execution_start_claim_test.go` 的 `request` 与 `execution_task_claim_project_test.go` 的 `mintToken` 中本应合法的 `mdt_` 令牌补对应 runtime owner，使其到达真正的 stale-generation 判定。不改生产授权、对外状态码或 runtime 绑定门；刻意外部/空身份令牌仍为无 owner；跨 workspace 夹具不扩权。仅按之前单独裁定将对应 start/terminal 外部及空身份负例的预期对齐到现行绑定掩蔽 404，保留 `ownership_change` 并发负例的 409，以及原有拒绝与零写入断言。

- `server/internal/daemon/pi_skill_identity_test.go`：实际 helper 响应仍作原 JSON/交付检查；内存 `ExecOptions` 直接读取 `PiSkillDeliveries`，保留逐条身份、路径、主文件 SHA-256 和空准备清除旧值的断言。不序列化带运行时回调的整对象，不改生产代码。

- daemon/execenv 既有测试对齐（任务 2.19；仅四个测试文件）：`server/internal/daemon/health_test.go` 与 `repo_checkout_url_test.go` 的合法仓库检出夹具按真实 claim 路径补齐 `activeTaskAuth`；`skills_for_env_test.go` 的既有期望补齐技能 `ID` 和 `Source`；`execenv/runtime_config_test.go` 的既有期望保留技能段末尾的 `skillsRoutingRule`。不改生产鉴权、技能处理、测试选择或验收标准；沿用 `TC-DQB-002` 全量后端入口。

#### D2-D. 平台 skip 补全与前端上游已知红声明（用户采纳专家建议）

- **后端 allowed-skips 11→20**：完整环境（迁移＋Redis＋Tools＋Git2.45＋串行）下 regular 全量 0 功能失败，ci-evidence 仅报 9 条名单外 skip。逐条核实均为合法平台/helper 约束（非功能失败、候选未碰）：cmd/multica autostart×3 与 TestDisableKeepsRunningServiceRecoverable（systemctl not available）、TestDaemonStopUnconfirmedExitHelper/TestDaemonStopWithTaskProcess（subprocess helper）、TestProbeAgentCLIsDiscoversZCodeAppBundle（macOS layout）、TestCommentReplySnippetPropagatesPostFailure/windows/pwsh（pwsh 缺）、TestLoadHelperProcess（helper process）。按现有 11 条同一模式登记进 `test-ownership.json` allowed-skips，附源码行号与触发条件；`ci evidence OK … 20 declared skip(s)`（计数为表条目数）。不装 systemd/pwsh 强凑（过度工程，macOS 装不出）；名单外 skip 仍红，声明不掩盖功能失败。
- **前端上游已知红（文件级声明）**：本轮修改前的 fork 基线（含历史二开）全负载 `pnpm test` 中 Views 6 个文件出现 16 个失败；日志同时包含超时、断言失败及一个 Vitest 未处理异常。纯上游 `ff41e7a77` 的独立全量运行也在这 6 个文件观察到超时及其他失败；其 Views 终结摘要未留全。候选全负载亦有失败，原 170/170 隔离 A/B 仅覆盖四个文件。上述对照说明部分失败先于本轮候选，但不能证明所有失败均为超时或排除候选间接影响。用户裁定不改上游测试或产品，并接受以下文件级例外：`inbox/components/inbox-snooze-menu.test.tsx`、`issues/components/issue-detail.test.tsx`、`issues/components/issues-header.property-filter.test.tsx`、`projects/components/project-date-pickers.test.tsx`、`modals/create-issue.test.tsx`、`search/search-command.test.tsx`。清单内新失败也可能被容忍，故不能声称这些文件无新回归；不放宽规则、不调超时，集外失败仍红。上游修复落地后回收清单。
- **前端检查器与证据**：`scripts/aifi45-disposable/frontend-quality.mjs` 继续依次执行 `pnpm lint`、`pnpm typecheck` 和 `pnpm test --concurrency=1 --continue=always`。仅让本次 test 的 Turbo 包级任务串行，以减少并行包竞争；`--continue=always` 确保某包失败后其他任务仍执行，命令仍如实返回失败。测试选择、断言、超时和 hosted workflow 均不变。完整收集测试输出，避免默认子进程缓冲截断；通过现有 Turbo 任务汇总核对成功数、失败任务与总数，只在全部任务有结果且唯一失败任务为 Views、失败均可归属声明文件时接受文件级例外。其他任务失败、进程异常、Vitest 未处理异常、输出截断或结果不完整不得因同时存在已知红而被放行。`frontend-quality.test.mjs` 覆盖命令参数及正常通过、清单内失败、集外失败、混合失败与异常退出；两文件均列入同次冻结输入，检查器测试纳入 CP-DQB-003 后再执行完整前端命令。串行对照只支持资源竞争假设，不保证每次运行均通过；仍复用现有测试入口，不新增 runner 或修改上游用例。

### D3. 前端质量与唯一必跑 E2E

- `quality.lint`、`quality.typecheck` 保留 `pnpm lint`、`pnpm typecheck`；把原 `scripts/check.sh` 的 `pnpm test` 与 Go wrapper 合同测试保留为必跑项。Go race 命令覆盖原 wrapper 的同批 Go 测试，不额外再跑一次非 race 组。
- `quality.e2e.scope` 仍为 `critical_only`；`critical_paths` 仅含 `e2e/issue-task-history.spec.ts`。`quality.e2e.command` 与 CP 的浏览器命令一致：`bash -ec 'DATABASE_URL="${MULTICA_E2E_DATABASE_URL:?}" pnpm exec playwright test --project=chromium --reporter=line e2e/issue-task-history.spec.ts'`。从该次明确配置的 `PLAYWRIGHT_BASE_URL` / API base 访问自建 web/backend，浏览器用专用的一次性库、与抢占 Go 测试 fixture 的库隔离。不复制 `.env`，不以端口已应答就接管现有服务。
- 选择已有运行历史用例，是因为它验证关键用户路径的真实 compact/own/subtree 响应，并已有有效的隔离部署经验；不把它当作执行授权、撤销或 pipeline 行为的完整浏览器覆盖。不纳入已明确延期的评论路由，不添加新的领域 E2E。
- `apps/desktop/scripts/package.mjs`：只去掉 Vite 转换后遗留在模块正文内的 shebang；脚本已由显式 `node` 调用，保留打包命令、参数、测试与依赖，不改构建流程。
- `e2e/issue-task-history.spec.ts`：保留 UUID 起始导航和原 compact 断言；用测试专用的 `e2e/issue-task-history-trigger.mjs` 等待当前 issue 的规范编号 URL 后再取得 Runs 按钮；CP-DQB-004 先用一个 Node 测试验证精确路径匹配和等待顺序，再执行原单条 Chromium 用例。其余网络、内容、对话框内控件与勾选断言不变。不加睡眠、重试或超时，也不改产品路由。

## Architecture

```text
干净 Linux 候选检出（非 root） + 同 pin 的 Tools 检出
  ├─ owned PostgreSQL/Redis → ci-provision up → Go 迁移 → test-ci/对账 → ci-provision down
  ├─ 锁文件依赖 → pnpm lint / typecheck / test
  └─ 独立的一次性库 + 自建 Go API / Next.js → 单条 Chromium 用例 → 仅关闭本次进程和资源
同次 STDD run 执行这组 CP → ci check-failures（同 run）→ 报告附各层真实结果与回收证据
```

最终取证在同一 Linux 业务候选运行 STDD 3.0.7，Go 使用 `-count=1 -mod=readonly`，前端不接受旧任务缓存；测试检出的 binding 必须解析到同一 `multica` 记录和同版本资源（可在隔离检出使用适用于 Linux 的记录路径，不迁移或修改主 binding）。只有稳定、可提交的候选输入进入冻结清单；外层一次性资源、事件流和 `.env` 不写入被测目录。回收成功是项目质量结果的一部分，不因测试通过省略。项目配置只改本变更所需字段，并在最终 run 冻结前稳定。既有 run 记录不改写；项目级配置更新可能使原 change 的旧证据不再 current，原 change 合入新基线时依其流程检查并补取证，不在本变更重签。

## Risks / Trade-offs

| 风险 | 范围与处理 |
|---|---|
| 本地 Podman root、系统服务差异制造假失败 | 用非 root 和真实 job 配置先复现；本地结果标为本地，不冒充 GitHub Actions。现有 hosted 合同若需真实 CI，仍须独立取得执行授权与可用额度。 |
| 新配方漏执行某组或把失败吞掉 | 在现有 `scripts/test-go.test.sh` 的 stub 夹具中断言各 suite 调用数、管理员凭据只赋给所属命令且 agent 不继承、缺输入时零执行，注入红项则非零。正式跑用现有两个对账器而非新解析器。 |
| shared 数据或报告反过来影响下轮输入 | 临时目录、显式环境、后端与浏览器各用一次性库；只清理由本次运行创建且已有 ownership/handle 的资源。 |
| 候选依赖漂移或错误复用原 change 证据 | 依照 `EXP-2026-0012` 冻结配方、CI/ownership 选择和实际被测输入；记录精确 Git 基点及候选变更、运行环境和本次 run。受审输入变更才重取证。`EXP-2026-0005` 用于保留既有一次性身份拒绝覆盖；不复制一套校验。 |

模式沿用 Gate 1 确认的 `standard`，设计由主会话完成；两项取证子任务按配置请求 balanced，未获实际模型元数据。未执行测试或触发托管 CI。

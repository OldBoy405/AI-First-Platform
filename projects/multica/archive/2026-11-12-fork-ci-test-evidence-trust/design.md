# fork CI 与测试证据可信性修复 - 技术设计

> change：`2026-11-12-fork-ci-test-evidence-trust`（项目 multica，thorough）
> 真源：`canonical/proposals/…yaml`（Gate 1 已确认，含 D1/D2 裁定）。本设计中的事实均来自 CI 日志、源码与本地命令核实；"未验证"项集中列在文末。
> **产出方式说明**：按 STDD 分层约定本应派发 strong 档 planner 子代理写本稿。已派发一次（`GB-JP/kimi-k3.1-pro:max`，读取约 160 次文件后因服务端 429 过载反复中断，未返回任何正文；续跑同样失败）。本稿由主会话（claude-sonnet-5-5，非 strong 映射）完成，实际档位记为 unknown，未升档。

## Context

**现状（2026-11-12）**：multica main = origin/main = `903a46c5a`；最近 CI run 43021822604 失败于 `backend-tests`（Test 步骤）与 `transitions-contract-check`。最近 45 个 run 中 `backend-tests` 没有成功过。

**根因分层（已核实）**

1. *环境缺口*：
   - `cmd/server`、`governance` 的 `TestMain` 调 `verifyDisposableTestDatabase`，要求库名 `aifi45_tmp_<nonce>`、角色 `aifi45_role_<nonce>`、库与角色两处 marker、非超级用户等；CI 的服务容器库 `multica` 不满足，两包整包退出（governance 因此一个测试都没跑）。
   - tools：`crosslang_test` 3 项与 crctl CLI 测试找不到 tools。`execution_authorization_test.go:614`、`execution_authorization_revoke_interop_test.go:100`、`execution_trust_install_test.go:56` 三处把 `CRCTL_MJS` 的默认值写死为开发机路径 `C:/Users/GOBAO/Downloads/AI/tools/...`。
   - **tools pin 问题**：`ci.yml` 的 pin `9e41ad74` 不含 `execution-control-protocol.mjs` 与 `control-vectors.json`；在 tools `f774ffb`（origin/main）下 `crosslang_test` 失败，在 tools `e52b808`（本地 HEAD，**尚未推送**，origin/main 之前 1 个提交）下通过。`generate-transitions.mjs --check`（54 条）与 `generate-gate-nodes.mjs --check` 在 e52b808 下通过，`generate-transitions` 在 9e41ad74 下也通过，所以单一 pin 推进到 e52b808 不会破坏 transitions 检查。
2. *专项测试的前置状态不是整包运行能给的*：
   - `TestChannelIsolation` 需要 Linux root + `AIFI45_ISOLATION_PROFILE`（uid/gid）。先例证据 `archive/2026-10-27-trusted-verdict-channel/validation/iso-20261027T101534Z.*` 是在 WSL2 的 `AIFI-ISO` 发行版里 `sudo` 跑的（`wsl -l -v` 现仍有该发行版，Stopped）。
   - `TestChannelMigrationAfterDown`/`AfterReapply` 断言"648 down 之后表不存在"，必须从 `648-down` 或 `648-down-up` 初始状态起跑（`run-selection.mjs` 的 `INITIAL_STATES`），在完整迁移后的库上整包运行必然失败。
   - 整包运行里还有若干 `t.Skip`（governance 6 个文件含 `t.Skip`；其中 `execution_binding_issue_test.go:856` 在 `AIFI45_TOOLS_ROOT` 未设置时 skip，而同类的 `execution_control_protocol_test.go:334`、`execution_tc_auth010_test.go:27` 是 Fatal——不一致，且 skip 会被 `go test` 报成通过）。
3. *真实缺陷*：
   - 19 张 `cr_execution_*` 表不在 `workspaceDeletionManifest`；全部无指向 workspace 的外键；7 张带 `workspace_id`，12 张无；16 张有禁 DELETE 的触发器（无触发器：`notice`、`dispatch_root`、`tool_cursor`）。
   - `run-selection.mjs` 读 `reconciliation.matched`/`.blocked`，`selection.mjs` 返回 `{status, reason}`，对账失败永不使 selection 失败。
   - `use-logout.test.ts` 的 `../../core/...` 相对导入使 `@multica/views` typecheck 出 60 条 TS6059。**该文件所在提交 `26f6c5b0a` 夹带了 31 个前端文件（登录页 session 清理等，+3656 行），这些前端测试从未在 CI 跑过**（路径过滤使前端 job 在最近的 push 都被跳过）。
4. *证据缺口*：CI 不跑 `scripts/aifi45-disposable` 的 42 个 node 单测，`.github/ci-paths.json` 里没有任何 scope 覆盖 `scripts/aifi45-disposable/**`（改 run-selection 不触发任何 CI job）；handler `TestMain` 在库不可达时 `exit 0`。
5. *凭据*：secret `AIFIRST_TOOLS_READ_TOKEN` 存在（updatedAt 2026-10-07），失败在检出 tools 的认证（GitHub 拒绝）；该 job 自 11-02 首次执行就没成功过。

**约束**：multica `AGENTS.md`、`CONTRIBUTING.AIFIRST.md`（自研逻辑放新文件，改上游文件仅挂钩点并标 `AIFIRST`，英文注释，`CUSTOM.md` 登记，不加兼容层）；一次性库只经 runner 自建实例；不读/打印/创建凭据；不放宽 nonce 门禁；提交/推送/部署/secret/推送 tools 各自单独授权；CI 验证需推送且耗私有库额度（改 `ci.yml` 会触发 backend+frontend 等全部 scope，推送次数要压到最少）。

**工具链**：本机 Windows + podman 6.1.4 + Go + Node v24；`~/go/bin/sqlc` 在；CI 用 ubuntu-latest + Node 22。

## Decisions

### 1. CI 在服务容器里开 nonce 库（C1）

**方案**：新增 `scripts/aifi45-disposable/ci-provision.mjs`，两个子命令：
- `up`：以 job 环境的服务容器管理员 URL 调用既有 `provision.mjs::createDisposableDatabase`，把 `DATABASE_URL`（nonce 角色 URL，先 `::add-mask::` 其口令）、`AIFI45_DISPOSABLE_NONCE`、`AIFI45_DISPOSABLE_HANDLE`（库名/角色/marker/nonce/去掉口令的管理员 URL 的 JSON）写入 `GITHUB_ENV`。
- `down`：读 handle，管理员口令取自 `ci.yml` job 级声明的 `AIFI45_CI_ADMIN_URL`（工作流配置，不是本 change 写出的文件），调 `dropDisposableDatabase`（marker 不符即拒绝）；handle 缺失（`up` 在写出前失败）时静默成功并说明"无资源可清理"。

`backend-tests` 中顺序：`up` → `go run ./cmd/migrate up`（现有步骤，随 `DATABASE_URL` 改为迁移 nonce 库）→ Test；`down` 放在 `if: always()` 的收尾步骤。全包共享一个 nonce 库（与现状"全包共享 multica 库"一致，handler 等不查 nonce 的包同用）。Node 依赖：`pg` 用 `npm install --prefix $RUNNER_TEMP/aifi45-node pg@<根 package.json 声明的版本>` 取得并经 `NODE_PATH` 解析，**不**为此跑全仓 `pnpm install`。

**为什么**：`createDisposableDatabase` 已经产出两份 `TestMain` 检查的全部身份（库名、角色、两处 marker、非超级用户、所有者），复用同一函数就不会出现"同名不同语义"的第二份规则；服务容器本身是 job 级一次性资源，不需要在 runner 上再起 podman。

**备选**：
- A：在 runner 上用 `run-selection.mjs`（podman 自建实例）跑全部 selection。排除：runner 上 podman 版本/拉镜像/`--timeout` 行为未验证；且 `run-selection` 明确拒绝外部 admin 连接是上一 change 的刻意设计，不放宽。
- B：bash + psql 复刻 provision 规则。排除：两份规则，漂移风险。
- C：在 CI 里把 `multica` 库改名/加 marker。排除：角色是超级用户，`TestMain` 会因 superuser 拒绝，只有走新建角色才合规。

### 2. 门禁不放宽，且每个拒绝分支都有测试（C1，EXP-0005）

**方案**：`cmd/server/integration_test.go` 与 `governance/crsync_test.go` 里各有一份 `verifyDisposableTestDatabase`，现有 `TestVerifyDisposableTestDatabaseRejectsMismatch` 只覆盖 nonce 非法与"库 marker 被改"。为两份各补表驱动测试，对 nonce 格式、库名、角色名、session_user≠current_user、非所有者、库 marker、角色 marker、superuser、createdb、createrole、bypassrls 逐条构造失败并断言被拒，且每条的"单独退化"都变红（不是只测组合）。**条件名由独立命名的子测试承载**（`t.Run("<condition>", …)`），不要求错误串含条件名——两份门禁现有实现只返回一句通用错误，改错误串就要改门禁函数体，超出"仅补测试、不改逻辑"。放进 `selections.identity.json`/`selections.json` 的 identity 组由 `run-selection` 在一次性库里真跑。

**为什么**：EXP-2026-0005 正是这个形态；CI 提供 nonce 库之后门禁才第一次在 CI 路径上承担作用，必须先证明它仍然挑剔。

**备选**：合并两份实现为共享包。排除：需要改上游包（`cmd/server`）结构，范围外；以"测试对齐"控制漂移。

### 3. tools：单一 pin、环境注入、去掉开发机路径（C2）

**方案**：
- 新增 `.github/aifirst-tools-pin`（单行 40 位 hex）。`transitions-contract-check` 与 `backend-tests` 的 tools 检出步骤都先读它再 `actions/checkout`（`ref:` 取自读出的值），`ci.yml` 里不再出现 tools 的字面 ref。
- `backend-tests` 检出 tools 到 `.aifirst-tools`，设 `AIFI45_TOOLS_ROOT=$GITHUB_WORKSPACE/.aifirst-tools` 与 `CRCTL_MJS=$AIFI45_TOOLS_ROOT/skills/shared/crctl/scripts/crctl.mjs`。检出后立刻有一步"pin 完整性检查"：必需文件（`execution-control-protocol.mjs`、`control-vectors.json`、`crctl.mjs`）存在，缺任一则失败并打印 pin 与缺失文件，而不是让后面十几个测试各自红。
- 三处 `CRCTL_MJS` 默认值删除；变量缺失时 `t.Fatalf("CRCTL_MJS is required …")`（保持"缺失即 Fatal"的既有语义）。`execution_binding_issue_test.go:856` 的 `t.Skip` 改 `t.Fatal`，与同类测试一致。
- 本地入口：本机开发者设 `AIFI45_TOOLS_ROOT`；`run-selection.mjs` 不改环境注入（它透传 `process.env`）。

**前置依赖（需用户裁定 U1）**：测试需要 tools e52b808，它未推送。pin 必须是 origin 上存在的提交。路径 α：你授权推送 tools（或自行推送）后 pin = e52b808。路径 β：推送前 CI 的 pin 完整性检查必然红，我们诚实地让它红并在报告里标"CI 的 tools 相关测试因 pin 前置未满足而未验证"，不 skip、不绿。推荐 α。

**为什么**：一个 pin 两个消费者，避免 transitions 与测试针对不同 tools 修订；完整性检查把"pin 错了"这一类原因收敛成一条清楚的失败。

**备选**：把 fixture 拷进 multica 仓。排除：与 tools 的契约会静默漂移，"共享向量"就失去共享意义。

### 4. 专项测试验收归属表与 CI 排除（C3，D1）

**方案**：`scripts/aifi45-disposable/test-ownership.json`（机器可读）列出**不在 CI 整包运行里**的测试：`{package, test, owner: "independent", entry, reason}`。初始已知项：
- `daemon.TestChannelIsolation` → entry：`wsl -d AIFI-ISO`，root + `AIFI45_ISOLATION_PROFILE`（D1）。
- `governance.TestChannelMigrationAfterDown`、`TestChannelMigrationAfterReapply` → entry：`run-selection.mjs --only channel-migration-down|channel-migration-reapply`（状态敏感；已有 selection）。
- BUILD 第 0 片的整包基线会枚举其余整包下失败/skip 的测试，**只有带证据的才可加入**，每项必填 reason。

`test-ownership.mjs` 提供 `check` 与 `skip-regex`：`check` 核对每个条目在源码里确有对应 `func TestX(`（拼错的排除项不会被悄悄接受），并输出名单与数量；`skip-regex` 生成 `^(A|B|…)$` 给 `go test -skip`。CI 排除在 `scripts/test-go.sh` 里用 `--skip-regex <re>` 传给 `go test -skip`（见决策 5 的脚本改动）。

**为什么**：排除必须显式、可见、有归属；`go test -skip` 不需要改上游/自研测试源码，也不引入 build tag 造成"漏编译"（`agentintegration` 先例是靠额外的 `go vet -tags` 兜底，这里不想再多一条）。

**备选**：build tag（需改每个测试文件、且 tagged 测试默认不编译，容易腐烂）；显式包清单（粒度太粗，会把整个 governance 排除）；对其 `t.Skip`（正是要消灭的"静默跳过"）。

**状态敏感探针的归属（需用户裁定 U2）**：推荐 owner=independent（本地 `run-selection` 真跑并留证据）。备选：CI 里新增 podman job 跑这两个 selection——runner 上 podman 能否按 `instance.mjs` 的参数工作未验证，且每次 push 增加分钟数。

### 5. CI 测试证据对账（C4）

**方案**：
- `scripts/test-go.sh` 增加两个可选参数（上游文件，挂钩点，标 `AIFIRST`）：`--skip-regex RE` → `go test -skip RE`；`--json-out FILE` → `go test -json`，输出同时落盘并保持原退出码（`pipefail`），`scripts/test-go.test.sh` 补对应用例（参数形态、退出码透传、缺参数拒绝）。
- 新增 `scripts/aifi45-disposable/ci-evidence.mjs`（+ 单测）读取 `-json` 事件流，规则（任一违反则非 0 退出并打印原因）：
  1. 必需包（`cmd/server`、`internal/governance`、`internal/governance/crosslang_test`、`internal/handler`、`internal/daemon`，清单随 `test-ownership.json` 同目录的 `required-packages` 字段声明）各自 ≥1 个通过的测试且包级结论为 pass——覆盖"整包 0 测试"和 handler `TestMain` 静默 `exit 0`；
  2. 事件流里所有 `skip` 必须在允许名单（含 reason）内，名单外的 skip 即失败；
  3. 归属表里的排除测试不得出现在事件流里（证明排除生效、没有"以为排除了其实在跑"）；
  4. 流必须完整（以包级 pass/fail 结尾，无半截 JSON；EXP-0003：逐行解析，不取首行），解析失败硬失败。
- 与 `selection.mjs::verifyGoTestSelection` 的关系：**独立**。后者按完整 expected 清单逐测试对账，用于 selection；前者按包级下限和 skip 名单做 CI 对账。不复用的理由：expected 清单在 CI 整包规模下不可维护，强行复用会把两种语义混进同一函数。两者共享的只有"流必须以换行结束、逐行 JSON 解析、失败硬失败"这一输入纪律，各自测试。

**为什么**：把"没跑"变成可失败的事实，而不修改上游测试文件（handler 的静默 exit 0 不改，由包级下限兜住）。

**备选**：改 handler `TestMain` 为失败退出（上游文件改动，增加同步冲突面）；用 `-v` 文本解析（脆弱）。

### 6. run-selection 对账修复（C5/C6）

**方案**：新增 `scripts/aifi45-disposable/selection-decision.mjs` 导出纯函数 `decideSelection({ selection, test, totals, reconciliation })` → `{ ok, reasons[], reconciliationLine }`，`run-selection.mjs` 只调用它并打印：
- `expected` **未配置**（属性不存在/`undefined`）：沿用旧判定 `test.code===0 && totals.fail===0 && totals.skip===0 && totals.pass>0`，输出行逐字不变；
- `expected` 已配置：必须是非空数组，否则失败（reason `EXPECTED_INVALID`）；调 `verifyGoTestSelection`，`status!=='matched'` 即失败并输出 `blocked=<reason>`；
- 修正读取字段为 `status`/`reason`，删掉不存在的 `.matched`/`.blocked`。

**为什么**：缺陷是契约错配，不是逻辑复杂；抽出决策函数后才能用真实 `go test -json` 夹带的流单测，而不必起 podman。

**备选**：让 `selection.mjs` 返回 `matched/blocked` 以迁就调用方。排除：`selection.mjs` 有 223 行单测并有"不返回不可信事件输出"的契约，改返回形状要动它的全部断言，错配另一端更小。

**CI 保护**：`.github/ci-paths.json` 的 `scripts` 与 `backend` scope 加入 `scripts/aifi45-disposable/**`；`script-checks` job 增加 `node --test scripts/aifi45-disposable/*.test.mjs`（先取 `pg`，同决策 1 的 `npm install --prefix`）。`scripts/ci-scope.test.mjs` 补"改 run-selection 会触发 scripts 与 backend"用例。**变异验证**：本地把决策函数的 blocked 判断恢复成旧写法，对应单测必红，记入证据。

### 7. workspace 删除：显式"保留"分类与删除路径（C7，D2）

**方案**：清单（`workspace_delete_manifest_test.go`，上游文件，只追加、标记、`CUSTOM.md` #87 条目补登）新增 `workspaceDeleteRetain`（语义：随 workspace 删除后行**保留**，且这是被断言的保证）。逐表映射（依据来自迁移 643–648 头注释与 Gate 1 裁定 D2）：

| 表 | workspace_id | DELETE 触发器 | 分类 | 依据 |
|---|---|---|---|---|
| `cr_execution_notice` | 有 | 无 | **delete** | 可操作通知，运营态；D2 |
| `cr_execution_dispatch_root` | 有 | 无 | **delete** | 派发根运行态；D2 |
| `cr_execution_binding_issue` | 有 | 有（`no_mutation`；TRUNCATE 守卫由 649 补，见 R4） | **retain** | binding 证据；648 头注释"binding … retained" |
| `cr_execution_consumption` | 有 | 有（TRUNCATE 守卫由 649 补，见 R4） | **retain** | 消费证据（审计记录） |
| `cr_execution_activation` | 有 | 有（含 no_truncate） | **retain** | 激活历史（审计记录） |
| `cr_execution_contract_selection` | 有 | 有 | **retain** | selection；648 头注释 |
| `cr_execution_code_source_freeze` | 有 | 有（`no_delete`） | **retain** | 批准源冻结（审计记录） |
| `cr_execution_control_reservation` | 无 | 有 | **retain** | 经 `selection_id` 归属 workspace |
| `cr_execution_tool_verdict` | 无 | 有 | **retain** | 审计记录 |
| `cr_execution_control_settlement` | 无 | 有 | **retain** | settlement；648 头注释 |
| `cr_execution_task_binding` | 无 | 有 | **retain** | binding；648 头注释 |
| `cr_execution_control_fact` | 无 | 有 | **retain** | facts；648 头注释 |
| `cr_execution_control_command` | 无 | 有（`no_delete`+转移 guard） | **retain**（见下，需 U3） | D2 写"收敛"，见下 |
| `cr_execution_tool_cursor` | 无 | **无** | **keep** | D2"收敛"；无 workspace_id，沿用 KEEP 规则 |
| `cr_execution_deployment_head` / `deployment_snapshot` / `policy_readiness` / `policy_activation_head` / `policy_activation_event` | 无 | 有 | **keep** | D2：全局表，非 workspace 所有 |

新分类的断言（清单测试内，查 `pg_trigger`/`pg_constraint`）：Retain 表必须（a）至少一个禁 DELETE 的触发器，（b）没有指向 `workspace` 的外键。既有规则不变：KEEP 不得带 `workspace_id`，DETACH/SETTLE 必须带。5 张"带 `workspace_id` 的 retain 表"因此不再违反 KEEP 规则。

**删除实现**：notice 与 dispatch_root 没有外键，不会级联。新增 `governance.DeleteWorkspaceExecutionRows(ctx, tx, workspaceID)`（自研包，两条 `DELETE … WHERE workspace_id = $1`，走现有 `tx`），在 `DeleteWorkspace` 的 `deleteSteps` 里**追加一步**（`workspace.go`，上游文件，挂钩点，标 `AIFIRST`）。不新增 sqlc 查询、不改任何既有触发器；迁移只新增 649 为 `binding_issue`/`consumption` 补 TRUNCATE 语句级守卫（见修订记录 R4）。

**command/cursor 与 D2 的出入（需用户裁定 U3，置信度低）**：D2 写"command、cursor 收敛"。`cr_execution_control_command` 的状态机只有 `created/issued/result_ready/settled_effect/settled_no_effect/uncertain`，`settled_*` 要求 `verdict_id`（需要可信 verdict，删除 workspace 时无法伪造），`uncertain` 的语义需读转移 guard 才能确认能否用于"workspace 已删"；cursor 没有触发器但也没有 workspace_id。任何"收敛"都意味着新增或改动转移 guard，性质与 D2 保留的"若需对触发器开例外须上报"同类。本设计因此：**本 change 不实现收敛转移**，command 登记为 retain（禁 DELETE 已由现有触发器保证）、cursor 登记为 keep，并加一条测试验证"为已删 workspace 的 selection 创建新 reservation/command 被拒"（D2 的"禁新建"半句）；该测试若发现当前代码**允许**，则作为发现上报用户，由你裁定是否在本 change 内修，不静默改。收敛转移作为后继议题登记。**R5 更新**：探针实测两条创建路径都放行；按用户裁定只修 reservation 半句（`CreateReservationTx` 加 workspace 存在性检查），command 半句保持红灯断言原样并登记为 `owner=known-finding` 的已声明排除，指向后继议题。

**行为测试**（handler 包，真实 `DeleteWorkspace`，一次性库）：建两个 workspace A、B，各写入 19 张表中每类至少一行；删 A 后断言——delete 类 A 行消失、B 行仍在；retain 类 A 行逐字节不变（含 digest 列）；对 retain 表的普通 `DELETE` **与 `TRUNCATE`** 仍被触发器拒绝（TRUNCATE 半句以 canonical SC-WSD-003 为准，两张原缺语句级守卫的表由迁移 649 补齐，见 R4）；keep 表不动；删除事务失败时 A 的任何行不被半删。**不是只改清单**：缺行为测试或缺删除步骤时红。

**为什么**：把"事实上保留"变成"被断言的保留"，只对确有运营语义的两张表加删除；对审计触发器只做加强（649 补 TRUNCATE 拒绝），不为任何表开删除例外。

**备选**：全部删除（需给 16 张表的触发器开例外，削弱防篡改，D2 明确未授权）；给 notice/dispatch_root 加 FK `ON DELETE CASCADE`（新迁移，存量行风险，与"无 FK/cascade"约定相悖）；全部标 KEEP 并去掉 KEEP 的 workspace_id 规则（改变上游规则的语义，影响所有表）。

### 8. 一次性库使用边界与 handler 入口（C7，SC1）

**方案**：
- 复现与验证只经 `run-selection.mjs`（自建 podman 实例，`DATABASE_URL` 只指向它创建的库）。`selections.json` 新增 `handler-workspace-deletion`（`./internal/handler`，`^(TestWorkspaceDeletionManifestCoversPublicSchema|TestWorkspaceDeletionRetention.*)$`）。`run-selection` 的 `totals.pass>0 && skip===0` 判定同时覆盖 handler `TestMain` 静默 `exit 0`（无事件→pass=0→FAIL）与清单测试的 `t.Skip("database not available")`。
- 操作前后记录 `podman ps -a` 与库清单，旧容器 `multica-postgres`/`multica-backend` 状态不变。
- 本地跑 handler 测试**不经** runner 直接 `go test` 属禁止路径（默认连 `localhost:5432`）。

### 9. transitions 凭据诊断（C8）

**方案**：新增 `scripts/aifi45-disposable/tools-access.mjs`（可注入 `fetch` 的小函数 + 单测），在 tools 检出前一步调用 GitHub API `GET /repos/OldBoy405/AI-First-tools/commits/<pin>`，用 token 但**永不打印**它，映射：空 → `credential missing`；401 → `credential rejected (invalid, expired or revoked)`；403/404（用 `X-Accepted-GitHub-Permissions` 等公开头判断不到时按 404 处理）→ `no access to repository or pin not found`；200 → ok；其它/网络错误 → `inconclusive` 并失败。该步骤替换现有"Require the tools read credential"的单一判断。凭据由管理员按"仅 `OldBoy405/AI-First-tools`、Contents: Read-only"重新签发并更新 secret；我不读取、不创建。

**备选**：只改文案。排除：文案无法区分"被拒绝"与"pin 不存在"。

### 10. 前端：恢复 views typecheck（C9）

**方案**：`use-logout.test.ts` 的 4 条 `../../core/...` 导入改为包导入：`import type { ApiClient } from "@multica/core/api"`、`import type { User } from "@multica/core/types"`（类型导入，不受 mock 影响）；运行时的 `createAuthStore` 因同一文件 `vi.mock("@multica/core/auth")` 会遮蔽它，改 `await vi.importActual<typeof import("@multica/core/auth")>("@multica/core/auth")`；`SESSION_BARRIER_KEY` 没有公开导出，倾向在 `packages/core/package.json` 增加一条 `"./platform/storage"` exports（上游文件，一行，标记），若 lint/knip 不接受则退为 `vi.importActual` 取值或内联常量并说明。`vi.mock("../../core/…")` 字符串路径 tsc 不解析，保持不动。`login-page-session.test.tsx:19` 同理不动。
验证：`@multica/views` typecheck 0 条 TS6059；`use-logout.test.ts` 通过；views/core 的 vitest 全量本地跑一遍并记录结果。**范围边界（U4）**：因 `26f6c5b0a` 夹带的 31 个前端文件从未在 CI 跑过，修好 TS6059 后前端 job 才会第一次真正执行它们；若暴露这些夹带功能自身的失败，属于范围扩大，先报告再决定。

### 11. governance 超时（TestMTick003）

不在设计里假装已解决。BUILD 第 1 片在 runner 自建实例里完整跑 governance（`-timeout` 放宽并记录每个测试耗时），判定树：环境因素（如缺 tools/DB 状态）→ 修；真实缺陷 → 修或上报；仅慢 → 作为显式决定（拆包/超时）写进设计调整。定位前，CI 的 governance 步骤沿用默认 10 分钟超时，超时即失败（诚实红）。

### 12. 验收报告（C10）

`validation/acceptance-report.md`：每项实际执行的 CI run（run id、commit、各 job 结论）与本地命令（命令、退出码、pass/fail/skip）；独立入口（WSL 隔离、两个状态 selection）的真实执行记录；未覆盖项与原因（含 U1 路径 β、推送未授权时的"CI 工作流未经真实 CI 验证"）。skip>0 的包逐个说明。

## Architecture

```
CI backend-tests（修复后）
  checkout multica ─┬─ checkout tools@pin(.github/aifirst-tools-pin) ── pin 完整性检查 ──┐
                    │   （先 tools-access 诊断：缺失/被拒绝/无权限/pin 不存在）            │
  services.postgres ─┴─ ci-provision up ─→ DATABASE_URL + NONCE(GITHUB_ENV, 口令已 mask) │
                         └→ cmd/migrate up（迁到 nonce 库）                               │
  AIFI45_TOOLS_ROOT/CRCTL_MJS ◀───────────────────────────────────────────────────────┘
  test-go.sh --race --only regular --skip-regex <test-ownership.json> --json-out events.ndjson
      └→ go test -json -skip …（排除名单 = 归属表，名单与数量打印）
  ci-evidence.mjs events.ndjson  ←(always) 必需包 pass>0 / skip 名单 / 排除项未运行 / 流完整
  ci-provision down              ←(always)
  test-ownership check           独立步骤：归属表 ↔ 源码 func Test*

独立入口（不在 CI）：
  TestChannelIsolation      → wsl -d AIFI-ISO（root + AIFI45_ISOLATION_PROFILE）→ 证据入报告
  TestChannelMigration*     → run-selection --only channel-migration-down / -reapply（podman 自建实例）
  handler 清单/保留测试      → run-selection --only handler-workspace-deletion

run-selection 决策：go test -json ─┬→ summarizeEvents(totals)
                                  └→ verifyGoTestSelection(expected?) ─→ decideSelection ─→ PASS/FAIL 行 + 退出码
DeleteWorkspace tx: …既有 deleteSteps… ─→ [追加] governance.DeleteWorkspaceExecutionRows(notice, dispatch_root)
```

## Risks / Trade-offs

| 风险 | 缓解措施 |
|------|----------|
| tools e52b808 未推送，CI 的 tools 相关测试无 pin 可用（U1） | pin 完整性检查让失败清晰；路径 α 需用户授权推送 tools，路径 β 如实报"未验证"，不 skip、不绿 |
| governance 整包在 CI 可能重现 10 分钟超时，耗额度 | 第 1 片本地定位；CI 超时即失败；改 `ci.yml` 会触发全部 scope，推送次数压到最少并先在本地等价验证 |
| 整包基线暴露更多"整包下不成立"的专项测试 | 第 0 片枚举并逐个带证据地写入归属表；无证据不得排除；`test-ownership check` 与 `ci-evidence` 双向核对 |
| D2 与现有触发器/状态机的出入（command/cursor 收敛） | 本 change 不改既有触发器语义；retain 断言 + "禁新建"测试；发现缺口先上报（U3）。TRUNCATE 缺口经 R4 裁定补迁移 649，只加拒绝、不开删除例外。禁新建缺口经 R5 裁定只修 reservation 半句，command 半句登记为已知失败（声明式排除，非静默跳过），后继议题承载 |
| 上游文件改动面：`ci.yml`、`test-go.sh`、`workspace.go`、清单测试、`core/package.json`、views 两个测试 | 全部最少行 + `AIFIRST` 标记 + `CUSTOM.md` 登记；不新增 sqlc；迁移仅 649（R4，配套 down） |
| `26f6c5b0a` 夹带的前端改动首次进 CI 可能暴露其他失败 | 本地先跑 views/core 全量 vitest；超出 TS6059 的失败先报告（U4） |
| `go test -skip` 排除项拼错而悄悄排除 0 个 | `check` 核对源码存在；`ci-evidence` 核对排除项确未运行；故意制造不一致的测试必须失败 |
| CI 里 `pg` 装不上或版本漂移 | 版本取自根 `package.json`；`npm install` 失败即步骤失败；不回退到 skip |
| WSL `AIFI-ISO` 启动/profile 在本机已失效 | 启动前征得同意；失败则隔离测试如实列为未覆盖，不用同 uid 对照冒充 |
| 本机 handler 测试默认连 `localhost:5432` | 禁止直接 `go test ./internal/handler`；经 `run-selection` 的 handler selection；前后容器清单对账 |

## 用户裁定（Gate 2 一并确认）

用户原话：「U1至U4都采纳你的建议；U5：授权；确认 Gate 2」。据此：

- **U1 = α**：CI pin 指向 tools `e52b808`；该提交当前未推送，pin 必须是 origin 上存在的提交，因此推送 tools 是 pin 生效的前置动作。推送前按 AGENTS 规则逐项列出将推送的提交与范围再执行；未推送期间 CI 的 tools 相关测试如实"未验证"，不 skip、不报绿。
- **U2 = independent**：`TestChannelMigrationAfterDown`/`AfterReapply` 归独立入口（本地 `run-selection` 真跑并留证据），CI 不新增 podman job。
- **U3**：本 change 不实现 command/cursor 收敛转移；command 登记 retain、cursor 登记 keep，并加"禁新建"测试；该测试若发现当前代码放行，停下上报，不静默修复。收敛转移作为后继议题。**BUILD 中实测放行，用户追加裁定（R5）：「只修reservation半句，command做好记录，待以后可以找回并修订」。**
- **U4**：本 change 只保证 views typecheck 与本地 vitest 并如实报告，不负责修复 `26f6c5b0a` 夹带前端功能的自身失败；暴露时先报告再裁定。
- **U5 = 授权**，范围仅限本设计所列：创建 runner 自建的一次性 podman 实例（TTL ≤3600s，运行前后核对容器清单）、启动 WSL `AIFI-ISO`、`npm install` 拉取 `pg`、推送触发 CI、管理员更新 PAT。不含：连接 `localhost:5432` 与旧容器 `multica-postgres`、读取/创建凭据、修改仓库 secret、超出上述范围的推送或部署。

## 修订记录（BUILD 前，Gate 2 重签）

Gate 2 确认不等于设计中的每个事实都已验证。BUILD 恢复前核对发现两处**已锁定规格与代码事实冲突**，经用户裁定后修订如下。原批准与原指纹保留，重签以本次裁定原文为 evidence。

### R1：SC-CBE-001 的口令边界不可同时成立

- **原文**：`任何输出（日志、环境文件、handle 文件）SHALL NOT 含明文口令。`
- **核实依据**：`scripts/aifi45-disposable/provision.mjs:81-86` 把 `randomBytes(18)` 生成的角色口令写入 URL userinfo；`DATABASE_URL` 必须带它才能以 nonce 角色连接。GitHub Actions 的 `::add-mask::` 只遮蔽**日志**，`GITHUB_ENV` 是 runner 上的明文文件。原条款与"把 DATABASE_URL 写入环境文件"互相排斥。
- **用户裁定**：收敛规格到日志与 handle。
- **修订后**：`任何日志、stdout/stderr 与 handle 文件 SHALL NOT 含明文口令；GITHUB_ENV 中的 DATABASE_URL 承载 job 级一次性角色口令，写入前 SHALL 先对该口令发出 ::add-mask::，且该口令 SHALL NOT 被复用于任何非一次性资源。`
- **连带实现决定**：handle 若原样存 `adminUrl`，会把服务容器管理员口令（上游 `ci.yml` 既有固定 fixture `multica`）写进我们产出的文件。因此 handle 只存**去掉口令**的管理员 URL，`down` 从 `ci.yml` job 级新增的 `AIFI45_CI_ADMIN_URL` 取回完整 URL。这样本 change 写出的文件中，只有 `GITHUB_ENV` 的 `DATABASE_URL` 带口令，即裁定明确允许的那一处。
- **影响范围**：SC-CBE-001、TC-CBE-001、CP-CBE-001、决策 1。安全边界结论：一次性口令随机、job 级、随服务容器销毁，不用于任何持久资源；不放宽 nonce 门禁。

### R2：SC-CBE-002 要求"拒绝信息含该条件名"，现有门禁不产出条件名

- **原文**：`SHALL 每一条单独退化都被拒绝，且拒绝信息含该条件名`
- **核实依据**：`server/cmd/server/integration_test.go:129-131` 与 `server/internal/governance/crsync_test.go:116-118` 的 11 个条件合并为一个 `if`，只返回 `"database, role, marker, owner or privilege mismatch"`。满足原条款必须改门禁函数体，与决策 2 及回归矩阵的"仅补测试，不改逻辑"冲突。
- **用户裁定**：改规格，子测试名承载条件名。
- **修订后**：`SHALL 每一条单独退化都被拒绝，且该条件由独立命名的子测试逐条归因；合法的 nonce 库 SHALL 通过。`
- **影响范围**：SC-CBE-002、TC-CBE-002、CP-CBE-002、决策 2。门禁实现一行不改；每个条件仍是独立子测试、单独退化必须变红，可归因性不降低。

### R3：未验证事实 #4 已排除（无需修订规格）

`server/internal/handler/daemon.go:27`、`daemon_terminal_claim.go:11`、`trace.go:15` 已导入 `internal/governance`。新增 `DeleteWorkspaceExecutionRows` 的调用不引入新的包依赖方向。

### R4：两张 retain 表缺 TRUNCATE 守卫，SC-WSD-002「不新增迁移」与 SC-WSD-003 不可兼得（BUILD 中，ADJ-014）

- **原文**：SC-WSD-002 `SHALL 不新增迁移、不新增触发器例外、不改 sqlc 查询。`；SC-WSD-003 `对 retain 表的普通 DELETE 与 TRUNCATE SHALL 仍被触发器拒绝。`
- **核实依据**：Slice 9 在 runner 自建一次性库实测 `FAIL handler-wsd-retain pass=20 fail=3 skip=0`，`truncate_cr_execution_binding_issue` 与 `truncate_cr_execution_consumption` 两个子测试红：数据库**接受** TRUNCATE。迁移 `643_cr_execution_binding_issue.up.sql:36-38` 与 `644_cr_execution_consumption.up.sql:34-36` 各只有 `BEFORE UPDATE OR DELETE … FOR EACH ROW`；645/648 的其余 retain 表都另有 `BEFORE TRUNCATE … FOR EACH STATEMENT`。PostgreSQL 的 TRUNCATE 不触发行级触发器，故只有 row 守卫等于没有守卫；648 头注释第 11–12、406 行自己声明「every retained table needs this statement guard」。grep 全部迁移确认无后续迁移补过，648 是最后一个迁移，本切片 `git status --porcelain -- server/migrations/` 为空 → **既有缺陷，非本 change 引入**。安全影响：具备数据库写权限者可 TRUNCATE 清空 binding 签发证据与消费回执而不被拒绝。
- **用户裁定**：补迁移修缺口（修订 SC-WSD-002）。新增迁移 649，给这两张表加 `BEFORE TRUNCATE FOR EACH STATEMENT`，复用各自已有的 `append_only` 函数（纯加强，不开任何删除例外，不违反 D2 的实质 concern）。需按 STDD revision 修订 SC-WSD-002 的「不新增迁移」并重签 Gate 2。结果：SC-WSD-003 全绿，真实修掉一个审计证据可被清空的缺口。代价：本 change 首次触碰 schema，需配套 down 迁移。
- **修订后**：SC-WSD-002 的该条改为 `SHALL 除补 TRUNCATE 守卫的迁移 649 外不新增迁移、不新增触发器例外（不得为 append-only 触发器开任何删除例外）、不改 sqlc 查询；649 SHALL 只加语句级 TRUNCATE 拒绝、复用两张表各自已有的 append_only 函数，并 SHALL 配套 down 迁移。` SC-WSD-003 原文不动（TRUNCATE 半句保留），CP-WSD-003 不动。
- **影响范围**：SC-WSD-002、TC-WSD-002、决策 7（删除实现段与逐表映射的触发器列）、风险表两行；新增 `server/migrations/649_cr_execution_truncate_guard.{up,down}.sql` 与 `CUSTOM.md` 登记。D2 的实质 concern（不得削弱防篡改、不得开删除例外）不变：本次只加拒绝，不加放行。command/cursor 收敛转移仍不实现（U3、SC-WSD-005 不动）。

### R5：禁新建探针实测放行，U3 裁定只修 reservation 半句（BUILD 中，ADJ-017）

- **原文**：SC-WSD-005 `SHALL 被拒绝；若当前代码允许，该测试红灯即为发现，SHALL 停止并向用户上报，由用户裁定是否在本 change 内修复（design U3），不得静默放宽断言或改触发器。`；U3 `该测试若发现当前代码放行，停下上报，不静默修复`。
- **核实依据**：Slice 10 在 runner 自建一次性库实测 `FAIL handler-wsd-no-recreate pass=2 fail=3 skip=0`（exit 1）。两个正向对照（活着的 workspace B 上同样构造的 reservation 与 command）均 PASS 并在事务内核对 `count(*)=1`，故 A 的放行不能归因于请求构造或 lineage 的 open 槽冲突。根因：`execution_control_reservation.go:70` `CreateReservationTx` 全函数不查 `workspace` 表，唯一 workspace 相关语句是 `:89-91` 对**保留下来的 selection 行**做 `WHERE id=$1 AND workspace_id=$2 AND project_id=$3 AND cr_id=$4` 过滤（teardown 后依然命中）；`execution_control_store_state.go:148` `ApplyControlCommandTx` 全文件 `workspace` 零引用。修复代价已读码核实：reservation 路径**零生产调用方**，但 `execution_control_reservation_test.go:25` 用硬编码 `selectionWorkspace = "aaaaaaaa-0000-4000-8000-000000000001"`（无对应 workspace 行），加检查须同时修正该 fixture；command 路径唯一生产调用方 `execution_consumption_effect.go:155` 传的是 `ReservationID: in.ReceiptID`（**消费回执 id，不是 reservation 行 id**），故「reservation → selection → workspace」lookup 会打断生产消费流，另有 33 处测试调用用不透明随机 reservation/lineage id。
- **用户裁定**：「只修reservation半句，command做好记录，待以后可以找回并修订」。
- **修订后**：SC-WSD-005 的 then 改为 `reservation 半句 SHALL 被拒绝，本 change SHALL 在 CreateReservationTx 内加 workspace 存在性检查使其成立；command 半句经探针实测当前代码放行，按 U3 用户裁定不在本 change 内修复，SHALL 保持探针断言原样（红灯即为已声明的发现），SHALL 登记为可找回的已知失败并指向后继议题，不得静默放宽断言、不得改触发器、不得把红灯洗成绿灯。` and 追加两条：`两个半句 SHALL 各自独立成测试函数，使 reservation 半句可独立绿、command 半句可独立红。` 与 `command 半句的登记 SHALL 能被 test-ownership check 与归档后的基线规格找回。` CP-WSD-005 的 action 与两条断言不动（`--only handler-wsd-no-recreate` 改为只跑 reservation 半句的测试函数），description 同步。SC-TOR-001 的 and 追加一条：`归属表 SHALL 允许 owner=known-finding 的条目承载经用户裁定不在本 change 内修复的已知失败；该条目 SHALL 指名后继议题与复现命令，SHALL 与其他条目一样被 check 核对真实 func、被 skip-regex 排除、被 ci-evidence 核对排除生效，且 SHALL NOT 被计为覆盖。`
- **连带实现决定**：不新增机制。`test-ownership.json` 的 `entries` 现有 schema（package/test/owner/entry/reason，owner 为自由字符串）已能承载已知失败条目，`check`/`skip-regex`/ci-evidence Rule 3 原样覆盖，故 `test-ownership.mjs` 与 `ci-evidence.mjs` **一行不改**。command 探针因此被**声明式排除**出 CI 整包运行（不是静默跳过：check 打印其 reason 与计数，ci-evidence 核对它确实没出现在事件流），手动运行仍红。
- **影响范围**：SC-WSD-005、TC-WSD-005、CP-WSD-005（description）、SC-TOR-001（and）、决策 7 的 U3 段、风险表 D2 行、U3 裁定行、未验证事实 #3；`server/internal/governance/execution_control_reservation.go` 加 workspace 存在性检查、`execution_control_reservation_test.go` fixture 修正、探针拆成两个测试函数、`selections.json` 的 `handler-wsd-no-recreate` 指向 reservation 半句、`test-ownership.json` 新增一条 known-finding、`CUSTOM.md` 登记。command/cursor 收敛转移仍不实现；command 半句的 workspace 边界与收敛转移一并作为后继议题。

## BUILD 前未验证的事实

1. 整包运行下除 TestChannelIsolation 与两个状态探针外，还有哪些测试失败/skip（需第 0 片在 nonce 库上实际跑）。
2. `TestMTick003` 挂住原因。
3. `cr_execution_control_command` 转移 guard 对"workspace 已删"是否有可用语义；当前创建路径是否拒绝已删 workspace（U3 的测试会给出答案）。**已回答，见 R5**：两条创建路径都不查 workspace，探针实测放行；reservation 半句在本 change 内修，command 半句按裁定登记为已知失败。转移 guard 的 `uncertain` 语义仍未用于"workspace 已删"，收敛转移不实现。
4. `handler` 中 `governance` 包是否已被 handler 导入（新增 `DeleteWorkspaceExecutionRows` 的调用是否引入新的包依赖方向）。**已排除，见 R3。**
5. `core/package.json` 新增 `./platform/storage` exports 是否被 lint/knip/`check-ui-wildcard-exports` 接受。
6. ubuntu-latest 上 `npm install --prefix` 取 `pg` 的耗时与稳定性；`ci.yml` 改动触发的 CI 总分钟数。
7. WSL `AIFI-ISO` 的 profile（uid 995/gid 994、launcher）现在是否仍可用。
8. `go test -skip` 在 Go 1.26 下对多包、子测试名的匹配细节（`-skip` 按斜杠分层匹配）。

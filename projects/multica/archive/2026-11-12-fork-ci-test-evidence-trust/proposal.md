# fork CI 与测试证据可信性修复

<!-- source_hash: dd59ac55294e83a1 -->
<!-- generated_at: 2026-11-13T09:21:19.716304 -->
<!-- canonical: canonical/proposals/2026-11-12-fork-ci-test-evidence-trust.yaml -->

## Why

fork（OldBoy405/AI-First-multica）main 的 CI 持续为红，且红灯背后既有环境缺口，也有真实缺陷，还有让"绿"或"红"不可信的测试证据问题。
核实时点 2026-11-12，multica main = origin/main = 903a46c5a（上一 change 2026-11-11-aifi-45-admission-task-binding 已归档并推送），
该 push 的 CI run 43021822604 为 failure：backend-tests（Test 步骤）与 transitions-contract-check 失败，backend 汇总 job 随之失败；
frontend-build 因 paths 过滤在最近几次 push 被 skipped，红灯被掩盖。最近 45 个 CI run 中 backend-tests 没有成功过，
2026-11-02 起所有跑完的 run 均失败（另有若干被取消）。已核实的具体事实（逐项来自 CI 日志、源码与本地复现）：
1. backend-tests 失败的包与原因（run 43021822604）：cmd/server 与 governance 的 TestMain 因没有一次性库 nonce 而退出，
   governance 整包因此一个测试都没跑；governance/crosslang_test 3 项因 CI 没有同级 tools 检出；
   daemon TestChannelIsolation 因没有隔离 profile（需 root + 异于 daemon 的 worker uid/gid）；
   handler TestWorkspaceDeletionManifestCoversPublicSchema 报 19 张表 unclassified。
   另有 2026-11-02 的失败（早于 nonce 门禁）已查明：TestChannelIsolation、两项 crctl 测试
   （execution_authorization_test.go 默认路径写死开发机 C:/Users/GOBAO/...，CI 上不存在）、
   governance 整包 10 分钟超时 panic（挂住原因仍未查）、handler 清单漂移。
   所以 nonce 不是 CI 变红的起因，也不是唯一原因。
2. transitions-contract-check：此前登记写"secret 未配置"，核实后不成立——仓库 secret AIFIRST_TOOLS_READ_TOKEN 存在
   （updatedAt 2026-10-07），"Require the tools read credential" 步骤通过，失败在检出 pinned tools 的 git 认证
   （could not read Username，即凭据被 GitHub 拒绝，多半是 PAT 失效、过期或权限不足）；
   该 job 自 2026-11-02 首次真实执行起就没有成功过，无法判断该凭据是否曾经有效。凭据值不可读取，需管理员处理。
3. frontend-build：@multica/views#typecheck 报 60 条 TS6059，本地同样复现（60 条）。根因已定位：
   提交 26f6c5b0a（11-10，AIFI-45 的 114 文件大提交）改写 packages/views/auth/use-logout.test.ts，
   引入 "../../core/..." 相对导入（上游用包导入），核心文件被当作 views 的源文件而越出 rootDir。
   frontend-build 在 11-09 全量 run 通过、11-10 首次因该提交变红。
4. scripts/aifi45-disposable/run-selection.mjs 与 selection.mjs 对账结果不一致：selection.mjs 返回
   { status: 'matched' | 'blocked', reason }，run-selection.mjs 读的是 reconciliation.matched / reconciliation.blocked。
   于是 `matched !== false` 恒为真，对账失败从不使 selection 失败，失败原因也无法打印。目前 selections.json 没有任何条目配置 expected，
   缺陷尚处潜伏。同一处还有：expected 配置为空数组或非数组时被静默当作"未配置"。
5. 19 张 cr_execution_* 表（迁移 643–648）不在 workspace 删除清单里。已读迁移：全部没有指向 workspace 的外键/级联；
   其中 7 张带 workspace_id，12 张按 scope/lineage 键控、无 workspace_id；其中 16 张表带禁止 DELETE 的 append-only 或 guard 触发器（部分还禁 TRUNCATE），仅 notice、dispatch_root、tool_cursor 没有。
   因此删除 workspace 时这些行不会被级联删除，其中 16 张还不能被普通 DELETE 删除——这是事实上的保留，不是经过决定的保留。
   上游清单测试只校验分类覆盖，不校验删除行为，且规定 KEEP 类表不得带 workspace_id，所以这 7 张表目前无法被合规地登记为保留。
   旧设计（2026-10-27-trusted-verdict-channel §5）只对 14 张表写了一句"audit/selection/settlement/binding/fact 保留，command/cursor 禁新建并收敛"，
   643–647 的表没有任何删除决定。
6. 测试证据的其他缺口：scripts/aifi45-disposable 下 42 个 node 单测不在任何 CI job 里执行；
   handler 的 TestMain 在数据库不可达时打印 "Skipping tests" 并 exit 0，go test 会报 ok 而一个测试没跑；
   handler 测试未设 DATABASE_URL 时默认连 localhost:5432，本机有旧的 multica-postgres 容器（当前已停止），一旦它运行，直接跑会连到旧库。


## What Changes

- CI backend-tests 前置条件：为受 nonce 门禁保护的包（cmd/server、governance）在 CI 的服务容器里按 provision.mjs 的现行规则开出一次性库并注入 DATABASE_URL 与 AIFI45_DISPOSABLE_NONCE；门禁本身不放宽。
- CI 检出 tools 并注入 AIFI45_TOOLS_ROOT / CRCTL_MJS，使 crosslang_test 与 crctl CLI 测试在 CI 真跑；去掉 execution_authorization_test.go 中写死的开发机路径默认值，缺失时报出所需环境变量名。pinned 修订与 transitions 检查共用一处声明。
- 专项测试验收归属表：每类专项测试（nonce 库、tools 依赖、特权隔离 profile 等）明确归属 CI 或独立入口；归属独立入口的测试在 CI 中被显式排除并输出名单，由独立入口真实执行并留证据；归属表与实际排除项由机器核对，二者不一致时失败。
- CI 测试证据对账：nonce 库、DB 依赖包（cmd/server、governance、handler）及 crosslang_test 在 CI 中必须有真实通过的测试；整包 0 测试、被静默跳过或 DB 前置失败时 CI 失败（含 handler TestMain 的 exit 0 路径），不依赖修改上游测试文件。
- 修复 run-selection.mjs 与 selection.mjs 的对账契约：预期测试缺失、对账 blocked、expected 已配置但为空或非数组，均使 selection 失败并打印原因；未配置 expected 的条目行为与修改前逐项一致；对账决策抽成可单测的小函数。
- scripts/aifi45-disposable 的 node 单测纳入 CI（script-checks 或等价 job），使 C5 的修复受 CI 保护。
- workspace 删除：在 runner 自建的一次性库内复现 19 张 cr_execution_* 表漂移；确认每表保留/删除策略（见 Gate 1 待裁定 D2）后，实现删除路径（如需）、更新清单、补 workspace 删除的行为测试（创建带这些数据的 workspace → 删除 → 断言每类数据按策略处置）。不仅改清单。
- transitions-contract-check：只做诊断与失败信息改进——检出前以不输出凭据的方式区分「secret 缺失」与「secret 被拒绝或无权限」；凭据由仓库管理员按最小权限（仅 OldBoy405/AI-First-tools、Contents: Read-only）更新；不读取、不输出、不创建凭据。
- frontend-build：把 packages/views/auth/use-logout.test.ts 的相对导入改回包导入，恢复 views typecheck；在本地跑 views 的 typecheck 与该测试，并核实 frontend-build 其余任务无同类问题。
- 验收报告：列出实际执行的 CI run 与本地检查（命令、退出码、通过/失败/跳过数）、测试范围与未覆盖项；失败与跳过如实记录。

### New Capabilities

- **专项测试验收归属与 CI 对账**：每类专项测试有唯一明确的验收归属；CI 对 DB 依赖与专项包做真实执行对账，缺跑或静默跳过即失败。

### Modified Capabilities

- **fork CI 后端测试环境**：为 nonce 门禁包提供一次性库，检出 pinned tools，并让 crctl 与 crosslang 测试在 CI 真跑。
- **一次性库 selection 对账（run-selection）**：对账失败与预期缺失使 selection 失败；未配置 expected 的行为不变。
- **workspace 删除清单与删除路径**：AIFI-45 执行控制表的保留/删除策略落地为清单与行为测试。
- **CI 凭据诊断与前端 typecheck 回归**：transitions 检查的凭据失败原因可区分；views typecheck 恢复。

## Success Criteria

- [ ] SC1 基线与复现：在 runner 自建的一次性库中复现 handler 清单漂移，unclassified 列表恰为 CI 日志中的 19 张 cr_execution_* 表；复现与修复全程 DATABASE_URL 只指向一次性库，前后容器清单一致（旧库 multica-postgres 未被启动或访问）。
- [ ] SC2 nonce 包真跑：CI 中 cmd/server 与 governance 不再因 nonce 退出，各自 go test -json 里通过测试数大于 0；governance-identity selection（错误 nonce 必须被拒）仍通过，证明门禁未放宽。
- [ ] SC3 tools 真跑：CI 以单一声明的 pin 检出 tools；crosslang_test 3 项与 TestExecutionGrantCheckAgainstRealCrctlCLI、TestExecutionAuthorizationRevokeHTTPToRealNodeCLI 在 CI 通过；测试源码中不再有开发机绝对路径默认值，缺环境时的错误信息含所需变量名。
- [ ] SC4 归属表：每个专项测试组都有“CI”或“独立入口”归属；归属独立入口的测试在 CI 中被显式排除并输出名单与数量；机器核对归属表与排除项，故意制造不一致时 CI 步骤失败；独立入口至少真实执行一次，结果入验收报告，无法执行的列为未覆盖。
- [ ] SC5 CI 对账：故意让 handler/governance 连不上库、或让必需包 0 测试通过时，CI 对账步骤失败（本地用等价输入证明）；该机制不修改上游测试文件，或对其改动给出必要性说明并登记。
- [ ] SC6 run-selection：expected 中的测试在流里缺失、对账返回 blocked、expected 为空数组或非数组，均使该 selection 为 FAIL 且整体退出码非 0，并打印 blocked 原因；未配置 expected 的条目，用修改前后相同输入比对，输出与退出码一致；以上均有自动测试，其中缺失与 blocked 用真实 go test -json 输出或忠实夹具；把旧判断恢复回去时相应测试必红。
- [ ] SC7 node 单测入 CI：scripts/aifi45-disposable 的 node 单测在 CI 某个 job 中真实执行，日志可见测试数。
- [ ] SC8 workspace 删除：19 张表的保留/删除策略经用户确认后记录在案；清单按策略登记；对每类策略有行为测试（建数据 → 删 workspace → 断言处置结果；保留类断言行完整未被改写，删除类断言行已删且一般 DELETE 仍被触发器拒绝）；TestWorkspaceDeletionManifestCoversPublicSchema 与新增行为测试在一次性库真实执行通过（无 skip）。
- [ ] SC9 transitions：给出凭据失败的诊断结论与证据（不含凭据值）；CI 失败信息能区分 secret 缺失与被拒绝；凭据更新由管理员完成后该 job 通过（该项依赖管理员动作，未完成则如实列为未闭合）。
- [ ] SC10 frontend：packages/views 的 typecheck 本地 0 条 TS6059；use-logout.test.ts 通过；frontend-build 在 CI 通过（需推送授权，未授权则列为本地验证）。
- [ ] SC11 验收报告：列出每项实际执行的 CI run 与本地命令、退出码、通过/失败/跳过数，测试范围与未覆盖项；任何 skip 数大于 0 的包有说明；失败与跳过如实报告，不出现“未执行却报绿”的项。

# 专用 Podman machine 上的 disposable PostgreSQL（2026-10-31）

**这是基础设施就绪记录，不是业务验收。** 原 AIFI-45 两侧 Gate3 仍为 NO-GO；尚未运行任何迁移或业务测试。

用户已同意：为新 PG 新建专用 Podman machine、必要时下载其系统镜像与 PG 镜像；已说明可能读写 Podman 共享机器登记与连接配置。历史事故数据库、容器、卷与旧引擎 HOLD **未解除**，本轮不访问、不清理、不验证它们。

## 已建立的环境

| 项 | 值 |
|---|---|
| Podman（安装版） | 5.8.3，WSL provider |
| 专用 machine | `aifi45-pg-db604fa9e182`（2 CPU / 2 GiB / 20 GiB，rootless） |
| machine OS 镜像 | `quay.io/podman/machine-os:5.8`，blob `sha256:5089400f…` |
| PG 镜像 | `docker.io/pgvector/pgvector@sha256:cd4ccfdaf62cbfeb5c6ee19ef0dd663406d4ed740c320b324d016a90e85385b3`（与项目 `docker-compose.yml` 的 `pgvector/pgvector:pg17` 标签对应的 linux/amd64 清单一致） |
| 容器 | `aifi45-pg-6ea67340`，ID `880613ba4a52…` |
| 数据库 / 用户 / 端口 | 随机生成，记录于 `control/pg-identity.json`；密码仅存于 `control/pg.env`（已被 `.gitignore` 排除），未进入任何输出 |
| 实际 PostgreSQL | 17.11 (Debian 17.11-1.pgdg12+2) on x86_64-pc-linux-gnu |
| 可用扩展 | `vector` 0.8.7、`pg_trgm` 1.6、`pgcrypto` 1.3；**`pg_bigm`、`pg_cron` 在该镜像中不可用** |

迁移 032（pg_bigm）与 076（pg_cron）本身有 DO/EXCEPTION 容错，因此这两个扩展缺失与该镜像在项目 CI 中的行为一致；但这意味着 fresh-install 的账本计数**不能**被解释为“所有扩展均已创建”。

## 隔离的实际边界（不得夸大）

1. **控制目录与连接隔离**：所有 Podman 命令在自建控制目录中以显式构造的环境变量运行（`HOME`/`USERPROFILE`/`APPDATA`/`LOCALAPPDATA`/`XDG_*`/`TMP`/`TEMP` 指向该目录，`PODMAN_CONNECTIONS_CONF`、`REGISTRY_AUTH_FILE` 指向该目录内的路径）。隔离配置中只列出本轮的 machine 与两条连接；`podman images` 初始为空，证明镜像存储是新的。
2. **未触碰旧环境**：真实用户配置下的 `podman-machine-default.json` mtime 为 2026-10-26（本轮之前），未读取其内容，也未停止、列举或修改任何既有 machine、容器、卷。真实 `podman-connections.json` 与 `containers.conf` 在该路径不存在。
3. **未设为默认连接（在真实配置中）**：本机 5.8.3 的 `machine start` 没有 `--update-connection`；因 stdin 非 TTY，按官方文档不会提示或更新。隔离配置中本机为默认，但该文件只在本控制目录内。
4. **网络是共享的**：WSL 后端下所有发行版共用同一 WSL2 网络。`podman inspect` 显示 `NetworkMode=pasta`。这意味着**本容器所在机器与 HOLD 环境共享 localhost**；隔离依靠“不发起连接”，不是网络隔离。端口发布只绑 `127.0.0.1:49258`。
5. **没有宿主目录绑定**：`Mounts` 为 1，是 Podman 自建的匿名卷（`…:/var/lib/postgresql/data`），位于本 machine 的存储内；`HostConfig.Binds` 只含该卷 ID，没有任何宿主路径。
6. **WSL 自动挂载仍存在**：本 machine 的 Linux 系统默认挂载 `C:`（官方文档确认 `--volume` 无法改变）。测试代码不在该 Linux 系统内运行，PG 容器也没有挂载宿主目录；但这**不是**隔离证明，只是“未使用该可见性”。
7. **PG 容器可访问宿主机回环**：pasta/slirp 用户态网络下，容器可经网关访问宿主 127.0.0.1。HOLD 数据库在同一 localhost 上可达。必须确保迁移与测试代码只连接本容器的端口。
8. **进程同用户**：Podman、WSL、容器进程都与当前 Windows 用户同级；这不构成对同用户恶意进程的边界。

## 运行记录（证据位置）

`control/` 下保存了各步骤的原始 stdout/stderr（`machine-init.*`、`machine-start.*`、`pull-registry-1/`、`run-1/`、`verify-1..4/`）。这些是命令退出码与片段，不是完整业务日志。

## 待决定

- **fresh-install 正式迁移：已完成。**
- **业务测试：部分完成，见下。**
- **清理**：仅删除本轮创建的容器与该 machine（`podman rm -f`、`podman machine rm`），不使用 `wsl --shutdown`、不按名字杀进程、不 prune 任何既有资源。

---

# 附：正式迁移与业务测试结果（2026-10-31 晚）

## 1. fresh-install 正式迁移（两处独立库）

对两个各自独立的库执行 `go run ./cmd/migrate up`（cwd `multica/server`，显式 `DATABASE_URL`，`GOPROXY=off`，未使用仓库既有 runner）：

| 库 | 身份 | 结果 |
|---|---|---|
| `aifi45_ad2612ca` | 初始 superuser | exit 0，677 个 `up` 条目，`Done.` |
| `aifi45_tmp_9646091b823f4cf8` | `aifi45_role_9646091b823f4cf8`（NOSUPERUSER/NOCREATEDB/NOCREATEROLE/NOBYPASSRLS，库 owner，双 marker `AIFI45_DISPOSABLE:9646091b823f4cf8`） | exit 0，677 个 `up` 条目，`Done.` |

账本核对：`schema_migrations` 仅 `version`、`applied_at` 两列，**677 行**；`server/migrations/*.up.sql` 共 **677 个版本**，集合逐一相等（无缺失、无多余、无重复）。迁移后用户表 156 张。已装扩展 `pg_trgm 1.6`、`pgcrypto 1.3`、`plpgsql 1.0`；`vector` 可用但迁移未创建；**`pg_bigm`、`pg_cron` 在该镜像不可用**，对应迁移按条件跳过并在输出中注明（5 条带注释的 `up`：139、140、371、446、469）。

## 2. 业务测试

统一环境：`PATH` 含 Go/Git/Node/OpenSSH，`HOME` 为真实 profile（Go 模块缓存所需），`AIFI45_TOOLS_ROOT` 指向 tools 仓，`DATABASE_URL` + `AIFI45_DISPOSABLE_NONCE` 指向本轮 disposable 库。`-race` 未用（`CGO_ENABLED=0`）。

**更正（复核 finding F4，2026-10-31）**：上面这句只描述**后期**的运行。此前有两次全包回归用的 `PATH` 更窄（缺 `git`/`node`），产生了 `internal/governance` 14 项、`internal/daemon` 89 项失败，其中绝大部分是「找不到 git/node」的环境性失败，与本轮改动无关；这两次结果不并入下表，也不能用「统一环境」一句把差异盖掉。相关原始日志在 `control/attempts/full-regression*/`。

| 范围 | 结果 |
|---|---|
| `./cmd/server -run '^TestTC_RUN_(002\|003\|010)$'` | **3/3 PASS** |
| `./internal/governance -run '^TestTC_(RUN_00[45]\|NTF_00[1-7])'`（首轮） | **9/9 PASS** |
| `./internal/service` 全包 | **ok** |
| `./cmd/server` 全包 | **ok** |
| `./internal/governance` 全包 | FAIL 8（见下） |
| `./internal/daemon` 全包 | FAIL 18（见下） |

### governance 余下 8 项
- `TestChannelMigrationAfterUp/AfterDown/AfterReapply`：在各自**独立初态**的库上单独运行**全部 PASS**（up 态 = 完整迁移后；down 态 = 额外应用 `648_cr_execution_control.down.sql`；reapply 态 = down 后再 up）。全包内失败是共库顺序污染，不是缺陷。
- `TestChannelProtocol/purpose_domain_scope`：**已修为通过（仅改测试，未改产品代码）**。原测试对「domain 与操作固定域不符」期待 `ErrControlSignatureInvalid`，但 Go 与 Node 参考实现（`lib/execution-control-protocol.mjs` L344、其测试 `execution-control-protocol.test.mjs` L114）**都在解析/验签前**就以 `EXECUTION_CONTROL_BINDING_MISMATCH` 拒绝，所以那条断言永远无法到达签名层。现已改为期待 `BINDING_MISMATCH`，并新增两条更强的覆盖：① 用 `CheckpointDomain` 前像签一份 verdict payload（`signOverDomain` 绕过签发端策略）当 `verdict/VerdictDomain` 验 → 必得 `SIGNATURE_INVALID`，这才是「域在签名内」的实据；② 用一把「purpose 正确、只授权 `CheckpointDomain`」的 attestation key 构造真正的 allowlist 反例 → `KEY_INVALID`。结果：`TestChannelProtocol` 8/8 子测试全 PASS，`gofmt -l` 干净、`go vet ./internal/governance/` 通过。
- `TestTC_NTF_001/002/005/006/007`：**在全新库上整包首跑 7/7 PASS；同一库二跑即 4 项失败**。这些用例在固定 `cr_id` 上断言绝对行数、fixture 不清理也不换号，所以不是产品缺陷、也不是用例间顺序依赖，而是**「一次性库、每次验收新建」的前置条件**。已写入 `test-plan.md` §三。

### 全新库上的整包结果（本轮最新）
新建 `aifi45_tmp_de551b34a7582f9d` / `aifi45_role_de551b34a7582f9d`（标记与权限四项全过，role 为 db owner），按正式 `cmd/migrate up` 迁移后跑整包：

- `./internal/governance` exit 1，**仅 3 项 FAIL**，全部是 `TestChannelMigrationAfterUp/AfterDown/AfterReapply`（已知需独立初态，已在专用库上全 PASS）；NTF 组全部通过。
- 同一库重跑 NTF 组：exit 1、4 项 FAIL（NTF-002/005/006/007），坐实「重跑不幂等」而非产品缺陷。

### daemon 余下 18 项（分类）
- 缺 `claude` CLI（环境）：5 项 `TestRunTask*`。
- macOS / agent CLI 专属路径（平台）：5 项（Codex app bundle、DSH Desktop 布局）。
- 可能为 Windows 真实缺陷：`TestDshPluginPathDirs_FindsBothLayouts/flat`（期望恰好 1 个目录，Windows 返回 2 个）、`TestRefreshHealedVersion_*`、`TestListRuntimeLocalSkills_CodexUsesSharedCODEXHOME`、`TestListRuntimeLocalSkills_ClaudeEnabledPlugin`（skills 为空）、`TestListRuntimeLocalMcpServersClaudeEnabledPlugin`、`TestMergeRuntimeAndAgentMcpConfigClaudeCombinesAndAgentWins`、`TestRefreshAgentVersions_DemotesWhenTheDowngradeMovedThePath`、`TestHandleRuntimeGone_DistinctDeletionsWithinCoalesceWindowBothRecover`。
- 文件系统/环境：`TestLockReusablePriorEnvRootSurvivesWorkspacesRootSwap`（Windows 下 rename 目标被占用）、`TestPruneWorktree_LegacyCacheFallbackSerializesWithCreateWorktree`（git clone）。

### daemon 余下失败（本轮做了两组对照实验）

在**真实 HOME**（Go 模块缓存所需）与**自建独占临时 HOME** 两种环境下各跑一次整包，失败数 18 / 23，两次均失败的是同一批用例：

| 类别 | 用例 | 实测证据 |
|---|---|---|
| 宿主机缺 agent CLI | `TestRunTaskReusesPriorWorkdirForFreshSession`、`TestRunTaskSquadLeaderReusesWorkdirBeforeGCMetaWritten`、`TestRunTaskSquadLeaderDoesNotReuseExternalPriorWorkdir`、`TestRunTaskCancelledWaitingForThePriorWorkdirStopsInsteadOfPreparing`、`TestRunTaskDeclinesReuseWhenTheClaimedDirectoryIsSwappedBeforeUse`、`TestLoadConfig_UsesCodexDesktopAppBundleFallback`、`TestLoadConfig_UsesChatGPTAppBundleCodexPath`、`TestLoadConfig_CodexDesktopFallbackDoesNotOverrideExplicitPath`、`TestListRuntimeLocalSkills_ClaudeEnabledPlugin`、`TestListRuntimeLocalMcpServersClaudeEnabledPlugin`、`TestMergeRuntimeAndAgentMcpConfigClaudeCombinesAndAgentWins` | `claude executable not found` / `no agent CLI found: install claude, codebuddy, codearts, codex, copilot, opencode, ...` |
| Windows 文件语义 | `TestLockReusablePriorEnvRootSurvivesWorkspacesRootSwap` | `rename ... The process cannot access the file because it is being used by another process` |
| git 在临时 HOME 下的行为 | `TestEnsureRepoReady*`（4）、`TestPruneWorktree_LegacyCacheFallbackSerializesWithCreateWorktree`、`TestRegisterTaskReposAllowsProjectOnlyURL` | `git clone --bare: could not create leading directories` / `Lookup returned empty`（只在 HOME 被隔离时出现） |
| 平台（macOS 专属目录） | `TestDshPluginPathDirs_FindsBothLayouts/flat` | 期望恰好 1 个目录，本机返回 2 个 |
| 待定 | `TestRefreshHealedVersion_KeepsHealedPairCurrentAfterInPlaceUpgrade`、`TestRefreshAgentVersions_DemotesWhenTheDowngradeMovedThePath`、`TestHandleRuntimeGone_DistinctDeletionsWithinCoalesceWindowBothRecover` | 两次都失败，未单独定位；与 AIFI-45 改动文件无关 |

本会话在 `server/internal/daemon/` 下只改了 `crevents.go`、`daemon.go`、`crevents_test.go`、`execution_control_recovery_d8_test.go`、`execution_control_worker_test.go`、`health_test.go`；上表失败用例的源文件均不在其中，且失败信息指向缺二进制/平台路径/Windows 锁语义。**但这不等于已证明零回归，也不等于 `./internal/daemon` 全包回归通过**——该包在本机无法跑绿，test-plan 要求的全包回归仍是未完成项。

### 与 test-plan 的执行方式偏差（必须如实记录）

`test-plan.md` §三要求 DB 用例经版本化 `scripts/aifi45-db/run.mjs` 在专用隔离库执行。本轮**没有**使用该脚本（它属历史事故库链路，继续 HOLD，禁止访问/改向），而是直接 `go test` + `TestMain` 的 disposable 身份门禁（nonce/角色/库名/双 marker/四项特权）在新建的独立库上执行。因此本轮结果只能算工程证据，**不算 plan-conformant 的正式 TC 证据**；正式验收仍须按 test-plan 的执行路径重跑。

### 本轮代码改动（multica 仓）
1. `server/internal/daemon/health_test.go`：16 处手写 JSON 请求体改为 `json.Marshal`（新增 `repoCheckoutJSON`）。原因是 Windows 临时路径含 `\U`、`\t` 等转义，被 `/repo/checkout` 在断言前拒绝。**纯测试改动，断言与字段不变**；已登记 `multica/CUSTOM.md` #288。效果：7 个 `TestRepoCheckout*` 不再出现在失败列表，该包 FAIL 25 → 18。逐项证据（复核 finding F4 之后补测）：`go test ./internal/daemon -run '^TestRepoCheckout' -count=1 -v` exit 0、**15 项逐项 PASS、0 FAIL、0 SKIP**（`control/attempts/repo-checkout-verbose.txt`）。整包非 verbose 输出本身只能证明「不再出现在失败列表」。
2. `server/internal/governance/execution_control_protocol_test.go`：修正上述两条陈旧期望 + 新增 `signOverDomain` 与受限 manifest 反例，**不动产品代码**；已登记 `multica/CUSTOM.md` #289。

## 3. 仍未完成（不计入通过）
- `TestTC_RUN_001` 及 `authorized_execution_integration_test.go` 尚不存在（test-plan 中标为“拟新增”）。
- 642 前旧行初态：`cmd/migrate` 只能整体 up/down，无法只迁移到 641，该初态本轮未建立。
- cr-events 投影/ACK 重放、Composio 预事务、RUN-009、EVD-009、checkpoint outbox 恢复、`durable-tx` 恢复清理归属、通知 producer 重新接线等仍未验证。
- 上述任何一项都不构成原 AIFI-45 的 Gate3 放行。

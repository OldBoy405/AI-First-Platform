# Slice 13 — CI 接线与独立入口（收口）

- **change**：`2026-11-12-fork-ci-test-evidence-trust`（STDD 原生，非 CR）
- **业务仓**：`C:\Users\GOBAO\Downloads\AI\multica`，`HEAD = origin/main = 903a46c5ae9f`，本切片未提交、未推送、未部署
- **模式**：thorough / 长程 `full_auto`；Gate 2 以 R5 裁定原文重签于 **2026-11-12T23:54:09**
- **完成时刻**：2026-11-13T02:34:17（本地 UTC+8）
- **结论摘要**：CI 接线与本地等价验证**全部实跑通过**；TC-TOR-004 **前半通过、后半 UNCOVERED**（WSL AIFI-ISO 无 Go 工具链、无核准 profile）；TC-CBE-005（真实 CI run）**未执行**，须推送另行授权。

---

## 1. 锁定依据与范围

| 依据 | 内容 |
|---|---|
| `canonical/specs/code/test-ownership-and-ci-reconciliation.yaml` | SC-TOR-001（归属表 check / skip-regex）、SC-TOR-002（`test-go.sh` 两个新参数）、SC-TOR-003（ci-evidence 五条硬失败）、**SC-TOR-004**（两个独立入口真实执行；不能执行时 SHALL 如实列为未覆盖，**不得以同 uid 对照代替**；执行前 SHALL 先说明并征得同意）、SC-TOR-005（验收报告） |
| `canonical/specs/code/ci-backend-environment.yaml` | SC-CBE-001（一次性库、环境文件不含明文口令，R1 已收敛到「日志与 handle」）、SC-CBE-003（单一 tools pin）、SC-CBE-004（凭据诊断）、SC-CBE-005（真实 CI run，manual） |
| `canonical/specs/code/selection-reconciliation.yaml` | SC-SEL-004（`ci-paths.json` scope 命中） |
| `design.md` 决策 1 / 3 / 5 / 6 / 9 + R1 | down 放 `if: always()` 收尾；凭据只诊断不打印；pin 单一来源；`DATABASE_URL` 不得指向旧库 |
| `test-plan.md:225-237` | **TC-SEL-004**，命令 `node --test --test-reporter=tap scripts/ci-scope.test.mjs` |
| `test-plan.md`（TC-TOR-004） | 两个状态敏感 selection + WSL 隔离入口，逐项记命令 / 退出码 / 通过数 |
| `slices.md:123-127` | 风险 3（跨模块 +1、接口变更 +1、真实 CI 未验证 +1）；工作量 L；`ci.yml`/`ci-paths.json` 回归矩阵 🔴；**改 `ci.yml` 会触发全部 scope，推送次数压到最少并先本地等价验证** |
| U5 预授权 | 一次性 podman 实例、启动 WSL AIFI-ISO、npm 安装 pg、推送触发 CI、管理员更新 PAT。**不含**读取/创建 PAT、改仓库 secret、部署；Git 提交仍须单独授权 |

**本切片只改 4 个文件**（3 个上游文件 + 1 个台账）：`.github/workflows/ci.yml`、`.github/ci-paths.json`、`scripts/ci-scope.test.mjs`、`CUSTOM.md`。S1–S12 新增的 fork 独有脚本**一行未改**（`git diff --name-only` 核对）。

## 2. 上游挂钩点逐处清单

### 2.1 `.github/ci-paths.json`（+2 / −0，2 处）

`"scripts/aifi45-disposable/**"` 分别加入 `backend`（第 26 行，紧随 `scripts/test-go.test.sh`）与 `scripts`（第 99 行，紧随 `scripts/makefile-build.test.sh`）。其余 6 个 scope 一字未动。

### 2.2 `.github/workflows/ci.yml`（累计 +113 / −12，其中 S13 为 8 个 hunk；另 2 个 hunk `@@ -126 +137 @@`、`@@ -129,0 +141,5 @@` 属 S2 的 pin 工作，本切片未动）

| 位置 | 改动 | 归属 |
|---|---|---|
| `transitions-contract-check` | **删除**旧「Require the tools read credential」步骤（9 行，只判 token 非空） | SC-CBE-004 |
| 同 job，Checkout + Setup Node.js 之后 | **新增**「Diagnose the tools read credential」（20 行含 AIFIRST 注释）：`env.AIFIRST_TOOLS_READ_TOKEN` ← secret，`run: node scripts/aifi45-disposable/tools-access.mjs` | SC-CBE-004 / S11 产物首次被消费 |
| `backend-tests` job env | **删除** `DATABASE_URL: postgres://…@localhost:5432/multica`；**新增** `AIFI45_CI_ADMIN_URL`（同一 URL，改名以断绝「测试默认连旧库」）、`AIFI45_TOOLS_ROOT: ${{ github.workspace }}/.aifirst-tools`、`CRCTL_MJS: …/skills/shared/crctl/scripts/crctl.mjs`。最终 env 键恰为 `AIFI45_CI_ADMIN_URL / AIFI45_TOOLS_ROOT / CRCTL_MJS / REDIS_TEST_URL / GOFLAGS` | SC-CBE-001；S9/S10 硬结论「CI 必须显式注入这两个变量」 |
| `backend-tests`，Checkout 之后 | **新增** `Setup Node.js`（`actions/setup-node@v6`，node 22，无 cache）——pin / provision / 对账三步都要 node | 接线前置 |
| `Vet tag-gated agent integration tests` 之后、`Run migrations` 之前 | **新增连续 AIFIRST 块（37 行）**：Diagnose credential → Read the single tools pin（`id: tools-pin`，`pin="$(node …tools-pin.mjs read --pin .github/aifirst-tools-pin)"` → `GITHUB_OUTPUT`）→ Checkout the pinned tools contract revision（`OldBoy405/AI-First-tools`，`ref: ${{ steps.tools-pin.outputs.ref }}`，`path: .aifirst-tools`，token 用 secret）→ Check the tools pin integrity → Fetch the pg driver for provisioning → Provision the one-time test database（`ci-provision.mjs up`） | SC-CBE-001 / 003 / 004 |
| `Test` 步骤 | 加 `id: go-test`；run 体改为两行：先 `skip_regex="$(node …test-ownership.mjs skip-regex)"`，再 `bash scripts/test-go.sh --race --only regular --skip-regex "$skip_regex" --json-out "$RUNNER_TEMP/aifi45-go-test.json"` | SC-TOR-001 / 002 |
| `Test` 之后、上游 Prune/Save cache 之前 | **新增收尾三步**：Reconcile the Go test evidence（`if: !cancelled() && steps.go-test.outcome != 'skipped'`）→ Check the test ownership table（同条件）→ **Drop the one-time test database（`if: always()`，最后一个数据库步骤；其后仍有上游 `Prune Go build cache`（:547）与 `Save Go build cache`（:559）两步，C1 更正措辞）** | SC-TOR-003 / 001；design 决策 1 |
| `script-checks` 末尾 | **新增**「Test disposable database harness」（10 行）：读根 `package.json` 的 pg 版本 → `npm install --prefix "$RUNNER_TEMP/aifi45-node"` → `NODE_PATH=… node --test scripts/aifi45-disposable/*.test.mjs` | SC-SEL-004；harness 自身也要被 CI 跑 |

`ci.yml` 内含 `AIFIRST` 的行由 HEAD 的 **7** 增至 **19**（其中 `# AIFIRST:` 注释行 **4 → 15**；实测口径为 `grep -c`，按行计）。`.yml` 不属四数基线口径，只作追溯。YAML 解析通过，**17 个 job**（`scope-and-jobs.txt`）。

### 2.3 `scripts/ci-scope.test.mjs`（+111 / −1，4 处）

1. **第 80 行上游挂钩（1 行替换）**：读 workflow 时 `.replaceAll("\r\n", "\n")`。理由见 §12.1。
2. **第 37 行 scope 表新增 1 行**：`["disposable test harness", ["scripts/aifi45-disposable/run-selection.mjs"], ["backend", "scripts"]]`（TC-SEL-004 的表驱动用例）。
3. **第 103–132 行新增 4 个 helper**：`stepsOf(job)`（按 `^      - ` 切步骤边界）、`stepNamed(job, name)`（要求恰好 1 个同名步骤）、`stepOrder(job, names)`（顺序 + 齐全）、`runBody(step)`（**只取 `run:` 之后的正文**）。
4. **第 235–312 行新增 3 个独立测试**：script-checks 的 fail-closed 与顺序、backend-tests 的完整接线、两个 tools 消费者都改为诊断。

`runBody` 不是多余抽象：首轮 GREEN 时 `assert.doesNotMatch(test, /--skip-regex "\$\(/)` **被我自己写的注释命中**（注释里引用了被禁形式作为说明）。注释是文档不是可执行内容，故所有「这一步执行什么」的断言一律只读 `run:` 正文。**未放宽任何断言**，只是把断言指向正确的字节范围。

## 3. RED（两轮，均先取得干净基线）

**基线先行**：动手前 `scripts/ci-scope.test.mjs` 在本机是 **44 pass / 1 fail**（45 tests）。该失败是**既有基线缺陷**，不是本切片引入：第 208 行的跨行正则对 CRLF 工作树不匹配（`core.autocrlf=true`，HEAD blob 是 LF）。按业务仓 `AGENTS.md`「对仓库文件做跨行正则的代码，读入后先将 `\r\n` 规范化为 `\n`」加 1 行 AIFIRST 挂钩后基线 **45/45**。语义等价、不弱化任何断言。**先有干净基线，RED 的 2 个失败才能无歧义归因于新断言。**

| 轮次 | 证据 | 结果 |
|---|---|---|
| 13.1 RED（scope + script-checks） | `red-ci-scope.txt` | **47 tests / 45 pass / 2 fail / 0 skipped**，exit 1，duration 219.4 ms |
| 13.3 RED（backend-tests + 凭据诊断） | `red-backend-wiring.txt` | **49 tests / 47 pass / 2 fail / 0 skipped**，exit 1，duration 240.7 ms |

两轮失败的都是本切片新写的断言（scope 表新行 + script-checks 步骤；backend-tests 接线 + 两个消费者的诊断步骤），既有 45 项全绿。

## 4. GREEN

| 轮次 | 证据 | 结果 |
|---|---|---|
| 13.2 GREEN | `green-ci-scope.txt` | **47 / 47 / 0 fail / 0 skipped**，exit 0，236.1 ms |
| 13.3 GREEN | `green-backend-wiring.txt` | **49 / 49 / 0 fail / 0 skipped**，exit 0，243.7 ms |

命令即 TC-SEL-004 锁定命令：`node --test --test-reporter=tap scripts/ci-scope.test.mjs`。

## 5. 本地等价验证（`local-step-equivalence.txt`，7 项，逐项真实执行）

| # | 步骤 | 命令 | 实测 |
|---|---|---|---|
| 1 | Diagnose credential（**凭据从环境剔除**，`env -u`） | `node scripts/aifi45-disposable/tools-access.mjs` | `missing: AIFIRST_TOOLS_READ_TOKEN is not set; …`，**exit 1** |
| 2 | Read the single tools pin | `node …tools-pin.mjs read --pin .github/aifirst-tools-pin` | `e52b8081f159d581bf62f82447c76f818fc52426`，exit 0 |
| 3 | Check the tools pin integrity | `node …tools-pin.mjs check --tools <本地 tools checkout>` | `tools pin e52b808… complete (3 required files present)`，exit 0 |
| 4 | Test 步骤的 skip-regex 取值 | `node …test-ownership.mjs skip-regex` | `^(TestChannelIsolation\|TestChannelMigrationAfterUp\|TestChannelMigrationAfterDown\|TestChannelMigrationAfterReapply\|TestWorkspaceDeletionRefusesNewCommand)$`，exit 0 |
| 5 | Drop（`up` 从未跑过的 `always()` 路径） | `node …ci-provision.mjs down`（无 handle） | `no disposable handle; nothing to clean up`，**exit 0** |
| 6 | Reconcile（流文件缺失必须硬失败） | `node …ci-evidence.mjs --stream <不存在> --table …` | `ENOENT …`，**exit 1**（不报绿） |
| 7 | Check the test ownership table | `node …test-ownership.mjs check` | `test ownership OK: 5 entry(ies)` + `allowed skips: 4`，**exit 0**（`local-ownership-check.txt`） |

第 5 项是 `always()` 收尾的关键安全性质：`up` 失败时 `down` 仍会跑，**必须成功空转而不是把 job 再染红一次**；`ci-provision.mjs` 在**导入 pg 之前**就处理无 handle 分支，所以连驱动都没装时也不会炸。第 6 项证明对账不会因缺流而静默通过。

## 6. fail-closed 证明（实跑，不是断言）

`script-checks` 新步骤的承诺是「先取 pg，失败即步骤失败」。两条都用 `bash -e` 真实执行：

| 证据 | 注入 | 实测 |
|---|---|---|
| `script-checks-pg-fetch-fails.txt` | `pg_version="999.999.999"`（硬编码不存在的版本） | `npm error code ETARGET` / `No matching version found for pg@999.999.999`，**exit 1**，**零条测试输出**——harness 根本没跑 |
| `script-checks-version-read-fails.txt` | `pg_version="$(node -e "process.exit(3)")"` | **exit 3**，`REACHED_INSTALL` **未打印** |

第二条钉住的是 bash 的一个真实陷阱：**`cmd "$(failing)"` 不会中止，而 `var="$(failing)"` 会**。`backend-tests` 的 `skip_regex="$(…)"` 正是因此写成两行；若写成 `--skip-regex "$(node …)"`，取值失败会被吞掉、空正则放行被排除的测试。该形式已由断言 `assert.doesNotMatch(testRun, /--skip-regex "\$\(/)` 锁死，并由 §7 的变异 M1 证明有 teeth。

> 首次尝试用 `sed` 改版本号做注入，结果把脚本改成了 Node eval 崩溃而非预期的 npm 失败；**该次输出未采信**，改用硬编码版本号重做，得到干净的 ETARGET。

## 7. 变异验证（`mutation-wiring.txt`，3 条，全部 DETECTED）

基线 `ci.yml` sha256 = `72c16f6b9302bb976402a57ddbf8c557e2444881aa8b5b390e9ac26725e1c43e`。

| # | 变异（把生产接线改坏） | 结果 | 还原 |
|---|---|---|---|
| M1 | `skip_regex` 改为内联 `--skip-regex "$(node …)"`（bash -e 陷阱） | exit 1，`not ok 46 - backend-tests provisions a one-time database, reconciles the evidence and tears it down` | sha256 逐字节相同 |
| M2 | 收尾 `Drop` 的 `if: always()` 去掉 | exit 1，同一条测试红 | sha256 逐字节相同 |
| M3 | 恢复 job 级 `DATABASE_URL` 默认值 | exit 1，同一条测试红 | sha256 逐字节相同 |

三条都只打中**预期的那一条**测试（46 号），其余 48 项保持绿——说明断言定位精确，不是靠连带失败蒙对。全部还原后 **exit 0 / 49 tests / 49 pass / 0 fail**，最终 sha256 与基线**逐字节相同**（本次记账时重测仍为 `72c16f6b…`）。

## 8. scope 与 runner 分钟数核对（`scope-and-jobs.txt`）

- 本 change 累计 **48 个改动文件** → 命中 **全部 8 个 scope**（frontend / backend / sqlc / runtime / quality / scripts / installer / images），`quality_only=false`、`full=false`。
- **这是改 `ci.yml` 的既有行为，不是本切片引入的回归**：`ci.yml` 属所有 scope 的公共路径。slices.md 已据此要求「推送次数压到最少」。
- **反事实核对**：只改 `scripts/aifi45-disposable/run-selection.mjs` → 命中 **backend + scripts**（正是 TC-SEL-004 要的性质，新增 scope 行生效）。
- 17 个 job 的 runner 与条件逐个列出：**14 个 ubuntu-latest**，`windows-execenv` = windows-latest、`macos-runtime` = macos-latest（两者都只在 `full == 'true'` 时跑，本次 `full=false` → **不触发 ×10 / ×2 计费**），`installer` = `${{ matrix.os }}`，`image-budget` 只在 PR 且 images 命中时跑。
- **真实分钟数未测量**：没有推送，就没有 Actions 计时。只能给出「哪些 job 会被触发、跑在什么 runner 上」这一可核实的部分；**不得据此声称分钟数已验证**（属 TC-CBE-005）。

## 9. 独立入口真实执行 · 前半：两个状态敏感 selection（TC-TOR-004，**通过**）

**执行前说明**（SC-TOR-004 要求）：两条都由 `run-selection.mjs` **自建一次性 podman 实例**，跑完即释放；不连 `localhost:5432`、不操作旧 `multica-postgres` 容器。U5 已预授权一次性实例。执行前后各取一次容器清单。

| selection | 初始状态 | package / run | 命令 | 结果 |
|---|---|---|---|---|
| `channel-migration-down` | `648-down`（先 migrate up，再 apply `648_cr_execution_control.down.sql`） | `./internal/governance` / `^TestChannelMigrationAfterDown$` | `node scripts/aifi45-disposable/run-selection.mjs --selections scripts/aifi45-disposable/selections.json --only channel-migration-down --evidence-dir <本目录>/selection-down` | **PASS pass=22 fail=0 skip=0**，`ok=true`、`stage=test`、packages=1 |
| `channel-migration-reapply` | `648-down-up`（down 后再 up） | `./internal/governance` / `^TestChannelMigrationAfterReapply$` | 同上，`--only channel-migration-reapply --evidence-dir <本目录>/selection-reapply` | **PASS pass=15 fail=0 skip=0**，`ok=true`、`stage=test`、packages=1 |

- 实例 nonce：`2841871c7e35`、`60b25a7d67dd`；两条日志均以 `released instance … remaining=0` 结束（`selection-down.log`、`selection-reapply.log`）。
- `stage=test` 意味着 `go run ./cmd/migrate up` 先成功（exit 0）；初始状态由 runner 按名字 apply，**测试自身不跑 DDL**（`INITIAL_STATES` 是闭集）。
- **未传 `--admin-url`**（该 flag 被设计拒绝）；admin URL 只经 runner 内部传递。
- 事件流完整性逐行核对：down **92 事件 / 0 行不可解析**（start 1、run 22、output 46、pass 23 = 22 测试 + 1 包级）；reapply **64 事件 / 0 行不可解析**（start 1、run 15、output 32、pass 16）。
- **容器清单前后不变**：`inventory-before.txt` 与 `inventory-after-selections.txt` 都只有 `multica-postgres`、`multica-backend` 两个既有 **Exited** 旧容器；`final-inventory.txt` 收尾再核一次，仍相同，卷只有既有 `multica-pgdata`（未触碰）。
- **如实说明一处口径**：这两条 selection **未声明 `expected` 名单**，故 `reconciliation=null`——它们走的是 `decideSelection` 的 totals 判定，**没有 exercising S1 的逐名对账**。逐名对账由 S1 自己的用例与声明了 `expected` 的其他 selection 覆盖，不由本切片这两条冒领。
- **平台差异如实标注**：本机是 Windows + podman，**CI 是 ubuntu-latest**。这两条在 ubuntu 上的真实执行属 TC-CBE-005，未做。

## 10. 独立入口 · 后半：`TestChannelIsolation` 经 WSL AIFI-ISO —— **UNCOVERED（未覆盖，不得报通过）**

SC-TOR-004 明文：「任一项不能执行（如 WSL profile 失效）时 SHALL 如实列为未覆盖，**不得以同 uid 对照代替**」。本项**如实列为未覆盖**。

**只读探针**（`wsl-isolation-probe.txt`，2026-11-13T02:19:23+0800；U5 授权启动 WSL；**未安装、未创建、未修改任何东西**）：

| 探针 | 实测 |
|---|---|
| 身份 | `uid=0(root) gid=0(root)`——root 可用 |
| 内核 / 发行版 | `6.18.58.1-microsoft-standard-WSL2` / `Ubuntu 24.04.3 LTS` |
| **Go 工具链** | `command -v go` 空、`go version` → `command not found`；`/usr/local/go`、`/usr/lib/go*`、`/opt/go` 均不存在；maxdepth 4 搜 go 二进制**无结果** |
| **核准 profile 身份** | `getent passwd 995` **空**、`getent group 994` **空**。实际存在的只有 `aifi-svc` **1500:1500**、`aifi-agent` **1501:1501** |
| profile 根 | `/var/lib/aifi45/daemon-iso` **不存在**；`/var/lib/aifi45` 存在但**空**（目录日期 Nov 9） |
| 仓库 checkout | `/root/multica`、`/home/*/multica` **均不存在** |

**为什么不能跑**：`server/internal/daemon/execution_control_isolation_test.go` 是 `//go:build linux`，`requireIsolationProfile` 在没有核准 profile 时 **`t.Fatalf`**（不是 skip）。历史核准 profile 见 `archive/2026-10-27-trusted-verdict-channel/validation/iso-20261027T101534Z.meta.json`：`wsl2-aifi45-v1`、**uid 995 / gid 994**、root `/var/lib/aifi45/daemon-iso`、`go1.26.10`。当前 AIFI-ISO **四项前置全缺**（无 Go、无 995/994、无 profile 根、无仓库）。

**为什么不自行补齐**：安装 Go 工具链、创建 995/994 身份、建 profile 根、克隆仓库，**都超出 U5 的授权清单**（U5 只授权「启动 WSL AIFI-ISO」）。按用户「能力缺口先分析后动手」「范围外遗留项上报待定」的既定要求，**停在这里上报，不擅自扩范围**。

**为什么不用替代对照**：用现成的 1500/1501 或同 uid 跑一遍**不能证明隔离**——该测试的全部意义就是 worker 与 daemon 身份不同且由 root 拉起。SC-TOR-004 明文禁止这种冒充，**未做任何替代对照**。

**归属表已如实承载**：`test-ownership.json` 第 1 条 `owner=independent`、`entry=wsl -d AIFI-ISO, root, AIFI45_ISOLATION_PROFILE + AIFI45_ISOLATION_UID/GID/ROOT`，reason 写明「CI 无此 profile，整包跑会 fail 而非 skip，证明属 WSL 隔离入口」；`TestChannelIsolationChild` 在 allowed-skip 中标注为**源码推导而非基线观测**（Windows 基线根本没编译该文件）。`ci-evidence` rule 3 会核对该排除确实生效。

**恢复覆盖所需（待用户裁定，不在本 change 内自行执行）**：在 AIFI-ISO 内装 Go ≥ 1.26、按 `wsl2-aifi45-v1` 重建 uid 995 / gid 994 与 `/var/lib/aifi45/daemon-iso`、准备仓库 checkout，然后以 root + `AIFI45_ISOLATION_PROFILE` 等四个变量实跑并留证。

**WSL 状态无残留**：探针把 AIFI-ISO 从 Stopped 拉起为 Running；收尾 `final-inventory.txt` 复测已因 WSL 空闲超时**自动回到 Stopped**，与 `inventory-before.txt` 一致。

## 11. 安全边界逐条

| 边界 | 本切片的实际做法 |
|---|---|
| 不读取、不打印 PAT 或任何凭据 | 本地等价第 1 项用 `env -u AIFIRST_TOOLS_READ_TOKEN` 跑，**环境里根本没有凭据**；`ci.yml` 只把 secret 传给那一步的 `env`，诊断脚本自身保证不回显（S11 已 16 条变异证明）。**本切片未读取、未打印、未创建、未轮换任何凭据，未改仓库 secret** |
| 不连 localhost:5432 旧库 | **删除了 `backend-tests` 的 job 级 `DATABASE_URL`**，改名为 `AIFI45_CI_ADMIN_URL`。这不是改个名字好看：job 级 `DATABASE_URL` 会让任何漏配的一次性库步骤**静默连上旧库**。删除后，测试要连库只能由 `ci-provision up` 写入的 nonce URL 提供。已核 `up` 之前**没有任何步骤需要数据库** |
| 不操作旧 `multica-postgres` 容器 | 三次清单（前 / 后 / 收尾）都只有两个既有 Exited 容器，卷未触碰 |
| 不放宽 nonce 门禁 | `ci-provision.mjs` / `provision.mjs` **一行未改**；S6/S7 的门禁与逐条件用例原样 |
| 一次性实例必回收 | `down` 是 `if: always()` 的**最后一个数据库步骤**（其后还有上游 Prune/Save cache 两步，C1 更正措辞）；无 handle 时成功空转（§5 第 5 项实测） |
| 绿必须可信 | `ci-evidence` 在 `!cancelled()` 下跑（Test 红也要对账），缺流硬失败（§5 第 6 项实测）；`skip_regex` 取值失败即中止（§6 第 2 项实测） |
| 不夹带他人改动 | tools 仓未触碰（pin 仍 `e52b8081f159`，其既有未提交改动未清理未混入）；记录仓他人未提交改动未清理未混入；multica `git status --short` = **21 modified + 27 untracked**，全属本 change（C1 修复后为 **22 modified + 27 untracked**：新增 `approval_crosscheck_test.go` 一处修改，untracked 数不变） |
| 不提交 / 不推送 / 不部署 | 三者**均未做**。Gate 2 确认不推导 Git 授权 |

**一处必须上报的外部依赖**：pin `e52b8081f159d581bf62f82447c76f818fc52426` 是 tools 仓的**本地 HEAD**，`origin/main` 仍是 `f774ffb30770`（本地领先 1）。**该 commit 不在 origin 上**，所以 CI 的「Checkout the pinned tools contract revision」**会诚实失败**（拉不到这个 ref）。这是 U1 的路径 β：要么先把 tools 的那 1 个提交推上去（须单独授权），要么把 pin 改回 origin 上已有的 commit。**本切片不擅自推送、也不擅自改 pin**，如实列为未闭合前置。

## 12. 回归、静态检查与一处基线缺陷的定性

### 12.1 CRLF 挂钩（既有基线缺陷，非本切片引入）

`core.autocrlf=true` → multica 工作树是 CRLF，HEAD blob 是 LF。`ci-scope.test.mjs:208` 的跨行正则因此在 Windows 上**改前就是红的**（44/45）。按业务仓 `AGENTS.md`「对仓库文件做哈希、跨行正则或逐行解析的代码，读入后先将 `\r\n` 规范化为 `\n`」加 1 行 `// AIFIRST:` 挂钩，基线回到 45/45。**语义等价、不弱化断言**，且让该测试在 Linux CI 与 Windows 本地给出同一结论。已登记为设计偏离（见 `pending-adjustments.yaml`）。

顺带一条工具坑：**ripgrep 的 `$` 不匹配 `\r` 之前**，核对 CRLF 文件要用 `\r?$` 锚定（本切片用它才发现 `id: go` 在 backend-tests 与 backend-agent-tests 各有一处，从而把 Edit 锚在唯一的 `CRCTL_MJS` 行上）。

### 12.2 回归

| 范围 | 命令 | 结果 |
|---|---|---|
| harness 目录全量（接线前） | `node --test scripts/aifi45-disposable/*.test.mjs` | **171 tests / 171 pass / 0 fail / 0 skipped**，1939.3 ms（`harness-glob.txt`） |
| harness 目录全量（接线后） | 同上 | **171 / 171 / 0 / 0**，1935.7 ms（`harness-glob-after-wiring.txt`） |
| ci-scope 全量 | `node --test --test-reporter=tap scripts/ci-scope.test.mjs` | **49 / 49 / 0 / 0**，exit 0 |

harness 171 项与 S11 收尾**逐数相同**（本切片未改任何 harness 脚本，只改消费它们的 CI）。**注意 reporter 差异**：`node --test` 传多个文件时用 **spec reporter**（`ℹ tests 171`），单文件加 `--test-reporter=tap` 才是 TAP（`# tests`）；对账脚本两种都要解析，S11 曾因只解析 TAP 得出假结论，本切片沿用修正后的口径。

**Go 侧回归本切片未重跑**：S13 未改任何 `.go` 文件，S10 收尾的 handler / governance 整包逐名对账仍是最新证据；两条状态敏感 selection 在本切片**真实重跑并通过**（§9）。

### 12.3 静态检查

- `ci.yml` YAML 解析通过，17 job；`ci-paths.json` JSON 解析通过，8 scope。
- `node --check scripts/ci-scope.test.mjs` exit 0。
- 三个改动文件行尾：`ci.yml` / `ci-paths.json` / `ci-scope.test.mjs` 均**全 CRLF、裸 LF 0**（与各自 HEAD 一致，未引入混合行尾）。
- `git diff --check` 无空白错误。

## 13. 记账与四数基线

### 13.1 `CUSTOM.md`

- 新明细行 **#330**（第 1097 行，**2699 字符，7 个未转义竖线 / 6 单元格**，0 个转义竖线），覆盖 §2 全部五组挂钩点；「原因/追溯」引 Slice 13、SC-SEL-004/TC-SEL-004、SC-CBE-001/003/004 的 CI 侧、SC-TOR-001/002/003、design 决策 1/3/5/6/9 与 R1，并写明 bash -e 陷阱、`runBody` 的理由、3 条变异；「合并注意」写明**未验证/未完成**（TC-CBE-005 须推送；pin `e52b808` 不在 origin = U1 路径 β；TestChannelIsolation WSL 未覆盖）。
- M31 头（第 1080 行）→ `### M31 fork CI 与测试证据可信性修复（14 行：#317–#330）`。
- M31 汇总行（第 111 行）→ `#317–#330 | 14 |`，文件清单追加 `scripts/ci-scope.test.mjs`（并入 `scripts/{test-go.sh,test-go.test.sh,ci-scope.test.mjs}`）与 `.github/ci-paths.json`；**1557 字符 / 6 竖线 / 5 单元格**。
- **完整性实测**：全文件 **1098 行（1097 CRLF / 裸 LF 0）**；**#327 = 4987、#328 = 3304、#329 = 2524 字符，与改前逐字相同**；#317–#330 共 **14 行**，与头、汇总行的「14」一致。
- `git diff --numstat -- CUSTOM.md` = **21 / 1**，3 个 hunk：`+111`（M31 汇总行，HEAD 无此行）、`743→744`（**S8 对 #87 的补登，非本切片**）、`+1079,19`（M31 明细段）。1 + 1 + 19 = 21，算术自洽。

### 13.2 四数基线（ADJ-018 沿用，未自行补行）

按《核对命令》实测当前工作树：**611 文件 / 1678 命中行**，其中 `AIFIRST` **477 文件 / 755 行**——与 S10 实测**逐位相同**。

**S13 对四数贡献为 0，且这是可核实的**：本切片改的 4 个路径（`.github/*.yml`、`.github/*.json`、`scripts/*.mjs`、`CUSTOM.md`）**全部落在口径之外**（口径只扫 git 跟踪的 `server/` + `packages/` 下 `.go/.sql/.mjs/.ts/.tsx`）。`ci.yml` 的 `AIFIRST` 由 8 增至 19 **不计入**，与 2026-10-08 行的既有说明一致。

**仍不补基线表行**，理由沿用 ADJ-018：① 表最后一行是 2026-11-10（#312，596/1659/736/314），差值跨该日之后全部落码，不归本切片；② `git grep` 只计**已跟踪**文件，本 change 另有新增 `.go`/`.mjs` 未计入，提交后四数还会变；③ 第四数 `packages/` 的测量口径**未在《核对命令》中给出**，不臆造。**待用户裁定。**

## 14. B3.4 切片验证（三项如实记录）

1. **TC 覆盖 2/2**：
   - **TC-SEL-004**：锁定命令实跑，49/49 exit 0；新增表驱动行证明「仅改 harness → backend + scripts」，`scope-and-jobs.txt` 用真实 `ci-scope` 逻辑复核了反事实。
   - **TC-TOR-004**：**部分覆盖，如实拆分**。两个状态敏感 selection 实跑通过（22/0/0、15/0/0，命令 / 退出码 / 通过数均已记录）；`TestChannelIsolation` **UNCOVERED**（§10）。按 SC-TOR-004 的明文，「不能执行时如实列为未覆盖」本身就是该 TC 要求的处置，**故记为已按规格处置，但不记为「隔离性已验证」**。
2. **产出物核对**：slices.md 第 13 行要求的三项（`ci.yml` provision/evidence/script-checks 接线、`ci-paths.json` scope、独立入口真实执行）逐项存在；前两项由 49 项断言 + 3 条变异 + 7 项本地等价 + 2 项 fail-closed 实跑证明，第三项**只完成一半**。
3. **测试运行**：新增 **4 项 > 0 且全部通过**（1 个表驱动用例 + 3 个独立测试），ci-scope 49/49、harness 171/171 零回归。**无声明偏离**（与 S10 不同，本切片「新增测试全部通过」真实成立）。**但 Go 侧的 `TestChannelIsolation` 未跑，不计入通过数。**

## 15. 仍未验证 / 未完成（不得报通过）

1. **TC-CBE-005 真实 CI run 未执行**——须推送，Git 提交与推送**须单独授权**；17 个 job 的真实行为、真实分钟数、ubuntu 上的 selection 全部未验证。**不得声称 CI 已修好。**
2. **tools pin `e52b8081f159` 不在 `origin/main`**（U1 路径 β）——CI 的 pin 检出会诚实失败。推 tools 那 1 个提交或改 pin，**都须用户裁定**。
3. **`TestChannelIsolation` UNCOVERED**——WSL AIFI-ISO 无 Go、无 995/994、无 profile 根、无仓库；补齐超出 U5，未做替代对照（§10）。
4. **SC-CCF-003 未闭合**——管理员按最小权限更新 PAT，外部依赖；本 change 不读取/创建/轮换凭据。
5. **`ci-evidence` 与 `ci-provision` 的真实 CI 端到端未跑**——本地只逐项等价验证了各步骤的命令与退出码，**没有把整条 job 串起来跑过**。
6. **ADJ-005（major）仍未决**——tools `rules.json` 的 `show` 形状缺口。已核实 `MULTICA_CONTROLLED_SHELL_RULES` **不在 canonical / design 中**，故不是锁定要求，本切片**未设该变量**；仍待用户裁定。
7. **ADJ-018 四数基线欠债待裁定**（§13.2）。
8. **ADJ-019（S12 新增测试数 0）、ADJ-020（views load flake）** 沿用未决。
9. **`make test` 未执行**（U5 排除旧容器与 localhost:5432）。
10. **Gate 3 未推进**——须另经用户明确确认，AI 不得自跑 approve。

## 16. 复现命令

```bash
cd "C:/Users/GOBAO/Downloads/AI/multica"

# TC-SEL-004 锁定命令（49/49）
node --test --test-reporter=tap scripts/ci-scope.test.mjs

# harness 目录全量（171/171，spec reporter）
node --test scripts/aifi45-disposable/*.test.mjs

# 本地等价（凭据从环境剔除，不读取任何真实凭据）
env -u AIFIRST_TOOLS_READ_TOKEN node scripts/aifi45-disposable/tools-access.mjs   # exit 1 missing
node scripts/aifi45-disposable/tools-pin.mjs read --pin .github/aifirst-tools-pin
node scripts/aifi45-disposable/test-ownership.mjs skip-regex
node scripts/aifi45-disposable/test-ownership.mjs check                          # exit 0
node scripts/aifi45-disposable/ci-provision.mjs down                             # exit 0 空转

# 两个状态敏感 selection（各自建/释放一次性 podman 实例；前后核对 podman ps -a）
node scripts/aifi45-disposable/run-selection.mjs \
  --selections scripts/aifi45-disposable/selections.json \
  --only channel-migration-down --evidence-dir <evidence>/selection-down
node scripts/aifi45-disposable/run-selection.mjs \
  --selections scripts/aifi45-disposable/selections.json \
  --only channel-migration-reapply --evidence-dir <evidence>/selection-reapply

# 四数基线（《核对命令》原文）
git grep -cE "AIFIRST|CR-2026-[0-9]{3}" -- 'server/**/*.go' 'server/**/*.sql' 'server/**/*.mjs' 'packages/**/*.ts' 'packages/**/*.tsx' 'packages/**/*.mjs' | awk -F: '{n++; s+=$NF} END {print n" 文件 / "s" 行"}'
```

## 17. 证据清单（本目录）

| 文件 | 内容 |
|---|---|
| `red-ci-scope.txt` / `green-ci-scope.txt` | 13.1 RED 47/45/2 → 13.2 GREEN 47/47/0 |
| `red-backend-wiring.txt` / `green-backend-wiring.txt` | 13.3 RED 49/47/2 → GREEN 49/49/0 |
| `harness-glob.txt` / `harness-glob-after-wiring.txt` | 接线前后各 171/171/0/0 |
| `local-step-equivalence.txt` | §5 的 7 项，含命令输出与退出码 |
| `local-ownership-check.txt` | 归属表 5 条全文 + 4 条 allowed-skip + exit 0 |
| `script-checks-pg-fetch-fails.txt` / `script-checks-version-read-fails.txt` | §6 两条 fail-closed 实跑 |
| `mutation-wiring.txt` | §7 三条变异 + 逐字节还原 sha256 |
| `scope-and-jobs.txt` | 48 文件 → 8 scope、反事实 backend+scripts、17 job 的 runner 与条件 |
| `selection-down/` `selection-down.log` | down 的 JSON 结论 + 92 事件 ndjson + PASS/released 日志 |
| `selection-reapply/` `selection-reapply.log` | reapply 的 JSON 结论 + 64 事件 ndjson + PASS/released 日志 |
| `inventory-before.txt` / `inventory-after-selections.txt` / `final-inventory.txt` | 三次容器 / 卷 / WSL 清单 |
| `wsl-isolation-probe.txt` | §10 只读探针全文与探针后 WSL 状态 |
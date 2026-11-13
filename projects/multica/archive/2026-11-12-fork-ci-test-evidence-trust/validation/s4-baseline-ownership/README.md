# Slice 4 证据 — 整包基线与测试归属表（TC-TOR-001）

> change：`2026-11-12-fork-ci-test-evidence-trust`｜执行时间：2026-11-12 本地｜Node v24.15.0｜Windows
> 数据库验证只经 `run-selection.mjs` 自建的一次性 podman 实例（TTL ≤3600s）；
> 未连接 localhost:5432，未操作 `multica-postgres`，未读取或打印任何凭据值。

## 产出物

| 文件 | 性质 |
|---|---|
| `scripts/aifi45-disposable/selection-evidence.mjs` | 新增，把原始 `go test -json` 流与结论落盘（`writeSelectionEvidence`） |
| `scripts/aifi45-disposable/selection-evidence.test.mjs` | 新增，2 项测试 |
| `scripts/aifi45-disposable/run-selection.mjs` | 修改，新增 `--evidence-dir`；`runSelection` 改为返回 `{result, ndjson}` |
| `scripts/aifi45-disposable/run-selection.test.mjs` | 修改，追加 2 项参数边界测试（原 11 项未动） |
| `scripts/aifi45-disposable/selections.baseline.json` | 新增，5 个整包 selection |
| `scripts/aifi45-disposable/test-ownership.mjs` | 新增，`check` / `skip-regex` 两个命令 + `skipRegex` / `hasTestFunc` 导出 |
| `scripts/aifi45-disposable/test-ownership.test.mjs` | 新增，16 项测试 |
| `scripts/aifi45-disposable/test-ownership.json` | 新增，`required-packages` 5 + `entries` 4 + `allowed-skips` 4 |

`run-selection.mjs` 是 fork 独有文件，改动为直接修改（非上游挂钩）；新增文件均带 `// AIFIRST:` 英文注释。
CUSTOM.md 登记为 M31 第 **#320** 行。

## 为什么需要 `--evidence-dir`

改前 runner 只打印一行结论，`-json` 流被丢弃，因此"每个失败的原因、每个 skip 的理由、
每个测试的耗时"都无法事后取证 —— 而归属表要求**每项排除都带证据**。
新增参数把原始流与结论同时落盘，基线一次运行即产出 10 个证据文件。

## RED

| 对象 | RED 方式 | 结果 | 文件 |
|---|---|---|---|
| `--evidence-dir` 参数 | 实现前跑 runner 用例 + 新 evidence 用例 | 14 tests / 12 pass / **2 fail**：`not ok 12 --evidence-dir requires a value…`（参数未被拒）与 `not ok 2 selection-evidence.test.mjs`（模块不存在） | `red-evidence-dir.tap` |
| 归属表检查器 | 检查器不存在时跑其用例文件 | 文件级加载失败：`ERR_MODULE_NOT_FOUND: …test-ownership.mjs`，1 tests / 0 pass / **1 fail** | `red-test-ownership.tap` |
| manifest 缺口（S8 的 RED） | 真实基线 | `TestWorkspaceDeletionManifestCoversPublicSchema` 失败，列出 19 张未分类 `cr_execution_*` 表 | `events/baseline-handler.ndjson` |

**如实记录一处弱 RED**：`--evidence-dir with a value is accepted` 用例在实现前**即通过**，
因为 `parseArgs` 对未知参数静默忽略（不报错）。该用例只能证明"不拒绝"，不能证明"会写盘"。
正向写入路径改由**真实基线运行产出 10 个证据文件**证明（`events/` 下 5 个 `.ndjson` + 5 个 `.json`）。
`parseArgs` 静默接受未知参数本身是范围外发现，已上报，未擅自修改。

## GREEN

| 命令 | 退出码 | tests | pass | fail | skipped | 文件 |
|---|---|---|---|---|---|---|
| `node --test --test-reporter=tap scripts/aifi45-disposable/selection-evidence.test.mjs` | 0 | 2 | 2 | 0 | 0 | `green-evidence-dir.tap` |
| `node --test --test-reporter=tap scripts/aifi45-disposable/test-ownership.test.mjs` | 0 | 16 | 16 | 0 | 0 | `green-test-ownership.tap` |
| `node scripts/aifi45-disposable/test-ownership.mjs check` | 0 | — | — | — | — | `real-ownership-check.txt` |
| `node scripts/aifi45-disposable/test-ownership.mjs skip-regex` | 0 | — | — | — | — | 同上 |
| `node --test --test-reporter=tap "scripts/aifi45-disposable/*.test.mjs"`（全量回归） | 0 | **106** | **106** | **0** | **0** | `regression-directory.tap` |

真实表检查输出：`test ownership OK: 4 entry(ies)` + `allowed skips: 4`。
排除正则：`^(TestChannelIsolation|TestChannelMigrationAfterUp|TestChannelMigrationAfterDown|TestChannelMigrationAfterReapply)$`

> Windows Node 24 上 `node --test <目录>` 会 `MODULE_NOT_FOUND`，必须用上面的 glob 形式。
> S13 的 CI 步骤沿用 glob 形式。

## 变异验证（检查有牙，不空转）

| 变异 | 期望 | 实测 | 文件 |
|---|---|---|---|
| 把 `TestChannelMigrationAfterUp` 改成 `TestChannelMigrationAfterUpX` | exit 1，点名拼错的项 | exit 1，`1 problem(s) in 4 entry(ies) and 3 allowed skip(s)` | `mutation-typo-entry.txt` |
| 删掉一条 `allowed-skips` 声明 | 钉住用例失败 | 1 test / 0 pass / **1 fail**（`deepStrictEqual` 名单不符） | `mutation-allowed-skip-pin.txt` |

第二个变异在**真实表**上就地施加，`finally` 中按原字节还原，
sha256 前后一致（`8a3da004…bea1ae`），工作区未被留下改动。

精度测试另覆盖：`TestAlphaExtended` 不满足 `TestAlpha`（整名匹配）、
正则元字符转义（`TestA.B` / `TestC+D` / `TestE(x)`）、CRLF 归一化、
`""`/`null`/`undefined`/`42` 输入 `throw`（硬失败，不静默返回空）、
空/坏 JSON 对**两个命令**都硬失败、缺目录或包内无 `*_test.go` 时报"无法核实"而非放行。

## 整包基线（真实运行）

5 个 selection 各用独立一次性数据库，合计 **8645 pass / 75 fail / 135 skip**，runner exit 1。
容器纪律：前后 `podman ps -a` 去表头后逐字节相同，`multica-postgres` / `multica-backend` 全程 Exited，
卷 `multica-pgdata` 未触碰，结束 `released instance 48d027ce582a remaining=0`。

**逐项分类见 `baseline-findings.md`**（29 个顶层失败 / 75 帧，135 个 skip 事件 / 129 顶层）。
要点：

- 只有 **A 类 3 个状态敏感迁移探针**进入 CI 排除，且三者在各自独立入口下已实测 PASS
  （up 19 / down 22 / reapply 15，0 fail 0 skip，`independent-entries.txt`）。
- **B 类 2 个 handler 唯一键冲突是 Windows 时钟粒度**（`UnixNano` 探针 199996/200000 连续相同），
  不是常量 id 缺陷，**不排除**。
- **D 类 6 个 daemon 失败是跨仓 tools 契约缺口**（`rules.json` 的 `show` 白名单未授予
  `test-report.md` / `trace.tests*` / `--name-only --format=`），CI 目前被内联 fixture 掩盖；上报待裁定。
- **E 类 16 个 Windows-only**（POSIX exec stub、JSON 未转义、路径分隔符、真实 %APPDATA%、
  文件占用、MAX_PATH），CI-linux 预期通过，**不排除**。
- **F 类 1 个未定性**（`TestHandleRuntimeGone_…` register 次数），证据不足，**不排除**，待真实 CI 观察。
- skip 中 **46 个是 `REDIS_TEST_URL not set`**（CI 有 Redis，会跑）、**86 个是平台守卫**（Linux 会跑），
  均不声明；只声明 3 个基线观测项 + 1 个源码推导项。

## 未验证项（如实记录，不 skip、不报绿）

1. **`allowed-skips` 只是下界**：由 Windows 基线 + 源码守卫推导，CI-linux 的真实 skip 集合
   必须由 **TC-CBE-005（真实 CI 运行）** 最终确认。S5 的对账会把名单外 skip 判失败，使漏声明可见。
2. **S3 改后守卫的运行时行为仍未观测**：基线运行时本机 `AIFI45_TOOLS_ROOT` / `CRCTL_MJS` 存在，
   4 处守卫未被触发（governance 的 48 个失败全部来自 3 个迁移探针）。
   "缺变量时真的 Fatal 而不是 skip" 需在**变量缺失**的一次性实例下运行，**推迟到 S7**。
3. **`TestChannelIsolation` 与 `TestChannelIsolationChild` 未在 WSL 实跑**（TC-TOR-004，manual，
   依赖 `wsl -d AIFI-ISO` + 获批 profile）；本切片只依据源码守卫声明排除。
4. **未执行 `make test`**（U5 排除：会启动旧 `multica-postgres`、连 localhost:5432）。
5. **未执行真实 CI run**（依赖推送，Git 提交与推送须另行取得授权）。
6. **D 类 6 项与 F 类 1 项在 CI-linux 上的真实结论未知**，未以任何方式推定为通过。

## 范围外发现（上报，不擅自修改）

见 `baseline-findings.md` 第 5 节，共 7 项：tools `show` 形状缺口、
`writeTestClaudePlugin` JSON 未转义、DSH 测试读真实 %APPDATA%、
`TestHandleRuntimeGone_…` 未定性、`parseArgs` 静默接受未知参数、
S3 遗留 5 个 governance skip、handler fixture 依赖 `UnixNano` 唯一性
（**S9 生成随机唯一键时不得沿用 `UnixNano`**，本机已证伪）。
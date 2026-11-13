# Slice 5 证据 — test-go.sh 证据参数与 CI 事件流对账（TC-TOR-002、TC-TOR-003）

> change：`2026-11-12-fork-ci-test-evidence-trust`｜执行时间：2026-11-12 本地｜Node v24.15.0｜Windows
> **本切片未运行任何数据库**：不新建 podman 实例、不连接 localhost:5432、不操作 `multica-postgres`。
> 真实数据对账复用 S4 已落盘的 5 个基线事件流，因此容器清单无需前后核对（未发生容器操作）。
> 未读取或打印任何凭据值；未提交、未推送。

## 产出物

| 文件 | 性质 |
|---|---|
| `scripts/test-go.sh` | 修改（**上游文件**），3 处 `# AIFIRST:` 挂钩：`--skip-regex`、`--json-out`、`run_go_test` 包装 |
| `scripts/test-go.test.sh` | 修改（**上游文件**），假 `go` 增加输出/退出码注入 + 8 个新用例（4 行为 + 4 usage 拒绝），原有用例未动 |
| `scripts/aifi45-disposable/ci-evidence.mjs` | 新增，`reconcileCiEvidence` 四条规则 + `--stream/--table` CLI |
| `scripts/aifi45-disposable/ci-evidence.test.mjs` | 新增，22 项测试 |
| `scripts/aifi45-disposable/test-ownership.json` | 沿用 S4，`required-packages` 5 项即本切片的必需包声明（未改） |

不带新参数时 `test-go.sh` 的调用与改前逐字节一致：`pipefail` 只在 `--json-out` 分支内开启，
`-json`/`-skip` 只在对应参数非空时追加。CUSTOM.md 登记为 M31 第 **#321** 行。

## RED

| 对象 | RED 方式 | 结果 | 文件 |
|---|---|---|---|
| `--skip-regex` / `--json-out` | 实现前跑 `bash scripts/test-go.test.sh` | 前 3 项既有用例 PASS，随后 `--skip-regex returned 2, want 0`，usage 行仍是上游原文（无新参数） | `red-test-go.tap` |
| `ci-evidence.mjs` | 实现不存在时跑其用例文件 | 文件级加载失败 `ERR_MODULE_NOT_FOUND: …ci-evidence.mjs`，1 tests / 0 pass / **1 fail** | `red-ci-evidence.tap` |

## GREEN

| 命令 | 退出码 | tests | pass | fail | skipped | 文件 |
|---|---|---|---|---|---|---|
| `bash scripts/test-go.test.sh` | 0 | — | — | — | — | `green-test-go.tap` |
| `node --test --test-reporter=tap "scripts/aifi45-disposable/ci-evidence.test.mjs"` | 0 | 22 | 22 | 0 | 0 | `green-ci-evidence.tap` |
| `node --test --test-reporter=tap "scripts/aifi45-disposable/*.test.mjs"`（目录全量回归） | 0 | 128 | 128 | 0 | 0 | `regression-directory.tap` |

`green-test-go.tap` 内容为 `TC-TWG-001/003/002: PASS` + `TC-TOR-002: PASS` + `test-go.test.sh: PASS`：
三个既有守卫用例与全部上游用例（默认、`--only`、`--race`、参数顺序、usage 拒绝、`go list` 三种模式）均未回归。
目录回归 128 = S4 结束时的 106 + 本切片 22。

> Windows Node 24 上 `node --test <目录>` 会 `MODULE_NOT_FOUND`，必须用上面的 glob 形式。

## 变异验证（证明守卫真的有牙）

### test-go.sh：pipefail 退出码透传

去掉 `--json-out` 分支里的 `set -o pipefail` → `--json-out returned 0, want go test's 3`
（假 `go` 退出 3，脚本却报 0，事件流仍落盘）。恢复后 sha256 前后一致：
`fcf6d3253e6e291557aef6f1f6231abd916158ef5d0b65d4a826800f4be87ebd`。见 `mutation-pipefail.txt`。

### ci-evidence.mjs：9 条守卫逐条中和

每条守卫单独改成恒假（解析硬失败改成 `continue`，即 AGENTS.md 禁止的静默降级），
跑全量用例，要求变红，然后按原始字节恢复并核对 sha256。

| 守卫 | 结果 | 变红用例数 |
|---|---|---|
| rule1 必需包 0 个通过测试 | DETECTED | 2 |
| rule1 必需包包级结论必须 pass | DETECTED | 1 |
| rule1 必需包在流中完全无事件 | DETECTED | 1 |
| rule1 必需包名匹配到两个包（歧义不得静默取一） | DETECTED | 1 |
| rule2 名单外 skip | DETECTED | 4 |
| rule3 排除项出现在流中 | DETECTED | 3 |
| rule4 最后一个事件必须是包级结论 | DETECTED | 1 |
| rule4 每个出现过的包都必须有结论 | DETECTED | 1 |
| rule4 逐行解析失败必须硬失败 | DETECTED | 3 |

`sha256 before = after = ebcb1b4bc2dcbd26fc3ba954e93aedcb1daa50dc46226a48cebff702ea4d5cd2`。
见 `mutation-rules.txt`。

**如实记录：第一轮探针发现一处真实覆盖缺口。** 当时 21 项用例下
「rule4 每个包都必须有结论」**NOT DETECTED**（exit=0 pass=21 fail=0）——
原用例只删掉必需包 handler 的结论，rule 1 已先判红，该守卫从未被单独压住。
处置：新增第 22 项用例，让**非必需包** `./internal/daemon` 有 start/run/pass 但无包级结论，
且最后一个事件仍是 handler 的包级 pass，断言 `problems` 恰好等于那一条。
补入后重跑 → 9/9 DETECTED。第一轮原始输出逐字保留在 `mutation-rules-first-pass.txt`。

## 真实基线对账（不是构造数据）

用 S4 落盘的真实 `go test -json` 流 + 仓库内真实归属表跑 CLI，输出见 `real-baseline-reconcile.txt`。

| 输入 | 字节 | 退出码 | 结论 |
|---|---|---|---|
| `baseline-governance.ndjson` | 1478424 | 1 | 8 problems |
| `baseline-crosslang.ndjson` | 22438 | 1 | 4 problems |
| `baseline-cmd-server.ndjson` | 981059 | 1 | 4 problems |
| `baseline-handler.ndjson` | 4718132 | 1 | 51 problems |
| `baseline-daemon.ndjson` | 3054661 | 1 | 91 problems |
| **5 个流按 CI 方式拼接**（`--json-out` 两半追加到同一文件） | 10254714 / 40390 events | **1** | **138 problems** |
| 正向对照：crosslang，`required-packages` 收窄为该包 | 22438 | **0** | `ci evidence OK: 1 required package(s), 4 declared skip(s)` |
| 正向对照：cmd-server，同上 | 981059 | **0** | 同上 |

单包流各报 4 个「no events in the stream」是**正确行为**：检查器面向整份 CI 流，
声明的 5 个必需包必须全部出现。拼接流不再报缺包，只剩真实问题：

- **3 条**包级结论为 fail（governance / handler / daemon）——对应 S4 定性的 75 个真实失败；
- **132 条**名单外 skip——即 S4 明确**不声明**的 46 个 `REDIS_TEST_URL not set` 与 86 个平台守卫。
  CI-linux 有 Redis 且非 Windows，这些 skip 本就不该发生，因此**不得**为了让本地变绿而把它们塞进允许名单；
- **3 条**排除项仍出现在流中（3 个 `TestChannelMigration*`）——基线是不带 `-skip` 跑的，正好证明 rule 3 能抓到「排除没生效」。

两个正向对照用的是**真实全绿包**（crosslang 19 pass / 0 fail / 0 skip，cmd-server 659 pass / 0 fail / 0 skip），
证明检查器不是恒红。拼接流未写入记录仓（10MB，与已存 5 个流重复），只在临时目录生成。

## 未验证 / 范围外（不得记为通过）

1. **`TestChannelIsolation` 的 rule 3 覆盖在本机无法验证**：`execution_control_isolation_test.go` 是
   `//go:build linux`，Windows 基线根本没编译它，5 个流中 `TestChannelIsolation` 与
   `TestChannelIsolationChild` 的事件数均为 **0**（已逐流核对）。该排除项与其允许 skip 的依据是
   源码（build tag + `t.Fatalf`/`t.Skip` 守卫），不是基线观测；归属表 reason 已如实写明。
   真实验证只能落在 CI-linux（TC-CBE-005）与 WSL 独立入口（TC-TOR-004）。
2. **132 条名单外 skip 只是本机下界**：CI-linux 的真实 skip 集合要等一次真实 CI run 才能定，
   允许名单在此之前不得视为完备。
3. **`quality.test`（`make test`）本切片未执行**：属 U5 范围外的整仓命令，留待 Part C 统一处置。
4. **S3 改动的 4 个 runtime 守卫仍未在「环境变量缺失」下实跑验证**（S4 基线带着这些变量，守卫没触发），
   仍挂在 S7。
5. 本切片未接线 CI：`ci.yml` 目前只有 S2 的 tools pin 改动，`--skip-regex`/`--json-out`/`ci-evidence.mjs`
   的接线属 S13。

## 证据文件索引

| 文件 | 内容 |
|---|---|
| `red-test-go.tap` / `green-test-go.tap` | 上游 shell 用例的 RED / GREEN |
| `red-ci-evidence.tap` / `green-ci-evidence.tap` | 对账器的 RED / GREEN（22 项） |
| `regression-directory.tap` | `scripts/aifi45-disposable/*.test.mjs` 全量 128/128 |
| `mutation-pipefail.txt` | pipefail 变异 + sha256 复原核对 |
| `mutation-rules-first-pass.txt` | 第一轮探针原始输出（含 NOT DETECTED 缺口） |
| `mutation-rules.txt` | 补入第 22 项后 9/9 DETECTED + sha256 复原核对 |
| `real-baseline-reconcile.txt` | 5 个真实单包流 + 拼接流 + 2 个真实正向对照 |
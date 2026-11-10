# NTF-003 TAB：仅编译预检与阻塞交接（2026-10-31）

**时序说明**：本报告有关「未执行公开 API 二进制」及环境状态是预检时记录；此后旧/新二进制和整包已执行，独立审查发现隔离证明缺口，不能作为合规验收，详见 [隔离复核](../notice-tab-isolation-20261031/ISOLATION-REVIEW.md)。执行计划以该复核的暂停条件为准。

## 结论

**局部函数快照 RED→GREEN 已完成；公开 API RED、GREEN 和同包回归仍 BLOCK。** 原编译预检时只完善真实公开 API 测试并离线编译；随后按 [切片计划](../notice-tab-guard-slice-plan.md) 调整验证顺序，在生产守卫增加五种 TAB 模式。不能计 TC-NTF-003、X6、广播/DB 或 Gate3 通过。没有建立或验证 OS 隔离，也没有取得覆盖完整依赖初始化的独立安全结论；不得直接运行已生成的公开 API 测试二进制，包括 `-test.list`。

用户已授权必要命令及全新独占离线隔离环境/disposable PG，但并未因此证明任何具体环境安全。本执行者未调用容器引擎、WSL、数据库或历史 DB runner；未访问凭据、真实 CR、现有 DB/容器/卷，未安装/下载、提权、提交、推送、部署或审批。没有接管另一执行者的环境工作。

## 本轮改动（保留原有脏改）

- `multica/server/internal/governance/noticeguard_test/execution_notice_test.go`：仅改 `TestNoticeRejectsTabbedExistingCommands`。
  - 五个既有命令 × 两个字段/受众组合维度（共四种字段位置）× 空格/TAB 的矩阵，现分开 `build` / `deliver` 子例，保留明确命令错误及零返回断言。
  - TAB 矩阵不再捕获 nil-pool panic。`DeliverNotice(..., nil pool, event, nil broadcaster)` 若漏过 Build 命令守卫，会在现有 broadcaster 检查处返回可诊断错误；普通输入对照要求 `notice broadcast is required`。因此可区分命令校验缺口与后续错误，而不是用 nil pool 假红。该断言仅验证前置校验顺序，不验证真实 DB 或广播。
  - 超长 TriedPaths 的命令优先级扩展到 authorizer / maintainer，命令仍在非首项；前者旧行为接受、后者旧行为 VERBATIM 的差异仅是静态推断，未实测。
  - 补字面反斜杠 t 和命令名后仅尾随 TAB/空白的接受边界，保留普通 TAB、长度优先级、标识/渲染字段优先级、静默和多 TAB/换行对照。不声称是完整 shell 解析器。
- `multica/CUSTOM.md`：仅更新现有追加表的 **#285**，沿用当前列结构与稳定编号；追溯 AIFI-45 原 STDD tasks 3.1 / SC-NTF-003，不新造 CR/TASK、不改其他登记。
- 随后对 `execution_notice.go` 仅增加五个 TAB 匹配项；快照函数 RED/GREEN 结果见下，不把原仅编译的预检说成业务测试。
- 平台侧更新 `notice-tab-guard-slice-plan.md`，在旧静态审阅顶部注明其计数、哈希不覆盖本轮增量。独立只读复核 session `01a18f8e-9853-7468-8217-4b0f4e8de346` 对照当前测试及生产路径未发现阻塞性断言缺陷；requested=`GBClaude/claude-opus-5-5:high`（plan 配置），actual 后端无回执、记 unknown。该复核只作静态意见，不是实际 RED/GREEN 或完整 TC。

## 实际运行的检查

| 检查 | 实际结果 | 证明边界 |
|---|---|---|
| 固定本机 `gofmt.exe -d` 目标测试文件 | exit 0，无格式差异 | 解析/格式，不是编译或测试 |
| `node --check notice-tab-guard-preflight.mjs` | exit 0 | 仅预检脚本语法 |
| 本机 `go version` | exit 0，Go 1.27.1 windows/amd64 | 未使用自动 toolchain 下载 |
| `go list -deps -test -json ./internal/governance/noticeguard_test` | exit 0；491 包 / 251 非标准库包 | 依赖元数据，不运行目标 init 或 TestMain |
| `go test -c -vet=off -o <本轮新目录>/noticeguard.test.exe ./internal/governance/noticeguard_test` | exit 0 | 真实源码与依赖编译成功；**未执行**产物、依赖 init、测试或 vet |
| 指定三个拥有文件的 `git diff --check` | exit 0 | 不包含未跟踪测试文件；该文件由 gofmt 独立核对 |

精确 argv、退出码及时间见 [preflight.json](preflight.json)，stdout/stderr 均保存。仅编译脚本为同级 `../notice-tab-guard-preflight.mjs`，只用 Node 内建模块与固定本机 Go 工具。

Go 进程使用显式白名单环境，不继承宿主环境；`GOENV=off`、`GOWORK=off`、`GOTOOLCHAIN=local`、`GOPROXY=off`、`GOSUMDB=off`、`GOTELEMETRY=off`、`CGO_ENABLED=0`、`GOFLAGS=-mod=readonly`。HOME/TEMP/GOCACHE/GOPATH 均位于本轮新建独占目录，module cache 指向本机已有依赖。该目录保留产物和 cache，未清理任何既有资源；二进制未复制入仓。

**最小环境与独占目录不是 OS 隔离**，不允许据此运行测试。`parentGovernanceImportedWithoutTestVariant=true` 仅表示没有编入父包测试变体，不表示 governance 和第三方 init 安全。

## 冻结材料与初始化风险

| 源码（UTF-8，先 CRLF→LF，再 SHA-256） | SHA-256 |
|---|---|
| `execution_notice.go` | `9be5120bef4fb80ab2b4973c44cd0c032d7c43ca6406969297f255d0843611db` |
| `noticeguard_test/execution_notice_test.go` | `c6981fa9ba09296c174b426fae349c3b8c4bc4dec7e681167227a440f239c152` |

生产文件哈希与先前静态审阅记录一致；两文件编译前后哈希均相等。本轮快照见 `source/`（含 go.mod/go.sum）；其路径只是保存材料，不是替代产品包测试入口。

- [dependency-source-manifest.json](dependency-source-manifest.json)：251 个非标准库包条目，1813 个选中文件条目（含不同测试变体的重复条目及合成 test main），保存 import edges 与规范化源码哈希；不是 1813 个独立初始化点。此清单在编译前读取，不是整个并发脏工作区的原子快照；仅两个本轮拥有文件做了编译前后校验。独立安全审核/执行前仍须冻结并核对完整实际依赖。
- [explicit-init-candidates.json](explicit-init-candidates.json)：正则定位 39 个显式 init 候选文件，包括第三方库及 realtime/metrics/redact。**可能有注释误命中，也遗漏包级变量初始化、间接调用和标准库副作用；不是安全审计。**
- [deps.stdout](deps.stdout)：完整 Go 元数据，可用于核对平台、build tags 和选中文件。仅本轮 Windows/amd64、CGO=0 配置有效；换平台或源码后必须重取图和安全结论。
- [artifact-hashes.json](artifact-hashes.json)：编译时记录的元数据/输出清单哈希；不充当独立签名或批准。

独立静态复核提示：长度例使用 `x…sudo`，依赖现有子串匹配而非单词边界；nil-broadcast 例当前安全到达前置错误，但未来如果 DB 检查顺序改变可能 panic；尾随 TAB 的接受例固定了现有修剪行为。该切片不覆盖 `\t&&\t`、NBSP 或完整 shell 语法。上述均不是实际运行结果。

## 生产守卫函数快照 RED→GREEN

`guard-snapshot-run.mjs` 从生产源文件唯一注释锚点原样提取函数，在 `mkdtempSync` 独占目录组装 `guard-snapshot_test.go`；采用显式无凭据环境、禁用 CGO / 网络依赖和用户 go.env、仅 Go 标准库的构建图。运行器独立只读安全审核 `01a18f9b-7fd7-7468-8217-4b1c2c113f83` 未发现阻断；actual backend 无回执、记 unknown。无 OS 沙箱或网络系统级阻断，标准库 init 有执行。脚本不清理资源；完整 NDJSON 与依赖输出既保留在下列本轮新建目录，也已无覆盖地归档为同级 [RED](guard-red.ndjson)、[GREEN](guard-green.ndjson)、[RED 依赖](guard-red-deps.txt)、[GREEN 依赖](guard-green-deps.txt)。

| 阶段 | 测试退出 | 父/子 run | pass | fail | skip | 源文件 LF SHA-256 | 片段 LF SHA-256 | 临时证据目录 |
|---|---:|---:|---:|---:|---:|---|---|---|
| RED | 1 | 19 | 13 | 6 | 0 | `9be5120bef4fb80ab2b4973c44cd0c032d7c43ca6406969297f255d0843611db` | `fcdafa43a90df2ff87516be6a6e749faffc3ad85c1a4e88b4dae7b16643dafb6` | `C:\Users\GOBAO\AppData\Local\Temp\aifi45-guard-5RVLk2` |
| GREEN | 0 | 19 | 19 | 0 | 0 | `9557407af61b2d8c8a3b11a42cfbfa2827cb887573f7a481b10ae6191453a24f` | `5282810752d898e103c06a6a1babbb2e7dd4f1e3046303acd06d6c3e70f923f2` | `C:\Users\GOBAO\AppData\Local\Temp\aifi45-guard-KGfwPY` |

RED 的六个失败事件正好是五个 `tab_*` 子测试和父测试；空格对照与普通 TAB、既有 shell chain、Unicode 行分隔符等正反控通过。两次测试源码 LF SHA-256 均为 `f575a70ab6af7ca58cc068371fb9356af8a26ac82a4d9b545c1296546d28e80f`，测试前后目标源与测试内容未变。匹配仍是既有子串语义：如 `mydocker\tx` 现在会拒绝；命令名后的单独尾随空白仍被 `TrimSpace` 去除。该证据不执行真实 `BuildNotice`/`DeliverNotice`，不代表公开入口测试或完整 TC。

修复后再次用原受控编译预检入口在新建目录 `C:\Users\GOBAO\AppData\Local\Temp\notice-tab-green-compile-7ee87953a3eb9af3a52eec35` 对真实 `noticeguard_test` 执行 `go list -deps -test` 和 `go test -c -vet=off`：均 exit 0，未运行测试二进制。源码和测试 LF 哈希分别为 `9557407af61b2d8c8a3b11a42cfbfa2827cb887573f7a481b10ae6191453a24f`、`c6981fa9ba09296c174b426fae349c3b8c4bc4dec7e681167227a440f239c152`，编译前后未变；二进制 SHA-256 `2121e80bb9864176648eec7d4d6c5cafb156e897d8aa3b7c56550455971f2427`。两次非标准依赖清单均为 1813 个文件条目、251 个包，包导入图相同；除目标 `execution_notice.go` 外内容哈希相同，合成 test main 的 cache 绝对路径不同但内容哈希相同。清单在编译前生成、仅目标两文件核编译前后，不能证明所有依赖是原子冻结快照；该编译仍不是公开 API RED/GREEN。旧版冻结源码 `source/execution_notice.go` 与当前源码按 LF 规范化后逐字比较，差异仅为该列表增加五个 TAB 模式；当前生产源码 `gofmt -d` exit 0 且无差异，目标文件和 CUSTOM 的 `git diff --check` exit 0。

## 解除阻塞后的顺序（尚未执行）

1. 由环境执行者交付可验证、全新独占、无外网且无法接触既有 DB/容器/卷/凭据的 OS 隔离证据；或者取得绑定实际工具链、完整选中文件及初始化/测试入口的充分独立安全审核。仅环境变量、依赖计数、无 DB fixture 或本报告不足以放行。
2. 在该安全环境中，先核验并运行修复前保留的公开 API 测试二进制 `noticeguard.test.exe`，其编译记录为旧源码 LF SHA `9be5120b…`、测试源码 `c6981fa9…`、二进制 SHA `a2a59176…`；用 `-test.run '^TestNoticeRejectsTabbedExistingCommands$' -test.count=1 -test.v` 保存真实非零选中、TAB 断言失败、空格及普通文本正控结果和退出码。编译/依赖失败、零选中、skip、panic 或其他初始化错误均不是 RED。不要从静态预测填入 pass/fail 数。
3. 现有修复不再重复修改：隔离就绪后核验并运行修复后编译的二进制，用相同选择器取 GREEN，再运行 `noticeguard_test` 整包回归；二进制来自不同编译快照，证据与依赖冻结局限见上。不得跑父 governance TestMain 或 `./...`，除非另行完成该范围的安全前置。
4. 非作者审核当前 diff 和证据。记录历史 TAB 输入拒绝及维护者超长 TriedPaths 错误优先级改变的兼容风险；组件结果仍不替代真实恢复耗尽、生产者、收件人解析、持久化、广播、消费者和完整 TC。

本 TAB 子包不需要 PostgreSQL；全新 disposable PG 可解除其他真实业务链验证的资源前置，但 PG 可用本身不证明依赖初始化或 OS 隔离安全。

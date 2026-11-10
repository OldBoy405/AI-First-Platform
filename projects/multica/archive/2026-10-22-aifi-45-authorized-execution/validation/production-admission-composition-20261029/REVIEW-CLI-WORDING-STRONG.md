# 生产 runner 组合 guard：最终 CLI help 措辞窄范围强审

> 本报告只读复核 `server/cmd/multica/cmd_cr_pipeline.go` 最终版的 help 改动。所有 SHA 都是对原始字节直接计算的 raw SHA，没有做行尾归一化。**未运行或构建 CLI，未运行 `cmd/multica` 的测试（该包有 TestMain），未操作 DB、容器、真实 CR，未修改源码，未使用固定临时路径。**

## 绑定 raw SHA（sha256，逐字节计算）

| 对象 | raw SHA |
|---|---|
| 当前 `server/cmd/multica/cmd_cr_pipeline.go`（新） | `9829b5d606d9e70ab3bd7c6d1592f78e1faea44634b3edfac22d75991e3a5a33` |
| `source-final/cmd_cr_pipeline.go` | `9829b5d606d9e70ab3bd7c6d1592f78e1faea44634b3edfac22d75991e3a5a33`（与当前文件一致） |
| `source-cli-review/cmd_cr_pipeline.go`（旧） | `13c5d729ec5bbdbb1a1395ea27bdc68aa1c730088194621545159c6e03141258` |
| `source-final/router_admission_test.go` | `897b8192b6eb47704822cc2ed23775e8356a33f878f32dc91adf81aa46da8026`（补齐了最新 AST 测试的快照） |
| `server/cmd/server/router.go`（语义对照用） | `0ee5c8cfeafd688a851c8604d2382354f2fb2171d7facbe18a5185eee7b18f87` |

当前 CLI 文件中没有 CR 字符（LF）；`gofmt -l` 无输出。

## diff（旧快照 → 当前文件）

只有两处，替换内容完全相同：start help（旧 `:70-71` → 新 `:70-72`）与 resume help（旧 `:99-100` → 新 `:100-102`）。

- 旧：`Enabling it also requires a configured admission decider; otherwise the server refuses to start.`
- 新：`When enabled, runner composition requires a non-nil admission decider or the server refuses to start. The current server main does not provide one.`

每处多出一行，命令逻辑和其他文字未改动。

## 语义核对

- **与 router 一致**：开关开启时，`router.go:1616-1619` 拒绝缺失或 typed-nil 的 decider，并执行 `os.Exit(1)`。
- **"当前 main 未提供"属实**：复核时 `server/cmd/server/main.go` 中没有任何 `AdmissionDecider`，与 git HEAD 无差异；`main.go:701` 构造的 `RouterOptions` 不注入 decider。
- **不再暗示有配置项**：去掉了 "configured"，改用 "runner composition"（代码组合层面），并说明 main 不提供。按这段文字推下去，当前构建只要开关开启就会拒绝启动，与实际一致。
- **不暗示 decider 可信**：只说"需要非 nil"，没有可信、生产就绪或 Gate3 之类的说法。

## typed-nil 措辞的精确度上限（低）

"non-nil" 比实际行为略宽。helper 也会拒绝 typed nil，比如装进接口的 nil 指针、nil map、nil func 等。按 Go 语义，这种接口值本身 `!= nil`，但照样会被拒绝。所以 help 对拒绝范围写得不全，但没有说错。若要精确，可写成 "non-nil (including no typed nil)"。这不影响本次结论。

## main 变化时须同步 help

以下任一情况发生时，start/resume 两处 help 必须一起修改，否则 "The current server main does not provide one." 会变成错误陈述：

- `main.go` 开始注入 decider；
- 新增环境变量或配置项来提供 decider；
- router 的拒绝规则改变；
- 开关的取值改变。

用户告知已在 CUSTOM #275 登记这一要求。复核时只读 grep 了 `../multica/CUSTOM.md` 的 #275 行，看到"main 注入方式、开关或拒绝规则变化时须同步 start/resume help"的字样；只做了这一处文字核对，CUSTOM.md 的其余内容未审查。

## 不在本次范围 / 不能证明

- 本次只复核 help 文字，不构成启动、服务可用性、RUN、Gate3、部署或生产安全验收；用户授权也不等于验收。
- 之前强审中 AST 测试的其他局限仍然有效（只扫 `router.go`、检测不到间接或跨文件构造、不检查上游 `opts` 改写、没有类型检查、不执行启动）。
- 非 nil decider 是否可信仍未证明；real decider 仍是 CR 级判定，未绑定 generation，未接可信 verdict 写入方。

## 时间注记

本文件写入时间为 2026-10-29T05:03:43Z。结论只适用于上表的 raw SHA。CLI、router、main 或 CUSTOM 之后的任何改动都需要另行复核。

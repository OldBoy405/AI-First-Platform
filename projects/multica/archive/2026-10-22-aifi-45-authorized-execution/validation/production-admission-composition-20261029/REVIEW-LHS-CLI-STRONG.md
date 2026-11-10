# 生产 runner 组合 guard：LHS 补测与 CLI help 窄范围强审

> 本报告只审两个补项，并绑定下表中审查时的 raw SHA。审查方式：只读 live 源码，加两个 no-TestMain、no-DB 子包测试，输出只保存在内存中。未运行 DB、容器、真实 CR，未执行或构建 `cmd/server` / `cmd/multica`，未运行 `cmd/multica` 的 TestMain 测试，未修改源码，未使用固定临时路径。
>
> **审过的 CLI 是旧版本**：`cmd_cr_pipeline.go` raw SHA `13c5d729ec5bbdbb1a1395ea27bdc68aa1c730088194621545159c6e03141258`。原样快照保存在 `source-cli-review/cmd_cr_pipeline.go`，写本报告时已逐字节复算，raw SHA 一致。此后作者修改的 CLI wording 未经本审查验证，见文末注记。

## 审查时绑定的 raw SHA（sha256，逐字节计算）

| 文件 | raw SHA |
|---|---|
| `server/internal/governance/runnerquery_test/router_admission_test.go` | `897b8192b6eb47704822cc2ed23775e8356a33f878f32dc91adf81aa46da8026` |
| `server/cmd/multica/cmd_cr_pipeline.go`（旧 CLI） | `13c5d729ec5bbdbb1a1395ea27bdc68aa1c730088194621545159c6e03141258` |
| `server/cmd/server/router.go` | `0ee5c8cfeafd688a851c8604d2382354f2fb2171d7facbe18a5185eee7b18f87` |
| `server/internal/governance/execution_admission.go` | `23cac3ae674b5aa7e93676bc3c2f04c691e5dde27a695ad0e347a0b266c5a92e` |
| `server/internal/governance/runner.go` | `d8898444d260d2f674d84b2709ac3f4c622b00d502013a2cd0626c0ad4552811` |
| `server/internal/governance/admissionguard_test/decider_test.go` | `60b99f2518400449ba7e22942b41a189249e6d9d1aae3073a2244c0e22bd0028` |

- 测试前后，上述 6 个文件加 `go.mod`、`go.sum` 的合并 SHA 都是 `c830a36d61b23c5c6d97fb4f01ce8e68c5272e384977a8b95475c5f3a3d2bb5e`。
- 本目录没有 `897b8192…` 版 AST 测试的原样快照，这个 SHA 只在审查时对 live 文件计算过。

## 1. AST LHS 补测（对比 `source-recheck/router_admission_test.go`，raw `7c817e9c…`）

- **diff 范围**：只有一处，原 `:110-111` 改为新 `:110-112`。原条件 `!ok || len(Rhs) != 1` 扩展为四项：
  - `construction.Tok != token.ASSIGN`；
  - `len(Lhs) != 2`；
  - `Lhs[0]` 必须是 `architectureRunner`，`Lhs[1]` 必须是 `runnerErr`；
  - 原有的 `len(Rhs) != 1` 保留。

  断言消息也相应改了。没有其他改动。
- **能否检出 shadow**：能检出用 `:=` 遮蔽外层 runner 的情况。写成 `:=` 时 token 是 DEFINE，测试会失败；用 `=` 本身不会产生新变量。对应的真实源码：`router.go:1614` 有 `var architectureRunner *governance.Runner`，`:1620` 有 `var runnerErr error`，`:1621` 是 `architectureRunner, runnerErr = governance.NewRunnerWithOptions(...)`。
- **新出现的边界**：
  - 测试不断言外层 `var architectureRunner` 声明存在；这个由编译器保证，AST 不管。
  - 构造之后对 `architectureRunner` 的再次赋值，以及 `:1785` 路由挂载处的后续使用，都没有检查。
  - 只按名字比对，没有类型检查。
- **之前的局限仍然存在**：
  - 只扫 `router.go`；检测不到其他文件、其他包、包装函数和函数值形式的间接构造。
  - 不检查启用分支之前对 `opts` 的上游改写；例如赋一个假 decider，AST 照样是绿的。
  - 不执行启动，也不验证非 nil decider 是否可信。
- 作者的 `=`→`:=` 变异实验没有重做；上述判断来自逐行阅读断言。

## 2. 旧 CLI help（raw `13c5d729…`，对比 git HEAD）

- **对比基线**：审查时目录里没有 CLI 的前置快照，因此和 git HEAD 比较。该文件最后一次提交是 `5a5d94bc7`。
- **diff 范围**：只有两处，在 start help（`:69-71`）和 resume help（`:98-100`）。两处都是在原来的 `...returns 404.` 后追加同一句：`Enabling it also requires a configured admission decider; otherwise the server refuses to start.` 统计为 4 行新增、2 行删除，命令逻辑未改。
- **与 router 的语义对照**：
  - 一致的部分：开关开启且 decider 缺失时，router 会 `os.Exit(1)`（`router.go:1616-1619`），与"refuses to start"相符。
  - 措辞偏宽：
    - helper 会拒绝 typed nil；从 Go 语义上说 typed nil 也算"已配置"，但实际会被拒。
    - 当前生产代码里，运维方没有办法配置 decider：`main.go:701` 不注入，也没有对应的环境变量或配置项。"configured admission decider"容易让人以为存在这么一个配置开关；现状是当前构建只要开关开启，就必然启动失败。
    - "configured"也不代表可信：非 nil 的假实现同样能通过 guard。
  - 这些不算错误陈述，但不能作为"已有生产配置路径"的依据。
- 未运行 `cmd/multica` 的测试（`cmd_auth_test.go:18` 有 TestMain），未构建 CLI。grep 未发现有测试断言这段 help 文字。

## no-DB 测试（输出只保存在内存）

- 环境：去除 DB/PG 相关环境变量与 `AIFIRST_ARCHITECTURE_RUNNER`，设置 `GOPROXY=off`、`GOWORK=off`。
- 范围：只运行 `./internal/governance/admissionguard_test` 与 `./internal/governance/runnerquery_test`。
- 结果：exit 0，17 个 PASS，0 FAIL，0 SKIP。
- 无真实 server、无 DB，**不算验收**。

## 不能证明的事项

- 不构成 RUN、Gate3、部署或生产安全验收；用户授权也不等于验收。
- `main.go` 仍不注入 decider。
- real decider 仍是 CR 级判定，未绑定 generation，未接可信 verdict 写入方。

## 更正：行尾与 raw SHA

上一轮强审对话中说过"以后核对 `13c5d729…` 前需要先统一行尾"。**这句话错误，予以更正：**

- raw SHA 的证据必须逐字节计算、逐字节比对，不能在核对 raw SHA 之前统一行尾。
- 文件如果被 git autocrlf 改成 CRLF，它的 raw SHA 就会变化，不再等于 `13c5d729…`。这时应当去核对保存下来的原样旧快照（`source-cli-review/cmd_cr_pipeline.go`）。
- 如果确实需要比较行尾归一化后的内容，那个结果必须另称 **normalized digest**，并写明归一化规则，不能与 raw SHA 混用。
- 这处更正不影响本报告的审查结论：审查时的 SHA 都是对原始字节直接计算的。

## 时间注记（2026-10-29T04:59:56Z 写入本文件时）

- 这处行尾更正由用户提出，本审查者认可，并在本文件写入。
- 本审查完成后，作者已把 CLI wording 改为 non-nil composition，并说明当前 `main.go` 不提供 decider。**改动后的 CLI 版本、它的 SHA 和语义，都未经本审查验证。** 本报告的 CLI 结论只适用于 raw `13c5d729…`（即 `source-cli-review/` 中的快照），不能用来替代对新版本的独立复核。

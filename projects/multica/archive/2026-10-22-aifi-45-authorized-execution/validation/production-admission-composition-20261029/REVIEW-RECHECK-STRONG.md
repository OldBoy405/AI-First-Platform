# 生产 runner 组合 admission guard：recheck 独立强审

> 本报告只针对下表 5 个 SHA 绑定的快照，其中 AST 测试为 `7c817e9c…`。审查方式：只读 live 源码，加两个 no-TestMain、no-DB 子包测试，输出只保存在内存中。未运行数据库、容器、真实 CR，未执行或构建 `cmd/server`，未修改源码，未使用固定临时路径。`source-recheck/` 目前只保存了 `router_admission_test.go`，其 SHA 与 `7c817e9c…` 一致；另外 4 个文件的 SHA 以下表为准，其中 `router.go` 和 `decider_test.go` 与 `source-first-green/` 逐字节相同。

## 结论

本次 recheck 在源码结构层面通过：上一轮强审指出的 AST 前三类假绿已关闭；生产代码相比 `source-first-green/` 只改了注释，`router.go` 行为未变。**这是一次源码结构复核，不是生产验证，不构成 RUN、Gate3 或部署验收；用户授权也不等于生产安全验收。**

## 绑定 SHA（sha256，复核时的 live 源码）

| 文件 | SHA |
|---|---|
| `server/internal/governance/execution_admission.go` | `23cac3ae674b5aa7e93676bc3c2f04c691e5dde27a695ad0e347a0b266c5a92e` |
| `server/internal/governance/runner.go` | `d8898444d260d2f674d84b2709ac3f4c622b00d502013a2cd0626c0ad4552811` |
| `server/cmd/server/router.go` | `0ee5c8cfeafd688a851c8604d2382354f2fb2171d7facbe18a5185eee7b18f87` |
| `server/internal/governance/admissionguard_test/decider_test.go` | `60b99f2518400449ba7e22942b41a189249e6d9d1aae3073a2244c0e22bd0028` |
| `server/internal/governance/runnerquery_test/router_admission_test.go` | `7c817e9cffed262e215c9afba94db908e39fa8e5cd80d51c5d2f8a8d2b884e91` |

- 测试前后，上述 5 个文件加 `go.mod`、`go.sum` 的合并 SHA 都是 `07cd1a4e85c4d00c064c4bb3c3e04d36865ba714cf72aac087d69678d2c08049`；git 显示 `go.mod` / `go.sum` 无改动。
- `REVIEW-FIRST-GREEN-STRONG.md` 仍为 `ce05ed84598bdc90c8bf022ea43bcc45e1eb2f77780ed94bfa5b150190a96843`，未被改动。

## 与 `source-first-green/` 的 diff

- `router.go`、`decider_test.go`：逐字节相同。
- `execution_admission.go`（`:105-106`、`:151-178`）与 `runner.go`（`:542-554`）：过滤掉 diff 中以 `//` 开头的行后，剩余改动行数为 **0**，即只改了注释。新注释措辞更保守：
  - decider 只覆盖部分 mutation 路径，直接调用构造函数时仍走旧路径；
  - CR 级 component decider 不可直接用于生产接线；
  - "request id 等于 task id"标为未验证的假设；
  - manifest/scope 来源和链恢复标为未证明。
- 上一轮强审指出的 `runner.go:546-551` 注释冲突已消除。

## no-DB 测试（独立运行，输出只保存在内存）

- 环境：去除 `DATABASE_URL` / `TEST_DATABASE_URL` / `PG*` / `AIFIRST_ARCHITECTURE_RUNNER`，设置 `GOPROXY=off`、`GOWORK=off`。
- 范围：只运行 `./internal/governance/admissionguard_test` 与 `./internal/governance/runnerquery_test`。未执行 `cmd/server`，未构建。
- 结果：exit 0，17 个 PASS（`TestRequireAdmissionDecider` 1 个顶层加 13 个子用例；`runnerquery_test` 3 个测试），0 FAIL，0 SKIP。
- 无真实 server、无 DB，**不算验收**。

## AST 前三类假绿：已关闭（`router_admission_test.go`@`7c817e9c…`）

1. **构造参数被换掉**：`:118-139` 要求第 4 个参数是 `governance.RunnerOptions` 字面量，且恰好有一个字段 `AdmissionDecider: opts.AdmissionDecider`。
2. **guard 与构造之间改写 `opts`**：`:95-111` 要求启用分支第二条语句只能是未初始化的 `var runnerErr error`，第三条必须就是构造调用。
3. **`os.Exit` 前提前 return**：`:72-93` 要求 guard 体只有两条语句，依次是 `slog.Error` 与 `os.Exit(1)`。

另外两处也已补上：`:17-28` 拒绝 governance 的别名导入和点号导入；`:143-145` 拒绝 router.go 中出现 `governance.NewRunner`。

审查者没有重做作者的变异实验。以上关闭结论来自逐行阅读 AST 断言。

## 该快照下仍存在的盲点

- **扫描范围**：只扫 `router.go`。检测不到 `cmd/server` 其他文件、其他包、governance 将来新增的包装函数，以及 `f := governance.NewRunner; f(...)` 这种函数值间接调用。
- **函数内上游改写**：不检查 `NewRouterWithOptions` 内启用分支之前对 `opts` 的赋值。例如 `opts.AdmissionDecider = fake{}` 能通过 guard，AST 测试也是绿的。
- **构造调用左侧**：不检查 LHS 和赋值符号。写成 `:=` 会遮蔽外层 `architectureRunner`，导致路由不挂载。这不是绕过，但属于功能性错误，测试发现不了。
- **没有类型检查**：只认标识符文字，不验证 `os` / `slog` / `opts` 真的绑定到标准库或函数参数。
- **没有执行**：没有真正运行启动或 `os.Exit`。guard 位于 `NewRouterWithOptions` 中段，此前的其他初始化已经发生。
- **CLI 帮助文字**：`cmd_cr_pipeline.go` 的帮助仍未说明"开启开关但没有 decider 会拒绝启动"。
- **仍未修复（不在本次范围）**：runner 内部继续用接口是否为 nil 来判断（`runner.go:1059`、`:1539`，`runner_requirement.go:681`，`execution_admission_gate.go:191`）；旧 `NewRunner` 仍允许 nil。

## 不能证明的事项

- **非 nil decider 是否可信**：guard 只检查形状，测试中总是返回零值的假实现也能通过。
- **能否上线**：`main.go:701` 仍不注入 decider，开关一开整个 server 进程就会退出。
- **生产集成**：real decider 仍是 CR 级判定，未绑定 generation，未接可信 verdict 写入方。
- **验收**：不构成 RUN、Gate3、部署或生产安全验收。

作者的 `AUTHOR-RECHECK.md` 与以上结论一致，未发现夸大之处。

## 时间注记（2026-10-29T04:47:46Z 写入本文件时）

本复核完成后，作者又新增了 `AUTHOR-CLI-HELP.md`（补 CLI help）和 `AUTHOR-AST-LHS.md`（在新版 AST 测试中补 LHS `=` 检查）。**本报告没有审查这两项及其对应的新源码或测试版本，结论只适用于上表 SHA，尤其是 AST `7c817e9c…`。** 上文"CLI 帮助文字"和"构造调用左侧"两条盲点是针对该旧快照的记录。新版本是否关闭这两条，需要另行独立复核，不能用本报告替代。

# 生产 runner 组合 admission guard：独立强审（first-green）

> 本文是独立强审结果的摘要，审查对象为下列 SHA 绑定的源码组合。审查方式：只读 live 源码，加两个 no-TestMain、no-DB 子包测试。未运行数据库、容器、真实 CR，未执行 `cmd/server` 及其父包 TestMain，未修改源码。旧快照已保存在 `source-first-green/`，其中 4 个文件 SHA 与下表一致。

## 结论

本次改动只做到一件事：在当前 `router.go` 唯一的 runner 构造点，feature 开启时拒绝缺失或 typed-nil 的 `AdmissionDecider`，并让进程退出。未发现直接绕过该 guard 的新路径。设计不阻断，合入且不部署也不阻断，前提是继续标注"已知启用即拒绝启动、未部署"。部署与真实接线继续阻断。

**这不等于生产安全验收，也不等于 Gate3、RUN 或部署验收；用户授权同样不等于生产安全验收。**

## Scope

- 覆盖：`server/cmd/server/router.go` 中 `NewRouterWithOptions` 的 runner 启用分支，以及 `governance.RequireAdmissionDecider` helper。
- 不覆盖：将来新增的构造点；`NewRunner` 及其他非 router 构造路径；非 nil decider 的真实性与权威性；未门控的 effect；手动 crctl 路径；real `NewAdmissionDecider` 在 CR 级未绑定 generation 的问题；可信 verdict writer 接线。

## 绑定 SHA（sha256，live 源码与 `source-first-green/` 一致）

| 文件 | SHA |
|---|---|
| `server/cmd/server/router.go` | `0ee5c8cfeafd688a851c8604d2382354f2fb2171d7facbe18a5185eee7b18f87` |
| `server/internal/governance/execution_admission.go` | `40fb47671c6e6ccaf12ccd869b0c3a8b4d8ba0de568b4647114d5e163ab68e4d` |
| `server/internal/governance/admissionguard_test/decider_test.go` | `60b99f2518400449ba7e22942b41a189249e6d9d1aae3073a2244c0e22bd0028` |
| `server/internal/governance/runnerquery_test/router_admission_test.go` | `13ecf4b862e8285968e35700834f5e1f800c103dd988e559f4bd20593e6e8be7` |

对比 `source-before/`，真实 diff 只有两部分，未发现夹带改动：
- `router.go`：`:253-254` 注释改写，`:1616-1619` 新增 guard。
- `execution_admission.go`：新增 `reflect` import，以及 `:84-102` 的 `ErrAdmissionDeciderRequired` 与 `RequireAdmissionDecider`。

## 已核实事实

- **顺序**：`router.go:1615` 为 `if governance.ArchitectureRunnerEnabled()`，分支第一条语句（`:1616`）是 guard，失败时 `os.Exit(1)`（`:1618`）。之后依次是：
  1. `NewRunnerWithOptions`（`:1621-1623`），传入同一个 `opts.AdmissionDecider`；
  2. `WireEvents` / `WireRequirementEvents`；
  3. approval 钩子；
  4. `ResumeActiveRuns` goroutine；
  5. `h.PipelineResume`；
  6. 路由挂载（`:1785` 起，要求 `architectureRunner != nil`）。

  feature 关闭时路径不变。
- **启用条件**：`runner.go:60-66` 只把 `1/true/yes/on`（忽略大小写、去空格）视为开启；`enabled` 不算开启。
- **typed nil**：helper 检查 Chan / Func / Map / Pointer / Slice 是否 nil。UnsafePointer 未列入，但已在临时目录独立实测：`type U unsafe.Pointer` 声明方法会报 `invalid receiver type`，无法实现接口，所以不列入没有影响。Interface kind 不会从 `reflect.ValueOf` 出现。能带方法、可为 nil 的 kind 已全部覆盖。
- **构造点与 flag 盘点**：
  - 非测试代码中，`NewRunnerWithOptions` 只在 `router.go:1621` 调用；`NewRunner`（`runner.go:559`）只出现在 governance 包测试里。
  - Go 测试里只有 `runner_contract_test.go:20,26` 设置 `AIFIRST_ARCHITECTURE_RUNNER`，且只测开关判定函数，没有任何 `cmd/server` 测试开启 feature。
  - deploy / compose 文件中没有开启该 flag 的配置（非 Go 文件里只有 CUSTOM.md 的文字说明）。

## no-DB 测试结果（独立运行）

环境：已去除 `DATABASE_URL` / `TEST_DATABASE_URL` / `PG*` / `AIFIRST_ARCHITECTURE_RUNNER`，设置 `GOPROXY=off`、`GOWORK=off`。只运行以下两个子包：

- `./internal/governance/admissionguard_test`：`TestRequireAdmissionDecider` 1 个顶层测试，13 个子用例全部 PASS（6 个 nil/typed-nil 用例被拒；6 个非 nil 用例加 `real_decider` 通过）。
- `./internal/governance/runnerquery_test`：3 个测试全部 PASS。
- 0 FAIL，0 SKIP，exit 0；运行前后 `go.mod` / `go.sum` 未变化。
- 这两个包都没有真实 server、没有 DB，**不算验收**。

## 风险与问题

1. **main 不注入，feature 启用即启动失败（高，作者已披露）**：`main.go:701` 构造的 `RouterOptions` 不含 `AdmissionDecider`，`NewRouter`（`router.go:215-216`）传的是 `RouterOptions{}`。任何开启 feature 的部署都会拒绝启动。`os.Exit` 让整个 server 进程退出，所有 API 一起不可用，不只是 runner。回滚办法是关闭 flag。CUSTOM #275 已登记此影响。
2. **AST 测试的具体盲点（可能假绿）**，文件为 `router_admission_test.go`：
   - `:77-91` 只统计 `NewRunnerWithOptions` 的次数和位置，不检查参数。构造参数改成 `RunnerOptions{}` 或 nil，测试仍然通过。
   - 不检查 guard 与构造之间是否对 `opts` 重新赋值。插入 `opts.AdmissionDecider = nil` 后测试仍然通过。
   - `:60-76` 只统计 guard 体内有 1 条 `os.Exit(1)` 表达式语句。在它之前插入 `return r, h`，测试仍然通过。
   - 统计不到以下新增构造：`governance.NewRunner(...)`；通过别名或点号 import governance 的构造；`cmd/server` 其他文件里的构造。
   - 只扫描 `NewRouterWithOptions` 顶层的 if 语句，且只看 `router.go` 一个文件。
   - 只证明源码结构，没有执行启动或退出。
3. **注释冲突**：`runner.go:546-549`（"Production leaves it nil until Gate3…"）和 `:551`（"seams that stay nil in production"）与新的 `router.go:253-254`（启用时必须提供 decider）矛盾。`cmd_cr_pipeline.go` 中关于该 flag 的帮助文字没有说明"需要 decider，否则拒绝启动"。
4. **启动前已有其他初始化**：guard 位于 `NewRouterWithOptions` 中段，此前 approval service、execution contract 校验及各类集成初始化（含 goroutine）已经执行过，之后才退出。这与已有 registry 错误分支的模式相同，不是本次引入，但也不是最早的快速失败；放到 `main.go` 构造 router 之前会更干净。
5. **Runner 内部仍按接口 nil 判定（不在本次范围）**：`runner.go:1059`、`:1539`，`runner_requirement.go:681`，`execution_admission_gate.go:191` 都用 `decider != nil` 判断。typed nil 若经其他构造路径进入，会被当成"已门控"，随后在 `execution_admission_gate.go:106` 调用 `DecideAdmission`，可能 panic。`NewRunnerWithOptions` 本身不调用 guard，旧 `NewRunner` 仍允许 nil。
6. **测试环境泄漏（低）**：开发者 shell 若残留 `AIFIRST_ARCHITECTURE_RUNNER=1`，运行 `go test ./cmd/server` 时，任何调用 `NewRouter` 的测试都会让整个测试进程 `os.Exit(1)`，而不是报普通失败。

## 为什么不能证明非 nil decider 可信

- `execution_admission.go:89-90` 自己声明 helper 只做形状检查，不验证实现的权威性和行为。
- `decider_test.go:56-61` 中 `valueDecider` / `funcDecider` / `mapDecider` 等总是返回零值决定的假实现都能通过 guard。
- real `NewAdmissionDecider()`（`execution_admission.go:106`）仍是 CR 级判定，未绑定 generation，也未接可信 verdict writer。

## 建议

- 补强 AST 测试：
  - 断言构造参数中的 `AdmissionDecider` 字段就是 `opts.AdmissionDecider`；
  - 断言 guard 与构造之间没有对 `opts` 的赋值；
  - 断言 guard 体内 `os.Exit(1)` 之前没有 `return`；
  - 把 `NewRunner` 与别名 import 纳入统计。
- 修正 `runner.go:546-551` 的注释。
- 在 generation 绑定、可信 verdict writer、可用性评估完成之前，部署与真实接线继续阻断。

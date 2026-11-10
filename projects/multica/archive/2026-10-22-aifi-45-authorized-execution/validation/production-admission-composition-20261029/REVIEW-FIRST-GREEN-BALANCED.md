# AIFI-45 runner admission 生产组合：独立 no-DB 复跑

## 结论

2026-10-29 12:28:41–12:28:42 +08:00，在 `multica/server` 使用 Go 1.27.1 windows/amd64 执行：

```text
go test -count=1 -json ./internal/governance/admissionguard_test ./internal/governance/runnerquery_test
```

退出码 **0**，两个包均 PASS；**4 个顶层测试、16 个 leaf 测试通过，skip 0**。`-count=1` 禁用测试结果缓存。设置 `GOPROXY=off`、`GOWORK=off`、`GOENV=off`、`GOFLAGS` 为空、`GOTOOLCHAIN=local`；按 DB 相关环境变量名称筛查时无待清除项。`AIFIRST_ARCHITECTURE_RUNNER` 未设置。

顶层测试：

- `TestRequireAdmissionDecider`：13 个 leaf，通过 nil interface、typed-nil pointer/function/map/slice/channel，以及非 nil pointer/value/function/map/slice/channel 和 real decider 的检查。
- `TestFindActiveRunTxBindsRequestedPipeline`：通过。
- `TestAdmissionRollbackGuardPrecedesLockAndDecider`：通过。
- `TestRouterRequiresAdmissionBeforeConstructingRunner`：通过。

后 3 个顶层测试无子测试，本身也是 leaf。上述计数不重复计入有子测试的顶层测试。

## 文件 SHA-256

以下路径均相对 `multica/server`。运行前后原始字节 SHA-256 一致，均匹配指定值；LF 规范化后的 SHA 也相同：

| 文件 | 运行前及运行后 SHA-256 |
| --- | --- |
| `internal/governance/execution_admission.go` | `40fb47671c6e6ccaf12ccd869b0c3a8b4d8ba0de568b4647114d5e163ab68e4d` |
| `cmd/server/router.go` | `0ee5c8cfeafd688a851c8604d2382354f2fb2171d7facbe18a5185eee7b18f87` |
| `internal/governance/admissionguard_test/decider_test.go` | `60b99f2518400449ba7e22942b41a189249e6d9d1aae3073a2244c0e22bd0028` |
| `internal/governance/runnerquery_test/router_admission_test.go` | `13ecf4b862e8285968e35700834f5e1f800c103dd988e559f4bd20593e6e8be7` |

旧测试快照保存在本目录的 `source-first-green/`；快照中对应四个文件的原始字节 SHA 与上表一致。

## 范围、局限及未执行事项

- Router 测试只解析源码 AST：检查启用块、guard、`os.Exit(1)` 和 constructor 的源码位置，不实际执行 server 启动。它不证明退出语句或 constructor 的运行时可达性，也不验证 constructor 实际接收的 decider；例如 guard 内在 exit 前增加提前返回，或改变 constructor 参数，仍可能假绿。
- active-run 查询及 rollback 测试同样是源码结构检查，不证明数据库查询、事务、锁释放或并发语义。decider 测试只检查缺失/typed-nil 判定，不证明非 nil 实现的可信性、真实 admission 决策或生产部署就绪。
- runner 开关在代码中默认关闭，`1`、`true`、`yes`、`on` 可启用（大小写及周围空格经处理）。本次未设置不能代表生产环境开关或依赖注入状态。
- 未进行 overlay 或其他变异测试；未实际启动 server，未执行 DB、容器或 CR。没有修改工作区源码。
- 原始后端 receipt **未知**；本报告仅总结本次独立复跑，不声称替代真实后端 receipt 或端到端验证。

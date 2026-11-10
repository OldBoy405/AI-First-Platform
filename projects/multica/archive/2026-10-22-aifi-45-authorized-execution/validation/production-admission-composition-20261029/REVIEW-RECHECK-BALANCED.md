# AIFI-45 生产 admission 组合：独立复跑归档

## 结果与环境

2026-10-29 12:42:25–12:42:26 +08:00，在 `multica/server` 以 Go 1.27.1 windows/amd64 独立执行：

```text
go test -count=1 -json ./internal/governance/admissionguard_test ./internal/governance/runnerquery_test
```

两包 PASS，退出码 0；**4 个顶层测试、16 个 leaf 测试通过，skip 0、fail 0**。JSON 输出仅在内存中捕获和解析。`GOPROXY=off`、`GOWORK=off`、`GOENV=off`、`GOFLAGS` 为空、`GOTOOLCHAIN=local`；DB 相关环境变量按名称筛查无待清除项，`AIFIRST_ARCHITECTURE_RUNNER` 未设置。

顶层：`TestRequireAdmissionDecider`（13 个 leaf）、`TestFindActiveRunTxBindsRequestedPipeline`、`TestAdmissionRollbackGuardPrecedesLockAndDecider`、`TestRouterRequiresAdmissionBeforeConstructingRunner`（后三者各为一个 leaf）。

## 运行前后 SHA-256

路径均相对 `multica/server`。以下原始字节 SHA 前后均一致且匹配指定值；LF 规范化 SHA 也一致。此次复跑期间其余源码未由验证操作修改。

| 文件 | 运行前及运行后 SHA-256 |
| --- | --- |
| `internal/governance/execution_admission.go` | `23cac3ae674b5aa7e93676bc3c2f04c691e5dde27a695ad0e347a0b266c5a92e` |
| `internal/governance/runner.go` | `d8898444d260d2f674d84b2709ac3f4c622b00d502013a2cd0626c0ad4552811` |
| `cmd/server/router.go` | `0ee5c8cfeafd688a851c8604d2382354f2fb2171d7facbe18a5185eee7b18f87` |
| `internal/governance/admissionguard_test/decider_test.go` | `60b99f2518400449ba7e22942b41a189249e6d9d1aae3073a2244c0e22bd0028` |
| `internal/governance/runnerquery_test/router_admission_test.go` | `7c817e9cffed262e215c9afba94db908e39fa8e5cd80d51c5d2f8a8d2b884e91` |

当时的 AST 测试快照保存于本目录 `source-recheck/router_admission_test.go`；其原始字节 SHA 与上表最后一项一致。其他四个文件的上表哈希为当时工作区实测值，不声称它们都保存在 `source-recheck/`。

## 局限

Router AST 测试只检查源码结构和 decider 参数，不执行 server 启动，不能证明运行时控制流可达或实际退出。另两个 AST 测试不证明 DB 查询、事务、锁释放或并发语义；decider 单测也不证明实际生产依赖的可信性或部署就绪。未启动真实 server、未触及 DB、容器或 CR；未做变异。原始后端 receipt **未知**。

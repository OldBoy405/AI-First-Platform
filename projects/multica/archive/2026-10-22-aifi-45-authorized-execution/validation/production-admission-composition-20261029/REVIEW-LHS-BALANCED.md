# AIFI-45 runner admission：LHS 快照独立 no-DB 复跑

## 结果

2026-10-29 12:48:26–12:48:27 +08:00，在 `multica/server` 使用 Go 1.27.1 windows/amd64 执行：

```text
go test -count=1 -json ./internal/governance/admissionguard_test ./internal/governance/runnerquery_test
```

两包均 PASS，退出码 0；**4 个顶层测试、16 个 leaf 全部通过，skip 0、fail 0**。JSON 测试输出仅在内存中捕获和解析，未写入结果文件。`-count=1` 禁用测试结果缓存。

设置 `GOPROXY=off`、`GOWORK=off`、`GOENV=off`、空 `GOFLAGS`、`GOTOOLCHAIN=local`。按 DB 相关环境变量名称筛查无待清除项；`AIFIRST_ARCHITECTURE_RUNNER` 未设置。

四个顶层测试：`TestRequireAdmissionDecider`（13 个 leaf）、`TestFindActiveRunTxBindsRequestedPipeline`、`TestAdmissionRollbackGuardPrecedesLockAndDecider`、`TestRouterRequiresAdmissionBeforeConstructingRunner`（后三者各为一个 leaf）。

## 运行前后 SHA-256

路径相对 `multica/server`。下列原始字节 SHA 均为运行前、后的共同值，并匹配预期；LF 规范化 SHA 也相同。

| 文件 | SHA-256 |
| --- | --- |
| `internal/governance/execution_admission.go` | `23cac3ae674b5aa7e93676bc3c2f04c691e5dde27a695ad0e347a0b266c5a92e` |
| `internal/governance/runner.go` | `d8898444d260d2f674d84b2709ac3f4c622b00d502013a2cd0626c0ad4552811` |
| `cmd/server/router.go` | `0ee5c8cfeafd688a851c8604d2382354f2fb2171d7facbe18a5185eee7b18f87` |
| `internal/governance/admissionguard_test/decider_test.go` | `60b99f2518400449ba7e22942b41a189249e6d9d1aae3073a2244c0e22bd0028` |
| `internal/governance/runnerquery_test/router_admission_test.go` | `897b8192b6eb47704822cc2ed23775e8356a33f878f32dc91adf81aa46da8026` |

与 `source-recheck/router_admission_test.go` 的旧快照比较，新 AST 测试仅增加构造赋值的 `=` 和 LHS 检查，并更新对应失败提示。

## 范围与限制

Router 测试只检查源码 AST 结构及传入的 decider，不实际启动 server；即使检查了赋值目标，也不能证明运行时控制流可达或真实退出。其余 AST 测试不证明 DB 查询、事务、锁释放或并发语义。decider 单测不证明实际生产依赖的可信性、真实 admission 决策或部署就绪。

未修改源码，未实际启动 server，未触及 DB、容器或 CR；未做变异。原始后端 receipt **未知**；此复跑不是端到端验证。

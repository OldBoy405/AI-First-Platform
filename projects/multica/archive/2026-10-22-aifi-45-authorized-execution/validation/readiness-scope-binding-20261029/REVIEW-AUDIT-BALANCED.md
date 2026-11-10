# AIFI-45 readiness audit scope 独立复跑

## 结果与快照

在 `server` 目录使用 `go test -json -count=1 ./internal/governance/deploymentaccess_test` 复跑最终 live，退出 0：顶层 9/9 PASS，leaf 152/152 PASS，skip 0；新增 audit 矩阵 30/30 leaf PASS。Go JSON 及 stderr 仅在内存捕获，不打印或留存原始进程输出。`source-audit-final/` 三文件与 live 相同。

运行前后 raw SHA-256 均一致：

| 相对 server 的路径 | 前后 SHA-256 |
| --- | --- |
| `internal/governance/execution_deployment.go` | `7b9078db96c6a54b9cb87c040bedfb7b346d8c1a4a77b772367fa94063e3268a` |
| `internal/governance/deploymentaccess_test/execution_deployment_test.go` | `0fe7cbf4ca840595d11ecbc68b393fe6195ff521741ac64dd606fff4cecd4a52` |
| `internal/governance/deploymentaccess_test/readiness_scope_test.go` | `2abec82fdc40f31025ab12a9343165252ad287ea3463857193887998052ce31e` |

## 覆盖与限制

新增矩阵覆盖五种 audit 操作 × ACTIVE 未过期、ACTIVE 已过期、STOP_NEW 带 verdict × 同 scope、异 scope。每组均 PASS；同 scope 返回 AuditOnly，异 scope 返回 ErrDeploymentNotReady，fake 记录零写入。fake 按 readiness 查询的 scope 谓词和参数模拟缺行，并非真实 SQL 引擎，也不完整建模其他查询及写入。

静态 schema 定义允许 STOP_NEW 事件有 verdict_ref；fake 构造该状态。当前 `StopNewAdmissionsTx` 的事件插入列未指定 verdict_ref，因此不能把此 fake 场景当作已证明的真实 STOP_NEW 数据形态。真实数据、PostgreSQL 约束与行锁行为均未检；不构成端到端授权或生产安全证明。

## 环境

白名单仅含 `APPDATA`, `CGO_ENABLED`, `GOCACHE`, `GOENV`, `GOFLAGS`, `GOPATH`, `GOPROXY`, `GOSUMDB`, `GOTELEMETRY`, `GOTOOLCHAIN`, `GOWORK`, `LOCALAPPDATA`, `PATH`, `SYSTEMROOT`, `TEMP`, `TMP`, `USERPROFILE`, `WINDIR`；不含 DATABASE、PG 或 token 变量。`GOPROXY=off`、`GOWORK=off`、`GOSUMDB=off`、`GOTOOLCHAIN=local`、`GOENV=off`、`GOFLAGS=-mod=readonly`、`CGO_ENABLED=0`、`GOTELEMETRY=off`。静态检查不等于操作系统级网络隔离。

backend receipt unknown。旧的 `REVIEW-BALANCED.md` 对应旧测试快照，不作为本次结果。

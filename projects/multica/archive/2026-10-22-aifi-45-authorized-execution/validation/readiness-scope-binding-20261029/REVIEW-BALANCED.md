# AIFI-45 readiness scope 独立复跑

## 结果

复核前曾因尚未确认依赖初始化安全而标记 INCOMPLETE、未运行。完成只读检查后，在 `server` 目录运行 `go test -json -count=1 ./internal/governance/deploymentaccess_test`，退出码 0：顶层测试 8/8 PASS，leaf 122/122 PASS，skip 0；其中 readiness scope leaf 为 13 个。原始进程输出只在内存捕获，未打印或留存。

## 前后 raw SHA-256

以下三个文件运行前后哈希相同：

| 相对 server 的路径 | 前后 SHA-256 |
| --- | --- |
| `internal/governance/execution_deployment.go` | `7b9078db96c6a54b9cb87c040bedfb7b346d8c1a4a77b772367fa94063e3268a` |
| `internal/governance/deploymentaccess_test/execution_deployment_test.go` | `0fe7cbf4ca840595d11ecbc68b393fe6195ff521741ac64dd606fff4cecd4a52` |
| `internal/governance/deploymentaccess_test/readiness_scope_test.go` | `f1acecbd4c4db3a298809d7c3be906ab6b46cb3f560e9c8618ca6913822551f1` |

## 环境与边界

测试进程使用显式白名单：`APPDATA`, `CGO_ENABLED`, `GOCACHE`, `GOENV`, `GOFLAGS`, `GOPATH`, `GOPROXY`, `GOSUMDB`, `GOTELEMETRY`, `GOTOOLCHAIN`, `GOWORK`, `LOCALAPPDATA`, `PATH`, `SYSTEMROOT`, `TEMP`, `TMP`, `USERPROFILE`, `WINDIR`。不含 DATABASE、PG 或 token 变量；`GOPROXY=off`、`GOWORK=off`、`GOSUMDB=off`、`GOTOOLCHAIN=local`、`GOENV=off`、`GOFLAGS=-mod=readonly`、`CGO_ENABLED=0`、`GOTELEMETRY=off`。

子包无 TestMain，测试使用内存 pgx fake；对所选依赖初始化及连接相关路径的静态检查未发现启动时连接 DB 的路径。fake 根据 SQL scope 谓词及参数模拟过滤，并非真实 PostgreSQL；其他查询及写入并未完整建模。结果不能证明数据库锁、隔离、签名、可信输入或生产安全边界；静态检查也不是操作系统级网络隔离。

## 记录提示

原生请求 model 与 backend receipt 未知；环境标签 `PI_MODEL` 为 `gpt-6.1-terra`，不等于已核实的 backend receipt。

此前工具因搜索输出截断在用户临时目录自动生成随机日志 `pi-bash-63097079203d8b95.log`，含内部源码及生成的提示文本，应视为潜在敏感。工具未明确证明该日志以独占方式创建；已只读核查，未修改或删除。此报告不含日志正文。

# AIFI-45 恢复操作覆盖独立复跑

## 选择与结果

在 `multica/server` 执行 `go test -count=1 -json ./internal/governance/deploymentaccess_test`，Go 版本 `go1.27.1 windows/amd64`。只选独立 fakeTx 测试包；该包无 TestMain，未运行父包测试。测试退出码 0，包通过：**7 个顶层、109 个 leaf 全部通过、0 skip**；stderr 为空。顶层按不含斜杠的 run 事件统计，leaf 按没有后代 run 事件统计。

使用进程环境白名单清除数据库连接环境变量，并设置 `GOPROXY=off`、`GOWORK=off`、`GOSUMDB=off`、`GOTOOLCHAIN=local`、`GOTELEMETRY=off`、`GOENV=off` 和 `GOFLAGS=-mod=readonly`。测试 stdout 和 stderr 通过子进程管道纯内存捕获、解析，未将测试输出写入文件。

## 前后 raw SHA-256

测试前后两文件均与指定值一致：

- `server/internal/governance/execution_deployment.go`：`0d9773985591f63035c7bc706d9e406e1a929f2bed990235b5d0d287cea96e0a`
- `server/internal/governance/deploymentaccess_test/execution_deployment_test.go`：`646f5214e424d08f66dac5fae0cb59ffeac20a7acc3b581f445ef90191fc4c59`

## 限制

本次仅复跑 fakeTx 子包；未修改源码，未操作真实 DB、容器或真实 CR。单侧空字段与两种恢复操作的测试覆盖不代表新增产品行为，也不证明真实数据库、并发锁或生产安全。

过程身份自报：session `01a185c5-eccb-7020-aecc-d24bc422ce0e`；模型 `gpt-6.1-terra`，provider `OpenAIPersonal`；backend receipt 未知。

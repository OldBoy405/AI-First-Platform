# 生产 runner 组合缺失依赖：作者证据

## 变更及影响

生产 `router.go` 在 feature 启用分支首个语句调用 `RequireAdmissionDecider(opts.AdmissionDecider)`；缺失或 typed nil 时 `os.Exit(1)`，不会继续构造 runner / 连接事件。feature 关闭路径不变。`main.go` 目前不传 decider，故应用此改动到启用 runner 的部署将**拒绝启动**；本轮不部署。非 nil 仅是形状检查，假 decider 也可通过，且没有实现可信接线。旧 `NewRunner` 及非 router 构造路径、其他未门控 effect、手动 crctl 路径并未修复。

## RED / GREEN

原源码 `source-before/`：`execution_admission.go` raw SHA `33c8c9bdc55384acde24521a5a5272f647439a2ed99326baeb207b5bed90eb2a`，`router.go` `e0f52b4039d4610485d4da28740507c06294ffbe58014747838d23166724b76a`。先新增**返回 nil 的编译桩**和行为测试：6 个 nil/typed-nil 例因实际 nil 错误而 RED，6 个非 nil 正控通过；这是新 helper 的桩 RED，不是旧生产路径运行证据。router 尚未修改时，源码 AST 测试实际 RED：`runner-enabled block must start with admission guard`。

实现后清 DB/PG 环境、`GOPROXY=off`、`GOWORK=off`，`go test -count=1 -json ./internal/governance/admissionguard_test ./internal/governance/runnerquery_test` exit 0：前者 1 顶层、13 leaf，后者 3 顶层/leaf，0 fail、0 skip。另 `go build -o <独占临时目录>/server.exe ./cmd/server` exit 0；没有运行二进制或父包 TestMain，核空删除自有产物与目录。AST 测试只覆盖当前源码结构，并未实际执行启动或退出。

最终 SHA：
- `execution_admission.go` `40fb47671c6e6ccaf12ccd869b0c3a8b4d8ba0de568b4647114d5e163ab68e4d`
- `router.go` `0ee5c8cfeafd688a851c8604d2382354f2fb2171d7facbe18a5185eee7b18f87`
- `admissionguard_test/decider_test.go` `60b99f2518400449ba7e22942b41a189249e6d9d1aae3073a2244c0e22bd0028`
- `runnerquery_test/router_admission_test.go` `13ecf4b862e8285968e35700834f5e1f800c103dd988e559f4bd20593e6e8be7`

三个独占 Go overlay 变异：nil 分支错误返回 nil、忽略 typed-nil 指针、忽略 typed-nil map 均在对应断言处失败；工作区源码和测试 SHA 未变，逐一清理自有临时文件、核空删除目录。撤除 overlay 后两包再次 exit 0、0 skip。此为作者证据，独立复核待完成。

未运行 DB、容器或真实 CR；未连接可信 verdict writer，未验收 RUN 或 Gate3。multica CUSTOM #275。

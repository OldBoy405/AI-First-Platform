# 未知操作 guard 回退变异（作者）

以 `go test -overlay <独占临时 JSON> -count=1 -run '^TestUnknownOperationIsDenied$' -v ./internal/governance/deploymentaccess_test`，仅将 `execution_deployment.go` 映射到保全的旧源码 SHA `f1e719d9388c09eadecc9da17aa21bdafb080265237fabd8b58dc0f50b728811`，测试使用最新 SHA `8dd07c9609f5657d39b45a991cc6ba2d18be8f9bd2167437187b09f2d5d69adf`。命令 exit 1；ACTIVE/未过期断言明确显示 `future_operation = NewAdmission, want Denied`，不是编译或环境失败；其余 3 个状态通过。源码与测试的工作区 SHA 前后均未变化。删除两份本次独占文件，核空后移除独占目录。

移除 overlay 后，目标测试再次执行：1 顶层及 4 子例 PASS，0 skip；此为作者变异证据，不代替独立验证。仍未运行 DB/容器，未知状态及恢复安全不在此证明范围。

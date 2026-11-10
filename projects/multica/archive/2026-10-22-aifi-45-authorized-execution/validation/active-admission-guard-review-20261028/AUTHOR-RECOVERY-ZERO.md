# 精确恢复零值边界：作者证据

实施前源码/测试完整保存在 `source-unknown-mode-final/`，raw SHA 分别为 `feab73bd1f79bba2661f8db3808ddaf306c7a854e11664047c83e45651fbfd9b`、`65bc2ea93b22ddbbf118f5875cf17413587e6d0b12791eecb118a4eef2adb496`。按 `RECOVERY-ZERO-PLAN.md`，先添加 STOP_NEW/过期 × 五种缺失或无效身份事实的 fakeTx 断言；原源码返回 ExactRecovery，10/10 目标子例真实 RED（非编译错误）。

修复后 `go test -count=1 -json ./internal/governance/deploymentaccess_test`：7 顶层、75 leaf PASS、0 fail、0 skip；源码测试运行前后 raw SHA 稳定，分别为 `449216c3469c48cdc7bb33fd9e138bd632bfabf0c95815f891fb00bab446178a`、`2a5bcd5fae7d965a74a96263940c30aa32d36775882fbacdd7ac1cbfbd9a0de5`。清除 DB/PG 环境，`GOPROXY=off`、`GOWORK=off`，未连接 DB、容器或真实 CR。

在独占临时目录通过 Go overlay 分别恢复 issuedAt 旧守卫和 generation 旧守卫：前者 exit 1 且两条 `missing_issued_at` 断言失败，后者 exit 1 且八条 generation 断言失败；两者均报告 `ExactRecovery, want Denied`。实际工作树源码和测试 SHA 前后不变；逐一删除自有文件，核空移除目录；去掉 overlay 后目标测试 1 顶层及 10 子例全部通过，0 skip。独立审核待完成。

非零与相等仍是未认证的调用方输入，不证明 DB 原事实、签名、截止时间与 request 绑定、当前 generation 或停止准入竞态；不意味着 RUN-006 可验收。multica CUSTOM #273 登记。

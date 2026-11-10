# 未知 activation mode：作者证据

原源码与测试以 raw 字节保全在 `source-unknown-mode-before/`，分别为 `dc6407f98b07fbd63d7c039a5db497a9540b3dd674206b320b3e31cd92a18e7b`、`8dd07c9609f5657d39b45a991cc6ba2d18be8f9bd2167437187b09f2d5d69adf`。依 `UNKNOWN-MODE-PLAN.md` 新增 fakeTx 反例，旧源码执行 `go test -count=1 -run '^TestUnknownActivationModeIsDenied$' -v ./internal/governance/deploymentaccess_test`：exit 1，两个恢复动作误为 ExactRecovery、checkpoint_ingest 误为 AuditOnly；new_admission 被拒。是目标断言 RED，不是编译失败。

实现上在 event 查询后拒绝非 ACTIVE/STOP_NEW；作者重跑整个 no-DB 子包 `go test -count=1 -json ./internal/governance/deploymentaccess_test`：6 顶层、65 leaf PASS，0 fail、0 skip，源码测试 SHA 前后相同。源码 raw SHA `feab73bd1f79bba2661f8db3808ddaf306c7a854e11664047c83e45651fbfd9b`，测试 `65bc2ea93b22ddbbf118f5875cf17413587e6d0b12791eecb118a4eef2adb496`；multica CUSTOM #272。待独立复核。

migration 648 当前 CHECK 限制 mode 为 ACTIVE/STOP_NEW；fakeTx 异常状态不等于受约束 DB 内发生过该状态。此切片不证明真实恢复字段来源、签名、锁竞态或生产接线安全，不调整 RUN TC。

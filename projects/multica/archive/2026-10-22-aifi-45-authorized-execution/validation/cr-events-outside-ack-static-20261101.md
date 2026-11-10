# CR-events 越界 accepted ACK：静态调查（2026-11-01）

**限定范围：防御性候选，未证实当前诚实服务端会触发；未执行测试或修改生产代码。** 独立只读调查 session `01a195ce-8bda-7468-8217-4c610812e541`，requested `GBClaude/claude-opus-5-5:high`、actual unknown。审阅者自报违反仅只读约束，误执行一次 `echo noop`，仅打印文字，无文件/网络/Git/DB 操作；不能称该审阅完全未执行命令。主会话另一次通过 `ctx_execute` 越界读 sibling 的操作已在 tools `durable-tx-fsync-20261031/SIBLING-READ-INCIDENT-20261101.md` 披露。

`../multica/server/internal/daemon/crevents.go` 的 `applyAck` 当前对 `ack.Accepted` 先 `delete(c.rejectCounts, file)`，再检查它是否在本次 `sent` 集合；不在则记错并跳过删除磁盘文件。审阅者据代码推断，异常 ACK 可能重置批次外文件的三振计数；诚实服务端按请求中的文件回 ACK，因此不应将其描述为已证实的正常生产故障。此前对不同命令/信任根及 outbox 延迟的问题另行阻断，不以本候选代替。

候选是将计数删除移动至 sent 检查之后，并评估 synthetic ID、sent=nil、重复 ACK、磁盘删除失败与 rejected 分支兼容；先独立审查测试包 TestMain、环境和隔离，再以精确纯内存/专有 fixture 做真实 RED→GREEN。任何对 multica 源码的修改须按当前 `CUSTOM.md` 结构登记；未预检前不运行 daemon 整包，不使用真实 outbox、DB 或 Git。当前是否适合在既有合同下实施与测试尚待独立复核。

## synthetic rejected 与依赖预检（静态）

会话 `01a19bad-f7ce-7468-8217-4e381fe5c6b4` 只读核查指出：`applyAck` 对 `commit:` / `snapshot:` 的 rejected 直接跳过，调用链随后可能推进扫描 cursor 或更新 `lastSnapshot`；这是源码推断，尚未动态复现。另有同 CR/SHA 多 stage 事件共享服务端幂等身份的潜在冲突、同批部分失败后的顺序，以及异常 2xx 空 ACK 的完整性问题；这些不能由单独改变 rejected 处理来宣称解决。当前服务端正常响应并非已证实会给空 ACK。

`applyAck` 可作组件 seam，但 daemon 包初始化先于选中的测试：`TestMain` 创建和清理临时 HOME，部分依赖在它之前读取环境；静态依赖估算与未解析项不足以证明隔离。后续只读预检会话 `01a19c96-19fa-7597-a4bf-b69eab136a0c` 定位可精确选择的 `TestMDelivery006/applyAck_rejection_is_failure`，该测试自身使用 `t.TempDir`，不是零文件 IO；编译仍会加载 daemon 全部适用源码和依赖，且 `pkg/redact` 在 TestMain 前读取 home。该现有测试只覆盖普通 rejected，不能替代 synthetic rejected/cursor 的业务 RED。当前未运行 Go 测试、`go list`、真实 Git 或 DB，也未改 multica 源码或 CUSTOM。下一步须先核准本轮专属离线环境的依赖闭包、初始化、子进程及精确清理；`GOPROXY=off` 单独不足以覆盖继承的 direct lookup 或 telemetry sidecar，环境白名单也不是 OS 沙箱。不能把静态风险写成已实测生产故障或授权通过。

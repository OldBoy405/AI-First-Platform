# Worker 恢复重放：绑定权威原字节

> **历史快照。** 本页日志及 hash 保留为当时证据。本轮续核发现大小写正例、SQL 匹配及部分步骤断言弱于原表述，已在对应位置纠正；当前有效大小写反例、完整 SQL 比较和新运行证据见 [20261104 续修](../reconcile-authoritative-bytes-20261104/README.md)，不覆盖本页原日志。

**授权：**用户先回复“允许仅修复该关闭路径并运行内存测试”。本切片只改 `ReconcileOwnerTx` 的 journal 分支与新增内存测试；未启用 worker、未装配 C 路径、未连接数据库、未改 API/schema/启动准入、未推进 CR 或 Gate。

## 缺陷（已修复）

`../multica/server/internal/daemon/execution_control_worker.go` 的 journal 分支：

1. 只按 `request_id` 读 DB `digest`，成功后却返回 **`journal.PayloadBytes`**——核对的是 DB 标签，交还的是未经该比较绑定的本地 bytes；
2. journal 对应行查不到时继续落到链尾比较，链尾相同即返回 `ready`，把“有 journal 但记录缺失”混同成“无待核 journal”。

归档规范 `projects/multica/archive/2026-10-27-trusted-verdict-channel/canonical/specs/code/verdict-channel.yaml` 的 SC-VC-015/016 要求恢复只做固定动作：恢复原 request、导入原 verdict bytes、返回原 mapping、重放原 command，或 freeze；核对后的重发必须是原 bytes。本次按该合同实现，不新增字段、表或协议。

## 修改

- journal 行按 `request_id + lineage_id + store_id + epoch` 读出 `id::text, seq, digest, payload_bytes`。
- `ErrNoRows` → 直接 `frozen("journal_missing")`，不再落入链尾比较。
- 仅当本地 `VerdictID`/`Seq` 与记录一致、且记录 `seq`/`digest` 等于当前链尾时 `ready`，`Replayed` 用库内 `payload_bytes`；查得记录但身份、序列或 digest 不符 → `frozen("journal_divergent")`；空 payload → `frozen("journal_missing_payload")`；查询本身失败则原错误上抛，不当作恢复结论。
- UUID 身份按**值**比较：写入侧允许大写 UUID 文本，直接比字符串会把同一 UUID 误判为分叉。解析失败仍按不同处理。新增 `journal_missing`、`journal_missing_payload` 两个冻结原因（仓库内无按原因字符串分支的消费方）。

## 测试与证据

新增 `../multica/server/internal/daemon/execution_control_worker_replay_memory_test.go`：fake `pgx.Tx` 按脚本匹配 SQL 片段与参数，多跑一条查询即失败；这些测试体及 fake 路径不使用连接池、网络、文件或子进程。整个 Go 测试进程仍执行依赖初始化与 TestMain，后者创建自有 scratch home 并尝试删除，清理结果未独立核实，不能称进程零 FS。用例覆盖：

| 输入 | 期望 |
|---|---|
| DB payload 与本地 payload 不同、身份与链尾一致 | 返回 DB 原 bytes，不得返回本地 bytes |
| journal 指向不存在记录、链尾相同 | `frozen/journal_missing` |
| 同上但 `ErrNoRows` 被包装 | 仍为 `frozen/journal_missing` |
| verdict id 不同 / 本地 seq 与记录 seq 不符 / 记录低链尾一格 / digest 与链尾不同 | `frozen/journal_divergent` |
| 权威 payload 为空 | `frozen/journal_missing_payload` |
| journal 不完整 / 本地超前 | 读账本前即冻结 |
| 无 journal 且链尾相同 | 仍 `ready`（正例保留） |
| 名为本地大写 UUID 的正例 | 本快照 UUID 全数字，ToUpper 后未变化，尚未真正验证大小写差异；当前有效回归见续修记录 |
| 本地 verdict id 不可解析 | `frozen/journal_divergent` |
| 账本查询非 `ErrNoRows` 错误 | 原错误向上返回，不当作恢复结论 |
| 缺 lineage 或缺 store | `ErrWorkerInvalid`，零查询 |

该快照对 SQL 做子串检查，参数值精确比较；不能据此声称完整 SQL/列序已严格匹配。非预期 `Exec`/`Query`/`Commit`/`Rollback` 显式失败，其他嵌入接口方法未完整实现；四个顶层用例缺少步骤用尽断言。两个 seq 失配子例已分别隔离「本地 vs 记录」与「记录 vs 链尾」两个比较。完整 SQL 与缺失步骤断言在续修中补齐。

RED 用 `go test -overlay`：`red-overlay/execution_control_worker.go` 是把**当前**文件唯一的 journal 块还原为修复前形状（LF 规范化，仅该块不同），`overlay.json` 把真实产品路径映射到该副本。**未修改活体源码**做变异。

- [`red.stdout.log`](red.stdout.log)：退出 1，4 项顶层测试失败（含 4 个冻结子例）：返回 `local-bytes`、名为大小写正例的测试因返回本地 bytes 失败（其全数字 UUID 并无大小写差异）、不可解析 id 得到 `ready`（旧代码不做身份比较）、两种缺失行仍 `ready`、标识不同的行仍 `ready`、空 payload 仍 `ready`。均为行为断言失败，不是编译或权限失败。非 `ErrNoRows` 错误、两个 seq 失配、journal 不完整/超前、链尾相同正例与非法入参在旧版同样通过（前二者属旧代码已有的条件）。
- [`green.stdout.log`](green.stdout.log)：退出 0，7 项顶层测试与 9 个子例全部 PASS，无 skip。
- [`run.meta.json`](run.meta.json)：两轮 argv/cwd/退出码/`go version`/stdout-stderr hash、`gofmt -l` 结果，及产品文件、测试文件、overlay 副本执行前后 SHA-256（均相同）。当时产品 `bb9e2ec8d93b0c285c72cd659a96253111bddb5ed1694c86fa3bb24c3a858c7a`，测试 `55cbdfa60b141dabdbc0f3e014bd675e958e3b8441f9c60482450f26dd4a7c28`，overlay 副本 `f8f072a01f5ecc140769274a3437dc116da96a03e9daa994465063f5db9102fb`。哈希不能排除执行期间替换后恢复。
- 两文件 `gofmt -l` 为空。整个包测试只跑了 `-run TestReconcileOwnerTx`；包内既有 DB 用例未运行。
- 静态核对既有 DB 用例（**未运行**）：`execution_control_worker_test.go#journal_prepared_replay` 从库内读出 payload 与 `request_id` 后构造 journal，其 `VerdictID`/`Seq` 与本行一致，新查询会命中同一行并返回同一值的 bytes，预期仍通过；`divergent_freeze` 与 `execution_control_recovery_d8_test.go` 走无 journal 分支，不受影响。这是代码阅读结论，不是执行证据。

## 独立审阅与据此修正

委派前已刷新 multica STDD 配置（`schema_version=1`、`kind=configured`）：代码 strong `OpenAIPersonal/gpt-6.1-sol:high`、测试 balanced `OpenAIPersonal/gpt-6.1-terra:high`；无后端回执，actual 均 unknown。strong 会话 `01a1a41a-a5f2-7374-9f4d-464ba9b06b41` 认定无“仍返回未绑定 bytes”的漏洞，但指出 P2：`id::text` 为小写而写入侧接受大写 UUID，字符串比较会把同一身份误冻结；已改为按 UUID 值比较并补两个用例。balanced `01a1a41a-a603-7374-9f4d-464c93effdd1` 指出 fake 不校验投影顺序/WHERE、seq 失配两条件未被分别隔离、包装 `ErrNoRows` 与“缺 store”未覆盖；当时补充了 SQL 子串、四个 Tx 方法拒绝、部分步骤断言、两个 seq 隔离例、包装 `ErrNoRows` 例及双缺字段例；后续复核发现完整 SQL、全部步骤及真正大小写差异仍不足，不能称所有 finding 已闭合，见本页顶部续修链接。两路均仅静态，未独立复跑；上述 RED/GREEN 为补齐后重跑。

## 边界

未验证：真实 PostgreSQL 事务、`FOR UPDATE`/锁序、worker 的实际调用方（本次有界搜索未发现产品内非测试调用者）、启动准入、原字节与签名跨语言互操作、完整 suite。RED 依赖 overlay 副本而非历史旧源码文件；副本与 README 描述一致但由本轮构造。既有 `journal_prepared_replay` 是 DB 测试，未运行，不能据此称数据库行为已验证。归档设计的 P0 门控与 C 路径装配/启用状态不变，Gate3 仍 NO-GO。

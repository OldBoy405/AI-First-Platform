# Worker 关闭路径：有效的身份回归与精确查询替身

## 本轮最小变更

继续原“仅修复该关闭路径并运行内存测试”的授权；不启用 worker，不装配 C 路径，不连接数据库，不修改 API/schema/启动准入。

- `execution_control_worker_replay_memory_test.go` 的 verdict UUID 改为含字母的合法 UUID，大小写正例额外断言两种文本确实不同；不再用全数字 UUID 伪证大小写等价。
- fake 对 cursor 查询、当前完整 verdict 查询和唯一旧 digest 查询，先规范化 SQL 空白，再与完整 SQL 比较；参数与 Scan 列形状继续精确核对。不再用 SELECT/WHERE 子串声称完整 SQL 匹配。
- 为原先缺失的四个顶层用例补步骤用尽断言。只保留既有四个显式拒绝的 Tx 方法，不扩写与本保证无关的接口 mock。
- 产品本轮仅把上轮新增的中文注释改为英文；恢复行为和 UUID parser 没有变化，没有继续追加产品 guard 或冻结原因。

## 运行证据

Go `go1.27.1 windows/amd64`；实际 argv、白名单环境键及编译控制保存在各轮 `*.meta.json`。使用 `-run ^TestReconcileOwnerTx -json -count=1 -p=2`，不运行完整包用例；`GOPROXY=off`、`GOSUMDB=off`、`GOTOOLCHAIN=local`、`CGO_ENABLED=0`、`GOFLAGS=-buildvcs=false`。这些是执行控制，不是 OS 沙箱或产品网络隔离证明。

| 运行 | 结果 | 证明范围 |
|---|---|---|
| [green.stdout.jsonl](green.stdout.jsonl) | exit 0；7 个顶层测试 PASS，9 个子例 PASS，无 skip | 当前公开恢复函数在 fake-Tx 下通过；父子事件不累计成业务 TC |
| [journal-red.stdout.jsonl](journal-red.stdout.jsonl) | exit 1；4 个顶层失败，其中冻结表有 4 个失败子例 | 当前文件副本仅还原原 journal 块，复现返回 local bytes、缺行落回 ready 等行为 |
| [uuid-text-red.stdout.jsonl](uuid-text-red.stdout.jsonl) | exit 1；恰好大小写正例失败，其余 6 个顶层及 9 个子例 PASS | 副本仅给既有 UUID 值比较附加文本相等条件，确实造成同一 UUID 误冻结 |

两个 RED 都是 overlay 下的受控回归构造，**不是独立历史快照，也不是本轮先 RED 后首次实现产品功能**。journal 旧块取自上一轮保存的构造副本，块外使用本轮当前源码；UUID 变异保留有效代码和原解析，不用编译失败冒充行为失败。产品活体源码不被变异。

所有原 stdout/stderr 与 meta 均在本轮新目录独占创建，未覆盖 [上一轮证据](../reconcile-authoritative-bytes-20261103/README.md)。各轮输入前后 hash 相同，stderr 均 0 字节；hash 不能排除执行期间替换后恢复。

## 定向续审

balanced `01a1a45c-7be1-7374-9f4d-465850f56a7b` 静态核对当前 UUID 夹具、完整 SQL、步骤断言以及 JSONL/meta，确认本轮局部补强与记录一致；所有成功路径均核脚本用尽。requested 为 `OpenAIPersonal/gpt-6.1-terra:high`，actual unknown。没有独立动态复跑或重算全部 hash，也不凭该静态阅读证明完整产品差异仅为注释。

## 证据边界

测试体及 fake-Tx 不访问连接池、DB、网络或子进程；整个 Go 测试进程仍执行包/依赖初始化和 TestMain。后者创建自有 scratch home、设置 LOCALAPPDATA，并在结束时尝试 RemoveAll；本轮未独立核实该清理结果。因此不能称本进程零文件系统副作用或已受 OS 隔离。

尚未验证真实 PostgreSQL 行锁、事务/列解码、实际 caller、签名跨语言互操作、完整 suite 和端到端 TC。归档 P0、worker 关闭状态、资源 HOLD 和 Gate3 NO-GO 不变。

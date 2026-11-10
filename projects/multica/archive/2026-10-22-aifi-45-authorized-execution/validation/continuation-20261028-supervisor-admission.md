# 本轮续做：supervisor 收集与准入异常清理

## 门禁状态

Gate3 **NO-GO**；`TC-EVD-008`、`TC-RUN-001/003/006/007` 仍 MISSING，M001–M004 未改为 resolved。历史 44/49 是命名 CP 命令/断言台账快照，不是端到端验收计数。信任判定通道是用户负责的独立后续 change，本轮没有创建、实现或生产接线。

## 有限进展

- `multica/scripts/aifi45-db/supervisor-collector.mjs` 是 fake I/O 事件收集器，限制 stdout、丢弃 stderr 内容、双 EOF 后解析；没有接真实进程、容器或清理器。decoder 临时私有副本通过非池化分配并在退出时清零。强化测试覆盖指定失败与若干额外分配变异；不能证明所有副本、被丢弃未收尾 collector 或真实管道安全。Buffer 原型伪装的非字节 typed array 被拒；字节数组伪造原型仍通过，身份不认证。
- 当前 8 个 fake I/O 文件作者跑 207/207、0 skip；当前关键 4 文件独立跑 45/45、0 skip。该结果不是容器生命周期或真实进程退出证据。详细作者和审阅材料在 `ci-supervisor-collector-review-20261028/`，各报告按原始 SHA 区分旧、新快照。
- `multica/server/internal/governance/execution_admission_gate.go` 的未交接事务 guard 前移；统一回滚尝试使用独立 5 秒 context，普通错误路径也走同一 guard。未成功或超时回滚不证明服务端锁已释放。无 DB 源码测试独立 2/2；DB panic/锁回归仅编译、未运行。交接后持锁 effect 路径、网络故障及真实服务端行为未验证，不能当 RUN-006 验收。详见 `admission-cleanup-20261028/`。
- 双 Job kill-on-close 源码尝试因无法证明安全清理而未写入；没有进行该实验。membership/natural-exit 先前证据不能升级为进程树或容器安全证明。

## 阻塞及需要真实事实

- 已获独占新 PostgreSQL 容器的授权，但容器的可信引擎 adapter、持久 journal、进程树/目标身份和安全清理资格尚未闭合；Windows Job 不证明 Podman Linux VM 内 PostgreSQL 退出。不得启动或清理真实容器，不得绕过 TestMain。
- 可信 verdict channel 仍需由用户另行推进；没有该依赖不能把静态桥接或局部测试升级为 RUN-001/003 生产闭环。
- EVD-008 已有 D9 deviation 意向，但后续变更真实 ID、owner、触发机制和正式必要审批尚未建立。不能代填虚构事实；依赖用户提供真实归属和登记安排。
- RUN-006/007 的权威事实、生产入口、准入/消费语义和安全隔离 DB 证据仍缺；X6 收件/授权/旧版本隔离等仍未获闭合。

本轮未做 commit、push、部署、真实 CR、数据库或容器操作。三仓 `git diff --check` 通过；multica `CUSTOM.md` 保持 LF，tools `CUSTOM.md` 保持 CRLF。静态检查不覆盖未跟踪文件的全部内容。

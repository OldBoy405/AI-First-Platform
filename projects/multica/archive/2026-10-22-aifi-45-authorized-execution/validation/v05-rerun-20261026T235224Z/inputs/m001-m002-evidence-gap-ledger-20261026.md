# M001/M002 证据缺口台账（2026-10-26）

> 目的：把 `pending-adjustments.yaml` 的 ADJ-AIFI45-M001 / M002 与 Gate3 安全轴 major 逐条对齐，
> 分清「现在就能在 AIFI-45 内产出的证据」与「必须等 M003 可信通道的事实」。
> 本文件只盘缺口与分类，不新增代码、不跑 DB、不改任何 pending-adjustments 的 `resolved` 字段。

## 0. 口径

- 「证据」= 可复跑的产物：DB 用例（`scripts/aifi45-db/run.mjs`，`skip=0`）、tools 用例、或带 sha 的只读核查记录。
- 「描述性结论」不算证据；「静态成功」不算验收（M002 原文：静态成功仍 `EXECUTION_CONSUMPTION_REQUIRED`）。
- 分类：**A=本 change 内可产出**；**B=需 M003 可信事实**；**C=需部署/真实 CR 授权**（当前授权外）。

## 1. 缺口清单

| # | 缺口 | 来源 | 现状 | 分类 | 产出方式 |
|---|---|---|---|---|---|
| G1 | claim TOCTOU：读到 active generation 后暂停，另一事务取消/重领 task 或改 runtime 归属并提交，原事务仍可写 receipt/activation（共享 helper 只锁 CR/head record） | 安全轴 major（`execution_consumption.go:99,129`、`execution_activation.go:89,121`、`execution_binding.sql:7-20`） | 未修 | **A** | 三写端点共用完整校验事务；按与 claim/reclaim 兼容锁序锁 task/runtime 及归属行并持锁至提交；用 `lock_timeout` 探针（只认 `55P03`）+ 并发用例取证 |
| G2 | 拿别次签发换本次消费：活动 B 用 A 已签的 challenge C 请求 consumption；只查 workspace/CR/head/C 存在；同 task 重领后可复用 | 安全轴 major（`execution_consumption.go:164-168`、`execution_binding_issue.go:251-255,295-299`） | **部分已修**（B1：643 加 `dispatched_at`、INSERT 带该列、`executionBindingIssueMatchesRequest` 比对 task/runtime/dispatched_at/daemon、consumption EXISTS 加三谓词） | **A** | 残余：签名 payload 仍不含 `dispatched_at`；补「同 task 重领后旧 issuance 复用」反例 |
| G3 | strict 可降级：`context.execution.contract` 为 null/空/类型错即当「不声明合同」，`strict=false` 后跳过 claim/安装检查；无服务端持久化合同 | 安全轴 major（`pipeline_task.go:568-583`、`execution_verifier.go:27,47-51`） | 未修 | **A/B 混合** | 显式块缺字段/null/类型错一律拒绝（**A**，纯本地判定）；「strict 必须来自可信 task/run 合同」的持久化合同读（**B**，M003 受保护 store） |
| G4 | 终态 fence 可自行退出：持 workspace daemon 凭据的旧回调省略 runtime/dispatched_at 即 `enforce_claim=false`；task 已重领后旧 `/fail`/`/complete` 仍走状态型 CAS | 安全轴 major（`daemon_terminal_claim.go:41-43`、`service/terminal_claim.go:26-28`、`agent.sql:1264,1438`） | **部分已修**（B3：`terminalFenceBlocks` + 同事务判定，`to_regclass` 探测兼容未迁移部署） | **A** | 残余：服务端读持久化合同对 strict task 强制完整 tuple、拒绝无代次回调；补「省略 runtime/dispatched_at 的旧回调」反例 |
| G5 | 终态与 adoption 竞态：adopter 普通 SELECT 读到 open → 另一事务标 terminal → adopter 无 `terminal_at IS NULL`/generation CAS 的 UPDATE 仍返回非终态成功；两个 adopter 可覆盖 mapping；该 helper 未见生产调用点（潜伏） | 安全轴 major（`execution_dispatch_root.go:158-200`） | 未修；disposition 将 B8 归 M003 | **A**（竞态本身是本地 DB 锁问题，不需要可信事实） | 根读加锁、UPDATE 附终态与期望 generation 并用 `RETURNING`、受影响行数为零即拒；`55P03` 探针 + 双 adopter 并发用例 |
| G6 | 可信 current-head / 撤销 / DB claim / 隔离控制通道 / 不可删 activation / 消费事务 | M002 正文 | 未取证 | **B** | 归 M003：可信 T 裁决通道 + 受保护 store；AIFI-45 只保留既有拒绝侧用例（不得据此标 PRESENT） |
| G7 | 完整认证链 / 当前绑定 / 消费 / 调度链验收；真实 HTTP 冻结与重投；原始人类事件 digest/附件/字段映射合同；daemon 资源根严选 | M001 正文 | 部分（daemon 安装授权记录已接生产 `handleTask→prepareClaimedPipelineTask`，见 M002 历史段） | **A/B 混合** | 真实 HTTP 冻结/重投的端到端用例（**A**）；原始事件合同与当前绑定权威确认（**B**） |
| G8 | 真实部署与真实 CR 授权（隔离执行位置、公钥/授权文件不落 agent 可写集的正反向验证） | M002 `impact_scope` | 未取证 | **C** | 需部署授权；不在当前授权范围内 |

## 2. 依赖关系

- G1/G2/G4/G5 相互耦合：都要求「task/runtime 归属行 + head record」在同一锁序下持锁至提交。**先画锁图再动手**
  （既有 `validation/lock-graph-20261026.md` 只覆盖 bind↔consume 与 B3；G1/G5 需要补 task→runtime→CR head 与 dispatch_root 两段）。
- G3 的本地半（显式拒绝 null/空/类型错）可立即做，不依赖 M003；持久化合同半依赖 G6。
- G6 是 M003 的前置；G6 不闭合前，RUN-002/003/006/010 与 AUTH-004/006 的公钥/授权文件面保持 MISSING。

## 3. 下一步（按依赖排序，均需 DB runner）

1. 补锁图两段（task/runtime 归属、dispatch_root），确认单调性（重领、换 generation、换账本位置）。
2. G5：`execution_dispatch_root` 加锁 + `terminal_at IS NULL` + generation CAS + `RETURNING`，先 RED 后 GREEN。
3. G1：三写端点共用校验事务，`55P03` 探针并发用例。
4. G2 残余：签名 payload 补 `dispatched_at`；同 task 重领后旧 issuance 复用反例。
5. G4 残余：strict task 强制完整 tuple + 拒绝无代次回调。
6. G3 本地半：contract null/空/类型错一律拒绝（含正反例）。

## 4. 本文件未做的事（不得冒称）

- 未修改任何 Go 代码、未运行 DB 用例、未改 `pending-adjustments.yaml` 的 `resolved` 字段。
- 未关闭 M001/M002：两者 `severity: major`、`resolved: false` 的状态保持不变。
- 分类为 **A** 的项只代表"技术上不需要可信事实"，不代表已实现或已验证。

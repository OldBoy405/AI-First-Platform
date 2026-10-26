# AIFI-45 — task claim 的 runtime 归属子组件

> **STOP：独立扩大回归发生历史漂移83→82（missing41/extra40）。不是完整验收通过；暂停DB写入/后续接线，等待原始备份或新隔离库授权。原42保护集完整。事故与事实修正见[事故记录](claim-build-20261024T153817Z-incident.md)。**

## 授权与范围

- 沿用 Gate 1/2、普通 BUILD/in_progress；用户要求继续主线、能并行则并行，不重复索取已批准方向的确认。
- 主会话实现；两个 balanced 只读调查分别核 task claim 和每 repo 当前身份，不另派普通实现作者。
- 本片只补 **带 generation 的 StartTask：认证 daemon → 当前 DB runtime 归属 → 同事务启动/重投**。不签新 receipt，不授予 T 消费资格，不将 mdt 持有人当隔离 daemon。
- 无共享 DB、真实 CR、生产迁移、环境升级、Gate 3、commit、push 或部署。

## 真实调用链与改动

- `handler.StartTask` 保留现有 UUID/时间精度校验；workspace 由 `requireDaemonTaskAccessWithWorkspace` 从服务端 DB 解析，daemon ID 只取 `DaemonAuth` context，不用 body/header 自报值。已存在 daemon workspace 而 daemon ID 为空时 403。
- `TaskService.StartTaskForClaim` 增加服务端 workspace/daemon 参数；同一事务先复用 `LockAgentRuntime`，核 runtime 的 workspace/daemon，再执行 `LockAgentTaskStartClaim(task_id,runtime_id,dispatched_at)`；非拥有者首次启动和 running 重投都 409。提交前保持 runtime 锁。既有用户/PAT 路径可无 daemon ID，但不被认作可信 daemon 绑定。
- 没有新增表、迁移、SQL 查询或手编生成物。legacy 无 generation 分支原样保留，**不能用该分支提供新合同的可信 claim，防降级仍未闭合**。
- 新增 `server/internal/governance/execution_start_claim_test.go`：从真实 DB `daemon_token` 经真实 `DaemonAuth` 到公开 StartTask handler，不注入 auth context/cache。两 token 同 workspace，body/header 伪报 owner 不改变鉴权身份。
- 既有 `daemon_start_claim_test.go` fixture 改为每测试自建、带真实 daemon ID 的 runtime/agent，不再把无 daemon 身份的共享 cloud runtime 当成拥有者。
- 安全前置：旧 handler TestMain 会按固定 email/slug 清历史，因此在跑其回归前修为每进程 UUID email/slug、setup 单事务、只按本进程创建的 user/workspace 精确 ID 清理。此修改仅测试 harness；不回收其它 fixture。
- `CUSTOM.md` #166、M11 索引/位置/19 行已登记。

## 作者 RED → GREEN

证据前缀均为本目录 `claim-build-20261024T153817Z-`，保存原 go JSONL、stderr 与 argv/exit/count 元数据，wx 新建，不覆盖失败证据。

| 阶段 | 公开 seam / 断言 | 实测 |
|---|---|---|
| `red1` | 同 workspace 外来真实 mdt，持精确 runtime/generation，必须不能启动 | 实际 HTTP 200/running；1 RUN、0 PASS、1 FAIL、0 SKIP、exit1 |
| `green1` | 外来者首次/replay 409，拥有者首次/replay 200 | 1/1、exit0、0 SKIP |
| `green2` | 上述行为 + 空 daemon identity403 + 并发归属变更 | 3/3、exit0、0 SKIP；是父1+子2事件，不是3条完整TC |
| `handler-green` | 既有 `^TestStartClaim`，含 generation/reclaim/丢响应/并发/cancel/precision/legacy | 13/13、exit0、0 SKIP |

竞态不是靠 sleep 猜：事务先 UPDATE 拥有的 runtime 行，启动请求并发进入；用该事务的 `pg_backend_pid()` 与 `pg_blocking_pids()` 确认实际 `LockAgentRuntime` 等待，再提交归属变更，旧拥有者得到409。5ms轮询仅等待已存在的锁，不代替并发断言。

## DB 单执行者与完整历史

- 批准容器完整 ID：`666bfec52ac3c3d13b43389891f50c4105833198eab7e4167b76f014a774e823`；change label、127.0.0.1:55432、DB/user 每轮由既有 harness 核对；凭据仅内存，不打印/落盘。
- T validation 同前缀 `-db-before.json` 保存 83 条全部 `approval_record` 的 ID + `md5(row_to_json(a)::text)`（全行，不只 grant_json）。baseline42 是这 83 条的历史子集，不以新计数覆盖旧证据。
- 作者 `green2` 后 `-db-handoff.json`：83/83 全行一致、locks0/session0。
- handler 回归后 `-db-before-independent.json`：2026-10-24T16:07:13Z，83/83 全行一致、locks0/session0，移交 balanced 为唯一 DB 测试执行者；主会话随后不访问 DB，strong/economy 只读。

## 独立复核（未完成不得计 PASS）

- strong `01a16ea6-cece-77b9-a3c5-0ed3fe85bcac`：两轮均 **INCOMPLETE**；所读鉴权/claim锁链未发现新增问题，但未穷尽修改runtime路径/FK/teardown及独立测试核验，不能当完整静态PASS。
- balanced `01a16e9e-57a0-77b9-a3c5-0ecf5eddf4f0`：串行治理817/817、handler claim13/13、daemon48=47PASS/1 symlink权限SKIP，均exit0；批后却83→82/missing41/extra40，立即STOP且locks0/session0后释放。此批不得验收。作者-source与独立source5/5一致，和实施前before-manifest的预期差异不构成源码漂移，见补充forensics。
- economy `01a16ead-df26-77b9-a3c5-0ed405ed3e7e`：已核计数/主报告内部边界，CUSTOM正文/跨仓链接未完成，不当整体验收PASS。
- 原生两项目 `stdd config models --format json` 均 exit0、schema_version1/kind=configured；T/M validation 保存同前缀 `-models.json`。请求映射 strong=OpenAIPersonal/gpt-6.1-sol/high、balanced=Gobao/deepseek-flash/max；actual 无后端回执均 unknown。主会话 harness 三键 unknown，不据此伪称同档，也不为普通实现强行增加作者。

## 后续与不变量

- 每 repo 当前身份调查确认：签发时已有去重资源 FOR SHARE 校验；现有资源 API 可复用 `NewProjectResourceBinding`。缺口在消费前回读每个当前 descriptor，不能把旧 roots 投影当当前身份；需先解决历史事故和安全测试环境，当前不继续该片。
- 当前 project/原始 claim receipt、每 repo 当前绑定、隔离控制域、不可删 activation、legacy 新合同防降级、T 消费事务、dispatch/adoption/wake 仍未闭合。
- 业务完整 TC **0/49**、5 major unresolved、消费关闭；本片组件通过不勾整 TC/slice，不改变 Gate 或质量配置。

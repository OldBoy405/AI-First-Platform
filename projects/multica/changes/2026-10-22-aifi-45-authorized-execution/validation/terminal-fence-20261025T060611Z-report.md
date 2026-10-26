# 终态 callback 代次 fence — 纵片报告（进行中）

前缀 `terminal-fence-20261025T060611Z-`。原库事故现场 HOLD；本片所有测试仅经版本化 `scripts/aifi45-db/run.mjs` 建 schema-only nonce 库 + 受限 role，逐条 pre-run pin 源码、后核原库与资源。

## 1. 实际缺陷（先复现，后修）

| # | 缺陷 | 真实证据 |
|---|---|---|
| D1 | 旧代次 `fail` 回调可终结已重领的新代次运行 | `fail-red1` 1RUN/1FAIL：HTTP 200 且 `status=failed` |
| D2 | 旧代次 `complete` 回调可完成已重领的新代次运行 | `complete-red1` 1RUN/1FAIL：HTTP 200 且 `status=completed` |
| D3 | 终态幂等回放只比 runtime/代次/状态，**同 workspace 另一 daemon** 用同 tuple 回放得 200（strong 发现 P2） | `foreign-replay-red1` 1RUN/1FAIL |
| D4 | retryable `fail` 在 CAS **之前**构建 Composio overlay，会真实 POST 创建外部 session；DB 回滚不撤销外部资源 | `overlay-red2` 1RUN/1FAIL（`BuildTaskOverlay` calls=1） |
| D5 | daemon 终态 sender 不携带 `runtime_id`/`dispatched_at`；outbox 丢 tuple；同 task 两代互相覆盖 | `sender-store-red1` 6RUN/6F |
| D6 | 已验证 claim 的 run 发出的终态回调仍为 legacy；`acknowledge` 与文件名未按代次键 | `daemon-attach-red1` 1RUN/1FAIL；`daemon-attach-green1` 7RUN/6P/1F（实现自身遗漏） |
| D7 | strong daemon 评审 F1/F2/F3/F4：runtime-offline 早退降级 legacy、taskID 缓存可把新代 tuple 附到旧代结果、single-flight 按 taskID 丢新代、缓存可耗尽 | `finding-red1` 4RUN/2P/2F（另 2 例为守护 PASS） |
| D8 | 把 tuple 改成「task 有值就发」后，**普通 PAT 认证的 daemon** 也会发 strict body，而服务端 strict 路径要求真实 MDT ⇒ 403，终态回调永不落地（strong 复核新增 P1） | `n1-red1` 3RUN/1P/2F（PAT 与 nil-client 均被错误升级） |
| D9 | `copyClient := *c` 复制含 `sync.Mutex` 的 `Client`，`go vet` 报 "assignment copies lock value" | 作者自查 + `final2-vet.json` exit1（修后 `final5-vet.json` exit0） |
| D10 | `PAT daemon + strict/runtime-offline` 仍发 legacy；且 `strictExecutionContract` 解析出错时守卫被跳过 | `n2-red1` 3RUN/1P/2F → `n2-green1` 84/84（78 leaf）→ `n2b-green1` 91RUN/90P/1 SKIP（84 leaf） |

## 2. 修法（最小面，不新增锁序/表/迁移）

- **服务端 CAS**：在既有 `CompleteAgentTask`/`FailAgentTask` 的 `WHERE` 上追加上 `enforce_claim` 与 exact `runtime_id`/`dispatched_at`/认证 workspace/daemon 谓词；`false` 保持旧调用语义。未新增前置 task/runtime 行锁，未改签名字节/head/历史。sqlc 用 Makefile 固定版本 v1.31.1 原生离线生成（`make sqlc` 的 `go run …@v1.31.1` 在 `GOPROXY=off` 下因 deprecation lookup 失败，证据保留；改用同版本本地二进制，先存生成前全量字节 archive，规范化后仅 `agent.sql.go` 变化；首轮生成因 `id` 歧义失败且未产出，已保留）。
- **服务层**：`TaskTerminalClaim` + 可选 variadic claim 参数；strict 路径要求真实 `TxStarter`、≤6 位小数、非空无控制字符 daemon；CAS 零行即事务回滚（既有 `runInTx`），active/mismatch 返回 `TASK_TERMINAL_CLAIM_REJECTED`；终态幂等改由单条 scoped SELECT 重新核 owner/scope 后才 200。
- **HTTP 边界**：新增 strict body 解码（两键同时有/无、canonical 大小写、`governance.ValidateExecutionJSON` 完整 JSON + EOF、canonical UUID、严格时间 token），要求真实 MDT + 认证 workspace。无字段路径保持旧解码（legacy）。
- **daemon**：tuple 随 run 的 context 传递 —— `handleTask` 入口 stamp，`reportTerminalTask`（唯一发送汇聚点）读取；**取消了 taskID 缓存**（F2/F4 结构性消除）。single-flight 改按 `deliveryKey`（每代）。client 注入两键 + 仅本调用禁 redirect（只复制 `http.Client`，不复制含 mutex 的 `Client`）。**仅当 daemon 自身持 `mdt_` daemon token 时才升级 qualified**，PAT/nil client 保持 legacy（否则服务端 403 会让回调永不落地）。outbox record v3 显式 `claim_mode=generation|legacy`；v1/v2 仍解码为 legacy；quarantine 的 complete→fail 补偿复制 tuple；文件名/ack/reject/temp 恢复统一按 `deliveryKey`。
- 事实：批量 claim 响应在 `task.DispatchedAt.Valid` 时总会下发 canonical 代次（`handler/daemon.go:2730-2735`），且 `dispatched_at` 只在 claim 与「未启动的 dispatch 恢复」两处刷新 ⇒ 对已启动运行，tuple 稳定。

## 3. 作者证据（组件级，不计业务 TC）

见 `plan.md` 的 tag 表。关键终点：`http-green1` 15/15（14 leaf）、`finding-green2` 39/39（35 leaf，含 daemon sender/outbox/早退/双代/重放）。

## 4. 独立回归（冻结链，只认最后一轮）

| 报告 | 冻结 | 结果 | 认领 |
|---|---|---|---|
| `independent2-report.md`（`41faa3ed…`） | 第 1 个（`4140b311…`） | governance 868/867/0/1（785 leaf）、handler 13/13（10）、daemon 116/115/0/1（107） | ❌ 历史 |
| `final-independent-report.md`（`9ea232fe…`） | 第 2 个（`f341dbff…`） | 879/878/0/1（795）、13/13（10）、120/119/0/1（111） | ❌ 历史（N1 前） |
| `final3-independent-report.md`（`a315dc03…`） | 第 3 个（`ecccf1ff…`） | 879/878/0/1（795）、13/13（10）、122/121/0/1（113） | ❌ 历史（N2 前） |
| `final4-independent-report.md`（`366a4c59…`） | 第 4 个（`bfb95c31…`） | 879/878/0/1（795）、13/13（10）、125/124/0/1（115） | ❌ 历史（N2 残余前） |
| **`final5-independent-report.md`（`23fcb892…`）** | **第 5 个（`53bff392…`）＝最终源码** | **governance 879/878/0/1（795 leaf）、handler 13/13（10 leaf）、daemon 125/124/0/1（115 leaf）** | ✅ **本片唯一认领** |

每条均：独占 schema-only nonce 库+受限 role、执行前后 27/27 源码 pin 一致、原库 137 表/6228 行/82 审批 ID+hash 与冻结基线完全一致、`sessions=0`/`locks=0`、精确资源清理且末尾 catalog 均不存在。两处 SKIP 未计 PASS：`TestReconcileLiveGitHub`（缺 `KNOWLEDGE_BASE_REMOTE_URL/TOKEN`）、`TestExecutionTrustRefusesLinkedRootInsideWorkspace`（Windows symlink 权限）。

宿主终局静态：`final5-vet.json` vet exit0；`final5-host-audit.json` 27/27 无漂移、四项保护文件 hash 不变、两仓 `main` 且 staged 空、`git diff --check` 通过、文档链接无悬空。

## 4b. strong 评审链

`fail-strong.md`（fail 范围，1 项 P2 → 已修）→ `daemon-strong.md`（REQUEST_CHANGES：F1/F2/F3/F4）→ `daemon-strong-resume1.md`（F2/F3/F4 CLOSED、F1 PARTIAL、新增 N1=P1）→ `daemon-strong-resume2.md`（N1 CLOSED、vet 修复 CLOSED、新增 N2=P1）→ `daemon-strong-resume3.md`（N2 PARTIAL：strict 解析错误未覆盖；prepare 前早退清单仅 `!tracked` 一处）→ `daemon-strong-resume4.md`（**N2 残余 CLOSED**，附 11 行限定结论）。

## 5. 仍未关闭（不得由本片签 PASS）

- **legacy 无字段路径仍被服务端接受**：这本身是「不可删 activation / 防降级」major 的入口，本片未关闭；旧 daemon 仍可发 legacy。
- **有效代次 + 事务失败时的 Composio 外部 session 泄漏**：`terminal-fence-20261025-retry-overlay-facts.md` 已确认是真实 POST 且无撤销；建议的无锁方案（先 deferred `fire_at` 建 retry、事务后回填 overlay 再激活）**未实现**。
- **动态并发**：CAS 与 scoped SELECT 之间的快照 race 无动态证明；静态结论不外推。
- **完整 terminal 链**：恢复/补偿、wakeup、system cleanup、Builder rebind 等仍属旧 claim INCOMPLETE 范围。
- **同代 complete 与 fail 并发**：`deliveryKey` 不含 kind，若同代同时产生两种终态，第二个会被 single-flight 拒绝而不落盘（strong 判定未新增缺口，但也不保证落盘）。
- **daemon PAT 认证的任务**：按 N1 修复保持 legacy（服务端 strict 只认 MDT）；因此对 PAT daemon 而言，防降级仍依赖后续 activation major。
- 完整业务 TC **0/49**、5 major 未关闭、`EXECUTION_CONSUMPTION_REQUIRED` 仍关闭消费；Gate3/提交/推送/部署未获授权。

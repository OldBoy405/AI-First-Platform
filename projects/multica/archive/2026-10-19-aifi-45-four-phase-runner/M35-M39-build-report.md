# AIFI-45 M35–M39 — build report

## M38a — pending 公钥响应（TC-MKEY-001 服务端半）

### 实现（仅 `internal/governance/approval.go` + `approval_test.go`）
- `HandleGrantsPending` 在既有 `/api/daemon/approvals/pending` 响应中新增同响应 `public_key:{key_id, pem}`：
  - `key_id` = `ApprovalService.keyID`（当前签名 key id，与 grant 的 `key_id` 一致）；
  - `pem` = 既有 `PublicKeyPEM()` 产出的 SPKI `PUBLIC KEY` PEM；未复制/重写密钥逻辑。
  - `grants` 数组结构与 `ORDER BY created_at` 顺序不变，仅追加顶层字段。
- 安全语义：公钥只来自服务端构造时的配置；`a == nil`、`keyID == ""` 或 key 长度非法、`PublicKeyPEM` 失败时返回既有 JSON 错误（500 `{"error":"approval signing key unavailable"}`），不返回空 pem 冒充可用。
- **未改** ack 续接（`HandleGrantsAck`/continuation 属 M50）；未改 handler/daemon/service/tools/DDL/event/`transitions_gen.go`。

### 测试（`approval_test.go::TestMKey001`）
- 同响应存在 `public_key`，`key_id` 等于当前 signing key（`approval-test`），`pem` 经 `pem.Decode`+`x509.ParsePKIXPublicKey` 与 `newTestApprovalService` 的公钥逐字节一致；
- 本 CR 的两条 grant 顺序按 `created_at`（tech-design → requirement），`id/cr_id/stage/grant` 字段完整，grant 内 `key_id` 与 `public_key.key_id` 一致；
- 无 key/keyID 的 service（`NewApprovalService(pool,nil,"",...)`）→ 500 且返回 error，响应不含 `public_key`。

### RED / GREEN
- RED `.../aifi45-m35-m39-evidence/m38a/red.log`：exit=1，RUN 1，fail 1 —— `public_key.key_id = "", want current signing key "approval-test"`。
- GREEN `.../m38a/green.json`：exit=0，RUN 1 PASS。
- 回归 `.../m38a/regression.log`：`TestMKey001 + TestGrantDeliveryQueue + TestApprove* + signing/digest` exit=0（1.533s）；`vet.log` exit=0。

### 边界
- 未改 M37b/daemon 多 workspace 投递；未提前删除 ack 续接（M50）。
- 共享测试库存在其它测试遗留的 pending grants：测试只断言本 CR 的 grants 子集及其相对顺序。
- 未 commit/push；完整整包留 Main。

## M36 — heartbeat 快照驱动 collector 生命周期

### 实现
- `crevents.go`：collector 增加 `rootsMu` + `identities{workspace\x00daemon -> roots}`：
  - 非空快照**整体替换**该身份 roots（不累积），`resources:[]` 删除该身份；
  - nil/外层 null/`resources:null`/非法快照保留原 roots；
  - `settleRoot`、`collectAll`、`deliverGrants` 全部读当前动态投影；
  - 空投影 collectAll 安全空转。
- `daemon.go`：
  - collector **无条件**启动并跑 `crEventsLoop`，不再依赖 `CRWorkspaceRoots` 非空；
  - `handleHeartbeatActions` 消费 `resp.LocalDirectorySnapshot`，失败只 warn 保留旧 roots；roots 变化时立即触发一次现有 collectAll（无新 goroutine 系统/第二执行器）。
- `config.go`：`LoadConfig` 启动即拒绝 `MULTICA_CR_WORKSPACES`（明确错误），不再从 env 解析 roots；`Config.CRWorkspaceRoots` 仅保留内部 pipeline 夹具用途。

### 测试
- `TestMKb003`：A 根替换不累积；A 清空不影响 B；nil/null 保留。
- `TestMKb005`：冷启动无 roots 不阻塞；晚到快照接管并采集；重连重复快照不重复投递。
- `TestMKb007`：env 残留 helper + `LoadConfig` 双重拒绝；显式空快照不泄漏 env 根。
- RED：把替换改成 append，`TestMKb003` 实际失败 `replace accumulated roots: [...001 ...002]`。
- GREEN：3 RUN / 3 PASS；相关 collector 回归 10 RUN / 10 PASS。
- daemon 整包：native exit=1；1032 父 RUN；父 pass 897 / fail 61 / skip 74；子 pass 855 / fail 1 / skip 12；总 62 fail、86 skip。**62 failure 与 Main 已核实的既有 Windows 环境基线数量一致**，M36 三个测试均 PASS；未出现新的 M36 相关失败。
- vet / build / diff-check = 0。

### 边界
- 快照只在内存中按 workspace+daemon 保存，未新增持久根账本/表/列/flag。
- 快照资源仅取合法绝对 `resource_ref.local_path`；路径合法性与 KB 识别仍由既有流程。
- 未改 handler/governance/service/pkg/protocol/DDL。

## M37a — 同源根视图与统一 CR not found 诊断

### 实现
- `crevents.go`：新增统一 `crRootViewEntry{workspace_id,daemon_id,root,source}`：
  - 生产来源为 M36 snapshot 投影；无 snapshot 身份时才暴露 config-fixture（仅测试）。
  - `rootViewsForTask` 按 task workspace/daemon 过滤；`containsRoot` 用 realpath 归一化比较，不再字符串 `Contains`。
- `pipeline_task.go`：
  - pipeline 非 archive 定位改走 `d.findPipelineCRRootForTask`，候选来自同一 root view；
  - archive 定位改走同一视图；
  - 零/多根/无 CR 错误统一附加 `workspace_id/cr_id/candidate_roots/daemon_id/runtime_id/projection_source`；
  - 保留原 project containment/reparse/realpath 去重规则；普通任务绑定路径未放宽。
- `daemon.go`：终态 settle 从同一 view 取候选；未 watch 和“root 在但 CR 文件缺失”都输出同一组诊断字段；采集仍照常运行，不因诊断失败丢 outbox。
- 不新增运行时报告、表、状态或权限扩展。

### 测试
- `TestMKb008`：同一 workspace 有 root 但无 CR 目录：
  - pipeline 定位错误包含 workspace/CR/root/daemon/runtime/snapshot；
  - settle 日志包含同一组线索；
  - 定位报 `found 0`。
- RED：临时移除定位诊断后缀，实际失败 `locator diagnostic missing "workspace_id=ws-m37"`。
- GREEN：1 RUN / 1 PASS；相关 pipeline/collector/MKb 回归 13 RUN + 14 subtest 全 PASS。
- daemon 整包：native exit=1；1033 父 RUN；父 pass 898 / fail 61 / skip 74；子 pass 855 / fail 1 / skip 12；总 62 fail / 86 skip，**与 M36/Main 已核实 Windows 环境基线同数**；`TestMKb008` PASS。
- vet / build / diff-check = 0。

### 边界
- 普通（非 pipeline）任务绑定与 workspace 权限未改；root view 仅用于 pipeline 定位/采集/settle。
- 采集本身不知道具体 CR；同一诊断在 settle 入口输出，保证与 pipeline 定位同源同字段。

## M37b — 请求级 workspace 路由与 ack 批次隔离

### 实现
- `client.go`：新增 context 级 `workspaceHeaderKey`；共享 Client 不保存全局 workspace。所有 POST/GET 请求在构造时从当前 ctx 设置 `X-Workspace-ID`。
- `crevents.go`：
  - `collectRoot` 用同一 root view 解析当前 workspace，包进请求 ctx → `ReportCREvents` 带正确 header。
  - 每批发送前记录本批文件集合；`applyAck` 只删除/计数本批文件，批次外 accepted/rejected 一律拒绝并记录，不误删他批。
  - `deliverGrants` 按 workspace 分组：每组独立 FetchPendingGrants / 写该组 roots / AckGrants，均带该 workspace context。
- `daemon.go`（最小接线，超出字面文件列表但 heartbeat 需要）：HTTP heartbeat 与 pending-work hint 的 `SendHeartbeat` 调用按 `runtime -> workspace` 包 ctx；未改 wakeup.go。
- 无全局 workspace setter、无新表/状态/flag。

### 测试
- `TestMKb006`：
  - 两 workspace 并发 collectRoot，假服务端断言每请求 header 与事件 CR 对应（ws-1/ws-2），并验证 heartbeat header；
  - ack 返回批次外 `foreign.json`，断言不删除且 collect 报错；
  - deliverGrants 两 workspace 的 pending fetch/ack 各带自身 header。
- RED：临时去掉请求 header 设置，实际失败 `workspace headers = ws1:"" ws2:""`。
- GREEN：1 RUN + 3 subtest 全 PASS；相关 collector/pipeline 回归 15 RUN + 3 subtest 全 PASS。
- daemon 整包：native exit=1；1034 父 RUN；父 pass 899 / fail 61 / skip 74；子 pass 858 / fail 1 / skip 12；总 62 fail / 86 skip，与已知 Windows 环境基线同数；`TestMKb006` PASS。
- vet / build / diff-check = 0。

### 边界
- 为 heartbeat 请求级 header，需在 `daemon.go` 两个既有 `SendHeartbeat` 调用点包 workspace ctx；这是列明文件之外的唯一改动，未改 heartbeat 协议或全局 client。
- ack 批次外文件被拒后 collectRoot 返回错误（cursor 不前进、下轮重试），属保守失败语义。

## M38b — grant 唯一目标 / 传输信任 / key 前置

### 实现
- `crevents.go`：
  - `pendingGrantsResponse` 增加 `public_key{key_id,pem}`；校验非空、SPKI PEM、ed25519。
  - key 不可用 → 整个 workspace 批次不写、不 ack。
  - grant 内嵌 `key_id` 必须与服务端 `public_key.key_id` 一致；缺失/不一致拒绝该 grant。
  - 每条 grant 用同一 root view + 唯一 CR 根解析，且只在该 workspace 组内；零/多根/跨 workspace → 记诊断、拒绝该 grant，不再广播、不再“任一成功即 ack”。
  - 先验 key → 写完整 grant → 才收集 ID 并 ack。
  - `validateTrustedServerURL`：远程必须 https；http/ws 仅回环允许；`deliverGrants` 首次投递前拒绝不可信来源。
- `client.go`：`GrantSourceURL()` 暴露 base URL；未放宽 TLS。
- `wakeup.go`：`taskWakeupURL` 复用同一信任校验，远程明文 http/ws 拒绝。
- 本轮未做公钥原子落盘/旧 key 处理（M39）。

### 测试
- `TestMKey003` 8 subtest：唯一写+ack、零根拒绝、歧义双根拒绝、跨 workspace 拒绝、远程明文 http 拒绝、回环 http 允许、wakeup 远程明文拒绝、key 缺失整批不投递。
- RED：临时让解析失败回落第一个 root，实际 zero/ambiguous/cross 三个子例被写入并 ack。
- GREEN：1 RUN + 8 subtest 全 PASS；相关 collector/wakeup 回归 12 RUN + 15 subtest 全 PASS。
- daemon 整包：native exit=1；1035 父 RUN；父 pass 900 / fail 61 / skip 74；子 pass 866 / fail 1 / skip 12；总 62 fail / 86 skip，与已知 Windows 环境基线同数；`TestMKey003` PASS。
- vet / build / diff-check = 0。

### 边界
- 公钥只做校验，不落盘；M39 补原子安装与旧 key 处理。
- 同响应 public_key 作为可信服务端（已验证 https/回环）的通道材料，同时强制 grant key_id 一致；不自我证明 grant 内容。

## M39 — grant/key 原子落盘、重放与旧 key（M35–M39 收口）

### 实现
- `writeFileAtomic`：同目录临时文件 → chmod/write → fsync → rename → 目录 fsync（复用 `syncTerminalReportDir`）。
- 公钥安装 `<root>/.crctl/keys/<key_id>.pub`：
  - 已有其他 key 不删除/不覆盖；
  - 同 key_id 同内容幂等跳过；
  - 同 key_id 不同内容 fail closed，整批不写 grant、不 ack；
  - key_id 做安全文件名校验。
- 顺序：校验 public_key → 原子安装 key → 测试故障点 `after_key` → 原子写 grant → `after_grant` → 收集 ID → ack。
- 仅测试注入故障点（生产 nil），重投时 key 幂等、grant 原子重写、已 ack 不再写入。
- 不修改 `.crctl/.gitignore`，不触碰真实 KB；无新表/状态/CLI。

### 测试
- `TestMKey001`：key→完整 grant→ack 顺序探针。
- `TestMKey002`：TLS 服务；默认证书校验拒绝测试证书（不写），可信 TLS 客户端成功写入。
- `TestMKey003`：唯一/零/歧义/跨 workspace、远程明文拒绝、回环允许、key 缺失不投递（8 子例）。
- `TestMKey004`：写 key 后中断、写 grant 后中断 → 均不 ack；重投补齐、无半文件、无重复；已 ack 不再重写。
- `TestMKey005`：其他 key 不变；同 key 同内容幂等；同 key 内容冲突拒绝；旧 key/旧 grant 保留。
- `TestMKey006`：临时 git 仓 `.crctl/.gitignore` anchor 字节不变；普通文件仍 ignored，keys 白名单可见 key。
- RED：关闭故障点后，中断批次被 ack（`interrupted batch acked`）。
- GREEN：6 RUN + 13 subtest 全 PASS；相关回归 17 RUN + 20 subtest 全 PASS。
- daemon 整包：native exit=1；1040 父 RUN；父 pass 905 / fail 61 / skip 74；子 pass 871 / fail 1 / skip 12；总 62 fail / 86 skip，与已知 Windows 环境基线同数；所有 MKey PASS。
- vet / build / diff-check = 0。

### M35–M39 daemon CP 覆盖
- 已覆盖：`TestMKey001`–`TestMKey006`；`TestMKb003/005/006/007/008`；`TestMKb001` 在 daemonws/protocol 侧（M35a）。
- 跨包缺口（不在本 lane）：`internal/handler` 精确 `TestMKb001`、`TestMKb004` 未新增；handler `TestMKb002` 已覆盖资源隔离/N+1。
- 断言强度：MKey004 未单独注入“写文件失败”，已覆盖两处中断；MKey005 旧 grant 缺 key 的 `KEY_NOT_FOUND` 由 crctl 既有语义承担，未在 daemon 模拟；MKey006 断言 anchor 字节与 `git check-ignore`，未断言完整 dirty 集合。

## CP 定位符审计 + handler 两处收口

### A. CP 审计（35 条 M-CP 定位符）
最终结果：**OK 31 / MISSING 4 / WRONG_PACKAGE 0**（本轮修复后）。
- 初始：OK 29 / MISSING 5 / WRONG_PACKAGE 1。
- 本轮修复：`M-CP-KB-001`（WRONG_PACKAGE → handler 新增）、`M-CP-KB-004`（MISSING → handler 新增）。
- 证据：`cp-audit/audit.txt`、`audit.json`、`raw-grep.txt`。

仍 MISSING：
1. `M-CP-DELIVERY-002`（`./internal/daemon ^TestMDelivery002$`，M-SC-DELIVERY-002）
   - 断言要点：authority 元数据继承；缺 spec/真实版本阻断；不猜标题/legacy milestone。
   - 最小补法：薄测试复用 `TestM30AAuthorityFactsReject` / `TestM30AMergeRebindNewRoot` 的 `pipelineCarrierForTest`/authority inspect 夹具。
2. `M-CP-DELIVERY-004`（`./internal/daemon ^TestMDelivery004$`，M-SC-DELIVERY-004）
   - 断言要点：merge 旧 task 结束后新 task 本机重绑 operational 根；不改运行 env/server 猜路径。
   - 最小补法：薄测试复用 M30A 重绑夹具与 `pipeline_task_test` 的临时安装根。
3. `M-CP-DEV-002`（`./internal/governance ^TestMDev002$`，M-SC-DEV-002）
   - 断言要点：dev-plan/test/upstream 往返投影；错归属/过期拒绝；测试失败/BLOCK 不吞。
   - 最小补法：把现有 `TestM24DevPlanUpstreamBlockProjectsWithoutRoundBump` 等投影用例提为 helper，新增命名测试调用同一 helper。
4. `M-CP-DEV-003`（`./internal/governance ^TestMDev003$`，M-SC-DEV-003）
   - 断言要点：release-subjects 匹配/漂移决定代码评审有效性；设计单 hash 不替代。
   - 最小补法：复用 `TestM24ReleaseSubjectsDoNotRequireSingleSubject` + `TestM25ReviewPayload*` 夹具，提 helper 后新增命名测试。

### B. handler 缺口
- 新增 `TestMKb001`：同一资源经 HTTP 手动响应与 WS ack 返回；`buildDaemonWebSocketIdentity` lease 保留 runtime.daemon_id；两端资源 JSON 字节一致。
- `TestMKb002SnapshotFailureKeepsActions` 改名为 `TestMKb004`，原失败保留投影/actions 断言全保留，新增“后续成功读取收敛出投影且 action 不丢”。
- RED：
  - 去掉 HTTP 响应 snapshot 映射 → `HTTP snapshot = <nil>`；
  - attach 临时 no-op → `successful read did not converge the projection`。
- GREEN：`TestMKb001` / `TestMKb004` 均 PASS。
- handler 整包（TRUNCATE skill_usage_event 后）：native exit=0；2481 父 RUN；父 pass 2434 / fail 0 / skip 47；子 pass 1867 / fail 0 / skip 0；总 PASS 4301，FAIL 0，SKIP 47；无 DBskip。
- vet / build / diff-check = 0。

## CP DELIVERY-002 / DELIVERY-004 补测

### canonical 定位
- `M-CP-DELIVERY-002` / `M-SC-DELIVERY-002` / `TC-MDELIVERY-002` → `./internal/daemon ^TestMDelivery002$`；stdout 要求 `--- PASS: TestMDelivery002`。
- `M-CP-DELIVERY-004` / `M-SC-DELIVERY-004` / `TC-MDELIVERY-004` → `./internal/daemon ^TestMDelivery004$`；stdout 要求 `--- PASS: TestMDelivery004`。

### 实现（仅测试）
- `TestMDelivery002`：
  - 复用 M30A authority/workspace inspect 夹具；
  - `TARGET_SPEC_AUTHORITY_DRIFT`、`WRITEBACK_VERSION_UNASSIGNED`、`WRITEBACK_VERSION_INVALID` 三例均阻断；
  - 断言拒绝后无 workspace/local dir 绑定；
  - 断言 prompt/carrier/node/attempt 全部保持原值，不写臆造标题/milestone/元数据；
  - 合法 authority 成功后 carrier 同样不被改写。
- `TestMDelivery004`：
  - 复用 M30A 重绑夹具：旧 task 绑 old operational，新 task 绑 new operational；
  - 断言旧 task workspace/dir/prompt 不变（运行中 env 输入不被改写）；
  - 断言新 task 不复用旧根。
- 未改生产代码。

### RED → GREEN
- `TestMDelivery002` 临时让 authority facts 直接返回 nil：实际三子例 `authority ... err=<nil>` 全失败。
- `TestMDelivery004` 临时让 prepare 用 root 覆盖 inspected operational：实际 `old task dir=... want ...old\CR-2026-045` 失败。
- GREEN：2 RUN + 3 subtest 全 PASS；相关 M30A/MDelivery 回归 6 RUN + 11 subtest 全 PASS。

### daemon 整包
- native exit=1；1042 父 RUN；父 pass 907 / fail 61 / skip 74；子 pass 874 / fail 1 / skip 12；总 62 fail / 86 skip。
- 与 Main 已核实的 Windows 环境基线 **62 失败、86 skip 同数**，无新增失败；`TestMDelivery002/004` 均 PASS。
- vet / build / diff-check = 0。

## M-CP-DEV-002 / M-CP-DEV-003 — governance 侧 CP 落地

### 实现（仅 governance 测试）
- `gate_review_test.go`：把既有 M24 夹具公共部分提为 helper（`projectDevPlanUpstream`、`projectTestBlock`），原 `TestM24DevPlanUpstreamBlockProjectsWithoutRoundBump` / `TestM24TestBlockIsNotPassed` 改用 helper，**原断言逐条保留**。
- 新增 `dev_phase_cp_test.go`：
  - `TestMDev002`（M-CP-DEV-002）：dev-plan upstream 只落自身节点且 0 architecture run、repair-target 保留；test BLOCK 文本不吞；过期 round-1 结果不重写已判定的 round-2（历史行保留）；payload 自报其它 CR 时**归属仍以 ledger 事件 CR 为准**，被命名 CR 零 run/零节点。
  - `TestMDev003`（M-CP-DEV-003）：复用 crosscheck 夹具，匹配的 release-subjects（无设计式单 `subject-sha256`）→ `code-approved`；评审后改动受控 artifact → crctl 返回 `RELEASE_SUBJECT_DRIFT`，CR 保持 `code-reviewing`。

### RED（严格读法的缺口，生产改动未授权，已停）
临时探针（已删除）对“硬拒绝”逐条实测，`.../cp-dev/red.log` exit=1：
- `payload naming another CR was accepted (accepted=[probe-wrongcr.json] rejected=[]); want hard rejection`
- `expired round-1 result was accepted (rejected=[], attempt-1 rows=1); want hard rejection`
原因：`gate_projection.go::applyReview` 以 ledger 事件 CRID/stage 为准投影，不校验 payload 内 `cr-id`/`review-type`，也不拒绝早于当前已判定轮次的记录（按历史保存）。当前交付按“归属不被 payload 改写 + 过期不覆盖当前轮次”实现；若 Main 要求硬拒绝（事件进 rejected/error），需授权改 `gate_projection.go::applyReview`。

### GREEN / 整包
- 目标：`.../cp-dev/green.json` exit=0，RUN 8（2 父 + 6 子）全 PASS。
- 整包：`.../cp-dev/package.json` exit=0，**RUN 461（238 父 + 223 子）PASS 460 / fail 0 / skip 1（既有 LiveGitHub） / DBskip 0**。
- `go vet ./internal/governance` exit=0（`.../cp-dev/vet.log`）。
- canonical 摘录：`.../cp-dev/canonical-excerpt.md`。

### 边界
- 未改生产代码；未动 daemon（M-CP-DEV-002 action 里的 daemon crevents 配套断言属另一 lane/后续）。
- 未 commit/push。

## M-CP-DEV-002 — 授权修复（错归属/过期硬拒绝）

### 实现（仅 `internal/governance/gate_projection.go`）
- `reviewEventPayload` 增加 `CrID string \`json:"cr-id"\``。
- `applyReview`：`p.CrID != "" && p.CrID != ev.CRID` → error（不建 run/不写 detail；空值容忍历史事件），与 daemon `buildReviewPayload` 对等。
- `applyReview`：写前查 `(run_id,node_id)` 的 `max(attempt)`；规范化后 `attempt >= 1 && maxAttempt > attempt` → error（不插入/不改写）。attempt 0 的 dev-plan upstream cycle 标记天然豁免（M27）。
- 未动 factsOnly、ON CONFLICT、attempt 补齐、publish、reserved runner key；无新表/列/状态/CLI/账本。

### RED（基线实现，收紧后的 TestMDev002）
`.../cp-dev/red.log` exit=1：
- `expired round-1 result was accepted (accepted=[late1.json] rejected=[]), want hard rejection`
- `payload naming another CR was accepted (accepted=[wrongcr.json] rejected=[]), want hard rejection`
（`upstream_attempt_zero_is_not_expired` 子例首轮因夹具 SQL 错误失败，修正夹具后在基线语义下同样复现为“过期检查缺失”，随后随实现转绿。）

### GREEN / 整包
- 目标 `green.json`：exit=0，RUN 9（2 父 + 7 子）全 PASS（含新增 `upstream_attempt_zero_is_not_expired`）。
- 整包 `package.json`：exit=0，**RUN 462（238 父 + 224 子）pass 461 / fail 0 / skip 1（既有 LiveGitHub）/ DBskip 0**。
- `go vet ./internal/governance` exit=0（`vet.log`）。
- 回归 `m20-m28.log`：M20–M28 + ApplyReview + AIFI60 + MDev002/003 共 22 父测试全 PASS；逐条结论见 `conclusions.md`，**无既有测试依赖“错归属/过期被接受”**，新拒绝未过宽（attempt 0 豁免与递增轮次均通过）。
- diff 摘要：`diff-summary.md`。

### 边界
- M25 daemon crevents payload 测试属另一 lane；服务端已与其实义对齐，未改 daemon。
- 未 commit/push。

## M-CP-DEV-002 daemon 配套断言

### 盘点
- `TestM25ReviewPayloadRoundTripCanonicalIdentity`：cr-id/review-type/repair-target 透传；release-subjects 非空；reviewed_at；attempt/cycle；subject_sha256。
- `TestM25ReviewPayloadRejectsWrongAttribution`：错 CR、错 review-type、缺精确 commit 均拒绝。
- `TestM25DevPlanUpstreamPayloadKeepsM24Facts`：verdict/repair-target/attempt/cycle。
- `TestParseCRCommitMessageReviewContract`：结构化 blockers → issue 文本。
- `TestBuildReviewPayloadUsesHistoricalCommitAttempt`：标量 blockers + 历史 commit。
- `TestBuildReviewPayloadTechDesignAttemptTwoParity`：stage/verdict/attempt/空 blockers/reviewed_at/subject_sha256。
- 缺口：条件字段缺失省略、显式空 release-subjects、错归属“零事件”。

### 补齐（仅测试）
- 新增 `TestM25ReviewPayloadConditionalFields`：
  - `repair-target`/`release-subjects`/`cycle` 为空时不出现在 payload；
  - 显式 `release-subjects: {}` 作为存在值保留。
- 扩展 `TestM25ReviewPayloadRejectsWrongAttribution`：调用 `scanCommitsSinceCursor`，断言错归属/错类型 annotation 不产生任何 review 事件，而非仅 payload 缺字段。
- 未改生产代码。

### RED → GREEN
- 条件字段 RED：强制 `cycle` 恒出现 → `empty conditional field "cycle" was emitted`。
- 零事件 RED：让 invalid annotation 仍发出 review event → `wrong-attribution annotation produced a review event`。
- GREEN：M25 4 RUN 全 PASS；相关 9 RUN 全 PASS。

### daemon 整包
- native exit=1；1043 父 RUN；父 pass 908 / fail 61 / skip 74；子 pass 874 / fail 1 / skip 12；总 62 fail / 86 skip。
- 与 Main 已核实 Windows 基线同数，无新增失败；所有 M25 PASS。
- vet / build / diff-check = 0。

## M50 + M51 — canonical ACK tests: BLOCKED（生产仍未删旧续接/未四阶段路由）

### 已核实（canonical + 代码）
- 5 条 CP 的精确断言已摘录：`.../aifi45-m50-m53-evidence/m50-m51/canonical-excerpt.md`（001 纯送达+旧 continuation 探针=0；002 认证/workspace/幂等矩阵；003 commit 后四阶段 WakeGrant、单失败不撤 ack/不阻他条；004 真 DB commit 失败不假 ack；005 终态/缺 run/旧 subject 不建执行；006 为人工断言「真实旧续接处置未执行」）。
- 当前生产仍是旧契约：`approval.go::HandleGrantsAck` 调 `resolveContinuationTarget` + `EnqueueApprovalContinuation`，Leader 缺失整批回滚；`runner.go::WakeGrant` 仅 requirement / 其它→architecture 两桶。

### 真实 RED（临时探针，已从仓库删除；`.../m50-m51/red.log` exit=1，3/3 失败）
- `pure delivery ack: code=500 delivered=<nil> body={"error":"approval continuation failed","reasons":[{"cr_id":"CR-9007-901","stage":"code","reason":"issue-missing"}]}, want 200 with delivered_at committed even without Leader`
- `ack enqueued 1 continuation task(s); canonical M50 requires 0 (delivered_at is delivery only)`
- `WakeGrant does not route stage CodeImplementation to its own Runner; body=func (r *Runner) WakeGrant(...) { if ev.Stage == "requirement" { ReconcileRequirement } return Reconcile }`

### 按指示停在此处
- 未改生产代码、未留下失败测试（避免打断另一 lane 整包）：探针已删除，仓库无 `zz_*`/`approval_ack_cp_test.go`。
- 需授权才能 GREEN 的最小改动：删 `HandleGrantsAck` 正常路径的 Leader 解析/续接入队与仅为续接的整批回滚（保留 `AckApprovalGrants` SQL 语义与 commit 后唤醒）；`WakeGrant` 按四阶段（`PipelineIDs.RequirementAuthoring/ArchitectureDesign/CodeImplementation/FeatureWriteback`）路由到各自 Runner。既有 `approval_continuation_test.go::TestAC1_* / TestAC2_* / TestAC6_*` 断言旧契约，届时需同步调整（当前授权禁止改既有断言）。
- M-CP-ACK-006：人工断言，**未执行**，未写自动化模拟。

### 仓库状态
- 探针删除后整包 `go test ./internal/governance` exit=0（`.../m50-m51/package.log`，"ok 43.195s"）；`go vet`/`go build ./...` 见 `vet.log`/`build.log`。
- 未 commit/push。

## M50 + M51 实施（授权后）— ACK 纯送达 + 按实际阶段唤醒

### A/B 生产改动（`internal/governance/approval.go`、`runner.go`）
- `HandleGrantsAck` 删除正常路径的 `resolveContinuationTarget`/`EnqueueApprovalContinuation`/`NotifyContinuationTaskEnqueued` 与仅为续接的 reasons 整批回滚；保留 workspace 认证/403、`AckApprovalGrants` SQL、pre-commit `onGrantAck` 回滚 5xx、真实 commit 失败 5xx（`delivered_at` 未落盘）、post-commit `onGrantAckCommitted` 逐条 log-only、200 `{"status":"ok","reasons":[]}`（reasons 降级为诊断）。旧 continuation 机器函数/类型保留供 tools T04。
- `WakeGrant` 改为先 `Reconcile`（writeback/architecture，含 upstream rereview）再 `ReconcileRequirement`，不再按发 grant 时的 stage 字符串分桶；两者对活跃 run 幂等、无 run 为 no-op。

### C 既有旧契约断言调整
`approval_continuation_test.go` 的 AC1/AC2/AC6/AC6d/AC5/AC8 按新契约重写，每处注释写明「旧契约断言什么 → 新契约断言什么 → 为何不是弱化」；AC7/AC9 等仍成立的断言未动，未删除/未 skip/未放宽 timeout。逐条见 `.../m50-m51/diff-summary.md`。

### D 五个 canonical 测试（新文件 `approval_ack_cp_test.go`）
- `TestMAck001`：同批无 Leader/缺 shell issue 仍 200 且全部 `delivered_at`；0 continuation task；源码探针（brace 匹配 `approval.go::HandleGrantsAck` 函数体）不含三个旧 continuation 符号且保留三个 hooks；ack 不改 CR 状态/不建 run/task。
- `TestMAck002`：未认证 403；有效与重复 IDs 幂等（`delivered_at` 保持首次值、无任务）；跨 workspace ID 不更新。
- `TestMAck003`：四阶段同批 commit 后逐条唤醒，handler 内验证 `delivered_at` 已可见（commit-before-wake）；一个唤醒失败不撤 ack、不阻断其他；每阶段唤醒计数=1；另含 `WakeGrant` 源码路由探针（Reconcile 先于 ReconcileRequirement、无 stage 字符串分支）。
- `TestMAck004`：pre-commit hook 取消请求 ctx 触发真实 DB commit 失败 → 500、`delivered_at` NULL、0 唤醒；新鲜重投 200 + delivered + 唤醒 1。
- `TestMAck005`：archived CR + 旧 cycle/subject grant、无活动 run → 0 新 task/0 run、状态不变、`delivered_at` 与业务消费分离。
- `M-CP-ACK-006`：人工断言「真实旧续接处置未执行」，**未执行**、未模拟。

### 证据与回归（`C:/Users/GOBAO/AppData/Local/Temp/aifi45-m50-m53-evidence/m50-m51/`）
- 行为 RED（旧实现）：`red.log` 3/3 失败（`issue-missing` 整批 500、`ack enqueued 1 continuation task`、`WakeGrant does not route CodeImplementation`）。
- GREEN：`green.json` 19 条测试事件全 PASS（5 个 MAck + WakeGrant 路由探针 + 全部 AC 测试）。
- 整包：governance **483 RUN（247 父+236 子）/pass 482/fail 0/skip 1（既有 LiveGitHub）**；handler **4348 RUN/pass 4301/fail 0/skip 47**；cmd/server **552 RUN/pass 552/fail 0/skip 0**；service **913 RUN/pass 886/fail 9 事件/18 skip** —— 9 个失败事件即既有基线 `TestBuiltinSkillsConformToTemplate`(+3)/`TestBuiltinSkillsFrontmatterIsStrictYAML`(+3)/`TestPlatformSkillDescriptionNamesEveryDomain`，与 ACK 契约无关（Main 已核实的 SKILL.md frontmatter 基线），无新回退。
- `go vet` 四包 exit=0；`go build ./...` exit=0。
- 逐条结论：`conclusions.md`；diff 摘要：`diff-summary.md`。

### 边界
- 未删除旧 continuation 机器（tools T04 收尾）；未改 tools/daemon/DDL/事件；未 commit/push。

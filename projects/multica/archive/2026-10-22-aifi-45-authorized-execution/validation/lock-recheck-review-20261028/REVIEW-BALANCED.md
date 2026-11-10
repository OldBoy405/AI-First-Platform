## 受限结论

**Verdict: NOT VERIFIED / INCOMPLETE（维持原判）**  
本轮只做静态读取、哈希比对与 grep，不运行测试、不连接 DB、不修改文件、不提交、不发起真实 CR。**不能宣布整体生产或 Gate3 PASS，也不能代作者或既有 reviewer 升级。**

---

## 1. 快照与哈希范围

以 `validation/lock-recheck-review-20261028/source-manifest.json` 为基准，使用绝对路径重算：

- `base_manifest_sha256`：**OK**，`replay-review.../source-manifest.json` 当前字节匹配。
- multica：**12/12 OK**，包括 9 个 base 文件和 3 个 override：
  - `CUSTOM.md`
  - `execution_run_003_test.go`
  - `integration_test.go`
  - daemon 两个测试
  - requirement enqueue / revoked permit / settlement / store state / store state test / verdict attestation
  - `execution_control_command_attestation_test.go`（untracked 新文件）
- change：**10/10 OK**，包括 canonical agent/code、test-plan、tc-coverage 四个 override，以及 backlog、hardening、R4 三份报告和 R4 receipts。
- change additions：**4/4 OK**，当前 `replay-review-20261028/REVIEW-{STRONG,BALANCED}.md`、`REVIEW-RECEIPTS.json`、`CLOSEOUT.md` 均匹配。

当前 `../multica`：

- `HEAD = 81e5293adc758e392a045026cf81ec5cc1bac72d`，与 base manifest 一致。
- 工作区 11 个 modified + 1 个 untracked，集合与 manifest 的 12 个文件一致。
- 因此**本次核对时未发现快照漂移**，但这是**未提交工作树字节**，不是 commit 冻结；`tools`/`workspace` 两个 head 仅见 base manifest，本轮没有独立重算。
- R4 报告与 receipts 的 SHA 也匹配；R4 `source-manifest.json` 是历史输入 `a929e443...`，不能拿来当当前源码快照。

---

## 2. cp-final 与 full governance 证据

### 2.1 `cp-final-*-20261028T082912Z` 逐项结果

从每个 `.meta.json` 和 `.stdout.jsonl` 读取顶层 `run/pass/skip`，不是只看 parent：

| 证据 | 顶层测试 | run/pass | leaf | skip |
|---|---|---|---:|---:|---:|
| `cp-final-cp-run-003` | `TestTC_RUN_003` | 1/1 | 1 | 0 |
| `-a` | `TestAdmissionWaitingIsNotPersistedAsRunFailure` | 1/1 | 1 | 0 |
| `-b` | `TestPassHumanApprovalNodeIsGated` | 5/5 | 4 | 0 |
| `-c` | `TestVerdictWriterVerifiesAttestation` | 11/11 | 10 | 0 |
| `-d` | `TestRequirementEnqueueIsGated` | 1/1 | 1 | 0 |
| `-e` | `TestAdmissionDeciderWaitsForCommittedConsumption` | 1/1 | 1 | 0 |
| `-f` | `TestControlCommandWriterVerifiesAttestation` | 14/14 | 13 | 0 |
| `-g` | `TestControlCommandEarlierRevokeCannotBeHidden` | 1/1 | 1 | 0 |
| `-h` | `TestControlCommandSerializesWithRevoke` | 1/1 | 1 | 0 |
| `-i` | `TestControlCommandRejectsRepeatableRead` | 1/1 | 1 | 0 |
| `-j` | `TestControlCommandExactConcurrentReplay` | 1/1 | 1 | 0 |
| `-k` | `TestVerdictExactReplayRejectsConflict` | 5/5 | 4 | 0 |
| `-l` | `TestVerdictConcurrentExactReplay` | 1/1 | 1 | 0 |
| `-m` | `TestControlRequestConflictsAcrossLineages` | 3/3 | 2 | 0 |
| `-n` | `TestControlWriterRejectsExpiryAfterLockWait` | 3/3 | 2 | 0 |

15 条均命中指定顶层测试，**skip=0**；parent 只覆盖 `TestTC_RUN_003`，不能替 A–N 作证。

隔离回执链也逐条存在：

- `isolation-verified`：target 为 `aifi45_tmp_*`，role 非 superuser，`create_db=false`、`create_role=false`、`bypass_rls=false`、`audit_rows=0`、`workspace_rows=0`。
- `original-compared`：`unchanged=true`，`release.sessions=0`、`locks=0`。
- `database-dropped` / `role-dropped` / `resources-absence-verified=false,false`。

**限制**：这些是 harness 自报，且全部为作者运行。本报告只验证了回执内部一致，未独立连接 DB 验证原库或清理；`original-before/after` 在 15 条中字节相同，也只能说明 harness 记录一致，不是独立审计。

### 2.2 full governance 不能当验收

`final2-governance-20261028T083528Z`：

- `run=1147`, `pass=1146`, `fail=0`, **`skip=1`**, `exit=0`
- stdout `:2471`：`TestReconcileLiveGitHub` **SKIP**
- meta `error`: **“test unverified: skipped leaves cannot count as verified”**

因此该运行只能是 skip 限定回归比较，**不能作完整 governance 验收**。

历史 `replay-snapshot-gov-20261028T080158Z` 更是红：`exit=1`、`fail=3`、`skip=2`，实际失败包括：

- `TestChannelProtocol/cross_language_vectors`（stdout `:4200`）
- `TestTCAuth010GoSignedBytesWithNonASCIIAndCRLFVerifyInNode`（`:4473`）
- package FAIL（`:4698`）

`replay-snapshot-gov-tools-20261028T080416Z` 虽然 `exit=0`，但 `skip=1`，harness 明确判 unverified（meta `error`）。这些旧证据只能说明历史红/限定回归，不能反推当前全包通过。

`final2-daemon` 为 12/12、skip 0，但仍只是 daemon 子集。

---

## 3. 具体问题与未验证事项

| 严重度 | 文件/行 | 问题 |
|---|---|---|
| **High** | `final2-governance-...meta.json`、`stdout:2471`；旧 `replay-snapshot-gov...` `stdout:4200/4473/4698` | 全量 governance 只有 skip 限定结果；旧快照实际 3 fail。任何“完整全绿/整体验收”表述都与证据冲突。 |
| **High** | `replay-review-20261028/CLOSEOUT.md:4-8`；`r4-review-20261028/CLOSEOUT.md:11-15` | 既有原判仍是 strong **BLOCK**、balanced/economy **INCOMPLETE**；作者 F1/F3 修补、cp-final 绿和文档修改都不等于独立复评。 |
| **High（开放信任边界）** | `execution_control_store_state.go:249-281`；`control-channel-hardening-20261028.md:9` | `ApplyControlPolicyEventTx` 自行构造 unsigned envelope，接受任意调用者填写的 revoke/stop；目前无生产调用点，故不是已证实对外利用，但绝不能当“权威停止”已闭合。 |
| **Medium** | `execution_run_003_test.go:15-17` vs `:310-324`, `:451-471` | 文件头声称“每个 phase 都断言 human gate 未 passed”；实际 `held()` 只检查首节点/任务/run/wait reason，human gate 只在最终派发后、且仅当 registry 有 `human_approval` 节点时检查。证据陈述过度。 |
| **Medium** | `execution_run_003_test.go:299-306`, `:331-350` | `wake` 是直接调用 `runner.WakeGrant`，不是实际 periodic scheduler；consumption、settlement、cursor 由 SQL 夹具直接插入。真实的是 ACK 路由、writer 和 TaskService，但**不是生产 producer/ingest 全链**。 |
| **Medium** | `execution_admission_test.go:129-136`, `:208-232`；`execution_admission.go:161-170` | CP-E 的 cursor 反例通过直接插入空 envelope/任意 digest 的 verdict 和 cursor，只验证 `last_seq >= v.seq` 判定；它不证明真实 writer 产生该行、也不证明 cursor digest/链包含关系。RUN003 虽走真实 writer，但 cursor 仍是夹具预置。 |
| **Medium** | `canonical/specs/agent/authorized-runner.yaml:61`；`execution_control_command_attestation_test.go:485-503` | CP-I 描述的是“拒绝可能读取过期快照的事务隔离级别”，但实际只有 **command** 有 READ COMMITTED 硬拒绝和 RR 测试；`AppendVerdictFrameTx` 没有同样的 isolation guard，也没有 verdict RR 负例。A–N 映射在此处不精确。 |
| **Medium** | `execution_control_store_state.go:411-413`；`canonical...:35`；`tc-coverage:2351` | F2 历史 key 过期后的已提交重放仍未闭合：writer 在 replay 查询前先验签，过期 key 会阻断原记录重放。文档承认策略未定，不能宣称 replay/recovery 完整。 |
| **Medium** | `execution_control_store_state.go:74-127`, `:380-399` | CP-F 只是“部分绑定”：`Scope`/`EffectiveFence`、`CommitRef`/`ReceiptRef` 不是首次写入签名主体；测试只在 replay 时改这些字段并期待 conflict。若这些字段属于合同不可变事实，当前没有首写绑定证据。 |
| **Medium** | `tc-coverage-20261025T153000Z.md:1460`；`CUSTOM.md:889` | 两个 Markdown 文件各含一个 NUL 字节，`grep`/普通文本工具判为 binary；R4 balanced 曾因此读不到台账增量。文本证据可审性受损。 |
| **Low** | `tc-coverage-20261025T153000Z.md:2358` | 指引“现行计数见各增量末尾的『仍未闭合』小节”，但增量 85–87 并无该标题；44/49 实际写在正文 bullet。当前数字仍是 44/49，但锚点错误。 |
| **Low** | `execution_control_command_attestation_test.go:390`, `:451-465` | CP-N 用 3 秒墙钟和 `time.Sleep` 等待 key 过期；虽有 `pg_blocking_pids` 真屏障，仍是时间敏感测试，慢环境有 flake 风险。 |
| **Low** | `execution_control_command_attestation_test.go:64-78`, `:95-98` | `"request"` 负例把 `input.RequestID` 改成新 UUID 后，用这个新 ID 查“无行”；没有用原 request ID 复查。该分支在 insert 前失败，所以目前不是假绿，但负例断言对象不完整。 |

### 其他未验证

- `execution_control_store_state.go:493-499` 的 cursor 更新会无条件清空 `open_request_id`；`AppendVerdictFrameTx` 没有验证 open-request 归属、owner fence、frozen 状态。当前 strong 报告 `REVIEW-STRONG.md:109` 已把它列为开放边界；没有生产调用点，故不冒报为现有漏洞。
- `TestRequirementEnqueueIsGated` 的真实任务身份（agent/node/issue/context）确实回读；但它用的 trusted consumption/verdict/cursor 由 `admitTrustedConsumption` 直接构造，不是真实 producer/ingest。
- `TestTC_RUN_003` 的最终任务身份、重复 wake 同一 task ID 断言有效；但 human gate 每阶段断言、production producer/ingest、真实部署路由仍未覆盖。
- `cp-final` 的 15 条作者运行不等于独立复评；`original_unchanged`、`owned_resources_cleaned` 未由本报告独立证明。
- R4/本轮报告的实际 provider/model、session 记录在 receipts 中，但未验证 backend 另有回执；R4 receipts 本身也明确“不冒称后端回执”。

---

## 4. Canonical / test-plan / tc-coverage / CUSTOM / R4

- **Canonical CP-RUN-003 + A–N**：`canonical/specs/agent/authorized-runner.yaml:24-83` 中 15 个 CP 的 action 名字均能在源码/证据中找到；cp-final 全部 top-level PASS、skip 0。A–N 均被标为“补充回归，不替代完整 TC”，与 `test-plan.md:72` 基本一致。
- **不准确处**：CP-I 的 generic 描述与 command-only 测试/guard 不一致（见上表）；CP-E/CP-F 的“完整/部分”边界在文档中有披露，但不能当作完整链验证。
- **test-plan**：`:49` 的 TC-RUN-003 写“ACK回调及periodic wake”，实际 RUN003 是 ACK 路由后直接 `WakeGrant`；`:72` 已正确披露 A–N 不可替代完整 TC、fixture 和生产 producer 限制。
- **tc-coverage 85–87**：`:2329-2336`（85）、`:2338-2344`（86）、`:2346-2352`（87）把 44/49、Gate3 NO-GO、cp-final 作者运行、final2-governance skip 限定限定得基本准确；`:2352` 的 15 条 cp-final 描述与本次读取的 15 个回执一致。
- **文档错误**：`:2358` 的“仍未闭合”锚点不存在；`:1460` 的 NUL 使文件被 grep 视为 binary。
- **CUSTOM #250–252**：`CUSTOM.md:902-904` 三行均存在；#250 明确登记 `execution_control_command_attestation_test.go`（新）、#252 也登记该文件；base manifest 确实包含该 untracked 文件。之前“manifest 未列入新增文件”的说法是错误的，本次已核实登记完整。
- **R4**：`validation/r4-review-20261028/REVIEW-STRONG.md` 为 **BLOCK**，`REVIEW-BALANCED.md`、`REVIEW-ECONOMY.md` 为 **INCOMPLETE**；文件 SHA 与 `REVIEW-RECEIPTS` 一致，`CLOSEOUT.md:11-15` 明确作者修补“均待独立复核”。本轮 `REVIEW-STRONG/BALANCED` 的 SHA 与当前 `REVIEW-RECEIPTS` 一致；strong 仍 BLOCK、balanced 仍 NOT VERIFIED，F2 仍开放。没有把作者修复或 cp-final 绿升级为 PASS。

---

## 5. 最终受限判断

**NOT VERIFIED / INCOMPLETE。**  
可确认的正面事实是：新 manifest 的 26 个哈希全部匹配、CP-RUN-003 A–N 的 15 条作者回执均命中顶层测试且 skip 0、隔离/清理事件链完整、CUSTOM #250–252 已登记。  
但这些**不足以**支持整体 PASS，原因是：全量 governance 仍是 skip 限定、R4/本轮原判未获独立复评、F2 历史重放未闭合、policy/cursor/open-fence 等信任边界仍开放、CP-E/F/I 的测试范围小于其描述、human gate 与 README 式声明存在证据过度，以及两份 Markdown 含 NUL 影响可审性。
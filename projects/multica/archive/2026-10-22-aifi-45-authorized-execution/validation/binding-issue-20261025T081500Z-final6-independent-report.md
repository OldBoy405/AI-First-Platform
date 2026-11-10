# binding issue final6（硬上限 + trust-root 探针修正）独立回归报告

- at: 2026-10-25T09:01Z
- 角色: 本片唯一 DB 执行者（非作者）；未改产品/测试源码
- 证据前缀: `binding-issue-20261025T081500Z-final6-independent-`
- DB 访问: 仅版本化 `scripts/aifi45-db/run.mjs` 串行 3 条；未手工 SQL/psql，未启动/操作容器
- 三条命令均设置 `AIFI45_TOOLS_ROOT=C:/Users/GOBAO/Downloads/AI/tools`
- 结论: 3 条均完成且 runner/资源/原库门禁通过；互通用例与签发上限用例均实际 PASS（非 SKIP）；混合 SKIP 单列且不计 PASS。本文只是组件证据，不签消费/准入/activation/隔离域/全局 C1。

## 权威源码冻结与 pins

- 权威 freeze: `binding-issue-20261025T081500Z-final6-freeze-manifest.json`，14 项，sha256 `72a94140e86f982b1de731b9d37c7b8932f125acd3ac90e531119cc91fe0684a`
- 相对 final5 变化：`execution_binding_issue.go`（硬上限 advisory lock）与 `scripts/aifi45-isolation/trust-root-probe.mjs`（B1/B2 修正）。
- 每条命令执行前，自读实际文件重算 raw/LF，14/14 与 freeze 相等；执行后再次重算仍 14/14 相等（无漂移）。
- 三条 wx 新建 pre-run pin:
  - governance `d99db1a72f1c25dd0c4babb42908154273ec35290f06895c65617c673530be35`
  - handler `06d779bf0a4157e2687210473f984d9bbbdc452891c3094ed9dc7177d4ff7257`
  - daemon `5aa5bd18e2e3d18c1e6573de2e9eb680275c9a4a7ff2f2b7b5c9a57d15547201`
- 上一轮 final5 结论保留为历史，不再被本最终源码认领，也未删除/改写。

## 命令（cwd=C:/Users/GOBAO/Downloads/AI/multica，flag 均在 prefix 之后）

1. `AIFI45_TOOLS_ROOT=C:/Users/GOBAO/Downloads/AI/tools node scripts/aifi45-db/run.mjs ./internal/governance '^Test' "<V>/binding-issue-20261025T081500Z-final6-independent-governance" -timeout=280s -migration=server/migrations/643_cr_execution_binding_issue.up.sql`
2. `AIFI45_TOOLS_ROOT=C:/Users/GOBAO/Downloads/AI/tools node scripts/aifi45-db/run.mjs ./internal/handler '^TestStartClaim' "<V>/binding-issue-20261025T081500Z-final6-independent-handler" -timeout=280s`
3. `AIFI45_TOOLS_ROOT=C:/Users/GOBAO/Downloads/AI/tools node scripts/aifi45-db/run.mjs ./internal/daemon '^Test(TerminalReport|SendTerminalTaskReport|Execution)' "<V>/binding-issue-20261025T081500Z-final6-independent-daemon" -timeout=280s`

## 迁移、互通与签发上限

- 第 1 条 `migrations` 与事件记录：
  - path: `server/migrations/643_cr_execution_binding_issue.up.sql`
  - sha256: `495ec3c0ee54d1a29b3ad376a2f7d0cbd5844960c9035685a7821fb612cfcbbe`
- `TestExecutionBindingEnvelopeInteropWithToolsVerifier` 实际 PASS（非 SKIP），3 个 PASS 事件、2 个 PASS leaf。
- `TestExecutionBindingIssuanceLimit` 实际 PASS（非 SKIP），4 个 PASS 事件、3 个 PASS leaf：
  - `.../under_limit_still_issues`
  - `.../limit_reached_rejects_new_challenge`
  - `.../replay_still_works_at_limit`
- handler/daemon 的 `migrations` 为空，符合命令设计。

## 实际结果

| # | 包 / pattern | nonce | exit | RUN | PASS | FAIL | SKIP | PASS leaf | SKIP leaf |
|---|---|---|---|---:|---:|---:|---:|---:|---:|
| 1 | `./internal/governance` `^Test` | `3ab277bb0be67f7c` | 0 | 904 | 903 | 0 | 1 | 817 | 1 |
| 2 | `./internal/handler` `^TestStartClaim` | `a6aac052451093a7` | 0 | 13 | 13 | 0 | 0 | 10 | 0 |
| 3 | `./internal/daemon` `^Test(TerminalReport\|SendTerminalTaskReport\|Execution)` | `cd09209a414745e1` | 0 | 125 | 124 | 0 | 1 | 115 | 1 |

### SKIP 明细（不计 PASS）

- governance `TestReconcileLiveGitHub`：`reconcile_live_test.go:21: KNOWLEDGE_BASE_REMOTE_URL / KNOWLEDGE_BASE_TOKEN not set`；本组另有 817 个 leaf 通过，非全叶 SKIP。
- daemon `TestExecutionTrustRefusesLinkedRootInsideWorkspace`：`execution_trust_test.go:133`，Windows symlink 权限；本组另有 115 个 leaf 通过，非全叶 SKIP。

## 门禁与基线

三条 meta 均满足：`test.exit==0`、`error==null`、`package_failures==0`、`output_redacted==false`、`leaf_pass>0`、`original_unchanged==true`、`original_release.sessions==0`、`original_release.locks==0`、`owned_resources_cleaned==true`。stderr 均为 0 字节。

- 每条 `original-before.json` / `original-after.json` 与冻结基线 `current-bindings-20261025T034807Z-preflight.json` 的 `rows` 完全一致：**137 表、6228 行、82 条审批 ID+hash**。
- 每条 before 与 after 完全相等，无原库漂移或写入。
- 14 项源码在每条执行前后均与 freeze 相同。

## 临时资源与末尾 catalog

| # | role OID | database OID | 末尾 catalog |
|---|---:|---:|---|
| governance | 339276 | 339277 | `database_present=false`, `role_present=false` |
| handler | 342634 | 342635 | `database_present=false`, `role_present=false` |
| daemon | 345473 | 345474 | `database_present=false`, `role_present=false` |

- 每条均为独占 nonce 的 template0/schema-only 新库与受限 login；approval/workspace 为空，原 approval 表真实读被 permission denied；未复制原表行。
- 未强杀、未 `DROP OWNED`、未前缀清理、未手工补删；catalog 按精确库名/role 名核验不存在。

## trust-root 探针只读核对（未运行 podman）

核对文件：`trust-root-20261025T085700Z-probe.json`（9 checks）与 `trust-root-20261025T084600Z-report.md`。

**与 JSON 字段一致的核心表述：**

- 同 UID 可改公钥：`same_uid_rewrite_possible=true`，一致。
- 容器只读 bind 挡住写尝试：`container_rewrite_denied=true`；checks 含 “every container write attempt was denied”“a fresh create fails with a read-only filesystem error”“the key content is unchanged after every attempt”，一致（限于本探针尝试范围）。
- 无控制通道：`control_channel_visible=false`，一致。
- 无宿主工作区暴露：`host_workspace_mounted=false`，与“无宿主工作区”一致。
- 准入/消费关闭：`admission_enabled=false`、`consumption_enabled=false`，与“消费关闭”一致。
- 探针整体 claim 与报告结论方向一致：same-UID 不能保护验签键；只读容器 bind 能挡住且不暴露控制通道。

**需要修正/不能直接由 JSON 支撑的文本：**

1. 报告写 “两者仍 `unresolved: false`” 与“仍 unresolved / major 未关闭”方向相反，是明显的状态措辞错误；不能据此把 major 说成已关闭。
2. 报告末尾“退出码 0 表示 7 项断言全过”，与本轮 9 checks 及报告自身“9 项 check 全过”不一致；7 是旧版数字。
3. 报告写 “`/work` 空卷”，而新探针要求并断言 `/work` 不存在/无 workspace volume；JSON 的 `host_workspace_mounted=false` 支持“未挂载”，但“空卷”是陈旧且容易误导的表述。
4. “9 类写尝试”在 JSON 中没有逐项清单，JSON 只有 `container_rewrite_denied=true` 和 “every container write attempt was denied” 的聚合断言；具体 9 个向量需由探针脚本/日志支撑，不能仅凭该 JSON 逐项复核。
5. “daemon 尚未容器化”不是该 JSON 的字段结论；JSON 能支持的是 admission/consumption 关闭与探针未接任务/claim/准入的范围说明，不能单独证明 daemon 部署形态。

**核对结论：** 核心安全方向没有被夸大——同 UID 可改、只读 bind 能挡、无控制通道、消费关闭均有 JSON 字段/checks 支撑；但报告存在状态反转（`unresolved: false`）、旧计数（7 vs 9）、`/work` 空卷等陈旧措辞，以及“daemon 尚未容器化”这类非 JSON 直接事实。应修正文本，不能把该报告当作 major 已关闭或 admission/隔离域已交付的证据。

## 最终只读核对（取自最后一条 daemon 的 after 与 release；未额外手工连库）

- `original-after` 与冻结基线 `rows` 完全一致：137 表 / 6228 行 / 82 审批。
- `original_unchanged=true`、`original_release={sessions:0,locks:0}`、`error=null`。
- 之后无运行中测试、无遗留 owned 临时库/role。

## 边界声明

- 本次只是硬签发上限、tools verifier 互通与 trust-root 探针文本核对的**组件证据**，**不签**消费、准入、activation、隔离域或全局 C1。
- 旧 claim 锁序仍 **INCOMPLETE**；完整业务 TC 仍 **0/49**，5 个 major 未关闭，消费仍关闭。
- 未访问真实 CR、未做真实模型调用、未写原库、未改源码/测试、未 gate/commit/push。
- 请求配置 requested `Gobao/deepseek-flash/max`（configured schema1），actual unknown。
- 历史红绿原始证据全部保留，未覆盖旧 prefix。

## DB 权

**DB 单执行权已释放，无运行中测试；无遗留 owned 临时数据库/role。**

## 附：同代理 final5 报告的重投（时间顺序澄清）

代理 `01a17158-a034-77b9-a3c5-0eed780e9d5f` 的 **final5** 报告（`…-final5-independent-report.md`，sha `5a9230dc…b5ad5`）在本轮结束时被平台重投。它是**同一代理更早一次执行**的结果（前缀 `final5-independent-`，跑的是加入 advisory lock 之前的 final5 冻结），当时同样三项全绿、原库无漂移。

冻结链的认领顺序不变：

1. final4（13 项）—— 历史，不认领；
2. **final5（14 项）—— 历史，不认领**（本附注针对它）；
3. **final6（14 项）—— 已认领**，跑在含 advisory lock 的源码上：治理 904/903/0/1（817 leaf）、handler 13/13（10）、daemon 125/124/0/1（115）；
4. final7（14 项）—— 相对 final6 只有 execution_binding_issue.go 的**注释**改动与探针断言/JSON 字段改动（探针不参与 go 测试），作者 issuelimit-green4 25/25（22 leaf）复跑通过。

因此 final5 的重投**不改变**任何结论，也不需要重跑；差异只是 final5 缺少 advisory lock（其"硬上限"表述已在 strong resume4 判 OPEN 后撤回，见 `…-issuelimit-report.md`）。

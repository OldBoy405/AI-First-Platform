# binding issue final3（tools verifier 互操作）独立回归报告

- at: 2026-10-25T08:33Z
- 角色: 本片唯一 DB 执行者（非作者）；未改产品/测试源码
- 证据前缀: `binding-issue-20261025T081500Z-final3-independent-`
- DB 访问: 仅版本化 `scripts/aifi45-db/run.mjs` 串行 3 条；未手工 SQL/psql，未启动/操作容器
- 三条命令均设置 `AIFI45_TOOLS_ROOT=C:/Users/GOBAO/Downloads/AI/tools`
- 结论: 3 条命令均完成且 runner/资源/原库门禁通过；互通用例真实 PASS（非 SKIP）；混合 SKIP 均单列且不计 PASS。本文只是组件证据，不签消费/准入/activation/隔离域/全局 C1。

## 权威源码冻结与 pins

- 权威 freeze: `binding-issue-20261025T081500Z-final3-freeze-manifest.json`，13 项，sha256 `ab182ab98588a1dec93279818bd61f864dda0852f0113bd88ce35382366ffae5`
- 每条命令执行前，自读实际文件重算 raw/LF，13/13 与 freeze 相等；执行后再次重算仍 13/13 相等（无漂移）。未沿用他人 manifest 声明。
- 三条 wx 新建 pre-run pin:
  - governance `0cb027f27fceb6f17ce67b09f55107615363cc03d8f9fb4545515ca949ee1e13`
  - handler `a0175a80c13b2b286a56a62b36bde6ba9e193e41ac9fdad052ee0dc255182ab7`
  - daemon `740b47ceb827c98116fdf23a29e0b3309eb1461e36d125d0e3b623bae5eb800e`
- 上一轮 final2 结论保留为历史，不再被本最终源码认领，也未删除/改写。

## 命令（cwd=C:/Users/GOBAO/Downloads/AI/multica，flag 均在 prefix 之后）

1. `AIFI45_TOOLS_ROOT=C:/Users/GOBAO/Downloads/AI/tools node scripts/aifi45-db/run.mjs ./internal/governance '^Test' "<V>/binding-issue-20261025T081500Z-final3-independent-governance" -timeout=280s -migration=server/migrations/643_cr_execution_binding_issue.up.sql`
2. `AIFI45_TOOLS_ROOT=C:/Users/GOBAO/Downloads/AI/tools node scripts/aifi45-db/run.mjs ./internal/handler '^TestStartClaim' "<V>/binding-issue-20261025T081500Z-final3-independent-handler" -timeout=280s`
3. `AIFI45_TOOLS_ROOT=C:/Users/GOBAO/Downloads/AI/tools node scripts/aifi45-db/run.mjs ./internal/daemon '^Test(TerminalReport|SendTerminalTaskReport|Execution)' "<V>/binding-issue-20261025T081500Z-final3-independent-daemon" -timeout=280s`

## 迁移与互操作

- 第 1 条 `migrations` 与事件记录：
  - path: `server/migrations/643_cr_execution_binding_issue.up.sql`
  - sha256: `495ec3c0ee54d1a29b3ad376a2f7d0cbd5844960c9035685a7821fb612cfcbbe`
- `TestExecutionBindingEnvelopeInteropWithToolsVerifier` 实际 PASS（不是 SKIP），共 3 个 PASS 测试事件、2 个 PASS leaf：
  - `.../real_tools_verifier_accepts_server_envelope`
  - `.../real_tools_verifier_rejects_tampered_payload`
- handler/daemon 的 `migrations` 为空，符合命令设计。

## 实际结果

| # | 包 / pattern | nonce | exit | RUN | PASS | FAIL | SKIP | PASS leaf | SKIP leaf |
|---|---|---|---|---:|---:|---:|---:|---:|---:|
| 1 | `./internal/governance` `^Test` | `96b9edc8d49a5bf3` | 0 | 900 | 899 | 0 | 1 | 814 | 1 |
| 2 | `./internal/handler` `^TestStartClaim` | `88fa14da771d0bfd` | 0 | 13 | 13 | 0 | 0 | 10 | 0 |
| 3 | `./internal/daemon` `^Test(TerminalReport\|SendTerminalTaskReport\|Execution)` | `fff0690030e66e61` | 0 | 125 | 124 | 0 | 1 | 115 | 1 |

### SKIP 明细（不计 PASS）

- governance `TestReconcileLiveGitHub`：`reconcile_live_test.go:21: KNOWLEDGE_BASE_REMOTE_URL / KNOWLEDGE_BASE_TOKEN not set`；本组另有 814 个 leaf 通过，非全叶 SKIP。
- daemon `TestExecutionTrustRefusesLinkedRootInsideWorkspace`：`execution_trust_test.go:133`，Windows symlink 权限；本组另有 115 个 leaf 通过，非全叶 SKIP。

## 门禁与基线

三条 meta 均满足：`test.exit==0`、`error==null`、`package_failures==0`、`output_redacted==false`、`leaf_pass>0`、`original_unchanged==true`、`original_release.sessions==0`、`original_release.locks==0`、`owned_resources_cleaned==true`。stderr 均为 0 字节。

- 每条 `original-before.json` / `original-after.json` 与冻结基线 `current-bindings-20261025T034807Z-preflight.json` 的 `rows` 完全一致：**137 表、6228 行、82 条审批 ID+hash**。
- 每条 before 与 after 完全相等，无原库漂移或写入。
- 13 项源码在每条执行前后均与 freeze 相同。

## 临时资源与末尾 catalog

| # | role OID | database OID | 末尾 catalog |
|---|---:|---:|---|
| governance | 300462 | 300463 | `database_present=false`, `role_present=false` |
| handler | 303562 | 303563 | `database_present=false`, `role_present=false` |
| daemon | 306404 | 306405 | `database_present=false`, `role_present=false` |

- 每条均为独占 nonce 的 template0/schema-only 新库与受限 login；approval/workspace 为空，原 approval 表真实读被 permission denied；未复制原表行。
- 未强杀、未 `DROP OWNED`、未前缀清理、未手工补删；catalog 按精确库名/role 名核验不存在。

## 最终只读核对（取自最后一条 daemon 的 after 与 release；未额外手工连库）

- `original-after` 与冻结基线 `rows` 完全一致：137 表 / 6228 行 / 82 审批。
- `original_unchanged=true`、`original_release={sessions:0,locks:0}`、`error=null`。
- 之后无运行中测试、无遗留 owned 临时库/role。

## 边界声明

- 本次只是服务端执行绑定签发与 tools verifier 互操作的**组件证据**，**不签**消费、准入、activation、隔离域或全局 C1。
- 旧 claim 锁序仍 **INCOMPLETE**；完整业务 TC 仍 **0/49**，5 major 未关闭，消费仍关闭。
- 未访问真实 CR、未做真实模型调用、未写原库、未改源码/测试、未 gate/commit/push。
- 请求配置 requested `Gobao/deepseek-flash/max`（configured schema1），actual unknown。
- 历史红绿原始证据全部保留，未覆盖旧 prefix。

## DB 权

**DB 单执行权已释放，无运行中测试；无遗留 owned 临时数据库/role。**

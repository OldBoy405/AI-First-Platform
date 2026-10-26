# binding issue final2（CR 归属首次写入胜出）独立回归报告

- at: 2026-10-25T08:25Z
- 角色: 本片唯一 DB 执行者（非作者）；未改产品/测试源码
- 证据前缀: `binding-issue-20261025T081500Z-final2-independent-`
- DB 访问: 仅版本化 `scripts/aifi45-db/run.mjs` 串行 3 条；未手工 SQL/psql，未启动/操作容器
- 结论: 3 条命令均完成且 runner/资源/原库门禁通过；混合 SKIP 均单列且不计 PASS。本文只是组件证据，不签消费/准入/activation/隔离域/全局 C1。

## 权威源码冻结与 pins

- 权威 freeze: `binding-issue-20261025T081500Z-final2-freeze-manifest.json`，13 项，sha256 `4df74ce6d6e74422f6762b7f32ceabf3a6f74e0e4019c6b764825debbbe8ca82`
- 每条命令执行前，自读实际文件重算 raw/LF，13/13 与 freeze 相等；执行后再次重算仍 13/13 相等（无漂移）。未沿用他人 manifest 声明。
- 三条 wx 新建 pre-run pin:
  - governance `70e266e240b4c19b7f65905b84fee390233c5fe70d15a048b2a035e68c7deb1e`
  - handler `a71429ee877fb49e29a41852227f38768372ac7008ff22c05777703d3e84e5c6`
  - daemon `a251f5d95c3cd311cfe8c7dce854b5dc6e210ed32de607273572c106e1b4ddae`
- 上一轮 binding-issue final freeze（8 项）结论保留为历史，不再被本最终源码认领，也未删除/改写。

## 命令（cwd=C:/Users/GOBAO/Downloads/AI/multica，flag 均在 prefix 之后）

1. `node scripts/aifi45-db/run.mjs ./internal/governance '^Test' "<V>/binding-issue-20261025T081500Z-final2-independent-governance" -timeout=280s -migration=server/migrations/643_cr_execution_binding_issue.up.sql`
2. `node scripts/aifi45-db/run.mjs ./internal/handler '^TestStartClaim' "<V>/binding-issue-20261025T081500Z-final2-independent-handler" -timeout=280s`
3. `node scripts/aifi45-db/run.mjs ./internal/daemon '^Test(TerminalReport|SendTerminalTaskReport|Execution)' "<V>/binding-issue-20261025T081500Z-final2-independent-daemon" -timeout=280s`

## 迁移记录（第 1 条）

meta 与 `migrations-applied` 事件均记录：

- path: `server/migrations/643_cr_execution_binding_issue.up.sql`
- sha256: `495ec3c0ee54d1a29b3ad376a2f7d0cbd5844960c9035685a7821fb612cfcbbe`

handler/daemon 的 `migrations` 为空，符合命令设计；迁移只作用于 governance 的临时 schema-only 库。

## 实际结果

| # | 包 / pattern | nonce | exit | RUN | PASS | FAIL | SKIP | PASS leaf | SKIP leaf |
|---|---|---|---|---:|---:|---:|---:|---:|---:|
| 1 | `./internal/governance` `^Test` | `18fa523375e007c7` | 0 | 897 | 896 | 0 | 1 | 812 | 1 |
| 2 | `./internal/handler` `^TestStartClaim` | `750794c6c964e677` | 0 | 13 | 13 | 0 | 0 | 10 | 0 |
| 3 | `./internal/daemon` `^Test(TerminalReport\|SendTerminalTaskReport\|Execution)` | `2b4e6957bf4b09c5` | 0 | 125 | 124 | 0 | 1 | 115 | 1 |

### SKIP 明细（不计 PASS）

- governance `TestReconcileLiveGitHub`：`reconcile_live_test.go:21: KNOWLEDGE_BASE_REMOTE_URL / KNOWLEDGE_BASE_TOKEN not set`，环境未配置导致 SKIP；本组另有 812 个 leaf 通过，非全叶 SKIP。
- daemon `TestExecutionTrustRefusesLinkedRootInsideWorkspace`：`execution_trust_test.go:133`，Windows symlink 权限 `A required privilege is not held by the client`，SKIP；本组另有 115 个 leaf 通过，非全叶 SKIP。

## 门禁与基线

三条 meta 均满足：`test.exit==0`、`error==null`、`package_failures==0`、`output_redacted==false`、`leaf_pass>0`、`original_unchanged==true`、`original_release.sessions==0`、`original_release.locks==0`、`owned_resources_cleaned==true`。stderr 均为 0 字节。

- 每条 `original-before.json` / `original-after.json` 与冻结基线 `current-bindings-20261025T034807Z-preflight.json` 的 `rows` 完全一致：**137 表、6228 行、82 条审批 ID+hash**。
- 每条 before 与 after 完全相等，无原库漂移或写入。
- 13 项源码在每条执行前后均与 freeze 相同。

## 临时资源与末尾 catalog

| # | role OID | database OID | 末尾 catalog |
|---|---:|---:|---|
| governance | 288827 | 288828 | `database_present=false`, `role_present=false` |
| handler | 291926 | 291927 | `database_present=false`, `role_present=false` |
| daemon | 294768 | 294769 | `database_present=false`, `role_present=false` |

- 每条均为独占 nonce 的 template0/schema-only 新库与受限 login；approval/workspace 为空，原 approval 表真实读被 permission denied；未复制原表行。
- 未强杀、未 `DROP OWNED`、未前缀清理、未手工补删；catalog 按精确库名/role 名核验不存在。

## 最终只读核对（取自最后一条 daemon 的 after 与 release；未额外手工连库）

- `original-after` 与冻结基线 `rows` 完全一致：137 表 / 6228 行 / 82 审批。
- `original_unchanged=true`、`original_release={sessions:0,locks:0}`、`error=null`。
- 之后无运行中测试、无遗留 owned 临时库/role。

## 边界声明

- 本次只是 CR 归属首次写入胜出与服务端执行绑定签发的**组件证据**，**不签**消费、准入、activation、隔离域或全局 C1。
- 旧 claim 锁序仍 **INCOMPLETE**；完整业务 TC 仍 **0/49**，5 major 未关闭，消费仍关闭。
- 未访问真实 CR、未做真实模型调用、未写原库、未改源码/测试、未 gate/commit/push。
- 请求配置 requested `Gobao/deepseek-flash/max`（configured schema1），actual unknown。
- 历史红绿原始证据全部保留，未覆盖旧 prefix。

## DB 权

**DB 单执行权已释放，无运行中测试；无遗留 owned 临时数据库/role。**

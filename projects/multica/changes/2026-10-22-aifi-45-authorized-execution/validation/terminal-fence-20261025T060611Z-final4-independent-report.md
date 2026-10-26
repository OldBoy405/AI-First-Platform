# terminal fence final4 freeze 独立回归报告

- at: 2026-10-25T07:35Z
- 角色: 本片唯一 DB 执行者（非作者）；未改产品/测试源码
- 证据前缀: `terminal-fence-20261025T060611Z-final4-independent-`
- DB 访问: 仅版本化 `scripts/aifi45-db/run.mjs` 串行 3 条；未手工 SQL/psql，未启动/操作容器
- 结论: 3 条均完成且 runner/资源/原库门禁通过；混合 SKIP 均单列且不计 PASS。本文仅覆盖终端 fence 组件独立回归，不签完整 terminal 链、生产准入或全局 C1。

## 权威源码冻结与 pins

- 权威 freeze: `terminal-fence-20261025T060611Z-final4-freeze-manifest.json`，27 项，sha256 `bfb95c31be3e0b3c5ffa7e3928e7ffc09f1f9e95bb168edc90a8818b565918d0`
- 每条命令执行前，自读实际文件重算 raw/LF，27/27 与 final4 freeze 相等；执行后再次重算仍 27/27 相等（无漂移）。未沿用他人 manifest 声明。
- 三条 wx 新建 pre-run pin:
  - governance `07e670c9980243c429a896fb431de35c46d201dee44e79fe063d407ff224c095`
  - handler `1b9dc637fc95961098eab7069dafa8e7c37574b2e53a70197349620bdb3e135f`
  - daemon `7609312fb1ec02aa3e86bbf6abb714a34845f4c9b4271be7be844d226fbe65d3`
- 上一轮 final3 的结论保留为历史，不再被本最终源码认领，也未删除/改写。

## 命令（cwd=C:/Users/GOBAO/Downloads/AI/multica，flag 均在 prefix 之后）

1. `node scripts/aifi45-db/run.mjs ./internal/governance '^Test' "<V>/terminal-fence-20261025T060611Z-final4-independent-governance" -timeout=280s`
2. `node scripts/aifi45-db/run.mjs ./internal/handler '^TestStartClaim' "<V>/terminal-fence-20261025T060611Z-final4-independent-handler" -timeout=280s`
3. `node scripts/aifi45-db/run.mjs ./internal/daemon '^Test(TerminalReport|SendTerminalTaskReport|Execution)' "<V>/terminal-fence-20261025T060611Z-final4-independent-daemon" -timeout=280s`

## 实际结果

| # | 包 / pattern | nonce | exit | RUN | PASS | FAIL | SKIP | PASS leaf | SKIP leaf |
|---|---|---|---|---:|---:|---:|---:|---:|---:|
| 1 | `./internal/governance` `^Test` | `4ed6eccd5e597986` | 0 | 879 | 878 | 0 | 1 | 795 | 1 |
| 2 | `./internal/handler` `^TestStartClaim` | `40f1d9befd5e3943` | 0 | 13 | 13 | 0 | 0 | 10 | 0 |
| 3 | `./internal/daemon` `^Test(TerminalReport\|SendTerminalTaskReport\|Execution)` | `7cd04a6f473da3c9` | 0 | 125 | 124 | 0 | 1 | 115 | 1 |

### SKIP 明细（不计 PASS）

- governance `TestReconcileLiveGitHub`：`reconcile_live_test.go:21: KNOWLEDGE_BASE_REMOTE_URL / KNOWLEDGE_BASE_TOKEN not set`，环境未配置导致 SKIP；本组另有 795 个 leaf 通过，非全叶 SKIP。
- daemon `TestExecutionTrustRefusesLinkedRootInsideWorkspace`：`execution_trust_test.go:133`，Windows symlink 权限 `A required privilege is not held by the client`，SKIP；本组另有 115 个 leaf 通过，非全叶 SKIP。

## 门禁与基线

三条 meta 均满足：`test.exit==0`、`error==null`、`package_failures==0`、`output_redacted==false`、`leaf_pass>0`、`original_unchanged==true`、`original_release.sessions==0`、`original_release.locks==0`、`owned_resources_cleaned==true`。stderr 均为 0 字节。

- 每条 `original-before.json` / `original-after.json` 与冻结基线 `current-bindings-20261025T034807Z-preflight.json` 的 `rows` 完全一致：**137 表、6228 行、82 条审批 ID+hash**。
- 每条 before 与 after 完全相等，无原库漂移或写入。
- 27 项源码在每条执行前后均与 final4 freeze 相同。

## 临时资源与末尾 catalog

| # | role OID | database OID | 末尾 catalog |
|---|---:|---:|---|
| governance | 239727 | 239728 | `database_present=false`, `role_present=false` |
| handler | 242794 | 242795 | `database_present=false`, `role_present=false` |
| daemon | 245636 | 245637 | `database_present=false`, `role_present=false` |

- 每条均为独占 nonce 的 template0/schema-only 新库与受限 login；approval/workspace 为空，原 approval 表真实读被 permission denied；未复制原表行。
- 未强杀、未 `DROP OWNED`、未前缀清理、未手工补删；catalog 按精确库名/role 名核验不存在。

## 最终只读核对（取自最后一条 daemon 的 after 与 release；未额外手工连库）

- `original-after` 与冻结基线 `rows` 完全一致：137 表 / 6228 行 / 82 审批。
- `original_unchanged=true`、`original_release={sessions:0,locks:0}`、`error=null`。
- 之后无运行中测试、无遗留 owned 临时库/role。

## 边界声明

- 本次仍只是终端 fence 组件的独立回归，**不签**完整 terminal 链、生产准入或全局 C1。
- 旧 claim 锁序仍 **INCOMPLETE**；完整业务 TC 仍 **0/49**，5 major 未关闭，消费仍关闭。
- 未访问真实 CR、未做真实模型调用、未写原库、未改源码/测试、未 gate/commit/push。
- 请求配置 requested `Gobao/deepseek-flash/max`（configured schema1），actual unknown。
- 历史红绿原始证据全部保留，未覆盖旧 prefix。

## DB 权

**DB 单执行权已释放，无运行中测试；无遗留 owned 临时数据库/role。**

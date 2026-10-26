# AIFI-45 claim/project 独立 balanced 回归报告

- at: 2026-10-25T05:55Z
- 角色: 独立 balanced 执行者（非产品/测试作者）
- DB 执行: 仅通过版本化 `scripts/aifi45-db/run.mjs` 串行 3 条；未手工 SQL/psql，未启动/操作容器，未修改源码/测试/fixture/计划/台账/旧审批/旧证据
- 证据前缀: `claim-project-20261025T052646Z-`（新 prefix；旧 `current-bindings-*` 全部保留，未覆盖）
- 结论: 3 条 runner 命令均完成且门禁通过；daemon 唯一 Windows symlink leaf SKIP 不计 PASS。本文不构成完整业务 TC、C1 或授权准入签署。
- 请求配置: 刚从 M native CLI 读取 schema1/configured，requested balanced `Gobao/deepseek-flash/max`；actual unknown。

## 源码 freeze 与 pre-run pins

- freeze: `claim-project-20261025T052646Z-source-manifest.json`，19 项，sha256 `ae99639a7ed5a84bd93fa7f4afa541f7a4996fd2396eac9a8fee7a00702b61ee`
- 每条命令前以 `wx` 新建独立 manifest，实际 raw/LF 逐项与 freeze 的 19 项相等；三条执行后再次复核仍 19/19 相等（无源码漂移）:
  - governance pin sha256 `fea2d55b2a80ca52cee017d62b2aa61b3590bf45a51f459f5f272a810d64fac2`
  - handler pin sha256 `1ef9d570346aa023138de1cdf9f54468319888a44be104f5703f1e7951411c40`
  - daemon pin sha256 `e4e87cb3a4f197249ec388d98e300dcdbcd939c5b6272b1c875f818313c883bf`
- `run.mjs` 自身包含在 19 项 freeze 内且匹配。

## 执行命令（cwd=C:/Users/GOBAO/Downloads/AI/multica）

1. `node scripts/aifi45-db/run.mjs ./internal/governance '^Test' ".../claim-project-20261025T052646Z-independent-governance" -skip=LiveGitHub`
2. `node scripts/aifi45-db/run.mjs ./internal/handler '^TestStartClaim' ".../claim-project-20261025T052646Z-independent-handler"`
3. `node scripts/aifi45-db/run.mjs ./internal/daemon 'Test.*Execution' ".../claim-project-20261025T052646Z-independent-daemon" -skip=LiveGitHub`

runner 注入默认 `-timeout=180s`；未添加额外未授权参数。每条 events 为 11 个（plan, source-preserved, create-role-intent, create-database-intent, created, isolation-verified, test-finished, original-compared, database-dropped, role-dropped, resources-absence-verified）。

## 实际结果

| # | 包 / pattern | nonce | exit | run | pass | fail | skip | leaf_pass | leaf_skip |
|---|---|---|---|---:|---:|---:|---:|---:|---:|
| 1 | `./internal/governance` `^Test` | `3f36a23d881c7fc2` | 0 | 851 | 851 | 0 | 0 | 770 | 0 |
| 2 | `./internal/handler` `^TestStartClaim` | `bf555c723cd43ede` | 0 | 13 | 13 | 0 | 0 | 10 | 0 |
| 3 | `./internal/daemon` `Test.*Execution` | `0e3048aa5a165d43` | 0 | 113 | 112 | 0 | 1 | 106 | 1 |

- governance 与 author 的 851/851、770 leaf 一致；daemon 与 author 的 112 PASS / 1 SKIP、106 leaf 一致；handler 13/13、10 leaf。
- 每条均核验: `test.exit==0`、`error==null`、`package_failures==0`、`output_redacted==false`、`leaf_pass>0`、`original_unchanged==true`、`original_release sessions=0/locks=0`、`owned_resources_cleaned==true`。
- 每条 `original-before.json` 与 `current-bindings-20261025T034807Z-preflight.json` 的 219 行冻结基线（137 表 + 82 approval）逐项完全相等；每条 before/after 也完全相等。
- 唯一 SKIP: `TestExecutionTrustRefusesLinkedRootInsideWorkspace`（`execution_trust_test.go:133`，Windows symlink 权限 `A required privilege is not held by the client`），**未计 PASS**；非全叶 SKIP。governance/handler 无 SKIP。
- 所有 stderr 0 字节；无生成密码泄露。

## 精确 catalog / 资源

| # | role OID | database OID | 最终 catalog |
|---|---:|---:|---|
| governance | 125215 | 125216 | `database_present=false`, `role_present=false` |
| handler | 128282 | 128283 | `database_present=false`, `role_present=false` |
| daemon | 131124 | 131125 | `database_present=false`, `role_present=false` |

- 每条为独占 nonce 的 template0/schema-only 新库与受限 login；approval/workspace 为空，对原 approval 表真实读被 permission denied；未复制原表行。
- 未使用强杀、`DROP OWNED`、前缀清理或手工补删；catalog 按精确数据库名/role 名核验不存在。
- 原库 `stdd_aifi45_20261022` 保持 137 表/82 approval，事故现场 HOLD 未变；原 83 未恢复，82 仅为事后现场。

## 保留与边界

- 旧 SDK 编译失败为 0 RUN，不计业务 RED；所有历史红绿原始证据保留，不以本次结果覆盖。
- 本次仅证明相应包级回归与 runner/资源/原库门禁；**不是完整业务 TC**。业务仍 **0/49**，5 major unresolved，消费关闭；Gate3 未授权，无 commit/push/发布。
- readonly claim snapshot 不等于 MDT 隔离、签名或 admission；不签 C1/授权准入。
- 未新增代理，未改产品/测试/fixture/计划/台账/旧审批。

## DB 权

DB 单执行权已释放；无遗留 owned 临时数据库/role。

# AIFI-45 独立 balanced 回归报告（current project resource read）

- at: 2026-10-25T04:40:59.148Z
- 角色: 独立 balanced 回归执行者（非作者）；源码已冻结
- 证据前缀: current-bindings-20261025T034807Z-
- DB 执行: 仅通过版本化 scripts/aifi45-db/run.mjs，串行 3 条；未使用旧 Temp runner，未手工执行 SQL/psql/其他入口，未启动容器
- 结论: 3 条 runner 命令均完成且 runner 级门禁通过；daemon 有 1 个已知 Windows symlink leaf SKIP，按要求不计 PASS 并逐项列明。本文不构成完整业务 TC、C1 或授权准入签署。

## 请求配置

- 来源: multica 根原生 CLI 读取 schema_version=1、kind=configured（证据见 current-bindings-20261025T034807Z-review-multica-models.json 与 current-bindings-20261025T034807Z-balanced-writer-source.json）
- requested: Gobao/deepseek-flash / effort max（balanced）
- actual: unknown（无后端凭据可证）
- 主会话自本条起未执行 DB 命令；本次 DB 单执行权由本执行者独占，结束已释放。

## 源码冻结与 pre-run pin

- 冻结清单: current-bindings-20261025T034807Z-source-manifest.json
- 冻结清单 sha256: a48ca661aa209be52707b9fc152b95e2d4164afb18e251516b52804045562983
- 11 个实际源码文件的 raw_sha256/LF_sha256/bytes 在每条命令执行前分别重算，全部与冻结 11 项相等；执行后再核仍全部相等（无源码漂移）。
- 每条独立的 pre-run pin（均以 wx 新建，记录实际 raw/LF 与 frozen 对照）:
  - independent-governance-source-manifest.json sha256 c0643d5969723ff144a588dddbf31cf0a7d2cf8fa70e5f5acdf37e86f9b57e78 (11/11 match)
  - independent-handler-source-manifest.json sha256 7b0c7d84ae67dbfc71860baf9080cb17bd2728dd7fc5041894542d58139cb81c (11/11 match)
  - independent-daemon-source-manifest.json sha256 09db68b4e6efa3f2558e17478c095017bbebeecc81dfcac64b65c318836146cd (11/11 match)
- 11 项含 run.mjs 自身 raw b4d70ae10ee5c0eabc51fc3cb897410ebfcee2816bdf097e93c147fc09a9df00，与冻结值相等。
- 作者中间阶段部分 manifest 为事后补采，不作为本报告的预先 pinned 凭据；本文以冻结包加本次三条 pre-run pin 为独立源码凭据。

## 执行命令（串行，cwd=C:/Users/GOBAO/Downloads/AI/multica）

1. node scripts/aifi45-db/run.mjs ./internal/governance "^Test" "C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/current-bindings-20261025T034807Z-independent-governance" -skip=LiveGitHub -timeout=180s
2. node scripts/aifi45-db/run.mjs ./internal/handler "^TestStartClaim" "C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/current-bindings-20261025T034807Z-independent-handler" -timeout=120s
3. node scripts/aifi45-db/run.mjs ./internal/daemon "Test.*Execution" "C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/current-bindings-20261025T034807Z-independent-daemon" -timeout=120s

说明: 该 runner parser 只接受单横线额外参数（skip/shuffle/timeout），因此按真实支持形式使用 -skip=LiveGitHub、-timeout=...；未使用伪装的 --skip。runner 默认先注入 -timeout=180s，extra 再追加，Go 取最后一次值：governance 实际 180s，handler/daemon 实际 120s。

## 结果汇总（每条 events 均为 11 个，顺序: plan, source-preserved, create-role-intent, create-database-intent, created, isolation-verified, test-finished, original-compared, database-dropped, role-dropped, resources-absence-verified）

| 命令 | 包 / pattern | nonce | go test exit | run | pass | fail | skip | leaf_pass | leaf_skip |
|---|---|---|---|---|---|---|---:|---:|---:|---:|
| 1 | ./internal/governance / ^Test | 7025f323deca009b | 0 | 828 | 828 | 0 | 0 | 749 | 0 |
| 2 | ./internal/handler / ^TestStartClaim | 8c468786e9c159ca | 0 | 13 | 13 | 0 | 0 | 10 | 0 |
| 3 | ./internal/daemon / Test.*Execution | e4dc67ababab45c7 | 0 | 69 | 68 | 0 | 1 | 64 | 1 |

每条均满足: meta test.exit==0、error==null、package_failures==0、output_redacted==false、真实 leaf_pass>0、original_unchanged==true、original_release sessions=0/locks=0、owned_resources_cleaned==true。

### SKIP 明细（不当 PASS）

- TestExecutionTrustRefusesLinkedRootInsideWorkspace（./internal/daemon）
  - 原因: execution_trust_test.go:133 "directory link unsupported: symlink ... A required privilege is not held by the client."
  - 性质: Windows 无 symlink 创建权限导致的 leaf SKIP；未计为 pass。daemon 其余 64 个 leaf 全部通过，未出现全叶 SKIP，故 runner 允许 leaf_pass>0。
- governance、handler 无任何 SKIP。

## 原库与资源（逐条）

- 原库/容器: stdd_aifi45_20261022 / 666bfec52ac3c3d13b43389891f50c4105833198eab7e4167b76f014a774e823（runner 固定 pin）。
- 每条 source-preserved: 137 张原表、82 条 approval 记录；测试前后 original-before/original-after 内容相等（JSON 逐项一致），approval id 与整行 hash 未漂移。
- 每条 test 后原库 release: sessions=0、locks=0。
- 资源精确 catalog 结果:
  - governance: 创建 role aifi45_role_7025f323deca009b (oid 67724) / db aifi45_tmp_7025f323deca009b (oid 67725)；drop 后 database_present=false、role_present=false。
  - handler: role aifi45_role_8c468786e9c159ca (oid 70791) / db aifi45_tmp_8c468786e9c159ca (oid 70792)；drop 后 database_present=false、role_present=false。
  - daemon: role aifi45_role_e4dc67ababab45c7 (oid 73633) / db aifi45_tmp_e4dc67ababab45c7 (oid 73634)；drop 后 database_present=false、role_present=false。
- 新建库均为 template0/schema-only 新库，受限 login 非 superuser/create-db/create-role/bypassrls，approval/workspace 为空，且对原库 approval 表真实读被 permission denied；未复制原表行。
- 所有 stderr 为 0 字节；stdout 无生成密码泄露（runner 检查 output_redacted=false）。未强杀、未用 DROP OWNED、未做前缀清理、未手工补删资源。
- schema/audit dump 的 sha256 逐条不同可由 pg_dump 随机 restrict token 解释；原库行级 snapshot 严格相等，非原库漂移。

## 边界声明

- 原 83 行历史未恢复；82 只是事故后的现场保全值，不是恢复原 83。
- 上述均为包级回归/runner 门禁结果，不是完整业务 TC；完整 TC 仍 0/49，5 个 major unresolved，消费仍关闭，无 Gate3、无 commit/push、无发布。
- 不签署整个 C1、不签署授权准入、不把本次结果当作每 repo 绑定/claim/隔离/activation/防降级/永久派发闭环证明。
- 作者结果仅作背景: server RED1 1 fail → GREEN1 1 pass；sdk-red1 16 RUN/6 PASS/10 FAIL（父含 1）→ sdk-green1 21/21、matrix-green1 11/11；均非完整业务 TC，未被本报告升级为完整验证。
- 未修改源码/测试/fixture/计划/台账/旧审批/旧证据；仅新增本前缀证据与本报。

## DB 权

DB 单执行权已释放。主会话可恢复其正常职责；本次未留下 owned 临时数据库/role，原库 HOLD 与事故现场保持原状。

# AIFI-45 P2 修复后最终独立 balanced 复跑报告（current project resource read）

- at: 2026-10-25T04:51:46.567Z
- 角色: 独立 balanced 执行者（非作者）；源码按 P2 freeze 冻结
- 证据标签: independent2-*（全新，与 P2 前 independent-* 分离）
- DB 执行: 仅通过版本化 scripts/aifi45-db/run.mjs 串行 3 条；未使用旧 Temp runner，未手工 SQL/psql，未启动容器
- 结论: 3 条均完成且 runner/资源/原库门禁全部通过；daemon 仍为同一 Windows symlink leaf SKIP（不计 PASS）。本文不构成完整业务 TC、C1 或授权准入签署。

## 请求配置

- 刚从 multica 根原生 CLI 重读 schema_version=1、kind=configured
- requested: balanced Gobao/deepseek-flash / effort max
- actual: unknown（无后端凭据）

## 源码 P2 freeze 与 pre-run pin

- P2 freeze: current-bindings-20261025T034807Z-p2-source-manifest.json
- P2 freeze sha256: e434dcec20a5e43e2dfac88d4be5a9fe59cb345f6e48482a80fdf3ca00361fa6
- 11 项中相对上一份 freeze 实际变化: server/internal/daemon/client.go, server/internal/daemon/execution_current_resource_binding_test.go
- 其他文件 raw/LF/bytes 与上一份一致；与 strong 结论相符的两处变化为 client.go 和 daemon 新测试文件。
- 每条命令前分别以 wx 新建实际 raw/LF pin，均记录 11/11 与 P2 freeze 相等；执行后再次核对仍 11/11 相等（无漂移）:
  - independent2-governance-source-manifest.json sha256 09a6d1fbc176b18b46794b6bfe385c2622c1076afd52e9fe5f96e79b5d8338c4
  - independent2-handler-source-manifest.json sha256 e4492da6bdededcfd666974ebb1488d63a533207d628141101a8fb98215968ca
  - independent2-daemon-source-manifest.json sha256 c9382ebe837301e105316aa9c6be3a48d9c32b51a927bd1dbcb9d0a274a30d46
- P2 前 independent-* 三组证据保留为历史；不作为本次最终结果追认。

## 执行命令（串行，cwd=C:/Users/GOBAO/Downloads/AI/multica）

1. node scripts/aifi45-db/run.mjs ./internal/governance "^Test" ".../validation/current-bindings-20261025T034807Z-independent2-governance" -skip=LiveGitHub -timeout=180s
2. node scripts/aifi45-db/run.mjs ./internal/handler "^TestStartClaim" ".../validation/current-bindings-20261025T034807Z-independent2-handler" -timeout=120s
3. node scripts/aifi45-db/run.mjs ./internal/daemon "Test.*Execution" ".../validation/current-bindings-20261025T034807Z-independent2-daemon" -timeout=120s

CLI 仍使用 parser 实际支持的单横线 -skip/-timeout；governance 实际 timeout 180s，handler/daemon 为 120s。每条 events 共 11 个（plan, source-preserved, create-role-intent, create-database-intent, created, isolation-verified, test-finished, original-compared, database-dropped, role-dropped, resources-absence-verified）。

## 结果汇总

| # | 包 / pattern | nonce | exit | run | pass | fail | skip | leaf_pass | leaf_skip |
|---|---|---|---|---:|---:|---:|---:|---:|---:|
| 1 | ./internal/governance / ^Test | 2f229c061693f934 | 0 | 828 | 828 | 0 | 0 | 749 | 0 |
| 2 | ./internal/handler / ^TestStartClaim | 88fcd401a941b7b2 | 0 | 13 | 13 | 0 | 0 | 10 | 0 |
| 3 | ./internal/daemon / Test.*Execution | 5029b9928ef336e9 | 0 | 73 | 72 | 0 | 1 | 67 | 1 |

- 每条均核验: test.exit==0、error==null、package_failures==0、output_redacted==false、真实 leaf_pass>0、original_unchanged==true、original_release sessions=0/locks=0、owned_resources_cleaned==true。
- daemon 相比 P2 前实际新增 4 个 test 事件（69→73 RUN，68→72 PASS，65→68 leaf，64→67 leaf pass；仍为 1 leaf SKIP）；新增测试名: TestExecutionCurrentProjectResourceBindingsClient/case-folded_aliases_cannot_override_canonical_fields, TestExecutionCurrentProjectResourceBindingsClient/case-folded_aliases_cannot_override_canonical_fields/alias_cannot_replace_invalid_canonical_bindings, TestExecutionCurrentProjectResourceBindingsClient/case-folded_aliases_cannot_override_canonical_fields/alias_cannot_replace_wrong_canonical_workspace, TestExecutionCurrentProjectResourceBindingsClient/case-folded_aliases_cannot_override_canonical_fields/alias_cannot_replace_tampered_canonical_descriptor_digest。
- 未预设 PASS 数字；以上为实际值。

### SKIP 明细

- TestExecutionTrustRefusesLinkedRootInsideWorkspace（./internal/daemon）：execution_trust_test.go:133 "directory link unsupported ... A required privilege is not held by the client."，Windows symlink 权限 SKIP，未计 PASS。
- governance、handler 无 SKIP；daemon 非全叶 SKIP（67 leaf 通过）。

## 原库与资源

- 原库: stdd_aifi45_20261022（固定容器 666bfec52ac3c3d13b43389891f50c4105833198eab7e4167b76f014a774e823）。
- 每条 source-preserved: 137 表、82 条 approval；before/after snapshot 内容相等；approval id/整行 hash 未漂移；每条测试后 sessions=0、locks=0。
- 资源精确 catalog:
  - governance: role 82153 / db 82154 → database_present=false、role_present=false
  - handler: role 85220 / db 85221 → database_present=false、role_present=false
  - daemon: role 88062 / db 88063 → database_present=false、role_present=false
- 均为独占 nonce、template0/schema-only 新库、受限 login（非 superuser/create-db/create-role/bypassrls），approval/workspace 为空，原 approval 表读被 permission denied；未复制原表行，未强杀、未 DROP OWNED、未前缀清理。
- 所有 stderr 0 字节；output_redacted=false。

## 边界与声明

- 原 83 行未恢复；82 只是事故后现场，不能称恢复原 83。
- 业务 TC 仍 0/49，5 major unresolved，消费关闭；无 Gate3、无 commit/push、无发布；未签 C1/授权准入。
- 作者上下文: SDK-RED2 25RUN/20PASS/5FAIL（3 失败 leaf + 2 父）→ GREEN2 25/25、23 leaf，原库不变/清理；仅背景，不替代本独立证据，也不等于完整业务 TC。
- 未修改源码/测试/fixture/计划/台账/旧审批/旧证据；仅写 independent2-* 新证据与本报。

## DB 权

DB 单执行权已释放；无遗留 owned 临时数据库/role，原库 HOLD 与事故现场保持原状。

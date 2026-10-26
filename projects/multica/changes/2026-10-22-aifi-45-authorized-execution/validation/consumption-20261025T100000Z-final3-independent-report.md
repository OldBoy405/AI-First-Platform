# consumption final3（对抗/并发）独立回归报告

- at: 2026-10-25T12:20Z
- 角色: 本轮唯一 DB 执行者（非作者）
- 代码仓/cwd: `C:/Users/GOBAO/Downloads/AI/multica`
- 证据仓: `.../validation/`
- 前缀: `consumption-20261025T100000Z-final3-independent-`
- DB 访问: 仅版本化 `scripts/aifi45-db/run.mjs` 三条串行
- 结论: 三条均完成且门禁通过；4 个对抗/并发用例全部实际 PASS（非 SKIP）；14/14 前后一致。

## 1. 源码冻结

- 权威 freeze: `consumption-20261025T100000Z-final3-freeze-manifest.json`，14 项，sha256 `7ff92c77ee47fefcf3ec17c39b16f1d32ca7177fde926703f0e518092991f7ce`
- 三条 pre-run pin 均 14/14 匹配；跑后复核仍 14/14（无漂移）:
  - consumption `b6ce9bfc3b54a2c59c07f1e2ddbfff6bd3a1a0348668c193ee920cdfa1f71ffa`
  - handler `8b55cda86832b36bddca1c6b7f4c760c2d3d47e28196d8819a7ffaffdb38e330`
  - daemon `0904f8d7fc434eb9af69332a930a727f2d13c81fb0bdf056e316d3aecb2e1d5a`
- final2 清单未作为本轮依据。

## 2. 回归计数

| # | 命令 | nonce | exit | RUN | PASS | FAIL | SKIP | PASS leaf | SKIP leaf |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | governance `^TestExecutionConsumption`（643+644） | `b4d50bd7b4f0d479` | 0 | 12 | 12 | 0 | 0 | 10 | 0 |
| 2 | handler `^TestStartClaim` | `e1b2f291e14bc8aa` | 0 | 13 | 13 | 0 | 0 | 10 | 0 |
| 3 | daemon `^Test(...)` | `50ed0273da3d9143` | 0 | 153 | 151 | 0 | 2 | 138 | 2 |

- 三条 meta：`test.exit=0`、`error=null`、`original_unchanged=true`、`owned_resources_cleaned=true`、`sessions=0`、`locks=0`。
- 每条 before/after 与 `current-bindings-20261025T034807Z-preflight.json` 完全一致：**137 表 / 6228 行 / 82 审批**。
- catalog 精确不存在：
  - governance role `481217` / db `481218`
  - handler role `484098` / db `484099`
  - daemon role `486937` / db `486938`
- SKIP 单列（不计 PASS）：daemon `TestExecutionBindingRelayHelperProcess`（helper）、`TestExecutionTrustRefusesLinkedRootInsideWorkspace`（Windows symlink）；governance 无 SKIP。

## 3. 四个对抗/并发用例

均实际 PASS（非 SKIP）：

| 用例 | 耗时 |
|---|---:|
| `TestExecutionConsumptionRefusesMovedAuthority/a_revoked_head_cannot_be_consumed` | 0.09s |
| `TestExecutionConsumptionRefusesMovedAuthority/another_generation_cannot_consume_this_proof` | 0.07s |
| `TestExecutionConsumptionRefusesMovedAuthority/a_consumed_proof_cannot_be_reconsumed_after_revoke` | 0.08s |
| `TestExecutionConsumptionIsRaceFree` | 0.10s |

governance `test.migrations` 记录两条：

- `server/migrations/643_cr_execution_binding_issue.up.sql` — `495ec3c0ee54d1a29b3ad376a2f7d0cbd5844960c9035685a7821fb612cfcbbe`
- `server/migrations/644_cr_execution_consumption.up.sql` — `d07d528240d4c5cfa74609e4029d7117badfb70360bd436912548726acf2e3bb`

## 4. 14/14 前后

| 时点 | 14/14 raw hash 与 final3 freeze |
|---|---|
| 三条跑前 | 一致 |
| 三条跑后 | 一致 |
| 最终 | **一致** |

未修改任何源码/测试/迁移；无 mutation、无临时文件。

## 5. 边界

receipt ≠ 准入；消费关闭；T 侧仍以 `EXECUTION_CONSUMPTION_REQUIRED` 退出；不签 activation/隔离域/全局 C1。旧 claim 锁序 INCOMPLETE；业务 TC 0/49，5 major 未关闭。

## DB 权

**DB 单执行权已释放，无运行中测试；无遗留 owned 临时数据库/role。**

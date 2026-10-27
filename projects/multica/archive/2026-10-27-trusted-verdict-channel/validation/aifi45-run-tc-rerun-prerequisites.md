# AIFI-45 `TC-RUN-001/002/003/006/007/010` 重跑前置

> 本文件由 M003（`2026-10-27-trusted-verdict-channel`）单方面提供**前置清单**，不是 AIFI-45 的回填，也不改它的记录。
> 依 `design-adjustments.md` ADJ-12：**通道组件通过不能自动回填 AIFI-45 的计数**；AIFI-45 台账仍是 **41/49**，
> 六条 RUN TC 仍是 **MISSING**。哪些能重跑、跑出来算什么，由 AIFI-45 自己决定并登记。

## 0. 通用前置（六条都要）

| # | 前置 | 现状 | 说明 |
|---|---|---|---|
| G-1 | 迁移 643–648 已应用到被测库 | 可用 | 只能经 `multica/scripts/aifi45-db/run.mjs`（每轮独占 nonce 库）；**不要**手工 `psql -f` |
| G-2 | daemon 端点已挂载 | **已完成**（M003） | `POST /api/daemon/crs/{crID}/execution-authorization/{consumption,activation}`、`GET /api/daemon/execution-control/merge-facts/{crID}`、`POST /api/daemon/execution-control/verdict`、`POST /api/daemon/crs/{crID}/merge-effects` |
| G-3 | 被测 CR 有**持久化 selection** | 需要造 | M003 的 strict 路径要求 `cr_execution_contract_selection` 有一行 `mode='strict'`；没有则按 legacy，fence 判据不同 |
| G-4 | 重跑前先复核对应 label 的证据仍新鲜 | 已完成 | `node scripts/aifi45-verify/channel-evidence.mjs verify <label> <prefix> --side go`，源码一变就报 `source changed`，此时先重跑该 label 再谈 TC |
| G-5 | 真实 daemon 凭据 | 需要 | 端点只认 daemon token 路径（`EXECUTION_DAEMON_BINDING_REQUIRED` 拒 PAT/JWT/task-token）；TC-RUN-002 的负例正依赖这一点 |

## 1. 逐条前置与 M003 贡献

| TC | 断言（摘 AIFI-45 test-plan） | M003 提供了什么 | 重跑前必须先绿 | 仍不在 M003 范围 |
|---|---|---|---|---|
| `TC-RUN-001` | 充分授权自动执行、无重复阶段确认；实际任务与 T receipt 匹配 | 受保护 verdict store（`execution-control-store`）+ reader 的 `DispatchCount`：派发前必须已有 committed T | `reader`（11 leaf）、`store`(node) | 真实 runner 的启动与阶段推进（AIFI-45 自己的入口） |
| `TC-RUN-002` | task-token/伪 header/越权/Agent 候选包 → 无有效 grant、无执行任务 | `binding` 6 leaf：644 只认 643 签发的 proof（`EXECUTION_BINDING_NOT_ISSUED`）、645 只认 644 记录过的 proof（`EXECUTION_ACTIVATION_CONFLICT`）、消费期间终态 UPDATE 得 `55P03` | `binding`（6 leaf，`bi4-20261027T144831Z`） | 「无执行任务」在真实队列里的断言 |
| `TC-RUN-003` | grant 落盘 ACK、T 未消费 → 只 wake 不推进；提交后才按实际状态 | `reader` 的 `missing_t_zero_dispatch` / `RequireCommittedTForStrict`：无 committed T 时零派发 | `reader` | periodic wake 的真实调度时序 |
| `TC-RUN-006` | T 拒绝/无进展/不可达、额度刚耗尽且已有 receipt、撤销 revision → 拒新根但允许最后已准入任务收尾；只有签名 resume 可恢复 | `policy-facts`（额度键 `GrantID\|Kind\|Target\|Environment`，不含安装/信任根）+ `policy-resume`（`signed_resume_no_revive`）+ D7 `StopNewAdmissionsTx`/`CheckDeploymentAccessTx`（`ExactRecovery` 只放行截止前 issued 的原请求） | `policy-facts`、`policy-resume`、`readiness-activation`、`readiness-access` | 业务侧「额度耗尽」的真实触发 |
| `TC-RUN-007` | 四阶段交接重启，唯一派发可恢复，不靠手敲命令或直接 walker | `worker`（接管只 `owner_fence+1`，回读整行）+ `recovery`(node)（五个固定动作）+ `d8-recovery`（同 lineage 重启保字节、regrant 不清零） | `worker`、`recovery`(node)、`d8-recovery` | 真实 daemon 重启编排 |
| `TC-RUN-010` | 敏感 action 缺专项无动作；精确授权正例只一次消费 | `policy`(node)：`consumeSensitiveAction` 只认原 `operation_id`（`sensitive_same_operation_replay`），额度键不含安装/信任根 | `policy`(node) 23 leaf | 敏感动作在生产环境的真实投递 |

## 2. 明确不构成重跑依据的

- **M003 的 label 全绿 ≠ 对应 TC 通过。** `binding` 绿只说明 643→644→645 链路在组件层一致；TC-RUN-002 还要求真实认证路由与真实队列。
- **不得用 M003 证据改写 AIFI-45 的 41/49。** `pending-adjustments.yaml` 的 M003 条目写死「通道组件通过不能自动回填或跨 change 双计」。
- **`strict-production` profile 未验证**（ADJ-4：本 change 只按 `channel-component` 验收）。任何 TC 若要求生产 profile，前置尚缺。
- **`binding`/`reader` 的绿灯带前置条件**：`binding` 每条 leaf 依赖一行 M003 strict selection；`reader` 的 fence 由「有 consumption ∨ strict selection」并集决定。重跑 TC 时若造的是 legacy CR，这些断言不适用。

## 3. 本地可复现的最小命令

```bash
# 证据复核（任一 label）
node scripts/aifi45-verify/channel-evidence.mjs verify binding \
  "<change>/validation/bi4-20261027T144831Z" \
  --expectations "<change>/validation/channel-test-expectations.json" --side go

# 数据库测试（隔离 nonce 库；不加 642）
node scripts/aifi45-db/run.mjs ./internal/governance '^TestChannelIngestBinding$' <prefix> \
  -migration=server/migrations/643_cr_execution_binding_issue.up.sql \
  -migration=server/migrations/644_cr_execution_consumption.up.sql \
  -migration=server/migrations/645_cr_execution_activation.up.sql \
  -migration=server/migrations/646_cr_execution_notice.up.sql \
  -migration=server/migrations/647_cr_execution_dispatch_root.up.sql \
  -migration=server/migrations/648_cr_execution_control.up.sql
```

`meta.json` 必须 `original_unchanged:true`、`owned_resources_cleaned:true`、`skip:0`，否则该轮不算。

## 4. M003 侧当前证据指针

| label | 跑次 | leaves |
|---|---|---|
| `binding` | `bi4-20261027T144831Z` | 6 |
| `reader` | `rg2-20261027T143755Z` | 11 |
| `policy-facts` / `policy-resume` | `pj-20261027T115443Z` | 5 / 5 |
| `worker`（go） | `wo-20261027T125625Z` | 7 |
| `d8-recovery` | `dg-20261027T125558Z` | 2 |
| `readiness-activation` / `readiness-access` | `s3-20261027T135434Z` / `s5-20261027T135518Z` | 4 / 3 |
| `policy` / `recovery` / `store`(node) | `n3-policy-20261027T142326Z` / `n3-recovery-20261027T142327Z` / `n-store-20261027T111459Z` | 23 / 2 / 2 |

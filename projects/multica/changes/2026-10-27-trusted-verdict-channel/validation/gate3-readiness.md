# Gate 3 就绪报告（2026-10-27）

> 这份报告回答一个问题：**现在能不能进 Gate 3（deliver）**。
> 每条结论都指向可复跑的跑次前缀；没有任何一条靠文字自称。
> 判定工具：`multica/scripts/aifi45-verify/channel-evidence.mjs`（`verify <label> <prefix>`，exit 0 才算过）。

## 0. 结论

**不能进 Gate 3。** 已实现并出证的部分是稳的（见 §1），但：
- 6 个 label 尚未实现（§2），其中 `composition` / `readiness-composition` 决定端点是否真的挂上线；
- `binding` 有 4 条 leaf **按规格设计就该是 RED**（§3），前置是 AIFI-45 的 G1/G2-G4 残余；
- 4 项环境/身份类证明仍 UNVERIFIED（§4），其中 ADJ-10 决定本机的隔离声明上限。

Gate 3 只能在 §2、§3 有明确处置（实现 / 划出范围 / 随上游修复）之后进行。

## 1. 已实现且证据当前有效（19 个 label）

全部在本轮用**当前源码**重跑并 `verify` 通过（早期证据因 ADJ-11 改过协议源码而失效，已刷新）：

| label | leaves | 跑次前缀 |
|---|---|---|
| `foundation-selection` | 5 | `r-foundation-selection-20261027T111158Z` |
| `foundation-reservation` | 5 | `r-foundation-reservation-20261027T111158Z` |
| `store-guards` | 9 | `r-store-guards-20261027T111158Z` |
| `migration-up` | 14 | `r-migration-up-20261027T111158Z` |
| `migration-down` | 14 | `r-migration-down-20261027T111322Z` |
| `migration-reapply` | 14 | `r-migration-reapply-20261027T111322Z` |
| `migration-protected` | 2 | `r-migration-protected-20261027T111322Z` |
| `task-tx` | 2 | `r-task-tx-20261027T111322Z` |
| `store-state` | 7 | `sx-20261027T110226Z` |
| `settlement` | 4 | `sh-20261027T110932Z` |
| `protocol`（go） | 3 | `ai-proto4-20261027T175236Z` |
| `merge-facts`（go） | 6 | `mk-20261027T104452Z` |
| `merge-effects`（go） | 4 | `mz-20261027T105320Z` |
| `isolation`（linux） | 5 | `iso-20261027T101534Z` |
| `protocol`（node） | 2 | `n2-protocol-20261027T111511Z` |
| `store`（node） | 2 | `n-store-20261027T111459Z` |
| `merge-facts`（node） | 11 | `mf-20261027T103357Z` |
| `merge-effects`（node） | 16 | `me-20261027T104637Z` |

变异（m1–m39）全部落在 `validation/mutations/`，每条带 `.patch` 与 `.sha256`，且各自只打红对应 leaf（例外：m26/m35/m37/m39 各打红两条，均为语义相关的两条）。

## 2. 未实现（6 label）

| label | leaves | 缺什么 | 影响 |
|---|---|---|---|
| `revoked-permit` | 2 | 撤销后 permit 零 effect + 控制表不变 | 撤销线性化的调用侧证据 |
| `policy-facts` | 5 | `ResolveFactsTx` 只消费已验签事实 | repair/sensitive 的准入 |
| `policy-resume` | 5 | signed resume 只消耗一次 epoch | resume 语义 |
| `reader` | 10 | 严格模式只由已提交可信事实驱动 | projection fence |
| `worker` / `d8-recovery` / `client` | 7 / 2 / 1 | daemon 侧 worker、恢复表、客户端 | C 路径运行时 |
| `composition` / `readiness-composition` | 2 / 1 | **路由挂载**（`merge-facts` 端点至今未接进 `cmd/server/router.go`） | 端点不挂上去，CLI 无法真实调用 |

`readiness-*`（protocol 3 / component 2 / activation 4 / retirement 3 / fresh-work 1 / access 3）、`deployment-observer` 4、`deployment-launch` 1 同样未实现；它们属 D7，依赖可信 observer 身份。
node 侧未实现：`worker` 1、`recovery` 2、`policy` 23、`readiness` 2、`isolation` 3。

## 3. 按规格设计就该 RED（不得登记完成）

`specs/verdict-channel/spec.md` SC-VC-024 明写：该 leaf 的真实前置是 **AIFI-45 的 G1 与 G2/G4 残余**，未修时按设计为 RED，**不得登记完成**。

受此约束的是 `binding` 的 4 条 leaf：

- `cross_issuance_challenge`（task A 的 challenge 用于 task B）
- `same_task_redispatch_challenge`（同 task/runtime 但旧 `dispatched_at`）
- `same_nonce_different_proof`（同 nonce 异证明）
- `claim_terminated_before_consume`（读 claim 后任务转终态，须以 `55P03` 证明行锁）

`binding` 的另 2 条（`start_preflight_643_645_match`、`generation_bound_once`）可以独立实现。
**Gate 3 报告必须把这 4 条列成 blocked-on-upstream，而不是「未完成」或（更糟）改测试让它变绿。**

## 4. 仍 UNVERIFIED 的证明（不可用「看起来对」替代）

| # | 项 | 现状 |
|---|---|---|
| 1 | `isolation` 的 Windows 3 leaf | 无第二个受限 Windows 身份、无命名管道实现；`_unsupported.go` 对所有平台原语返回 `EXECUTION_CHANNEL_ISOLATION_UNSUPPORTED`，缺 profile 时 `t.Fatalf` |
| 2 | `strict-production` profile | 本 change 只按 `channel-component` 验收（ADJ-4） |
| 3 | 对 agent 的隔离（ADJ-10） | agent 以 Windows 用户 GOBAO 运行，可 `wsl -u root` 免密；能改 launcher、读任一私有根。**接受为残余风险**，不声称满足 strict-production |
| 4 | execve 审计 | WSL 发行版在非初始 PID 命名空间，kernel 拒绝 audit 控制请求；改用 bpftrace `sched_process_*` tracepoint（已在 `p0-isolation-evidence.md` 记载替代关系） |
| 5 | Windows 目录 fsync | 未验证（写盘语义以 Linux 为准） |

## 5. 本 change 期间发现并修正的实现偏差

| 编号 | 内容 |
|---|---|
| ADJ-8 | key-purpose 从两种修为规格要求的三种（`control-command`/`tool-attestation`/`human`），SC-VC-008 闭环 |
| ADJ-9 | 重复 JSON 键从「仅顶层」扩到任意深度（两侧一致） |
| ADJ-11 | 方案 §2 逐条比对：域名改规格名、`digest=SHA256(domain\|\|payload)`、每 key 的 `domains/scope/valid_from/valid_until` 签发与验签两端都核、键材料两形式互斥、Go 递归拒重复键 |
| 期间 | `head.record_id` 缺失曾被当作「head 没动」→ 改 `UNVERIFIABLE`；`ack` 独立入口被 DB 触发器否掉（admission 边界冻结在 issuance 之后）→ ack 随 `created→issued` 写 |

## 6. AIFI-45 六条 RUN TC 可据此重跑（非「已回填」）

`TC-RUN-001`、`TC-RUN-002`、`TC-RUN-003`、`TC-RUN-006`、`TC-RUN-007`、`TC-RUN-010` **可按下列前置重跑**，本 change 不声称已回填：

1. 迁移 643–648 按 `r-migration-up-*` 的顺序应用（**不要加 642**：保留库已含其列，重复应用会报 duplicate column）。
2. 每轮用 `node scripts/aifi45-db/run.mjs` 起独占 nonce 库，要求 `original_unchanged:true`、`owned_resources_cleaned:true`、`skip=0`；结论只表述为「该库该轮通过」（ADJ-6），不声称隔离成立。
3. `protocol` 类测试需 `AIFI45_TOOLS_ROOT` 指向 tools 仓，共享夹具 v3 在 `tools/.../test/fixtures/control-vectors.json`。
4. `isolation` 需 `AIFI45_ISOLATION_PROFILE` + `AIFI45_ISOLATION_UID/GID`（本机 995/994）与 root。
5. 结论用 `channel-evidence.mjs verify <label> <prefix>` 判，不看报告文字。

## 7. 进 Gate 3 前的最小收尾清单

1. 实现 `revoked-permit`、`policy-facts`、`policy-resume`、`reader`（4 label / 22 leaf），各自带变异。
2. 把 `MountDaemonMergeFactsRoute` 真正接进 `cmd/server/router.go`，并补 `composition` / `readiness-composition`。
3. 为 §3 的 4 条 leaf 在 tasks/报告中标注 `blocked-on-upstream(AIFI-45 G1/G2-G4)`，并说明它们不影响其余 label 的验收。
4. 为 §2 的 daemon 侧（worker/recovery/client/observer/launch）决定：本期实现，或正式划出本 change 范围并写理由（不得静默留空）。
5. 报告 §4 的 5 项按现状写入 Gate 3 材料，禁止改写成「已验证」。

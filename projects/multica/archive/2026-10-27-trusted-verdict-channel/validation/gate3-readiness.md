# Gate 3 就绪报告（2026-10-27）

> 这份报告回答一个问题：**现在能不能进 Gate 3（deliver）**。
> 每条结论都指向可复跑的跑次前缀；没有任何一条靠文字自称。
> 判定工具：`multica/scripts/aifi45-verify/channel-evidence.mjs`（`verify <label> <prefix>`，exit 0 才算过）。

## 0. 结论

**可按 `channel-component` 口径提交 Gate 3 审议**（Gate 3 强制人工确认；本文件只备料，不自我判定通过）。依据：
- §2 **已无未实现的 label**；§1 的 37 个 label / 42 条证据行经 `verify` 全过，`audit` 37 个 label 全有 CP；
- `binding` 从「误记为按规格 RED」改为真实 6 leaf（ADJ-12）；
- 仍有一类缺口且**不会因本 change 继续编码而消失**：`isolation` 两侧的 Windows leaf（§4 #1）、`strict-production`（§4 #2）、ADJ-10（§4 #3）、execve 审计的 auditd 替代（§4 #4）。这些按 §7 的口径**声明为未声称**，不写成已验证。

Gate 3 材料必须同时带上 §4 与 §7；把 §4 任一项写成「已验证」即违规。

## 1. 已实现且证据当前有效（37 个 label / 42 条证据行）

早期 8 个因 ADJ-11 改源码而失效，已用当前源码重跑；`revoked-permit`、`binding`、`reader` 的 partial-tuple leaf、node `worker`、node `isolation`(linux) 为本轮新增。全部 `verify` 通过：

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
| `settlement` | 4 | `st2-20261027T142417Z` |
| `revoked-permit` | 2 | `rr-20261027T112634Z` |
| `policy-facts` | 5 | `pj-20261027T115443Z` |
| `policy-resume` | 5 | `pj-20261027T115443Z` |
| `reader` | 11 | `rg2-20261027T143755Z` |
| `binding` | 6 | `bi4-20261027T144831Z` |
| `worker` | 7 | `wo-20261027T125625Z` |
| `client` | 1 | `cm-20261027T124626Z` |
| `composition` | 2 | `cs-20261027T124942Z` |
| `d8-recovery` | 2 | `dg-20261027T125558Z` |
| `readiness-protocol` | 3 | `rq-20261027T131611Z` |
| `readiness-activation` | 4 | `s3-20261027T135434Z` |
| `readiness-retirement` | 3 | `s4-20261027T135458Z` |
| `readiness-access` | 3 | `s5-20261027T135518Z` |
| `readiness-component` | 2 | `cc-20261027T135756Z` |
| `deployment-observer` | 4 | `od-20261027T140233Z` |
| `deployment-launch` | 1 | `lu-20261027T140438Z` |
| `readiness-composition` | 1 | `rd-20261027T140645Z` |
| `readiness-fresh-work` | 1 | `g0-20261027T141710Z` |
| `foundation-fresh-work` | 4 | `fz-20261027T141650Z` |
| `policy`（node） | 23 | `n3-policy-20261027T142326Z` |
| `readiness`（node） | 2 | `n3-readiness-20261027T142327Z` |
| `recovery`（node） | 2 | `n3-recovery-20261027T142327Z` |
| `protocol`（go） | 3 | `pg2-20261027T142437Z` |
| `merge-facts`（go） | 6 | `mk-20261027T104452Z` |
| `merge-effects`（go） | 4 | `mz-20261027T105320Z` |
| `isolation`（linux） | 5 | `iso-20261027T101534Z` |
| `worker`（node） | 1 | `nw-20261027T145425Z` |
| `isolation`（node / linux） | 3 | `ni-20261027T145815Z` |
| `protocol`（node） | 2 | `np2-20261027T142510Z` |
| `store`（node） | 2 | `n-store-20261027T111459Z` |
| `merge-facts`（node） | 11 | `mf2-20261027T142500Z` |
| `merge-effects`（node） | 16 | `me-20261027T104637Z` |

变异（Go m1–m84 / Node n1–n28）全部落在 `validation/mutations/`，每条带 `.patch` 与 `.sha256`，且各自只打红对应 leaf（例外：m26/m35/m37/m39 各打红两条，m41/m48 连带同一只桶/同一入口的第二条，均为语义相关）。

## 2. 未实现（0 label）

Go 与 node 侧均无未实现 label。node `isolation` 的 2 条 Windows leaf **不是未实现就完了**：Linux 已实现出证，**Windows 驱动确实没写**（§4 #1），叠上本机无第二个受限令牌（ADJ-10），按 ADJ-13 延后到后续 change。

其余 label（含 D7 全片 `readiness-*` 13 / `deployment-observer` 4 / `deployment-launch` 1、`d8-recovery`、`foundation-fresh-work`、`binding`，以及 node `policy` 23 / `readiness` 2 / `recovery` 2）均已实现并出证，见 §1。

## 3. `binding`：已实现（ADJ-12 处置生效）

**实测**（跑次 `bi4-20261027T144831Z`）：`run:7 / pass:7 / fail:0 / skip:0`，leaf 6；checker `binding` 6/6 OK。

**历史失真（保留为教训）**：本节与 `test-report.md` 曾写「4 条按规格设计就该是 RED」，而 2026-10-27 实测 `run:0`——`TestChannelIngestBinding` 根本不存在。「测试不存在」与「测试跑红」在 `channel-evidence.mjs verify` 眼里都报 `required leaf did not pass`，外观相同、性质不同；把未实现记成合规等待，等于给自己发了一张通行证。

SC-VC-024 的「未修时按设计为 RED，不得登记完成」是**条件句**，而条件已变（依 AIFI-45 `backlog-b-disposition-20261026.md` 与 `m003-handover-20261027.md`）：

| 前置 | 现状 |
|---|---|
| G1（三写端点锁 claim 行） | **已修**（增量 44，`lockExecutionClaimRows`，三个 `55P03` 探针 RED→GREEN）；移交文档明写「不要重复做」 |
| G2 残余（签名 payload 不含 `dispatched_at`） | **决定不做**（增量 46）：固定 20 键跨仓合同，代次由服务端强制并有反例证据——故 `same_task_redispatch_challenge` 按「服务端代次校验」断言，不要求签名层能区分 |
| G4 残余（strict 强制完整 tuple / 拒绝无代次回调） | **移交 M003**（增量 46）；已落在 **reader 片**：无代次回调由 `terminal_report_without_claim`、半缺 tuple 由新增的 `partial_claim_field_rejected` 兑现（m85） |

**ADJ-12 口径**：这 4 条从 M003 入口做跨 change 集成验证（真 router + 真 permit + 真 DB），每条 leaf 前置一条 M003 的 strict selection，以此区别于 AIFI-45 自己的同行为用例；不重测 AIFI-45 函数、不把 G1 证据算作 M003 实现、PASS 不回填 AIFI-45 的 41/49。未修改 AIFI-45 记录目录，也未重做 G1/G3/G5/EVD-007。

| leaf | 断言 | 变异（只红本条） |
|---|---|---|
| `start_preflight_643_645_match` | 645 无 644 即拒；644 的 proof 必须由 643 签发；645 的 proof 必须与 644 记录一致 | m92 |
| `generation_bound_once` | 重放读回原 receipt，不生成第二张 | m88 |
| `cross_issuance_challenge` | 同 generation 的另一 task 用 A 的 challenge → 409 `EXECUTION_BINDING_NOT_ISSUED` | m87 |
| `same_task_redispatch_challenge` | 重领后旧 generation 的 proof → 409；新 generation 自签可消费（正控制） | m90 |
| `same_nonce_different_proof` | 同 generation 的第二份 proof → 409 `EXECUTION_CONSUMPTION_CONFLICT` | m89 |
| `claim_terminated_before_consume` | 消费持锁期间终态 UPDATE 得 `55P03` | m91 |

**边界**：M003 只验 643→644→645 链路一致；runner 的真正启动属 AIFI-45 的 `TC-RUN-002/003/006/010`，不在本 label 声称范围。

**变异过程的两处自捉**：m87 首版把 `task_id` 比较**反向**，结果红 5 条（正常路径也被打断）——不是精准变异，改为恒真式；同时发现 `cross_issuance_challenge` 原被 `dispatched_at` 项遮蔽（两个 task 用不同 generation，挡住的并非 task 身份），改为**同一 dispatched_at** 后才真正隔离 task 项。m90 同理。反向版跑次已删除，不入档。


## 4. 仍 UNVERIFIED 的证明（不可用「看起来对」替代）

| # | 项 | 现状 |
|---|---|---|
| 1 | `isolation` 的 Windows leaf（node 2 / go 3） | **UNVERIFIED**。Linux 侧已实现并出证（node 5 项真实内核 `EACCES`，go 5 leaf）；**Windows 侧驱动未实现**：node 测试拿到 profile 后只是 `assert.fail('…令牌驱动尚未接上')`，Go 侧 `_unsupported.go` 对全部平台原语返回 `EXECUTION_CHANNEL_ISOLATION_UNSUPPORTED`，命名管道与令牌驱动都没写。同时本机无第二个受限 Windows 令牌（ADJ-10）。node 测试仅在 `AIFI45_WINDOWS_ISOLATION_PROFILE` 存在时才声明这两条 leaf，否则打一行 `# ... is unset (UNVERIFIED, not skipped)`。按 **ADJ-13 延后到后续 change，不删冻结 leaf、不改绿** |
| 2 | `strict-production` profile | 本 change 只按 `channel-component` 验收（ADJ-4） |
| 3 | 对 agent 的隔离（ADJ-10） | agent 以 Windows 用户 GOBAO 运行，可 `wsl -u root` 免密；能改 launcher、读任一私有根。**接受为残余风险**，不声称满足 strict-production |
| 4 | execve 审计 | WSL 发行版在非初始 PID 命名空间，kernel 拒绝 audit 控制请求；改用 bpftrace `sched_process_*` tracepoint（已在 `p0-isolation-evidence.md` 记载替代关系） |
| 5 | ~~Windows 目录 fsync~~ → **已验证（收窄口径）** | 事实修正：**EPERM/EINVAL 容忍分支从未存在**（全仓无相关处理）；Windows 走 `terminal_report_queue_sync_windows.go` 的**显式 no-op**，Unix 侧 `dir.Sync()` 错误直接上抛、不吞。新增 Windows 原生测试 `TestTerminalReportDirSyncWindowsNoop` + `TestTerminalReportQueuePublishesAtomicallyOnWindows`（`go test` 在 windows/amd64 真跑，见 `winsync-*.log`；m93 把 no-op 改报错、m94 去掉冲突检查，各自 RED）。仍不声称的：崩溃时目录项丢失/复活的**持久性**（无目录 fsync 就无法证明），由「flush + 原子 rename + 重放去重」兑付 |

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

## 7. Gate 3 提交口径

### 7.1 声称的

- 37 个 label / 42 条证据行当前有效（源码 digest 与证据一致，`skip=0`）；
- `audit`：37 个 label 全有 CP；
- 变异归档于 `validation/mutations/`：**112 个 patch + sha256**，其中 **107 个可打到当前源码**（`git apply --check` 通过），
  5 个（`m12`/`m13`/`m14`/`m17`/`m79`）是目标源码后续演进后的**历史记录**、不可重放到 HEAD——如实标注，不假装可重放，清单见 `mutations/README.md`；
  本轮同时修掉归档自身两处缺陷：n1–n27 的基线选错（曾全部对 policy.mjs 取 diff）与 100 个 patch 的 `+++` 写成标签名；
  从未打红过任何 leaf 的 `n24_empty_components_ok` 已剔除；m86 与 m85 的重叠分支作为 `mutation_asymmetries` 明示；
- Gate 1/2 与 Phase 2 产物按要求入档。

### 7.2 不声称的（必须随材料声明）

| 项 | 口径 |
|---|---|
| `strict-production` | **未声称**。本 change 只按 `channel-component` 验收（ADJ-4）；`READY_STRICT` 要求 `admission_decider === 'present'`，完整 decider 属 AIFI-45 剩余工作（方案 L60/L262） |
| Windows 平台隔离 | **未声称**（ADJ-13 延后）；Linux 侧已出证 |
| 对 agent 的隔离 | **已接受残余风险**（ADJ-10）；解除需独立主机或非管理员 agent 账号 |
| execve 审计 | 用 bpftrace `sched_process_*` 替代（WSL 内 auditd 不可用）；替代关系见 `p0-isolation-evidence.md` |
| AIFI-45 41/49 | **未回填**；六条 RUN TC 的前置见 `aifi45-run-tc-rerun-prerequisites.md` |

### 7.3 提交后仍待外部动作

1. **独立 Linux 主机**（agent 账号无 sudo）—— 属**本 change**：重跑 `p0-run-20261027/scripts/run.sh` + Go/node isolation 的 Linux 原生路径 + 「agent 身份写 launcher 被拒」探针 → 成则 ADJ-10 可结、auditd 可替代 bpftrace。环境到位即继续。
2. **Windows 隔离**（ADJ-13）—— 另开 change：建受限 Windows 账号 + 实现令牌/命名管道驱动后出证。
3. **`strict-production`** —— 等 AIFI-45 的 AdmissionDecider 完成后另开 change 验收。
4. **AIFI-45 41/49** —— 由 AIFI-45 按前置清单自行决定重跑，本 change 不写其记录。

## 8. Gate 3 确认记录

| 项 | 值 |
|---|---|
| 确认人 | 用户（dialog） |
| 确认原话 | 「确认Gate 3」 |
| 确认时间 | 2026-10-27 |
| 覆盖范围 | 本 change（multica）与配对 change（tools）两条 `.stdd.yaml` 的 `phases.build` 同步置 `completed`，`current_phase` 转 `deliver` |
| 确认依据 | §7.1 声称项全部当前有效；§7.2 五项**未声称**随材料声明 |
| 记录方式 | 写入两条 `.stdd.yaml` 的 `phases.build`（字段结构与 Gate 1/2 完全一致：`confirmed_actor/confirmed_at/confirmed_by/confirmed_evidence/status`）。
**修正（2026-10-27）**：本节初稿曾写「`stdd gate approve` 解析不到 change，故手写」，**理由错误**——当时是在记录目录（`AI First Platform/projects/multica`）里运行的，而 `binding.yaml` 在**源码仓** `Downloads/AI/multica/.stdd/` 下，CLI 从 cwd 往上找因此找不到。从源码仓运行即正常：`stdd gate status` 读回 Gate 1/2/3 均 `confirmed_by=dialog`，`stdd phase status` 为 `Phase 4: DELIVER / completed`。写入内容本身与 CLI 预期一致，无需重写 |

确认同时修正：`multica/.stdd.yaml` 的 `design_adjustments.count` 原为 2（实际 13 条 ADJ-1…ADJ-13）；tools 侧为 2，正确。

**本条确认不改变以下事实**：Gate 3 通过 ≠ AIFI-45 的 41/49 回填；≠ `strict-production` 就绪；≠ Windows 隔离出证；≠ ADJ-10 解除。这四项仍按 §4/§7.3 处理。

# BUILD 测试报告（M003，截至 2026-10-27）

> 唯一证据入口是 `evidence-index.md`；本报告汇总「已验证 / 未验证」，不重复贴跑次。
> 规则：label 只有在**全部冻结必达 leaf** 都是真实非 skip PASS 时才算验证；summary 全绿不算。

## 1. 已验证（checker `verify` 判 OK）

| label | 必达 leaf | 结论 |
|---|---|---|
| `migration-up` | 14 | OK |
| `migration-reapply` | 14 | OK |
| `migration-down` | 14 | OK（另出 7 个 `fn_*` 额外 PASS，不计入必达） |
| `migration-protected` | 2 | OK |
| `store-guards` | 9 | OK（`audit` 已确认 37 个冻结 label 全部有 CP 引用） |
| `foundation-selection` | 5 | OK |
| `foundation-reservation` | 5 | OK（SC-VC-003 root+task+settlement 同 Tx / 固定 ID 逐字段等同；SC-VC-004 55P03） |
| `task-tx` | 2 | OK（commit 后通知一次；rollback 零持久零通知） |
| `protocol` | 3 | OK：三 purpose 矩阵、SC-VC-008 的 attestation→command 反例、**方案 §2 域名与 digest 公式（`SHA256(domain\|\|payload)`）**、**每 key 的 domains/scope/有效期在签发与验签两端生效**、跨语言夹具 v3、两侧任意深度重复键拒绝。Go 9/9（leaf 7），Node 3/3；跑次 `ai-proto4-*` |

合并跑次：65 pass / 0 fail / 0 skip，leaf_pass=58，`original_unchanged=true`、`owned_resources_cleaned=true`；`migration-down` 单独 22/22（leaf 21），`TestChannelTaskTx` 3/3（leaf 2）。跑次前缀见 `evidence-index.md`。

Node 侧（tools `test/execution-control-{protocol,store}.test.mjs`）：各 2/2 PASS，共 4 个必达 leaf；mutation m1/m2 各自只打红自己的 leaf。**注意**：TAP 产物共用时间戳前缀，跑次顺序不可从产物判定；结论仅依据「文件 sha256 与 green 跑次一致」这一条（由 checker 判，不靠报告文字）。

## 2. 未验证（不得计入 Gate 3 通过项）

| 项 | 状态 |
|---|---|
| `foundation-fresh-work` | 未实现（SC-VC-005 主体） |
| `merge-facts`（go） | 6 | OK：认证主体解析 workspace、回退凭据 403、冻结行 append+supersede+撤销打戳、闭集响应与摘要自洽、绑定三态、失败码分层。跑次 `mk-20261027T104452Z` |
| `merge-facts`（node） | 11 | OK：`lib/merge-facts.mjs`（认证主体解析 workspace、回退凭据拒绝、仓库集合精确相等、祖先下界、current_binding 三态、legacy 目录比对、失败码优先级、404 分层）。跑次 `mf-20261027T103357Z`，`--side node` 验过 |
| `reader` | 10 | OK：无 T 零派发、原 mapping 重放、未结算不换候选、删字段仍 strict、Unknown 不降级、legacy 不变、终态 fence 并集。跑次 `rg-20261027T121500Z` |
| `policy-facts` / `policy-resume` | 5 / 5 | OK，跑次 `pj-20261027T115443Z` |
| `worker` | 7 | OK：旧 fence 拒、tail 相同续写、T 领先一格补一格、prepared journal 重发原字节、分叉冻结、重启保 epoch/链尾（断言到库里的行）。跑次 `wn-20261027T124441Z` |
| `client` | 1 | OK：重发逐字节原样，服务端与客户端都不重编码。跑次 `cm-20261027T124626Z` |
| `composition` | 2 | OK：真 router + 真 permit 建出唯一候选且两次读取字节相同；strict 缺 T 零派发、零 root。跑次 `cs-20261027T124942Z` |
| `d8-recovery` | 2 | OK：同 lineage 重启后 command/verdict/effect 三份字节与游标都不变；regrant 开新链但旧链、累计消费、原结算都在。跑次 `dg-20261027T125558Z` |
| `readiness-protocol` | 3 | OK：request 冻结后不可重写且空 slot 拒绝、每 slot 只收一份观测、签名结果写一次。跑次 `rq-20261027T131611Z`；m59–m61 |
| `readiness-activation` | 4 | OK：同裁决只能启用一次（先证 55P03 串行，再证冲突）、签后换代即 stale、nonce 由 648 唯一约束保证、STOP_NEW 不动历史与计数。跑次 `s3-20261027T135434Z`；m62–m65 |
| `readiness-retirement` | 3 | OK：活旧 run 与未知未决都挡住 drain、revision 漂移挡住 RETIRED（正对照可收尾）。跑次 `s4-20261027T135458Z`；m66–m68 |
| `readiness-access` | 3 | OK：截止前 issued 的原请求可精确恢复、停新准入后新候选一律拒、换 origin/摘要/未 issued 都拒。跑次 `s5-20261027T135518Z`；m69–m70 |
| `readiness-component` | 2 | OK：READY_COMPONENT 只能入账（activation head/event 均不变）；strict 缺 decider 的 NOT_READY 不启用。跑次 `cc-20261027T135756Z`；m71–m72 |
| `deployment-observer` | 4 | OK：未登记键/未列实例/agent 可写来源一律拒；受保护测量为完整正例；少一个实例或重复观测 NOT_READY；换代/换 trust revision/换 nonce 即 stale。跑次 `od-20261027T140233Z`；m73–m76 |
| `deployment-launch` | 1 | OK：预检钉住 generation 与冻结安装根，同代提交拿到身份；中间换代即拒且快照未被改写。跑次 `lu-20261027T140438Z`；m77 |
| `readiness-composition` | 1 | OK：真 manifest + 真签名 + 两份观测 → READY_COMPONENT 落库；再用它启用生产 policy 必须失败且 activation head/event 为零。跑次 `rd-20261027T140645Z`；m78（先修掉了「因过期而绿」的假绿） |
| `foundation-fresh-work` | 4 | OK：新 origin 只凭 operator 钉住的源记录建立 strict selection；同 origin 换 CR 被拒且只有一条 selection；源记录缺失只能 UNKNOWN、非 NEW 或带未决引用不建 selection；新 proof 只追加 revision 且历史字节与摘要不变。跑次 `fz-20261027T141650Z`；m80–m84 |
| `readiness-fresh-work` | 1 | OK：同 origin 换 lineage 被拒且原归属原样交回；同 lineage 重放不新增行；历史覆盖未知不建立新 origin。跑次 `fx-20261027T140828Z`；m79 |
| `policy`（node） | 23 | OK：未验签 fact 拒、CAS 只收一份、合同与 store 不一致拒、敏感动作只认原 operation；merge 范围 19 条（只认已批准 sha、覆盖发布集合、rename 双端、候选树 symlink、空集合/缺 release-subject/采集失败一律 UNVERIFIABLE、Unknown 不降 legacy、legacy 不核对、删字段仍 strict、恢复用冻结输入、中途撤销保 journal、越界零写入且不推进状态、不受 grants 目录影响、head 撤销/前移即拒、finalize 写集逐项授权、KB 审批后写入纳入核对）。跑次 `n3-policy-20261027T142326Z`；n1–n23 |
| `readiness`（node） | 2 | OK：空/缺 components、重复观测、未批 NA、runtime/安装漂移、恢复未知均 NOT_READY；action×purpose 矩阵外一律拒，verify-channel 只出 READY_COMPONENT。跑次 `n3-readiness-20261027T142327Z`；n24–n25 |
| `recovery`（node） | 2 | OK：五个观察各对应唯一动作、缺 store/checkpoint 冻结；restart 只动 owner fence。跑次 `n3-recovery-20261027T142327Z`；n26–n27 |
| `binding`（4 条按规格 RED） | 按规格不得登记完成 |
| `isolation`（linux） | 5 | OK：root + `AIFI45_ISOLATION_PROFILE=wsl2-aifi45-v1`（uid 995/gid 994）真跑；pidfd 钉身份并检测死进程、SO_PEERCRED 取真身份、`ReadMsgUnix` 拒 SCM_RIGHTS。m12/m13/m14 各只红一条。跑次 `iso-20261027T101534Z` |
| `isolation`（windows） | 3 | **UNVERIFIED**：无受限 Windows 身份，`_unsupported.go` 对所有原语返回 `EXECUTION_CHANNEL_ISOLATION_UNSUPPORTED`，缺 profile 直接 `t.Fatalf` |
| tools SC-TR-003 并发三请求、rename 前后 kill | 未测（报告未声称） |
| tools SC-TR-001 Go 侧 `cross_language_vectors` | 不存在 |
| P0 隔离证明（两真实受限身份 + 批准 profile） | UNVERIFIED（Windows 无第二受限身份；WSL podman 无批准 profile） |
| `strict-production` profile | UNVERIFIED（待部署授权） |
| Windows 目录 fsync（EPERM/EINVAL 容忍分支） | 待在 Gate 3 披露 |

## 3. mutation 证据（可复现条件）

四个变异都只改 `648_cr_execution_control.up.sql` 的一行，跑 `^TestChannelStoreGuards$`，恢复后校验 sha 与基线 `89f0c3f0…` 一致。

| 变异 | 目标文件 | 替换（原文 → 变异） | 失败 leaf | patch sha256（unified diff，去缩进行） |
|---|---|---|---|---|
| m1 | 648 up | `RAISE EXCEPTION '% is append-only', TG_TABLE_NAME;` → `RETURN OLD;` | `selection_row_immutable`、`reservation_row_immutable` | `96707b44a0daf66f…` |
| m2 | 648 up | `RAISE EXCEPTION 'illegal control command transition …'` → `RAISE NOTICE …` | `command_transition_rejects_skips` | `dd410bdf75bb0842…` |
| m3 | 648 up | `RAISE EXCEPTION 'readiness verdict is write-once';` → `RAISE NOTICE …` | `readiness_verdict_write_once` | `8a7af21b085d289c…` |
| m4 | 648 up | `RAISE EXCEPTION 'deployment head scope is immutable';` → `RAISE NOTICE …` | `deployment_head_scope_immutable` | `5286b3f675d4d181…` |
| m5 | `execution_channel_admission.go` | 固定 ID 的逐字段比较 → `if false` | `fixed_id_conflict_and_rollback` | 见跑次 `x-m5_task_identity-*` |
| m6 | `execution_dispatch_root.go` | 采纳读的 `FOR UPDATE` 删除 | `root_adoption_terminal_race`（断言 55P03 失败） | 见跑次 `x-m6_no_row_lock-*` |
| m7 | `execution_control_protocol.go` | 验签 preimage 去掉 `schema\0` 前缀 | `purpose_domain_scope`、`cross_language_vectors/{verdict,command}` | 见跑次 `ad-m7_signature_domain-*` |
| m8 | `execution_control_protocol.go` | 允许重复 JSON 键 | `exact_keys` | 见跑次 `ad-m8_duplicate_keys-*` |

**缺口**：m1–m4 的 patch sha256 是按「去掉缩进的行替换 + 手写 unified diff」重建的，不是当时落盘的原始 patch；m5/m6 未重建 patch hash。原始落盘只有失败 leaf、argv、跑次前后源文件 sha256。要彻底满足 long-range-auth §C1，需在下一次变异时由脚本 `diff -u` 落盘。

**m5/m6 的追加证据**：两次变异后 checker 对 green 前缀（`z-combined-*`）均报 `changed since the run`（rc=1），恢复后 sha 与基线一致（`restored=true`）。

## 4. 回滚证明（机器判据，不靠文字）

green 跑次写入 `<prefix>.source.json`（10 个源文件 sha256）。一次真实变异后同一前缀判定：

```text
FAIL source server/migrations/648_cr_execution_control.up.sql changed since the run (89f0c3f061c7 -> 43a5651c3e13)
```

恢复后同一前缀回到 `OK store-guards: 9 required leaves passed`，且 up.sql sha 与基线一致。

## 5. 对 AIFI-45 六条 RUN TC 的可重跑性

本报告**不构成回填**。`TC-RUN-001/002/003/006/007/010` 可据此重跑，前置为：

1. 两个源码仓处于本 change 的分支（源码改动**未提交**，重跑前先确认工作树内容与 `<prefix>.source.json` 一致）；
2. 每轮独占 nonce 库（`scripts/aifi45-db/run.mjs`），带 `-migration=` 643–647 up + 648 up（保留库 schema-only 克隆不含 643–647，且已含 642 的列）；
3. 四条 648 专例各自的迁移前置不同：down 需 648 up + down；protected 自身做 down/up，不能与 after-up 同库混跑；
4. `foundation-reservation` 在 SC-VC-003/004 落地前必然 FAIL，重跑时按「未验证」记录，不得按 label 全绿上报。

## P0 隔离前提与残余风险（2026-10-27）

- 环境前提：经 launcher 的 24 条探针全 PASS，bpftrace execve trace clean 窗口 0 旁路、control 窗口能抓到旁路；证据 `validation/p0-isolation-evidence.md`、原始产物 `validation/p0-run-20261027/`。
- **残余风险 ADJ-10**：agent（Windows 用户 GOBAO）可 `wsl -u root` 免密，对 agent 的隔离不成立。C 路径片只按 `channel-component` 组件级验收，**不得声称 `strict-production`**。
- 仍 UNVERIFIED：`isolation` 的 Windows 3 leaf（`win32` 分支）、容器路径。Linux 5 leaf 已实现并真跑通过。

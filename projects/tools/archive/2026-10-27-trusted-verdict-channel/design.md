# 可信 T committed verdict channel — tools 技术设计（T runtime 与 merge 门禁）

> 阶段：Gate 2 已确认，BUILD 进行中（长程模式：协议/store 两个库已落并真跑）。证据入口在 multica 侧 `validation/evidence-index.md`；本文件是设计基线。
> Gate 1 原文「确认这份 Gate 1（multica + tools 两条）」已由原生 CLI 登记。
> 设计输入：前身 change `validation/trusted-verdict-channel-implementation-plan-20261026.md`（v0.6.5，sha256 `55ee0d01…b4d8`），
> 六轮三路复核 R2/R3 全 PASS 属**静态**结论，不是实现验证。
> 跨仓配套：[multica 设计](../../../multica/changes/2026-10-27-trusted-verdict-channel/design.md)。

## Context

- tools 是 merge 的唯一发布方（`skills/shared/crctl/scripts/lib/workspace-transactions.mjs::mergeCr`，本仓 1986 行），
  也是 T 规则、repair/resume、sensitive action 与 component readiness 的所在处。
- 已核实（2026-10-27，修订后）：`lib/change-scope.mjs` 的 `evaluateChangeScope` 是纯判定器，缺失/非数组 `changes`
  **已返回** `AUTH_SCOPE_INPUT_INVALID`、`allowed:false`（AIFI-45 已修，35–39 行），仅显式 `[]` 放行；内部 `gitFields`
  已用 `-z` NUL 分隔、rename 已双侧记录；`collectChangedPaths` 仍含工作区/untracked 与 `origin/trunk` 回退；`crctl.mjs` 准入在
  1968 行仍返回 `EXECUTION_CONSUMPTION_REQUIRED`；`scripts/test/` 现有 46 条 merge 测试 leaf（19 范围 + 11 merge-facts + 16 merge-effects；与本 change 的「测试文件数」不是同一口径）（含 `merge-tx.test.mjs`、
  `merge-release-recovery.test.mjs`、`change-scope.test.mjs`）。
- 依赖前提（AIFI-45 已交付）：grant/verifier、`execution-authorization.mjs`、`execution-binding.mjs`、
  `execution-transaction.mjs`、643–647 的 daemon 侧安装与 binding；本 change 不重写这些。

## Decisions

### 1. merge 范围核对：新写 `collectCommittedPaths`，不复用工作区采集

- 只核对 `trunk...HEAD`（merge 实际发布的提交区间），**不是** `trunk...<release subject sha>`；后者会漏掉
  release subject 之后含 `approval.yml`、`cr.md` 等写入——正是要守的面。
- 改动集合的权威来源是 **M 侧持久 code 批准记录**；`approval.yml#code.release-subjects` 只作投影，逐字段不等即
  `AUTH_SCOPE_UNVERIFIABLE`。
- 新写 `collectCommittedPaths(base, sha)`：committed 区间 + git tree mode `120000` 逃逸判定。路径编码与 rename 双侧
  **复用**同文件既有 `gitFields`（`-z`）与 rename 解析，不另写一套；**不复用** `collectChangedPaths` 本身（语义不同，含工作区与回退）。
- `evaluateChangeScope` 不改：它对缺失/非数组输入已 fail-closed，对显式 `[]` 放行是判定器的正确行为；空集合四证明（仓集合完整、
  每仓取到 SHA、采集成功、路径非空或显式零改动）缺一即 `AUTH_SCOPE_UNVERIFIABLE`。
- 与既有 `verifyReleaseSubjects` 的顺序不变：先过既有校验（`allowLocalDrift: codeTrust.ok`），再做范围核对；
  越界只拒，**不走** `release-drift` 回退（回退会写状态）。
- 失败码闭集与优先级以方案 R2.4 为唯一权威：`UNAVAILABLE > REVOKED > HEAD_MOVED > VIOLATION > UNVERIFIABLE`；
  grant 派生字段每次从端点重读，journal 只存摘要供审计。

### 2. `merge-facts` 客户端（只读）

- 端点由 multica 提供：`GET /api/daemon/execution-control/merge-facts/{crID}`；workspace 由服务端从认证主体解析，
  CLI 不传 `--workspace`/`--grant`/revision。
- 客户端校验：`len(repos)==expected_repo_count`、repo_id 唯一且集合等于 grant `allowed_repositories`、`repos_digest` 自洽；
  `current_binding` 三态分别映射 mismatch→VIOLATION、unknown→UNVERIFIABLE；`head_revoked` → REVOKED。
- 批准下界只在 CLI 判：`approved_source_sha` 必须是候选 HEAD 的祖先且落在 `trunk...<candidate HEAD>` 内
  （端点看不到候选 HEAD）。
- legacy provenance 只与可信目录记录比对，不接受响应自报。

### 3. `merge-effects` 客户端与 journal 三态

- `op=reserve` 在 push 前提交；`op=report` 在 push 返回后提交。Tx 内不调用网络。
- journal 按 effect 持久三态：`intent`（reserve 已提交、push 未发）/ `unknown`（**发 push 之前先写**）/ `confirmed`。
- 恢复判定（R3.2 矩阵）：服务端终态优先于本地 journal；远端分类用祖先关系
  （`git merge-base --is-ancestor <expected> <remote>` 含相等 = 含 expected；等于 `prev_sha` 且不含 expected = == prev；
  其余 = 其他）。`unknown`/`uncertain` 下**禁止**发起任何新 publish；`confirmed` 而服务端无终态属事实不一致 → uncertain。
- `attempt` 单调：同 attempt 原字节重放→原结果；已 settled 的新 attempt→原 mapping；无未终结前 attempt→新 command；
  前 attempt 未终结→409 CONFLICT（CLI 记 `halted.reason=uncertain`）。
- `input_digest = sha256(trunk ‖ 每仓 base_sha ‖ 每仓 candidate HEAD ‖ selection_kind ‖ 按 repo_id 排序的
  (approved_source_sha, approved_revision) ‖ authorization_head_id ‖ grant_digest)`，预检写入 journal、reserve 时服务端比对。
- 中止：CR 保持 `code-approved`，journal 记 `halted:{at_effect, reason∈revoked|head_moved|base_drift|input_mismatch|
  publish_failed|uncertain}`；`INVALID/UNTRUSTED/NOT_FOUND/UNAVAILABLE` **不写 halted**；不新增 abort 命令、不改状态机。

### 4. T 侧协议与受保护 store

- 独立 key-purpose 与 `execution-control-trust-manifest/v1`（绝对路径 + 原始 SHA256 pin、exact keys、禁 agent enrollment）；
  `VerifyEnvelope(raw,expectedPurpose,domain,scope)` 只接受三元组完全匹配的原字节。
- `ApplyOnce(command,fn)`：journal → 原子 bundle → 完整冻结 envelope；fsync 失败不得留 frame；重投返回原 bytes，
  不重算 `replayed`。
- 冻结帧链：`sequence` 连续、`previous_verdict_digest` 指向上一帧；断链/跳号/占位签名一律拒（只保证账本不可篡改，
  **不等于** RPR-007/008 的追加授权）。
- 复用 `toolsRuntimeDigest` 等既有摘要定义；marker digest 只用于原身份诊断，不混作全量 runtime digest。

### 5. worker、fence 与恢复

- `BeginOwnerTx` 持久递增 fence；`Worker.Apply(command)` 只在持有当前 fence 时写入；旧 fence 不执行新操作。
- checkpoint 字段：`schema,key_id,scope,lineage_id,store_id,epoch,accepted_fence,last_seq,last_digest,
  after_state_digest,journal_state,open_request_id,open_command_digest,result_digest`。
- 恢复沿用 multica §4 恢复表的同一分组；本仓实现 T 侧（journal/store/checkpoint）判定，不猜「未消费」、不清 slot、
  不建空 store。普通 restart 不变 epoch/sequence；key rotation 只影响新 verdict。

### 6. facts、repair/resume 与 sensitive action

- 只消费已验签 facts：`repair_admit` 的 `fact_refs` 必须指向已验签 grant，额度不得来自解码 payload；
  `repair-governance.mjs` 不再从解码内容取额度。
- 追加域只扩额度、不扩仓库集合；CAS 只接受一份；同 operation 原字节重放返回原 receipt、不再消费。
- `cr.md` 合同字段只是 store 的投影；与 store 不一致即拒（字段缺失不等于 legacy）。

### 7. D7 readiness 求值器（T 侧）

- 新增 `component-readiness.mjs::evaluateStrictComponentReadiness`（fail-closed）：拒绝空/缺 components、重复 declared/observed、
  unknown/NA 绕过、仅 marker 一致但 runtime/安装变化、恢复能力未知。
- 新增 request/verdict exact-key schema 与 `Worker.EvaluateReadiness`：冻结 request slots → 各 observer 签发 →
  最终 verdict；同 request 丢响应/重启只返回原 bytes；无业务 lineage 也可求值。
- `verify-channel` 只出 `READY_COMPONENT`，不得调用生产 activation；`not-applicable` 只允许 profile 明确批准项。

## 切片与依赖

| 片 | 内容 | 依赖 |
|---|---|---|
| T-S2 | key-purpose、wire、跨语言向量（Node 侧） | multica M-S2 合同 |
| T-S3 | store：journal/原子 bundle/冻结帧链 | T-S2 |
| T-S4 | worker/fence/checkpoint/恢复 | T-S3 |
| T-S5a | facts 接线、repair 追加、sensitive 规则 | T-S3/T-S4 |
| T-S5b | merge 范围核对（19 leaf） | multica M-R2 端点 |
| T-R2 | `merge-facts` 客户端（11 leaf） | T-S5b、M-R2 |
| T-R3 | `merge-effects` 客户端与 journal 三态（16 leaf） | T-R2 |
| T-S8 | readiness 求值器（T 侧） | T-S2 |

P0（隔离证明，SC-TR-013）在 tools 侧对应 `test/execution-control-isolation.test.mjs`，Linux/Windows 分别出证，未获环境授权前记 UNVERIFIED。
**P0 门控（Gate 2 前用户采纳）**：P0 只阻塞依赖方案 C 的片（T-S3/T-S4 worker 与恢复、T-S8 的 worker 求值路径）；
两条路径都适用的 T-S2 协议纯函数、T-S5a 规则接线、T-S5b/T-R2/T-R3 merge 三族可先行。P0 失败转 B 须另行提审，禁止 silent fallback。

## 残余风险与非目标

- 端点只保证事实可信，不保证执行强制；持 push 权限者可绕过 CLI。仓库侧闸门不在本 change。
- 不重写本地规则本身（B16）、不修采集器通用缺陷（路径编码/rename/symlink）与锁——那些归 AIFI-45 就地修，
  本 change 只定「取哪些 SHA/树」的契约。
- 不做 legacy 迁移（D8=A）、不新增 CR 状态机状态、不部署。
- 通道组件通过不自动回填 AIFI-45 的 41/49。

## 修订记录

| 日期 | 修订 | 结论是否受影响 |
|---|---|---|
| 2026-10-27 | 初稿（Gate 2 草案） | — |
| 2026-10-27 | 更正事实：`evaluateChangeScope` 对缺失/非数组已 fail-closed（原文照抄方案的旧描述）；`-z` 与 rename 双侧已由 AIFI-45 修好，`collectCommittedPaths` 改为复用 `gitFields`；19 条 merge 范围 leaf 按方案固定在 `test/execution-control-policy.test.mjs`（原写 `merge-scope.test.mjs`）；补 P0 为 SC-TR-013 并按 C 路径门控；leaf 名单改由 multica change 的 `channel-test-expectations.json` 在 SPEC 冻结 | 否：判定器不改、四证明归采集层的结论不变；范围与必达 leaf 下限不变 |

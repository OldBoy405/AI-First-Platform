# 可信 T committed verdict channel — tools BUILD 任务清单

> STDD Phase 2 / Gate 2 草案。**全部任务未开始**；本文件是计划，不是执行记录。

## 1. merge 范围核对（T-S5b，19 leaf）

- [ ] 1.1 新增 `lib/merge-scope.mjs`：`collectCommittedPaths(base, sha)`（committed 区间、rename 源/目标、tree mode `120000` symlink、无损路径分隔与引号解转义）。
- [ ] 1.2 采集完整性四证明（仓集合完整、每仓取到 SHA、采集成功、路径非空或显式零改动），失败即 `AUTH_SCOPE_UNVERIFIABLE`。
- [ ] 1.3 在 `mergeCr` 既有链插入：先 `verifyReleaseSubjects`，再范围核对；越界只拒，不走 `release-drift` 回退。
- [ ] 1.4 改动集合只读 M 持久批准记录；`approval.yml` 只作投影，逐字段不等即拒。
- [ ] 1.5 finalize 三生成路径（`cr.md`/`merge-commits.yml`/`merge-verification.md`）逐项进 `allowed_paths`，无暗设豁免。
- [ ] 1.6 selection 判定：Unknown 即拒、legacy 只由可信目录证明、Strict 删投影仍 strict。
- [ ] 1.7 `test/merge-scope.test.mjs`（proposed）：承载 19 条 leaf 与对应 mutation。

## 2. merge-facts 客户端（T-R2，11 leaf）

- [ ] 2.1 新增 `lib/merge-facts-client.mjs`：只传 crID，workspace 由服务端解析；拒绝任何版本参数。
- [ ] 2.2 响应校验：闭集字段、`len(repos)==expected_repo_count`、repo_id 唯一、集合等于 grant、`repos_digest` 自洽。
- [ ] 2.3 `current_binding` 三态映射（mismatch→VIOLATION、unknown→UNVERIFIABLE）与 `head_revoked`→REVOKED。
- [ ] 2.4 本地下界：`approved_source_sha` 须为候选 HEAD 祖先且落在 `trunk...<candidate HEAD>`。
- [ ] 2.5 外层码优先级 `UNAVAILABLE>REVOKED>HEAD_MOVED>VIOLATION>UNVERIFIABLE`；grant 派生字段每次重读。
- [ ] 2.6 `test/merge-facts.test.mjs`：11 条 leaf 与 mutation。

## 3. merge-effects 客户端（T-R3，16 leaf）

- [ ] 3.1 新增 `lib/merge-effects-client.mjs`：`op=reserve|report`、`attempt` 单调、四支结果处理。
- [ ] 3.2 journal 三态（`intent`/`unknown`/`confirmed`），**发 push 前先写 `unknown`**。
- [ ] 3.3 恢复判定：服务端终态优先于 journal；远端用 `git merge-base --is-ancestor` 分类；`unknown`/`uncertain` 禁止新 publish。
- [ ] 3.4 `input_digest` 计算公式与预检写入；reserve 时由服务端比对，不同即拒。
- [ ] 3.5 `halted.reason` 闭集（revoked/head_moved/base_drift/input_mismatch/publish_failed/uncertain），`INVALID/UNTRUSTED/NOT_FOUND/UNAVAILABLE` 不写 halted。
- [ ] 3.6 `test/merge-effects.test.mjs`：16 条 leaf、`55P03` 探针与两条不对称 mutation。

## 4. T runtime：协议与 store（T-S2/T-S3）

- [ ] 4.1 `lib/execution-control-protocol.mjs`：`VerifyEnvelope`、三元组严格匹配、与 Go 侧向量互验。
- [ ] 4.2 `execution-control-trust-manifest/v1` 加载：绝对路径 + 原始 SHA256 pin、exact keys、禁 agent enrollment。
- [ ] 4.3 `lib/execution-control-store.mjs`：`ApplyOnce`、journal→原子 bundle→冻结 envelope、fsync 失败无 frame。
- [ ] 4.4 冻结帧链：sequence 连续、`previous_verdict_digest` 指向上一帧、拒绝占位签名。
- [ ] 4.5 `test/execution-control-protocol.test.mjs`、`test/execution-control-store.test.mjs`。

## 5. T runtime：worker、fence 与恢复（T-S4）

- [ ] 5.1 `lib/execution-control-worker.mjs`：`BeginOwnerTx` 持久 fence、`Worker.Apply` 只认当前 fence。
- [ ] 5.2 checkpoint 全字段与 `ReconcileOwnerTx` 恢复表（T 侧四类动作 + freeze）。
- [ ] 5.3 key rotation：新 verdict 用新 key，历史用旧 key 验证。
- [ ] 5.4 `test/execution-control-worker.test.mjs`、`test/execution-control-recovery.test.mjs`。

## 6. facts 与规则接线（T-S5a）

- [ ] 6.1 `repair-governance.mjs`：`fact_refs` 必须指向已验签 grant，额度不来自解码 payload。
- [ ] 6.2 追加域只扩额度、CAS 只接受一份、重放返回原结果。
- [ ] 6.3 `cr.md` 合同字段只作投影，与 store 不一致即拒。
- [ ] 6.4 `execution-sensitive-action.mjs`：exact target/environment、新 operation 耗尽、同 operation 原 receipt。
- [ ] 6.5 `test/execution-control-policy.test.mjs`：4 条 leaf（含现有文件的 3 条固定 title）。

## 7. readiness 求值器（T-S8）

- [ ] 7.1 加固 `component-readiness.mjs::evaluateComponentReadiness`：空/缺/重复/unknown/NA 绕过全拒。
- [ ] 7.2 新增 `lib/execution-control-readiness.mjs`：request/verdict exact-key schema、slot CAS、原字节不可改。
- [ ] 7.3 `verify-channel` 只出 `READY_COMPONENT`；`not-applicable` 只允许 profile 明确批准项。
- [ ] 7.4 `test/execution-control-readiness.test.mjs`。

## 8. 证据与收尾

- [ ] 8.1 与 multica 共同冻结 `validation/channel-test-expectations.json`（46 条 merge leaf + T runtime leaf）。
- [ ] 8.2 每条 mutation 保存 patch hash、基线与恢复后 source hash、argv、失败 leaf 与条件断言。
- [ ] 8.3 既有 `test/` 46 个文件的套件门禁在改动后仍 pass（失败码与退出码不变）。
- [ ] 8.4 deliver 产物写明 AIFI-45 6 条 RUN 类 TC 的重跑前置，不写成「已回填」。

## 9. 明确不做

- [ ] 9.1 不改 AIFI-45 两个 change 目录、不动 `change-requests/`、不改 tools `dir-graph.yaml` 状态机。
- [ ] 9.2 不修采集器通用缺陷与锁（归 AIFI-45）；不重写本地规则本身（B16）。
- [ ] 9.3 不新增 abort 命令、CR 状态、第三个决策服务；不部署、不做真实 CR。

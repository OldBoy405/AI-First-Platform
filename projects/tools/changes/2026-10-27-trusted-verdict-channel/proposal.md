# 可信 T committed verdict channel：T runtime 与 merge 门禁（tools 侧）

<!-- source_hash: 7a5b65730463a7b4 -->
<!-- generated_at: 2026-10-27T15:47:27.435433 -->
<!-- canonical: canonical/proposals/2026-10-27-trusted-verdict-channel.yaml -->

## Why

tools 是 merge 的唯一发布方（`lib/workspace-transactions.mjs::mergeCr`），也是 T 验证规则的
所在处（本地规则、repair/resume、sensitive action、component readiness）。但当前：
merge 的「批准后改动集合」取自 agent 可写的 `approval.yml#code.release-subjects`，
`evaluateChangeScope` 只是判定器（缺失/非数组已 fail-closed，显式空集合放行），不证明采集完整；`collectChangedPaths`
带工作区/untracked 与 `origin/trunk` 回退，语义与「已提交发布区间」不同；
repair CLI 只解码 payload，`crctl.mjs` 准入仍返回 `EXECUTION_CONSUMPTION_REQUIRED`；
verdict 无受保护 store、无 owner fence、无恢复表，`durable-tx.mjs` 只是 best-effort。


## What Changes

- merge 门禁：新写 `collectCommittedPaths(base, sha)`（committed 区间 + git tree mode 120000 逃逸判定 + rename 源/目标 + 无损路径分隔），`merge-facts` 客户端按认证主体解析结果校验 仓库集合/摘要/current_binding/legacy 证明，并按固定优先级映射 `UNAVAILABLE>REVOKED>HEAD_MOVED>VIOLATION>UNVERIFIABLE`；不改动 `evaluateChangeScope` 的判定语义。
- `merge-effects` 客户端：按 effect 的 `reserve`/`report` 兑现撤销线性化，`attempt` 单调， journal 三态（`intent`/`unknown`/`confirmed`）在发出 push 之前先写 `unknown`， 恢复按 R3.2 矩阵只读核实远端祖先关系，`halted.reason` 闭集，不新增 CR 状态与 abort 命令。
- T 侧协议与受保护 store：独立 key-purpose 与 `execution-control-trust-manifest/v1` （exact keys、禁止 agent enrollment）、`VerifyEnvelope(raw,expectedPurpose,domain,scope)`、 `ApplyOnce(command,fn)` 的 journal + 原子 bundle + 完整冻结 envelope，冻结帧链 （sequence 连续、prev digest 指向上一帧）。
- 固定 worker、fence 与恢复：`BeginOwnerTx`/`ReconcileOwnerTx`/`Worker.Apply`、 checkpoint 字段与恢复表的 T 侧实现，普通 restart 保持 epoch/seq 并重发原 bytes， 旧 fence/缺 store/落后/分叉冻结。
- facts 与规则接线：`repair-governance.mjs`、`execution-sensitive-action.mjs` 与 evidence commit wrapper 只消费已验签 facts（`fact_refs` 指向已验签 grant、额度不来自解码 payload）， 追加域只扩额度不扩仓库集合，`cr.md` 合同字段与 store 不一致即拒。
- D7 readiness 求值器：加固 `component-readiness.mjs::evaluateComponentReadiness`， 拒绝空/缺 components、重复 observed、unknown/NA 绕过与仅 marker 一致；新增 `execution-control-readiness.mjs` 的 request/verdict exact-key schema 与 `Worker.EvaluateReadiness`，`verify-channel` 只出 `READY_COMPONENT`。

### New Capabilities

- **trusted-merge-gate**：merge 前的可信事实核对与撤销线性化：committed 区间写集、merge-facts 客户端与失败码优先级、 merge-effects reserve/report、journal 三态与恢复判定。
- **verdict-channel-runtime**：T 侧裁决运行时：key-purpose 与 wire 验证、受保护 store 与原字节重放、固定 worker 与 fence、 typed facts 接线、以及部署就绪求值器（只出 READY_COMPONENT）。

## Success Criteria

- [ ] 协议：purpose/domain/scope 任一错用即拒；Go↔Node 原字节双向向量通过；attestation key 签 resume、human key 签 command、重复键与 union 双分支均拒。
- [ ] Store：同 admit/assessment/resume 请求并发与 rename 前后 kill，恢复后只一次业务变化且 bytes 相同；fsync 失败无 frame；断链/跳号/占位签名一律拒。
- [ ] Worker/恢复：普通 restart 保持 epoch/seq 并重发原 bytes；旧 fence、缺 store、落后/分叉冻结；合法一致 checkpoint 可继续。
- [ ] Facts/规则：未验签 payload、自报 reviewer、专项改 target、账本来源不可核实均拒；追加 CAS 只接受一份；`cr.md` 合同字段与 store 不一致即拒。
- [ ] merge 范围（S5 的 19 条 leaf）：rename 源/目标、symlink 取自发布候选树、空集合不放行、Unknown 即拒、恢复沿用原冻结输入、部分发布后撤销、legacy 不核对、不受 grants 目录旧文件影响、head 撤销/前移即拒、越界零写入、只看已批准 source sha、覆盖发布集合、删合同字段仍 strict、release-subject 缺失/无法核实即拒、越界不推进状态、finalize 写集逐项授权、KB 审批后写入纳入核对——全绿且 mutation 对应。
- [ ] merge-facts：R2.5 的 11 条必达 leaf 全绿，含认证主体解析、拒绝 PAT/JWT/task-token、冻结行唯一、批准下界为候选祖先、仓库集合精确相等、current_binding 三态、legacy 证明、失败码优先级、不可用、撤销、head 前移。
- [ ] merge-effects：R3.5 的 16 条必达 leaf 全绿，含共享锁 55P03 探针、撤销/reserve 双向排序、journal 三态与远端分类、attempt 四支、base 漂移、finalize 也 reserve、码序、正常前进不判改写。
- [ ] D7 求值器：空/缺 components、重复 observed、unknown/NA 绕过、仅 marker 一致均 NOT_READY；合法非空 profile 正例；`verify-channel` 只出 READY_COMPONENT。
- [ ] 既有回归：crctl 既有 46 个测试文件的套件门禁在改动后仍 pass；失败码闭集与退出码不变（非零、CR 状态保持 `code-approved`）。
- [ ] 残余风险写实：交付后文档与回复均不得声称「merge 已强制」或「strict 生产已启用」。

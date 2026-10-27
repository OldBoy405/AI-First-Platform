# Spec: trusted-merge-gate

> Change: 2026-10-27-trusted-verdict-channel | Auto-generated Human View

## Requirements

### Requirement: merge 范围核对以已提交发布区间与 M 持久批准记录为准，越界零发布且不推进状态。

#### Scenario: SC-MG-001

- **GIVEN** 已批准 CR 的 source 区间包含 release subject 之后的提交，且 `approval.yml` 的 release subject 与 M 持久记录相等或不等。
- **WHEN** 执行 merge 前的范围核对。
- **THEN** SHALL 以 `trunk...HEAD` 为核对区间并覆盖 finalize 生成写集与 KB 审批后写入，`approval.yml` 只作投影、逐字段不等即 `AUTH_SCOPE_UNVERIFIABLE`。
- **AND** 越界路径判 `AUTH_SCOPE_VIOLATION`，不得把区间收窄为 `trunk...<release subject sha>`。

#### Scenario: SC-MG-002

- **GIVEN** 发布区间内含 rename（源与目标都在授权外/一内一外）、以及 symlink 条目。
- **WHEN** 采集 committed 路径与逃逸判定。
- **THEN** SHALL 同时检查 rename 源与目标，并从选定提交的 tree/blob mode `120000` 解析 symlink 目标。
- **AND** 不读工作树 realpath、不读 index mode；无法判定记 problem 并按 UNVERIFIABLE 拒绝。

#### Scenario: SC-MG-003

- **GIVEN** 仓集合缺一项、某仓取不到目标 SHA、采集失败、路径集合为空且无零改动证明；以及 release subject 缺失。
- **WHEN** 汇总范围核对输入。
- **THEN** SHALL 按四证明缺一即 `AUTH_SCOPE_UNVERIFIABLE`，不得把缺失或失败当空集合放行。
- **AND** `release-subject 缺失` 与 `无法核实` 共用同一条「缺省当空集合放行」mutation。

#### Scenario: SC-MG-004

- **GIVEN** selection 为 Unknown 或目录缺行/读失败；CR 由可信历史目录证明为 legacy；Strict 下 `cr.md` 合同字段被删。
- **WHEN** 判定是否核对范围、是否要求 grant。
- **THEN** SHALL 对 Unknown 直接拒绝、对已证明 legacy 保持原行为、对 Strict 删字段仍按 strict 判定。
- **AND** 缺行或读失败不降 legacy；legacy 只由可信目录证明。

#### Scenario: SC-MG-005

- **GIVEN** 一次 merge 因故中止后以既有恢复路径重入，期间 `approval.yml` 或合同字段已变化。
- **WHEN** 恢复原 merge 事务。
- **THEN** SHALL 沿用原冻结输入，输入已变即拒绝，不重读当前 YAML 追认新内容。

#### Scenario: SC-MG-006

- **GIVEN** 逐仓 publish 过程中发生撤销；以及首次预检即越界（分别在 publish 之后、journal 之后 prepare 之前注入核对）。
- **WHEN** 继续发布或尝试重入。
- **THEN** SHALL 停止后续 publish、保留原 journal/receipt 并转人工，越界路径注入的 publish 端口调用数为零。
- **AND** 不得自动新建事务或换源解除阻断；零写入断言观测 journal/锁/outbox/Git 写命令。

#### Scenario: SC-MG-007

- **GIVEN** `grants/` 目录放入一份更宽的旧 grant；授权 head 在首次读取后被撤销或前移。
- **WHEN** 解析当前授权并做效力检查。
- **THEN** SHALL 不从目录扫描「最新」grant，且在预检后再读时按当前 head 判 `EXECUTION_AUTHORIZATION_REVOKED` 或 `EXECUTION_AUTHORIZATION_HEAD_MOVED`。
- **AND** 不按批准时快照比对；撤销与 head 前移是两种事实，不混用。

#### Scenario: SC-MG-008

- **GIVEN** 越界后检查 CR 状态；finalize 需写 `cr.md`/`merge-commits.yml`/`merge-verification.md`；获批后 KB 又发生写入。
- **WHEN** 结束本次核对或执行 finalize。
- **THEN** SHALL 保持 CR 状态 `code-approved`（不走 release-drift 回退），并要求 finalize 三个生成路径逐项出现在 `allowed_paths`。
- **AND** 任一生成路径漏列即 `AUTH_SCOPE_PATH_NOT_ALLOWED`，无暗设豁免。
- **AND** KB 审批后写入必须在核对区间内被检查。

### Requirement: merge-facts 客户端只按认证主体解析事实，失败码与优先级固定。

#### Scenario: SC-MG-009

- **GIVEN** 合法 MDT 凭据配他人 crID；以及携带 PAT/JWT/task-token 的请求。
- **WHEN** 调用 merge-facts 客户端并映射外层码。
- **THEN** SHALL 期待 404 `MERGE_FACTS_NOT_FOUND` 并映射 `AUTH_SCOPE_UNVERIFIABLE`，回退凭据得 403 并映射 `EXECUTION_AUTHORIZATION_UNAVAILABLE`。
- **AND** 不向端点传 workspace/grant/revision；认证先于资源查找。

#### Scenario: SC-MG-010

- **GIVEN** `approved_source_sha` 分别是候选 HEAD 的严格祖先、非祖先、已是 trunk 祖先（在区间外）。
- **WHEN** 在本地下界校验。
- **THEN** SHALL 只放行严格祖先且位于 `trunk...<candidate HEAD>` 内的情形，其余 `AUTH_SCOPE_UNVERIFIABLE`。
- **AND** 端点看不到候选 HEAD，区间与祖先判定只能由 CLI 完成。

#### Scenario: SC-MG-011

- **GIVEN** 响应少一仓、多一仓、同计数但替换 repo_id（摘要按替换后集合自洽）、摘要不符。
- **WHEN** 校验 `repos_digest` 与集合。
- **THEN** SHALL 要求 `len(repos)==expected_repo_count`、repo_id 唯一且集合等于 grant `allowed_repositories`、摘要自洽，否则 `AUTH_SCOPE_UNVERIFIABLE`。

#### Scenario: SC-MG-012

- **GIVEN** `current_binding` 为 mismatch/unknown/ok；以及 legacy 证明缺失或与目录记录不符。
- **WHEN** 生成 findings 并判定外层码。
- **THEN** SHALL 把 mismatch 判 VIOLATION、unknown 判 UNVERIFIABLE，并把 legacy 证明缺失或不符判 UNVERIFIABLE。
- **AND** 不接受响应自报的 `provenance_digest`，只与可信目录记录比对。

#### Scenario: SC-MG-013

- **GIVEN** 越界 findings 与不可核实并存；端点不可达/超时/5xx/400/未知 code；撤销；head 前移；同仓有多条当前冻结行。
- **WHEN** 汇总并输出外层码。
- **THEN** SHALL 按 `UNAVAILABLE>REVOKED>HEAD_MOVED>VIOLATION>UNVERIFIABLE` 输出，非 200 码一律 UNAVAILABLE，多条当前行按事实缺失处理。
- **AND** grant 派生字段每次从端点重读，journal 只存摘要；所有码退出非零且 CR 状态不变。

### Requirement: merge-effects 以 reserve/report 兑现撤销线性化，journal 三态与恢复矩阵唯一。

#### Scenario: SC-MG-014

- **GIVEN** reserve 事务与撤销并发；以及撤销先提交、reserve 先提交两种顺序。
- **WHEN** 执行 reserve 与后续 push。
- **THEN** SHALL 由 CR 行锁串行（并发撤销在钩位只认 `55P03`），撤销先提交时 reserve 返 REVOKED 且零 push，reserve 先提交时撤销不追溯。

#### Scenario: SC-MG-015

- **GIVEN** journal `unknown` 且远端含 expected（等于或其后续）；`confirmed` 且远端为 expected 后继；`confirmed` 且远端退回 prev。
- **WHEN** 执行恢复判定。
- **THEN** SHALL 在含 expected 时不重推并结算成功，在正常前进时不动作，在退回 prev 时判 history rewrite 转 uncertain。
- **AND** 精确相等不是判定标准；祖先关系才是。

#### Scenario: SC-MG-016

- **GIVEN** journal `intent` 且远端等于 prev；以及服务端已 `settled_no_effect` + journal `unknown` + 远端 prev。
- **WHEN** 重入 merge。
- **THEN** SHALL 先以 `not_attempted` 结算旧 attempt 再以 `attempt+1` 重新 reserve，不得直接 push 或复用旧 attempt。

#### Scenario: SC-MG-017

- **GIVEN** 远端分叉（不含 expected 且不等于 prev）；journal `unknown` 无服务端终态且远端仍为 prev。
- **WHEN** 判定是否继续发布。
- **THEN** SHALL 在分叉时进入 uncertain 并禁止任何新 publish，在旧 push 可能延迟完成时保持 uncertain、不结算 no_effect、不重推。
- **AND** `unknown`/`uncertain` 状态下禁止发起任何新 publish；确认旧 effect 不授权后续 effect。

#### Scenario: SC-MG-018

- **GIVEN** 部分发布后仅 base 变化；或 base 与授权 head 均不变而候选 HEAD 变化。
- **WHEN** 继续推进原 merge 事务。
- **THEN** SHALL 分别记 `halted.reason=base_drift` 与 `halted.reason=input_mismatch` 并转人工。
- **AND** 不得换 base 续跑；`input_digest` 不同即拒绝恢复。

#### Scenario: SC-MG-019

- **GIVEN** finalize push 待发，以及 finalize reserve 时授权已被撤销。
- **WHEN** 执行 finalize。
- **THEN** SHALL 同样先 reserve 再 push，撤销时返 REVOKED 且不推送。

#### Scenario: SC-MG-020

- **GIVEN** attempt 四支（同 attempt 重放、前 attempt 已 settled、无未终结前 attempt、前 attempt 未终结）；head 前移且摘要不同；畸形请求、PAT+他人 crID、合法+他人 crID、服务端不可用。
- **WHEN** 提交 reserve/report。
- **THEN** SHALL 按四支返回 200/200/201/409，先判 head 再比摘要（HEAD_MOVED 不被 INPUT_MISMATCH 遮盖），认证与归属码序为 INVALID>UNTRUSTED>NOT_FOUND，非授权失败不写 halted。
- **AND** 409 时 journal 记 `halted.reason=uncertain`，且 409 body 不含 reason。

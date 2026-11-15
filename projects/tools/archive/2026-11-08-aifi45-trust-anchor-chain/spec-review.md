# SPEC 审查（2026-11-08）

> 审查方式：独立、只读文档/代码审查；按 LF 解读文本并在引用前以 grep 复核行号。未运行业务测试、未运行 `suite-gate`、未确认 Gate 2、未修改其他文件。
>
> 路径缩写：`change/` = `projects/tools/changes/2026-11-08-aifi45-trust-anchor-chain/`；`baseline/` = `projects/tools/specs/`；`T/` = `C:/Users/GOBAO/Downloads/AI/tools/skills/shared/crctl/scripts/`。

## 结论

**BLOCK**：10 条 CP 的命令形状和 TAP 汇总断言齐全，但仍有 SC 子句没有对应 TC 断言、真实平台/内核事实可缺席而 CP 仍 PASS，以及 repair 重放规则与基线及本设计自身冲突。

## 阻断项（若有）

| # | 问题 | 证据 | 建议 |
|---|---|---|---|
| B1 | **SC → TC/CP 的行为覆盖未闭合。**至少三处 THEN/AND 子句没有详细 TC 断言：① `endpoint` 只能定位；② 认证 actor 或 DB 归属不一致必须拒签；③ repair 不另建“信任账”。 | ① 规范明确写“环境变量、sidecar、**endpoint**和路径……只用于定位”（`change/canonical/specs/code/execution-authorization.yaml:19`），但 TC-TAC-001 只写“env 仅定位”（`change/test-plan.md:53`），TC-TAC-003 的表驱动项也只有 env/sidecar/路径/key/trustRoot，没有 endpoint（`:55`）。② SC-TAC-004 要求“来源结构、字段映射、**认证actor或DB归属**不一致”均拒签（`change/canonical/specs/code/execution-authorization.yaml:44`），TC-TAC-004 只写“独立提取与错误映射拒签”（`change/test-plan.md:56`）；CP 补充证据也只覆盖“不一致结构/映射”（`change/canonical/specs/agent/execution-authorization.yaml:40`）。③ SC-TAC-007 要求“不另建**信任、额度或历史账**”（`change/canonical/specs/code/repair-governance.yaml:16`），TC-TAC-007 只断言“无第二预算/历史账”（`change/test-plan.md:64`）。 | 在同一对应顶层 TC 中逐项增加可观察断言，而不是只改描述：伪造/替换 endpoint 不得成为证明；分别注入结构、字段映射、机器凭据/错误 actor、跨 DB project 归属并断言拒签；对 repair 的快照/文件/接口清单断言没有第二信任账。同步 code/agent YAML 与 test-plan。 |
| B2 | **CP-TAC-004/005 的机械 PASS 不要求其 SC 最关键的外部事实，允许“组件绿、真实事实未证”的假通过。** | 两条 CP 的 action 都只是一个本地 Node 文件，assertions 仅核 TAP 退出与汇总（`change/canonical/specs/agent/execution-authorization.yaml:36-37,44-45`）。真实 M route/DB 和每目标 OS 内核拒绝被放在 `supplementary_evidence`，且均标 `not_counted_as_cp_pass: true`（`:38-41,46-50`）。该字段只表达“补充证据本身不记作 CP PASS”，没有表达“缺补充证据则 CP FAIL”。因此一个自造 signer/source 的测试可以满足 CP-TAC-004，一个模拟权限错误或只测当前 OS 的测试也可以满足 CP-TAC-005 的五条机械断言。test-plan 虽要求“二者都满足才可登记相应 ADJ”（`change/test-plan.md:93`），但这不能使 **SC 所对应的 CP 本身**证明外部事实。 | 明确区分“组件 CP PASS”和“SC/ADJ 验证完成”；若坚持一 SC 对一 CP，则真实 route/DB 或目标 OS 证据必须是该 CP PASS 的必要条件，并将证据标识与实际执行输出绑定。缺真实链、缺任一拟启用 OS、以 fixture/模拟错误代替时不得给该 SC PASS；不得以 `# skipped 0` 代替目标平台覆盖。 |
| B3 | **SC-TAC-008 把“重放”也纳入“全部失败关闭”，与基线幂等恢复及本 change 的恢复决策矛盾。** | 新规格原文为“逐项请求修复准入、恢复**或重放**”后“SHALL **全部失败关闭**”（`change/canonical/specs/code/repair-governance.yaml:23-24`）。基线要求同逻辑 repair-admit“返回原 repair_id/receipt”（`baseline/repair-governance/spec.md:37-39`）、崩溃重启“按已提交事实恢复或回滚”（`:45-49`），有效 resume 重投“同恢复只生效一次”（`:89-92`）。本设计也明确“已提交……repair 的幂等重放……不重新发起一次业务准入”（`change/design.md:82`）及“成功重放沿原 receipt/journal”（`:97`）。TC-TAC-008 实际只列负例和模糊继续回退，没有重放操作（`change/test-plan.md:65`），所以既暴露冲突，也留下该 WHEN 子句无覆盖。 | 将 SC-TAC-008 限定为“首次新业务写入/未提交请求”的无效证明负例；已提交重放和崩溃恢复只沿原 receipt/journal，由 SC-TAC-007 的正例/幂等分支覆盖。不要把旧 head、撤销或失联下提交后恢复一概改成拒绝。 |

## 非阻断发现

| # | 问题 | 证据 | 建议 |
|---|---|---|---|
| N1 | **三条新 Requirement 没有与基线某一条整条同义，但规范主题有明显局部重叠。**这不会触发按标题的字面冲突，却会造成规范分散；B3 已展示其实际风险。 | 新标题分别在 `change/canonical/specs/code/execution-authorization.yaml:9`、`repair-governance.yaml:9`、`evidence-delivery-contract.yaml:9`。相近基线包括可信来源/scope（`baseline/execution-authorization/spec.md:25`）、当前 scope/版本/租户（`:55`）、原 bytes（`:80`）、repair 幂等恢复（`baseline/repair-governance/spec.md:33`）、停止恢复（`:67`）、交付恢复不重复消费（`baseline/evidence-delivery-contract/spec.md:63`）。 | 保留新增的信任链/首写准入主题，但明确“首次写入”与“已提交恢复”的优先级和交叉引用；不要在两条 Requirement 中各自重新定义同一重放语义。 |
| N2 | **register 的正例依赖尚未落地的“平台预分配 CR/claim”时序；设计承认了风险，但没有给出该关键选择的被否决替代。**现状 T 代码还是本地分配 CR，且 journal 先于候选 CR 创建。 | 设计要求 daemon 已持有平台分配 CR/claim，并在任何持久化前核对（`change/design.md:74,77`）；风险表再次把预分配设为前置（`:170`）。但现有 `registerCr` 先 `loadOrCreateJournal`（`T/lib/workspace-transactions.mjs:986`），随后才用 `scanMaxCrNumber + 1` 生成 candidate（`:1023`），并保存 `allocated`（`:1031`）。平台侧现成预分配接口在本次指定的 T 代码范围内**无法定位**；这不等于断言 M 一定没有。五个 Decisions 虽都有备选段落（`change/design.md:42,60,88,101,115`），但没有比较“平台预分配 / 两阶段本地预留 / register 暂不启用”的专门决策。 | 在 BUILD 前明确 CR 的分配权威、预分配接口、registration key 关联和崩溃恢复所有权，并记录被否决替代；否则 TC-TAC-009 的 register 正例只能一直按设计 fail-closed，不能误报为已验证。 |

## 逐项回答（A1–D12）

### A1. 每条 SC 的 THEN（含 AND）是否都有 CP 断言覆盖？

**结论：否。**以下把“CP → 唯一 TC → test-plan 对该 TC 的详细断言”视为行为覆盖链；CP 中那五条 TAP 断言只证明测试进程及汇总，不直接表达业务语义。Human View 与 Canonical code YAML 的相应文字一致，因此下列缺口不是 Human View 渲染漂移。

| SC / CP | 审查结论 | THEN / AND 覆盖证据与缺口 |
|---|---|---|
| SC-TAC-001 / CP-TAC-001 | **部分覆盖** | TC-TAC-001 覆盖共用缝、平台独立来源、env、原 bytes 和业务 gate（`change/test-plan.md:53`）；但规范的 **endpoint** 定位边界（`change/canonical/specs/code/execution-authorization.yaml:19`）在 TC-001/003 都没有对应负例或断言（`change/test-plan.md:53,55`）。见 B1。 |
| SC-TAC-002 / CP-TAC-002 | **纸面覆盖** | 两个首次写入口、同 key 跨 project/跨根复制及 CR/Git/receipt/task/trust-root 零变化均列出（`change/test-plan.md:54`）；对应 THEN 和同 key AND 在 `change/canonical/specs/code/execution-authorization.yaml:23-27`。真实链是否足以防止假通过仍取决于执行证据，当前未运行。 |
| SC-TAC-003 / CP-TAC-003 | **纸面覆盖** | env、sidecar、自报路径/pin、缺 key/未知 key、trustRoot 位于或包含安装根均列入表驱动；断言零副作用、无本地静态验签回退、不得把路径检查称为隔离证明（`change/test-plan.md:55`）。它不能补 SC-001 的 endpoint 缺口，因为该 TC 的场景和断言均未列 endpoint。 |
| SC-TAC-004 / CP-TAC-004 | **部分覆盖** | 改 `accepted_rules` 一字、digest/结构/json-pointer 拒绝和零副作用有覆盖（`change/test-plan.md:56`）；**认证 actor、DB 归属不一致拒签**没有对应断言，见 B1。 |
| SC-TAC-005 / CP-TAC-005 | **文字覆盖，但 PASS 机制不闭合** | 覆盖/替换/追加、内核错误、digest、不同身份、无证据不得启用及同 UID 不计证据都写入 TC（`change/test-plan.md:57`）；但真实 OS 证据不参与 CP PASS 的必要判定，见 B2。 |
| SC-TAC-006 / CP-TAC-006 | **纸面覆盖** | 错 scope、旧 policy/template/tools、旧 head、撤销、失联、普通读、check/check-source 与恢复均列出；断言零副作用、读路径无新增要求、`bound=false`、恢复不重复准入/消费（`change/test-plan.md:58`）。 |
| SC-TAC-007 / CP-TAC-007 | **部分覆盖** | 原 origin/消耗/streak/stop、预算、重放及第二预算/历史账均有断言（`change/test-plan.md:64`）；THEN 的“不另建**信任**……账”没有对应断言，见 B1。 |
| SC-TAC-008 / CP-TAC-008 | **部分覆盖且规则冲突** | 缺失/跨 project/跨根/改来源/坏 key/错 scope/旧 head/撤销和零副作用在详细 TC 有覆盖（`change/test-plan.md:65`）；SC 的“重放”没有出现在该 TC 操作中，而且“全部失败”本身与恢复基线冲突，见 B3。 |
| SC-TAC-009 / CP-TAC-009 | **纸面覆盖** | register/archive 首写前准入、平台 CR/claim/registration key、本地候选、时序不足拒绝、已提交重放不新增交付事实均列出（`change/test-plan.md:71`）。register 正例的现实依赖见 N2。 |
| SC-TAC-010 / CP-TAC-010 | **纸面覆盖** | 各类无效证明、env/sidecar/同名 CR/图路径以及 registration key、CR/worktree/registry、archive journal、交付记录、Git/index/task 零副作用均列出（`change/test-plan.md:72`）。 |

### A2. 每个 CP 的 action 是否可执行且只可能选中一条顶层测试？文件名/ID 是否一致？

**结论：形状上全部是；未发现文件名或 ID 不一致。**这里只审查 SPEC 命令合同，不表示目标文件已经存在或命令已运行。

- CP-TAC-001～006 均为 `node --test --test-reporter=tap --test-name-pattern="^TC-TAC-NNN$" skills/shared/crctl/scripts/test/trust-anchor-chain.test.mjs`（`change/canonical/specs/agent/execution-authorization.yaml:16,24,32,36,44,52`）；与 test-plan 映射一致（`change/test-plan.md:82-87`）。
- CP-TAC-007～008 使用 `^TC-TAC-007$` / `^TC-TAC-008$` 和具体 `repair-trust-anchor-chain.test.mjs`（`change/canonical/specs/agent/repair-governance.yaml:15,23`）；与 test-plan 一致（`change/test-plan.md:88-89`）。
- CP-TAC-009～010 使用 `^TC-TAC-009$` / `^TC-TAC-010$` 和具体 `delivery-trust-anchor-chain.test.mjs`（`change/canonical/specs/agent/evidence-delivery-contract.yaml:15,23`）；与 test-plan 一致（`change/test-plan.md:90-91`）。

精确锚点能在测试按合同以 TC-ID 作为顶层名称时只选一个顶层测试。文件计划在 BUILD 创建，本阶段不可把“命令形状正确”解释为“已执行成功”（`change/test-plan.md:7`）。

### A3. 每个 CP 是否都有五项指定 assertions？

**结论：全部有，没有缺项。**每条都同时包含 `exit_code=0`、`stdout_contains: 'ok 1 - <TC-ID>'`、`# fail 0`、`# skipped 0`、`# todo 0`：CP-001～006 见 `change/canonical/specs/agent/execution-authorization.yaml:17,25,33,37,45,53`；CP-007～008 见 `change/canonical/specs/agent/repair-governance.yaml:16,24`；CP-009～010 见 `change/canonical/specs/agent/evidence-delivery-contract.yaml:16,24`。B2 指出的是这些断言不足以证明外部事实，不是五项字段缺失。

### A4. 是否有 CP 依赖测试内部自造事实而有空跑风险？

**结论：测试文件尚不存在，无法指认一段已经写好的“必然通过”测试；但规格层面确实存在假通过通道，最可疑的是 CP-TAC-005 和 CP-TAC-004。**

1. **CP-TAC-005（最可疑）**：SC 的事实是不同 OS 身份下的真实内核拒绝，而 CP 的必选输出只有本地 Node TAP 五行；真实身份、实际写命令和内核错误全部位于不计作 CP PASS 的补充证据（`change/canonical/specs/agent/execution-authorization.yaml:44-50`）。因此模拟 `EACCES`、只检查 mode、或只覆盖当前 OS 的实现，在机械 CP 层面都可绿色；`# skipped 0` 并不能证明“每个拟启用平台”已覆盖。
2. **CP-TAC-004**：测试可自行制造 grant/source、修改一字并让 T 的 digest 检查拒绝，却只能证明本地校验器，不足以证明真实 M 在签发前独立提取及 actor/DB 拒签。真实 route/DB 同样被排除在 CP PASS 判定之外（`change/canonical/specs/agent/execution-authorization.yaml:36-41`）。

这不是说当前 ADJ 已被宣称关闭；test-plan 明确说未关闭。问题是 **CP/SC 的 PASS 语义本身仍可脱离其决定性事实**，故列 B2 阻断。

### B5. 三条新 Requirement 标题与基线 12 条是否语义重复？重复了会怎样？

**结论：没有“整条 Requirement 完全同义”的一对一重复，但有实质局部重叠。**三条新标题见各自 code YAML 第 9 行；基线 12 条标题位置为 execution-authorization 的 `:7,25,55,80`、repair-governance 的 `:7,33,51,67`、evidence-delivery-contract 的 `:7,21,41,63`。

- REQ-TAC-001 与基线的可信来源、当前 scope/版本、原始字节三题重叠，但新增点是把根归属、来源和 key 组成统一控制准入缝。
- REQ-TAC-002 与基线 repair 幂等、额度历史、停止恢复重叠，但新增点是首次业务写入前先过同一信任缝。
- REQ-TAC-003 与基线交付适用性/恢复不重复消费部分重叠，但新增点是 register/archive 首写的 project/root 归属。

语义重叠若不划清边界，会产生两个规范来源和优先级歧义；B3 已是具体结果。按标题的 archive 字面查重不能发现这种语义重叠。

### B6. 新规格是否与基线 THEN 矛盾？

**结论：有，SC-TAC-008 的重放分支矛盾，详见 B3。**基线要求返回原 repair receipt、按已提交事实恢复以及有效 resume 重投只生效一次（`baseline/repair-governance/spec.md:39,47,91-92`），新 SC 却在含“重放”的 WHEN 后要求“全部失败关闭”（`change/canonical/specs/code/repair-governance.yaml:23-24`）。其余已审 THEN 未发现另一条同等直接的基线矛盾；SC-TAC-006/009 对普通读和已提交恢复的处理方向反而与基线一致。

### B7. archive 按 Requirement 标题查冲突时是否有字面重复？

**结论：未发现字面重复。**三条新标题完整原文为“控制写准入必须由外部信任链同时证明根归属、原始来源与验钥身份。”、“修复与恢复先复用控制准入信任缝，再执行原有额度与停止裁决。”、“注册与归档只能把交付事实写入已验证归属的当前项目。”（三个 `change/canonical/specs/code/*.yaml:9`），均不等于 B5 所列基线 12 个标题。因此按所述标题查重规则，不应因这三条标题而中止；语义重叠仍需按 N1/B3 处理。

### C8. 五个入口的 design 接线是否与 CP/TC 覆盖一致？是否有只在设计里的入口？

**结论：五类入口均有 CP/TC，没有发现只写在设计里而完全无 TC 的应接入口。**

| 设计入口 | 设计证据 | CP/TC 覆盖 |
|---|---|---|
| `authorization-bind` 非只读 | `change/design.md:71` | TC/CP-TAC-001～006；正例、跨 project/根、伪定位、改来源、key/OS、当前性及只读 check 均有规划（`change/test-plan.md:53-58`）。 |
| `advance` | `change/design.md:72` | 同上，TC-001～004/006 明列 authorization-bind 与 advance；OS/公共信任链由 TC-005 补充。 |
| `repair-admit` / `repair-resume` | `change/design.md:73` | TC/CP-TAC-007～008（`change/test-plan.md:64-65`）；但有 B1/B3 缺口。 |
| `register` | `change/design.md:74,77` | TC/CP-TAC-009～010（`change/test-plan.md:71-72`）；预分配依赖见 N2。 |
| `archive` | `change/design.md:75` | TC/CP-TAC-009～010，包含首写与已提交重放。 |

`readRepairGrantPayload`、`reverifyRepairAuthorization` 等是实现接线点，不是新增第六个业务入口。`repair-assess/outcome`、extend/migrate、sensitive-action 和普通读被明确排除，不应误判为漏 TC（`change/design.md:83-84`）。

### C9. 是否有 proposal non_goals 明令排除的范围蔓延？

**结论：未发现。**设计明确“不建第二本账，不引入原生依赖、CA/PKI、新密钥管理体系或普通读路径改造”（`change/design.md:22`），并排除自由文本、comment、附件、`issue_source_context` 和普通文件读/哈希改造（`:83`）；这些与 proposal 的 non_goals（`change/canonical/proposals/2026-11-08-aifi45-trust-anchor-chain.yaml:73-77`）一致。新增内部编排器和复用现有 Ed25519/daemon/DB 不等于引入第二本账或 CA/PKI。N2 是 register 时序依赖未落地，不属于上述 non_goals 范围蔓延。

### C10. test-plan 的不可验证项是否诚实？

**结论：诚实，未发现把未取得证据写成已满足。**文件开头统一声明“待实现 / 未运行”且没有 TC、ADJ 或部署通过结论（`change/test-plan.md:7`）；末尾分别声明全部实现/TC 未运行（`:139`）、真实 M route/DB/daemon 与五入口未执行、ADJ-001/002 不能关闭（`:140`）、无目标平台清单和真实身份覆盖输出、ADJ-003 不能关闭（`:141`），生产启用/真实 CR/共享 DB 等也不可由本方案证明（`:142`）。因此 C10 本身不是阻断；B2 关注的是未来 CP PASS 的判定合同，不是当前证据报告造假。

### D11. design 是否有被否决替代及原因？缺哪条最关键的？

**结论：五个正式 Decisions 都有“备选方案及排除原因”**（`change/design.md:42,60,88,101,115`），涵盖 env/sidecar、只做路径 pin、各入口自行组合、新总账、请求自携 bindings、同 UID 权限、CA/KMS、全命令强制 daemon、只接 advance、恢复重复准入、信任链替代业务裁决、补偿清理、只用 fixture、skip 记 PASS 等。

**最关键的实质缺项是 register 分配时序的专门替代分析**：设计直接选择平台预分配 CR/claim（`change/design.md:77,170`），却没有比较两阶段预留、本地 candidate 与平台 claim 的原子关联、或该机制不可用时 register 不启用等方案及被否决原因。详见 N2。

### D12. 是否依赖尚不存在的机制或有隐含假设？

**结论：有一个关键未解决依赖，但设计已把它写成显式风险，不完全是隐含假设：register 的平台预分配 CR/claim。**

- 目标行为要求 daemon 已持有平台分配 CR/claim，T 在本地 candidate 确定后、任何持久化前核对（`change/design.md:77`）；SC-TAC-009 同样以此为 GIVEN（`change/canonical/specs/code/evidence-delivery-contract.yaml:14-18`）。
- 当前 T 实现并非此时序：先创建/读取 register journal（`T/lib/workspace-transactions.mjs:986`），后由本地扫描最大编号生成 candidate（`:1023`），再保存 `allocated`（`:1031`）。
- 因而必须有新的跨端分配/查询与关联合同，或重构本地分配时序，才能跑通 TC-TAC-009 的 register 正例。平台侧已有可复用预分配接口的位置在本次指定材料中**无法定位**，不能假称已经存在。设计允许缺事实时 fail-closed，所以这不是“永远不可实现”的证明；但若不正视该依赖，就会把永远拒绝误当成正例覆盖。列 N2 并要求 Gate 2 前澄清。

## 我认为 Gate 2 应当驳回的唯一理由（若没有就写「没有」）

**规格尚未形成一份可无歧义执行并据实判定 PASS 的合同：它同时存在未覆盖的强制子句、真实外部事实可缺席的 CP 绿色通道，以及 repair 重放与既有恢复语义冲突（B1–B3）。**

## 修复回应（2026-11-08）

### B1 · SC 子句补对应 TC 断言

1. **endpoint 只定位**：`test-plan.md:55` 的 TC-TAC-003 表驱动项加入伪造/替换 endpoint，断言真实控制准入失败且零业务副作用；即使 endpoint 可响应，也只能由签名与归属合同决定结果。`canonical/specs/agent/execution-authorization.yaml:31` 同步列出 endpoint。这样可观察结果不再只覆盖 env，endpoint 响应不能冒充信任来源。
2. **actor / DB 归属拒签**：`test-plan.md:56` 的 TC-TAC-004 增加机器凭据/错误 actor、跨 DB project 两组负例，各自断言拒签、DB 无新增签发记录及 CR/Git/授权消费/平台任务零变化；`canonical/specs/agent/execution-authorization.yaml:40` 同步补充证据断言。这样两类外部归属错误都有独立可观察的拒签与零副作用结果。
3. **repair 不另建信任账**：`test-plan.md:64` 的 TC-TAC-007 在操作前后枚举安装根与账本目录，断言无新增信任/凭据账文件、无第二预算/历史账，且信任事实只来自既有 grant/keys。这样“不另建信任账”不再只由预算和历史账断言间接代替。

### B2 · CP-TAC-004/005 外部事实改为整条通过的必要条件

- `canonical/specs/agent/execution-authorization.yaml:42-46` 为 CP-TAC-004 增加 `unmet_requirements`：机械 PASS 仅覆盖本地 digest、结构/json-pointer 拒绝与零副作用；整条 SC 另需真实 M route/DB 行、actor/DB 拒签及真实 daemon/T 关联证据。`:57-61` 为 CP-TAC-005 增加同类字段：机械 PASS 仅覆盖本地写尝试组件子句；整条 SC 另需每个拟启用平台的不同身份真实内核覆盖/替换/追加拒绝及 digest 证据。两处都明确外部证据缺席只能记条款级，不得登记整条通过或以 skip 代替。
- `canonical/specs/code/execution-authorization.yaml:44,50` 同步规定外部证据缺席时 SC-TAC-004/005 不得记整条通过，且新合同失败关闭/不得启用；`test-plan.md:56-57,95-102` 增加对应 TC 断言与整条/条款级登记表。未把外部证据塞进 CP action，也未新增 skip 通道，因此自造 signer、模拟权限错误或只测当前 OS 的 TAP 绿色不能再被解释为完整 SC 通过。

### B3 · 无效首写与已提交幂等恢复分流

- `canonical/specs/code/repair-governance.yaml:23` 将 SC-TAC-008 的 WHEN 收窄为“尚未提交的新业务写入”，不再把已提交重放列入全部失败关闭。`:14-18` 将已提交重放和崩溃恢复归入 SC-TAC-007，明确沿原 repair_id/receipt/journal、重放返回原 receipt 且不重新消费、未提交写入回滚。
- `test-plan.md:64-65` 分别在 TC-TAC-007 增加原 receipt/不重复消费及崩溃恢复断言，在 TC-TAC-008 明确只执行未提交新写入负例；`canonical/specs/agent/repair-governance.yaml:19,22` 与 `design.md:82,97` 同步。这样无效证明仍零副作用失败关闭，而基线要求的已提交幂等重放和崩溃恢复不会被误判为必须拒绝。

以上修改未确认 Gate 2；三份 Human View 均由 Canon 渲染器重新生成。

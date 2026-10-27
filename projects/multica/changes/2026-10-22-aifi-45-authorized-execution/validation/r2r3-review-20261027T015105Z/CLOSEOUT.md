# R2/R3 修订草案复核结果：两道均未通过

## 结论

| 轴 | R2（存储/端点/认证/失败码） | R3（撤销与实际发布的线性化） | 会话 |
|---|---|---|---|
| strong | **BLOCK** | **BLOCK** | `01a17b21-9c2c-760a-b938-34e86e764929`（首次 `01a17b0e-3844-…` 被中断，同法重试一次） |
| balanced | **BLOCK** | **INCOMPLETE** | `01a17b0e-385f-77b9-a3c5-0f8c3393ee2e` |
| economy | **BLOCK** | **PASS**（仅文档一致性轴） | `01a17b21-c484-760a-b938-34ea79d54fb2`（首次 `01a17b0e-3871-…` 被中断，同法重试一次） |

- 三路均为新鲜非作者、只读静态复核；被审对象为 `inputs/plan.md` 的 v0.6 节，SHA256 `7d688fda1faa31f1cbe5e92ad459167edb70008636ed7eaad569db9b6faa97ba`，与冻结值一致。
- **两路首次启动在完成前被中断**（strong、economy），按 subagent 规则各同法重试一次；重试成功。中断不计入结论，也不把中断当失败证据。balanced 一次完成。
- 未跑 DB/测试/迁移，未改被审文件，未互相传递输出。economy 的 R3 PASS **只**表示文档一致性轴无冲突，不覆盖 strong/balanced 的 R3 结论。

## 合并后的实质阻断（R2）

| ID | 问题 | 来源 | 最小修订 |
|---|---|---|---|
| Q1 | facts 取不到时**两个失败码并存**：R2 第 4 项给 `AUTH_SCOPE_UNVERIFIABLE`，§3 失败码闭集给 `EXECUTION_AUTHORIZATION_UNAVAILABLE`；两条 leaf 的 code 断言必有一边红 | BAL-R2-01 | 三档定码：端点不可达/超时/5xx → `EXECUTION_AUTHORIZATION_UNAVAILABLE`；可达但 facts 缺失/身份不符/集合不全 → `AUTH_SCOPE_UNVERIFIABLE`；§3 改为指向 R2 为唯一权威 |
| Q2 | `approved_source_sha` 究竟是“祖先下界”还是“精确”，表里无法判定；多行如何取用未定 | STR-01、BAL-R2-02、EC-4 | 表改为每 `(cr_id,repo_id)` 一行 + 单调 `approved_revision`，或加 `bound_kind ∈ {ancestor,exact}`；写死多行/并列即拒 |
| Q3 | 响应闭集缺“仓库集合完整”的可判字段（无 `expected_repo_count`/`repos_digest`）；`current_binding_ok` 布尔吞掉“未知”，与既有 `identityMismatch` 三态不一致 | STR-02、BAL-R2-04 | 闭集加计数与摘要；`current_binding` 改 `ok|mismatch|unknown`，`unknown` 归 `UNVERIFIABLE` |
| Q4 | 认证主体 ≠ 目标绑定：未规定声明 CR 必须等于哪条可信会话绑定；`workspace_revision` 比什么、不等用什么码未定 | STR-02、BAL-R2-03 | 固定 主体→workspace→CR→当前 grant 的解析与相等校验；`workspace_revision` 定性为断言值或删除 |
| Q5 | 失败码→CLI 折叠无映射表：`HEAD_MOVED`/`REVOKED` 是否保留、多错优先级、已知越界是否会被静默降级为“不可验证” | STR-03 | 列 服务端条件→响应码→CLI 外层码 表，含优先级；不得把已知越界变 `UNVERIFIABLE` |
| Q6 | `legacy_proven` 要求证明摘要，但闭集无该字段；“否则按 strict 处理”未定义后果 | STR-02、BAL-R2-05 | 闭集加 `provenance_digest`；缺失/不符 → `UNVERIFIABLE` |
| Q7 | `execution_code_source_freeze` 使 §4 从 13 表变 14 表，而 §4 的“13”“8+5”“精确 13 名”与迁移三例未同步 | EC-1 | 计数与迁移三例同步到 14（或按交付面分支记 13），并在同一 proposed migration 内 |
| Q8 | merge-facts 端点未进 §6 端点归口；GET 语义未继承 §6 的状态码/未知字段规则 | EC-3 | 两分支写死（随 change 交付 → §6 三改四 + 状态码/closed-code 映射；M 内部调用 → §6 不变并注明），交付面由人类定 |

## 合并后的实质阻断（R3）

| ID | 问题 | 来源 | 最小修订 |
|---|---|---|---|
| Q9 | “重验通过那一刻”与“M 事务唯一提交点”是三个时点（读通过 / 提交 / 实际 push），未定重验事务锁哪些共享授权行、如何与撤销互斥、提交后释放再 push 的顺序 | STR-04 | 明确授权排序点与远端 effect 确认点分离；定义撤销/重验共享锁与 effect 身份幂等；写清“重验提交后撤销是否仍允许该已排序 effect” |
| Q10 | “以 journal 记录的 effect 为事实”在 push 成功但 journal 未记成功时失效（只有 intent）；“先查远端”未定义查什么、三分支结局未定 | STR-05、BAL-R3-01 | 持久区分 `intent/unknown/confirmed`；恢复先只读核实远端，写死 相等→幂等完成 / 旧 sha 仍可达→转人工 / 分叉→转人工+标 `diverged`；未知禁止发布 |
| Q11 | “停止后续 publish、转人工”无状态、无终码、无恢复入口；部分发布后 CR 状态未定 | BAL-R3-02 | 定终态名与 journal 中止字段（`halted_at_effect`/`halted_reason`），receipt 不改写；唯一人工入口与拒绝条件 |
| Q12 | base 变化“拒绝并要求新授权”与“部分发布后禁止新事务”相互冲突：新授权能否续旧 journal 未定；finalize 的独立 push 是否算 effect 未定 | STR-06、BAL-R3-04 | 给 零发布/部分发布/全部发布待 finalize 的恢复矩阵；定义 `input_digest`（含 base）与 finalize 重验/漂移规则 |
| Q13 | 撤销提交点缺可观测标识，交错夹具无法定位“撤销已提交”这一时点 | BAL-R3-03 | 以 `…freeze.revoked_at IS NOT NULL` 的可见性为提交点，夹具挂在重验前/后各一支 |

## 主会话判断：跨路冲突与不采纳处

1. **R3 的 economy PASS 不构成通过**：economy 只判文档一致性（与 (a)、§4 不矛盾），明确声明“可测试性归 balanced、竞态归 strong”。因此 R3 仍按 strong BLOCK / balanced INCOMPLETE 记。
2. **Q1 与 Q5 是同一根因**（失败码未分层），修时必须一次改 §3 闭集 + R2 第 4 项 + CLI 折叠表，不能只补一句映射。
3. **Q2 与 Q7 会互相影响**：表结构若改为 `(cr_id,repo_id)` 单行 + `approved_revision`，则“13→14”的迁移清单与 `ChannelTableNames` 断言必须同批改，反之亦然。故 Q2/Q7 必须同批落。
4. **`workspace_revision`（Q4）我倾向删除**：M 既然能解析 workspace，就不该再收一个调用方可控的 revision；但这是交付面（Q8）的一部分，留给人类决策时一并定。
5. 不采纳 balanced 关于“R2 第 4 项折进 `AUTH_SCOPE_UNVERIFIABLE` 与 CLI 折叠语义相容、故不冲突”的局部结论——它与 §3 闭集仍冲突（Q1），只采纳其“fold 语义本身相容”的部分。

## 后续顺序（本轮未执行）

1. 先定 Q8 交付面（人类决策）：端点随本 change 交付 vs M 内部调用。它决定 §6 端点计数、迁移/台账增量、以及 Q1 的码归属。
2. 按 Q1→Q2+Q7→Q3/Q4/Q5/Q6 的顺序合并成一份唯一合同（不追加条目）。
3. R3 按 Q9→Q10→Q11/Q12/Q13 收敛；核对 STR-04 的“撤销即时性”是否需要人类决定。
4. 收敛后冻结新 SHA 再复核一次；本轮 BLOCK 不自动继承为 PASS。

## 效力

- **R2/R3 未通过**；v0.6 仍是作者草案，不得称已批准；M003 仍 proposed/搁置、注册由用户。
- AIFI-45 权威覆盖 41/49、Gate NO-GO、M001/M002/M003 unresolved、原库 HOLD 均未因本轮复核改变。
- 本轮未改源码、未提交被审方案内容（仅新增复核记录）、未 push。

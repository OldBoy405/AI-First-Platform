本章裁决：R2 **BLOCK**
本章裁决：R3 **INCOMPLETE**

（读入：`REVIEW-BRIEF.md`；`inputs/plan.md` 的 v0.6 节（L480–L513），SHA256 与冻结值一致；对照源码 `crctl.mjs:1860–1888`、`lib/change-scope.mjs:120–175`。未编辑任何文件，未跑 DB/测试，未看其他 lane。）

---

## R2——可验证性判断

**总体：请求面可写，响应面半闭合，失败码面不可写（两章对同一条件给了两个码）。**

**BAL-R2-01｜blocker｜`## v0.6 修订草案` → R2 第 4 项**（`AUTH_SCOPE_UNVERIFIABLE`（facts 缺失/读失败/身份不符/仓库集合不全））**与 §3 L135 失败码闭集**（`EXECUTION_AUTHORIZATION_UNAVAILABLE`（§6 只读端点取不到 facts））直接冲突。同一物理条件（端点取不到 facts）在两章各映射一个码，且 L135 明写“每条各配 leaf”。后果：leaf `merge 范围无法核实即拒`（L319，断言 `AUTH_SCOPE_UNVERIFIABLE`）与新增的两个码无法同时成立；任何测试的 code 断言必有一边 RED，mutation 也可两面打红——这不是“写不写得出测试”，而是**测试会互相打架**。
最小修订：R2 第 4 项显式分三档并写死判定点——`facts 端点不可达/超时/5xx` → `EXECUTION_AUTHORIZATION_UNAVAILABLE`；`端点可达但 facts 缺失/身份不符/仓库集合不全` → `AUTH_SCOPE_UNVERIFIABLE`；并把 L135 的这一行改为指向 R2 第 4 项为唯一权威。归属：R2 草案本身（附带 §3 L135 一致性改写）。
可写测试：是（改后）。改前不可写。

**BAL-R2-02｜major｜R2 第 1 项存储列**（`approved_source_sha` 单值 + `UNIQUE(cr_id,repo_id,approved_source_sha)`）与 R1=(a) 的“区间下界”语义**既未对齐也未给判定点**。表中无 `parent_sha`/`lower_bound`/`approved_range` 列，也无“多行如何取用（取 max? 取最新 `approved_at`? 多行并存即拒?）”的规定。结果是：`approved_source_sha` 究竟是“HEAD 下界”还是“祖先下界”无法从 schema 判定，正反例都构造不出——“区间包含批准 sha 的祖先”与“HEAD 必须等于批准 sha”都能读进这段文字。
最小修订：加一列 `bound_kind ∈ {ancestor, exact}`（或 `approved_parent_sha`），并写死“多行时取唯一最新 `approved_at`；并列即 `AUTH_SCOPE_UNVERIFIABLE`；`bound_kind≠ancestor` 时按 exact 判”。归属：R2 草案本身（需人类确认是否引入 `bound_kind`，但取舍成本极小）。
可写测试：改后可写；当前不可写。

**BAL-R2-03｜major｜R2 第 2 项端点**（`?cr=<id>&workspace_revision=<n>`）**未定义 `workspace_revision` 的失配语义与来源**。端点拒绝调用方决定 workspace，却接受一个由调用方给出的 `workspace_revision`；草案没说它是“断言”（不等即拒，用哪个码？）还是“提示”（忽略）。正例可写（同 revision），反例的期望码无处可查。
最小修订：写明 `workspace_revision` 为**断言值**，与 M 解析出的当前 revision 不等即 `AUTH_SCOPE_UNVERIFIABLE`；或删除该参数、只由绑定解析。归属：R2 草案本身。
可写测试：是（二选一后）。

**BAL-R2-04｜major｜R2 第 3 项响应闭集**（`{cr_id, selection_kind, head_revision, repos:[{repo_id, identity_digest, current_binding_ok, approved_source_sha}], grant_digest, frozen_at}`）**不足以判定“仓库集合完整”**。闭集里没有 `expected_repo_count`/`repos_digest`，而第 4 项把“仓库集合不全”判为失败——CLI 无从区分“M 认为该 CR 只有 2 个仓”与“M 本该返回 3 个仓但漏了一个”。同时 `current_binding_ok` 是布尔，草案未定义“谁来算、算不出来时是 false 还是缺字段”——这与既有 `identityMismatch`（`change-scope.mjs:152–175`）返回三态（ok / 原因串 / null 未知）的粒度不一致，测试无法断言“未知≠不符”。
最小修订：闭集加 `expected_repo_count` 与 `repos_digest`（覆盖 `repo_id+identity_digest+approved_source_sha` 排序后摘要）；`current_binding_ok` 改为 `current_binding: ok|mismatch|unknown`，`unknown` 与 `mismatch` 均拒但码不同（前者 `AUTH_SCOPE_UNVERIFIABLE`）。归属：R2 草案本身。
可写测试：改后可写（正例：count 与 digest 自洽；反例：删一项 → digest 不符即拒）。

**BAL-R2-05｜minor｜R2 第 3 项**（`legacy_proven` 必须携带可信目录证明摘要，否则按 strict 处理）**“按 strict 处理”未定义后果**：是拒绝，还是用 strict 路径继续？“可信目录证明摘要”字段名未进闭集（闭集只有 `selection_kind`）。测试无法写“缺摘要 ⇒ 期望码”。
最小修订：闭集加 `provenance_digest`，并写“`selection_kind=legacy_proven` 且 `provenance_digest` 缺失/不符 → `AUTH_SCOPE_UNVERIFIABLE`”。归属：R2 草案本身。
可写测试：是（改后）。

**BAL-R2-06｜minor（核过，确认不冲突）｜`55P03`、journal、零 publish 三处落点**。结论：**R2 章内不承载这三项**，落点在 §S5：`55P03` 在 L29/L285/L329（binding/root/claim 探针，均“只认 SQLSTATE，不接受超时当 RED”）；journal 观测在 L311/L312（`merge 范围核对越界零写入` 要求“观测 journal/锁/outbox/Git 写命令而非只验目录”）；零 publish 在 L312（“注入 publish 端口并断言零调用，而不只验退出码”）。三处均明确可执行，且与 `crctl.mjs:1869`（`purpose==='revoke'` 先拒）的现存行为不矛盾。**唯一缺口**：R2 新增的端点/存储若随 change 交付，需要一个自己的 `55P03` 落点（并发在 facts 读与 publish 之间），草案未提；但这取决于“端点是否随 change 交付”这一**未决项**，故记 minor、不阻断。

**BAL-R2-07｜未决项可验收性（minor）**：R2 末段“端点随 change 交付 vs M 内部调用”**未写由谁在何时决定、影响哪些 leaf**。可验证性后果是可枚举的（交付面决定 `T/lib` 是否有 merge-facts client、决定正反例走 HTTP 还是函数级注入）。最小修订：写明“由人类在 v0.6 定稿时择一，并在 S5 增两条互斥 leaf：`merge-facts 端点拒绝跨 workspace 查询`（HTTP 面）/ `merge-facts 内部调用不经 CLI 参数决定目标`（函数面）”。归属：需人类决策（但**影响面必须写进草案**，否则测试计划无法冻结）。

---

## R3——可验证性判断

**总体：四种情形中 3.5 条可写出 leaf+mutation；“部分发布”与“响应丢失”的判定动词未定义，属不可写。**

**BAL-R3-01｜blocker｜R3 第 4 项**（“以 journal 记录的 effect 为事实，恢复时**先查远端**再决定重放或转人工”）。“先查远端”未定义查什么：`git ls-remote` 的 ref 相等？对象可达？强推后的祖先关系？三个查询给出三个不同判定；而“决定重放或转人工”是**判定点未定义**（brief 明列“重验/一致/人工处理”）。当前只能写“恢复入口被调用”，不能写期望结局，正反例不成立。
最小修订：写死判定为 `ls-remote <repo> refs/heads/<trunk> == journal.effect.expected_sha` → 幂等完成（不重推）；`!=` 且旧 sha 仍可 `merge-base --is-ancestor` 达成 → 转人工并保留 journal；否则 → 转人工 + 标 `diverged`。三档各一条 leaf。归属：R3 草案本身。
可写测试：改后可写；当前不可写。

**BAL-R3-02｜major｜R3 第 3 项**（“停止后续 publish、保留原 journal/receipt、转人工；**不自动新建事务、不换源解除阻断**”）。“转人工”无状态、无终码、无恢复入口名。可写部分只有“后续 publish 端口未被调用”（L312 已具备），但“保留原 journal/receipt”缺断言面（哪个文件、哪个字段不变），且转人工后的 CR 状态未写（L135 说失败保持 `code-approved`，但部分发布后是否仍 `code-approved` 未定）。现有 leaf `merge 范围撤销发生在部分发布后`（L310）因此只覆盖一半（mutation 面可写，正向断言面不可写）。
最小修订：写死“部分发布后撤销 ⇒ CR 状态置 `merge-blocked`（或复用既有终态名），journal 增 `halted_at_effect` + `halted_reason ∈ {revoked, head_moved, publish_failed}`，receipt 不改写；人工恢复入口唯一为 `crctl merge --resume <journal>`，其拒绝条件为 `input_digest` 不符”。归属：R3 草案本身。
可写测试：改后可写。

**BAL-R3-03｜major｜R3 第 1/2 项**（线性化点 =“该仓 push 前最后一次 head/撤销重验通过”那一刻；“M 侧撤销提交先于重验 → 拒；重验先于撤销提交 → 该 effect 视为撤销前已获授权”）**可写但需要交错夹具的定义**。第 2 项给了清晰的两支，与 L311 的既有要求（“必须在首次读取之后、效力检查之前**确定性交错**撤销或 head 前移”）一致，所以“撤销先/后”**能各出一条可执行 leaf+mutation**：leaf A `merge 范围撤销先于重验即拒`（mutation：去掉重读 → 不拒）；leaf B `merge 范围重验先于撤销提交则不影响已发生 effect、不追认后续`（mutation：把撤销解释为追溯作废已发生 effect → 结局断言反）。缺口仅在“M 事务唯一提交点”这一表述**未给可观测标识**：测试需要一个能看到“撤销已提交”的句柄（表行 `revoked_at` 或 journal seq）。最小修订：写明“以 `execution_code_source_freeze.revoked_at IS NOT NULL` 的可见性为撤销提交点，夹具用事务挂起在重验前/后各一支”。归属：R3 草案本身。
可写测试：是（补上观测标识后即可）。

**BAL-R3-04｜major｜R3 第 5 项**（“rebuild 更换 base 属输入变化：按 3 拒绝，要求新授权”）**与 § L120 的既有规定一致，但两处都缺“输入同一性”的定义**（摘要算哪些字段、是否含 `trunk`、是否含 `allowed_paths`）。leaf `merge 范围恢复沿用原冻结输入`（L310）当前只能靠“YAML 已变 → 拒”这一粗粒度反例，无法覆盖“base 变但 YAML 未变”的情形——而这恰是 R3 第 5 项声称要拦的。
最小修订：定义 `input_digest = SHA256(base_sha‖trunk‖selection_kind‖sorted(approved_source_sha)‖grant_digest)`，并入 journal；恢复时比对，不等即拒。归属：R3 草案本身（与 L120 合写）。可写测试：改后可写。

**BAL-R3-05｜minor｜R3 第 6 项**（“不试图把跨网络 push 包进 DB 事务；能保证的是 effect 前重验 + 部分发布后不继续”）——**写得诚实且可验证**，与 L122（“不得声称此前连锁文件都没写过”）一致，无竞态措辞夸大。唯一残留：未写“push 与 journal 写入的先后”（journal 先记 effect-intent 再 push，还是 push 成功再记）。这直接决定第 4 项“journal 记录的 effect 为事实”是否成立。
最小修订：写明“push 前写 `effect_intent`（含 `expected_sha`），push 成功后写 `effect_done`；恢复时 `effect_intent` 无 `effect_done` ⇒ 必查远端”。归属：R3 草案本身。可写测试：是。

---

## 可写 / 不可写测试的判断落点

- **不可写（当前）**：BAL-R2-01（码冲突，两码并存无法断言）、BAL-R2-02（区间语义）、BAL-R2-04（集合完整性不可判）、BAL-R3-01（“先查远端/转人工”）、BAL-R3-02（“转人工”无终态）、BAL-R3-04（输入同一性）。
- **可写（草案已够具体）**：R2 第 2 项认证拒绝面（PAT/JWT/task-token、`--grant`/`--workspace` 不决定目标）可写正反例；R2 “不降 legacy、不扫 `grants/`” 可写反例（已有 `merge 范围不受 grants 目录旧文件影响`，mutation 已补强）；R3 第 1/2 项撤销先后两支；R3 第 5 项“同一次 merge 内静默换 base 即拒”；`55P03`/journal/零 publish 三处落点（§S5 已可执行）。
- **与既有 CLI 折叠规则**：`crctl.mjs:1883–1884` 现为 `findings→AUTH_SCOPE_VIOLATION`、`problems→AUTH_SCOPE_UNVERIFIABLE`（`cmdAuthorizationScope`）。R2 第 4 项把 facts 失败折进 `AUTH_SCOPE_UNVERIFIABLE` 与该折叠**语义相容**（它不是 findings），故不冲突；冲突只在 R2 vs §3 L135 的 UNAVAILABLE。判定器本身 `change-scope.mjs` 只返回 findings/problems 二元，无第三类，故 R2 若继续增加第三码，必须在 `cmdMerge` 侧另设 fail 点，不能塞进 `checkChangeScope`。

## 阻断通过的最小集合

1. **BAL-R2-01**：facts 失败三档定码，§3 L135 改为单一权威（否则测试必自相矛盾）。
2. **BAL-R2-02**：`approved_source_sha` 是“祖先下界”还是“精确”，落成列或字段 + 多行取用规则。
3. **BAL-R2-04**：响应闭集加 `expected_repo_count`/`repos_digest`，`current_binding` 三态。
4. **BAL-R3-01**：远端查询的判定三档（相等/可达/分叉）与“转人工”的可观测终态。
5. **BAL-R3-04**：`input_digest` 定义（覆盖 base 变化，否则第 5 项无 leaf 可覆盖）。
6. **BAL-R3-02/05**：部分发布后 CR 状态与 journal 中止字段；`effect_intent`/`effect_done` 双写顺序（决定第 4 项前提）。

不阻断但须落纸：BAL-R2-03（`workspace_revision` 语义）、BAL-R2-05（`provenance_digest`）、BAL-R2-07（交付面决策的影响面）、BAL-R3-03（撤销提交点的可观测标识）。

未决但不代选：端点交付面（HTTP vs M 内部调用）仍属人类；我仅指出它决定 2 条互斥 leaf 的形态。

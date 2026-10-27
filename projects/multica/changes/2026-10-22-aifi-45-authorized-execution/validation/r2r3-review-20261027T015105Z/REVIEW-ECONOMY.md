本章裁决：R2 BLOCK（文档一致性：表计数、表名与 §4 冲突，交接面未闭环）
本章裁决：R3 PASS（仅限本条：与 R1=(a)、§4 的线性化描述不矛盾；可测试性归 balanced 路）

判定前提：被审对象是 `validation/r2r3-review-20261027T015105Z/inputs/plan.md` 末尾 L480–514（brief 所说的“本目录 inputs/plan.md”）；对照正文 §4 L143–170、§6 L192–205、L451 版本行。

**(a) 与 R1=(a) 是否矛盾**：不矛盾，但有一处残留旧指针（见 EC-2）。
- R2 §1 明确：表只存“批准下界”，不存实际发布 sha；实际候选 HEAD 由本地预检写入 journal/receipt，且写明“本地审计事实，不是授权凭据”。这与 L114/L451 的 (a) 五条一致。
- R3 的逐仓 effect、撤销排序与 §4 L166–167（effect 线性化点 = caller Tx commit；revoke 不等待 slot、不追溯）同向；R3 §2 的“M 事务唯一提交点”是对既有措辞的重述，不是新增语义。R3 §6 显式否认“把跨网络 push 包进 DB 事务”，与 §4“Tx 内不调用网络”一致。

**(b) 是否残留 (b) 语义 / “批准树” / 把草案写成已批准**：无 (b) 语义残留；无“批准树”断言；未把草案写成已批准。L480 标题自带“未复核，不得称已批准”，L482 明说“R2/R3 给出可评审合同草案”，R3/R2 均未被写成“已决”。L310 与 L451 的“取自批准树”仅作历史改写说明（“原形态只在 (b) 成立”），属版本记录语境，可接受。唯一问题是 L508 标题仍写“仍待人类决策”，与同节末“已决（2026-10-26，用户选择 (a)）”自相矛盾（EC-2）。

**(c) `execution_code_source_freeze` 与 `merge-facts` 端点 vs §4 十三表 / §6 三端点**：存在实质冲突（EC-1、EC-3）。

## Findings

**EC-1｜blocker｜位置：R2 L489–494 “§4 新增 `execution_code_source_freeze`” ↔ §4 L160 “v0.3 合计 13 张新表（原业务通道 8 + D7 5）…up/down/索引/immutable 测试按此清单核对”；另 L324 “精确 13 名、无重复”“全部 13 张新表”。**
问题：新增第 14 张表，但正文的“13”计数、8+5 分解、“精确 13 名”清单断言与迁移三例（up/down/reapply 逐表检查）均未随之改写 → 草案与 §4 内部直接冲突，且会与 `ChannelTableNames` 专例断言打架。
最小修订：R2 §1 末尾加一句“§4 表清单与计数由 13 改为 14（原业务通道 8 + D7 5 + merge facts 1），`ChannelTableNames`、`TestChannelMigrationAfter{Up,Down,Reapply}` 的 13 同步改为 14，并在同一 proposed migration 内”；正文 L160/L324 的计数改为“14（若端点不随本 change 交付则记 13）”。
归属：R2 草案本身（正文 §4 计数属需同步修订的章节）。

**EC-2｜major｜位置：R1 小节标题 L508 “### R1（原 STR-01）：仍待人类决策——发布语义 (a) 还是 (b)”，以及 L510 “（即 R2 的第 1 项按 source 区间而非单一 sha）”。**
问题1：标题残留“仍待人类决策”，与同节 L512 起“已决（2026-10-26，用户选择 (a)）…本段保留为决策记录”矛盾，也与整个 v0.6 节的前提冲突（把已决写成待决）。
问题2：L510 的括注要求 R2 第 1 项“按 source 区间而非单一 sha”，而 R2 §1 已改为“单列 `approved_source_sha` 作批准下界、区间由预检产生”——该括注是 (a) 早期写法，未随 R2 定稿回收，会诱导实现者把区间写进表。
最小修订：标题改为“### R1（原 STR-01）：已由用户决定为 (a)（决策记录，不再重开）”；删 L510 括注或改为“（R2 §1 只冻结批准下界；实际区间/HEAD 由本地预检写入 journal/receipt）”。
归属：R2/R1 记录文字（不需要人类再决策）。

**EC-3｜major｜位置：R2 §2 L495–496 `GET /api/daemon/execution-control/merge-facts?...` ↔ §6 L193 三端点清单；另 L486 “§6 的三个端点也不提供 merge facts”。**
问题：§6 是本文件唯一的 API 归口，若 merge-facts 随本 change 交付，它必须出现在 L193 的 proposed 清单（并继承 §6 的 201/200/409 与 closed-code 规则或以 GET 语义另行声明状态码）；草案把它留在“交付面未定”，却未写“若随 change 交付则 §6 清单与迁移/台账增量需同步”，读者无法判断 §6 是否仍是三端点。同时 GET 端点未继承 §6 L194–196 的状态码/未知字段规则，失败码只给三个 `AUTH_SCOPE_*`/`EXECUTION_AUTHORIZATION_*`，未说明与 §6 closed-code 枚举的映射关系。
最小修订：§2 改为两分支显式化——“(i) 随本 change 交付：§6 L193 端点清单由三改四，补 merge-facts 的 200/400/403/503 与 closed-code 映射（`AUTH_SCOPE_UNVERIFIABLE`→现有 findings 折叠规则不变）；(ii) M 内部调用：§6 不增端点，另注‘不经 CLI、由 M 服务内签名调用’，并写明台账/迁移不变”。附一句“本项由人类决定交付面，二者影响 §6 端点计数与台账增量”。
归属：R2 草案本身 + 需人类选择交付面（brief 第 5 条允许的“未定”只需补足影响面，不属于选语义）。

**EC-4｜minor｜位置：R2 §1 表名 `execution_code_source_freeze` ↔ §4 L145 表头“表名后缀（均以 `cr_execution_` 开头）”。**
问题：草案用裸名，与既有命名约定（全名 `cr_execution_*`）不一致；且 `UNIQUE(cr_id,repo_id,approved_source_sha)` 在“重新批准/HEAD 前移后再批准”时允许同一 (cr_id,repo_id) 多行，而表无 `superseded`/`approved_revision` 列，响应里的 `head_revision`/`frozen_at` 无法确定哪行“当前有效”——这是收窄而非扩权，但会让“批准下界”出现多值歧义。
最小修订：改名为后缀 `code_source_freeze`（全名 `cr_execution_code_source_freeze`），唯一键改为 `UNIQUE(cr_id,repo_id)` + 单调 `approved_revision`（或保留现键并加 `is_current` 部分唯一索引）；响应加 `freeze_revision`。
归属：R2 草案本身。

**EC-5｜minor｜位置：L451 v0.6 版本行。**
问题：该行只记 R1 决策与 R4/R7 修，未记“R2/R3 草案入册（未复核）”与 R1 标题/括注的回收，后续读者会把 L480 节当成 v0.6 的额外附录而非版本内容；也未记 EC-1 的 13→14 计数影响。
最小修订：v0.6 行末补“同轮加入 R2/R3 合同草案（未复核、不得称已批准）；§4 计数按 R2 交付面在 13/14 间需同步，CLOSEOUT 与台账增量按该面记录”。
归属：记录性文字（其他章节，非 R2/R3 语义）。

## 可写测试 / 不可写测试的落点
R2 的“返回批准下界、拒调用方提供的实际 HEAD、未知仓库即拒”可写正反例（断言在 EC-3 决定交付面后即可固定）；EC-1/EC-4 修好后迁移三例的“14 表/唯一键”可写。R3 的四种情形本轮不判可测性（归 balanced），仅记录 R3 §3“转人工”、§4“先查远端”仍是未定义判定点，须 balanced 路给最小可测化要求，本条不计入 economy 的通过条件。

## 最小通过集合（解除 economy 对该节 BLOCK）
1. EC-1：§4 表计数与迁移三例的 13→14 同步（或按 EC-3 分支落 13），并入 R2 §1。
2. EC-3：merge-facts 交付面写成两条显式分支，含 §6 端点计数与状态码/closed-code 映射后果，并注明由人类决定。
3. EC-2：R1 标题改为“已决 (a)（决策记录）”，删/改 L510 的“按 source 区间”括注。
以上三条落盘后，R2 可转 PASS；EC-4、EC-5 为 minor，可同批修但不阻断。R3 无需修订即可通过 economy 路（其余风险交 strong/balanced）。

本章裁决：R2 INCOMPLETE
本章裁决：R3 BLOCK

读入：plan L488–562、L135/L160–161/L194–195/L326/L455（冻结 sha256 `04aacc…`，未复算）；对照 v0.6.1 CLOSEOUT 与 REVIEW-BALANCED。lane=balanced（requested Gobao/deepseek-flash max，actual unknown）；只读，未跑测试/DB、未编辑、未看其他 lane。

**总判断**：22 条 leaf 中 R2 有 10 条可直接写、R3 有 9 条可写；mutation 均为行为型（去锁/去索引/去重验/去远端核实/unknown 当 ok/problems 先判），`55P03` 属既定锁信号，未以崩溃或连接错充 RED。缺陷集中在 R3.5 两条 leaf 互斥、R3 码序不完整/无 leaf，以及 R2.5 缺 mutation 总则与 provenance 不符分支。

## 上轮 finding 闭合

| finding | 状态 | 依据 |
|---|---|---|
| STR61-01 | 部分 | R3.2 三态×远端表已补，leaf10/11 可写；但 leaf5 与之互斥（R3-01） |
| BAL-R2-08 / R2-N1 | 闭合 | L488 全名、L160 后缀、L326 精确 14；leaf3 有明确拒斥对象 |
| BAL-R2-09 | 闭合 | R2.4 增“CLI 本地下界校验”行；leaf4 正反例可写 |
| BAL-R2-10 | 闭合 | R2.3 增 `current_binding`/`head_revoked` 判据；leaf6 三态可构造 |
| BAL-R2-11 | 部分 | 原像已写死，但 leaf7 只钉“缺失”，漏“不符” |
| BAL-R2-12/13、R2-N2/N4 | 闭合 | 优先级措辞、403 归口、子码、摘要边界已落；余见 R2-03/04 |
| R2-N3 | 闭合 | leaf10/11 增补，行为型 mutation 可 RED |
| BAL-R3-06 | 未闭合 | 码序+NOT_FOUND 已加，但 `INVALID` 缺序、与 §6 冲突、零 leaf |
| BAL-R3-07 | 部分 | reason 全集与映射已加；`base_drift` 分流无判定方，`not_attempted` 未排除 |
| BAL-R3-08 | 部分 | 201/200/409 已定，但无 leaf 冻结，mutation 不可 RED |

## 新 finding

- **BAL62-R3-01 major｜R3.5 L560–561**：#5“远端未变须重新 reserve”与 #10“`unknown`+prev 不得重推、不得结算 no_effect”对同一可观测断言相反；同一夹具无法双绿。最小：#5 限定 `journal=intent`，#10 限定 `journal=unknown`。
- **BAL62-R3-02 major｜§6 L195 / R3.1 码序**：闭集 8 码含 `MERGE_EFFECT_INVALID`，码序只列 7 码；“PAT/JWT/task-token 一律 403 UNTRUSTED”与 `NOT_FOUND > UNTRUSTED` 在“他人 crID + PAT”冲突（404 vs 403）。R2 侧靠分桶隐含 403 优先，R3 无此兜底。最小：补 `INVALID` 位次；把 `UNTRUSTED` 置于 `NOT_FOUND` 前（并改“一律”措辞），或反之以 leaf 钉 404。
- **BAL62-R3-03 major｜R3.1 / R3.5**：本轮两处核心承诺无 leaf——attempt 三态（新 201/原字节 200/未终结 409）与“先判 head 再比 digest”（`HEAD_MOVED` 不被 `INPUT_MISMATCH` 遮盖）。mutation“重放也 201”“先比 digest”不使任何 leaf RED；`CONFLICT`/`NOT_FOUND`/`UNTRUSTED`/`INVALID` 四码无任何 leaf。最小：R3.5 增 2 条（共 13），或删除 201/200/409 承诺。
- **BAL62-R3-04 minor｜R3.3**：`base_drift`↔`input_mismatch` 依赖“仅 base 不同”，但 digest 不可逆、reserve 只回 `INPUT_MISMATCH`，未指定由 CLI 用预检分量比对；`settled_no_effect→publish_failed` 未排除 R3.2 的 `reason=not_attempted`。最小：补判定方一句 +“（not_attempted 除外）”，leaf7 断 reason 值。
- **BAL62-R2-01 major｜R2.5**：无 R3.5 式 mutation 总则，#1/#2/#3/#5/#7 未给 mutation；#7 只覆盖“缺失”，故“以自报 `provenance_digest` 为准”的 mutation 不会 RED（BAL-R2-11 半闭合）；未知 code/`400 INVALID` 亦无 leaf。最小：照 R3.5 加总则；#7 改“缺失或与目录记录不符”。
- **BAL62-R2-02 minor｜R2.5 #3**：宜写死第二条当前行取 `approved_revision+1` 且不 supersede，否则同 revision 会先被普通 UNIQUE 拒，删部分唯一索引的 mutation 不 RED。
- **BAL62-R2-03 minor｜R2.4 末行**：“200 或 404”混合缺行/revoked/计数/集合/摘要/provenance/problems 六条件，端点级反例无唯一 status oracle；leaf5/6/7 实际只断 CLI 外层码。最小：逐条件定码，或声明 leaf 只断外层码。
- **BAL62-R2-04 minor｜R2.4 优先级**：“`UNAVAILABLE` 与 `VIOLATION` 不并存”依赖本地不缓存 allowed_paths；恢复路径复用预检事实时该前提未写死。最小：一句“grant 派生字段每次重读、不落 journal”。

**最小通过集合**：R3-01/02/03 必修（leaf 集与码面冻结前），R2-01 必修；其余一句可修。未重开 R1=(a)、Q8 交付面；41/49、Gate NO-GO、M003 proposed 不变。

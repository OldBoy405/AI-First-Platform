本章裁决：R2 INCOMPLETE
本章裁决：R3 INCOMPLETE

读入：`inputs/plan.md` L487–550、L135/L160/L194–195/L454（按冻结 SHA 给定，未复算）；对照上轮 CLOSEOUT Q1–Q13 与 REVIEW-BALANCED。未编辑、未跑命令/DB、未看其他 lane。lane=balanced（requested Gobao/deepseek-flash max，actual unknown）。

**总判断**：Q1 类“同条件两码”已消失；18 条 leaf 全部具备可写形状，13 条现即可写正反例，5 条需一行修订。所有 mutation 均为行为型（去锁/去重验/去远端核实/去摘要比对/unknown 当 ok/problems 先判/删索引），不依赖崩溃或超时；`55P03` 探针属既定锁信号，合规。

## Q1–Q13 闭合

| Q | 状态 | 依据 |
|---|---|---|
| Q1 | closed | R2.4 三档定码，§3 L135 改为引用唯一权威 |
| Q2 | closed | 固定“祖先下界”；追加写+部分唯一，单当前行，缺行/多行即缺失 |
| Q3 | closed | `expected_repo_count`/`repos_digest`/`current_binding` 三态入闭集 |
| Q4 | closed | workspace 由主体解析、只带 crID、跨库 404、禁调用方目标/版本参数 |
| Q5 | closed | 条件→响应码→CLI 码表+优先级；措辞/覆盖见 R2-12 |
| Q6 | closed | `provenance_digest` 入闭集，缺失/不符按事实缺失，不降 legacy |
| Q7 | closed | §4 14 表、同迁移；表名两写为新增 R2-08 |
| Q8 | closed | 用户定随本 change；§6 3→5；R3 码面缺项见 R3-06 |
| Q9 | closed | reserve 提交=排序点、Tx 外 push、report=确认点；锁序归 strong |
| Q10 | closed | intent/unknown/confirmed + ls-remote 三分支 + 禁新 publish；再 reserve 语义见 R3-08 |
| Q11 | partial | 中止字段/receipt 不改/唯一入口已定；reason 枚举缺项、无码→reason 映射（R3-07） |
| Q12 | closed | 三态矩阵 + `input_digest`（含 trunk/base/candidate/授权）+ finalize 行 |
| Q13 | partial | 撤销提交点仍为析取“head 变更或 grant 撤销记录”，非单一可见谓词（R3-09） |

## 新 finding

- **BAL-R2-08 major｜R2.1 vs §4 L160**：表名两写 `cr_execution_code_source_freeze` / `code_source_freeze`，leaf #3（索引拒绝）与迁移/名册断言二选一。最小：统一用 §4 精确名（或改 §4 行）。归属 R2/§4。
- **BAL-R2-09 major｜R2.4 表 vs leaf #4**：表自称唯一权威却无“非祖先”行，leaf 断言的 `UNVERIFIABLE` 在表内无出处；该检查在 CLI（端点不见候选 HEAD）。最小：加一行“本地下界校验失败→`AUTH_SCOPE_UNVERIFIABLE`”，注明判定侧。归属 R2。
- **BAL-R2-10 major｜R2.3**：`current_binding=unknown` 无生成判据（何表何状态算 unknown/mismatch），服务端反例只能打桩；`head_revoked` 指当前 head 也未写死。最小：定义“无绑定行/身份摘要不可得→unknown；identity_digest 冲突→mismatch”，同 RR 事务按 repo_id 读。归属 R2。
- **BAL-R2-11 minor｜R2.3**：`provenance_digest` 原像未定义，leaf #7“不符”分支与 mutation 无独立 oracle。最小：仿 `repos_digest` 写死字段与排序。归属 R2。
- **BAL-R2-12 minor｜R2.4 末句 vs 优先级**：`UNAVAILABLE>…>VIOLATION` 与“已知越界永远输出 `VIOLATION`”在“端点不可达+本地越界”下两种读法；leaf #8 只钉 VIOLATION>UNVERIFIABLE。最小：把“永远”限定为“与 UNVERIFIABLE 之间”，并补一支 UNAVAILABLE+VIOLATION 夹具或明示排除。归属 R2。
- **BAL-R2-13 minor｜§6 L194/leaf #2**：认证被拒只由 §3 归 UNAVAILABLE，未见“一律 403 `MERGE_FACTS_UNTRUSTED`”，PAT/JWT/task-token 反例的 status 断言靠猜。最小：补一句。归属 R2/§6。
- **BAL-R3-06 major｜§6 L195/R3.1**：`MERGE_EFFECT_*` 无优先级；`authorization_head_id` 又在 `input_digest` 内，head 前移同时构成 HEAD_MOVED 与 INPUT_MISMATCH，HEAD_MOVED 可能永不可达；闭集还缺跨库/不存在 crID 的 NOT_FOUND 类码。最小：给码序（REVOKED>HEAD_MOVED>INPUT_MISMATCH>CONFLICT>UNAVAILABLE）、把 head/grant 移出摘要或声明先查 head、补 NOT_FOUND。归属 R3/§6。
- **BAL-R3-07 major｜R3.3/R3.4**：`halted.reason∈{revoked,head_moved,base_drift,uncertain}` 无法表示“非 base 的输入不等”与“可判定失败的 push（settled_no_effect 后）”；无 reserve/report 码→reason→CR 状态映射，leaf #7 仅覆盖 base_drift。最小：加 `input_mismatch`、`publish_failed` 及四行映射。归属 R3。
- **BAL-R3-08 major｜R3.2/leaf #5**：“同 effect_id 重新 reserve”未定服务端语义（旧 command 仍 issued 时是 200 重放、201 新命令还是 409？是否重跑重验）。leaf 只能断言“发生过 reserve”，响应/状态不可断言。最小：定义“同 effect 新尝试=attempt+1 新命令，或重放必重验”，并写返回码。归属 R3。
- **BAL-R3-09 minor｜R3.1（Q13）**：提交点仍是“head 变更或 grant 撤销记录可见”析取，未落到唯一谓词（R2.1 的 `revoked_at` 反而未被引用）。最小：以“当前行/授权 grant 的 `revoked_at IS NOT NULL` 在另一连接可见”为唯一标识；交错夹具本身可用。归属 R3。

**仍不可写（当前）**：unknown 判据、provenance 原像、同 effect_id 再 reserve 语义、merge-effects 码序/缺 NOT_FOUND、halted reason 与码映射、撤销提交点单一标识。另：18 条与 S5“19 条”的总数关系未写，建议 economy 核，不计入本节。

## 最小通过集合

1. R2：R2-08（一名）、R2-09（一行码）、R2-10（一句判据）→ 9/9 leaf 可冻结；R2-11/12/13 各一句，非阻断。
2. R3：R3-06（码序+NOT_FOUND）、R3-07（reason/映射）、R3-08（再 reserve 语义）→ 9/9 leaf 与码面可测；R3-09 收 Q13。
3. 未重开：R1=(a)、Q8 交付面、merge-effects 替代方案（不主张“只读重验”）。41/49、Gate NO-GO、M003 proposed 不变。

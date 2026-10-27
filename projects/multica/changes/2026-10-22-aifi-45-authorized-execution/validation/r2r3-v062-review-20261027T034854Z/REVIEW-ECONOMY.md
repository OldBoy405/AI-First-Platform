本章裁决：R2 PASS
本章裁决：R3 BLOCK

**上轮 finding 闭合表（economy 轴，逐行）**

| 项 | 结论 |
|---|---|
| STR61-01（push 前持久 unknown；状态×远端表） | 闭合：R3.2 三行俱全；`intent`→先 `not_attempted` 再 `attempt+1`（L548）；`unknown`+prev 保持 uncertain 且不结算 no_effect |
| BAL-R2-08/R2-N1 表名双写 | 闭合：DB 全名 `cr_execution_code_source_freeze`（L492、L455、L326），§4 仅后缀（L160 与表头「均以 `cr_execution_` 开头」自洽） |
| BAL-R3-09/R3-N1/Q13 撤销谓词单一 | 闭合：R2.1 唯一谓词＝当前行 `revoked_at IS NOT NULL` 可见；R2.3 `head_revoked`、R3.1 排序/夹具均只认该谓词，head 前移另判 HEAD_MOVED |
| BAL-R2-09 非祖先无码出处 | 闭合（R2.4 第 5 行 → UNVERIFIABLE） |
| BAL-R2-10/11 三判据 | 闭合（R2.3 current_binding/head_revoked/provenance_digest 各一条） |
| BAL-R2-12/13、R2-N2/N4 | 闭合（优先级句、403 归口、子码非外层码、`repos_digest` 边界） |
| R2-N3 REVOKED/HEAD_MOVED 无 leaf | 闭合（R2.5 共 11 条，实测计数 11） |
| BAL-R3-06 merge-effects 码序 | 闭合：R3.1 `NOT_FOUND>INVALID?`…>UNAVAILABLE，先判撤销/head 再比 `input_digest`；§6 补 `NOT_FOUND` |
| BAL-R3-07 halted reason 映射 | **未完全闭合**（见 R3-N1） |
| BAL-R3-08 再 reserve 语义 | 闭合（201/200/409，attempt 单调） |

一致计数：14 表（8+5+1，L161/L326/L492 三处一致）、5 端点（L194 实测 5）、11+11 leaf（L525/L561 实测各 11）、§6 merge-facts 5 码与 R2.4 互指一致、§3 五外层码与 R2.4 表一致、`workspace_revision` 已无残留参数表述。

**新 finding**

1. R3-N1（minor，L552）：halted `reason` 闭集 6 值，但 reserve 的 `NOT_FOUND`/`UNTRUSTED`/`INVALID`/`CONFLICT`/`UNAVAILABLE` 无归口，中止时 reason 无值可写。最小修订：加一句「reserve 失败于上述码时按 `uncertain` 记 halted（或声明不写 halted、仅报错退出）」。
2. R3-N2（minor，L536 vs L195）：§6 闭集 8 码含 `INVALID`，R3.1 码序只列 7 码。最小修订：码序前置「`INVALID` 在解析层先判」。
3. R2-N5（minor，L493/L160）：部分唯一索引未写列，未固定为 `UNIQUE(workspace_id,cr_id,repo_id) WHERE superseded_at IS NULL`；按现文可实现成 4 元组，使「每仓至多一条当前行」与 leaf「构造两条当前行被拒」不可测。最小修订：显式写出列。
4. nits：L161 计数句仍用裸后缀（在 §4 后缀约定内，非双写）；R3.2「其他（后继/分叉/改写）→同左」把合法后继也标 history rewrite，建议改称「未含 expected → uncertain、转人工」；§3 L135 仍写「v0.6.1 节 R2.4」。

未重开已定事项；M003 proposed、41/49、Gate NO-GO 不变。未编辑、未跑测试/DB。

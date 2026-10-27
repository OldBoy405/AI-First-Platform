# v0.6.2 R2/R3 复核结果与 v0.6.3 处置

## 结论（冻结 plan SHA256 `04aacc…3d09`；三路一次完成无中断）

| 轴 | R2 | R3 |
|---|---|---|
| strong `01a17b79-e5f7-…` | **PASS** | BLOCK |
| balanced `01a17b79-e607-…` | INCOMPLETE | BLOCK |
| economy `01a17b79-e613-…` | **PASS** | BLOCK |

v0.6.1 的 finding 三路基本判闭合（STR61-01、表名、撤销谓词、判据、码行等）。合并：R2 未全过（balanced 要求 leaf 逐条给 mutation），R3 BLOCK。

## 新问题 → v0.6.3 落点（作者已修，未复核）

| 来源 | 问题 | v0.6.3 落点 |
|---|---|---|
| STR62-01 / economy nit | “其他”把远端正常前进误判为改写/分叉，与 `classifyRemoteCommit` 祖先判定不一致 | R3.2 改按 `merge-base --is-ancestor` 分“含 expected / == prev / 其他”；R3.5 #4、#16 |
| STR62-02 | 缺服务端 `settled_no_effect` 恢复格 | 服务端终态优先；新增该行：== prev → attempt+1；R3.5 #12 |
| BAL62-R3-01 | R3.5 #5 与 #10 互斥 | #5 限 `intent`，#10 限 `unknown` 且无终态 |
| BAL62-R3-02 / R3-N2 | 码序缺 INVALID；PAT+他人 crID 403/404 冲突 | 码序 `INVALID > UNTRUSTED > NOT_FOUND > …`，merge-facts 同序 |
| BAL62-R3-03 | attempt 语义、head 先判、四码无 leaf | R3.5 #13–#15 |
| BAL62-R3-04 | base_drift 判定方、not_attempted | CLI 逐项比对预检分量；publish_failed 排除 not_attempted |
| R3-N1（economy） | reserve 非授权类失败无 reason | 不写 halted、非零退出、journal 不变；CONFLICT → uncertain |
| BAL62-R2-01/02 | R2.5 缺 mutation 总则/逐条 mutation；#7 漏“不符”；#3 构造不明 | R2.5 改为编号列表逐条 mutation + 总则；#7 缺失/不符两支；#3 写明 revision+1 不 supersede |
| BAL62-R2-03/04 | “200 或 404”无唯一 oracle；不并存前提未写死 | 404 单独成行；grant 派生字段每次重读、journal 只记摘要 |
| R2-N5 | 部分唯一索引未写列 | `UNIQUE(workspace_id,cr_id,repo_id) WHERE superseded_at IS NULL`（R2.1 与 §4 行） |

## 效力
v0.6.3 未复核，不继承 R2 的两路 PASS。已定事项未重开。M003 proposed；41/49、Gate NO-GO、M001/M002/M003 unresolved、原库 HOLD 不变。

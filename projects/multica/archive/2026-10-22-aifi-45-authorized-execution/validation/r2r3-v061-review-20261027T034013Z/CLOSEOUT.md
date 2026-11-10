# v0.6.1 R2/R3 复核结果与 v0.6.2 处置

## 结论（冻结 plan SHA256 `1b63d777…842821`）

| 轴 | R2 | R3 |
|---|---|---|
| strong `01a17b72-3cb5-…` | **PASS**（合同轴） | **BLOCK** |
| balanced `01a17b72-3cda-…` | INCOMPLETE | INCOMPLETE |
| economy `01a17b72-3cc9-…` | BLOCK（表名双写） | INCOMPLETE（Q13） |

三路均一次完成、无中断；只读静态复核。合并仍为 **R2 未通过 / R3 未通过**，但上一轮 Q1–Q13 中 Q1–Q9、Q12 三路一致判 closed，剩余均为可单点修订项。

## 剩余问题 → v0.6.2 落点（作者已修，未复核）

| 来源 | 问题 | v0.6.2 落点 |
|---|---|---|
| STR61-01（blocker） | `ls-remote == prev_sha` 不能证明旧 push 未在途；`confirmed` 后回退到 prev 被误当可重推 | R3.2：push 前先持久 `unknown`；状态×远端表（`unknown`+prev 保持 uncertain，`confirmed`+prev 判 history rewrite，`intent`+prev 先结算 not_attempted 再 attempt+1）；R3.5 加 2 条 leaf |
| BAL-R2-08 / R2-N1 | 表名双写 | DB 全名 `cr_execution_code_source_freeze`；§4 表格只列后缀；`ChannelTableNames` 登记全名 |
| BAL-R3-09 / R3-N1 / Q13 | 撤销提交点非单一谓词 | 唯一谓词＝当前冻结行 `revoked_at IS NOT NULL` 在另一连接可见；head 前移另判 HEAD_MOVED |
| BAL-R2-09 | 非祖先无码出处 | R2.4 增“CLI 侧本地下界校验失败 → UNVERIFIABLE”行 |
| BAL-R2-10/11 | `current_binding`/`head_revoked`/`provenance_digest` 无判据 | R2.3 三条判据 |
| BAL-R2-12/13、R2-N2/N4 | 优先级措辞、403 归口、子码、摘要边界 | R2.4/R2.3/§6 各一句 |
| R2-N3 | REVOKED/HEAD_MOVED 无 leaf | R2.5 加 2 条（共 11） |
| BAL-R3-06 | merge-effects 无码序、缺 NOT_FOUND、HEAD_MOVED 可能被 INPUT_MISMATCH 遮盖 | R3.1 码序 + 先判撤销与 head 再比 `input_digest`；§6 加 `NOT_FOUND` |
| BAL-R3-07 | halted reason 不全、无映射 | R3.3 加 `input_mismatch`/`publish_failed` 与码→reason 映射 |
| BAL-R3-08 | 同 effect_id 再 reserve 语义未定 | R3.1 attempt 语义：新 attempt 201、原字节重放 200、前次未终结 409 |

## 效力
- v0.6.2 为作者修订，**未复核**，不继承本轮任何 PASS。
- 已定事项未重开：R1=(a)、Q8 端点随 change 交付、R3 写端点（兑现 §4 已定撤销语义）。
- M003 proposed；41/49、Gate NO-GO、M001/M002/M003 unresolved、原库 HOLD 不变。

# v0.6.4 R2/R3 复核结果与 v0.6.5 处置

## 结论（冻结 plan SHA256 `4ab2b18c…27080f`；三路一次完成无中断）

| 轴 | R2 | R3 |
|---|---|---|
| strong `01a17b85-6ea7-…` | **PASS** | **PASS** |
| balanced `01a17b85-6ec3-…` | INCOMPLETE | **PASS** |
| economy `01a17b85-6eb7-…` | **PASS** | **PASS** |

**R3 三路 PASS（针对 v0.6.4）**。R2 只剩一处实质缺口 BAL64-R2-01；其余均为 nit。

## v0.6.5 落点（作者已修，未复核）

| 来源 | v0.6.5 落点 |
|---|---|
| BAL64-R2-01（major） | R2.5 #5 补“同计数替换 repo_id”支；mutation 分列“跳过集合比较”“只比计数不校摘要” |
| BAL64-R2-02 / ECON64-01 | #1 补外层 UNVERIFIABLE，#2 补外层 UNAVAILABLE |
| BAL64-R2-03 | `head_revoked` 定为全部当前行已撤销；仅部分仓撤销 = 事实不一致 → UNVERIFIABLE |
| BAL64-R3-01 / ECON64-03 | #9 夹具限 base 与授权 head 均不变、只改候选 HEAD |
| BAL64-R3-02 | #13 写明 reason 记在 journal，409 body 不含 reason |
| BAL64-R3-03 | #15 写明 400 支只断端点 |
| ECON64-02 | R3.4 部分发布格拆 base_drift / input_mismatch |
| ECON64-04 | R3.1 与 #13 补“前 attempt 已 settled_effect → 200 原 mapping、无新 command” |
| ECON64-05 | §7 生命周期测试 13→14 |

## 效力
v0.6.5 改动了 R3 文本（R3.1/R3.4/#9/#13/#15），因此 **R3 的三路 PASS 不继承**，须与 R2 一起重审。M003 proposed；41/49、Gate NO-GO、M001/M002/M003 unresolved、原库 HOLD 不变。

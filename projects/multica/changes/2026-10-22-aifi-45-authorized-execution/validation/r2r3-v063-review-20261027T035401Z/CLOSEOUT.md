# v0.6.3 R2/R3 复核结果与 v0.6.4 处置

## 结论（冻结 plan SHA256 `ce169404…6e18`；三路一次完成无中断）

| 轴 | R2 | R3 |
|---|---|---|
| strong `01a17b7e-9499-…` | **PASS** | **PASS** |
| balanced `01a17b7e-94b6-…` | INCOMPLETE | BLOCK |
| economy `01a17b7e-94aa-…` | **PASS** | **PASS** |

合同轴（strong）与一致性轴（economy）均无新阻断；剩余问题全部在 leaf 可测性层（balanced）。合并仍判未通过。

## 剩余 → v0.6.4 落点（作者已修，未复核）

| 来源 | 问题 | v0.6.4 落点 |
|---|---|---|
| BAL63-R2-01 | #4 只有非祖先负例，“精确相等” mutation 不 RED | 补严格祖先正例 + 区间负例，三种 mutation 各对应一支 |
| BAL63-R2-02 | #1 mutation 不可执行、未限合法 MDT | 限合法 MDT；mutation 改为“按 CR 行 workspace 返回、跳过主体比对” |
| BAL63-R3-01 | #7/#9 同一 base 漂移夹具互斥 | #7 只改 base；#9 只改非 base 分量 |
| BAL63-R3-02 / ECON63-01 | 503 不写 halted 无 leaf | #15 增 503 支并断言不写 halted |
| BAL63-R3-03 | 201/200/409 适用面重叠 | R3.1 与 #13 改为三情形互斥 |
| ECON63-02 | `confirmed` 而服务端无终态未定义 | 写明属事实不一致 → uncertain；首行改为服务端 `settled_effect` |

## 效力
v0.6.4 未复核，不继承本轮 PASS。leaf 数不变（11+16）。M003 proposed；41/49、Gate NO-GO、M001/M002/M003 unresolved、原库 HOLD 不变。

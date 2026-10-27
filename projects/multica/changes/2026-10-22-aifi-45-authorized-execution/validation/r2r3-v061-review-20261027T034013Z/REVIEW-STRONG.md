本章裁决：R2 PASS（strong 合同轴）
本章裁决：R3 BLOCK

仅只读指定行及 tools 符号片段；未编辑、未跑命令/测试/DB、未委派。requested：OpenAIPersonal/gpt-6.1-sol high；actual：unknown。以下 closed 不代表实现或测试已通过。

### Q1–Q13 闭合表

| Q | 状态 | 依据 |
|---|---|---|
| Q1 | closed | R2.4 唯一权威，§3 已引用 |
| Q2 | closed | 固定祖先下界；追加版本、当前行唯一 |
| Q3 | closed | 仓库计数/集合/摘要与绑定三态已补 |
| Q4 | closed | 认证主体解析 workspace；删除 revision 参数 |
| Q5 | closed | 外层码映射与多错优先级明确 |
| Q6 | closed | legacy 证明摘要必填，缺失不降级 |
| Q7 | closed | 指定联动行已统一 14 表及迁移测试范围 |
| Q8 | closed | 端点随 change 交付；§6 已归口 |
| Q9 | closed | reserve 提交排序、CR 锁互斥、Tx 外 push 明确 |
| Q10 | partial | 三分支有定义，但 `prev_sha` 不能证明“未发布” |
| Q11 | closed | CR 状态、中止字段、恢复入口与拒绝条件明确 |
| Q12 | closed | 三类恢复矩阵、新授权限制及 finalize 已明确 |
| Q13 | closed | 撤销提交可见标识与交错钩位明确 |

**锁序判断**：R3.1 引用 §4 完整锁序，未引入显式逆序。CR `FOR SHARE` 与撤销 `FOR UPDATE` 互斥；“不等待 command slot”不等于“不等待 CR 行锁”，二者不矛盾。

### 新 finding

**STR61-01｜BLOCK｜`inputs/plan.md` L534–538（R3.2）｜归属：R3 恢复合同 / tools、merge-effects**

`ls-remote == prev_sha` 只证明查询时引用尚未改变，不能证明旧 push 没有在途，也不能证明历史上未发布。

反例：reserve 先提交，push 已发出但远端尚未更新；CLI 崩溃，随后撤销提交；恢复读到 `prev_sha`，按现稿重新 reserve 并结算 `settled_no_effect`；旧远端请求随后完成，形成“已结算无 effect，但实际已发布”。这不是撤销追溯问题，而是错误认定零 effect。

另一个边界：已 `confirmed/settled_effect` 后远端被重置到 `prev_sha`，同一分支会要求重新 reserve。既有 `workspace-transactions.mjs::classifyRemoteCommit` L556–560 则把“曾发布、现不含该提交”识别为 history rewrite，不能退回可重推。

**最小修订**：
- 发出 push 前持久化 `unknown`。
- 恢复先结合 journal/服务端终态，再分类远端 SHA。
- 对可能在途的旧 push，读到 `prev_sha` 仍保持 `uncertain`；没有旧尝试终止或远端 fencing 证据，不得重推或结算 no_effect。
- 已结算 effect 不重发；回退/改写冻结转人工。finalize 同样适用。

### 最小通过集合

修正上述状态×远端判定矩阵，补“旧 push 延迟完成”和“已确认后回退至 prev”两类反例 leaf，再冻结复核即可。无需重开 R1/Q8 或改判撤销语义；事实可信≠执行强制的残余风险保留。M003 proposed、41/49、Gate NO-GO 及 M001/M002/M003 unresolved 不变。

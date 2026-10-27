本章裁决：R2 INCOMPLETE
本章裁决：R3 BLOCK

lane=balanced（requested Gobao/deepseek-flash max；actual unknown）。仅读 brief 指定行及上轮 CLOSEOUT/REVIEW-BALANCED；sha256 复算为 `ce1694…6e18`；未编辑、未跑测试/DB、未委派、未看本轮他 lane。

**上轮 finding 闭合**

| finding | 状态 | 依据 |
|---|---|---|
| STR62-01/02 | 闭合 | R3.2 祖先三分支；`settled_no_effect` 行/#12 |
| BAL62-R3-01 | 闭合 | #5 限 `intent`、#10 限 `unknown` |
| BAL62-R3-02 | 闭合 | `INVALID` 置首、`UNTRUSTED` 先于 `NOT_FOUND`；#15 |
| BAL62-R3-03 | 闭合 | #13–#15 覆盖 attempt/head/三码；`UNAVAILABLE` 见新 |
| BAL62-R3-04 | 闭合 | CLI 逐项比对、`not_attempted` 排除；#7 断 reason（#7/#9 见新） |
| BAL62-R2-01/02 | 闭合 | 逐条 mutation+总则；#3 `revision+1` 不 supersede（#4/#1 见新） |
| BAL62-R2-03/04 | 闭合 | 404 单行、5–7 只断外层；grant 每次重读、journal 只摘要 |

**新 finding**

- **BAL63-R2-01 major｜R2.5 #4**：只写“非祖先”负例，未写“严格祖先（落后于 candidate HEAD）放行”及“祖先但不在 `trunk...candidate` 拒绝”；mutation“改为精确相等”仍全绿。最小：补上述正例与区间负例。
- **BAL63-R2-02 minor｜R2.5 #1**：mutation“按请求参数解析 workspace”不可执行（请求只带 crID，未知参数应 400）；404 亦未限定“合法 MDT”，与 #2 的 PAT→403、§6“一律 403”字面冲突。最小：删该 mutation 分支或改为“按 CR 行 workspace 返回、跳过主体比对”；leaf 加“合法 MDT 凭据”。
- **BAL63-R3-01 major｜R3.5 #7/#9、R3.3**：`input_digest` 含 base；base 漂移同一夹具下 #7 要 `reason=base_drift`、#9 要 `reason=input_mismatch`，互斥。最小：#9 限定“非 base 分量不同（且部分发布）”，#7 专测 base。
- **BAL63-R3-02 major｜R3.5 #15、R3.3**：R3.3 的 no-halted 四码含 `UNAVAILABLE`，#15 只测 `INVALID/UNTRUSTED/NOT_FOUND`；503 无 leaf，mutation 写 halted 不 RED。最小：#15 增 503 子例或 #17。
- **BAL63-R3-03 minor｜R3.5 #13、R3.1**：“新 attempt→201”未限定；与“前次未终结→409”及同 attempt 重放→200 重叠。最小：201 仅限无未终结前 attempt；200 仅限同 attempt 原字节；409 仅限新 attempt。

**最小通过集**：R2-01、R3-01/02 必修（或 #9 限非 base、#15 加 503）；R2-02、R3-03 一句可修。R2 的 11 条正反例/mutation 大体可写；R3 的 16 条因 #7/#9 不能同时双绿。未重开 R1=(a)、Q8、41/49、Gate NO-GO、M003 proposed。

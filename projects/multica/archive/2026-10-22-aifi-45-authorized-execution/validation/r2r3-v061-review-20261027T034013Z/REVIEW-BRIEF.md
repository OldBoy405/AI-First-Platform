# v0.6.1 R2/R3 合同稿复核

## 对象与冻结
- cwd：`C:/Users/GOBAO/Downloads/AI/AI First Platform`。
- 被审：本目录 `inputs/plan.md`（SHA256 `1b63d777aef552be2f569feea5a4e25d7c846949fd50dc6c133103c8ae842821`）。
- **只读这些行**（行号见 `source-manifest.json#line_map`）：R2 合同 L487–522、R3 合同 L523–550；联动处 §3 失败码闭集 L135、§4 新表行 L160 及其后计数行、§6 端点 L194–195、修订表 v0.6.1 行 L454。其余章节不重新裁决。**不要通读全文件。**
- 上一轮复核与阻断编号：`../r2r3-review-20261027T015105Z/CLOSEOUT.md`（Q1–Q13）。本轮核心问题：**每个 Q 是否已在 v0.6.1 闭合**，以及改写是否引入新矛盾。
- multica 源码正被其他工作改动，不是冻结输入。

## 已定事项（不得重开）
- R1=(a)；Q8 已由用户定为 `merge-facts` 端点随本 change 交付、删除 `workspace_revision`、“事实可信≠执行强制”入残余风险。
- R3 新增的 `merge-effects` 写端点是为兑现 §4 已定撤销语义（effect 先提交不追溯、revoke 先提交 → no_effect）。若你认为应改用“只读重验、撤销非即时”，请标为“需人类决策”，不要自行改判。
- M003 仍 proposed；41/49、Gate NO-GO、M001/M002/M003 unresolved 不变。

## 边界
新鲜非作者、独立只读；不编辑文件、不跑 DB/测试、不委派、不读其他 lane。不把“未实现”当缺陷（M003 是 proposed）。

## 分工
- **strong**：R2.1–R2.4、R3.1–R3.4 是否仍有竞态或 agent 自选面；特别核 reserve 事务的锁序是否与 §4 L166 锁序一致、撤销“不等待 command slot”与“等待 CR 行锁”是否矛盾；恢复三分支是否闭合；可读 tools `crctl.mjs`、`lib/workspace-transactions.mjs` 按符号定位核引用。
- **balanced**：R2.5、R3.5 共 18 条 leaf 能否各写正反例与有效 mutation；仍不可写的表述；失败码优先级是否可测。
- **economy**：Q1–Q13 逐条闭合状态表；§3/§4/§6/修订表与 R2/R3 的计数、名称、引用一致性；有无残留 `workspace_revision`、“13 张”、“未定交付面”。

## 返回
首两行 `本章裁决：R2 …`、`本章裁决：R3 …`（PASS/BLOCK/INCOMPLETE）；Q1–Q13 闭合表（closed/partial/open，一行一条）；新 finding 给 ID/severity/位置/最小修订/归属；最后最小通过集合。约 1500 中文以内，不写文件。

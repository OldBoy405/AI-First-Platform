# TC-RUN-003 第四轮复核与后续处置

## 原始输入与报告

- 冻结输入是 `source-manifest.json`：multica `a929e4438db069cdaf672f53dfcb23d3f11a3c12`，范围 `6eb5b7f7f..a929e4438`，工作区 `8486a0e3e82719ff2d51c9d494d3bd1e119637d9`。该文件保持原样，不能改写为后续版本。
- `REVIEW-STRONG.md`、`REVIEW-BALANCED.md`、`REVIEW-ECONOMY.md` 由对应本地会话的最后一条 assistant 文本原样提取；`REVIEW-RECEIPTS.json` 保存 session、消息 ID、原会话和导出文本的 SHA-256，以及会话消息记载的 provider/model/effort。它是会话记录，不冒称另有后端回执。三个导出文件已与 receipt 哈希复核一致。
- 冻结清单的六个文档中，处置后覆盖台账、canonical agent CP 和测试方案已改变；disposition、历史设计稿、canonical code spec 与冻结哈希仍一致。修复后的文件不能冒充第四轮当时的输入，须另留当前源码快照并重新复核。

## 原裁决及处置

| lane | 原裁决 | 作者处置（均待独立复核） |
|---|---|---|
| strong | BLOCK | 已绑定签名 request/epoch/seq，现又绑定 prev；补伪签拒绝、真实 writer→Admission→Runner 正控。桥接中的 consumption/settlement 仍是夹具，不能声称生产全链。 |
| balanced | INCOMPLETE | nil manifest 已隔离；requirement 增真实 TaskService/任务身份和变异；四条 governance 补充 CP 已列入 canonical；registry 自适应范围与 generator `--check` 的局限已更正。 |
| economy | INCOMPLETE | 作者修正已见的文档问题，但其未读的交叉核对并未自动变成独立 PASS。 |

## 当前限制

- Node store 的 frame body digest、Go writer 的 payload digest、验签器的域分离 digest 不同，不能声称已跨语言对齐；生产签发/摄取与受保护密钥隔离尚待实现和验证。
- `ApplyControlCommandTx` 的完整验签、可信主体 B 绑定及重放一致性尚未验收；相关生产使用不可依赖 verdict 验签替代。
- Gate3 人工批准前不在 `main.go` 启用 AdmissionDecider，producer/ingest 与判定器须同批审批及接线。用户同意现在开发不等于正式批准；未 push、部署或操作真实 CR。
- TC-RUN-003 暂不记 PRESENT，台账仍 44/49；Gate3 仍 NO-GO。已完成的测试与变异证据详见 `../tc-coverage-20261025T153000Z.md` 增量 84，需冻结修复后源码并进行独立复核。

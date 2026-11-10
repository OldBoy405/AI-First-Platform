# settlement 授权头缺失：静态边界与修复前提

**结论：可确证的局部 fail-open；尚未证明生产越权链可达或业务效果已发生。** 仅源码静态分析；没有运行 CLI、Git、DB、测试或访问受保护资源，不改变现有授权/终态合同。

## 可复核事实

- `server/internal/governance/execution_control_settlement.go#SettleControlCommandTx` 先校验输入形态；有效输入遇已有 settlement 才返回原 mapping。新请求锁 command 后调用 `controlAuthorizationRevoked`；仅 `true` 时把传入的 effect 改成 no_effect。
- `controlAuthorizationRevoked` 连接 command → reservation → selection → CR，LEFT JOIN 同 workspace/CR 的当前 approval head。内连接任一环断链时 `pgx.ErrNoRows` 返回 `false,nil`；head 空、悬空或跨 scope 时 decision 为 NULL，亦返回 `false,nil`；非 `reject` 的值同样为 false。上层因此保留传入的 effect 并继续尝试结算，但能否成功仍受 command 状态及后续 transition 等约束：`issued` 虽通过入口检查，后续状态机拒绝其直接转 settled，调用者须回滚。迁移 433 对正常 approval decision 约束为非空 `approve/reject`；其他值是 fake、损坏或约束变化的防御性情形，不作为正常数据库现状。**这证明的是缺失事实被当作未撤销，不证明 caller 的 permit、业务效果或生产可达性。**
- 迁移 648 明示关系由应用验证而不建 FK；642 中 head 可空，不能依 schema 推定整链必有。既有 `execution_admission.go` 对有头且 decision `approve` 的新准入另做判断，但该 component 当前也不等于完整可信生产授权。
- 唯一非测试直接 caller 是 `execution_channel_reader.go#SettleCandidateTx`，本轮静态扫描未发现它的非测试调用；不据此排除动态/外部调用。`execution_channel_admission.go` 中 root → task → settlement 同事务的另一源码写入口不调用该函数；静态未见其非测试调用，不能把它称为已接线生产路径或声称已修复。
- 本函数本身不提交或回滚调用者的事务，也不执行外部效果。调用者必须回滚同事务中的效果；不能推断外部效果随 DB 回滚而消失。

## 不可误用的修法

不能把未知链统一当成 `revoked=true`：现逻辑会把 effect 改写为 no_effect 并释放槽位，可能把未知或已发生的外部效果伪造为无效果。仅当有权威事实证明 effect 未发生、且结算合同允许时才可认定 no_effect；本 helper 的未知不能直接伪造 no_effect 或盲目重做；恢复应按适用合同分别判定。归档 SC-MG-015/016 另有可证明远端状态下不重推并成功结算、或特定条件下结算旧 attempt 后重新 reserve 的正例，本段不取代它们。有效输入下已提交 mapping 的幂等重放与已授权工作合法有界收尾须单独保留，不能因新准入约束一刀切阻断。

`execution_contract_selection.go` 明确 persisted legacy mode 本身不足以证明 legacy，还需解析部署 pin 的可信目录；不可用 caller 自报、空 head 或 mode 字符串取代。严格 selection 的新 effect 与经可信历史证明的 legacy / 原有工作收尾必须分开。当前函数先锁 command，不能未经锁序设计就在其后加 CR/head 锁并宣称闭合撤销竞态。

## 可推进的最小测试设计（未执行）

先核定可信身份与 legacy/closeout 合同；在独立子包引入真实 production package，以 fake `pgx.Tx`/`Row` 对真实 `SettleCandidateTx`/`SettleControlCommandTx` 测试，而不调用父包的 DB TestMain。预检 Go 工具链、编译传递 import/init、缓存与网络、环境、临时路径和清理；禁止连接事故数据库。模拟无链、NULL/跨 scope、查询失败，以及防御性的无效 decision，断言未知 effect 在 INSERT/transition 前拒绝而不是伪造 no_effect；检查错误情况下 caller 不提交模拟效果。分别保留已提交 mapping 重放、经过可信来源证明的 legacy 正例、真实允许的 no_effect 收尾及可证明未发生效果的撤销正例。

单凭 fake tx 只能说明本函数在替身下的控制流，不证明 SQL JOIN/锁、事务原子性、真实 caller 执行顺序、验签、revocation 与 dispatch。真实效果路径及隔离 PostgreSQL 证据仍未完成；Gate3 继续 NO-GO。

## 静态快照

LF SHA-256，源码根 `../multica/`：

- `server/internal/governance/execution_control_settlement.go` `1a6c8072e068462b2e6c79fefa253ff1936a1da812dbfa94c25a7440da749311`
- `server/internal/governance/execution_channel_reader.go` `ad7e0e6078bdb32a28be927457b4c1af74f473d77e426d4bef94c26ccedd55e5`
- `server/internal/governance/execution_channel_admission.go` `3fff5e31721a4b4da4f8d8f30781cbd96e95feda0ef2ca751471fb2529c04b6e`
- `server/internal/governance/execution_contract_selection.go` `327275b359600eeed3b0cba843f19e19ff7814ece59961c45fa3ddf2d93c72cc`
- `server/migrations/648_cr_execution_control.up.sql` `89f0c3f061c73dae188f99ada0accd13ab770e72e7a96130eb70c3c8c07b5b61`
- `server/migrations/642_cr_execution_authorization_head.up.sql` `a1195e11f493b26396d7cb1d904e8b14dc33324b4bed3ce7f1cccf0ae53129db`

独立静态分析 session `01a19fbb-d2fe-7374-9f4d-4565ce3bd36c`，requested `OpenAIPersonal/gpt-6.1-sol:high`；balanced 审阅 session `01a19fc5-8d3b-7374-9f4d-4566a57d2972`，requested `OpenAIPersonal/gpt-6.1-terra:high`；actual 均 unknown。balanced 指出的有效输入、状态转换、decision schema、远端恢复正例及可达性措辞已订正；其未重算摘要或运行测试。报告中的源码观察不代表已修改 multica；若后续改其代码，按现时 `CUSTOM.md` 登记。

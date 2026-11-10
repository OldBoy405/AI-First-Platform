# Terminal fence / Fail 限定 strong 静态报告

## 结论与限域

**有1项静态确证的严格claim回放分类问题（P2），不判通过。** 已完成本次Fail handler/body/helper、Fail事务主路径和新CAS/generated接线的定向阅读；副作用“不含任何外部活动”的结论另有具体未穷尽点，不用旧claim锁序将整个限定范围泛化成INCOMPLETE。

仅Fail纵片；Complete虽有SQL guard，但production未传flag、handler未接，**不算Complete已修**。client/outbox/完整terminal链、全局C1/Gate3/生产准入均不签。新pin为fail-green1-source-manifest，不用上片19项当漂移基准。

未访问DB、未运行测试/sqlc、未改源码、未启动子代理。唯一写入是本报告，以Python open('x')独占创建，等价wx。模型沿宿主nativeM schema1/configured strong/high，actual无后端回执unknown，不伪称实际型号已验证。

## F1 / P2：strict CAS拒绝可被同代终态fallback改写成200

位置：`service/terminal_claim.go:39–42`；`service/task.go:5884–5893`；响应在`handler/daemon.go:5600`附近的 !transitioned 分支。

当前可触发路径：任务T在workspace W、runtime R、代次G，已failed/completed/cancelled；R的daemon_id=A。同workspace另一真实mdt（daemon B）POST /fail，body带R/G。初始helper只检查task workspace访问；body helper从真实context得到W/B，并不会伪造身份。SQL的新EXISTS要求r.daemon_id=B且状态active，故零行。

runInTx返回ErrNoRows并回滚后，service用无scope的GetAgentTask(T)取现有行；matchesTerminal只比R/G/terminal，**不检查claim.WorkspaceID或claim.DaemonID对应的DB关系**，于是返回(existing,false,nil)，handler返回200和taskToResponse。SQL未通过的认证scope被当成功回放，违反strict模式“成功已核tuple+MDT scope”的口径。

影响限定：这不改task、不创建retry/通知，也不是已证跨workspace泄露（示例是同workspace）。旧legacy本来有更宽访问，不能据此宣称新增了该旧权限；问题是**显式strict请求身份不符仍被ack成功**。如果业务明确允许这种终态跨daemon只读ACK，应把它登记为合同例外，不能再称所有strict成功都核过DID。

建议：严格ErrNoRows回放需同时核终态、同runtime/代次和认证workspace/daemon关系，scope不符返回ErrTaskTerminalClaimRejected。可在回滚后的只读fallback用workspace-scoped task/runtime查询复核，不新增前置task/runtime锁；读取故障仍归500。补真实MDT B→A所属同代终态409及A自身回放200，另补runtime/tenant漂移；本轮只静态推导，未动态复现。

## 已核SQL、参数、Scan与事务保护

- Fail源SQL `agent.sql:1404–1430`：在原UPDATE CAS WHERE追加`NOT enforce_claim OR (runtime=claimRuntime AND dispatched_at=claimTime AND EXISTS(agent workspace=authW, runtime workspace=agent workspace, daemon_id=authDID))`。target字段已qualified，无新增前置task/runtime锁；false时即原id+active status，NULL claim参不影响legacy。
- generated `agent.sql.go:3808–3955` 与源一致；参数$1–$9依次ID/Error/FailureReason/SessionRolloutMissing/SessionID/WorkDir/DurableWorkDir/BranchName/RetiredSessionID，$10–$14依次bool/UUID/Timestamptz/UUID/Text。service命名字段与QueryRow顺序一致，ClaimDaemonID.Valid=enforceClaim，RETURNING及Scan尾含ProjectID/ApprovalWorkspaceID，无错位迹象。实体仍AgentTaskQueue，未引入新model/table。
- terminalClaimOption要求最多一个claim、各Valid、微秒时间、非空无C0/C1 DID，strict必须TxStarter；缺Tx不走非事务降级。无claim保持原service签名调用兼容。
- `runInTx:7585–7597`真实Begin、WithTx，callback error时defer Rollback，只有成功才Commit。现有chat session锁在CAS前，未新增task/runtime锁，不重新签旧锁序。
- FailAgentTask CAS错误立即return，故SettleTerminalTaskState、chat resume更新、retry child、chat failure消息均不可越过该错误；事务后analytics/recovery/comment/notify/broadcast及handler token revoke只在transitioned成功后。active新代次/不同runtime在fallback不匹配即ErrTaskTerminalClaimRejected→409，不被当终态noop。真实非ErrNoRows数据库故障仍500。
- 仅同R/G终态的fallback会false,nil且无后续写，但缺少身份复核即F1。不把CAS零行的DB保护夸成全链身份已核。

## Body与legacy

新helper完整读：先解第一文档为raw/map与原DTO；只有第一文档出现runtime_id/dispatched_at（EqualFold也检测大小写别名）才启strict。非canonical claim键立即400；strict用既有完整UTF8/duplicate scanner且要求后续Decode为EOF，拒第二文档/坏尾部。

两字段都必须是字符串且同时有效，runtime须canonical UUID，时间用已核ParseExecutionClaimTime（Parse前最多6位且拒comma）；half/null/错误类型/超精度不会降legacy。auth path必须真实MDT，context workspace等于task workspace，DID非空且拒控制符，header不能提供这些事实。请求字段不被用来指定auth workspace/DID。

无claim字段保留旧first-document行为（包括忽略第二文档），不强制旧客户端发送新tuple；这按本片合同兼容，不代表关闭legacy-bypass major。普通Fail payload的未知字段/别名规则未被静默升级成全局strict schema。

## 副作用结论的精确边界

**已确认DB事务内CAS拒绝不会走后续写或提交；但不能签“拒绝前绝无活动”。** `task.go:5629–5653`在事务/CAS之前，会对retryable failure先读取当前parent/agent并调用buildRuntimeMCPOverlay；该helper554–590在Composio启用时调用BuildTaskOverlay。例：stale tuple配retryable failure_reason，当前parent重试预算未尽且有issue/chat，就能走该调用，然后才在CAS被拒绝。

已确认的是前置builder调用；实际Composio实现位于`internal/integrations/composio/dispatch.go:86`，本片未读完该函数及远端CreateSession链，**不声称已证远端写/凭据生成，也不能声称它们不存在**。这是具体剩余副作用审查点，不将缺证升级为第二项已确认漏洞。若要求拒绝请求完全零外部活动，应继续核这条链；新CAS本身不保护事务外调用。

其他未动态验证：竞争reclaim/双终态/回放、故障回滚、副作用计数、全部body负例。现有首例只断言409和status仍running，不是所有side effect的动态证明。

## 现成证据与sqlc provenance

完整静态读governance首例：真实MDT→公开/fail→旧/status回读，gen1比现行gen2早1微秒。raw RED输出为旧200（返回failed task），GREEN1 meta为1RUN/1PASS/0SKIP；我未重跑，meta所报原库/清理安全仅转述，未访问DB核实。

已读make失败及本地sqlc两次记录的头部/相关内容：make固定v1.31.1在GOPROXY=off的deprecation lookup失败，changed=[]；同版已装exe记录SHA `9668d6e9615694b943e5a8beeb80517d590edfeb83a28478f5f11186a0142307`，首次ambiguous id失败0生成，qualified后成功。记录支持非手编生成，但我未执行exe/独立重生成，不把记录当二进制供应链attestation。

本次对pre/post保存的全部generated哈希清单做静态比较：raw变化=agent.sql.go；LF变化=agent.sql.go。支持“规范化仅agent.sql.go变”，并直接核了该方法source/params/Scan。未完整人工阅读所有generated或逐份备份；不需要为此扩大本片到全仓。

## 实际read与source pin

完整：两个新handler/service claim helper、新governance terminal test、terminal plan、新fail-green1 manifest。定向：handler/daemon.go:127–177、5549–5698；service/task.go:554–665、5584–6028、6152–6167、7585–7614及lock helper grep；源agent.sql:1230–1259、1388–1433；generated agent.sql.go:3808–3963；GREEN1 meta、RED raw行；三份sqlc记录部分及pre/post清单机器比较。旧认证/时间helper沿用已核上下文；未审核Complete生产链/client/outbox。

下表本次实算raw/LF SHA与长度对本纵片pin。产品变化是新纵片预期，不与旧claim19项判漂移。产品match=True；若DRIFT则相应修订不能继承已读基线结论。hash整文件不代表整文件代码已审。

| 文件（业务根相对） | raw SHA-256 | CRLF→LF SHA-256 | 对新pin |
|---|---|---|---|
| `server/internal/handler/daemon_terminal_claim.go` | `164e9304d29c6061975eae0159b8d303be9d35136d141e7cb66e4b3141a365af` | `164e9304d29c6061975eae0159b8d303be9d35136d141e7cb66e4b3141a365af` | MATCH |
| `server/internal/handler/daemon.go` | `e60c79d77d7c312a6b82c4a09c67a977be8a73e9c3e87101187288cad0c010e6` | `e60c79d77d7c312a6b82c4a09c67a977be8a73e9c3e87101187288cad0c010e6` | MATCH |
| `server/internal/service/terminal_claim.go` | `d2410fed3ecab92d39569e55c2db411897f7e38bdc3810ea1fb4d45aa10293a3` | `d2410fed3ecab92d39569e55c2db411897f7e38bdc3810ea1fb4d45aa10293a3` | MATCH |
| `server/internal/service/task.go` | `f37e38fd5a20e0574628c228f328a8ad8253ea9cc1eeaa1b503c413830030155` | `f37e38fd5a20e0574628c228f328a8ad8253ea9cc1eeaa1b503c413830030155` | MATCH |
| `server/pkg/db/queries/agent.sql` | `cb19419b12c7a5e7d080ad70b1e40e445593a38bb073ce262032286066d73b9c` | `189b22a618dc9ae9424eb43ecfb7931108ff376b5c72631a7a60422a872904a2` | MATCH |
| `server/pkg/db/generated/agent.sql.go` | `96e708dbde97c750a157317a71dd4cdddd62a3a7d8d0ba351e8bc885afe7b64c` | `96e708dbde97c750a157317a71dd4cdddd62a3a7d8d0ba351e8bc885afe7b64c` | MATCH |
| `server/internal/governance/execution_terminal_claim_test.go` | `aad71f7e5c20a1359232c2f79bedb2138deab11ca52ed915a274a1ac0e985b1e` | `aad71f7e5c20a1359232c2f79bedb2138deab11ca52ed915a274a1ac0e985b1e` | DRIFT |

不签Complete、SDK/outbox、完整terminal fence、旧claim锁序、全局C1/Gate3或生产准入。

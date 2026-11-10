# Gate3 两轴（strong）评审结果 — 2026-10-26

非作者只读评审。**均不给 Gate 结论**；本节记录它们的轴结论与 finding。requested `OpenAIPersonal/gpt-6.1-sol:high`，actual 无后端回执记 unknown。

- 规格轴 session `01a177c6-c2ff-77b9-a3c5-0f64ff1af43c`：**BLOCK**
- 安全轴 session `01a177c6-c324-77b9-a3c5-0f6812b8fc3c`：**BLOCK**
- 评审基线：`source-manifest.json`（sha256 `9b80fec5…`）。**注意**：评审期间 `tools/lib/workspace-transactions.mjs` 又改了两次（零发布死锁修正、远端事实判据），两项安全轴 finding 正是针对这两处；当前字节与对应证据见 `../../../../tools/changes/2026-10-22-aifi-45-authorized-execution/validation/evd-009-wiring-20261026/meta-current.json`。

## 规格轴 findings

| 严重度 | SC | 文件:行 | 反例 | 最小修复 |
|---|---|---|---|---|
| blocker | SC-RUN-004/005 | `M/internal/governance/execution_dispatch_root_test.go:31-38,73,275`；`runner.go:1040-1044`；`M/internal/service/task.go:381-431` | 永久根三函数仅测试调用；测试根任务 ID 是随机 UUID。真实派发直接调 TaskService，载体没有 logical key/repair receipt；跨 run 重投不经过永久根围栏 | 把 receipt→永久根→真实任务创建/终态/技术重试接成生产路径；测试必须查真实队列行 |
| blocker | SC-AUTH-001；SC-RPR-002；SC-RUN-001/003/006/007/010 | `T/crctl.mjs:1885-1894`；`M/internal/daemon/execution_verifier.go:66-69` | 充分包完成静态检查后仍无条件返回 `EXECUTION_CONSUMPTION_REQUIRED`；最后一个合法修复名额也没有继续验证交付的正向执行链 | 依赖可信 T 裁决通道，接已提交业务消费及恢复；不能用"全部拒绝"覆盖正向 then |
| blocker | SC-AUTH-004 | `T/lib/execution-authorization.mjs:202-205`；`T/crctl.mjs:1885-1894`；`T/lib/workspace-transactions.mjs:2007-2022` | 现有检查只校验包内路径格式/来源/release snapshot，**没有**"实际候选 diff vs 授权路径/交付目标/验收边界"比较；授权仅 src、候选改 private 无对应求值步骤 | 在候选变更生效入口核实际 diff、realpath 与冻结资源绑定；越界要求新授权 |
| blocker | SC-AUTH-006/008 | `T/crctl.mjs:1827-1837`；`T/lib/execution-sensitive-action.mjs:72-135` | sensitive-action 离线验 grant/source 后直接写动作账本，不查当前 head/claim；平台撤销后保留旧 initial 包，公开 CLI 无识别当前撤销的执行点 | 敏感消费接可信当前 head/撤销检查，与消费同一准入边界 |
| blocker | SC-RPR-007/008 | `T/crctl.mjs:1599-1620`；`T/lib/execution-authorization.mjs:183-189,314-315`；`T/test/repair-governance.test.mjs:14-17,45-46` | repair 只解码 payload；测试用 `signature=AA==`。所谓追加 initial 包要求同 lineage/不同 grant/supersedes，而正式验签 schema 要求 lineage=grant 且不接受该追加形状 → 可信追加协议不存在 | 定义并贯通可验签追加凭据、前驱 head CAS、唯一增量；禁用未验证 payload 扩额 |
| blocker | SC-RPR-012 | `T/crctl.mjs:1674-1685`；`T/lib/repair-governance.mjs:418-454` | 已登记 reviewer + 当前 cr.md hash 即可 resume；不要求签名恢复授权、预期 stop version 或新证据；成功直接删 stop，"旧 stop 完整保留"的 then 未实现 | 验签精确 stop 恢复授权与独立新证据；CR 锁内 CAS、归档 stop/streak、按新 epoch 隔离计数 |
| blocker | SC-EVD-005 | `T/lib/workspace-transactions.mjs:5106`；`T/crctl.mjs:1802-1805,5794-5802`；`T/lib/evidence-delivery.mjs:86-95` | `testCr` 不传 `authorizationDigest`；生产收集器不传 digest/report_digest；机械入口不读该字段 → 摘要漂移拒绝分支只有单测喂 facts 才进得去 | 从真实授权写报告摘要并在交付/机械入口读取；补规则/输入/工具语义绑定，禁新合同缺字段放行 |
| blocker | SC-EVD-006 | `T/crctl.mjs:1803`；`T/lib/evidence-delivery.mjs:31-37` | 合同归属只取可编辑 `cr.md` 字段；删 `execution-contract` 即返回 legacy deliver，不查权威已提交注册/迁移历史 | 从权威注册与迁移历史确定合同，拒绝删字段降级 |
| major | SC-EVD-007/008；SC-RUN-008 | `T/lib/component-readiness.mjs:94`；`T/lib/legacy-migration.mjs:19`；`T/test/delivery-contract.test.mjs:251,421` | 两判定只有测试调用，无启用/迁移入口执行它们；迁移正例构造 facts 后算剩余，不迁移真实历史或未决任务 | 就绪接实际启用入口；迁移按 D8 保持明确拒绝，不把纯函数正例记成生产能力 |
| major | SC-NTF-001～007 | `M/internal/governance/execution_notice.go:173,235,337,387,413`；`execution_notice_test.go:58,310,379` | Deliver/Recover/Bus/Load 均无非测试调用点；正文还需调用方给 conclusion/action。真实阻断不会因这些 TC 通过而产生通知 | 补事件正文产出方、收件人解析、投递与启动恢复接线；从事件入口观察 Inbox |
| major | SC-NTF-005/006 | `execution_notice.go:69-82,134-138,218-220,277-297` | 去重键用受众角色、不含 RecipientID，事件结构也无 project；同原因/证据从授权者 A 改发 B 仍命中旧 Inbox；测试只改 cause 来改角色 | 键绑定 project 与实际接收者；补"角色不变、接收者改变"反例 |
| major | SC-AUTH-002 | `T/lib/execution-authorization.mjs:183,270-285`；`T/crctl.mjs:1862-1873,5875-5882` | facts 缺口仅由传入的 unverifiable/facts_verified 触发；生产只传严格 schema 的 grant payload，无环境采集器；规范命令 `authorization-check` 也没路由 | 实现规范只读入口并采集真实仓库事实；分别验证 business/facts 缺口 |
| major | SC-RPR-001 | `T/lib/repair-governance.mjs:185-214` | "首次实施"只以 `consumed.length>0` 阻断；已有未解决 blocker 但未准入 repair 时，新 origin 可反复声明 implementation，counted=false | 从已接受阻断与真实 run 状态裁决 kind，不接受调用方分类 |
| major | SC-RPR-005 | `T/crctl.mjs:1714-1744`；`repair-governance.mjs:223-233` | 不给 `--blocker` 时仍直接采用 `--origin`；同一阻断换标签可再扣一次，与"标签不参与身份"记录不符；跨 run 重放无 adoption/当前 subject 重验 | 强制引用可信已接受 origin；补 adoption 映射与适用性复验 |
| major | SC-RPR-006 | `repair-governance.mjs:58-63,180-182,223-233`；`T/lib/execution-transaction.mjs:662` | 修复只持 lineage 文件锁；请求/receipt 不绑定 subject，同 origin 在 subject 改变后仍返回旧 receipt；共用 CR/CAS/Git 事务助手只有测试调用 | 准入接共用 CR 锁、授权复验与 subject CAS；补同键异 subject 与提交边界冲突测试 |
| major | SC-RPR-009/010/011 | `T/crctl.mjs:1630-1665`；`repair-governance.mjs:363-399` | 同一次评估重投两次累计两次 no-progress；无纠正尝试身份或幂等键；progress 只需 basis 枚举、evidence 可空；attempted 实际保存 reviewer ID | 绑定独立 assessment/真实尝试/证据/epoch；幂等记录并产出升级通知 |
| major | SC-EVD-001/002/004 | `T/crctl.mjs:1355,1386,1802-1808,5826-5842` | 新判定只在独立 evidence-check/mechanical 运行；gate/advance 不消费其结果。旧门禁全满足但缺 execution grant 时不能阻止真实推进；机械例外只返回 allowed，无替代评审接线 | 内容合同与机械证明接适用 gate/交付入口，保留证明链；测试实际推进而非查询结果 |
| major | SC-EVD-002/003/010 | `T/crctl.mjs:1578-1592,1793-1805,3236-3237`；`evidence-delivery.mjs:49-70` | 任意非空 test-report 即 `verification.ok`；null subject 在新合同检查中仍走 legacy 成功；没有实际 diff/报告可运行性/cycle 比较 | 新合同要求当前可重算 subject/cycle、真实验证结果、独立实际 diff 证据；legacy 豁免按权威合同归属选择 |
| major | SC-EVD-009 | `T/lib/workspace-transactions.mjs:22-28,2041-2052`；`T/test/merge-release-recovery.test.mjs:58-81`；`L:574` | 当前守卫额外要求远端已发布；prepare 失败后同 journal 重入会覆盖 receipt，新测试明确允许重批成功。规范 given 没有"必须已有 push"限制。receipt 只含审批/发布主体，没有原授权/repair 消费 receipt、repair_charge 或 cycle | 区分"恢复原操作"与显式新操作，原操作冻结 receipt；绑定原业务消费引用，补 prepare/publish 故障与三项不重复断言 |

规格轴的补充判断（值得记）：
- **EVD-009 只能判部分满足**，不是三项 then 全闭合；但 checkpoint/writeback 未调用同名 helper **本身不是缺口证据**（checkpoint 复用 payload `:2508-2538`；writeback `found` 分支复用 candidate、仅 `!found` 读审批 `:3413-3461`）。仍需证明原业务 receipt 的关联。
- RPR 12 条**并非整族死代码**：四个 CLI 动词有调用点（`crctl.mjs:1654,1678,1699,1736`），问题是调用不满足完整 then。
- 不得再报"消费侧完全没有自评检查"——该检查存在（`runner.go:1321-1340`）。

## 安全轴 findings

| 严重度 | 文件:行 | 反例 | 最小修复 |
|---|---|---|---|
| blocker | `M/internal/daemon/execution_binding_endpoint.go:135-146`；`M/internal/governance/execution_binding_issue.go:295-298`；`M/internal/daemon/execution_trust.go:73,96,146` | **F1 是代签能力**：agent 已拿到 endpoint URL，可自行 POST 任意合法 nonce/PID/根/tools digest；daemon 转发，server 把这些自报值签入。0700/0600 与 inode pin 不能阻止同 UID 改写已有公钥文件；单次 URL 不证明调用者是可信 T | 隔离 agent 与 daemon/T 的 UID/凭据/密钥/控制通道；challenge 由受监督 T 产生并绑定实际子进程；隔离接通前关闭这些控制证明写入口 |
| major | `M/internal/governance/execution_consumption.go:99,129`；`execution_activation.go:89,121`；`M/pkg/db/queries/execution_binding.sql:7-20` | **claim TOCTOU**：读到 active generation 后暂停；另一事务取消/重领 task 或改 runtime 归属并提交；原事务仍可写 receipt/activation。共享 helper 只锁 CR/head record | 三写端点共用完整校验事务；按与 claim/reclaim 兼容锁序保护 task/runtime 及归属行，持锁至提交 |
| major | `execution_consumption.go:164-168`；`execution_binding_issue.go:251-255,295-299` | **拿别次签发换本次消费**：A 已签 challenge C；同 CR 的活动 B 用自己的 task/runtime + C 请求 consumption。这里只查 workspace/CR/head/C 存在；同 task 重领后可复用；签发记录与签名均无 dispatched_at | 签名与签发账本绑定完整 generation；消费精确引用 issuance ID 并比完整证明内容 |
| major | `M/internal/daemon/pipeline_task.go:568-583`；`execution_verifier.go:27,47-51` | **strict 可降级**：`context.execution.contract` 为 null/空/类型错即当作"不声明合同"，strict=false 后跳过 claim/安装检查；无服务端持久化合同判断该 task 是否必须 strict | strict 必须来自可信 task/run 合同；显式块缺字段/null/类型错一律拒绝；仅持久化确认的 legacy 才兼容 |
| major | `M/internal/handler/daemon_terminal_claim.go:41-43`；`M/internal/service/terminal_claim.go:26-28`；`M/pkg/db/queries/agent.sql:1264,1438` | **终态 fence 可自行退出**：持 workspace daemon 凭据的旧回调省略 runtime/dispatched_at 即 `enforce_claim=false`；即使 task 已重领，旧 `/fail`/`/complete` 仍走状态型 CAS | 服务端读持久化合同，对 strict task 强制完整 tuple；拒绝无代次回调 |
| major | `T/crctl.mjs:1592-1616,1711-1744`；`T/lib/repair-governance.mjs:151-158` | **repair-admit 接受未验签输入**：自写 `payload_b64`、指定目标 CR/新 lineage/任意 repair_limit，甚至省略额度得默认 6；命令持久化"准入"receipt，未过 `authorization-bind`，未核当前 head/scope | 写命令统一要求可信绑定与当前消费裁决；验签/验 scope/head 后入账；新合同缺额度不得回退默认 |
| major | `T/crctl.mjs:1827-1838`；`T/lib/execution-authorization.mjs:86,300-319`；`execution-sensitive-action.mjs:33-40,104-128` | **敏感动作绕过关闭的消费链**：保留已撤销的 initial 包仍可消费；或把真实包/公钥/source 复制到另一个可写 `--trust-root`，空 actions 账本重新获额度。只核静态包，不核当前 head/真实 claim；root 由调用者选择 | 敏感动作走同一可信在线裁决；密钥根固定且 agent 不可写；额度账本固定绑定租户/lineage，禁复制根重置 |
| major | `M/internal/governance/execution_dispatch_root.go:158-200` | **终态与 adoption 竞态**：adopter 普通 SELECT 读到 open；另一事务标 terminal；adopter 随后无 `terminal_at IS NULL`/generation CAS 的 UPDATE 仍返回非终态成功；两个 adopter 可覆盖 mapping。该 helper 未见生产调用点（潜伏） | 根读加锁；UPDATE 附终态与期望 generation 条件并用 RETURNING；核 CR/stage 与可信 adoption 来源，拒绝受影响行数为零 |
| major | `T/lib/workspace-transactions.mjs:2034-2048`（首读版） | **零发布恢复卡死**（作者同轮自证，已修）：receipt 在 preflight/prepare 前保存，之后失败且零 push，合法修复后重新批准重跑仍报 REAPPROVED，无转换入口 | 只有确证零发布时才允许显式结束旧意图并重建 receipt |
| major | `T/lib/workspace-transactions.mjs:2041-2052,2170-2173`（漂移版） | **修补又留丢响应窗口**：push 成功后、`pushed=true` 保存前崩溃；恢复按"零发布"刷新 receipt，无需攻破 SHA，重批字段即可改变决定 | push 前持久化 intent；恢复先核远端是否含 candidate；结果不明不得换 receipt |

安全轴另核实（正向）：F4 复用属代码事实（binding/consumption/activation 都调 `lockExecutionAuthorizationHead`，SQL 带 workspace/CR 且 `FOR SHARE`）；迁移 643-647 无新增 FK/级联，643-645 trigger 拒普通 UPDATE/DELETE，645 另拒 TRUNCATE；**643/644 未拦 TRUNCATE**；manifest 双空返回 nil 时相关 handler 返回 503。

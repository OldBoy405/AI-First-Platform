# AIFI-45 Runner 通知固定映射：只读事实调查归档

> 归档说明：下文为上一轮调查答复原文。表中映射为候选，用户决定由 Runner 使用固定映射，并不构成对生产发送的授权；本次未执行生产发送，也不宣称事实、授权、证据、投递链已存在或已接通。

---

## 结论

按已决定的方向，**Runner 在可证实的停／等待点使用固定映射**；不再把生产方选择交还用户。但当前多数路径缺少可信收件人、可访问证据或真实恢复记录，**不能因此构造并发送通知**。完成通知也不能由阶段 run 完成推断。

本次只读查看了工作树：multica HEAD 为 `81e5293…`，`execution_notice.go` 等已有未提交修改；tools HEAD 为 `75ec007…`，亦有未提交修改。以下是当前工作树分析，不代表部署状态；未修改代码、DB 或容器，也未运行测试。

## 固定映射与事实门槛

表中 cause 是**拟定的生产映射**；现有 `BuildNotice` 只对四个维护类 cause 特判，其他 cause 默认路由 authorizer，因此新增映射必须先闭集校验，不能依赖默认分支。

| 可证实触发事实 | cause → 结论 / 行动 | 发送前额外条件 |
|---|---|---|
| 可信业务裁决明确指出授权的具体字段不足 | `authorization-insufficient` → “执行等待补充授权” / “补充所列欠缺范围或验收内容” | 有具体缺项、当前 scope 和有权决策者；不能从 `HEAD_UNAVAILABLE` 猜出缺项 |
| 可信已提交裁决 `REPAIR_QUOTA_EXHAUSTED` | `repair-quota-exhausted` → “新纠正性修复未准入” / “决定是否追加额度” | 已核实当前额度与消费及裁决引用；不阻止已准入工作的验证或交付 |
| 可信已提交 `REPAIR_STOPPED`，并有独立、适用的无进展评估及 stop 版本 | `repair-no-progress` → “修复因无进展停止” / “决定改变路径及是否授权恢复” | 不能把 Runner 的 `RUNNER_LOOP_EXHAUSTED` 等同两次无进展；恢复还须新证据及明确签名授权 |
| 有界恢复结束，可信诊断明确为环境、凭据、部署或绑定故障 | 分别为现有 `environment-failure`、`credential-failure`、`deploy-failure`、`binding-failure` → “执行受阻” / “处理对应故障” | 必须有确实执行过的恢复路径、结果及维护责任人；只有 `RUNNER_TASK_FAILED` 或 `TEMPLATE_DIGEST_MISMATCH` 不足以判根因 |
| 约定交付的权威事实已提交，当前 subject、独立验证和交付目标均适用 | `delivery-completed` → “约定交付已完成” / “查看交付结果” | 交付事实及链接可核验；不是 requirement/architecture/code 阶段 `pipeline_run.status='completed'` |

**等待而不主动通知**：`WAIT_CONSUMPTION`、`WAIT_TRUSTED_T_COMMIT`、`HEAD_UNAVAILABLE`、`HEAD_REJECTED` 只证明准入未通过，分别不能证明用户缺授权、撤销原因或维护故障。`authority_postcondition`、`projection_stale`、`review_evidence`、活跃任务及 ACK 同样不能直接升级为人需处置的阻断。若后续取得上表明确事实，再按对应行处理；未知值 fail-closed。

实际值与位置：

- `../multica/server/internal/governance/execution_admission.go`：上述四个 admission reason；当前检查是按 CR 计数，代码自己注明尚未绑定单次 generation。
- `execution_admission_gate.go:162-181`：等待只写 `detail.runner.wait_reason=admission` 和 reason，入口将内部等待错误转为成功 wake；它不是通知事实。
- `runner.go:982-1035, 1546-1669`：任务状态、authority wait、review delivery gap 和失败；`failRun` 的 run 与 node 更新目前是**两次独立写入**。
- `runner_requirement.go:94-109, 188-290, 540-580`：需求阶段的评审、等待和阶段完成；`requirement-approved` 只证明该阶段状态。
- `runner_code.go:383-405`：writeback 有 `deliveryFactsConverged` 屏障；即便该 run 完成，仍须核验屏障的具体事实是否足以证明本 CR 的**约定交付**。
- `../tools/skills/shared/crctl/scripts/lib/repair-governance.mjs:239-260, 333-470` 有 `REPAIR_STOPPED`、`REPAIR_QUOTA_EXHAUSTED` 等真实值；这不证明 Runner 已有可信消费路径。`crctl.mjs:1994-2008` 当前仍以 `EXECUTION_CONSUMPTION_REQUIRED` 拒绝未接通的消费。

## Evidence、已试路径与收件人

- **Evidence ref**：采用可授权访问的 canonical CR/issue、已提交裁决或评审 artifact 的稳定引用，连同 workspace/project/CR、commit/receipt、subject digest 和版本校验。`cr_sync_event` 或 node row ID 可作内部定位，但**本次未证实可直接供收件人访问的 canonical URL**；不得拼造链接。投影 `needs_reconcile`、占位 `pending:` commit、旧 subject 或跨 scope 证据不能证明当前事实。
- **TriedPaths**：只从同一根因、同一执行身份下已落盘的实际 task/retry lineage 和结果重建；记录“做过什么、结果是什么”，不是从 attempt 数、模板、计划或错误文案推测。无记录时维护通知 fail-closed；空列表不等于“已恢复但未成功”。
- **业务收件人**：从可信认证的人类原请求／已签授权记录及当前有效 scope 解析有权决策者，并验证该用户仍可访问该 workspace/project/CR；缺失或不适用则不发送。不能用 task-token、Agent 自报、Git owner、`started_by` 或普通成员身份替代授权。
- **维护收件人**：必须来自可信、当前有效的项目/故障责任绑定并验证访问权限；不能因 workspace owner/admin 就假定其是该故障责任人。
- 当前 `execution_notice.go` 的 `ResolveNoticeRecipient` 对传入 authorizer 只检查 workspace membership；维护侧选最早 owner/admin。它**不能单独证明上述授权或责任**，UUID 合法也不是授权。

## 原子性、去重与恢复

`execution_notice.go:235` 起的事务只把 `cr_execution_notice` 与 Inbox 一起提交；**不与 Runner 业务事实或通知引用同事务**。`crsync.go` 的事件插入、投影、processed 标记也不是一个事务，不能简单在 ingest 后调用就声称可靠。

未来切片应：

1. 在同一平台 DB 事务中提交可重建的**业务事实版本／通知引用和 Inbox pending**；通知写失败不得抹掉已提交的业务事实。若事实先已提交，则必须有持久、可枚举的未投影事实及幂等 rebuild，不能只靠提交后的内存回调。
2. T 的 Git 事实与 M 的 DB 无跨系统原子事务：先接受可验证的已提交事实，按稳定身份投影并重建；提交结果未知时查询原身份，不重签授权、不重派 writer。
3. 当前 `NoticeDedupeKey` 只有 CR、cause、evidence digest、audience；表唯一键另含 workspace，**缺 project、稳定 root/event 和具体 recipient**，收件人变化可能被吞。须按设计 §5 修正并覆盖跨 CR、跨 project、证据及受众变化；不能把 `646_cr_execution_notice` 的现状说成已满足该设计。
4. pending 提交后广播、成功后标 delivered；崩溃恢复重投**同一 Inbox ID**，客户端按 ID 幂等。广播后标记前崩溃允许重复广播，不宣称物理 exactly-once；已 delivered 重放不再提醒。

## 可实施的 test-only 切片

仅作为后续计划，**不接生产**：

1. 在 `../multica/server/internal/governance/execution_notice_test.go` 增加表驱动固定映射测试：真实 reason/status、未知值静默；缺具体缺项、证据、tried paths、授权或交付事实均拒绝。用测试 fixture 表示可信裁决，不伪装为生产接通。
2. 以 `execution_admission_gate_test.go`、`runner_requirement_test.go` 和 `runner_recovery_m41b_test.go` 的隔离 fixture 覆盖 wait、失败但 retry in-flight、late verdict、loop exhausted，以及阶段完成不生成交付通知。
3. 设计事务／rebuild 测试：事实提交后通知失败、重复 wake、并发、广播前后崩溃、recipient 和证据变化、跨租户与陈旧 subject；断言同 ID 恢复且不重派任务。涉及 DB 的测试只在经验证的专用隔离 DB 中运行，不能使用默认共享库。
4. 用 `execution_notice.go`、`crsync.go` 和设计 §5 对照测试标出当前失败项；在可信 recipient、canonical ref、事实原子性和实际客户端幂等都闭合前，保持生产入口不可达。

**主要剩余风险**：现有 notice helper 接受任意正文、可选 evidence 和空 TriedPaths；可信裁决到 Runner、责任绑定、可访问证据以及事实→通知的可重建提交链尚未证实。此前 `validation/ntf-producer-gap-20261026.md` 所列“待选生产方”已被本次决定取代，但“函数存在不等于生产可用”的结论仍成立。

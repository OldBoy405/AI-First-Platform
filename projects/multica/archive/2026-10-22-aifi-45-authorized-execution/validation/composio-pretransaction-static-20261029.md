# Composio 事务前 overlay：条件化静态风险

本检查是 AIFI-45 邻接依赖分析，**不等于通知调用 Composio**。请求 strong 只读会话 `01a186ec-8176-7020-aecc-d2d2ba0ac148` 未读到全部外部实现，结论 INCOMPLETE；协调者随后只读补查 `multica/server/internal/integrations/composio/dispatch.go:53–152` 和 `internal/service/discussion_session.go:278–500`。actual backend unknown；未运行 DB、网络、外部服务、测试，也没有读取或记录任何凭据值。

## 已直接观察

- `SendDiscussionMessage` 在 DB 事务之前读取项目 coordinator 并调用 `buildRuntimeMCPOverlay`（`discussion_session.go:291–306`），之后才开启事务、检查 membership 和锁内 session 状态、重新解析 coordinator、判断 trigger 和调用权限、预留/重放 idempotency（`:309–420`）。因此**在调用条件满足时**，同 key 重放、冲突、权限拒绝、session 状态变化或后续事务回滚之前，都可能先执行 overlay 构建；并非每次都一定调用远端，实际重试和部署启用情况未知。
- `BuildTaskOverlay` 在 owner 存在、allowlist 非空且活跃连接交集非空时调用外部 `CreateSession`（`dispatch.go:86–128`）。外部响应、远端幂等/计费、取消能力与实际创建结果尚未验证。DB rollback 不会自动证明撤销外部调用。
- **独立 strong 静态复核证实代码存在条件性错配**（会话 `01a186ee-8e9a-7020-aecc-d2d818b29b9b`，actual backend unknown，未运行测试/DB/网络）：预事务保存 coordinator A 构建的 overlay（`:295–305`），事务内重新解析 coordinator 并对 B 做权限检查（`:370–397`），创建 task 同时使用 B 的 `routable.ID` 和先前 A 的 overlay（`:446–459`），两次结果没有绑定比较。设置写者 `UpdateProjectSettingsWithDiscussionCoordinator` 及事务内读共用 project advisory lock，但预事务 A 的读取在锁外；所以写者在预读取之后、锁内重读之前完成更改，并不被该锁的相对顺序排除。A 的 owner 与允许工具、活跃连接满足 overlay 条件且锁内 B 获调用权限时，静态上可能出现 B 的任务携带按 A 生成的 session。**该交错尚未以真实事务实证；实际部署、客户端可达性、远端效果、后续消费与安全影响均未证明**，不能断言实际利用或泄露。
- 同一 agent ID 也不必然证明 owner、允许的工具、活跃连接和授权上下文未改变；独立复核指出 agent 的配置写入和调用目标操作未与上述 advisory 锁统一，owner transfer 路径则未核实。单独比较 agent ID 或假定某时间戳完整覆盖全部依赖，不能被表述为完整信任绑定。事务外预判权限/trigger 也只能减少部分无谓调用，不能替代锁内权威检查或解决 replay 重复效果，更不能直接保证配置漂移时安全。
- 对当前工作树的后续只读复核：HTTP 入口已有前置成员检查，锁内还会复核成员、session 和 invocation 权限；问题不能描述成未认证请求无条件创建远端 session。调用使用 agent owner 的连接，owner 共享能力本身不是漏洞。已查服务端组装 daemon claim 响应时，在 Composio 启用且合并成功的条件下会将 task overlay 合入 MCP 配置；证据止于该响应构造，不能证明线上 daemon 收到、执行或使用该连接。
- 带 claim 的 `FailTaskWithTransition` 在 overlay 构建前会对已知 stale 拒绝、对同代已终态幂等返回；无 claim 的 legacy 分支和 `MaybeRetryFailedTask` 不经过该代次预读。即使经过预读，之后、远端 POST 之前仍可发生并发变化，最终任务终态 CAS 失败或后续本地事务回滚不会自动撤销已发送的 POST。远端成功而没有 retry child、超时结果未知、连接撤销与新建并发都必须分别审议，不能把已知 stale 的 fake 测试当作全部竞态已关闭。具体条件和实际远端结果仍未运行验证。

## 后续界限

后续只读复核 session `01a18d17-857c-7468-8217-4a7688522843` 请求 `OpenAIPersonal/gpt-6.1-sol:high`，actual backend 无回执记 unknown；未做 Git 字节对比、测试或部署核验。相比旧记录，本轮补充了 handler 成员边界、claim 消费路径及 retry 的终态代次区分。

在完整审查设置写者锁、事实快照/有效期、外部 session 的身份与撤销，以及真实 task 使用前，不实施预判、简化身份比较或移动调用。若属于 AIFI-45 外的既有 discussion 功能，应另行登记并按所属流程授权；不能借本 follow-up 默许扩大范围。需针对 A→B、同 A 改 owner/连接、撤销、重放/冲突/普通消息/拒绝、外部调用成功后事务失败等设计隔离无真实凭据的确定性交错测试和补偿/幂等合同。相关真实可达性、外部效果、X6 和 Gate3 均未证。

# Readiness scope 绑定实施计划

**目标**：请求级 readiness 读取必须同时匹配调用动作的 scope，防止另一个 scope 的 request ID 被复用。此改动只补本地一致性，不能证明签名、结果、时间、代次、数据库隔离或实际入口可信。

**依据**：readiness request 在 `execution_policy_readiness.go` 冻结 `request_id` 与 `scope`；共享 `signedReadinessTx` 当前仅按 ID 取行，四个调用方已持各自动作的 scope。归档 `deployment-readiness` 要求受保护实例/请求绑定和原子启动。该修复不改签名字段、不更改归档契约、不部署，不是 RUN 或 Gate3 验收。

## 单一切片

- **改**：`server/internal/governance/execution_deployment.go` 的共享查询加 `scope` 谓词及参数，四处调用分别传入自身 scope；不更改缺行的既有错误分类或 signed 原字节。
- **测**：`server/internal/governance/deploymentaccess_test/readiness_scope_test.go` 使用内存 pgx fake 模拟 request 按 scope 过滤；对 Activate、IssueAdmission、FinalizeLegacyRetirement、CheckDeploymentAccess 各测一次异 scope 拒绝且无写入、同 scope 正控。旧实现无谓词时，异 scope 必须真实走到成功/放行而非因编译或 fake 不识别 SQL 假红。
- **回归**：更新同包已有 fake 的 readiness SQL 参数期望；跑独立子包全部测试，统计实际顶层/leaf/skip。先保存已按 SHA 引用的旧版，再做 RED→实现→GREEN；完成后定向变异移除谓词并恢复，复测前后 raw SHA 一致。
- **复核**：独立审查全部调用方、是否影响 STOP_NEW 与恢复；指定快照独立复跑。禁止连接 DB、容器、真实 CR 或固定临时文件。

## 明确排除

现有 readiness verdict 未完成验签和权威时间、producer/ingress、签名命令/结果、策略/主体/代次的完整绑定；同 scope 假数据正控只是测试形状。真实 PostgreSQL 行锁、其他输入权威性、生产组合和运行中既存数据的兼容性仍需独立验收。为避免放大风险，不把当前 decider 注入 main，不调整 Gate 或 TC 状态。

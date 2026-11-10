# F4 测试与通道方案文档复核

## 来源与边界

- test_config/balanced：只读非作者会话 `01a17703-a597-77b9-a3c5-0f4afe71847c`；requested `Gobao/deepseek-flash:max`，actual unknown。仅静态读码/读取既有证据，没有动态执行。
- docs_skills/economy：只读会话 `01a17703-a5ac-77b9-a3c5-0f4d67f836e6`；requested `GB-JP/deepseek-flash:high`，actual unknown。仅文档一致性核对，不承担安全复核。
- 以下为主会话归纳及处置；不冒称原始逐字报告。

## balanced findings 与处置

- F4 判定 PASS（有限定）。确认三个处理器复用同一辅助函数；直接记录行竞争探针仅 binding 路径，不能称另外两条也分别做过该探针。
- 原测试 UPDATE 先断言使 DELETE 缺独立 RED；原 `timeout`/`canceling statement` 文本可能把非锁错误当锁冲突。**已修**：UPDATE/DELETE 各独立夹具，仅 `pgconn.PgError.Code==55P03` 为正确原因，锁超时 300ms、语句超时 3000ms、上下文 5s；提交后同一 SQL 必须成功影响一行。
- v2 RED 移除记录行锁：两条叶子各自命中业务失败，run 3 / fail 3 / leaf 0；恢复后 GREEN run 3 / pass 3 / leaf 2。扩大回归 256/256、0 fail/skip、229 PASS leaf。证据前缀 `f4-lockstate-20261026-{red,green,regression}-v2`。
- 修改后实现 raw SHA256 恢复一致（主会话计算，不冒称 reviewer 独立核 hash）。同一 balanced reviewer 后续只读复查 v2：**F4-test PASS**；独立夹具、SQLSTATE、提交后正对照三项旧弱点已闭合，256/256 证据已逐项复核。仍未动态复跑。
- 残留：另两条处理器未分别做记录行锁探针；旧 `execution_revocation_race_test.go` 的超时文本判定未改；本轮未跑 Go race detector。当前同步 hook 捕获变量仅在 handler 同步调用条件下成立，不把未来异步用法纳入本结论。
- 证据限制：runner meta 不记录源码 freeze；不能用事后 manifest 冒称当时已冻结。实现变异前/恢复后的 hash 对比来自主会话工具记录，事后 source manifest 仅标当前快照。
- probe 用例只证明行锁，不证明完整授权；跨租户/悬空头的新增辅助函数分支不冒称已有直接 HTTP 竞争测试。
- 通道 v0.1 §7 判定 INSUFFICIENT-AS-WRITTEN：缺实际命令、迁移清单、tools 根环境、允许测试包、业务 RED、S1/S4/S7 正对照，以及不同 OS 身份探针；这些进入 v0.2 修订要求。
- runner 自带 `-timeout=180s`；模板不额外重复指定 timeout。新 Go 测试落现有 approved package，不改 runner 白名单。跨仓用例显式 `AIFI45_TOOLS_ROOT`，SKIP 不算通过。

## economy findings 与处置

- 保留原作者草案/历史评审正文，增加醒目的当前状态与来源 cutoff；F4 已修，其他接口未实现。
- 已在 dispatch-admission-design 顶部声明 F4 执行状态；strong BLOCK 仅针对已撤回 RUN-009 补丁，不是 F4/Gate 总结。
- 台账增量 16 标题和 RUN-009 条目就地标注已撤回，原 RED/审核过程仍保留；增量 17 登记补强，不增加 TC。
- 新 channel 未登记，只有建议 ID。方案保存在 AIFI-45 validation 是依赖说明，不表示新 change 已注册或实施。
- TC-RUN-002/003/006/010 是 AIFI-45 验收编号：channel 产出依赖证据，不能自动回填 AIFI-45 或跨 change 双计。台账保持 41/49；全量 Gate 仍 NO-GO。

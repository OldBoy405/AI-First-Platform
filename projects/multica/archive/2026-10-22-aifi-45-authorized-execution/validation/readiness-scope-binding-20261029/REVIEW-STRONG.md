# Readiness scope 防串用：独立静态复核

复核者：请求 strong（`GBClaude/claude-opus-5-5:high`），实际 backend receipt unknown；只读、未运行测试/DB/容器/CR。复核者无 SHA 工具，下面 hash 由作者记录、**非复核者独立核验**。结论适用于作者报告的 final 源 `7b9078db96c6a54b9cb87c040bedfb7b346d8c1a4a77b772367fa94063e3268a` 与对应 `source-final/`；非正式 Gate 或 RUN。

- 四处调用分别传入自身 `in.Scope`/`scope`，查询参数 request ID 再 scope；只过滤 DB 行，不验证调用方 scope 的权威性、签名 scope、签名 outcome、generation、target、workset、权威时间。原 payload 未重编码。
- STOP_NEW 正常 event 无 verdict_ref，不进入该查询；已存在的 ACTIVE event 若关联其他 scope 的 readiness，audit 与过期 exact recovery 也从原先放行变为 NotReady 错误。旧数据、运维/恢复兼容性未核，不应将局部结果称为生产完成。
- fake 使用 SQL 条件与参数来模拟过滤；RED 中六个跨 scope 分支确实继续到成功或对应分类，同 scope 正控通过。正则不识别所有 SQL 变体；完整子包中另有严格 SQL/参数匹配。RED/GREEN/MUTATION 是作者提取的事件，不是 PostgreSQL 证据；变异体原始源码未存档。

**后续测试增量**：上述复核针对当时的 `source-final/` 测试。后来在 `source-audit-final/` 仅扩展 fake-Tx 审计矩阵至五种操作、三种状态；`AUDIT-RED.json` / `AUDIT-GREEN.json` 为作者派生结果，不能反过来归称为本次 strong 复核或真实数据库证明。

## 新识别的既有锁序风险（静态推论，未在真实 DB 复现）

1. **Medium：Activate / Finalize 可能构成双事务死锁。** Activate 先锁 readiness R，再锁 deployment head H；Finalize 先锁 H，再锁 R。若 H 为 DRAINING，Finalize 被传入同一个 enable-policy request，且 revision/generation 通过，会形成 R→H 与 H→R；Finalize 在取得 R 后才核 action。此顺序在本次改动之前已有，本次仅使 R 的 scope 必须匹配，不能声称已消除。真实报错、超时和影响范围未验证。
2. **Low：三事务环可能存在。** Activate 锁 readiness→deployment head→activation head；Issue 锁 activation head→readiness。若同一 readiness 可跨 target 重用，两个 Activate 加一个 Issue 有可能组成环。依赖现有 target/replay 绑定缺口，未动态复现；不得推断实际部署或可利用性。

后续需先确定全局锁图、冻结 request action/target 及 writer 的权威来源，再设计回归；任何 `FOR SHARE`、死锁或竞争证明须使用受批准 runner 的隔离 PostgreSQL、精确锁超时/SQLSTATE、正控和资源回执。当前结果只允许作为局部默认拒绝；Gate3 和相关 RUN 继续未通过。

# RUN-009 绑定候选 strong 静态复审

请求 `GBClaude/claude-opus-5-5:high` 的独立会话 `01a186bf-706e-7020-aecc-d2b2692ea9cd` 正常完成；actual backend 回执 unknown。只读候选报告、gap 报告、canonical RUN 要求和 `multica/server/internal/governance/gate_projection.go`，未运行 DB/测试/容器或改源码；作者报告中涉及 crsync/crevents/crctl/runner 的路径**未由该评审者独立复核**。结论是方案与实现准备 **BLOCK**，不是已复现并发，也不是 Gate/TC 判定。

## 新增具体静态观察

- `gate_projection.go:141-180,374,408-415`：没有活跃 run 时投影先新建 run，再在该 run 内查最大 attempt；旧轮迟到事件因新 run 无旧节点而可能绕过轮次过期检查。同一把锁不能取代原始 run 身份。
- `:153-163`：新 run 的 `started_by` 使用工作区最早 owner 兜底，并不证明该用户实际启动了执行。
- `:383-390`：除 dev-plan 上游修复特例外，`attempt < 1` 在服务端被改成 1；严格绑定路径不能把这一兼容行为直接当可信轮次。
- `:417-430`：同 run/node/attempt 的 detail 使用 `jsonb ||` 后写覆盖同名字段，非 facts-only 分支也覆盖 status；不具备候选方案所需的已核验事实不可静默替换规则。
- `:408-430` 的读取和写入、`:297-311` 的 node/run 终态更新分别使用 pool 调用，现状未形成覆盖这些动作的同一事务；不能将候选中的共同事务/同步域视为已有事实。
- `completeRun`（`:260-267`）排除 runner 标记的 run；`cancelActiveRuns`（`:297-311`）对该 CR 所有活跃 run 生效，包含 runner run。关闭、取消及 Runner 写者的归属需一起决定。评审还指出部分投影调用路径吞错；本条不推断部署状态。
- `:367` 对**payload 自报**空 `cr-id` 有历史兼容，不等于事件 `ev.CRID` 为空；`:399-400` 只拒绝顶层 `runner` reserved key。严格身份不能无条件把前者当成已核验权威。
- `:216-224` 的 approve 关联按 workspace/CR/stage 和最新时间查询，未绑定 run/cycle；重读下一轮审批归属需要另行设计。

以上风险来自静态代码，具体可达性与竞态需要经审批的隔离环境验证；不把投影行为直接等同真实权限提升。

## 需决定的边界与无 DB 下一步

优先明确原始 run/cycle 权威与 wire 影响、legacy 的空自报/缺 attempt/cycle 存量处置、事实补全与冲突、共同同步域与终态所有权、pending 上限及终结规则、重判时撤销/STOP_NEW/resume 核验；任何签名合同修改须单独评审。建议先只读盘点 outbox / commit-scan / annotation 字段及绑定、所有终态写者和锁、现存 legacy 形状，再构造纯模型决策表覆盖旧评审晚到、新评审早到、先不完整后丰富、冲突及服务端 attempt 兜底。纯模型不能证明 SQL 锁、真实入口或身份；真实 SQL 必须使用版本化隔离入口和合格清理回执。

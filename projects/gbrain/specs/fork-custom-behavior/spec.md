# Spec: fork-custom-behavior

> Change: 2026-11-24-upstream-sync-58352363d0 | Auto-generated Human View

## Requirements

### Requirement: Inbox 工作流保留处理顺序与实际写入内容

#### Scenario: SC-FCB-001

- **GIVEN** 候选包含 fork ingest-capture 预处理和 importAs/managed put_page 写入路径；FORK 的 managed 分支已确认存在未消费预处理内容的基线缺口
- **WHEN** 对带 provenance 的 Inbox 捕获分别执行 unmanaged 与 managed 入库并读取落库页面
- **THEN** SHALL 使两条分支的实际页面都消费处理后的 frontmatter/content，且 provenance 与工作流状态可核对
- **AND** 不得只断言预处理函数返回值
- **AND** auto-link SHALL 保留上游自读快照和权限守卫
- **AND** 基线缺口修复与合并引入变化 SHALL 分别归因

### Requirement: Admin op 代理保留鉴权优先和独立审计

#### Scenario: SC-FCB-002

- **GIVEN** 候选包含 CUSTOM ADMIN ROUTES 和 serve-http-admin-op
- **WHEN** 分别以无会话和合法会话调用 POST /admin/api/op
- **THEN** SHALL 使无会话请求在分派前被拒绝，合法会话可达且仅产生一条 Admin 独立审计
- **AND** 不得放松 requireAdmin 或 source/scope 限制
- **AND** 不得复制 /mcp 请求日志

### Requirement: 查询 trace 保持可选信封和诊断元数据

#### Scenario: SC-FCB-003

- **GIVEN** 候选保留 query.trace 参数、op emitResponseMeta、MCP _meta 和 CLI/Ask 消费路径；FORK 的 trace 摘要未承载完整检索诊断
- **WHEN** 以 trace 开、关和空结果三种输入执行查询，并经 MCP/Admin client 消费
- **THEN** SHALL 在 trace.retrieval 保留 op 实际 emit 的完整 retrieval meta（含 evidence/page cap/degraded/explain-target），在关闭时保持上游结果形状
- **AND** MCP _meta.retrieval SHALL 独立保留同一诊断对象，Admin client 不得丢弃 _meta
- **AND** 空结果 SHALL 不丢失信封或诊断字段
- **AND** 未启用 fork 分支时 SHALL 不改变默认行为

### Requirement: Graph 扩展保留两引擎列、规模护栏和可见性

#### Scenario: SC-FCB-004

- **GIVEN** 候选保留 graph_overview、traversePaths* 和 fork 默认上限；FORK 的 graphOverview 已确认缺少 private/origin 过滤
- **WHEN** 在 PGLite 与实际执行的 Postgres 上运行 Graph 定向、source-isolation 和 op remote 检查
- **THEN** SHALL 使 both 方向返回 to_title/to_type，source/private/软删除过滤和行上限生效，graphOverview 的 degree、节点和边均不受不可见端点或 private origin 污染
- **AND** PGLite plannerRead SHALL 保留
- **AND** PGLite 与 Postgres 均实际执行且 skip=0；任一缺失时本 Scenario SHALL 判定未通过
- **AND** 基线缺口修复与合并引入变化 SHALL 分别归因

### Requirement: 其余已登记 fork 能力与技能路由保持可达

#### Scenario: SC-FCB-005

- **GIVEN** 台账仍保留的 AI、Truth、Jobs、MCP、Admin SPA、构建与文档增量
- **WHEN** 运行 AI/Truth/Jobs/op 合同/Admin 测试并检查生成后的注册与路由
- **THEN** SHALL 使受影响能力在实际加载路径可达，且无重复注册或已上游化旧实现回流
- **AND** skills RESOLVER SHALL 同时包含 fork 技能触发和上游 atom_fence_rows 路由
- **AND** 类型镜像与 Admin client 合同 SHALL 不因合并漂移

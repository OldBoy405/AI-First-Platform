# Spec: ci-backend-environment

> Change: 2026-11-19-delivery-quality-baseline | Auto-generated Human View

## Requirements

### Requirement: 交付检查入口消费本次已配置的隔离环境，缺失前置条件或子步骤失败不能报告成功。

#### Scenario: SC-DQB-CBE-001

- **GIVEN** 已有 Go wrapper、一次性库和 CI 接线夹具可记录参数、环境、生命周期及退出状态，不连接真实服务。
- **WHEN** 验证完整输入、缺失 nonce 或必需夹具、注入 Go 非零、夹具准备失败，以及记录写入或创建结果不明。
- **THEN** SHALL 成功时 regular、admin、agent 各调用一次；缺必需输入时不启动测试；Go 非零时入口返回非零。
- **AND** 管理员 URL SHALL 仅由外层供给回收或既有 admin 命令使用，regular 只继承受限常规与夹具库连接，agent 不继承数据库、nonce 或 Redis 测试环境。
- **AND** 夹具供给 SHALL 按固定案例提供独立库和非 CREATEDB 角色，缺失或重复绑定不能回落到共享库；夹具文件 SHALL 含测试名→DSN 映射和无密码的主库及夹具身份，在对应资源创建前记录预留、确认创建后记录已确认。首次记录写入未成功时不得创建资源；后续记录更新失败时 SHALL 保留上次完整记录。
- **AND** 验收入口 SHALL 不读取普通 .env 或降级到默认数据库。
- **AND** 指定夹具文件的外层回收 SHALL 只以文件内身份为准，不消费环境变量句柄；文件缺失、无效或必需身份缺失时硬失败。已确认身份中仍存在的库和角色须分别重读 marker、全部匹配后才可删除任一对象；创建未确认的预留身份不得自动删除，须保留记录并报错，即使 marker 相同或暂未发现对象也不例外。全部身份确认无残留后才移除记录；连接错误或归属不明时保留记录，可能须人工核实。未指定夹具文件的现有回收路径不变。

### Requirement: 全量后端检查必须复用现有 CI 分组和对账，使用本次专用库执行，不把跳过或未执行当成通过。

#### Scenario: SC-DQB-CBE-002

- **GIVEN** 代表性非 root Linux 干净候选、同一经批准 pin 的 Tools、本次新建并迁移的常规库及每案独立夹具库、既有独立管理员环境就绪。
- **WHEN** 运行配置所列的后端全量检查命令。
- **THEN** SHALL regular、admin、agent 均成功并产生实际结果；regular 与 admin 的事件流均由现有对账器确认。
- **AND** 现有必需包、所有权和许可跳过约束 SHALL 保持；任何名单外跳过、未运行的必需测试或异常退出不得计作通过。allowed-skips SHALL 由 11 补全至 20，新增 9 条为平台/helper 合法 skip（systemctl/pwsh 缺件、macOS layout、subprocess helper），附源码行号与触发条件；该补全不把任何功能失败计作通过。
- **AND** 同次质量验收 SHALL 确认隔离夹具实际执行、不污染共享库，且记录本轮受管库和角色的迁移与回收；未回收不得计为完整通过。
- **AND** 已有托管 CI 与独立测试归属 SHALL 保留；现有 hosted 后端 job 仅为同一夹具合同补供给、凭据隔离、回收与 regular 包级串行，不以本地成功替代 hosted 实际结论。
- **AND** 如更换 Tools pin，SHALL 在正式 run 前取得单独采用授权及真实规则 allow/deny、crctl 兼容结果；正式运行 SHALL 使用同一不可变提交的规则和 crctl，不得混用。
- **AND** 迁移测试 SHALL 使用现行真实 SQL 保留上／下迁移与不合法数据断言；Pi SHALL 对每个已绑定路径只追加一次技能参数，OMP 原发现行为不变。

# Spec: upstream-sync-merge

> Change: 2026-11-24-upstream-sync-58352363d0 | Auto-generated Human View

## Requirements

### Requirement: 冻结且可回滚的同步输入与隔离候选

#### Scenario: SC-USM-001

- **GIVEN** FORK=8f0e2d9998、UPSTREAM=17b68cef、BASE=553b547334 和 pre-sync/2026-11-24-58352363d0 已登记
- **WHEN** 核对 Git 祖先、提交计数、目标 VERSION 与回滚锚点
- **THEN** SHALL 确认 59 个 fork 侧提交、13 个上游侧提交、BASE 为共同祖先且目标 VERSION 为 0.60.638.0
- **AND** 回滚锚点 SHALL 指向 FORK
- **AND** 主工作区 SHALL 未发生合并且本地未跟踪状态未被暂存

### Requirement: fork 增量完整归因且按三方行为裁决

#### Scenario: SC-USM-002

- **GIVEN** 台账 #1–#32、生成物登记和相对 BASE 的 516 个 fork 改动
- **WHEN** 对 6 个双边改动路径和 66 个上游单侧路径做三方核对
- **THEN** SHALL 使每个仍保留的 fork 改动对应台账编号或生成物真源，无法归因项为零
- **AND** 已上游化行为 SHALL 无双实现
- **AND** 上游新行为 SHALL 保留

### Requirement: 两个文本冲突按真源和门禁语义解决

#### Scenario: SC-USM-003

- **GIVEN** merge-tree 预测 scripts/module-size-limits.tsv 与 skills/skills.lock.json 冲突，另有四个双边改动文件
- **WHEN** 处理 TSV、RESOLVER、skills.lock、plugin README 与 llms-full
- **THEN** SHALL 保留 11 行 module-size fork 例外、11 行 page-body fork reviewed rows 和 fork 技能路由，同时吸收上游新 ratchet 与 atom_fence_rows 路由
- **AND** skills.lock SHALL 由生成器产出
- **AND** plugin README 与 llms-full SHALL 由各自真源产出

### Requirement: 无文本冲突的上游行为变化与 fork 调用链兼容

#### Scenario: SC-USM-004

- **GIVEN** 上游在 persistence/cycle/repair 的 17 个源文件有 344 insertions/45 deletions，fork 写入链未被 Git 标为冲突
- **WHEN** 执行恢复文件、保留已提交文件、purge、world-row atom 读取和 repair 的定向验证
- **THEN** SHALL 证明恢复/清除/读取的实际结果符合上游新合同且不破坏 fork provenance、权限与写入顺序
- **AND** 测试 SHALL 断言文件、页面状态、可见性或脱敏字段等观测值
- **AND** 仅编译或标记存在 SHALL 不作为行为证据

### Requirement: 迁移编号与注册关系保持有效

#### Scenario: SC-USM-005

- **GIVEN** 上游 latest 仍为 v297，fork Inbox 迁移为 v298，窗口无新增迁移
- **WHEN** 重生成 registry/latest 并执行迁移顺序与 registry 测试
- **THEN** SHALL 保持 v298 为唯一 inbox_workflow_frontmatter 且顺序检查以冻结 UPSTREAM 为 base ref 通过
- **AND** 不得引入 v299–v331 的未合入迁移
- **AND** 未执行旧库结构探针时 SHALL 明确数据库升级未验证

### Requirement: 生成物可重复且相对候选无漂移

#### Scenario: SC-USM-006

- **GIVEN** 真源和手工基线已裁决，相关生成物已整组暂存
- **WHEN** 运行生成、freshness 检查和第二次同输入生成
- **THEN** SHALL 使 check:regen-all 与 check:admin-embedded 通过且第二次生成不改变候选暂存区
- **AND** Admin 嵌入清单 SHALL 来自根 build:admin
- **AND** 不得手拼 lock、registry、嵌入清单或金标准

### Requirement: 高风险 fork 行为保持并取得定向证据

#### Scenario: SC-USM-007

- **GIVEN** 合并候选保留 Inbox、Admin、query.trace 和 Graph fork 增量，并明确三项 FORK 既有基线缺口的最小修复边界
- **WHEN** 运行 ingest-capture/inbox、Admin route guard、trace 与 Graph 定向回归，对照固定 FORK 的 A/B 结果
- **THEN** SHALL 证明 Inbox 实际写入处理后的 frontmatter/content/provenance，Admin 先鉴权后分派且审计不重复
- **AND** trace 开启 SHALL 在 trace.retrieval 保留完整上游诊断且 Admin 不丢弃 _meta，关闭 SHALL 保持原结果形状
- **AND** Graph SHALL 在 source/private/软删除约束下保留两引擎必需列，总览 degree 与边不得被不可见数据污染
- **AND** 三项基线缺口与合并引入变化 SHALL 分别归因

### Requirement: 质量门禁与测试结果来自候选树

#### Scenario: SC-USM-008

- **GIVEN** 候选生成物稳定且使用 Bun 1.4.4 隔离环境
- **WHEN** 执行 typecheck、根单测、Admin 测试和所需定向/E2E 检查
- **THEN** SHALL 记录每条命令的 run、rc、耗时和结果，新增回归为零
- **AND** 未运行、跳过或超时 SHALL 明确标为未验证
- **AND** 固定 FORK 同项同因失败 SHALL 与新增回归分开

### Requirement: 候选可审计且交付边界清晰

#### Scenario: SC-USM-009

- **GIVEN** 候选源码、测试、生成物和台账已完成
- **WHEN** 执行 ls-files -u、cached diff --check、双父 diff 与分支状态审计
- **THEN** SHALL 无未解决冲突、无本轮新增 whitespace 告警，所有新增/删除/改名/上游吸收均有解释
- **AND** 台账 SHALL 记录 SHA、裁决、验证和未跑项
- **AND** Gate 3 前 SHALL 未合入 master、未推送、未部署、未执行生产迁移

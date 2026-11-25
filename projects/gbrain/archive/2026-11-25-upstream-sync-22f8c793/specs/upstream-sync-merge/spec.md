# Spec: upstream-sync-merge

> Change: 2026-11-25-upstream-sync-22f8c793 | Auto-generated Human View

## Requirements

### Requirement: 冻结且可回滚的同步输入与隔离候选

#### Scenario: SC-USM-001

- **GIVEN** FORK=2e50b638f2、UPSTREAM=22f8c793b1、BASE=17b68cef4f 已确定，回滚锚点为 pre-sync/2026-11-25-2e50b638f2
- **WHEN** 在独立同步 worktree 中核对 Git 祖先、左右提交计数、目标 VERSION 与回滚锚点
- **THEN** SHALL 确认 BASE 为共同祖先、FORK 侧 62 提交、UPSTREAM 侧 2434 提交且 UPSTREAM VERSION 为 0.60.772.0
- **AND** 回滚锚点 SHALL 解析到 FORK
- **AND** 主工作区 SHALL 未发生合并、未被切分支且本地未跟踪状态未被暂存

### Requirement: fork 增量继续完整归因

#### Scenario: SC-USM-002

- **GIVEN** 台账 #1–#32、生成物登记和相对 BASE 的 527 个 fork 改动路径
- **WHEN** 逐路径核对候选仍保留的 fork 改动与上游吸收项
- **THEN** SHALL 使每个仍保留的 fork 改动对应台账编号或生成物真源，无法归因项为零
- **AND** 已上游化行为 SHALL 无双实现
- **AND** 上游新行为 SHALL 保留且不整片选边

### Requirement: 67 个双边路径按行为裁决且门禁基线一致

#### Scenario: SC-USM-003

- **GIVEN** 两边相对 BASE 均改动的 67 个路径清单，以及按路径登记的 module-size、page-body-readers、core-world-reads 基线
- **WHEN** 按 A–F 类别逐行裁决并贴回上游新增 ratchet 与 fork 门禁行
- **THEN** SHALL 产出覆盖全部 67 条路径的裁决记录，且 check:module-size、check:page-body-readers、check:core-world-reads 在候选树上通过
- **AND** 迁移改名后所有按路径登记的基线 TSV SHALL 同步改名或按守卫出口调整
- **AND** 生成物与锁文件 SHALL 由生成器或包管理器重建，不手拼冲突块
- **AND** 技能路由 SHALL 同时保留 fork 触发词与上游新增路由，无重复注册

### Requirement: 上游窗口改动路径完成覆盖核对

#### Scenario: SC-USM-004

- **GIVEN** 相对 BASE 的 5879 个上游改动路径，其中多数不产生文本冲突
- **WHEN** 按目录、迁移区间与高风险链路（引擎、鉴权、来源隔离、Inbox、Admin、op 合同、生成器）核对上游新合同
- **THEN** SHALL 证明 Inbox、Admin、query.trace、来源隔离和权限行为在候选树上保持，且无未核对的改动块
- **AND** 无文本冲突的共享文件 SHALL 有行为级核对结论，不以文件存在或编译通过代替
- **AND** 上游删除与改名路径 SHALL 有对应 fork 增量的去向说明

### Requirement: fork Inbox 迁移顺延到上游 v336 之后且注册唯一

#### Scenario: SC-USM-005

- **GIVEN** 上游迁移区间 v298-attest-read 至 v336-files-follow-page-slug，fork 迁移原为 v298-inbox-workflow-frontmatter
- **WHEN** 把 fork 迁移顺延为 v337 并重建 registry/latest，执行顺序检查、registry 测试与空库升级探针
- **THEN** SHALL 保持全部迁移 version 唯一、上游迁移原号原内容、fork 迁移位于 v336 之后且 SQL payload 不变
- **AND** check:schema-migration-order SHALL 以冻结 UPSTREAM 为 base ref 通过并报告 1 条新迁移
- **AND** 空 PGLite 库 SHALL 升级到 337 且第二次运行 applied 数为 0
- **AND** 旧 fork 库（config.version=298）缺失上游 attest_read DDL 的偏差与补偿方案 SHALL 登记在台账，不在本轮执行生产迁移

### Requirement: 生成物由真源重建且二次生成无漂移

#### Scenario: SC-USM-006

- **GIVEN** 真源与手写基线已裁决，相关生成物已整组暂存
- **WHEN** 运行 regen:all、check:regen-all、build:admin、check:admin-embedded，并以相同输入第二次生成
- **THEN** SHALL 使 freshness 检查全部通过且第二次生成相对候选暂存区不产生任何改动
- **AND** Admin 嵌入清单 SHALL 来自根 build:admin，admin/bun.lock SHALL 在 admin/ 下重算并通过冻结锁复验
- **AND** 不得手拼 registry、嵌入清单、lock 或金标准
- **AND** VERSION SHALL 为 0.60.772.0 且与 package.json、CHANGELOG 版本门禁一致

### Requirement: 候选树取得质量信号且失败逐条定性

#### Scenario: SC-USM-007

- **GIVEN** 候选生成物稳定，验证在隔离环境与冻结 Bun 版本下执行
- **WHEN** 执行 typecheck、受影响定向回归、Admin 测试套件与必要的 PGLite E2E
- **THEN** SHALL 记录每条命令的 rc 与结果，新增回归为零
- **AND** 失败项 SHALL 对照固定 FORK 的同项同因基线定性，区分既有失败与合并回归
- **AND** 未运行、跳过与超时 SHALL 明确标为未验证，不冒充通过

### Requirement: 候选可审计、台账完备且交付边界清晰

#### Scenario: SC-USM-008

- **GIVEN** 候选源码、测试、生成物与台账已完成
- **WHEN** 执行 ls-files -u、cached diff --check、双父 diff 审计与台账检查
- **THEN** SHALL 无未解决冲突、无本轮新增 whitespace 告警，所有新增/删除/改名/上游吸收均有解释
- **AND** CUSTOM-LEDGER SHALL 记录本轮 SHA、67 条裁决汇总、迁移映射、验证结果与未跑项
- **AND** Gate 3 前 SHALL 未提交、未合入 master、未推送、未部署、未执行生产迁移、未创建 release tag

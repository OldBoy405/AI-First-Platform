# Spec: upstream-sync-merge

> Change: 2026-10-26-upstream-sync-2568d32ac8 | Auto-generated Human View

## Requirements

### Requirement: 二开能力在合并后保持可编译、可注册、可回归

#### Scenario: SC-001

- **GIVEN** 在 sync/upstream-2026-10-26-2568d32ac8 上完成 merge upstream/master
- **WHEN** 执行 bun run typecheck
- **THEN** SHALL 输出 0 个类型错误
- **AND** inbox / truth / graph_overview 的 op 在 operation-manifest、operation-loaders、operation-load 三处均有登记

#### Scenario: SC-002

- **GIVEN** 合并完成且生成物已重跑
- **WHEN** 执行定向回归 test/inbox-workflow.test.ts、conflicts.test.ts、compile-truth.test.ts、graph-overview.test.ts、traverse-paths-metadata.test.ts
- **THEN** SHALL 全部通过，0 fail
- **AND** test/ingestion/ingest-capture.test.ts 的 inbox 分支用例 SHALL 通过

#### Scenario: SC-003

- **GIVEN** 合并完成
- **WHEN** 执行 grep -rn "CUSTOM ADMIN ROUTES" src/ 与 grep -c "CUSTOM (Qoder)" AGENTS.md
- **THEN** SHALL 分别命中 2 行（均在 src/commands/serve-http.ts）与 4 行
- **AND** test/serve-http-admin-route-guard.test.ts SHALL 通过

### Requirement: 迁移编号不冲突，DDL 不被静默跳过

#### Scenario: SC-004

- **GIVEN** inbox_workflow_frontmatter 已从 239 顺延到 275
- **WHEN** 执行 GBRAIN_MIGRATION_BASE_REF=upstream/master bun run check:schema-migration-order
- **THEN** SHALL 输出 above upstream/master's latest v274 (275)
- **AND** src/core/schema-migrations 下 SHALL 不存在重复的 version 值

#### Scenario: SC-005

- **GIVEN** 迁移已应用到一个空库
- **WHEN** 用 information_schema 查询 inbox_workflow_frontmatter 的 DDL 目标列
- **THEN** SHALL 查到该列存在，且证据不来自迁移日志

#### Scenario: SC-006

- **GIVEN** 合并后的工作树
- **WHEN** 执行 bun run build:schema-migrations && bun run check:schema-migrations
- **THEN** SHALL 绿，registry.generated.ts 与 latest.generated.ts 含 v275 且为生成器输出

### Requirement: 生成产物由生成器重建，freshness 门保持绿

#### Scenario: SC-007

- **GIVEN** 冲突中涉及 7 个生成物文件
- **WHEN** 按顺序执行 build:schema-migrations → regen:all → regen:all --goldens → build:admin → build:llms
- **THEN** SHALL 无手工 resolve 痕迹（生成物改动均来自生成器）
- **AND** bun run check:regen-all SHALL 绿

#### Scenario: SC-008

- **GIVEN** 生成物已重建
- **WHEN** 执行 bun run check:tool-catalog、check:skills-manifest、check:plugin-tree、check:structural-manifest、check:module-size
- **THEN** SHALL 全部绿
- **AND** scripts/module-size-limits.tsv 中 fork 上调的 9 行 SHALL 保留 GBrain Custom 标注

### Requirement: 失败项逐条定性，不把环境问题当合并事故

#### Scenario: SC-009

- **GIVEN** bun run verify 出现失败项
- **WHEN** 在 pre-sync/2026-10-26 worktree 上实测同一检查
- **THEN** 既有失败 SHALL 命中《已知测试失败基线》；非既有失败 SHALL 当场解释并修复
- **AND** test-report.md SHALL 列出每条失败的命令、输出与定性

#### Scenario: SC-010

- **GIVEN** 全量 bun run test 在 Windows 下出现 shard 统计异常或挂死
- **WHEN** 改用定向 bun test <paths> 取信号
- **THEN** SHALL 记录为环境基线，不据此判定合并失败

### Requirement: 台账与本轮记录反映合并事实

#### Scenario: SC-011

- **GIVEN** 合并与验证完成
- **WHEN** 阅读 CUSTOM.md《阶段记录》
- **THEN** SHALL 出现 2026-10-26 本轮记录（窗口、迁移顺延、尺寸棘轮、基线变化、欠债登记）
- **AND** SHALL NOT 修改任何历史阶段行

#### Scenario: SC-012

- **GIVEN** 合并后的工作树
- **WHEN** 按台账明细表逐行 grep 文件与符号
- **THEN** SHALL 全部命中；未命中的 SHALL 进《已上游化》或从台账删除

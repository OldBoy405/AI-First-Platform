# 上游同步 v0.60.176.0 → v0.60.461.0（gbrain fork）

<!-- source_hash: 60b47ae50d992ad8 -->
<!-- generated_at: 2026-10-26T16:05:23.059803 -->
<!-- canonical: canonical/proposals/2026-10-26-upstream-sync-2568d32ac8.yaml -->

## Why

fork 停在 upstream v0.60.176.0（2895edb3c6），上游已到 v0.60.461.0（2568d32ac8）：
5333 提交、4804 个改动文件，跨度 285 个 release stamp，违反 CUSTOM.md
《合并守则·小增量、频繁合并》（>2 release 即欠债）。
同时上游本窗口新增 36 个迁移（v239..v274），与我方 inbox_workflow_frontmatter
占用的 v239 同号——迁移 runner 只按版本号记 schema_version，同号会导致一方 DDL
被静默跳过（v133 事故同类风险）。


## What Changes

- 台账修复（Gate 1 前置，已提交 1b8e921983）：补登 json-repair 导出、tsconfig 路径别名、doctor 类别守卫三项；7 个「相关 tests」回归行改为逐文件清单；修正 3 处与 git 事实不符的状态描述；登记 .stdd/ 勿提交。
- 在 sync/upstream-2026-10-26-2568d32ac8 分支上 merge upstream/master（2568d32ac8，冻结窗口 2895edb3c6..2568d32ac8）；master 不动，基线标签 pre-sync/2026-10-26。
- 迁移号顺延 239 → 275（文件名 v275-inbox-workflow-frontmatter.ts、导出名 v275、version 字段、registry.generated.ts/latest.generated.ts 注册行四处同改），并用 GBRAIN_MIGRATION_BASE_REF=upstream/master 探针验证。
- 19 个真实冲突按守则裁决：贴回挂钩 8（cli/main、operations、operation-load、ops/jobs、ops/links、ops/search、engine、engine-sql/links）、取并集 3、生成物重跑 7、重估 1；另有 28 个可干净合并但必须逐条核挂钩（serve-http.ts 的 CUSTOM ADMIN ROUTES、AGENTS.md 的 CUSTOM (Qoder) 围栏等）。
- 生成产物一律不手工 resolve：bun run regen:all + regen:all --goldens（SQL 金标准四个文件），再跑 build:admin + build:llms；check:regen-all 的 freshness 门必须绿。
- 合并后在 CUSTOM.md《阶段记录》追加本轮记录（含欠债登记、迁移顺延、尺寸棘轮调整、基线变化），历史行不回填。

### Modified Capabilities

- **Inbox 工作流与真理沉淀**：ops/inbox.ts、ops/truth.ts、inbox.ts、conflicts.ts、compile-truth.ts、inbox-enrich.ts 与 275 号迁移在上游新代码结构下保持可编译、可注册、可回归。
- **Graph 规模护栏与遍历元数据**：traversePaths/traversePathsDetailed 的 frontierCap + to_title/to_type、graph_overview op，贴回 engine-sql/links.ts 与 ops/links.ts 的新位置。
- **Jobs / Query / CLI 诊断面**：execution_lane、query trace 信封、CLI 空结果解包两处在上游拆分后的 cli/main.ts 与 ops/* 中保持有效。
- **Admin 双表层与 cookie 代理**：CUSTOM ADMIN ROUTES 挂钩块在 serve-http.ts、serve-http-admin-op.ts 独立文件、Admin 落地哈希路由，全部在合并后仍被引用且被既有守卫测试覆盖。
- **AI 提供方（Ollama 维度 / DeepSeek 配置）**：dimsProviderOptions 的 providerId 分支、DEEPSEEK_BASE_URL、deepseek_api_key → env 注入，与上游 trust_custom_dims 及原生 base-URL fold 并存。

## Success Criteria

- [ ] §0 台账新鲜度四维全部 FRESH，修复提交独立于代码改动之外（已完成：1b8e921983）。
- [ ] 合并后 src/core/schema-migrations 中不存在重复 version：inbox_workflow_frontmatter SHALL 为 275，且 GBRAIN_MIGRATION_BASE_REF=upstream/master bun run check:schema-migration-order 输出「above upstream/master's latest v274 (275)」。
- [ ] inbox_workflow_frontmatter 的 DDL 探针 SHALL 在迁移日志之外独立验证产物列存在（information_schema 探针），不只看 applied 记录。
- [ ] grep -rn "CUSTOM ADMIN ROUTES" src/ SHALL 命中 2 行且位于 src/commands/serve-http.ts；grep -c "CUSTOM (Qoder)" AGENTS.md SHALL 为 4。
- [ ] bun run typecheck SHALL 0 错误；bun run regen:all 与 regen:all --goldens 后 bun run check:regen-all SHALL 绿。
- [ ] 定向回归（test/inbox-workflow、conflicts、compile-truth、graph-overview、traverse-paths-metadata、retrieval-op-redaction、engine-surface-coverage、operation-manifest、parity）SHALL 全绿。
- [ ] cd admin && bun run test SHALL 全绿，bun run build:admin 后按 admin/docs/TYPE-MIRROR-CHECKLIST.md 人工对照无差异。
- [ ] bun run verify 的失败项 SHALL 逐条归类：命中《已知测试失败基线》或当场解释，不允许笼统归因「上游新增/已知基线」。
- [ ] CUSTOM.md《阶段记录》SHALL 追加本轮记录，且不修改任何历史阶段行；台账明细表 SHALL 与合并后的工作树可 grep 核对。

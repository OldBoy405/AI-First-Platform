# Gate 2 裁决矩阵：2026-10-26-upstream-sync-2568d32ac8

> 依据：CUSTOM.md《合并守则》（台账唯一事实源 / 上游为基底 / 加法优先 / 功能重叠→上游胜出 /
> 标记挂钩无论是否冲突都核对 / 生成产物不手工 resolve / 减法定制重估 / 迁移号顺延）。
> 窗口：`2895edb3c6..2568d32ac8`。真实冲突 19 个（`git merge-tree --write-tree`），
> 两边都改但可干净合并 28 个。逐行裁决如下，Gate 3 按本表执行。

## A. 真实冲突 19 个（逐文件裁决）

| # | 文件 | fork 侧（台账依据） | 上游侧（本窗口） | 裁决 | 合并后验证 |
|---|------|--------------------|------------------|------|-----------|
| A1 | `src/cli/main.ts` | +7/−1：`--json` 空结果解包两处（`search` 数组分支 + `query --trace` 信封） | +134/−186：CLI 大重构 | **上游基底 + 贴回两处**：`Array.isArray(result)` 分支与 `{...result, results}` 信封保留在重构后的输出路径 | `bun test test/cli-goldens`；`bun run src/cli.ts query --trace --json` 不崩 |
| A2 | `src/core/engine-sql/links.ts` | +98/−26：`traversePaths`/`Detailed` 的 `frontierCap` + `to_title`/`to_type`；`graphOverview` SQL | +261/−213：新增 temporal walk filter、`addLink` 扩展等 | **上游基底 + 贴回 SQL 增量**（`sqlFragment`/`renderFragment` 渲染口径不变） | `GBRAIN_TEST_UPDATE_GOLDENS=1 bun test test/engine-sql-sql-text*.ts` 后 `bun test test/traverse-paths-metadata.test.ts test/graph-overview.test.ts` |
| A3 | `src/core/engine.ts` | +17/−2：`BrainEngine` 接口的 `graphOverview` | +136/−51：接口扩面（`TakesListOpts`、`TransactionOptions` 等） | **并集** | `bun test test/engine-surface-coverage.test.ts` |
| A4 | `src/core/operation-load.ts` | +6：5 个 op 的 area 映射（inbox 4 + graph_overview + truth 3） | 6/6：已有 op 的 area 调整 | **上游基底 + 贴回 5 行映射**（`list_inbox/get_inbox_item/trigger_inbox_enrichment/discard_inbox_items`→pages，`graph_overview`→links，`find_conflicts/compile_truth/adopt_compiled_truth`→insights） | `bun test test/operation-manifest.test.ts` + `bun run src/cli.ts --help` |
| A5 | `src/core/operations.ts` | +8：inbox / truth op splice | +12/−7：op 导入与注册扩面 | **上游基底 + 贴回 splice**（位置在 `find_contradictions` 之后） | `bun test test/parity.test.ts test/operation-manifest.test.ts` |
| A6 | `src/core/ops/jobs.ts` | +6/−2：`list_jobs`/`get_job` 返回 `execution_lane` | +95/−21：job 字段/分页/scope 改造 | **上游基底 + 贴回 `execution_lane`**（在 `publicJob`/`LIST_JOB_FIELDS` 的新结构上） | `bun test test/inbox-workflow.test.ts -t "lane"` + admin Jobs 页标签 |
| A7 | `src/core/ops/links.ts` | +73/−4：`graph_overview` op + `node_limit`/`frontier_cap` | +130/−90：link op 扩面 | **上游基底 + 贴回** | `bun test test/graph-overview.test.ts test/retrieval-op-redaction.test.ts` |
| A8 | `src/core/ops/search.ts` | +29/−1：可选 `trace` 参数与返回信封 | +285/−210：search 大改（feedback / last-retrieved / explain） | **上游基底 + 贴回 `trace`**（参数 + 信封 + `outputRedaction` 不变） | `bun test test/retrieval-op-redaction.test.ts`；admin Ask 页 TraceWaterfall |
| A9 | `src/core/schema-migrations/registry.generated.ts` | +2：注册 v239 | +72：注册 v239..v274 | **生成物**：改号后 `bun run build:schema-migrations` 一次生成（禁止手改） | `bun run check:schema-migrations` 绿 |
| A10 | `src/core/schema-migrations/latest.generated.ts` | +1/−1 | +1/−1 | 同上（生成物） | 同上 |
| A11 | `test/fixtures/goldens/sql-text/links.json` | +35/−12 | +62/−54 | **生成物**：`bun run regen:all --goldens`（不手改 json） | `bun run check:regen-all` 绿 |
| A12 | `test/retrieval-op-redaction.test.ts` | +10：`list_inbox` / `graph_overview` / `find_conflicts` 行 + inbox 播种 | +6：SWEEP 新增上游 op 行 | **并集**（保留双方行） | 该文件全绿 |
| A13 | `admin/package.json` | +15/−3：Admin SPA 依赖 | 1/1：版本/脚本调整 | **并集** | `cd admin && bun install && bun run test` |
| A14 | `admin/bun.lock` | +341/−1 | +2/−2 | **以上游锁定文件为基底 + `cd admin && bun install` 重算**（生成物） | `cd admin && bun install --frozen-lockfile` 通过 |
| A15 | `docs/TOOL_CATALOG.md` | +13/−5 | +39/−26 | **生成物**：`bun run regen:all`（tool catalog lane） | `bun run check:tool-catalog` 绿 |
| A16 | `plugin/README.md` | 1/1 | 2/2 | **生成物**：`bun run scripts/generate-plugin-tree.ts --out plugin --variants-out plugin-variants --write-gaps` | `bun run check:plugin-tree` 绿 |
| A17 | `skills/skills.lock.json` | +4/−4 | +33/−29 | **生成物**：`bun run scripts/generate-skills-manifest.ts` | `bun run check:skills-manifest` 绿 |
| A18 | `scripts/module-size-limits.tsv` | 9/9：9 个文件上限上调，note 标 `GBrain Custom` | 36/33：新增/调整上游行 | **取并集 + 重测**：上游表为基底，重贴 9 行 fork 限额（取 `max(fork限额, 现场实际行数)`），note 保留来源标注 | `bun run check:module-size` 绿；`git diff` 中 fork 9 行可逐行解释 |
| A19 | `scripts/structural-suites.tsv` | 389/389（整表重排） | 47/9（新增套件行） | **生成物为基底 + 重跑**：`bun run regen:all` 的 structural-suites lane，再人工确认 fork 独有套件行仍在 | `bun run check:structural-manifest` 绿 |

## B. 可干净合并但必须核对的 28 个

| 文件 | fork 侧 | 必须确认 | 验证 |
|------|---------|----------|------|
| `src/commands/serve-http.ts` | 挂钩块（+若干行） | **`CUSTOM ADMIN ROUTES (BEGIN/END)` 仍在上游路由之后**，块内仍是 `mountAdminOpProxy(app, ctx)` 一行 | `grep -rn "CUSTOM ADMIN ROUTES" src/` = 2 行；`bun test test/serve-http-admin-route-guard.test.ts` |
| `AGENTS.md` | 两处 `CUSTOM (Qoder)` 围栏 + “Read this order” 契约节 | 围栏在文件头部与中段各一对；上游新增节不得吞掉围栏 | `grep -c "CUSTOM (Qoder)" AGENTS.md` = 4；`bun run build:llms` 后 freshness 测试绿 |
| `.gitignore` | +4：`.context/` 等 | 上游新条目与 fork 条目并集 | `git status` 只报 3 个已登记未跟踪项 |
| `llms-full.txt` | 生成物 | 由 `bun run build:llms` 重写，不手改 | `bun test test/build-llms.test.ts` |
| `skills/RESOLVER.md` | +2/−1：二开路由行 | 上游新增路由不删 | `bun run check:resolver` 绿 |
| `docs/architecture/key-files/core-ai.md` | 1/1 | 合并后指向的仍是上游新文件路径 | 人工读 1 分钟 |
| `docs/integrations/embedding-providers.md` | +13/−1：Ollama 维度说明 | 与上游新文档结构对齐，不叠第二套 | 人工核对 |
| `src/commands/jobs.ts` | +2 | `execution_lane` 在 jobs 命令输出中保留 | `bun run src/cli.ts jobs --json` 含字段 |
| `src/commands/status.ts` | +20/−1：DreamCycle `phases` | 上游 status 改造后 `phases` 仍并列输出 | `bun test test/inbox-workflow.test.ts` + admin Today 页 |
| `src/commands/serve-http-admin-api.ts` | +12/−1：SSE `: ping` 心跳 | 上游 SSE 改造后心跳仍在 | admin 实时刷新不超时 |
| `src/core/ai/gateway.ts` | +1：`embed()` 传 `recipe.id` | 上游网关改造后第 5 参仍传对 | `bun test test/ai/gateway.test.ts` |
| `src/core/minions/handlers/ingest-capture.ts` | +17/−2：inbox 分支 | 上游 ingest 改造后 inbox 分支仍在 | `bun test test/ingestion/ingest-capture.test.ts` |
| `src/core/operation-manifest.generated.ts` | 生成物 | `bun run regen:all` 生成，fork 5 op 出现 | `bun test test/operation-manifest.test.ts` |
| `src/core/operation-loaders.generated.ts` | 生成物 | 同上 | 同上 |
| `src/core/ops/pages.ts` | +4/−1：`runAutoLink` 契约 | 上游若改签名，按上游新签名重贴 | `bun test test/inbox-workflow.test.ts` |
| `src/core/pglite-engine.ts` | `graphOverview` 包装 + `plannerRead()` | 上游 PGLite 执行器改造后包装仍成立 | `bun test test/graph-overview.test.ts`（PGLite 路径） |
| `src/core/postgres-engine.ts` | `graphOverview` 直调 | 同上 | 同上 |
| `src/core/skill-frontmatter.ts` | +4：注释（CRLF 逻辑以上游为准） | 上游逻辑未被 fork 覆盖 | `bun test test/skill-brain-first.test.ts` |
| `src/core/types.ts` | +69：graphOverview / traversal 类型 | 上游类型扩面后并集 | `bun run typecheck` |
| `src/mcp/surface.ts` | +30/−2：starter 集 | 上游 surface 改造后 starter 仍排除默认关 op | `bun test test/mcp-tool-defs.test.ts` |
| `test/engine-surface-coverage.test.ts` | `INTERFACE_METHODS` 含 `graphOverview` | 上游名单扩面后 fork 项仍在 | 该文件绿 |
| `test/helpers/postgres-engine-sql-cases.ts` | `graphOverview` 归 `links` 域 | 上游 EO8 分类表扩面后 fork 项仍在 | 该文件绿 |
| `test/model-pricing.test.ts` | +2 | 《已上游化》：缓存字段增量已删，按上游定价表口径 | 该文件绿 |
| `test/traverse-paths-row-cap.test.ts` | `frontier_cap: 0` 用例 | 上游行上限逻辑变更后仍显式关闭 | 该文件绿 |
| `test/fixtures/goldens/exports/runtime.json` | 生成物 | `regen:all --goldens` | `bun run check:regen-all` |
| `test/fixtures/goldens/exports/types.json` | 生成物 | 同上 | 同上 |
| `test/fixtures/goldens/sql-text/_classification.json` | 生成物 | 同上 | 同上 |
| `test/fixtures/goldens/sql-text/_driver.json` | 生成物 | 同上 | 同上 |

## C. 生成物重跑顺序（Gate 3 执行，禁止手工 resolve）

1. `bun run build:schema-migrations`（改号 275 后；生成 `registry.generated.ts` + `latest.generated.ts`，含 `src/schema-embedded`）
2. `bun run regen:all`（error-code 文档、agent-protocol 块、harness 文档、operation-manifest + loaders、MCP tool catalog、skills manifest、metric glossary、CLI flag registry、plugin-tree、structural suites、llms.txt）
3. `bun run regen:all --goldens`（`export-surface` / `cli-goldens` / `cli-dispatch-phase` / `engine-sql-sql-text`）
4. `bun run build:admin`（`admin/dist` + `src/admin-embedded.ts`）
5. `bun run build:llms`（若 `regen:all` 未覆盖 `llms-full.txt`，以该命令为准）
6. `bun run check:regen-all`（freshness 门，必须绿）

## D. 迁移改号执行单（239 → 275）

| 步骤 | 动作 | 验证 |
|------|------|------|
| D1 | 合并后把文件改名为 `src/core/schema-migrations/v275-inbox-workflow-frontmatter.ts` | `ls src/core/schema-migrations \| grep 275` |
| D2 | 导出名 `export const v275`，对象内 `version: 275` | `grep -n "v275\|version: 275" <file>` |
| D3 | `bun run build:schema-migrations` 重建 registry / latest；确认注册行出现 `v275` 且无重复 version | `bun run check:schema-migrations` |
| D4 | 排序探针：`GBRAIN_MIGRATION_BASE_REF=upstream/master bun run check:schema-migration-order` | 输出 `above upstream/master's latest v274 (275)` |
| D5 | 产物探针（不只看日志）：对 `inbox_workflow_frontmatter` 的 DDL 目标列做 information_schema 查询 | 迁移后列存在 |
| D6 | 本机 brain 迁移 | **只提命令**：`gbrain apply-migrations --yes`（239→275，含上游 240..274），由操作者执行并核对迁移条数 |

## E. 明确不做

- 不做「全取上游」或「全取二开」；不手工编辑任何 `.generated.ts` / goldens / `admin/dist` / 嵌入哈希。
- 不为兼容保留双份实现：上游已吸收的能力（《已上游化》表）一律删 fork 那份。
- 不改 `CUSTOM.md` 历史《阶段记录》行；本轮记录 Gate 3 后追加。
- 不把《故意不用的路径》里的减法项自动恢复（Windows `bun build --compile`、`openwiki/` 需重新评估后才动）。
- Gate 3 前不 push、不部署、不代跑本机 brain 迁移。

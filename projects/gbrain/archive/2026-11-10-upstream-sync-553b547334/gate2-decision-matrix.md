# Gate 2 裁决矩阵：2026-11-10-upstream-sync-553b547334

> 依据：`CUSTOM.md`《合并守则》（台账唯一事实源 / 小增量频繁合并 / 上游为基底 / 加法优先 /
> 功能重叠→上游胜出 / 功能不重叠→上游基底 + 二开补回 / 标记挂钩无论是否冲突都核对 /
> 生成产物不手工 resolve / 减法定制重新评估 / 迁移号顺延 / 合并后无条件验证）。
> 窗口：`2568d32ac8..553b547334`。预测（`git merge-tree --write-tree --name-only`）与
> `git merge upstream/master` 实测**均为 19 个冲突**，路径逐项一致（见 `conflict-surface.txt`）。
> 两边都改但可干净合并 51 个（见 `both-changed.txt`）。

## A. 7 个源码 / 配置：上游为基底 + fork 增量贴回

| # | 文件 | fork 侧（台账依据） | 上游侧（本窗口） | 裁决 | 验证 |
|---|------|--------------------|------------------|------|------|
| A1 | `AGENTS.md` | 两对 `CUSTOM (Qoder)` 围栏（+约 8 KB 本仓特有开发指引） | 重写头部 preamble、新增 hosted GBrain / harness 引导 | **上游新 preamble 为基底 + 保留两对围栏**；中段围栏随干净合并保留 | `grep -c "CUSTOM (Qoder)" AGENTS.md` = 4 |
| A2 | `admin/package.json` | Admin SPA 依赖 `jsdom` / `tailwindcss` / `typescript` / `vitest` | 依赖版本调整 | **取并集**：fork 依赖全保留，`vite` 取上游 `^6.4.5` | `cd admin && bun run test` 28 文件 / 227 用例全绿 |
| A3 | `scripts/module-size-limits.tsv` | 11 行 `GBrain Custom` 上限与来源标注 | 上游表整体重排/调整 | **以上游表为基底重贴 11 行**；再按现场行数上调 9 个超限文件（两轮 `ratchet.py` / `ratchet2.py`） | `GBrain Custom rows: 11`；`check:module-size` 长超时单跑 `OK` |
| A4 | `src/cli/main.ts` | `--json` 空结果/trace 信封解包 | 新增 `withExplainTargetJson` 与 explain target 输出 | **上游基底 + 贴回** `Array.isArray(result)` 分支与 `{...(result), results}` 信封 | `bun run typecheck` 0；CLI 定向回归 |
| A5 | `src/core/ops/search.ts` | 可选 `trace` 参数与返回信封 | 新增 `evidenceOutput` / `pageCapMeta` / `capturedMeta?.degraded` 等 | **上游结果赋给 `delivered` + 贴回** `if (p.trace === true) return { results: delivered, trace: {...} }` | 定向批 571 pass / 0 fail |
| A6 | `src/core/minions/handlers/ingest-capture.ts` | Inbox slug 的 `prepareInboxCaptureContent()` 预处理 | 新增 `importAs(sourceId)` 闭包、`checkWriter()`、`idempotency_key` 结构 | **采用上游闭包，但把闭包内的 `event.content` 改为 fork 预处理后的 `content`**；`result = await importAs(sourceId)` 与 `importAs(undefined)` fallback 保留 | `bun test test/inbox-workflow.test.ts test/ingestion/ingest-capture.test.ts`；否则 Inbox frontmatter 会静默失效 |
| A7 | `test/traverse-paths-row-cap.test.ts` | `frontier_cap: 0` 例外用例 | 新增 `emitNotice` / `notices` 契约 | **以上游 `emitNotice` 上下文为基底 + 保留** fork 注释与 `frontier_cap: 0` | 该文件绿 |

A6 是本轮最易漏的一处：上游把导入逻辑搬进闭包后，干净合并也会让 fork 预处理失效
（不报冲突、只丢行为）。属「标记挂钩即使无冲突也必须逐条核」的同类风险。

## B. 12 个生成物 / 金标准：零手工 resolve

统一裁决：`git checkout --theirs` 取上游基底 → 丢弃全部冲突块 → 由生成器重建。

| # | 文件 | 重建命令 |
|---|------|----------|
| B1 | `admin/bun.lock` | `git checkout --theirs` → `cd admin && bun install` 重算（见 D5） |
| B2 | `admin/dist/index.html` | `bun run build:admin` |
| B3 | `docs/TOOL_CATALOG.md` | `bun run regen:all` |
| B4 | `llms-full.txt` | `bun run build:llms`（另见 D1 link-only 适配） |
| B5 | `plugin/README.md` | `bun run regen:all`（plugin-tree lane） |
| B6 | `scripts/structural-suites.tsv` | `bun run regen:all` |
| B7 | `skills/skills.lock.json` | `bun run regen:all` |
| B8 | `src/admin-embedded.ts` | `bun run build:admin`（`ADMIN_ASSET_COUNT` 3 → 5） |
| B9 | `src/core/schema-migrations/latest.generated.ts` | `bun run build:schema-migrations` |
| B10 | `src/core/schema-migrations/registry.generated.ts` | `bun run build:schema-migrations` |
| B11 | `test/fixtures/goldens/cli/tools-json.json` | `bun run regen:all --goldens` |
| B12 | `test/fixtures/goldens/sql-text/links.json` | `bun run regen:all --goldens` |

`regen:all --goldens` 明确改变 `tools-json.json` 与 `links.json`，生成器输出提示
`Changed contract goldens are reviewer-visible behavior changes: justify each in the PR body`——
本轮两者均为上游契约变更（新 op / SQL 结构）的派生结果，非 fork 行为改写。

## C. 干净合并但必须逐条核对（51 个 both-changed 中的重点）

| 文件 / 挂钩 | 必须确认 | 实测 |
|-------------|----------|------|
| `src/commands/serve-http.ts` | `CUSTOM ADMIN ROUTES (BEGIN/END)` 块仍在，且仍调用 `mountAdminOpProxy(app, ctx)` | `grep -rn "CUSTOM ADMIN ROUTES" src/` = 2 行 ✅ |
| `AGENTS.md` 中段 Qoder 围栏 | 上游新 preamble 未吞掉中段围栏 | 合计 4 行 ✅ |
| `tsconfig.json` | 上游基底没有改回 `baseUrl`，`@/*` 仍为 `./src/*` | 人工 `cat` 复核 ✅ |
| `src/core/schema-migrations/*` | 上游占 `v275..v297`，fork `v275` 必须顺延 | 顺延 298 ✅ |
| `admin/src/lib/op-types.ts` | fork-only 类型镜像在合并结果中完好 | 40 接口 / 252 字段 / 0 drift ✅ |
| `src/core/minions/types.ts` | 上游新增 `idempotency_key` 后 fork mock 是否兼容 | 补 `idempotency_key: null` ✅ |
| `scripts/llms-config.ts` | 上游结构变化后 `includeInFull: false` 是否仍是合法字段 | `build:llms` 12/12 绿 ✅ |

## D. 生成物重跑顺序（Gate 3 执行，禁止手工 resolve）

1. `bun run build:schema-migrations`（迁移改号 298 后，重建 registry / latest）
2. `bun run regen:all`
3. `bun run regen:all --goldens`
4. `bun run build:admin`（`admin/dist` + `src/admin-embedded.ts`）
5. `bun run build:llms`（若 `regen:all` 未覆盖 `llms-full.txt`）
6. `bun run check:regen-all`（freshness 门 → `all 16 generated artifacts fresh`）

## E. 迁移改号执行单（275 → 298）

| 步骤 | 动作 | 验证 |
|------|------|------|
| E1 | `git mv v275-inbox-workflow-frontmatter.ts v298-inbox-workflow-frontmatter.ts` | 路径存在、旧路径消失 |
| E2 | 注释占号史追加 `→ v298`；导出名 `export const v298`；`version: 298` | `grep -n "v298\|version: 298"` |
| E3 | `bun run build:schema-migrations` 重建 registry / latest | `bun run check:schema-migrations` fresh |
| E4 | 排序探针 `GBRAIN_MIGRATION_BASE_REF=upstream/master bun run check:schema-migration-order` | `1 new migration(s) above upstream/master's latest v297 (298)` |
| E5 | 空 PGLite 库产物探针（`migration-probe.ts`） | `293 migration(s) applied`、`config.version = 298`、`IDEMPOTENT = true` |
| E6 | `bun test test/schema-migration-registry.test.ts` | 2 pass / 0 fail |
| E7 | **按路径登记的基线 TSV 全量扫描** | 见 `design-adjustments.md` D2（本轮首跑漏了，Gate 3 抓到） |
| E8 | 本机 brain 迁移 | **只提命令**：`gbrain apply-migrations --yes`（275→298，含上游 275..297），由操作者执行 |

## F. 明确不做

- 不「全取上游」或「全取二开」；不手工编辑任何 `.generated.ts` / goldens / `admin/dist` / 嵌入哈希。
- 不为兼容保留双份实现；上游已吸收的能力按《已上游化》删 fork 那份。
- 不为 `llms-full.txt` 过预算而删除 `AGENTS.md` 的 `CUSTOM (Qoder)` 围栏。
- 不改 `CUSTOM.md` 历史《阶段记录》行；本轮记录在 Gate 3 后追加。
- 不在根仓执行 `bun install`（`CUSTOM.md` 记录 root postinstall 会动 `~/.gbrain`）；
  工作区无 `node_modules`，用 PowerShell Junction 复用主仓依赖，`admin/` 下单独重算 lock。
- 不 push、不部署、不代跑本机 `gbrain apply-migrations --yes`。

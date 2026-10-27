# CUSTOM.md 更新草案（Gate 3 后落账）

> 纪律：补登与状态刷新在 Gate 1 前（已提交 `1b8e921983`、`dd38530d5b`）；
> 历史基线行/合并记录只在 Gate 3 确认后追加。本文件是待追加的两段。

## 1. 《已知测试失败基线》新增行（Windows guard 路径分隔符假阳性）

根因：上游本轮新增/改写的 5 个 guard 用 `relative(root, file)` 得到 `src\core\...`（反斜杠），
再拿它去匹配用正斜杠书写的基线键，于是**每条基线行都"不存在"、每个文件都"新增"**。
证据（均为上游文件，非二开改动）：

| guard | 代码位置 | 现象 |
|-------|----------|------|
| `check:function-size` | `scripts/check-function-size.ts:289` `measureSource(relative(ROOT, f), ...)` vs `scripts/function-size-baseline.tsv` 正斜杠键 | 49「no baseline row」+ 49「row no longer exists」= 99 violation |
| `check:core-guard-coverage` | `scripts/check-core-guard-coverage.mjs:75,80` `relative()` 结果查 `EXEMPT[rel]` | 名单内文件全部误报 |
| `check:item-allowlist-catches` | `scripts/check-item-allowlist-catches.ts:226` `relative(root, full)` | 基线 0 → 报 1 |
| `check:derived-census` | `scripts/check-derived-census.ts:42` `counts.set(relative(root, file))` | 已复核行全部误报 |
| `check:sync-run-state` | `scripts/check-sync-run-state.ts:30,75` `${DIR}/sync-run.ts` 与 `relative()` 比较 | 自己文件被判「outside itself」 |
| `check:test-env-opt-ins` | `scripts/check-test-env-opt-ins.ts:196` `relative(ROOT, path)` | `test/e2e/*` 豁免失效 |

建议新增一行：

| 项 | 症状 | 定性 |
|----|------|------|
| `check:function-size` / `check:core-guard-coverage` / `check:item-allowlist-catches` / `check:derived-census` / `check:sync-run-state` / `check:test-env-opt-ins`（Windows） | 基线与豁免全部失效、命中路径显示反斜杠 | 上游 guard 未归一化路径分隔符（`relative()` → 反斜杠 vs 正斜杠键）。合并前树同样复现（OS 级，与合并无关）；Linux CI 不受影响。判定方法：`grep -n "relative(" scripts/check-*.{ts,mjs}` 看是否 normalize |

同时修正既有 `check:function-size` 行的归因：原写「base-ref 假阳性」，本轮实测在 `GBRAIN_FUNCTION_SIZE_BASE_REF=upstream/master` 下仍红，真实原因是路径分隔符；base-ref 只影响 `check:schema-migration-order`。

## 2. 《阶段记录》新增（置顶，2026-10-26）

### 2026-10-26 — 对齐上游 v0.60.461.0（v0.60.176.0 → v0.60.461.0，5333 提交）

**欠债登记**：跨度 285 个 release stamp，违反「小增量、频繁合并」（>2 release 即欠债）。本轮按 Gate 1 v2 模板走完 §0 台账新鲜度（首判 BLOCK → 修复提交 → PASS）、Gate 1/2/3 与裁决矩阵；上台账的新增/变更见下。

**窗口与冲突面**：上游 4804 改动文件；fork 增量 509；两边都改 47，真实冲突 19（`git merge-tree` 预测与实测一致）。裁决：贴回挂钩 8、取并集 3、生成物重跑 7、重估 1（`structural-suites.tsv` 由生成器重跑）。

**上游重构波（本轮新变化）**：
1. `engine-sql/links.ts` 的 `traversePaths` 全量改写为 `bfsWalkCtes` + 统一 `edges`；上游自带的 `layerCap` 参数正好承接 fork 的 `frontierCap`，但 both 分支 SELECT 丢了 `to_title`/`to_type`，按 fork 契约补回两列并重生成 SQL 金标准。
2. 上游新增「分段页存储」体系（v248）与 page-body-reader 守卫：任何整页 body 读取必须登记 `scripts/page-body-readers-baseline.tsv` 并给 action code。fork 的 inbox/truth 共 11 处整页读取已登记为 `INLINE`/`SEGW`（fork 页面按 inline 构造；分段存储是上游可选能力）。
3. 上游新增 5 个路径敏感 guard（见《已知测试失败基线》），Windows 下全部假阳性。

**迁移号**：`inbox_workflow_frontmatter` 239 → **275**（上游本轮占 239..274）。四处同改 + registry 重生成 + 排序探针（`GBRAIN_MIGRATION_BASE_REF=upstream/master` → `above upstream/master's latest v274 (275)`）+ 空库产物探针（270 迁移全应用，UPDATE 幂等）。新增 `test/schema-migration-registry.test.ts` 守卫「版本唯一 + 我方迁移永远是最新」。

**尺寸棘轮**：11 个文件上限按现场行数上调并标注 `GBrain Custom` 来源（原 9 个 + `src/core/ai/gateway.ts` + 新增行 `src/core/ops/search.ts`）。

**验证**：typecheck 0 错误；fork 定向批 289 用例 288 pass → 修 `to_title/to_type` 后全绿；admin vitest 28 文件 / 227 用例全绿；`regen:all` + `--goldens` + `build:admin` + `build:llms` 全绿且 `check:regen-all` fresh；`bun run verify` 70 pass / 19 fail，19 项逐条定性（13 项既有基线、6 项 Windows 路径假阳性、0 项未解释）。

**环境副作用（需知）**：`bun install` 的 postinstall 对本机 `~/.gbrain` 跑了一次内容迁移 v0.53.0，停在 `shared_skill_members` 缺失（partial），并在 `~/.gbrain/` 留下 `brain.pglite.gbrain-migrations.lock`。本机 brain 的 schema 迁移（239 → 275）**仍未执行**，由操作者跑 `gbrain apply-migrations --yes` 并核对条数。

**分支状态**：合并只在 `sync/upstream-2026-10-26-2568d32ac8`，`master` 未动；Gate 3 确认前不 push。

# 上游同步 v0.60.461.0 → v0.60.636.0（gbrain fork）

> Gate 1 提案 | 冻结窗口 `2568d32ac8..553b547334` | 2026-11-10
> 依据：上一轮 `archive/2026-10-26-upstream-sync-2568d32ac8` 的 `upstream-sync` 四 Gate 变体。

## Why

fork 停在 upstream `0.60.461.0`（`a752cc41a4`），上游已到 `0.60.636.0`（`553b547334`）：
**3056 提交 / 180 个 release stamp（`VERSION` 提交数）/ 2452 个上游改动文件**，
再次违反 `CUSTOM.md`《合并守则·小增量、频繁合并》（>2 release 即欠债；上轮 285，本轮 180）。

三项必须先判的风险：

1. **迁移撞号**：上游本窗口新增 `v275..v297`，fork 的 `inbox_workflow_frontmatter` 正占 `v275`。
   runner 只按 version 记 `schema_version`，同号会让一方 DDL 被静默跳过（v133 事故同类）。
2. **生成物冲突面**：`git merge-tree --write-tree --name-only` 预测 19 个真实冲突、
   51 个两边都改可干净合并；其中 12 个是生成器输出，按守则**零手工 resolve**。
3. **台账新鲜度**：§0 四维首判发现 7 个 fork 侧生成物/金标准未登记、2 处状态失真，
   属 Gate 1 硬前置 BLOCK，不修复不得合并。

## What Changes

- **Gate 1 前置修复**（独立提交 `387f1e0341`）：补登 7 个 fork 侧生成物/金标准；
  删除失真的 `origin/master = 61dffc7613`；《二开专属文件》`v239-` 修正为 `v275-`。
  复跑 `UNREGISTERED_NOW=0` PASS 后，由用户选项「确认继续（推荐）」通过 Gate 1。
- **窗口冻结与回滚锚点**：`git fetch --no-tags upstream master` → `553b547334`；
  建同步分支 `sync/upstream-2026-11-10-553b547334` 与标签 `pre-sync/2026-11-10`，
  `master` 不动。
- **19 个冲突按守则裁决**：12 个生成物全部 `git checkout --theirs` 取上游基底后由生成器重建；
  7 个源码/配置以上游为基底逐文件贴回 fork 增量（见 `gate2-decision-matrix.md`）。
- **迁移号顺延 275 → 298**：文件名 / 导出名 `v298` / `version: 298` / registry 注册行四处同改，
  再 `bun run build:schema-migrations`，排序探针与空库产物探针双查。
- **生成链重建**：`build:schema-migrations` → `regen:all` → `regen:all --goldens` →
  `build:admin` → `build:llms` → `check:regen-all`（16 个生成物 fresh）。
- **合并后适配**：`llms-full.txt` 体积预算、`MinionJobContext.idempotency_key` 契约漂移、
  尺寸棘轮、`admin/bun.lock` frozen lockfile、上游新增 guard 的按路径登记基线 TSV。
- **台账与档案**：`CUSTOM.md`《阶段记录》追加 2026-11-10 记录（历史行不回填）、
  《已知测试失败基线》补新增行、《合并守则》补三条本仓特有规则；外置记录仓补本轮档案。

## Modified Capabilities（受影响的二开能力）

- **Inbox frontmatter 预处理**：`src/core/minions/handlers/ingest-capture.ts` 上游新增 `importAs()`
  闭包，必须改用 fork 预处理后的 `content`，否则 Inbox frontmatter 静默失效。
- **Query trace / CLI 空结果信封**：`src/core/ops/search.ts` 与 `src/cli/main.ts` 在上游
  `evidenceOutput` / `pageCapMeta` / `degraded` / `withExplainTargetJson` 重构后保持信封语义。
- **标记挂钩**：`AGENTS.md` 两对 `CUSTOM (Qoder)` 围栏（上游重写了 preamble）、
  `src/commands/serve-http.ts` 的 `CUSTOM ADMIN ROUTES` 块——干净合并也必须核。
- **Admin SPA**：依赖并集 + lock 重算，28 文件 / 227 用例保持全绿。
- **DeepSeek / Ollama 配置注入**：上游新增 `core-world-reads` ratchet 后按 raise-with-justification 出口登记。
- **AGENTS.md 分发**：从 `llms-full.txt` inline 改为 link-only，`llms.txt` 索引不变，Qoder 仍直接读原文件。

## Success Criteria

- [x] §0 台账新鲜度四维 FRESH，修复提交独立于合并（`387f1e0341`），Gate 1 取得用户确认。
- [x] `src/core/schema-migrations` 无重复 version；`inbox_workflow_frontmatter` = **298**；
      `GBRAIN_MIGRATION_BASE_REF=upstream/master bun run check:schema-migration-order`
      输出 `above upstream/master's latest v297 (298)`。
- [x] 空 PGLite 库产物探针独立验证：`293 migration(s) applied`、`config.version = 298`、
      `target columns = compiled_truth, frontmatter`、两次执行 `IDEMPOTENT = true`。
- [x] `grep -c "CUSTOM (Qoder)" AGENTS.md` = 4；`grep -rn "CUSTOM ADMIN ROUTES" src/` = 2 行。
- [x] `bun run typecheck` 0 错误；`bun run check:regen-all` = `all 16 generated artifacts fresh`。
- [x] 合并面定向批 21 文件 **571 pass / 0 fail**；`cd admin && bun run test` **28 文件 / 227 用例**全绿。
- [x] `bun run verify` 的失败项逐条定性，不允许笼统归因；2 处真实回归当场修复并复跑通过。
- [x] fork-delta 双向审计：无二开增量静默丢失；TYPE-MIRROR 机械首过 40 接口 / 252 字段 / 0 drift。
- [x] `CUSTOM.md`《阶段记录》追加本轮记录且不修改任何历史阶段行。
- [ ] **未纳入本轮**：推送 `master`/`origin`、部署、本机 `gbrain apply-migrations --yes`、
      Linux CI/Ubicloud 全量单测——需操作者另行授权或在 CI 侧完成。

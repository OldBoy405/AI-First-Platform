# Gate 3 测试报告：2026-11-10-upstream-sync-553b547334

> 环境：Windows / Git Bash / Bun；工作区通过 PowerShell Junction 复用主仓 `node_modules`
> 分支：`sync/upstream-2026-11-10-553b547334`
> 提交：`387f1e0341`（Gate 1 台账修复）→ `d0a0515036`（merge commit，双亲 `387f1e0341` + `553b547334`）
> 说明：fork 的 GitHub Actions 因计费受限无法运行，以下全部为**本地**结果。

## 一、成功标准逐条结果

| SC / 检查 | 命令 | 结果 |
|-----------|------|------|
| typecheck | `bun run typecheck` | ✅ `TYPECHECK_EXIT=0`（补 `idempotency_key` 后） |
| 生成链 freshness | `regen:all` / `regen:all --goldens` / `build:admin` / `build:llms` / `check:regen-all` | ✅ `all 16 generated artifacts fresh` |
| 迁移排序 | `GBRAIN_MIGRATION_BASE_REF=upstream/master bun run check:schema-migration-order` | ✅ `1 new migration(s) above upstream/master's latest v297 (298)` |
| 迁移注册 | `bun run check:schema-migrations`；`bun test test/schema-migration-registry.test.ts` | ✅ fresh；2 pass / 0 fail |
| 迁移产物 | 空 PGLite 库探针（一次性脚本） | ✅ `Setting up brain schema (v298)...` / `293 migration(s) applied` / `config.version = 298` / `target columns = compiled_truth, frontmatter` / `IDEMPOTENT = true` |
| 标记挂钩 | `grep -c "CUSTOM (Qoder)" AGENTS.md`；`grep -rn "CUSTOM ADMIN ROUTES" src/` | ✅ 4；2 行 |
| 定向回归 | 合并面 21 文件 `bun test <paths>` | ✅ **571 pass / 0 fail** |
| Admin | `cd admin && bun run test` | ✅ **28 文件 / 227 用例全绿** |
| llms 体积 | `bun run build:llms`；`bun test test/build-llms.test.ts` | ✅ `llms-full.txt` 766842 字节（< 800000 预算）；12 pass / 0 fail |
| Admin lock | `cd admin && bun install --frozen-lockfile` | ✅ `Checked 223 installs across 289 packages (no changes)`；`FROZEN_EXIT=0` |
| 尺寸棘轮 | `timeout 420 bash scripts/check-module-size.sh` | ✅ 239s → `OK: module sizes within committed ceilings`、`MODULE_SIZE_EXIT=0` |
| TYPE-MIRROR | `admin/docs/TYPE-MIRROR-CHECKLIST.md` 机械首过 | ✅ 40 接口 / 252 字段 / **0 drift** |
| fork-delta 审计 | 合并前后相对上游 delta 双向比对 | ✅ 无二开增量静默丢失（见第四节） |
| `bun run verify` | 有界并发驱动重跑 `--dry-list` 的 95 项 | ✅ **74 pass / 21 fail，21 项全部定性、0 项未解释**（见第二节） |
| 台账 | `CUSTOM.md`《阶段记录》2026-11-10 | ✅ 已写入提交，历史阶段行零改动，无占位符残留 |
| 全量单测 | `bun run test` | ⚠️ Windows 下 shard 统计解析失败 + 挂死文件（既有基线），**不提供信号**，需 Linux CI/Ubicloud 补跑 |

## 二、`bun run verify` 21 个失败逐条定性

原始 95 项 rc 与耗时见 `verify-rerun-results.tsv`。
首次 `bun run verify` 在 Git Bash 下**卡死**（不是失败）：runner 的节流循环
`$(jobs -rp | wc -l | tr -d ' ')` 中后台作业持有管道写端，`wc` 等不到 EOF；
`ps -ef` 可见 runner 子壳带着僵住 21 分钟的 `wc`/`tr`。终止后改用自写有界并发驱动
（每批 4 个 + `wait`、单项 `timeout 180`、per-check rc 哨兵）重跑同一清单。
另有 Python 版驱动因 `subprocess(["bash", ...])` 在 Windows 解析到 WSL `bash.exe` 被安全策略拦截，
已弃用，不再重试该路径。

### A. 2 项真实合并事故（已修复并复跑通过）

| 检查 | 根因 | 处置 | 复跑 |
|------|------|------|------|
| `check:page-body-readers` | 迁移 `v275 → v298` 改名后，`scripts/page-body-readers-baseline.tsv` 仍留旧 `v275` reviewed row（报 stale），新 `v298` 文件未登记（报 new whole-body reader） | 该行改为 `v298-inbox-workflow-frontmatter.ts / v298 / sql / INLINE`，保留 `GBrain Custom` 理由 | `ok, 694 baseline rows` |
| `check:core-world-reads` | 上游本轮新增 guard 把 `src/core/ai/build-gateway-config.ts` 的 `process_env` 基线钉在 13；fork 的 `DEEPSEEK_BASE_URL` 两处引用使实际为 15 | 按守卫的 raise-with-justification 出口把该行改 15 并写明理由，不删 fork 增量 | `ok (process_env 550)` |

**共同教训**：上游新增按路径登记 ratchet，或 fork 迁移改名后，必须扫**所有按路径登记的基线 TSV**
（`page-body-readers-baseline.tsv`、`core-world-reads-baseline.tsv`、`module-size-limits.tsv`、
`function-size-baseline.tsv` 等）。已写入 `CUSTOM.md`《合并守则》。

### B. 2 项 base-ref 假阳性（推送后自愈）

| 检查 | 证据 |
|------|------|
| `check:schema-migration-order` | `origin/master` 仍是合并前 fork 树 `a752cc41a4`（那时迁移是 275）。换 `GBRAIN_MIGRATION_BASE_REF=upstream/master` 复跑为绿 |
| `check:function-size` | 换 `GBRAIN_FUNCTION_SIZE_BASE_REF=upstream/master` 后仍 105 FAIL，命中项全是 `src\...` 反斜杠路径，属已登记的 Windows 路径分隔符问题 |

`check:behavior-since` 等同源 base-ref 守卫在本次重跑中 rc=0，但推送前结论仍不应表述为「真绿」。

### C. 2 项超时（rc=124，非失败；已取真实结论）

| 检查 | 真实结论 |
|------|----------|
| `check:newlines`（181s 超时） | 上游本轮把该 guard 接进 verify。等价快速计算：7455 候选文件中 **250 个缺尾换行**，全部是 fork-only `.qoder/repowiki/**/*.md`；合并前 fork HEAD 上同样 250 个、上游树无 `.qoder/` → **存量欠债，非合并事故**。已登记 `CUSTOM.md`《待办》 |
| `check:module-size`（180s 超时） | 长超时单跑 **239s → `OK: module sizes within committed ceilings`、rc=0**；精确等价计算（按脚本排除 `*.generated.ts` / `*.test.ts` 规则）：46 行上限表 0 违规、未列出文件 0 超 1500 行 cap |

两者都逐文件起 `tail -c 1` / `wc -l` 进程，Windows 下数千文件极慢，与代码无关。

### D. 15 项 Windows / 环境 / 既有基线

| 类别 | 检查 | 证据 |
|------|------|------|
| 上游新增编译链（临时目录解析不到依赖） | `check:wasm`、`check:pglite-embedded` | 被点名的 `src/core/chunkers/code.ts`、`src/core/pglite-engine.ts`、`src/core/chunkers/image.ts` 与上游 tip **逐字节一致**（`git diff --numstat upstream/master` 为空） |
| 输出格式假阳性 | `check:skills-embedded` | 90 行哈希 diff 去掉前导 `\` 后 **0 处不一致** |
| 参数长度上限 | `check:shared-tree-git` | 4600 字节 awk 程序作单个 `xargs` 参数超 Git Bash 上限；直接分批调 awk 扫 778 文件 = **0 违规**，三份 `multi-agent-rules` 块各 1759 字节完全一致 |
| guard 自检 | `check:guard-self-test` | 11 项自检误报（由下列 Windows 假阳性派生）+ 39s 超 30s 预算，既有基线 |
| Windows 反斜杠路径 | `check:core-guard-coverage`、`check:item-allowlist-catches`、`check:derived-census`、`check:sync-run-state`、`check:test-env-opt-ins` | `check:test-env-opt-ins` 点名的 3 个 `test/e2e/` 文件与上游一致，是反斜杠路径让 e2e 豁免失效（台账已记的 6 个 Windows 假阳性之一） |
| 《已知测试失败基线》既有项 | `check:image-decoders`、`check:orphan-modules`、`check:skill-brain-first`、`check:bootstrap-tag`、`check:skill-refs` | 与本轮 diff 无关 |

### E. 另有 1 项「暂存假阳性」

`check:admin-embedded` 在**首次僵死运行**中 rc=1，报 `ADMIN_ASSET_COUNT 3 → 5`。
根因：合并进行中 index 里是上游的 3、工作区已重生成 5，脚本拿工作区比 index 才报红。
`git add -A` 后有界并发重跑 rc=**0**。不是合并事故，已写入 `CUSTOM.md`《已知测试失败基线》。

## 三、定向回归的替代信号

全量 `bun run test` 在 Windows 下按台账属已知基线问题，不作为信号。本次取信号来自：

- 合并面定向批 **21 文件 / 571 pass / 0 fail**
- Admin vitest **28 文件 / 227 用例全绿**
- 迁移三道探针：排序 / `check:schema-migrations` / `test/schema-migration-registry.test.ts` 2/2
- 空 PGLite 库产物探针（幂等性）
- `check:regen-all` 16 个生成物 fresh
- `bun run typecheck` 0 错误
- 95 项 verify 逐项定性

**残留风险**：未覆盖的测试文件仍应在 Linux CI/Ubicloud 跑一遍；本地结论不表述为「全量全绿」。

## 四、fork-delta 双向审计

| 项 | 合并前 | 合并后 |
|----|--------|--------|
| 相对上游 delta 文件数 | 513 | 514 |

- **PRE-only 2 个**：旧 admin 构建产物 `admin/dist/assets/index-CaaGFcPc.js`（新产物替代）、
  `v275-...` 迁移（改名 `v298`）——均有替代。
- **POST-only 3 个**：`scripts/llms-config.ts`、`v298-inbox-workflow-frontmatter.ts`、
  `src/core/skills/bundled-skills.generated.ts`——均为本轮新增适配。
- **fork-only 434 个文件中 6 个不在合并结果**：1 个是迁移改名；另 5 个
  （`src/core/unreadable-sources-notice.ts`、`test/mcp-unreadable-sources-notice.test.ts`、
  3 个 grandfather 测试）是**上游自己在本窗口删除**的（`fa7232c6c7` 把前者换成
  `sources-not-readable.ts`；`b92d2ba75f` 修完 v0.13.1 迁移后删测试）。这 5 个在 fork HEAD 上
  **零修改**、都是上游原文件，按「上游为基底」删除正确。

**结论：无二开增量静默丢失。**

## 五、`git diff --check`

合并 diff 有 **546 处尾随空白告警 / 27 文件**，其中
`docs/test-audit/2026-10-04/expected-deltas.tsv` 一个文件占 520 处。
逐行比对上游 tip blob：521 条新增行在上游原文里逐字存在、**0 条来自 fork**。
按「上游为基底」不改上游内容，CI 也不以 `git diff --check` 为门。

## 六、Gate 3 状态与未放行项

| 项 | 状态 |
|----|------|
| 验证执行与失败定性 | ✅ 完成 |
| 2 处真实回归修复与复跑 | ✅ 完成 |
| merge commit | ✅ `d0a0515036`，工作区 `git status --porcelain` = 0 行 |
| `upstream/master` 是否为 HEAD 祖先 | ✅ 是 |
| **`master` / `origin/master` 推送** | ✅ 已推送，最终 `origin/master` = `18ba403289`（首次落地 `06a600043f`，其后两个文档提交；见 `delivery-log.md`） |
| **部署** | ✅ 本机 CLI 随主仓 master 快进自动切到 `0.60.636.0`；主仓 typecheck rc=0 |
| **本机 `gbrain apply-migrations --yes`** | ✅ rc=0，doctor `schema_version: Version 298 (latest: 298)`、1392 列、175 表 |
| **Gate 3 用户确认** | ✅ 首次未取得；同日用户明确授权全部交付动作（不是后台通知） |

**base-ref 复核（推送后实测）**：`check:schema-migration-order` 不带覆盖即绿
（`0 new migration(s) above origin/master's latest v298`）、`check:behavior-since` 绿；
`check:function-size` 仍 105 FAIL，全是 `src\...` 反斜杠路径（既有 Windows 基线，与 base-ref 无关）。

**残留**：全量 `bun run test` 在 Windows 不提供信号，Linux CI/Ubicloud 仍需补跑；
fork 的 `Test` / `E2E Tests` 已由本次推送触发，但多为 `queued`（计费受限），不假设其给信号。

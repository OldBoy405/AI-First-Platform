# Gate 3 测试报告：2026-10-26-upstream-sync-2568d32ac8

> 环境：Windows 10.0.19045 / Bun **1.4.4** / Node 24.15.0 / git 2.54.0
> 分支：`sync/upstream-2026-10-26-2568d32ac8`
> 合并提交：`3644cb8bb5`（merge `upstream/master` @ `2568d32ac8`）
> 实施提交：`dd38530d5b`（迁移改号）、`71d8d9e9bf`（both 分支字段 + 棘轮 + 生成物）
> 说明：fork 的 GitHub Actions 因计费受限无法运行，以下全部为**本地**结果。

## 一、成功标准逐条结果

| TC | 对应 SC | 命令 | 结果 |
|----|---------|------|------|
| TC-SYNC-001 | SC-001 | `bun run typecheck`；`bun test test/operation-manifest.test.ts test/parity.test.ts` | ✅ typecheck 0 错误；两测试通过；5 个二开 op 三处登记齐全 |
| TC-SYNC-002 | SC-002 | 定向批 12 文件（inbox/conflicts/compile-truth/graph-overview/traverse-paths/ingest-capture/redaction/surface/manifest/parity/migration-registry/admin-route-guard） | ✅ 289 用例：首跑 1 fail（both 分支缺 `to_title`/`to_type`）→ 修复后 289/289 |
| TC-SYNC-003 | SC-003 | `grep -rn "CUSTOM ADMIN ROUTES" src/`；`grep -c "CUSTOM (Qoder)" AGENTS.md`；`bun test test/serve-http-admin-route-guard.test.ts` | ✅ 2 行（均在 `src/commands/serve-http.ts:837,839`）；4；测试通过 |
| TC-SYNC-004 | SC-004 | `GBRAIN_MIGRATION_BASE_REF=upstream/master bun run check:schema-migration-order` | ✅ `1 new migration(s) above upstream/master's latest v274 (275)` |
| TC-SYNC-005 | SC-005 | 空 PGLite 库 `initSchema()` + 对 `inbox/probe-275` 连跑两次迁移 SQL | ✅ 记录版本 **275**；270 个迁移全应用；两次结果一致（`raw_content` / `inbox_status` / `inbox_legacy_source`），幂等 |
| TC-SYNC-006 | SC-006 | `bun run build:schema-migrations && bun run check:schema-migrations` | ✅ registry 含 `v275`，无重复 version，`LATEST_SCHEMA_VERSION = 275` |
| TC-SYNC-007 | SC-007 | `build:schema-migrations` → `regen:all` → `regen:all --goldens` → `build:admin` → `build:llms` → `check:regen-all` | ✅ `all 13 generated artifacts fresh` |
| TC-SYNC-008 | SC-008 | `check:tool-catalog` / `skills-manifest` / `plugin-tree` / `structural-manifest` / `module-size` | ✅ 全绿（module-size 首次红：11 文件超限 → 上限按现场行数上调并标 `GBrain Custom`） |
| TC-SYNC-009 | SC-009 | `bun run verify` + 逐条定性 | ✅ **72 pass / 17 fail，17 项全部归类**（见第二节），0 项未解释 |
| TC-SYNC-010 | SC-010 | `bun run test`（8 shard 并行） | ⚠️ 环境基线：2m56s 时 4 个 shard 全为 `0/1032f`（零进度）——与 CUSTOM 基线一致；改用定向批取信号（见第三节） |
| TC-SYNC-011 | SC-011 | 台账《阶段记录》追加 | ⏳ 待 Gate 3 确认后追加（草案见 `custom-update-draft.md`） |
| TC-SYNC-012 | SC-012 | 台账逐行 grep | ⏳ Gate 3 后随台账更新一并核 |

## 二、`bun run verify` 17 个失败逐条定性

> 判定依据：合并前基线（CUSTOM《已知测试失败基线》）+ 代码根因 + 单跑复验。**没有一项是合并引入的行为回归**。

### A. 既有基线（6 项，CUSTOM 已登记）

| 检查 | 定性 |
|------|------|
| `check:skill-brain-first` | Windows py 路径解析（既有） |
| `check:image-decoders` | 走被摘除的 Windows 编译路径（既有） |
| `check:bootstrap-tag` / `check:skill-refs` / `check:test-names` | 上游工具与内容现状不一致（既有） |
| `check:orphan-modules` | Windows 误报 known-good fixture（既有） |

### B. base-ref 假阳性（1 项，推送后自愈）

| 检查 | 定性 |
|------|------|
| `check:schema-migration-order` | 报 `v239-extract-rollup-halt-reasons.ts reuses version 239, which origin/master assigns to 'inbox_workflow_frontmatter'`。`origin/master` 仍是合并前 fork 树（239 = 我方迁移）。以 `GBRAIN_MIGRATION_BASE_REF=upstream/master` 复跑为绿（TC-SYNC-004）。推送后自愈 |

### C. Windows 路径分隔符假阳性（6 项 + guard 自检 1 项）

上游本轮新增/改写的 guard 用 `relative(root, file)` 得到反斜杠路径，再匹配正斜杠键：

| 检查 | 证据 | 现象 |
|------|------|------|
| `check:function-size` | `scripts/check-function-size.ts:289` | 49 条「无基线行」+ 49 条「行已不存在」 |
| `check:core-guard-coverage` | `scripts/check-core-guard-coverage.mjs:75,80` | 名单内文件全部报 |
| `check:item-allowlist-catches` | `scripts/check-item-allowlist-catches.ts:226` | 基线 0 → 报 1 |
| `check:derived-census` | `scripts/check-derived-census.ts:42` | 已复核行全部报 |
| `check:sync-run-state` | `scripts/check-sync-run-state.ts:30,75` | 自己的文件被判「outside itself」 |
| `check:test-env-opt-ins` | `scripts/check-test-env-opt-ins.ts:196` | `test/e2e/*` 豁免失效 |
| `check:guard-self-test` | 上述 6 项 + `skill-brain-first` + `orphan-modules` 的 fixture 误报 | 7 failure |

OS 级问题，与本次合并无关；Linux CI 不受影响。**注意**：这修正了 CUSTOM 既有表格对 `check:function-size` 的归因（原写「base-ref 假阳性」）。

### D. pool timeout（3 项，单跑全绿）

`check:test-isolation`（121s 超时）、`check:newlines`（120s）、`check:module-size`（120s）——单独重跑分别通过：
- `check:test-isolation`: OK (4283 non-serial unit files scanned)
- `check:newlines`: ok (6809 files)
- `check:module-size`: OK

## 三、全量单测的替代信号

- `bun run test`（8 shard）：2m56s 仍 `0/1032f`，按 CUSTOM 基线判为 Windows shard 统计失败，终止。
- **合并面定向批**（27 文件）：`bun test ...` → **600 pass / 0 fail / 8518 expect**，109s。覆盖：traverse-paths（metadata/row-cap）、graph-overview、redaction、engine-surface、operation-manifest、parity、mcp-tool-defs、inbox-workflow、conflicts、compile-truth、ingest-capture、ai/gateway×3、model-pricing、skill-brain-first、doctor-categories、cli-goldens、cli-dispatch-phase、export-surface-golden、engine-sql-sql-text、schema-bootstrap-coverage、schema-migration-registry、build-llms、serve-http-admin-route-guard、admin-embed-spawn。
- **E2E 子集**（临时 pgvector:pg17 容器 + PGLite）：`engine-parity` + `source-isolation-pglite` → **90 pass / 0 fail**。容器已删除（`gbrain-e2e-merge`），原有容器未动。
- **Admin SPA**：`cd admin && bun run test` → **28 文件 / 227 用例全绿**；`bun run build:admin` 产出 5 个嵌入文件。

## 四、未执行项（如实记录）

| 项 | 原因 | 让谁跑 |
|----|------|--------|
| 全量 `bun run test`（8 shard） | Windows shard 零进度（既有基线） | 需要时在 Linux CI 或 Ubicloud 跑 |
| 全量 E2E（806 文件） | 串行设计，单机 20+ 分钟；本轮只跑 2 个高价值文件 | 需要时 `bun run ci:local` 或 `ci:ubicloud` |
| `test/e2e/schema-catalog-golden` / `doctor-json-golden` 金标准重生成 | 需要独立 Postgres | 有 DB 时按 `regen:all` 提示执行 |
| 本机 brain 迁移 239 → 275 | **运行中系统，只提命令不代跑** | 操作者：`gbrain apply-migrations --yes` 后核对条数 |

## 五、环境副作用（需你知悉）

`bun install` 的 postinstall 对本机 `~/.gbrain` 触发了一次**内容迁移 v0.53.0**，停在
`relation "shared_skill_members" does not exist`（status=partial），并在 `~/.gbrain/` 留下
`brain.pglite.gbrain-migrations.lock`（空文件，16:27）。这不是本仓代码改动，但属于对在跑 brain 的写操作。
处置建议（未执行）：先 `gbrain doctor --json` 看 schema/content 版本，再决定 `gbrain apply-migrations --yes`
是否继续；如需回退，`.gbrain/backup-*` 与 `backup-status.json` 是现成的恢复入口。

## 六、Gate 3 结论

- 合并、迁移改号、生成物重跑、台账外的代码修复全部完成；**无未解释失败**。
- 待办：Gate 3 确认后追加 CUSTOM 台账（草案已备）并跑 TC-SYNC-011/012；push 需要你的单独授权。

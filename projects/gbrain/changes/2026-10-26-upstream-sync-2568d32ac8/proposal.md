# 上游同步提案：2026-10-26-upstream-sync-2568d32ac8

> 模板：Gate 1 v2（2026-10-20 定稿，见 multica 归档 `2026-10-20-upstream-sync-gate1-v2`）
> 事实源：`gbrain/CUSTOM.md`《合并守则》。本提案不复制台账，只登记本次窗口的范围、基线与准入条件。
> 状态：**§0 判定 BLOCK，未进 Gate 1**。§1–§8 已按现场实测填好备用，待台账修复提交后重跑 §0 转 PASS 才正式提请确认。

## 0. 台账新鲜度检查（硬前置）

### 0.1 四维

| 维度 | 现场证据 | 判定 |
|---|---|---|
| 条目新鲜 | `git diff --name-only 2895edb3c6..HEAD` = 509 文件；fork-only 代码文件 33 个逐个 `grep -F <basename> CUSTOM.md`。**3 个完全未登记**（`src/core/eval-shared/json-repair.ts`、`tsconfig.json`、`test/doctor-categories.test.ts`）+ **7 个测试文件只能靠推断归属**（《回归》行写「相关 tests」不写文件名） | **STALE-ENTRIES** |
| 基线新鲜 | 挂钩两类现场值与台账口径一致：`CUSTOM ADMIN ROUTES` 2 hits / 1 file（`serve-http.ts:836,838`）、`CUSTOM (Qoder)` 4 hits（`AGENTS.md:7,15,287,439`）；fork-only 后端文件 9 个齐全；5 个二开 op 在 manifest/loaders/load 三处均登记。见 `ledger-hook-baseline.txt` | FRESH |
| 状态新鲜 | 《基本信息》「当前对齐上游 v0.60.176.0」＝ git 事实（merge-base `2895edb3c6`）。**3 处内容失真**：C1《已上游化》称 `embedding-dim-check.ts` 与上游一致，实际 `test/embedding-dim-check.test.ts` 有 +51 行 fork 用例；C2 迁移行括号「上游本次占了 160」与 239 轮事实（上游占 160..238）不符；C3《迁移号顺延》「当前 239」已被上游 `v239-extract-rollup-halt-reasons.ts` 占用 | STALE-STATUS |
| 格式可解析 | 四张明细表列语义一致（能力/位置/说明），基线表 3 列可按行读取；无列错位 | FRESH |

### 0.2 结论

**BLOCK**（命中 STALE-ENTRIES）。按守则「先补台账，再合并」，修复项与提交纪律见 `ledger-repair-plan.md`（A 类 3 项补登、B 类 7 项改精确文件清单、C 类 3 项事实修正）。
修复须独立提交在同步分支，不动代码、不回填历史《阶段记录》；重跑 §0 得 PASS 才进 Gate 1。

### 0.3 Gate 1 准入结论

`BLOCK` → 待修复提交后复跑。复核人／时间／结论：待填。

## 1. 窗口与策略

| 项 | 值 |
|---|---|
| 仓库 | gbrain（fork `OldBoy405/GBrain-custom`，上游 `garrytan/gbrain`） |
| fork 分支 | `master` @ `709c16b4a9`（VERSION 0.60.176.0） |
| 上游分支 | `upstream/master` @ `2568d32ac8`（VERSION 0.60.461.0，2026-10-25） |
| 上次同步点 | `2895edb3c6`（＝ merge `709c16b4a9` 的第二父，也是 `merge-base HEAD upstream/master`；台账《阶段记录》2026-10-12 行） |
| 本次窗口 | `2895edb3c6..2568d32ac8` |
| 提交数 | **5333**（非浅克隆，`git rev-parse --is-shallow-repository` = false） |
| 上游改动文件 | **4804** |
| fork 增量文件 | 509（其中 `.qoder/repowiki/**` 273、`admin/src/**` 107、`admin/dist` 8 为生成物） |
| 两边都改 | **47** |
| 预测真实冲突 | **19**（`git merge-tree --write-tree HEAD upstream/master`），余 28 个可干净合并但仍需挂钩核对 |
| 触发原因 | release 跟随 + **迁移撞号**（上游已占我方 v239，见 §3.2） |
| 合并策略 | merge（守则默认；历史四轮均 merge） |
| 同步分支 | `sync/upstream-2026-10-26-2568d32ac8`（Gate 1 确认后创建，`master` 不动） |
| 基线标签 | `pre-sync/2026-10-26` |
| 执行模式 | **thorough** |
| 模式理由 | 跨度 285 个 release stamp / 5333 提交，违反守则「小增量、频繁合并」（>2 release 即欠债），与 2026-10-12 那轮同量级；冲突面虽只有 19 文件，但上游同期新增 36 个迁移与 belief ledger / segmented pages / derived generations 等新子系统，属高风险大合并。不用冲突文件数直接套 complexity score |
| 上游 tip 冻结 | 以 Gate 1 确认的 `2568d32ac8` 为准，窗口外新提交不纳入本次 |

## 2. 前置检查

- [ ] **§0 转 PASS**（前置：台账修复独立提交）
- [ ] **本机 Bun ≥ 1.4.0** —— 现场 `bun --version` = **1.3.14**，低于 `src/core/runtime-version.ts` 的 `MINIMUM_BUN_VERSION`。未升级则合并后 `check:conversation-parser`、`check:resolver`、`skill-refs` 的 cli-refs lane、`test/cli-goldens` 必红，且并行 `bun run test` 拿不到信号。`bun upgrade` 是全局工具链变更，**须你决定**，我不代跑
- [x] 非浅克隆
- [x] `git fetch upstream --tags` 完成，upstream/master = `2568d32ac8`
- [ ] `git status` 干净 —— 当前 3 个未跟踪项：`.gbrain/`、`.qoder/better-harness/`（台账已登记勿提交）、`.stdd/`（本次新增，归属见 `ledger-repair-plan.md` §6，需你裁定 `.gitignore` 或台账登记）
- [ ] 同步分支 + `pre-sync/2026-10-26` 标签（Gate 1 后创建）
- [ ] 停写窗口确认：无其他 agent/PR 正向 `master` 合入
- [ ] 本次不 push、不部署、不改生产库；本机 brain 的 `gbrain apply-migrations`（239→275 含上游 240..274 DDL）只提命令，不代跑

## 3. 基线快照（现场重取，见 `ledger-hook-baseline.txt`）

### 3.1 挂钩四数

| 指标 | 本次基线 | 台账口径 | 差异 |
|---|---|---|---|
| `CUSTOM ADMIN ROUTES` hits | 2（`src/commands/serve-http.ts:836,838`） | 《标记挂钩》第 1 类 | 0 |
| `CUSTOM (Qoder)` hits | 4（`AGENTS.md:7,15,287,439`，两处围栏） | 《标记挂钩》第 2 类 | 0 |
| fork-only 后端文件 | 9 | 《二开专属文件》表 | 0 |
| 二开 op 三处登记 | 5 op × manifest/loaders/load 全中（`find_conflicts` 在 manifest 出现 2 次，属名字复用） | 《工作流》Inbox 行「三个地方都要登记」 | 0 |

### 3.2 迁移水位（本次最高风险项）

| 项 | 值 |
|---|---|
| 上次同步点上游最新号 | v238（`v238-persistence-client-request-id.ts`） |
| 上游本次新增 | **36 个**：v239 `extract_rollup_halt_reasons` … v274 `pages_withheld_source_path` |
| fork 占用 | **v239**（`v239-inbox-workflow-frontmatter.ts`，`inbox_workflow_frontmatter`） |
| 是否重叠 | **是**——上游 v239 与我方同号。文件名不同，git 会两个都留下 → registry 出现两个 `version: 239` |
| 后果 | 命中台账《已知测试失败基线》与 v133 事故同类：runner 只按版本号记 `schema_version`，同号即跳过，**上游 v239 DDL 或我方 frontmatter DDL 必有一份静默不执行** |
| 顺延方案 | **239 → 275**（守则：永远取上游最新号 +1）。改号需同时动四处：文件名 `v275-inbox-workflow-frontmatter.ts`、导出名 `v275`、`version` 字段、`registry.generated.ts`/`latest.generated.ts` 注册行，然后 `bun run build:schema-migrations` |
| 探针 | `GBRAIN_MIGRATION_BASE_REF=upstream/master bun run check:schema-migration-order`（默认 base ref 是 `origin/master`＝合并前旧树，未推送期间必假阳性） |

### 3.3 测试基线（合并前现场，Gate 1 确认前我只取只读信号；Bun 1.3.14 限制见 §2）

| 检查 | 合并前结果 | 备注 |
|---|---|---|
| `bun run typecheck` | 待跑（台账记录 2026-10-12 轮为 0 错误） | 与 Bun 版本无关，可先取 |
| `bun run test`（并行 8 shard） | 台账基线：Windows shard 统计失败 + 两个文件挂死，上轮 18 分钟零进度 | 信号靠定向 `bun test <paths>` |
| fork 定向批（inbox/conflicts/compile-truth/graph-overview/traverse-paths-metadata） | 待跑 | 上轮 91/91 |
| `cd admin && bun run test` | 待跑 | 上轮 227 pass |
| `bun run verify` | 待跑 | 上轮 62 pass / 16 fail，16 项全部归入基线 |
| 空库迁移 | 待跑 | 需 Bun ≥1.4.0 |

合并前 A/B 快照：`pre-sync/2026-10-26` + 按台账《已知测试失败基线》判定法建 worktree 实测。

### 3.4 路径与生成物基线

| 项 | 值 |
|---|---|
| git 跟踪文件数 | 11250 |
| 生成物在冲突面内 | `llms-full.txt`、`docs/TOOL_CATALOG.md`、`plugin/README.md`、`skills/skills.lock.json`、`admin/bun.lock`、`operation-manifest/loaders.generated.ts`、`registry/latest.generated.ts`、`test/fixtures/goldens/exports/*.json`、`sql-text/*.json` |
| 处置口径 | 一律不手工 resolve：`bun run regen:all` + `bun run regen:all --goldens`（金标准四个文件，含 `engine-sql-sql-text`），否则 `check:regen-all` freshness 门必红 |
| 上游新子系统 | belief ledger(v249) / segmented pages(v248) / derived generations(v265-266) / commit notifier(v262) —— 与 fork 真理沉淀**不同名不同义**，按「上游基底 + 二开补回」，不得叠第二套 |

## 4. 预测冲突面

### 4.1 分类（19 个真实冲突；裁决矩阵在 Gate 2 出）

| 类别 | 文件 | 守则依据 |
|---|---|---|
| 贴回挂钩（功能不重叠，上游基底+二开补回） | `src/cli/main.ts`（CLI 空结果解包 2 处）、`src/core/operations.ts`（inbox/truth op splice）、`src/core/operation-load.ts`（op→area）、`src/core/ops/jobs.ts`（`execution_lane`）、`src/core/ops/links.ts`（`node_limit`/`frontier_cap`/`graph_overview`）、`src/core/ops/search.ts`（`trace` 信封）、`src/core/engine.ts`（`graphOverview` 接口）、`src/core/engine-sql/links.ts`（`traversePaths*` SQL） | 《后端增量》《Graph·路径安全》 |
| 取并集 | `admin/package.json`、`scripts/module-size-limits.tsv`（fork 已上调 9 项）、`test/retrieval-op-redaction.test.ts`（fork 加 3 行扫描覆盖） | 守则「优先保留双方能力并集」 |
| 生成物不手工 resolve | `admin/bun.lock`、`docs/TOOL_CATALOG.md`、`plugin/README.md`、`skills/skills.lock.json`、`registry.generated.ts`、`latest.generated.ts`、`test/fixtures/goldens/sql-text/links.json` | 《生成产物不手工 resolve》 |
| 按内容重新核对 | `scripts/structural-suites.tsv` | 减法定制不适用总则，需重估 |

### 4.2 干净合并但必须核对的 28 个（git 无冲突 ≠ 挂钩仍有效）

`src/commands/serve-http.ts`（**挂钩块 host**）、`AGENTS.md`（**Qoder 围栏 host**）、`.gitignore`、`llms-full.txt`、`skills/RESOLVER.md`、`docs/architecture/key-files/core-ai.md`、`docs/integrations/embedding-providers.md`、`src/commands/{jobs,status,serve-http-admin-api}.ts`、`src/core/ai/gateway.ts`、`src/core/minions/handlers/ingest-capture.ts`、`src/core/operation-{manifest,loaders}.generated.ts`、`src/core/ops/pages.ts`、`src/core/{pglite,postgres}-engine.ts`、`src/core/skill-frontmatter.ts`、`src/core/types.ts`、`src/mcp/surface.ts`、`test/engine-surface-coverage.test.ts`、`test/helpers/postgres-engine-sql-cases.ts`、`test/model-pricing.test.ts`、`test/traverse-paths-row-cap.test.ts`、`test/fixtures/goldens/exports/{runtime,types}.json`、`test/fixtures/goldens/sql-text/{_classification,_driver}.json`

### 4.3 高风险清单

- [x] 迁移号再次压进 fork 区间 —— **已命中**，见 §3.2
- [ ] `serve-http.ts` 拆分面继续扩大时挂钩块位置（上轮已拆 `serve-http-*.ts`；`test/serve-http-admin-route-guard.test.ts` 会 glob 全部 `serve-http-*.ts` 要求 `/admin*` handler 前有 `requireAdmin`）
- [ ] 上游新 op 与二开 op 同名（已核：上游 `src/core/ops/` 68 文件无 inbox/truth/conflicts 同名；上游 `src/core/ingestion/sources/inbox-folder.ts` 与 fork「Inbox 工作流」**同名不同义**，Gate 2 单独裁定）
- [ ] `admin/src/**` 107 个 fork 文件本轮上游未触及（`admin/src` 不在 47 交集内）→ 冲突风险低，但类型镜像清单需人工对照
- [ ] `regen:all --goldens` 未跑则 `check:regen-all` 红（SQL 金标准钉整段文本，fork 只加列也要重生成，不可手改 json）
- [ ] 减法定制重估：`openwiki/`（上游本无）、Windows `bun build --compile`（#1340 是否已修 → `check:image-decoders`）

## 5. 在途状态

| 项 | 状态 |
|---|---|
| 未推送的大合并 | 上轮 2026-10-12 合并结果**只在本地**：`master` = `709c16b4a9`，`origin/master` = `f9e2a9966c`，本地领先 **4490 提交**（`git rev-list --count origin/master..master`）。本轮开始前需你决定是否先把上轮结果推 origin——不推则 §3.2 探针与 `check:function-size` 的两条 base-ref 假阳性会叠加两轮，且台账《阶段记录》2026-10-12「状态」行仍为未推送 |
| 活跃 STDD change | 本 change（gbrain 首个，`projects/gbrain/` 骨架 2026-10-26 新建） |
| 本机 brain | 未迁移到 239（台账记录：上轮留给你执行 `gbrain apply-migrations --yes`）。本轮顺延到 275，命令同样只提不代跑 |
| 台账待办 | 《待办》7 项均为功能项，与本次合并无阻塞关系 |

## 6. 范围外

- 不处理与本次窗口无关的 fork 技术债（《待办》7 项不动）
- 不修改 `CUSTOM.md`《阶段记录》历史行；本轮合并记录在 Gate 3 后追加
- 不在 Gate 3 前 push `origin/master`
- 不自动部署、不自动重启服务、不代跑 `bun upgrade`、不代跑 `gbrain apply-migrations`
- 不碰生产库与本机 brain 数据文件

## 7. 风险与回滚

| 项 | 内容 |
|---|---|
| 主要风险 | ① 迁移同号导致 DDL 静默跳过（v133 事故重演）；② 挂钩点在干净合并后静默失效；③ 生成物手工 resolve 导致 freshness 门长期红；④ Bun 1.3.14 使合并后验证拿不到完整信号，可能把环境问题误判成合并事故（台账要求逐条分类，不许笼统归因） |
| 回滚方式 | `git merge --abort` → 删同步分支 → 回到 `pre-sync/2026-10-26`（＝ `709c16b4a9`）。`master` 在 Gate 3 前不受影响 |
| 升级复核条件 | 出现台账未登记改动 / 迁移号无法顺延 / 关键行为测试无法解释 / 上游吸收了我方某项能力（需走「上游胜出并移入《已上游化》」） |

## 8. Gate 1 确认项（待 §0 转 PASS 后正式提请）

请你就以下 6 项逐条给结论：

0. 台账修复方案 `ledger-repair-plan.md` 是否批准（A 类 3 项补登、B 类 7 项改精确清单、C 类 3 项事实修正；附带项 `.stdd/` 归属选 A 或 B）
1. 窗口与冻结点：`2895edb3c6..2568d32ac8`（5333 提交 / 4804 文件），merge 策略，同步分支名
2. 迁移顺延：239 → **275**
3. 执行模式 thorough ＋ 预测冲突面 19/28 的分类口径
4. **Bun 1.3.14 是否升级**（不升级则接受合并后验证面残缺）
5. §5 第一项：上轮未推送的合并结果是否先推 `origin`
6. 是否授权进入 Phase 2 编 Gate 2 裁决矩阵

| 项 | 值 |
|---|---|
| 确认人 | 待填 |
| 确认时间 | 待填 |
| 方式 | dialog（须你在消息里直接打「确认 Gate 1」；选项框文字对动作分类器不可见，会被拦） |
| 确认原文 | 待填 |

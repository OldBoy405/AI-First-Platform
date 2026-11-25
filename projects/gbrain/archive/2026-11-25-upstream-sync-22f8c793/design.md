# 按二开合并规则同步上游 v0.60.772.0 - 技术设计

## Context

GBrain 是 TypeScript + Bun 的单仓知识图谱引擎（PGLite / Postgres 双后端、Admin React SPA、MCP 与 CLI），本次变更只做上游同步，不扩展任何新定制。设计以 `CUSTOM.md` 的合并守则、冲突决策表与合并 SOP 为准，以 `CUSTOM-LEDGER.md` 的二开台账为事实层，锚定上一轮 2026-11-24 同步记录与 154/204/208 行的合并事故教训（anchoring.level = L2）。

冻结输入（2026-11-25 在仓库内实测）：

| 项 | 冻结值 |
|---|---|
| FORK | `2e50b638f2`（master tip，`VERSION=0.60.638.0`） |
| UPSTREAM | `22f8c793b1`（`VERSION=0.60.772.0`） |
| BASE | `17b68cef4f`（上一轮已对齐上游） |
| 同步窗口 | `BASE...UPSTREAM` 2434 提交 / 5879 改动路径；fork 侧 62 提交 / 527 路径 |
| 双边路径 | 67 个（两边相对 BASE 都改过） |
| fork 迁移 | 仅 `src/core/schema-migrations/v298-inbox-workflow-frontmatter.ts` |
| 上游迁移 | `v298-attest-read` 至 `v336-files-follow-page-slug`（v298 与 fork 撞号） |

已确认的机制性风险：`src/core/migrate.ts` 的 runner 只应用 `version > current`，且只把版本号写回 `config.version`，同名不同义的 v298 不会被发现。上游 v298 新增 `access_tokens.attest_read` / `oauth_clients.attest_read` 两列；旧 fork 库已记录 298，升级后将永久跳过这条上游 DDL。

约束：保留改动须有台账归因；来源隔离、远端权限收紧、Admin 先鉴权后分派、private/soft-delete 过滤不得放松；迁移只顺延不手拼；验证使用隔离环境，禁止无保护根 `bun install`/postinstall；不新增 Graph 修复；未获授权不提交、不推送、不部署、不对生产 brain 执行迁移。

BUILD 首步需重新核实（冻结后按 SHA 重算，不追远端 HEAD）：
- 上游迁移最大号是否仍为 336（若变，顺延号改为该 SHA 下 max+1）；
- 67 / 527 / 5879 / 2434 是否与本表一致，冲突文件实际数量以 `git merge` 输出为准；
- 候选树 `src/core/runtime-version.ts` 的 `MINIMUM_BUN_VERSION`（当前两侧均为 1.4.4）与 `package.json` engines；
- 旧库副本的真实 schema 状态（`config.version`、`attest_read` 是否存在）必须实测，不得只按预期登记。

## Decisions

### 1. 冻结输入并在独立同步工作区隔离候选

**方案**：
- 新建 worktree `C:/Users/GOBAO/Downloads/AI/gbrain-sync-2026-11-25-22f8c793`，分支 `sync/upstream-2026-11-25-22f8c793`，从 FORK `2e50b638f2` 检出；回滚锚 `pre-sync/2026-11-25-2e50b638f2` 指向 FORK。
- 主工作区 `C:/Users/GOBAO/Downloads/AI/gbrain` 保持 master，不切分支、不合并、不安装依赖；本机 CLI shim 指向主仓 `src/cli.ts`，主仓快进即等于部署，必须留到授权阶段。
- 冻结命令按 CUSTOM.md 合并 SOP §1 执行并留证：`git status --short --branch`、`git fetch upstream master`、`git rev-parse` 三 SHA、`git log -1`、`git rev-list --left-right --count`、两份 `git diff --name-status -M`；确认无 `MERGE_HEAD`、无未授权用户改动；未跟踪的 `.gbrain/`、`.qoder/better-harness/`、`.stdd/` 为本地状态，不进入候选。
- 依赖复用：优先用 junction 复用主仓 `node_modules`（旧同步 worktree 已有同形态，仅作参照）；不得在候选树执行会触发 postinstall 的根安装，必要时 `bun install --frozen-lockfile --ignore-scripts`。
- 记录核对基线（当前 HEAD 实测）：`AGENTS.md` 的 `CUSTOM (Qoder)` 围栏 4 行、`src/` 的 `CUSTOM ADMIN ROUTES` 2 行、`scripts/` + `.gitignore` + `schema-migrations/` 的 `GBrain Custom` 26 行，合并后逐项复核并解释变化。

**为什么**：CUSTOM.md 要求“先核账，再合并”并禁止以同步代替验收；独立工作区让主工作区、生产 brain 与候选树物理隔离，回滚锚保证任何阶段可回到 FORK。旧同步分支 `sync/upstream-2026-11-24-17b68cef` 虽已合入，但比 FORK 少 2 个 docs 提交，直接复用会让双父 diff 与归因失真。

**备选方案及排除原因**：
- 在主工作区直接切分支合并：CLI 源码入口即主仓，根安装/postinstall 可能迁移 `~/.gbrain`，且事故时难以区分候选与生产状态。
- 复用旧同步分支 `sync/upstream-2026-11-24-17b68cef`：缺少 FORK 后 2 个提交，候选与 master 基线不一致。
- 复用旧 worktree 就地切新分支：可作后备，但路径名带 `17b68cef` 易误读；默认新建，旧 worktree 保留供 A/B 与旁证。

### 2. 以冻结 SHA 合并，保留未提交状态，先真源后生成物

**方案**：
- 在同步分支上执行 `git merge --no-ff --no-commit "$UPSTREAM"`，保持 HEAD=FORK、`MERGE_HEAD`=UPSTREAM，冲突清单用 `git diff --name-only --diff-filter=U` 记录；任何结论都以这个未提交候选为准。
- 解决顺序固定为：源码/配置（`src/`、`admin/src/`、`scripts/` 手写工具、skills 文档）→ 测试 → 手写门禁 TSV → 生成物。生成物冲突不手拼：先取上游基底材料，再由生成器重建。
- 每完成一组已核对路径就 `git add`，让 index 与受测工作区一致；生成物必须整组暂存后再跑 `check:admin-embedded`（该检查比较工作区与 index，未暂存会假红）。
- 合并结果在 Gate 3 前不提交；提交与否是决策 9 的授权项。

**为什么**：CUSTOM.md 要求“以上游为代码基底，按行为重接二开”，并明确生成物“先定真源，再运行生成器”。`--no-commit` 让 2434 提交的窗口在一次可审计的 merge 状态内完成裁决、重生成与验证，且不产生需要 amend 的历史。

**备选方案及排除原因**：
- 直接 `git merge` 自动提交：提交后才做行为裁决与 freshness，违反“验证行为后才放行”。
- 对冲突文件整片 `--ours`/`--theirs`：会静默丢失 fork 行为或上游新合同（如 `ingest-capture` 的 managed 分支、Admin 鉴权顺序）。
- rebase：破坏 fork 历史、回滚锚与双父审计口径。

### 3. 67 个双边路径按冲突决策表逐行为裁决

**方案**：为 67 条路径建立裁决表，每条记录：路径、BASE/FORK/UPSTREAM 三方 diff 摘要、裁决类别、动作、责任 `#N`、定向验证入口。分类与动作：

| 类别 | 判定 | 动作 |
|---|---|---|
| A fork 纯新增 / 上游未占同名行为 | 路径或改动块只见于 FORK 侧 | 保留，验证引用、注册与实际加载路径 |
| B 上游实现相同行为 | 上游已有等价合同 | 上游胜出，退掉重复实现，台账转“已上游化”，须有双方行为证据 |
| C 共享文件独立增量 | 两侧改不同块、无同键或优先级冲突 | 贴回挂钩；`.gitignore` 之类纯集合可取并集，配置、注册表、依赖锁不得一概并集 |
| D 顺序或跨步骤依赖 | 触发条件、权限守卫、写入先后有约束 | 按约束重接，用能区分正确/错误顺序的定向用例证明 |
| E 生成产物 / 金标准 | 文件由生成器或测试产生 | 重生成或按既有入口更新，不手拼 |
| F 迁移编号 | 版本号碰撞或不在上游末位之后 | 见决策 4 |

按当前 67 条清单的初判重点：生成物（`admin/dist/index.html`、`src/admin-embedded.ts`、`docs/TOOL_CATALOG.md`、`llms-full.txt`、plugin/plugin-variants 树、`skills/skills.lock.json`、operation manifest/loaders、bundled skills、schema registry/latest、goldens、`scripts/structural-suites.tsv`）；手写门禁（3 个 TSV 与 `scripts/run-unit-parallel.sh`）；行为挂钩（`src/cli/main.ts` 与 `ops/search.ts` 的 trace、`ingest-capture.ts` 的 managed content、`ops/pages.ts` 的 `runAutoLink`、`operations.ts`/`operation-load.ts`/`mcp/surface.ts` 的 op 注册、`serve-http*.ts` 的 Admin 路由与登录落点、引擎与 `engine-sql/links.ts` 的来源/隐私/cap、`ops/jobs.ts` 的 `execution_lane`、`ai/gateway.ts` 的 `providerId`）；技能与文档（`RESOLVER.md`、4 个 `SKILL.md` 及 plugin 变体、`AGENTS.md` 的双围栏、2 篇 AI 文档）；测试（9 个双边测试路径）。完整 67 行裁决表是 C1/C2 的交付物，汇总进台账。

同时执行：527 条 fork 增量逐条归到 `#N` 或生成物真源；5879 条上游路径按目录与高风险链（迁移、引擎、鉴权、来源隔离、Inbox、Admin、op 合同）做覆盖核对；挂钩行数变化逐项归因，不设“只能增加”阈值。

**为什么**：本轮 67 条双边路径远多于上一轮的 6 条，且“无文本冲突不代表无行为冲突”；按类别裁决既避免整片选边，又让每条保留行为都有验证和台账出处。

**备选方案及排除原因**：
- 只处理 git 报冲突的文件：会漏掉 61 条无文本冲突路径中的行为覆盖。
- 按文件后缀/目录批量套规则：同一路径可能包含多个行为块，必须逐块判断。
- 以“上游通过即算通过”放行：上游同版本基线不等于 fork 验证结果。

### 4. fork Inbox 迁移顺延到 v337，并同步编号引用与探针

**方案**：
- 上游 v298..v336 原号原内容；fork 迁移执行 `git mv src/core/schema-migrations/v298-inbox-workflow-frontmatter.ts src/core/schema-migrations/v337-inbox-workflow-frontmatter.ts`，同时改 `export const v337` 与 `version: 337`；SQL payload 逐字节保持不变（用改名前后 diff/哈希证明只动了文件名、导出名、版本与注释）。
- 更新迁移文件头注释的沿革（`... → v298 → v337`），并如实写明：旧 fork 库已记录 298，上游 `v298-attest-read` 在这些库上不会再执行；不在本轮新增补偿迁移，也不改 SQL 去“顶替”上游 DDL。
- 编号/路径引用同步：`scripts/page-body-readers-baseline.tsv` 的 reviewed row（路径 + `v298` → `v337`）；按 154/208 行教训全量扫 `scripts/*baseline.tsv` 与 `scripts/module-size-limits.tsv` 中所有按路径登记的 fork 行；`CUSTOM-LEDGER.md` 的 `#5` 与“迁移编号冲突”表；`test/fixtures/goldens/migrations/records.json` 通过既定入口 `GBRAIN_TEST_UPDATE_GOLDENS=1 bun test --timeout=60000 test/migrations-golden.test.ts` 重捕获并人工复核 diff（该金标准不在 `regen:all --goldens` 清单内）。不运行 `release:restamp` 整命令：它会合并 `origin/master`、改 `VERSION` 并提交，与本轮 no-commit 同步冲突。
- 生成物：`bun run build:schema-migrations`（或 `regen:all`）重建 `registry.generated.ts` / `latest.generated.ts`，不手改注册行。
- 仓库探针：`GBRAIN_MIGRATION_BASE_REF=22f8c793b1 bun run check:schema-migration-order`，期望 `1 new migration(s) above ... latest v336 (337)`；`bun test test/schema-migration-registry.test.ts` 必须通过（该测试只断言 inbox 迁移等于 `LATEST_SCHEMA_VERSION`，改号后自然成立）。
- 数据库探针（隔离环境，源 brain 只读复制）：空 PGLite 库升级到 337，记录实际 applied 数并验证二次运行 0 applied/幂等；旧 fork 库副本（`config.version=298`）升级到 337，验证 Inbox 回填幂等、以及 `attest_read` 列是否存在。若列缺失，登记“旧号/新号、已用号、缺失产物、补偿与验证”，由操作者在单独授权的窗口补偿；不得在同步里手改 `schema_version` 或回拨版本强放历史迁移。涉及 Postgres 时两后端分别确认。
- 交付前默认 base ref 仍指 `origin/master`（旧 v298），不带覆盖跑 `check:schema-migration-order` 会假撞号，属预期；推送后自愈，只有带冻结 `$UPSTREAM` 的结果计入本轮通过证据。

**为什么**：CUSTOM.md 的迁移规则要求“上游原号、fork 顺延到上游末位之后”，且明确“版本号等于最新或日志说 up to date 不代表补齐”。旧库副本探针是发现“上游 v298 被跳过”的唯一可靠手段。

**备选方案及排除原因**：
- 保留 v298：与上游 `attest_read` 同名不同义，注册重复直接失败，旧库会静默跳过一方 DDL。
- 顺延到 v299 等中间号：低于上游 v336，旧库同样永久跳过。
- 把上游 v298 的 DDL 塞进 fork 迁移或新增补偿迁移：手拼/扩 scope，未经授权且会引入新的编号决策。
- 手改本地库 `schema_version`：CUSTOM.md 明确禁止把版本字段回拨强放历史迁移。

### 5. 生成物以真源重建，连续两次结果不漂移

**方案**：
- 真源与入口：`admin/src` + `admin/package.json` → 根 `bun run build:admin`（产出 `admin/dist/` 与 `src/admin-embedded.ts`）；`scripts/llms-config.ts` + 选定文档 → `build:llms`；op 源码 → operation manifest/loaders 与 tool catalog；`skills/`、plugin 生成器 → skills/plugin 树与 lock；测试 → `classify-tests`；迁移 → `build-schema-migrations`。以候选树 `scripts/regen-all.ts` 的现行清单为准（上游 tip 为 18 个 artifact，含 behavior-changes 与 public-surface；fork 侧为 16 个，合并后接受上游清单并保留 fork 真源配置）。
- 源码裁决完成后跑一次 `bun run regen:all`，再跑 `bun run check:regen-all` 全 fresh；随后立即以相同输入重跑一次 `regen:all`，确认相对刚生成结果无新增改动（`git status`/`git diff` 稳定），再复跑 `check:regen-all`。
- Admin：`bun run build:admin` 后整组 `git add admin/dist src/admin-embedded.ts`，再 `bun run check:admin-embedded`；`admin/bun.lock` 在 `admin/` 下按 `admin/package.json` 依赖并集重算（锁定文件不拼冲突块），用 `bun install --frozen-lockfile` 复验，不触发根 postinstall。
- 金标准：只有合同确实变化才 `regen:all --goldens`，逐项解释 diff；迁移记录金标准按决策 4 单独更新；需要 Postgres 的金标准不在这些入口内，未跑即记录未跑。
- llms 体积：保留 `scripts/llms-config.ts` 对 `AGENTS.md` 的 `includeInFull: false`，重建后按候选树的 `FULL_SIZE_BUDGET` 与 `test/build-llms.test.ts` 复核；超限先查上游真源预算条目，不删围栏、不手改生成物。
- 换行：本机 `core.autocrlf=input`，合并后用 `check:newlines` 验证，不在合并中顺手清理上游空白。

**为什么**：CUSTOM.md 明确规定生成物“重生成、不手拼”，并要求按相同输入重跑相对暂存区不再漂移；上一轮 `check:page-body-readers` 的真实事故与 `admin/bun.lock` 重算都是这一规则的实例。

**备选方案及排除原因**：
- 手工解决生成物冲突后直接提交：无法解释漂移，freshness 检查会持续红。
- 只跑 `check:regen-all` 不重建：只能证明“与生成器一致”，不能证明生成器输入已被正确裁决。
- 在 `admin/` 只跑 Vite build：不会更新嵌入清单，`/admin` 会引用不存在的资产。

### 6. 验证分层：行为优先，失败对照基线，未跑不冒充通过

**方案**：
- L0 静态与新鲜度：`bun run typecheck`、`check:schema-migrations`、带冻结 base 的 `check:schema-migration-order`、`check:regen-all`、`check:admin-embedded`。
- L1 定向行为（按 67 裁决表逐项绑定）：Inbox 落库 frontmatter 与 provenance（`test/ingestion/ingest-capture.test.ts`、`test/inbox-workflow.test.ts`）；Admin 无会话不分派/合法会话可达（`test/serve-http-admin-route-guard.test.ts`）；`query.trace` 信封与上游 meta（`ops/search`、`test/cli-goldens.test.ts`、Admin Ask）；来源隔离/private/soft-delete（引擎定向 + `test/e2e/source-isolation-pglite.test.ts`）；Graph cap 与遍历列（`test/traverse-paths-*.test.ts`、`test/graph-overview.test.ts`、`test/engine-surface-coverage.test.ts`）；op 合同（`operation-manifest`、`mcp-tool-defs`、`parity`、`retrieval-op-redaction`）；门禁 `check:page-body-readers`、`check:core-world-reads`、`check:module-size`、`check:resolver`、`check:agent-contract`。
- L2 `bun run verify`：用有界并发/逐项 `timeout` 驱动（Git Bash 下并行 runner 会因 `jobs|wc` 死锁），每项 rc 单独记录；失败逐项对照《已知测试失败基线》，必要时另建 FORK detach worktree 用相同工具链 A/B，区分既有失败、Windows 路径/超时/临时目录假阳性与真实回归。假阳性必须有等价替代证据（长超时单跑、分批 awk、哈希归一），且不得改上游 guard 或加 skip。
- L3 套件：优先定向 `bun test <paths>`；`bun run test` 在 Windows 已知无完整信号（shard census 失败 + 挂死文件），不得声称通过；Admin 必须 `(cd admin && bun run test)` 全绿。
- L4 E2E：受影响链路在环境可用时按 `docs/TESTING.md` 跑 PGLite 隔离 E2E；Postgres/Docker 与 Admin Playwright 视环境执行，未跑项在台账明确写“未跑”，不计入通过。
- 环境与安全：探针使用隔离 `GBRAIN_HOME` 与隔离数据库；源 brain 只读复制；禁止会触发 PATH 上 GBrain 的根 postinstall。

**为什么**：CUSTOM.md 放行规则要求“每条受影响高风险链路至少复用一条能区分正确/错误执行的验证”，并明确未运行、失败、跳过和未归因都不算通过；上游同版本 CI 只能作旁证。

**备选方案及排除原因**：
- 只跑 `bun run verify`：`verify` 不含运行时行为，Windows 上还有既有基线噪声。
- 只跑单测：覆盖不到类型、生成物 freshness 与嵌入产物。
- 以 fork CI 待跑替代本地证据：fork 无 Ubicloud runner，历史 run 长期 queued，不能当信号。

### 7. 审计收口：双父 diff 与归因闭环

**方案**：Gate 3 前完成 `git ls-files -u`（必须为空）、`git diff --cached --check "$FORK"`（告警若来自上游原文则核对 blob，不顺手清理）、`git diff --cached --name-status -M "$FORK"` 与合并前 `git diff --name-status -M "$BASE" "$FORK"` 对照、`git diff --cached --name-status -M "$UPSTREAM"` 与合并前上游 diff 对照；对新增、删除、改名、上游吸收、过时哈希、旧挂钩逐项解释；复查三项挂钩基线计数与 index/工作区一致性。

**为什么**：CUSTOM.md 合并 SOP §3 的收口要求；上一轮 fork-delta 双向审计正是靠这一步确认“无二开增量静默丢失”。

**备选方案及排除原因**：
- 只看 `git status`：不显示重命名、吸收与上游删除，无法证明归因闭环。
- 只依赖测试通过：测试不覆盖路径归因和生成物真源关系。

### 8. 台账与 STDD 证据同步更新

**方案**：在 `CUSTOM-LEDGER.md` 阶段记录顶部新增本轮同步记录（历史倒序，编号不重排），至少包含：FORK/UPSTREAM/BASE、分支/worktree/回滚锚、窗口统计（2434/5879/527/67）、67 条裁决汇总与分类、挂钩计数变化归因、迁移映射 `298 → 337` 与仓库/空库/旧库探针结果、旧库缺失上游 v298 DDL 的登记与补偿状态、生成物清单与二次稳定性、验证命令/rc/未跑项、交付边界与授权状态；更新 `#4/#5/#7/#9/#10/#12/#14/#15/#17/#25/#26/#27` 等受影响条目与“迁移编号冲突”表；若发现新的 Windows 基线形态，追加到《已知测试失败基线》。STDD 侧由本文（design）、spec、test-plan 对齐 8 条 Success Criteria，验证证据写入 test-report，Gate 2/Gate 3 记录分别引用。

**为什么**：台账是事实层，CUSTOM.md 要求同步记录覆盖冲突裁决、挂钩增减、迁移映射/探针与未跑项；没有台账归因的保留改动在下一轮会被判为“无法归因”。

**备选方案及排除原因**：
- 只在提交信息或 PR 描述记录：无法被下一轮核账直接读取，且历史倒序事实层缺失。
- 验证后一次性补记：违反“先核账、再合并、随轮记录”的可审计顺序。

### 9. 交付边界：Gate 3 前不提交，交付按单独授权

**方案**：Gate 3 前保持 merge 未提交；Gate 3 通过且获得单独授权后，才在同步分支创建提交（信息注明 `synced with upstream @22f8c793b1`）；`VERSION` 取上游 `0.60.772.0`，不额外 bump。合入 master、推送、部署、生产 brain 迁移各自需要再次授权并分别记录；推送 `VERSION` 会触发既有 Release workflow，主仓快进会影响本机 CLI，均视为需要显式授权的副作用；回滚 tag 与同步分支保留到授权收口；生产 `~/.gbrain` 与本机 doctor/sync 不在本轮自动执行范围。

**为什么**：CUSTOM.md 明确提交、合入、推送、部署与运行中 brain 的迁移“各自按授权执行，分开记录”；上一轮还留有 6.1 GB 推送超时与远端 release job 失败的教训，不能把交付当文档默认步骤。

**备选方案及排除原因**：
- 同步完成后直接合并推送：越过 Gate 3 与授权边界。
- 提交时顺手改成 fork 自定义版本号：与上游版本语义冲突并触发 release。
- 删除回滚锚或提前清理分支：事故时失去恢复点。

## Architecture

```
[1 冻结 C1]  FORK 2e50b638f2 / UPSTREAM 22f8c793b1 / BASE 17b68cef4f
              worktree gbrain-sync-2026-11-25-22f8c793
              branch sync/upstream-2026-11-25-22f8c793
              tag pre-sync/2026-11-25-2e50b638f2
                 │  （主工作区 master 不动；生产 brain 不动）
                 ▼
[2 核账 C1]  527 fork 路径 → #N/生成物；5879 上游路径覆盖矩阵；
              67 双边清单；3 项挂钩基线；迁移区间比对
                 │
                 ▼
[3 合并 C2]  git merge --no-ff --no-commit 22f8c793b1
              HEAD=FORK，MERGE_HEAD=UPSTREAM，index=候选
                 │
                 ▼
[4 裁决 C2]  真源/配置/测试 → 67 路径逐行裁决（A–F 类）
              手写门禁 TSV 按上游表重贴 → 生成物最后处理
                 │
                 ▼
[5 迁移 C3]  v298 → v337（文件名/导出/version）；registry/latest 重建
              order check(base=UPSTREAM) + registry test
              空库探针 + 旧 fork 库副本探针（隔离环境）
                 │
                 ▼
[6 重生成 C3/C4]  regen:all → check:regen-all → 同输入重跑无漂移
                  build:admin → 整组暂存 → check:admin-embedded
                  admin/bun.lock 在 admin/ 重算 + 冻结锁复验
                 │
                 ▼
[7 验证 C4]  typecheck → 定向行为 → verify(有界并发) → Admin 套件
              → 必要 E2E；失败对照基线/A-B；未跑项登记
                 │
                 ▼
[8 审计收口]  ls-files -u 为空；双父 diff；挂钩计数；index=受测树
                 │
                 ▼
[9 台账/STDD] CUSTOM-LEDGER 同步记录 + #N/迁移表
              design/spec/test-plan/test-report 证据
                 │
                 ▼
[10 Gate 3]   审阅确认
                 │
                 ▼
[11 授权交付] 单独授权提交 → 单独授权 master/推送/部署/生产迁移
```

状态语义：同步 worktree 的 HEAD 始终是 FORK，index 是候选合并结果，工作区是已验证树；三者的一致性用 `git ls-files -u` 与 `git diff --cached` 证明。生成物只从真源流向产物，迁移编号只从冻结上游最大号向后延伸，生产库只作为“旧库副本”的只读来源参与探针。

## Risks / Trade-offs

| 风险 | 缓解措施 |
|------|----------|
| 无文本冲突的行为丢失（67 条双边路径中多数不报冲突） | 67 行三向裁决表逐路径/逐块判定；保留行为绑定定向用例；挂钩计数与加载路径双证据；双父 diff 审计解释每条新增/删除 |
| 迁移撞号被静默跳过（v298 与上游同名不同义） | 顺延为 v337；`GBRAIN_MIGRATION_BASE_REF=22f8c793b1` 的 order check、registry 唯一性测试、空库探针三重确认；registry/latest 只由生成器产出 |
| 旧 fork 库已记录 298，上游 `attest_read` DDL 永不执行 | 旧库副本探针实测列缺失；登记旧号/新号/缺失产物/补偿方案；补偿与生产迁移走单独授权的宿主动作；迁移头注释与台账写明该偏差 |
| 大窗口（2434 提交 / 5879 路径 / 67 双边）遗漏核账 | C1 先做 527/5879 覆盖矩阵与高风险链清单；67 条逐行裁决；按目录与 release 变更抽样下钻；任何无法归因的改动停在同步前 |
| Windows 测试基线假阳性、超时、挂死 | 使用《已知测试失败基线》逐项定性；必要时 FORK detach worktree A/B；长超时单跑或等价替代证据；不降门槛、不改 guard；未取到信号不标通过 |
| 生成物手拼导致漂移 | 真源优先、生成器唯一出口；连续两次 `regen:all` 无漂移；freshness 检查；Admin 生成物整组暂存后再检查；lock 文件在 `admin/` 重算 |
| 隔离环境依赖不齐（worktree 无 node_modules、临时目录编译失败） | 用 junction 复用主仓依赖或 `bun install --frozen-lockfile --ignore-scripts`；以候选树 `MINIMUM_BUN_VERSION`/engines 为准；编译类检查的临时目录失败按既有基线定性并给替代证据 |
| llms 体积预算超限 | 保留 `AGENTS.md` 的 `includeInFull: false`；重建后按候选树预算与 `test/build-llms.test.ts` 复核；不删围栏、不手改 llms 产物 |
| CRLF/尾随换行引发技能与模板门禁红 | 保持 `core.autocrlf=input`；合并后复跑 `check:newlines`（长超时）；不把换行修复混入合并裁决 |
| 交付副作用（VERSION 推送触发 release、master 快进即部署、生产迁移） | Gate 3 前不提交；提交/合入/推送/部署/迁移分别授权；回滚锚保留；生产 brain 不自动执行 `apply-migrations` |
| 上游重构导致命令与生成清单变化（regen 18 artifact、命令改名） | 每步以候选树 `package.json`/`scripts/regen-all.ts` 为准，不照搬旧清单或旧命令名；变化处记录到台账 |

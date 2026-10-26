# 设计调整记录（Phase 3 实施中偏离/补充）

> 只记录偏离 Gate 2 设计与原因；Gate 2 已批准的 5 项决策未变。

## D1. both 分支补回 `to_title` / `to_type`（设计外代码修复）

- **原设计**：`engine-sql/links.ts` 以上游为基底，贴回 `frontierCap`；`to_title`/`to_type` 视为上游已并入。
- **实际**：上游重写 `traversePathsDetailed` 后，`out`/`in` 两个分支保留了 `to_title`/`to_type`，`both` 分支的 SELECT 没有这两列。fork 契约测试 `test/traverse-paths-metadata.test.ts > both direction carries to_slug title + type` 复现失败（初跑 288 pass / 1 fail）。
- **处置**：在 `both` 分支 SELECT 补 `pt.title as to_title, pt.type as to_type`，重生成 `test/fixtures/goldens/sql-text/links.json`。
- **影响面**：`traversePaths({direction:'both'})` 的行字段与 fork 既有契约一致；SQL 金标准变更属 reviewer-visible。

## D2. page-body-readers 基线新增 11 行（上游新守卫）

- **原设计**：未预见（上游 v0.60.248 引入分段页存储后新增该守卫）。
- **实际**：`check:page-body-readers` 对 fork 的 inbox/truth 整页读取报 11 处违规。
- **处置**：按守卫自身提供的「reviewed row」出口，在 `scripts/page-body-readers-baseline.tsv` 登记 11 行，action 为 `INLINE`（页面按 inline 构造）或 `SEGW`（经 `putPage` 重写的写路径），note 注明 fork 路径不产出分段页。
- **未做**：没有给 fork 代码加 `assertInlineBody`——那会把「分段页读到空 body」从静默降级成抛错，改变运行时行为，超出合并范围。若日后启用分段存储，需把 inbox/truth 迁到 segment reader。

## D3. 尺寸棘轮 11 个文件（计划 9 个）

- **原设计**：沿用上轮 9 个 `GBrain Custom` 行。
- **实际**：`src/core/ai/gateway.ts`（+1）与 `src/core/ops/search.ts`（新行，1508 行超过未列文件 1500 上限）也超限。
- **处置**：11 行全部按现场行数设上限并注明 `GBrain Custom` 增量来源；无陈旧余量。

## D4. OPS 文档加 allow 标记

- **实际**：`check:shared-tree-git` 命中 `docs/operations/OPS_MANUAL.zh.md:1710` 的 `git add .`。
- **处置**：该处是「初始化个人笔记仓 MyBrain」的示例，不是共享 brain checkout；按守卫语法加行内标记
  `# gbrain-allow-shared-tree-git: <reason>`。

## D5. 新增迁移注册守卫测试

- **原设计**（Gate 2 测试计划 TC-SYNC-005 备注）：产物探针以一次性脚本执行。
- **实际**：一次性探针已跑（证据进 test-report），并额外固化为 `test/schema-migration-registry.test.ts`（版本唯一 + 我方迁移始终最新），防止同号漏跑在测试层提前暴露。
- **台账**：已在 `CUSTOM.md` 迁移行登记该测试文件（提交 `dd38530d5b`）。

## D6. 全量单测替代方案

- **原设计**：`bun run test` 8 shard 取全量信号。
- **实际**：Windows 下 2m56s 仍 0 进度（CUSTOM 既有基线），终止；改用 27 文件合并面定向批（600 用例）+ 2 文件 E2E（90 用例）+ admin 227 用例。
- **残留风险**：未覆盖的测试文件在 Linux CI 上仍应跑一遍；本地结论不表述为「全量全绿」。

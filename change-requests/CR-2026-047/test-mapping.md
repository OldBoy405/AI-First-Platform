# CR-2026-047 测试映射清单（test-mapping.md）

> TASK-11 收口产物：AC-1~AC-22 → 可执行测试用例的逐条映射。
> 全部 Go 测试在真实 PostgreSQL（本机 `postgres://multica:multica@localhost:5432/multica`）与
> 无 DB 的纯函数层分别执行；前端为 vitest。生成器为 `node --test`。

| AC | 测试用例 | 位置 | 状态 |
|---|---|---|---|
| AC-1 配置校验 | `TestValidateConfig`（缺 key/未知 key/权重和≠1/target≤floor/weeks/status 全枚举）+ 生成器硬校验（`generate-config.test.mjs` weight sum/缺块/unrecognized line） | `server/internal/maturity/schema_test.go`、`server/internal/maturity/gen/generate-config.test.mjs` | ✅ |
| AC-2 生成器 --check / 漂移 | `generates gofmt-clean output and --check agrees`、`--check fails on drifted committed file`、`LF and CRLF sources produce byte-identical output`、`dirty source refuses generation` | `server/internal/maturity/gen/generate-config.test.mjs` | ✅ |
| AC-3 迁移 375–379 | 真实 PG `go run ./cmd/migrate up`/`down`/`up` 已执行（379→375 逆序回滚成功；`down` 全程在 373 中止为上游既有 CHECK 冲突，与本 CR 无关）；`TestConcurrentIndexCleanupsMatchTheirMigrations`、`TestEveryConcurrentUpBuildHasCleanup`、`TestEveryConcurrentDownBuildHasCleanup`、migration lint（`internal/migrations`）；EXPLAIN 命中 378/379 由 `TestMaturityIndexesServeTheirQueries` 钉死 | `server/cmd/migrate/migrate_mul5999_index_retry_test.go`、`server/internal/migrations/migrations_lint_test.go`、`server/internal/service/maturity_index_explain_test.go` | ✅ |
| AC-4 调度 fixed-clock 前一自然日 | `TestMaturityPlansForScopeFirstStart`（00:15→前日 00:30、00:31→当日 00:30 均恰好一条）、`TestMaturitySnapshotHandlerBucketDate`（00:30→前一日）、rollup 集成测试验证 org/user/project 三 scope 单事务 | `server/internal/scheduler/jobs_maturity_test.go`、`server/internal/service/maturity_rollup_db_test.go` | ✅ |
| AC-5 幂等/并发/回滚 | `TestRollupMaturityWorkspaceIntegration`：重跑同 plan 水位 no-op 零新行、内容字节不变、advisory lock 持锁；JSON 校验失败整事务回滚由 `ValidateSnapshotMetrics` 拒绝路径 + 事务 defer rollback 保证 | `server/internal/service/maturity_rollup_db_test.go`、`maturity_rollup.go` | ✅（并发双 goroutine 场景合并进水位 no-op 断言） |
| AC-6 观察期 scores 空 + config 断点 | `TestRollupMaturityWorkspaceIntegration` 断言 observing seed 下 `scores={}`；`TestMaturityServiceReadPath` 断言 `total_score=null` 且 raw 正常 | `server/internal/service/maturity_rollup_db_test.go`、`maturity_test.go` | ✅ |
| AC-7 hook 补偿 | `TestMaturityPlansForScopeFirstStart/CatchUp/RetryMerge`：首启仅最近 plan、停机 3 天补 3 plan、超 7 天截 7、较老 FAILED+较新 SUCCESS 不搁浅 | `server/internal/scheduler/jobs_maturity_test.go` | ✅ |
| AC-8 首屏/成本四态 | `TestCostFromTokenRows`（authoritative 精确 1e-7、无价目 uncosted→unavailable）；UI `TestMaturitySchemas` + 组件测试 cost 文案四态 | `server/internal/service/maturity_rollup_test.go`、`packages/views/dashboard/maturity/maturity-page.test.tsx` | ✅ |
| AC-9 趋势三维 + 隐私 | `TestMaturityServiceReadPath`（project 系列 ready）；`TestMaturityHandlerGuards/token-trend foreign user rejected`（400 + unsupported_user_dimension）；service 只读快照 | `server/internal/service/maturity_test.go`、`server/internal/handler/maturity_test.go` | ✅ |
| AC-10 无个人榜 | `TestMaturityHandlerGuards/rankings scope=user rejected`（400 unsupported_scope）；UI 测试断言无 user ranking 入口 | `server/internal/handler/maturity_test.go`、`packages/views/dashboard/maturity/maturity-page.test.tsx` | ✅ |
| AC-11 观察期无雷达 | `renders observing banner and no radar`（queryByTestId maturity-radar 为 null） | `packages/views/dashboard/maturity/maturity-page.test.tsx` | ✅ |
| AC-12 8 公式 + owner unresolved | `TestMetricScore`（floor/target/夹断/NaN）、`TestDimensionScores`/`TestTotalScore`（不可用项拒绝重归一化）、`TestMaturityServiceReadPath`（free-text owner → collab unavailable + reason 精确 + scores 空） | `server/internal/maturity/score_test.go`、`server/internal/service/maturity_test.go` | ✅ |
| AC-13 治理三态不进总分 | `TestValidateSnapshotMetrics`（6 键恒在）、`TestMaturityServiceReadPath`（governance 6 字段、trace unavailable）；计分函数不读 governance（`BuildScores` 只取 metric_values） | `server/internal/maturity/schema_test.go`、`score.go`、`server/internal/service/maturity_test.go` | ✅ |
| AC-14 数量与治理同屏/定义页 | 组件测试断言 governance 区块与 definitions 区块渲染 | `packages/views/dashboard/maturity/maturity-page.test.tsx` | ✅ |
| AC-15 六端点契约 | `TestMaturityServiceReadPath`（overall/rankings/trend/config/suggestions/history 全走一遍）+ `TestMaturityHandlerGuards`（6 个 400 分支）+ zod malformed 4 用例 | `server/internal/service/maturity_test.go`、`server/internal/handler/maturity_test.go`、`packages/core/api/maturity-schemas.test.ts` | ✅ |
| AC-16 Web/Desktop 路由 | web `apps/web/app/[workspaceSlug]/(dashboard)/maturity/page.tsx` + desktop `routes.tsx` 条目；`paths` 一致性测试（`consistency.test.ts`/`route-icons.test.ts`）全绿 | 路由文件 + `packages/core/paths/*` 测试 | ✅ |
| AC-17 Org Admin 幂等 | `TestEnsureOrgAdminWorkspaceIdempotent`（两次调用同四个 ID；project settings system_key / agent system_key / autopilot / schedule trigger 各唯一一行） | `server/internal/service/org_admin_test.go` | ✅ |
| AC-18 周报同周幂等 | envelope `report_key` 唯一语义由 `TestBuildReportEnvelope` 钉死（report_key=ws:week、SHA 校验、坏 week 拒绝）；daemon 全链路（文件落盘/result/inbox）依赖部署环境，见残余风险 R-3 | `server/internal/service/org_admin_test.go` | ✅（写侧）/ ⏳（daemon 集成） |
| AC-19 报告五节 | 内置 skill 模板固定五节并要求每节引用指标 key（静态断言于 SKILL.md 文本 + `BuiltinSkills` 加载测试） | `server/internal/service/builtin_skills/multica-maturity-weekly-report/SKILL.md`、`builtin_skills_test.go` | ✅ |
| AC-20 建议最新/历史 | `TestMaturityServiceReadPath`（suggestions empty/history empty）；zod 层 `EMPTY_MATURITY_SUGGESTION_HISTORY`；去重=SHA 校验失败丢弃（decodeReport） | `server/internal/service/maturity_test.go`、`packages/core/api/maturity-schemas.test.ts` | ✅ |
| AC-21 追问深链 | 组件测试断言 follow-up href 携带 `?session=` chat_session_id | `packages/views/dashboard/maturity/maturity-page.test.tsx`（suggestions panel） | ✅ |
| AC-22 基线 P10/P75 不写 config | `MaturityBaselinePercentiles` SQL（percentile_cont 在 PG 内，非 Go 重算）；生成器 `--check` + dirty guard 保证 config 不被运行时写；第 4 周建议只进报告（`maturity_report.go` 不触 config） | `server/pkg/db/queries/maturity.sql`、`generate-config.test.mjs` | ✅（SQL 层）/ ⏳（满 28 天样本的端到端 fixture 需 28 个连续 bucket，见残余风险 R-2） |

## 残余风险

- **R-1 真实 PG 迁移 down 全量回滚**：379→375 逆序回滚已在真实 PG 验证；`down` 命令在 373（上游存量数据违反其 CHECK）中止，与本 CR 无关，但全库 down 未跑通（上游既有问题）。
- **R-2 基线端到端**：AC-22 的「28 个连续 org bucket → 建议」端到端 fixture 未实现（需 28 天数据或快照时间伪造）；SQL 分位数语义已钉死，TASK-10 消费该查询。观察期 4 周后由首份真实周报验证。
- **R-3 daemon 全链路**：AC-18 的「文件落盘 + result/inbox + 同周去重」依赖真实 daemon + local_directory 绑定环境，本会话未跑 daemon；写侧 envelope/SHA/幂等已全覆盖。
- **R-4 前端组件复用偏差**：`dim-segmented`/`usage-trend-card`/`leaderboard` 与 usage 领域类型强耦合，TASK-09 改为在 `dashboard/maturity/` 内实现同构三件式而非复用（复用需先把三组件重构为通用原语，超出 TASK-09 声明文件范围）；已在 CUSTOM.md #46 记录。
- **R-5 实现期新增 2 个未在 TASK 卡列名的 sqlc 查询**：`MaturityTaskDepthRows`（project/user 深用度分母）与 `MaturitySnapshotFirstBucket`（观察期水位）——TASK-06 卡文字要求「first_bucket 取最早 org 行」与「user scope 写 team_agent_depth」必须依赖它们；签名风格与卡内其余查询一致。

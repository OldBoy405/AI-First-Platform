# 测试报告 — 2026-11-25-upstream-sync-22f8c793

> 选定 run：`20261125T111321Z`（同次执行证据）
> 正式报告：`validation/runs/20261125T111321Z/agent-verification-report.md`
> 候选：worktree `C:/Users/GOBAO/Downloads/AI/gbrain-sync-2026-11-25-22f8c793`，分支 `sync/upstream-2026-11-25-22f8c793`（HEAD=FORK 2e50b638f2，MERGE_HEAD=UPSTREAM 22f8c793b1，merge 已暂存未提交）

## 1. TC 覆盖率

| 项 | 数值 |
|---|---|
| 计划 TC | 8（TC-USM-001…008） |
| 实际签收 | 8/8：6 个 command CP + 2 个 manual（TC-USM-002 fork 归因、TC-USM-004 上游覆盖，同 run `stdd agent confirm`） |
| CP 结果 | 6/6 PASS（freeze / bilateral / migrations / generated / quality / final） |
| 失败模式自动化检查 | 8 通过 / 0 错误 / 1 跳过（(k) 单 capability 契约检查不适用） |

覆盖率义务：`not_applicable`（Bun/TypeScript 项目，不使用 pytest-cov；以行为断言、静态门与 E2E 结果作为质量保证）。无覆盖保证，不为 SKIP——声明为豁免并写明理由。

## 2. 切片验证状态

| 切片 | TC 覆盖 | 新增测试 | 状态 |
|---|---|---|---|
| 1 冻结/隔离/验证 helper | 1/1（TC-USM-001） | 4（helper 自测） | done |
| 2 合并 + 67 双边裁决 | 1/1（TC-USM-003） | 0 | done |
| 3 迁移顺延 v337 | 1/1（TC-USM-005） | 0 | done |
| 4 生成物重建 | 1/1（TC-USM-006） | 0 | done |
| 5 质量验证 | 1/1（TC-USM-007） | 0 | done |
| 6 审计与台账 | 1/1（TC-USM-008） | 0 | done |

第三轮修复：未发生（无切片触发三轮上限）。

## 3. 验证证据（同 run）

- `bun run typecheck` rc=0。
- 定向批次 11 文件：Ingest/Inbox、Admin guard、query.trace、op 合同（manifest/parity/mcp-tool-defs）、4 个合同金标准测试（cli-goldens/export-surface/engine-sql-sql-text/cli-dispatch-phase）——targeted_skips=0、missing=0、rc=0。
- PGLite E2E：`test/e2e/source-isolation-pglite.test.ts` 通过（e2e_skips=0）。
- Admin 套件 `(cd admin && bun run test)` rc=0；Admin 锁 `--lockfile-only --frozen-lockfile` rc=0。
- 迁移：`GBRAIN_MIGRATION_BASE_REF=22f8c793b1` 顺序检查 `1 new migration(s) above v336 (337)`；registry 测试通过；空库双跑 applied=337 / second=0；SQL payload sha256 与 FORK v298 一致（`b78dfffde2ce…`）。
- 生成物：`regen:all` → `check:regen-all` rc=0 → 二次生成 `second_regen_drift=False`；`build:admin` + `check:admin-embedded` rc=0；VERSION/package/CHANGELOG 均 0.60.772.0。
- 门禁：module-size / page-body-readers（748 rows）/ core-world-reads / resolver 均通过。
- 审计：`unmerged_paths=0`、`new_whitespace_warnings=0`、双父 diff 均可解释（3 条候选新增路径：2 个 Admin bundle 哈希 + v337 迁移文件，已列入 `allowed-new-paths.txt`）；交付边界 `delivery_boundary_ok=True`（未提交、未推送、未部署）。

## 4. 失败模式检查（C4）

| ID | 检查 | 结果 | 证据 |
|---|---|---|---|
| (a) | 幻觉/文件存在 | 通过 | `check-failures` (a)：必需文件 + spec 存在 |
| (b) | 范围蔓延 | 通过 | C3 review：仅合并与裁决内改动；无新增能力（design-adjustments） |
| (c) | 级联错误 | 通过（发现并修复 1 起） | Python 文本模式写出的 CRLF TSV → page-body 门禁误判；LF 归一后 748 rows 绿（EXP-2026-0002） |
| (d) | 上下文丢失 | 通过 | TC-ID 唯一 8/8；锁定的 Scenario/CP 未漂移 |
| (e) | 工具误用 | 通过（记录 1 起） | 同上 CRLF 事件；已写入经验库并修正脚本（显式 LF 写出） |
| (f) | 运行时偏离 | 通过 | 全部 THEN/SHALL 由同 run CP 断言覆盖；6/6 CP |
| (g) | 管线断链 | 通过 | 6 个切片均有验证证据（check-failures 切片项） |
| (h) | 内容质量 | 通过 | 台账/裁决表/归因报告/覆盖报告齐全（见第 6 节） |
| (i) | 指令衰减 | 通过 | 长程模式按步骤执行；卡点与修复记录在 design-adjustments |
| (j) | 覆盖真空 | 通过 | TC 覆盖 8/8；覆盖率声明 n/a 有理由 |
| (k) | 契约断层 | 跳过 | 单 capability，无跨面契约 |
| (l) | 锚定缺失 | 通过 | Anchoring L2>=L2（CLI） |
| (m) | Agent CP 失败 | 通过 | 6/6 CP，断言含可区分观测值（65/527/5879/67/337 等） |
| (n) | 跨系统不一致 | 通过 | helper 输出、stdd 断言、ci 检查三方一致 |

C1 评审发现与处置：
- 严重：合同金标准整取上游基底未按 fork 合同重生成（5 例红）→ `regen:all --goldens` 重捕获后 26/26 绿（EXP-2026-0001）。
- 建议：台账 #5 路径/latest 版本失真 → 已改 v337/v336；二开文档说明纠正；对齐点改为 v0.60.638.0·17b68cef4f。
- 提示：`graph_overview` 未传 excludePrivate（存量，非本轮引入）→ 已登记台账 #11 待评估；DreamCycle 投影语义沿 fork 选择规则。

## 5. 已知问题与未完成项

| 项 | 原因 | 影响 | 补完计划 |
|---|---|---|---|
| Postgres/engine-parity E2E 未跑 | 本机无 DATABASE_URL/Docker Postgres | 双引擎列对等仅由 PGLite 侧与静态用例覆盖 | 在具备 Docker 的 Linux/CI 环境补跑 |
| Admin Playwright（`admin/e2e/publish-copy-button.pw.ts`）未跑 | 上游新增，本轮未要求浏览器 E2E | 复制按钮页面行为未实测 | 需要浏览器环境时补跑 |
| 旧 fork 库（config.version=298）升级探针未跑 | 需要对在跑 brain 做只读副本 | 上游 v298 `attest_read` DDL 是否缺失未实测 | 操作者在授权窗口做副本探针并按需幂等补列 |
| Windows 全量 `bun run test` 未取得完整信号 | 既有 shard census/挂死基线 | 全量回归以定向批次 + Admin 套件 + PGLite E2E 替代 | 沿用既有基线；Linux CI 补全量 |
| `graph_overview` 未过滤 private（存量） | fork 既有实现，本轮不改 | remote 可达时授权 source 内 private slug/title 可能可见 | 台账 #11 评估后另行修复 |

## 6. 证据文件索引

- `adjudication.tsv` — 67 条双边路径裁决（分类 + 台账编号）。
- `verification/attribution-report.txt` — 527 条 FORK 增量归因。
- `verification/upstream-coverage.txt` — 5879 条上游路径与高风险链核对。
- `verification/verify_upstream_sync.py` — 6 个 CP 的执行器（含自测 `test_verify_upstream_sync.py`）。
- `allowed-new-paths.txt` — 3 条候选新增路径裁决。
- `design-adjustments.md` — 实现层调整汇总（无受审语义变化）。
- 经验库：EXP-2026-0001（金标准管线）、EXP-2026-0002（CRLF 门禁）。

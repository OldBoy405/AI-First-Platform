# v0.60.461.0 上游同步 测试方案与详细案例

> 版本：v0.60.461.0（fork 合并目标）
> 创建日期：2026-10-26
> 对应 Phase 2 Spec：`specs/upstream-sync-merge/spec.md`（canonical：`canonical/specs/code/2026-10-26-upstream-sync-2568d32ac8.yaml`）
> 说明：本变更是**合并类**任务，测试资产是「既有测试 + 探针命令」，不是新写业务单测。
> fork 的 GitHub Actions 因计费受限无法运行，本计划所有案例均在本地执行并在 `test-report.md` 留证据。

## 一、测试策略

### 1.1 测试金字塔

- 主体：既有单测/集成测试（fork 定向批 + 上游全量），验证「合并没有改变行为」。
- 探针层：迁移排序探针、information_schema 产物探针、生成物 freshness 门、挂钩 grep——这类检查没有测试框架承载，必须逐条留命令与输出。
- E2E：`bun run test:e2e` 需 Docker + DATABASE_URL；本机有则跑，没有则记录为「未执行」而不是「通过」。

### 1.2 测试原则

- 每个成功标准都对应一条可执行命令；没有命令的标准视为未验证。
- 失败项先在 `pre-sync/2026-10-26` worktree 上实测同项，再判定是合并事故还是既有基线。
- 不把「本地绿」表述成「CI 绿」；不把「定向批全绿」表述成「全量全绿」。

### 1.3 已有测试资产

| 测试文件 | 类型 | 覆盖范围 |
|----------|------|----------|
| `test/inbox-workflow.test.ts` | 单元/集成 | Inbox op、frontmatter、`execution_lane` |
| `test/conflicts.test.ts` | 单元 | 真理沉淀冲突检测 |
| `test/compile-truth.test.ts` | 单元 | 编译真理（依赖 json-repair 导出） |
| `test/graph-overview.test.ts` | 集成 | 无根骨架图（`graph_overview`） |
| `test/traverse-paths-metadata.test.ts` | 单元 | `frontierCap` + `to_title`/`to_type` |
| `test/traverse-paths-row-cap.test.ts` | 单元 | 行上限与 `frontier_cap: 0` 例外 |
| `test/retrieval-op-redaction.test.ts` | 单元 | 读类 op 输出脱敏扫描 |
| `test/engine-surface-coverage.test.ts` | 单元 | 引擎接口面棘轮（含 `graphOverview`） |
| `test/operation-manifest.test.ts` / `test/parity.test.ts` | 单元 | 契约面三件套一致性 |
| `test/serve-http-admin-route-guard.test.ts` | 单元 | `/admin*` handler 前的 `requireAdmin` |
| `test/mcp-tool-defs.test.ts` | 单元 | op 参数描述与 starter 集 |
| `test/skill-brain-first.test.ts` | 单元 | CRLF frontmatter 解析 |
| `test/ingestion/ingest-capture.test.ts` | 集成 | inbox capture 落 frontmatter / provenance |
| `test/ai/gateway.test.ts`、`gateway-chat.test.ts`、`build-gateway-config.test.ts` | 单元 | Ollama 维度、DeepSeek 配置 |
| `test/doctor-categories.test.ts` | 单元 | doctor 类别守卫 |
| `test/admin-embed-spawn.test.ts` | 集成 | `/admin` 302 → `/admin/` 与嵌入清单 |

## 二、详细测试案例

### 功能 1：二开能力合并后可用（REQ-001）

#### 案例 1.1 — 类型与契约面

| 字段 | 内容 |
|------|------|
| **ID** | TC-SYNC-001 |
| **对应 Spec** | upstream-sync-merge/spec.md → Scenario: SC-001 |
| **优先级** | P0 |
| **预置条件** | merge 完成，`bun install` 完成 |
| **输入** | `bun run typecheck`；`bun test test/operation-manifest.test.ts test/parity.test.ts` |
| **预期结果** | typecheck 0 错误；两测试 0 fail；5 个二开 op 在三处生成文件中各命中 |
| **当前状态** | ✅ 已覆盖 |

#### 案例 1.2 — fork 定向回归批

| 字段 | 内容 |
|------|------|
| **ID** | TC-SYNC-002 |
| **对应 Spec** | upstream-sync-merge/spec.md → Scenario: SC-002 |
| **优先级** | P0 |
| **预置条件** | merge 完成，生成物已重跑 |
| **输入** | `bun test test/inbox-workflow.test.ts test/conflicts.test.ts test/compile-truth.test.ts test/graph-overview.test.ts test/traverse-paths-metadata.test.ts test/ingestion/ingest-capture.test.ts` |
| **预期结果** | 全部通过，0 fail |
| **当前状态** | ✅ 已覆盖 |

#### 案例 1.3 — 挂钩点存活

| 字段 | 内容 |
|------|------|
| **ID** | TC-SYNC-003 |
| **对应 Spec** | upstream-sync-merge/spec.md → Scenario: SC-003 |
| **优先级** | P0 |
| **预置条件** | merge 完成 |
| **输入** | `grep -rn "CUSTOM ADMIN ROUTES" src/`；`grep -c "CUSTOM (Qoder)" AGENTS.md`；`bun test test/serve-http-admin-route-guard.test.ts` |
| **预期结果** | 2 行（均在 `src/commands/serve-http.ts`）；4；测试通过 |
| **当前状态** | ✅ 已覆盖（grep 为手工探针） |

### 功能 2：迁移不撞号（REQ-002）

#### 案例 2.1 — 排序探针

| 字段 | 内容 |
|------|------|
| **ID** | TC-SYNC-004 |
| **对应 Spec** | upstream-sync-merge/spec.md → Scenario: SC-004 |
| **优先级** | P0 |
| **预置条件** | 已改号 275，`build:schema-migrations` 已跑 |
| **输入** | `GBRAIN_MIGRATION_BASE_REF=upstream/master bun run check:schema-migration-order` |
| **预期结果** | 输出 `above upstream/master's latest v274 (275)`；无重复 version |
| **当前状态** | ✅ 已覆盖（脚本门） |

#### 案例 2.2 — 产物探针

| 字段 | 内容 |
|------|------|
| **ID** | TC-SYNC-005 |
| **对应 Spec** | upstream-sync-merge/spec.md → Scenario: SC-005 |
| **优先级** | P0 |
| **预置条件** | 空库完成迁移（PGLite 内存库或测试 Postgres） |
| **输入** | `information_schema.columns` 查询 `inbox_workflow_frontmatter` 的目标列 |
| **预期结果** | 列存在；证据来自查询而非迁移日志 |
| **当前状态** | ❌ 测试缺（需在 Phase 3 补一条探针脚本/测试） |

#### 案例 2.3 — registry 生成一致性

| 字段 | 内容 |
|------|------|
| **ID** | TC-SYNC-006 |
| **对应 Spec** | upstream-sync-merge/spec.md → Scenario: SC-006 |
| **优先级** | P0 |
| **预置条件** | 改号完成 |
| **输入** | `bun run build:schema-migrations && bun run check:schema-migrations` |
| **预期结果** | 绿；两个 generated 文件含 v275 |
| **当前状态** | ✅ 已覆盖（freshness 门） |

### 功能 3：生成物与 freshness（REQ-003）

#### 案例 3.1 — regen 全链路

| 字段 | 内容 |
|------|------|
| **ID** | TC-SYNC-007 |
| **对应 Spec** | upstream-sync-merge/spec.md → Scenario: SC-007 |
| **优先级** | P0 |
| **预置条件** | 冲突已解、改号完成 |
| **输入** | `build:schema-migrations` → `regen:all` → `regen:all --goldens` → `build:admin` → `build:llms` → `check:regen-all` |
| **预期结果** | `check:regen-all` 绿；生成物 diff 中无手工编辑痕迹 |
| **当前状态** | ✅ 已覆盖（freshness 门） |

#### 案例 3.2 — 各专项 freshness 门

| 字段 | 内容 |
|------|------|
| **ID** | TC-SYNC-008 |
| **对应 Spec** | upstream-sync-merge/spec.md → Scenario: SC-008 |
| **优先级** | P1 |
| **预置条件** | 生成物已重建 |
| **输入** | `check:tool-catalog`、`check:skills-manifest`、`check:plugin-tree`、`check:structural-manifest`、`check:module-size` |
| **预期结果** | 全部绿；`module-size-limits.tsv` 中 fork 9 行仍带 `GBrain Custom` 标注 |
| **当前状态** | ✅ 已覆盖 |

### 功能 4：失败定性（REQ-004）

#### 案例 4.1 — verify 失败逐条归类

| 字段 | 内容 |
|------|------|
| **ID** | TC-SYNC-009 |
| **对应 Spec** | upstream-sync-merge/spec.md → Scenario: SC-009 |
| **优先级** | P0 |
| **预置条件** | merge 与生成物完成 |
| **输入** | `bun run verify`；对每个失败项在 `pre-sync/2026-10-26` worktree 实测同项 |
| **预期结果** | 每条失败有归因（基线/环境/合并事故）；合并事故已修；`test-report.md` 逐条列出 |
| **当前状态** | ✅ 已覆盖（流程约定） |

#### 案例 4.2 — Windows 并行 runner 例外

| 字段 | 内容 |
|------|------|
| **ID** | TC-SYNC-010 |
| **对应 Spec** | upstream-sync-merge/spec.md → Scenario: SC-010 |
| **优先级** | P1 |
| **预置条件** | 全量 `bun run test` 出现 shard 统计异常或挂死 |
| **输入** | 定向 `bun test <paths>` 重跑同批文件 |
| **预期结果** | 定向批给出明确通过/失败；异常记录为环境基线 |
| **当前状态** | ✅ 已覆盖（流程约定） |

### 功能 5：台账一致性（REQ-005）

#### 案例 5.1 — 阶段记录追加

| 字段 | 内容 |
|------|------|
| **ID** | TC-SYNC-011 |
| **对应 Spec** | upstream-sync-merge/spec.md → Scenario: SC-011 |
| **优先级** | P1 |
| **预置条件** | 合并与验证完成 |
| **输入** | `git diff 709c16b4a9 -- CUSTOM.md` 检查历史行是否被改 |
| **预期结果** | 新增本轮记录；历史《阶段记录》行零改动 |
| **当前状态** | ❌ 待 Phase 3 执行 |

#### 案例 5.2 — 台账逐行可核

| 字段 | 内容 |
|------|------|
| **ID** | TC-SYNC-012 |
| **对应 Spec** | upstream-sync-merge/spec.md → Scenario: SC-012 |
| **优先级** | P1 |
| **预置条件** | 合并完成 |
| **输入** | 按台账明细表逐行 grep 文件与符号 |
| **预期结果** | 全部命中；未命中项进《已上游化》或删除 |
| **当前状态** | ❌ 待 Phase 3 执行 |

## 三、测试执行矩阵

| 功能模块 | 单元测试 | 集成测试 | E2E | 状态 |
|----------|---------|----------|-----|------|
| Inbox / 真理沉淀 | `inbox-workflow`、`conflicts`、`compile-truth` | `ingest-capture` | 无 | 🟡 待合并后执行 |
| Graph / 遍历 | `graph-overview`、`traverse-paths-*` | 引擎 PGLite/Postgres | 无 | 🟡 待合并后执行 |
| 契约面 | `operation-manifest`、`parity`、`mcp-tool-defs` | — | 无 | 🟡 待合并后执行 |
| 迁移 | — | 排序探针 + 产物探针 | 空库迁移 | 🟡 产物探针缺 |
| 生成物 | freshness 门 ×6 | — | 无 | 🟡 待合并后执行 |
| Admin SPA | vitest 227 | 构建+类型镜像对照 | 无 | 🟡 待合并后执行 |

## 四、回归风险矩阵

| 风险区域 | v0.60.461.0 改动 | 已有回归保护 | 风险等级 |
|----------|------------------|-------------|---------|
| 引擎 SQL 共享模块 | 上游 `engine-sql/links.ts` +261/−213 | SQL 金标准 + `traverse-paths-*` | 🔴 |
| 迁移体系 | 上游新增 36 个迁移，与 fork 同号 | 排序探针 + 产物探针（后者待补） | 🔴 |
| serve-http 挂钩 | 上游继续拆 mount 模块 | `serve-http-admin-route-guard` | 🟡 |
| op 契约三件套 | 上游 op 表扩面 | `operation-manifest` / `parity` | 🟡 |
| 生成物 | 生成面持续扩大 | `check:regen-all` + 6 个专项门 | 🟡 |
| Admin SPA | 上游 `admin/package.json` 变更 | admin vitest + 构建 | 🟢 |

## 五、建议补充顺序

1. **第一优先**（Gate 3 前必补）：案例 2.2 的产物探针（information_schema），缺它等于回到「只看迁移日志」。
2. **第二优先**（Gate 3 中执行）：案例 5.1 / 5.2 的台账一致性检查。
3. **第三优先**（合并后补）：把案例 2.1 / 2.2 固化成脚本，接入 `check:schema-migration-order` 旁边，避免每轮手工。

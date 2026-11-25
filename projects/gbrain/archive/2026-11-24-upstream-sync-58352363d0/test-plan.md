# v0.60.638.0 上游同步测试方案与详细案例

> 版本：v0.60.638.0（UPSTREAM=17b68cef4f4267ca0e5710b42f6ddc95acf9fe51）
> 创建日期：2026-11-24
> 对应 Phase 2 Spec：`canonical/specs/code/upstream-sync-merge.yaml`、`canonical/specs/code/fork-custom-behavior.yaml`
> 接口锚定：`anchors/L2-interfaces/2026-11-24-upstream-sync-58352363d0/api-contract.yaml`

## 一、测试策略

### 1.1 测试金字塔

- 底层：Git 冻结事实、迁移 registry、生成物 freshness、类型检查与现有单元测试。
- 中层：Inbox、Admin、query.trace、Graph 及 persistence/cycle/repair 的定向行为测试。
- 高层：PGLite source-isolation 与 Postgres engine-parity；Graph 的 Postgres 实际执行是 Gate 3 必需条件，Docker 不可用或数据库未启动时本项不通过，不得以 PGLite 冒充双引擎结果。
- 全量根单测使用仓库既有 runner；Windows 上若出现已登记挂死/统计故障，保留完整输出并用定向批次补信号，超时不记通过。

### 1.2 测试原则

- 所有命令在独立同步 worktree 执行，Bun 固定为 1.4.4；依赖用 `--frozen-lockfile --ignore-scripts` 安装。
- 断言必须包含可区分对错的状态、计数或字段值，不得只匹配 PASS 标签。
- 生成物先由真源重建并整组暂存，再运行 freshness；相同输入第二次生成后，暂存区不得漂移。
- 失败项在固定 FORK 上用相同工具链、相同依赖和相同命令做 A/B；同项同因才能归入既有基线。
- 未运行、跳过、超时、失败或未归因均不得记为通过；Postgres、旧库结构探针等未执行项必须在报告单列。
- 人工检查依据候选树、Git 对象和实际输出确认，不用口头描述替代证据。

### 1.3 已有测试资产

| 测试文件/命令 | 类型 | 覆盖范围 |
|---|---|---|
| `test/sync-restored-file-purge.test.ts`、`test/purge-eval-fixes.test.ts` | 单元/集成 | 恢复文件、保留已提交文件、purge 时序与脱敏 |
| `test/cycle-world-fence-rows.test.ts`、`test/extract-atoms-world-fence-rows.test.ts`、`test/repair-atom-fence-rows.test.ts` | 单元/集成 | world-row 读取、owner-only fence 与 atom repair |
| `test/repair-explicit-only.test.ts`、`test/fix-wave-5-integration.test.ts`、`test/sync-classify-6712.test.ts` | 单元/集成 | 显式 repair、修复波集成与 sync 分类 |
| `test/ingestion/ingest-capture.test.ts`、`test/inbox-workflow.test.ts` | 单元/集成 | Inbox 预处理、实际落库、provenance 与 auto-link |
| `test/serve-http-admin-route-guard.test.ts`、`test/admin-embed-spawn.test.ts` | 集成 | Admin 鉴权顺序、分派与登录落地 |
| `test/query-trace.test.ts`（新增）、`test/search-remote-page-cap.test.ts`、`test/dispatch-response-meta.serial.test.ts`、`test/cli-goldens.test.ts`、`test/cli-dispatch-phase.test.ts` | 合同/CLI | query.trace 开/关/空结果、完整 retrieval meta、page cap 与 MCP/CLI 信封 |
| `admin/src/lib/mcp-client.test.ts`、`admin/src/pages/brain/__tests__/Ask.page.test.tsx`（增补） | Admin 单元/页面 | ToolResult `_meta` 保留与 Ask trace 合并 |
| `test/traverse-paths-metadata.test.ts`、`test/traverse-paths-row-cap.test.ts`、`test/graph-overview.test.ts` | 单元/集成 | Graph 元数据、层 cap、无根概览；增补 private/origin/degree/source 与 op remote 断言 |
| `test/e2e/engine-content-privacy.test.ts`、`test/e2e/source-isolation-pglite.test.ts`、`test/e2e/engine-parity.test.ts` | E2E | Graph 双引擎可见性、both 元数据、frontierCap 与 source/private/软删除约束 |
| `bun run check:regen-all`、`bun run check:admin-embedded` | 静态/生成物 | 真源产物新鲜度与暂存区一致性；拒绝缺 dist 导致的 skip |
| `bun run check:module-size`、`bun run check:page-body-readers`、`bun run check:schema-migration-order` | 静态门禁 | fork 例外、页面正文读法、v297→v298 迁移顺序；拒绝 base-ref skip |
| `bun run typecheck`、`bun run test`、`cd admin && bun run test` | 全量回归 | 根类型/单测与 Admin 前端回归 |

## 二、详细测试案例

### 功能 1：冻结输入与三方合并审计

对应 `REQ-USM-001`～`REQ-USM-003`。

#### 案例 1.1 — 冻结 Git 输入可复核

| 字段 | 内容 |
|---|---|
| **ID** | TC-USM-001 |
| **对应 Spec** | upstream-sync-merge → SC-USM-001 |
| **优先级** | P0 |
| **预置条件** | FORK、UPSTREAM、BASE 和回滚锚点已登记；主工作区保持 FORK。 |
| **输入** | 核对 merge-base、左右提交计数、UPSTREAM:VERSION、锚点解析值和主工作区状态。 |
| **预期结果** | BASE=553b547334；计数为 59/13；VERSION=0.60.638.0；锚点指向 FORK；主工作区未被合并改变，本地状态未暂存。 |
| **当前状态** | 已规划，BUILD 待执行 CP-USM-001。 |

#### 案例 1.2 — fork 增量逐路径归因

| 字段 | 内容 |
|---|---|
| **ID** | TC-USM-002 |
| **对应 Spec** | upstream-sync-merge → SC-USM-002 |
| **优先级** | P0 |
| **预置条件** | 台账 #1–#32、生成物登记和 516 个 fork 改动路径清单可用。 |
| **输入** | 人工逐路径核对候选仍保留的 fork 改动、上游单侧路径和已上游化项。 |
| **预期结果** | 每个仍保留改动对应台账编号或生成物真源；无法归因项为零；已上游化行为无双实现；上游新行为保留。 |
| **当前状态** | 人工项，Gate 3 前确认。 |

#### 案例 1.3 — 六个双边文件按语义裁决

| 字段 | 内容 |
|---|---|
| **ID** | TC-USM-003 |
| **对应 Spec** | upstream-sync-merge → SC-USM-003 |
| **优先级** | P0 |
| **预置条件** | merge-tree 预测两个文本冲突；六个双边路径已逐项列出。 |
| **输入** | 审计 TSV、RESOLVER、skills.lock、plugin README 与 llms-full 的候选内容和生成关系。 |
| **预期结果** | 双边路径=6；module-size fork 行=11；page-body fork 行=11；atom-fence 行=2；技能路由不重复；生成物来自真源；新增 atom-fence 行无尾随空白。 |
| **当前状态** | 已规划，BUILD 待执行 CP-USM-002。 |

### 功能 2：无冲突上游行为与迁移

对应 `REQ-USM-004`～`REQ-USM-006`。

#### 案例 2.1 — persistence/cycle/repair 行为兼容

| 字段 | 内容 |
|---|---|
| **ID** | TC-USM-004 |
| **对应 Spec** | upstream-sync-merge → SC-USM-004 |
| **优先级** | P0 |
| **预置条件** | 上游 17 个源文件、344 insertions/45 deletions 已合入候选。 |
| **输入** | 运行恢复文件、purge、world-row atom、显式 repair、集成与 sync-classify 定向测试。 |
| **预期结果** | 命令退出 0 且 0 fail；测试实际断言文件/页面状态、可见性或脱敏字段，不破坏 fork provenance、权限与写入顺序。 |
| **当前状态** | 已规划，BUILD 待执行 CP-USM-003。 |

#### 案例 2.2 — 迁移顺序与 registry

| 字段 | 内容 |
|---|---|
| **ID** | TC-USM-005 |
| **对应 Spec** | upstream-sync-merge → SC-USM-005 |
| **优先级** | P0 |
| **预置条件** | 上游 latest=297，fork Inbox migration=298，窗口无新增迁移。 |
| **输入** | 重生成 registry/latest，运行迁移顺序与 registry 测试，以冻结 UPSTREAM 为 base ref。 |
| **预期结果** | latest=297、fork=298；v298 唯一且文件名/导出名/version 一致；不得引入 v299–v331；migration-order 使用冻结 UPSTREAM 且 skipped=False、baseMax=297；未做旧库探针时明确 database_upgrade_verified=False。 |
| **当前状态** | 已规划，BUILD 待执行 CP-USM-004。 |

#### 案例 2.3 — 生成物稳定且无漂移

| 字段 | 内容 |
|---|---|
| **ID** | TC-USM-006 |
| **对应 Spec** | upstream-sync-merge → SC-USM-006 |
| **优先级** | P0 |
| **预置条件** | 真源和手工基线已裁决，生成物已整组定向暂存。 |
| **输入** | 运行 regen:all、必要的 goldens、build:admin/build:llms、freshness 检查和第二次同输入生成。 |
| **预期结果** | admin_dist_present=True；check:regen-all 与 check:admin-embedded 退出 0 且无 skip；generated_stable=True；第二次生成不改变候选暂存区；不手拼 lock/registry/嵌入清单/金标准。 |
| **当前状态** | 已规划，BUILD 待执行 CP-USM-005。 |

### 功能 3：候选质量与交付边界

对应 `REQ-USM-007`～`REQ-USM-009`。

#### 案例 3.1 — 高风险 fork 行为综合复核

| 字段 | 内容 |
|---|---|
| **ID** | TC-USM-007 |
| **对应 Spec** | upstream-sync-merge → SC-USM-007 |
| **优先级** | P0 |
| **预置条件** | TC-FCB-001～004 已取得独立候选信号。 |
| **输入** | 人工将 Inbox、Admin、trace、Graph 的实测输出逐项对照 L2 锚点和台账 #4/#9/#10/#11/#12。 |
| **预期结果** | Inbox 写处理后的 frontmatter/content/provenance；Admin 先鉴权后分派且只审计一次；trace 保留上游诊断；Graph 双引擎不漏列、不越权。 |
| **当前状态** | 人工项，Gate 3 前确认。 |

#### 案例 3.2 — 候选类型、单测、Admin 与 A/B 归因

| 字段 | 内容 |
|---|---|
| **ID** | TC-USM-008 |
| **对应 Spec** | upstream-sync-merge → SC-USM-008 |
| **优先级** | P0 |
| **预置条件** | 候选生成物稳定；FORK 基线 worktree 使用相同 Bun 与依赖。 |
| **输入** | 运行候选 typecheck、根单测、Admin 测试和所需定向/E2E；失败时运行相同 FORK 检查。 |
| **预期结果** | typecheck_rc=0、unit_rc=0；每条命令保存 run/rc/耗时/完整输出；新增回归为零；未跑/跳过/超时单列；同项同因基线失败不得冒充候选通过。 |
| **当前状态** | 不适用：Windows 全量 runner 基线未完成；以合并面定向批次、Admin 套件和 Slice 2-5 证据替代，Linux 全量另计。 |

#### 案例 3.3 — 最终 Git 与交付审计

| 字段 | 内容 |
|---|---|
| **ID** | TC-USM-009 |
| **对应 Spec** | upstream-sync-merge → SC-USM-009 |
| **优先级** | P0 |
| **预置条件** | 候选源码、测试、生成物和台账已完成并暂存。 |
| **输入** | 执行 ls-files -u、cached diff --check、双父 diff、分支状态和台账回填审计。 |
| **预期结果** | final_audit_ok=True；无未解决冲突；new_whitespace_warnings=0；新增/删除/改名/上游吸收均有解释；Gate 3 前未合 master、未推送、未部署、未做生产迁移。 |
| **当前状态** | 已规划，BUILD 待执行 CP-USM-007。 |

### 功能 4：fork 定制行为回归

对应 `REQ-FCB-001`～`REQ-FCB-005`。

#### 案例 4.1 — Inbox 实际写入处理后的内容

| 字段 | 内容 |
|---|---|
| **ID** | TC-FCB-001 |
| **对应 Spec** | fork-custom-behavior → SC-FCB-001 |
| **优先级** | P0 |
| **预置条件** | Inbox 捕获事件具备 source_kind、received_at 和可选 metadata。 |
| **输入** | 运行 ingest-capture 与 inbox-workflow 测试，覆盖 unmanaged 与 managed 写入分支。 |
| **预期结果** | 0 fail；落库 frontmatter 含 inbox_status/raw_content/source_kind/captured_at；provenance 正确；managed put_page 消费处理后的 content；auto-link 不越权。 |
| **当前状态** | 已规划，BUILD 待执行 CP-FCB-001。 |

#### 案例 4.2 — Admin 先鉴权后分派

| 字段 | 内容 |
|---|---|
| **ID** | TC-FCB-002 |
| **对应 Spec** | fork-custom-behavior → SC-FCB-002 |
| **优先级** | P0 |
| **预置条件** | Admin 会话、source header 和 op 请求 fixture 可用。 |
| **输入** | 运行 route guard 与 embed-spawn 测试，覆盖无会话、合法会话、未知 op 和登录落地。 |
| **预期结果** | 0 fail；无会话不分派；合法请求返回 JSON-RPC ToolResult；remote=true；每个已分派请求恰好一条 admin-ui 审计/SSE。 |
| **当前状态** | 已规划，BUILD 待执行 CP-FCB-002。 |

#### 案例 4.3 — query.trace 信封与诊断

| 字段 | 内容 |
|---|---|
| **ID** | TC-FCB-003 |
| **对应 Spec** | fork-custom-behavior → SC-FCB-003 |
| **优先级** | P0 |
| **预置条件** | query 操作、MCP dispatch、CLI 与 Admin client 消费路径可用；固定 FORK 的 trace 摘要缺口已通过 A/B 确认。 |
| **输入** | 增补并运行真实 op trace 测试、remote page cap 的 trace 分支、dispatch/meta 合同、Admin client 与 Ask 页面测试，核对 trace 开、关和空结果。 |
| **预期结果** | trace=true 返回 results+trace；trace.retrieval 与 op emit 的完整对象一致且含 evidence/page cap/degraded/explain-target；MCP _meta.retrieval 独立保留；CLI JSON 保留 trace.retrieval；Admin client 不丢弃 _meta，Ask 合并入 trace；trace 关闭保持原数组形状；必需用例 skip=0。 |
| **当前状态** | 已规划，BUILD 待执行 CP-FCB-003。 |

#### 案例 4.4 — Graph 双引擎元数据与可见性

| 字段 | 内容 |
|---|---|
| **ID** | TC-FCB-004 |
| **对应 Spec** | fork-custom-behavior → SC-FCB-004 |
| **优先级** | P0 |
| **预置条件** | PGLite 与隔离 Postgres 测试数据库可用；Docker 不可用时本项不通过。 |
| **输入** | 增补 graphOverview 的 private/private-origin/deleted/source/degree 测试和 graph_overview remote fail-closed 测试；运行 Graph 定向、PGLite source-isolation、engine-content-privacy 与实际 Postgres engine-parity。 |
| **预期结果** | pglite_rc=0、postgres_rc=0、postgres_executed=True、两者 skip=0；both 方向含 to_title/to_type；frontierCap/行上限生效；source/private/软删除过滤一致；graphOverview 的 degree、节点与边均不受不可见端点或 private origin 污染；无根总览可用。 |
| **当前状态** | 不适用：Graph 缺口位于本次未改动的 FORK 文件，属既有问题，按用户指令移出本次合并范围。 |

#### 案例 4.5 — 其余已登记 fork 能力

| 字段 | 内容 |
|---|---|
| **ID** | TC-FCB-005 |
| **对应 Spec** | fork-custom-behavior → SC-FCB-005 |
| **优先级** | P1 |
| **预置条件** | AI、Truth、Jobs、op 合同、技能路由与 Admin 依赖已安装。 |
| **输入** | 运行台账列出的 AI/Truth/op/manifest/parity/skills/doctor/llms 测试，再运行 Admin 全套测试。 |
| **预期结果** | 退出 0 且 0 fail；已上游化项无重复实现；keyless compile_truth 等跳过不得冒充真实模型调用通过；Admin 页面与数据路径无回归。 |
| **当前状态** | 已规划，BUILD 待执行 CP-FCB-005。 |

## 三、测试执行矩阵

| 功能模块 | 单元测试 | 集成测试 | E2E | 状态 |
|---|---|---|---|---|
| Git 冻结与归因 | CP-USM-001 | 人工 TC-USM-002 | 不适用 | 待执行 |
| 双边冲突与生成物 | CP-USM-002/005 | regen/freshness | 不适用 | 待执行 |
| persistence/cycle/repair | CP-USM-003 | 定向行为测试 | 必要时扩展 | 待执行 |
| 迁移 | CP-USM-004 | registry/顺序 | 旧库探针未授权则不跑 | 待执行 |
| Inbox | CP-FCB-001 | 实际落库 | PGLite 覆盖 | 待执行 |
| Admin | CP-FCB-002/005 | 路由与审计 | Admin 浏览器路径按需 | 待执行 |
| query.trace | CP-FCB-003 | CLI/Admin 信封 | 不适用 | 待执行 |
| Graph | 不适用（移出范围） | 两引擎定向 | PGLite + Postgres 必需 | 不适用 |
| 全量质量 | 不适用（Windows 基线） | 根单测 + Admin | 所需 E2E | 不适用 |
| 最终审计 | CP-USM-007 | 人工 TC-USM-007 | 不适用 | 待执行 |

## 四、回归风险矩阵

| 风险区域 | 本轮改动 | 已有回归保护 | 风险等级 |
|---|---|---|---|
| Inbox managed 写入 | 上游持久化链变化叠加 fork 预处理 | CP-FCB-001 + L2 content 不变量 | 高 |
| Admin 鉴权/审计 | serve-http 挂钩与 op 代理 | CP-FCB-002 | 高 |
| query.trace | 上游 evidence 元数据与 fork 信封 | CP-FCB-003 | 高 |
| Graph | 既有可见性缺口；本次未改 Graph 文件 | 不在本次范围；另立变更 | 高（既有） |
| persistence/cycle/repair | 17 文件无声行为变化 | CP-USM-003 | 高 |
| 迁移 registry | v297/v298 顺序 | CP-USM-004 | 高 |
| 生成物/锁文件 | 双亲生成面变化 | CP-USM-002/005 | 高 |
| Windows  runner/guard | 已知路径假阳性、超时、挂死 | 合并面定向批次 + 已登记 Windows 基线 | 中 |
| 文档 whitespace | FORK 存量 397 条告警 | CP-USM-007 新增告警为零 | 中 |

## 五、建议补充顺序

1. **P0**：TC-USM-001～009、TC-FCB-001～004；任一必需信号缺失则不进入 Gate 3 放行。
2. **P1**：TC-FCB-005 及其余台账定向回归；与 P0 同次候选树执行，失败按 A/B 归因。
3. **P2**：仅在失败归因或依赖变化时扩大 E2E；不把未执行项写成通过。

### 5.1 验证 helper 的防假通过合同

- 每个子命令把逐条命令的 argv、cwd、start/end、耗时、rc、完整 stdout/stderr、timeout、pass/fail/skip 计数写入本轮日志；stdout 只输出汇总断言。
- Bun 定向测试生成 JUnit，helper 按下列**必需用例名**核对实际通过、失败与跳过；文件存在但用例缺失、零匹配、超时或 skip 均返回非零。
- Admin 测试使用 Vitest 机器可读结果核对必需用例；不得把 mock 页面测试当作后端合同证据。
- `check:admin-embedded` 运行前必须存在根 `build:admin` 生成的 `admin/dist`；输出含 `skipping` 或 `GBRAIN_CHECK_SKIPPED` 即失败。
- `check:schema-migration-order` 必须通过子进程环境设置 `GBRAIN_MIGRATION_BASE_REF=17b68cef4f4267ca0e5710b42f6ddc95acf9fe51`；skip、baseMax≠297 或新增 migration≠0 即失败。
- Graph helper 必须确认 `DATABASE_URL` 已提供且 Postgres 套件实际执行；`postgres_rc=0` 但 `postgres_executed=False` 或 `postgres_skips>0` 即失败。

| 组 | 必需用例或观测值 |
|---|---|
| Inbox | `managed capture persists prepared content and provenance`；`unmanaged capture persists prepared content and provenance`；`managed auto-link uses the committed snapshot and permission guard` |
| Admin | `unauthenticated op request is rejected before dispatch`；`authenticated op request dispatches with remote context`；`admin op emits exactly one independent audit event` |
| trace 根测试 | `trace on preserves the complete emitted retrieval metadata`；`trace off preserves the upstream result array`；`empty trace result preserves envelope and diagnostics`；`remote page cap remains available in trace retrieval metadata`；`MCP query trace preserves response metadata`；`CLI JSON preserves trace retrieval metadata` |
| trace Admin | `MCP client preserves ToolResult response metadata`；`Ask merges retrieval metadata into the visible trace` |
| Graph | `graphOverview excludes private nodes origins and degree contributions`；`graphOverview applies source scope to degree nodes and edges`；`remote graphOverview excludes private pages while local retains them`；`graphOverview privacy parity excludes hidden endpoints and origins`；`both direction retains target metadata and frontier cap parity` |
| persistence/cycle/repair | 八个定向文件均实际执行且每组 pass>0、fail=0、skip=0、timeout=False |
| 其余能力 | AI/Truth/Jobs/op/manifest/parity/skills/doctor/llms 与 Admin 必需用例实际通过；Jobs 套件 pass>0；重复 operation 注册=0 |
| 全量质量 | typecheck/root unit/Admin 的 rc、耗时、完整输出和 skip 分类入账；超时非零；固定 FORK 同项同因失败单列，不冒充候选通过 |

## 六、同次执行证据计划 / Same-Run Evidence Plan

本节随 Gate 2 锁定。每个 TC 有且仅有一条 check；required command 绑定且独占一个 CP，manual 不绑定 CP。覆盖率声明为 not_applicable：本仓是 Bun/TypeScript，不使用 pytest-cov；行为正确性由具体断言、静态门和 E2E 结果保证。

```stdd-evidence-plan-v1
{
  "task": "upstream-sync-verification",
  "inputs": [
    {"root": "project", "path": ".claude-plugin/plugin.json"},
    {"root": "project", "path": ".codex-plugin/plugin.json"},
    {"root": "project", "path": "BOOTSTRAP_FOR_AGENTS.md"},
    {"root": "project", "path": "CHANGELOG.md"},
    {"root": "project", "path": "CUSTOM-LEDGER.md"},
    {"root": "project", "path": "CUSTOM.md"},
    {"root": "project", "path": "VERSION"},
    {"root": "project", "path": "admin/bun.lock"},
    {"root": "project", "path": "admin/index.html"},
    {"root": "project", "path": "admin/package.json"},
    {"root": "project", "path": "admin/src/lib/mcp-client.test.ts"},
    {"root": "project", "path": "admin/src/lib/mcp-client.ts"},
    {"root": "project", "path": "admin/src/lib/op-types.ts"},
    {"root": "project", "path": "admin/src/pages/brain/Ask.tsx"},
    {"root": "project", "path": "admin/src/pages/brain/__tests__/Ask.page.test.tsx"},
    {"root": "project", "path": "admin/src/test/setup.ts"},
    {"root": "project", "path": "admin/vite.config.ts"},
    {"root": "project", "path": "bun.lock"},
    {"root": "project", "path": "docker-compose.test.yml"},
    {"root": "project", "path": "docs/architecture/key-files/canonical-reconciliation-continued.md"},
    {"root": "project", "path": "docs/architecture/key-files/core-cycle-patterns.md"},
    {"root": "project", "path": "docs/architecture/key-files/core-cycle.md"},
    {"root": "project", "path": "docs/architecture/key-files/hindsight.md"},
    {"root": "project", "path": "docs/architecture/key-files/memory-purge.md"},
    {"root": "project", "path": "docs/guides/repair.md"},
    {"root": "project", "path": "docs/guides/sync-unblock-runbook.md"},
    {"root": "project", "path": "llms-full.txt"},
    {"root": "project", "path": "openclaw.plugin.json"},
    {"root": "project", "path": "package.json"},
    {"root": "project", "path": "plugin-variants/gbrain-coding/.claude-plugin/plugin.json"},
    {"root": "project", "path": "plugin-variants/gbrain-coding/.codex-plugin/plugin.json"},
    {"root": "project", "path": "plugin-variants/gbrain-coding/README.md"},
    {"root": "project", "path": "plugin-variants/gbrain-coding/skills/data-loss-gate/SKILL.md"},
    {"root": "project", "path": "plugin-variants/gbrain-daily/.claude-plugin/plugin.json"},
    {"root": "project", "path": "plugin-variants/gbrain-daily/.codex-plugin/plugin.json"},
    {"root": "project", "path": "plugin-variants/gbrain-daily/README.md"},
    {"root": "project", "path": "plugin/README.md"},
    {"root": "project", "path": "plugin/skills/data-loss-gate/SKILL.md"},
    {"root": "project", "path": "scripts/build-admin-embedded.ts"},
    {"root": "project", "path": "scripts/check-admin-embedded.sh"},
    {"root": "project", "path": "scripts/check-module-size.sh"},
    {"root": "project", "path": "scripts/check-page-body-readers.ts"},
    {"root": "project", "path": "scripts/check-schema-migration-order.ts"},
    {"root": "project", "path": "scripts/llms-config.ts"},
    {"root": "project", "path": "scripts/module-size-limits.tsv"},
    {"root": "project", "path": "scripts/page-body-readers-baseline.tsv"},
    {"root": "project", "path": "scripts/regen-all.ts"},
    {"root": "project", "path": "scripts/run-unit-parallel.sh"},
    {"root": "project", "path": "skills/RESOLVER.md"},
    {"root": "project", "path": "skills/data-loss-gate/SKILL.md"},
    {"root": "project", "path": "skills/skills.lock.json"},
    {"root": "project", "path": "src/cli/main.ts"},
    {"root": "project", "path": "src/commands/doctor/checks/atom-fence-rows.ts"},
    {"root": "project", "path": "src/commands/doctor/checks/graph-health.ts"},
    {"root": "project", "path": "src/commands/doctor/wave-checks.ts"},
    {"root": "project", "path": "src/commands/serve-http-admin-api.ts"},
    {"root": "project", "path": "src/commands/serve-http-admin-op.ts"},
    {"root": "project", "path": "src/commands/serve-http-oauth.ts"},
    {"root": "project", "path": "src/commands/serve-http-spa.ts"},
    {"root": "project", "path": "src/commands/serve-http.ts"},
    {"root": "project", "path": "src/core/behavior-change-notice.ts"},
    {"root": "project", "path": "src/core/cycle/extract-atoms-input.ts"},
    {"root": "project", "path": "src/core/cycle/extract-atoms.ts"},
    {"root": "project", "path": "src/core/cycle/patterns.ts"},
    {"root": "project", "path": "src/core/cycle/propose-takes.ts"},
    {"root": "project", "path": "src/core/doctor-categories.ts"},
    {"root": "project", "path": "src/core/engine-sql/links.ts"},
    {"root": "project", "path": "src/core/engine.ts"},
    {"root": "project", "path": "src/core/import-file.ts"},
    {"root": "project", "path": "src/core/inbox.ts"},
    {"root": "project", "path": "src/core/minions/handlers/ingest-capture.ts"},
    {"root": "project", "path": "src/core/operation-load.ts"},
    {"root": "project", "path": "src/core/operations.ts"},
    {"root": "project", "path": "src/core/ops/context.ts"},
    {"root": "project", "path": "src/core/ops/links.ts"},
    {"root": "project", "path": "src/core/ops/search.ts"},
    {"root": "project", "path": "src/core/search/private-visibility.ts"},
    {"root": "project", "path": "src/core/persistence/coordinator.ts"},
    {"root": "project", "path": "src/core/persistence/intent-redaction.ts"},
    {"root": "project", "path": "src/core/persistence/page-prepare.ts"},
    {"root": "project", "path": "src/core/persistence/page-purge.ts"},
    {"root": "project", "path": "src/core/persistence/preview-approval.ts"},
    {"root": "project", "path": "src/core/persistence/sync-classify.ts"},
    {"root": "project", "path": "src/core/persistence/sync-markers.ts"},
    {"root": "project", "path": "src/core/persistence/sync-pass-run.ts"},
    {"root": "project", "path": "src/core/persistence/sync-pass.ts"},
    {"root": "project", "path": "src/core/pglite-engine.ts"},
    {"root": "project", "path": "src/core/postgres-engine.ts"},
    {"root": "project", "path": "src/core/repair/atom-fence-rows.ts"},
    {"root": "project", "path": "src/core/repair/core.ts"},
    {"root": "project", "path": "src/core/repair/registry.ts"},
    {"root": "project", "path": "src/core/schema-migrations/v298-inbox-workflow-frontmatter.ts"},
    {"root": "project", "path": "src/core/types.ts"},
    {"root": "project", "path": "src/mcp/dispatch.ts"},
    {"root": "project", "path": "templates/bootstrap/template-repo/README.md"},
    {"root": "project", "path": "test/admin-embed-spawn.test.ts"},
    {"root": "project", "path": "test/ai/build-gateway-config.test.ts"},
    {"root": "project", "path": "test/ai/gateway-chat.test.ts"},
    {"root": "project", "path": "test/ai/gateway.test.ts"},
    {"root": "project", "path": "test/build-llms.test.ts"},
    {"root": "project", "path": "test/cli-dispatch-phase.test.ts"},
    {"root": "project", "path": "test/cli-goldens.test.ts"},
    {"root": "project", "path": "test/compile-truth.test.ts"},
    {"root": "project", "path": "test/dispatch-response-meta.serial.test.ts"},
    {"root": "project", "path": "test/conflicts.test.ts"},
    {"root": "project", "path": "test/cycle-world-fence-rows.test.ts"},
    {"root": "project", "path": "test/doctor-categories.test.ts"},
    {"root": "project", "path": "test/e2e/engine-content-privacy.test.ts"},
    {"root": "project", "path": "test/e2e/engine-parity.test.ts"},
    {"root": "project", "path": "test/e2e/managed-sync-shared-origin-6517.test.ts"},
    {"root": "project", "path": "test/e2e/source-isolation-pglite.test.ts"},
    {"root": "project", "path": "test/embedding-dim-check.test.ts"},
    {"root": "project", "path": "test/engine-sql-sql-text.test.ts"},
    {"root": "project", "path": "test/engine-surface-coverage.test.ts"},
    {"root": "project", "path": "test/extract-atoms-world-fence-rows.test.ts"},
    {"root": "project", "path": "test/fix-wave-5-integration.test.ts"},
    {"root": "project", "path": "test/fixtures/fold-hook-noop-6712.json"},
    {"root": "project", "path": "test/fixtures/goldens/doctor/content-pglite-human.json"},
    {"root": "project", "path": "test/fixtures/goldens/doctor/content-pglite-json.json"},
    {"root": "project", "path": "test/fixtures/goldens/doctor/hot-checks-pglite-json.json"},
    {"root": "project", "path": "test/fixtures/goldens/doctor/hot-checks-postgres-json.json"},
    {"root": "project", "path": "test/fixtures/goldens/doctor/json-pglite-degraded.json"},
    {"root": "project", "path": "test/fixtures/goldens/doctor/json-pglite-fresh.json"},
    {"root": "project", "path": "test/fixtures/goldens/doctor/json-postgres-fresh.json"},
    {"root": "project", "path": "test/fixtures/goldens/doctor/registry-build-checks.json"},
    {"root": "project", "path": "test/graph-overview.test.ts"},
    {"root": "project", "path": "test/helpers/postgres-engine-sql-cases.ts"},
    {"root": "project", "path": "test/helpers/world-fence-page.ts"},
    {"root": "project", "path": "test/inbox-workflow.test.ts"},
    {"root": "project", "path": "test/ingestion/ingest-capture.test.ts"},
    {"root": "project", "path": "test/init-env-detection.test.ts"},
    {"root": "project", "path": "test/mcp-tool-defs.test.ts"},
    {"root": "project", "path": "test/minions.test.ts"},
    {"root": "project", "path": "test/model-pricing.test.ts"},
    {"root": "project", "path": "test/operation-manifest.test.ts"},
    {"root": "project", "path": "test/parity.test.ts"},
    {"root": "project", "path": "test/postgres-unit-arms.txt"},
    {"root": "project", "path": "test/purge-eval-fixes.test.ts"},
    {"root": "project", "path": "test/query-trace.test.ts"},
    {"root": "project", "path": "test/repair-atom-fence-rows.test.ts"},
    {"root": "project", "path": "test/repair-explicit-only.test.ts"},
    {"root": "project", "path": "test/schema-migration-registry.test.ts"},
    {"root": "project", "path": "test/search-remote-page-cap.test.ts"},
    {"root": "project", "path": "test/serve-http-admin-route-guard.test.ts"},
    {"root": "project", "path": "test/skill-brain-first.test.ts"},
    {"root": "project", "path": "test/sync-classify-6712.test.ts"},
    {"root": "project", "path": "test/sync-restored-file-purge.test.ts"},
    {"root": "project", "path": "test/takes-reservation-callers.test.ts"},
    {"root": "project", "path": "test/traverse-paths-metadata.test.ts"},
    {"root": "project", "path": "test/traverse-paths-row-cap.test.ts"}
  ],
  "coverage": {"applicability": "not_applicable", "reason": "Bun/TypeScript 项目，不使用 pytest-cov；以具体行为断言、静态门和 E2E 结果作为质量保证。"},
  "checks": [
    {"tc": "TC-USM-001", "case_id": "freeze-inputs", "requirement": "REQ-USM-001", "scenarios": ["SC-USM-001"], "cp": "CP-USM-001", "kind": "command", "applicability": "required"},
    {"tc": "TC-USM-002", "case_id": "fork-attribution", "requirement": "REQ-USM-002", "scenarios": ["SC-USM-002"], "kind": "manual", "applicability": "required"},
    {"tc": "TC-USM-003", "case_id": "bilateral-resolution", "requirement": "REQ-USM-003", "scenarios": ["SC-USM-003"], "cp": "CP-USM-002", "kind": "command", "applicability": "required"},
    {"tc": "TC-USM-004", "case_id": "upstream-behavior", "requirement": "REQ-USM-004", "scenarios": ["SC-USM-004"], "cp": "CP-USM-003", "kind": "command", "applicability": "required"},
    {"tc": "TC-USM-005", "case_id": "migration-order", "requirement": "REQ-USM-005", "scenarios": ["SC-USM-005"], "cp": "CP-USM-004", "kind": "command", "applicability": "required"},
    {"tc": "TC-USM-006", "case_id": "generated-stability", "requirement": "REQ-USM-006", "scenarios": ["SC-USM-006"], "cp": "CP-USM-005", "kind": "command", "applicability": "required"},
    {"tc": "TC-USM-007", "case_id": "fork-behavior-review", "requirement": "REQ-USM-007", "scenarios": ["SC-USM-007"], "kind": "manual", "applicability": "required"},
    {"tc": "TC-USM-008", "case_id": "candidate-quality", "requirement": "REQ-USM-008", "scenarios": ["SC-USM-008"], "kind": "command", "applicability": "not_applicable", "reason": "Windows 全量 runner 基线未完成；以合并面定向批次、Admin 套件和 Slice 2-5 证据替代，Linux 全量另计。"},
    {"tc": "TC-USM-009", "case_id": "final-audit", "requirement": "REQ-USM-009", "scenarios": ["SC-USM-009"], "cp": "CP-USM-007", "kind": "command", "applicability": "required"},
    {"tc": "TC-FCB-001", "case_id": "inbox-write", "requirement": "REQ-FCB-001", "scenarios": ["SC-FCB-001"], "cp": "CP-FCB-001", "kind": "command", "applicability": "required"},
    {"tc": "TC-FCB-002", "case_id": "admin-auth-dispatch", "requirement": "REQ-FCB-002", "scenarios": ["SC-FCB-002"], "cp": "CP-FCB-002", "kind": "command", "applicability": "required"},
    {"tc": "TC-FCB-003", "case_id": "query-trace", "requirement": "REQ-FCB-003", "scenarios": ["SC-FCB-003"], "cp": "CP-FCB-003", "kind": "command", "applicability": "required"},
    {"tc": "TC-FCB-004", "case_id": "graph-parity", "requirement": "REQ-FCB-004", "scenarios": ["SC-FCB-004"], "kind": "command", "applicability": "not_applicable", "reason": "Graph 缺口位于本次上游窗口未改动的 FORK 文件，属既有问题，按用户指令移出本次合并范围。"},
    {"tc": "TC-FCB-005", "case_id": "remaining-capabilities", "requirement": "REQ-FCB-005", "scenarios": ["SC-FCB-005"], "cp": "CP-FCB-005", "kind": "command", "applicability": "required"}
  ]
}
```

Gate 2 前预检：`stdd agent verify upstream-sync-verification --change 2026-11-24-upstream-sync-58352363d0 --dry-run`。

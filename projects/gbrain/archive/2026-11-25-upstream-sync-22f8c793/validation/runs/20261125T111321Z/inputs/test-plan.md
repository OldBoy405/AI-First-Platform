# v0.60.772.0 上游同步测试方案与详细案例

> 版本：v0.60.772.0（UPSTREAM=22f8c793b1fa56bb46835801878b2053be940098）
> 创建日期：2026-11-25
> 对应 Phase 2 Spec：`canonical/specs/code/upstream-sync-merge.yaml`
> 验证规格：`canonical/specs/agent/upstream-sync-verification.yaml`

## 一、测试策略

### 1.1 测试金字塔

- 底层：Git 冻结事实、迁移 registry 与顺序检查、生成物 freshness、typecheck 与门禁 TSV。
- 中层：Inbox（ingest-capture / inbox-workflow）、Admin 鉴权顺序、query.trace 信封、来源隔离与 op 合同的定向行为测试。
- 高层：PGLite 隔离 E2E（source-isolation、engine parity）；Postgres/Docker 与 Admin Playwright 视环境执行，未跑项单列，不冒充通过。
- 全量根单测在 Windows 已知无完整信号（shard census 失败 + 挂死文件），以定向批次与 Admin 套件补证；不得声称 `bun run test` 通过。

### 1.2 测试原则

- 所有命令在独立同步 worktree 执行，Bun 固定为 1.4.4；依赖用 `--frozen-lockfile --ignore-scripts` 安装。
- 断言必须包含可区分对错的状态、计数或字段值，不得只匹配 PASS 标签。
- 生成物先由真源重建并整组暂存，再运行 freshness；相同输入第二次生成后，暂存区不得漂移。
- 失败项在固定 FORK 上用相同工具链、相同依赖和相同命令做 A/B；同项同因才能归入既有基线。
- 未运行、跳过、超时、失败或未归因均不得记为通过；旧库探针等未执行项必须在报告单列。

### 1.3 已有测试资产

| 测试文件/命令 | 类型 | 覆盖范围 |
|---|---|---|
| `test/ingestion/ingest-capture.test.ts`、`test/inbox-workflow.test.ts` | 单元/集成 | Inbox 预处理、落库 frontmatter/content/provenance 与 auto-link |
| `test/serve-http-admin-route-guard.test.ts`、`test/admin-embed-spawn.test.ts` | 集成 | Admin 先鉴权后分派、登录落地与嵌入清单 |
| `test/query-trace.test.ts`、`test/cli-goldens.test.ts`、`test/dispatch-response-meta.serial.test.ts` | 合同/CLI | query.trace 开/关/空结果、retrieval meta 与 MCP/CLI 信封 |
| `test/e2e/source-isolation-pglite.test.ts`、`test/e2e/engine-parity.test.ts`、`test/e2e/engine-content-privacy.test.ts` | E2E | 来源隔离、双引擎列与可见性、private/软删除过滤 |
| `test/schema-migration-registry.test.ts`、`bun run check:schema-migration-order` | 静态/迁移 | 迁移唯一性、顺序与 base-ref 撞号 |
| `test/operation-manifest.test.ts`、`test/parity.test.ts`、`test/mcp-tool-defs.test.ts` | 合同 | op 注册、CLI/MCP 生成一致 |
| `bun run check:regen-all`、`bun run check:admin-embedded` | 静态/生成物 | 真源产物新鲜度与暂存区一致性 |
| `bun run check:module-size`、`bun run check:page-body-readers`、`bun run check:core-world-reads` | 静态门禁 | fork 例外行、页面正文读法与 process_env ratchet |
| `bun run typecheck`、`cd admin && bun run test` | 类型/前端回归 | 根部类型与 Admin 套件 |

## 二、详细测试案例

### 功能 1：冻结输入与隔离候选

对应 `REQ-USM-001`。

#### 案例 1.1 — 冻结 Git 输入可复核

| 字段 | 内容 |
|---|---|
| **ID** | TC-USM-001 |
| **对应 Spec** | upstream-sync-merge → SC-USM-001 |
| **优先级** | P0 |
| **预置条件** | FORK=2e50b638f2、UPSTREAM=22f8c793b1、BASE=17b68cef4f 已登记；同步 worktree 从 FORK 建立。 |
| **输入** | 核对 merge-base、左右提交计数、UPSTREAM:VERSION、锚点解析值和主工作区状态。 |
| **预期结果** | BASE 为共同祖先；计数 62/2434；VERSION=0.60.772.0；锚点指向 FORK；主工作区未被合并改变，本地未跟踪状态未暂存。 |
| **当前状态** | 已规划，BUILD 待执行 CP-USM-001。 |

### 功能 2：fork 增量归因

对应 `REQ-USM-002`。

#### 案例 2.1 — 527 条 fork 增量逐路径归因

| 字段 | 内容 |
|---|---|
| **ID** | TC-USM-002 |
| **对应 Spec** | upstream-sync-merge → SC-USM-002 |
| **优先级** | P0 |
| **预置条件** | 台账 #1–#32、生成物登记和 527 个 fork 改动路径清单可用。 |
| **输入** | 逐路径核对候选仍保留的 fork 改动与上游吸收项，检查挂钩标记与加载路径。 |
| **预期结果** | 每个仍保留改动对应台账编号或生成物真源；无法归因项为零；已上游化行为无双实现。 |
| **当前状态** | 人工项，Gate 3 前由审阅者确认（`stdd agent confirm`）。 |

### 功能 3：67 个双边路径行为裁决

对应 `REQ-USM-003`。

#### 案例 3.1 — 双边路径裁决表与门禁基线一致

| 字段 | 内容 |
|---|---|
| **ID** | TC-USM-003 |
| **对应 Spec** | upstream-sync-merge → SC-USM-003 |
| **优先级** | P0 |
| **预置条件** | 67 条双边路径清单已冻结；三方 diff 可用；门禁 TSV 已按本轮改名与 ratchet 更新。 |
| **输入** | 生成/核对 67 行裁决记录；运行 `check:module-size`、`check:page-body-readers`、`check:core-world-reads`；检查技能路由重复与生成物来源。 |
| **预期结果** | `both_changed_paths=67 fork_delta_paths=527 upstream_delta_paths=5879`；`adjudication_rows=67 adjudication_missing=0`；三项门禁 `ok`；`duplicate_skill_routes=0`；生成物均来自真源。 |
| **当前状态** | 已规划，BUILD 待执行 CP-USM-002。 |

### 功能 4：上游 5879 路径覆盖核对

对应 `REQ-USM-004`。

#### 案例 4.1 — 上游窗口覆盖与高风险链核对

| 字段 | 内容 |
|---|---|
| **ID** | TC-USM-004 |
| **对应 Spec** | upstream-sync-merge → SC-USM-004 |
| **优先级** | P0 |
| **预置条件** | 上游 5879 条改动路径清单与高风险链清单（引擎、鉴权、来源隔离、Inbox、Admin、op 合同、生成器）可用。 |
| **输入** | 按目录与高风险链核对上游新合同的落地，抽下钻无文本冲突的共享文件改动块。 |
| **预期结果** | 五类高风险链均有行为核对结论；上游删除/改名路径有 fork 增量去向说明；无未核对改动块。 |
| **当前状态** | 人工项，Gate 3 前由审阅者确认（`stdd agent confirm`）。 |

### 功能 5：迁移顺延与注册

对应 `REQ-USM-005`。

#### 案例 5.1 — v298 → v337 顺延与探针

| 字段 | 内容 |
|---|---|
| **ID** | TC-USM-005 |
| **对应 Spec** | upstream-sync-merge → SC-USM-005 |
| **优先级** | P0 |
| **预置条件** | 上游 v298..v336 已合入；fork 迁移已改名为 v337，registry/latest 由生成器重建。 |
| **输入** | `GBRAIN_MIGRATION_BASE_REF=22f8c793b1 bun run check:schema-migration-order`；`bun test test/schema-migration-registry.test.ts`；隔离空 PGLite 库升级两次。 |
| **预期结果** | 顺序检查报告 `1 new migration(s) above latest v336 (337)`；registry 唯一且等于 337；空库 applied 到 337，第二次 applied=0；旧库偏差已登记台账。 |
| **当前状态** | 已规划，BUILD 待执行 CP-USM-003。 |

### 功能 6：生成物重建与稳定性

对应 `REQ-USM-006`。

#### 案例 6.1 — regen 与嵌入清单二次稳定

| 字段 | 内容 |
|---|---|
| **ID** | TC-USM-006 |
| **对应 Spec** | upstream-sync-merge → SC-USM-006 |
| **优先级** | P0 |
| **预置条件** | 源码、测试与手写门禁 TSV 已完成裁决并暂存。 |
| **输入** | `bun run regen:all` → `check:regen-all` → 第二次 `regen:all` 比较暂存区；`bun run build:admin` 后整组暂存并跑 `check:admin-embedded`；VERSION 门禁。 |
| **预期结果** | freshness 全通过；第二次生成漂移为 False；Admin 嵌入清单一致；VERSION=0.60.772.0 且版本门禁通过。 |
| **当前状态** | 已规划，BUILD 待执行 CP-USM-004。 |

### 功能 7：候选树质量信号

对应 `REQ-USM-007`。

#### 案例 7.1 — typecheck、定向回归、Admin 与 E2E

| 字段 | 内容 |
|---|---|
| **ID** | TC-USM-007 |
| **对应 Spec** | upstream-sync-merge → SC-USM-007 |
| **优先级** | P0 |
| **预置条件** | 候选生成物稳定；验证环境隔离且 Bun 版本合规。 |
| **输入** | `bun run typecheck`；定向批次（Inbox、Admin guard、trace、来源隔离、迁移 registry、op 合同）；`cd admin && bun run test`；可用的 PGLite E2E。 |
| **预期结果** | 每条命令 rc 与结果记录在案；`targeted_skips=0`；`source_isolation_passed=True`；新增回归为零；未跑项在台账标为未验证。 |
| **当前状态** | 已规划，BUILD 待执行 CP-USM-005。 |

### 功能 8：审计收口与交付边界

对应 `REQ-USM-008`。

#### 案例 8.1 — 双父 diff、台账与交付边界

| 字段 | 内容 |
|---|---|
| **ID** | TC-USM-008 |
| **对应 Spec** | upstream-sync-merge → SC-USM-008 |
| **优先级** | P0 |
| **预置条件** | 候选源码、测试、生成物与台账已完成并暂存。 |
| **输入** | `git ls-files -u`；`git diff --cached --check "$FORK"`；双父 name-status 对照；台账关键字检查；分支/远端状态检查。 |
| **预期结果** | 未解决冲突为 0；无本轮新增 whitespace 告警；新增/删除/改名/吸收均有解释；台账含本轮 SHA、迁移映射与验证结果；Gate 3 前未提交、未推送、未部署。 |
| **当前状态** | 已规划，BUILD 待执行 CP-USM-006。 |

## 三、测试执行矩阵

| 功能模块 | 单元/静态 | 集成/合同 | E2E | 状态 |
|---|---|---|---|---|
| 冻结输入（Git 事实） | 命令型 CP-USM-001 | — | — | 🟡 待 BUILD |
| fork 归因 / 上游覆盖 | 人工审阅 | — | — | 🟡 待 BUILD |
| 双边裁决与门禁 | 三项门禁 + 裁决表检查 | — | — | 🟡 待 BUILD |
| 迁移顺延 | 顺序/registry 检查 | 空库 PGLite 探针 | — | 🟡 待 BUILD |
| 生成物 | regen/freshness/嵌入清单 | — | — | 🟡 待 BUILD |
| 二开行为保持 | 定向批次 | Admin 套件 | PGLite source-isolation/parity | 🟡 待 BUILD |
| 审计与交付边界 | 双父 diff/台账 | — | — | 🟡 待 BUILD |

## 四、回归风险矩阵

| 风险区域 | 本轮改动 | 已有回归保护 | 风险等级 |
|---|---|---|---|
| Inbox 写入链 | 上游 minions/types、handlers 可能变化 | `ingest-capture.test.ts`、`inbox-workflow.test.ts` | 🔴 高 |
| Admin 鉴权与嵌入 | 上游 serve-http*/SPA 重构 | `serve-http-admin-route-guard.test.ts`、`admin-embed-spawn.test.ts` | 🔴 高 |
| 来源隔离/权限 | 引擎与 SQL 共享层改动 | `source-isolation-pglite.test.ts`、op remote 检查 | 🔴 高 |
| 迁移编号 | v298 撞号顺延 v337 | 顺序检查、registry 测试、空库探针 | 🔴 高 |
| query.trace | search/dispatch meta 变化 | `query-trace.test.ts`、`cli-goldens.test.ts` | 🟡 中 |
| 生成物 | regen 清单与 plugin 树变化 | `check:regen-all`、二次无漂移 | 🟡 中 |
| Windows 测试基线 | 既有假阳性/挂死 | 已知失败基线 + A/B | 🟡 中 |

## 五、建议补充顺序

1. **第一优先**（Gate 3 前必须）：冻结事实、迁移顺序与探针、生成物 freshness、Inbox/Admin/来源隔离定向、双父审计。
2. **第二优先**（Gate 3 前尽量）：query.trace、op 合同、门禁 TSV、E2E。
3. **第三优先**（记录为未跑或后续补）：Postgres/Docker E2E、Admin Playwright、旧 fork 库副本探针（需要操作者在安全窗口复制）。

## 六、同次执行证据计划 / Same-Run Evidence Plan

> 本节随 Gate 2 锁定。每个 TC 在此有且仅有一条 check；`required` 的 command/pytest check 必须绑定 CP（command 型每条独占一个 CP），`manual` 与 `not_applicable` 不得绑定 CP（后者须写 `reason`）。晚补要走 design-adjustment 与重新确认。

覆盖率义务：Bun/TypeScript 项目不使用 pytest-cov，声明 `not_applicable`，以行为断言、静态门与 E2E 结果作为质量保证。

```stdd-evidence-plan-v1
{
  "task": "upstream-sync-verification",
  "inputs": [
    {"root": "project", "path": "CUSTOM.md"},
    {"root": "project", "path": "CUSTOM-LEDGER.md"},
    {"root": "project", "path": "VERSION"},
    {"root": "project", "path": "package.json"},
    {"root": "project", "path": "admin/package.json"},
    {"root": "project", "path": "admin/bun.lock"},
    {"root": "project", "path": "src/admin-embedded.ts"},
    {"root": "project", "path": "src/core/migrate.ts"},
    {"root": "project", "path": "src/core/schema-migrations/v298-inbox-workflow-frontmatter.ts"},
    {"root": "project", "path": "src/core/schema-migrations/registry.generated.ts"},
    {"root": "project", "path": "src/core/schema-migrations/latest.generated.ts"},
    {"root": "project", "path": "src/core/minions/handlers/ingest-capture.ts"},
    {"root": "project", "path": "src/core/ops/search.ts"},
    {"root": "project", "path": "src/commands/serve-http-admin-op.ts"},
    {"root": "project", "path": "scripts/regen-all.ts"},
    {"root": "project", "path": "scripts/check-schema-migration-order.ts"},
    {"root": "project", "path": "scripts/page-body-readers-baseline.tsv"},
    {"root": "project", "path": "scripts/module-size-limits.tsv"},
    {"root": "project", "path": "scripts/core-world-reads-baseline.tsv"},
    {"root": "project", "path": "test/schema-migration-registry.test.ts"},
    {"root": "project", "path": "test/ingestion/ingest-capture.test.ts"},
    {"root": "project", "path": "test/inbox-workflow.test.ts"},
    {"root": "project", "path": "test/serve-http-admin-route-guard.test.ts"},
    {"root": "project", "path": "test/query-trace.test.ts"},
    {"root": "project", "path": "test/operation-manifest.test.ts"},
    {"root": "project", "path": "test/parity.test.ts"},
    {"root": "project", "path": "test/e2e/source-isolation-pglite.test.ts"},
    {"root": "project", "path": "test/e2e/engine-parity.test.ts"},
    {"root": "project", "path": "test/cli-goldens.test.ts"},
    {"root": "project", "path": "test/export-surface-golden.test.ts"},
    {"root": "project", "path": "test/engine-sql-sql-text.test.ts"},
    {"root": "project", "path": "test/cli-dispatch-phase.test.ts"},
    {"root": "project", "path": "test/fixtures/goldens/cli/tools-json.json"},
    {"root": "project", "path": "test/fixtures/goldens/cli/help-and-errors.json"},
    {"root": "project", "path": "test/fixtures/goldens/exports/runtime.json"},
    {"root": "project", "path": "test/fixtures/goldens/exports/types.json"},
    {"root": "project", "path": "test/fixtures/goldens/sql-text/links.json"},
    {"root": "project", "path": "test/fixtures/goldens/sql-text/_classification.json"},
    {"root": "project", "path": "test/fixtures/goldens/sql-text/_driver.json"},
    {"root": "project", "path": "test/fixtures/goldens/migrations/records.json"},
    {"root": "project", "path": "src/commands/status.ts"},
    {"root": "project", "path": "test/migrations-golden.test.ts"}
  ],
  "coverage": {"applicability": "not_applicable", "reason": "Bun/TypeScript 项目，不使用 pytest-cov；以具体行为断言、静态门和 E2E 结果作为质量保证。"},
  "checks": [
    {"tc": "TC-USM-001", "case_id": "freeze-inputs", "requirement": "REQ-USM-001", "scenarios": ["SC-USM-001"], "cp": "CP-USM-001", "kind": "command", "applicability": "required"},
    {"tc": "TC-USM-002", "case_id": "fork-attribution", "requirement": "REQ-USM-002", "scenarios": ["SC-USM-002"], "kind": "manual", "applicability": "required"},
    {"tc": "TC-USM-003", "case_id": "bilateral-resolution", "requirement": "REQ-USM-003", "scenarios": ["SC-USM-003"], "cp": "CP-USM-002", "kind": "command", "applicability": "required"},
    {"tc": "TC-USM-004", "case_id": "upstream-window-coverage", "requirement": "REQ-USM-004", "scenarios": ["SC-USM-004"], "kind": "manual", "applicability": "required"},
    {"tc": "TC-USM-005", "case_id": "migration-renumber", "requirement": "REQ-USM-005", "scenarios": ["SC-USM-005"], "cp": "CP-USM-003", "kind": "command", "applicability": "required"},
    {"tc": "TC-USM-006", "case_id": "generated-stability", "requirement": "REQ-USM-006", "scenarios": ["SC-USM-006"], "cp": "CP-USM-004", "kind": "command", "applicability": "required"},
    {"tc": "TC-USM-007", "case_id": "candidate-quality", "requirement": "REQ-USM-007", "scenarios": ["SC-USM-007"], "cp": "CP-USM-005", "kind": "command", "applicability": "required"},
    {"tc": "TC-USM-008", "case_id": "final-audit", "requirement": "REQ-USM-008", "scenarios": ["SC-USM-008"], "cp": "CP-USM-006", "kind": "command", "applicability": "required"}
  ]
}
```

Gate 2 前预检：`stdd agent verify upstream-sync-verification --change 2026-11-25-upstream-sync-22f8c793 --dry-run`。

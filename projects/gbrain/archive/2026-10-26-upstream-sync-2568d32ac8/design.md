# 上游同步 v0.60.176.0 → v0.60.461.0 - 技术设计

## Context

- fork `OldBoy405/GBrain-custom` 的 `master` 停在 upstream `2895edb3c6`（v0.60.176.0），上游已到 `2568d32ac8`（v0.60.461.0）。
- 本轮窗口 5333 提交 / 4804 改动文件；fork 增量 509 文件；两边都改 47 文件，其中 19 个真实冲突。
- 上游本轮新增 36 个迁移（v239..v274），我方 `inbox_workflow_frontmatter` 占 v239，**同号**。
- 上游同期引入 belief ledger、segmented pages、derived generations 等新子系统，与 fork 的 Inbox / 真理沉淀不同名不同义。
- 本机 Bun 已升 1.4.4；`origin/master` 已与本地 `master` 同步（`709c16b4a9`）。
- fork 的 GitHub Actions 因计费受限全部无法启动，**没有推送级 CI 信号**，验证只能本地做。

## Decisions

### 1. 同步分支承载全部合并工作，`master` 到 Gate 3 后才动

**方案**：从 `master`（`709c16b4a9`）开 `sync/upstream-2026-10-26-2568d32ac8`，打 `pre-sync/2026-10-26`；台账修复合并在该分支。

**为什么**：守则要求 `master` 可回退；Gate 3 前不 push、不部署。冲突与改号都在分支上可反复重来。

**备选方案及排除原因**：
- 直接在 `master` 上 merge：一旦中途失败，回退要动已推送的主线，风险不可控。
- rebase 到上游：fork 的 20+ 提交会被全量重写，历史不再可审计。

### 2. 冲突裁决按「改动点归属」而非 git 冲突块

**方案**：对 47 个两边都改的文件，先按台账定位 **fork 改动点**（文件 + 符号级），再看上游在该处的**新结构**，把改动点贴回新位置；生成物不参与裁决。

**为什么**：git 只能标出文本冲突；上游重构后，fork 改动点常常在「无冲突」的文件里被静默覆盖。台账已把每个改动点登记到符号级（Gate 1 §0 已校验 33/33 可核对）。

**备选方案及排除原因**：
- 按冲突块逐块选边：会把同一功能的 upstream / fork 两半拼在一起，产生语义断层。
- 全取上游再人工补：会漏掉干净合并文件里的静默失效，v0.60 重构面已证明这一点。

### 3. 迁移号顺延到 275，且以「产物探针」而非迁移日志为准

**方案**：`v239-inbox-workflow-frontmatter` → `v275`（上游最新 274 + 1），同步改文件名、导出名、`version` 字段、registry 注册行（生成器产出）。

**为什么**：runner 只按版本号记 `schema_version`；同号意味着两份 DDL 里必有一份永远不执行。v133 事故（`embedded_text_hash` 列缺失）就是这条路径。

**备选方案及排除原因**：
- 保留 239、依赖上游 skew guard：guard 只覆盖它自己知道的对象，管不到我方表。
- 手工在数据库补列：绕过迁移体系，下一台机器仍缺失。

### 4. 生成物全部走 `regen:all` 管线，零手工 resolve

**方案**：顺序 `build:schema-migrations` → `regen:all` → `regen:all --goldens` → `build:admin` → `build:llms` → `check:regen-all`。

**为什么**：`check:regen-all` 是 freshness 门，钉的是生成器输出而非内容正确性。手改 json / `.generated.ts` 会让门长期红，且下次生成即被覆盖。

**备选方案及排除原因**：
- 保留上游生成物、只补 fork 段：registry 与 manifest 是整表生成，局部补丁无法保持顺序与哈希一致。

### 5. 验证先定向后全量，失败逐条归类

**方案**：先跑定向批次（inbox / truth / graph / redaction / surface / migration probe），再 `typecheck` → `bun run verify` → 全量 `bun run test`；每个失败项必须归入《已知测试失败基线》或当场解释。

**为什么**：Windows 下并行 runner 有已知 shard 统计失败与挂死文件（台账基线）；先取定向信号能区分「合并事故」与「既有基线」。

**备选方案及排除原因**：
- 直接 `bun run test` 全量：上轮出现 18 分钟零进度，等于没有信号。

## Architecture

```
Gate 1 (PASS) ── Gate 2 本设计 + 裁决矩阵
      │
      ▼
Phase 3 BUILD
  1. git merge upstream/master        → 19 冲突按矩阵 A 裁决，28 文件按矩阵 B 核挂钩
  2. 迁移改号 239→275                  → build:schema-migrations → 排序探针 + 产物探针
  3. regen 管线                        → regen:all → regen:all --goldens → build:admin → build:llms → check:regen-all
  4. 验证                              → typecheck → 定向批 → verify → 全量 → admin vitest
  5. 台账                              → CUSTOM.md《阶段记录》追加本轮（Gate 3 后）
      │
      ▼
Gate 3 (test-report + design-adjustments)  → 用户确认 → 才允许 push origin
```

数据/契约边界不变：CLI 与 MCP 仍由 `operations.ts` 契约生成；两引擎仍实现同一 `BrainEngine`；
查询仍经 `sourceScopeOpts(ctx)` 做 source 隔离。

## Risks / Trade-offs

| 风险 | 缓解措施 |
|------|----------|
| 迁移同号导致 DDL 静默跳过 | 改号 275 + 排序探针（base ref = upstream/master）+ information_schema 产物探针 |
| 干净合并文件里的挂钩静默失效 | 矩阵 B 逐条列挂钩与验证命令；`test/serve-http-admin-route-guard.test.ts` 等既有守卫兜底 |
| 上游重构把 fork 改动点整段替换 | 矩阵 A 每行给出「贴回位置 + 验证命令」；定向测试先行 |
| 生成物手改导致 freshness 门长期红 | 零手工 resolve，全部重跑；失败先看 `check:regen-all` 输出 |
| Windows 环境噪声被误判为合并事故 | 合并前 `pre-sync/2026-10-26` worktree 实测同一项；失败逐条分类，不笼统归因 |
| fork 无 CI 信号 | 全部验证本地执行并在 test-report 记录命令与输出；不把「本地绿」表述成「CI 绿」 |
| 大窗口（285 release）本身是欠债 | 本轮记录写进《阶段记录》的欠债登记；下一轮回到「每个 release 合并一次」 |

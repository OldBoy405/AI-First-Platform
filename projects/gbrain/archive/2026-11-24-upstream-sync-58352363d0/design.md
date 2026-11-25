# 按二开合并规则同步上游 v0.60.638.0 - 技术设计

## Context

- 业务根：`C:/Users/GOBAO/Downloads/AI/gbrain`；Bun 1.4.4 满足候选 `package.json` 的 `>=1.4.4`。
- `FORK=8f0e2d99983885d980fef98d6d5088c2649b38e5`，`UPSTREAM=17b68cef4f4267ca0e5710b42f6ddc95acf9fe51`，`BASE=553b5473344af4b8d9e09ebb8078e4e51a6d15eb`。
- 窗口为 v0.60.636.0 → v0.60.638.0，13 个上游提交、66 个上游单侧改动路径；FORK 相对 BASE 有 59 个提交。change ID 与回滚锚点保留原 release SHA 标签，effective UPSTREAM 明确为同版本 upstream/master merge。
- 台账新鲜度：相对 BASE 的 515 个历史 fork 改动已有归因；第 516 个路径 `CUSTOM-LEDGER.md` 由 #28 自登记。TC-USM-002 在候选树人工复核全部路径与保留符号，CP-USM-002 只验证六个双边文件的裁决；最终未归因项为零由人工归因和 CP-USM-007 候选审计共同证明。
- 当前主工作区只有 `.gbrain/`、`.qoder/better-harness/`、`.stdd/` 未跟踪本地状态；它们不是合并输入。
- 模型派发：STDD 配置的 design 档为 strong，但当前 Agent 工具不能传 model/effort；actual=unknown，本设计由主会话生成，未声称按 strong 档执行。

## Decisions

### 1. 只合并冻结的两个 release，在独立 worktree 准备候选

**方案**：从 FORK 新建 `sync/upstream-2026-11-24-17b68cef`，在隔离 worktree 用 `git merge --no-ff --no-commit` 合入冻结 UPSTREAM。所有冲突处理、生成、测试和分父审计都在候选树进行；主工作区保持 FORK。

**为什么**：本轮只有 13 个上游提交、72 个上游改动文件，风险显著小于 132 release 的追平窗口；隔离可防止合并中的生成物、测试或未提交状态污染主分支和本机 CLI 入口。

**备选方案及排除原因**：
- 直接追平 v0.60.768.0：2388 提交、132 release、迁移扩展到 v331，违反小增量原则，范围和验证面未经本轮 Gate 确认。
- 在主工作区直接合并：会改变下一次本机 CLI 可能读取的树，且现有未跟踪状态增加误纳入风险。
- rebase/cherry-pick：破坏“双父审计”和上游完整历史，不能证明上游基底被原样吸收。

### 2. 以上游为代码基底，只重接可归因的 fork 行为

**方案**：按 BASE/FORK/UPSTREAM 三方差异和台账 #N 裁决。已由上游实现的相同行为以上游胜出；纯 fork 新增保留；共享文件只贴回独立、可交换且不改优先级/默认值/权限的增量。无文本冲突也沿调用链核对。

**为什么**：路径名、ours/theirs 和冲突数量都不能证明行为正确。当前预测只有两个文本冲突，但上游修改了 17 个 persistence/cycle/repair 源文件，必须验证它们与 fork 写入链的交互。

**备选方案及排除原因**：
- 整文件选边：会静默丢掉 Inbox、Admin、Graph 或上游修复。
- 机械并集：会重复注册、破坏锁文件/生成物或改变门禁口径。
- 只修冲突文件：无法发现 `putPage`、purge、sync/repair 的无冲突行为变化。

### 3. 六个双边改动文件逐项裁决，生成物不手拼

**方案**：
- `scripts/module-size-limits.tsv`：手写真源。以上游新表为底，保留 11 行 fork 例外并复核实际行数/理由；上游 `behavior-change-notice.ts` 上限 1697→1699，其他上游上限调整不得被 fork 旧值覆盖。
- `scripts/page-body-readers-baseline.tsv`：手写真源。保留 11 行 Inbox/Truth/迁移 reviewed rows，加入上游 `atom-fence-rows.ts` 两行；v298 路径和读法必须继续对应实际迁移。上游新增的 `atom-fence-rows.ts` 行带尾随 tab，重建此行时去除尾随空白，避免把可定位的本轮告警带入候选。
- `skills/RESOLVER.md`：合并两个独立路由增量，保留 fork 的 `create a new skill` 触发和 skill-optimizer 路由，同时纳入上游 `atom_fence_rows` 与显式 repair 预览措辞；不叠重复 skill-optimizer 路由。
- `skills/skills.lock.json`：由 resolver/skills 真源重生成，采用新哈希，不手拼冲突。
- `plugin/README.md`：由 plugin 生成链重生成，吸收版本 stamp 和上游 operation 数，不手改。
- `llms-full.txt`：由 `scripts/llms-config.ts` 和选定文档重生成；保留 #25 的 AGENTS `includeInFull: false`，不得因上游产物 inline AGENTS 而改变 fork 配置。

**为什么**：前两项是带理由的门禁输入，后四项是生成物；分别处理可避免“并集”制造双重注册或假新鲜度。

**备选方案及排除原因**：
- 对六个文件统一 ours/theirs：要么丢上游 ratchet/修复，要么丢 fork 例外和路由。
- 手工修改所有生成文件：无法证明同输入可重复生成，违反 CUSTOM.md。

### 4. 不引入新迁移；验证 v298 仍位于上游 v297 之后

**方案**：上游窗口没有新增 schema migration，latest 仍为 v297。fork `inbox_workflow_frontmatter` 保持 v298，不改名、不改内容；重生成 registry/latest 后运行迁移顺序和 registry 测试。由于本轮迁移文件不变，不重复声称需要执行生产升级；若实施发现相关调用或 DDL 被上游改变，则暂停并重审。

**为什么**：v298 已高于上游末位，顺延反而会制造无依据的新旧库差异；版本号检查也不能替代结构探针。

**备选方案及排除原因**：
- 自动顺延到 v331：把未合入的上游迁移混入本轮，造成编号空洞和错误依赖。
- 只检查版本号相等：无法证明 v298 列、状态和 legacy 回填真实存在。

### 5. 风险验证按实际影响面展开，不按 72 个文件平均用力

**方案**：
- P0 验证上游恢复文件、保留已提交文件、purge 时序脱敏、world-row atom 读取/repair；复用上游新增测试并补最小 fork 交叉断言（如需要）。
- P0 回归 Inbox 捕获实际写入、Admin 先鉴权后分派、query.trace 信封、Graph source/private/软删除约束。
- 验证生成物、门禁基线、typecheck、根单测、Admin 测试、迁移顺序和 registry。
- 持久化 E2E 使用隔离 PGLite；Graph 的 Postgres parity 是 Gate 3 必需信号，Docker/DB 不可用时本项保持未通过，不以 PGLite 冒充双引擎证据。其他非 Graph E2E 按实际影响面执行，未跑项明确列出。
- 对失败项在固定 FORK 上用相同工具链和相同检查做 A/B；Windows 超时/挂死记录为未完成，不用旧记录充当候选通过。

**为什么**：CUSTOM.md 要求行为证据，且已知 Windows runner 有超时、路径分隔符和 base-ref 假阳性；必需检查没有候选信号时不能放行。

**备选方案及排除原因**：
- 只跑 `typecheck`/`verify`：无法证明写入、清除和权限行为。
- 全套重型 E2E 无差别执行：本轮没有引擎/合同修改，成本与风险不匹配；仅在依赖变化或失败归因需要时扩大。
- 把上游 CI 成功当 fork 通过：不能覆盖 fork 的 Inbox/Admin/Graph 增量。

### 6. 生成和依赖安装隔离，候选可重复生成

**方案**：在 worktree 用 `bun install --frozen-lockfile --ignore-scripts`；不运行根 postinstall。按依赖关系先处理真源/手工基线，再运行 `regen:all`、必要的 `regen:all --goldens`、`build:admin`/`build:llms`，整组定向暂存后运行 freshness 检查，再以相同输入复跑并确认无漂移。锁文件只允许安装器重算。

**为什么**：根 postinstall 可能调用当前 brain；Admin 与 schema/ops/skills/llms 有各自真源，手工解决产物会制造假阳性或漏项。

**备选方案及排除原因**：
- 根 `bun install`：可能迁移运行中的 brain，超出本轮授权。
- 只跑 Admin Vite build：不会更新根嵌入清单。
- 用未暂存工作区运行 `check:admin-embedded`：会把 index/工作区差异误报为产物陈旧。

### 7. 三项阻断验收承诺的既有基线缺口在候选树做最小修复

**方案**：
- Inbox：managed `put_page` 分支改用 `prepareInboxCaptureContent` 的返回值，保留同一 source 快照、provenance 和 auto-link 守卫；测试读取实际落库页面，不只断言预处理函数。
- Graph：`graph_overview` 通过 `readPolicyOpts` 取得 `excludePrivate`；`graphOverview` 的 degree 聚合、节点选择、边两端和 private origin 使用同一 source/private/软删除可见性范围。复用 `privatePagesFilterForCaller` 与 `privateLinkOriginFilterForCaller`，不新增权限抽象。
- query.trace：trace 开启时在 `trace.retrieval` 保留 op 实际 emit 的完整 retrieval meta；MCP `_meta.retrieval` 继续作为独立传输元数据。Admin client 保留 ToolResult `_meta`，Ask 将其合并入 trace，trace 关闭时仍返回原数组。

**为什么**：三项缺口在冻结 FORK 已存在，但本轮 success criteria 已承诺实际写入、Graph 不越权和完整诊断。不修则候选无法诚实放行；只修到已承诺合同可避免把同步合并扩大为无关重构。

**备选方案及排除原因**：
- 悄悄忽略并宣称回归通过：违反成功标准和 CUSTOM.md 的证据规则。
- 另开大规模重构：超出本轮范围，且增加同步归因难度。
- 把基线缺口算作 merge 新回归：会扭曲 A/B 结论；固定 FORK 同项失败与候选修复后的通过分别记录。

## Architecture

```text
冻结 FORK / UPSTREAM / BASE + 台账 #N + 回滚锚点
                    |
       Gate 2: 冲突/行为矩阵 + 测试方案
                    |
 独立 worktree: merge --no-ff --no-commit UPSTREAM
                    |
     +-- 真源/手工基线裁决（TSV、RESOLVER）
     +-- 无冲突行为核对（persistence / cycle / repair）
     +-- 生成物重建（schema/ops/skills/plugin/llms/admin）
                    |
       定向行为验证 + 静态/单测/Admin/E2E
                    |
       FORK A/B 归因 + 双父审计 + 台账回填
                    |
         Gate 3: 仅放行独立同步分支候选
                    |
  另行授权: commit / master / push / deploy / host migration
```

关键调用约束：

1. Inbox 捕获先生成 workflow frontmatter，unmanaged `importAs()` 与 managed `put_page` 都写入处理后的 content；`runAutoLink` 必须走上游自读快照和权限守卫。
2. Admin `/admin/api/op` 必须先通过 `requireAdmin`，再分派到 op handler；独立审计只写一次，不复制 `/mcp` 日志。
3. `query.trace=true` 在 `trace.retrieval` 保留 op 实际 emit 的完整 retrieval meta（含 evidence/page cap/degraded/explain-target）；MCP `_meta.retrieval` 保持独立，Admin client 不得丢弃；未开启时不改变结果形状。
4. Graph 遍历和总览都应用 source/private/软删除约束；总览的 degree 与边不得被不可见端点或 private origin 污染；两引擎的 `both` 方向不能漏 `to_title` / `to_type`。
5. 上游 purge/sync 新行为不得绕过 fork 的写入顺序和 provenance；repair 读取 world rows 必须保留 owner-only fence 隔离。

## Risks / Trade-offs

| 风险 | 缓解措施 |
|------|----------|
| 两个文本冲突掩盖了 persistence/cycle/repair 的无声行为变化 | 66 个上游单侧路径全部三方核对；P0 运行恢复、purge、world-row 和 repair 的行为测试 |
| 三项 FORK 既有缺口被忽略、误报为合并回归或扩大成重构 | 仅修复已承诺合同；固定 FORK A/B 与候选通过分别归因；Graph Postgres 为必需信号 |
| cached diff 的存量 whitespace 告警被误判为本轮回归 | 冻结 FORK 已有 397 条告警（29 文件，含 Markdown 硬换行）；按路径与新增行内容对照双亲基线，只要求本轮新增为零，不顺手清理无关文档 |
| fork TSV 例外被上游 ratchet 更新覆盖 | 手写基线以上游为底重贴 11 行例外，逐项核对实际行数/理由，禁止机械 ours |
| 生成物被手工 resolve 或未整组暂存 | 真源重建、定向整组暂存、freshness 检查和同输入二次复跑 |
| v298 迁移被误顺延或被版本号检查误判安全 | 本轮保持 v298；顺序/registry 测试通过，数据库结论只按实际执行的结构探针表述 |
| 根安装触发运行中 brain | worktree 内 `--frozen-lockfile --ignore-scripts`，生命周期步骤单独评估 |
| Windows guard/runner 假阳性或超时 | 固定 FORK A/B；记录 rc/耗时/未完成，必需信号缺失则不标通过 |
| 主工作区或本地状态被合并污染 | 独立 worktree/分支；本地 `.gbrain/`、`.stdd/`、`.qoder/better-harness/` 不纳入 |
| Gate 3 被误当作推送/部署授权 | 候选只留同步分支；每类交付动作单独确认并记录 |

## 实施边界

- 可创建隔离 worktree、同步分支、STDD 过程文件、最小回归测试和临时验证产物。
- 可执行本地依赖安装（仅隔离且 ignore-scripts）、生成、测试和只读 Git 审计。
- 不可推远端、切 master、部署、执行生产迁移或修改共享 CI/权限；这些不在 Gate 2 的技术授权内。

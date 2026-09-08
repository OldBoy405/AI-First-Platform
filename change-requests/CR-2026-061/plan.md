---
id: CR-2026-061-plan
type: PLAN
cr-ref: CR-2026-061
sdd-ref: "change-requests/CR-2026-061/sdd.md"
target-version: 0.34
status: draft
created: 2026-09-08T12:04:37+08:00
updated: 2026-09-08T20:44:46+08:00
---

# CR-2026-061 开发计划（Discussion 显式升级）

输入：已审批 SDD v1.1（提交 `6cb4937`，review-annotations/sdd.yml verdict=pass、blockers=[]、subject-sha256 `310434e726469511a5018a8aab627f872b1e8fae8420776054789e38d1f184be`）+ PRD v0.3。目标版本 `0.34`（继承 cr.md，未改写）。

## 0. 基线核实（开工前 freshness gate）

`crctl workspace freshness CR-2026-061`（gate=implement-start）→ **route=continue，allFresh=true**：

| 仓 | CR 分支 | trunk | 分类 |
|---|---|---|---|
| multica | `requirement/CR-2026-061` @ `eafce66b1fd135dac458f128ba2c94779ff8e2c4`（= trunk main，fresh） | `eafce66b` | healthy / fresh |
| tools | `requirement/CR-2026-061` @ `30b49d2`（trunk main `bef1f4d` 治理边已并入，fresh） | `bef1f4d` | healthy / fresh |
| ai-first-platform-docs | `requirement/CR-2026-061` @ `731216db`（**落笔时快照**；master 之上，fresh） | master `4e6a3a49` | healthy / fresh |

注：docs CR 分支 SHA 为**落笔时快照**——docs 仓随每次 CR 提交（plan/tasks/状态/checkpoint/review 记录）持续前移（本回修落笔时已至 `e0d35ab`），实施期不得按陈旧 SHA 对照 docs，以 `crctl workspace freshness` 为准。tools trunk 新增治理边 `bef1f4d`（本 CR 修订链所需，先例 `49c46dd` 同模式，见 §9），已 merge 进 tools CR 分支 `30b49d2`；实施事实源不变。

**基线前移事实（需评审证据链知晓）**：SDD 的 35 项既有实现依赖锚定于 multica `78e14082`；开工时 multica trunk 已前移至 `eafce66b`（第 5 次 upstream 同步，`476cf8c3` merge upstream/main + 台账提交 `eafce66b`）。本计划已在新基线逐项复核 35 项锚点：**全部符号/语义存活**；行号微移仅 4 处（均在既有清单带行号的条目上）：`loadIssueForUser` handler.go L1049→**L1053**、`GetIssue` issue.go L2225→**L2232**、`BindCurrentTaskToCR` task.go（定义现位于 ~L4523/4547/4567 区域）、`mergeForwardDiscussion` client.ts L3855。其余锚点文件（gate_projection.go、idempotency.sql、chat.sql、agent.sql、issue_limit.go、cr_bind.go、migrations 451/456/501–504、router.go 等）在本区间无 diff，行号不变。**实施以 `eafce66b` 为事实源**；实施期每个 TASK 开工前重跑 freshness 复核。

## 1. 交付里程碑

| 里程碑 | 内容 | 对应 TASK | 估时 |
|---|---|---|---|
| M1 数据层 | 迁移 505（scope CHECK 扩展）/506（promotion run 部分唯一索引）/507（context_refs GIN）+ `promotion.sql` 新 sqlc 查询 + migrate 并发索引清理登记 | TASK-01 | 1.5 人天 |
| M2 服务内核 | `createInTx` 提取（D-7）+ `PromoteDiscussion` 全流程（fingerprint/dedupe_key 纯函数、幂等四分支、查重、默认标题描述、预建 run）+ zero_diff 回归 | TASK-02 | 3 人天 |
| M3 HTTP 与绑定链路 | promote handler + 路由 + 错误闭包 + `IssueResponse.context_refs` 暴露 + bind-promotion-run 端点/服务 + `multica cr bind-promotion-run` CLI | TASK-03 | 2.5 人天 |
| M4 前端与 tools 协同 | client/schemas/discussion-pane 两入口/Issue 详情来源入口/四语文案 + tools requirement-register SKILL 绑定步骤与集成测试 | TASK-04 | 2 人天 |
| 联调/验收 | 全量 cmd-01..06 证据跑绿、写测试报告（write-test-report）、统一 checkpoint、review-code | — | 1 人天 |

**估算总工时（TASK 账本口径，与 tasks/_index.yml 的 totalEstimateHours 一致）= 72h**；另计联调/验收 8h 为跨 TASK 非账本工时（不进 TASK estimate，也不写入 tasks/_index.yml）。发布经既有 CR merge 流程，不在本计划 TASK 范围内（流程控制 TASK 禁止，见 write-dev-tasks）。

## 2. 任务依赖图

```text
TASK-01 (multica 数据层：迁移 505/506/507 + promotion.sql sqlc)
   │  产出：sqlc 生成的 Go 查询接口（FindPromotionDuplicateIssue / InsertPipelineRun /
   │        InsertPipelineNodeRun / FindActiveRequirementRunForIssue /
   │        SetIssueContextRefPipelineRun / AppendIssueContextRefs / ListAttachmentsForPromotion）
   ▼
TASK-02 (multica 服务层：createInTx 提取 + PromoteDiscussion + 纯函数)
   │  产出：IssueService.createInTx、IssueService.PromoteDiscussion、
   │        canonicalUUIDs / promotionFingerprint / promotionDedupeKey、
   │        defaultPromotionTitle / defaultPromotionDescription、PromotionRunPlan
   ▼
TASK-03 (multica HTTP/绑定层：promote handler + 错误闭包 + context_refs 暴露
   │     + BindPromotionRunToCR + HandleBindPromotionRun + cmd_cr.go 子命令)
   │  产出：POST /api/projects/{projectId}/discussion/promote、
   │        POST /api/crs/{crID}/bind-promotion-run、multica cr bind-promotion-run、
   │        IssueResponse.ContextRefs
   ▼
TASK-04 (multica 前端 + tools：client.promoteDiscussion、schemas、discussion-pane
        两入口、Issue 详情来源入口、locales、requirement-register SKILL 绑定步骤)
```

- 依赖全部为「上游产出 → 下游消费」：sqlc 接口 → service；service 方法 → handler；端点/CLI 契约冻结 → 前端 client 与 tools SKILL。
- 无环、无悬空引用；TASK-04 的 tools 子部分与前端子部分同属一个 TASK（同一契约消费方、同一 owner、合计 ≤3 天）。
- 顺序执行（串行链），不做并行分支：后续每个 TASK 的接口契约逐字依赖上游签名。

## 3. 资源与分工

- owner.development = Ray，owner.test = Ray（cr.md 权威）。
- 实施执行：dev-agent（本 Agent）；测试报告消费 implement-code 真实验证结果；代码/计划评审由独立 quality-reviewer-agent（不自评）。

| TASK | 估时 | 责任人 | 说明 |
|---|---|---|---|
| CR-2026-061-TASK-01 | 12h | dev-agent | multica 仓，迁移与 sqlc 数据层 |
| CR-2026-061-TASK-02 | 24h | dev-agent | multica 仓，服务内核（最大单体，唯一 Issue 写入路径） |
| CR-2026-061-TASK-03 | 20h | dev-agent | multica 仓，HTTP/绑定/CLI |
| CR-2026-061-TASK-04 | 16h | dev-agent | multica 前端 + tools requirement-register |
| 联调/证据/测试报告 | 8h（非账本） | dev-agent（实现证据）+ test owner 消费 | 跨 TASK，不进 TASK 账本（totalEstimateHours 口径仅计上表 4 行 = 72h） |

## 4. 风险与回滚策略

| # | 风险 | 等级 | 应对 | 回滚 |
|---|---|---|---|---|
| R1 | 基线漂移：实施期间 multica upstream 再合入，行号/符号移动 | 中 | 每 TASK 开工先 `crctl workspace freshness`；代码按 stable symbol 定位，不按行号硬编码；SDD §12 锚点失效时以 revision 修订 plan/TASK 并注明 | 以 freeze 的 `eafce66b` 为事实源；漂移影响结论时停止并报告 |
| R2 | `createInTx` 提取破坏既有 `IssueService.Create` 行为 | 高 | 提取纯机械（D-7）：`Create` 保持原签名行为 = Begin→createInTx→Commit→事件；既有 Create 测试全量回归（zero_diff 清单）；新字段零值逐字节等价 | revert TASK-02 commit（单 commit 可逆） |
| R3 | 506 部分唯一索引竞态 / 与 456 槽位冲突（SDD §4.5 违约路径） | 中 | 并发补建走「506 冲突 → FindActiveRequirementRunForIssue 重读」；绑定违约路径按 SDD §4.5 恢复（定位 issue_id IS NULL 投影行人工确认删除后幂等重试）；测试夹具覆盖 23505 | 迁移 down 已登记（506 无数据依赖，降级语义=应用锁仍工作） |
| R4 | 505 CHECK 扩展的 PG 默认约束名与预期不符 | 低 | 实施时先经 `pg_catalog`/测试夹具确认 `chat_idempotency_scope_type_check` 再 DROP；单条 ALTER 两动作原子（SDD §2.6/§13.2） | down 反向回旧枚举（前置：无 `discussion_promotion` 行） |
| R5 | 前端旧后端/旧前端兼容（context_refs 缺字段、新响应形状） | 中 | `z.array(...).catch([])` fallback + `parseWithFallback` + malformed-response 测试（CLAUDE.md API Compatibility） | revert TASK-04 commit |
| R6 | tools requirement-register SKILL 改动影响普通注册主路径 | 高 | promotion 上下文为**可选输入**：缺失时按普通注册、不定位不绑定（行为不变）；集成测试显式断言普通注册路径；lint-prompts enforce 通过 | revert TASK-04 中 tools 部分 |
| R7 | 预建 run 未被消费（用户升级后未注册）长期滞留 | 低 | 明确范围排除（SDD §9 scope_out / follow_up）；不引入清理逻辑 | 无需回滚；后续 CR |

回滚单元 = 每个 TASK 的独立 commit（revert 单 TASK 不影响其余）；迁移 505/506/507 的 down 语义见 SDD §13.1。

## 5. 验收与发布策略

**估算总工时（TASK 账本口径）**：72h（CR-2026-061-TASK-01 12h + TASK-02 24h + TASK-03 20h + TASK-04 16h）。联调/验收 8h 为跨 TASK 非账本工时。

- **验收门槛（发布前 checklist）**：
  1. cmd-01..cmd-06 全绿（证据命令表，见 §6.2；`crctl test` 机器区执行，cmd-NN 日志 `test-evidence/cmd-NN.log` 与表一一对应）；
  2. `write-test-report` status=pass 且 blockers=[]（消费 implement-code 真实验证结果）；
  3. 统一 checkpoint 三仓 confirmed；
  4. 独立 `review-code` verdict=pass、blockers=[]；
  5. `crctl approve --stage dev-start` 与 `--stage code` 均经人工（Ray）。
- **feature-flag**：PRD/SDD 未要求 feature-flag；promotion 是纯新增端点 + 前端显式入口，对既有 Discussion 路径零改动（FR-1/FR-5 zero_diff），无需开关。
- **发布**：经既有 CR merge 流程（`merge-feature-branch` / writeback），不进交付 TASK（流程控制 TASK 禁止；merge/审批/checkpoint 的审计以 approval.yml、merge-commits.yml、checkpoint 元数据为准）。
- **发布后观测**：成功指标按 PRD §6 核验（显式升级 Issue=1、同源 run≤1、零残留、零账本写入、零越权）。

## 6. 两张稳定表（契约必填，CR-2026-060 AC-07）

### 6.1 交付覆盖表（稳定表 1/2）

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-1 只有显式升级才创建工作 Issue | §6.1 FR-1：promotion 是唯一新增 Issue 写入路径（经 `createInTx`）；Discussion GET/发送/协办/merge-forward 零改动；AC-1 断言 | CR-2026-061-TASK-02 | cmd-01 | revert TASK-02 commit |
| FR-2 升级入口契约 | §3.1 端点 + §1.1 模块边界（router.go 注册）+ D-7（复用既有创建内核，无第二写入路径） | CR-2026-061-TASK-03（关联 TASK-02） | cmd-01 | revert TASK-03 commit |
| FR-3 来源选择校验 | §4.3 前置步骤 1/5/6（形状校验器 + `GetActiveProjectSharedSession` + `GetChatMessageInWorkspace` + `ListAttachmentsForPromotion`） | CR-2026-061-TASK-03（关联 TASK-02） | cmd-01 | revert TASK-03 commit |
| FR-4 创建 Issue 并写入来源引用 | §2.1 条目 schema + §4.3 创建分支（`AppendIssueContextRefs`）+ §4.6 默认标题/描述 | CR-2026-061-TASK-02（关联 TASK-01） | cmd-01 | revert TASK-02 commit |
| FR-5 原消息附件保持原归属 | §6.1 FR-5：promotion 事务对 chat_* 零写（AC-4 结构测试 grep 断言） | CR-2026-061-TASK-02 | cmd-01 | revert TASK-02 commit |
| FR-6 同源唯一（查重） | §4.1 dedupe_key + §4.2 查重 SQL + §4.3 步骤 7/10（项目级锁 + 507 GIN） | CR-2026-061-TASK-02（关联 TASK-01） | cmd-01 | revert TASK-02 commit（507 随 TASK-01 revert） |
| FR-7 幂等键（fingerprint 与重放） | §4.1 promotionFingerprint + §2.2 505 scope + §4.3 步骤 9 四分支（reservation/replay/takeover/409） | CR-2026-061-TASK-02（关联 TASK-01） | cmd-01 | revert TASK-02 + TASK-01（505） |
| FR-8 权限边界（固定顺序） | §4.3 前置 1–6 + 事务内成员复核 + D-6（容量双查 → 403 `forbidden_promotion`） | CR-2026-061-TASK-03（关联 TASK-02） | cmd-01 | revert TASK-03 commit |
| FR-9 可回溯来源 | §3.4 `IssueResponse.context_refs` 暴露（Go）+ 前端「来自 Discussion」来源入口 | CR-2026-061-TASK-04（关联 TASK-03） | cmd-03 | revert TASK-04 commit |
| FR-10 升级为 CR（预建 run，不写 CR 账本） | §2.3/§2.4 预建 run + 首节点 + §4.3 创建/补建分支 + 502 `pipeline_run_create_failed` 闭包 + 506 唯一语义 + AC-8/AC-13 | CR-2026-061-TASK-02（关联 TASK-01/TASK-03） | cmd-01 | revert TASK-02 commit（506 随 TASK-01 revert） |
| FR-11 前端交互 | §6.1 FR-11：discussion-pane 多选/两入口/结果链接/失败保留选择（复用 merge-forward 模式） | CR-2026-061-TASK-04 | cmd-03 | revert TASK-04 commit |
| FR-12 不新增 discussion_promotion 表 | §2.5/§2.6：仅 CHECK 扩展 + 2 索引；AC-10 断言 server/migrations/ 无该命名迁移 | CR-2026-061-TASK-01 | cmd-02 | revert TASK-01 commit（down 已登记） |
| FR-13 可区分错误与零残留 | §4.4 错误闭包表逐条实现（`writeErrorCode` `{code,error}`）+ 单事务整体回滚 | CR-2026-061-TASK-03（关联 TASK-02） | cmd-01 | revert TASK-03 commit |

### 6.2 证据命令表（稳定表 2/2）

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | multica | server | go | ["test", "-run", "^TestPromotion|^TestPromoteDiscussion|^TestPromoteProjectDiscussion|^TestBindPromotionRun|^TestValidatePromotionRequestShape|^TestParseIssueContextRefs|^TestCanonicalUUIDs|^TestSummarizePromotionContent|^TestBuildPromotionEntry|^TestCreateInTxPromotionRun", "./internal/handler/", "./internal/service/", "-count=1"] | 900 |
| cmd-02 | multica | server | go | ["test", "./internal/governance/", "./cmd/migrate/", "-count=1"] | 900 |
| cmd-03 | multica | packages/views | pnpm | ["test"] | 600 |
| cmd-04 | multica | packages/core | pnpm | ["test"] | 600 |
| cmd-05 | tools | . | node | ["--test", "--test-reporter=dot", "skills/requirement/requirement-register/scripts/test/promotion-bind.test.mjs"] | 300 |
| cmd-06 | tools | . | node | ["skills/shared/crctl/scripts/lint-prompts.mjs", "--mode", "enforce"] | 120 |

- `cmd-NN` 与 `crctl test` 机器区 `commands` 1-based 下标及 `test-evidence/cmd-NN.log` 全等；args 为 JSON token 数组（shell:false 直接 spawn）。
- **canonical 执行环境口径（write-test-report / `crctl test` 会话统一；环境变量不属于 commands 数组，不违反 cr-test-plan/v1 schema）**：会话环境导出 `DATABASE_URL`（dev 库，来自主克隆 `.env`，迁移 505–507 已应用）与 `GOFLAGS=-v`（逐条 RUN/PASS 可见，不改测试集合/断言/退出码）；`pnpm` 经 `pnpm.exe` shim 前置 PATH（Windows 只解析 .exe）。cmd-01/02 在 `DATABASE_URL` 下真库实跑，**B-CODE-01 回归测试在 canonical 引用日志中 PASS（非 SKIP）**。
- cmd-01 覆盖面（promotion 真库范围，`-run` 前缀精确过滤）：handler 8 项（`TestPromoteProjectDiscussion*`×3、`TestBindPromotionRun*`×3、`TestValidatePromotionRequestShape`、`TestParseIssueContextRefs`）+ service 13 项（`TestPromotion*`×5、`TestPromoteDiscussion*`×4、`TestCanonicalUUIDs`、`TestSummarizePromotionContent`、`TestBuildPromotionEntry`、`TestCreateInTxPromotionRun`）——AC-1~AC-8、AC-11 全链路：幂等四分支、查重补建、**B-CODE-01 异构 context_refs 回归（`TestPromoteDiscussionBackfillPreservesHeterogeneousContextRefs`，真库 PASS）**、错误矩阵、绑定端点、FR-5 结构断言、createInTx 失败注入零残留。上游既有失败 `TestLoadAgentSkills_*`（3 项，skill 表 13 列 vs 夹具 10 列）不在 promotion 面，被 `-run` 前缀排除，归因与基线见 CUSTOM.md《已知测试失败基线》。createInTx 提取的 zero_diff 回归（既有 `IssueService.Create` 调用方测试全绿）为实施期真库专项证据（已完成并登记 CUSTOM.md），不在 cmd-01 机器区。
- cmd-02 覆盖面：AC-13 投影复用集成断言（绑定后注入 requirement-reviewing/review 事件 → pipeline_run 行数不增、seq5/seq4 正常、seq1 保持 passed）+ 505/506/507 迁移与并发索引清理登记测试（AC-10）。
- cmd-03 覆盖面：discussion-pane 多选/两入口/失败保留（AC-9）、Issue 详情来源入口（AC-7 前端面）、四语文案 parity（AC-12）。
- cmd-04 覆盖面：`PromotionResultSchema`/`IssueSchema.context_refs` malformed-response 与 fallback（AC-7 client 面）。
- cmd-05 覆盖面：tools 侧 AC-13 消费契约（promotion 上下文存在 → `crctl register` 成功后调用 `multica cr bind-promotion-run` 绑定、幂等/失败语义；无上下文 → 普通注册不定位不绑定）。args 带 `--test-reporter=dot`：dot reporter 输出仅点号、无 `skipped` 摘要行，冻结 skip 模式表不再误命中 spec reporter 恒打印的 `ℹ skipped 0`（B-CODE-03 根因消除）——机器区 `skipped` 恒 false（除非确有真实 skip），AC-13 tools 消费面的 canonical 证据可被 review-code 只读机器区直接判定。
- cmd-06 覆盖面：requirement-register SKILL.md 改动通过 lint-prompts enforce（R1~R13 零 CONTRADICTS/STALE-REF）。

## 7. AC/业务闭环覆盖矩阵（契约必填，CR-2026-057 FR-8）

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-1 唯一创建路径 | §6.2 AC-1 | CR-2026-061-TASK-02 | cmd-01 |
| AC-2 选择矩阵与零写入 | §6.2 AC-2 | CR-2026-061-TASK-03 | cmd-01 |
| AC-3 来源引用与默认标题/描述 | §6.2 AC-3 | CR-2026-061-TASK-02 | cmd-01 |
| AC-4 原消息/附件全等 | §6.2 AC-4 | CR-2026-061-TASK-02 | cmd-01 |
| AC-5 幂等/查重/并发收敛 | §6.2 AC-5（缺 key/空 key/超长 key → 400 三码属 handler 面，关联 CR-2026-061-TASK-03） | CR-2026-061-TASK-02 | cmd-01 |
| AC-6 权限固定顺序 | §6.2 AC-6 | CR-2026-061-TASK-03 | cmd-01 |
| AC-7 前端来源入口（用户可观察面：详情展示并可跳回 Discussion） | §6.2 AC-7（唯一 owner 行；API 响应解析面关联 CR-2026-061-TASK-03，见下行业务闭环行） | CR-2026-061-TASK-04 | cmd-03 |
| 业务闭环：AC-7 API 响应解析面（issueToResponse 透出 context_refs） | §6.2 AC-7 / §3.4 | CR-2026-061-TASK-03 | cmd-01 |
| 业务闭环：AC-7 client schema 兼容面（fallback/malformed） | §3.4 | CR-2026-061-TASK-04 | cmd-04 |
| AC-8 预建 run 同事务/run_id/502 零残留/无 agent_task_queue | §6.2 AC-8 | CR-2026-061-TASK-02 | cmd-01 |
| AC-9 前端交互与失败保留 | §6.2 AC-9 | CR-2026-061-TASK-04 | cmd-03 |
| AC-10 无新表 | §6.2 AC-10 | CR-2026-061-TASK-01 | cmd-02 |
| AC-11 逐类失败零残留 + 原 key 重试 | §6.2 AC-11（前端按错误类型保留选择/提示重试子句关联 CR-2026-061-TASK-04，证据面 cmd-03） | CR-2026-061-TASK-03 | cmd-01 |
| AC-12 四语文案 parity + 旧容器不回归 | §6.2 AC-12 | CR-2026-061-TASK-04 | cmd-03 |
| AC-13 绑定端点错误矩阵/幂等/CAS/审计 + 绑定后投影复用同一 run 不新建（multica 面，唯一 owner 行） | §3.2/§4.5 | CR-2026-061-TASK-03 | cmd-01 / cmd-02 |
| 业务闭环：AC-13 tools 消费面（requirement-register 定位/绑定/失败语义/普通注册不变） | §3.3/§4.5（tools SKILL 增量，SDD §9 scope_in） | CR-2026-061-TASK-04 | cmd-05 |
| 业务闭环：promotion SKILL 改动不引入 crctl 命令面/prompt 漂移 | §8（Prompt 采纳影响不触发）+ lint-prompts | CR-2026-061-TASK-04 | cmd-06 |

> 关键 AC 唯一 owner 说明（CR-2026-057 FR-9，矩阵内机械可判）：
> - **AC-7 唯一 owner = CR-2026-061-TASK-04**（用户可观察面责任层：前端来源入口与可跳回，证据 cmd-03）；API 响应解析面（TASK-03，cmd-01）与 client schema 兼容面（TASK-04，cmd-04）为业务闭环行，不参与 AC-7 owner 判定。
> - **AC-13 唯一 owner = CR-2026-061-TASK-03**（multica 绑定端点 + 绑定后投影复用行为的实际产生层，证据 cmd-01 / cmd-02）；tools 消费面（TASK-04，cmd-05）与 prompt 漂移防护（TASK-04，cmd-06）为业务闭环行，不参与 AC-13 owner 判定。
> - 业务闭环行与关键 AC 行证据面不重叠（cmd-NN 分属），可分别机械核验。
> - **cmd-01 promotion 真库口径**：关键 AC 行引用的 cmd-01 现为 promotion 范围真库执行（21 项实跑 PASS、无 SKIP）；被排除的上游既有失败 `TestLoadAgentSkills_*` 不属于任何 AC 验收面（归因登记 CUSTOM.md）。
> - **cmd-05 skipped=false 保证**：`--test-reporter=dot` 使输出不含 `skipped` 字样，冻结模式表不再误命中（B-CODE-03 根因消除），机器区 `skipped` 恒 false。

## 8. 已审批 SDD 第 2 轮评审 3 条 suggestions 的处理口径（plan 层记录，不改 sdd.md）

sdd.md v1.1 已经评审（verdict=pass）与人工审批（approval.yml#tech-design），其 subject-sha256 已绑定评审证据与审批摘要。按协调要求**不静默改写已审批产物**：3 条 suggestions 一律在计划层记录处理口径，是否允许对 sdd.md 本体做后续合法修订由评审证据链（review-dev-plan / 未来 upstream blocker 通道）裁决。逐条处理如下：

| # | suggestion（canonical，review-annotations/sdd.yml） | 处理口径 | 证据一致性影响 |
|---|---|---|---|
| 1 | §12 #30/#31 首现顺序互换，§12 引言注明排序口径 | **保留理由（plan 层落实；理由文本经 review-dev-plan 第 1 轮更正）**：sdd.md v1.1 已经评审（verdict=pass）与人工审批（approval.yml#tech-design），**冻结不动**（subject-sha256 `310434e7…` 保持），§12 编号顺序不得由 plan 层静默改写。正文首现顺序事实以 SDD 原文为准：§4.5 违约后果推演（引用 456）先于 §4.6 默认描述（引用 chatMessageAuthorDisplayName），即 **#31 先于 #30**，原 suggestion 的顺位方向正确，仅因产物冻结无法执行。plan 锁定实施期事实引用顺序：#31（456 谓词）用于 §4.5 违约推演、#30 用于 §4.6 默认描述，实施按用途取用不按编号。若未来 SDD 经合法修订（如 dev-plan upstream blocker），可一并互换 #30/#31 并在 §12 引言加注「排序口径=正文首现顺序」 | 无功能影响；不触碰 subject-sha256。 |
| 2 | #24 `AllocateIssueNumber` 实际位于 issue_limit.go L87；#18 `loadIssueForUser` 实际位于 handler.go L1049 | **已处理（plan 层核实并锁定）**：本计划开工核实（multica `eafce66b`）：`AllocateIssueNumber` = `server/internal/service/issue_limit.go` **L87** ✓（与 suggestion 一致；SDD #24 括注「issue_limit 服务」本已消歧）；`loadIssueForUser` = `server/internal/handler/handler.go` L1049（`78e14082`）✓，新基线 `eafce66b` 处为 **L1053**。plan/TASK 实施期一律以修正后的位置标注为准（见 TASK-02/TASK-03 涉及文件） | 无功能影响；行号标注修正不改变结论。 |
| 3 | §9 zero_diff / D-1 引用符号未入 §12 | **已处理（plan 层补齐基线声明锚定）**：suggestion 自认「性质为基线声明而非设计依赖」。plan 在下方新增「zero_diff 基线锁定表」，把 §9 zero_diff 与 D-1 引用的既有符号逐项锚定 repo/path/symbol/SHA（`eafce66b`），达到「清单与正文一一对应」意图，且不动 sdd.md | 无功能影响；plan 层锚定表作为实施期 zero_diff 回归的核对清单。 |

**zero_diff 基线锁定表（plan 层，实施期与 review-code 核对）**：

| 符号/行为（SDD §9 zero_diff 与 D-1 引用） | repo | relative path / symbol | SHA（multica eafce66b 核实） |
|---|---|---|---|
| `IssueService.Create` 公开签名与行为 | multica | server/internal/service/issue.go | eafce66b1 |
| `sendProjectChatCore` / `MergeForwardDiscussion`（message/comment 双臂 + 幂等三事务） | multica | server/internal/service/project_chat.go + server/internal/handler/project_chat.go | eafce66b1 |
| `EnsureProjectDiscussionSession` / `EnsureProjectDiscussionIssue` / `GetProjectDiscussion` | multica | server/internal/service/project_chat.go / server/internal/handler/project_chat.go | eafce66b1 |
| `CreateIssue` HTTP 行为 | multica | server/internal/handler/issue.go | eafce66b1 |
| `chat_idempotency` 既有 scope 语义 + 24h 清理 + idempotency.sql 四查询签名 | multica | server/pkg/db/queries/idempotency.sql / server/internal/service/chat_idempotency_cleanup.go | eafce66b1 |
| 456/457 索引与 451 表结构 | multica | server/migrations/456_* / 457_* / 451_* | eafce66b1 |
| `findOrCreateRun`/`upsertNodeRunning`/`markNodePassed`/`applyReview` 投影 SQL 与语义 | multica | server/internal/governance/gate_projection.go | eafce66b1 |
| `bind-current-task` 端点/CLI/服务行为 | multica | server/internal/handler/cr_bind.go / server/internal/service/task.go / server/cmd/multica/cmd_cr.go | eafce66b1 |
| `LockIssueDuplicateKey` 原语与既有锁键字符串 | multica | server/pkg/db/queries/issue.sql | eafce66b1 |

（D-1 引用的 merge-forward 三事务内核 = `sendProjectChatCore` 自带事务不可包裹，已在表中；promotion 单事务决策依据不变。）

---

## 9. §6.2 修订记录（review-code B-CODE-02/03 修订链，plan-blocker 回退）

review-code 第 3 轮 BLOCK（B-CODE-02/03：canonical 测试证据问题，非源码缺陷；B-CODE-01 源码已闭合）→ Ray 批准①式治理修订链 → dev-agent 落 tools `dir-graph.yaml` 治理边 `{ from: developing, to: tech-design-reviewed, trigger: "review-code:plan-blocker -> write-dev-plan" }`（tools main `bef1f4d`，先例 `49c46dd` 同模式；已 merge 进 tools CR 分支 `30b49d2`）→ `crctl advance` 回 `tech-design-reviewed` → 本节修订。reviewLoop 记账：Ray 已在交互式终端执行两条 `review-loop reset`（review-code / write-test-report 均 cycle 1→2、attempt 0，审计 20:26）；`review-dev-plan` 仍 2/3（本轮评审为 attempt 3/3，无需 reset）。

| 变更 | 修订前 | 修订后 | 目的 |
|---|---|---|---|
| cmd-01 | 全包 `./internal/handler/ ./internal/service/`（无 DB） | `-run` promotion 前缀过滤（handler 8 + service 13，21 项），真库（DATABASE_URL） | B-CODE-02：新回归在 canonical 引用日志中 PASS；排除 3 项上游既有失败 |
| cmd-05 | spec reporter 恒打印 `ℹ skipped 0` 误命中冻结模式表 | args 加 `--test-reporter=dot` | B-CODE-03：机器区 `skipped=false` |
| §7 注记 | — | cmd-01 promotion 真库口径 / cmd-05 skipped 保证两条注记 | 证据链口径与命令表一致 |

修订后执行口径：Ray 重新 `crctl approve --stage dev-start`（交互式终端）→ `crctl test --plan` 重跑（write-test-report cycle 2）→ 新 cycle `review-code`。§6.2 命令表本体变更即本次评审对象，review-dev-plan 以本表为准。

---

## 附：TASK 拆分预分配（write-dev-tasks 的输入，共 4 个，组映射 1:1）

| 变更组 | TASK id | 仓库 | 粒度 | 依赖 |
|---|---|---|---|---|
| G1 数据层与迁移 | CR-2026-061-TASK-01 | multica | 1.5 天 | — |
| G2 服务内核 | CR-2026-061-TASK-02 | multica | 3 天 | TASK-01 |
| G3 HTTP/绑定/CLI | CR-2026-061-TASK-03 | multica | 2.5 天 | TASK-02 |
| G4 前端 + tools 协同 | CR-2026-061-TASK-04 | multica + tools | 2 天 | TASK-03 |

每个 in-scope FR 的主责 TASK 唯一（§6.1），关联 TASK 不改变主责；TASK 卡的接口契约逐字对齐 SDD 签名（详见 write-dev-tasks 产物）。

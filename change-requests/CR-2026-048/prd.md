---
id: CR-2026-048-prd
type: PRD
cr-ref: CR-2026-048
title: P3 组织智能 · 内部 Skill Market
target-version: 0.22
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-20T11:57:07+08:00
updated: 2026-08-20T12:37:55+08:00
---

# PRD — P3 组织智能 · 内部 Skill Market

> 依据：`docs/product/P3-组织智能设计.md` §3（内部 Skill Market）、§5.1 CR-B、§5.2 E6、§7（2026-08-19 第二轮评审 23 项决议）；`docs/analysis/P3组织智能-开工前代码核对评审.md`（评审方法与证据链）。
> 本 CR 与 CR-2026-047（CR-A，成熟度看板）**零交集、可真并行**：B 动 `skill` 表与 Market 前端，A 动 `maturity_snapshot` 与看板，无共享表、无共享端点。

## 1. 概述

### 1.1 问题陈述

个人沉淀的工作方法目前停留在两个地方：一是各自机器上的私有 SKILL.md，二是口口相传。平台已有 `skill` / `skill_file` 表并兼容 Anthropic Agent Skills 标准；当前按 `tools/skills/_index.yml` 的 active 条目核对为 **56 个**内置方法论 Skill（P3 §3.1/§3.3 中的“59”是待回写的陈旧数字，不作为本 CR 验收口径），但**缺三样东西**，导致资产无法在组织内流通：

1. **没有可见性概念**——Skill 要么是某人的，要么是内置的，没有"我发布给团队用"这个动作，因此也没有"发布即授权"的语义边界；
2. **不知道什么被用了**——没有任何地方记录"哪个任务用了哪些 Skill"，于是无法回答"沉淀有没有被扩散"（P3 §1.2 资产复用率的数据源缺失），也无法给出使用量排行；
3. **复用者拿不到使用说明**——`ParseSkillFrontmatter` 只提取 `name` 与 `description` 两个字段，一个 Skill 适用什么场景、依赖什么上下文、能读写哪些目录、失败了怎么办，全靠读正文或问作者。

同时存在一条隐私风险：如果把"发布"做成简单的可见性翻转，作者机器上的 API Key、内网凭据、个人路径会随 SKILL.md 一起进入组织视野。

### 1.2 解决方案摘要

把个人 Skill 到组织资产的流通面补齐，**增量收敛为三块**：`skill` 表加三列、新增一张 append-only 遥测表、发布路径加一道门禁。四条设计取向：

- **可见性只有两档**（`private` / `org`）——内部平台没有"公开发布"这一档；
- **遥测采集点在服务端任务认领路径**，不新增任何跨进程字段；
- **敏感扫描复用既有 `redact` 包的同一份正则表**，只加一个定位入口与一条新模式；
- **`version` 只是展示字段**，"内容是否变了"一律用既有的内容哈希判定。

### 1.3 已解决基础设施（本次直接复用，不重新设计）

| 能力 | 现成件 | 本次用法 |
|---|---|---|
| Skill 存储与文件 | `skill` / `skill_file` 表（`server/migrations/008_structured_skills.up.sql`，`UNIQUE(workspace_id,name)` / `UNIQUE(skill_id,path)`） | 只加列，不重建 |
| 内容身份 | `pkg/skillbundle.BuildManifest(skill).Hash`（`handler/daemon.go:3382` 已用它判定包变更） | 一切"内容是否变化"判定的唯一依据 |
| 内置 Skill 标识 | `service/task.go:5840 BuildAgentSkillBundles`，对 `id == ""` 现场合成 `"builtin:" + Name`（`skillbundle.SourceBuiltin`） | 遥测的 `skill_ref` 直接沿用该合成 id |
| 权威 Skill 清单 | `handler/daemon.go:1982-2070`：服务端在任务认领时算出 `[]AgentSkillRefData{ID,Source,Name,Hash,…}` 并发给 daemon（当前未持久化，:3308 那次 marshal 仅用于日志字节数统计） | 遥测采集点，零新增探针 |
| 密钥检测 | `server/pkg/redact`：16 条 patterns（AWS / GitHub PAT 两形制 / OpenAI `sk-` / Slack 两形制 / GitLab / Google / Stripe / JWT / Bearer / PEM / 连接串嵌密码 / 通用 `KEY=VALUE`）+ `Text()` / `InputMap()` | 敏感扫描复用同一份 `patterns` |
| frontmatter 解析 | `internal/skill/frontmatter.go:27 ParseSkillFrontmatter`（CRLF 容错，仅返回 name/description） | 扩展提取范围，不另写解析器 |
| 审计留痕 | `activity_log` + `internal/governance/audit.go` 的封闭 action 白名单模式（`auditActions`，防伪造） | 放行记录沿用该模式加一个 action 值 |
| 权限判定 | `handler/skill.go:406 canManageSkill`（workspace owner/admin 或 creator） | 发布权限在其基础上判定，不另建角色体系 |
| 前端 | `packages/views/skills/`（components / hooks / lib 已在位） | Market 列表与详情页在该域内扩展 |

**明确不重建的三样**：不新建事务/队列/outbox 抽象（仓内已有三套可用机制）；不新建 Skill 内容哈希；不新建密钥正则表。

### 1.4 模块职责边界

| 层 | 职责 | 不做 |
|---|---|---|
| 迁移（`server/migrations/`，编号从 **380** 起） | 加三列 + 建遥测表 + 索引 | 不加 FK、不加级联 |
| 认领路径（`handler/daemon.go`） | 算出 skillRefs 后写遥测行 | 不改 `TaskCompleteRequest`、不碰 `sanitizeTaskCompleteRequest` |
| 发布路径（`handler/skill*.go`） | 门禁校验 + 敏感扫描 + 可见性翻转 | 不实现"公开发布"档、不为 builtin 写特判分支 |
| `pkg/redact` | 新增 `Findings()` 定位入口 + 第 17 条模式 | 不新增第二份 patterns |
| 前端（`packages/views/skills/`） | 列表 / 排行 / 详情页使用说明卡 / 发布确认框 | 不开新的写通路 |

## 2. 用户故事

- **US-1**（Skill 作者）：作为把某个工作方法打磨成熟的开发者，我希望把私有 Skill 发布给组织，并在发布时清楚看到"这等于授权团队复用我的工作方法"，这样沉淀才有意义而不只是躺在我机器上。
- **US-2**（Skill 作者）：作为发布者，我希望平台在发布前拦住我 SKILL.md 里可能残留的密钥与个人路径，并告诉我第几行命中了什么，这样我不必靠自己逐行检查来保证不泄漏。
- **US-3**（复用者）：作为想用别人 Skill 的工程师，我希望在详情页直接看到它适用什么场景、依赖什么上下文、能读写哪些目录、失败了找谁，这样我不用去问作者或读全文。
- **US-4**（Owner / 管理者）：作为组织 Owner，我希望看到哪些 Skill 真的被使用、被谁使用，这样"沉淀有没有被扩散"是有数据的，而不是靠感觉。
- **US-5**（Owner）：作为处理误报申诉的 Owner，我希望逐条确认放行且每次放行都留痕，这样"拦截是默认、放行是例外"这条边界可审计。

## 3. 功能需求

### 数据面

- **FR-1**：`skill` 表新增三列：`visibility TEXT NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','org'))`、`version TEXT NOT NULL DEFAULT '0.1.0'`、`owner_actor TEXT`。**不得包含 `builtin` 枚举值**——内置 Skill 在 `skill` 表里没有行（`service/task.go:5851`），给不存在的行加枚举值是死代码。
- **FR-2**：新增 `skill_usage_event` 表：`id UUID PRIMARY KEY DEFAULT gen_random_uuid()`、`skill_ref TEXT NOT NULL`、`task_id UUID`、`project_id UUID`、`used_at TIMESTAMPTZ NOT NULL DEFAULT now()`。**`task_id` 与 `skill_ref` 均不得设外键**：仓硬规则禁新增 FK 与级联，且遥测本质是 append-only 审计行，指向已删除 Skill 的历史行应当保留。为支持完成任务过滤与排行聚合，新增 `(task_id)` 与 `(skill_ref, used_at)` 两个索引；每个索引各自放在独立迁移文件中。
- **FR-3**：`skill_ref` 取值两形制——workspace Skill 为其 `skill.id` 的文本形式，内置 Skill 为 `"builtin:" + Name`（沿用 `BuildAgentSkillBundles` 的合成规则，不另定义）。
- **FR-4**：`version` 为**纯展示字段**。任何"内容是否发生变化"的判定必须使用 `skillbundle.BuildManifest(skill).Hash`；**禁止以比较 `version` 值作为内容变更依据**。workspace Skill 的创建、编辑与详情响应可读写/展示该字段；更新版本号本身不触发内容变更判定，也不改变历史遥测事件的 `skill_ref`。

### 遥测采集

- **FR-5**：在服务端任务认领路径（`handler/daemon.go` 的 `useSkillRefs` 分支，即已算出 `skillRefs` 之后）为每个 ref 写一行 `skill_usage_event`。写入失败不得阻断任务认领（遥测是观测面，不是门禁），失败记日志。允许同一任务多次 claim 产生多行 append-only 事件；任务 claim 路径写入的 `task_id` 必须对应当前任务。
- **FR-6**：**`TaskCompleteRequest` 与 `sanitizeTaskCompleteRequest` 零改动**，禁止新增 `skills_used[]` 或任何等价字段。理由：该 sanitize 函数注释明写漏加字段会重现 GH #7098（NUL 字节 → SQLSTATE 22P05 → 任务永久卡在 `running`）。
- **FR-7**：`used_at` 的语义是"**派发时物化**"而非"完成时使用"，该语义必须写入指标定义页与 `skill_usage_event` 的表注释。所有使用量/复用率排行查询必须 join `agent_task_queue`，显式带 `agent_task_queue.status = 'completed'`，并按 `(task_id, skill_ref)` 去重计数；同一任务重试后最终完成只计一次，重试后最终失败计零。原始事件行仍可用于诊断，不得把原始行数直接当作使用次数。

### 发布门禁

- **FR-8**：`private → org` 的发布动作触发服务端校验，任一项不通过即拒绝发布并返回结构化错误码与失败原因，不做部分放行；所有校验通过时才原子地完成可见性更新。
- **FR-9**：校验项一——`name` 与 `description` frontmatter 必填；缺失任一字段必须返回对应结构化错误码。
- **FR-10**：校验项二——org 可见的 Skill 必须指定**一个且仅一个非空** `owner_actor`；无 owner 或 owner 值不唯一的发布被拒。这里的“唯一”指每个 Skill 只有一个负责人身份，不要求全组织 owner_actor 全局唯一。
- **FR-11**：校验项三——**资产元数据卡四字段必填**：`applicable-scenarios`（适用什么场景）、`context-dependencies`（依赖什么上下文）、`permission-declaration`（能读写哪些目录）、`failure-handling`（失败后怎么办）。缺任一字段发布被拒，错误指出字段名。
- **FR-12**：校验项四——SKILL.md 通过 `validate-doc` 结构校验（daemon 侧执行）；校验失败不得改变 visibility。
- **FR-13**：`permission-declaration` 中声明了 P1 `rules.json#protectedPaths` 内路径的，发布响应和详情页给出**警告**（不阻断、不改写声明）；警告必须可被验收测试读取。
- **FR-14**：**不得为"builtin 不可编辑"编写任何特判分支**——该性质由"内置 Skill 不入 `skill` 表"天然成立。新增 `is_builtin` 类判断字段或分支视为违反本条。

### 敏感信息扫描

- **FR-15**：在 `server/pkg/redact` 新增 `Findings(s string) []Finding` 入口，`Finding` 至少含命中模式标识、行号、片段摘要。该函数**必须与 `Text()` 共用同一个 `patterns` 变量**；新增回归测试断言包内只存在一份 patterns 定义，防止日后平行出第二份。
- **FR-16**：在既有 16 条模式上新增第 17 条**个人路径模式**（覆盖 `/Users/<name>`、`C:\Users\<name>`、`/home/<name>` 三形制）。
- **FR-17**：发布校验时对 SKILL.md 正文与该 Skill 的全部 `skill_file` 内容执行扫描；**命中即拦截**，并向作者返回每一处命中的位置（文件 + 行号 + 模式标识）。
- **FR-18**：作者可对某个命中项提交误报申诉；申诉以 `appeal_id = hash(skill_ref, content_hash, file, line, pattern_id)` 绑定当前内容与精确命中项，Owner 才能逐条确认放行，不支持批量一键放行。使用既有 `activity_log` 作为 append-only 状态账本：提交、确认、拒绝均写入封闭 action；同一 `appeal_id` 的重复提交/重复决定幂等；内容哈希变化后旧放行自动失效，不能绕过新内容扫描。每次放行含放行人、时间、Skill、内容哈希与命中项标识，且 action 值须加入 `governance/audit.go` 风格的封闭白名单，防伪造。

### 前端

- **FR-19**：Market 列表展示作者、版本、使用量排行；workspace Skill 的排行由 `skill_usage_event` 聚合，按已完成任务的 `(task_id, skill_ref)` 去重，内置 Skill 也必须能上榜（其 `skill_ref` 为 `builtin:<name>`）。workspace Skill 展示其 `version`，builtin 展示 tools 包版本/ builtin 标识，不为 builtin 伪造 `skill` 行。
- **FR-20**：详情页把**org 可见 workspace Skill** 的元数据卡四字段渲染为"使用说明卡"；builtin Skill 的元数据卡补齐属于 tools 包基线，不作为本 CR 的发布门禁或新增数据库字段。
- **FR-21**：详情页展示运行时要求标签（该 Skill 需要哪些本机 CLI / 网络 / TTY），从 SKILL.md 既有前置要求按确定性规则半自动提取；无法识别的要求不阻断详情页，显示原文/不生成错误标签。
- **FR-22**：发布确认框明示"发布 = 授权团队复用该工作方法"。
- **FR-23**：带 `source: session-export` 标记的草稿在列表中可筛选；该 marker 从 SKILL.md frontmatter 解析读取，不新增 `skill` 表列，列表筛选与详情显示使用同一解析结果。

## 4. 非功能需求

- **NFR-1（迁移合规）**：新增迁移编号从 **380** 起（CR-2026-047 已占用 375–379）；每个索引必须 `CREATE INDEX CONCURRENTLY`，且**一个迁移文件只含一条索引语句**；up / down 成对。
- **NFR-2（无外键）**：本 CR 不得新增任何 `FOREIGN KEY` / `REFERENCES` / 级联删改；关系与依赖清理在应用层解决。
- **NFR-3（性能）**：遥测写入在任务认领路径上，单任务新增写入量与其 Skill 数同阶（典型 < 10 行），不得引入额外往返或阻塞认领；排行查询走 `skill_ref, used_at` 索引，完成任务过滤走 `task_id` 索引，查询计划不得退化为对遥测表的无约束全表扫描。验收使用固定 fixture 与 `EXPLAIN (FORMAT JSON)` 检查索引条件/扫描范围；不得以小表偶然选择 seq scan 作为唯一证据。
- **NFR-4（安全）**：敏感扫描是发布路径的**默认拦截**而非提示；放行必须留痕。扫描结果中回传给前端的片段摘要不得包含命中的密钥明文。
- **NFR-5（兼容性）**：三列均有默认值，存量 Skill 迁移后自动为 `private` / `0.1.0` / `NULL`，不影响既有 Skill 的使用与 daemon 侧物化；`TaskCompleteRequest` 契约不变，旧版 daemon 无需升级。
- **NFR-6（仓规约）**：multica 仓代码注释一律英文；自研代码带 `// AIFIRST:` 标记（`.sql` 用 `-- AIFIRST:`）；全部改动登记 `../multica/CUSTOM.md`。

## 5. 验收标准

- **AC-1**（对 FR-1/FR-2/NFR-1/NFR-2）：迁移应用后 `skill` 表含三列且 `visibility` 的 CHECK **只有 `private` 与 `org` 两值**；`skill_usage_event` 表存在且 `information_schema` 查不到本 CR 新增的任何外键约束；新增 `(task_id)` 与 `(skill_ref, used_at)` 索引各在独立迁移文件中，所有新增索引语句均为 `CONCURRENTLY`。
- **AC-2**（对 FR-4）：修改一个 Skill 的内容但不改 `version`，系统仍能判定内容已变（`BuildManifest().Hash` 变化）；改 `version` 但不改内容，判定为内容未变；版本更新在列表/详情可见。
- **AC-3**（对 FR-3/FR-5/FR-19）：派发一个使用了 1 个 workspace Skill 与 1 个内置 Skill 的任务，`skill_usage_event` 新增两行，`skill_ref` 分别为该 Skill 的 uuid 文本与 `builtin:<name>`；Market 排行页两者均可见，且显示的 workspace 使用量为 1。
- **AC-4**（对 FR-6）：本 CR 的 diff 中 `TaskCompleteRequest` 结构体与 `sanitizeTaskCompleteRequest` 函数**零改动**（评审以 diff 为证）。
- **AC-5**（对 FR-7）：同一任务对同一 Skill 先后 claim 两次后最终 `completed`，遥测表有两行但使用量只计 1；另一任务反复重试后最终失败，遥测行不计入使用量；所有相关查询都带 `status='completed'`、按 `(task_id, skill_ref)` 去重，表注释含"派发时物化"语义说明。
- **AC-6**（对 FR-8/FR-9）：name 或 description 任一缺失时 org 发布返回对应结构化错误且 visibility 保持 private；四项校验全部通过时才完成一次性 private→org 更新，失败不能部分更新。
- **AC-7**（对 FR-10/FR-11）：未指定唯一 owner_actor，或缺少元数据卡四字段中任意一个的 Skill 执行 org 发布被拒，错误信息指出缺失/非法字段；通过后详情页显示四字段。
- **AC-8**（对 FR-12/FR-13）：validate-doc 失败时 org 发布被拒且 visibility 不变；protectedPaths 命中时发布成功但响应/详情含可读警告，警告不改变 permission-declaration。
- **AC-9**（对 FR-14）：代码中不存在针对 builtin 的可编辑性特判分支；尝试编辑内置 Skill 时因其在 `skill` 表中无对应行而自然失败。
- **AC-10**（对 FR-15/FR-16/FR-17/NFR-4）：含 `ghp_` 形制 token 与含 `C:\Users\<name>` 路径的 SKILL.md 发布均被拦截，且返回结果**指出命中的文件与行号**；返回内容不含密钥明文；`redact` 包内 `patterns` 定义只有一处（回归测试断言通过）。
- **AC-11**（对 FR-18）：作者提交一个命中项申诉后，非 Owner 决定被拒；Owner 对该 `appeal_id` 逐条确认放行后，`activity_log` 出现提交与放行记录（含放行人 / 时间 / Skill / 内容哈希 / 命中项标识）；重复提交/重复决定不产生重复效果；改变 Skill 内容后旧 appeal 不能绕过扫描。
- **AC-12**（对 FR-19/FR-20/FR-21/FR-22）：详情页对 org workspace Skill 渲染四字段使用说明卡、可识别的运行时要求标签与版本；builtin 可进入排行但不生成 skill 行；发布确认框文案含"发布 = 授权"语义。
- **AC-13**（对 FR-23）：带 `source: session-export` 的 SKILL.md 出现在 session-export 筛选结果中，不带该 marker 的不出现；列表和详情使用同一 frontmatter 解析结果且数据库 schema 无新增 source 列。
- **AC-14**（对 NFR-3）：迁移生成 `(task_id)` 与 `(skill_ref, used_at)` 两个索引，分别位于独立迁移文件且 up/down 均使用 `CONCURRENTLY`；固定 fixture 的 `EXPLAIN (FORMAT JSON)` 证明完成任务过滤和排行使用相应索引条件。
- **AC-15**（对 NFR-5）：迁移应用于含存量 Skill 的库后，既有 Skill 全部为 `private`，daemon 侧任务物化行为无变化。
- **AC-16**（对 NFR-6）：`../multica/CUSTOM.md` 已登记本 CR 全部改动；新增 Go / SQL 文件注释为英文并带 `AIFIRST:` 标记。

## 6. 成功指标

上线后按 P3 §1.2 SII 维度与 Market 自身数据观测（口径与观察期规则以 P3 §1.2 为准）：

1. **资产被扩散而非被囤积**——org 可见 Skill 中"被他人发起的任务使用过至少一次"的占比（只发不被用不算数）；
2. **复用者不再靠口口相传**——org 发布的 Skill 100% 具备完整元数据卡（由 FR-11 门禁保证，观测的是它是否造成大量发布失败重试，即门槛是否过高）；
3. **隐私边界有效且不扰民**——敏感扫描的拦截数与其中经申诉放行的比例；放行占比长期偏高说明模式误报率需要调整，而不是把门禁放松；
4. **内置方法论的真实使用分布**——使用量排行覆盖 tools 包 `skills/_index.yml` 当前 `status: active` 的全部 builtin Skill；基线数量在上线时由该索引记录，不把 P3 正文中的旧数字作为固定验收值。

## 7. 范围排除

- **不做"公开发布"档**——内部平台只有 `private` / `org` 两档（P3 §3.2）。
- **不做 Skill 的付费 / 积分机制**——内部资产，流通靠可见性与排行即可（P3 §6）。
- **不做资产复用率指标本身**——该子指标属 CR-D（P3 §1.2 注、§5.1）；本 CR 只交付其数据源 `skill_usage_event`。
- **不做会话导出为 Skill 草稿的生成链路**——该链路在 P2 §7；本 CR 只保证带 `source: session-export` 标记的草稿在 Market 列表可筛（FR-23）。
- **不做 builtin Skill 元数据卡四字段的补齐**——该工作在 tools 包内一次性完成（P3 §3.3），不属本 CR。
- **不改上游 `task_usage*` 系列表**——与本 CR 无关。
- **不新建任何事务 / 队列 / outbox 抽象**——仓内已有 crctl 文件 outbox + `cr_sync_event` 幂等账本、`webhook_delivery` 租约投递、`agent_task_queue` 的 `FOR UPDATE SKIP LOCKED` 三套机制（P3 §6）。

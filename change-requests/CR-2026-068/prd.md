---
id: CR-2026-068-prd
type: PRD
cr-ref: CR-2026-068
title: CR-P2：plan/TASK 返工成本与执行前提
target-version: 0.41
owner: Ray
owner-role: requirement
status: draft
created: 2026-09-15T20:30:00+08:00
updated: 2026-09-15T20:30:00+08:00
---

# 1. 概述

## 1.1 问题陈述

需求来源是 Issue AIFI-31 附件《AIFI-18_SDD到planTASK_原位修订方案.md》（33,478 B，附件 id `01a0a47b-3088-760a-b307-bcf076426c31`）第 6 节「CR-P2：plan/TASK 返工成本与执行前提」（含 §6.1–§6.7 与边界段落；KB 内同文路径 `docs/analysis/AIFI-18_SDD到planTASK_原位修订方案.md`，与附件逐字节一致，已 cmp 核实，见 §1.4 事实 21）。基线：tools main 已合并 CR-2026-063(CR-P0) / 064(CR-R) / 065(CR-S) / 066(CR-P3) / 067(CR-P1)，全部 `archived`。该节钉出四类问题，全部是**合同缺可判定承载体**，不是「执行不认真」：

1. **upstream 返工把增量当整轮**：`write-dev-plan/SKILL.md#Step 2a` 回修模式只定义普通轨（逐条消费 review-dev-plan canonical blockers）；upstream SDD 重新批准后（`review-dev-plan:upstream-design-blocker` → 人工修订 → 重新评审与审批 → pipeline 重放 `write-dev-plan→write-dev-tasks→review-dev-plan`），没有任何文字定义「以新旧批准 SDD 的变更 delta 为输入的增量回修」——coordinator 只能把现有 plan/TASK 当作整轮作废并全量重建（来源 §6.1「原文问题」）。这是 AIFI-18 实测中返工成本被放大的第一形态。
2. **TASK 层现行文字与增量语义直接矛盾**：`write-dev-tasks/SKILL.md#Step 2a` 现写作「逐条消费 blockers，**重新生成** TASK 卡并调用 `crctl task init` 刷新 `_index.yml`；不保留已被评审判废/删除的旧 TASK」（§1.4 事实 6）——即使 plan 只做 delta 修订，TASK 层仍被要求全量重建；同时「只修 plan、让旧 TASK 留给下一轮评审发现」的形态也无人禁止（来源 §6.2「必须原位改写的相反现行文字」）。
3. **证据命令的观测面缺可判据**：`write-dev-plan` 两张稳定表说明只有一条概括性反假绿句（「该命令必须实际覆盖本行所声称的验收面，不得只覆盖其中一部分造成假绿」，§1.4 事实 4），没有可判定口径——`--list` 不能证明浏览器行为、文件级 `--name-only` 不能证明符号级不变量、子集测试不能声称全量、涉 Git 命令应走受控入口；`review-dev-plan` 的 `acceptance-verifiability` 增量维度只写「核对 TASK 验收步骤是否在真实责任边界组合证明 AC，拒绝无关依赖的假绿短路」（§1.4 事实 9），「观测面窄于声称面」「命令形态越受控边界」均无 blocker 判定——假绿命令与越界命令被留到 implement 阶段才暴露（来源 §6.3）。
4. **环境前提缺位、动态健康被写成人工长期事实**：plan 的「验收与发布策略」章节说明只有「发布前 checklist / feature-flag 计划」（§1.4 事实 2），没有环境 owner、建立方式、可获得性、readiness 证据与缺失处置；dev-start 人工审批提示（`code-implementation.pipeline.json` 节点 `…0004`）只确认任务拆分完成（§1.4 事实 12）；`implement-code` 环境节写「任务开始时只做一次有界前提检查」（§1.4 事实 18），没有「在第一个依赖环境的 TASK 前执行 plan 指定的 readiness `cmd-NN`」的即时性约束。结果：环境缺位要么在 implement 深处才以 `ENVIRONMENT_MISMATCH` 暴露，要么被错误地要求在人工审批时全部在线——把动态健康状态写成人工长期事实（来源 §6.5）。

**根因结论（来源 §6 与 §7，本 PRD 采纳）**：四项的共同根因是 plan/TASK 写作合同缺三个可判定承载体——**delta 语义**（upstream 增量回修 + TASK 依赖闭包重算）、**观测面判据**（证据命令证明力）、**环境前提的静态声明 + 即时验证**（plan 声明 / dev-start 静态确认 / implement 即时 readiness）。crctl 状态机、reviewLoop、两张稳定表双向唯一映射、`ENVIRONMENT_MISMATCH`、结构化 `recovery`、`suite-gate` 真门禁等基础设施全部已就位（来源 §7「继续复用、不再造」）。因此本 CR 的全部杠杆是**原位改四份 Skill 的既有段落 + 一处 pipeline 人工审批提示文本**，零新增结构承载（§6.6/§6.7）。

## 1.2 解决方案摘要

按来源 §6.1–§6.5 逐条落地（每组锚定「仓 + 文件 + 既有段落」，见 §1.3.1 与 §3 各 FR）：

1. **upstream 后 plan 增量回修**（FR-1）：`write-dev-plan/SKILL.md#Step 2a` 原位扩写——普通轨语义保留；新增 upstream 轨：upstream SDD 重新批准后，以**新旧批准 SDD 的变更 delta** 与**同轮未闭合 plan blockers** 为输入，在**同一份 plan** 上只重算受影响章节、稳定表行、证据与回滚，未受影响内容保留；coordinator 只传 subject / delta / canonical feedback 引用，不指定具体行如何修改。不改 review-route 枚举、不把 repair-target 改成多值。
2. **TASK 及依赖闭包重算**（FR-2）：`write-dev-tasks/SKILL.md#Step 2a` 的「重新生成」段**在该段内原位改写**为 delta 重算 + 依赖闭包同步 + 未受影响 TASK 保留，`crctl task init` 只用于刷新 `_index.yml` 索引；节点层零改动（12 节点、`…0001→…0002` 顺序、replayNodes 条目全保持；`purpose: regenerate-tasks` 是标签，其 delta 重算语义只在 SKILL 正文内明确）。
3. **证据命令的可执行性与证明力**（FR-3）：`write-dev-plan` 两张稳定表说明原位加入观测面判据（每个 `cmd-NN` 必须能观测该表行声称的 AC 结果；`--list` 不能证明浏览器行为；文件级 `--name-only` 不能证明符号级不变量；子集测试不能声称全量；涉 Git 命令用 `rules.json` 已允许的受控入口；不再通过委派评论补写命令算法）；`review-dev-plan` 既有 `acceptance-verifiability` 维度原位加入同一判据：观测面窄于声称面即 blocker、命令形态越受控边界即 blocker。
4. **回滚单元是依赖闭包**（FR-4）：`write-dev-plan` 交付覆盖表既有 `回滚` bullet 原位明确：被其它 TASK 消费的共享改动，其回滚单元必须包含受影响下游消费者并与风险节逆拓扑顺序一致；单点 revert 会破坏下游时不得声明为单点回滚。
5. **环境责任与即时 readiness**（FR-5，三侧）：plan 侧在既有「验收与发布策略」章节项（不新增第八节）原位扩写——证据依赖常驻服务/浏览器/数据库时必须写明环境 owner、建立方式、可获得性、readiness 证据（**必须复用该环境所保障的那一行 FR 的既有 `cmd-NN`**，不破坏两张稳定表双向唯一映射；确实无法复用时另立 CR，本 CR 不放宽该映射）与缺失时 `ENVIRONMENT_MISMATCH` 处置引用；dev-start 侧把 `code-implementation.pipeline.json` 节点 `…0004` 既有 approvalPrompt 原位改为只确认 owner、建立方式和可获得性（静态前提），不要求审批时所有服务在线；implement 侧在 `implement-code/SKILL.md` 既有环境节原位加入：在第一个依赖环境的 TASK 前执行 plan 指定的 readiness `cmd-NN`，失败按既有 `ENVIRONMENT_MISMATCH` 中止并报告建立动作，环境无关 TASK 不被提前阻断。
6. **零新增边界**（FR-6）：不新增 Pipeline 环境节点（节点数保持 5/4/12）、不改 review-route 枚举与 replayNodes、不改 upstream attempts 账本（来源 §6.6：不把 upstream block 追加到 `attempts[]`、不新增 review-events、不改 traceability schema、不做聚合指标）、不新增账本字段/评审维度/观测指标；`suite-gate --run` 全量绿、`gate-registry.json#manifest.cases` 与实际一致、零新例外。

## 1.3 已拍板范围（采纳 cr.md summary，不重新定义）

降低 upstream 返工成本并提前声明执行前提：upstream SDD 重新批准后 write-dev-plan 以新旧 SDD delta 与同轮未闭合 plan blockers 为输入，在同一份 plan 上只重算受影响章节、稳定表行、证据与回滚（未受影响内容保留）；write-dev-tasks 的『重新生成』原位改写为 delta 重算 + 依赖闭包同步 + 未受影响 TASK 保留；证据命令必须可执行且观测面覆盖 AC 声称面；回滚单元必须包含受影响下游依赖闭包；plan 侧声明环境 owner、建立方式、可获得性与 readiness（复用既有 cmd-NN，不破坏两张稳定表双向唯一映射），dev-start 只确认静态前提，implement 侧在首个环境依赖 TASK 前执行即时 readiness。不新增 Pipeline 环境节点（节点数保持 5/4/12）、不改 review-route 枚举与 replayNodes、不改 upstream attempts 账本、不新增账本字段、评审维度或观测指标。

### 1.3.1 scope_in 边界（原文前缀，评审核对用）

> CR-P2 只动 Step 2.x 评审判据与 plan/TASK 写作合同：upstream 增量回修、TASK 依赖闭包重算、证据证明力、环境责任与即时 preflight；明确不负责新 Pipeline 环境节点、动态环境人工门禁、评审观测指标。

（该边界来自来源 §2 的 CR-P2 行与 §6 边界段落；与已归档 CR 的块级不重叠约束见 FR-6 与 AC-8。）

逐条落到「哪个仓的哪个文件、改哪一段」（基线行号与证据见 §1.4）：

| # | 仓 | 文件 | 修订类型（原位） |
|---|---|---|---|
| 1 | `../tools` | `skills/develop/write-dev-plan/SKILL.md` | Step 2a 原位扩写 upstream delta 回修轨；两张稳定表说明加观测面判据；交付覆盖表 `回滚` bullet 加依赖闭包判据；「验收与发布策略」章节项（plan.md 第 5 章说明）加环境责任声明五要素（不新增第八节） |
| 2 | `../tools` | `skills/develop/write-dev-tasks/SKILL.md` | Step 2a 第 1 条的「重新生成」段原位改写为 delta 重算 + 依赖闭包同步 + 未受影响 TASK 保留（`crctl task init` 只用于刷新索引） |
| 3 | `../tools` | `skills/develop/review-dev-plan/SKILL.md` | 既有 `acceptance-verifiability` 增量维度原位加入观测面 / 受控边界 blocker 判据 |
| 4 | `../tools` | `pipeline-templates/code-implementation.pipeline.json` | 节点 `…0004`（确认进入代码开发）approvalPrompt 原位改写：加环境静态前提确认（owner / 建立方式 / 可获得性），保留结构化决定，不含 `git` / `journal` / `review-annotations` / `reject_reason` |
| 5 | `../tools` | `skills/develop/implement-code/SKILL.md` | 既有「环境验证与 ENVIRONMENT_MISMATCH」节原位加入：首个环境依赖 TASK 前执行 plan 指定 readiness `cmd-NN`、失败按既有标签中止、环境无关 TASK 不提前阻断 |

**本 CR 明确零 diff 的面**（评审核对清单）：`skills/shared/crctl/scripts/**`（含全部测试与 `gate-registry.json`——本 CR 预期零测试改动，见 §1.5 第 2 条）；`skills/develop/{write-tech-design,review-tech-design,review-code,write-test-report,coding-discipline}/SKILL.md`；`pipeline-templates/**` 中除 `…0004` approvalPrompt 文本外的全部内容（节点集、节点数、reviewLoop、其余 prompt）；`tools/agents/**`；`agent-skill-matrix.yml`；`../multica/**`（零 diff）；KB 的 `specs/`、`delivery/`、`docs/`（`docs/analysis/` 来源文档只读）。

### 1.3.2 目标仓库与版本

- 代码实施在 `../tools/`（四份 Skill 正文 + 一份 pipeline JSON 的 approvalPrompt 文本）。
- knowledge-base 承载本 PRD 与评审产物；本 CR 不改 KB 的 `specs/`、`delivery/`、`docs/`。
- `../multica/` 本 CR 零 diff（不改任何 Agent Prompt 部署副本、不改 Go/TS 代码）。
- `target-version` 继承 `cr.md` 的 `0.41`（注册阶段人工确定「版本在当前基础上顺延」，现行最新 CR-2026-067 = `0.40`；`crctl version-set` 之外无改写入口）；`target-spec-id` = `ai-first-platform`，由注册事务写入双账本，本文件不得改写。

### 1.3.3 契约说明（确定性四查适用面）

本 CR **不新增、不修改任何用户可调用契约**，四查（幂等 / 权限 / 错误闭包 / 副作用）对本 CR **N/A**，理由逐条：

- **无 HTTP API**：本 CR 不改任何 endpoint / request / response。
- **无 crctl CLI 契约变更**：`skills/shared/crctl/scripts/**` 零 diff——不新增/删除子命令与 flag，不改任何 JSON 输出形状、退出码、错误码、调用者约束。
- **无 Skill 契约变更**：五份目标文件涉及的 Skill（write-dev-plan / write-dev-tasks / review-dev-plan / implement-code）的**必填参数、落盘路径、允许的状态转换、失败码、与 `crctl` 的唯一写入边界全部不变**（§1.4 事实 6–10、18）。本 CR 改的是 SKILL **正文内的 Prompt 判据**与 pipeline **人工审批提示文本**：回修的 delta 语义、依赖闭包重算、观测面判据、回滚单元判据、环境责任声明、dev-start 静态确认内容、implement 侧 readiness 即时性。这些是**写作与评审判据**，不是调用契约；它们的验收以「文本合同 + 既有测试断言仍绿」形式给出（AC-1~AC-9）。
- **唯一语义强度变化**：`review-dev-plan` 的 `acceptance-verifiability` 判据收紧（观测面窄于声称面 → blocker；命令形态越受控边界 → blocker），会让原本可通过的 plan 在**新口径**下形成 blocker。该变化不改变任何 crctl 状态转换或错误码，只改变 `review-dev-plan` 的 blocker 判定输入；对既有已归档 CR 无追溯效力（评审判据只对评审发生时的 SKILL 版本生效）。

## 1.4 当前事实（落笔前核实）

基线（`crctl register` ensure 的 requirement worktree HEAD）：

| 仓 | worktree HEAD |
|---|---|
| `ai-first-platform-docs`（本 KB） | `f05e71d7abf696379c8454ac8e34d82267e4e56d`（register 提交 = KB trunk HEAD） |
| `../tools` | `49fa37748d9b2fc7fc58fd53f839e2ed293bde17`（= tools `main`） |
| `../multica` | `d4a49e2b9`（requirement/CR-2026-068 分支基线） |

以下结论均在上述 SHA 上核实（路径相对各自仓根）：

| # | 结论 | 证据 |
|---|---|---|
| 1 | `write-dev-plan/SKILL.md` 现共 Step 1 / Step 2 / **Step 2a** / Step 3 / Step 4 五个编号节；Step 2a「回修模式（CR-2026-026 FR-8/FR-9）」只有普通轨三条：① 逐条消费 blockers、只处理评审指出的问题不扩散 SDD 范围；② 禁止只刷新评审证据而不修改被指出的产物；③ 回修期间允许 status=`tech-design-reviewed`。**无**任何 upstream delta 回修文字 | `skills/develop/write-dev-plan/SKILL.md` L86–93（TOC 与正文实读） |
| 2 | Step 2 的 plan.md 章节列表共 **7 章**：交付里程碑 / 任务依赖图 / 资源与分工 / 风险与回滚策略 / **验收与发布策略**（现说明仅「发布前 checklist / feature-flag 计划」）/ 两张稳定表（CR-2026-060 AC-07）/ AC 业务闭环覆盖矩阵（CR-2026-057 FR-8）。**无**环境 owner / 建立方式 / 可获得性 / readiness / `ENVIRONMENT_MISMATCH` 处置文字，**无第八节** | 同文件 L57–66 |
| 3 | 交付覆盖表（稳定表 1/2）5 列固定（`FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚`）；`回滚` bullet 现文「该 FR 的回滚单元（如 revert 某 TASK commit）」——**无**依赖闭包 / 下游消费者 / 逆拓扑判据 | 同文件 L67–85 |
| 4 | 交付覆盖表 `验收证据` bullet 已有概括性反假绿句「该命令必须实际覆盖本行所声称的验收面，不得只覆盖其中一部分造成假绿」；证据命令表（稳定表 2/2）bullets：`证据ID`=`cmd-NN`（两位十进制）、`args` 为 JSON token 数组、`executable` 直接可 spawn、`cwd` 相对路径、`timeout` 秒。**无** `--list`≠浏览器 / `--name-only`≠符号不变量 / 子集≠全量 / Git 受控入口 / 命令算法不经委派评论的可判定口径 | 同文件 L73–91 |
| 5 | `write-dev-tasks/SKILL.md` 现共 Step 1 / Step 2 / **Step 2a** / Step 3 / Step 4 / Step 5 / Step 6 编号节 + 注意事项；Step 2a 第 1 条逐字为「逐条消费 blockers（每条内含可执行修复说明），**重新生成** TASK 卡并调用 `crctl task init` 刷新 `_index.yml`；不保留已被评审判废/删除的旧 TASK」——与 delta 语义直接矛盾（来源 §6.2 点名的相反现行文字） | `skills/develop/write-dev-tasks/SKILL.md` L46–53 |
| 6 | `write-dev-tasks/SKILL.md` L115「`tasks/_index.yml` 是受控账本，禁止 Agent/Skill 手写」与 `crctl task init` 指引并存（crctl.test.mjs CR-2026-037 用例两条 match 断言的载体）；TASK 卡结构 = frontmatter（id / type / cr-ref / plan-ref / sdd-ref / target-version / title / slug / status / estimate / **depends-on** / created）+ 正文 6 节（任务描述 / 涉及文件 / 实现要点 / 验收条件 / 完成标志 / 接口契约——消费/产出签名逐字对齐 SDD） | 同文件 L54–93、L115；`skills/shared/crctl/scripts/test/crctl.test.mjs` L1338–1349 |
| 7 | `review-dev-plan/SKILL.md` 的 `acceptance-verifiability` 增量维度（「增量职责与事实核验（CR-2026-055）」节四个增量维度之一）现文「核对 TASK 验收步骤是否在真实责任边界组合证明 AC，拒绝无关依赖的假绿短路」——**无**「观测面窄于声称面即 blocker」「命令形态越受控边界即 blocker」判据 | `skills/develop/review-dev-plan/SKILL.md` L75–85 |
| 8 | `review-dev-plan` Step 2「八类维度评审」表含「验收可验证性」行（每个 TASK ≥2 条可执行验收步骤，总体覆盖 SDD 验收面）；该表与四个增量维度名均为既有枚举，本 CR 不新增维度名 | 同文件 L53–93 |
| 9 | `review-dev-plan` Step 4 双轨：**NORMAL**（repair-target=write-dev-plan 缺省 → `advance tech-design-reviewed`，pipeline 按 write-dev-plan → write-dev-tasks → review-dev-plan 重放 ≤3 轮）；**UPSTREAM**（repair-target=write-tech-design → `advance tech-design-review-pending`，停止自动重放，输出 `UPSTREAM_DESIGN_BLOCKER`，由人工走既有技术设计修订、重新评审与审批流程）——upstream 后的重放入口与顺序已存在，缺的是增量回修的写作合同 | 同文件 L141–148 |
| 10 | `code-implementation.pipeline.json` 共 **12 节点**；顺序 `…0001 write-dev-plan → …0002 write-dev-tasks → …0014 review-dev-plan → …0004 human_approval（确认进入代码开发）→ …0005 approve-dev-start → …`；`…0014 reviewLoop`：maxAttempts=3、replayNodes = [write-dev-plan(`repair-plan`), write-dev-tasks(`regenerate-tasks`), review-dev-plan(`rerun-current-review`)]——「两个 authoring 节点 + 复审」已含 | `pipeline-templates/code-implementation.pipeline.json` 实读（node 遍历 + reviewLoop JSON） |
| 11 | `…0004`（完整 id `00000000-0000-0000-0015-000000000004`，human_approval「确认进入代码开发」）approvalPrompt 现文只确认任务拆分完成：「✅ 通过：勾选此 Todo，下一节点 approve-dev-start 会记录确认并推进到 developing / ❌ 暂缓：补充任务拆分意见，重新执行 write-dev-tasks 后再确认」——**无**任何环境内容、无 `git` / `journal` / `review-annotations` / `reject_reason` | 同文件实读 |
| 12 | `pipeline-templates/_index.yml`：`code-implementation-v1 nodes: 12`（注释「CR-2026-066：删除 4 个 checkpoint 节点与 auto_push_after_task（16 -> 12）」）、`requirement-authoring-v1 nodes: 5`、`architecture-design-v1 nodes: 4` | `_index.yml` L53–58 与 `pipeline-structure.test.mjs` AC-1（L35） |
| 13 | `pipeline-structure.test.mjs` 现有约束：CR-2026-043 用例断言**全部 12 节点的 prompt+approvalPrompt 无 `git` / `journal` 字样**；human_approval 判据（requirement `…0005` / architecture `…0003` / code `…0010`）无 `review-annotations` 路径、无 `reject_reason` 引导、保留 approve/reject 结构化决定；AC-1 断言节点数 5/4/12 ≡ `_index.yml`；`…0014 < …0004 < …0005` 顺序断言 | `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` L35、L113–125、L160–171、L385–386 |
| 14 | `crctl.test.mjs` CR-2026-037 用例：`write-dev-tasks/SKILL.md` 必含 `/crctl task init/` 与 `/禁止 Agent\/Skill 手写/`、**不得含** `/重新生成.*TASK 与 \`_index\.yml\`/`（doesNotMatch 型）；pipeline 节点 prompt 对受治理账本写指令零命中；pipeline 节点数 ≡ `_index.yml` 登记值。另有 CR-2026-029 用例：write-dev-tasks 与 code-implementation pipeline 不得含「发布…联调 / 联调…TASK / 发布类任务拆分」 | `skills/shared/crctl/scripts/test/crctl.test.mjs` L1338–1358、L3918–3925 |
| 15 | `gate-registry.json`：`manifest.cases["pipeline-structure.test.mjs"] = 36` = 该文件实际顶层用例数 36（`grep -c '^test('` 实测）；`exceptions: []`；`suite-gate` 判据为 `cases < 登记值` 即红 | `test/gate-registry.json` 实读 + 实测 |
| 16 | `contract-scan.test.mjs` AC-1 扫描面 = 3 个 pipeline JSON + 11 个 SKILL.md（含本 CR 4 个目标 SKILL 与 code-implementation pipeline）对废弃 canonical 字段零命中；`RETIRED_RECOVERY`（`recoverCommand` / `recover_command`）整树零命中 | `skills/shared/crctl/scripts/test/contract-scan.test.mjs` L30–52、L418 |
| 17 | `implement-code/SKILL.md`「环境验证与 ENVIRONMENT_MISMATCH」节（该 Skill 是有界验证与 `ENVIRONMENT_MISMATCH` 的**唯一详细事实源**，其余文档只链接不复述）现有 bullets：一次环境检查（任务开始时只做一次有界前提检查，不反复探测）/ 最多一次重跑 / 遵守测试计划 timeout 与既有测试入口、不创建脱离验证步骤存活的后台进程 / `ENVIRONMENT_MISMATCH` 稳定技术失败标签（不写 crctl 状态、gate、账本、评审 blocker、测试证据 schema；由既有 Pipeline `onFail=abort` 中止）/ 临时隔离实例例外 / 受控建立时归因于当前变更的失败按普通代码失败。**无** readiness `cmd-NN` 即时性文字、无「环境无关 TASK 不被提前阻断」判据 | `skills/develop/implement-code/SKILL.md` L102–111 |
| 18 | `review-dev-plan/SKILL.md` 的 `push-progress` 命中 2 处，均在 Step 5「PASS 发布与对账」（CR-2026-066 合法发布面）；`crctl checkpoint` 命中 0 处；Step 1.0 只读 clean 前置（CR-2026-066 FR-2）与 Step 5/6 已被 CR-2026-066 占用，Step 编号不得重编 | `grep` 实测 + SKILL.md TOC（L33–177） |
| 19 | 串行约束当前成立：CR-2026-063 / 064 / 065 / 066 / 067 的 `crctl status` 均为 `archived`（067 = terminal，`next` = null）；`change-requests/_backlog.yml` 在途条目仅 CR-2026-068；本次 `crctl register` 返回 `cr_id = CR-2026-068`、`phase = complete`、`targetVersion = 0.41`、commit `f05e71d7`，三仓 worktree 已 ensure | `crctl status CR-2026-067`、`_backlog.yml`、register JSON 输出 |
| 20 | KB 内来源文档 `docs/analysis/AIFI-18_SDD到planTASK_原位修订方案.md`（33,478 B）与 Issue AIFI-31 附件**逐字节一致**（`cmp` 通过）；来源 §6.2 所引「12 节点、`…0001→…0002` 顺序、replayNodes 含两个 authoring 节点」与盘上事实相符（事实 10） | `cmp` 实测 + §6.2 逐条核对 |
| 21 | 来源 §6.5 所引约束「节点 prompt/approvalPrompt 不得出现 `git` / `journal` 字样」确为现行测试断言（事实 13 CR-2026-043 用例，覆盖全部 12 节点含 `…0004`）；「两张稳定表双向唯一映射（CR-2026-060 AC-07）」确为 `review-dev-plan` 覆盖矩阵节既有机械核对判据 | `pipeline-structure.test.mjs` L113–125 + `review-dev-plan/SKILL.md` L86–92 |

## 1.5 对来源文档的事实更正与需人工确认的口径

1. **FR-3 写侧不是从零新增反假绿句**：交付覆盖表 `验收证据` bullet 已有概括性反假绿句（§1.4 事实 4）。本 CR 的加入是**具体化可判定口径**（观测面公式与四类典型错配 + 受控入口 + 命令算法唯一事实源），与来源 §6.3「原位加入」一致；既有概括句保留，不在旁边另立第二句概括。
2. **本 CR 预期零测试改动（与 CR-2026-067 的用例同步义务不同）**：改动面唯一触及的既有字样断言是 crctl.test.mjs CR-2026-037 用例的 **doesNotMatch** 型 `/重新生成.*TASK 与 \`_index\.yml\`/`（§1.4 事实 14）——「重新生成」措辞删除后该断言天然仍绿；`…0004` approvalPrompt 现文本无任何既有 match 型断言（§1.4 事实 13 的 git/journal 断言是保持性反向断言）。`gate-registry.json#manifest.cases = 36` 已与实际一致（CR-2026-067 已同步），本 CR 不新增用例、预期 36 保持；若实施中用例数意外变化，同 CR 同步登记值，不签任何例外。
3. **`…0004` approvalPrompt 的「原位改为」落点**：现文本不含任何环境内容（§1.4 事实 11），来源 §6.5 dev-start 侧的「原位改为只确认 owner、建立方式和可获得性」= 在既有任务拆分确认文本上**扩写环境静态前提**（保留拆分完成确认的语境），不是删除拆分确认；现文本决定形态是「✅ 通过 / ❌ 暂缓」两分支，重写保留两分支结构化决定（approve/reject 结构化决定的现行载体形态）。需人工一并确认。
4. **`ENVIRONMENT_MISMATCH` 的单一事实源纪律**：`implement-code/SKILL.md` 是该标签的唯一详细事实源（「其余文档只链接不复述」，§1.4 事实 17）。write-dev-plan 侧 FR-5 的新文字只**引用**标签名与处置入口，不得复述其完整语义（避免第二份事实源）；implement-code 侧新文字加在同一节内，与既有 bullets 同节共生、不改写它们。
5. **「一次环境检查」与 readiness `cmd-NN` 的关系钉定（来源未写明，本 PRD 钉定）**：「在第一个依赖环境的 TASK 前执行 plan 指定的 readiness `cmd-NN`」是既有「任务开始时只做一次有界前提检查」在环境依赖 TASK 上的**具体化执行内容**，不是新的反复探测；仍受「最多一次重跑」、测试计划 timeout 与受控入口约束。「环境无关 TASK 不被提前阻断」是新增的隔离判据。需人工一并确认。
6. **readiness 无法复用既有 `cmd-NN` 时**：来源已钉「确实无法复用时，该诉求超出本 CR 边界，另立 CR 修改稳定表合同与对应评审判据，本 CR 不放宽该映射」；本 PRD 落为 FR-5 第 4 条硬边界 + AC-6 第 2/3 项。评审按「不存在『为 readiness 单独申请新 `cmd-NN`』的形态文字」核对。
7. **`purpose: regenerate-tasks` 标签语义钉定**：标签文本不改（撞 CR-2026-066 的节点数与 `_index.yml` 断言面即 AC-7 fail）；其「delta 重算」语义只在 `write-dev-tasks/SKILL.md` 正文内明确（FR-2 第 2 条）。来源 §6.2 已写明，本 PRD 落为可检查约束。

## 1.6 修订记录

- 初稿（2026-09-15）：按来源附件 §6（含 §6.1–§6.7 与边界段落）与注册摘要（`cr.md` summary）起草；基线事实在 §1.4 三个 worktree HEAD 上逐条核实。FR 编号与来源 §6 小节一一对应（§6.1→FR-1、§6.2→FR-2、§6.3→FR-3、§6.4→FR-4、§6.5→FR-5、§2+§6.6+§6.7→FR-6）；AC-1~AC-8 对应来源 §6.7 十条验收（按行为面 / 证据面 / 零 diff 面分组，未合并判据），**AC-9 为本 PRD 新增**，把来源 §2 的 CR-P2 边界与 §8 的串行约束写成可检查约束。§1.5 记录三处需人工一并确认的钉定（第 3、5 条）、三处本 PRD 钉定（第 4、6、7 条）与两处事实核对（第 1、2 条）。

# 2. 用户故事

- **US-1 dev-plan 写手（`write-dev-plan` / dev-agent）**：作为写 plan 的人，我希望 upstream SDD 重新批准后在**同一份 plan** 上只重算受影响章节、稳定表行、证据与回滚，这样未受影响的已确认内容不被无理由重写，返工成本与 delta 成正比而不是与全文成正比。
- **US-2 dev-tasks 写手（`write-dev-tasks` / dev-agent）**：作为拆 TASK 的人，我希望回修语义是 delta 重算 + 依赖闭包同步 + 未受影响 TASK 保留，这样受影响闭包的输入/输出/接口/命令/depends-on/完成标志/回滚被同步更新、不残留旧口径，而不是每轮全量重建 TASK 卡。
- **US-3 CR 协调者（coordinator）**：作为路由 upstream 回修的人，我希望只传 subject、delta、canonical feedback 引用而不指定具体行如何修改，这样我不会把增量回修升级成整轮作废的委派。
- **US-4 dev-plan 评审者（`review-dev-plan` / quality-reviewer-agent）**：作为核对证据命令的人，我希望「观测面窄于声称面」「命令形态越受控边界」是可判定的 blocker 判据，这样假绿命令与越界命令在 dev-plan 阶段就被拦下，不会漏到 implement 阶段才暴露。
- **US-5 人工审批者（Ray）**：作为批准进入代码开发的人，我希望 dev-start 审批只确认环境 owner、建立方式和可获得性这类**静态前提**，不用在审批时逐个确认服务在线，这样动态健康状态不会被写成人工长期事实、也不会被审批卡错误背书。
- **US-6 implement 执行者（`implement-code` / dev-agent）**：作为写代码的人，我希望在第一个依赖环境的 TASK 前执行 plan 指定的 readiness `cmd-NN`，失败按既有 `ENVIRONMENT_MISMATCH` 中止并报告建立动作，这样环境缺位在正确的位置、以正确的标签暴露，环境无关 TASK 不被提前阻断。
- **US-7 本 CR 的 reviewer**：作为本 CR 的评审者，我希望逐条核对「哪个仓的哪个文件、哪一段被原位改了、哪些面必须零 diff」，确认没有两套并存的回修规则、没有新的环境验证事实源、没有新节点 / 新账本字段 / 新观测指标。

# 3. 功能需求

## FR-1 upstream 后 plan 增量回修（`write-dev-plan`）〔来源 §6.1〕

修订面 = `skills/develop/write-dev-plan/SKILL.md` 的 **Step 2a「回修模式（CR-2026-026 FR-8/FR-9）」**——在该节内**原位扩写**（不新增小节、不重编号、保留出处标注）：

1. **普通轨语义逐字保留**：既有三条（逐条消费 blockers 只处理评审指出的问题不扩散 SDD 范围 / 禁止只刷新评审证据而不修改被指出的产物 / 回修期间允许 status=`tech-design-reviewed`）不动（§1.4 事实 1）。
2. **新增 upstream 轨判据（同在 Step 2a 内）**：
   - upstream SDD 重新批准后（`review-dev-plan:upstream-design-blocker` → 人工修订 → 重新评审与审批 → pipeline 按 replayNodes 重放，§1.4 事实 9/10），`write-dev-plan` 以**新旧批准 SDD 的变更 delta** 与**同轮未闭合 plan blockers** 为输入；
   - 在**同一份 plan** 上只重算受影响章节、稳定表行、证据与回滚；
   - 未受影响内容保留；
   - coordinator 只传 subject、delta、canonical feedback 引用，**不指定具体行如何修改**（委派合同遵守 CR-2026-063 已落地的公共 dev-agent 委派合同文字，不重述、不改写）。
3. **不改路由面**：不修改 review-route 枚举、不把 `repair-target` 改成多值；upstream 轨由既有 `review-dev-plan` Step 4 UPSTREAM 分支与状态机既有转换承载，本 CR 零状态机改动（FR-6）。

## FR-2 TASK 及依赖闭包重算（`write-dev-tasks`）〔来源 §6.2〕

修订面 = `skills/develop/write-dev-tasks/SKILL.md` 的 **Step 2a 第 1 条**——**在该段内原位改写**，不得在别处另写一段增量规则与它并存：

1. 现「逐条消费 blockers（每条内含可执行修复说明），**重新生成** TASK 卡并调用 `crctl task init` 刷新 `_index.yml`；不保留已被评审判废/删除的旧 TASK」改写为：
   - `write-dev-plan` 完成 SDD→plan delta 后，`write-dev-tasks` 必须继续执行 plan→TASK delta（`…0001 → …0002` 节点顺序承载，§1.4 事实 10）；
   - 重算**直接受影响 TASK 及其下游依赖闭包**（普通轨 blockers 指向的 TASK 与 upstream delta 波及的 TASK 都是「直接受影响」的来源）；
   - 同步更新受影响 TASK 的输入、输出、接口（接口契约节的消费/产出签名）、命令、`depends-on`、完成标志和回滚；
   - 未受影响 TASK 保留；
   - **`crctl task init` 只用于刷新 `_index.yml` 索引**（受控账本唯一初始化入口，既不手写也不承担重算语义；既有「禁止 Agent/Skill 手写」句保持，§1.4 事实 6）；
   - 禁止只修 plan、让旧 TASK 留给下一轮评审发现。
2. **节点层零改动**：`code-implementation.pipeline.json` 节点集（12）、`…0001 write-dev-plan → …0002 write-dev-tasks` 顺序、`…0014 reviewLoop.replayNodes` 条目全部保持；`purpose: regenerate-tasks` 是标签，本 CR 只在 `write-dev-tasks/SKILL.md` 正文内明确其语义为 delta 重算，**不改节点集、不改节点数（保持 5/4/12）、不改 replayNodes 条目**（以免撞 CR-2026-066 的节点数与 `_index.yml` 断言，§1.5 第 7 条）。
3. **文件内单一回修规则**：delta 重算规则与全量重建规则不得并存（「重新生成」措辞零残留；AC-2 第 3 项）；既有 doesNotMatch 断言（crctl.test.mjs CR-2026-037）删除措辞后天然仍绿（§1.5 第 2 条）。
4. Step 2a 第 2、3 条（禁空转 / 允许 `tech-design-reviewed` 重放态）保留。

## FR-3 证据命令的可执行性与证明力（写侧 + 评侧）〔来源 §6.3〕

**写侧**（`skills/develop/write-dev-plan/SKILL.md` 两张稳定表说明，原位加入；既有概括反假绿句保留，§1.5 第 1 条）：

1. 每个 `cmd-NN` 必须能观测该表行声称的 AC 结果（**观测面 ≥ 声称面**）；
2. `--list` 类命令不能证明浏览器行为；
3. 文件级 `--name-only` 不能证明符号级不变量；
4. 子集测试不能声称全量；
5. 涉及 Git 的命令必须使用 `rules.json` 已允许的受控入口（不新开裸 git 面、不改 `rules.json`）；
6. 不再通过委派评论补写命令算法（命令算法唯一事实源 = 证据命令表行）。
- 两条稳定表的表头 / 列集 / 「验收证据 ↔ 证据ID」双向唯一映射合同不变（CR-2026-060 AC-07 面，FR-6 第 3 条）。

**评侧**（`skills/develop/review-dev-plan/SKILL.md` 既有 `acceptance-verifiability` 增量维度，原位加入同一判据）：

7. **观测面窄于声称面即 blocker**；
8. **命令形态越受控边界即 blocker**，不留到 implement 阶段才暴露。
- 修订只在该维度段内原位扩写：**不重编 Step 号**（Step 1.0 clean 前置与 Step 5/6 PASS 发布已由 CR-2026-066 占用，§1.4 事实 18）；本 CR 在 `review-dev-plan` 中的新增文字**不得出现** `crctl checkpoint` / `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`（CR-2026-066 反向断言零命中，保持性约束）；**不新增新的评审维度名或证据账本**（判据落在既有 `acceptance-verifiability` 维度内，八类维度表与四个增量维度名不变，§1.4 事实 8）。

## FR-4 回滚单元是依赖闭包（`write-dev-plan` 交付覆盖表）〔来源 §6.4〕

修订面 = `write-dev-plan/SKILL.md` 交付覆盖表既有 `回滚` bullet（现文「该 FR 的回滚单元（如 revert 某 TASK commit）」，§1.4 事实 3）——原位明确：

1. 被其它 TASK 消费的**共享改动**，其回滚单元必须**包含受影响下游消费者**；
2. 并与风险节（plan.md 第 4 章「风险与回滚策略」）中的**逆拓扑顺序一致**；
3. 单点 revert 会破坏下游时**不得声明为单点回滚**。

不改交付覆盖表列集（仍为固定 5 列，§1.4 事实 3）。

## FR-5 环境责任与即时 readiness（plan / dev-start / implement 三侧）〔来源 §6.5〕

**plan 侧**（`write-dev-plan/SKILL.md` 既有「验收与发布策略」章节项 = plan.md 第 5 章说明，**不新增第八节**，原位扩写）——若证据依赖常驻服务、浏览器或数据库，plan 必须在该节写明：

1. **环境 owner**；
2. **建立方式**；
3. **可获得性**；
4. **readiness 证据**：必须复用**该环境所保障的那一行 FR 的既有 `cmd-NN`**，不得为 readiness 单独申请新 `cmd-NN`（理由：两张稳定表「验收证据 ↔ 证据ID」双向唯一映射（CR-2026-060 AC-07，`review-dev-plan` 覆盖矩阵节机械核对）不允许存在不被交付覆盖表引用的命令行——进证据命令表而不被引用即 blocker，不进表则不是合法 `cmd-NN`（无 executable/args/timeout 与 `crctl test` 机器区下标）。确实无法复用时，该诉求超出本 CR 边界，**另立 CR** 修改稳定表合同与对应评审判据，**本 CR 不放宽该映射**，§1.5 第 6 条）；
5. **缺失时的 `ENVIRONMENT_MISMATCH` 处置**（只引用既有标签与处置入口，不复述其完整语义——`implement-code` 是该标签唯一详细事实源，§1.5 第 4 条）。

**dev-start 侧**（`code-implementation.pipeline.json` 节点 `00000000-0000-0000-0015-000000000004` 既有 approvalPrompt，原位改写）：

6. 改为**只确认 owner、建立方式和可获得性**（静态前提）；不要求审批时所有服务在线，**不把动态健康状态写成人工长期事实**；
7. 改写文本满足现行 `pipeline-structure.test.mjs` 断言：节点 prompt/approvalPrompt **不得出现 `git` / `journal` 字样**（因此环境建立方式只写责任人与获得途径，不写命令）；**保留 approve/reject 结构化决定**（既有「✅ 通过 / ❌ 暂缓」两分支形态，§1.5 第 3 条）；**不得残留 `review-annotations` 路径与 `reject_reason` 引导**；
8. 节点对象其余字段（id / kind / label / onFail / timeoutMinutes）与节点集零变化（§1.4 事实 11）。

**implement 侧**（`skills/develop/implement-code/SKILL.md` 既有「环境验证与 ENVIRONMENT_MISMATCH」节，原位加入）：

9. 在**第一个依赖环境的 TASK 前**执行 plan 指定的 readiness `cmd-NN`（该命令属于既有「一次环境检查」有界前提检查的执行内容，不是反复探测，§1.5 第 5 条）；
10. 失败则按既有 `ENVIRONMENT_MISMATCH` 中止并报告建立动作（标签语义、不写 crctl 状态 / gate / 账本 / 评审 blocker / 测试证据 schema、`onFail=abort` 等既有边界全部不变，§1.4 事实 17）；
11. **环境无关 TASK 不被提前阻断**；
12. 不新增环境 Pipeline 节点、不让 coordinator 启停共享服务；「一次环境检查 / 最多一次重跑 / 临时隔离实例例外 / 受控建立归因」等既有 bullets 原样保留（同节共生，不改写）。

## FR-6 边界与零新增〔来源 §2、§6.6、§6.7〕

1. **不修改 upstream attempts 账本**（来源 §6.6）：不把 upstream block 追加到 `attempts[]`（该设计会产生 attempt 0 或重复 `(cycle,attempt)`、混淆「评审事件」与「预算 attempt」）、不新增 review-events、不改 traceability schema、不做聚合指标；既有 canonical annotation 与 audit 保留 upstream 事实。
2. **不新增 Pipeline 环境节点**：节点数保持 5/4/12（`_index.yml` 计数一致）；不改 replayNodes 条目、不改 review-route 枚举、不把 repair-target 改成多值。
3. **不新增账本字段 / 评审维度 / 观测指标 / crctl 子命令 / flag / 错误码 / Skill 参数 / 落盘文件 / lint 规则 / CI step**；`skills/shared/crctl/scripts/**`（含 gate-registry.json 与全部测试）预期零 diff（§1.5 第 2 条）。
4. **面不重叠（与已归档 CR 的块级边界，来源 §2）**：四个 review SKILL 的 Step 1.0 clean 前置、Step 5 PASS 发布与对账、Step 6 摘要零 diff（CR-2026-066 面）；`write-tech-design` / `review-tech-design` 的 dep-N 与 SDD 写作合同零 diff（CR-2026-067 面）；`review-code` / `write-test-report` / `coding-discipline` 零 diff；本 CR 新增文字不得出现 `crctl checkpoint` / `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`。
5. **不复活旧字段名**：不引入 `recoverCommand` / `recover_command`（`contract-scan` 退役名单整树零命中，§1.4 事实 16）。
6. **测试与门禁**：`suite-gate --run` 全量绿、`gate-registry.json#manifest.cases` 与实际顶层用例数一致（当前 36/36）、`exceptions` 保持空（**不签任何新例外**，CR-S 后全量测试是真门禁）；本 CR 预期不新增测试用例（改动面无 match 型既有断言，§1.4 事实 14/15、§1.5 第 2 条）。

# 4. 非功能需求

- **NFR-1 兼容性与门禁（最重要）**：`../tools` 全量既有测试与 CI（lint-prompts enforce / skill matrix / agents contract / pipeline JSON 结构断言 / suite-gate --run / writeback 单测，Ubuntu + Windows）保持绿；本 CR **不得签任何新例外**，`gate-registry.json#exceptions` 保持空。
- **NFR-2 零新增**：同 FR-6 第 2/3 条（无新节点 / 维度名 / 账本字段 / 观测指标 / 子命令 / flag / 错误码 / Skill 参数 / 落盘文件 / lint 规则 / CI step）。
- **NFR-3 原位与单一事实源**：所有修订发生在**既有段落内部**；不得出现「新旧两套规则并存」的形态——尤其：`write-dev-tasks` 的 delta 重算规则不得与全量重建规则并存；`ENVIRONMENT_MISMATCH` 唯一详细事实源仍是 `implement-code`（write-dev-plan 侧只引用不复述）；plan 侧环境声明不得另造第二套验证语义。
- **NFR-4 判据可机械核对**：新增/改写的判据必须能被既有文本断言或 AC 的逐字核对覆盖（AC-1~AC-8）；**不得**把不可判定表述（如「足够详细」「合理覆盖」）写成判据。
- **NFR-5 行尾纪律**：触及跨行文本断言与 `\r\n` 归一化读取的测试面（contract-scan / pipeline-structure / crctl.test 的 `readTextNormalized` / `replaceAll('\r\n','\n')`），读写前必须归一；断言/解析失败**硬失败报错**，禁止「匹配不到 → 空集 → 静默通过」。SKILL 与 JSON 文件保持 LF 检出内容一致。
- **NFR-6 语言纪律**：`../tools` SKILL 正文用中文；本 CR 对 `../multica` 零 diff。
- **NFR-7 可回退**：全部为 Prompt 判据与提示文本的原位改动，**同批交付、同批还原**，不产生半套合同（尤其 `write-dev-plan` 的 upstream delta 轨与 `write-dev-tasks` 的 delta 重算语义必须同批落地——一侧单独存在即规则矛盾）。

# 5. 验收标准

| ID | 覆盖 FR | 来源 | 可执行验收 |
|---|---|---|---|
| AC-1 | FR-1 | §6.7 | `write-dev-plan/SKILL.md#Step 2a`：① 普通轨三条既有语义逐字保留；② 含 upstream 轨判据——以新旧批准 SDD 变更 delta + 同轮未闭合 plan blockers 为输入、同一份 plan 上只重算受影响章节/稳定表行/证据/回滚、未受影响内容保留；③ 含「coordinator 只传 subject/delta/canonical feedback 引用、不指定具体行如何修改」；④ review-route 枚举与 repair-target 单值语义未被修改；⑤ 未新增 Step、未重编号。 |
| AC-2 | FR-2 | §6.7 | `write-dev-tasks/SKILL.md#Step 2a`：① 「重新生成」措辞零残留，该段表达 delta 重算 + 下游依赖闭包同步 + 同步更新输入/输出/接口/命令/depends-on/完成标志/回滚 + 未受影响 TASK 保留；② 「`crctl task init` 只用于刷新 `_index.yml` 索引」语义已写明；③ 文件内不存在两套并存的回修规则；④ 既有「`tasks/_index.yml` 是受控账本，禁止 Agent/Skill 手写」句仍在且 crctl.test.mjs CR-2026-037 用例仍绿（match 与 doesNotMatch 断言两侧）；⑤ 节点集 / 节点数 / replayNodes / `purpose: regenerate-tasks` 标签文本未被改动。 |
| AC-3 | FR-3 | §6.7 | ① `write-dev-plan` 两张稳定表说明含六项观测面判据（观测面 ≥ 声称面、`--list`≠浏览器行为、`--name-only`≠符号级不变量、子集≠全量、Git 用 `rules.json` 受控入口、命令算法不经委派评论补写），既有概括反假绿句保留且未另立第二句；② `review-dev-plan` `acceptance-verifiability` 维度含「观测面窄于声称面即 blocker」与「命令形态越受控边界即 blocker」；③ 八类维度表与四个增量维度名未变、无新证据账本；④ `review-dev-plan` 本 CR 新增文字不含 `crctl checkpoint` / `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`；⑤ 两张稳定表表头/列集/双向唯一映射合同未变。 |
| AC-4 | FR-4 | §6.7 | `write-dev-plan` 交付覆盖表 `回滚` bullet：① 共享改动的回滚单元必须包含受影响下游消费者；② 与风险节逆拓扑顺序一致；③ 单点 revert 会破坏下游时不得声明为单点回滚；④ 表列集未变（固定 5 列）。 |
| AC-5 | FR-5 | §6.7 | ① `write-dev-plan`「验收与发布策略」章节项含环境五要素（owner / 建立方式 / 可获得性 / readiness 复用既有 `cmd-NN` / 缺失时 `ENVIRONMENT_MISMATCH` 处置引用），plan.md 章节未新增第八节；② `code-implementation.pipeline.json` `…0004` approvalPrompt 只确认 owner/建立方式/可获得性等静态前提、不要求审批时服务在线、不含 `git`/`journal` 字样、保留 ✅/❌ 两分支结构化决定、无 `review-annotations`/`reject_reason` 残留，节点对象其余字段与节点集零变化；③ `implement-code` 环境节含「首个环境依赖 TASK 前执行 plan 指定 readiness `cmd-NN`」「失败按既有 `ENVIRONMENT_MISMATCH` 中止并报告建立动作」「环境无关 TASK 不被提前阻断」，且该节既有 bullets（一次检查/一次重跑/timeout/标签不写账本/临时隔离例外/受控归因）未改写。 |
| AC-6 | FR-5 | §6.7（映射不破坏） | ① readiness 证据复用既有 `cmd-NN`：两张稳定表「验收证据 ↔ 证据ID」双向唯一映射未被放宽或修改（`review-dev-plan` 覆盖矩阵节机械核对判据原样保留）；② 不存在「为 readiness 单独申请新 `cmd-NN`」的形态文字；③ 无法复用场景的文字指向「另立 CR」，本 CR 内无任何放宽。 |
| AC-7 | FR-6 | §6.7（零新增） | ① 交付 diff 只含 §1.3.1 表内 5 个文件；② `skills/shared/crctl/scripts/**`（含全部测试与 `gate-registry.json`）、`write-tech-design` / `review-tech-design` / `review-code` / `write-test-report` / `coding-discipline`、pipeline 节点集与 reviewLoop、`tools/agents/**`、`agent-skill-matrix.yml`、`../multica/**`、KB `specs/`/`delivery/`/`docs/` 零 diff；③ 节点数保持 5/4/12 且 `_index.yml` 计数一致；④ upstream attempts 账本 / traceability schema / 账本字段 / 评审维度 / 观测指标 / crctl 子命令 / flag / 错误码零新增。 |
| AC-8 | FR-1~FR-6 | §6.7 + §2（CR-2026-066/067 面零 diff） | ① 四个 review SKILL 的 Step 1.0 clean 前置、Step 5 PASS 发布与对账四要素（`phase` / `batchId` / `repositories[]` / `metadataCommit`）逐字保留；② 四 SKILL 不含 `crctl checkpoint`、不含 `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`；③ CR-2026-067 的 dep-N 面（`write-tech-design` / `review-tech-design`）零 diff；④ `pipeline-structure.test.mjs` 的 CR-2026-043（git/journal 零命中）、CR-2026-037（账本写指令零命中 + `task init` 断言）、AC-1（5/4/12）与 `crctl.test.mjs` CR-2026-029（无发布联调拆分指引）全部仍绿。 |
| AC-9 | 全部（边界与串行） | §2、§8（**本 PRD 新增**） | ① **串行约束**：实施与交付期间 `change-requests/_backlog.yml` 在途条目只有本 CR，CR-2026-063/064/065/066/067 的 `crctl status` 均为 `archived`；② **顺序**：CR-P0(063) → CR-R(064) → CR-S(065) → CR-P3(066) → CR-P1(067) → **本 CR(068)**，不与任何 CR 并发（tools 单写者）；③ `suite-gate --run` 全量绿、`gate-registry.json#manifest.cases` 与实际顶层用例数一致（36）、`exceptions` 为空数组（未签任何新例外）。 |

来源 §6.7 的十条验收与上表一一对应（AC-1~AC-8 按行为面 / 证据面 / 零 diff 面分组，未合并判据）；AC-9 是「把来源 §2 的 CR-P2 边界与 §8 的串行约束写成可检查约束」的落地判据（来源文档没有对应 AC）。

# 6. 成功指标

- upstream 重放后 plan 的重写面与 delta 成正比：未受影响章节 / 稳定表行 / 证据 / 回滚的改写数 = 0。
- upstream 重放后未受影响 TASK 的重建数 = 0；受影响依赖闭包内残留旧接口 / 命令 / `depends-on` 数 = 0。
- 「只修 plan、旧 TASK 留给下一轮评审发现」形态的发生数 = 0（由 AC-2 判据约束）。
- 观测面窄于声称面 / 命令形态越受控边界的 blocker 在 **dev-plan 阶段**拦截率 = 100%；漏到 implement 阶段才暴露数 = 0。
- readiness 复用既有 `cmd-NN` 的比例 = 100%；两张稳定表双向唯一映射被放宽次数 = 0。
- dev-start 审批要求动态服务在线 / 把动态健康写成人工长期事实的文字 = 0。
- 环境依赖 TASK 执行前即时 readiness 执行率 = 100%；环境无关 TASK 被提前阻断次数 = 0。
- 本 CR 新增的 Pipeline 节点 / 账本字段 / 评审维度 / 观测指标 / crctl 子命令 / flag / 错误码 / Skill 参数 / 落盘文件 = 0；测试用例数变化 = 0（36 保持）；`gate-registry.json#exceptions` 长度 = 0。
- 既有测试回归数 = 0；CI 新增例外数 = 0；CR-2026-066 / CR-2026-067 的既有断言失败数 = 0。

# 7. 范围排除

**来源 §2 的 CR-P2 边界（逐条不做，判据见 AC-7 / AC-9）**

- **不新增 Pipeline 环境节点**：节点集 / 节点数（5/4/12）/ replayNodes 全保持；`purpose: regenerate-tasks` 标签文本不改。
- **不做动态环境人工门禁**：dev-start 不要求审批时服务在线；不让 coordinator 启停共享服务。
- **不新增评审观测指标**：无 SLO / 轮数承诺 / 计数门禁 / 聚合指标。

**来源 §6.6 明确不做（upstream attempts 账本零改动）**

- 不把 upstream block 追加到 `attempts[]`、不新增 review-events、不改 traceability schema、不做聚合指标；既有 canonical annotation 与 audit 保留 upstream 事实。

**来源 §6.5 明确交出的面**

- readiness 无法复用既有 `cmd-NN`、需要独立 readiness 命令行 → 修改两张稳定表双向唯一映射合同与对应评审判据，**另立 CR**，本 CR 不放宽映射。
- 不修改 `review-route` 枚举、不把 `repair-target` 改成多值（FR-1 第 3 条）。

**与已归档 CR 的面不重叠（块级零 diff，判据见 AC-8）**

- CR-2026-066 面：四个 review SKILL 的 Step 1.0 clean 前置、Step 5 PASS 发布与对账、Step 6、节点集与权限矩阵。
- CR-2026-067 面：`write-tech-design` / `review-tech-design` 的 dep-N 表达、`commit SHA` 双侧必填、状态链整体重证、批准范围四字段自洽。
- CR-2026-065（CR-S）面：`suite-gate` 判据语义、`gate-registry.json` 登记机制——本 CR 不签任何新例外。
- CR-2026-064（CR-R）面：结构化 `recovery` 合同；不复活 `recoverCommand` / `recover_command`。

**本次明确不碰的既有资产**

- crctl 状态机、gate、CAS、durable ledger transaction、`reviewLoop` / `replayNodes` / `maxAttempts`、controlled-shell 与 `rules.json`、`ENVIRONMENT_MISMATCH` 标签语义（唯一详细事实源在 `implement-code`）、版本化 `cmd-NN` 与 test evidence、两张稳定表合同（CR-2026-060 AC-07）、`skills/shared/crctl/scripts/**` 全部测试与 `gate-registry.json`。
- `../multica/` 的 `CUSTOM.md`、`cr-prompts-revised/**`、`aifirst/**` 与任何 Go/TS 代码；平台 DB；KB 的 `specs/`、`delivery/`、`docs/`（`docs/analysis/` 来源文档只读）。
- `tools/agents/**`（不在来源 §6 修订面内，Agent Prompt 零 diff）。

**顺序与并发约束（可检查形式见 AC-9）**

- 顺序：CR-P0(063) → CR-R(064) → CR-S(065) → CR-P3(066) → CR-P1(067) → **本 CR(068)**；本 CR 不得早于 CR-P1 执行（来源 §8 实施顺序第 6 条：CR-P2 最后落地），不与任何 CR 并发（tools 单写者）。
- 任一 CR 失败只回滚本 CR；不得为了保持后续 CR 而保留半套新旧合同（来源 §8）。

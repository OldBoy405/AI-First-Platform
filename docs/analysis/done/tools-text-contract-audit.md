# Tools 文本契约全仓审计与治理实施方案

> 审计日期：2026-08-10  
> 审计对象：`C:/Users/GOBAO/Downloads/AI/tools`（分支 `custom/main`）  
> 审计依据：`docs/2026-08-10/tools文本契约排查与治理方案.md`、tools 仓 `AGENTS.md`、`dir-graph.yaml`、`agent-skill-matrix.yml`、`README.md`  
> 文档性质：审计产物，不是运行时事实源；状态机、Pipeline、权限和 Git 白名单仍以 tools 仓权威文件为准。

## 1. 结论摘要

本次扫描了 57 个 active Skill、8 个 Pipeline、9 个 Agent，以及 crctl、controlled-shell、writeback 版本化脚本、README/ARCHITECTURE、现有检查器和测试。审计按 P0 事务/状态链、P1 写回/评审链、P2 只读/内容生成链展开，并把文本声明与真实代码路径交叉验证。

发现共 27 项：

| 级别 | 数量 | 结论 |
|---|---:|---|
| P0 | 9 | 存在 owner 错写、审批流程不可执行、状态转换不可达、多仓发布与账本非原子、恢复入口缺失等问题；对应流程再次使用前应修复 |
| P1 | 12 | 存在证据/通知/traceability 半状态、allowlist 契约不实、Pipeline/Agent 逻辑泄漏、检查与 CI 覆盖不足 |
| P2 | 6 | 存在固定计数漂移、悬空章节引用、ignore/历史噪音、能力声明和只读属性不一致 |

当前基线全部为绿：

- `lint-prompts`：0 findings；
- skill matrix：57 个 active Skill 校验通过；
- Agent contract：9 个 Agent 校验通过，但脚本明确说明“不绕过 Skill 写受控文件”没有静态校验；
- crctl/契约测试：189/189 通过；
- writeback 脚本测试：9/9 通过；
- 8 个 Pipeline JSON 均可解析。

这些绿灯没有发现本报告中的 P0，原因包括：测试固化了错误实现、检查器只检查命令形状而不检查语义、关键测试只断言文本存在、tools 仓 CI 没有运行 lint 和行为测试。

## 2. 审计基线与方法

### 2.1 实际规模

| 项目 | 实际值 | 观察 |
|---|---:|---|
| Active Skill | 57 | 与附件一致 |
| Pipeline | 8 | 与附件一致 |
| Agent | 9 | 与附件一致 |
| active Skill/Pipeline 中 `lint-prompts:ignore` | 87 | 每条有行内原因，但 26 条集中在 merge/archive 两个 P0 Skill |
| 全仓 `crctl` 命令形态引用 | 约 327 | 高于附件审计时的 225，文本执行面持续扩大 |
| Skill/Agent/Pipeline/README/ARCHITECTURE 历史 CR 引用 | 约 516 | 历史说明已显著侵入当前契约 |
| `crctl.mjs` | 3,221 行 | 能力集中，但事务边界仍不完整 |

### 2.2 检查方法

1. 按规定读取 tools 的四个入口事实源和 active 索引。
2. 对所有 active Skill 核验登记文件、frontmatter `name`、owner、Pipeline ref。
3. 提取全部 `crctl advance`，与权威状态机对照。
4. 提取 `runGit`/`crctl git`/裸 Git/恢复命令，与 `rules.json` 和 `controlledGit()` 对照。
5. 对 P0 Skill 推演首次副作用、逐仓失败、commit/push 失败、CAS、重试、linked worktree、非 TTY、CRLF/Windows 场景。
6. 对 P1 reviewLoop、证据投影、writeback 顺序、freshness 和幂等语义做代码交叉验证。
7. 对 P2 的只读声明、写入能力、固定路径、下游消费和重复事实源做扫描。
8. 运行现有全部检查与测试，反查绿灯未发现问题的原因。

## 3. P0 发现：事务型与状态型链路

### TCA-001：`cr-init` 丢弃 development/test owner

- **级别**：P0
- **位置**：`skills/requirement/requirement-register/SKILL.md:30-31,50-51`；`pipeline-templates/requirement-authoring.pipeline.json:58-71,88`；`skills/shared/crctl/scripts/crctl.mjs:2383-2389,2400-2443`
- **证据**：Pipeline 和 Skill 把 `dev_owner`、`test_owner` 声明为必填，但调用只传 `--owner-requirement`。`cmdCrInit()` 把三个角色全部写成同一个 `ownerId`。
- **影响/风险**：架构审批、开发启动、测试报告、代码审批均读取错误身份，可能造成审批越权、测试责任错配和审计失真。
- **修复**：扩展 `crctl cr-init` 为必填 `--owner-requirement`、`--owner-development`、`--owner-test`，一次生成三角色及三条 owner-history；删除 Pipeline 的僵尸 `cr_id` 输入。增加三人不同值的黑盒测试，并断言 `cr.md`、backlog、execution_context 一致。

### TCA-002：`owner-set` 只改 backlog，且不做授权校验

- **级别**：P0
- **位置**：`skills/sync/handover-cr/SKILL.md:34-36,53-73`；`skills/sync/resume-from-remote/SKILL.md:76-80`；`crctl.mjs:2193-2222,2251-2261`；测试 `crctl.test.mjs:1654-1665`
- **证据**：两个 Skill 声称原子更新 backlog、`cr.md`、顶层 owner、owner-history/handover-history；实现只对 `loadBacklogEntry()` 执行一次 `casWrite()`。测试也只断言 backlog。
- **影响/风险**：主 checkout 与 CR worktree 对 owner 得出不同结论；实际接手人无法从 `cr.md` 恢复责任上下文。Skill 的“当前 owner 或管理员”检查只存在于文本，crctl 没有强制。
- **修复**：用 `crctl owner-handover` 替代 `owner-set + inbox-emit`，一次 CAS 更新 `cr.md` 与 backlog、追加两类 history、生成通知；校验调用者为当前角色 owner 或持有管理员授权。

### TCA-003：四个审批 Pipeline 在非 TTY 环境必然卡死

- **级别**：P0
- **位置**：`requirement-authoring.pipeline.json:141-152`；`architecture-design.pipeline.json:75-86`；`code-implementation.pipeline.json:130-141,271-282`；`crctl.mjs:1337-1339`
- **证据**：Pipeline 先执行 UI `human_approval`，下一 Skill 再由 Agent 调用 `crctl approve`。crctl 明确拒绝模型/管道/脚本的非 TTY 调用，除非传入签名 `--grant`；四条 Pipeline 均未传 grant。
- **影响/风险**：需求、架构、开发启动、代码四个主流程会在人工已点选通过后返回 `APPROVAL_REQUIRES_HUMAN`。驳回文案还要求直接补写受保护 annotation。
- **修复**：定义统一审批桥接协议：`human_approval` 输出服务端签名 grant，approve Skill 只接收 `grant_ref` 并执行 `crctl approve --grant`。本地 CLI 模式则由人类在 TTY 直接执行 approve。扩展 grant reject，使其原子记录驳回证据并执行状态回退。

### TCA-004：`review-dev-plan` 普通回修 trigger 不存在

- **级别**：P0
- **位置**：`skills/develop/review-dev-plan/SKILL.md:81-83`；`pipeline-templates/code-implementation.pipeline.json:78`；权威转换 `dir-graph.yaml#change-request-track.state_machine`
- **证据**：调用使用 `--trigger review-dev-plan:block`；状态机声明的是 `review-dev-plan:block -> write-dev-plan`。crctl 精确匹配 trigger。
- **影响/风险**：NORMAL block 无法从 `task-breakdown` 回到 `tech-design-reviewed`，reviewLoop 在修复前中止。
- **修复**：修正 Skill 调用，Pipeline 删除复制命令；新增状态可达性检查和真实命令测试。

### TCA-005：merge status 与 N 条 metadata 不是同一事务

- **级别**：P0
- **位置**：`skills/writeback/merge-feature-branch/SKILL.md:156-172`；`crctl.mjs:1688-1703`
- **证据**：Skill 声称“同一 metadata commit”，实际先 `advance` 写 `cr.md`，再逐 repo 调用 `merge-metadata`，每次只 CAS backlog。
- **影响/风险**：任一步失败会留下 `merging + 部分 merge-commits`；traceability、归档预检和清理会基于不完整集合。
- **修复**：增加 `crctl merge-finalize --manifest <json>`，一次校验所有 repo/trunk/source/preflight/merge SHA，内存生成 `cr.md + backlog` 候选并同批 CAS、单 commit、单审计事件；废弃逐仓公开写入口。

### TCA-006：跨仓 merge 没有持久化事务日志，恢复入口本身不可写

- **级别**：P0
- **位置**：`merge-feature-branch/SKILL.md:123-152,175-181,242-246`
- **证据**：进程若在首个 trunk push 后退出，没有持久化阶段记录。补偿失败时要求写 `_backlog.yml#merge-recovery`，但 crctl 无该子命令且文件被 guard deny。远端 stale 在本地 merge commit 已创建后只要求“重新运行”，没有清理本地候选。
- **影响/风险**：多仓部分发布、部分补偿、metadata 未发布等状态无法确定性恢复；重跑可能漏记已合并仓或受残留本地 commit 干扰。
- **修复**：把 merge 算法下沉为版本化执行器/crctl 子命令族，建立受控 `change-requests/{cr}/merge-recovery.yml`，记录 `prepared -> committed-local -> pushed[] -> compensated[] -> finalized`；每个远端副作用后立即 CAS 记账，重试先 reconcile 再继续或补偿。

### TCA-007：注册与远端恢复的多 worktree 创建不可幂等

- **级别**：P0
- **位置**：`requirement-register/SKILL.md:56-90,124-131`；`resume-from-remote/SKILL.md:52-64,100-105`
- **证据**：注册先把 CR 推到 trunk，再逐仓创建 worktree；任一仓失败只说“交由受控清理入口”，没有真实入口。resume 第二仓失败后，重试会因第一仓 already exists 而整体停止。
- **影响/风险**：留下已注册 CR、部分本地分支/worktree、部分远端分支，既不能继续 PRD，也不能由只接受终态的归档清理。
- **修复**：新增幂等 `crctl workspace ensure <cr>` 与 `workspace cleanup-partial`，识别 missing/branch-only/worktree-only/healthy/stale-metadata；正确存在即跳过，异常状态结构化修复。

### TCA-008：merge 后主 checkout 与 CR worktree 的权威状态未收敛

- **级别**：P0
- **位置**：`merge-feature-branch/SKILL.md:162,187-191`；`writeback-prd-sdd/SKILL.md:57-68`；`writeback-tasks/SKILL.md:56-57`；`writeback-traceability/SKILL.md:75-76`
- **证据**：merge metadata 在 trunk 推进到 `merging`，又把主 checkout 的 `STATUS_DIVERGED` 视为预期，并在 CR worktree 调 `next`。三个 writeback Skill 却要求在 `<knowledge-base worktree>` 提交 baseline。
- **影响/风险**：writeback 可能在仍为 `code-approved` 的 requirement 分支运行，或把 baseline commit 提交到已合并过的旧 CR 分支而非 trunk；两个位置的 `crctl next` 不一致。
- **修复**：明确 phase handoff：merge-finalize 成功后运行上下文切到 knowledge-base trunk；writeback/archive 只接收 `operational_workspace=trunk checkout`，CR worktree 从此只读等待清理。Pipeline 必须机器传递该字段。

### TCA-009：`casWriteMulti` 的“全有或全无”在崩溃时不成立

- **级别**：P0
- **位置**：`crctl.mjs:764-785,2058`
- **证据**：实现依次 `renameSync` 多个文件，注释承认 rename 之间崩溃会留半状态。测试只覆盖 CAS 在 write/rename 前失败。
- **影响/风险**：approval、review-record、cr-init、archive-move 都可能出现部分文件已替换、部分仍旧值；Git 未提交不能自动恢复业务一致性。
- **修复**：实现轻量 durable transaction：temp + transaction manifest + before/after hash + fsync + 完成标记；crctl 启动先恢复未完成事务。另应减少投影，把同一事实集中到一个 canonical 文件。新增 `CRCTL_FAULT_AT=rename:N` 测试。

## 4. P1 发现：写回、评审闭环与治理层

### TCA-010：archive 四文件事实仍被拆成两次写入

- **级别**：P1
- **位置**：`skills/cr/cr-archive/SKILL.md:43-81`；`crctl.mjs:1706-1772`
- **影响/风险**：先 `advance` 改 `cr.md`，再 `archive-move` 改三本账，中断后留下“archived 但仍在 backlog”。当前 repair 文案不等于原子完成。
- **修复**：新增 `crctl archive-finalize`，一次执行 gate、生成四文件候选、归档通知和单 commit；cleanup 独立为可重试 `cleanup-cr`。

### TCA-011：checkpoint 文本与实现语义不一致

- **级别**：P1
- **位置**：`push-progress/SKILL.md:62-75`；`crctl.mjs:2168-2189,2232-2248`
- **影响/风险**：Skill 未传 `--remote-ref` 却声称更新该字段；文本说按 repo 覆盖最新 checkpoint，实现无限追加；逐仓失败留下部分 metadata。
- **修复**：用 `checkpoint-record --manifest` 单次写本轮全部 repo SHA、remote-ref、batch-id；按 `(batch-id, repo)` 幂等，分开 history 与 latest projection。

### TCA-012：测试报告、测试轮次和 traceability 不是同一写入

- **级别**：P1
- **位置**：`write-test-report/SKILL.md:47-80`；`code-implementation.pipeline.json:159`；`crctl.mjs:2703-2750`
- **影响/风险**：`crctl test` 直接覆盖 report/log，没有状态守卫、CAS、attempt bump 或 traceability 投影；Skill 再要求模型手写 traceability 和单独 attempt。Pipeline 声称 `--bump-attempt` 会级联，实际命令不存在。
- **修复**：扩展为 `crctl test-record`：仅 developing 可用，一次写 report、evidence manifest、review-loop tests、traceability tests；正文分析经临时 payload 合并。

### TCA-013：`feedback-writeback` 在合法状态下无法发送完成事件

- **级别**：P1
- **位置**：`feedback-writeback/SKILL.md:9,23,51-101,126`；`crctl.mjs:2326-2331`
- **影响/风险**：Skill 只允许 archived/rejected/withdrawn，Step 4 的 `inbox-emit` 明确拒绝终态。Skill 还直接修改 baseline traceability，并建议手动创建空文件。
- **修复**：新增终态可用 `history-event`，或把事件写入 history 条目；新增 `writeback-feedback.mjs` 做确定性追加、CAS 和校验。

### TCA-014：质量 Skill 的只读/写入契约矛盾

- **级别**：P1
- **位置**：`review-alignment/SKILL.md:11,37,62-106`；`change-impact-analysis/SKILL.md:60-108`
- **影响/风险**：`review-alignment` 标记 `readonly: true`，正文却写 drift 和 summary；两个 Skill 直接改同一 traceability，可能互相覆盖或写出不同 schema。
- **修复**：修正 readonly；把 drift/stale/change-log 变换下沉到 `traceability-drift.mjs`，输入 payload，脚本负责 schema、CAS、幂等和 summary 重算。

### TCA-015：controlled-shell 声称校验 caller，实际只记录

- **级别**：P1
- **位置**：`controlled-shell/rules.json:3-24`；`controlled-shell/SKILL.md:25,63`；`crctl.mjs:501-555`
- **影响/风险**：文档声称“子命令 + 形态 + 调用者三元放行”，loader 丢弃 callers，rules 也全是 `"*"`。任何调用者都可执行所有 allowlisted 写操作。
- **修复**：要么删除 caller 安全承诺；要么真正加载 callers，并由不可伪造的执行上下文传 actor/skill，禁止 CLI 任意 `--caller` 自报。

### TCA-016：多条恢复/提交命令不命中真实入口

- **级别**：P1
- **位置**：`requirement-register/SKILL.md:65-68`；`writeback-prd-sdd/SKILL.md:57`；`resume-from-remote/SKILL.md:105`；`cr-archive/SKILL.md:122`
- **影响/风险**：平台 `runGit` 示例传 crctl 专属 `--template/--cr`；`crctl git checkout --` 不匹配 allowlist 且缺文件；`git worktree prune` 不在 allowlist；`Remove-Item` 绕过 controlled-shell。恢复建议本身不可执行。
- **修复**：统一为真实 `crctl git` CLI，或新增 `restore-paths`、`workspace prune`。R12 对示例实际跑 rules regex。

### TCA-017：Pipeline 大量复制 Skill 完整算法

- **级别**：P1
- **位置**：`feature-writeback.pipeline.json:40`（merge 10 步，约 1,814 字符）；`requirement-authoring.pipeline.json:88`（39 行）；`code-implementation.pipeline.json:78,150,218`
- **影响/风险**：同一 Git/owner/review 算法双份维护；merge 联调测试甚至要求两份文本同步存在，主动固化第二事实源。
- **修复**：Pipeline prompt 只留 input/output mapping、passCondition、reviewLoop 和 `ref`。设置 report 阈值：prompt 超过 12 行或 1,000 字符且含多个命令时报警。

### TCA-018：Agent 保存状态机与错误事实源，并承担直接写入

- **级别**：P1
- **位置**：`agents/dev-agent.md:30-49`；`agents/requirement-writer.md:14-39`；`agents/customer-support-agent.md:68-79`
- **影响/风险**：dev-agent 复制状态链，且从 v2 已无 status 的 backlog 读取状态；requirement-writer 复制八步 Pipeline；customer-support-agent 直接写反馈与索引但无对应 Skill。
- **修复**：Agent 只保留意图路由，状态统一调用 `crctl status/next`；新增 `record-feedback`，补齐前客服只输出候选 payload。

### TCA-019：crctl 的“写入 + Git commit”失败不回滚

- **级别**：P1
- **位置**：`crctl.mjs:1196-1252,1276-1323`
- **影响/风险**：`advance` 先改 status，commit 失败后要求人工提交；approve 也留下两文件未提交且不发 outbox。crctl 尚未真正拥有原子 commit。
- **修复**：写前完成 Git dirty/preflight；commit 失败按候选 hash 自动恢复 before image，或提供 `crctl recover <tx-id>`，禁止依赖人工理解半状态。

### TCA-020：现有检查器无法验证核心边界

- **级别**：P1
- **位置**：`lint-prompts.mjs:14,168-218`；`check-agents-contract.mjs:17-28,104-126`；`check-skill-matrix.mjs:1-18`
- **影响/风险**：R1-R9 没有命令存在性、状态可达性、allowlist shape、章节引用、重复算法；Agent checker 明确跳过不变式 4；matrix 不检查 name/写入章节。TCA-001/003/004/016/018 均在 0 findings 下存在。
- **修复**：按第 7 节实现 R10-R21；无法静态证明的项从“通过”改为“未检查”。

### TCA-021：测试与 CI 主要证明文本存在和当前实现自洽

- **级别**：P1
- **位置**：`crctl.test.mjs:1291-1328,1654-1665,1751-1771,3446-3468`；`.github/workflows/check-skill-matrix.yml:1-32`
- **影响/风险**：owner-set 只测 backlog；cr-init 不测三个不同 owner；casWriteMulti 不测 rename 中断；merge 联调只做 `includes()`；tools CI 只跑 matrix/Agent，不跑 lint、crctl tests、writeback tests和 Pipeline 合约。
- **修复**：补第 8 节测试矩阵和统一 CI；每个语义修复先增加旧行为下失败的测试。

## 5. P2 发现：低副作用能力与文档漂移

### TCA-022：固定规模数字漂移

- **级别**：P2
- **位置**：`ARCHITECTURE.md:19` 写“59 Skill”；实际 active 为 57；`docs/QODER-使用指南.md:589` 写 57
- **风险**：架构入口给出错误能力规模。
- **修复**：删除可从索引计算的固定数量；确需展示时由检查器生成。

### TCA-023：章节和步骤引用悬空

- **级别**：P2
- **位置**：`merge-feature-branch/SKILL.md:21` 写“见 Step 4”但调用在 Step 5；`:193` 引用不存在的 `§2.1`；`cr-archive/SKILL.md:73-85` 缺 Step 4、重复序号 4、保留空壳 Step 5；`extract-market-insight/SKILL.md:99` 把 Step 3.5 写成 Step 4
- **风险**：恢复和人工核对跳到错误章节。
- **修复**：增加 heading/Step 目标检查，删除空壳标题。

### TCA-024：ignore 与历史注脚掩盖主契约

- **级别**：P2
- **位置**：merge/archive 各 13 个 ignore；当前契约约 516 个历史 CR 引用
- **风险**：ignore 增长不可见，历史原因挤占当前输入/输出/失败语义。
- **修复**：R15 输出基线增量；ignore 使用 `rule/reason/scope/expires`；纯历史迁到 CR/ADR/git。

### TCA-025：`focus-briefing` 的只读索引说明与真实写入不一致

- **级别**：P2
- **位置**：`skills/_index.yml:69-72`；`focus-briefing/SKILL.md:14,53-76`
- **风险**：Skill 覆盖 `focus.yml` 并修改竞品索引，调用方却按“只读”授权，且无 validate/恢复说明。
- **修复**：下沉为版本化脚本，或明确写入型契约、校验和幂等键；同步 index brief。

### TCA-026：客服/知识 Agent 的能力声明先于可调用 Skill

- **级别**：P2
- **位置**：`customer-support-agent.md:68-79`；`agents/_index.yml:161-218`；`agent-skill-matrix.yml:151-193,234-237`；`README.md:134-135`
- **风险**：README 已承认 known gap，但 Agent 正文仍把反馈/知识写入描述成现有能力。
- **修复**：新增 `record-feedback`、`write-tech-note` 前把能力降为候选 payload；Skill 落地后再更新矩阵。

### TCA-027：README/Agent 维护状态映射与旧路径噪音

- **级别**：P2
- **位置**：`README.md:181-232` 完整复制状态图/review 路由；`dev-agent.md:30-49`；多个 Agent 仍出现 `_archived/`；`requirement-register/SKILL.md:18` 用“main”描述动态 trunk
- **风险**：README 和 Agent 成为状态机/流程第二事实源；主干名变化时误导。
- **修复**：README 仅保留阶段总览和权威链接；状态图从 dir-graph 生成；Agent 只写 `crctl next`；删除旧路径和固定 main 用词。

## 6. 目标逻辑架构

| 层 | 应保留 | 应下沉/删除 |
|---|---|---|
| Agent | 意图识别、actor 权限、选择 Pipeline/Skill、展示结果 | 状态链、Git/worktree、账本字段、完整步骤 |
| Pipeline | node 顺序、输入/输出映射、reviewLoop、passCondition、失败中止、workspace phase handoff | 命令序列、错误码表、转换和补偿算法 |
| Skill | 业务判断、调用深模块、输入输出、失败分类与恢复入口 | 逐行 YAML、逐仓 Git、重复 crctl |
| crctl | 状态/gate/CAS/审批/受控账本/审计/原子 commit、resolver、事务恢复 | PRD/SDD 质量判断和 LLM 结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability/focus 确定性转换与自检 | 状态推进、人工审批、直接 push |
| README/ARCHITECTURE | 人读阶段总览、概念边界、权威入口 | 完整 CLI、状态副本、固定计数、补偿细节 |

### 6.1 建议的最小深模块接口

| 接口 | 解决问题 |
|---|---|
| `crctl cr-init --owner-requirement --owner-development --owner-test` | 三角色注册 |
| `crctl owner-handover --role --to --note [--grant]` | owner、history、通知、授权单事务 |
| `crctl approve --grant` 支持 approve/reject | 平台审批桥接 |
| `crctl workspace ensure/cleanup-partial` | worktree 幂等恢复 |
| `crctl checkpoint-record --manifest` | 多仓 checkpoint 单批落账 |
| `crctl merge prepare/publish/finalize/recover` | 多仓发布、journal、status+metadata |
| `crctl archive-finalize` + `cleanup-cr` | 归档事实与清理分离 |
| `crctl test-record` | report、attempt、trace tests 同批 |
| `traceability-drift.mjs` / `writeback-feedback.mjs` | baseline 确定性转换 |

不建议引入数据库、通用 Pipeline Runner、分布式锁或新的 YAML 台账框架。使用现有 Node 标准库、Git、受控 manifest 和小型版本化脚本即可。

## 7. 增强检查器规则

### 7.1 `lint-prompts.mjs`

| 规则 | 级别 | 检查内容 | 可捕获案例 |
|---|---|---|---|
| R10 crctl 命令存在性 | block | 从 dispatch/help 建 capability map，校验顶层/二级命令和必填旗标 | 不存在的恢复/账本入口 |
| R11 状态转换可达性 | block | 解析 `--to/--trigger/--expect`，与状态机精确对照 | TCA-004 |
| R12 Git shape | block | 解析 `runGit`/`crctl git` 参数并跑 rules regex；禁止裸 PowerShell 清理 | TCA-016 |
| R13 引用完整性 | warning/block | Step、§、heading、错误码、相对链接必须存在 | TCA-023 |
| R14 Pipeline 算法重复 | report | node 有 ref 且 prompt >12 行/1000 字符、含多个命令或与 Skill 高重合 | TCA-017 |
| R15 ignore 治理 | warning/block | reason、scope、rule；输出总量/增量，P0 ignore 升 review | TCA-024 |
| R16 层级越权 | block | Agent 出现 Git/账本/worktree/状态转换；Pipeline 出现账本算法 | TCA-018 |
| R17 readonly 一致性 | block | readonly 元数据与写动词/输出文件冲突 | TCA-014/025 |
| R18 受控写入口 | block | 受保护路径写动词必须对应 capability map 中的合法 crctl 命令 | merge-recovery |

实现要求：按行和反引号代码块解析，不用跨行宽泛 `\s`；JSON prompt 从解析后的 node 读取；CRLF 先统一；解析失败硬失败。

### 7.2 `check-skill-matrix.mjs`

新增：

1. active path 存在，frontmatter name 等于 id；
2. 写入型 Skill 声明读取、写入、校验、失败、幂等/恢复；
3. 状态型 Skill 增加最小 `states.from/to/trigger`，与状态机交叉验证；
4. Pipeline owner 对 node.ref 有 owns/can-call 权限；
5. 固定 active 数量出现时告警；
6. `readonly`、index brief、正文行为一致。

### 7.3 `check-agents-contract.mjs`

把当前未检查的不变式 4 变成规则：

- 禁止 Agent 出现 `runGit`、裸 Git、`casWrite`、worktree 拼接；
- 禁止描述 backlog/history/cr.md status/approval/annotation 的写算法；
- 状态读取必须路由 `crctl status/next`，不得读 backlog status；
- 正文引用的 Pipeline/Skill 必须在矩阵允许范围；
- human approval 后只能路由 approve Skill，不复制命令或目标状态。

### 7.4 新增轻量 `check-pipeline-contract.mjs`

1. 用状态型 Skill frontmatter做跨节点符号推演；
2. 验证节点前后状态衔接；
3. 验证 reviewLoop repairRef/replayNodes 存在且顺序可达；
4. 验证 maxAttempts 耗尽后不能进入 human approval；
5. 验证 human approval pass/reject 均有合法消费节点；
6. 验证 required input 被传给 Skill/crctl，Skill 必填参数无丢失；
7. 验证 phase handoff 后使用 trunk 还是 CR worktree，不允许模糊占位符；
8. R19-R21 分别覆盖状态推演、参数传递、workspace authority。

## 8. 测试策略

### 8.1 必须新增的红绿回归

| 测试 | 旧行为下失败点 |
|---|---|
| 三个 owner 用不同值注册 | development/test 被写成 requirement |
| handover 后比对 cr.md/backlog/history/notify | 当前只有 backlog 改 |
| 四 Pipeline 非 TTY 审批 grant | 当前拒绝 |
| dev-plan NORMAL block 真命令 | 当前 trigger 不存在 |
| merge-finalize 三仓 manifest 第二项非法 | 当前留下 status/第一项 metadata |
| archive-finalize 任一候选失败 | 当前可能留下 archived + backlog |
| test-record block/pass 两轮 | 当前 report/attempt/trace 不一致 |
| feedback terminal event | 当前 inbox-emit 拒绝 |
| 文档 Git 命令跑 matcher | checkout/prune/Remove-Item 失败 |

### 8.2 Git 沙箱

使用临时目录创建 3 个 bare remote 和 3 个 checkout，运行真实 Git：

1. 三仓成功，其中一仓无改动；
2. 第二仓 push 被拒，第一仓补偿成功；
3. 补偿前远端推进，返回 blocked 且 journal 可恢复；
4. 代码仓 push 成功、metadata push non-fast-forward；
5. 本地 merge commit 后远端 stale，重试先清候选；
6. requirement 分支已 merge 后又 revert 的重试；
7. linked worktree、Windows 路径和 long path；
8. 非 TTY、编辑器禁用、凭证 prompt 禁用。

### 8.3 故障注入

增加仅测试可用 `CRCTL_FAULT_AT`：temp 写后、每个 rename 前后、Git add/commit/push 前后、audit/outbox 前后、每个 repo worktree add/push/revert 前后强制退出。每点断言文件 hash、local/remote ref、journal phase、audit/outbox、recover 结果，不能只断言退出码。

### 8.4 P0 场景矩阵

附件 A-O 全部参数化到 registration、handover、merge、archive。每 case 固定输出 initial state、action、exit code、file hashes、local refs、remote refs、audit/outbox、recovery command。CRLF/LF 对同一输入必须得到相同 digest；跨行解析失败硬失败。

## 9. 分批实施步骤

### CR-A：解除当前主流程阻断

范围：TCA-001/002/003/004。

1. 扩展 cr-init 三 owner 参数和测试；
2. 实现 owner-handover 原子命令和授权；
3. 定义 Pipeline approval grant 输入/输出，支持 reject；
4. 修正 dev-plan trigger；
5. 加 R11 和参数传递检查；
6. 全量跑 crctl、Pipeline contract、matrix、Agent contract。

完成门：四条主 Pipeline 的 approve pass/reject 可执行；三角色不会塌缩。

### CR-B：merge 与 workspace 事务链

范围：TCA-005/006/007/008/009/015/016。

1. 定义 merge journal 与 fault points；
2. 实现 workspace ensure/cleanup-partial；
3. 实现 merge prepare/publish/recover/finalize；
4. merge-finalize 一次写 status+metadata；
5. 明确 writeback handoff 到 trunk；
6. 收紧 controlled-shell caller/shape；
7. 建 3 bare remote 沙箱；
8. Skill 缩成业务判断，Pipeline 删除算法。

完成门：任一 push/rename/中断都能由 journal 恢复，无部分 metadata。

### CR-C：archive、checkpoint、test 与 traceability

范围：TCA-010/011/012/013/014/019。

1. archive-finalize 四文件事务；
2. cleanup-cr 独立重试；
3. checkpoint manifest 批量落账；
4. test-record 同批写证据/轮次/trace；
5. feedback/drift 版本化脚本；
6. commit 失败自动回滚或 recover；
7. 每个旧半状态补红测。

完成门：所有 P1 写入有唯一入口、幂等键、失败零写入或可执行 recover。

### CR-D：检查器与 CI

范围：TCA-020/021/023/024。

1. 落地 R10-R21；
2. 新增 check-pipeline-contract；
3. ignore 基线与增量门禁；
4. CI 运行 lint enforce、三个 contract checker、crctl tests、writeback tests、JSON parse；
5. Windows + Ubuntu 跑关键测试；
6. 静态“文本存在”测试改为结构/行为测试。

### CR-E：P2 与文本去重

范围：TCA-017/018/022/025/026/027。

1. 精简 6 个超长 Pipeline prompt；
2. 精简 dev/requirement/quality Agent；
3. 补 record-feedback，未补前降级能力；
4. 修 readonly/index brief/章节引用；
5. 删除固定计数、旧 `_archived`、固定 main；
6. 历史 CR 注脚迁移到 ADR/CR。

## 10. CI 与长效机制

统一 workflow 在 `skills/**`、`agents/**`、`pipeline-templates/**`、`dir-graph.yaml`、`rules.json`、检查器或脚本变化时运行：

```text
lint-prompts --mode enforce
check-skill-matrix
check-agents-contract
check-pipeline-contract
node --test skills/shared/crctl/scripts/test/*.test.mjs
node --test skills/writeback/scripts/test/*.test.mjs
Pipeline JSON parse
```

长效机制：

1. crctl dispatch/help/Skill 索引从同一 capability API 导出；
2. 状态型 Skill 只声明最小 from/to/trigger，checker 与权威状态机交叉验证；
3. P0 错误 JSON 必须含 `sideEffects`、`txId`、`recoverCommand`；
4. ignore 输出总量和 diff，新增 P0/P1 ignore 必须有规则号、原因、评审人和过期条件；
5. Pipeline prompt 长度/命令数、Agent 状态词命中只增不减时告警；
6. active 数量只在生成报告出现；
7. Linux 验证 CI，Windows 验证 CRLF、long path、PowerShell adapter、linked worktree；
8. 定期用 bare remote 演练 partial push、remote stale、process kill、cleanup retry；
9. 本报告不参与运行时路由。

## 11. 完成标准

- 三角色注册与移交在 cr.md/backlog/history 中一致；
- 四个人工审批 pass/reject 在平台和本地 CLI 都有真实、不可绕过的路径；
- 所有 `advance` 与状态机精确可达；
- merge/archive/checkpoint/test 的同一事实不再由多次独立写入拼成；
- 多仓任一 push/中断均有持久化、幂等恢复入口；
- 主 checkout 与 CR worktree 的 phase authority 唯一且机器可读；
- 文本中的 crctl/Git/Step/错误码引用全部真实；
- P0 场景 A-O 有可执行回归测试；
- tools CI 运行全部 checker 和行为测试；
- Pipeline 不复制 Skill 算法，Agent 不复制状态机和写入细节；
- 版本化脚本只做确定性转换，crctl 不做 LLM 业务判断；
- README/ARCHITECTURE 不维护固定计数或第二份执行契约。

最终目标是把“文本承诺的原子性”变成“代码和故障测试证明的可恢复事务”，同时缩短 Agent、Pipeline 和 Skill，让每层只保留它真正拥有的逻辑。

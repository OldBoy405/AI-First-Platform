# CONTEXT.md — AI First Platform 通用语言（Ubiquitous Language）

本文件只记录已敲定的领域术语及其精确含义，不记录实现细节与决策过程。
术语一经写入即视为规范；新用法与既有定义冲突时，先在此处解决，再改文档。

## 术语表

### 成熟度 Scope（Maturity Scope）

成熟度快照（`maturity_snapshot`）的聚合层级。**有且仅有三个层级：org / user / project**。

- **org**：全组织聚合，`scope_id` 恒为 `'·'`。
- **project**：Multica 项目，是本平台的天然组织单元——Team Agent、共享队列、CR 归属均以 project 为锚点，"哪个团队用得好"由 project 聚合回答。
- **user**：个人，仅在个人榜开关开启时呈现（见《P3-组织智能设计》§1.5）。

**Department（部门）不是本平台的领域概念**（2026-08-07 敲定）：Multica 无部门模型，
P3 不引入 `department` 表或成员部门归属；曾出现在设计稿中的部门聚合、部门排名、
按部门下钻一律由 project 层级替代。未来若出现真实的多层级管理诉求，再作为独立的
schema 变更引入。

### 观察期（Baseline Calibration Window）

成熟度看板上线后的前 **4 周**（2026-08-07 敲定）。期内快照管道照常每日计算原始
指标值入库，但看板**只呈现原始值与趋势，不呈现雷达图总分**（显示「基线校准中」）。
观察期结束后，用实测分布的分位数规则（floor ≈ P10、target ≈ P75，规则写在
`maturity-config.yaml` 内）自动生成第一版基线，此后正式计分。
含义：**任何成熟度分数都必须有实证基线支撑，禁止拍脑袋初值直接计分**；
口径（`maturity-config.yaml`）变更走 git PR + Owner 审批，`config_rev` 保证可追溯。

### 影子工程 / bypass-commit

绕过 CR 流程直接向 trunk 写代码的行为（2026-08-07 敲定探测口径）。本地执行模式下
平台无法强制所有代码经 CR，但可以让绕过变得**可见**。P3 的探测信号为**前缀层**：

- trunk 提交前缀不在白名单（`wip:` / `[cr] ` / `merge(`）且不属于该仓特许格式
  （如 tools 仓 conventional commits）→ `bypass-commit`，severity `warn`；
- trunk 出现 `wip:` 前缀 → 单独一类提醒（severity `info`），不计入 bypass 计数。

扫描范围 = `dir-graph.yaml#repositories` 声明的全部仓，每仓口径随白名单配置走。
**前缀合规 ≠ 通路合规**（前缀可手写伪造）；通路层对账（controlled-shell 审计行 ↔
trunk 提交）属新采集，显式延后到 P3+，不属于 bypass-commit 的当前语义。

### CR 状态机口径（16 态 vs 15 态）

文档口径与代码口径的换算于 2026-08-07 重申（沿 AGENTS.md 工程纪律 2 已敲定口径）：状态机 = **15 个具名状态
+ 注册前 `(new)`**（口语「16 态」含 (new)）；转移 = 25 条声明，wildcard 展开后 47 条。
multica 代码（`cr-status-badge.tsx`）按 15 态渲染是正确的；PRD §5.2.3 与 P0 文档中
「16 态」的表述指含 (new) 的口语口径，写正式断言时必须写明用的是哪个口径。

### 上游设计疑点（upstream-design blocker）

开发计划与 TASK 评审发现的、只能通过修订已审批 SDD 才能解决的阻断问题。它不属于 plan/TASK 自动回修范围，必须回到既有技术设计修订、评审与审批流程处理。
_Avoid_: 普通回修 blocker、TASK blocker

### CR 关联 Issue（原「壳 Issue」，已废止）

`cr.shell_issue_id` 指向的 Issue（2026-08-07 敲定，见 ADR-0001）：CR 与项目的
关联锚点，由 crsync 从 `cr.md#origin={type:issue}` 回填。**「壳 Issue」三件套
设计（issue.cr_id 指针 / 7 态看板映射 / 禁拖拽）已正式废止，不再承诺实现**；
「壳 Issue」一词不得再用于新文档。TASK 子 Issue 投影的锚点随之一并悬置。

### origin（修复归因）

cr.md frontmatter 的**可选**字段（2026-08-07 敲定），指向本 CR 所修复的原 CR
（`origin: CR-2026-XXX`）。仅修复类 CR 填写；登记时由 requirement-register 提示。
**变更失败率的唯一归因信号 = 显式 origin**，不用「同 spec_id + 14 天」启发式
（specs 基线是累积文档，同 spec 多 CR 演进是常态，启发式会系统性虚高）。
origin 同时服务跨 CR 追溯：修复链一跳可达。

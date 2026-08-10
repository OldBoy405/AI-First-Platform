# CONTEXT.md — AI First Platform 通用语言（Ubiquitous Language）

本文件只记录已敲定的领域术语及其精确含义，不记录实现细节与决策过程。
术语一经写入即视为规范；新用法与既有定义冲突时，先在此处解决，再改文档。

## 术语表

### Tools Root

目标 workspace 所使用的 tools 包根目录。其唯一声明来源是 Installation Workspace 目录图中的 `workspace.tools_package_path`；相对值以 Installation Workspace 为基准，绝对值直接使用，两者最终归一到真实目录。该声明是使用 tools 流程的前置条件：缺失或无效即表示 workspace 未绑定 tools 包，不从同名目录、当前目录或调用方自身位置推断。

所有调用方共享同一 Tools Root 契约，但绑定时机分为两类：动态调用方在执行流程时解析；IDE hooks、CI 等静态集成在安装配置时物化。统一的是路径事实源与有效性语义，不要求所有调用方共享一个运行时解析模块。

### Operational Workspace

本次 CR 操作实际读写阶段产物的 knowledge-base checkout；可以是主 checkout，也可以是该 CR 的 linked worktree。
_Avoid_: Installation Workspace、tools checkout

### Installation Workspace

声明并锚定 Tools Root 的 knowledge-base 主 checkout。linked worktree 仍共享该安装基准，不复制或改写自己的 tools 包绑定。
_Avoid_: Operational Workspace、当前工作目录

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

文档口径与代码口径的换算于 2026-08-09 更新：状态机 = **15 个具名状态
+ 注册前 `(new)`**（口语「16 态」含 (new)）；转移 = **27 条声明，wildcard 展开后 49 条**。
CR-2026-026 在既有 25/47 基线上新增两条开发计划评审转换：
`review-dev-plan:block -> write-dev-plan` 与
`review-dev-plan:upstream-design-blocker`。正式断言必须以
`../tools/dir-graph.yaml#change-request-track.state_machine` 的当前内容为准，不得把历史
25/47 口径继续描述成现状。
multica 代码（`cr-status-badge.tsx`）按 15 态渲染是正确的；PRD §5.2.3 与 P0 文档中
「16 态」的表述指含 (new) 的口语口径，写正式断言时必须写明用的是哪个口径。

### 上游设计疑点（upstream-design blocker）

开发计划与 TASK 评审发现的、只能通过修订已审批 SDD 才能解决的阻断问题。它不属于 plan/TASK 自动回修范围，必须回到既有技术设计修订、评审与审批流程处理。
_Avoid_: 普通回修 blocker、TASK blocker

### CR 阶段文档（CR-local artifact）

服务单个 CR 审批与交付过程的 PRD、SDD、Plan、TASK、测试报告和评审记录。其生命周期
随 CR 结束，不等同于跨 CR 累积维护的产品基线文档。

CR 阶段 PRD 与产品区活文档是两个不同概念；不得仅因二者都叫“PRD”就默认使用同一
标识或内容契约。

### specs 基线文档（baseline artifact）

多个已完成 CR 的有效变更逐里程碑累积形成的发布基线，不是任一 CR 阶段文档的副本。
不得用单个 CR 文档覆盖整份基线。

### CR 目录索引（change-requests/_index.yml）

CR 的全生命周期轻量目录，用于登记身份和基本生命周期摘要。它不是当前状态或历史详情
的权威来源，不复制完整历史记录，也不在归档时删除 CR。

### CR 参与仓（participating repository）

被工作区明确声明为参与 CR 生命周期的仓库。当前模型中，每个参与仓都参与每个 CR，
不存在只写在流程说明里的隐藏仓库，也不存在每 CR 单独选择仓库的第二套参与模型。

### 归档事件（archive event）

CR 进入最终态时产生的生命周期事件，携带 final status、归档原因和可选 writeback
spec。它与 backlog→history/index 的归档移动是同一个业务事实：不得出现“事件已发但
未归档”或“已归档但事件丢失”。

### CR 终态查询（terminal CR lookup）

对已结束 CR 的状态和下一步进行只读查询。终态没有合法后继；终态查询不会恢复 CR 的
可写性。若活动视图与历史视图同时声称拥有同一 CR，必须视为数据冲突。

### 正常归档与提前终止

- **正常归档（archived）**：完整走过开发、代码审批、合并和回写链路的完成态。按现有
  流程必然产生非空 TASK 集合；缺少任务或存在未完成任务都表示流程不完整。
- **提前终止（rejected / withdrawn）**：可在生命周期任意 active 状态终止，可能尚未
  产生 TASK 或回写产物，不适用正常归档的任务与回写门禁。

未来若需要“无 TASK 但正常完成”的业务流程，必须显式定义，不得以缺失产物作为领域
信号。

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

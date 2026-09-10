---
id: CR-2026-062-plan
type: PLAN
cr-ref: CR-2026-062
sdd-ref: "change-requests/CR-2026-062/sdd.md"
target-version: 0.35
status: draft
created: 2026-09-09T21:14:52+08:00
updated: 2026-09-09T23:33:03+08:00
---

# CR-2026-062 开发计划（Team Agent 和 Private Ask 发送框 UI 优化）——二次重建版

输入：**最新批准 SDD**（`review-annotations/sdd.yml` verdict=pass、blockers=[]、subject-sha256 `5259087713930e7eee00bb6074ae0d4a3d78f9df4eb18d1256401e6afb5fdf28`，评审证据提交 `b2329dd0`，人工二次审批提交 `493ede05`；含 B-005 修订：`listTasksByIssue` 按 `Promise<AgentTask[]>` 数组消费 + `tasks.find(task => task.id === sentTaskId)` 唯一选取 + 未命中回落 items-only）+ PRD（FR-1~8 / AC-1~8）。目标版本 `0.35`（继承 cr.md，未改写）。

> **二次重建声明（非从零新建）**：本文件覆盖首轮重建 `ca562bc8`/`8d7c229a` 的 plan.md。首轮重建已被 review-dev-plan 第二轮 BLOCK（canonical `review-annotations/dev-plan.yml`，评审提交 `246a5109`）判 UPSTREAM（B-005，SDD 侧）并留下本链责任 blocker **B-006**（plan/TASK 侧）；B-005 已在 SDD 修订（`fe689a97`）并经独立 `review-tech-design` PASS（`b2329dd0`）+ 人工二次审批（`493ede05`）闭环。本轮重建继承的**双份责任**：
>
> - **同步 B-005 数组语义**（§1/§2/§4.1/§6.1 FR-5 及 TASK-02）：`api.listTasksByIssue(sentIssueId)` 返回 `Promise<AgentTask[]>`（client.ts L2478；`AgentTaskListSchema = z.array(AgentTaskSchema)` schemas.ts L2300，解析失败 fallback `[]`）——先定义 `tasks` 数组，再以 **`taskEntry = tasks.find(task => task.id === sentTaskId)`**（`AgentTask.id: string`，types/agent.ts L279）按 id 唯一选取最近一次发送的 task；空列表/非空未命中/查询 disabled/加载中/fallback `[]` → `taskEntry=undefined`、`taskActive/taskTerminal=false`、活动性回落 **items-only**，**绝不借用容器 Issue 其他 task 的状态**；测试矩阵含 §6.9-2(iv)(v) 未命中两行。
> - **关闭 B-006 符号级零差异证据缺口**：`cmd-08` 的 `crctl git diff --name-only` **仅保留文件白名单职责**（B-003 已使其受控可执行，但 name-only 不含符号/签名信息）；删除「name-only 清单可证明 `chat-input.tsx` 内 `ChatInput`/`ChatInputCore` 函数体与 props 签名 zero_diff / 符号在 diff 清单中零出现」的错误完成条件（该文件因修改 `ChatInputCore` 必然出现在清单）。新增**稳定符号级 zero_diff 证据 `cmd-09`**：入库的版本化检查器 `packages/views/chat/components/chat-input-zero-diff.test.ts`（§6.2 cmd-09 与 §5 门槛；受控 patch diff 的可审计判定为评审侧辅助手段，见 §6.2 注）。FR-7/AC-8/§6.2 与 TASK-01/04 完成边界同步（TASK 层落实见 write-dev-tasks 产物）。
>
> 首轮 blockers 已关闭项不重开：B-001（SDD 侧，已审批）；B-002（真实 e2e cmd-07、全量回归 cmd-04、白名单核对 cmd-08 各为稳定 cmd）；B-003（受控 `crctl git diff`，禁原生 git，路径只取 `execution_context.resources`）；B-004（逆拓扑组合回滚 RU1~RU4）。

## 0. 基线与工作区事实（落笔时实读）

- status=`tech-design-reviewed`；`crctl next`=`write-dev-plan`（humanApproval=false，why=技术设计已审批，编写开发计划）。
- 远端同步：origin/requirement/CR-2026-062 已推至 `493ede05`（push `fea83b01..493ede05`，远端携带 B-005 评审证据 `b2329dd0` 与二次审批 `493ede05`）。
- `crctl workspace inspect CR-2026-062`：ai-first-platform-docs / multica / tools 三仓 resources 全部 `healthy`、dirty=false；operationalWorkspace 正常解析。
- 代码事实源：multica requirement worktree HEAD `117fc6be657f91d43df5892b52782a18329c7aed`（SDD 全部 21 条既有实现依赖的锚定 SHA）。本计划 B-005/B-006 相关代码事实均在该 SHA 实读核实：`interface ChatInputProps`（chat-input.tsx L58–160）、`export function ChatInput`（L162–790）、`export interface ChatInputDraftAdapter`（L810–827）、`interface ChatInputCoreProps extends ChatInputProps`（L829–833）、`export function ChatInputCore`（L835–文件尾 1154）；`api.listTasksByIssue`（client.ts L2478，`Promise<AgentTask[]>`）；`AgentTask.id: string`（types/agent.ts L279）。
- 本 CR 是纯前端体验 CR：实施全部落在 multica `packages/views/`（+ `e2e/` 一个 spec + 差异文档 + 零差异检查器测试文件）+ 治理台账 `multica/CUSTOM.md`（§9 受控 sidecar）；**无 server/API/迁移/数据模型改动**（SDD §1.1 改动面白名单、§9 zero_diff）。tools 仓无实施改动（仅 cmd-08 经 tools 仓 crctl 受控执行）。
- 开工前每个 TASK 重跑 `crctl workspace freshness CR-2026-062` 复核基线（gate=implement-start 口径），按 stable symbol 定位代码，不按行号硬编码。

## 1. 交付里程碑

| 里程碑 | 内容 | 对应 TASK | 估时 |
|---|---|---|---|
| M1 共享 composer 对齐 | `ChatInputCore` wrapper（外层 `CHAT_GUTTER`）/surface（内层 `CHAT_COLUMN`+`data-slot="chat-input-surface"`）两层 DOM；surface 类名集合对齐 `ChatInput`；底栏 absolute→flow 布局（左组 wrap + 右组 shrink-0）；`ariaLabel`/`stopAriaLabel` 补传；采纳 `allowSubmitWhileRunning`；**新增入库版本化零差异检查器 `chat-input-zero-diff.test.ts`（cmd-09 符号级 zero_diff 证据，B-006）**；chat-input 组件测试新增套件 | TASK-01 | 16h |
| M2 Team Agent 面板对齐与停止路径 | 消息流根/队列栏/横幅区两层 DOM；`ModePane` 加 `@container`；`project-chat-model-row` 随独立行移除（无替换锚点）、Model/Thinking 经 `leftAdornment` 进工具栏（三态 + sr-only 类别标签）；运行中停止双源路径（`sentTaskId`/`sentIssueId` + queue items ∪ 容器 Issue 任务时间线——`AgentTask[]` 数组，`tasks.find(task => task.id === sentTaskId)` 唯一选取最近发送 task，未命中回落 items-only，B-005 口径）；项目组件测试 | TASK-02 | 20h |
| M3 Private Ask 面板对齐 | composer 外层对齐、pending-message 两层块；`private-ask-model-row` 随独立行移除（替换锚点 `private-ask-model-picker`）、控件经 `leftAdornment` 进工具栏（creator-only + sr-only）；停止路径原样；组件测试 | TASK-03 | 12h |
| M4 e2e 真跑交付与差异文档 + 全量回归 + 范围核对 | `e2e/project-chat-composer.spec.ts`（宽面板对齐/360px 窄面板/运行中停止/键盘发送，**真跑**为浏览器行为证据）；`project-chat-composer-layout-diff.md`（SDD-CLOSE-04 五项大纲）；packages/views 全量 `vitest run`；交付 diff 白名单核对（受控 `crctl git diff --name-only`，cmd-08 文件级，AC-8）；符号级 zero_diff 复核（cmd-09，B-006） | TASK-04 | 16h |
| 联调/验收/评审 | cmd-01..09 证据闭环、write-test-report、review-dev-plan/review-code、人工审批 | 非交付（审计事实承载） | 8h（1 人天） |

**估算总工时（TASK 账本口径，与 tasks/_index.yml 的 totalEstimateHours 一致）= 64h**（16h + 20h + 12h + 16h）；另计联调/验收 8h 为跨 TASK 非账本工时（不进 TASK estimate，也不写入 tasks/_index.yml）。发布经既有 CR merge 流程，不在本计划 TASK 范围内（流程控制 TASK 禁止，见 write-dev-tasks）。

## 2. 任务依赖图

```text
TASK-01 (multica packages/views/chat：ChatInputCore 两层 DOM + flow 底栏
         + aria 补传 + allowSubmitWhileRunning 采纳
         + 入库版本化零差异检查器 chat-input-zero-diff.test.ts（cmd-09，B-006）)
   │  产出：ChatInputCore surface 对齐（data-slot="chat-input-surface"）、
   │        底栏 flow 结构、可见动作判定语义、leftAdornment slot 消费契约、
   │        符号级 zero_diff 检查器（cmd-09 证据，供 TASK-04 复核消费）
   ▼
TASK-02 (multica packages/views/projects：Team Agent 消息流/队列栏/横幅两层
   │     + ModePane @container + 工具栏 leftAdornment + 双源停止路径
   │     ——B-005 口径：任务时间线为 AgentTask[] 数组，
   │       taskEntry = tasks.find(task => task.id === sentTaskId)，
   │       空列表/未命中回落 items-only，绝不借用容器 Issue 其他 task 状态)
   │  产出：面板级 @container 祖先、Team Agent composer 最终行为口径
   ├──────────────────────────────┐
   ▼                              │（@container 前置）
TASK-03 (multica packages/views/projects：Private Ask 横幅两层 + 工具栏
         leftAdornment + 停止路径原样)
   ▼
TASK-04 (multica e2e spec 真跑 + 差异文档 + 全量回归
         + 交付 diff 白名单核对（cmd-08 文件级）+ 符号级 zero_diff 复核（cmd-09）)
```

- 依赖全部为「上游产出 → 下游消费」或「共享前置」：TASK-01 的 ChatInputCore surface/flow/判定语义是 TASK-02/03 的消费契约、其 cmd-09 检查器是 TASK-04 的符号级 zero_diff 复核证据；TASK-02 的 `ModePane @container` 是 TASK-03 容器感知 gutter 变体的前提；TASK-04 的 e2e 与差异文档消费三个 TASK 的最终行为口径。
- 无环、无悬空引用；四个 TASK 同属 multica 仓（唯一代码仓），同一 implementer 串行执行（同 repo 不得并行）。
- **回滚拓扑（B-004）**：共享组件改动（TASK-01）被 TASK-02/03 消费、TASK-02 被 TASK-03/04 消费、TASK-03 被 TASK-04 消费，因此**不存在「单 TASK 独立 revert 且不影响其余」的通用承诺**——回滚单元按逆拓扑定义（§4 RU1~RU4）。
- 组映射 1:1（write-dev-tasks 三步断言输入）：G1=共享 composer（TASK-01）、G2=Team Agent 面板（TASK-02）、G3=Private Ask 面板（TASK-03）、G4=e2e/差异文档/回归/范围核对（TASK-04）。

## 3. 资源与分工

- owner.development = Ray，owner.test = Ray（cr.md 权威）。
- 实施执行：dev-agent（本 Agent）；测试报告消费 implement-code 真实验证结果；计划/代码评审由独立 quality-reviewer-agent（不自评）。
- 实施只写 `resources[].worktreePath` 指向的 multica CR worktree，不拼接、不猜测、不回退主工作区。

| TASK | 估时 | 责任人 | 说明 |
|---|---|---|---|
| CR-2026-062-TASK-01 | 16h | dev-agent | multica packages/views/chat，共享 composer 对齐 + 零差异检查器（cmd-09） |
| CR-2026-062-TASK-02 | 20h | dev-agent | multica packages/views/projects，Team Agent 面板对齐 + 双源停止（B-005 数组口径；最大单体） |
| CR-2026-062-TASK-03 | 12h | dev-agent | multica packages/views/projects，Private Ask 面板对齐 |
| CR-2026-062-TASK-04 | 16h | dev-agent | multica e2e spec（真跑）+ 差异文档 + 全量回归 + diff 白名单核对（cmd-08）+ 符号级 zero_diff 复核（cmd-09） |
| 联调/证据/测试报告 | 8h（非账本） | dev-agent（实现证据）+ test owner 消费 | 跨 TASK，不进 TASK 账本（totalEstimateHours 口径仅计上表 4 行 = 64h） |

## 4. 风险与回滚策略

### 4.0 回滚单元定义（B-004，逆拓扑组合回滚，唯一事实）

每个 TASK 的提交仍是独立 commit，但**回滚单元 = 含该 TASK 及其全部下游消费者（逆拓扑闭包）的 commit 组合**，revert 顺序恒为 TASK 编号**降序**（先叶子后上游）；不存在「revert 上游单 commit 而保留下游」的单元（会留下依赖契约不完整的组合）：

| 回滚单元 | 成员（revert 顺序） | 适用 |
|---|---|---|
| RU1 | TASK-04（仅叶子） | TASK-04 交付物缺陷（e2e spec/差异文档/核对结论）；无下游消费其代码行为，可单独 revert |
| RU2 | TASK-04 → TASK-03 | TASK-03 缺陷（Private Ask 面板）；TASK-04 的 e2e/差异文档消费 TASK-03 行为 |
| RU3 | TASK-04 → TASK-03 → TASK-02 | TASK-02 缺陷（Team Agent 面板/双源停止）；TASK-03 消费其 `@container`、TASK-04 消费其行为 |
| RU4 | TASK-04 → TASK-03 → TASK-02 → TASK-01 | TASK-01 缺陷（共享 composer 基座）；TASK-02/03/04 全部消费其契约 |

- 任一 TASK commit 的回滚 = 包含它的最小 RU；revert 命令经受控 `crctl git revert --no-edit <sha>`（按 RU 内顺序逐个执行）。
- **独立兼容性证明的例外**：若实施期某 TASK 的 diff 经评审确认不依赖上游改动（如纯新增文件、无共享符号消费），可在 plan revision 中降级其回滚单元并注明依据——默认不采用，未证明前一律按上表。

### 4.1 风险表

| # | 风险 | 等级 | 应对 | 回滚 |
|---|---|---|---|---|
| R1 | 基线漂移：实施期间 multica upstream 再合入，行号/符号移动 | 中 | 每 TASK 开工先 `crctl workspace freshness`；代码按 stable symbol 定位（SDD 既有实现依赖 21 条全部带 symbol），不按行号硬编码；锚点失效且影响结论时以 revision 修订 plan/TASK 并注明 | 以 `117fc6be` 为 SDD 事实锚点；漂移影响结论时停止并报告（非代码缺陷，不触发 RU） |
| R2 | `ChatInputCore` 改造影响普通聊天 `ChatInput` 或既有消费方回归（共享组件改动，TASK-01） | 高 | props 签名与 draft 隔离结构零改动（zero_diff）；`ChatInput`（全局）函数体零 diff；**符号级证据 = cmd-09（入库版本化检查器：`ChatInput` 函数体、`ChatInputProps`/`ChatInputCoreProps`/`ChatInputDraftAdapter` 四段基线快照逐字比对，B-006）**，name-only 清单不承担符号级证明；chat-input 既有测试 + adapter isolation 套件全量回归（cmd-01）+ packages/views 全量回归（cmd-04）；surface 改动只改类名集合 | **RU4**（共享基座回滚必须连带全部消费者，逆拓扑 revert 04→03→02→01） |
| R3 | 双源停止路径的活动性/竞态语义错判（TASK-02；items 只含 queued/dispatched、时间线覆盖 running） | 高 | §4.3.1 生命周期闭合表逐行测试（七态矩阵 + 终态覆盖 + 硬降级顺序分支 + **未命中矩阵 (iv)/(v)**——`AgentTask[]` 空列表与非空未命中均回落 items-only，绝不借用容器 Issue 其他 task 状态，B-005）；复用既有 query key 与 WS `task:*` 失效，无新增请求/轮询；TSUG-007 三支语义与队列栏一致 | **RU3**（连带消费其 `@container` 的 TASK-03 与消费其行为的 TASK-04） |
| R4 | Playwright e2e 真跑依赖运行中的前端+服务端（FRONTEND_ORIGIN），canonical 环境可能不可用 | 中 | cmd-07 为**真跑**命令（无 `--list` 口径）；环境无法建立 → 按 SDD §6.9-3 以 ENVIRONMENT_MISMATCH **技术中止**：AC-1/AC-3/AC-5/AC-7 的浏览器行为面不得记为完成，test-report 记录未执行原因（不假绿、不以 `--list` 冒充） | spec/差异文档缺陷 → RU1；环境缺失非代码缺陷，修复环境后重跑 cmd-07 |
| R5 | 窄屏视觉回归（360px 浮窗/窄面板；共享底栏判定式在 TASK-01、面板集成在 TASK-02/03） | 中 | 底栏 flow + flex-wrap + 右组 shrink-0 + `min-h-8` 地板为纯 CSS，无测量/无新 state；组件断言（cmd-01/02）+ e2e 360px 真跑（cmd-07）；两宿主既有测试全绿 | 面板侧根因 → RU3；共享底栏根因 → RU4（按 §4.0 例外条款仅经证明后可降级） |
| R6 | 只读 Model/Thinking chip 类别语义丢失（纯 span 无可访问名称） | 低 | B-002 已裁决：宿主工具栏以 `sr-only` 类别标签（既有 `model_label`/`thinking_label` 文案）包裹，无新文案 key；测试断言 sr-only 存在（cmd-02） | RU3（两宿主工具栏改动所在）；共享底栏侧根因 → RU4 |

无迁移/DDL，无 down 语义。回滚执行一律经受控 `crctl git revert`（controlled-shell 白名单形态 `^--no-edit (-m 1 )?\S+$`），并按 RU 内顺序提交。

## 5. 验收与发布策略

**估算总工时（TASK 账本口径）**：64h（CR-2026-062-TASK-01 16h + TASK-02 20h + TASK-03 12h + TASK-04 16h）。联调/验收 8h 为跨 TASK 非账本工时。

- **验收门槛（发布前 checklist）**：
  1. cmd-01..cmd-09 全绿（证据命令表，见 §6.2；`crctl test` 机器区执行，cmd-NN 日志 `test-evidence/cmd-NN.log` 与表一一对应）；**cmd-07 必须为 e2e 真跑**，环境无法建立时按 ENVIRONMENT_MISMATCH 技术中止（SDD §6.9-3），不得以 `--list` 或其他静态检查替代浏览器行为证据；**cmd-09 为符号级 zero_diff 证据（B-006）**——`chat-input.tsx` 内 `ChatInput` 函数体、`ChatInputProps`/`ChatInputCoreProps`/`ChatInputDraftAdapter` 四段基线快照逐字命中、符号锚点唯一，由入库版本化检查器机器判定（name-only 文件清单不承担符号级证明）；
  2. `write-test-report` status=pass 且 blockers=[]（消费 implement-code 真实验证结果；test-report 命令集逐条转录自 §6.2，不在 plan 之外另造命令）；
  3. 独立 `review-dev-plan` verdict=pass、blockers=[]（plan + TASK 合并评审）；
  4. `crctl approve --stage dev-start` 与 `--stage code` 均经人工（Ray）；
  5. multica `CUSTOM.md` 按当时实际结构登记（纪律 #10）：每个 TASK 落地的新文件（差异文档、e2e spec、零差异检查器测试文件）与修改文件（chat-input.tsx、project-team-agent-chat.tsx、project-private-ask.tsx、project-chat-panel.tsx、project-queue-bar.tsx、测试文件）由各 TASK 登记并纳入完成标志（§9 治理 sidecar 受控例外）；
  6. 交付 diff 白名单核对（AC-8，cmd-08，**仅文件级职责，B-006**）：受控 `crctl git diff --name-only 117fc6be --cwd <resources[].multica.worktreePath>` 输出清单 ∈ SDD §1.1 白名单（含测试文件、`e2e/project-chat-composer.spec.ts`、差异文档、`chat-input-zero-diff.test.ts` 检查器与 `CUSTOM.md` 受控例外），无 `server/`、无 `server/migrations/`、无 API 路由/数据模型变更；清单不证明符号不变，符号级由 cmd-09 承担。
- **feature-flag**：PRD/SDD 未要求 feature-flag；本 CR 为纯视觉对齐，对既有路径零业务语义改动，无需开关。
- **发布**：经既有 CR merge 流程（`merge-feature-branch` / writeback），不进交付 TASK（流程控制 TASK 禁止；merge/审批/checkpoint 的审计以 approval.yml、merge-commits.yml、checkpoint 元数据为准）。
- **发布后观测**：成功指标按 PRD §6 核验（与普通聊天非必要布局差异数=0、窄面板溢出/遮挡缺陷=0、draft/attachment/send/stop/retry 回归=0、新增 API/迁移/数据模型=0、普通聊天视觉基线变化=0、截图验收通过率=100%）。

## 6. 两张稳定表（契约必填，CR-2026-060 AC-07）

### 6.1 交付覆盖表（稳定表 1/2）

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-1 发送框布局对齐（AC-1） | §4.1 规则 1/2（ChatInputCore wrapper/surface 两层 DOM + data-slot）、规则 3（Team Agent 消息流根两层）、规则 5（队列栏两层）、规则 6（两 composer 横幅区两层）、规则 4（ModePane `@container`）；§6 AC-1 | CR-2026-062-TASK-01（关联 CR-2026-062-TASK-02/CR-2026-062-TASK-03） | cmd-01；cmd-02；cmd-07 | RU4 |
| FR-2 单一输入 surface（AC-2） | §4.1 规则 2（surface 类名集合与 `ChatInput` 一致：border-surface-border/bg-surface/rounded-lg/focus-within ring）+ §4.2（输入区/底栏分层、编辑器 `overflow-y-auto` 内部滚动）；§6 AC-2 | CR-2026-062-TASK-01 | cmd-01 | RU4 |
| FR-3 配置控件入底部工具栏（AC-4） | §3.2（两宿主 `leftAdornment` 构造：三态分支/sr-only 类别标签/PATCH 路径不变/testid 保留-移除-替换清单）+ D-3（chip variant 复用）；§6 AC-4 | CR-2026-062-TASK-02（关联 CR-2026-062-TASK-03） | cmd-02 | RU3 |
| FR-4 窄屏双端不溢出不遮挡（AC-3） | §4.2（底栏 flow 布局 + 左组 flex-wrap + 右组 shrink-0 + `min-h-8` 地板）+ D-2/D-5；§6 AC-3（360px e2e 真跑回归） | CR-2026-062-TASK-01（关联 CR-2026-062-TASK-02/CR-2026-062-TASK-04） | cmd-01；cmd-07 | RU4 |
| FR-5 视觉状态一致（AC-5） | §4.3 状态映射表 + §4.3.1/D-7（双源活动性判定：queue items ∪ 容器 Issue 任务时间线——`AgentTask[]` 数组、`tasks.find(task => task.id === sentTaskId)` 唯一选取最近发送 task、空列表/未命中回落 items-only，确定性转移、失败回流可见动作）+ §4.2 `running` 判定式；§6 AC-5（含 e2e 运行中停止真跑） | CR-2026-062-TASK-02（关联 CR-2026-062-TASK-01/CR-2026-062-TASK-04） | cmd-01；cmd-02；cmd-07 | RU3 |
| FR-6 可访问性保持（AC-7） | §3.2（ChatInputCore 补传 `ariaLabel`/`stopAriaLabel`；只读/可编辑控件带 sr-only 类别标签）+ 依赖 #10/#11（chip 内建 aria/tooltip）；§6 AC-7（含 e2e 键盘发送真跑） | CR-2026-062-TASK-01（关联 CR-2026-062-TASK-02/CR-2026-062-TASK-03） | cmd-01；cmd-02；cmd-07 | RU4 |
| FR-7 不新增数据与业务语义（AC-6/AC-8） | §1.1 改动面白名单（仅 packages/views + e2e + 差异文档 + 零差异检查器测试文件 + `CUSTOM.md` 治理 sidecar）+ §2 数据模型 N/A + §9 zero_diff（ChatInput 函数体/props 签名、draft adapter、`useProjectChatStore`、全部 packages/core、server 零改动）+ §9 testid 保留/移除/替换清单；§6 AC-6/AC-8 | CR-2026-062-TASK-04（关联 CR-2026-062-TASK-01/02/03） | cmd-08；cmd-09；cmd-04；cmd-06 | RU1（收口交付；违规改动落在其它 TASK 时按 §4.0 取含该 TASK 的最小 RU） |
| FR-8 共享组件适配与测试（AC-7/AC-8） | §6.9 测试计划（chat-input/项目组件/e2e spec 真跑）+ SDD-CLOSE-04/D-6 差异文档（`project-chat-composer-layout-diff.md`）；Web/Desktop 共享 packages/views；NFR-3 四语 parity | CR-2026-062-TASK-04（关联 CR-2026-062-TASK-01/02/03） | cmd-03；cmd-04；cmd-05；cmd-06；cmd-07 | RU1 |

### 6.2 证据命令表（稳定表 2/2）

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | multica | packages/views | node | ["node_modules/vitest/vitest.mjs", "run", "chat/components/chat-input.test.tsx"] | 900 |
| cmd-02 | multica | packages/views | node | ["node_modules/vitest/vitest.mjs", "run", "projects/components/project-team-agent-chat.test.tsx", "projects/components/project-chat-panel.test.tsx", "projects/components/project-queue-bar.test.tsx", "projects/components/project-private-ask.test.tsx"] | 1200 |
| cmd-03 | multica | packages/views | node | ["node_modules/vitest/vitest.mjs", "run", "locales/parity.test.ts"] | 600 |
| cmd-04 | multica | packages/views | node | ["node_modules/vitest/vitest.mjs", "run"] | 1800 |
| cmd-05 | multica | . | node | ["scripts/check-ui-wildcard-exports.mjs"] | 300 |
| cmd-06 | multica | packages/views | node | ["node_modules/typescript/bin/tsc", "--noEmit", "-p", "."] | 900 |
| cmd-07 | multica | . | node | ["node_modules/@playwright/test/cli.js", "test", "e2e/project-chat-composer.spec.ts"] | 1800 |
| cmd-08 | tools | . | node | ["skills/shared/crctl/scripts/crctl.mjs", "git", "diff", "--name-only", "117fc6be657f91d43df5892b52782a18329c7aed", "--cwd", "<resources[].multica.worktreePath>", "--workspace", "<resources[].ai-first-platform-docs.worktreePath>"] | 300 |
| cmd-09 | multica | packages/views | node | ["node_modules/vitest/vitest.mjs", "run", "chat/components/chat-input-zero-diff.test.ts"] | 600 |

- `cmd-NN` 与 `crctl test` 机器区 `commands` 1-based 下标及 `test-evidence/cmd-NN.log` 全等；args 为 JSON token 数组（shell:false 直接 spawn）；`cwd` 为该 repo 的 CR worktree 内相对路径；`repo` 为 dir-graph.yaml#repositories active 项。依赖安装（`pnpm install`）属实施期准备，不在证据命令内；`node_modules/*` 路径以 multica 根 node_modules（pnpm hoist）为事实。
- **cmd-07（B-002：真实 e2e 真跑，浏览器行为证据唯一口径）**：无 `--list`——`--list` 仅证明 spec 可解析/可发现，**不得冒充 AC-1/AC-3/AC-5/AC-7 的浏览器行为证据**（本表不注册 `--list` 口径）。执行会话需 `FRONTEND_ORIGIN`（或 `PLAYWRIGHT_BASE_URL`）指向运行中的前端+服务端（playwright.config.ts baseURL 链、testDir=./e2e）。环境无法建立 → 按 SDD §6.9-3 以 ENVIRONMENT_MISMATCH **技术中止**：AC-1/AC-3/AC-5/AC-7 的浏览器行为面不得记为完成，test-report 分析段记录未执行原因；test plan 不带 env 字段，环境变量由执行会话注入。
- **cmd-04（B-002：packages/views 全量回归）**：`vitest run` 无文件参数 = packages/views 全量测试（含 TASK-01/02/03 新增套件、cmd-09 检查器与全部既有套件），NFR-5 不回归的全量证据；cmd-01/02/03/09 是定向套件（快反馈与矩阵行证据），**不得以定向跑替代全量回归**。
- **cmd-08（B-003 + B-006：受控 diff 文件白名单核对，仅文件级职责）**：`crctl git diff --name-only <基线 117fc6be> --cwd <multica CR worktree>`，**禁止原生 git**（controlled-shell deny-closed gateway 会拒绝）；`--cwd` 与 `--workspace` 两个占位在 write-test-report 转录 test-plan.json 时从 `execution_context.resources` 解析为绝对路径（`<resources[].multica.worktreePath>`、`<resources[].ai-first-platform-docs.worktreePath>`，不硬编码、不拼接、不回退主工作区）；args 形态 `git diff --name-only <sha>` 命中 controlled-shell 白名单 `^--name-only .+$`。输出为基线→工作区变更文件名清单；白名单成员判定（§1.1 表 + 测试文件 + `e2e/project-chat-composer.spec.ts` + 差异文档 + `chat-input-zero-diff.test.ts` + `CUSTOM.md` 受控例外；无 `server/`、无 `server/migrations/`、无 API 路由/数据模型变更）由 TASK-04 完成标志与 test-report/review-code 对照该清单判定。**B-006 职责收窄**：name-only 清单只含文件名、不含函数/签名信息，`chat-input.tsx` 因修改 `ChatInputCore` 必然出现在清单——**cmd-08 不得用于证明任何符号级 zero_diff，符号级证据由 cmd-09 唯一承担**（TASK-01/04 完成标志与 FR-7/AC-8 验收均按此口径）。
- **cmd-09（B-006：入库版本化符号级 zero_diff 检查器，唯一稳定机器证据）**：TASK-01 在**修改 `chat-input.tsx` 之前**新建 `packages/views/chat/components/chat-input-zero-diff.test.ts`（属 §1.1「组件测试与 e2e | 修改/新增」白名单行），内含从基线 `117fc6be` 逐字提取的四段快照常量——S1 `interface ChatInputProps`（L58–160）、S2 `export function ChatInput` 完整函数体（L162–790）、S3 `export interface ChatInputDraftAdapter`（L810–827）、S4 `interface ChatInputCoreProps extends ChatInputProps`（L829–833），文件头注释记录提取来源 SHA/行号/提取时机（修改前）。运行时校验（全部先 `\r\n → \n` 规范化，AGENTS.md #1；读取/解析失败**硬失败**报错，禁止静默降级）：① 读取同目录 `chat-input.tsx`（相对 `import.meta.url` 解析，不硬编码绝对路径）；② 断言 S1–S4 逐字 substring 命中（该区域零变化）；③ 断言符号锚点（`interface ChatInputProps {`、`export function ChatInput({`、`export interface ChatInputDraftAdapter {`、`interface ChatInputCoreProps extends ChatInputProps {`、`export function ChatInputCore({`）各恰出现一次；④ 修改前先跑绿（构造校验快照正确）、修改后复跑仍绿（证明修改未触碰四个零 diff 区域）。**可审计辅助判定（评审侧，非 cmd）**：reviewer/approver 可经受控 `crctl git diff --unified=3 117fc6be… -- packages/views/chat/components/chat-input.tsx`（白名单形态 `^--unified=\d+ .+$`）人工核对该文件全部 hunk 仅落在 `ChatInputCore` 区域（L835–文件尾）。
- 覆盖面说明（与 §6.1/§7 逐格对应）：cmd-01 覆盖 AC-1/AC-2/AC-5/AC-6/AC-7 组件面 + NFR-5（chat-input.test.tsx 全量，含 `ChatInput` 全局既有套件不回归 + ChatInputCore 新增套件）；cmd-02 覆盖 AC-1/AC-3/AC-4/AC-5/AC-6 项目组件面（两层 DOM、控件 testid 于 composer 子树、三态与 PATCH、sr-only、双源七态矩阵、硬降级矩阵、未命中矩阵 (iv)/(v)、pending-message）；cmd-03 覆盖 NFR-3 四语 parity；cmd-04 覆盖全量回归；cmd-05 覆盖 packages/views wildcard 导出完整性；cmd-06 覆盖 packages/views 全量 typecheck；cmd-07 覆盖 AC-1/AC-3/AC-5/AC-7 浏览器行为面（宽面板截图对齐、360px 无溢出/无重叠、运行中停止、键盘发送四组真跑）；cmd-08 覆盖 AC-8 交付 diff **文件级**白名单；cmd-09 覆盖 FR-7/AC-8 的**符号级** zero_diff（普通聊天基线不变）。

## 7. AC/业务闭环覆盖矩阵（契约必填，CR-2026-057 FR-8）

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-1 布局对齐（Team Agent 主路径：消息流/队列栏/发送框边缘对齐） | §4.1 规则 3/5/6 + §6 AC-1（含宽面板截图差 < 1px 真跑） | CR-2026-062-TASK-02 | cmd-01；cmd-02；cmd-07 |
| 业务闭环：AC-1 Private Ask 侧两层对齐 | §4.1 规则 6 | CR-2026-062-TASK-03 | cmd-02 |
| AC-2 单一输入 surface（用户可观察：与普通聊天同构） | §4.1 规则 2/§4.2 + §6 AC-2 | CR-2026-062-TASK-01 | cmd-01 |
| AC-3 窄面板不溢出不重叠 | §4.2 + §6 AC-3（360px e2e 真跑） | CR-2026-062-TASK-01 | cmd-01；cmd-07 |
| 业务闭环：AC-3 项目面板 `@container` 容器变体前提 | §4.1 规则 4 | CR-2026-062-TASK-02 | cmd-02 |
| AC-4 Team Agent 三态 + PATCH 目标不变（不调 updateAgent） | §3.2/§6 AC-4（testid 保留-移除-替换清单） | CR-2026-062-TASK-02 | cmd-02 |
| 业务闭环：AC-4 Private Ask creator-only 面（`private-ask-model-picker` 新锚点） | §3.2 | CR-2026-062-TASK-03 | cmd-02 |
| AC-5 双源停止与可见动作（含 running 且离开 items 时 stop 可达、终态回发送态；`tasks.find(task => task.id === sentTaskId)` 唯一选取、未命中回落 items-only） | §4.3.1/§6 AC-5（含 e2e 运行中停止真跑） | CR-2026-062-TASK-02 | cmd-01；cmd-02；cmd-07 |
| 业务闭环：AC-5 ChatInputCore 可见动作判定式（allowSubmitWhileRunning/失败保草稿→发送重试） | §4.2/§3.2 | CR-2026-062-TASK-01 | cmd-01 |
| AC-6 draft adapter 隔离/pending-message 不用全局 store | §2/§6 AC-6 | CR-2026-062-TASK-02 | cmd-01；cmd-02 |
| AC-7 可访问名称/tooltip/键盘发送（组件断言面） | §3.2/§6 AC-7 | CR-2026-062-TASK-01 | cmd-01；cmd-02 |
| 业务闭环：AC-7 e2e 键盘发送/运行中停止真跑交付物 | §6.9-3 | CR-2026-062-TASK-04 | cmd-07 |
| AC-8 范围纪律与普通聊天基线不变（无新增 API/迁移/模型 + 差异文档 + CUSTOM.md 受控例外；文件级 cmd-08 + 符号级 cmd-09） | §1.1/§9/§5.6 + §6 AC-8 | CR-2026-062-TASK-04 | cmd-08；cmd-09；cmd-04；cmd-06 |
| 业务闭环：NFR-3 无新文案 key、四语 parity | §7/依赖 #12 | CR-2026-062-TASK-04 | cmd-03 |

> 关键 AC 唯一 owner 说明（CR-2026-057 FR-9，矩阵内机械可判）：
> - **AC-2/AC-3/AC-7 唯一 owner = CR-2026-062-TASK-01**（用户可观察的 surface 结构与可见动作产生层：ChatInputCore 两层 DOM + flow 底栏 + aria 补传；证据 cmd-01/02 + cmd-07）；TASK-02 的 @container、TASK-04 的 e2e 交付物分别为 AC-3/AC-7 的业务闭环行，不参与 owner 判定。
> - **AC-1/AC-4/AC-5/AC-6 唯一 owner = CR-2026-062-TASK-02**（Team Agent 项目面板主路径的实际产生层：消息流/队列栏两层、工具栏三态、双源停止；证据 cmd-01；cmd-02 + cmd-07）；TASK-03（Private Ask 侧）与 TASK-01（判定式基础）为业务闭环行。
> - **AC-8 唯一 owner = CR-2026-062-TASK-04**（范围纪律的收口层：交付 diff 文件级白名单核对 cmd-08 + 符号级 zero_diff 复核 cmd-09 + 差异文档；辅助证据 cmd-04/cmd-06）。
> - 业务闭环行与关键 AC 行证据面不重叠（cmd-NN 分属），可分别机械核验。

## 附：TASK 拆分预分配（write-dev-tasks 的输入，共 4 个，组映射 1:1）

| 变更组 | TASK id | 仓库 | 粒度 | 依赖 |
|---|---|---|---|---|
| G1 共享 composer 对齐 + 零差异检查器 | CR-2026-062-TASK-01 | multica（packages/views/chat） | 2 天（16h） | — |
| G2 Team Agent 面板对齐与停止 | CR-2026-062-TASK-02 | multica（packages/views/projects） | 2.5 天（20h） | TASK-01 |
| G3 Private Ask 面板对齐 | CR-2026-062-TASK-03 | multica（packages/views/projects） | 1.5 天（12h） | TASK-01、TASK-02 |
| G4 e2e/差异文档/回归/范围核对 | CR-2026-062-TASK-04 | multica（e2e + packages/views） | 2 天（16h） | TASK-02、TASK-03 |

每个 in-scope FR 的主责 TASK 唯一（§6.1），关联 TASK 不改变主责；回滚单元按 §4.0 RU1~RU4（逆拓扑组合）；TASK 卡的接口契约逐字对齐 SDD 签名（TASK-02 同步 B-005 数组语义、TASK-01/04 落实 B-006 cmd-09，详见 write-dev-tasks 产物）。

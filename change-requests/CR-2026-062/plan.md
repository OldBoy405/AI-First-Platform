---
id: CR-2026-062-plan
type: PLAN
cr-ref: CR-2026-062
sdd-ref: "change-requests/CR-2026-062/sdd.md"
target-version: 0.35
status: draft
created: 2026-09-09T21:14:52+08:00
updated: 2026-09-09T21:14:52+08:00
---

# CR-2026-062 开发计划（Team Agent 和 Private Ask 发送框 UI 优化）

输入：已审批 SDD（`review-annotations/sdd.yml` verdict=pass、blockers=[]、subject-sha256 `473887394cea62372b911907a5ea7e61ae8d135fde6f2dc29a08c6ef52bb3b0f`，cycle 2 attempt 2；评审证据提交 `178bae83`，人工审批提交 `cf3482d3`）+ PRD（FR-1~8 / AC-1~8）。目标版本 `0.35`（继承 cr.md，未改写）。

## 0. 基线与工作区事实（落笔时实读）

- status=`tech-design-reviewed`；`crctl next`=`write-dev-plan`（humanApproval=false）。
- 远端同步：origin/requirement/CR-2026-062 已推至 `cf3482d3`（push `c27d0d68..cf3482d3`，checkpoint outbox 已发），远端携带已审批状态。
- `crctl workspace inspect`：ai-first-platform-docs / multica / tools 三仓 resources 全部 `healthy`、clean；operationalWorkspace 正常解析。
- 代码事实源：multica requirement worktree HEAD `117fc6be657f91d43df5892b52782a18329c7aed`（SDD 全部 21 条既有实现依赖的锚定 SHA）。SDD 证据链、组件测试与 e2e 计划的代码事实均在该 SHA 实读核实。
- 本 CR 是纯前端体验 CR：实施全部落在 multica `packages/views/`（+ `e2e/` 一个 spec + 差异文档）；**无 server/API/迁移/数据模型改动**（SDD §1.1 改动面白名单、§9 zero_diff）。tools 仓无实施改动。
- 开工前每个 TASK 重跑 `crctl workspace freshness CR-2026-062` 复核基线（gate=implement-start 口径），按 stable symbol 定位代码，不按行号硬编码。

## 1. 交付里程碑

| 里程碑 | 内容 | 对应 TASK | 估时 |
|---|---|---|---|
| M1 共享 composer 对齐 | `ChatInputCore` wrapper（外层 `CHAT_GUTTER`）/surface（内层 `CHAT_COLUMN`+`data-slot="chat-input-surface"`）两层 DOM；surface 类名集合对齐 `ChatInput`；底栏 absolute→flow 布局（左组 wrap + 右组 shrink-0）；`ariaLabel`/`stopAriaLabel` 补传；采纳 `allowSubmitWhileRunning`；chat-input 组件测试新增套件 | TASK-01 | 16h |
| M2 Team Agent 面板对齐与停止路径 | 消息流根/队列栏/横幅区两层 DOM；`ModePane` 加 `@container`；model-row 移除、Model/Thinking 经 `leftAdornment` 进工具栏（三态 + sr-only 类别标签）；运行中停止双源路径（`sentTaskId`/`sentIssueId` + queue items ∪ 任务时间线）；项目组件测试 | TASK-02 | 20h |
| M3 Private Ask 面板对齐 | composer 外层对齐、pending-message 两层块；model-row 移除、控件经 `leftAdornment` 进工具栏（creator-only + sr-only）；停止路径原样；组件测试 | TASK-03 | 12h |
| M4 e2e 交付与差异文档 + 全量回归 | `e2e/project-chat-composer.spec.ts`（宽面板对齐/360px 窄面板/运行中停止/键盘发送）；`project-chat-composer-layout-diff.md`（SDD-CLOSE-04 五项大纲）；全量回归与交付 diff 白名单核对 | TASK-04 | 16h |
| 联调/验收/评审 | cmd-01..06 证据闭环、write-test-report、review-dev-plan/review-code、人工审批 | 非交付（审计事实承载） | 8h（1 人天） |

**估算总工时（TASK 账本口径，与 tasks/_index.yml 的 totalEstimateHours 一致）= 64h**（16h + 20h + 12h + 16h）；另计联调/验收 8h 为跨 TASK 非账本工时（不进 TASK estimate，也不写入 tasks/_index.yml）。发布经既有 CR merge 流程，不在本计划 TASK 范围内（流程控制 TASK 禁止，见 write-dev-tasks）。

## 2. 任务依赖图

```text
TASK-01 (multica packages/views/chat：ChatInputCore 两层 DOM + flow 底栏
         + aria 补传 + allowSubmitWhileRunning 采纳)
   │  产出：ChatInputCore surface 对齐（data-slot="chat-input-surface"）、
   │        底栏 flow 结构、可见动作判定语义、leftAdornment slot 消费契约
   ▼
TASK-02 (multica packages/views/projects：Team Agent 消息流/队列栏/横幅两层
   │     + ModePane @container + 工具栏 leftAdornment + 双源停止路径)
   │  产出：面板级 @container 祖先、Team Agent composer 最终行为口径
   ├──────────────────────────────┐
   ▼                              │（@container 前置）
TASK-03 (multica packages/views/projects：Private Ask 横幅两层 + 工具栏
         leftAdornment + 停止路径原样)
   ▼
TASK-04 (multica e2e spec + 差异文档 + 全量回归/交付 diff 白名单核对)
```

- 依赖全部为「上游产出 → 下游消费」或「共享前置」：TASK-01 的 ChatInputCore surface/flow/判定语义是 TASK-02/03 的消费契约；TASK-02 的 `ModePane @container` 是 TASK-03 容器感知 gutter 变体的前提；TASK-04 的 e2e 与差异文档消费三个 TASK 的最终行为口径。
- 无环、无悬空引用；四个 TASK 同属 multica 仓（唯一代码仓），同一 implementer 串行执行（同 repo 不得并行）。
- 组映射 1:1（write-dev-tasks 三步断言输入）：G1=共享 composer（TASK-01）、G2=Team Agent 面板（TASK-02）、G3=Private Ask 面板（TASK-03）、G4=e2e/差异文档/回归（TASK-04）。

## 3. 资源与分工

- owner.development = Ray，owner.test = Ray（cr.md 权威）。
- 实施执行：dev-agent（本 Agent）；测试报告消费 implement-code 真实验证结果；计划/代码评审由独立 quality-reviewer-agent（不自评）。
- 实施只写 `resources[].worktreePath` 指向的 multica CR worktree，不拼接、不猜测、不回退主工作区。

| TASK | 估时 | 责任人 | 说明 |
|---|---|---|---|
| CR-2026-062-TASK-01 | 16h | dev-agent | multica packages/views/chat，共享 composer 对齐 |
| CR-2026-062-TASK-02 | 20h | dev-agent | multica packages/views/projects，Team Agent 面板对齐 + 双源停止（最大单体） |
| CR-2026-062-TASK-03 | 12h | dev-agent | multica packages/views/projects，Private Ask 面板对齐 |
| CR-2026-062-TASK-04 | 16h | dev-agent | multica e2e spec + 差异文档 + 全量回归 |
| 联调/证据/测试报告 | 8h（非账本） | dev-agent（实现证据）+ test owner 消费 | 跨 TASK，不进 TASK 账本（totalEstimateHours 口径仅计上表 4 行 = 64h） |

## 4. 风险与回滚策略

| # | 风险 | 等级 | 应对 | 回滚 |
|---|---|---|---|---|
| R1 | 基线漂移：实施期间 multica upstream 再合入，行号/符号移动 | 中 | 每 TASK 开工先 `crctl workspace freshness`；代码按 stable symbol 定位（SDD 既有实现依赖 21 条全部带 symbol），不按行号硬编码；锚点失效且影响结论时以 revision 修订 plan/TASK 并注明 | 以 `117fc6be` 为 SDD 事实锚点；漂移影响结论时停止并报告 |
| R2 | `ChatInputCore` 改造影响普通聊天 `ChatInput` 或既有消费方回归 | 高 | props 签名与 draft 隔离结构零改动（zero_diff）；`ChatInput`（全局）函数体零 diff；chat-input 既有测试 + adapter isolation 套件全量回归（cmd-01）；surface 改动只改类名集合 | revert TASK-01 commit（单 commit 可逆） |
| R3 | 双源停止路径的活动性/竞态语义错判（items 只含 queued/dispatched、时间线覆盖 running） | 高 | §4.3.1 生命周期闭合表逐行测试（七态矩阵 + 终态覆盖 + 硬降级顺序分支）；复用既有 query key 与 WS `task:*` 失效，无新增请求/轮询；TSUG-007 三支语义与队列栏一致 | revert TASK-02 commit |
| R4 | Playwright e2e 依赖运行中的前端+服务端（baseURL/FRONTEND_ORIGIN），canonical 环境可能不可用 | 中 | e2e spec 为交付物，canonical 机器证据用 `--list`（spec 可解析可发现，不启动浏览器/服务器）；有环境时按 TASK-04 验收条件真跑，无环境按 ENVIRONMENT_MISMATCH 口径记录于 test-report 分析段（组件测试已覆盖功能断言，不假绿） | 无需回滚（交付物静态可查） |
| R5 | 窄屏视觉回归（360px 浮窗/窄面板） | 中 | 底栏 flow + flex-wrap + 右组 shrink-0 + `min-h-8` 地板为纯 CSS，无测量/无新 state；组件断言 + e2e 360px 回归；两宿主既有测试全绿 | revert 对应 TASK commit |
| R6 | 只读 Model/Thinking chip 类别语义丢失（纯 span 无可访问名称） | 低 | B-002 已裁决：宿主工具栏以 `sr-only` 类别标签（既有 `model_label`/`thinking_label` 文案）包裹，无新文案 key；测试断言 sr-only 存在 | revert 对应 TASK commit |

回滚单元 = 每个 TASK 的独立 commit（revert 单 TASK 不影响其余）；无迁移/DDL，无 down 语义。

## 5. 验收与发布策略

**估算总工时（TASK 账本口径）**：64h（CR-2026-062-TASK-01 16h + TASK-02 20h + TASK-03 12h + TASK-04 16h）。联调/验收 8h 为跨 TASK 非账本工时。

- **验收门槛（发布前 checklist）**：
  1. cmd-01..cmd-06 全绿（证据命令表，见 §6.2；`crctl test` 机器区执行，cmd-NN 日志 `test-evidence/cmd-NN.log` 与表一一对应）；
  2. `write-test-report` status=pass 且 blockers=[]（消费 implement-code 真实验证结果）；
  3. 独立 `review-dev-plan` verdict=pass、blockers=[]（plan + TASK 合并评审）；
  4. `crctl approve --stage dev-start` 与 `--stage code` 均经人工（Ray）；
  5. multica `CUSTOM.md` 按当时实际结构登记（纪律 #10）：每个 TASK 落地的新文件（差异文档、e2e spec）与修改文件（chat-input.tsx、project-team-agent-chat.tsx、project-private-ask.tsx、project-chat-panel.tsx、project-queue-bar.tsx、三个测试文件）由各 TASK 登记并纳入完成标志；
  6. 交付 diff 白名单核对（AC-8）：无 `server/`、无 `server/migrations/`、无 API 路由/数据模型变更。
- **feature-flag**：PRD/SDD 未要求 feature-flag；本 CR 为纯视觉对齐，对既有路径零业务语义改动，无需开关。
- **发布**：经既有 CR merge 流程（`merge-feature-branch` / writeback），不进交付 TASK（流程控制 TASK 禁止；merge/审批/checkpoint 的审计以 approval.yml、merge-commits.yml、checkpoint 元数据为准）。
- **发布后观测**：成功指标按 PRD §6 核验（与普通聊天非必要布局差异数=0、窄面板溢出/遮挡缺陷=0、draft/attachment/send/stop/retry 回归=0、新增 API/迁移/数据模型=0、普通聊天视觉基线变化=0、截图验收通过率=100%）。

## 6. 两张稳定表（契约必填，CR-2026-060 AC-07）

### 6.1 交付覆盖表（稳定表 1/2）

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-1 发送框布局对齐（AC-1） | §4.1 规则 1/2（ChatInputCore wrapper/surface 两层 DOM + data-slot）、规则 3（Team Agent 消息流根两层）、规则 5（队列栏两层）、规则 6（两 composer 横幅区两层）、规则 4（ModePane `@container`）；§6 AC-1 | CR-2026-062-TASK-01（关联 CR-2026-062-TASK-02/CR-2026-062-TASK-03） | cmd-01；cmd-02 | revert TASK-01/02/03 commit |
| FR-2 单一输入 surface（AC-2） | §4.1 规则 2（surface 类名集合与 `ChatInput` 一致：border-surface-border/bg-surface/rounded-lg/focus-within ring）+ §4.2（输入区/底栏分层、编辑器 `overflow-y-auto` 内部滚动）；§6 AC-2 | CR-2026-062-TASK-01 | cmd-01 | revert TASK-01 commit |
| FR-3 配置控件入底部工具栏（AC-4） | §3.2（两宿主 `leftAdornment` 构造：三态分支/sr-only 类别标签/PATCH 路径不变）+ D-3（chip variant 复用）；§6 AC-4 | CR-2026-062-TASK-02（关联 CR-2026-062-TASK-03） | cmd-02 | revert TASK-02/03 commit |
| FR-4 窄屏双端不溢出不遮挡（AC-3） | §4.2（底栏 flow 布局 + 左组 flex-wrap + 右组 shrink-0 + `min-h-8` 地板）+ D-2/D-5；§6 AC-3（360px e2e 回归） | CR-2026-062-TASK-01（关联 CR-2026-062-TASK-02/CR-2026-062-TASK-04） | cmd-01；cmd-02；cmd-06 | revert TASK-01/02 commit |
| FR-5 视觉状态一致（AC-5） | §4.3 状态映射表 + §4.3.1/D-7（双源活动性判定、确定性转移、失败回流可见动作）+ §4.2 `running` 判定式；§6 AC-5 | CR-2026-062-TASK-02（关联 CR-2026-062-TASK-01） | cmd-01；cmd-02 | revert TASK-02 commit |
| FR-6 可访问性保持（AC-7） | §3.2（ChatInputCore 补传 `ariaLabel`/`stopAriaLabel`；只读/可编辑控件带 sr-only 类别标签）+ 依赖 #10/#11（chip 内建 aria/tooltip）；§6 AC-7 | CR-2026-062-TASK-01（关联 CR-2026-062-TASK-02/CR-2026-062-TASK-03） | cmd-01；cmd-02 | revert TASK-01 commit |
| FR-7 不新增数据与业务语义（AC-6/AC-8） | §1.1 改动面白名单（仅 packages/views + e2e + 差异文档）+ §2 数据模型 N/A + §9 zero_diff（ChatInput 函数体/props 签名、draft adapter、`useProjectChatStore`、全部 packages/core、server 零改动）；§6 AC-6/AC-8 | CR-2026-062-TASK-04（关联 CR-2026-062-TASK-01/02/03） | cmd-04；cmd-05 | revert 对应 TASK commit |
| FR-8 共享组件适配与测试（AC-7/AC-8） | §6.9 测试计划（chat-input/项目组件/e2e spec）+ SDD-CLOSE-04/D-6 差异文档（`project-chat-composer-layout-diff.md`）；Web/Desktop 共享 packages/views | CR-2026-062-TASK-04（关联 CR-2026-062-TASK-01/02/03） | cmd-03；cmd-06 | revert TASK-04 commit |

### 6.2 证据命令表（稳定表 2/2）

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | multica | packages/views | node | ["node_modules/vitest/vitest.mjs", "run", "chat/components/chat-input.test.tsx"] | 900 |
| cmd-02 | multica | packages/views | node | ["node_modules/vitest/vitest.mjs", "run", "projects/components/project-team-agent-chat.test.tsx", "projects/components/project-private-ask.test.tsx", "projects/components/project-chat-panel.test.tsx", "projects/components/project-queue-bar.test.tsx"] | 1200 |
| cmd-03 | multica | packages/views | node | ["node_modules/vitest/vitest.mjs", "run", "locales/parity.test.ts"] | 600 |
| cmd-04 | multica | . | node | ["scripts/check-ui-wildcard-exports.mjs"] | 300 |
| cmd-05 | multica | packages/views | node | ["node_modules/typescript/bin/tsc", "--noEmit", "-p", "."] | 900 |
| cmd-06 | multica | . | node | ["node_modules/@playwright/test/cli.js", "test", "e2e/project-chat-composer.spec.ts", "--list"] | 300 |

- `cmd-NN` 与 `crctl test` 机器区 `commands` 1-based 下标及 `test-evidence/cmd-NN.log` 全等；args 为 JSON token 数组（shell:false 直接 spawn）；`cwd` 为 multica CR worktree 内相对路径；`repo` 为 dir-graph.yaml#repositories active 项。
- **执行环境口径（write-test-report / `crctl test` 会话统一）**：实施期在 multica CR worktree 完成依赖安装（`pnpm install` 属实施期准备，不在证据命令内）；`node_modules/vitest/vitest.mjs`、`node_modules/typescript/bin/tsc`、`node_modules/@playwright/test/cli.js` 均以 multica 根 node_modules 为事实（与 CR-2026-059 cmd-06/07 同模式）。vitest 组件测试不需要浏览器/服务端；`cmd-06` 使用 `--list`（只解析/发现 spec，不启动浏览器、不连 baseURL），全量 e2e 真跑需 FRONTEND_ORIGIN 指向运行中的前端+服务端（实施期按 TASK-04 验收条件，环境不可用按 ENVIRONMENT_MISMATCH 口径记录于 test-report 分析段，canonical 机器证据不含真跑 e2e——防环境依赖假绿/假红）。
- cmd-01 覆盖面（AC-1/AC-2/AC-5/AC-6/AC-7 核心面 + NFR-5）：chat-input.test.tsx 全量（含 `ChatInput` 全局既有套件不回归 + ChatInputCore 新增套件）——wrapper（外层 `CHAT_GUTTER`）/surface（内层 `CHAT_COLUMN`）两层类名断言与 `data-slot="chat-input-surface"`、surface token（border-surface-border/bg-surface/rounded-lg/focus-within ring）、底栏 flow 布局结构与 `leftAdornment` 渲染于左组、发送按钮 accessible name=send_tooltip、运行中停止按钮 accessible name=stop_tooltip、`allowSubmitWhileRunning=true` 时运行中+有内容→发送可用且 handleSend 放行 / 空输入→停止、未传→运行中发送被拦、adapter isolation（`useChatStore` 零订阅）不回归。
- cmd-02 覆盖面（AC-1/AC-3/AC-4/AC-5/AC-6 项目面）：Team Agent 消息流根/队列栏两层 DOM（外层 GUTTER 节点与内层 COLUMN 节点分离）、控件 testid 位于 composer 子树（`project-chat-model-picker`/`project-chat-model-readonly`/`project-chat-model-runtime-guide`/`project-chat-thinking-picker`/`private-ask-model-picker`/`private-ask-thinking-picker`）、三态与 PATCH 断言保持、sr-only 类别标签（model_label/thinking_label）、双源停止矩阵（七态 + items 只放 queued/dispatched：running 且 items 不含时 stop 仍渲染；终态覆盖回发送态；点击调用 `cancelTaskById(task_id)`；非 cancelled 终态 → `cancel_already_finished` toast）、硬降级矩阵（首发送空 ID 不渲染死按钮；活动 A→下一次成功返回空 `task_id`→stop 消失且不调用 `cancelTaskById(A)`；发送失败→草稿保留+发送（重试）按钮→清空草稿→stop 重新渲染并调用 `cancelTaskById(A)`）、pending-message 渲染条件不变、queue-bar/chat-panel 既有交互不回归。
- cmd-03 覆盖面：四语 locale parity（NFR-3 无新文案 key 下的 parity 全绿）。
- cmd-04 覆盖面：packages/views 共享组件 wildcard 导出完整性（FR-8 Web/Desktop 共享适配不破坏 UI 出口）。
- cmd-05 覆盖面：packages/views 全量 typecheck（AC-7 共享组件类型契约完整；AC-8 改动面不含 server 的编译面证据——前端改动零服务端耦合）。
- cmd-06 覆盖面：e2e spec 交付物 well-formed（可解析、可发现）；AC-8 的交付 diff 白名单核对（无 server/、无 server/migrations/、无 API 变更）为静态检查，随 review-code 执行（SDD §6 AC-8 可观测结果「范围由提交内容静态可查」）。

## 7. AC/业务闭环覆盖矩阵（契约必填，CR-2026-057 FR-8）

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-1 布局对齐（Team Agent 主路径：消息流/队列栏/发送框边缘对齐） | §4.1 规则 3/5/6 + §6 AC-1 | CR-2026-062-TASK-02 | cmd-01；cmd-02 |
| 业务闭环：AC-1 Private Ask 侧两层对齐 | §4.1 规则 6 | CR-2026-062-TASK-03 | cmd-02 |
| AC-2 单一输入 surface（用户可观察：与普通聊天同构） | §4.1 规则 2/§4.2 + §6 AC-2 | CR-2026-062-TASK-01 | cmd-01 |
| AC-3 窄面板不溢出不重叠 | §4.2 + §6 AC-3 | CR-2026-062-TASK-01 | cmd-01；cmd-06 |
| 业务闭环：AC-3 项目面板 `@container` 容器变体前提 | §4.1 规则 4 | CR-2026-062-TASK-02 | cmd-02 |
| AC-4 Team Agent 三态 + PATCH 目标不变（不调 updateAgent） | §3.2/§6 AC-4 | CR-2026-062-TASK-02 | cmd-02 |
| 业务闭环：AC-4 Private Ask creator-only 面 | §3.2 | CR-2026-062-TASK-03 | cmd-02 |
| AC-5 双源停止与可见动作（含 running 且离开 items 时 stop 可达、终态回发送态） | §4.3.1/§6 AC-5 | CR-2026-062-TASK-02 | cmd-01；cmd-02 |
| 业务闭环：AC-5 ChatInputCore 可见动作判定式（allowSubmitWhileRunning/失败保草稿→发送重试） | §4.2/§3.2 | CR-2026-062-TASK-01 | cmd-01 |
| AC-6 draft adapter 隔离/pending-message 不用全局 store | §2/§6 AC-6 | CR-2026-062-TASK-02 | cmd-01；cmd-02 |
| AC-7 可访问名称/tooltip/键盘发送（组件断言面） | §3.2/§6 AC-7 | CR-2026-062-TASK-01 | cmd-01；cmd-02 |
| 业务闭环：AC-7 e2e 键盘发送/运行中停止交付物 | §6.9-3 | CR-2026-062-TASK-04 | cmd-06 |
| AC-8 范围纪律与普通聊天基线不变（无新增 API/迁移/模型 + 差异文档） | §1.1/§9/§5.6 + §6 AC-8 | CR-2026-062-TASK-04 | cmd-03；cmd-04；cmd-05 |
| 业务闭环：NFR-3 无新文案 key、四语 parity | §7/依赖 #12 | CR-2026-062-TASK-04 | cmd-03 |

> 关键 AC 唯一 owner 说明（CR-2026-057 FR-9，矩阵内机械可判）：
> - **AC-2/AC-3/AC-7 唯一 owner = CR-2026-062-TASK-01**（用户可观察的 surface 结构与可见动作产生层：ChatInputCore 两层 DOM + flow 底栏 + aria 补传，证据 cmd-01）；TASK-02 的 @container、TASK-04 的 e2e 交付物分别为 AC-3/AC-7 的业务闭环行，不参与 owner 判定。
> - **AC-1/AC-4/AC-5/AC-6 唯一 owner = CR-2026-062-TASK-02**（Team Agent 项目面板主路径的实际产生层：消息流/队列栏两层、工具栏三态、双源停止，证据 cmd-01；cmd-02）；TASK-03（Private Ask 侧）与 TASK-01（判定式基础）为业务闭环行。
> - **AC-8 唯一 owner = CR-2026-062-TASK-04**（范围纪律的收口层：交付 diff 白名单核对 + 差异文档，证据 cmd-03；cmd-04；cmd-05）。
> - 业务闭环行与关键 AC 行证据面不重叠（cmd-NN 分属），可分别机械核验。

## 附：TASK 拆分预分配（write-dev-tasks 的输入，共 4 个，组映射 1:1）

| 变更组 | TASK id | 仓库 | 粒度 | 依赖 |
|---|---|---|---|---|
| G1 共享 composer 对齐 | CR-2026-062-TASK-01 | multica（packages/views/chat） | 2 天（16h） | — |
| G2 Team Agent 面板对齐与停止 | CR-2026-062-TASK-02 | multica（packages/views/projects） | 2.5 天（20h） | TASK-01 |
| G3 Private Ask 面板对齐 | CR-2026-062-TASK-03 | multica（packages/views/projects） | 1.5 天（12h） | TASK-01、TASK-02 |
| G4 e2e/差异文档/回归 | CR-2026-062-TASK-04 | multica（e2e + packages/views） | 2 天（16h） | TASK-02、TASK-03 |

每个 in-scope FR 的主责 TASK 唯一（§6.1），关联 TASK 不改变主责；TASK 卡的接口契约逐字对齐 SDD 签名（详见 write-dev-tasks 产物）。

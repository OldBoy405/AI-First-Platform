---
id: CR-2026-010-prd
type: PRD
cr-ref: CR-2026-010
title: P2 三模式聊天 CR-E — D4 presenter 控制权（claim 串行化键 agent_id→project_id）
target-version: "0.17"
owner: Ray
owner-role: requirement
status: draft
created: "2026-08-02T10:51:04+08:00"
updated: "2026-08-02T10:56:00+08:00"
revision: "0.1.1"
---

# PRD — P2 三模式聊天 CR-E：presenter 控制权（含 claim 串行化键改造）

> 依据：`docs/product/P2-三模式聊天窗口主体-交付切分.md` v2（d7e4ece）的 CR-E / D4 节，
> 状态机、字典锚点与权限语义以《P2-三模式聊天交互设计》§2 / §3.1 为准。
> 前置 CR-A（CR-2026-006，已合并）提供 UI 挂点：项目群聊窗口、chatHeader、Team Agent
> 消息流与薄发送端点。D1 队列治理（CR-2026-004）为既有前提，本 CR 不改其容量/插队/撤回语义。

## 1. 概述

**背景**：CR-A 交付后，项目群聊窗口内**任何成员**发消息都会入队执行——Team Agent 是共享执行层，
但"谁能驱动它"目前只有 D1 的容量守卫，没有控制权语义。设计稿 §2 的口径是**单一写者**：
Owner+Admin 默认可驱动，其余成员须申请 presenter（主持人）；同一时刻仅一人驱动 Agent。
这是 Team Agent 与 Private Ask 的核心区别之一，也是后续计费归属（Owner/Presenter 可配）的前提。

**本 CR 交付**（交付切分 v2 的 CR-E，后端重、风险面独立）：
1. **后端 presenter 状态机**：申请/批准/拒绝/转让/撤销/释放六个转移；presenter 判定接入
   入队/claim 路径（单一写者裁决点在服务端，前端只做呈现）。
2. **claim SQL 串行化键改造**：`agent_id` → `project_id`（交互设计 §3.1 论证），
   `NOT EXISTS(active task on same project)` 天然保证项目级单写者，无需额外锁。
3. **前端三件套**：§3.1 全部 6 个通知文案卡片、chatControlPanel 权限面板
   （Owner 标记、成员列表、请求按钮）、chatHeader「当前主持人」实时显示。
   可选吸收 CodeBanana 的内联系统状态卡作为通知呈现形式（SDD 定夺，不作硬性要求）。

**权限语义口径**（综合设计稿 §2、§3.1 与切分文档 §0.1"管理员可直接对话但 Agent 忙时需等待"，
本 PRD 定死，评审时确认）：
- `presenter == null`（默认态）：Owner/Admin 可直接驱动；普通成员发送被同步拒绝
  （结构化原因 + 「请求 Agent 访问权限」引导），不落库不入队。
- `presenter != null`：仅 presenter 的消息被执行；普通成员同上被拒；
  **Owner/Admin 可正常发送入队但需等待**（Agent 忙时排队，不抢占 presenter）。
- Admin 接管：Agent 空闲（无 active task）时 Owner/Admin 直接发送即接管执行，不必逐次审批
  ——映射为 claim 前检查 `presenter==null || caller∈{owner,admin}` 的空闲分支。
- 审批权：presenter 申请由 Owner 批准/拒绝；撤销权在 Owner；转让/释放权在当前 presenter。

**技术前提与文档回写项**：
- multica 实时层是单 workspace socket + payload 过滤（切分文档 §B WS 语义修正），
  presenter 变更事件走既有 workspace fanout 加 handler，不建新连接。
- **P0 §2.2 原文"claim 串行化不变（仍按 agent_id + 来源键）"与本 CR 冲突**，
  以切分文档 v2 与交互设计 §3.1 为准；P0 映射表该句随本 CR 写回阶段修订。
- 串行化键改造**只作用于项目共享（Team Agent）任务**；`chat_session` 来源（Private Ask，CR-C）
  的任务保持独立并行，不受 project 级单写者约束——否则违反设计稿 §4"与 Team Agent 并行"。
  精确 SQL 边界 SDD 定案。

## 2. 用户故事

- **US-1** 作为**项目 Owner**，我希望默认只有我和 Admin 能驱动 Team Agent，其他成员须经我批准
  才能获得控制权，以便共享执行层不因多人同时派活而互相踩踏。
- **US-2** 作为**普通成员**，我希望一键申请 Agent 访问权限并在获批/被拒时收到明确通知，
  获得控制权后即可独立驱动 Agent，用完可转让给同事或主动释放。
- **US-3** 作为**Admin**，我希望 Agent 空闲时不必走申请流程直接派活，Agent 忙时我的消息排队等待
  而不是被拒绝，以便管理动作低摩擦且不干扰当前主持人。
- **US-4** 作为**项目成员**，我希望在窗口头部随时看到当前主持人是谁、并在控制权每次变更时
  看到消息流内的通知卡片，以便"谁在驱动 Agent"对全员透明。
- **US-5** 作为**平台维护者**，我希望单写者语义直接落在 claim SQL 的串行化键上而非额外锁，
  且改造后既有队列治理与群聊入队行为零回归。

## 3. 功能需求

| ID | 需求 | 优先级 |
|---|---|---|
| FR-1 | **presenter 状态模型**：项目维度唯一 presenter（可空）；六个转移——申请（成员→待审）、批准（Owner，presenter=该成员）、拒绝（Owner，维持原状）、转让（presenter→另一成员）、撤销（Owner，presenter=null）、释放（presenter 本人，presenter=null）；非法转移（如非 Owner 批准、非 presenter 转让）服务端 403 结构化拒绝 | P0 |
| FR-2 | **入队路径接入 presenter 判定**：薄发送端点（CR-A）在容量守卫**之前**加控制权守卫——普通成员非 presenter 时同步拒绝（结构化错误码，含当前 presenter 信息，消息不落库不入队）；presenter 与 Owner/Admin 放行入队 | P0 |
| FR-3 | **claim 串行化键改造**：项目共享任务的 claim SQL 串行化键由 `agent_id` 改为 `project_id`，同一项目同时至多一个 active task；Owner/Admin 在 Agent 忙时的消息保持排队（D1 插队语义只影响队列顺序，不抢占运行中任务）；`chat_session` 来源任务不受此键约束 | P0 |
| FR-4 | **通知卡片**：六个状态转移各触发对应通知（`permissionRequestSentToOwner` / `youGotPermissionToControlAgent` / `youReceivedPermissionFromAnotherMember` + `youTransferredPermissionToAnotherMember` / `permissionHasBeenRevoked` / `yourPresenterRequestHasBeenRejected` / `permissionHasBeenReleased`），按字典锚点语义定向触达（如申请通知达 Owner、批准通知达申请人）；呈现形式为消息流内通知卡或内联状态条（SDD 定） | P0 |
| FR-5 | **chatControlPanel 权限面板**：右侧抽屉（CR-A 占位入口激活）——Owner 标记、成员列表、当前 presenter 标识；普通成员见「请求 Agent 访问权限」按钮；Owner 对待审申请见批准/拒绝、对当前 presenter 见撤销；presenter 本人见转让/释放 | P0 |
| FR-6 | **chatHeader 当前主持人**：头部显示 `currentPresenter`（「当前主持人」，空态显示默认口径如「Owner/Admin」），经 WS 实时更新无需刷新 | P0 |
| FR-7 | **WS 事件**：presenter 变更（六转移）广播 workspace 级事件，前端 handler 更新头部/面板/通知，复用单 socket 架构（新事件类型 + handler，无新连接） | P0 |
| FR-8 | **发送端拒绝呈现**：普通成员被控制权守卫拒绝时，输入区就地提示（含当前主持人 + 「请求 Agent 访问权限」入口），与 D1 满队 429 的禁用态呈现并存不冲突 | P1 |

## 4. 非功能需求

- **NFR-1 服务端权威**：presenter 判定、转移权限校验、单写者裁决全部在服务端；前端禁用态仅为呈现，
  绕过前端直接调 API 同样被拒（403/结构化错误）。
- **NFR-2 零回归（本 CR 首要风险）**：claim 串行化键改造后，CR-2026-004 的容量守卫/插队/撤回/
  queue-status 与 CR-2026-006 的群聊入队→claim→执行→回放全链路回归测试全绿；
  既有浮窗/全页 chat（chat_session 来源）执行不受影响。
- **NFR-3 四语文案**：六通知 + 面板 + 头部全部新增 UI 文案提供 en/ja/ko/zh-Hans 四语，
  locale parity 测试全绿。
- **NFR-4 双端一致**：web 与 desktop（Electron 共享 `packages/views`）行为一致；mobile 不在 P2 范围。
- **NFR-5 并发安全**：presenter 转移与 claim 竞态（如撤销瞬间 presenter 的消息正在入队）不产生
  双写者或死锁；以 DB 层约束/事务保证，SDD 给出方案。

## 5. 验收标准

- **AC-1**（FR-1/2/3/8，单一写者）presenter 非空时：普通成员发送被同步拒绝且不落库不入队，
  输入区就地提示当前主持人并给出「请求 Agent 访问权限」入口（与满队 429 禁用态并存不冲突）；
  Owner/Admin 发送入队但在 presenter 任务运行期间不被执行（排队等待）；presenter 消息正常执行。
  Agent 空闲时 Admin 直接发送即执行（免申请接管）。
- **AC-2**（FR-1/4/5/6，状态机全覆盖）申请→批准、申请→拒绝、转让、撤销、释放五条路径真机走通，
  6 个转移各自触发对应通知卡片且定向正确；chatControlPanel 各角色按钮可见性正确；
  chatHeader 主持人显示在每次转移后经 WS 实时更新（无手动刷新）。
- **AC-3**（FR-3/NFR-2，回归——独立成 CR 的主因）claim 串行化键改造后：
  ① CR-2026-004 语义回归——满队 429、owner/admin 插队、撤回释放槽位、queue-status 实时，全绿；
  ② CR-2026-006 语义回归——群聊发送→守卫→落库→入队→claim→工具卡实时渲染→刷新回放，全绿；
  ③ 同一项目并发发送多条消息，任意时刻至多一个 active task（项目级单写者 SQL 验证）；
  ④ chat_session 来源任务与项目共享任务并行执行互不阻塞。
- **AC-4**（FR-1/NFR-1，服务端权威）绕开前端直接调用转移 API：非 Owner 批准/撤销、非 presenter
  转让/释放、非成员申请，均返回 403 结构化拒绝；普通成员直发消息 API 同样被控制权守卫拒绝。
- **AC-5**（NFR-3/4）locale parity 测试全绿；web 与 desktop 行为一致。

## 6. 成功指标

- Team Agent 从"人人可派活"升级为"单一写者 + 显式控制权"，共享执行层的驱动权对全员透明可审计，
  与 Private Ask（人人独立）的模式分界完全成立。
- 单写者语义落在 claim SQL 串行化键上，未引入额外锁或独立仲裁服务；
  后续计费归属（Owner/Presenter 可配）与「清空上下文需 Agent 使用权限」等依赖 presenter 的
  能力获得判定基础。

## 7. 范围排除

- 队列条完整形态/停止/过滤开关 → **CR-B**（并行中，互不依赖）；Private Ask 内容面 → **CR-C**
  （本 CR 仅保证 chat_session 任务不受串行化键改造影响）；Discussion 面 → **CR-D**；
  门禁接合 → **CR-F**；DC 与合并转发 → **CR-G**。
- 计费归属（Owner/Presenter 可配）本 CR 不做，仅留判定基础；「清空上下文」对接 presenter 权限
  随其所属功能（切分文档 §0.4 已排除）后续交付。
- 切分文档 §0.4 全部写死排除项继续有效（双入口、work-viewer、上下文用量、语音、回复/转发线程、
  成员管理增强、斜杠命令、导出 Skill 草稿、恢复检查点、点踩反馈、mobile）。
- presenter 申请的收件箱/站内信全局通知中心不在本 CR——通知触达以消息流内卡片 + WS 实时为准，
  全局通知集成随平台通知体系另议。

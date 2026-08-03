---
id: CR-2026-011-prd
type: PRD
cr-ref: CR-2026-011
title: P2 三模式聊天 CR-F — D7 门禁接合（B4 迁移 + 审批卡/blocker/CR 徽标）
target-version: "0.18"
owner: Ray
owner-role: requirement
status: draft
created: "2026-08-02T11:15:45+08:00"
updated: "2026-08-02T11:15:45+08:00"
revision: "0.1.0"
---

# PRD — P2 三模式聊天 CR-F：D7 门禁接合

> 依据：`docs/product/P2-三模式聊天窗口主体-交付切分.md` v2（d7e4ece）的 CR-F 节（D7 + B4），
> 交互契约以《P2-三模式聊天交互设计》§3.5 为准；审批语义严格按《P1-crctl接入设计》§B
> 的签名审批链路（CR-2026-002 已交付其服务端与 crctl 全部能力）；数据模型按《P0-数据模型映射表》
> §2.2（B4 两列）、§3.1（cr 投影）、§3.4（pipeline 两表）、§4.1（16 态 → 7 态映射）。
> 审批卡视觉自定——CodeBanana 快照无审批卡实物，只有"{count} 个待审批任务"计数佐证该场景存在。

## 1. 概述

**背景**：P1（CR-2026-002/003）交付了治理数据全链路——CR 事件同步投影（`cr` 表 + WS 广播）、
Ed25519 签名审批（审批 API + grant 签发/下发 + `crctl approve --grant` 验签 + EVIDENCE_DRIFT 两轨检测），
但**明确排除了交互层**：审批至今没有任何产品 UI，验收是直接调 API 完成的；CR 状态投影也只到
看板 7 态，16 态无处展示。另一边，CR-2026-006（CR-A）交付了项目群聊窗口与 Team Agent 消息流。
两条线尚未接合：pipeline 节点任务在消息流里与普通任务无异，成员看不到"任务卡在哪个门禁"、
审批人无法在协作现场批准/驳回。本 CR 就是这次接合（D7），也是"过程即记录"审计理念在聊天窗口的落点。

**本 CR 交付**：
1. **B4 迁移**：`agent_task_queue` 增 `cr_id` / `pipeline_node_run_id` 两列（P0 §2.2 原样，
   均 nullable，claim 串行化不变）；因 FK 前提，连带创建 `pipeline_run` / `pipeline_node_run`
   两表（P0 §3.4 定义），及打通验收所需的最小节点运行归因路径（见技术前提第 3 条）。
2. **门禁状态条 + 审批卡**：`pipeline_node_run_id` 非空的任务在消息流内渲染门禁状态条；
   `human_approval` 节点渲染审批卡（走 P1 服务端签名审批，非 TTY），有权限者见批准/驳回，
   驳回 `reject_reason` 注入 review_feedback；review 节点 `verdict=block` 显示 blocker 列表
   + reviewLoop attempt N/3。
3. **CR 16 态徽标**：chatHeader 显示关联 CR 的 16 态徽标，消费 P1 已交付的 `cr` 投影 + WS 广播。

**技术前提**（SDD 阶段细化，偏离需论证）：
1. 审批强度全部由已交付链路承担：`RequireHumanActor`（mat_ 403）、证据 digest 比对（409）、
   Ed25519 验签、grant 落盘 → `crctl approve --grant` 验签推进。本 CR 只做消费面 UI，
   **不改审批服务端逻辑、不引入任何前端"本地放行"路径**。
2. CR 状态权威在 git、PG 只读投影（权威铁律）：徽标/状态条/卡片一切展示只读 `cr` 投影；
   点击批准是调审批 API 签发 grant，状态推进仍由 crctl advance 产生并经同步链路回流。
3. **已核实的缺口，本 CR 定案**：`pipeline_run` / `pipeline_node_run` 两表至今未建
   （CR-2026-002 只建了 cr / cr_sync_event / approval_record 三表），Pipeline Runner 全量编排
   （总 PRD P1-F2：when/passCondition 解释器、四条主 pipeline 持久化编排）**未交付且不在本 CR**。
   本 CR 建表 + 打通"pipeline 节点任务入队时写入两列、产生对应 node run 行"的最小归因路径
   （具体挂点——daemon 任务回调族或 cr-events 通道扩展——SDD 定案），以支撑 D7 验收的真实
   pipeline 跑通；Runner 本体另行 CR。

## 2. 用户故事

- **US-1** 作为**审批人**，我希望在项目群聊消息流内直接看到审批卡（证据摘要 + digest 指纹）
  并点击批准/驳回，而不是去调 API 或跑 crctl 的机器开终端，以便审批发生在协作现场且强度不降级。
- **US-2** 作为**项目成员**，我希望看到 pipeline 任务当前卡在哪个门禁——审批等待中、review 被
  block（blocker 列表）、修复第几轮（attempt N/3）——而不必翻 knowledge-base 仓的 yml 文件。
- **US-3** 作为**项目成员**，我希望 chatHeader 上实时看到 CR 的精确 16 态（而非看板的粗粒度 7 态），
  以便在聊天窗口内掌握需求的治理进度。
- **US-4** 作为**平台维护者**，我希望任务与 CR / pipeline 节点的归因落库（B4 两列），
  以便 P3 治理指标（EPC/ACM 均引用 `pipeline_node_run` 与 `agent_task_queue`）有数据地基。

## 3. 功能需求

| ID | 需求 | 优先级 |
|---|---|---|
| FR-1 | **B4 迁移**：`agent_task_queue` 增 `cr_id TEXT NULL` + `pipeline_node_run_id UUID NULL REFERENCES pipeline_node_run(id) ON DELETE SET NULL` + 部分索引（P0 §2.2 原样）；连带创建 `pipeline_run` / `pipeline_node_run` 两表（P0 §3.4 schema）；claim 串行化与既有入队路径（chat/quick-create/autopilot/issue 评论）行为不变，存量任务两列为 NULL | P0 |
| FR-2 | **最小节点运行归因**：pipeline 节点驱动的任务在入队时写入 `cr_id` + `pipeline_node_run_id`，并存在对应 `pipeline_node_run` 行（状态字段足以驱动 FR-3~FR-5 渲染与验收）；写入挂点 SDD 定案，Runner 全量编排不在本 CR | P0 |
| FR-3 | **门禁状态条**：Team Agent 消息流内，`pipeline_node_run_id` 非空的任务额外渲染门禁状态条（节点名/类型/当前门禁状态），随投影更新经 WS 实时刷新 | P0 |
| FR-4 | **审批卡**：到达 `human_approval` 节点时消息流渲染审批卡——内容为 P1 审批 API 返回的证据摘要（verdict / blockers / test-report.status + digest 指纹）；有审批权限者（P1 审批 API 角色策略判定）见「批准/驳回」，无权限者只读；批准 → POST 审批 API → grant 签发下发 → crctl 验签推进 → 投影回流后卡片自动更新为已批准态；驳回必填 `reject_reason` → 注入 review_feedback 回修复节点；403（身份/验签）与 409（证据漂移）以结构化原因呈现在卡片上，不静默失败 | P0 |
| FR-5 | **blocker 列表 + reviewLoop**：review 节点 `verdict=block` 时消息流显示 blocker 列表（与 review-annotations 权威内容一致）+ 「reviewLoop attempt N/3」轮次指示，轮次随修复循环递增 | P0 |
| FR-6 | **CR 16 态徽标**：chatHeader 显示项目关联 CR 的 16 态徽标（直读 `cr` 投影表，WS 实时更新）；多 CR 并存时的取值规则（如最近活跃 pipeline 任务所属 CR）SDD 定案；徽标只读，不提供任何状态操作入口（看板"禁止反向"约束同样适用） | P0 |

## 4. 非功能需求

- **NFR-1 审批强度不降级**：人类身份（mat_ 403）、签名、证据漂移检测全部依赖服务端与 crctl
  既有校验；前端不缓存、不代签、不实现任何绕过路径；审批动作仅经用户会话鉴权的审批 API。
- **NFR-2 权威铁律**：UI 永不写 CR 状态；一切 CR 数据只读 `cr` 投影；本 CR 不触碰同步 worker
  与状态机转移表。
- **NFR-3 零回归**：B4 迁移后既有队列全语义（入队/claim/撤回/容量守卫/插队）回归不变；
  CR-2026-004 与 CR-2026-006 交付的代码路径不因两列新增改变行为。
- **NFR-4 双端一致**：web 与 desktop（Electron 共享 `packages/views`）行为一致；mobile 不在 P2 范围。
- **NFR-5 四语文案**：审批卡/状态条/徽标全部新增 UI 文案提供 en/ja/ko/zh-Hans，locale parity 测试全绿。

## 5. 验收标准

- **AC-1**（FR-2/3/4，核心链路）真实跑一条带 `human_approval` 节点的 pipeline：消息流出现门禁
  状态条与审批卡 → 网页点批准 → 服务端签名 grant → daemon 落盘 → crctl 验签推进 → 投影回流
  → 卡片自动转已批准态，**全链路不落 TTY**，无需手动刷新。
- **AC-2**（FR-4，驳回路径）网页驳回并填写 reject_reason → 状态机走显式回退转移，`reject_reason`
  作为 review_feedback 注入修复节点（修复任务上下文中可见）；消息流 reviewLoop 轮次递增。
- **AC-3**（FR-5）构造 review 节点 `verdict=block` → 消息流 blocker 列表与 review-annotations
  权威内容一致，attempt N/3 指示正确。
- **AC-4**（FR-6）chatHeader 徽标与 `cr` 投影表状态一致（16 态全集渲染无缺）；`crctl advance`
  触发状态转移后徽标经 WS 实时更新，无需刷新。
- **AC-5**（FR-1，迁移回归）B4 迁移后：既有 chat/quick-create/autopilot/评论 @提及四路入队、
  claim、撤回、容量守卫回归全绿；非 pipeline 任务两列保持 NULL；`pipeline_node_run` 删除时
  队列行 `ON DELETE SET NULL` 生效。
- **AC-6**（NFR-1，安全回归）mat_ 任务令牌调审批 API 仍 403；批后篡改证据文件 → 卡片操作返回
  409 且展示结构化漂移原因、状态不推进；无审批权限成员只见只读卡、无批准/驳回按钮。
- **AC-7**（NFR-4/5）web 与 desktop 行为一致；locale parity 测试全绿。

## 6. 成功指标

- 签名审批首次获得产品级 UI：审批人从"调 API / 找有 TTY 的机器"变为"在群聊消息流内一键批准/驳回"，
  P1 成功指标"无 TTY 审批完成率 100%"在真实产品交互下成立。
- 门禁过程在协作现场可见（过程即记录）：pipeline 任务卡点、blocker、修复轮次、CR 精确状态
  全部呈现在团队共享的消息流与窗口头部，不再需要翻 git 仓核对。
- P3 治理指标获得数据地基：`agent_task_queue.cr_id` / `pipeline_node_run` 归因落库，
  EPC（原型直出）与 ACM（Agent 协作）指标的引用表就位。

## 7. 范围排除

- **Pipeline Runner 全量编排**（总 PRD P1-F2：线性 nodes + reviewLoop 回边 + passCondition
  解释器 + 显式 when 提升 + 四条主 pipeline 持久化编排）→ 另行 CR；本 CR 只建表 + 最小归因路径。
- 「{count} 个待审批任务」计数入口与审批任务中心页（CodeBanana 有计数佐证）→ 后续按需注册。
- 审批角色策略的配置界面（策略本身沿 P1 服务端可配实现，本 CR 不做管理 UI）。
- EVIDENCE_DRIFT / 越权尝试的治理看板呈现 → P3 治理板块（数据留证 P1 已交付）。
- DC 协调者与合并转发 → CR-G；presenter 控制权 → CR-E（并行 CR，互不依赖）。
- 切分文档 §0.4 全部写死排除项继续有效（双入口、work-viewer、上下文用量、语音、回复/转发、
  斜杠命令、导出 Skill 草稿、恢复检查点、点踩反馈、mobile）。

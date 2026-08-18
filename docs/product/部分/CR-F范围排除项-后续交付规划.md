# CR-F 范围排除项 — 后续交付规划

> 来源：CR-2026-011（P2 三模式聊天 CR-F：D7 门禁接合）PRD §7 的范围排除项。
> CR-F 起草时核实出一个切分文档未明说的事实：`pipeline_run` / `pipeline_node_run` 两表
> 从未创建（CR-2026-002 只建了 cr / cr_sync_event / approval_record），**Pipeline Runner
> （总 PRD P1-F2）未被任何 CR 交付**。CR-F 已把"建表 + 最小节点运行归因路径"收进自己
> 范围以保验收可跑，其余排除项在此规划归宿，防止"排除"演变成"遗忘"。
> 日期：2026-08-02。
>
> **修订状态（2026-08-17）**：本文保留为 CR-F 起草时的历史规划。当前方案见 `缺口清单-计划未做.md`、`缺口清单-排除与条件触发.md` 与 `docs/analysis/AI-First平台缺口修订与最小落地方案.md`；Runner 已改为“architecture-design 纵切 → 四主 Pipeline”，审批中心与角色策略不再捆绑，§4 的永久排除口径也已拆成维持不做、最小替代和条件 backlog。

---

## 0. 排除项清单与归宿总览

| # | 排除项 | 归宿 | 状态 |
|---|---|---|---|
| 1 | Pipeline Runner 全量编排（P1-F2 遗留） | **新 CR（本文 §1，建议序号 CR-H）** | 需规划，本文主体 |
| 2 | 待审批任务计数入口 + 审批任务中心 | **新 CR（本文 §2，与 §3 合并为"审批周边"）** | 需规划 |
| 3 | 审批角色策略配置界面 | 同上（§2 合并交付） | 需规划 |
| 4 | EVIDENCE_DRIFT / 越权尝试治理看板 | P3 §1.2 治理板块（已有设计，数据留证 P1 已交付） | 已有归宿，不重复规划 |
| 5 | DC 协调者 + 合并转发 | CR-G（切分文档已定义，**尚未注册**——007~011 只注册到 CR-F） | 待注册 |
| 6 | 切分文档 §0.4 写死排除项 | 无归宿，**故意不做** | 重申，防被当遗漏 |

**建议交付序列**：CR-G 注册补齐（依赖 CR-D，不依赖本文各项）→ CR-H Pipeline Runner
（依赖 CR-F 落地后）→ 审批周边 CR（依赖 CR-F，量级小，可与 CR-H 并行）。

---

## 1. CR-H（建议）：Pipeline Runner 全量编排

**这是全平台当前最大的已识别缺口**——总 PRD 里程碑 M1（"一条需求走完四主 pipeline +
完整 traceability"）与验收项 A2 都以它为前提，但它在 P1 交付时被留下，此后无 CR 承接。

### 1.1 现状（CR-F 交付后的起点）

- crctl 是**门禁引擎不是编排器**：状态机、gate、审批都在，但"按 pipeline JSON 依次驱动
  节点、失败走 reviewLoop 回边"目前靠 IDE 内 Agent + 人工驱动（M0 以来一直如此）。
- CR-F 已交付：`pipeline_run` / `pipeline_node_run` 两表（P0 §3.4 schema）、
  `agent_task_queue.cr_id` / `pipeline_node_run_id` 归因两列（B4）、pipeline 节点任务的
  **最小归因路径**、门禁状态条/审批卡/blocker/reviewLoop 的**全部 UI 消费面**。
- P1 已交付：grant 签发 API、daemon 轮询下发（`GET /api/daemon/approvals/pending`）、
  `crctl approve --grant` 验签推进——审批链路无 Runner 也能走，Runner 缺的是"编排"不是"门禁"。

### 1.2 范围（沿总 PRD §Pipeline Runner 定义，不扩）

1. **线性编排器**：按 `pipeline-templates/*.pipeline.json` 依次驱动 nodes（3 种 kind），
   每节点建 `pipeline_node_run` 行、任务入队带归因两列（复用 CR-F 归因路径，从"最小"升级为"全量"）。
2. **passCondition 解释器**：equals / isEmpty 两种（与 crctl 现有解析对齐，单一事实源仍是
   pipeline JSON，不新增声明格式）。
3. **reviewLoop 回边**：review 节点 `verdict=block` → 回到修复节点，attempt 计数递增、
   上限 3；轮次经 crctl 回写 `review-loop.yml`——**全表唯一的 PG→git 反向流动**（权威铁律
   的既定例外，总 PRD §数据权威已声明）。
4. **human_approval 节点**：阻塞等待 grant（runner 把 grant 作为任务上下文交 daemon，
   P1 §B.1 ④ 的 runner 路径；daemon 轮询路径保留为兜底）。
5. **自然语言条件提升为显式 when**：pipeline JSON 逐步补写；过渡期未补写的条件交模型判断
  （总 PRD 风险表既定策略，不在 Runner 内做 NLP）。

### 1.3 明确不做

- DAG / 并行分支——8 条 pipeline 全是线性 + 回边，YAGNI。
- 新的 pipeline 声明格式——JSON 模板与 dir-graph.yaml 仍是单一事实源。
- runner 轻量档池编排（多机调度）——P2.5 DevOps 议题，单 daemon 起步。

### 1.4 验收要点与量级

- 一条真实需求端到端走完四条主 pipeline（规划/需求/架构/编码），traceability 完整——
  即总 PRD A2 / M1 门槛。
- reviewLoop 实测：构造 block → 修复 → attempt 1→2 递增，`review-loop.yml` 回写与
  `pipeline_node_run.attempt` 一致；聊天窗口内 CR-F 的状态条/attempt 指示直接复用、无需改 UI。
- human_approval 节点实测：runner 阻塞 → 网页批准（CR-F 审批卡）→ grant 注入 → 推进。
- 乱序/崩溃恢复：runner 重启后从 `pipeline_node_run` 状态续跑，不重复入队（幂等键）。
- 量级粗估：后端 6–8 人日（编排器 + 解释器 + 回写 + 恢复语义），前端 0（CR-F 已备齐）。
- 风险：自然语言条件的过渡期语义（既定策略是交模型，需在 SDD 写清判定失败的降级路径）。

---

## 2. 审批周边 CR（建议）：待审批中心 + 角色策略配置

两项都小，合并为一个纯周边 CR，避免两个 1 人日级碎片 CR。

### 2.1 待审批任务计数入口 + 审批任务中心

- **依据**：CodeBanana 快照有「{count} 个待审批任务」计数与 Approval Workflow 项目实证——
  场景真实存在；CR-F 只把审批卡放进单个项目的消息流，审批人跨多项目并行时没有聚合入口。
- **范围**：全局导航（侧栏或 header）待审批计数徽标（WS 实时）；审批中心列表页——聚合
  "我有权审批且 pending"的审批项（CR / stage / 证据摘要 / 等待时长），点击跳转对应项目
  聊天窗口并定位到审批卡（不在列表页重复实现审批操作，单一操作入口在卡片）。
- **后端**：一个聚合查询端点（按当前用户角色策略过滤 approval 待办），小。

### 2.2 审批角色策略配置界面

- **现状**：P1 的审批人校验是"审批人 ∈ cr.owners 对应角色 或 具备审批角色（策略可配）"，
  但"可配"目前只在服务端配置，无 UI。
- **范围**：工作区设置页新增一节：四个 approvalStage（`gates.json#approvalStages` 的四个键）
  各自映射可审批角色集合；改动即生效、留 `activity_log` 审计行。
- **不做**：per-CR / per-项目粒度策略、审批委托/代理——需求出现再说。

### 2.3 前置与量级

前置 CR-F（审批卡与权限判定先存在）。合计 2–3 人日（前端为主 + 一个聚合端点 + 一个配置端点）。
优先级 S2：审批人单项目阶段不痛，多 CR 并行后升 S1。

---

## 3. 已有归宿项（指针，不重复规划）

- **EVIDENCE_DRIFT / 越权尝试治理看板**：P3 §1.2 治理板块已含设计；数据留证链路
  （`activity_log` 两个 action）P1 已交付。唯一注意事项沿 P1 §B.4：指标上线时必须能区分
  "从未漂移"与"从未测过"。
- **CR-G（DC 协调者 + 合并转发）**：切分文档 D8 节已定义范围与验收，依赖 CR-D（+CR-A）。
  当前批次只注册到 CR-F（007~011），**CR-G 需要在 CR-D 交付后补注册**——列入注册待办，
  设计阶段先定 0.3 节的两处偏差（DC 可见输出、合并转发自研交互）。

## 4. 故意不做（重申切分文档 §0.4，防被当遗漏）

项目/消息双入口、右侧 work-viewer、上下文用量指示器、语音输入、消息回复线程/逐条转发、
成员管理增强、斜杠命令、导出 Skill 草稿、恢复检查点、点踩反馈、mobile（RN 版另立交付）。
以上均有排除理由记录在切分文档 §0.4，本文不重开。

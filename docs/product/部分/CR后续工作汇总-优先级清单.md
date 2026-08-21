# CR 后续工作汇总 — 优先级清单

> 来源：通读 change-requests/CR-2026-001 至 CR-2026-011 全部报告（cr.md / prd.md / sdd.md /
> test-report.md / review-annotations）后汇总的"建议后续工作"清单，按优先级分级。
> 与《CR-F范围排除项-后续交付规划.md》衔接：该文覆盖 CR-F 的排除项归宿；本文覆盖全部 11 个
> CR 中出现的后续建议，含规划文档之外的验收补验项、技术债、上游回馈候选。
> 日期：2026-08-03。
>
> **修订状态（2026-08-17）**：本文保留为 CR-001~011 时点的历史汇总；当前优先级、Runner 最小落地和排除项分类已由 `缺口清单-计划未做.md`、`缺口清单-排除与条件触发.md` 与 `docs/analysis/AI-First平台缺口修订与最小落地方案.md` 修订。本文中的“前置全部就位”“审批周边可与 Runner 合并/并行”“P3 组织智能 + Wiki 打包”和“写死排除”不再作为立项依据。

---

## 0. 总览（按优先级）

| 级 | 内容 | 建议动作 |
|---|---|---|
| **P0** | CR-H Pipeline Runner、CR-G（CR-2026-012 已注册）、ChatInput 解耦技术债 | 立即立项 |
| **P1** | 审批周边 CR、部署前真机验收关口、P3 组织智能 + Wiki 立项 | 中期 |
| **P2** | 上游回馈 PR、mdt_ 单轨化、Skill 安装器、测试失败诊断等工具链收尾 | 随时可并行 |
| **P3** | 上下文用量/清空、回复线程/转发/语音、恢复检查点、斜杠命令、mobile 等 | 按需/条件触发 |
| **不做** | 切分文档 §0.4 写死排除项 | 重申，防被当遗漏 |

---

## 1. P0 — 已识别、建议立即立项（有明确归宿且前置已就位）

### 1.1 CR-H：Pipeline Runner 全量编排

- **来源**：CR-2026-011 PRD §7；《CR-F范围排除项-后续交付规划》§1。
- **定位**：**全平台当前最大的已识别缺口**——总 PRD 里程碑 M1（"一条需求走完四主 pipeline +
  完整 traceability"）与验收项 A2 都以它为前提，P1 交付时被留下，此后无 CR 承接。
- **范围**：线性编排器（pipeline-templates JSON 驱动，3 种 kind）；passCondition 解释器
  （equals / isEmpty）；reviewLoop 回边（verdict=block → 修复节点，attempt ≤3，PG→git
  回写 review-loop.yml——全表唯一反向流动）；human_approval 阻塞等待 grant（runner 注入
  路径，daemon 轮询兜底）；自然语言条件提升为显式 when。
- **明确不做**：DAG/并行分支（8 条 pipeline 全线性，YAGNI）；新声明格式；多机调度
  （P2.5 DevOps 议题，单 daemon 起步）。
- **量级**：后端 6–8 人日，前端 0（CR-F 已备齐全部 UI 消费面）。
- **状态**：前置全部就位——CR-F（建表 pipeline_run / pipeline_node_run、归因两列、
  最小归因路径、门禁状态条/审批卡/blocker/徽标）已于 2026-08-03 归档。

### 1.2 CR-G：DC 协调者 + 讨论转执行（合并转发）

- **来源**：交付切分 v2 D8；CR-2026-009 cr.md（"CR-G 依赖本 CR"）；CR-2026-012。
- **状态**：**已注册（CR-2026-012，status=drafting，target-version 0.19）**，尚未启动设计。
- **范围**：DC 特殊 Agent——默认静默、@提及或回复激活；只协调不执行（execenv 只读 +
  forbidden 全部写 Skill）；可 EnqueueTaskForMention 路由到 Team Agent。合并转发——多选
  Discussion 消息合并为带 triggerMessage + chatHistory 汇总结构的 Team Agent 任务；
  无 CR 时可触发 requirement-register 升级为 CR。
- **设计阶段必须先定两件事**（切分文档 0.3 两处偏差）：① DC 输出可见性（本文预设可见
  协调输出，审计要求，与 CodeBanana 静默协调器不同）；② 合并转发是本平台增量
  （CodeBanana 只有逐条转发），需自行设计多选态与合并预览。
- **依赖**：CR-D（已归档）+ CR-A（已归档）。

### 1.3 ChatInput 组件与全局 store 解耦技术债

- **来源**：docs/product/P2-ChatInput组件与全局store解耦-技术债务.md §6。
- **触发条件已成立**：该文约定"CR-D 或 CR-G 任一个开始设计阶段"即立项——CR-G 已注册。
- **背景**：4 个 CR 独立绕过同一个坑：CR-A 输入区未复用 chat-input.tsx（改用绑定
  project-chat-store 的最小 composer）；CR-C 附件/@提及延后（FR-8，chat-input.tsx 读全局
  useChatStore，引入会把本面草稿泄入全局命名空间）；CR-D 草稿走 ReplyInput 原生 draftKey。
  收敛为一次性解决，可让附件/@提及/完整输入区能力回归三模式各面。
- **建议**：CR-G 设计前或随 CR-G 一并立项（立项验收标准见技术债务文 §6）。

---

## 2. P1 — 中期（量级小或构成部署前置）

### 2.1 审批周边 CR：待审批中心 + 角色策略配置

- **来源**：《CR-F范围排除项-后续交付规划》§2。
- **范围**：① 全局导航待审批计数徽标（WS 实时）+ 审批中心列表页（聚合"我有权审批且
  pending"的项：CR / stage / 证据摘要 / 等待时长，点击跳转对应项目聊天窗口定位审批卡，
  不在列表页重复审批操作）；② 工作区设置页新增 approvalStage 四键的可审批角色集合配置，
  改动即生效 + activity_log 审计行。
- **不做**：per-CR / per-项目粒度策略、审批委托/代理（需求出现再说）。
- **量级**：2–3 人日（前端为主 + 一个聚合端点 + 一个配置端点）。优先级 S2，多 CR 并行后升 S1。
- **依赖**：CR-F（已归档）。

### 2.2 部署前独立验收关口（真机补验项汇总）

多个 CR 明确标注"待 daemon runtime 环境 / 部署前独立验收"，构成一个集中的验收关口：

| # | 补验项 | 来源 |
|---|---|---|
| 1 | 本机 daemon 真实执行链路：agent claim+执行 → toolExecutionCard 流式渲染 → 完成回复 → 刷新回放；AC-7 daemon 上报模型列表一致性 | CR-006 AC-2/3/7、CR-007 AC-3、CR-008 §5 人工清单 |
| 2 | 双浏览器 WS 跨会话实时观察（一侧入队/撤回/presenter 转移，另一侧无刷新自动更新） | CR-004 AC-5、CR-007 AC-1、CR-010 AC-2 |
| 3 | 跨用户 @提及 → inbox 通知 → 跳转条 → 落对应 tab 的全链路（需第二真实账号 + 第二浏览器会话） | CR-009 AC-2 |
| 4 | web + desktop（Electron）双端视觉核对（chatHeader 主持人显示、控制权面板、6 种通知卡、CrGateCard 三变体） | CR-010 AC-5、CR-011 AC-7 |
| 5 | 真实 daemon commit-scan 循环驱动 review 事件（非手工构造 payload）；tech-design/dev-start/code 三个有回退转移阶段各跑一次真实驳回 | CR-011 §4 |
| 6 | 浏览器实测 `cr:updated` WS 推送后 CR 徽标无刷新自动更新 | CR-011 §4 |
| 7 | "注册第二个 workspace 被拒"字面场景（机制级已过，留待首次实际锁定部署） | CR-001 §5-1 |
| 8 | 一个真任务内 gitguard 三层拦截齐动（shim/hook/铸造） | CR-002 §5-1 |

### 2.3 P3 组织智能 + Wiki 子系统立项

- **来源**：总 PRD（P3 里程碑）；docs/product/P3-组织智能设计.md、Wiki子系统设计.md
  （设计文档已存在，**尚无任何 CR 承接**）。
- **衔接**：EVIDENCE_DRIFT / 越权尝试治理看板归宿在 P3 §1.2 治理板块（数据留证 P1 已交付；
  指标上线时必须能区分"从未漂移"与"从未测过"，沿 P1 §B.4）。
- **建议**：P2 收尾（CR-G 落地）后规划。

---

## 3. P2 — 上游回馈与工具链收尾（不阻塞主流程）

| # | 后续工作 | 来源 | 说明 |
|---|---|---|---|
| 1 | **上游回馈 PR 整理** | CR-001 test-report §6-①；CR-002 cr.md 备注 / review-annotations | 候选：claude.go 环境过滤名单（CR-001）；D1 outbox、rules.json 抽取、EVIDENCE_DRIFT/server-approve 扩展（tools 通用增强）；mdt_ 分支 X-User-ID 头统一处理（CODE-SUG-002）。CR-002 已注明"归档后单独整理 PR"——至今未做 |
| 2 | **上游 mdt_ 接线后 PAT 回退路径退役（单轨化）** | CR-002 CODE-SUG-003 / test-report §6-③ | rebase 时检查 `GenerateDaemonToken` 是否有调用方；有则开 CR 收敛到 mdt_ 单轨，避免长期双轨 |
| 3 | **56 个 Skill 导入 Multica 安装器化** | CR-001 test-report §5-4、review-annotations code.yml | `agent-import.mjs` 安装器化（--provider claude 自动解析首个在线 runtime），把 56 skill 导入 skill 表并绑定 |
| 4 | **Traecli/Qoder 测试失败根因诊断**（上游 3 个） | CR-001 test-report §6-② | 疑对本机环境有隐含假设，根因未诊断，仅建基线台账 |
| 5 | **TaskExecutionCard 迷你门禁指示条** | CR-011 test-report §3-4 | 需 Go 端 `AgentTask` 响应体新增 `cr_id` 字段（当前 T04 只写库不序列化），独立小任务 |
| 6 | **工具摘要聚合专用查询**（ListTaskMessages 无 LIMIT 全量读） | CR-002 CODE-SUG-001 | 超长任务完成时一次性载入内存；后续加只取 tool_use/tool_result 且限行的查询。当前规模不构成风险 |

---

## 4. P3 — 按需/条件触发（有明确触发时机或升级路径）

| # | 后续工作 | 触发条件 | 来源 |
|---|---|---|---|
| 1 | 上下文用量指示器 + 清空上下文；计费/用量归属展示（Owner/Presenter 可配，CR-010 只留判定基础） | 依赖 daemon usage 回调聚合，"随后续交付" | 切分文档 §0.4、CR-008 PRD、CR-010 PRD |
| 2 | 消息回复（reply）线程、逐条消息转发、语音输入 | §0.4 "后续"（D8 合并转发除外） | 切分文档 §0.4、CR-009 PRD |
| 3 | 恢复检查点（三态回滚）——独立 CR 量级 | 按需 | 切分文档 §0.4、CR-008 PRD |
| 4 | 斜杠命令（含只读类命令）、成员管理增强（邮件邀外部/解散群组/头像编辑器）、导出 Skill 草稿、点踩反馈 | 按需 | 切分文档 §0.4 |
| 5 | mobile（独立 RN 组件集） | P2 全程不在范围，RN 版另立交付 | 切分文档 §0.4 |
| 6 | timeline 分页（现硬帽 2000 无分页）；Team Agent 面附件接线（comment 关联需额外接线）；执行卡耗时实时跳秒 | 消息量逼近上限 / 用户反馈 | CR-006 test-report §3 简化项 |
| 7 | presenter 收件箱/站内信全局通知中心 | 随平台通知体系另议 | CR-010 PRD |
| 8 | 多 worktree 并行执行（per-project 串行是天花板）；runner 轻量档池编排 | P2.5 DevOps 议题 | CR-010 SDD 风险表、《CR-F范围排除项》§1.3 |
| 9 | ContentEditor mention 目标过滤 prop（@列表仍含 agent 的 UX 误导） | 观察实际误用率后决定 | CR-009 DD-7 升级路径 |
| 10 | 项目级成员模型（Discussion 行内系统条 AC-7 裁剪的升级路径） | 未来引入项目级成员模型时 | CR-009 test-report AC-7 |
| 11 | canApprove 补 `cr.owners` 分支（crctl caller ↔ user.id 身份桥接） | 平台有身份映射表后 | CR-011 SDD §4 升级路径 |
| 12 | 仓库转 private 时重新核验只读 PAT 范围 | 条件触发 | CR-002 test-report §5-4 |
| 13 | `_history.yml` 数千条后分片/旁路缓存 | 量级增长到数千条 | CR-003 test-report §5-2 |
| 14 | 悬浮 1:1 chat 组件展示性观察（测试工作区双 agent 未选对象所致） | 已用 spawn_task 登记，按需调查 | CR-007 test-report §3 |

---

## 5. 明确"故意不做"（重申切分文档 §0.4，防被当遗漏）

项目/消息双入口、右侧 work-viewer、上下文用量指示器（见 §4-1 实际随后续交付）、语音输入、
消息回复线程/逐条转发、成员管理增强、斜杠命令、导出 Skill 草稿、恢复检查点、点踩反馈、
mobile（RN 版另立交付）。以上均有排除理由记录在切分文档 §0.4 与《CR-F范围排除项》§4，不重开。

---

## 6. 建议执行序列（依赖链视角）

```
CR-G（CR-2026-012，已注册 drafting）──→ P2 三模式收尾
   └─ 同时触发：ChatInput 解耦技术债立项
CR-H Pipeline Runner ──→ M1/A2 前提，最大缺口（依赖已全就位）
审批周边 CR ──→ 可与 CR-H 并行（小）
部署前验收关口（daemon / 双浏览器 / 跨用户）──→ 阻塞真实部署，环境就绪时优先执行
P3 组织智能 + Wiki ──→ P2 收尾后规划
上游回馈 / 工具链收尾 ──→ 随时可并行
```

**注**：CR-2026-002 时期的"三仓远端缺失"前置缺口已解决（GitHub 三仓就位，见 CR-002 PRD
前置声明），不再构成阻塞项。

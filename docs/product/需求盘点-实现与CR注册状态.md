# 需求盘点 — docs/product 实现状态与 CR 注册对照

> 平台级需求追踪文档：对照 `docs/product/` 下各需求文档与**实际代码实现情况**（当前工作区 `AI First Platform` 的运行态证据 + 其 `dir-graph.yaml` 声明的 sibling 代码仓库 `../multica`、`../tools`），输出「已实现 / 部分实现 / 未实现」全景，并对照 CR 注册台账给出承接关系。
> 盘点时点：**2026-08-17**（CR-2026-044 归档完成后；应用代码基线 = `../multica` HEAD `merge CR-2026-031`，工具包基线 = `../tools` HEAD `merge CR-2026-043`）。
> 上次盘点：2026-08-17（基于 CR 台账）；本次为**基于实际代码的实证盘点**，与台账结论交叉印证。

---

## 0. 数据口径（本次盘点的关键前提）

### 0.1 实证基：当前工作区 + 其声明的代码仓库

`AI First Platform` 是知识库/文档工作区，不含应用源码；其实际代码实现由两部分构成：

**① 工作区内运行态证据（状态机实际运行产物）**

| 证据 | 实测内容 | 佐证的功能 |
|---|---|---|
| `.crctl/outbox/` | 244 个历史事件文件 | crctl outbox 机制（P1 D1）实际产生过事件 |
| `.crctl/keys/aifirst-approval-2026-07.pub` | 签名审批公钥已提交入库 | 签名审批（P1 D4）公钥分发链在位 |
| `.crctl/.scan-cursor` | 有游标值 `d8185ed…` | daemon commit 扫描兜底通道（P1 D2）运行过 |
| `.crctl/audit.log` | 至 `2026-08-17T11:01:57` CR-2026-044 archive complete | crctl 全流程行为审计持续记录 |
| `.github/workflows/cr-guard.yml` | 存在 | 远端复核门禁（P1 C.4 第 5 层） |
| `specs/_index.yml` | ~~v0.20.5，cr-ref CR-2026-044，cr-history 36~~ → **实为 v0.20.7，cr-ref CR-2026-046，cr-history 38**（2026-08-19 重核） | 回写基线累积（CR-001~012 产品 CR 全在列）。盘点后 CR-045/046 又归档两个，原数字已陈旧 |
| `delivery/task/` | 254 个交付任务索引文件 | writeback 交付产物 |
| `change-requests/` | `_history.yml`：CR-001～044（36 archived / 8 withdrawn）；`_backlog.yml` 为空 | CR 台账：产品需求全部有终态 |
| `wiki/` | **不存在** | Wiki 子系统零落地 |

**② 工作区声明的 sibling 代码仓库**（`dir-graph.yaml#workspace.tools_package_path` = `../tools`，`#repositories` 声明应用仓）

| 组件 | 位置 | 基线 | 说明 |
|---|---|---|---|
| **multica 定制版** | `C:\Users\GOBAO\Downloads\AI\multica`（`../multica`） | HEAD = `merge CR-2026-031`，migrations 628 个，CUSTOM.md 82 条登记 | 平台应用代码（Go 后端 + Next.js 前端），定制迁移 `158_aifirst_*` / `162_aifirst_*` 在位 |
| **tools 定制版** | `C:\Users\GOBAO\Downloads\AI\tools`（`../tools`） | HEAD = `merge CR-2026-043`，crctl.mjs 3070 行（outbox 51 处、`--grant` 63 处） | 方法论包（9 Agent / Skill / 8 Pipeline / crctl / rules.json） |

### 0.2 判定规则

| 结论 | 判定 |
|---|---|
| 已实现 | 核心功能在代码中可定位到实现（文件/端点/迁移），核心流程可运行 |
| 部分实现 | 仅部分功能模块落地，列出具体缺失点 |
| 未实现 | 代码中无对应实现，或缺失关键依赖 |

---

## 1. 总览表（文档 × 实现状态 × 缺失项）

| 文档名称 | 实现状态 | 缺失项/待办事项详情 |
|---|---|---|
| `AI-First平台-PRD.md`（总 PRD v1.2） | **部分实现** | M0/P1-F1·F3·F4·F5·F6/P2-F1·F2·F3 + DC 已落地；**P1-F2 Pipeline Runner、P2-F4 A2A、P2-F5 IM 7 平台（仅 4 平台）、P2-F6/F7/F8（排除项）、P2.5 runner 轻量档、P3 全部（A8/A9）、Wiki 子系统均未实现**；验收 A2/M1 因 Runner 缺失未达成（详见 §3.1） |
| `P0-数据模型映射表.md` | **已实现** | 5 张新表 + 2 列迁移全部落地（158/162 迁移）；同步 worker（governance/crsync.go）在位；TASK 子 Issue 投影按 ADR-0001 悬置（文档已追认，非缺口）；**maturity_snapshot 属 P3 未落地；spec_trace 与 department 已于 2026-08-19 从 P3 设计中砍除（前者见 §7 R-10，后者见 2026-08-07 决策①）——两者不再是待建项** |
| `P1-crctl接入设计.md` | **已实现** | D1–D7 全部交付：crctl outbox（51 处）· `internal/daemon/crevents.go` · `POST /api/daemon/cr-events`（router.go:998）· `governance/crsync.go` · reconcile（governance/reconcile.go + reconcile_github.go）· 签名审批（`governance/approval.go` + `approval_record` 表 + crctl `--grant` 63 处）· `pkg/gitguard`（+spool 审计）· `rules.json` · EVIDENCE_DRIFT 留证（`governance/audit.go`） |
| `P2-三模式聊天交互设计.md` | **部分实现** | 主体已落地：三 tab / 队列（D1）/ presenter（project_presenter.go + presenter-control-sheet）/ toolExecutionCard / Private Ask / Discussion / DC+合并转发（comment.go `EnqueueTaskForMention`）/ 门禁接合（cr-gate-card.tsx + cr-status-badge.tsx）。**缺失**：技能选择器（前后端均无）、斜杠命令面板（`enableSlashCommands` 为 Tiptap 上游能力，非 `/需求` 等平台命令）、导出 Skill 草稿、恢复检查点、回复线程、语音、成员管理增强、上下文用量指示器——均按切分 §0.4 排除或未立项 |
| `P2-三模式聊天窗口主体-交付切分.md` | **已实现** | CR-A→006 ~ CR-G→012 全部交付（代码实证：project-chat-panel / project-team-agent-chat / project-private-ask / discussion-pane / project-queue-bar/status / cr-gate-card / cr-status-badge / merge_forward 全链路） |
| `P2-ChatInput组件与全局store解耦-技术债务.md` | **部分实现** | §1–§6 解耦已闭环：`ChatInputCore` + `ChatInputDraftAdapter` 就位（chat-input.tsx L745 起），Team Agent / Private Ask 面已接 adapter。**§7 技能选择器仍开放**（ChatAddMenu 注释原文 "leaving room for future add-actions"，前后端均未实现，语义未定案） |
| `P3-组织智能设计.md` | **未实现** | 代码零落地：无 maturity_snapshot / spec_trace / drift_finding / skill_usage_event 迁移；无 `/api/maturity` 端点；无 maturity / workshop 前端路由；skill 表无 visibility / version / owner_actor（Skill Market 无）；无周报 Autopilot（Org Admin Workspace 项目不存在）；drift 巡检未接平台侧 sys_cron 派发（tools 有 review-alignment skill 但仅手动）；bypass-commit 探测未落地。曾注册 CR-013～017，**2026-08-14 全部撤回**，编号作废 |
| `Wiki子系统设计.md` | **未实现** | 零落地：knowledge-base 无 `wiki/` 目录；tools 无 wiki-maintain skill（skills 九域无 wiki 域）；无 `wiki_query_log` 表；无 `rules.json#taskWriteAllowlist`；问答/晋升层随 P2.5 runner 一并缺失。openwiki 仅为上游借鉴参考 |
| `CR-F范围排除项-后续交付规划.md` | **部分实现**（元文档） | 其中 **CR-G（DC + 合并转发）已由 CR-2026-012 落地**；**CR-H Pipeline Runner 未注册未实现**（全平台最大缺口）；**审批周边**（待审批中心 + 审批角色策略配置 UI）未注册未实现；EVIDENCE_DRIFT/越权治理看板归宿 P3（随 P3 未落地） |
| `CR后续工作汇总-优先级清单.md` | **部分实现**（元文档） | **ChatInput 解耦已闭环**（§1.3）；CR-H / 审批周边 / 部署前验收关口（行为项，未执行）/ P3+Wiki 立项 / 上游回馈（上游 PR、mdt_ 单轨化、Skill 安装器、TaskExecutionCard 门禁指示条等）均仍开放 |
| `需求盘点-实现与CR注册状态.md` | 元文档 | 本文件（2026-08-17 基于代码实证重写） |

---

## 2. 已实现（代码实证 + 归档 CR 承接）

| 需求文档 | 主题 | 代码证据 | 承接 CR |
|---|---|---|---|
| P0-数据模型映射表 | cr / cr_sync_event / approval_record / pipeline_run / pipeline_node_run + `agent_task_queue.cr_id` / `pipeline_node_run_id` | 迁移 `158_aifirst_cr_projection`、`162_aifirst_pipeline_runs`（含 ALTER atq 两列）；governance/crsync.go 消费链路 | CR-001 / CR-002 / CR-011 |
| P1-crctl接入设计 D1–D7 | 同步协议 · 签名审批 · controlled-shell 下沉 · 行为审计 · EVIDENCE_DRIFT | crctl.mjs outbox+`--grant`+EVIDENCE_DRIFT；daemon/crevents.go；router.go:998 `cr-events` / :1001 `approvals/pending` / :1412 `queue-status`；governance/{crsync,approval,reconcile,audit,project_gates}.go；pkg/gitguard/{gitguard,spool}.go；`rules.json` | CR-002 / CR-003 及后续治理 CR |
| P2-三模式聊天（切分 CR-A～G） | 三 tab 窗口、队列治理、Private Ask、Discussion、Presenter、门禁接合、DC + 合并转发 | project-chat-panel.tsx / project-team-agent-chat.tsx / project-private-ask.tsx / discussion-pane.tsx / presenter-control-sheet.tsx / project-queue-bar.tsx + project-queue-status.tsx / cr-gate-card.tsx + cr-status-badge.tsx / service/project_chat.go + project_presenter.go + `project_presenter_grant` 表 / comment.go `EnqueueTaskForMention` | CR-004、006～012 |
| P2-ChatInput 解耦 §1–§6 | ChatInputCore + ChatInputDraftAdapter | chat-input.tsx L745+（接口 + 默认落回 useChatStore + adapter 注入） | CR-012（DD-9/DD-10） |
| 总 PRD 对应部分 | M0 / P1 主体 / P2 三模式 | 与上表对应 | CR-001～012 |

---

## 3. 部分实现 — 缺失项明细

### 3.1 总 PRD（`AI-First平台-PRD.md`）

| 需求项 | 现状 | 差距 |
|---|---|---|
| M0：fork + 9 Agent 注册 + 派单执行 + 一致性 CI | ✅ 已实现 | — |
| P1-F1 CR 投影三通道同步 | ✅ 已实现（outbox + commit 扫描 + reconcile） | — |
| P1-F3 服务端签名审批 | ✅ 已实现（approval_record + grant + `approvals/pending` 轮询） | — |
| P1-F4 gate 重算 evidence digest | ✅ 已实现（EVIDENCE_DRIFT，TTY 与 grant 两轨） | — |
| P1-F5 controlled-shell 白名单下沉 | ✅ 已实现（pkg/gitguard + rules.json + PATH shim + hooks 铸造） | — |
| P1-F6 AI 行为审计 | ✅ 已实现（governance/audit.go + gitguard/spool.go，activity_log） | — |
| **P1-F2 Pipeline Runner** | ❌ **未实现** | `pipeline_run` / `pipeline_node_run` 两表已建（162 迁移），但 **internal 无任何 pipeline 编排器代码**：无线性 nodes 驱动、无 passCondition 解释器、无 reviewLoop 回边、无崩溃恢复。现状仍靠 IDE Agent + 人工驱动。**卡死验收 A2 / 里程碑 M1** |
| P2-F1/F2/F3 三模式 + Presenter + 工具卡 | ✅ 已实现 | — |
| **P2-F4 A2A 跨项目派单** | ❌ 未实现 | 无 Add Agent 前端组件、无 `@agent` 派单入口、无 A2A 记录面板、后端无对应 API。DC 的 `EnqueueTaskForMention` 是 Discussion→Team Agent 单项目内路由，不是跨项目 A2A |
| **P2-F5 IM 渠道 7 平台** | ⚠️ **部分实现** | 实际 4 平台：lark / slack（上游既有）+ dingtalk / wecom（定制新增，`internal/integrations/` 实测）。Telegram / Discord / QQ 缺失（OpenClaw 补齐未立项） |
| P2-F6 恢复检查点 / F7 斜杠命令 / F8 导出 Skill 草稿 | ❌ 未实现 | 切分 §0.4 写死排除或按需触发；斜杠命令仅有 Tiptap 上游 `enableSlashCommands`（格式化菜单），非 `/需求` `/评审摘要` `/进度` `/工作流` 平台命令 |
| P2.5 runner 轻量档（含 LLM Wiki 问答） | ❌ 未实现 | 依赖 Pipeline Runner + Agent SDK 服务端直连；无 `wiki_query_log` 表；Org API Key 路径未接线 |
| P3 全部（A8/A9） | ❌ 未实现 | 见 §4.1。**但无技术阻塞**：不依赖 Pipeline Runner（读侧投影已交）、不依赖 Wiki（E9 已移出），可立即重新注册开工 |
| Wiki 子系统 | ❌ 未实现 | 见 §4.2 |

### 3.2 P2 交互设计（超出切分范围的能力）

已落地：三 tab / 队列 / presenter / 工具卡 / 门禁接合 / Private Ask / Discussion / DC+合并转发（对应切分 D1–D8 全交付）。

缺失（均未注册 CR）：

| 缺失项 | 详情 |
|---|---|
| **技能选择器** | 输入区能力表标注 Team Agent / Private Ask ✓ 但从未实现：前端 ChatAddMenu 仅文件上传（注释 "leaving room for future add-actions (agents, skills, tools)"）；后端无"本条消息 narrow 到指定技能子集"通路（execenv 无条件物化全部 AgentSkills）。语义未定案（窄化上下文 vs 技能即调用） |
| 斜杠命令面板 | 4 条命令（/需求、/评审摘要、/进度、/工作流）映射 Pipeline API 的设计未落地 |
| 导出 Skill 草稿 | 会话多选 → SKILL.md 草稿 → 私有库，未实现 |
| 恢复检查点 | 三态回滚（worktree git 快照 + 消息树截断 + session 版本），独立 CR 量级，未立项 |
| 回复线程 / 语音 / 成员管理增强 / 上下文用量指示器 | 切分 §0.4 写死排除或按需触发，非缺口 |

### 3.3 P2-ChatInput 技术债文档

- §1–§6 已闭环（见 §2）。
- **§7 技能选择器仍开放**：前后端均未实现（同 §3.2），且窗口头部"[技能]"抽屉仍为占位（CR-006 PRD §7 遗留），归宿待 P3 Skill Market 前端开工时一并定案。

---

## 4. 未实现 — 明细

### 4.1 P3 组织智能（`P3-组织智能设计.md`）— 代码零落地

| 子功能 | 代码证据（缺失） |
|---|---|
| E1 成熟度快照（maturity_snapshot + maturity-config.yaml） | 无迁移、无配置、无 rollup 任务 |
| E2 看板前端（趋势/雷达/排名/治理板块） | `packages/views` 无 maturity/workshop 目录（analytics 为上游用量页，非成熟度看板）；无 `/api/maturity/*` |
| E3 周报 Autopilot（Org Admin Workspace） | 无内置项目、无周报任务 |
| E4 追溯投影 | 无 trace 事件 kind。~~无 spec_trace 迁移~~ → **该表已于 2026-08-19 从设计中砍除**（P3 §7 R-10），不再是缺口；改走 `cr_sync_event.payload`（`event_kind` 无 CHECK 约束，零迁移） |
| E5 漂移检测 | 无 drift_finding 表；无 bypass-commit 探测落地。~~tools 有 review-alignment skill 但无平台侧 sys_cron 派发~~ → **两个 LLM 巡检已于 2026-08-19 推迟**（P3 §7 R-11：七跳链路 + daemon 在线依赖，静默无结果与无漂移不可区分），P3 只交服务端纯前缀扫描 |
| E6 Skill Market（visibility/version/owner_actor + skill_usage_event + 发布门禁 + 元数据卡 + 敏感扫描） | skill 表无自研列（migrations 无对应迁移）；无 usage_event 表；无 Market 前端 |
| E7 交付效能板块 + AI 净价值叙事条 | 无（随 E1/E2） |
| E8 效能驾驶舱 + 待我审批端点 | 无路由（`apps/web` 无 workshop 页面）；现有 `/api/daemon/approvals/pending` 在 daemon 组、服务 grant 取件，**无用户侧待审批端点**。~~工坊三视图~~ → **已砍到一个**（P3 §7 R-18） |
| ~~E9 知识晋升巡检~~ | **已于 2026-08-19 整节移出 P3**，归《Wiki 子系统设计》 W5（P3 §7 R-12）——不再计作 P3 的缺口 |

注册状态：CR-2026-013～017 曾注册（目标 0.20→0.24），**2026-08-14 全部以 withdrawn 归档**（从未写 PRD/SDD、从未回写 specs），需求回到未注册。

> **2026-08-19 更正两条陈旧断言（开工前对代码重核）**：
> ① 原文“P3 依赖 Wiki（E9），Wiki 未立项，E9 不能单独先做”——**该依赖已断开**：E9 整节移入 Wiki 文档（其两个信号源、执行体、产出全在 Wiki 侧），P3 现在**与 Wiki 零依赖**，可独立开工。
> ② 原文隐含“P3 卡在 Pipeline Runner”（§6 将 CR-H 排在 P3 之前）——**只有写侧 Runner 未实现，读侧投影已交付**：`server/internal/governance/gate_projection.go`（CR-2026-011 TASK-02）的 `applyReview` 已向 `pipeline_node_run` 写入 `attempt`/`status`，`pipelineForStatus` 已覆盖全 4 条 pipeline，该文件头明写其目的就是“不必等完整 Pipeline Runner 存在”。故 **P3 的 EPC 原型直出率、ACM 流程完整率、Review 负担、blocker 列表均有现成数据源**，P3 不以 CR-H 为前置（§6 的排序依据仅为业务优先级，不是技术阻塞）。

### 4.2 Wiki 子系统（`Wiki子系统设计.md`）— 代码零落地

| 子功能 | 代码证据（缺失） |
|---|---|
| W1 `wiki/` 目录契约 | knowledge-base 无 `wiki/` 目录；dir-graph 无对应声明 |
| W2 wiki-maintain Skill + Autopilot + no-op 门槛 | tools skills 九域（competitive/cr/develop/planning/requirement/review/shared/spec/sync/writeback）无 wiki 域 |
| W3 写白名单（文件 + shell 双路径）+ 确定性三段式 | `rules.json` 无 `taskWriteAllowlist` 段；无三段式收尾节点 |
| W4 问答（wiki-first 三层 + 出处 + 分流）+ 晋升双信号 | 无问答层（P2.5 不存在）；无 wiki_query_log；晋升随 P3 E9 |

注：openwiki（上游 langchain-ai 仓库）是设计借鉴来源，**不是**平台 Wiki 交付物。

### 4.3 规划类文档中的未落地项

| 来源 | 未落地项 | 详情 |
|---|---|---|
| CR-F 排除项 §1 / 优先级清单 §1.1 | **CR-H Pipeline Runner 全量编排** | 全平台最大已识别缺口；前置已就位（162 迁移建表、CR-F UI 消费面、P1 审批链路）；量级约 6–8 人日；**无在途 CR** |
| CR-F 排除项 §2 / 优先级清单 §2.1 | **审批周边**：待审批中心（计数徽标 + 聚合列表页）+ 审批角色策略配置 UI | 无后端聚合端点、无前端入口；`approvals/pending` 仅服务 daemon 轮询，无人类聚合视图 |
| 优先级清单 §2.2 | 部署前独立验收关口（8 项真机补验） | 行为项非功能 CR：daemon 真跑、双浏览器 WS、跨用户 @提及、web+Electron、commit-scan 真实驳回等，均未执行 |
| 优先级清单 §3 | 上游回馈与工具链收尾 6 项 | 上游 PR、mdt_ 单轨化、Skill 安装器化、TaskExecutionCard 门禁指示条、工具摘要聚合查询、Traecli/Qoder 根因诊断——均未做 |

---

## 5. 相对上次盘点（CR 台账版）的变化

| 当时结论 | 本次（代码实证） |
|---|---|
| P0/P1/P2 主体已实现 | **一致**：代码可定位到全部对应实现（迁移/端点/组件），工作区运行态（outbox 244 事件、audit.log、specs v0.20.5、cr-guard CI）交叉佐证 |
| P3 未落地（编号 013～017 已撤回） | **一致**：代码零落地，且无任何 P3 相关迁移/API/路由；`wiki/` 目录不存在。2026-08-19 重切为四个 CR（A 0.21 / B 0.22 / C 0.23 / D 0.24），待注册 |
| Wiki 未立项 | **一致**：代码零落地 |
| Pipeline Runner（CR-H）未注册 | **一致**：表已建、编排器代码不存在——实证了"最大缺口"论断 |

---

## 6. 结论

按实际代码实证，`docs/product/` 已闭环的是：**P0 数据模型、P1 crctl 治理接入（D1–D7 全部）、P2 三模式聊天窗口（含 DC、合并转发、ChatInput 解耦）**——与 CR 台账（CR-001～012 归档）完全一致，文档"已实现"标注均可信。

未落地且当前**零在途 CR** 的产品主线（按优先级）：

1. **Pipeline Runner（CR-H / P1-F2）** — 卡住总 PRD M1/A2；两表已在库、UI 消费面已备齐，只缺编排器（约 6–8 人日），建议下一件产品 CR。
2. **P3 组织智能** — 代码零落地，编号 013～017 已作废，需重新注册。
3. **Wiki 子系统 + P2.5 runner 轻量档** — 从未立项（按《缺口清单-最终版》`:202` 仍为条件触发候选）。~~P3 知识晋升依赖 Wiki~~ → **反向了**：知识晋升自 2026-08-19 整节归 Wiki（W5），P3 不再依赖 Wiki；且 W5 与两个 LLM 巡检同等待遇（均需 daemon 在线率的真实数据）。
4. **审批周边 / A2A / IM 补齐（TG/Discord/QQ）/ 技能选择器** — 量级不等的周边缺口，均未注册。

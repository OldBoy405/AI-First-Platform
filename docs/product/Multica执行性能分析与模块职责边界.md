# Multica 执行性能分析与模块职责边界

> 状态：分析收敛
> 版本：v0.3
> 更新日期：2026-08-26
> 分析对象：CR-2026-051（Multica 环境全流程）对照 Qoder 环境同类 CR（CR-2026-046 / 050）
> 证据来源：`~/.multica/daemon.log`、`~/.multica/pi-sessions/*.jsonl`、`.crctl/audit.log + outbox/`、`change-requests/CR-2026-051/`、Multica live API

## 1. 背景与结论

CR-2026-051 全部在 Multica 平台执行，墙钟 23.5h；Qoder 环境同类 CR（相同 crctl 管线、相同 tools 包）为 2~5h。拆解后发现：

| 组成 | 时长 | 占比 |
|---|---|---|
| 纯 agent 执行 | ~6.3h | 27% |
| 人工审批等待 | ~11.2h | 48% |
| 轮次调度与上下文重建损耗 | ~6h | 25% |

**结论一句话**：慢不在工具链（merge/writeback/archive 实测 6 分钟跑完），而在协作结构与审批链路。daemon 无性能缺陷；crctl 状态机无阻塞。修复方向是平台侧配置与调度策略，不是重写 tools 仓。

## 2. 整体架构：两条执行路径

### 2.1 Qoder 路径（基线）

单 agent 连续会话直跑全管线：上下文全程保留，Skill 提示词注入，人工审批在同一会话一句话完成。典型工具调用 500~800 次/CR。

### 2.2 Multica 路径（实测形态）

```
用户 issue → delivery-agent(leader, 评论@提及) → 执行 agent 新沙箱新会话
    ↑                                                    │
    └────────────── 回复评论（回传结果）──────────────────┘
```

每个 turn 的固定开销（转录实证）：

1. 新沙箱 + 新模型会话（`resume_session=false`，转录明示 "provider session could not be restored"）；
2. 强制 `multica issue get` + `comment list` 重建上下文；
3. 重跑 `crctl status` / `crctl next` 重建状态认知。

### 2.3 差异总表

| 维度 | Multica | Qoder |
|---|---|---|
| 会话连续性 | 每 turn 全新会话 | 单会话连续 |
| 协作模型 | hub-and-spoke 评论中继，38 turns | 单 agent 直跑 |
| 工具面 | 仅 bash/read/write/edit | 结构化工具 + Skill 注入 |
| skills | 开发期未导入（已事后补齐） | 提示词直接注入 |
| 模型 | 混用 deepseek-v4-flash（leader/部分 dev）与 gpt-5.6-sol | 单一强模型 |
| crctl 调用 | 699 次 | 50~80 次 |
| 人工审批 | 评论内请求 → 人类去终端执行，异步易跨夜 | 同会话即时 |

## 3. 关键实测数据

### 3.1 总量

- 38 个任务 / 48 个会话转录 / 2782 次工具调用（bash 2007、read 566、edit 106、write 103）
- 协调类调用：`issue get` 53 + `comment list` 136 + `comment add` 60 + `squad` 24
- 模型分布：12 turn 用 gpt-5.6-sol（评审/重型），26 turn 用 deepseek（flash 为主，含 leader 全部 turn）

### 3.2 阶段耗时（CR-2026-051 实测时间线）

| 阶段 | 耗时 | 说明 |
|---|---|---|
| 注册 → PRD → 需求评审 | ~1.7h | 2 轮评审 |
| 技术设计 | ~2h | 2 次评审循环（1 block 返工） |
| 开发计划 | ~13h | 3 次评审循环、2 block，一次 `route=upstream` 触发技术设计返工 + 重审批 |
| └ 其中人工审批 | **11.2h** | 00:55→10:35 跨夜 9h40m（技术设计重批）+ 1h17m（dev-start）+ 15min（code） |
| 实施（8 TASK） | 1.5h | 一次跑完，不慢 |
| 测试报告 | ~52min | 3 次迭代 |
| 代码评审 | ~30min | 2 次循环（1 block + 修复） |
| 合并 / 回写 / 归档 | 6min | 工具链本身最快的一环 |

### 3.3 daemon 与 crctl 侧异常记录

| 异常 | 证据 | 影响 |
|---|---|---|
| 任务取消 | `328d8eab` 20m50s（空 issue 触发，6 工具后废弃） | 浪费 ~21min |
| 任务失败 | `22f82eab` 24m11s（88 工具） | 浪费 ~24min |
| outbox 事件无消费者 | 主工作区 `.crctl/outbox` 累积 460 个事件（8-01 起）——daemon cr-events 采集器未启用（`MULTICA_CR_WORKSPACES` 未设置，daemon.log 零采集活动）；其中 `audit-drift` 反复 EMIT_FAILED 是 crctl dedup 缺陷（`comparable()` 含 `payload.detected_at`，同一漂移再观测必冲突，与"待采集期间只留一份"语义矛盾） | 事件滞留 + 每次重观测报错 |
| 沙箱目录 | 非缺陷：gc 已按 `local_directory` 保守策略把 19 个沙箱回收为 0~0.2MB 元数据壳（workdir 内容已删）；gc 日志 `status=in_progress` 是 issue 状态非任务未 finalize | 无 |
| 心跳告警 | 仅 1 条 WRN（localhost:8080 短暂不可达） | 无影响 |

## 4. 根本原因（三层）

1. **协作结构**：hub-and-spoke 中继把每次评审放大为 3~4 个 turn；每 turn 上下文重建税叠加成 ~6h 损耗，并导致评审 block 后修复链更长（设计/计划/代码共 8 轮返工 vs Qoder 典型 1~2 轮）。
2. **审批链路**：审批请求停留在评论里，等人类去终端跑 `crctl approve`。跨夜等待占全部墙钟 48%，是最大单项损失。
3. **能力缺口（历史实测）**：开发期 skill 未导入（每 turn 从磁盘重读 SKILL.md）、leader 跑在最弱模型上、delivery-agent 角色错配（tools 包定义它是写回执行者，却被平台配置为 squad 编排者）。这些均属于平台配置问题，已于 2026-08-26 补齐或替换，见 §7.2。

## 5. 模块职责边界（逻辑架构）

若需修改 tools 仓，各模块必须遵守以下边界；不遵守的改动视为越界，优先在平台侧解决：

| 模块 | 应该拥有 | 不应该拥有 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 复制 Skill 完整算法、手写账本操作 |
| Skill | 业务判断、编排步骤、输入输出和失败语义 | 手写原子账本逻辑、重复实现 crctl |
| crctl | 状态、门禁、CAS、受控账本写入、审计、原子提交 | 业务设计判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性转换 | 状态推进、人工审批 |
| README | 人读流程总览 | 另一份可执行细节事实源 |

判定准则：**评审/路由/编排在 Agent+Skill 层，状态与账本只在 crctl 层，确定性转换在版本化脚本层。** Multica 平台侧的 squad 调度属于 Agent 层的"路由"，落点应是平台配置，不应下沉进 tools 仓。

## 6. 已经解决的基础设施（复用，不重建）

以下能力已存在且验证可用，本次优化**禁止**在其旁边再造一套：

| 能力 | 载体 | 状态 |
|---|---|---|
| CR 状态机 + 门禁 + CAS + 审计 + 原子提交 | `../tools/skills/shared/crctl/`（含 `.crctl/transactions`、outbox、audit.log） | 已解决，CR-2026-051 全程正常 |
| 确定性转换（writeback baseline/tasks/traceability） | `writeback-prd-sdd.mjs` 等版本化脚本 | 已解决，回写 3 分钟完成 |
| skills 导入与 agent 绑定 | Multica `/api/skills/import` + `PUT /api/agents/{id}/skills` | 已补齐（56 skill、9 agent、矩阵对齐） |
| 审批提醒触达 | 飞书审批提醒卡片（CR-2026-051 交付物） | 已交付，直接复用 |

## 7. 本次应复用的最小改造（按收益排序）

改造原则：**全部优先落在平台配置层，不进 tools 仓**；只有第 5 项触及 tools 仓且是一次小修。

| # | 改造 | 落点 | 预期收益 | tools 仓影响 |
|---|---|---|---|---|
| 1 | 审批即时化：把 CR-2026-051 的飞书卡片作为审批提醒通道（审批请求触发卡片推送到人） | Multica 平台 + 已交付卡片能力 | 消掉 ~11.2h 等待，即 48% 墙钟 | 无 |
| 2 | 使用专用 `cr-coordinator-agent` 担任 `CR 协调小组` leader；只负责路由、委派、门禁提示与结果汇总 | Multica Agent/Squad 配置 | 消除 delivery-agent 角色错配，降低中继误判 | 无 |
| 3 | 强模型策略：leader、评审与编码 turn 使用强模型；flash 只配纯中继或窄职责 turn | 平台模型配置 | 减少弱模型首稿导致的返工循环 | 无 |
| 4 | 直连互评：dev-agent 与 quality-reviewer-agent 评论互 @，leader 只在 gate、blocker、职责冲突或阶段完成时介入 | 平台 Agent/Squad instructions | 每次评审 3~4 turn 降为 2 turn | 无 |
| 5 | outbox 分开处理：① crctl dedup 缺陷另建 tools CR；② 当前 outbox 已为空，设置 `MULTICA_CR_WORKSPACES` 并启用 daemon cr-events collector | ① `../tools/` crctl 小修；② 平台 daemon 配置 | 保持事件持续采集并消除重复报错根因 | ① 需 CR；② 无 |
| 6 | 复用现有同 issue `PriorSessionID`/Pi session 文件续接能力；不新增 resume 配置层 | Multica 已有能力 | 后续同 issue turn 减少上下文重建；以实际任务转录验收 | 无 |

专用 leader 仅是 Multica workspace 内的配置实体，不在 tools 仓新增 Agent 定义，也不改变 `agent-skill-matrix.yml`。它绑定 `cr-show`、`cr-query`、`cr-dashboard` 三个只读 Skill，不拥有写入型 Pipeline/Skill、状态机或账本能力。

### 7.1 审批后自动推进：复用 grant ACK 唤醒现有 Agent

目标语义：人工审批完成后，系统自动恢复同一个 CR，持续推进到**下一个人工审批点或明确阻塞点**；不是只执行一个节点，也不是越过后续门禁直接归档。

#### 当前已有能力与真实缺口

审批链路的基础设施已经存在：飞书卡片只负责提醒并打开 Multica 审批页；Multica 生成签名 grant；daemon 将 grant 写入目标 worktree 的 `.crctl/grants/` 后调用 ACK；`crctl` 继续负责授权消费、门禁、状态推进和审计。自动推进的触发点应选在**grant 已可靠写入 worktree 后的 ACK**，而不是飞书卡片回调。

当前 ACK 实现先把 `approval_record.delivered_at` 写入数据库，再调用无错误返回值的 `onGrantAck(workspaceID, crID)`；回调失败仍返回 HTTP 200，daemon 不会再次投递该记录。现有 Architecture Runner 默认关闭，而且只覆盖已纳入 Runner 的 `architecture-design` 固定切片，不能满足需求、架构、开发启动、代码四类审批的统一续跑。因此，本节是**需要单独 Multica CR 的目标方案**，尚未随 §7.2 的配置改造落地。

#### 单一路径最小方案

一个 Multica CR 覆盖四类审批，并统一走“ACK 后唤醒现有 `cr-coordinator-agent`”路径；Architecture Runner 保持关闭，不与通用路径并行。通过与驳回都触发续跑：通过向前推进，驳回进入既有修订/reviewLoop，均持续到下一个人工审批点或明确 blocker。

最小可靠性约束：

- 使用已有 pgx/sqlc 原生事务，把“幂等创建续跑任务 + 更新 `approval_record.delivered_at`”作为一个原子提交；不新增事务框架或 outbox；
- 复用 `agent_task_queue.trigger_evidence_kind/ref_id`，以 `kind=approval_continuation`、`ref_id=approval_record.id` 建窄范围唯一约束，避免同一审批重复唤醒；
- ACK 回调数据补齐审批记录 ID、stage、decision，并允许错误返回；入队失败时 ACK 失败，daemon 按现有 15 秒循环重试；
- 若同一 CR 已有运行任务，最多保留一个后继任务，不向运行中的沙箱注入新事件；
- 找不到现有 CR leader 时不回退到任意 Agent，保持未 ACK 并记录明确错误，等待配置修复；
- 只处理上线后的新 ACK，不开发历史审批回填；
- 唤醒任务不在 Multica 中维护“状态 → 下一 Skill”映射，不直接写账本，也不替代 `approve-*` Skill；下一步由 Agent 依据 `crctl status` / `crctl next` 路由；
- 续跑状态复用现有任务、issue 评论与收件箱展示，不给审批记录增加第二套执行状态机。

#### 职责与改动范围

| 模块 | 本方案中的职责 |
|---|---|
| Multica | 接收审批、投递签名 grant、在 ACK 后幂等唤醒一个已有 CR 任务 |
| Agent | 判断当前职责，依据 `crctl status` / `crctl next` 选择 Pipeline/Skill |
| Pipeline | 执行既有节点顺序、输入传递、reviewLoop、失败中止 |
| Skill | 消费业务输入，执行已有 `approve-*` 及后续业务步骤 |
| crctl | 校验授权、门禁、CAS、状态推进、受控账本写入和审计 |

预期只修改 Multica 的 ACK 服务、任务入队适配、数据库唯一索引与测试；飞书卡片、tools 状态机、Pipeline、Skill 和 crctl 原则上不改。禁止复制审批状态、扩建全阶段 Runner、增加通用工作流引擎或 IM 专用状态机。

### 7.2 已落地的平台配置（2026-08-26）

| 项目 | 落地结果 |
|---|---|
| 专用 leader | 新建 `cr-coordinator-agent`：Pi runtime，`openai/gpt-5.6-sol`，thinking=`high`，并发 1，workspace 可见 |
| 最小权限 | 仅绑定 `cr-show`、`cr-query`、`cr-dashboard` 三个只读 Skill |
| Squad 路由 | `CR 协调小组.leader_id` 已切换到专用 leader；delivery-agent 保留为普通回写成员 |
| 直连互评 | Squad、dev-agent、quality-reviewer-agent instructions 已允许 reviewLoop 内直接互 @；leader 仅在 gate/blocker 等边界介入 |
| crctl 调用纪律 | requirement-writer、dev-agent、quality-reviewer-agent、delivery-agent 与新 leader 均约束为每 turn 最多各读一次 status/next |
| 强模型 | leader 与 quality-reviewer-agent 使用 gpt-5.6-sol；requirement-writer/dev-agent 使用 deepseek-v4-pro；flash 保留给窄职责 Agent |
| cr-events | 当前 `.crctl/outbox` 为空；用户级 `MULTICA_CR_WORKSPACES` 已指向本工作区，daemon 已重启，日志确认 collector 以 15 秒周期启动 |
| Architecture Runner | 保持默认关闭，避免与未来统一审批续跑路径形成双重触发 |

SDD/plan 评审质量优化是独立问题，详见 [`SDD评审前移校验方案.md`](./SDD评审前移校验方案.md)。该方案遵循“两层各审自己新增的事实”：SDD 层审 AC 可达性和自身引用事实，plan 层审 TASK 新造事实、责任边界与假绿风险。其具体 Skill/Pipeline 改动不在本文复制，避免形成第二份可执行事实源；它不新增小组、leader Agent、状态、账本或事务框架。

## 8. pi runtime 工具面整改（保留 pi 的前提）

### 8.1 Skill 注入：平台机制已存在，缺的只是配置

Multica server 在任务启动前会把 agent 绑定的 skill 物化进任务沙箱的 provider 原生目录（`execenv/context.go` 的 `writeSkillFiles(skillsDir, ctx.AgentSkills)`；pi → `.pi/skills`）。CR-2026-051 开发期绑定为空，故目录里只有 13 个平台内置 skill。

- **整改：无代码改动。** 56 个 tools skill 已于 2026-08-26 绑定到 9 个 agent，下一任务启动时自动物化；验证方式 = 跑任意任务后检查沙箱 `.pi/skills` 是否出现 `requirement-register` 等。
- 可选第二通道：runtime-level 本地 skill 导入（daemon 的 `local skills` 流程，让 pi 原生列出这些 skill）。仅当 agent 依赖运行时 skill 列表而非 workdir 目录时才启用——先验证任务级物化，够用则不启用。

### 8.2 结构化工具：不补

- bash/read/write/edit 对 CR 工作足够。tools 包的结构化表面本来就是 crctl CLI（状态/门禁/账本），经 bash 调用正是其设计用法。
- pi 任务启动支持 `mcp_config` 开关，但 tools 包没有 MCP server，为它新建一个等于再造一层基础设施——跳过。
- 真正要治的是工具使用姿势：699 次 crctl 里大量是同 turn 内重复 status/next 验证。在 agent 指令中加一条纪律「turn 开始跑一次 `crctl status` + `crctl next`，本 turn 内信任结果，不重复验证」——平台 prompt 配置级，零代码。

### 8.3 上下文重建税

136 次 `comment list` 是每 turn 固定税。已通过专用 leader 与 instructions 限制重复读取；同 issue 会话续接复用现有 `PriorSessionID`/Pi session 文件能力，不新增配置。是否在真实任务中稳定命中 resume，以下一个同 issue 多 turn 的任务转录为验收证据。

## 9. 明确不做的事

- 不在 tools 仓新增"Multica 编排层"或任何平台适配抽象（平台差异由平台配置吸收）；
- 不在 tools 仓新增 squad/leader Agent；Multica workspace 只保留一个专用 `cr-coordinator-agent`，不再增加第二套协调角色；
- 不把状态机、门禁、账本逻辑复制进 Multica 或 Agent 提示词（唯一事实源仍是 `../tools/dir-graph.yaml` 与 crctl）；
- 不为审批提醒新建队列/outbox/重试框架；未来审批续跑只复用现有任务队列、daemon ACK 重试与 pgx/sqlc 原生事务；
- 不修改 crctl 的 gate 语义与状态转移（状态机改动是独立 CR 的范畴）；
- 不为 pi 建 MCP server 或结构化工具层（§8.2）。

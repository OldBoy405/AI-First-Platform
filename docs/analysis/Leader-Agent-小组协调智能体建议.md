# Leader Agent（小组协调智能体）设计建议

> 文档性质：架构评审/方案讨论，是后续 CR 的 PRD/SDD 依据，不是实施授权，不替代 CR 审批。
> 实证基线（2026-08-24）：multica `93aa7c5bd` + 本机两个接线修复（`1bed8e0b1`、`570bbfbce`，views exports / MarketPage）；tools `c4b10d5`（merge CR-2026-050）+ `2f71825`（ARCHITECTURE 计数订正）。
> 平台实例状态：后端 `localhost:8080`、daemon 运行中（`~/.multica/config.json` 指向本地）、workspace `ai-first`（`30641781-762e-401b-b541-f33387fe2294`）、9 个 tools agents 已导入并绑定 Claude runtime（`da5e9bf1`）、controlled-shell 已启用（`MULTICA_CONTROLLED_SHELL_RULES`）。

## 0. 执行摘要

目标：在 multica 上创建一个"主管智能体"，作为小组（squad）的 Leader Agent，协调 tools 工具包的各智能体完成 CR 生命周期全流程。

核心结论：**Leader 应定位为"分诊员 + 人机接口"，而不是"流程引擎"**。CR 生命周期的流程编排已经是确定性的（Pipeline JSON + crctl 状态机 + 服务端 Runner），让 LLM 重新实现"下一步跑哪个节点"只会降低可验证性。Leader 的真实价值在确定性引擎覆盖不到的地方：入口路由、跨 CR 调度、异常升级、审批证据打包、跨仓一致性。

## 1. 不要重复造轮子：平台/tools 已有的三个原语

| 原语 | 现状 | 含义 |
|---|---|---|
| `server/internal/governance/runner.go`（Runner Core，CR-2026-045） | 服务端幂等 Reconcile + PostgreSQL advisory lock 串行化 | 源码注释明写 **"intentionally not a generic workflow engine"**：只驱动固定的 architecture-design 切片，CR 状态/审批校验/Git 副作用一律留给 Skills + crctl。部署开关 `ArchitectureRunnerEnabled` 默认关 |
| `squad.leader_id` | multica 原生 squad 带 leader，且 leader 是 Agent；`LockSquadForAutopilotAssignment` 注释明确 "locks the same leader Agent"，与 Autopilot 调度联动 | 平台已有"编队 + leader agent + 自动调度"的骨架 |
| `system-orchestrator`（tools 权限矩阵 actor） | owns `feature-writeback` + `resume-cr` 两条 pipeline | 方法论层已有一个编排器 actor，但**无独立 agent 文件**（`tools/agents/*.md` 仅 9 个，均已导入平台），是权限矩阵里的虚拟 actor，不能直接拿来当平台 agent 记录 |

## 2. Leader 的真实价值（确定性引擎覆盖不到的地方）

1. **入口路由**：一句话需求 → 判断是新 CR / resume / 只是查询，选对 pipeline（现状靠人记 slash command）。
2. **跨 CR 调度分诊**：backlog 优先级、并行 CR 的 worktree/仓库冲突、合并顺序——crctl 只管**单个 CR 内部**状态机。
3. **异常升级**：reviewLoop 多次不过时，把 blocker 归类、汇总证据、升级给人，而不是死循环。
4. **审批前证据打包**：把 diff/测试报告/evidence 压成人类 3 分钟能看完的摘要，降低四个人工审批节点的成本。
5. **跨仓一致性**：docs/multica/tools 三仓 worktree 状态核对、`STATUS_DIVERGED` 告警处置。

## 3. 四条硬约束（违反必返工）

1. **不能写状态**：crctl 独占 `_backlog.yml` / `cr.md` / `approval.yml` 的写入；Leader 只能调 crctl。
2. **不能代签审批**：`RequireHumanActor` 拒绝 agent task_token；签名审批需人类私钥。Agent 代签 = 拆掉整个治理前提。
3. **必须进权限矩阵**：新建 actor 需在 `agent-skill-matrix.yml` 登记（owns 唯一性 + forbidden 明确列出 `advance` / `approve` / `git` 写操作）；tools pre-commit `check-skill-matrix` 会校验一致性。
4. **决策依据只能来自 `crctl status` / `crctl next` 与 gate 投影**：不维护"自认为的进度"（AGENTS.md 纪律 #9：主工作区 cr.md 可能是陈旧快照，以 worktree 为准）。

## 4. 落地路径（从最省开始）

- **阶段 1（零代码，已执行）**：不新建 agent。用 squad + `leader_id` 指向现有 agent，验证"编队 + leader + Autopilot"机制在平台上跑得通。
- **阶段 2（需开 tools CR）**：确认阶段 1 不够用后，在 `tools/agents/` 写 Leader 提示词，矩阵给**只读 + 路由**边界：可调 `crctl status/next/gate`（只读）+ 各 pipeline 入口 Skill；forbidden 明确禁 `advance/approve/git`。
- **阶段 3**：调度接平台原生 **Autopilot**（scheduled/triggered），不自建轮询循环。

阶段 2 起属于对 tools 仓版本化方法论包的变更，必须走 CR（参照 CR-2026-050 的纯 tools CR 流程）。

## 5. 当前限制（本次会话实测）

- **`agent-import.mjs` 的 `permission.bash` 字段平台不持久化**（脚本会打 `fieldsReadNotPersisted` 日志）。Leader 的权限边界**不能靠 frontmatter 声明兜底**，只能靠 controlled-shell 白名单 + 提示词矩阵约束 + crctl 自身门禁三层。设计时按"提示词约束是软的、crctl 门禁是硬的"来假设。
- 状态推进一律走 crctl；人工审批只能人在交互式终端 `crctl approve`（或平台签名审批）。

## 6. 阶段 1 执行记录（2026-08-24）

| 项 | 值 |
|---|---|
| Squad | `CR 协调小组`（id `364fcb42-b073-41be-9d21-f73acabdc7db`，workspace `ai-first`） |
| Leader | `delivery-agent`（`cf0d9dac-93c7-4d51-bfd0-a86365b0142a`）——占位，其 `consumers` 含 `orchestrator` + `feature-writeback.pipeline`，语义最贴近协调者 |
| 成员 | 9 个 tools agents（1 leader + 8 member）+ 1 人类成员（`403562935@qq.com`），合计 10 |
| 说明 | `system-orchestrator` 无独立 agent 文件，平台无对应记录，不能直接做 leader |

**踩坑记录**：用 `curl -d` 直接传中文时，git-bash 在 Windows 下把 UTF-8 参数转码错误，squad 名称/描述存成乱码；改用 UTF-8 文件 + `curl --data-binary @file` 重新 PUT 更正。平台 API 传中文参数一律走文件方式。

## 7. 待验证 / 后续触发

- 给 `CR 协调小组` 挂一个 Autopilot 触发任务，验证 leader 的调度语义是否符合预期。
- 阶段 1 验证通过且确有协调需求后，开 tools CR 落地阶段 2（Leader 提示词 + 矩阵条目）。

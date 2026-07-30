---
id: CR-2026-001-plan
type: PLAN
cr-ref: CR-2026-001
sdd-ref: "change-requests/CR-2026-001/sdd.md"
target-version: "0.10"
status: draft
created: "2026-07-30T22:43:34+08:00"
updated: "2026-07-30T22:43:34+08:00"
---

# CR-2026-001 开发计划 — M0 地基

> 输入：`sdd.md` v0.1.1（四组件：selfhost-compose / agent-frontmatter-adapter / issue-dispatch-smoke / tools-consistency-ci）。
> 本计划把 SDD 的组件切成可 1–3 天完成的 TASK，并显式落实 PRD §8 与 SDD 评审要求的两条依赖纪律：FR-1 先于 FR-2/FR-3；"查证先于编码"。

## 1. 交付里程碑

| 阶段 | 内容 | 估算 |
|---|---|---|
| 阶段一 · fork 与起服务 | fork Multica、剥离云端专属、内网 Compose 起全栈（FR-1） | 3–5 天 |
| 阶段二 · Agent 注册 | 查证 agent create 契约 → 写 frontmatter 适配器 → 注册 9 Agent（FR-2） | 2–4 天 |
| 阶段三 · 冒烟与 CI | 派 Issue 端到端冒烟（FR-3）；一致性 CI 接入（FR-4，可与阶段一/二并行） | 1–2 天 |

总估算：6–11 天（单人串行口径；FR-4 并行可压缩 1 天）。

## 2. 任务依赖图

```
TASK-01 fork + 剥离 + 起全栈 (FR-1)
   │
   ▼
TASK-02 查证 multica agent create 契约（前置查证任务，SDD §3 硬性约定）
   │
   ▼
TASK-03 agent-frontmatter-adapter 实现 + 注册 9 Agent (FR-2)
   │
   ▼
TASK-04 issue-dispatch-smoke 端到端冒烟 (FR-3)

TASK-05 tools-consistency-ci (FR-4) —— 无依赖，可随时并行
```

依赖纪律来源：PRD §8（FR-1 是 FR-2/FR-3 的前置）；SDD §3（TASK-02 必须先于 TASK-03，"先查证、后编码"）。

## 3. 资源与分工

单人（Ray 兼三角色）。无并行人力，按依赖图串行执行，TASK-05 可穿插在任意等待间隙做。

## 4. 风险与回滚策略

| 风险 | 应对/回滚 |
|---|---|
| fork 后 `make selfhost` 在本机环境跑不通（依赖版本/端口冲突） | 逐服务排查；实在不通则降级为逐进程手工起（后端+前端+PG），FR-1 的"两命令起全栈"验收目标不变但允许先记录环境差异 |
| `multica agent create` 不支持脚本化/批量调用 | SDD §3 已备选 `POST /api/agents`；TASK-02 查证阶段即可确认，不会走到编码一半才发现 |
| tools 的 8 项内部不一致（总 PRD 已知问题）阻塞 Agent 导入 | TASK-03 遇到时逐项修复并记录；已有 check-skill-matrix.mjs 可先跑一遍预检 |
| daemon 领取 Issue 依赖本机 Claude Code CLI 环境 | TASK-04 前确认 `claude` 命令可用；不可用则冒烟降级为观察 claim 行为（领取成功）+ 明确记录执行段未验证 |
| 回滚 | M0 全部工作在 fork 仓库与配置层，不动上游、不动本仓库事实源；放弃即删 fork 分支，无残留 |

## 5. 验收与发布策略

- 验收即 PRD §5 的 AC-1~AC-4，逐条对 TASK 的完成标志核销。
- M0 无对外发布动作；"发布"= 在本 CR 的 test-report.md 里记录四条 AC 的验证证据，走 review-code → approve-code → writeback 归档。
- 无 feature flag 需求（没有存量用户）。

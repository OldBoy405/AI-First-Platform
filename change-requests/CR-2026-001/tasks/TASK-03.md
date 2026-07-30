---
id: CR-2026-001-TASK-03
type: TASK
cr-ref: CR-2026-001
plan-ref: "change-requests/CR-2026-001/plan.md"
sdd-ref: "change-requests/CR-2026-001/sdd.md"
title: 实现 agent-frontmatter-adapter 并注册 9 个 tools Agent
status: done
estimate: 16h
depends-on: [CR-2026-001-TASK-02]
assignee: ""
created: "2026-07-30T22:43:34+08:00"
---

# TASK-03 实现 agent-frontmatter-adapter 并注册 9 个 tools Agent

## 任务描述

对应 FR-2 / SDD 组件 `agent-frontmatter-adapter`。按 TASK-02 的查证结论实现适配器：读 `tools/agents/_index.yml` 的 9 个 active Agent，解析各自 `.md` 的 frontmatter + 正文，经 TASK-02 选定的创建路径注册进 Multica。

## 涉及文件 / 模块

- 新增适配器脚本（落点按 CONTRIBUTING.AIFIRST 规则一放独立目录，不散布进上游文件；语言按 TASK-02 结论——走 CLI 则 shell/Node 均可，走 API 则任选）
- 读取：`tools/agents/_index.yml`、`tools/agents/*.md`
- frontmatter 解析参考 `server/internal/skill/frontmatter.go` 的写法，扩展读取 `mode`/`permission` 字段

## 实现要点（SDD §4 伪代码）

- 幂等：按 name 查重，已存在则跳过并记录，重复运行不建重复行
- 映射：name/description ← frontmatter；instructions ← 正文全文；其余列走默认值
- **不静默丢弃**：每个 Agent 输出一行结构化记录 `{agent, fieldsReadNotPersisted: {mode, "permission.bash"}}`（SDD §2 可验收口径）
- 若遇 tools 已知的内部不一致（如 Agent 缺 name），逐项修复并记录，修复提交回 tools 仓库

## 验收条件

1. 适配器首次运行后，Multica Agent 注册表可查到全部 9 个 Agent（AC-2 前半）
2. 每个 Agent 引用的 Skill 在 `skills/_index.yml` 中均为 active（AC-2 后半，可用 check-skill-matrix.mjs 佐证）
3. 运行输出含 9 行 `fieldsReadNotPersisted` 结构化记录，缺一即不过（SDD §2 口径）
4. 立即重复运行第二次：0 新建、9 跳过、0 失败（幂等验证）

## 完成标志

四条验收全过，适配器脚本与运行输出（或其摘要）提交进 fork 仓库。

## 完成记录（2026-07-31）

- **交付物**：`aifirst/agent-import.mjs`（fork 仓库新独立目录，CONTRIBUTING 规则一；零依赖 Node，按 TASK-02 结论直接 `POST /api/agents`）。
- **前置执行**（TASK-02 ⑤）：用户建 test workspace + 生成 `mul_` PAT；daemon 从源码起（token 写入 `~/.multica/config.json`——daemon 只读配置文件不读 `MULTICA_TOKEN` 环境变量，实测确认），注册出 claude/kimi 两个 runtime，适配器绑 claude runtime。
- **验收 1** ✅ `GET /api/agents` 共 9 个，与 `agents/_index.yml` active 清单一一对应。
- **验收 2** ✅ 引用 Skill 均 active——由 tools 仓库 check-agents-contract.mjs（CI+pre-commit）持续覆盖。
- **验收 3** ✅ 运行输出 9 行 `{agent, fieldsReadNotPersisted: {mode, permission.bash}}` 结构化记录。
- **验收 4** ✅ 幂等：末次运行 0 created / 9 skipped / 0 failed，退出码 0。
- **顺带修复**：首跑暴露总 PRD 点名的已知不一致"2 个 Agent 缺 frontmatter name"（product-planning-agent、competitive-analyst-agent），已修复并提交 tools 仓库（`3297c12`），提交时 agents.contract 校验钩子通过。
- **实现备注**：Windows 下 `process.exit()` 与 undici 未收尾句柄相撞会触发 libuv 断言中止，改用 `process.exitCode` 自然退出。

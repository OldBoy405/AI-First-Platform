---
id: CR-2026-001-TASK-02
type: TASK
cr-ref: CR-2026-001
plan-ref: "change-requests/CR-2026-001/plan.md"
sdd-ref: "change-requests/CR-2026-001/sdd.md"
title: 查证 multica agent create 的参数面与校验规则（编码前置）
status: done
estimate: 4h
depends-on: [CR-2026-001-TASK-01]
assignee: ""
created: "2026-07-30T22:43:34+08:00"
---

# TASK-02 查证 multica agent create 的参数面与校验规则

## 任务描述

SDD §3 的硬性约定任务（评审建议落地）：在写适配器代码**之前**，确认 Agent 创建路径的完整契约。这是 TASK-03 的前置依赖，不得跳过或与 TASK-03 合并执行。

## 涉及文件 / 模块（只读，不改）

- `server/internal/service/builtin_skills/multica-creating-agents/SKILL.md`
- 同目录 `references/creating-agents-source-map.md`
- `server/pkg/db/queries/agent.sql`（CreateAgent 查询）
- 必要时对照 `server/pkg/db/generated/models.go` 的 `Agent` struct

## 实现要点

确认并记录：① `multica agent create` CLI 是否支持非交互/脚本化调用及其完整 flag 列表；② name/description/instructions 之外哪些字段必填、有何长度/枚举校验；③ 按 name 查重的现成途径（CLI 或 API）；④ CLI 不满足时 `POST /api/agents` 的请求体与鉴权要求（SDD 备选路径）。

## 验收条件

1. 产出一份查证结论（记入本 TASK 的完成说明或 worktree 内笔记文件）：明确"选 CLI 还是 API"及理由，列出将使用的完整参数
2. 结论中对 SDD §2 表格里"具体落点留到开发计划阶段再定"的 `permission.bash` 记录位置给出定论（用哪个字段/日志承载）

## 完成标志

查证结论落盘且 TASK-03 可直接按结论编码，不需要再回头翻源码。

## 查证结论（2026-07-31，来源：`multica-creating-agents/SKILL.md` + `references/creating-agents-source-map.md` + `router.go` 实读）

**① 选型：直接调 `POST /api/agents`，不装 CLI。** `multica agent create` 本质是拼 JSON body 发同一端点（`runAgentCreate`），本机未装 CLI（Windows 需另跑 install.ps1），适配器用零依赖 Node 脚本直接 POST 反而少一层。

**② 完整参数面**（`CreateAgentRequest`）：
- 必填：`name`（空 → 400）、`runtime_id`（空 → 400；必须能解析为本 workspace 的 runtime，否则 400 "invalid runtime_id"）
- 我们要填的：`description`（≤255 Unicode 码点，超限 400——tools 9 个 Agent 的中文描述均 ~40 字，安全）、`instructions`（无校验，daemon 领任务时读，发给 provider 的运行时行为契约——**这才是提示词，description 只是目录元数据不进提示词**）
- 全部不发、吃服务端默认值：`model`/`thinking_level`（空=runtime 默认）、`custom_args`→`[]`、`runtime_config`→`{}`、`custom_env`→`{}`、`visibility`→`private`、`max_concurrent_tasks`→`6`、`mcp_config` 不发

**③ 查重途径**：服务端对 `name` **无唯一性约束**（source-map 通篇无 unique 校验）——幂等必须由适配器自己做：先 `GET /api/agents` 列表、按 name 比对、命中即跳过。

**④ `permission.bash: deny` 落点定论**：**只进适配器运行日志**（`fieldsReadNotPersisted` 结构化行，SDD §2 口径）。否决 SDD 里"或塞 `custom_env`"的备选——查证发现 `custom_env` 是密钥语义字段（读取要走 owner/admin 专用 env 端点、审计留痕），拿它存文档性备注是滥用。真正的执行期强制等 P1 gitguard。

**⑤ 新发现的前置依赖（TASK-03/04 执行序）**：`runtime_id` 必须指向已存在的 runtime，而 runtime = 用户配对本机 daemon 后才产生（`GET /api/runtimes` 可列）。所以适配器运行前，用户必须先完成：注册账号 → 建 workspace → 配对本机 daemon。适配器凭据用 `mul_` PAT（Web UI 生成）经环境变量传入，不写死。

**⑥ 范围澄清**：创建 Agent **不会**绑定 Skill（绑定是独立的 `POST /api/agents/{id}/skills/add`）。AC-2 的 Skill 检查口径是 tools 侧 `_index.yml`（已由 check-agents-contract.mjs 覆盖），把 59 个 Skill 导入 Multica `skill` 表并绑定属于安装器工作（P0 映射表 §6），不在本 CR 的 M0 范围，TASK-03 不做、不装作做了。

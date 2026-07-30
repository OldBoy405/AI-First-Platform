---
id: CR-2026-001-prd
type: PRD
cr-ref: CR-2026-001
title: AI First 研发协同平台
target-version: "0.10"
owner: Ray
owner-role: requirement
status: draft
created: "2026-07-30T21:27:12+08:00"
updated: "2026-07-30T21:42:12+08:00"
version: v0.1.1
refs:
  upstream:
    - docs/product/AI-First平台-PRD.md
    - docs/product/P0-数据模型映射表.md
    - docs/product/P1-crctl接入设计.md
    - docs/product/P2-三模式聊天交互设计.md
    - docs/product/P3-组织智能设计.md
    - docs/product/Wiki子系统设计.md
  downstream: []
fr-list: [FR-1, FR-2, FR-3, FR-4]
---

# AI First 研发协同平台 — CR-2026-001 PRD

> 本 PRD 是 `docs/product/AI-First平台-PRD.md`（v1.2，下称"总 PRD"）在 CR 治理流程下的落地起点，不是对总 PRD 的重写。总 PRD 与 P0–P3、Wiki 子系统设计已经把完整方案讲清楚，本文档只做两件事：① 把总 PRD 的目标转成本 CR 可核查的 FR/AC；② 把"探路"这个决定写明白——为什么 target-version 0.10 只对应总 PRD 的 M0 阶段，而不是试图一次性吃下整个平台。

## 1. 概述

**问题陈述**：`docs/product/` 下已有总 PRD 与 P0–P3、Wiki 子系统设计等六份完整方案文档，但平台目前没有一行实现代码，也没有走过 CR 治理流程——设计和执行之间缺一座桥。

**解决方案摘要**：以 CR-2026-001 作为第一条真正跑通 `crctl` 全流程（注册 → PRD → 评审 → 审批 → 架构 → 编码 → 测试 → 代码评审 → 代码审批 → 回写归档）的变更，验证方法论包 + crctl + worktree 这套机制在这个仓库里确实可用。**本 CR 的可交付范围是总 PRD 里程碑 M0（地基）**：fork Multica、剥离云端专属能力、把 tools 的 9 Agent 注册为可用、验证"派 Issue → daemon 本机执行"闭环、tools 一致性 CI 校验通过。M1（治理核心）、M2（协作体验）、M3（组织智能）在总 PRD 里已经分阶段设计好，将在 M0 验收通过后，按§7"范围排除"里说明的方式拆成独立 CR，不在本 CR 里一次性展开。

## 2. 用户故事

- **US-1（技术负责人）**：作为技术负责人，我希望能在内网 Docker Compose 一次起全栈，以便验证 fork 后的 Multica 底座在自己的环境里可用。
- **US-2（全栈/方法论集成工程师）**：作为负责 tools 集成的工程师，我希望 9 个内置 Agent（product-planning-agent、requirement-writer、dev-agent 等）注册进平台后能被实际调度，以便后续 CR 流程有 Agent 可用而不是空壳。
- **US-3（技术负责人/QA）**：作为需要验证闭环的负责人，我希望能给某个 Agent 派一个 Issue，看它在 daemon 本机领取并跑完，以便确认"本地执行"这条主路径真的通。
- **US-4（全栈/方法论集成工程师）**：作为维护 tools 包一致性的工程师，我希望有一条 CI 检查能自动发现 Agent/Skill/Pipeline 之间的登记不一致，以便这类漂移不需要靠人工巡查。

## 3. 功能需求

| ID | 需求 | 来源 | 优先级 |
|---|---|---|---|
| FR-1 | 内网 Docker Compose（或等价本地编排）一次起全栈：fork 后的 Multica 后端 + 前端 + 依赖服务在本机跑通，且已剥离计费/云节点/多 workspace 注册等云端专属能力 | 总 PRD §5.1.2 步骤 1；P0-F1 | P0 |
| FR-2 | tools 的 9 个内置 Agent（`agents/*.md`）通过 frontmatter 适配器注册为 Multica 可用的 Agent，`{domain}/{skill-id}` 两级目录发现生效 | 总 PRD §5.1.2 步骤 2；P0-F2 | P0 |
| FR-3 | 给已注册的某个 Agent 派发一个 Issue，daemon 能在本机领取并执行完成：Issue 状态字段变为 `done`，且 daemon 返回的执行摘要中包含预先约定的结果标记（例如任务描述里指定的一段可核对文本，或进程退出码 0），不是仅凭"看起来跑完了"判断 | 总 PRD §5.1.4；P0-F3 | P0 |
| FR-4 | tools 包一致性校验接入 CI：`dir-graph.yaml#agents.contract` 的 4 条不变式（Agent 必须先有 `.md` 再登记 `_index.yml`、引用的 Skill 必须 active、Skill 必须同步到 `agent-skill-matrix.yml` 的 owns/can-call、Agent 不得绕过 Skill 直接写受控状态文件）跑通并在 CI 中体现为通过/失败 | 总 PRD §5.1.2 步骤 3；P0-F4 | P0 |

## 4. 非功能需求

- **隐私**：模型凭据与源码不出内网；开发者流量走本人订阅（总 PRD §8）。
- **安全**：本阶段暂不要求签名审批（M1 范围），但 Agent 执行必须走 controlled-shell/gitguard 白名单，不得拿到裸 shell。
- **可部署**：内网 Docker Compose（或等价方案）两条命令内起全栈；端口默认绑 `127.0.0.1`。
- **可维护**：fork 建立 upstream 镜像与双周同步流程；二次开发记录在 `CUSTOM.md` 台账，不散布进上游文件（呼应 `multica/CONTRIBUTING.AIFIRST.md` 规则一、规则二）。

## 5. 验收标准

| ID | 验收项 | 对应 FR |
|---|---|---|
| AC-1 | 内网执行 `make selfhost`（或等价命令）后，Multica 后端、前端、依赖服务全部起来且可访问；Stripe/计费相关路由已摘除，`mcn_` 云节点凭据为空时对应端点天然返回 401 | FR-1 |
| AC-2 | `agents/_index.yml` 中登记的 9 个 Agent 均可在 Multica 的 Agent 注册表里查到，且每个 Agent 引用的 Skill 均能在 `skills/_index.yml` 中找到且状态为 active | FR-2 |
| AC-3 | 对任一已注册 Agent 创建一条 Issue 并指派，daemon 在无人工干预下领取该 Issue、执行完成后 Issue 状态字段变为 `done`，且执行摘要中出现该 Issue 预先约定的结果标记（而非仅凭日志"看起来正常"判断） | FR-3 |
| AC-4 | CI 流水线中存在一致性校验步骤；故意制造一处不一致（例如给某 Skill 引用一个未登记的 owner）后触发 CI 失败；修复后 CI 恢复通过 | FR-4 |

## 6. 成功指标

- **上线后如何度量成功**：M0 阶段没有面向最终用户的量化指标，用二元验收判定——本 CR 的四条 AC 是否全部通过。真正的量化指标（AI 成熟度看板五维十指标）从 M3 阶段才开始有数据源，见总 PRD §5.4.2，不在本 CR 范围内。

## 7. 范围排除

- **P1（治理核心）、P2（协作体验）、P3（组织智能）不在本 CR 范围内**：这三个阶段在总 PRD §5.2–§5.4 已有完整设计（CR 事件同步、签名审批、Pipeline Runner、三模式聊天、Presenter、AI 成熟度看板等），但体量各自需要 4–8 周，硬塞进同一个 CR 会让需求评审门（review-requirement，检查完整性/可测试性/范围/对齐）无法给出有意义的通过判断。约定：M0 本 CR 验收通过并回写归档后，P1/P2/P3 每个阶段（或阶段内进一步拆分的子功能，如 Wiki 子系统、签名审批）各自注册独立 CR，`source` 字段指向对应的 P1/P2/P3/Wiki 设计文档路径。
- **不做本 CR 的一部分**：云端沙箱 SaaS、Token 计费、多组织跨租户、runner 完整档、TicNote 硬件联动、记忆系统具体实现——这些是总 PRD §13"明确不做清单"里平台级别的范围排除，本 CR 直接继承，不重复论证。
- **target-version 说明**：`0.10` 对应总 PRD 里程碑 M0（地基）交付内容，不是"整个平台 0.10 版"的意思；M1 及之后的实际版本号在对应 CR 注册时另行确定。

## 8. 依赖关系

- **FR 内部顺序依赖**：FR-2（Agent 注册）、FR-3（派 Issue 验证执行闭环）都要求 FR-1（fork 后的服务已起来）先完成——daemon 没起来就无法注册 Agent，更谈不上执行 Issue。拆 `write-dev-tasks` 任务时必须把这条顺序显式写进任务依赖关系，不能假设三者可并行开工。
- **对其他 CR 的依赖**：本 CR（CR-2026-001）是本仓库注册的第一个 CR，不依赖任何其他在途 CR。
- **被依赖关系**：本 CR 是 §7 提到的 P1/P2/P3 后续 CR 的前置——那几个 CR 注册时应在各自 `cr.md` 的 `source` 之外，明确写上"依赖 CR-2026-001 已归档"。

## 9. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-07-30 | v0.1.0 | Ray | 初始草稿，source = `docs/product/AI-First平台-PRD.md` |
| 2026-07-30 | v0.1.1 | Ray | 采纳需求评审的两条非阻塞建议：① FR-3/AC-3 补充具体判定信号（Issue 状态字段 + 约定结果标记），不再靠"看起来跑完了"判断；② 新增第 8 章"依赖关系"，显式写出 FR-1 对 FR-2/FR-3 的顺序依赖，以及本 CR 与后续 P1/P2/P3 CR 的前后依赖 |

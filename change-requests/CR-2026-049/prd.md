---
id: CR-2026-049-prd
type: PRD
cr-ref: CR-2026-049
title: P3 组织智能 CR-C：跨 CR 追溯与漂移检测（E4 追溯 + E5 漂移）
target-version: 0.23
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-20T19:35:00+08:00
updated: 2026-08-20T20:01:37+08:00
---

# PRD — P3 组织智能 CR-C：跨 CR 追溯与漂移检测

## 1. 概述

### 问题陈述

工程侧有两个问题没有读侧答案：

1. 「这个功能（FR）是谁、经哪个 CR、什么证据落地的」——P0 的 writeback-traceability 已把 `traceability.yml` 落进 git（baseline 权威），但查询只能翻文件；spec 详情页无法从一条 FR 一跳直达落地它的 merge commit、测试证据与评审记录。
2. 「基线和现实漂了没有」——本地执行模式下没人能从平台侧强制所有代码经 CR，绕过 CR 直接提交 trunk（bypass）目前完全不可见，且「从未漂移过」与「从未测过」在看板上无法区分。

### 解决方案摘要

设计主线不变：**P3 不新增 Agent/LLM 采集管道，只做已有治理事实的聚合与呈现，并新增服务端确定性前缀扫描**。CR-C 交付两个严格依赖的交付物（E4→E5 一条线）：

- **E4 — 跨 CR 追溯查询**：writeback-traceability 完成时，crctl outbox 发出 `trace` 事件。`cr_sync_event.event_kind` 当前没有 CHECK 约束，因此新增 `trace` 本身不需要枚举迁移；事件 payload 使用明确的 canonical JSON envelope，包含 `spec_id` 与完整追溯文档。查询直打 `cr_sync_event`，**不建 `spec_trace` 投影表**（§7 R-10）。spec 详情页 + 全局搜索接入：FR 演进时间线、一跳直达 merge commit / 测试证据 / 评审记录、按人反查经手 spec。
- **E5 — 漂移检测（只做服务端确定性扫描）**：服务端纯 Go 前缀扫描（每小时，`sys_cron`，不走 Agent / 不走 LLM）按 workspace 的 `dir-graph.yaml#repositories` 声明扫各自 trunk 新提交，前缀不在白名单计 `bypass-commit`（warn）、`wip:` 前缀计 `wip-on-trunk`（info）；白名单单一事实源 = 本仓 `dir-graph.yaml#repositories[].commit_prefixes`，经生成器（照抄 `governance/gen/generate-transitions.mjs` 模式）吐 Go 副本。新增 `drift_finding` 表（workspace/repository 维度、明确的 spec 可空语义、幂等唯一索引），drift 数量与解决时延进看板治理板块，finding 流列表页挂治理板块下钻。

为保证现有多 workspace 数据契约，E4 同时补齐 `cr_sync_event` 的 workspace 维度与唯一键：`trace` event_kind 的增加仍然是零 CHECK/枚举迁移，但 ledger 的 tenant-safe key 是本 CR 必须交付的兼容修正。该修正不新增 `spec_trace` 表，也不改变既有事件的业务语义。

持久化面：**1 张新表**（`drift_finding`）+ `cr_sync_event` 的 workspace/key 修正 + 1 个 event_kind（零 CHECK 迁移）+ `dir-graph.yaml` 声明扩展（`commit_prefixes`）。其余全部复用现成机制。

### 范围边界（注册阶段已拍板，本 PRD 原样采纳）

- 目标版本 0.23，开工前置无；E4→E5 内部一条线。
- CR-C 只含 E4/E5；LLM 对齐巡检与变更影响扫描（`review-alignment` / `change-impact-analysis` 定时化）**推迟**（§7 R-11），本 CR 不做。
- 知识晋升巡检已整节移出 P3 归《Wiki 子系统设计》（§2.3 / R-12），不在本 CR。
- 成熟度看板（E1/E2/E3）属 CR-A（已归档 CR-2026-047）；Skill Market（E6）属 CR-B（已归档 CR-2026-048）；基线校准、交付效能板块、资产复用率、超级个体占比、个人榜、待我审批端点属 CR-D。

### 依赖与风险

- **既有能力依赖**：P1 crctl outbox 通道与 `cr_sync_event` 表；P0 writeback-traceability；`sys_cron_executions` 调度器；CR-A 已交付的看板治理板块框架；`governance/gen/generate-transitions.mjs` 生成器先例；workspace 的仓库访问配置。
- **CR 间依赖**：开工前置无；E4→E5 一条线。E4 的 trace 查询依赖 P0/P1 的累积追溯与事件投影；E5 的治理展示依赖 CR-A 的治理板块框架，但扫描、finding 数据和下钻列表属于本 CR。
- **主要风险**：
  - 前缀合规 ≠ 通路合规（前缀可手写伪造）；通路层对账明确延后 P3+，本 CR 的 bypass 信号只是「可见性」而非「强制」。
  - 「从未漂移过」与「从未测过」必须可区分——扫描任务失败/未运行必须在治理板块可见，不得与「无 finding」混淆。
  - trunk 历史重写、仓库暂时不可访问或扫描进程中断不得造成游标跳过；失败时保留上一个成功游标并重试。
  - 同一 CR-ID 可能在不同 workspace 重复出现；E4/E5 的事件、finding、查询和唯一键不得跨 workspace 串数据。

## 2. 用户故事

| ID | 角色 | 行为 | 价值 |
|---|---|---|---|
| US-1 | 工程师 | 在 spec 详情页从一条 FR 看到它由哪些 CR 演进而来（时间线），并一跳跳到那次上线的 merge commit 与测试证据 | 回答「这个功能是谁、经哪个 CR、什么证据落地的」 |
| US-2 | 工程师 | 全局搜索按人反查其经手过的 spec，按 spec 反查演进历史 | 追溯审计与知识复用 |
| US-3 | Tech Lead / Owner | 在治理板块看到各仓 trunk 的 bypass 提交数量与 wip-on-trunk 记录，并能区分扫描正常与扫描异常 | 探测影子工程，让绕过可见且不把无数据误读为无漂移 |
| US-4 | QA | 在治理板块下钻到 drift_finding 流列表页，查看并流转 finding 状态（open→acknowledged/resolved/wontfix） | 漂移问题闭环管理 |
| US-5 | 平台管理员 | 在本仓 dir-graph.yaml 维护各仓提交前缀白名单，生成器校验 Go 副本无漂移 | 约定变更走声明而非发版 |

## 3. 功能需求

### E4 — 跨 CR 追溯查询（trace event_kind + spec 详情页）

- **FR-1** writeback-traceability 成功完成 commit/push 后，crctl outbox 发出版本化的 `event_kind='trace'` 事件。payload 的 canonical JSON 结构固定为：
  ```json
  {
    "spec_id": "ai-first-platform",
    "traceability": {
      "spec-id": "ai-first-platform",
      "cr-ref": "CR-YYYY-NNN",
      "cr-history": [],
      "target-version": "0.23",
      "baseline-since": "0.10",
      "generated-at": "2026-08-20T00:00:00+08:00",
      "milestones": []
    }
  }
  ```
  `traceability` 是 `specs/{spec_id}/traceability.yml` 经 LF 规范化后解析得到的完整语义对象，保留其既有键名（包括 `spec-id`）；顶层 `spec_id` 是供查询/索引使用的稳定别名。payload 不要求保留 YAML 注释或字节顺序。事件的 `cr_id`、`commit_sha`、`occurred_at` 继续使用现有 outbox v1 顶层字段。
- **FR-2** daemon 与 server 的事件 schema/allowlist 必须接受 `trace`；trace 是 ledger-only 事件，不触发 CR 状态转换，不写入 `cr` 状态投影，但成功入账后必须写 `processed_at`，便于重试与健康判断。未知 `trace` 不得因当前 `knownEventKinds` 缺项而被拒收。
- **FR-3** trace 交付采用可恢复的 outbox 语义：writeback journal 记录 `trace-outbox` 的 pending/emitted 事实，并使用由 CR-ID + writeback commit SHA 派生的确定性 dedup 文件名。outbox 暂时不可写时，writeback 主流程仍可完成但必须返回 warning、保留 pending 事实；重跑同一 `writeback-apply --stage traceability` 必须补发，daemon/server 暂时不可用时文件保留并由既有 collector 重试。相同事件最多在 ledger 中落一行。
- **FR-4** 为解决现有多 workspace ledger 的同名 CR 冲突，`cr_sync_event` 增加 `workspace_id`（由 server daemon auth 上下文注入，不信任事件正文），历史行通过 `cr_sync_event.cr_id = cr.cr_id` 回填；回填遇到无法唯一归属的历史行必须硬失败，不得猜测。将唯一键从 `(cr_id, commit_sha, event_kind)` 扩展为 `(workspace_id, cr_id, commit_sha, event_kind)`，并移除旧唯一键；既有 outbox、commit-scan ingestor、review/approval 查询一并按 workspace 写入/读取。`trace` event_kind 本身仍因无 CHECK 约束而不新增枚举迁移。
- **FR-5** 查询直打 `cr_sync_event`，必要时加表达式索引 `(payload->>'spec_id') WHERE event_kind='trace'`；所有查询必须以当前 workspace 过滤，不得依赖 `cr_id` 单独隔离；**不建 `spec_trace` 投影表**（R-10：事件行自带时间戳与完整 payload，二次拆列只多一份会漂的副本）。
- **FR-6** spec 详情页展示该 spec 的 FR 演进时间线：读取 `payload.traceability.milestones[].frs[]`，按 trace 事件时序展示每条 FR 由哪些 CR 演进而来，并标明当前 workspace。
- **FR-7** 一跳直达：从 FR 时间线可跳转到对应 merge commit（commit 页/仓库链接）、测试证据（test-report）与评审记录（approval / review 记录）；链接目标必须使用 traceability evidence 中的路径与 commit SHA，不猜测 trunk 最新提交。
- **FR-8** 全局搜索接入：在当前 workspace 内按 `cr.owners` 反查某人经手过的 spec，按 spec 反查演进历史；搜索结果必须与 spec 详情页使用同一 trace 数据源，禁止跨 workspace 返回同名 CR。

### E5 — 漂移检测（前缀扫描 + drift_finding）

- **FR-9** 前缀扫描是服务端纯 Go（**不走 Agent、不走 LLM**），注册稳定 job name=`commit_prefix_scan`，每个 workspace 使用一个 scheduler scope（scope_id=workspace_id），每小时按该 workspace `dir-graph.yaml#repositories` 声明的全部仓扫各自 trunk 新提交。服务端必须通过现有仓库访问配置取得每个声明仓的 trunk HEAD 与 commit subject；任一声明仓不可访问时本次 plan 失败，不把缺仓误报为「无 finding」。
- **FR-10** 判定口径：`wip:` 是优先级更高的特许分类，带该前缀的 trunk 提交一律计 `wip-on-trunk`（severity=`info`），不计入 bypass；其余提交前缀不在该仓 `commit_prefixes` 白名单且不属该仓特许格式 → 计 `bypass-commit`（severity=`warn`）。每条 E5 finding 的 `evidence` 必须包含非空 `repository_id`、`trunk`、`commit_sha`、`commit_subject` 与扫描时间。
- **FR-11** 白名单单一事实源 = 本仓 `dir-graph.yaml#repositories[].commit_prefixes`（本 CR 新增字段）；本 CR 首次为 knowledge-base、multica、tools 三个声明仓提交非空初始白名单，并覆盖各仓当前既有合法提交格式。前缀约定不硬编码在 Go。照抄 `governance/gen/generate-transitions.mjs` 生成器模式：读声明 → 吐只读 Go 副本（文件头记源 commit SHA）→ 副本提交入库 → `--check` 模式在 CI/pre-commit 重生成并 diff，漂移则非零退出。
- **FR-12** 新增 `drift_finding` 表，租户与身份契约固定为：`workspace_id UUID NOT NULL`、`repository_id TEXT NOT NULL`、`spec_id TEXT NULL`、`cr_id TEXT NULL`、`kind` CHECK（`alignment-drift`/`impact-stale`/`bypass-commit`/`wip-on-trunk`）、`severity` CHECK（`info`/`warn`/`block`）、`summary TEXT NOT NULL`、`evidence JSONB NOT NULL DEFAULT '{}'`、`status` CHECK（`open`/`acknowledged`/`resolved`/`wontfix`，默认 `open`）、`found_at`、`resolved_at`。本 CR 的 bypass/wip finding 为仓库级记录，`spec_id=NULL`、`cr_id=NULL`；spec 详情不是伪造的 repo finding。未来 alignment/impact finding 才可填写真实 `spec_id`/`cr_id`。
- **FR-13** `drift_finding` 的幂等键为 `CREATE UNIQUE INDEX CONCURRENTLY drift_finding_dedup_idx ON drift_finding (workspace_id, repository_id, kind, COALESCE(spec_id, ''), (evidence->>'commit_sha'))`；E5 事件要求 `evidence.commit_sha` 非空。采用 at-least-once 交付 + 唯一索引去重，不在应用层「先查再插」（R-13）。同一 workspace、仓库、分类和 commit 连续扫描 24 小时仍只一行；不同 workspace 或仓库的同名 commit 不冲突。
- **FR-14** 增量扫描游标持久化在现有 `sys_cron_executions.result.scan_cursors`，按 repository_id 保存上一次**完整成功扫描**的 trunk HEAD SHA。首次成功 plan 只记录当前各仓 HEAD 为 baseline，不对 baseline 之前的存量历史生成 finding；随后每次只扫描 cursor（不含）到本次开始时 HEAD（含）的提交。全部声明仓扫描成功后才原子写入新 cursors；任一仓访问失败、游标不在当前 trunk 历史或进程中断时，不推进受影响 plan 的 cursors，重试必须从上一个成功游标继续，允许重复读取但不得漏扫或产生重复 finding。
- **FR-15** 治理板块使用同一个 `commit_prefix_scan` 的 `sys_cron_executions` 记录作为健康事实源：最新成功 plan 的 `result.scan_cursors` 必须覆盖当前全部声明仓且距当前不超过两个小时桶；无成功记录显示「未初始化」，超过窗口或最新 plan 为 FAILED 显示「扫描异常」。只有健康状态下的零 finding 才显示为「无漂移」，禁止把未运行/失败折叠成零值。健康状态、bypass 数量、wip-on-trunk 数量与解决时延均按当前 workspace 过滤。
- **FR-16** `drift_finding` 流列表页挂在治理板块下作为下钻目的地（§4 质量中心降级形态），支持 status 流转（`open`→`acknowledged`→`resolved`，记录 `resolved_at`；或 `wontfix`），并与治理板块计数使用同一 workspace/repository/finding 查询口径。

## 4. 非功能需求

- **NFR-1** 新增迁移从下一个可用编号 **385** 起（2026-08-20 核实 multica 当前已有 375–379 CR-A maturity/report、380–384 CR-B skill/appeal 迁移，当前最大编号为 384）。`drift_finding` 的 `id` 不得使用 inline `PRIMARY KEY` 生成索引：建表文件只定义 `id UUID NOT NULL DEFAULT gen_random_uuid()`，随后在独立迁移文件中用 `CREATE UNIQUE INDEX CONCURRENTLY` 建 id 索引，再在另一个独立文件用 `PRIMARY KEY USING INDEX`；`drift_finding_dedup_idx` 另占一个只含该索引语句的迁移文件。`cr_sync_event` workspace/key 修正同样不得 inline 新索引；**禁新增 FOREIGN KEY**；每个索引必须 `CREATE INDEX CONCURRENTLY` 且一个迁移文件一条。
- **NFR-2** 不新建任何事务/队列/outbox 抽象（仓内已有 crctl 文件 outbox + `cr_sync_event` 幂等账本、`webhook_delivery` 租约投递、`agent_task_queue` 的 `FOR UPDATE SKIP LOCKED`）。trace 重试复用 writeback journal、现有 outbox collector 和 sys_cron lease。
- **NFR-3** 前缀扫描为确定性纯计算（一次 `git log` 取增量），无 LLM 依赖、无 daemon 依赖，给定 repo HEAD 与白名单时结果可重现。
- **NFR-4** 扫描为旁路检测：只读被扫仓，不得阻塞或修改任何提交；仓库访问失败必须是 FAILED/异常信号，不得静默成功。
- **NFR-5** 所有 trace/finding API、SQL 查询、唯一键和状态变更均 workspace-scoped；不得以 `cr_id`、`spec_id` 或 commit SHA 单独作为跨 workspace 隔离条件。
- **NFR-6** 构建 multica 不需要 checkout 本仓：commit_prefixes 声明经生成器产出 multica 只读 Go 副本；运行时仓库访问使用现有 workspace 仓库配置，不新增跨仓运行时文件依赖。
- **NFR-7** trace outbox 写入失败不阻塞已经完成的 writeback 主流程，但必须保留可恢复 pending 事实；在 outbox/collector 恢复并重跑同一业务命令或自动重试后，不得永久丢失 trace 事件。

## 5. 验收标准

| ID | 覆盖 FR | 可执行验收 |
|---|---|---|
| AC-1 | FR-1、FR-2 | 用一份已生成的 `specs/{spec}/traceability.yml` 触发 trace writeback：事件 `event_kind='trace'` 被 daemon/server 接受，`payload.spec_id` 等于文件 `spec-id`，`payload.traceability` 与 LF 规范化后解析的完整 YAML 语义相等；事件入账后 `processed_at` 非空，且不改变 `cr.status`。 |
| AC-2 | FR-3、NFR-7 | 在 outbox 暂时不可写时，writeback 仍能完成并返回 warning，journal 保留 pending；恢复写入能力后重跑同一 `writeback-apply --stage traceability`，生成确定性 trace outbox 文件并最终入账；重复重跑/重复投递最终只产生一行。 |
| AC-3 | FR-4、NFR-5 | 两个 workspace 使用同名 CR-ID 时，各自产生不同 `workspace_id` 的 trace ledger 行；迁移先为既有行按 `cr` 投影成功回填 workspace_id，再删除旧唯一键并建立 workspace-scoped 唯一键；若存在无法唯一回填的历史行则迁移非零失败；trace 查询只返回当前 workspace，不能读到另一 workspace 的 payload。 |
| AC-4 | FR-5 | 迁移清单中不存在 `spec_trace` 表；`event_kind='trace'` 查询直打 `cr_sync_event`，使用 `payload->>'spec_id'` 过滤；表达式索引如建立则是独立 `CONCURRENTLY` 迁移。 |
| AC-5 | FR-6 | 归档两个以上同 spec CR 后，spec 详情页按 trace 事件时序展示每个 CR 对该 spec 各 FR 的演进，且只显示当前 workspace 的数据。 |
| AC-6 | FR-7 | 从 FR 时间线一跳可到达对应 merge commit、测试证据与评审记录；链接使用 evidence 中的路径/SHA，缺失证据时明确显示缺失，不回退到 trunk 最新提交。 |
| AC-7 | FR-8、NFR-5 | 全局搜索按人反查只返回当前 workspace 内其 owners 经手过的 spec；按 spec 反查返回同一 workspace 的演进历史；构造另一 workspace 同名 CR 后不会混入结果。 |
| AC-8 | FR-9、FR-14 | 注册 `commit_prefix_scan` 后，单 workspace 每小时产生一个 scope=workspace_id 的 plan；缺任一声明仓访问权限时 plan=FAILED，且不产生「无 finding」成功态。首次成功 plan 只建立三仓 HEAD baseline，不为 baseline 前提交生成 finding。 |
| AC-9 | FR-10 | 非白名单前缀提交产生 `bypass-commit`/`warn`；`wip:` 提交产生 `wip-on-trunk`/`info` 且不进入 bypass 计数；每条 evidence 含非空 repository_id、trunk、commit_sha、commit_subject、scanned_at。 |
| AC-10 | FR-11 | `dir-graph.yaml` 为三个声明仓均有非空 `commit_prefixes` 初始声明，覆盖当前已确认的合法提交格式；改一条声明后生成器副本更新，未更新副本时 `--check` 非零；副本头含源 commit SHA。 |
| AC-11 | FR-12、FR-13、NFR-1 | 执行迁移后 `drift_finding` 含 workspace_id/repository_id、可空 spec_id、四类 kind、三类 severity、四类 status 和默认值；bypass/wip 行的 spec_id/cr_id 均为 NULL；无 FK；id 主键及 dedup 索引均按独立 CONCURRENTLY/USING INDEX 迁移落地，dedup key 含 workspace、repository、kind、spec 空值归一化和 evidence.commit_sha。 |
| AC-12 | FR-14 | 给定 cursor=A 与 HEAD=B，扫描只处理 A 之后到 B（含）的提交；首次运行只写 baseline；模拟中途失败后 cursor 仍为 A，重试能处理 A→B 且不漏提交；游标不是当前 trunk ancestor 时 plan=FAILED，不猜测重置。 |
| AC-13 | FR-13 | 同一 workspace/仓库/kind/commit 连扫 24 小时仍只有一行；不同 workspace 或不同仓库即使 commit SHA 相同也分别保留；应用层不做先查再插。 |
| AC-14 | FR-15 | 无成功 plan 显示「未初始化」；最新成功 plan 超过两个小时桶或最新 plan=FAILED 显示「扫描异常」；健康且无 finding 才显示「无漂移」；治理板块显示 bypass 数量、wip-on-trunk 数量与解决时延。 |
| AC-15 | FR-16 | 治理板块可下钻到 drift_finding 列表页；finding status 可流转 open→acknowledged→resolved（记录 resolved_at）或 wontfix，流转后列表、健康状态与板块计数仍按同一 workspace/repository 口径一致。 |

## 6. 成功指标

- 在 outbox 可写、collector/server 恢复且执行同一重试语义后，归档 CR 的 trace 事件最终落库率 **100%**，每个事件只有一条 workspace-scoped ledger 记录。
- 三个声明仓的前缀扫描覆盖率 **100%**：每个 workspace 每小时有成功/失败的明确执行记录，不把缺仓或失败显示成零 finding。
- 首次 baseline 前的历史提交误报数 = **0**；已声明白名单内前缀的误报数 = **0**。
- 同一 workspace/仓库/kind/commit 24 小时重复扫描产生的重复 finding 数 = **0**。
- 跨 workspace 的 trace/finding 数据泄露数 = **0**。

## 7. 范围排除

本 CR 明确**不做**（含去向）：

- LLM 对齐巡检（`review-alignment` 定时化）与变更影响扫描（`change-impact-analysis` 定时化）——七跳链路 + daemon 在线依赖，静默无结果与无漂移不可区分（R-11），待 daemon 在线率有真实数据后再立项；`alignment-drift` / `impact-stale` 只保留表枚举，不由本 CR 产生。
- bypass 通路层对账（controlled-shell 审计行 ↔ trunk 提交交叉核对）——需把本地审计投影到服务端，属新采集，延后 P3+；P3 只做前缀层探测（§2.2 / §6）。
- `spec_trace` 投影表——`cr_sync_event.payload` 已是完整事实，二次拆列只多一份会漂的副本（R-10）。
- 知识晋升巡检（E9 已整节移出 P3，归《Wiki 子系统设计》，R-12）。
- 成熟度看板 E1/E2/E3（CR-A 已归档）、Skill Market E6（CR-B 已归档）、CR-D 全部内容（基线校准写入 config、交付效能板块、资产复用率、超级个体占比、个人榜、待我审批端点）。
- 通用 Pipeline Runner（读侧投影已由 `governance/gate_projection.go` 交付，属 M1/A2）。
- 跨组织对标、个人绩效导出/API、指标实时化、Skill 付费/积分机制（平台级不做项，§6）。

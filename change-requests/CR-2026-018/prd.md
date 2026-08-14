---
id: CR-2026-018-prd
type: PRD
cr-ref: CR-2026-018
title: 治理工具链 — 状态推进单写 cr.md，_backlog.yml 退化为注册索引（T1-full）
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: "2026-08-04T13:00:00+08:00"
updated: "2026-08-04T13:00:00+08:00"
---

# PRD — 状态推进单写 cr.md，_backlog.yml 退化为注册索引（T1-full）

## 1. 概述

### 1.1 问题陈述

CR-2026-012 收尾复盘（`docs/analysis/CR-2026-012-合并回写归档复盘.md`）确认的最大摩擦源（约占卡点耗时 35%）：`crctl advance` 每次状态推进同时写两处——`change-requests/_backlog.yml` 条目的 `status` + `updated-at` 行，与 `change-requests/{CR-ID}/cr.md` frontmatter 的同名字段。CR 分支与 master 各自积累状态提交后，合并/变基时 `_backlog.yml` 同一条目区域**必然**冲突（CR-2026-012 生命周期 9 个状态提交全部冲突）。更结构性的问题是：`merge-feature-branch` Step 2 规定 dry-run 冲突即中止，因此只要双侧存在状态提交，该 skill 按字面执行对知识库仓**永远走不通**。

### 1.2 解决方案摘要

状态的单一事实源收敛为 `cr.md` frontmatter：`crctl advance` 只写 `cr.md`，不再写 `_backlog.yml` 的 `status`/`updated-at`；`_backlog.yml` 退化为**注册索引**（保留 id / title / owners / prd-path / merge-commits 等注册与里程碑字段）。CR 分支上的高频状态提交从此只触碰 `change-requests/{CR-ID}/**`——该路径在合并前 master 侧不写，冲突面从源头消除。

**可见性无损失**：现状下在途 CR 的状态提交本来就在 CR 分支上，master 的 `_backlog.yml` 对在途 CR 同样陈旧；改为 cr.md 单一事实源不损失任何现有读取能力。

### 1.3 事实基线（已核实，纪律 #4）

| 事实 | 位置 |
|---|---|
| `_backlog.yml` status 写入点仅 1 处：`updateBacklogStatus()`，由 `advance` 调用（cr.md summary 中"8 处写入逻辑"系登记时误记，以此为准） | `crctl.mjs:674`（调用点 `:814`） |
| `status` 子命令从 `_backlog.yml` 读权威状态 | `crctl.mjs:335-342` |
| workspace 探测依赖 `change-requests/_backlog.yml` 存在性 | `crctl.mjs:289` |
| `validate` 对 `_backlog.yml` 条目做 schema 校验 | `crctl.mjs:1018-1024` |
| 31 个 skill 文档引用 `_backlog.yml`；其中直接消费条目 `status` 的至少有 cr-dashboard（按 `backlog[].status` 分组）、cr-archive（entry.status→final-status）、merge-feature-branch（Step 5 embedded status patch） | `grep -rln _backlog tools/skills --include=SKILL.md` |
| 状态机 scope 字段写明 `_backlog.yml` | `tools/dir-graph.yaml:210` |
| 适配器读取路径均经 crctl 子命令（claude-code SessionStart 注入 `crctl status`、CI 复用 `crctl gate`/`validate`），随 crctl 升级自然切换，但需回归验证 | `crctl/adapters/` |

## 2. 用户故事

- **US-1** 作为 CR 开发者，我在 CR 分支上推进状态时不产生任何会与 master 冲突的提交，merge-feature-branch 对知识库仓可以按字面流程一次走通。
- **US-2** 作为平台维护者，我通过 `crctl status` 得到的状态读数在改造前后语义一致，不需要改变任何使用习惯。
- **US-3** 作为看板使用者（cr-dashboard / cr-query），我在改造后仍能看到与现在等价的 CR 状态分布。
- **US-4** 作为存量 workspace 的所有者，我有一条明确的一次性迁移路径，且迁移期内新旧布局都能被 crctl 正确读取。

## 3. 功能需求

- **FR-1（advance 单写）**：`crctl advance` 只写 `cr.md` frontmatter 的 `status` 与 `updated-at`；删除对 `updateBacklogStatus()` 的调用路径。CAS 写保护、审计日志、门禁校验、状态事件行为不变。
- **FR-2（读取路径切换 + 兼容读）**：`status` / `advance`（前置读）/ `gate` / `next` / `validate` 的权威状态读取源改为 `cr.md` frontmatter；当 `cr.md` 缺失 status 字段时回退读 `_backlog.yml` 条目并在输出中携带 `legacy-source` 告警。回退路径为迁移期兼容，计划在下一个大版本移除。
- **FR-3（_backlog.yml 退化为注册索引）**：条目保留字段收敛为注册与里程碑类（id、title、owners、submitter、reviewer、opened、prd-path、merge-commits、merge-recovery、archived-at、writeback_spec_id 等低频字段）；`status`/`updated-at` 不再作为权威字段。`validate` 不再要求条目含 `status`；若仍含且与 `cr.md` 不一致，输出漂移告警（迁移期不阻断）。
- **FR-4（workspace 探测不变）**：`_backlog.yml` 文件继续作为 workspace 探测锚点（`crctl.mjs:289` 逻辑不变），文件本身不删除。
- **FR-5（一次性迁移命令）**：提供 `crctl migrate-backlog`（或等价子命令）对存量 workspace 执行：校验各条目 `status` 与 `cr.md` 一致 → 从 `_backlog.yml` 条目中移除 `status`/`updated-at` 行 → 生成迁移报告。不一致时硬失败并列出差异，禁止静默取一侧（纪律 #1 硬失败原则）。
- **FR-6（skill 文档同步修订）**：31 个引用 `_backlog.yml` 的 skill 文档中，凡读取条目 `status` 的段落改为读 `cr.md`（重点：cr-dashboard 状态分组改为扫描 `change-requests/*/cr.md`；merge-feature-branch Step 5 embedded patch 只落 `cr.md` + `merge-commits[]` 仍写 `_backlog.yml`；cr-archive Step 3 移动条目时以 `cr.md` 的 final-status 为准）。仅引用文件路径不消费 status 的文档不改。
- **FR-7（状态机声明同步）**：`tools/dir-graph.yaml#change-request-track.state_machine.scope` 从 `_backlog.yml` 改为 `change-requests/{CR-ID}/cr.md`。
- **FR-8（适配器同版本回归）**：claude-code 适配器（SessionStart/PreCompact 注入）与 CI 适配器（gate/validate）在改造后跑一遍回归：注入输出与 CI 判定在新布局 workspace 上与旧行为等价。
- **FR-9（归档流兼容）**：cr-archive 的 backlog→history 移动逻辑保持——归档发生在 master 单侧、每 CR 一次，不构成冲突面；history 记录的 `final-status` 字段语义不变。

## 4. 非功能需求

- **NFR-1（状态机语义零变更）**：15 个具名状态 + `(new)`、23 条声明转移（wildcard 展开 45 条）完全不变（口径见纪律 #2）；本 CR 只改状态的**存储位置与读写路径**。
- **NFR-2（行尾纪律）**：所有新增/修改的解析与写入代码遵守纪律 #1——读入先 `\r\n → \n` 规范化、`split(/\r?\n/)`、跨行解析失败硬报错；`cr.md` frontmatter 写入保持现有 `updateCrMdStatus()` 的 CAS 模式。
- **NFR-3（原子性）**：单文件写入沿用现有 sha256 CAS（读后被改则 `CAS_CONFLICT` 中止）；advance 从双文件写变为单文件写，原子性只增不减。
- **NFR-4（向后兼容窗口）**：兼容读（FR-2 回退路径）至少保留一个完整 CR 生命周期，供多 workspace 分批迁移。

## 5. 验收标准

- **AC-1**（对应 FR-1）：在测试 workspace 执行一次合法 `advance`，`git diff` 显示仅 `change-requests/{CR-ID}/cr.md` 变更，`_backlog.yml` 无 diff。
- **AC-2**（对应 FR-2）：新布局（_backlog 无 status）下 `crctl status` 返回 `cr.md` 中的状态；构造仅 `_backlog.yml` 有 status 的旧布局，`crctl status` 返回该状态且输出含 `legacy-source` 标记。
- **AC-3**（对应 FR-3）：`crctl validate` 对新布局 workspace 全绿；对 status 双写且不一致的 workspace 输出漂移告警且退出码为 0（迁移期）。
- **AC-4**（对应 FR-4）：在无其他标志文件的目录树中，`crctl --workspace` 缺省探测仍能命中含 `_backlog.yml` 的目录。
- **AC-5**（对应 FR-5）：对含 ≥2 个条目的存量 `_backlog.yml` 执行迁移命令：一致时产出无 status 的注册索引 + 迁移报告；人为制造一处不一致时命令非零退出且不写文件。
- **AC-6**（对应 FR-6）：`grep -rn "backlog\[\].status\|_backlog.*status"` 在修订后的 skill 文档中仅命中"迁移说明/历史注记"类段落；cr-dashboard 按新数据源描述统计逻辑。
- **AC-7**（对应 FR-7）：`dir-graph.yaml#state_machine.scope` 指向 cr.md；`crctl status` 输出的 `source.stateMachine` 不变、状态源指向 cr.md。
- **AC-8**（对应 FR-8）：claude-code 适配器 SessionStart 注入在新布局 workspace 输出正确状态；CI 模板对 `requirement/*` 分支的 gate 判定与改造前一致（用同一组 fixture 对比）。
- **AC-9**（对应 FR-9 与核心目标）：端到端演练一个测试 CR：分支上推进 ≥3 次状态 → master 侧注册另一 CR 制造并行写 → `merge-tree --write-tree` dry-run 对 `_backlog.yml` **零冲突**。
- **AC-10**（回归）：`crctl` 现有测试套件（`scripts/test/crctl.test.mjs`）全绿，新增用例覆盖 FR-1/2/3/5。

## 6. 成功指标

- 下一个走完整生命周期的 CR，在 merge-feature-branch 阶段知识库仓 dry-run 对 `_backlog.yml` 冲突数为 **0**（基线：CR-2026-012 为 9 个提交全冲突）。
- 合并/回写/归档三阶段实际耗时相对 CR-2026-012 的 ~190 min 显著下降（复盘将冲突连环归因为 ~35% 卡点耗时，预期至少消除该部分）。
- 迁移后一个月内无因状态读取源分裂产生的 `CAS_CONFLICT` / 状态漂移工单。

## 7. 范围排除

- **不做 P2**（账本操作 crctl 子命令化：任务 `_index.yml` 标 done、归档移动等）——本 CR 是其前置，P2 待本 CR 定型后另立。
- **不改状态机本身**：不增删状态、不改转移与门禁语义、不动 `gates.json` 的证据映射结构（仅在其引用 `_backlog.yml` 状态源处随 FR-7 同步措辞）。
- **不改 `_history.yml` 结构**与归档记录字段。
- **不处理非知识库仓**：独立代码仓不含 `change-requests/`，本 CR 与其无关。
- **不移除兼容读**：回退路径的删除放到后续版本，本 CR 只标记 deprecated。
- **不解决 cr.md 在 master 侧对未合并 CR 不可见的问题**：这是现状既有行为（_backlog.yml 同样如此），与本 CR 无关。

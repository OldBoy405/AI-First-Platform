---
id: CR-2026-071-plan
type: PLAN
cr-ref: CR-2026-071
sdd-ref: "change-requests/CR-2026-071/sdd.md"
target-version: 0.44
status: draft
created: 2026-09-27T16:37:21+08:00
updated: 2026-09-27T16:37:21+08:00
---

# CR-2026-071 开发计划

来源：`prd.md`（FR-1～FR-4，AC-1～AC-6）与 `sdd.md`（§4.1～§4.4，dep-1～dep-7）。
目标版本 0.44 自 `cr.md` 继承。AIFI-35 / CR-2026-001 只读，不触发其 reviewer，不改其账本。

## 1. 交付里程碑

- **M1 — multica 判定修复与合同回归（0.5 人天）**：§4.1 四份提示词全文替换 + `delegation-contract.md` 新建 + §4.3 回归脚本三组断言；`node --test` 全绿。对应 TASK-01、TASK-03。
- **M2 — tools checkpoint 节点恢复（0.5 人天）**：§4.4 `...0003` 节点恢复 + `_index.yml` nodes 5→6 + `pipeline-structure.test.mjs` 断言同步；结构测试全绿。对应 TASK-02。
- **M3 — bak 审计与线上同步（0.5 人天）**：§4.1 bak 审计（保留/排除理由落盘）+ §4.2 四个线上 Agent 同源同步 + 逐个 `agent get` 核验。对应 TASK-04。
- **M4 — 全量验证与交付记录（0.5 人天）**：cmd-01～cmd-03 全绿 + 线上核验原文留存 + AIFI-35 zero_diff 核验 + checkpoint 发布。对应 TASK-05。

估算总工时：2 人天。顺序 M1 → M2 → M3 → M4；M1 与 M2 无代码依赖可并行，但同属一人执行故串行。

## 2. 任务依赖图

```text
TASK-01 (multica 四份提示词 §4.1)
  └─► TASK-03 (合同源 + 回归 §4.3, 依赖 TASK-01 的替换落点)
        └─► TASK-04 (bak 审计 + 线上同步 §4.1/§4.2, 依赖 TASK-03 的合同全文)
TASK-02 (tools ...0003 + index + 结构测试 §4.4, 独立可并行)
  └─► TASK-05 (全量验证 + 交付, 依赖 TASK-03/TASK-04/TASK-02 全部完成)
```

跨仓依赖仅在 M4 会合；multica 与 tools 无共享代码依赖（SDD §1）。

## 3. 资源与分工

- 执行人：dev-agent（设计期与开发期责任）；owner 三角色均为 Ray，仅人工审批与线上指令 owner 确认由 Ray 执行。
- 工时分配：M1 0.5（含 dep-1～dep-4 取证复核）、M2 0.5（含 dep-5～dep-7 基线复核）、M3 0.5（4 次 `agent update` + 4 次 `agent get`）、M4 0.5（3 条证据命令 + 发布）。
- 工具：`crctl checkpoint`（发布）、`node --test`（回归/结构）、`multica agent update/get`（线上同步核验）。

## 4. 风险与回滚策略

- **R1 平台枚举未来新增 status**：合同回归枚举对齐断言变红。回滚：revert TASK-03 commit（含合同与测试），下游 TASK-04（线上同步）一并回滚；顺序 TASK-04 → TASK-03（逆拓扑）。
- **R2 线上指令更新部分失败**：某 Agent `agent get` 与合同不一致。回滚：revert TASK-04 commit；不触碰 TASK-01/TASK-03 文件侧（上游保留），仅重做线上同步。
- **R3 结构测试基线误改**：`pipeline-structure.test.mjs` 断言与 JSON 不一致。回滚：revert TASK-02 commit（节点 + index + 测试同属一个回滚单元）。
- **R4 bak 排除副本被误部署**：排除理由未留痕。回滚：revert TASK-04 的 bak 部分；下游无消费者，单点 revert 安全。
- **R5 共享改动回滚牵连**：TASK-03 合同源被 TASK-01/TASK-04 消费，其回滚单元含下游 TASK-04；单点 revert TASK-03 而保留 TASK-04 会造成提示词与合同不一致，故禁止单点回滚，必须连带 TASK-04。

回滚顺序（逆拓扑）：TASK-05（验证记录，无代码）→ TASK-04 → TASK-03 → TASK-01；TASK-02 独立分支单独 revert。

## 5. 验收与发布策略

发布前 checklist：cmd-01～cmd-03 全绿；四份 `agent get` 成品与合同逐字一致（原文留存交付记录）；AIFI-35 无新 reviewer run、其 CR 状态/账本零 diff；`crctl checkpoint` phase=complete 三仓 confirmed；feature-flag 不适用（提示词与 Pipeline JSON 即时生效，无灰度开关）。

环境前提与即时验证口径：本计划验收证据均为离线命令与只读线上核验，无常驻服务、浏览器或数据库依赖。

- 环境 owner、建立方式、可获得性：multica / tools CR worktree 由 CR 注册派生，责任人 Ray，已存在于本机，无需新建；`node`（v24）与 `multica` CLI 本机可用。
- readiness 证据：复用本计划既有 `cmd-01`（multica 回归全绿即 worktree 可读且依赖基线在位）与 `cmd-02`（tools 结构测试全绿即 Pipeline JSON 可解析）；证据 ID 照抄第 6 章证据命令表，不新增命令行。
- 缺失时处置：worktree 缺失或命令无法执行按 `ENVIRONMENT_MISMATCH` 标签中止并报告所需建立动作（详细事实源见 `implement-code`，此处只引用不复述）。

## 6. 两张稳定表

### 交付覆盖表

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-1 委派回执按目标判定 | §4.1 四份提示词全文替换（dep-3 行号） | CR-2026-071-TASK-01 / 关联 CR-2026-071-TASK-03 | cmd-01 | revert TASK-01 commit（被 TASK-03/04 消费时连带下游，见 §4 R5） |
| FR-2 源部署副本与线上一致 | §4.1 bak 审计 + §4.2 线上同源同步 | CR-2026-071-TASK-04 / 关联 CR-2026-071-TASK-01、CR-2026-071-TASK-03 | cmd-01 | revert TASK-04 commit（含 bak 与线上同步记录；文件侧上游保留） |
| FR-3 单一合同与漂移回归 | §4.1 合同源 + §4.3 三组断言 | CR-2026-071-TASK-03 / 关联 CR-2026-071-TASK-01 | cmd-01 | revert TASK-03 commit（含下游 TASK-04，见 §4 R5） |
| FR-4 恢复 node-2 后评审前 checkpoint | §4.4 `...0003` 节点 + `_index.yml` + 结构测试同步 | CR-2026-071-TASK-02 | cmd-02 | revert TASK-02 commit（节点 + index + 测试同一单元） |

说明：FR-2 的线上四份 `agent get` 原文核验属在线只读动作，不属离线 cmd 观测面，列入 §5 checklist 并在 TASK-04 交付记录留存；cmd-01 观测其文件侧全量（四份 + 需维护 bak 与合同一致），不存在以子集声称全量。

### 证据命令表

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | multica | . | node | ["--test", "cr-prompts-revised/test/delegation-contract.test.mjs"] | 120 |
| cmd-02 | tools | . | node | ["--test", "skills/shared/crctl/scripts/test/pipeline-structure.test.mjs"] | 120 |
| cmd-03 | tools | . | node | ["-e", "JSON.parse(require('fs').readFileSync('pipeline-templates/requirement-authoring.pipeline.json','utf8'));console.log('pipeline-json-ok')"] | 60 |

命令算法唯一事实源为本表行；`cwd` 为对应 repo CR worktree 内相对路径（`.` 即 worktree 根）；`executable` 直接可 spawn，无 shell 内建/管道/重定向；不涉及 Git 写操作，不改 `rules.json`。

## 7. AC/业务闭环覆盖矩阵

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-1 queued/coalesced/deferred 判成功零误报 | §4.1 + §4.3 向量前 3 例 | CR-2026-071-TASK-03 | cmd-01 |
| AC-2 blocked/缺失 outcome/human-only/未知 status | §4.1 四分支 + §4.3 向量后 4 例 + 2 例否定 | CR-2026-071-TASK-03 | cmd-01 |
| AC-3 源/bak/合同/回归/线上四份一致 | §4.2 + bak 审计 | CR-2026-071-TASK-04 | cmd-01 |
| AC-4 回归覆盖与枚举对齐漂移变红 | §4.3 三组断言 | CR-2026-071-TASK-03 | cmd-01 |
| AC-5 node-2 → checkpoint → review 顺序与回修重发 | §4.4 + _index/结构测试 | CR-2026-071-TASK-02 | cmd-02 |
| AC-6 AIFI-35 零触发零账本改动、新 CR 未来流程 | §9 zero_diff/scope | CR-2026-071-TASK-05 | cmd-03 |

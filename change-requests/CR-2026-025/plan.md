---
id: CR-2026-025-plan
type: PLAN
cr-ref: CR-2026-025
sdd-ref: "change-requests/CR-2026-025/sdd.md"
target-version: tbd
status: draft
created: "2026-08-09T02:10:00+08:00"
updated: "2026-08-09T02:10:00+08:00"
---

# 开发计划 — crctl 守卫与回显收敛

> **实施前提（已核实满足）**：PRD D-3/NFR-5 要求项①在 CR-2026-024 批次一合入后实施——tools 仓 `custom/main` 已含批次一（commit `18358df`），actor 级 external 现状即 B-3 预期终态（`brainstorming`×2、`executing-plans`、`subagent-driven-development` 共 4 项有引用点声明）。四项因此**无跨 CR 批次依赖，同批交付**。

## 1. 交付里程碑

| # | 里程碑 | 内容 | 估算 |
|---|---|---|---|
| M1 | 项②③：`crctl.mjs` 小改双联 | `guardDependsOn` 一跳守卫（FR-6~FR-8）+ `isEmpty` 回显收敛 `briefArray`（FR-11~FR-14）+ `crctl.test.mjs` 对应向量（FR-10 五类 / FR-15 五类） | 0.5 人天 |
| M2 | 项④：review-record 三账本一致写 + cmdNext 路由 | `nextLoopText` 拆分（I-1）+ attempts 历史合并（§4.4a 2b，含 TD-BL-4 分支）+ `upsertReviewsStage`（§4.4c）+ `subject-sha256`（§4.4b）+ `cmdNext` drafting 决策表（§4.4d）+ FR-21 八类向量 | 1.0 人天 |
| M3 | 项①：checker 检查 4 + 首测 | `externalByActor` + `readNorm` + 三段空结构硬失败守卫 + 引用点扫描（§4.1）+ 新建 `check-skill-matrix.test.mjs`（FR-5 六类）+ F-5/F-6/F-7 声明面修订（FR-4） | 0.5 人天 |
| M4 | 收尾：文档同步 + Prompt 采纳 + 全量验证 | F-8/F-9/F-10 用途表与表述同步（FR-9）+ P-1~P-5 SKILL 提示词采纳 + `ARCHITECTURE.md` §8 登记（FR-24）+ FR-22 三件套与三测试文件全绿 + FR-23 溯源提交 | 0.5 人天 |

**总估算：2.5 人天**。顺序 M1 → M2 → M3 → M4：M1 先行热身且与 M2 共享 `crctl.test.mjs`（串行避免同文件向量冲突）；M3 与 M1/M2 无代码依赖，排后只为让 M4 文档同步一次看到全部代码终态。

## 2. 任务依赖图

```text
M1: TASK(项②守卫) ─┐
                   ├─→ 同改 crctl.test.mjs，批内串行
M1: TASK(项③收敛) ─┘
        │
        ▼
M2: TASK(nextLoopText 拆分) → TASK(三账本一致写+attempts 合并) → TASK(cmdNext 路由)
        │                        （同一 cmdReviewRecord 重构链，严格串行）
        ▼
M3: TASK(checker 解析扩展+守卫) → TASK(检查 4) → TASK(声明面三处修订)
        │                          （测试文件独立，与 M2 无冲突）
        ▼
M4: TASK(文档/Prompt 采纳) → TASK(全量验证 FR-22 + 溯源提交 FR-23/24)
```

跨里程碑唯一硬依赖：M4 的 FR-9/P-1~P-5 文案必须引用 M1~M3 落地后的最终错误码与命令语义。

## 3. 资源与分工

- 单一实施者（dev-agent / Ray），无并行分工；工时分配即上表 M1~M4。
- 测试全部随码同批（每个里程碑的完成定义含对应向量全绿），不另设独立测试阶段。

## 4. 风险与回滚策略

| 风险 | 概率/影响 | 缓解与回滚 |
|---|---|---|
| M2 `cmdReviewRecord` 重构引入半状态回归 | 中/高 | 全校验前置 + `casWriteMulti` 原子批写；FR-21 向量④注入 CAS 失败断言三文件不变；回滚 = git revert 该里程碑单 commit |
| M2 attempts 合并误伤既有 trace 未知段 | 低/高 | `upsertReviewsStage` 只动目标 stage 块，其余 LF 规范化后逐字节保留（AC-19）；`TRACE_SHAPE` 硬失败不猜写 |
| M1 守卫误拒合法 `task done`（如带引号/缺失字段） | 低/中 | FR-10 五类向量钉住 `parseYaml` 行为；守卫只读不写，拒写即 `_index.yml` 哈希不变（AC-7 断言） |
| M3 检查 4 子串匹配误报/漏报 | 低/中 | 口径与 CR-2026-024 人工认定一致（I-3）；AC-5 在合入后真实仓库实跑验证；误报回滚 = revert checker commit（纯增量规则） |
| M3 空结构守卫把合法的小仓夹具场景判死 | 低/低 | 守卫只判"解析产物为空"，正常仓库必有 active skill；测试夹具显式覆盖 |
| M4 Prompt 采纳遗漏 | 低/中 | P-1~P-5 清单进 TASK；`lint-prompts --mode enforce` 兜底 |

## 5. 验收与发布策略

- **发布形态**：tools 仓 `custom/main` 直接提交（方法论包无 feature-flag 面）；按 M1~M4 分 commit，每 commit 自含代码+测试+文档同步，可独立 revert。
- **发布前 checklist**：
  1. FR-22：`check-skill-matrix.mjs` + `check-agents-contract.mjs` + `lint-prompts.mjs --mode enforce` 全绿
  2. `node --test` 三测试文件（crctl / lint-prompts / check-skill-matrix）全绿
  3. AC-1~AC-23 逐条对照执行证据（AC-5/AC-18 以"024 批次一已合入"为前提执行）
  4. FR-23：commit message 溯源（方案 v2.6 §7 + CR-2026-024 SDD 评审实测 + CR-2026-025）；`grep "C:\\Users"` 零命中
  5. FR-24：`ARCHITECTURE.md` §8 登记本 CR
  6. NFR-9：只 add 本 CR 文件清单，禁 `git add -A`
- **TD-SUG-3 遗留**：M2 实施时非 bump 分支在 review-loop.yml 缺失时按 attempt=1 处理并补一条向量（技术评审留痕，非阻塞）。

## 6. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-08-09 | v0.1.0 | Ray | 初始计划：M1~M4 四里程碑，2.5 人天；实施前提（024 批次一合入）已核实满足，无跨 CR 批次依赖 |

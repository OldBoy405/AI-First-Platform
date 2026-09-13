# CR-2026-065 工作流导航缓存（`_context.md`）

> 本文件是**导航缓存**，不是 canonical 事实。canonical 事实优先：`cr.md`、`review-loop.yml`、
> `traceability.yml`、`review-annotations/**`、`tasks/_index.yml`、`approval.yml`。
> 用途：返工与 `/resume` 时快速定位「做到哪、卡在哪、从哪继续」。

## 0. 路径甲授权落账（逐字留档，2026-09-13）

```yaml
cr_id: CR-2026-065
authorized_path: 甲
authorization:
  quote: "授权甲"
  by: Ray
  at: 2026-09-13T02:59:36Z
  comment: 01a098b4-bae5-7c9a-b197-c070a9f4546c
  scope: "以既有边 review-code:plan-blocker -> write-dev-plan 作为 code 阶段发现 SDD 前提失效的治理回退入口；本次回退无 review-code BLOCK 前因，该事实经此授权成立"
```

- 授权原话载体：AIFI-26 评论 `01a098b4-bae5-7c9a-b197-c070a9f4546c`（作者 `Ray`，`2026-09-13T02:59:36Z`，正文四字「**授权甲**」）。
- 派单载体：AIFI-26 评论 `01a098b7-9775-74e5-b915-a6f03726fb4f`（`cr-coordinator-agent`，`2026-09-13T03:02:43Z`，§3 列出 A1→A3 与 `authorization` 块）。
- **触发串与事实的对应关系**（关键：本回退**没有** `review-code` 的 BLOCK 前因，该事实在上列授权下成立）：

| 项 | 事实 |
|---|---|
| 使用的边 | `dir-graph.yaml` 已声明：`{ from: developing, to: tech-design-reviewed, trigger: "review-code:plan-blocker -> write-dev-plan" }` |
| 为什么用它 | `developing → tech-design-review-pending` **无边**；code 阶段治理（CR-2026-057 FR-6/FR-7）明文禁止为此新增状态转换 |
| 前提失效的事实 | SDD §3.4/§4.2 的 TAP 归属机制（`# Subtest: <file>.test.mjs` 文件名块 + file 级 plan `1..N`）在目标运行时**不存在**（B-4；第一手实测见 `plan.md` §0.0 一栏，**已关闭**） |
| 「无 BLOCK 前因」的含义 | 本次触发串**不声称**存在 `review-code` 的 BLOCK 结论；它是一条经人工授权的「code 阶段发现 SDD/证据链前提失效」治理回退入口 |
| 授权范围外 | 不新增状态转换、不 push |

## 1. 当前状态（最近一次刷新：`write-dev-plan`/`write-dev-tasks` replay run，2026-09-13 14:0x +08:00）

- CR：`CR-2026-065`；权威 workspace = `.rayai-worktrees/knowledge-base/requirement/CR-2026-065`；受控路径只走 `crctl`。
- CR 状态（canonical）：`tech-design-reviewed`（KB HEAD `db64dd37`）；`crctl gate --for tech-design-reviewed` = **`pass: true`**；
  审批绑定**修订版 SDD**（`review-annotations/sdd.yml#subject-sha256` = `approval.yml#tech-design` 的证据面 = `ecc1f902…`，与当前 `sdd.md` 逐字节相等）。
- 本条 run 的节点：`code-implementation / node-1 write-dev-plan` → `node-2 write-dev-tasks`（**B-4 修订后的二次 replay**，
  `reviewLoop.replayNodes` = `write-dev-plan` → `write-dev-tasks` → `review-dev-plan`）。
- 本 run 落盘：`change-requests/CR-2026-065/plan.md`（全文按修订版 SDD 重述）+ `tasks/TASK-03.md` / `tasks/TASK-04.md`
  （阻断叙事 → 关闭叙事；逐文件 spawn / 单文件 TAP / 15 字段报告 / `--report <ndjson>` 口径）+ 本文件刷新；
  单提交 `[cr] write dev plan CR-2026-065`（**不 push**）。
- 随后（同一 run 的 node-2 收尾）：`crctl advance --to task-breakdown --trigger write-dev-tasks --expect tech-design-reviewed`（**非 embedded**）⇒ **已执行实测**：`advanced=true` / `from=tech-design-reviewed` / `to=task-breakdown` / `committed=true` / `outbox=20260913T061123508Z-CR-2026-065-status-2de33f9f.json`；KB HEAD = `2de33f9f`、`status --short` 空。
  - **`crctl next` 读法提醒**：该命令现在返回 `write-tech-design`（why：上一条 `review-annotations/dev-plan.yml` 仍是 attempt 1 的 `verdict=block` / `repair-target=write-tech-design`）；该上游阻断已于 `fd48041c` 关闭，**本计划的下一节点是 `review-dev-plan`**，`crctl next` 的返回值不构成阻断事实。
  - **advance 后已知提醒**：`crctl status` 会报 `gateBlockers.developing = [EVIDENCE_DRIFT(development-start)]` —— 上一轮 `developing` 期签发的审批覆盖的 `plan.md` 被本轮 replay 修订（预期）；人工 `approve --stage dev-start` 写入时以新摘要重签即自然消失（`approveAndAdvance` 的 evidence override）。
- 再随后：新建独立 `quality-reviewer-agent` run 执行 `review-dev-plan`（**不得自评**）；PASS 后人工 `approve --stage dev-start`（输 `y`）→ `developing`。
- 未触碰：`sdd.md`（一个字节都不改）、`prd.md`、`review-annotations/**`、`review-loop.yml`、`approval.yml`、`cr.md` 的 status（只经 `crctl advance`）、
  `skills/**`、`pipeline-templates/**`、`dir-graph.yaml`、`TASK-01/02` 卡片与实现、CR-2026-064。

## 2. TASK 进度与第一手证据

| TASK | 状态（`tasks/_index.yml`，canonical） | 证据 / 本 run 处置 |
|---|---|---|
| `CR-2026-065-TASK-01` | `done` | cmd-02 = **exit 0 / 506 ms**（BR-1…BR-4 全绿）；`gate-registry.json` = 具名 15 / 声明 31 / any-active 12；**卡片与实现不动** |
| `CR-2026-065-TASK-02` | `done` | cmd-03 = **exit 0 / 40.0 s**（BR-5 构造 A/B + 契约用例）；**卡片与实现不动** |
| `CR-2026-065-TASK-03` | `pending` | 本 run 重述：§0 改为阻断关闭声明；§3.1 `--report <ndjson>`（`--rc` 取消）；§3.2 逐文件 spawn（池 = `CONCURRENCY`）；§3.3 报告 15 字段；§3.4 单文件 TAP 硬失败；§3.6 单文件片段解析自测 + 归属自测 + 用例名以 `CR-2026-065` 起始；§4.1 须附被命中用例名清单 |
| `CR-2026-065-TASK-04` | `pending` | 本 run 重述：§0 改为阻断关闭；§3.1 **三候选**（默认 / 2 / 1）× ≥2 次；§3.2 证据固定字段**补 `verdict`**；§3.3 `manifest.cases` 逐文件终值；§4 证据清单 = 6 份 concurrency + 6 份 drift |

- 账本口径：`_index.yml` 已有 TASK-01/02 的 `done` + `done-at` ⇒ `crctl task init` 被 `guardTaskIndexHasNoProgress`（`crctl.mjs:1653-1663`）拒绝（预期 `TASK_INDEX_HAS_PROGRESS`，零写入）⇒ 本 run **不重跑 `task init`**，`id`/`title`/`estimate`/`depends-on` 与账本逐项全等（只读复核通过）。
- 卡片 `status` 字段**非权威**（`crctl` 只读账本；`renderTaskIndex`（`crctl.mjs:1628-1638`）一律渲染 `pending`）；TASK-01/02 卡片保留 `pending` 是有意的（边界要求其卡片不动）。
- tools worktree：HEAD `2c84241462ed42580eeb1571de8d60d9c55d5a4b`、**clean**、未 push；交付面 9 条路径全部落在 `cmd-04` 白名单内。
- KB worktree：本 run 后 HEAD = `[cr] write dev plan CR-2026-065`（+ `advance` 的 `cr.md` 提交）。

## 3. B-4 阻断与本次修订的定稿口径（第一手实测；当前机制，未变）

**旧前提（已证伪，`051adca6` 引入、`1678ab09`/`0505ed2c` 沿用、`fd48041c` 废止）**：SDD §3.4/§4.2 用「TAP 文件名块（`# Subtest: <file>.test.mjs`）+ file 级 plan `1..N`」取 per-file 归属。
**实测**：正常文件下该形态**不存在**（`# Subtest:` 全是用例名、唯一 plan 是全局 `1..N`）；文件名块只在「整文件加载失败」时出现，且其**名字形态随 Node 版本变**（v24 = 文件名，v20 = 绝对路径）。

**定稿机制（已批准、当前权威）**：

| 维度 | 定稿 | 探针（原始输出在 `sdd.md` §7.4） |
|---|---|---|
| 归属 | **逐文件 spawn**（每文件一个 `node --test --test-reporter=tap <file>` 子进程），归属由 spawn 构造给出，**不读报告** | ——（构造保证，与格式无关） |
| 文件集合事实源 | 磁盘目录 `readTestFileSet` ↔ `manifest.files` | —— |
| 每文件用例数 | 单文件 TAP 的**顶层 plan ≡ 顶层结果行数**；证据面 = 报告 `files[]` | P9：真实套件文件单跑，v24 与 **v20.20.2（CI 同版本）** 逐字一致（17 / 7） |
| 并发 | 包装器池常量 `CONCURRENCY`（文件级并发）；默认 = `max(1, availableParallelism()-1)`，**候选 {默认,2,1}** 由 TASK-04 有界实测定值 | P8 |
| 失效出口 | 解析不符 → **硬失败红**；唯一允许的替代 = 每文件观察通道换成结构化事件流（需双运行时探针 + 报告 `observer` 登记 + `review-code` 覆盖） | P1/P2/P3 |
| 明确**不采用** | junit `file`（v20 无）、目录参数/glob 位置参数（跨版本不一致）、`--test-isolation`（v20 无此选项） | P3 / P5 / P6 / P7 |

**不变的不变量（未放宽）**：每文件被真实执行 + 每文件用例数 ≥ 基线 + 解析失败硬失败（`sdd.md` §3.2 I1…I3）。

## 4. 恢复入口

1. **node-2 收尾未完成**（`crctl status` 仍为 `tech-design-reviewed`）：先 `crctl gate CR-2026-065 --for tech-design-reviewed` 复核 `pass: true`，再
   `crctl advance CR-2026-065 --to task-breakdown --trigger write-dev-tasks --expect tech-design-reviewed`（非 embedded）。
2. 独立 `review-dev-plan`（新建 `quality-reviewer-agent` run；`repair-target` 缺省 `write-dev-plan`）：
   - PASS → 人工 `approve CR-2026-065 --stage dev-start`（输 `y`）→ `developing`；
   - BLOCK（普通轨）→ 按 `replayNodes` 回修本计划/`tasks/**` 后复评（`maxAttempts=3`）；
   - BLOCK（`repair-target=write-tech-design`）→ 走 `review-dev-plan:upstream-design-blocker`（条件性出口，须附第一手证据）。
3. `developing` 后：TASK-03 → TASK-04 → `write-test-report` → checkpoint → 独立 `review-code` → 人工 `approve --stage code`。
4. 已就绪可复用：`test/suite-gate.mjs` 的判定面 / 例外四查 / check code 表 / `--report` 解析自测框架；`assertion-sources.mjs`、`gate-registry.json`、`lib/outbox-contract.mjs` 与 TASK-01/02 全部用例。
   **TASK-03 待补齐**：逐文件 spawn（池 = `CONCURRENCY`）、单文件 TAP 解析、`files[]` / `observer`（13 → 15 字段）、`--report <ndjson>`（`--rc` 取消）、`crctl-ci.yml:109-111` 接线。
5. 范围外待办（`sdd.md` §9 `follow_up` 第 4 条）：`crctl gate --for tech-design-reviewed` 不校验 annotation 的 `subject-sha256` 是否等于当前 `sdd.md` —— 单开 CR 处理，不塞进本 CR。

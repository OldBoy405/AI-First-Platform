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
| 前提失效的事实 | SDD §3.4/§4.2 的 TAP 归属机制（`# Subtest: <file>.test.mjs` 文件名块 + file 级 plan `1..N`）在目标运行时**不存在**（B-4；第一手实测见 `plan.md` §0.0 与 §3） |
| 「无 BLOCK 前因」的含义 | 本次触发串**不声称**存在 `review-code` 的 BLOCK 结论；它是一条经人工授权的「code 阶段发现 SDD/证据链前提失效」治理回退入口 |
| 授权范围外 | 不新增状态转换、不 push |

## 1. 当前状态（最近一次刷新：`write-tech-design` B-4 回修 run，2026-09-13 13:3x +08:00）

- CR：`CR-2026-065`；权威 workspace = `.rayai-worktrees/knowledge-base/requirement/CR-2026-065`；受控路径只走 `crctl`。
- 本条 run 的节点：`architecture-design / node-1 write-tech-design`（**reviewLoop 回修模式**，进入前 `status = tech-designing`）。
- 本 run 落盘：`change-requests/CR-2026-065/sdd.md` **原地定点修订**（B-4）+ 本文件刷新，单提交 `[cr] write tech design CR-2026-065`（不 push）。
- 随后（同一 run）：`crctl advance --to tech-design-review-pending --trigger write-tech-design-complete --expect tech-designing`（非 embedded）⇒ **终点 = `tech-design-review-pending`**。
- 再随后：新建独立 `quality-reviewer-agent` run 执行 `review-tech-design --bump-attempt`（**attempt 3/3 = 最后一轮**），覆盖 `review-annotations/sdd.yml`。
- 下一人工节点（A7，仅限交互式终端）：评审 PASS 后 `approve CR-2026-065 --stage tech-design` → 提示时输 `y`。
- 之后（A8）：replay `write-dev-plan` → `write-dev-tasks` → 独立 `review-dev-plan` PASS → 人工 `approve --stage dev-start` → `developing` → 续做 TASK-03/04。

## 2. TASK 进度与第一手证据

| TASK | 状态（`tasks/_index.yml`） | 证据 |
|---|---|---|
| `CR-2026-065-TASK-01` | `done` | cmd-02 = exit 0（4 条断言转绿）；`gate-registry.json` 初值 具名 15 / 声明 31 / any-active 12 / 展开 53（本 run 用 `deriveStateMachine` 复算一致） |
| `CR-2026-065-TASK-02` | `done` | cmd-03 = exit 0（BR-5 构造 A + 新增构造 B + 契约不变性） |
| `CR-2026-065-TASK-03` | `pending` | `test/suite-gate.mjs` 已落地判定面，但按**旧** SDD 的 per-file 归属面不可完成；`crctl-ci.yml:109-111` 一字未改。A8 replay 后按修订版 SDD 重述 §3.4/§4.2 并补齐 |
| `CR-2026-065-TASK-04` | `pending` | 依赖 TASK-03（传递阻断）；其并发测量面与归属机制无关 |

- tools 全量套件实测（TASK-01/02 后、去参默认并发）：**exit 0 / 568 用例 / 0 失败 / 891.1 s**（`1..568`）。
- tools worktree：HEAD `2c84241`、**clean**、未 push；新增 `lib/outbox-contract.mjs`、`test/assertion-sources.mjs`、`test/gate-registry.json`、`test/suite-gate.mjs`（WIP）；修改 `crctl.mjs` + 4 个 test 文件。
- KB worktree：本 run 后 HEAD = `[cr] write tech design CR-2026-065`；`advance` 另提交 `cr.md`。

## 3. B-4 阻断与本次修订的定稿口径（第一手实测）

**旧前提（已证伪）**：SDD §3.4/§4.2 用「TAP 文件名块（`# Subtest: <file>.test.mjs`）+ file 级 plan `1..N`」取 per-file 归属。
**实测**：正常文件下该形态**不存在**（`# Subtest:` 全是用例名、唯一 plan 是全局 `1..N`）；文件名块只在「整文件加载失败」时出现，且其**名字形态随 Node 版本变**（v24 = 文件名，v20 = 绝对路径）。旧文档的根因句是 §7.4 的「TAP 解析不依赖 Node 版本专有输出格式」—— 无证据的保证性陈述。

**本次定稿的机制（已批准范围内，逐条有探针）**：

| 维度 | 定稿 | 探针（本轮自跑，原始输出在 `sdd.md` §7.4） |
|---|---|---|
| 归属 | **逐文件 spawn**（每文件一个 `node --test --test-reporter=tap <file>` 子进程），归属由 spawn 构造给出，**不读报告** | ——（构造保证，与格式无关） |
| 文件集合事实源 | 磁盘目录 `readTestFileSet` ↔ `manifest.files`（不再是「从报告读出的实际执行集合」） | —— |
| 每文件用例数 | 单文件 TAP 的**顶层 plan ≡ 顶层结果行数** | P9：真实套件文件单跑，v24 与 **v20.20.2（CI 同版本）** 逐字一致（17 / 7） |
| 并发 | 包装器池常量 `CONCURRENCY`（与 `--test-concurrency` 同语义，文件级并发）；默认 = `max(1, availableParallelism()-1)`，候选 {默认,2,1} 由 TASK-04 有界实测定值 | P8 |
| 失效出口 | 解析不符 → **硬失败红**；唯一允许的替代 = 每文件观察通道换成结构化事件流（需双运行时探针 + 报告 `observer` 登记 + `review-code` 覆盖） | P1/P2/P3 |
| 明确**不采用** | junit `file`（v20 无）、目录参数/glob 位置参数（跨版本不一致）、`--test-isolation`（v20 无此选项） | P3 / P5 / P6 / P7 |

**不变的不变量（未放宽）**：每文件被真实执行 + 每文件用例数 ≥ 基线 + 解析失败硬失败（`sdd.md` §3.2 I1…I3）。

## 4. 恢复入口

1. 独立 `review-tech-design`（cycle 1 **attempt 3/3**，最后一轮）：BLOCK → `LOOP_EXHAUSTED`，**不重试、不绕行**，出口是人工 `review-loop reset`。
2. PASS → 人工 `approve CR-2026-065 --stage tech-design`（输 `y`）→ `tech-design-reviewed`。
3. A8：replay `write-dev-plan` → `write-dev-tasks` → 独立 `review-dev-plan` PASS → 人工 `approve --stage dev-start` → `developing`。
4. A9：续做 TASK-03/04 → `write-test-report` → checkpoint → 独立 `review-code`。
5. 已就绪可复用：`test/suite-gate.mjs` 的判定面 / 例外四查 / check code / 报告模型（补齐 §3 表中「归属 + 每文件计数」两项）；`assertion-sources.mjs`、`gate-registry.json`、`lib/outbox-contract.mjs` 与 TASK-01/02 全部用例。
6. 范围外待办（已写入 `sdd.md` §9 `follow_up` 第 4 条）：`crctl gate --for tech-design-reviewed` 不校验 annotation 的 `subject-sha256` 是否等于当前 `sdd.md` —— 单开 CR 处理，不塞进本 CR。

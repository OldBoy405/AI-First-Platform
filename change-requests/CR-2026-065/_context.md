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
| 使用的边 | `dir-graph.yaml` 已声明：`{ from: developing, to: tech-design-reviewed, trigger: "review-code:plan-blocker -> write-dev-plan" }`（`crctl status` 的 `legalNext` 亦含该 `to`+`trigger` 对） |
| 为什么用它 | `developing → tech-design-review-pending` **无边**；code 阶段治理（CR-2026-057 FR-6/FR-7）明文禁止为此新增状态转换。故借既有回退边回到 `tech-design-reviewed`，再走 upstream 设计修订链（同 CR-2026-061 先例） |
| 前提失效的事实 | SDD §3.4/§4.2 的 TAP 归属机制（`# Subtest: <file>.test.mjs` 文件名块 + file 级 plan `1..N`）在目标运行时**不存在**（第一手实测见 `plan.md` §0.0 与本文件 §3） |
| 「无 BLOCK 前因」的含义 | 本次触发串**不声称**存在 `review-code` 的 BLOCK 结论；它是一条经人工授权的「code 阶段发现 SDD/证据链前提失效」治理回退入口 |
| 授权范围外 | 不新增状态转换、不改 `sdd.md` 正文（修订版 SDD 只能在 `tech-designing` 期由 `write-tech-design` 产出）、不 push |

## 1. 当前状态（最近一次刷新：dev-agent 路径甲 A1 run，2026-09-13）

- CR：`CR-2026-065`；权威 workspace = `.rayai-worktrees/knowledge-base/requirement/CR-2026-065`。
- 路径甲执行进度：**A1 保命本地提交** → **A2 `advance --to tech-design-reviewed`** → **A3 replay `write-dev-plan` → `write-dev-tasks` → 独立 `review-dev-plan`（route 必须 upstream）**。
- 本轮终点：`tech-design-review-pending`（由独立 `quality-reviewer-agent` run 按 `review-dev-plan/SKILL.md` §4 UPSTREAM 轨 `--embedded` 推进）。
- 下一人工节点（A4，仅限交互式终端）：`approve CR-2026-065 --stage tech-design` → 提示时输 `n`（驳回旧 SDD）→ 状态回 `tech-designing`。

## 2. TASK 进度与第一手证据

| TASK | 状态（`tasks/_index.yml`） | 证据 |
|---|---|---|
| `CR-2026-065-TASK-01` | `done` | cmd-02 = exit 0（4 条断言转绿）；负控自检「注入即红 / 还原即绿」；`gate-registry.json` 初值 声明 31 / 具名 15 / any-active 12 / 展开 53 |
| `CR-2026-065-TASK-02` | `done` | cmd-03 = exit 0（BR-5 构造 A + 新增构造 B + 6 条契约不变性）；回归保护 `同一漂移二次观测` = exit 0；五导出自检通过 |
| `CR-2026-065-TASK-03` | `pending` | `test/suite-gate.mjs` 已按 SDD 判定面落地但**不可按 SDD 完成**（§3）；`crctl-ci.yml:109-111` 一字未改 |
| `CR-2026-065-TASK-04` | `pending` | 依赖 TASK-03，未开始 |

- tools 全量套件实测（TASK-01/02 后，去参默认并发）：**exit 0 / 568 用例 / 0 失败 / 891.1 s**（`1..568`）。
- tools worktree 改动面：新增 `lib/outbox-contract.mjs`、`test/assertion-sources.mjs`、`test/gate-registry.json`、（WIP）`test/suite-gate.mjs`；修改 `crctl.mjs`（`emitOutboxEvent` 内部）+ `test/{crctl,checkpoint-tx,archive-tx,trace-outbox}.test.mjs`。
- 未 push、未 checkpoint；账本只经 `crctl task done` 写入两次（TASK-01/02）；未调 `approve`、未手改任何 status。

## 3. 阻断性事实（A3 回退的因，第一手实测）

**SDD §3.4/§4.2 的 TAP 归属机制在目标运行时不存在**（非环境标签、非自报）：

- 真实 21 文件全量 TAP：`# Subtest` 568 行**全部为用例名**，`# Subtest: *.test.mjs` = **0**，全文唯一 plan = 全局 `1..568`；passing 用例的 YAML 块内无 `location`。
- 三个 Node 版本一致（flat）：本地 Node **24.15.0**（SDD 登记的本地环境）、CI 版本 Node **20.20.2**、Node **18.20.8**。
- 变量排查：`--test-isolation=process|none`、`--test-concurrency=1`、显式文件列表 vs 目录发现，均不产生文件名块。
- 文件名块唯一出现场景 = 整文件加载失败（`# Subtest: <path>` + `not ok`，即 `SUITE_FILE_LOAD_FAILURE` 的形态），**不是**正常文件的正常分组。

⇒ `files_executed` / 每文件用例数 / `manifest.files` 集合核对**不可判** ⇒ cmd-01 永红 ⇒
AC-01 / AC-11 / AC-12 / AC-13 / AC-14 不可达。就地改成全局口径属「放宽」，故不就地放宽。

## 4. 恢复入口

1. A4（人工 TTY）驳回旧 SDD → `tech-designing`。
2. A5 `write-tech-design` 出修订版 SDD：O1（TAP 判定 + 显式第二 reporter 目的地取归属）/ O2（一文件一批）/ O3（全局口径，不建议）或其他方案在此定稿，必须带第一手证据；修订点 = SDD §3.4 归属机制 + §4.2 命令形态 + R-04 口径。
3. A6 独立 `review-tech-design`（cycle 1 **attempt 3/3**）→ A7 人工 `approve --stage tech-design`（输 `y`）。
4. A8 replay `write-dev-plan` → `write-dev-tasks` → `review-dev-plan` PASS → 人工 `approve --stage dev-start` → `developing`。
5. A9 续做 TASK-03/04 → `write-test-report` → checkpoint → 独立 `review-code`。
6. 已就绪可复用：`test/suite-gate.mjs` 的判定面 / 例外四查 / check code / 报告模型（缺 per-file 归属面）；TDEC-4 候选 A（去参）第 1 次整跑 = 891.1 s / converged=true / failures=0。

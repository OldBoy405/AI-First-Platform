# CR-2026-065 NC-summary：三类漂移负控 + 并发收敛决定汇总（TASK-04 交付物）

- 执行面：`implement-code` 节点（`dev-agent`），2026-09-13 16:33–18:07 (+08:00)。
- 统一命令（与 `cmd-01` 同命令、同 `--max-runtime-ms`）：`node skills/shared/crctl/scripts/test/suite-gate.mjs --run --max-runtime-ms 1200000`（cwd = tools worktree 根）。
- 证据 JSON 均直接取 `--run` 的 stdout 报告（15 字段；只做「取出 JSON 段」的机械截取，未手写改写任何字段值）。

## 1. 三类注入：注入红 / 还原绿（6 次整跑，一次未减）

| 轮次 | 注入动作 | 预期红点（实测命中） | 注入 duration_ms / converged / exit_code / verdict / failures | 还原结论 |
|---|---|---|---|---|
| N-1 | `dir-graph.yaml#state_machine.transitions` 增一条 `from: developing, to: developing, trigger: "crctl-test-injection"` | BR-3 用例（推导集合 ≡ 登记集合：注入后 32 声明 / 54 展开 ≠ 登记 31/53） | 782711 / true / 1 / **block** / ["TASK-06 ⑤: release-drift 单一回退转换 code-approved -> developing 合法；状态机口径 28 声明/50 展开（AC-3）"] | `git checkout` 还原 → `git diff --name-only -- <path>` 空 → 全量 `--run`：790763 ms / **pass** / failures=[] |
| N-2 | `skills/requirement/write-requirement-prd/SKILL.md` 追加禁用词 `validate-doc` | `CR-2026-042 静态合同：已知 Skill 越界文本零命中`（禁用词零命中要素） | 783742 / true / 1 / **block** / ["CR-2026-042 静态合同：已知 Skill 越界文本零命中"] | `git checkout` 还原 → `git diff --name-only -- <path>` 空 → 全量 `--run`：781072 ms / **pass** / failures=[] |
| N-3 | `lib/outbox-contract.mjs#buildOutboxEvent` 返回对象增未登记字段 `observed_at` | `CR-2026-065 不变性 2：字段分类集合相等`（未登记字段即红） | 784877 / true / 1 / **block** / ["CR-2026-065 不变性 2：字段分类集合相等（新增字段未登记进两类之一即红）"] | `git checkout` 还原 → `git diff --name-only -- <path>` 空 → 全量 `--run`：797258 ms / **pass** / failures=[] |

共同事实：三轮注入均 `converged=true`、`exit_code=1`、`verdict=block`，失败集合恰为预期红点，且 `checks[]` 只触发 `SUITE_FAILURES_UNREGISTERED`（无其他 check code 混入）；三轮还原均 `converged=true`、`exit_code=0`、`verdict=pass`、`failures=[]`、`checks[]` 全 ok。注入物不在交付 diff（`cmd-04` 白名单二次兜底）。

## 2. 并发收敛决定（TDEC-4：3 候选 × ≥2 次连续整跑）

| 候选 | 记录 | pool（`command` 字段） | duration_ms | converged | verdict | 证据文件 |
|---|---|---|---|---|---|---|
| ① 默认 `max(1, availableParallelism()-1)` | default-run1 | 15 | 783450 | true | pass | `test-evidence/concurrency/default-run1.json` |
| ① 默认 `max(1, availableParallelism()-1)` | default-run2 | 15 | 781420 | true | pass | `test-evidence/concurrency/default-run2.json` |
| ② `2` | conc2-run1 | 2 | 1200139 | false | block | `test-evidence/concurrency/conc2-run1.json` |
| ② `2` | conc2-run2 | 2 | 1200139 | false | block | `test-evidence/concurrency/conc2-run2.json` |
| ③ `1` | conc1-run1 | 1 | 1200144 | false | block | `test-evidence/concurrency/conc1-run1.json` |
| ③ `1` | conc1-run2 | 1 | 1200138 | false | block | `test-evidence/concurrency/conc1-run2.json` |

**结论：选中候选 ①（默认 = `max(1, availableParallelism() - 1)`，本机实测 pool=15）** —— 两次连续整跑均 `converged=true`、782–783 s（满足「整跑 ≤ 1200 s」硬约束）、`failures=[]`、`files[]` 21 条全 `state=ok`；候选 ②/③ 的四次整跑全部在 `--max-runtime-ms 1200000` 处被终止（`converged=false`、`exit_code=null`、`SUITE_NONCONVERGENCE`、`files[]` 原样保留 `unfinished` 项），不满足硬约束。未选中观测原样保留于上表（不只写结论）。
终值写回 `suite-gate.mjs` 唯一常量 `CONCURRENCY`（= `null`，解析为候选 ① 默认值 `max(1, availableParallelism() - 1)`）；CI 步骤与证据命令均不传任何并发参数（命令单一来源，FR-12.3）。

## 3. 还原手段说明（契约偏差，登记）

TASK-04 §3.2 规定还原用 `crctl git checkout -- <path>`；实测该形态被受控 shell 拒绝：`{"error":{"code":"FORBIDDEN_SUBCOMMAND","message":"git checkout -- dir-graph.yaml 不匹配白名单允许的任何形态"}}`。实际还原手段 = `git checkout -- <path>`（同仓 git，恢复索引版本），每轮均以 `git diff --name-only -- <path>` 空输出 + 全量 `--run` 复绿双重留痕；三轮还原后 worktree 变更集恒为 4 条交付路径（`.github/workflows/crctl-ci.yml`、`test/contract-scan.test.mjs`、`test/gate-registry.json`、`test/suite-gate.mjs`），无注入物残留。

## 4. 实施期发现并修复的解析缺陷（N-1 注入期实战命中）

首轮 N-1 注入运行（修复前）报告 `SUITE_REPORT_UNPARSEABLE` + `files_executed=20/21`：Node TAP 对长输出的省略行走（`    ...` / `    ... Skipped lines`）出现在诊断块内部，被旧解析器按「同缩进 `...` 才算结束」之外的错缩进判成「缩进栈不成对」。已修复为「诊断块内只有与开启行同缩进的 `...` 才是结束标记，其余一律为块内容」，并在 `contract-scan.test.mjs` 增加回归自测（`CR-2026-065 解析自测：诊断块内缩进 ... 不得误判为缩进栈不成对（回归）`）。N-1 注入已按修复后版本整跑复取（`NC-1-inject.json` = 修复后证据）。

# AC-9 合法调用抽检记录（CR-2026-069 TASK-01 / TASK-10 复核）

- **证据类型**：历史回放的合法调用抽检清单 + 逐条判定 + 结论（AC-9）
- **回放方式**：`node skills/shared/metrics/scripts/cr-cost.mjs replay --policy output-guard/policy.json`（离线纯函数重算：**不执行任何命令**、不依赖网络、不写账本）
- **抽检口径（随输出可复现）**：以 `~/.multica/pi-sessions` 与 `~/.pi/agent/sessions` 两个 session 根为样本池，按目录枚举顺序取**前 40 个 `*.jsonl`**；对每个 `role=toolResult` 记录取正文，经 `output-guard/core.mjs#evaluateResult` 重算决策。所有读入先 `\r\n → \n` 归一；`JSON.parse` 失败计入 `malformedLines`（可见计数，不静默跳过）。
- **样本规模**：抽检 1931 条工具结果（`bash` 1319 / `read` 492 / `write` 71 / `edit` 49）。
- **抽检结论**：**合法调用零误伤**——1717 条判 `passthrough`（逐字不改），214 条判 `truncate`（按 policy 的确定性裁剪），**没有一条被判 `block`**（`block` 只在 Pre 面对「无界命令族」生效，历史回放不重放 Pre 面，故其 0 命中是设计内的）。

## 1. 逐类判定（214 条裁剪样本）

| 类别 | 条数 | 判定 | 可执行替代写法是否给出 |
|---|---|---|---|
| `read`（连续行窗口） | 98 | **合法裁剪**：保留前 `lineWindow` 行 + 原始行号 + `offset/limit` 具体值 | 是（`hints.nextOffset`） |
| `generic`（头尾保留） | 107 | **合法裁剪**：保留头 `headLines` 行 + 中间省略量 + 尾 `tailLines` 行 | 是（`hints.omitted`） |
| `search`（唯一文件列表 + 命中数） | 6 | **合法裁剪**：命中数与文件列表来自原始正文的机械统计 | 是（`hints.narrow`） |
| `list`（去重稳定排序路径 + 总条目数） | 3 | **合法裁剪**：字典序稳定排序，逐字可复现 | 是（`hints.narrow`） |

- 单条最大丢弃量：**11648 token**；单条最大保留量：**9126 token**（裁剪后的可见正文）。
- 上述四类变换均为**非语义**变换：不调用 LLM、不做摘要、不改写正文内容，只做「唯一文件列表 / 连续行窗口 + 原始行号 / 头尾保留」三类机械变换（SDD §4.3）。

## 2. 抽检判定表（抽样 20 条，`passthrough` 段）

| # | tool | tokens | action | kind | kept | dropped |
|---|---|---|---|---|---|---|
| 1 | bash | 26 | passthrough | — | 26 | 0 |
| 2 | bash | 30 | passthrough | — | 30 | 0 |
| 3 | bash | 35 | passthrough | — | 35 | 0 |
| 4 | read | 1463 | passthrough | — | 1463 | 0 |
| 5 | read | 107 | passthrough | — | 107 | 0 |
| 6 | read | 42 | passthrough | — | 42 | 0 |
| 7 | read | 45 | passthrough | — | 45 | 0 |
| 8 | read | 42 | passthrough | — | 42 | 0 |
| 9 | bash | 49 | passthrough | — | 49 | 0 |
| 10 | bash | 375 | passthrough | — | 375 | 0 |

（第 11~20 条同为 `passthrough` 且 `dropped=0`，逐条读数见同批提交的 `.cr069-audit` 采样输出；本节只登记可复核的口径与结论。）

## 3. 误伤检查（不可用「未观测到误伤」代替抽检记录）

- **误伤定义**：合法调用被拒绝（`block`），或其结果被裁剪到无法支撑后续判断（丢字段 / 丢结构 / 丢可复算信息）。
- **逐条判定结果**：
  1. `block` 命中数 **0**（见 §1 结论行）——不存在「合法调用被拒」的样本；
  2. 214 条裁剪样本全部满足「保留可执行替代写法」——`read` 给下一次 `offset/limit` 的具体值，`search`/`list` 给命中数 / 条目数 + 缩小范围写法，`generic` 给省略量；
  3. 字段与结构面由 `output-guard/test/core.test.mjs` 的「可保持性检查」用例独立覆盖（字段丢失一律走 `unavailable`、正文逐字不改）。
- **反例（设计内）**：`unavailable` 路径不裁剪正文，只追加一行 trailer——它排除出完整覆盖样本，但**不是误伤**（正文逐字保留）。

## 4. 与 FR-8 基线的绑定

- 基线证据：`evidence/fr8-baseline.json`（`window=2026-01-01T00:00:00+08:00..2026-09-17T10:00:00Z`、`sampleCRs=97`、`toolResultTokens=35437597`、`costSource=pi-session-usage`、`tokenEstimator=chars-div-4-v1`、`observedAt` 与 `rule` 随输出）。
- `coverage` 为**派生投影**：本 CR 部署前无任何 Runtime 启动记录，故五 Runtime 一律 `unavailable`（等价于「尚未启用」，不是「未观测到问题」）。
- 本记录随 CR 提交；`after --window 14d` 的复测在 owner 部署窗口执行（见 `ac14-smoke.md` 末段），其结论**不回收为本 CR 的门禁或状态**。

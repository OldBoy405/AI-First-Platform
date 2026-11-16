# crctl report 状态完整性 - 技术设计

## Context

- 2026-11-16 修订：tools main 为已在远端的 `7a0a2ab`；本轮只改本 change 文档，不改归档、业务代码或两仓绑定。根因收敛为状态输入校验、字典承载和已发布归档事实选择，不逐异常加旁路。
- 下列实测为 2026-11-15 的既有记录，本轮未重跑。实施前重取真实数据基线；ADJ-006 的文字复现须在 BUILD 固化为已发布/未发布成对回归。
- 上游：已交付的 `2026-11-15-crctl-report-active-count`（业务提交 `b2a743a`）把 `report` 改为「目录 ∪ `_history.yml` 按 CR 编号去重、终态不计入 active」，并遗留 4 项未处理：ADJ-006、ADJ-007、ADJ-009、ADJ-011。本 change 处理它们。
- `cmdReport`（`crctl.mjs` 约 5492–5565 行）现状：
  - 目录扫描里 `if (!md || !md.status) continue`——没有 `cr.md`、没有 frontmatter、`status` 为空的 CR 目录被静默跳过，`total` 少算；同一函数对「`status` 非字符串或带首尾空白」又硬失败（`SCHEMA_INVALID`）。
  - `status` 取值不校验：笔误（如 `develping`）按「非终态」计入 `active`，与 b2a743a 修复的缺陷同类（把本该不可判的数据算成在途）。
  - `statusHistogram` 是普通对象，状态名 `__proto__` 会丢计数。
  - 不使用 `publishedArchiveStatus`（归档 journal 兜底），而 `crctl status` 使用。
- 实测（2026-11-15）：
  - 真实 `AI First Platform/change-requests`：`total 76 / active 0 / archived 76 / statusHistogram {archived 68, withdrawn 8}`；76 个 CR 目录都有可用 `status`，0 个缺失。这是改前基线。
  - ADJ-006 **已复现**：复用 `archive-tx.test.mjs` 的 `makeWritebackFixture`，本地 KB 主 checkout dirty 使归档发布后本地未同步，此时 `crctl status` 报 `archived`、`terminal: true`，同一工作区的 `crctl report` 报 `total 1 / active 1 / archived 0 / statusHistogram {merging: 1}`——已发布的归档被计成在途。临时实验文件已删除，tools 工作区干净。
- 状态集合的事实源：`dir-graph.yaml#change-request-track.state_machine`。它没有单独的 `statuses` 列表；`transitions[].to` 枚举了每个状态（`from: (new)` 只出现在 `from` 侧），另有 `terminal`。真实声明里 `to` 的并集 + `terminal` = 15 个状态（12 个在途 + `archived/rejected/withdrawn`）。
- CR 的写入口：`crctl register` 经 `workspace-transactions.mjs` 的 `buildRegistrationTexts`（约 541 行）在同一事务里生成 `cr.md`，内容含 `status: drafting`；`review` 等命令写 `review-annotations/` 前先 `resolveCrState`，缺 `status` 即 `CR_MD_STATUS_MISSING`。**已核实的 crctl 写入口不会产生无 `status` 的 CR 目录**；手工建目录或旧版本遗留是未核实的来源，所以本 change 对其硬失败并点名，而不是静默。

## Decisions

### 1. 缺 `status` 的 CR 目录：硬失败，沿用 `status` 命令的错误码（C2）

**方案**：目录扫描先显式区分无文档/字段、null、空字符串，再按 `CR_MD_STATUS_MISSING` 点名失败；不要继续用 `!md.status` 将 false/0 误分类为缺失。其后非字符串或带首尾空白按既有 `SCHEMA_INVALID` 拒绝，最后校验声明集合（决策 2）。两种错误沿用现有错误码，不新增错误通道；共同目标是不可判输入不能进入计数或返回半张报表。

**为什么**：`cmdReport` 现有原则是「不可判数据一律硬失败，不静默降级」；缺 `status` 是同一类。`status` 命令对同一数据已硬失败，两个命令对同一个目录给出不同结论才是不一致。错误信息带目录名，运维能直接定位。

**备选方案及排除原因**：
- 备选 A：计入一个 `(unknown)` 桶。新增输出键，违背「不新增输出字段」，而且仍然把不可判数据算进 `total`。
- 备选 B：跳过并附 warning 字段。新增输出字段，调用方（cr-dashboard）不读它，警告等于静默。
- 备选 C：维持跳过。`total` 少算且无人知道，正是本 change 要去掉的静默。

**代价**：一个残缺目录会让整张报表失败。这是有意的数据完整性信号；真实数据 0 个，错误点名目录便于清理。

### 2. 状态集合 = `transitions[].to` ∪ `terminal`，未声明的状态硬失败（C3）

**方案**：把 `requireStateMachineTerminalForReport` 扩展为返回 `{ terminal, known }`：`known` = 状态机里所有 `transitions[].to`（字符串、非空、无首尾空白）∪ `terminal`。`transitions` 缺失、为空、或任一 `to` 不是合规字符串时，与 `terminal` 不可用同口径：`fail('REPORT_TERMINAL_UNAVAILABLE', …, { reason: 'transitions-missing-or-invalid' })`。一个 helper `assertKnownStatus(cr, status, field, path)` 在目录与 history 两处写入 `byCr` 之前各调用一次：不在 `known` 内则 `fail('SCHEMA_INVALID', …, { cr, path, field, got })`。

**为什么**：
- `transitions` 就是 `legalTransitions` 等其他命令使用的同一张表，不新增声明、不改 `dir-graph.yaml` 的结构。
- 对 history 的 `final-status` 也校验：未声明的终态值（如笔误 `archvied`）既不在 `terminal` 内，会被算成在途，是同一类缺陷；不校验会留下一半的洞。对 `_history.yml` 的重复 id、缺 `final-status` 处理不动（constraints）。
- 错误码沿用 `SCHEMA_INVALID`（非字符串 `status` 已在用），不引入新错误码。

**备选方案及排除原因**：
- 备选 A：用 `wildcards.any-active` ∪ `terminal`。需要再声明一个必需项，且 `any-active` 的语义是「通配符」而非「状态列表」；`to` 的并集已经是权威转移表的一部分。
- 备选 B：在 dir-graph 新增 `statuses:`。改了跨仓的权威结构，范围远超本 change。
- 备选 C：只校验目录来源。留下 history 的洞（见上）。

**测试夹具影响**：`makeReportToolsFixture` 的 dir-graph 只有一条 sentinel 转移，`TCRPT001–003`、`TCRPT004` 账本侧用到的 `developing` 不在其中，BUILD 阶段要在该 helper 的默认声明里补一条 `to: developing` 的转移。这是夹具补全，不改这些用例的断言；`TCRPT004` 的 `terminal` 不可用用例显式传参，不受影响。使用真实 tools 根的既有用例不受影响。

### 3. `statusHistogram` 使用无原型字典，恢复原提案承诺

**方案**：使用 `Object.create(null)` 承载直方图，JSON 输出形状不变。未声明的 `__proto__` 按决策 2 拒绝；权威声明内的动态状态键须正确计数。

**为什么**：状态集合校验负责输入有效性，字典负责存放合法键，职责不同。普通对象的原型语义不是状态配置合同；不能把合法动态键的问题解释为恶意配置。标准库的一行修改即可满足原 proposal 的不丢计数、不污染承诺，不需要补丁式禁名表。

**备选方案及排除原因**：维持普通对象并禁止保留键会新增另一张名单、缩减原承诺；新增字典类或转换层没有必要。

### 4. 已发布但本地未同步的归档：`report` 与 `status` 同口径（C4，ADJ-006 已复现）

**方案**：目录扫描时记录「仅来自目录」的 CR 集合；`_history.yml` 处理完（history 覆盖目录）之后，对仍仅来自目录、且状态不在 `terminal` 内的每个 CR 调用 `publishedArchiveStatus(ws, cr)`；返回非空则以其状态（`archived`/`rejected`/`withdrawn`）替换该 CR 的状态。其余逻辑不动，`archived`（history 里带 `archived-at` 的条目数）口径不变，所以这种 CR 计入 `total` 与直方图，不计入 `archived`。

**为什么**：这与 `resolveTerminalForQuery` 的优先级一致：history 优先，其次已确认发布的 journal 事实，最后才是本地视图。`publishedArchiveStatus` 只在 journal 记录 `pushed=true` 时返回，未发布的归档意图不算终态。只对「非终态且仅目录来源」的 CR 调用，所以真实数据（`active` 为 0）零开销，在途 CR 通常很少。`publishedArchiveStatus` 本身在 journal 不可读或仓库不可解析时返回 `null`，退回本地视图，不会让 `report` 新增失败路径。

**备选方案及排除原因**：
- 备选 A：不修，仅记录。已复现且与 b2a743a 修复的缺陷同症状，不修等于留着已知错误数字。
- 备选 B：让 `report` 逐个调用 `resolveTerminalForQuery`。会让 history 命中的 CR 再走一遍 history 解析与 backlog 冲突检查，改变 `report` 对 history 的既有处理（constraints 不允许）。

### 5. spec-dashboard 引用 `crctl report`，不复写口径（C1，ADJ-009）

**方案**：只改 `skills/spec/spec-dashboard/SKILL.md` 三处，措辞与已交付的 cr-dashboard 一致：
- 第 40 行：`**在途 CR 状态分布**（取自 \`report.statusHistogram\`，只列非终态状态；终态集合以 \`dir-graph.yaml#change-request-track.state_machine.terminal\` 为准，不在此复制）：`
- 第 56 行（表内「（终态）archived / rejected / withdrawn」一行）：删除，并在表后增加说明：`> 上表只列非终态状态；终态 CR 不属于在途，不进入上表合计。在途总数取 \`report.active\`。`
- 第 128 行：`- 若 \`report.active\` 为 0，显示「当前无在途 CR」`

`<!-- lint-prompts:ignore -->` 注释第 39、127 行是否保留，以 `lint-prompts.mjs --mode enforce` 实测为准：删后为 0 findings 则删，否则保留。第 67 行与本 change 无关，不动。

**为什么**：改前该文件让读者按目录 `cr.md` 分组、表里放终态行、用 `_backlog.yml` 判空，三者都与 `crctl report` 的口径冲突。

**备选方案及排除原因**：同时改 `spec-dashboard` 第 61、68 行的「在途 CR」措辞——这两行没有声明统计口径，不属于冲突，不动。

### 6. 登记

**方案**：`tools/CUSTOM.md`（LF 文件）已有「AIFI-45 局部修复登记（非 CR，仅为可追溯）」一节，列为 日期｜位置｜改动｜边界。BUILD 阶段先重读该节口径，再为本 change 新增一行：位置为 `crctl.mjs#cmdReport`、`skills/spec/spec-dashboard/SKILL.md` 与相关测试；边界写明「只改 report 的失败面，成功时输出字段不变；保留 history 的重复 id/缺 final-status 拒绝及覆盖优先级，不改其他命令」。不编造 CR 编号。

**备选方案及排除原因**：不登记——tools 仓对每次跨仓可追溯的修改都有该台账，漏登会让后续追溯断链。

### 7. 三组自动检查、两项人工核对

**方案**：保留全部八个 Scenario，将八个 TC 收敛为五个，不减少正反断言：
- TC-RSI-001 / CP-RSI-001：一次运行 TCRSI001..004，覆盖 SC-RSI-001..004 的状态输入矩阵。原 TC-RSI-002/003/004 并入此项，尚无执行证据，不迁移或伪造结果。
- TC-RSI-005 / CP-RSI-005：一次真实 Git 夹具检查，覆盖已发布/未发布两侧；只推测试用本地 bare remote，不推实际项目。
- TC-DWC-001 / CP-DWC-001：既有 lint 与窄内容核对，不新增 lint 规则。
- TC-RSI-006：同一真实数据快照的前后结果及既有 report 回归；固定 76/0 不作为永久测试。
- TC-RSI-007：人工核对 CUSTOM 登记，文字改为保留 history 的重复 id/缺 final-status 拒绝与覆盖优先级，而非误称 history 完全不改。

**为什么**：产品测试内部断言具体错误、CR、字段及计数；CP 只证明指定测试确实执行且全绿。使用 Node TAP 的正向测试标识与 pass/fail 计数，删除额外 Python 日志管道，避免零匹配返回 0 与管道退出码掩盖失败。

**备选方案及排除原因**：逐异常一个 CP 增加重复调用；只判退出码会空跑报绿；为此新增测试框架或通用校验器没有必要。既有项目级门禁不被取消，执行失败或未执行均如实记录，不为 report 重复运行不相关的隔离证明。

## Architecture

```text
权威状态机 -> 一次解析 terminal/known
目录 status 与 history final-status -> 同一集合校验 -> byCr（history 优先）
仅目录非终态 -> publishedArchiveStatus -> 确认发布的终态
byCr -> 无原型直方图与 active（保留 archived/period/sla 原含义）
report 输出 -> spec-dashboard 引用
```

## Risks / Trade-offs

| 风险 | 缓解措施 |
|------|----------|
| 残缺或未声明状态的目录使 `report` 整体失败 | 错误点名目录与取值；真实数据逐项回归为 0 个（TC-RSI-006）；`status` 命令对同样数据本就硬失败 |
| 状态集合由 `transitions` 推导，与 `report` 之外的命令使用同一来源，但夹具只有 sentinel 转移 | 默认夹具补一条转移；决策 2 的夹具影响说明 |
| `publishedArchiveStatus` 在 `report` 的新调用点 | 只对非终态、仅目录来源的 CR 调用；其内部已吞掉不可读情形；TC-RSI-005 覆盖「已发布」与「未发布不算完成」 |
| 修改 `report` 的错误面，下游脚本依赖退出码 | 沿用既有错误码；只把「静默跳过」变成失败，不改成功时的输出字段 |

## 与 proposal 的差异（Gate 2 一并审阅）

| 编号 | proposal 的写法 | 本设计的写法 | 原因 |
|------|----------------|-------------|------|
| D1（2026-11-16 撤回原缩减） | 不丢计数、不污染原型 | 使用无原型字典；未声明状态拒绝，合法动态键正确计数 | 校验与字典承担不同职责，恢复原承诺；对应 SC-RSI-002/003 |
| D2 | C2 默认 `SCHEMA_INVALID` 一类 | 缺 `status` 用 `CR_MD_STATUS_MISSING`（与 `status` 命令一致）；未声明用 `SCHEMA_INVALID` | 同一数据在两个命令里同一错误码 |
| D3 | C3：来源「沿用 requireStateMachineTerminalForReport 所用的 dir-graph.yaml 路径」 | 同一路径；状态集合 = `transitions[].to` ∪ `terminal`，同时校验 history 的 `final-status` | 决策 2：不校验 history 会留一半的洞；不新增声明 |
| D4 | C5：`CUSTOM.md` 登记 | 登记在 `tools/CUSTOM.md` 的「AIFI-45 局部修复登记」节，按其列格式，不编造 CR 编号 | 已核实该文件与该节存在 |

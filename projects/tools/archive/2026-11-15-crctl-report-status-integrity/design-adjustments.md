# design-adjustments — 2026-11-15-crctl-report-status-integrity

结论：**无改变受审 proposal/design/spec/test-plan 承诺的设计偏离，不触发 Gate 重审。** 实现与 Gate 2 锁定规格一致；C1 三路评审均 NON-BLOCKING，发现按下列方式处置。

## 1. 与受审规格的一致性

- 决策 1–3（`crctl.mjs#cmdReport`）：缺 status → `CR_MD_STATUS_MISSING`（无 cr.md／无 frontmatter／缺失或空串），false/0 归 `SCHEMA_INVALID`；`requireStateMachineTerminalForReport` 扩展为 `{terminal, known}`（`transitions[].to` ∪ `terminal`，transitions 不可用 → `REPORT_TERMINAL_UNAVAILABLE`/`transitions-missing-or-invalid`）；目录与 history 各经 `assertKnownStatus`；直方图 `Object.create(null)`。成功输出字段与语义不变。
- 决策 4：仅目录来源且非终态的 CR 调用 `publishedArchiveStatus`；`pushed≠true` 返回 null 退回本地视图；history 覆盖目录与 `archived`（含 archived-at）口径不变。
- 决策 5：`spec-dashboard/SKILL.md` 三处口径对齐；三处 `<!-- lint-prompts:ignore -->`（39/68/128 行）中的两处按实测删除（lint 仍 0 findings），68 行未动。
- 决策 6：`tools/CUSTOM.md`「AIFI-45 局部修复登记」新增 2026-11-16 行（LF 保持，无编造 CR 编号）。
- 决策 2 的夹具影响：`makeReportToolsFixture` 默认声明补 `to: developing`；`TCRPT001–004` 断言未改。

## 2. C1 评审处置

| 来源 | 发现 | 处置 |
|---|---|---|
| 代码（strong） | `publishedArchiveStatus` 回写状态未再经 terminal 校验（低） | **记录**：design 决策 4 明确「返回非空则以其状态替换」；真实 dir-graph 已声明三终态 |
| 代码 | `CR_MD_STATUS_MISSING` 无 `got`（低） | **记录**：SC-RSI-001 只要求 cr/path/field |
| 代码 | 函数名与返回扩展不完全匹配（低） | **记录**：design 决策 2 原文即「扩展」该函数，未改名 |
| 代码 | `periodActivity` 仍为普通对象（低） | **记录**：改前遗留，本次范围外 |
| 测试（balanced） | TCRSI002 未断言 `error.got`（中低） | **已修复**：逐样本断言取值（含数组样本实测为 `['developing']`） |
| 测试 | 夹具 `replace` 失配会静默降级（提示） | **已修复**：模块级硬失败断言 |
| 测试 | 否定路径仅断言 JSON 为 null（低） | **记录**：`fail()` 只写 stderr，JSON=null 已证「无 JSON 报表」 |
| 测试 | test-plan/tc-evidence 的 `requirement` 单值只记 REQ-RSI-001（低） | **记录**：证据计划为 Gate 2 冻结产物，不改受审字节 |
| 文档（economy） | agent spec 未机器断言表后说明句（低） | **记录**：agent spec 为 Gate 2 冻结产物；该句由 docs 评审核实存在 |
| 文档 | tasks.md 未勾选（低） | **已修复**：勾选 1.1–1.9、2.1–2.3、3.1–3.2 |
| 文档 | slices.md「SC 覆盖 7 个场景」口径（低） | **已修复**：改为「该 capability 共 7 个 SC，Slice 1 覆盖 4 个」 |
| 文档 | design/proposal 行号 5492–5565（信息） | **记录**：Gate 2 冻结文本，行号随实现增长；不改受审字节 |
| 文档 | test-plan「当前状态」仍写待 BUILD（信息） | **记录**：Gate 2 冻结快照；实际状态以本报告为准 |

## 3. 证据 run 更替

- 首次 run `668a0d47-0b3d-4ad6-bf78-602fce1199a6`：verify 3/3、confirm、ci 9/9 通过；其后 C1 测试评审要求补 `got` 断言，测试文件变更使该 run 的输入摘要不再对应当前工作树。
- 现行 run `4338f56c-a380-4ca0-b8df-b1916e0b2145`：重新 verify 3/3、confirm（同一用户原话「确认该两项人工核对」——两项人工事实未变：真实 report 计数与 CUSTOM 行均未改动）、ci 9/9。Gate 3 将绑定此 run；668a0d47 保留为历史证据，不参与绑定。

## 4. 已知限制（记录不改，均不阻塞）

- `publishedArchiveStatus` 回写状态依赖 dir-graph 将 `archived/rejected/withdrawn` 声明为 terminal（真实声明成立）；自定义根若未声明，回写状态会被计为在途。
- `periodActivity.byDay/byMonth` 为普通对象（键来自日期前 10 位，正常数据不含原型键），属改前遗留。
- 受审文档（proposal/design/spec/agent spec/test-plan）保持 Gate 2 字节未改；其内部行号与「当前状态」文字为当时快照。

## 5. 后续迭代输入

- 无（本轮无未完成的受审承诺变更）。

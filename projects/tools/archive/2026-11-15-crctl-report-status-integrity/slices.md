# 2026-11-15-crctl-report-status-integrity 切片执行计划

## Dependency Graph Summary

```
crctl-report-status-integrity (P0)
  Slice 1  状态输入矩阵         TC-RSI-001 / CP-RSI-001   [无依赖]
     └─ Slice 2  已发布未同步归档  TC-RSI-005 / CP-RSI-005   [依赖 1]

dashboard-wording-consistency (P1)
  Slice 3  看板口径对齐         TC-DWC-001 / CP-DWC-001   [无依赖]

Slice 4  人工回归与台账登记     TC-RSI-006 / TC-RSI-007      [依赖 1、2、3]
```

**并行化说明**：
- 并行组 1：Slice 1、Slice 3（均无依赖，可并行）
- 并行组 2：Slice 2（依赖 Slice 1 的 `terminal`/`known` 解析与 `assertKnownStatus` 落点）
- 并行组 3：Slice 4（依赖三处实现完成后的真实数据与登记核对）

## Slice Execution Plan

| # | 优先级 | 风险 | 预估工时 | 并行组 | TC 覆盖 | 实现目标 | 依赖 |
|---|--------|------|---------|--------|---------|---------|------|
| 1 | P0 | 🟡 Med | M | 组1 | TC-RSI-001（CP-RSI-001） | `crctl.mjs#cmdReport`：缺 status 硬失败、`known` 集合校验、无原型直方图；夹具补 `to: developing` | 无 |
| 2 | P0 | 🟡 Med | M | 组2 | TC-RSI-005（CP-RSI-005） | `cmdReport`：仅目录非终态 CR 走 `publishedArchiveStatus` 兜底 | 1 |
| 3 | P1 | 🟢 Low | S | 组1 | TC-DWC-001（CP-DWC-001） | `spec-dashboard/SKILL.md` 三处口径对齐 + 既有 lint | 无 |
| 4 | P1 | 🟢 Low | S | 组3 | TC-RSI-006、TC-RSI-007（均 manual） | 真实数据回归事实 + `tools/CUSTOM.md` 登记 | 1、2、3 |

## Rationale

### Slice 1：状态输入矩阵（P0，先行）
- **依赖关系**：无；但其 `terminal`/`known` 解析与 `assertKnownStatus` 是 Slice 2 的前置，故必须先做。
- **风险分析**：该 capability 共 7 个 SC（>5，+1；Slice 1 自身覆盖 SC-RSI-001..004 四个）；跨模块（目录扫描、history、状态机解析、直方图，+1）；错误面变更（静默跳过→硬失败，+1）；基线 1 → 风险分 4（🟡）。经验库 5 条均为 `discovered`（无 verified/settled 可注入），其中两条提示与设计已一致：带引号 glob 交给 `node --test` 会 0 用例且退出 0（本 change 用显式文件路径 + 测试标识断言），命令型 CP 判定面窄于 spec（CP 已含 TAP 计数与具体标识）。
- **工作量估算**：M——一个生产文件（`crctl.mjs`）+ 一个测试文件（`crctl.test.mjs`）+ 夹具默认声明 1 行；单个 TC 内含四个顶层测试。

### Slice 2：已发布未同步归档（P0，依赖 1）
- **依赖关系**：需要 Slice 1 产出的终态集合与状态写入点，才能只对「仅目录来源且非终态」的 CR 调用 `publishedArchiveStatus`。
- **风险分析**：新增一个调用点（🟡）；`publishedArchiveStatus` 自身吞掉不可读情形，不新增失败路径；已发布/未发布两侧成对覆盖。
- **工作量估算**：M——生产逻辑约 10 行内 + `archive-tx.test.mjs` 一个顶层测试（复用 `makeWritebackFixture`）。

### Slice 3：看板口径对齐（P1，可并行）
- **依赖关系**：无；文档与 Slice 1/2 无代码耦合。
- **风险分析**：单文件三处措辞 + 既有 lint，风险分 1（🟢）；改前 `bad` 三项是现成红样本。
- **工作量估算**：S。

### Slice 4：人工回归与登记（P1，收口）
- **依赖关系**：真实数据回归需要最终代码；登记行需列出最终位置与边界。
- **风险分析**：基线对比不做成永久 CP（新增 CR 会让固定数字过期）；两项 required manual 由用户原话确认，AI 不代签。
- **工作量估算**：S。

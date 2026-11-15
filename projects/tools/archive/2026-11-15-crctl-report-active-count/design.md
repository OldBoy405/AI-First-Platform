# Design — crctl report 在途数口径修正

> 版本：1.1（lightweight；修订：补齐 Context／Architecture／Risks，订正 D1／D2／D3／D5 的表述）
> 创建日期：2026-11-15
> 对应 proposal：`canonical/proposals/2026-11-15-crctl-report-active-count.yaml`

## 一、Context

`crctl archive` 归档 CR 时**不删除** `change-requests/<CR>/`，而是改写其 `cr.md` 的 `status` 并追加 `_history.yml` 条目。
旧 `cmdReport` 把「目录里每个 `cr.md`」都计入 `active`，把「history 每个条目」都计入直方图，两处都不去重、都不看终态。
结果：已归档的 CR 被算成在途，同一个 CR 在 `active` 与历史计数里各记一次，`total` 也随之翻倍。

知识库主 checkout 的实测：目录 76 个、`_history.yml` 76 条且 76/76 重合，frontmatter 为 68 archived + 8 withdrawn。
旧实现输出 `total 152 / active 76 / 直方图 {archived:136, withdrawn:16}`；真实在途为 0。
两份看板技能直接消费该输出，因此错误数字没有提示地变成“在途工作量”。

## 二、D1 去重键与状态优先级

`cmdReport` 改为按 **CR 编号** 建一次集合：目录里读到的 id 与 `_history.yml` 的 `id` 合并去重，每个 id 只进直方图一次。

状态取值优先级：**history 的 `final-status` 优先，其次目录 `cr.md` 的 frontmatter `status`**。
方向与既有 `resolveTerminalForQuery`（`crctl status` 的终态判定）一致，但**不等价**：`report` 会回退目录 frontmatter，且不读已发布归档 journal（ADJ-006）。

**不可判的数据一律硬失败，不猜、不降级**（与仓库「解析失败必须硬失败」的纪律一致；旧实现的 `String(final-status || 'archived')` 会把缺失/空串/`false` 都伪装成 `archived`）：

| 数据形态 | 处置 |
|----------|------|
| `_history.yml` 顶层不是数组且无 `history` 数组 | `LEDGER_PARSE_FAILED`（带 `path`、`gotType`） |
| history 条目不是对象、`id` 不是非空字符串 | `LEDGER_PARSE_FAILED`（带 `path`、`index`、`field`） |
| 同一 `id` 在 history 出现多次 | `HISTORY_DUPLICATE_ENTRY`（复用 `findHistoryEntry` 的既有错误码，带 `id`） |
| history 条目缺 `final-status` 或其值非非空字符串 | `HISTORY_FINAL_STATUS_MISSING`（复用既有错误码，带 `id`；不再默认 `archived`） |
| 目录 `cr.md` 的 `status` 非非空字符串或带首尾空白 | `SCHEMA_INVALID`（带 `cr`、`path`、`got`） |

`_history.yml` 文件不存在仍按空历史处理（基线行为不变）。

## 三、D2 终态集合来源

新增 `requireStateMachineTerminalForReport(ws)`：经 `resolveToolsRoot(ws)` 读 tools 包 `dir-graph.yaml`，取 `change-request-track.state_machine.terminal`。

- 失败时统一 `fail('REPORT_TERMINAL_UNAVAILABLE', …)`；`extra` 带 `toolsRoot`、`field`、`reason`，仅当值非法时附 `got`（原值，不做类型推断）。
- `reason` 三种：`dir-graph-unparseable`（YAML 解析失败）、`terminal-missing-or-invalid`（缺声明／非数组／空数组／含非字符串或首尾空白项）；缺 `dir-graph.yaml` 的情形由 `resolveToolsRoot` 先以 `TOOLS_PACKAGE_NOT_FOUND` 失败，本 helper 不再重复分支。
- 不内建终态枚举副本，不回退空集合。

既有 `readStateMachineTerminal`（返回 `null` 或 `string[]`，供 `owner-source-scan` 的非阻塞维度用）**不改**：那是“不可判就不判”的只读维度，语义不同，合并会让它变成硬失败。

## 四、D3 输出字段

```
total            = 不同 CR 编号数（目录 ∪ history）；含没有 archived-at 的 history 条目
active           = 去重后状态不在终态集合内的 CR 数（number，不输出逐条列表）
archived         = `_history.yml` 中带 archived-at 的条目数（重复 id 已在 D1 拒绝，故等于按 CR 计数）
statusHistogram  = 去重后每个 CR 的生效状态计数（含终态键；各状态之和 = total）
period / periodActivity / sla = 不变
```

`active` 始终是计数：旧实现内部构造过 `{cr, status, created}` 数组但只取 `.length`，新实现直接累加计数，不再构造该数组（此前的 1.0 版本文档误称输出含 `active[]`，见 ADJ-001）。

`archived` 与 `statusHistogram.archived` 天然不等——前者是带 `archived-at` 的条目数（含 withdrawn 等终态），后者只数状态恰为 `archived` 的 CR。`total` 的新定义（并集大小）是本次唯一的输出口径扩展：旧版不计没有 `archived-at` 的 history 条目（ADJ-004）。

## 五、D4 文档同步

`skills/cr/cr-dashboard/SKILL.md` Step 2 的口径段与表下注解：`active` 只含非终态、重复登记不重复计数且以 `final-status` 为准、终态枚举以 `dir-graph.yaml#change-request-track.state_machine.terminal` 为权威（不复制枚举）。

## 六、D5 影响面

仓内 grep 到的 `crctl report` 消费者：
- `skills/cr/cr-dashboard/SKILL.md`（本次已改）。
- `skills/spec/spec-dashboard/SKILL.md`：**仍保留旧口径文字**（按 `cr.md` frontmatter 分组、表内含终态行）。本次不改，列为已知不一致（ADJ-009），待后续 change 处理。
- `docs/二开修改报告_v2.html`、`delivery/task/*`、`docs/analysis/done/*`（知识库）为历史记录，不回改。

## 七、Architecture（数据流）

```
change-requests/<CR>/cr.md  ──readCrMdFrontmatter──┐
                                                   ├─► byCr: Map<crId, status>   （history 覆盖目录）
change-requests/_history.yml ──parseYaml──────────┘        │
                                                           ├─► statusHistogram[status]++（含终态）
dir-graph.yaml # state_machine.terminal ──► terminalSet ───┴─► active = Σ status ∉ terminalSet
_history.yml 的 archived-at ──► archivedIds: Set<crId> ──► archived = |archivedIds|
```

失败面只有一处：`requireStateMachineTerminalForReport` 在聚合开始前执行，失败即不输出报表。

## 八、Risks

| 风险 | 影响 | 缓解 |
|------|------|------|
| 其他调用方依赖旧的重复计数口径 | 数字变化 | 全仓 grep：只有两份看板技能的文字；`spec-dashboard` 未同步，已登记 ADJ-009 |
| 无 `terminal` 声明的工作区由“出数”变“报错” | 看板不可用 | 错误码与 `reason` 指明缺失字段；`dir-graph.yaml` 是 tools 包身份文件，缺声明即配置错误 |
| `spec-dashboard` 仍指导旧口径渲染 | 两个技能说法冲突 | 列为已知不一致（ADJ-009），Gate 3 明示 |
| 既有两条 `report` 用例改用真实 tools 包后隐含依赖 `terminal` | 真实包缺声明时旧用例也红 | 已在 `test-plan.md` §1.3 注明该耦合 |
| TC-RPT-006 断言活数据 | 知识库新开在途 CR 时 CP 失败 | `active=0` 标注为当日快照；`total` 与直方图恒等式为真断言 |

## 九、回滚

- 改动只有 `crctl.mjs`、`crctl.test.mjs`、`cr-dashboard/SKILL.md` 三个文件，无数据迁移、无状态文件变更。
- 交付时**必须单独成一个提交**（不得与工作树里既有的 `merge-effects.mjs`、其测试与 golden、`CUSTOM.md`、`.crctl/` 混同），否则“单提交 revert”不成立。

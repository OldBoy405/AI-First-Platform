# SPEC 审查记录 — 2026-11-06-stdd-default-cr-opt-in

> 本记录是阶段审阅说明，不是原生 TC 执行证据、CR review-record 或 Gate 批准。
> 2026-11-15 随受审文档整体重写而重写；此前十个 CP／TC 版本的审查记录只在 git 历史中。

## 本轮实际执行的检查（2026-11-15，tools 业务根，只读）

| 检查 | 结果 | 覆盖边界 |
|---|---|---|
| `stdd validate <本ID>` | 通过 | 结构；TC 定义 4 个、Scenario 4 个，满足“TC 不少于 Scenario” |
| `stdd proposal validate <本ID>` | 通过 | 提案 YAML；提案本轮未修改 |
| `stdd canon verify <本ID>` | 2/2 通过 | 仅 proposal 的哈希与正文 |
| `stdd agent verify prompt-governance --change <本ID> --dry-run` | 列出 CP-PG-001、CP-PG-002，计划被接受 | 只证明计划可解析、检查点可定位，没有执行 action |
| 直接以 `shell=True`、tools 根为 cwd 运行 CP-PG-001 的 action（与 runner 相同方式） | 退出 0，输出 `CP-PG-001 PASS` 和五个哈希 | 预跑，不是证据；在当前工作副本上通过 |
| `contract-scan.test.mjs` 预跑 | 44/44 通过 | 预跑，不是证据 |
| `stdd gate status <本ID>` | 当时：Gate 1、2 为 historical/unfingerprinted，Gate 3 pending（2026-11-15 10:27 已重签，见 `.stdd.yaml` 与 tasks 0.2） | 当时须重签后才能证明当前有效 |

## 审阅结论与边界

- 这一轮修订由主会话完成，没有做独立的多路评审；独立评审安排在 BUILD 的 C1，以及 TC-WFR-001 的盲评。
- 设计变化：十个 CP／TC 缩减为四个检查，各对应一条保证；删除字符串断言、字符量上限与并行替代预期；补入 tools `AGENTS.md` CR 驳回段的修订、交付归属，以及知识库顶层文件无法被 CLI 冻结这一事实。
- 当时（重签前）：受审文档字节已变化，须用户审阅后重签 Gate 1、2；该重签已于 2026-11-15 10:27 完成（tasks 0.2）。
- 当时未做：真实 evidence run、人工确认、C1 评审、Gate 3，也没有修改任何业务文件、全局文件或 `.stdd.yaml`；其后的进展见 tasks、phase-context 与 ADJ-003。

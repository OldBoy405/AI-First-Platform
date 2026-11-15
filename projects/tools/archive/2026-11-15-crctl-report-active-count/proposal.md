# crctl report 的在途数不含终态且不重复计数

<!-- source_hash: d020b157d860b3be -->
<!-- generated_at: 2026-11-15T11:30:18.785260 -->
<!-- canonical: canonical/proposals/2026-11-15-crctl-report-active-count.yaml -->

## Why

`crctl report --workspace .` 在知识库主 checkout 返回 `total: 152, active: 76, archived: 76`，
`statusHistogram` 为 `archived: 136, withdrawn: 16`。实测该工作区 `change-requests/` 下 76 个 CR 目录
全部同时登记在 `_history.yml`（重合 76/76），frontmatter 为 68 个 archived、8 个 withdrawn，
即实际在途为 0。源码 `cmdReport` 把每个 CR 目录都计入 `active`，不看状态是否终态；又把同一 CR 的
history 条目再计一次，导致 `total` 与直方图都是真实值的两倍。`cr-dashboard` 与 `spec-dashboard`
都以该命令的输出作为看板数据源，「在途 CR」会显示 76。


## What Changes

- `crctl report` 的 `active` 只统计非终态 CR；`total`、`statusHistogram` 按 CR 编号去重，每个 CR 只计一次
- 终态集合取自 tools 包 `dir-graph.yaml#change-request-track.state_machine.terminal`，不内建副本；无法取得时命令硬失败，不猜
- `cr-dashboard` 技能中对 `crctl report` 输出口径的文字描述同步为新口径

### Modified Capabilities

- **crctl-report**：跨 CR 状态直方图/在途数/归档数聚合（只读）的统计口径

## Success Criteria

- [ ] 在含 N 个同时存在于目录与 `_history.yml` 的终态 CR 的夹具上，`active=0`，`total=N`，`statusHistogram` 各状态之和为 N
- [ ] 夹具含非终态目录 CR、仅在 history 中的 CR、仅在目录中且 frontmatter 为终态的 CR 时，`active` 只含非终态目录 CR，`total` 为不同编号数
- [ ] 从 tools 包取不到终态集合时，命令以非零退出并输出错误码，不输出报表
- [ ] 既有 `report` 与 `report --period` 测试在不改断言的前提下继续通过
- [ ] `crctl report --workspace` 对知识库主 checkout 输出 `active=0`、`total=76`
- [ ] `cr-dashboard` 技能文字不再把终态 CR 列在「在途」口径内

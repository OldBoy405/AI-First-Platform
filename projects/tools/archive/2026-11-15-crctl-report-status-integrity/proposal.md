# crctl report 不再静默丢弃或污染状态计数，并让 spec-dashboard 引用 report 口径

<!-- source_hash: 1bc39dac9645eba3 -->
<!-- generated_at: 2026-11-16T00:19:58.665495 -->
<!-- canonical: canonical/proposals/2026-11-15-crctl-report-status-integrity.yaml -->

## Why

上一个 change（2026-11-15-crctl-report-active-count，已交付 b2a743a）修好了 `crctl report` 的终态计数，并把 4 条邻近问题登记为未做：
ADJ-009：`skills/spec/spec-dashboard/SKILL.md` 第 40、56、128 行仍按「cr.md frontmatter 分组、表内含终态行」描述在途 CR 口径，与 `crctl report` 的口径（终态排除、每个 CR 只计一次）冲突；两个看板技能对同一命令说法不一致。
ADJ-011：`cmdReport`（crctl.mjs 约 5492–5565 行）遇到 cr.md 缺 `status` 的目录静默跳过（`if (!md || !md.status) continue`）；同一函数对「status 非字符串或带首尾空白」却硬失败，两处对「不可判的数据」的处理不一致。直方图 `statusHistogram` 用普通对象承载动态键，状态名为 `__proto__` 时会丢计数。
ADJ-007：status 值不做枚举校验，非法状态原样成为直方图的键。
ADJ-006：`report` 不读已发布归档 journal 兜底（`publishedArchiveStatus`），而 `crctl status` 读。现有 design.md 记录了已发布但本地未同步时 report 仍计 active 的复现；BUILD 须固化为已发布/未发布成对回归，不以文字记录代替执行证据。
2026-11-15 记录的真实数据基线为 76 个 CR、缺可用 status 为 0；实施前重新取同一数据快照的基线，不能把历史核对视为当前完整性证明。


## What Changes

- spec-dashboard/SKILL.md 第 40、56、128 行改为引用 `crctl report` 的输出与口径，不再自己复写分组与终态行的统计规则；与 cr-dashboard 的口径描述保持一致。
- cmdReport：每个 CR 目录要么计入 total 与直方图，要么使命令硬失败并指出目录；缺 `status` 与『非字符串、带空白』按同一条规则处理（默认选硬失败，与同函数内其余『不可判数据』一致；SPEC 阶段在 design 中给出理由与替代方案）。
- cmdReport：目录与 history 的状态均须来自权威状态机声明；未声明值点名失败，声明内的动态状态键正确计数且不受对象原型影响。具体状态读取与直方图承载方案留在 design.md。
- ADJ-006 先复现：构造「本地主 checkout 未同步已发布归档、journal 里已有终态」的场景，对比 report 与 status 的结果。复现并确属缺陷则本 change 内按同一口径修复；复现不了则在 design-adjustments.md 写明结论，不改代码。
- CUSTOM.md 登记本 change 对 tools 的修改。

### Modified Capabilities

- **crctl-report-status-integrity**：report 的 total、active、statusHistogram 对每个 CR 目录都有确定的归属：计入，或明确失败；不再静默跳过、不再被状态名污染。
- **dashboard-wording-consistency**：spec-dashboard 对在途 CR 口径的描述引用 crctl report，不独立复写。

## Success Criteria

- [ ] cr.md 缺 status 的目录使 `crctl report` 失败并指出该目录；不再静默计 0。
- [ ] 状态机未声明的 status 值使 `crctl report` 失败并指出该 CR；声明内的状态不受影响。
- [ ] 未声明的 `__proto__` 与其他非法状态一样被拒绝；权威声明内的动态状态键正确计数，不发生原型继承或污染。
- [ ] 在真实 change-requests/ 数据上，`crctl report` 结果与改前一致（total、active、archived、statusHistogram 逐项相同）。
- [ ] spec-dashboard/SKILL.md 不再包含与 `crctl report` 冲突的口径描述，并引用 `crctl report`。
- [ ] ADJ-006 有结论：复现并修复，或写明无法复现及依据，二者之一落入 design-adjustments.md。

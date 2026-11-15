# controlled-shell 白名单放宽 test-facts / 快照所需的 3 种 git show 只读形状

<!-- source_hash: 06076d3f19c01d4c -->
<!-- generated_at: 2026-11-15T17:26:04.423720 -->
<!-- canonical: canonical/proposals/2026-11-15-controlled-shell-snapshot-read-shapes.yaml -->

## Why

multica 的 daemon 在 CR 终态 settle 与测试事实采集时，以 system-orchestrator 身份对一个 40 位提交读取三类对象：
`git show --name-only --format= <40hex>`、`git show <40hex>:change-requests/CR-…/test-report.md`、`git show <40hex>:change-requests/CR-…/trace.tests[.yml|.yaml|.json]`。
tools 的 `skills/shared/controlled-shell/rules.json` 中 `git[sub=show]` 只放行两种形状（review-annotations/*.yml，以及 _backlog / _history / cr.md），上述三种被 guard 拒绝。
CUSTOM-TODO-017 声称「rules.json 已补」这三种形状，但 `git log --all -S'trace\.tests' -- skills/shared/controlled-shell/rules.json` 为空，与代码不符；这是跨仓契约缺口（multica 的 fork-ci-test-evidence-trust 的 ADJ-005，major，移交后续 change，至今未决）。
2026-11-15 实测（multica server/internal/daemon，MULTICA_CONTROLLED_SHELL_RULES 指向 tools 的真实 rules.json）：
6 个测试失败——TestProposedSnapshotReadShapes、TestM26B2TestFactsPayload、TestM26B2TestFactsPreserveFailures、TestM26B4CollectorKeepsBothReviewStages、TestM26B4ScanEmitsIndependentTestEvent、TestM26B4ScanTestOnlyAndReviewOnly；
不指向 rules.json（回落到测试内联 fixture）时 6 个全部通过，因此 CI 里它们的失败被 fixture 回落掩盖。
把三种形状加进 show 后（临时副本，未提交），同样 6 个测试全部通过。


## What Changes

- controlled-shell/rules.json 的 git[sub=show].shapes 增加三条：`^--name-only --format= [0-9a-f]{40}$`、`^[0-9a-f]{40}:change-requests/<CR-ID>/test-report\.md$`、`^[0-9a-f]{40}:change-requests/<CR-ID>/trace\.tests(?:\.yml|\.yaml|\.json)?$`；callers 仍仅 system-orchestrator，原两条形状不变。
- 新增 1 个 tools 测试：加载真实 rules.json，对 show 形状做允许/拒绝对照表——3 种新形状及原两种形状的正例必须放行，multica 已固化的 11 种近似形状（简写 sha、HEAD、路径穿越、非批准文件、小写或过长 KEY、后缀松弛等）必须拒绝。
- controlled-shell/SKILL.md 的 show 形状说明与 rules.json 同步。
- CUSTOM.md 的 CUSTOM-TODO-017 描述改为与代码一致，并登记本 change 的提交。

### Modified Capabilities

- **controlled-shell-git-show-shapes**：system-orchestrator 可对 40 位提交读取 test-facts 发现、test-report.md、trace.tests* 三类只读对象；不放行其他对象、简写 sha、分支名、路径穿越。

## Success Criteria

- [ ] rules.json 的 show 形状放行 3 种新形状及原 2 种形状，callers 仍仅 system-orchestrator；对照表测试中所有正例通过。
- [ ] 对照表测试中 11 种近似形状全部被拒绝。
- [ ] rules.json 相对改前只有 git[sub=show].shapes 一处变化（diff 复核，写入 test-report）。
- [ ] multica 的 6 个测试（TestProposedSnapshotReadShapes 等）在 MULTICA_CONTROLLED_SHELL_RULES 指向本仓 rules.json 时全部通过（跨仓一次性验证，写入 test-report）。
- [ ] controlled-shell/SKILL.md 与 CUSTOM-TODO-017 的描述与 rules.json 一致。

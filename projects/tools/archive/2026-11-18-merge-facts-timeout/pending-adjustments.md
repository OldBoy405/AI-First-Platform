# 待处理验证计划修订

- **原承诺**：Gate 2 锁定的 `test-plan.md`、`CP-MFT-001` 验证原 13 项；`design.md` 复用已有挂起和响应分类断言。
- **新发现**：现有 13 项在 Linux Node 20 可区分 RED/GREEN，但 Windows Node 24 的 runner 在未修版也全绿。BUILD B3.4 要求实现切片有新增测试。
- **修订**：按用户「按这个方向修订」同步 `design.md`、`test-plan.md` 与 `canonical/specs/agent/merge-facts-timeout.yaml`。把原挂起断言移入一个直启 Node 子进程的用例，不给子进程加保活任务；原用例名称与响应分类保留。计划总数 14；proposal 和行为 Spec 不变。
- **状态**：2026-11-19 00:10:24 以用户原文「确认修订后的 Gate 2」重签，旧批准回执保留。新用例已实现并验证 RED/GREEN，Linux 最终组合复验通过；生产修复不变。分阶段实测及质量终态见 `test-report.md`。

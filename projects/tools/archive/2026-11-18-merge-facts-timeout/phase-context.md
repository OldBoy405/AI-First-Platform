# merge-facts 超时 — 阶段上下文

## SPEC

- Gate 1：用户「确认独立轻量变更的 Gate 1」。Gate 2 与连续执行授权：用户「确认 Gate 2，按上述范围连续执行 BUILD」。
- 规格约束：只有现有定时器保活行为变化；超时结果、正常响应、授权和写入边界不变。已锁定 `design.md`、行为规格、Agent CP 和 `test-plan.md`；证据计划预检通过。
- BUILD 授权限本变更代码和记录、离线本机与已有 WSL 环境、一次性组合测试及必要只读 Git。不得修改受审承诺、访问外网、安装、提交、推送或部署。Gate 3 单独确认。

## BUILD

- 实现工作副本：`../tools-merge-facts-timeout`，从 Tools HEAD `6dacbaf64db69d57fe70c935c0dd640ef00e086d` detached 检出，复用已核实 `tools` 项目绑定。原 `../tools` 精简工作树不写入。组合仅在一次性 Linux 快照运行。
- 轻量模式使用一个隐式切片；复用能产出 RED 的现有 13 项模块回归，不新增等价测试。干净 HEAD Linux Node 20 确为 8 通过、5 取消；应用修复后 13 通过、0 取消，Windows 同次 run `mft-20261118-2332` CP/TC 各 1/1。经验 `EXP-2026-0009`。
- 组合快照 Linux suite-gate exit 0 / pass（100 文件、2247 顶层用例），writeback 24/24。两补丁保持分离，原工作树字节未变；已清理 Linux 临时目录。
- 用户「确认修订后的 Gate 2」已以 `--reapprove` 重签；保留原回执。裸子进程新用例在 Windows 未修基线退出 13（RED），修复后自然退出 0 且断言确切超时结果；`mft-r2-20261119` 模块 14/14、CP/TC 各 1/1。
- 最终 Linux Node20 两补丁组合 suite-gate 100/100 文件、2248 顶层、2319 通过/0 失败/0 取消/2 跳过；Windows Node24 `quality.test` 2428 通过/0 失败/0 取消/1 POSIX 跳过。writeback、lint、合同/矩阵输入不变，复用旧结果。S1 已由 CLI 登记 `1/1` TC、新增 1 测试；未选 Gate 3 run，未集成或提交。详见 test-report.md 和 design-adjustments.md。

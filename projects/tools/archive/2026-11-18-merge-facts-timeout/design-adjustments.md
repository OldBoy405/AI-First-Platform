# merge-facts 超时 — 设计调整

## 实现与受审方案

无生产设计调整。仅删除 `fetchMergeFacts` 的 `timer.unref()`；超时阈值、错误分类、`finally` 清理、授权和写入均未改。独立实现副本与原精简补丁只在临时 Linux 全量测试中组合。

## 已实施的验证计划修订

现有 13 项确实复现并证明 Linux Node 20 根因修复，但实现切片按 `stdd-build` B3.4 必须含实际新增测试，且 Windows Node 24 的 Node test runner 在未修复版本上已有全绿记录。不能把零新增登记为完成。将现有“挂起请求”断言移至一个不经 test runner 包裹的 Node 子进程测试，保留同文件其他分类断言及原测试名称，验证自然退出 0 和具体 `MERGE_FACTS_UNAVAILABLE` 超时结果；不加保活任务、不重复旧断言。已按用户确认的方向同步 `design.md`、`test-plan.md` 与 Agent CP：13→14 项。业务承诺及行为 Spec 不变。Gate 2 重签后只改该测试文件：干净源码下裸子进程退出 13，修复后自然退出 0 并返回确切超时结果；模块 14/14，见测试报告。

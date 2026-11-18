# merge-facts 超时 — BUILD 验证报告

- 基线：Tools `6dacbaf64db69d57fe70c935c0dd640ef00e086d`；实现位于 `../tools-merge-facts-timeout` 的独立 detached worktree，只删除 `skills/shared/crctl/scripts/lib/merge-facts.mjs` 的 `unref()` 一行。原精简工作树补丁字节未变。
- Gate 3 拟选 run：[`mft-r2-20261119`](validation/runs/mft-r2-20261119/tc-evidence.json)，Windows Node 24.15.0 CP 1/1、必需 TC 1/1，输入已冻结。初版 [`mft-20261118-2332`](validation/runs/mft-20261118-2332/tc-evidence.json) 为历史 13 项结果。Linux 对照和全量均为独立证据。

## 实测结果

| 验证 | 实测 | 结论 |
|---|---|---|
| Linux Node 20，干净 HEAD，`merge-facts.test.mjs` | exit 1；8 通过、0 断言失败、5 取消、0 跳过 | RED：首个取消为无额外活跃任务的挂起请求；[基线记录](../2026-11-18-defensive-trim-tools/test-report.md#十一linux-node-20-最终复验)见原精简报告第十一节 |
| Linux Node 20，只应用本修复，同文件 | exit 0；13 通过、0 失败、0 取消、0 跳过；0.138 秒 | GREEN：现有超时与响应分类全部兑现 |
| Linux Node 20，两补丁临时组合，`suite-gate` | exit 0、`pass`；100/100 文件、2247 个顶层案例；TAP 2318 通过、0 失败、0 取消、2 跳过；278.021 秒 | 100 个子进程均 exit 0；真实受限身份 12/12；merge-facts 13/13。既有 2 项平台条件跳过依赖 Windows 文件系统/真实 junction，未新增跳过或例外 |
| Linux Node 20，同一组合，writeback | exit 0；24/24、无跳过；2.805 秒 | 如实保留原跨秒 replay 的已知基线风险，本次未触发 |
| Windows 配置项 `quality.lint`、`quality.typecheck` | lint 0 findings；Agent 合同、Skill 矩阵均 exit 0 | 通过；独立变更修订前未重跑 `quality.test` 的 Windows 全套，不把 Linux suite-gate 写作该命令结果 |

Linux 使用已有 AIFI-ISO、Node v20.20.2、Git 2.56.0 标准模板、`1500:1500` 和 `1501:1501` 两个真实身份，隔离网络命名空间仅 loopback；不是托管 CI 实测。临时快照已清理。原始日志在 `%TEMP%/dt-regress/`：`node20-linux-baseline-merge-facts.txt`、`mft-linux-execution.txt`、`mft-linux-green.txt`、`mft-linux-gate.{ndjson,json}`、`mft-linux-writeback.txt`。组合身份为原补丁 SHA-256 `e29d2d2a3849c97bdc3bf764a33d46d4d04eee2f8795ab200c268c889a34933c` 与本补丁 `1839055f08e6f1fcdf6dd504447227bd842cd7656d8dc88231c0c430165a62f1`，NDJSON SHA-256 `e7304e7fe23a282676135ec28e167b257179d9acab4cc12649a1df0cddbf5d40`。

初版覆盖：`SC-MFT-001` 由现有挂起 `fetchImpl` → `TC-MFT-001` → `CP-MFT-001` 覆盖，关键行为另由 Linux RED/GREEN 区分；`SC-MFT-002` 同 TC/CP 验证响应分类。行覆盖率按证据计划 `not_applicable`（项目覆盖率验证仅支持 pytest-cov，不是测得的行覆盖率）。E2E 未启用。无第三轮修复。

## 三路评审与处置

| 评审 | Configured / Requested（相同） | Actual | 发现与处置 |
|---|---|---|---|
| code | `OpenAIPersonal/gpt-6.2-sol:high` | unknown | 无实质发现；主会话核对完整生产 diff、请求与 `finally` |
| test_config | `GB-JP/qwen4-max:xhigh` | unknown | 中：Windows runner 的通过不能单独区分回归；补已批准的 Linux 基线/修复对照，见上表。低：临时 Windows TAP 不足以证明退出码/输入绑定；改用正式同次记录，临时 TAP 不作签核证据 |
| docs_skills | `Gobao/deepseek-flash:high` | unknown | 低：RED 应可定位；已在上表补指针。低：轻量与显式设计产物并存；批准 CLI 自动渲染 Human View，不改 mode、不删受审产物。交付批次未选择，本轮不推进交付 |
| test_config（仅新增测试） | `Gobao/qwen4-max:xhigh` | unknown | SC→TC→CP→实测链路及裸进程、退出码、超时结果、原分类和名称均核对，无阻断发现。低：同步子进程无测试侧 timeout，若出现相反方向的永久挂起，独立 CP 可卡住；不在本次修复范围内，不额外添加 watchdog：proposal 成功标准要求现有超时兑现，本次已通过未修 RED 和修复 GREEN 验证；Linux suite-gate 有现有全局 watchdog。该风险不改变业务运行时行为 |

## C4 失败模式核查（`mft-r2-20261119`）

CLI 8 pass、0 warn、0 fail、1 skip（单 capability 契约）；以下人工核查针对最终生产代码与新测试，结合修订后的同次 run、Windows 和 Linux 实测。

| 项 | 实测/核查 |
|---|---|
| (a) 幻觉 | CI 必需文件/Spec 通过；Linux exit、TAP 与摘要逐项核对 |
| (b) 范围蔓延 | 最终两个补丁 SHA 不变；生产修复 1 行，测试将原断言移至一个新用例，无新兜底或门禁 |
| (c) 级联错误 | RED 首个挂起取消后还有 4 个取消，修复后 5 个全部执行；`finally` 保留 |
| (d) 上下文丢失 | TC ID 唯一；规范、代码和测试仍保留授权与分类边界 |
| (e) 工具误用 | 同次 run 明示，标准 `--reapprove` 保留旧回执；Linux 启动命令由无 MSYS 路径转换的子进程传参，未把未启动的命令计测试 |
| (f) 运行偏差 | SHALL 核查通过；Linux 干净基线和同输入 GREEN 可区分；入经验 `EXP-2026-0009` |
| (g) 流程断链 | AND 校验通过；实现切片 S1 已通过并以 `tc_coverage=1/1`、`new_tests=1` 经 CLI 登记 |
| (h) 内容质量 | Canonical 哈希、正文、项目索引均通过；报告区分 Windows 同次和 Linux 组合 |
| (i) 指令衰减 | 未联网/安装/提交/推送/部署；两处工作树隔离；Gate 1 保持当前，Gate 2 按用户确认重签 |
| (j) 覆盖真空 | 必需 TC 1/1，测试不空跑，不把 `not_applicable` 当作行覆盖 |
| (k) 契约断层 | 单 capability，CLI 不适用；人工核对输出和分类调用合同没有改动 |
| (l) 锚定缺失 | CI 判定非 critical，不要求锚定 |
| (m) CP 失败 | 修订后同次 CP 退出 0、14 通过、0 失败/取消/跳过；新用例在 Windows 同机未修源码 RED，修复后 GREEN，Linux 独立复验 14/14 |
| (n) 跨系统不一致 | 基线取消与 Windows runner 表现可同时成立；Linux 门禁在组合补丁通过，不等于原工作树已集成 |

## 修订后的实测（2026-11-19）

初版 13 项是历史证据。修订后，独立 worktree 的生产差异仍只有那一行；`merge-facts.test.mjs` 将原挂起断言移至一个裸 Node 子进程用例，未改原名称或响应分类。原三路评审复用：生产和流程边界未变；对新增测试再做一次定向 test_config 补审，详见上表。Windows 假绿已由下面的同环境 RED/GREEN 消除，旧临时 TAP 不作为签核证据；主会话核对修订后 `SC-MFT-001/002 → TC-MFT-001 → CP-MFT-001`。

| 验证 | 结果 |
|---|---|
| Windows Node v24.15.0 / `SC-MFT-001` RED | 同一份新测试、干净 HEAD 源码，裸子进程因未决顶层 await 实际退出 13；外层测试 exit 1、1 失败。临时副本已清理 |
| Windows Node v24.15.0 / `SC-MFT-001` + `SC-MFT-002` GREEN | [`mft-r2-20261119`](validation/runs/mft-r2-20261119/tc-evidence.json)：模块 14/14，0 失败、0 取消、0 跳过；CP 1/1、必需 TC 1/1。新用例要求子进程自然退出 0，精确核对 `MERGE_FACTS_UNAVAILABLE` 与 `timeout after 20ms`；正常和错误响应在原断言中验收 |
| Linux Node v20.20.2 / 最终组合 `suite-gate` | exit 0 / `pass`；100/100 文件、2248 个顶层案例；TAP 2319 通过、0 失败、0 取消、2 个既有平台跳过；399.001 秒。`merge-facts` 14/14、真实受限身份 12/12。临时快照已清理 |
| Windows Node v24.15.0 配置 `quality.test` | exit 0；2428 通过、0 失败、0 取消、1 跳过；1089.116 秒。进程内 `NODE_OPTIONS=--experimental-vm-modules`，使用已存在的真实身份，8 CPU 进程亲和性；唯一跳过为仅 POSIX 脚本接线测试 |
| writeback、lint、Agent 合同、Skill 矩阵 | 相应输入未变，复用上表结果，未重复执行 |

本轮日志 `%TEMP%/dt-regress/`：`mft-r2-final-red.tap`、`mft-r2-linux-execution.txt`、`mft-r2-linux-gate.{json,ndjson}`、`mft-r2-windows-execution.txt`、`mft-r2-windows-test.tap`。Linux 组合为原精简 18 条路径补丁 `e29d2d2a3849c97bdc3bf764a33d46d4d04eee2f8795ab200c268c889a34933c` + 本修订 2 条路径补丁 `1b499ddc04dbbc8e71ea4d9910af32c59006ebe88cdf481db945f7b8f4c1bc93`；NDJSON SHA-256 `62133efcee0021af4aa52f2965c306cbfca9f84b64d1c3d04c0e0e4ee8487fe0`，Windows TAP SHA-256 `9a1e4c8046eb502161c2424791d8410e01528ed33387b24bfce418f4c15c34d9`。S1 为 1/1 TC、1 项新增测试，已经 CLI 登记完成。未集成两补丁，组合通过仍不替代原精简工作树的任务 5.2；无托管 CI 或原生 Windows 受限令牌验证。

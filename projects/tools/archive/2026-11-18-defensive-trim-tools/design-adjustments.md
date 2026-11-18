# 设计调整说明

> 原始设计基线：Phase 2 产出的 design.md + specs/*.md + test-plan.md
> 调整来源：Phase 3 (BUILD) 实现与 C1 评审过程中的发现
> 本文只记录事实；受审文档（design.md、test-plan.md）未被改动，是否走 revision 由用户决定。

## 调整汇总

| # | 调整类型 | 涉及文档 | 严重程度 | 调整阶段 | 影响 TC | 用户已知 |
|---|---------|---------|---------|---------|---------|---------|
| 1 | 技术方案变更（参数形状） | design.md C4 | Minor | Phase 3 | TC-WSC-004–009（006、009 直接） | 已报告，未取得单独确认 |
| 2 | 实现补充（TTY 审批回答改为 await） | design.md C1 | Minor | Phase 3（C1 评审后） | 无自动化覆盖 | 已在会话中报告 |
| 3 | 范围补充（`CUSTOM.md`） | design.md 逐文件范围 | Minor | Phase 3（C1 评审后） | 无 | 已在会话中报告 |

## 调整详细说明

### 调整 1：`checkGenerator` 与 `checkBefore` 合并为单一 `fresh`

- **原始设计**：design.md C4「两函数传递调用方指定的 `checkGenerator` 布尔；新事务传 `true`……续办传 `false`」，既有 `checkBefore` 另存。
- **调整内容**：`readPreparedCandidate` / `validateWritebackManifest` 只保留一个 `fresh` 布尔（默认 `true`）：新事务同时做 before 预检和生成器 SHA 比较，journal 续办两者都不做。
- **调整原因**：原有两个调用点里 `checkBefore` 与新增的 `checkGenerator` 恒取同值，保留两个参数只多出一个无法区分的组合。行为与设计一致，不改变任何受审承诺（SC-WSC-005/006/007 的期望值不变）。
- **影响范围**：`crctl/lib/workspace-transactions.mjs`；`slices.md`、`tasks.md` 已改为 `fresh`；design.md C4 文字仍写 `checkGenerator`，未改。
- **影响 TC**：TC-WSC-006（续办不比较 SHA）、TC-WSC-009（新事务比较 SHA），其余 TC-WSC-004/005/007/008 间接。
- **调整阶段**：Phase 3
- **用户已知**：已报告；若认为参数形状属受审承诺，则需走 revision 同步 design.md。

### 调整 2：`crctl approve` TTY 分支改为 await 用户回答

- **原始设计**：design.md C1 规定读失败时抛局部 `ComponentConfigError`，由 CLI 现有 `fail` 信封返回 `EVIDENCE_COMPONENT_CONFIG_INVALID`；采集器不调用 `process.exit`，使回写门禁的事务清理先于 CLI 退出。
- **调整内容**：C1 代码评审指出 TTY 的 `approve --stage code` 把确认后的逻辑放在无人等待的 `rl.question` 回调里，该处抛出的异常不经 `main().catch`。现把回调内逻辑改为 `await` 用户回答后在原函数内继续，控制流等价；`ComponentConfigError` 的映射位置不变，仍在 `main().catch`。
- **调整原因**：新增的抛出点必须在所有入口都得到同一映射；此前一次“在采集函数里直接 `fail`”的修法违反了上面“不调用 `process.exit`”的设计约束，已撤销（见经验 EXP-2026-0008）。
- **影响范围**：`crctl/crctl.mjs` 的 `cmdApprove` TTY 分支（约 2755–2780 行，缩进改变，`git diff -w` 仅 2 处实质改动）。
- **影响 TC**：TC-EVD-101 在 `evidence-check` 与 `gate --for code-approved` 覆盖该错误信封；另在授权的 Linux WSL 上用真实 PTY 补验正常审批和配置错误零写入，2/2 通过，见 [测试报告](test-report.md#九授权使用本机podmanwsl-后的补验)。未在仓库新增常驻 TTY 测试。
- **调整阶段**：Phase 3（C1 评审后）
- **用户已知**：已报告。

### 调整 3：`CUSTOM.md` 删除两句已失效的「当前边界」描述

- **原始设计**：design.md 逐文件范围表不含 `CUSTOM.md`。
- **调整内容**：删除 `CUSTOM-TODO-016`「当前边界」中两句：「显式组件未就绪但无 findings 时补充阻断原因（纯接口防御）」（对应已删除的 `EVIDENCE_COMPONENT_NOT_READY` 兜底分支）与「组件声明读取失败或非数组会与空声明同样被当作 ready」（本 change 已改为硬失败）。
- **调整原因**：该台账的「当前边界」列声明尚未闭环的边界，保留这两句会与实现相反。
- **影响范围**：`tools/CUSTOM.md` 一行（CUSTOM-TODO-016）。
- **影响 TC**：无。
- **调整阶段**：Phase 3（C1 文档评审后）
- **用户已知**：已报告。

## 受审文档的未同步项（需要 revision 时一并处理）

- design.md:37 仍写 `checkGenerator`（见调整 1）。
- test-plan.md「三、测试执行矩阵」三行仍为“待 Phase 3”，执行结果以 test-report.md 为准。

## 后续迭代输入（C1 代码评审发现，已核实非本次引入，本 change 不修）

1. 续办（`fresh=false`）不复核目标父目录是否被换成符号链接/junction。旧的 `checkBefore: false` 即如此；design.md 把续办的校验面写死，加检查属受审承诺变更。
2. 归档 `buildEntries` 读错时抛普通 `Error` → `INTERNAL_ERROR`；评审称首跑读错会留下 `phase=init, archive=null` 的 journal，使省略 `--spec-id` 的原参重试报 `ARCHIVE_SPEC_REQUIRED`（未单独复现，需先复现）。`readT` 本就先于 `readHashRaw` 以同样方式抛错。
3. 归档 `_history.yml` 以 `existsSync` 探测后另行读取摘要，存在探测与哈希之间的 TOCTOU；本 change 的“同读”只覆盖生成侧。
4. 初次全量未配置隔离身份，触发缺失身份断言；后来复用 `AIFI-ISO` 受限账号，Windows→WSL 与 Linux 的真实隔离各 12/12，详见测试报告。

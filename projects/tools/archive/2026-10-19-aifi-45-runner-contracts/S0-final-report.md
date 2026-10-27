# S0 最终验收 — 全量复测通过（仅 S0 切片，不是 AIFI-45 整体完成）

范围：`2026-10-19-aifi-45-runner-contracts` 的 S0a/S0b/S0c（测试基线、根因修复、全量复测）。
不是四阶段合同改造、不是 multica 实现、不是 Gate 3。

## 1. 未改动基线（RED 起点，供对照）

- 修复前单次调用：35 文件、**869 case / 862 pass / 7 fail / 0 skip**，exit 1，单调计时 **2116.4877s**。
- 7 项失败：5 项 payload fixture 根错位（实际 `PAYLOAD_NOT_FOUND`，本应到达 forged/drift/refresh 目标分支）、1 项 authority 已知 `TxError` 被总 catch 改写成 `INTERNAL_ERROR`、1 项 `caller-09` 扫描把两处非可执行提及误判为可执行调用。
- 基线日志：`C:/Users/GOBAO/AppData/Local/Temp/aifi45-s0-build-9LHovb/`（`baseline-{command,result}.json`、`baseline-{stdout,stderr}.log`）。

## 2. 一次中断的后台尝试（不计通过）

- 尝试用单次后台托管调用重跑 35 文件：17:50:11 启动，17:53:41 结束，**209.5738s**，native 与 supervisor 均返回 **3221225786（0xC000013A）**，`timed_out=false`，**无 TAP 最终统计**（`counts={}`）。
- 同一时刻 `source_unchanged=true`（259 个受跟踪文件 canonical-LF 哈希一致），记录 PID 96200／57852 事后均已不存在，无匹配 Node 测试进程残留。
- 用户明确回答**不是主动停止**。终止的具体发起方仍**未证明**；能确定的只有：该后台承载方式无法可靠支撑本次约 35 分钟的测试墙钟，因此不作为验收证据。
- 证据：`C:/Users/GOBAO/AppData/Local/Temp/aifi45-s0-final-run1/`（`command.json`、`running.json`、`result.json`、`stdout.log`、`stderr.log`）。不再声称“后台进程不依赖会话存活”。

## 3. 最终全量复测（通过）

执行方式见 `pending-adjustments.yaml` 的 ADJ-T-002：**5 个前台顺序批次**，合计仍是同一 35 文件发现范围，`--test-concurrency=2`，`--test-reporter=tap`，**无 `--test-name-pattern` 过滤、无文件排除**。逐批真实退出码与 TAP 计数如下：

| 批次 | 文件数 | tests | pass | fail | cancel | skip | todo | exit |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| b1 小型单元 + output-guard(3) + registry(1) | 16 | 118 | 118 | 0 | 0 | 0 | 0 | 0 |
| b2 中量单元与 durable-tx | 8 | 123 | 123 | 0 | 0 | 0 | 0 | 0 |
| b3 contract/workspace/test-cr/merge/checkpoint | 6 | 191 | 191 | 0 | 0 | 0 | 0 | 0 |
| b4 caller/writeback/register/archive | 4 | 145 | 145 | 0 | 0 | 0 | 0 | 0 |
| b5 crctl.test.mjs（单文件，concurrency=1） | 1 | 298 | 298 | 0 | 0 | 0 | 0 | 0 |
| **合计** | **35** | **875** | **875** | **0** | **0** | **0** | **0** | 全 0 |

- 与基线的关系：875 = 869 + **6 项新增回归**（authority 兄弟 caller／合法容忍／未知异常 3 项、journal 恢复锁释放与真实非 authority TxError 信任 2 项、caller 可执行缺失 workspace 负向 1 项）。断言只增不减，未删除任何既有断言。
- 计数口径：每批内 Node 自带 TAP footer 为权威；跨批由主会话按 footer 求和，未用文件数或历史值推算。
- 复核：测试发现范围由仓库 glob 现场复核为 **35 个文件**，与分批清单一致、无遗漏无重复。
- 证据：`C:/Users/GOBAO/AppData/Local/Temp/aifi45-s0-run2/b{1..5}.log`（完整 TAP，含 footer）。

## 4. 既有质量入口（同一候选源码）

- `check-agents-contract.mjs` → exit 0（10 个 agent，不变式 1–3 + 附加检查 5）。
- `check-skill-matrix.mjs` → exit 0（56 个 active skill、8 个 actor，owns 唯一）。
- `lint-prompts.mjs` → exit 0，保留**既有**告警 `skills/sync/handover-cr/SKILL.md:59 [OUTDATED] R5: attempts[]`；该告警非本次引入，未隐藏、未顺带改写。
- `pipeline-templates/*.json` 全部可解析（`json ok`）。

## 5. 改动与审查

- 业务改动仅 4 个文件（均 uncommitted，`HEAD` 仍为 `a5ecb5783fd8f7b5fa1d0d3b328b704199bbe011`）：

```text
skills/shared/crctl/scripts/crctl.mjs
skills/shared/crctl/scripts/test/crctl.test.mjs
skills/shared/crctl/scripts/test/caller-contract.test.mjs
skills/shared/crctl/scripts/test/writeback-tx.test.mjs
```

- 既有 `.gitignore` 修改属于本任务之前就存在的工作区状态，未纳入 S0、未覆盖、未提交。
- 两轴独立审查（Standards／Spec）在最终 diff 上均无硬问题；首轮发现的 P2（深层 `process.exit` 跳过事务 `finally`）已修复并复测，详见 `S0-review.md` 与 ADJ-T-001。
- 未提交、未 push、未建分支、未改全局 Git/hook/依赖/环境、未连数据库、未操作真实 CR。

## 6. 结论与边界

- **S0 切片完成**：全部 35 文件自然跑完，875/875 通过，0 skip/todo/cancelled，源码与审查一致。
- 仍然**未**验证：四阶段 registry/绑定/模板/提示词改造（T01–T05），multica 消费与执行恢复，隔离数据库下的治理用例实际执行，跨平台（仅 Windows / Node v24.15.0 / Git 2.54.0.windows.1）。
- 不构成 Gate 3，也不代表 AIFI-45 已交付。

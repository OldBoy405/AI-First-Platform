# 2026-11-17-execution-admission-simplification 切片执行计划

## Dependency Graph Summary

```
dependency-graph: nodes = {admission-task-binding, authorized-runner, execution-wait-visibility}
edges = []  cycles = []  zero_dependency = 全部三个（CLI 只按 capability 建图）

实际实现依赖（按 design.md）：
  S1 驱动 --default-contract + 默认契约实现（D3/D4） ──真实隔离栈 strict 链跑通──▶ S3 准入收缩（含 TC-RUN-101/106）
  S4 等待可见（progressOf/回执/GET/CLI）  独立，可并行
```

**并行化说明**
- 并行组 1：S1、S4（互不依赖）。
- 组 2：S3（依赖 S1；TC-RUN-101 的 `TestTC_RUN_003` 改写与 TC-RUN-106 需要新判定与新签发同时存在）。
- 实际执行按 S1 → S4 → S3 串行推进（同一 multica 工作树，避免并行编辑同一文件；“可并行”只表示无依赖）。
- **S1 合并说明（PA-002）**：原计划 S1 为“只改驱动的诊断切片”、S2 为“默认契约实现”。核实后发现：当前 server 要求请求必须带三个契约字段（`decodeExecutionRawRequest`），且 architecture-stub 场景固定以 INCONCLUSIVE/exit 2 结束（“不是真实模型证据”的既定语义，不得改）；不改 server 就无法用“省略字段”的请求走通 strict 链，也无法让 CP-RUN-105 以 exit 0 结束。因此把驱动改造与 D3/D4 实现合为 S1，**实现顺序仍是先让联调跑通再做其他**：S1 内先完成最小 D3/D4 + 驱动，立刻跑 TC-RUN-105；失败即 C1 暂停，不进入 S4/S3。TC 归属不变（每 TC 恰一个切片）。

## Slice Execution Plan

| # | 优先级 | 风险 | 预估 | 并行组 | TC 覆盖 | 实现目标 | 依赖 |
|---|--------|------|------|--------|---------|---------|------|
| S1 | P0 | 🟡 高（5） | L | 组1 | TC-RUN-102、103、104、105（4/4） | `DefaultExecutionContract()`；router 装配三情形；请求三字段可省略、填充先于冻结；边界用例在默认契约下复跑；`scripts/aifi45-real-run/{config,stack,run,stub-flow,scenario-stub}.mjs` 增 `--default-contract`（该模式下以 `PASS … scenario architecture-stub-default-contract` 结束，其他模式不变）；隔离栈跑通 strict 链 | 无 |
| S4 | P0/P1 | 🟢 中（3） | M | 组1 | TC-EWV-001～004（4/4） | `internal/governance/pipeline_progress.go`；requirement resume / architecture start 回执；GET 路由；`cmd/multica` status 与 table | 无 |
| S3 | P0 | 🟡 高（5） | L | 组2 | TC-ATB-101～106、TC-RUN-101、TC-RUN-106（8/8） | `DecideAdmission` 只看头；调用点与 source 任务读取摘除；既有测试改写 + selections 同步；新增矩阵与 requirement 流转；覆盖矩阵核对 | S1 |

TC 合计 16/16；每 TC 恰一个切片。

## Rationale

### S1：默认契约实现 + 联调（P0，先行）
- **依赖关系**：design.md 最大未验证点是默认 digest 在“签发 → head → binding → crctl 检查 → consumption”各环节是否一致。顺序：先写 D3/D4 的 RED 测试与最小实现（TC-RUN-102/103/104），再改驱动 `--default-contract`（不生成 manifest、不传两个 flag、请求省略三字段），立刻在隔离栈跑 TC-RUN-105：真实 server + daemon + crctl + stub 执行器，请求省略字段 → 201 → head → binding → crctl 检查 → 预消费 → writer → reviewer → 人工门 → 重启去重。任一环节 digest 不一致即 C1 暂停。
- **驱动结束语义**：architecture-stub 现有模式固定 INCONCLUSIVE/exit 2（不是真实模型证据），不改；`--default-contract` 是新增模式，它证明的是平台事实（与 stub 场景同一组断言），在该模式下所有断言通过且清理干净时输出 `PASS <label> scenario architecture-stub-default-contract` 并 exit 0，仍附 NOTE 说明不是真实模型证据。此为驱动的新增行为，不改既有模式的输出。
- **风险分析**：跨系统契约一致性（EXP-0001 类比）；填充晚于冻结导致 head 409（EXP-0002 类比）；无密钥部署被默认契约弄成启动失败；MODIFIED 接口放宽 +1、跨模块 +1、Scenario 6+ → +1、合计 5（高）。
- **工作量**：L（4 TC；governance 2 文件 + router + 驱动 5 文件 + 各自测试）。

### S4：等待可见（P0/P1，可并行）
- **依赖关系**：只读推导与回执/路由/CLI，不依赖准入语义；先做它可让 S3 的等待用例直接读到 `progress`。
- **风险分析**：残留 runner 标记误报（design D5）、无任务节点误判；EXP-0005 类比（状态表逐格独立断言）。Scenario 5+3+2=10 → +1；跨 governance/handler/cmd 三层 → +1；新能力无接口变更 → 0；经验 high 无直接命中 → 0；合计 3（中）。
- **工作量**：M（4 TC，约 5 文件）。

### S3：准入收缩（P0）
- **依赖关系**：判定与签发都到位后，才能一次性改写全部旧测试并让 `TestTC_RUN_003`、requirement 流转通过。
- **风险分析**：EXP-0009（跨包调用点）、EXP-0008（锁序探测）、EXP-0005（身份检查只测一个失败条件）命中 → +2；Scenario 10+ → +1；跨 governance/cmd/server/daemon 测试 → +1；MODIFIED 接口变更 → +1；合计 5（高）。
- **工作量**：L（8 TC，>10 测试文件 + selections）。

## 验证口径

- 每切片 RED → GREEN → REFACTOR → B3.4（TC 覆盖 M=K、产出物核对、目标包测试 + 全量回归）→ `stdd state --complete-slice`。
- DB 类测试一律经 `run-selection.mjs --only <name>` 在自建一次性实例上跑；不连现网库。
- 全量回归：一次性库上的 `go test`（方式由 0.1 核实后确定）；`make test` 默认指向 .env 的库，**不得对现网库执行**。
- 每切片即时登记 CUSTOM-LEDGER 与 tasks.md，不积压。

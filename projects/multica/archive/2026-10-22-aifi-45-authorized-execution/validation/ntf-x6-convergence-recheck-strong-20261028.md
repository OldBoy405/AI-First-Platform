# X6 收敛草案第二版 — STDD strong 定向复核归档（2026-10-28）

> 本文归档对 `validation/ntf-x6-canonical-convergence-20261028.md` 第二版的定向复核，逐项核对其对前一份 strong 报告六项 blocking 的回应。**复核只针对 raw sha256 `7ece53e013a077d48a843e9c4bb7882c7834c71cfac90dab2a699baa4c06c7f6` 版本（110 行）**；作者随后可能继续修文，**本文不默认覆盖任何后续版本**，新版须另行复核。写入本文前重算该文件 sha256 仍为上值。
> 本文**不修改**此前报告：`ntf-scope-x6-review-strong-20261028.md`（sha256 `d71cf020…7fe34`）、`ntf-x6-convergence-review-strong-20261028.md`（sha256 `c6e8ba2d…f28ce`）。
> 复核期间**未改文件、未运行测试、未访问 DB/容器、未发送通知**。PostgreSQL 可见性/锁/索引行为仍为**未实测推断**；“已核”仅指静态读源确认。修订均为**建议**。

## 1. 对象与源 SHA

| 对象 | 值 |
|---|---|
| 被复核文档 | `validation/ntf-x6-canonical-convergence-20261028.md`，raw sha256 `7ece53e013a077d48a843e9c4bb7882c7834c71cfac90dab2a699baa4c06c7f6` |
| 前一轮报告（回应对象） | `validation/ntf-x6-convergence-review-strong-20261028.md`，sha256 `c6e8ba2db0eb5865149bfce17f7f57dee802ccca6201c75e08b7688378df28ce`（审阅版本 `d45ace60…ca85006`） |
| multica HEAD | `81e5293adc758e392a045026cf81ec5cc1bac72d` |
| `server/internal/governance/execution_notice.go` | 工作区 blob `22749eafb6d75144bf2f87775f4467538914b4cd`（含另一作者未提交广播依赖改动，非 X6） |
| `server/cmd/migrate/main.go` | blob `6e54cafff3717522b68e5685c2a8bc3db66e7b50`，无本地改动 |

## 2. 总体结论

第二版对六项均给出诚实、方向正确的书面方案，并**未把缺失的认证/授权来源或回滚 hook 写成已实现**。但**六项全部仍为 hard blocker**：没有一项已实现、已实测或已有可信来源。另存若干设计矛盾和未登记 ADJ（§4）。

## 3. 逐项：已写方案 vs 仍未实现/未证实

### B1 广播载荷缺 key

- **已写方案**：§2.4 明确 `LoadInboxItem` 不含 details；新 loader/广播须携带并验证非空 v2 key，测真实 loader → bus → 客户端；限定客户端同 ID claim 仅在 QueryClient 缓存内，刷新/重启/多窗口/多设备/mobile 不在保证内。已核：`apps/mobile/data/realtime/use-inbox-realtime.ts:51` 对 `inbox:new` 仅做刷新。
- **仍为 hard blocker**：loader/广播契约未实现；跨 session/设备的可见提醒保证尚无产品决定；SC-NTF-005/007 不能宣称满足。

### B2 旧恢复器隔离

- **已写方案**：§3 纠正“拒 UPDATE 非隔离”，要求旧恢复器在**广播前**不可运行，并增设“仅拒 UPDATE 仍会广播”的反例测试。
- **仍为 hard blocker**：未选具体的广播前控制手段（旧表改名/撤权/发布控制均未定）；实例、定时任务与仓外调用者清点证据不存在。
- **残留矛盾**：§4 上线顺序仍写“身份和状态更新保护仅作补充”。若存在未清点的旧恢复器，该补充会导致同一 pending 行反复重播（先广播、UPDATE 被拒、下一轮再广播），并非无害补充。应删除或明示副作用。

### B3 新默认恢复路径

- **已写方案**：独立 CONCURRENTLY pending partial 索引并要求实际查询计划；抢占/故障恢复、授权变更、触发/发现分别列 hard blocker。
- **仍为 hard blocker**：抢占协议（行锁/租约）、崩溃释放、撤权线性化、workspace 枚举与调度入口均未定。第二版明确“不新增第三种投递状态”，导致撤权/无法核验的 pending 永驻 pending、每轮重试告警且无终态——这是**设计缺口**，需要决定（若引入终态则须 ADJ）。

### B4 先筛后 insert

- **已写方案**：专用 SQL，不复用 `CreateInboxItem`；显式 READ COMMITTED；`ON CONFLICT … DO NOTHING RETURNING` 后以**独立 SELECT**回读并逐项核对身份；错误分类不得冒充幂等成功；启用前校验索引定义与 `indisvalid`；旧行检查与写入采用 workspace+CR 级串行化协议。
- **仍为 hard blocker**：查询、错误合同、串行化协议（锁粒度、哈希碰撞、超时、死锁）均未实现，PG 可见性未实测。
- **小问题**：“启用前确认索引”应改为每实例启动时（必要时周期）检查，因索引事后可能被删或重建。

### B5 CONCURRENTLY 索引 cleanup 与 down

- **已写方案**：每个 up 版本登记 `concurrentIndexCleanups`；需要时登记 `concurrentDownIndexCleanups`（已核存在于 `main.go:412`）；以 `preRollbackHooks` 在首个破坏性 SQL 前拒绝回退；承认 hook 覆盖风险及“检查—drop”非原子。
- **仍为 hard blocker**：**安全检查 hook 不存在**，仅为方案；检查与 drop 的原子性、SQL 成功但版本记录失败、部分升级逐版本 down 均未证。
- **已核约束，第二版未写全**：`main.go:448-470` 中 `preMigrationHooks` 与 `preRollbackHooks` 均为“每版本一个 hook”的 map，后赋值覆盖先赋值。若同一版本需同时做 invalid 清理与安全检查或重复 key 预检，必须实现**组合 hook**；up 方向同样适用，第二版只提到 down 的覆盖风险。

### B6 scope 与 recipient 可信来源

- **已写方案**：§2.1、§4 明确 workspace/project/CR/事件/recipient 的权威来源、校验者与撤权时点未定，不能凭 CR 名、当前 issue 或 membership 猜测；纠正 433 仅经 `shell_issue_id` 关联、585 run 无 project 列（已核）。
- **仍为 hard blocker**：授权事实源、维护职责来源、认证调用链**均不存在**；失败关闭意味着 NTF-002/003/004 当前不可用。第二版不再沿用此前“建议 648 selection”的提法，也未选定替代来源，此项完全未解决。

## 4. 设计矛盾与未登记 ADJ

1. **SC-NTF-006 偏离无 ADJ**：同 CR+同 recipient 旧行阻断会吞新失败，直接违背 canonical SC-NTF-006；design §5“旧通知无该字段，行为不变”与“旧行阻断新通知”亦冲突。第二版只写“不能宣称满足”。须补 ADJ 审批，或在规范层显式标记 NTF 未就绪。已核：`pending-adjustments.yaml` 仅 ADJ-AIFI45-M001–M004，当前未提交改动与 NTF 无关。
2. **旧 pending 永不恢复与 §5 不一致**：§5 要求“提交后广播前崩溃扫描 pending 恢复”；第二版对旧 pending 永不恢复且最终处置未定，需要记录在案的决定。
3. **决策记录未更新**：`backlog-b-disposition-20261026.md:89` 的 X6 旧决议“原位改 646”仅在文中被宣布不能作为授权，backlog 未写入新决定；`CUSTOM.md #195` 仍登记 646 附表为 NTF 实现，切换时须同步。
4. **键稳定性边界未定义**：§5“同 CR 跨 run 保持键”与第二版“失败发生身份”的边界——新 run 中同根因算重放还是新失败——依赖尚不存在的生产者合同。
5. **引用未提交代码**：第二版把 `BusBroadcaster` 的 ID/workspace 校验作为现状描述，但该行为来自另一作者**未提交的工作区改动**（非 HEAD、非 X6），应注明依赖。
6. **追溯链接缺失**：第二版文首只链接旧提案的审阅报告，未链接其所回应的 `ntf-x6-convergence-review-strong-20261028.md`（sha256 `c6e8ba2d…`）。

## 5. 最小后续修订（建议）

1. 为 SC-NTF-006 偏离及旧 pending 处置补 ADJ，或作明确的未就绪声明。
2. 删除 §4 中“状态更新保护仅作补充”，或明示其在旧恢复器残存时导致重播。
3. B5 写明 up/down 两向“每版本单 hook”约束及组合 hook 要求。
4. 撤权 pending 的终态或处置路径作决定（如需新状态则走 ADJ）。
5. 索引有效性检查改为每实例启动/周期检查。
6. 注明对未提交广播依赖改动的依赖，并补追溯链接。

## 6. 未核与限制

- PG 回读可见性、ON CONFLICT 与 INVALID 索引、锁/死锁行为：推断，未实测。
- 应用角色是否为旧表 owner、迁移 down 文件顺序、授权执行是否落在 pipeline_run、646 是否已部署：未核（禁止 DB/容器）。
- 本文仅为复核记录，不改任何源码、迁移、design、canonical、被复核文档或此前报告。

# RUN-009 方案 A 评审记录

## 结论与授权范围

主会话中用户明确确认：**可信裁决由 Ray 负责；RUN-009 按方案 A（权威 run/cycle 绑定 + 可恢复 pending）评审**。这不是对具体身份源、签发者、密钥、信任根的确认，也不是实现、签名合同变更、部署或 Gate 批准。A 的选择取代“尚未选择 A/B”的旧状态，不消除先前 strong 复审的实施准备 **BLOCK**。本次仅只读评审：未运行真实入口、测试、DB、容器，未访问真实 CR；实际 backend unknown。

## 主要发现

1. **权威链未闭合。** 旧字段盘点表明，所见 review outbox 无 run/cycle/reviewer UUID，commit-scan 无平台 run ID；本地 actor、非空 subject 或文件字段不是认证事实（`run009-producer-inventory-20261029.md:7-10,19-20`）。当前 `gate_projection.go:141-170` 可按 workspace/CR/pipeline 查找或创建 run，并以工作区最早 owner 作为 `started_by` 兜底；这不证明其实际启动或评审身份。需要明确不可伪造的原始 run、cycle、node、reviewer/任务 generation、subject、policy 和 receipt 的权威来源及验证者，而不是将 Ray 的负责人身份当作签发凭据。
2. **ACK 后重判可能失去原始材料。** 既有盘点记载持久去重键无独立 stage 维度（event_kind 是否足以区分 stage 未证），processed 直接 ACK；未 processed 时可能以当前 wire event 投影，而 ledger 保留首包；ACK 后 outbox 文件删除，Git blob 可否恢复未知（`run009-producer-inventory-20261029.md:15-19`）。方案 A 须在 ACK 前保存足以重判的输入、来源与可恢复责任，并分开摄入、事实补齐和业务处置；已核实事实不可静默覆盖。相同 commit 的不同 stage/review/test 是否真会发生碰撞仍须核真实生产者，不能仅凭键形状断言。
3. **旧轮和早到不能混为丢弃。** 可证明属于终态旧轮的事件仅留历史、不新建 run、不推进；潜在新轮但权威绑定尚未到达的事件须可恢复待决、不得提前推进。严格合同缺少 attempt/cycle 不能补造；已 pin legacy 的处理需明确，不能因缺字段自动降级，也不能无差别永久挂起。`gate_projection.go:386-431` 的 review 路径仍自行查找或创建 run，存在 attempt 兼容兜底、先读最大 attempt 再写及同键 detail 合并覆盖；未证明形成原子绑定。
4. **终态/开轮的同步域未证明。** `gate_projection.go:260-266,297-311` 完成时排除 Runner 标记 run，但取消更新包含所有活跃 run；节点和 run 是分开的 pool 写入。`runner.go:1661-1669` 的失败路径先写 run 再写 node，与投影取消先 node 后 run 的顺序不同。`runner.go:1124-1136` 在其事务内按 run ID 和空 runner 标记更新 context；该 SQL 本身没有更多资格条件，调用链的先后检查与提交点仍须逐入口核实。以上只是示例，不是写者完整清单：还须覆盖 architecture、requirement、code、writeback 完成与开轮、人工恢复、promotion、投影 node 等，见 `run009-terminal-writer-inventory-20261029.md`，该盘点自身也明确非穷尽。需定义终态所有权、共享跨进程同步域和实际锁序，再用并发实证；当前只是静态风险，不证明已发生死锁或误取消。
5. **pending 与现有 Runner 读路径尚未对接。** `runner.go:1496-1506,1560-1577,1602-1612,1629-1638` 从精确 run/node/attempt 读取评审、依赖 `needs_reconcile` 读投影状态；当缺少决定性证据且投影被认为已追平时，review delivery gap 可使 run 失败。持久保存 pending 本身不会自动让该读路径识别“绑定等待中”；需设计可审计的等待状态及与现有失败/人工恢复语义的协调，避免把未决事件误判为永久缺失或无限等待；同时核 grant、任务完成和其他 wake 是否触发该判断。已有受限片段如 source task 与 reviewer 独立性检查可供复用，但尚未证明闭合完整权威链。此为条件性的静态风险，非已经复现的错误。
6. **重试不能绕过撤销或耗尽资源。** 候选要求重判和 effect 前重新核对可信撤销、STOP_NEW、readiness 与必要 resume 事实（`run009-binding-candidate-20261029.md`）；pending 持久责任、上限、过载、审计和不可判处置尚无获批策略。不能仅凭超时丢弃可能早到的有效事件，也不能将无界堆积当恢复方案。

## 待 Ray 协调的决策包

以下是待评审问题，不假设均由 Ray 单独决定：

- **事实来源与合同：**由谁权威记录 run/cycle 与 reviewer/task generation，谁验证、如何冻结 subject/policy/receipt；核现有合同是否足够，任何已归档签名合同变更另行评审。
- **事件及恢复：**子事实身份、可信补齐/冲突、ACK 持久化、启动/周期恢复责任、容量与不可判处置；保持原始来源及处置可审计。
- **旧合同：**可信 contract selection、存量盘点与可证明的 legacy 解释、无法判定时的人工作业和回退。D8=A 未改变，不据本决策启动历史迁移。
- **终态与 Gate：**各投影/Runner 写者的所有权、跨进程同步域及统一锁序，Gate2 调整范围和接受标准。

## 待验证的最小场景（尚未执行）

| 场景 | 应证明的性质 |
|---|---|
| 旧评审终态后迟到 | 保留历史，不创建新 run、不污染新轮节点或派发；重投不重复生效 |
| 新评审早于可信开轮 | 保存可恢复 pending；验证 task 已结束、投影显示追平时 Runner 不误作不可恢复的缺交付，绑定出现并经重启后同一事件恰当应用一次 |
| 不完整副本后到达可核验补充 | 只补可信缺项，保留来源；矛盾已核验事实、错来源、重复投递不得静默覆盖或推进 |
| 终态、开轮与重判交错 | 双方提交顺序、全部终态写者/收编均覆盖；证明实际共享同步域和一致锁序 |
| 撤销/STOP_NEW 与恢复竞争 | 重判及 effect 时重读可信准入；无适用 resume 时不产生新的未授权 effect |
| strict 与已 pin legacy | 按权威合同分流；缺失/冲突/不可判不伪造 cycle 或误降级，且验证历史和恢复路径 |

纯模型可检查状态选择，不能证明真实锁、入口、身份或事务；真实 SQL 并发须获准的独占隔离库和合格回执。指定 `server/internal/governance/gate_review_late_test.go` 当前不存在；不能据此断定其他地方也无同类测试。本次不计 TC-RUN-009 通过、不更改任务状态，Gate3 仍 NO-GO。

## 独立评审与来源

两个独立只读会话：`01a18822-c01f-7020-aecc-d4039dda9a19` 复核既有候选/strong 复审/字段盘点；`01a18822-c030-7020-aecc-d4050fa0e31a` 复核限定的投影、Runner 与终态盘点。前者提到 A/B 还需选，是在用户已选 A 后的陈旧结论，已纠正；后者复核本报告时发现 pending 与 Runner 缺交付判断、终态写者范围两项遗漏，现已补入并经同一会话静态复核。关闭的是报告遗漏，不是方案实现问题；两者均未审计所有调用方或验证数据库。协调者在评审后读取以下现时文件 raw SHA-256；这不是评审者自行验证的固定快照：

- `multica/server/internal/governance/gate_projection.go`：`518606131939d4dae90c44e98f27cd39e0d127224ca1a43b693ba49532ac1431`
- `multica/server/internal/governance/runner.go`：`d8898444d260d2f674d84b2709ac3f4c622b00d502013a2cd0626c0ad4552811`
- `multica/server/internal/governance/runner_code.go`：`b163b99bee9342a88aa7ddef541bbcfead11abf457fa08ca91b7c49aa9ae2a06`
- `multica/server/internal/governance/runner_requirement.go`：`ab67f0468ff8b390bd5fea8ee7bba0f7c0a0959f82e2b909b76c7af6a4e211d3`
- `run009-binding-candidate-20261029.md`：`82c7268c7eb23f3bfc0a09208bd9409e2992db4b24fc2035595feefb338d1f53`
- `run009-binding-strong-review-20261029.md`：`9173918f3218f634b005adce566229921a43e50673675910152b694647c54e9a`
- `run009-producer-inventory-20261029.md`：`bc4574f260da323ea76e8012e357775d1882feaebb2f563c971b72897410d4e7`
- `run009-terminal-writer-inventory-20261029.md`：`9c2770eea392523a100c7c9c0e8016e82d7f0b021b87e4dbad78f246c9694b60`
